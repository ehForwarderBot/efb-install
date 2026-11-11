#!/usr/bin/env bash
# EH Forwarder Bot installer: isolated native service or Docker Compose.
set -Eeuo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SERVICE=efb
SERVICE_USER=efb
SERVICE_HOME=/var/lib/efb
VENV_DIR=/opt/efb/venv
SERVICE_FILE=/etc/systemd/system/efb.service

die() { printf '错误: %s\n' "$*" >&2; exit 1; }
info() { printf '==> %s\n' "$*"; }
need_root() { [[ "$EUID" -eq 0 ]] || die "原生安装需要 root 权限；请使用 sudo。Docker 模式不需要 sudo（用户必须能访问 Docker）。"; }
need_bundle() {
  [[ -f "$REPO_DIR/requirements.txt" && -f "$REPO_DIR/docker-compose.yml" && -f "$REPO_DIR/Dockerfile" ]] ||
    die "缺少配套文件。请先 git clone https://github.com/ehForwarderBot/efb-install.git 后在仓库目录中执行 bash install.sh。"
}
need_linux() { [[ "$(uname -s)" == Linux ]] || die "原生安装仅支持 Linux + systemd；macOS 可以使用 Docker 模式。"; }
need_docker() {
  command -v docker >/dev/null 2>&1 || die "未检测到 Docker CLI，请先安装 Docker Engine / Docker Desktop。"
  docker compose version >/dev/null 2>&1 || die "未检测到 Docker Compose v2 插件。"
}

native_packages() {
  [[ -r /etc/os-release ]] || die "无法识别 Linux 发行版。"
  # shellcheck source=/dev/null
  . /etc/os-release
  case "$ID" in
    debian|ubuntu)
      info "安装 Debian/Ubuntu 所需系统依赖（不升级系统或内核）"
      apt-get update
      local magic_package=libmagic1
      # Debian 13 / Ubuntu 24.04+ renamed the library to libmagic1t64.
      if apt-cache show libmagic1t64 2>/dev/null | grep -q '^Package: libmagic1t64$'; then
        magic_package=libmagic1t64
      fi
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        python3 python3-venv python3-dev build-essential \
        ffmpeg "$magic_package" libcairo2 ca-certificates
      ;;
    *)
      die "原生自动安装目前支持 Debian/Ubuntu；其他发行版可使用 Docker Compose。"
      ;;
  esac
}

native_guard() {
  if [[ -e "$SERVICE_FILE" ]] && ! grep -Fq 'Managed by ehForwarderBot/efb-install' "$SERVICE_FILE"; then
    die "$SERVICE_FILE 已存在，且不是本脚本创建的。为保护现有 EFB 实例，拒绝覆盖；请先手动迁移。"
  fi
}

native_wizard() {
  need_root
  need_linux
  [[ -x "$VENV_DIR/bin/efb-wizard" ]] || die "请先执行 sudo bash install.sh native install。"
  info "配置会写入 $SERVICE_HOME/.ehforwarderbot（不会覆盖 /root 下的旧数据）"
  runuser -u "$SERVICE_USER" -- env HOME="$SERVICE_HOME" "$VENV_DIR/bin/efb-wizard"
}

