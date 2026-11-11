# EH Forwarder Bot 一键安装（原生 / Docker Compose）

本仓库为 **EFB 2 + Telegram Master + WeChat Web Slave** 提供两种部署方式：原生 Python venv + systemd，或 Docker Compose。原有配置、微信会话、Telegram 群组绑定默认不迁移、不覆盖、不删除。

> 兼容性说明：微信从端基于非官方微信网页版协议，并非所有账号都能登录。旧版 Telegram 与微信插件也未保证与所有新 Python 版本兼容。Docker 默认 Python 3.12，以尽量避开 Python 3.13 删除旧标准库模块带来的兼容风险。为兼容旧版 `python-telegram-bot 13.x`，目前还需将 `urllib3` 限制在 1.26.x，并将 Peewee 限制在 3.x，同时保留提供 `pkg_resources` 的旧 setuptools 和与 APScheduler 3.6 兼容的 tzlocal；这是过渡性的旧依赖兼容措施，**不代表该依赖组合具有最新安全维护保障**。仍需实际测试。

## 下载

```bash
git clone https://github.com/ehForwarderBot/efb-install.git
cd efb-install
bash install.sh --help
```

旧版仅下载 `install.sh` 的运行方式已不适用，Dockerfile、Compose 和依赖文件必须一起下载。不要直接运行未经检查的远端 `curl | bash` 脚本。

## Docker Compose 部署

前提：Docker Engine / Docker Desktop、**Docker Compose v2**（`docker compose`）和使用者对 Docker 的操作权限。脚本不会自动安装 Docker。

```bash
bash install.sh docker init       # 生成 .env 和 data，已有文件不覆盖
bash install.sh docker build      # 从本仓库 Dockerfile 构建镜像
bash install.sh docker configure  # efb-wizard 配置 Telegram / 微信
bash install.sh docker up         # 后台运行
bash install.sh docker logs       # 查看扫码/登录情况，Ctrl+C 退出
```

默认完整数据位于 `./data`，默认 Profile 为 `default`（可通过 `.env` 中的 `EFB_PROFILE` 更改）；对应配置为 `profiles/<Profile名>/config.yaml`，同时持久化 Telegram 数据库、微信登录会话文件、PUID 和群组绑定等。容器不会发布任何入站端口。向导交互时需先配置 Telegram Bot Token，但 Token 只保存在本地数据目录，不写入代码仓库。

`.env` 中可以设置 `EFB_UID` / `EFB_GID`（容器运行用户）、`EFB_PROFILE`（默认 `default`）、`EFB_CONFIG_DIR`（默认 `./data`）及 `TZ`（默认 UTC）。运行 `docker init` 时 UID/GID 通常取当前用户；以 root 初始化时采用 1000:1000，避免默认以 root 身份启动机器人。Dockerfile 还会按该 UID/GID 建立实际 passwd 用户记录，以减少 `Could not determine home directory` 问题。数据目录必须对该 UID/GID 可读写；不要无差别递归更改旧生产目录的所有者。操作 Docker 的权限本身应被视为敏感权限。

常用维护操作：

```bash
bash install.sh docker status
bash install.sh docker doctor                # 诊断 Compose/Profile 及所需插件
bash install.sh docker restart
bash install.sh docker stop
bash install.sh docker update                 # 重新拉取基础镜像、重建、重新创建容器
bash install.sh docker backup /安全路径/efb-docker.tar.gz
```

备份会临时停止正在运行的 EFB 容器，打包整个配置目录后恢复原运行状态，减少 SQLite 在线写入导致备份不一致的风险。备份包含身份凭据，务必限制访问。更新之前必须先备份；更新不会保证旧插件或数据库的兼容性。

增加插件或自定义中间件：在 `requirements-extra.txt` 中添加经验证的包并重建镜像（通用依赖仍放 `requirements.txt`）。更改基础镜像：编辑 `Dockerfile` 中的 `PYTHON_IMAGE`。建议正式部署时另外固定依赖版本。多个实例分别使用不同仓库目录、`.env`、数据路径与 Compose project，**不得共享同一个活动数据库**。

## 原生 Debian / Ubuntu 部署

仅支持 systemd 环境。必须有 root 权限；脚本仅安装必要依赖，不做系统全量升级，也不修改系统 Python 的 alternatives 或全局 pip。

```bash
sudo bash install.sh native install
sudo bash install.sh native status
sudo bash install.sh native doctor
sudo bash install.sh native logs
sudo bash install.sh native configure
sudo bash install.sh native restart
sudo bash install.sh native backup /安全路径/efb-native.tar.gz
```

