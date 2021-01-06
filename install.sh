#!/bin/bash
if [[ $EUID -ne 0 ]]; then
  clear
  echo "错误：本脚本需要 root 权限执行。" 1>&2
  exit 1
fi

check_sys() {
  if [[ -f /etc/redhat-release ]]; then
    release="centos"
  elif cat /etc/issue | grep -q -E -i "debian"; then
    release="debian"
  elif cat /etc/issue | grep -q -E -i "ubuntu"; then
    release="ubuntu"
  elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
    release="centos"
  elif cat /proc/version | grep -q -E -i "debian"; then
    release="debian"
  elif cat /proc/version | grep -q -E -i "ubuntu"; then
    release="ubuntu"
  elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then
    release="centos"
  fi
}

welcome() {
  echo ""
  echo "欢迎使用 efb 一键安装程序。"
  echo "安装即将开始"
  echo "如果您想取消安装，"
  echo "请在 3 秒钟内按 Ctrl+C 终止此脚本。"
  echo ""
  sleep 3
}

yum_update() {
  echo "正在优化 yum . . ."
  echo "此过程稍慢 因为需要升级系统依赖"
  yum install yum-utils epel-release -y >>/dev/null 2>&1
  yum localinstall --nogpgcheck https://download1.rpmfusion.org/free/el/rpmfusion-free-release-7.noarch.rpm -y >>/dev/null 2>&1
  yum update -y >>/dev/null 2>&1
}

yum_git_check() {
  echo "正在检查 Git 安装情况 . . ."
  if command -v git >>/dev/null 2>&1; then
    echo "Git 似乎存在，安装过程继续 . . ."
  else
    echo "Git 未安装在此系统上，正在进行安装"
    yum install git -y >>/dev/null 2>&1
  fi
}

yum_python_check() {
  echo "正在检查 python 安装情况 . . ."
  if command -v python3 >>/dev/null 2>&1; then
    U_V1=$(python3 -V 2>&1 | awk '{print $2}' | awk -F '.' '{print $1}')
    U_V2=$(python3 -V 2>&1 | awk '{print $2}' | awk -F '.' '{print $2}')
    if [ $U_V1 -gt 3 ]; then
      echo 'Python 3.6+ 存在 . . .'
    elif [ $U_V2 -ge 6 ]; then
      echo 'Python 3.6+ 存在 . . .'
      PYV=$U_V1.$U_V2
      PYV=$(which python$PYV)
    else
      if command -v python3.6 >>/dev/null 2>&1; then
        echo 'Python 3.6+ 存在 . . .'
        PYV=$(which python3.6)
      else
        echo "Python3.6 未安装在此系统上，正在进行安装"
        yum install python3 -y >>/dev/null 2>&1
        update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.6 1 >>/dev/null 2>&1
        PYV=$(which python3.6)
      fi
    fi
  else
    echo "Python3.6 未安装在此系统上，正在进行安装"
    yum install python3 -y >>/dev/null 2>&1
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.6 1 >>/dev/null 2>&1
  fi
  if command -v pip3 >>/dev/null 2>&1; then
    echo 'pip 存在 . . .'
  else
    echo "pip3 未安装在此系统上，正在进行安装"
    yum install -y python3-pip >>/dev/null 2>&1
  fi
}

yum_screen_check() {
  echo "正在检查 Screen 安装情况 . . ."
  if command -v screen >>/dev/null 2>&1; then
    echo "Screen 似乎存在, 安装过程继续 . . ."
  else
    echo "Screen 未安装在此系统上，正在进行安装"
    yum install screen -y >>/dev/null 2>&1
  fi
}

yum_require_install() {
  echo "正在安装系统所需依赖，可能需要几分钟的时间 . . ."
  yum update -y >>/dev/null 2>&1
  yum install python-devel python3-devel ffmpeg ffmpeg-devel cairo cairo-devel wget -y >>/dev/null 2>&1
  yum list updates >>/dev/null 2>&1
}

apt_update() {
  echo "正在优化 apt-get . . ."
  apt-get install sudo -y >>/dev/null 2>&1
  apt-get update >>/dev/null 2>&1
}

apt_git_check() {
  echo "正在检查 Git 安装情况 . . ."
  if command -v git >>/dev/null 2>&1; then
    echo "Git 似乎存在, 安装过程继续 . . ."
  else
    echo "Git 未安装在此系统上，正在进行安装"
    apt-get install git -y >>/dev/null 2>&1
  fi
}