native_install() {
  need_root
  need_linux
  need_bundle
  command -v systemctl >/dev/null 2>&1 || die "需要 systemd。"
  native_guard
  native_packages

  local python_bin="${EFB_PYTHON:-python3}"
  command -v "$python_bin" >/dev/null 2>&1 || die "找不到 Python: $python_bin"
  "$python_bin" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' ||
    die "Python 版本需要 >=3.10；请通过 EFB_PYTHON 指定兼容版本。"
  if "$python_bin" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 13) else 1)'; then
    info "注意：EFB 部分旧插件在 Python 3.13+ 可能不兼容；请先测试依赖。"
  fi

  if ! id "$SERVICE_USER" >/dev/null 2>&1; then
    useradd --system --create-home --home-dir "$SERVICE_HOME" \
      --shell /usr/sbin/nologin "$SERVICE_USER"
  fi
  install -d -m 0750 -o "$SERVICE_USER" -g "$SERVICE_USER" "$SERVICE_HOME"
  install -d -m 0755 /opt/efb

  # Only a unit that we own may be stopped/replaced.
  if [[ -f "$SERVICE_FILE" ]] && systemctl is-active --quiet "$SERVICE"; then
    info "停止本脚本管理的旧实例，升级依赖后再启动。"
    systemctl stop "$SERVICE"
  fi

  info "创建独立 Python venv（不使用系统 pip，不修改 python3 alternatives）"
  if [[ ! -x "$VENV_DIR/bin/python" ]]; then
    "$python_bin" -m venv "$VENV_DIR" || die "venv 创建失败，请检查所选 Python 对应的 venv 包。"
  fi
  "$VENV_DIR/bin/python" -m pip install --upgrade pip
  "$VENV_DIR/bin/python" -m pip install -r "$REPO_DIR/requirements.txt"

  local config="$SERVICE_HOME/.ehforwarderbot/profiles/default/config.yaml"
  if [[ ! -f "$config" ]]; then
    info "尚无 EFB 配置，运行交互式 efb-wizard"
    native_wizard
    [[ -f "$config" ]] || die "配置未完成，服务未启动；重新执行 native configure。"
  fi

  cat > "$SERVICE_FILE" <<'EFB_UNIT'
# Managed by ehForwarderBot/efb-install
[Unit]
Description=EH Forwarder Bot
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=efb
Group=efb
Environment=HOME=/var/lib/efb
WorkingDirectory=/var/lib/efb
ExecStart=/opt/efb/venv/bin/ehforwarderbot
Restart=on-failure
RestartSec=10s
UMask=0077
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full

[Install]
WantedBy=multi-user.target
EFB_UNIT
  systemctl daemon-reload
  systemctl enable --now "$SERVICE"
  info "原生 EFB 已启动。日志: journalctl -u efb -f"
}

native_backup() {
  need_root
  [[ -d "$SERVICE_HOME/.ehforwarderbot" ]] || die "找不到原生 EFB 配置目录。"
  local target="${1:-$PWD/efb-native-$(date +%Y%m%d-%H%M%S).tar.gz}"
  local running=0 result=0
  umask 077
  if systemctl is-active --quiet "$SERVICE"; then
    running=1
    systemctl stop "$SERVICE"
  fi
  tar -czf "$target" -C "$SERVICE_HOME" .ehforwarderbot || result=$?
  if [[ "$running" -eq 1 ]]; then systemctl start "$SERVICE" || result=$?; fi
  [[ "$result" -eq 0 ]] || die "备份或恢复服务失败，请检查服务状态和备份文件。"
  info "备份已保存到 $target（含密钥与会话，请安全保存）"
}

docker_init() {
  need_bundle
  umask 077
  if [[ ! -f "$REPO_DIR/.env" ]]; then
    cat > "$REPO_DIR/.env" <<EOF
EFB_UID=$(id -u)
EFB_GID=$(id -g)
EFB_CONFIG_DIR=./data
TZ=UTC
EOF
    chmod 600 "$REPO_DIR/.env"
    info "已生成 .env（数据目录、UID/GID、时区均可修改）"
  else
    info "保留现有 .env"
  fi
  if [[ ! -e "$REPO_DIR/data" ]]; then
    mkdir -m 700 "$REPO_DIR/data"
  fi
  info "数据路径默认为 $REPO_DIR/data。首次运行请先执行 docker configure。"
}

compose() {
  need_docker
  [[ -f "$REPO_DIR/.env" ]] || die "先运行 bash install.sh docker init。"
  (cd "$REPO_DIR" && docker compose --env-file .env "$@")
}