原生安装位置（`default`）：

| 项目 | 路径 |
| --- | --- |
| 独立 venv | `/opt/efb/venv` |
| systemd 服务 | `/etc/systemd/system/efb.service` |
| 配置、数据库和授权缓存 | `/var/lib/efb/.ehforwarderbot` |
| 运行用户 | `efb`（无交互登录 shell） |

使用其他 Profile 时，服务名、Linux 运行用户、Home 和 venv **全部独立**。例如：

```bash
EFB_PROFILE=alpha bash install.sh native info
# Service=efb-alpha Profile=alpha User=efb-alpha Home=/var/lib/efb-alpha Venv=/opt/efb-alpha/venv
sudo EFB_PROFILE=alpha bash install.sh native install
sudo EFB_PROFILE=alpha bash install.sh native doctor
sudo EFB_PROFILE=alpha bash install.sh native backup /安全路径/alpha.tar.gz
```

Profile 只允许小写字母、数字、连字符和下划线（以字母开头，最多 24 字符）。三套原生安装可各自创建 Profile，互不共用 SQLite，也不会覆盖别的 systemd 服务。可以通过 `EFB_NOFILE=65536` 设置该新服务的文件描述符上限，**但提高上限不是修复连接泄漏**。

默认采用系统的 `python3`。建议先确认其与 EFB 依赖兼容；如需指定，使用 `sudo EFB_PYTHON=/usr/bin/python3.12 bash install.sh native install`，指定的 Python 需能运行 `venv`。在 Python 3.13/3.14 上，**依赖可以安装成功，也不等于插件可正常运行**。

## 老版本迁移与数据安全

此脚本没有“一键清空/卸载数据”功能。如果检测到不是本脚本创建的 `/etc/systemd/system/efb.service`，原生安装会拒绝覆盖。现有 `/root/.ehforwarderbot`、自定义 profile 和业务数据均不会被修改。

迁移请先停止旧服务，备份 `.ehforwarderbot` 中的全部 profiles、数据库、Telegram 群组绑定及微信会话缓存；再将完整目录复制到新的服务用户主目录或 Docker 的 `data`，检查权限并测试登录。切换时旧实例必须停机，不能让新旧实例同时操作相同 Bot Token、微信登录会话或 SQLite 数据库。

不要轻易运行 `docker compose down -v`，更不能未经确认删除 `data`。

## 三个真实 EFB 实例的兼容性与故障经验

以下信息来源于 **2026-11-12 对两台 Ubuntu 26.04 ARM64 服务器的只读检查**。为避免把私有服务器标识、账号、令牌或数据库位置发布到公开仓库，实例以 A/B/C 匿名表示。下表仅为现场取样，不能代表全部平台或微信账号的兼容保证。

| 检查项目 | 实例 A | 实例 B | 实例 C |
| --- | --- | --- | --- |
| Profile | 独立 Profile A | 独立 Profile B | 独立 Profile C |
| 运行方式 | systemd | systemd | systemd |
| 状态 | 运行中 | 运行中 | 运行中 |
| Python | 3.14.4 | 3.14.4 | 3.14.4 |
| 独立环境 | 与 B 共用一个 venv | 与 A 共用一个 venv | 独立 venv，含 Telegram 超时修复 |
| 打开的 FD（一次取样） | 约 325 | 约 1,479 | 约 2,048 |

三个实例均安装 EFB 2.1.1、Telegram Master 2.3.1、WeChat Slave 2.0.7，但**具体依赖版本不一致**：A/B 的 Peewee 为 4.x、Telegram SDK 为 13.15；C 的 Peewee 为 3.x、Telegram SDK 为 13.13。它们当前能够运行，并不意味着可以任意交换这些版本。通用 Docker 仍默认 Python 3.12，使用 CI 验证过的兼容版本限制；**不自动照搬生产机的 Python 3.14 或定制模块**。

### 1. 多 Profile 与 systemd 运行环境