apt_python_check() {
  echo "正在检查 python 安装情况 . . ."
  if command -v python3 >>/dev/null 2>&1; then
    U_V1=$(python3 -V 2>&1 | awk '{print $2}' | awk -F '.' '{print $1}')
    U_V2=$(python3 -V 2>&1 | awk '{print $2}' | awk -F '.' '{print $2}')
    if [ $U_V1 -gt 3 ]; then
      echo 'Python 3.6+ 存在 . . .'
    elif [ $U_V2 -ge 6 ]; then
      echo 'Python 3.6+ 存在 . . .'
      PYV=$U_V1.$U_V2
      PYV=$(which python$PYV)
    else
      if command -v python3.6 >>/dev/null 2>&1; then
        echo 'Python 3.6+ 存在 . . .'
        PYV=$(which python3.6)
      else
        echo "Python3 未安装在此系统上，正在进行安装"
        add-apt-repository ppa:deadsnakes/ppa -y
        apt-get update >>/dev/null 2>&1
        apt-get install python3 -y >>/dev/null 2>&1
        update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3 1 >>/dev/null 2>&1
        PYV=$(which python3.6)
      fi
    fi
  else
    echo "Python3.6 未安装在此系统上，正在进行安装"
    add-apt-repository ppa:deadsnakes/ppa -y
    apt-get update >>/dev/null 2>&1
    apt-get install python3 -y >>/dev/null 2>&1
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3 1 >>/dev/null 2>&1
  fi
  if command -v pip3 >>/dev/null 2>&1; then
    echo 'pip 存在 . . .'
  else
    echo "pip3 未安装在此系统上，正在进行安装"
    apt-get install -y python3-pip >>/dev/null 2>&1
  fi
}

debian_python_check() {
  echo "正在检查 python 安装情况 . . ."
  if command -v python3 >>/dev/null 2>&1; then
    U_V1=$(python3 -V 2>&1 | awk '{print $2}' | awk -F '.' '{print $1}')
    U_V2=$(python3 -V 2>&1 | awk '{print $2}' | awk -F '.' '{print $2}')
    if [ $U_V1 -gt 3 ]; then
      echo 'Python 3.6+ 存在 . . .'
    elif [ $U_V2 -ge 6 ]; then
      echo 'Python 3.6+ 存在 . . .'
      PYV=$U_V1.$U_V2
      PYV=$(which python$PYV)
    else
      if command -v python3.6 >>/dev/null 2>&1; then
        echo 'Python 3.6+ 存在 . . .'
        PYV=$(which python3.6)
      else
        echo "Python3.6 未安装在此系统上，正在进行安装"
        apt-get update -y >>/dev/null 2>&1
        apt-get install -y build-essential tk-dev libncurses5-dev libncursesw5-dev libreadline6-dev libdb5.3-dev libgdbm-dev libsqlite3-dev libssl-dev libbz2-dev libexpat1-dev liblzma-dev zlib1g-dev >>/dev/null 2>&1
        wget https://www.python.org/ftp/python/3.8.5/Python-3.8.5.tgz >>/dev/null 2>&1
        tar -xvf Python-3.8.5.tgz >>/dev/null 2>&1
        chmod -R +x Python-3.8.5 >>/dev/null 2>&1
        cd Python-3.8.5 >>/dev/null 2>&1
        ./configure >>/dev/null 2>&1
        make && make install >>/dev/null 2>&1
        cd .. >>/dev/null 2>&1
        rm -rf Python-3.8.5 Python-3.8.5.tar.gz >>/dev/null 2>&1
        PYP=$(which python3.8)
        update-alternatives --install $PYP python3 $PYV 1 >>/dev/null 2>&1
      fi
    fi
  else
    echo "Python3.6 未安装在此系统上，正在进行安装"
    apt-get update -y >>/dev/null 2>&1
    apt-get install -y build-essential tk-dev libncurses5-dev libncursesw5-dev libreadline6-dev libdb5.3-dev libgdbm-dev libsqlite3-dev libssl-dev libbz2-dev libexpat1-dev liblzma-dev zlib1g-dev >>/dev/null 2>&1
    wget https://www.python.org/ftp/python/3.8.5/Python-3.8.5.tgz >>/dev/null 2>&1
    tar -xvf Python-3.8.5.tgz >>/dev/null 2>&1
    chmod -R +x Python-3.8.5 >>/dev/null 2>&1
    cd Python-3.8.5 >>/dev/null 2>&1
    ./configure >>/dev/null 2>&1
    make && make install >>/dev/null 2>&1
    cd .. >>/dev/null 2>&1
    rm -rf Python-3.8.5 Python-3.8.5.tar.gz >>/dev/null 2>&1
    PYP=$(which python3)
    update-alternatives --install $PYP python3 $PYV 1 >>/dev/null 2>&1
  fi
  echo "正在检查 pip3 安装情况 . . ."
  if command -v pip3 >>/dev/null 2>&1; then
    echo 'pip 存在 . . .'
  else
    echo "pip3 未安装在此系统上，正在进行安装"
    apt-get install -y python3-pip >>/dev/null 2>&1
  fi
}

