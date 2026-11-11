# EH Forwarder Bot 安装与运维手册

> **efb-install：原生 Python + systemd / Docker Compose**
>
> 面向使用 **Telegram Master + WeChat Slave** 的 EH Forwarder Bot（简称 EFB）。提供新安装、多 Profile 隔离部署、插件依赖检查、日志与文件描述符诊断、备份以及审慎升级的操作入口。
>
> **文档状态**：本说明对应 `feature/modern-installer-docker-compose` 分支和 [PR #2](https://github.com/ehForwarderBot/efb-install/pull/2)。PR 未合并前，`main` 仍可能是旧脚本，必须明确检出该分支才能使用本文命令。合并后再改用 `main`。
>
> **重要限制**：安装脚本无法绕过微信网页版登录资格限制，无法保证 Telegram 网络始终可达，也不自动修复第三方插件本身的数据库连接泄漏。不要把「服务 active」误认为「微信已经登录且双向转发全部正常」。

---

## 阅读导航

1. [项目用途与不做什么](#intro)
2. [安装方式选择与兼容性](#choose)
3. [仓库文件及配置结构](#layout)
4. [准备工作与安全检查](#prepare)
5. [Docker Compose 从零安装](#docker-install)
6. [Docker 环境变量与多实例部署](#docker-config)
7. [Docker 日常维护、更新和诊断](#docker-ops)
8. [Debian / Ubuntu 原生安装](#native-install)
9. [原生多 Profile、路径与 systemd 管理](#native-profiles)
10. [原生版本化升级与回退](#native-update)
11. [EFB 配置向导、Telegram 和微信登录](#wizard)
12. [可选插件、中间件及兼容性校验](#plugins)
13. [数据、目录、权限与敏感信息](#storage)
14. [备份、验证与恢复](#backup)
15. [从旧 EFB 安全迁移](#migration)
16. [三个真实 EFB 实例的调查与经验](#field)
17. [Telegram 上传、超时、重试和限流](#telegram)
18. [SQLite / Peewee、FD 增长与资源排查](#fd)
19. [常见故障及逐项处理](#troubleshooting)
20. [安全措施、维护建议与已知限制](#security)
21. [部署验收清单](#acceptance)
22. [命令速查表和资料链接](#reference)

<a id="intro"></a>

## 1. 项目用途与不做什么

EFB 是跨消息平台的可扩展框架。这个安装项目目前围绕以下典型组合：

- **Master：** `efb-telegram-master`，在 Telegram 中接收和处理转发内容。
- **Slave：** `efb-wechat-slave`，连接微信网页版通道。
- **Middleware：** 根据实际需求添加公众号文章预览、链接预览、在线状态检测等插件。

本仓库不是上述三个项目的替代实现，主要负责部署与维护。

### 已提供的能力

| 功能 | Docker Compose | 原生 systemd |
| --- | --- | --- |
| 独立安装 Python/EFB 依赖 | 容器镜像 | Python venv |
| 交互式 `efb-wizard` 配置 | 支持 | 支持 |
| 显式 Profile 名称 | `.env` 中 `EFB_PROFILE` | 环境变量 `EFB_PROFILE` |
| 配置、数据库、登录缓存持久化 | Bind mount（默认 `./data`） | 独立的系统用户 Home |
| 后台运行与故障后重启 | Compose `restart: unless-stopped` | systemd `Restart=on-failure` |
| 构建、启动、停止、重启、状态、日志 | 支持 | 支持对应的系统服务操作 |
| 完整数据目录备份 | 支持，停容器复制 | 支持，停服务复制 |
| Profile 中已配置模块的注册检查 | 启动前检查 | 安装/切换前检查 |
| 只读诊断 | Compose / 数据目录 / 模块 | 服务、依赖和 FD |
| 多实例隔离 | 分别创建 Compose 项目和数据目录 | 分别创建服务、用户、Home、venv |
| 自动微信重新登录、跳过手机确认 | **不支持** | **不支持** |
| 自动修复 Peewee/SQLite 文件句柄泄漏 | **不支持** | **不支持** |
| 自动安装 Docker、迁移旧数据库或卸载旧实例 | **不支持** | **不支持** |

### 保留数据是首要原则

安装器不会自动清理已有 `/root/.ehforwarderbot`、删除微信缓存、清除 Telegram 群组绑定或将旧实例搬到 Docker 中。它也不会升级 Linux 内核、修改系统的 `python3` alternatives 或强制使用全局 pip。

对已有生产实例，建议 **先检查、再备份、后迁移**。尤其不要让两个正在运行的 EFB 同时操作同一 Telegram Bot Token、微信会话或 SQLite 数据库。

<a id="choose"></a>

## 2. 安装方式选择与兼容性

| 情况 | 建议方式 | 原因与代价 |
| --- | --- | --- |
| 新部署且宿主机有 Docker | Docker Compose | 易于隔离环境、重建镜像、转移数据；需要维护 Docker 本身 |
| Debian / Ubuntu，倾向系统服务 | Python venv + systemd | 直接使用 journalctl / systemctl，便于按 Profile 独立管理；需要 root |
| 已有复杂 EFB / 多个 Profile / 定制 SDK | **优先保留旧实例，另起测试环境** | 一键替换可能破坏插件和授权缓存 |
| macOS | Docker Desktop + Compose | 原生 systemd 路径不支持 macOS |
| CentOS 7 / 旧发行版 | 评估 Docker 或先升级宿主机 | 不再提供旧 CentOS 7 yum + Python 3.6 自动安装流程 |

**Python 兼容性注意：**

- Docker 默认镜像为 `python:3.12-slim-bookworm`，不是「系统能安装的最新版 Python」。
- Python 3.13 起移除部分旧标准库模块，旧 Telegram / 微信插件不一定完成迁移。
- 我们在真实运行环境观察到 Python 3.14.4 的实例，但它们具有特定依赖和部分本地定制。**生产能运行不等于使用原版 PyPI 包即可复现。**
- 原生模式接受 Python **3.10 或更高版本**，这只是脚本最低版本检查；实际能否工作，还要以依赖安装、模块导入、登录和消息转发测试为准。
- 部分旧依赖的版本约束是兼容性措施，不代表其安全漏洞已经修复。

**网络要求：** 安装阶段需访问源码仓库、软件包源或镜像仓库；运行阶段需要能够访问 Telegram API 和相应微信服务。EFB 通常建立**出站连接**，本 Compose 文件默认不公布 HTTP / TCP 入站端口。

<a id="layout"></a>

## 3. 仓库文件及配置结构

~~~~text
efb-install/
├── install.sh                   # 统一操作入口（原生 / Docker）
├── Dockerfile                   # Python 3.12 + EFB 镜像
├── docker-compose.yml           # 容器、持久化、日志、资源限制
├── requirements.txt             # 核心 EFB 和兼容性依赖
├── requirements-extra.txt       # 按需开启的额外中间件
├── tools/
│   └── validate_profile.py     # 校验 Profile 引用的模块是否已注册
├── tests/
│   └── smoke.sh                # 脚本与模拟 Docker 工作流测试
├── .github/
│   └── workflows/
│       └── ci.yml              # GitHub Actions Linux 镜像测试
├── .dockerignore               # 避免将本地数据打入镜像
├── .gitignore                  # 忽略 .env、data、备份等
└── readme.md                   # 本手册

# 执行 docker init 后，工作目录还会有：
├── .env                        # UID / GID / Profile / 时区 / 数据位置
└── data/                       # 默认持久化目录，不应上传到 Git
    └── profiles/
        └── default/
            ├── config.yaml
            ├── blueset.telegram/
            ├── blueset.wechat/
            └── ...             # 其他中间件或运行时目录
~~~~

实际 Profile 内容随插件版本而变化，不能只备份上面示意的几个文件。Telegram 数据库、SQLite WAL/SHM、微信会话文件、公众号 PUID、绑定关系都可能在插件各自子目录下。

<a id="prepare"></a>

## 4. 准备工作与安全检查

### 4.1 检查当前服务器

在 Debian / Ubuntu 中：

~~~~bash
cat /etc/os-release
uname -m
python3 --version
systemctl --version | head -1
df -h
~~~~

若计划使用 Docker，还应确认：

~~~~bash
docker --version
docker compose version
docker info
~~~~

最后一条会检测 Docker daemon 是否能访问；命令权限不足时先排查 Docker 环境。**本仓库不会为你安装 Docker。**

### 4.2 克隆正确的分支

在 PR #2 尚未合并时：

~~~~bash
git clone --branch feature/modern-installer-docker-compose \
  --single-branch https://github.com/ehForwarderBot/efb-install.git

cd efb-install
bash install.sh --help
~~~~

PR 合并后可以正常检出默认分支。若只下载了旧版单文件 `install.sh`，会因为缺少 Dockerfile、依赖文件和校验脚本而报错。新版**需要完整仓库**。

不要直接运行不经核对的 `curl ... | bash`。来自 GitHub 的安装脚本会调用系统包管理器、pip、systemd 或 Docker，务必先阅读代码和确认来源。

### 4.3 对于旧生产机，先只读调查

~~~~bash
systemctl list-units --type=service --all | grep -i efb

# 把示例服务名换成实际服务名
systemctl show efb.service \
  -p ActiveState -p MainPID -p ExecStart -p WorkingDirectory \
  -p User -p DropInPaths -p LimitNOFILE

systemctl cat efb.service
~~~~

只读检查本身不会停止进程。若这个服务不是本仓库安装的，不要直接对它执行本安装器的 `native install` 或 `native backup`。旧服务的迁移请看第 15 节。

<a id="docker-install"></a>

## 5. Docker Compose 从零安装

以下流程适用于**一个全新 EFB 实例**，已经存在的实例先看迁移章节。

### 第一步：初始化数据目录与 .env

~~~~bash
cd efb-install
bash install.sh docker init
~~~~

首次运行会建立 `.env` 和 `data/`；再次运行会保留已有 `.env`，不会重置你选择的 Profile。默认变量如下：

~~~~dotenv
EFB_UID=1000
EFB_GID=1000
EFB_PROFILE=default
EFB_CONFIG_DIR=./data
TZ=UTC
~~~~

注意：UID/GID **仅为示例**。如果由普通用户初始化，实际会写入执行者的 UID/GID；如果由 root 初始化，默认采用 1000:1000 而不是以 root 身份运行机器人。需要根据宿主机的目录属主核对。

### 第二步：按需编辑变量

~~~~bash
nano .env
~~~~

例如：

~~~~dotenv
EFB_UID=1000
EFB_GID=1000
EFB_PROFILE=alpha
EFB_CONFIG_DIR=./data
TZ=Asia/Shanghai
~~~~

修改 Profile 后，后面的配置向导与启动都会使用这个名称。不要在一个已经运行的实例上随手改 `EFB_PROFILE`，否则可能表现为「原来的聊天、登录或群组绑定突然消失」，其实是运行了另一个 Profile。

### 第三步：构建镜像

~~~~bash
bash install.sh docker build
~~~~

镜像使用 Python 3.12、FFmpeg、libmagic、Cairo，以及 `requirements.txt` / `requirements-extra.txt` 中列出的包。首次构建需要联网，时间和磁盘占用取决于宿主机与网络。

构建失败时先检查完整错误日志。不要为了强行安装而修改生产 Docker daemon 或关闭所有安全限制。

### 第四步：运行 EFB 配置向导

~~~~bash
bash install.sh docker configure
~~~~

这会在一次性容器中运行：

~~~~text
efb-wizard --profile <.env 中的 EFB_PROFILE>
~~~~

根据向导选择 Telegram Master 和 WeChat Slave，按照提示设置 Telegram Bot、模块等。**Bot Token 不应写进 README、Compose 文件、Dockerfile 或提交至 Git。**

某些插件可能没有完整向导，需按插件自己的说明配置。向导完成后，相关文件应出现在：

~~~~text
data/profiles/<你选择的 Profile>/config.yaml
~~~~

如果 Profile 中引用的可选 Middleware 尚未安装，进入第 12 节添加依赖并重新构建，否则下一步的预检查会拒绝启动。

### 第五步：启动服务

~~~~bash
bash install.sh docker up
~~~~

执行顺序是：

1. 构建当前镜像；
2. 用 `validate_profile.py` 检查 Master / Slave / Middleware 的 entry point；
3. 校验成功后，后台创建或更新 EFB 容器。

**不能保证所有网络或登录问题都在预检查时发现**。模块能导入只是第一关，还要验收真实消息收发。

### 第六步：查看状态、登录及日志

~~~~bash
bash install.sh docker status
bash install.sh docker logs
~~~~

`logs` 会跟随日志输出。退出跟踪用 Ctrl+C，**这不会停止容器**。

如果微信提示扫码或 `Confirm on your phone.`，按实际要求扫码、在手机端确认，并观察是否进入已登录状态。反复重启不等于获得微信网页版登录权限。

### 第七步：完成端到端验收

建议逐项实际发送/接收：

- Telegram → 微信：文字、图片和较大文件；
- 微信 → Telegram：文字、图片和消息来源信息；
- 公众号消息、Telegram 群组绑定及 PUID；
- 重启后登录和绑定状态是否保留；
- 网络短暂故障后是否能够恢复。

仅有 `docker compose ps` 显示 `running` 不构成完整验收。

<a id="docker-config"></a>

## 6. Docker 环境变量、多实例与权限

### 6.1 各项变量的含义

| 变量 | 默认值 | 用途及常见注意事项 |
| --- | --- | --- |
| `EFB_UID` | 当前用户 UID；root 初始化用 1000 | 容器实际运行 UID、镜像内的 passwd 记录 |
| `EFB_GID` | 当前用户 GID；root 初始化用 1000 | 容器实际运行 GID |
| `EFB_PROFILE` | `default` | 传给 `ehforwarderbot --profile` 和 `efb-wizard --profile` |
| `EFB_CONFIG_DIR` | `./data` | Bind mount 到容器内 `/home/efb/.ehforwarderbot` |
| `TZ` | `UTC` | 容器时区环境变量 |

Profile 名称必须以小写字母开头，最多 24 字符，后续仅可使用小写字母、数字、连字符和下划线。

`.env` 使用 `EFB_CONFIG_DIR=./data` 时，路径相对于**仓库所在目录**。如果使用绝对路径，注意 Compose 是否有权限访问该位置。

### 6.2 文件权限与 HOME

容器内默认：

~~~~text
HOME=/home/efb
USER=efb
LOGNAME=efb
XDG_CACHE_HOME=/home/efb/.ehforwarderbot/.cache
~~~~

Dockerfile 按 `EFB_UID` / `EFB_GID` 尝试创建对应的系统用户，避免仅指定数字 UID、却无法从 passwd 记录找到 Home 的问题。

~~~~bash
id
ls -ld data
docker compose --env-file .env config --quiet
~~~~

如果出现权限问题，请先核对 UID/GID、数据目录属主以及 Docker Desktop 的目录共享授权。**不要未经核查就对旧生产数据执行 `chown -R`，更不要将整个目录设为 777。**

镜像基础系统可能已有某些 UID/GID；使用与其冲突的自定义 UID/GID 时，镜像构建可能失败。应换用有效的未冲突映射，再检查数据权限。

### 6.3 两个以上的 Docker EFB 实例

推荐**每个实例独立一份仓库目录**：

~~~~text
/srv/efb-alpha/
    .env
    data/
    docker-compose.yml
/srv/efb-beta/
    .env
    data/
    docker-compose.yml
~~~~

两份 `.env` 分别使用不同 `EFB_PROFILE`、不同 `EFB_CONFIG_DIR` 和不同 Compose 项目名称。特别注意：

1. 不同实例不要共享同一份可写 SQLite 目录；
2. 不要让两个进程同时使用相同的 Telegram Bot Token 和微信授权状态；
3. **当前 Compose 文件的镜像标签固定为 `efb-install:local`**。即使两个 Compose 项目使用不同目录，构建镜像时仍可能复用这个全局标签。生产多实例应为每份 Compose 文件改成不同的 `image:` 标签，避免一次重建意外影响另一实例的下次重新创建；
4. `docker compose` 的项目名应独立，必要时为每个部署配置不同的 `COMPOSE_PROJECT_NAME`。

这部分需要使用者明确规划；安装器不会自动扫描其他目录中的 EFB。

### 6.4 Docker 安全和资源参数

当前 Compose 默认：

- 不公布任何入站端口；
- `restart: unless-stopped`；
- `init: true`，处理容器信号与子进程回收；
- 停止宽限期 `90s`；
- 文件描述符 `nofile` soft/hard 均为 `65536`；
- Docker 日志 `json-file`，单文件最多 `10m`、保留 `5` 份；
- `no-new-privileges` 且丢弃 Linux capabilities。

其中 `nofile` **只是上限，不是 SQLite 或 Peewee 连接泄漏的修复**。Docker socket 权限也很敏感；能操作 Docker 不等于普通无特权用户。

<a id="docker-ops"></a>

## 7. Docker 日常维护、更新与诊断

| 目的 | 命令 | 备注 |
| --- | --- | --- |
| 初始化 | `bash install.sh docker init` | 保留已有 `.env` |
| 构建镜像 | `bash install.sh docker build` | 拉取基础镜像 |
| 再次运行向导 | `bash install.sh docker configure` | 使用当前 Profile |
| 后台启动 | `bash install.sh docker up` | 先构建、检查插件再启动 |
| 查看容器 | `bash install.sh docker status` | 不检查微信是否已登录 |
| 跟踪日志 | `bash install.sh docker logs` | Ctrl+C 仅退出查看 |
| 只读诊断 | `bash install.sh docker doctor` | 检查 Compose / 路径 / 模块 |
| 重启 | `bash install.sh docker restart` | **不重新构建镜像** |
| 停止 | `bash install.sh docker stop` | 不是删除容器/数据 |
| 更新 | `bash install.sh docker update` | 拉取基础镜像、重建、预检查和重新创建 |
| 一致性备份 | `bash install.sh docker backup /安全路径/backup.tar.gz` | 会短暂停止正在运行的容器 |

### 推荐的更新流程

~~~~bash
cd efb-install

# 1. 检查状态及数据空间
bash install.sh docker status
df -h

# 2. 停机一致性备份（敏感归档放在 Git 仓库之外）
mkdir -p "$HOME/efb-backups"
chmod 700 "$HOME/efb-backups"
backup_file="$HOME/efb-backups/efb-before-update-$(date +%Y%m%d-%H%M%S).tar.gz"
bash install.sh docker backup "$backup_file"

# 3. 检查备份可读
gzip -t "$backup_file"
tar -tzf "$backup_file" | head

# 4. 查看近期提交对依赖文件的更改
git log -p -2 -- requirements.txt requirements-extra.txt Dockerfile

# 5. 更新并检查
bash install.sh docker update
bash install.sh docker doctor
bash install.sh docker status
bash install.sh docker logs
~~~~

`docker update` **不会自动先备份**，也不会验证微信账号实际登录、PUID 关系或数据库业务数据是否正常。重大依赖升级应先在克隆的隔离环境中试运行。

如果启动失败，应先检查日志和 Profile 插件依赖，不能直接删除 `data` 或强行创建一个新的微信会话。

<a id="native-install"></a>

## 8. Debian / Ubuntu 原生安装

原生模式要求 Linux + systemd、root 权限以及能够安装 Python venv。目标是一个独立服务，而不是将 EFB 装进系统 Python。

### 8.1 新安装

~~~~bash
cd efb-install

# 查看脚本打算使用的服务、用户、目录
bash install.sh native info

# 全新安装（需要 sudo）
sudo bash install.sh native install
~~~~

安装器会：

1. 检查服务名是否已经被其他安装占用；
2. 在 Debian / Ubuntu 使用 apt 安装 Python venv / 头文件、编译工具、FFmpeg、libmagic、Cairo 等依赖；
3. 创建无登录 shell 的 `efb` 系统用户及 `/var/lib/efb`；
4. 在 `/opt/efb/venv` 创建隔离的 Python 环境；
5. 安装项目依赖并执行 `pip check` 和模块导入测试；
6. 若 Profile 配置不存在，启动 `efb-wizard`；
7. 检查 Profile 引用的模块是否已安装；
8. 创建本项目托管的 systemd unit 并启动服务。

安装器不会将系统 Python 切换到 Python 3.6 / 3.14，也不会使用 `pip --break-system-packages`。

### 8.2 查看运行情况

~~~~bash
sudo bash install.sh native status
sudo bash install.sh native doctor
sudo bash install.sh native logs
~~~~

也可以直接执行：

~~~~bash
sudo systemctl status efb --no-pager
sudo journalctl -u efb -n 200 --no-pager
sudo journalctl -u efb -f
~~~~

原生 `logs` 默认持续跟踪；Ctrl+C 不停止服务。

### 8.3 指定 Python

~~~~bash
# 路径仅为示例，先确认对应解释器已安装并能创建 venv
sudo EFB_PYTHON=/usr/bin/python3.12 bash install.sh native install
~~~~

先执行：

~~~~bash
/usr/bin/python3.12 --version
/usr/bin/python3.12 -m venv --help
~~~~

系统上没有这个版本时，需另行安装对应解释器与 venv 支持。安装脚本不会替你编译新的 Python，也不应为了迁就 EFB 破坏 OS 自带的 Python 环境。

<a id="native-profiles"></a>

## 9. 原生多 Profile、路径与 systemd 管理

### 9.1 Profile 与服务名称的映射

默认 Profile：

| 项目 | 值 |
| --- | --- |
| EFB Profile | `default` |
| systemd 服务名 | `efb.service` |
| Linux 账户 | `efb` |
| HOME | `/var/lib/efb` |
| venv | `/opt/efb/venv` |
| 配置 | `/var/lib/efb/.ehforwarderbot/profiles/default/config.yaml` |

使用 `EFB_PROFILE=alpha` 后：

| 项目 | 值 |
| --- | --- |
| EFB Profile | `alpha` |
| systemd 服务名 | `efb-alpha.service` |
| Linux 账户 | `efb-alpha` |
| HOME | `/var/lib/efb-alpha` |
| venv | `/opt/efb-alpha/venv` |
| 配置 | `/var/lib/efb-alpha/.ehforwarderbot/profiles/alpha/config.yaml` |

### 9.2 创建第二个独立实例

~~~~bash
EFB_PROFILE=alpha bash install.sh native info

sudo EFB_PROFILE=alpha bash install.sh native install

sudo EFB_PROFILE=alpha bash install.sh native status
sudo EFB_PROFILE=alpha bash install.sh native doctor

# 也可直接按真实 systemd 单元名称管理
sudo systemctl status efb-alpha --no-pager
~~~~

如果再建一个 `beta`，其服务、用户、HOME 和 venv 也会独立。这里的「独立」是指**本脚本新建的部署结构**，不意味着它会自动拆分旧的共享 `/root/.ehforwarderbot` 数据目录。

### 9.3 两个容易混淆的参数

- `EFB_PROFILE`：选择 EFB 的 Profile，也决定本脚本新建的 systemd 服务名。
- `EFB_INSPECT_SERVICE`：只在 `native doctor` 中用于**只读检查已有服务**。它不会改变安装目标，也不会获得覆盖其他服务的许可。

例如，查看一台已有服务器的旧服务：

~~~~bash
sudo EFB_INSPECT_SERVICE=legacy-efb bash install.sh native doctor
~~~~

此命令主要检查 systemd 状态和 /proc 中的 FD，不会因此知道旧服务的 HOME、venv 或真实 Profile，也不会替你改它的配置。

### 9.4 systemd 与 FD 限制

~~~~bash
sudo EFB_PROFILE=alpha EFB_NOFILE=65536 bash install.sh native install
~~~~

`EFB_NOFILE` 范围为 1024～1048576，默认 16384。**提高这个值不能修复反复打开数据库连接却不释放的 bug**。建议在观察到 FD 增长时配合第 18 节持续诊断。

不要直接对生产机所有 EFB 服务统一增加 `LimitNOFILE=524288`。额度应按实际使用量、运行账户以及问题根因决定。

<a id="native-update"></a>

## 10. 原生版本化升级与回退

### 为什么不直接原地升级？

部分实际部署经过 Python 3.8、3.13、3.14 的多轮切换，曾保留多套 venv 和 systemd drop-in。随意在**正在使用的 venv** 上执行 `pip install --upgrade`，可能使运行环境的脚本和依赖版本不一致。

本脚本检测到现有服务已经使用目标 venv 时，会拒绝原地覆盖，要求选择**新的版本化 venv 路径**。这是为了保留旧环境作为回退基础。

### 示例：将 alpha 切换到新 venv

~~~~bash
# 1. 记录原 unit，查看真实启动命令
sudo systemctl show efb-alpha -p ExecStart -p DropInPaths
sudo systemctl cat efb-alpha

# 2. 备份（这一步会短暂停止服务）
sudo EFB_PROFILE=alpha bash install.sh native backup \
  /安全路径/alpha-before-upgrade.tar.gz

# 3. 确认新 Python 可用，选择一个新的 venv 目录
sudo EFB_PROFILE=alpha \
  EFB_VENV_DIR=/opt/efb-alpha/venv-v2 \
  EFB_PYTHON=/usr/bin/python3.12 \
  bash install.sh native update

# 4. 验收
sudo systemctl show efb-alpha -p ExecStart -p ActiveState
sudo journalctl -u efb-alpha -n 200 --no-pager
~~~~

示例的 `/安全路径/` 和 Python 路径必须换成真实存在的位置。`EFB_VENV_DIR` 只接受 `/opt/efb*` 下、符合脚本白名单的绝对 venv 路径。

脚本会先安装新环境、执行 `pip check`、检查模块导入和 Profile 的 entry point，再尝试停止旧服务、修改 unit 并启动新环境。如果 `systemctl enable --now` **直接返回失败**，脚本会尝试恢复旧 unit。

**这不是完整自动回滚机制：**

- 服务可能在 `systemctl` 返回成功之后才因微信/Telegram 插件错误而退出；
- 即使恢复旧 unit，也不代表数据库已经恢复到升级前；
- 旧 venv 保留只提供程序回退条件，不会恢复已发生的数据库 schema 迁移；
- systemd drop-in 可能覆盖主 unit 的 ExecStart。必须检查实际生效的命令。

### 手动回退的正确顺序

1. 先停止需要回退的服务，确认不会同时有两个 EFB 写同一个 Profile；
2. 检查 `systemctl cat`、`DropInPaths` 和当前真实 ExecStart；
3. 确认旧 venv 仍存在且依赖可导入；
4. 按 systemd 标准方式恢复此前记录的 ExecStart / unit，`daemon-reload` 后启动；
5. 如涉及数据库写入格式变化，使用事先**验证过的备份**恢复，而不是仅切换 Python；
6. 重新验收文字/图片转发、公众号及群组绑定。

不建议在一份仍有未知 drop-in 的旧服务上，盲目复制本项目生成的 unit 覆盖它。

<a id="wizard"></a>

## 11. EFB 向导、Telegram Bot 与微信登录

### 11.1 Profile 的概念

EFB Profile 是一组独立的模块启用配置。通过 `-p` 或 `--profile` 指定名称：

~~~~bash
ehforwarderbot --profile alpha
efb-wizard --profile alpha
~~~~

本仓库 Docker 和原生路径已经在命令中自动传递 Profile，不需要手工再追加一份 `--profile`。

### 11.2 config.yaml 的结构概念

以下只是为了理解键名的**示意结构**；不要将它当作某个插件版本的完整生产配置，实际请优先使用 `efb-wizard` 和插件文档。

~~~~yaml
master_channel: blueset.telegram
slave_channels:
  - blueset.wechat
middlewares: []
~~~~

EFB 的实际配置还可能包含 logging、telemetry 等字段，Telegram、微信的具体选项通常由各模块单独保存。把 Token 直接写在这份 README 示例中没有任何必要。

### 11.3 微信首次登录

- 某些账号需扫描二维码并在手机上确认；
- `Confirm on your phone.` 通常表示等待手机确认，不能仅凭这句话认定网络、二维码或缓存损坏；
- 微信网页版资格取决于微信侧账号状态。**不能保证新账号或受限账号一定可以使用**；
- 已登录的会话文件是敏感凭据。迁移时不能粗暴删除，否则可能需要重新登录；
- 一次性容器中的向导需要可用的交互终端；自动化无 TTY 运行时可能无法完成交互；
- 排查日志时注意二维码/登录状态可能包含敏感信息，公开提问前先清理。

### 11.4 验证是否真正成功

不要只看「服务 active」。至少验证 Telegram ↔ 微信的文字、图片、文件传输和回执，检查微信联系人/公众号同步、群组绑定、重新启动后的持续登录能力。

<a id="plugins"></a>

## 12. 插件、中间件及依赖校验

### 12.1 当前默认依赖

`requirements.txt` 包含：

~~~~text
ehforwarderbot
efb-telegram-master[tgs]
efb-wechat-slave
urllib3>=1.26.18,<2
peewee>=3.17,<4
setuptools>=67.5,<82
tzlocal==2.1
~~~~

这些不是随意挑选的版本范围：

| 组件 | 版本处理 | 兼容考虑 |
| --- | --- | --- |
| `python-telegram-bot 13.x` | 上游被 EFB Telegram Master 间接依赖 | 与新的 urllib3 / Python 存在老 API 兼容问题 |
| `urllib3` | 固定在 2 以下 | 旧 PTB 引用已在 urllib3 2.x 移除的接口 |
| `Peewee` | 限制在 3.x | 旧 Telegram Master 的数据库实现与 Peewee 4.x 不能直接假定兼容 |
| `setuptools` | 限制在 82 以下 | 旧代码仍可能引用 `pkg_resources` |
| `tzlocal` | 2.1 | 旧 APScheduler 3.6.3 与新版 tzlocal 存在时区 API 差异 |

版本约束解决的是**安装/导入兼容性**，不是长期安全维护保证。依赖可能有新漏洞和弃用风险，应持续审查，而不是永久冻结不管。

### 12.2 三个真实 Profile 的可选中间件

实际环境中观察到：

| EFB 模块 ID | 发行包名 | 检查时版本 |
| --- | --- | --- |
| `catbaron.link_preview` | `efb-link-preview-middleware` | 0.1.0 |
| `catbaron.mp_instantview` | `efb-mp-instantview-middleware` | 0.3.2 |
| 本地自定义在线状态模块（ID 已匿名） | `efb-online-guard` | 0.1.0（仅一套实际 Python 环境安装） |

前两个在三个已检查的 Profile 配置中均被启用。第三个是独立环境中的定制模块，**不能保证通过公开 PyPI 直接安装**；它也不是三个 Profile 都启用的模块。

为避免向所有新用户强制安装不必要的包，本仓库只在 `requirements-extra.txt` 放置注释示例：

~~~~text
# efb-link-preview-middleware==0.1.0
# efb-mp-instantview-middleware==0.3.2
~~~~

如果你的 Profile 真正启用了这两个模块，应先审查兼容性，然后去掉对应行前面的 `#`。

Docker 随后执行：

~~~~bash
bash install.sh docker build
bash install.sh docker up
~~~~

原生模式会在**新 venv 安装阶段**读取两个 requirements 文件；已运行的原生服务要按第 10 节进行版本化更新，不能在旧 venv 上随意覆盖。

### 12.3 为什么必须检查 entry point？

一份 Profile 可以引用多个插件。例如：

~~~~yaml
master_channel: blueset.telegram
slave_channels:
  - blueset.wechat
middlewares:
  - catbaron.link_preview
  - catbaron.mp_instantview
~~~~

如果配置中存在模块 ID，但对应 Python 包没有注册 EFB entry point，EFB 会在初始化时失败。新工具：

~~~~bash
# Docker 会在 up/update 之前自动执行
bash install.sh docker doctor

# 原生在 install/update 之前自动执行
sudo EFB_PROFILE=alpha bash install.sh native doctor
~~~~

`tools/validate_profile.py` 只读取 YAML 的模块列表，检查安装环境的 entry point 是否存在。它**不会输出 Token、联系人、聊天内容或数据库记录**。

注意此工具不能保证模块类实例化、网络认证、数据库迁移与消息转发一定成功，因而不是完整端到端测试的替代品。

<a id="storage"></a>

## 13. 数据、目录、权限及隐私

### 13.1 Docker 数据位置

默认：

~~~~text
./data/
    profiles/
        default/
            config.yaml
            blueset.telegram/
            blueset.wechat/
            其他 Middleware 的目录...
~~~~

容器中映射到：

~~~~text
/home/efb/.ehforwarderbot/
~~~~

### 13.2 原生数据位置

默认 Profile：

~~~~text
/var/lib/efb/.ehforwarderbot/profiles/default/
~~~~

非默认 Profile（例如 alpha）：

~~~~text
/var/lib/efb-alpha/.ehforwarderbot/profiles/alpha/
~~~~

旧版本安装常见于：

~~~~text
/root/.ehforwarderbot/profiles/<name>/
~~~~

**千万不要仅凭这几种路径推断用户当前部署位置。** 先读 `systemctl show ... -p ExecStart -p WorkingDirectory -p User -p Environment`，再核实真实 HOME 和 Profile。一次系统升级可能保留多个并存的 venv、unit drop-in 和历史目录。

### 13.3 哪些数据必须谨慎保护？

- Telegram Bot Token 与 Master 配置；
- 微信登录缓存、会话授权；
- Telegram 消息数据库及 SQLite WAL/SHM；
- 公众号 PUID、联系人、频道/群组 ID 与对应绑定；
- 用户自定义中间件及其数据；
- systemd 环境文件中可能存在的凭据；
- 备份文件，以及备份文件所在磁盘和对象存储。

生产数据不应被 Git 管理、不应作为 Docker 构建上下文打包，也不应为了排查而发到公共 Issue。当前 `.dockerignore`、`.gitignore` 排除了默认 `.env`、`data` 和备份归档，但如自定义了外部目录仍需自行检查。

### 13.4 常见权限错误

- 新 service user 的 HOME 与 passwd 记录不一致；
- Docker 使用 UID 1000，宿主数据却属于另一个 UID；
- 数据目录没有执行/遍历权限；
- 从 root 迁移到非 root 后只复制了文件，未调整所有者；
- 复制后 SELinux/AppArmor 或 Docker Desktop 共享策略仍阻止访问；
- 配置 YAML 有权限，但其 SQLite 子目录不可写。

处理时先**最小范围**地核查路径和权限，不要把 `/root` 或所有用户目录开放给容器。

<a id="backup"></a>

## 14. 备份、验证与恢复

备份是生产升级的必要前提，不是事后想起来再做的装饰。

### 14.1 本仓库备份命令究竟做了什么？

| 操作 | Docker | 原生 |
| --- | --- | --- |
| 备份源 | `.env` 里映射的整个 `EFB_CONFIG_DIR` | 当前本脚本服务用户 Home 下整个 `.ehforwarderbot` |
| 运行中是否会停止 | 是，短暂停容器 | 是，短暂停 systemd 服务 |
| 备份格式 | `.tar.gz` | `.tar.gz` |
| 备份后是否恢复原运行状态 | 会尝试启动原本运行中的实例 | 会尝试启动原本运行中的实例 |
| 是否覆盖已有同名文件 | 不会 | 不会 |
| 是否允许归档写入数据源目录内部 | 不允许 | 不允许 |
| 是否自动加密、同步云端或保留 3 个月 | **不提供** | **不提供** |

两种模式的归档内部结构不一样：

- Docker：通常以 `./profiles/...` 等内容开头；
- 原生：通常以 `.ehforwarderbot/profiles/...` 开头。

恢复时要区分，不能将一种归档直接按另一种路径解包。

### 14.2 Docker 备份

~~~~bash
cd efb-install

mkdir -p "$HOME/efb-backups"
chmod 700 "$HOME/efb-backups"

bash install.sh docker backup \
  "$HOME/efb-backups/efb-$(date +%Y%m%d-%H%M%S).tar.gz"
~~~~

完成后校验（将文件名换成实际值）：

~~~~bash
gzip -t "$HOME/efb-backups/efb-YYYYMMDD-HHMMSS.tar.gz"
tar -tzf "$HOME/efb-backups/efb-YYYYMMDD-HHMMSS.tar.gz" | head -30

# Linux
sha256sum "$HOME/efb-backups/efb-YYYYMMDD-HHMMSS.tar.gz"

# macOS
shasum -a 256 "$HOME/efb-backups/efb-YYYYMMDD-HHMMSS.tar.gz"
~~~~

以上只能检查压缩包结构与校验和，不等于已经做过**真实恢复测试**。正式环境应定期在独立目录恢复，并验证配置、登录与绑定关系。

### 14.3 原生备份

~~~~bash
sudo EFB_PROFILE=alpha bash install.sh native backup \
  /安全路径/efb-alpha-YYYYMMDD.tar.gz
~~~~

此命令只适用于由当前安装器管理、符合本脚本服务路径约定的实例。对于此前人工创建、已被另一套脚本管理的服务，不能拿它当作通用备份脚本使用；需要按真实环境先停机、再另行备份。

### 14.4 Docker 恢复示例：使用新目录验证

**恢复前先阻止旧容器再次同时运行**。以下为已验证来源的可信归档，不能用来随意解包不可信文件：

~~~~bash
cd efb-install

bash install.sh docker stop

# 恢复数据放在 Git 仓库之外，避免意外提交敏感缓存
mkdir -p "$HOME/efb-data-restore"
chmod 700 "$HOME/efb-data-restore"

# 此处以 Docker 备份为例，归档内直接包含 profiles/
tar -xzf /安全路径/efb-backup.tar.gz -C "$HOME/efb-data-restore"

# 请人工编辑 .env，将 EFB_CONFIG_DIR 改成上述目录的绝对路径
nano .env

bash install.sh docker doctor
bash install.sh docker up
~~~~

如果新目录属主与 `.env` 的 `EFB_UID` / `EFB_GID` 不一致，请先核实并修正权限，不要采用无差别的宽权限。原来的 `data` 应保留，作为回退来源，而不是立即删除。

### 14.5 原生恢复原则

先停止服务，在**新的隔离 HOME 或已停机的目标目录**恢复原生归档（其内部有 `.ehforwarderbot/`），核实 Profile、用户、文件权限和 venv，再启动。不要在旧服务仍运行时，将旧归档直接覆盖其 SQLite/WAL 文件。

如果确实发生了 schema 迁移，必须恢复数据库及其对应状态，而不是只复制 `config.yaml`。

### 14.6 备份策略建议

现场实际部署存在**每周备份的 systemd timer**，但本仓库没有安装同样的定时任务。你可以另行配置系统级 timer / cron，并确保：

- 低流量时段进行；
- 停机时间可接受；
- 归档加密、设定访问权限；
- 定期恢复演练；
- 按实际容量与保留策略清理历史备份；
- 不把新的备份放进被备份目录造成自我包含；
- 不让两项计划任务同时备份或更新同一个实例。

<a id="migration"></a>

## 15. 从旧 EFB 安全迁移

这里重点解决一种高风险情形：**旧系统的多个 EFB Profile 共用 `/root/.ehforwarderbot`，但启动命令来自不同 venv 和 systemd drop-in。**

### 15.1 迁移前必须回答的问题

- 当前有几个 EFB 进程？真正的 `-p` / `--profile` 名称是什么？
- 每个实例的 `ExecStart` 最终被哪个 drop-in 覆盖？
- 使用哪个 Python、Telegram SDK、Peewee、微信 Slave 和 Middleware？
- Profile 数据目录与 SQLite/WAL 所在目录有哪些？
- 是否有每周备份、在线检测、FD 监控、额外脚本？
- Telegram Bot Token、群组、公众号 PUID 绑定如何验收？
- 微信是否允许同一账号再次登录？
- 新旧并行时，会不会出现两个进程争抢同一个 Telegram polling / 微信会话？

这些答案没有核实前，不应该通过「卸载旧版，再装新版」的方式迁移。

### 15.2 推荐流程

1. **只读清点**旧 unit、drop-in、Python 路径、Profile 与配置目录；
2. 检查磁盘容量和文件权限，确认备份能写到安全位置；
3. 在旧环境停机一致性备份；保留所有相关 Profile 的配置、数据库、登录缓存和绑定；
4. 在**全新的 venv 或 Docker 目录**准备兼容的依赖，包括额外 Middleware；
5. 确认新环境的 `validate_profile.py` 检查通过；
6. 停止旧 EFB，复制完整的**目标 Profile 相关数据**，避免边复制边写；
7. 核对新运行用户的 HOME、目录所有权、`EFB_PROFILE`；
8. 启动新服务，验证真实文字/图片/文件、公众号、群组绑定；
9. 至少观察一段有代表性的运行时段，检查 FD 趋势、限流、超时与掉线恢复；
10. 验收后再考虑旧服务及旧 venv 的清理。**不要立即删除旧数据**。

### 15.3 迁移时为什么不能只复制 config.yaml？

因为 EFB 的运行状态分散在插件目录：Telegram Master 的 SQLite、微信授权缓存、会话元数据、PUID/群组绑定等可能依赖彼此。如果只复制 YAML，插件能启动却可能出现群组重建、微信要求重新登录、公众号绑定失踪等问题。

当一个旧 `/root/.ehforwarderbot` 同时存放多个 Profile 时，不能简单共享给多个新用户并同时写入。应先分析每个 Profile 的文件树，再在**停机状态**进行隔离复制。

### 15.4 不要误用 `native doctor`

对旧服务，可以：

~~~~bash
sudo EFB_INSPECT_SERVICE=legacy-efb bash install.sh native doctor
~~~~

这只是只读观察 FD 和 systemd 状态，不代表旧服务会因此变成本安装器管理的服务。**切忌把旧的 `legacy-efb.service` 改名、覆盖或者只更换 ExecStart 就宣称迁移完成。**

<a id="field"></a>

## 16. 三个真实 EFB 实例的调查与经验

本节为 **2026-11-12 的现场快照**，来源于两台运行 Ubuntu 26.04 ARM64 的机器（匿名为主机甲和乙）。为保护生产环境，公开 README 不披露实际服务器标识、账号、Bot Token、路径中的自定义标记、群组 ID 或缓存内容。

### 16.1 三个实例运行概况

| 检查项目 | 实例 A（甲） | 实例 B（甲） | 实例 C（乙） |
| --- | --- | --- | --- |
| EFB 进程状态 | running | running | running |
| 启动形式 | systemd | systemd | systemd |
| Python | 3.14.4 | 3.14.4 | 3.14.4 |
| EFB Core | 2.1.1 | 2.1.1 | 2.1.1 |
| Telegram Master | 2.3.1 | 2.3.1 | 2.3.1 |
| WeChat Slave | 2.0.7 | 2.0.7 | 2.0.7 |
| Python 环境 | 与 B 共用一个 venv | 与 A 共用一个 venv | 独立的定制 venv |
| 已打开 FD（一次取样） | 约 325 | 约 1,479 | 约 2,048 |
| FD 限制（当时） | 524288 | 524288 | 65536 |

三个 Profile 都有 1 个 Master、1 个 Slave、2 个启用的 Middleware。只读检查确认各自环境中的四个 entry point 均存在。

### 16.2 实际发现的差异

- A/B 使用的 Telegram SDK 为 **13.15**，Peewee 为 **4.x**；C 使用 Telegram SDK **13.13**、Peewee **3.x**。
- C 的运行环境具有与上传超时及额外重试有关的特定修改；不能认为所有 EFB 新安装都自动拥有相同行为。
- 部分环境经历过 Python 3.8 到 Python 3.14 的更替，保留了多个历史 venv 和层叠 systemd drop-in。
- A/B 服务器具有每周绑定备份和独立在线监控任务；C 服务器同样存在每周备份计时器。
- 近几天的 journal 日志出现 Telegram 网络超时、限流相关关键词；B 还有较多 FD / 数据库类别的异常记录。
- A/B/C 大部分已打开 FD 与数据库或会话文件相关，但需要**连续时间序列**才能判断是否仍在增长，以及是否存在未关闭的数据库连接。

以上是观察事实，不等于每个异常的根因已经证明。安装器没有把某一台机器的自定义插件补丁粗暴复制给所有用户。

### 16.3 从现场经验抽出的通用设计

| 实际问题 | 这次安装器的处理 | 仍需人工处理 |
| --- | --- | --- |
| 多 Profile 混用 service/HOME | 原生服务、用户和 venv 可按 Profile 隔离 | 旧数据的实际拆分和迁移 |
| 改 Python 后出现找不到模块 | 新 venv 安装 + `pip check` + 导入测试 | 定制插件与特定 Python 的深度兼容 |
| 旧 Profile 缺失 Middleware | `validate_profile.py` 启动前检查 | 补充安装/修改所需插件包 |
| 不知道是否存在 FD 增长 | `native doctor` 只读 FD 计数 | 长期取样与 Peewee 连接生命周期修复 |
| 高 FD 接近上限 | 可配置 LimitNOFILE | 修复不释放资源的真正原因 |
| 误删微信会话、群组绑定 | 完整目录备份与拒绝覆盖旧服务 | 恢复演练、PUID/群组核对 |
| Telegram 上传超时 | 记录排障与定制的边界 | SDK 补丁验证、限流协调与消息重试逻辑 |

**结论：** 三个 Profile 正在运行，不能据此推导它们可以直接迁到通用 Docker 镜像，也不能据此宣称 Peewee 4.x 与 Python 3.14 在所有 EFB 组合中可靠。迁移前必须逐项验收。

<a id="telegram"></a>

## 17. Telegram 上传、超时、重试与限流

### 17.1 三类错误不要混为一谈

| 现象 | 可能原因 | 处理思路 |
| --- | --- | --- |
| `TimedOut` / `NetworkError` | 网络不稳定、上传耗时、Telegram API 超时 | 区分连接与读取/上传超时，限制重试次数 |
| `RetryAfter` / `FloodWait` / HTTP 429 | Telegram API 主动限流 | 尊重服务端要求的等待时间，避免并发放大 |
| 上传失败后重复消息 | 重试前无法确认服务器是否已接收 | 对发送结果、消息 ID 和重复发送风险做识别 |

### 17.2 生产定制与默认安装器有什么区别？

现场有一个特定 venv 曾采用**上传超时约 120 秒、网络超时额外重试 1 次**的修复策略。它不是本仓库通用安装器的默认功能，实际实现位于对应插件/SDK 层。

如果你的网络频繁上传大媒体超时：

1. 确认日志中的错误来自上传、下载、Telegram polling 还是微信通道；
2. 区分 `connect_timeout`、`read_timeout`、`write_timeout`（具体字段依 SDK 版本而定）；
3. 明确「最多额外重试一次」等上限，不要无限循环；
4. 限流时使用服务端建议的等待时间和统一协调策略；
5. 重新发送前考虑重复转发、目标群组和消息顺序；
6. 验证图片作为图片/文件的发送方式，避免未经授权转换源文件；
7. 留存新的独立版本和回退路径，不要在线改动正运行的 site-packages。

**本仓库不会修改 `send_image_as_file` 或自动打补丁。** 如果需要这种行为，应作为可审计的独立插件改动开发和测试。

<a id="fd"></a>

## 18. SQLite、Peewee、FD 增长与资源诊断

### 18.1 FD 是什么？

文件描述符（File Descriptor，FD）是进程访问文件、数据库、socket 等资源的句柄。它高并不必然意味着泄漏：Telegram 连接、SQLite 主数据库及 WAL/SHM、缓存文件都可能正常占用 FD。

但如果进程在无明显业务增长的情况下，FD 持续、单向升高，最终接近上限，就需要排查资源是否正确关闭。

### 18.2 使用本脚本诊断

本项目管理的新原生实例：

~~~~bash
sudo EFB_PROFILE=alpha bash install.sh native doctor
~~~~

已有 systemd 服务的只读诊断：

~~~~bash
sudo EFB_INSPECT_SERVICE=legacy-efb bash install.sh native doctor
~~~~

诊断会显示进程状态、MainPID、LimitNOFILE，并在可以访问 `/proc/<PID>/fd` 时统计：

- FD 总数；
- 与 SQLite 扩展名匹配的 FD 数量；
- 是否超过较高的提示阈值。

**不要把 SQLite-related 这一项当成数据库连接数的严格计数。** 某些路径不按标准扩展名命名，同一数据库也可能有多个句柄。

### 18.3 按时间观察，而不是看一个瞬间

推荐记录同一个服务不同时段的 FD，总结趋势，并与 Telegram 发送量、图片上传、微信重连、SQLite 写入和错误日志关联起来。单次 2,048 FD 不能证明 2,048 个连接都泄漏了。

常用系统命令：

~~~~bash
# 真实服务名自行替换
systemctl show legacy-efb -p MainPID -p LimitNOFILE
sudo journalctl -u legacy-efb --since "2 hours ago" --no-pager
~~~~

如需用 `ls /proc/<PID>/fd` 或 `lsof` 做深入排障，注意必须拥有相应权限，而且命令可能暴露私有文件路径；公开日志前应脱敏。

### 18.4 Peewee / SQLite 需要检查的点

- 每次请求结束后是否关闭数据库连接；
- 异常分支是否漏掉 `close()`；
- 使用数据库连接池时是否设置容量与生命周期；
- 多线程访问的 SQLite 连接是否符合线程约束；
- 是否有 WAL/SHM 长期占用和 checkpoints 异常；
- 是否存在 `database is locked`、`Too many open files`、`OperationalError`；
- 进程重启后 FD 是否短暂下降又持续增长。

**不要在运行时删除 SQLite WAL/SHM 文件、直接修改生产数据库或反复强杀进程。** 可以临时提高 LimitNOFILE 给排障争取空间，但根因仍应在插件/连接生命周期修复。

<a id="troubleshooting"></a>

## 19. 常见故障及逐项处理

建议先从最小范围定位故障，不要直接重新安装或清空数据。

| 报错 / 现象 | 首先检查 | 不建议的做法 |
| --- | --- | --- |
| `docker: command not found` | 是否安装 Docker Engine / Desktop | 直接在未知脚本里安装高权限组件 |
| `docker compose version` 失败 | 是否有 Compose v2 插件 | 以为旧版 `docker-compose` 一定等价 |
| Docker daemon 权限不足 | socket 访问权、运行账户、Docker Desktop 状态 | 随意把 socket 对公网开放 |
| `EFB_PROFILE` 不合法 | 必须符合小写字母开头的规则 | 用空格、斜杠或大写作为 Profile |
| `Could not determine home directory` | passwd UID/GID、HOME、映射目录权限 | 只设置环境变量而忽略用户记录 |
| `Permission denied` 写配置 | 运行 UID/GID、宿主目录属主及遍历权限 | `chmod -R 777` |
| `ModuleNotFoundError: ehforwarderbot` | 正在运行的 Python/venv/ExecStart 是否正确 | 升级系统 Python 或破坏其它实例 |
| `missing middleware module` | `config.yaml` 引用的模块是否在当前环境注册 | 删除整个 Profile |
| `pkg_resources` 不存在 | setuptools 与旧 EFB 插件兼容性 | 盲目更新 setuptools 到最新版 |
| `urllib3.contrib.appengine` 不存在 | 旧 PTB 13.x 和 urllib3 的组合 | 只检查 `pip check` 就宣布成功 |
| Peewee 版本变了 | 数据库 API、插件支持范围与日志 | 将实验环境的版本直接覆盖生产 |
| `efb-wizard` 无法互动 | 是否在可用 TTY 终端运行 | 把 Token 当命令行参数暴露 |
| `Confirm on your phone.` | 是否需要在手机上确认微信登录 | 无限重启、删除所有微信缓存 |
| 微信一直无法 Web 登录 | 账号的微信网页版权限和网络 | 宣称安装器可绕过微信侧限制 |
| Telegram `TimedOut` | 网络与请求超时、媒体大小 | 无限无退避重试 |
| `RetryAfter` / `FloodWait` | 服务器建议的等待时间 | 提高并发继续发送 |
| 大图片/文件失败 | FFmpeg、图像依赖、上传超时和 SDK 行为 | 未经核实转换/删除源文件 |
| `Too many open files` | FD 趋势、`LimitNOFILE`、连接关闭情况 | 只把上限设得极高就当修好 |
| `database is locked` | 是否有两个实例共享 SQLite、WAL 状态 | 直接删除数据库 |
| 改 Python 后服务启动但转发失败 | systemd drop-in、模块导入、登录缓存 | 仅用 `systemctl is-active` 验收 |
| 迁移后公众号/群组绑定消失 | 是否复制完整 Profile 和相关数据库 | 只复制 `config.yaml` |
| Docker 构建成功但启动预检查失败 | 缺失 Middleware 或配置错误 | 绕过检查直接启动生产 |
| Docker 日志没看到二维码 | 当前微信状态、插件日志、交互方式 | 先删缓存再看 |
| 备份文件被拒绝覆盖 | 目标文件已存在或写在数据目录内 | 修改脚本强行覆盖旧备份 |
| 同一 Bot 出现 polling 冲突 | 是否有旧/新 EFB 同时运行 | 继续开第三个实例测试 |

### 推荐的排障顺序

1. **定位实例**：Profile、systemd unit / Compose 项目、HOME、venv。
2. **确认状态**：运行中、已退出、持续重启还是等待登录？
3. **查明错误层**：安装依赖、模块导入、微信认证、Telegram 网络、数据连接。
4. **进行只读检查**：`doctor`、`systemctl show`、`journalctl`、Compose 配置。
5. **先保护数据**：有写入、迁移或更换环境的动作前做一致性备份。
6. **最小修复**：只针对已证实的故障点修改，不一次升级所有包。
7. **重新验收**：收发消息、媒体、登录、群组绑定、FD 和错误日志。

<a id="security"></a>

## 20. 安全措施、维护建议与已知限制

### 20.1 建议的基本安全措施

- 不在公开仓库、Issue、Actions 日志和截图中放真实 Bot Token、微信会话或 API 密钥。
- `.env` 设置 600 权限，数据目录尽可能限制只有对应运行用户访问。
- 备份包含高度敏感的授权数据，采用私有存储并考虑额外加密。
- 不把 Docker daemon socket 对公网开放，不给无关用户 Docker 权限。
- 定期审查 Debian/Ubuntu、Docker、Python 依赖及插件版本的安全更新。
- 保留旧环境与可恢复的备份，**但不要让旧环境永久暴露于公共网络**。
- 更新前看差异、看 changelog，尤其是 Python / Telegram SDK / Peewee / SQLite 相关变更。
- 对微信登录失败、长时间 FloodWait、持续 FD 增长建立独立告警。

### 20.2 目前明确不提供的自动化

- 不自动安装/升级 Docker Engine；
- 不自动创建每周备份 timer 或设置三个月过期清理；
- 不自动迁移现有的 systemd/Screen/自定义进程；
- 不自动绑定公众号 PUID 与 Telegram 群组；
- 不自动重建微信已失效的登录资格；
- 不自动提供 Telegram 120 秒上传补丁、有限重试或统一 FloodWait 调度器；
- 不自动清理旧内核、旧 Python、旧 venv、旧数据和旧备份；
- 不保证修改过的上游插件或自定义 Middleware 与通用镜像兼容。

### 20.3 Docker 和原生模式各自的边界

Docker 有独立的镜像和文件系统，但 bind mount 仍连接宿主数据；数据权限、备份和密钥管理仍是管理员责任。

原生 venv 隔离 Python 包，但不会自动防止不同进程使用同一个 Bot Token 或微信账号；系统层的用户、网络和文件权限仍需单独考虑。

CI 的镜像构建、`pip check`、模块导入和 entry point 测试只能覆盖部分兼容问题，**不能代替连接真实 Telegram 和微信账号的验收**。

<a id="acceptance"></a>

## 21. 新安装或迁移后的验收清单

以下清单应在启动前、启动后和观察一段时间后分别复核：

### 启动前

- [ ] 已确认使用的是本仓库新版分支，而不是旧版 `main` 脚本
- [ ] 已确认部署模式（Docker / 原生）
- [ ] 已确认 Profile 名称、运行账户和数据目录
- [ ] 旧数据及授权缓存已有可靠备份，且知道如何恢复
- [ ] Telegram、微信 Slave、Middleware 均已安装并可注册
- [ ] Python / SDK / Peewee / SQLite 版本经过核对
- [ ] 已检查配置不会与另一个正在运行的 EFB 冲突

### 启动后

- [ ] systemd / Docker 显示进程正常
- [ ] 微信实际登录，手机确认流程已完成
- [ ] Telegram Bot 可以接收和发送测试消息
- [ ] 微信 → Telegram 文字、图片正常
- [ ] Telegram → 微信 文字、图片正常
- [ ] 大文件/媒体行为已经检查
- [ ] 公众号及 Telegram 群组绑定与原环境一致
- [ ] 重新启动后授权缓存与绑定关系保留
- [ ] 没有持续 `ModuleNotFoundError`、`FloodWait`、`OperationalError` 等异常

### 稳定性观察

- [ ] FD 在合理范围内，或至少有明确的时间序列和告警
- [ ] SQLite/WAL 没有持续锁定或异常增长迹象
- [ ] 没有两个进程同时操作同一个 Profile/数据库
- [ ] 备份归档经过完整性校验及恢复演练
- [ ] 所有服务、数据目录和备份的位置有记录
- [ ] 已明确回滚步骤和旧 venv / 旧 Docker 镜像的保留方式

<a id="reference"></a>

## 22. 命令速查表与相关资料

### Docker 命令

~~~~bash
bash install.sh docker init
bash install.sh docker build
bash install.sh docker configure
bash install.sh docker up
bash install.sh docker status
bash install.sh docker doctor
bash install.sh docker logs
bash install.sh docker restart
bash install.sh docker stop
bash install.sh docker update
bash install.sh docker backup /安全路径/efb-docker.tar.gz
~~~~

### 原生命令

~~~~bash
bash install.sh native info
sudo bash install.sh native install
sudo bash install.sh native configure
sudo bash install.sh native status
sudo bash install.sh native doctor
sudo bash install.sh native logs
sudo bash install.sh native restart
sudo bash install.sh native stop
sudo bash install.sh native start
sudo bash install.sh native backup /安全路径/efb-native.tar.gz

# 示例：非默认 Profile
sudo EFB_PROFILE=alpha bash install.sh native install
sudo EFB_PROFILE=alpha bash install.sh native doctor

# 示例：仅诊断现有、非本项目托管的服务
sudo EFB_INSPECT_SERVICE=legacy-efb bash install.sh native doctor

# 示例：先备份，再换新 venv
sudo EFB_PROFILE=alpha EFB_VENV_DIR=/opt/efb-alpha/venv-v2 \
  bash install.sh native update
~~~~

### CI 与验证

~~~~bash
# 脚本静态语法
bash -n install.sh

# Shell smoke tests（其中 Docker 操作用 mock 验证）
bash tests/smoke.sh

# 在具备 Docker Compose v2 的机器校验 Compose
bash install.sh docker init
docker compose --env-file .env config --quiet
~~~~

GitHub Actions 在 Linux Runner 中额外执行 Docker 镜像构建、`pip check`、核心模块导入、向导帮助页、Profile 缺失模块检测和可选 Middleware 测试。**查看具体 commit 的运行结果**，不要把旧提交的绿色 CI 当成新提交的结论。

### 资料

- [EFB 核心项目](https://github.com/ehForwarderBot/ehForwarderBot)
- [EFB 官方入门文档](https://ehforwarderbot.readthedocs.io/en/latest/getting-started.html)
- [Telegram Master](https://github.com/ehForwarderBot/efb-telegram-master)
- [WeChat Slave](https://github.com/ehForwarderBot/efb-wechat-slave)
- [Docker Compose 文档](https://docs.docker.com/compose/)
- [systemd.service](https://www.freedesktop.org/software/systemd/man/latest/systemd.service.html)
- [本仓库 PR #2：Docker / 多实例 / 运维文档更新](https://github.com/ehForwarderBot/efb-install/pull/2)

---

**维护约定：** 对实际安装脚本的每次功能调整，应同步修改本文的操作命令、默认值、限制和验收方式。对来自实际服务器的排障经验，必须区分「观察到的事实」「合理推断」「已在隔离环境测试的修复」以及「尚未修复的风险」，不要将单个定制环境包装成通用兼容承诺。