- systemd 服务名和 EFB Profile 是两个概念，启动与向导都必须明确 `--profile`。
- 每个 Profile 的 `config.yaml`、Telegram SQLite、微信会话授权、PUID 和 Telegram 群组绑定需要完整保存。不同 Profile 不可同时使用同一份正在写入的 SQLite 数据库。
- 原有实例经过 Python 3.8→3.14 升级，保留了多个虚拟环境与 systemd drop-in。修改 `ExecStart` 之前要先通过 `systemctl show <服务名> -p ExecStart -p DropInPaths` 判断真正生效的启动命令。
- 新脚本通过 `EFB_PROFILE=alpha` 为原生模式生成独立的 `efb-alpha` 服务、`efb-alpha` Linux 用户、Home、venv，避免多个 Profile 互相影响；不自动迁移或覆写现存服务。
- 实测三个 Profile 都启用了 `catbaron.link_preview` 与 `catbaron.mp_instantview`。对应的安装包为 `efb-link-preview-middleware==0.1.0` 和 `efb-mp-instantview-middleware==0.3.2`（放在 `requirements-extra.txt`，按需取消注释）。另有独立环境安装了 `efb-online-guard`，不能简单假设该包对所有人可从 PyPI 安装。
- 新增 `tools/validate_profile.py`：只读取配置结构和 EFB entry point，确认 Master、Slave、Middleware 均已注册；检测到缺失插件时，阻止新容器或新原生服务启动。它不会输出 Token、微信缓存或业务数据库内容。
- `Could not determine home directory` 应优先排查服务用户、passwd 记录、`HOME` 和数据目录权限。Dockerfile 现在会依照映射的 UID/GID 创建真实用户，而不只设置 `USER` 环境变量。

### 2. FD 增长与 SQLite/Peewee

- B/C 的 FD 数量明显高于 A，且大部分与数据库/会话文件有关；其中一套日志出现大量 FD 与数据库相关报错。
- 这是**需要持续排查的风险信号**，仅凭单次 FD 数和日志关键词数量不能断言确切泄漏原因。
- 推荐按时间记录 `FD total`、`SQLite-related` 和 `LimitNOFILE`；检查 Peewee 连接的创建与关闭、SQLite WAL 生命周期。新脚本的 `native doctor` 只读输出 FD 计数和版本。
- 可以临时提高 `LimitNOFILE` 减轻耗尽风险，但**不能替代修复资源生命周期**。不要直接删除打开的 `.db-wal` / `.db-shm` 文件。

### 3. Telegram 超时、有限重试和限流

- 一套真实环境采用了**上传超时 120 秒 + 网络超时额外重试一次**的独立定制 venv。这不是 upstream PyPI 包的通用行为。
- 不能简单地对所有请求无条件重试。针对 `TimedOut` / `NetworkError` 要限制次数、使用合理的退避；针对 `FloodWait` / `RetryAfter` 必须尊重服务器指示的等待时间。
- 默认安装器**不会 monkey-patch** Telegram SDK，也不会改动 `send_image_as_file`。要复用生产定制时，应另行维护有版本标识的补丁，独立测试发送图片、文件、大媒体和失败重试，再部署。

### 4. 微信缓存、二维码及绑定状态

- 出现 `Confirm on your phone.` 通常意味着等待手机确认，不是单纯的二维码生成失败；持续重启不能解决账号登录资格或手机确认问题。
- 登录排障先完整备份单个受影响 Profile，然后在旧实例停机的前提下检查缓存；不要清空整个 `.ehforwarderbot`。
- 迁移后不能只验收“进程正在运行”，还要核对公众号 PUID、Telegram 群组绑定、群名以及文字、图片的双向转发。

### 5. 备份、升级与可回退

- 实际部署采用每周备份计时器，部分实例另有独立在线监控。本安装器不会覆盖现有任务。
- 数据库可达数百 MB 甚至 GB。备份前应检查可用磁盘空间、停机完成一致性归档，并通过 `tar -tzf` 验证归档可读。脚本现在禁止备份文件覆盖已有文件或写入被备份的数据目录。
- 推荐操作顺序：记录 `systemctl show` 生效的命令、Profile 和依赖版本 → 备份 → 在新的独立环境执行 `pip check`、模块导入 → 单实例验证数据与微信授权 → 观察日志/FD → 核对 PUID 与群组绑定 → 最后切换生产。
- 升级 Python、Peewee、Telegram SDK 或中间件前应逐项核对兼容性。**运行环境可用不代表安全维护仍然充分**，旧依赖应继续跟踪安全更新。

## 排查

- `docker compose config` 检查 Compose 配置；`docker compose logs -f efb` 查看容器日志。
- `journalctl -u efb -n 200 --no-pager` 查看原生日志。
- 微信扫码/确认状态可从日志查看；微信账号被限制 Web 登录时，安装脚本无法绕过限制。
- 出现 `Could not determine home directory` 时，检查 `HOME`、UID/GID 与数据目录写入权限。
- 不要使用 `pip --break-system-packages` 覆盖系统 Python。

相关资料：[EFB 入门文档](https://ehforwarderbot.readthedocs.io/en/latest/getting-started.html) · [微信从端项目](https://github.com/ehForwarderBot/efb-wechat-slave)