apt_screen_check() {
  echo "正在检查 Screen 安装情况 . . ."
  if command -v screen >>/dev/null 2>&1; then
    echo "Screen 似乎存在, 安装过程继续 . . ."
  else
    echo "Screen 未安装在此系统上，正在进行安装"
    apt-get install screen -y >>/dev/null 2>&1
  fi
}

apt_require_install() {
  echo "正在安装系统所需依赖，可能需要几分钟的时间 . . ."
  apt-get install python3.6-dev python3-dev ffmpeg ffmpeg-devel libcairo2-dev libcairo2 -y >>/dev/null 2>&1
}

debian_require_install() {
  echo "正在安装系统所需依赖，可能需要几分钟的时间 . . ."
  apt-get install python3-dev ffmpeg ffmpeg-devel libcairo2-dev libcairo2 -y >>/dev/null 2>&1
}

download_repo() {
  echo "下载 repository 中 . . ."
  cd /root >>/dev/null 2>&1
  git clone https://github.com/shzxm/efb-install.git ~/.ehforwarderbot/profiles/default/ >>/dev/null 2>&1
  cd ~/.ehforwarderbot/profiles/default/ >>/dev/null 2>&1
  echo "Hello World!" >~/.ehforwarderbot/profiles/default/.lock
}

pypi_install() {
  echo "下载安装 pypi 依赖中 . . ."
  $PYV -m pip install --upgrade pip >>/dev/null 2>&1
  $PYV -m pip install -r requirements.txt >>/dev/null 2>&1
  sudo -H $PYV -m pip install --ignore-installed PyYAML >>/dev/null 2>&1
}

configure() {
  config_file=~/.ehforwarderbot/profiles/default/blueset.telegram/config.yaml
  echo "生成配置文件中 . . ."
  echo "bot api 申请地址： https://t.me/BotFather"
  printf "请输入 bot api ："
  read token <&1
  sed -i -e "s/xxxx/${token}/g" $config_file
  printf "请输入 个人 id ："
  read admins <&1
  sed -i -e "s/- 1234/- ${admins}/g" $config_file
}

login_screen() {
  cd /root/.ehforwarderbot/profiles/default
  screen -S efb -X quit >>/dev/null 2>&1
  screen -L -dmS efb
  sleep 4
  echo "请打开 微信"
  screen -x -S efb -p 0 -X stuff "/usr/local/bin/ehforwarderbot"
  screen -x -S efb -p 0 -X stuff $'\n'
  sleep 1
  while [ ! -f "/root/.ehforwarderbot/profiles/default/blueset.wechat/wxpy.pkl" ] ;
  do
    echo "请 扫一扫 二维码登录 微信"
    cat /root/.ehforwarderbot/profiles/default/screenlog.0
    sleep 5
  done
  sleep 5
  screen -S efb -X quit >>/dev/null 2>&1
  rm -rf /root/.ehforwarderbot/profiles/default/screenlog.0
}

systemctl_reload() {
  echo "正在写入系统进程守护 . . ."
  echo "[Unit]
    Description=ehforwarderbot
    After=network.target
    [Install]
    WantedBy=multi-user.target
    [Service]
    Type=simple
    WorkingDirectory=/root
    ExecStart=/usr/local/bin/ehforwarderbot
    Restart=always
    " >/etc/systemd/system/efb.service
  chmod 755 efb.service >>/dev/null 2>&1
  systemctl daemon-reload >>/dev/null 2>&1
  systemctl start efb >>/dev/null 2>&1
  systemctl enable efb >>/dev/null 2>&1
}

