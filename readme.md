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

默认完整数据位于 `./data`，包括 `profiles/default/config.yaml`、Telegram 数据库、微信登录会话文件、PUID 和群组绑定等。容器不会发布任何入站端口。向导交互时需先配置 Telegram Bot Token，但 Token 只保存在本地数据目录，不写入代码仓库。

`.env` 中可以设置 `EFB_UID` / `EFB_GID`（容器运行用户）、`EFB_CONFIG_DIR`（默认 `./data`）及 `TZ`（默认 UTC）。运行 `docker init` 时 UID/GID 取当前用户。数据目录必须对该 UID/GID 可读写；不要无差别递归更改旧生产目录的所有者。操作 Docker 的权限本身应被视为敏感权限。

常用维护操作：

```bash
bash install.sh docker status
bash install.sh docker restart
bash install.sh docker stop
bash install.sh docker update                 # 重新拉取基础镜像、重建、重新创建容器
bash install.sh docker backup /安全路径/efb-docker.tar.gz
```

备份会临时停止正在运行的 EFB 容器，打包整个配置目录后恢复原运行状态，减少 SQLite 在线写入导致备份不一致的风险。备份包含身份凭据，务必限制访问。更新之前必须先备份；更新不会保证旧插件或数据库的兼容性。

增加插件或自定义中间件：在 `requirements.txt` 中添加包并重建镜像。更改基础镜像：编辑 `Dockerfile` 中的 `PYTHON_IMAGE`。建议正式部署时另外固定依赖版本。多个实例分别使用不同仓库目录、`.env`、数据路径与 Compose project，**不得共享同一个活动数据库**。

## 原生 Debian / Ubuntu 部署

仅支持 systemd 环境。必须有 root 权限；脚本仅安装必要依赖，不做系统全量升级，也不修改系统 Python 的 alternatives 或全局 pip。

```bash
sudo bash install.sh native install
sudo bash install.sh native status
sudo bash install.sh native logs
sudo bash install.sh native configure
sudo bash install.sh native restart
sudo bash install.sh native backup /安全路径/efb-native.tar.gz
```

原生安装位置：

| 项目 | 路径 |
| --- | --- |
| 独立 venv | `/opt/efb/venv` |
| systemd 服务 | `/etc/systemd/system/efb.service` |
| 配置、数据库和授权缓存 | `/var/lib/efb/.ehforwarderbot` |
| 运行用户 | `efb`（无交互登录 shell） |

默认采用系统的 `python3`。建议先确认其与 EFB 依赖兼容；如需指定，使用 `sudo EFB_PYTHON=/usr/bin/python3.12 bash install.sh native install`，指定的 Python 需能运行 `venv`。在 Python 3.13/3.14 上，**依赖可以安装成功，也不等于插件可正常运行**。

## 老版本迁移与数据安全

此脚本没有“一键清空/卸载数据”功能。如果检测到不是本脚本创建的 `/etc/systemd/system/efb.service`，原生安装会拒绝覆盖。现有 `/root/.ehforwarderbot`、自定义 profile 和业务数据均不会被修改。

迁移请先停止旧服务，备份 `.ehforwarderbot` 中的全部 profiles、数据库、Telegram 群组绑定及微信会话缓存；再将完整目录复制到新的服务用户主目录或 Docker 的 `data`，检查权限并测试登录。切换时旧实例必须停机，不能让新旧实例同时操作相同 Bot Token、微信登录会话或 SQLite 数据库。

不要轻易运行 `docker compose down -v`，更不能未经确认删除 `data`。

## 排查

- `docker compose config` 检查 Compose 配置；`docker compose logs -f efb` 查看容器日志。
- `journalctl -u efb -n 200 --no-pager` 查看原生日志。
- 微信扫码/确认状态可从日志查看；微信账号被限制 Web 登录时，安装脚本无法绕过限制。
- 出现 `Could not determine home directory` 时，检查 `HOME`、UID/GID 与数据目录写入权限。
- 不要使用 `pip --break-system-packages` 覆盖系统 Python。

相关资料：[EFB 入门文档](https://ehforwarderbot.readthedocs.io/en/latest/getting-started.html) · [微信从端项目](https://github.com/ehForwarderBot/efb-wechat-slave)