docker_data_path() {
  local d=./data
  if [[ -f "$REPO_DIR/.env" ]]; then
    local value
    value="$(sed -n 's/^EFB_CONFIG_DIR=//p' "$REPO_DIR/.env" | tail -n 1)"
    [[ -z "$value" ]] || d="$value"
  fi
  [[ "$d" != *'$'* && "$d" != *'"'* && "$d" != *"'"* ]] || die "备份需要 .env 中的 EFB_CONFIG_DIR 为普通路径。"
  if [[ "$d" = /* ]]; then printf '%s\n' "$d"; else printf '%s\n' "$REPO_DIR/$d"; fi
}

docker_backup() {
  need_docker
  local data target running=0 result=0
  data="$(docker_data_path)"
  [[ -d "$data" ]] || die "配置目录不存在: $data"
  target="${1:-$PWD/efb-docker-$(date +%Y%m%d-%H%M%S).tar.gz}"
  umask 077
  if [[ -n "$(compose ps --status running -q efb)" ]]; then
    running=1
    compose stop efb
  fi
  tar -czf "$target" -C "$data" . || result=$?
  if [[ "$running" -eq 1 ]]; then compose start efb || result=$?; fi
  [[ "$result" -eq 0 ]] || die "备份或恢复容器失败，请检查容器状态。"
  info "备份已保存到 $target（含密钥与会话，请安全保存）"
}

docker_cmd() {
  local action="${1:-}"
  shift || true
  case "$action" in
    init) docker_init ;;
    configure|wizard) compose run --rm --no-deps efb efb-wizard ;;
    build) compose build --pull efb ;;
    up|start) compose up -d --build efb ;;
    down|stop) compose stop efb ;;
    restart) compose restart efb ;;
    logs) compose logs --tail=200 -f efb ;;
    status) compose ps ;;
    update) compose build --pull efb && compose up -d --no-deps efb ;;
    backup) docker_backup "${1:-}" ;;
    *) die "未知 Docker 命令: $action（参考 bash install.sh --help）" ;;
  esac
}

native_cmd() {
  local action="${1:-}"
  shift || true
  case "$action" in
    install|update) native_install ;;
    configure|wizard) native_wizard ;;
    restart|start|stop) need_root; need_linux; native_guard; systemctl "$action" "$SERVICE" ;;
    status) need_linux; systemctl status "$SERVICE" --no-pager ;;
    logs) need_linux; journalctl -u "$SERVICE" -f ;;
    backup) native_backup "${1:-}" ;;
    *) die "未知原生命令: $action（参考 bash install.sh --help）" ;;
  esac
}

usage() {
  cat <<'HELP'
用法:
  bash install.sh docker init           # 生成 .env 和持久化数据目录
  bash install.sh docker build          # 构建镜像
  bash install.sh docker configure      # 交互式 efb-wizard
  bash install.sh docker up             # 启动（同时构建）
  bash install.sh docker status|logs|restart|stop|update
  bash install.sh docker backup [路径]  # 停机一致性备份，自动恢复原运行状态

  sudo bash install.sh native install   # Debian / Ubuntu：venv + systemd
  sudo bash install.sh native configure # 配置向导
  sudo bash install.sh native status|logs|restart|stop|update
  sudo bash install.sh native backup [路径]

  bash install.sh                       # 交互菜单
环境变量:
  EFB_PYTHON=/path/to/python3           # 原生模式所使用的 Python
注意: 此脚本不会卸载或自动迁移已有 EFB 实例，也不会清理登录缓存。
HELP
}

menu() {
  usage
  printf '\n1) 原生安装/更新\n2) 原生配置\n3) 原生状态\n4) Docker 初始化\n5) Docker 配置\n6) Docker 启动\n7) Docker 状态\n8) Docker 日志\n9) Docker 更新\n0) 退出\n选择: '
  local n
  read -r n || exit 0
  case "$n" in
    1) native_cmd install ;;
    2) native_cmd configure ;;
    3) native_cmd status ;;
    4) docker_cmd init ;;
    5) docker_cmd configure ;;
    6) docker_cmd up ;;
    7) docker_cmd status ;;
    8) docker_cmd logs ;;
    9) docker_cmd update ;;
    0) exit 0 ;;
    *) die "无效选项" ;;
  esac
}

case "${1:-}" in
  native) shift; native_cmd "$@" ;;
  docker) shift; docker_cmd "$@" ;;
  --help|-h|help) usage ;;
  "") menu ;;
  *) usage; exit 2 ;;
esac