start_installation() {
  if [ "$release" = "centos" ]; then
    echo "系统检测通过。"
    welcome
    yum_update
    yum_git_check
    yum_python_check
    yum_screen_check
    yum_require_install
    download_repo
    pypi_install
    configure
    login_screen
    systemctl_reload
    echo "efb 已经安装完毕 在telegram 中 和bot对话 开始使用"
  elif [ "$release" = "ubuntu" ]; then
    echo "系统检测通过。"
    welcome
    apt_update
    apt_git_check
    apt_python_check
    apt_screen_check
    apt_require_install
    download_repo
    pypi_install
    configure
    login_screen
    systemctl_reload
    echo "efb 已经安装完毕 在telegram 中 和bot对话 开始使用"
  elif [ "$release" = "debian" ]; then
    echo "系统检测通过。"
    welcome
    apt_update
    apt_git_check
    debian_python_check
    apt_screen_check
    debian_require_install
    download_repo
    pypi_install
    configure
    login_screen
    systemctl_reload
    echo "efb 已经安装完毕 在telegram 中 和bot对话 开始使用"
  else
    echo "目前暂时不支持此系统。"
  fi
  exit 1
}

cleanup() {
  if [ ! -x "/root/.ehforwarderbot/profiles" ]; then
    echo "目录不存在不需要卸载。"
  else
    echo "正在关闭 efb"
    systemctl disable efb >>/dev/null 2>&1
    systemctl stop efb >>/dev/null 2>&1
    echo "正在卸载efb"
    pip3 uninstall -y -r ~/.ehforwarderbot/profiles/defaultrequirements.txt
    echo "正在删除 efb 文件 . . ."
    rm -rf /etc/systemd/system/efb.service >>/dev/null 2>&1
    rm -rf /root/.ehforwarderbot >>/dev/null 2>&1
    echo "卸载完成 . . ."
  fi
}

reinstall() {
  cleanup
  start_installation
}

cleansession() {
  if [ ! -x "/root/.ehforwarderbot/profiles" ]; then
    echo "目录不存在请重新安装 efb。"
    exit 1
  fi
  echo "正在关闭 efb . . ."
  systemctl stop efb >>/dev/null 2>&1
  echo "正在删除账户授权文件 . . ."
  echo "请进行重新登陆. . ."
  if [ "$release" = "centos" ]; then
    yum_python_check
    yum_screen_check
  elif [ "$release" = "ubuntu" ]; then
    apt_python_check
    apt_screen_check
  elif [ "$release" = "debian" ]; then
    debian_python_check
    apt_screen_check
  else
    echo "目前暂时不支持此系统。"
  fi
  login_screen
  systemctl start efb >>/dev/null 2>&1
}

stop_pager() {
  echo ""
  echo "正在关闭 efb . . ."
  systemctl stop efb >>/dev/null 2>&1
  echo ""
  sleep 3
  shon_online
}

start_pager() {
  echo ""
  echo "正在启动 efb . . ."
  systemctl start efb >>/dev/null 2>&1
  echo ""
  sleep 3
  shon_online
}

restart_pager() {
  echo ""
  echo "正在重新启动 efb . . ."
  systemctl restart efb >>/dev/null 2>&1
  echo ""
  sleep 3
  shon_online
}

install_require() {
  if [ "$release" = "centos" ]; then
    echo "系统检测通过。"
    yum_update
    yum_git_check
    yum_python_check
    yum_screen_check
    yum_require_install
    pypi_install
    systemctl_reload
    shon_online
  elif [ "$release" = "ubuntu" ]; then
    echo "系统检测通过。"
    apt_update
    apt_git_check
    apt_python_check
    apt_screen_check
    apt_require_install
    pypi_install
    systemctl_reload
    shon_online
  elif [ "$release" = "debian" ]; then
    echo "系统检测通过。"
    welcome
    apt_update
    apt_git_check
    debian_python_check
    apt_screen_check
    debian_require_install
    pypi_install
    systemctl_reload
    shon_online
  else
    echo "目前暂时不支持此系统。"
  fi
  exit 1
}

shon_online() {
  echo "请选择您需要进行的操作:"
  echo "  1) 安装 efb"
  echo "  2) 卸载 efb"
  echo "  3) 重新安装 efb"
  echo "  4) 重新登陆 efb"
  echo "  5) 关闭 efb"
  echo "  6) 启动 efb"
  echo "  7) 重新启动 efb"
  echo "  8) 重新安装 efb 依赖"
  echo "  9) 退出脚本"
  echo ""
  echo "     Version：0.1"
  echo ""
  echo -n "请输入编号: "
  read N
  case $N in
  1) start_installation ;;
  2) cleanup ;;
  3) reinstall ;;
  4) cleansession ;;
  5) stop_pager ;;
  6) start_pager ;;
  7) restart_pager ;;
  8) install_require ;;
  9) exit ;;
  *) echo "Wrong input!" ;;
  esac
}

check_sys
shon_online
