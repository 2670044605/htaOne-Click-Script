#!/bin/bash
# 一键搭建 hy2、tuic、anytls 终极版脚本（基于 sing-box）
# 作者：Inspired by mack-a/v2ray-agent, enhanced for ultimate edition
# 版本：v1.0.0 (2026-01-12)
# 支持：Hysteria2 (hy2), TUIC v5, AnyTLS
# 依赖：sing-box, acme.sh for TLS, curl, wget, jq, systemd

set -e

# 颜色输出
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"

# 全局变量
INSTALL_DIR="/etc/vproxy"
SING_BOX_BIN="$INSTALL_DIR/sing-box/sing-box"
CONFIG_DIR="$INSTALL_DIR/config"
ACME_DIR="$HOME/.acme.sh"
DOMAIN=""
EMAIL=""
PROTOCOLS=("hy2" "tuic" "anytls")
SING_BOX_VERSION="latest"  # 或指定如 "1.12.15"

# 检查 root
if [ "$(id -u)" != "0" ]; then
    echo -e "${RED}请以 root 权限运行脚本！${PLAIN}"
    exit 1
fi

# 检测系统架构
ARCH=$(uname -m)
if [[ $ARCH == "x86_64" ]]; then
    ARCH="amd64"
elif [[ $ARCH == "aarch64" ]]; then
    ARCH="arm64"
else
    echo -e "${RED}不支持的架构: $ARCH${PLAIN}"
    exit 1
fi

# 安装依赖
install_deps() {
    if command -v apt &> /dev/null; then
        apt update -y
        apt install -y wget curl jq unzip socat git iptables fail2ban
    elif command -v yum &> /dev/null; then
        yum update -y
        yum install -y wget curl jq unzip socat git iptables-services fail2ban
    else
        echo -e "${RED}不支持的系统！${PLAIN}"
        exit 1
    fi
    systemctl enable fail2ban && systemctl start fail2ban
}

# 下载最新 sing-box
download_sing_box() {
    if [ "$SING_BOX_VERSION" == "latest" ]; then
        SING_BOX_VERSION=$(curl -sL https://api.github.com/repos/SagerNet/sing-box/releases/latest | jq -r '.tag_name' | sed 's/v//')
    fi
    URL="https://github.com/SagerNet/sing-box/releases/download/v$SING_BOX_VERSION/sing-box-$SING_BOX_VERSION-linux-$ARCH.tar.gz"
    mkdir -p $INSTALL_DIR/sing-box
    wget -O /tmp/sing-box.tar.gz $URL
    tar -xzf /tmp/sing-box.tar.gz -C /tmp
    cp /tmp/sing-box-*/sing-box $SING_BOX_BIN
    chmod +x $SING_BOX_BIN
    rm -rf /tmp/sing-box*
    echo -e "${GREEN}sing-box v$SING_BOX_VERSION 已安装！${PLAIN}"
}

# 安装 AnyTLS 支持（sing-anytls）
install_anytls() {
    git clone https://github.com/anytls/sing-anytls /tmp/sing-anytls
    cp /tmp/sing-anytls/sing-anytls $INSTALL_DIR/sing-box/
    chmod +x $INSTALL_DIR/sing-box/sing-anytls
    rm -rf /tmp/sing-anytls
    echo -e "${GREEN}AnyTLS 支持已安装！${PLAIN}"
}

# 申请 TLS 证书
apply_tls() {
    if [ -z "$DOMAIN" ]; then
        read -p "请输入域名 (e.g., example.com): " DOMAIN
    fi
    if [ -z "$EMAIL" ]; then
        read -p "请输入邮箱 (for cert renewal): " EMAIL
    fi
    curl https://get.acme.sh | sh -s email=$EMAIL
    $ACME_DIR/acme.sh --issue -d $DOMAIN --standalone --keylength ec-256
    mkdir -p $CONFIG_DIR/certs
    $ACME_DIR/acme.sh --install-cert -d $DOMAIN --ecc \
        --cert-file $CONFIG_DIR/certs/cert.pem \
        --key-file $CONFIG_DIR/certs/key.pem \
        --ca-file $CONFIG_DIR/certs/ca.pem
    echo -e "${GREEN}TLS 证书已申请！路径: $CONFIG_DIR/certs${PLAIN}"
    # 设置自动续订
    crontab -l > /tmp/cron
    echo "0 0 * * * $ACME_DIR/acme.sh --cron --home $ACME_DIR > /dev/null" >> /tmp/cron
    crontab /tmp/cron
    rm /tmp/cron
}

# 生成 sing-box 配置（支持 hy2, tuic, anytls）
generate_config() {
    PROTOCOL=$1
    PORT=$(shuf -i 10000-65000 -n 1)  # 随机端口
    UUID=$(uuidgen)
    mkdir -p $CONFIG_DIR

    cat > $CONFIG_DIR/config.json << EOF
{
  "log": {
    "level": "info",
    "output": "$INSTALL_DIR/sing-box.log"
  },
  "inbounds": [
    {
      "type": "$PROTOCOL",
      "listen": "::",
      "listen_port": $PORT,
      "users": [
        {
          "uuid": "$UUID",
          "password": "$UUID"  // 对于 hy2/tuic
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "$DOMAIN",
        "certificate_path": "$CONFIG_DIR/certs/cert.pem",
        "key_path": "$CONFIG_DIR/certs/key.pem"
      }
    }
  ],
  "outbounds": [
    { "type": "direct" }
  ],
  "route": {
    "rules": [
      // 分流示例：绕过 BT 下载
      { "protocol": "bittorrent", "outbound": "block" },
      // Warp 分流
      { "domain": ["warp.example.com"], "outbound": "warp" }
    ]
  }
}
EOF
    # AnyTLS 特定调整
    if [ "$PROTOCOL" == "anytls" ]; then
        sed -i 's/"type": "anytls"/"type": "tls", "anytls_enabled": true/' $CONFIG_DIR/config.json
    fi
    echo -e "${GREEN}$PROTOCOL 配置生成！端口: $PORT, UUID: $UUID${PLAIN}"
}

# 创建 systemd 服务
create_service() {
    cat > /etc/systemd/system/vproxy.service << EOF
[Unit]
Description=VProxy Service (sing-box)
After=network.target

[Service]
ExecStart=$SING_BOX_BIN run -c $CONFIG_DIR/config.json
WorkingDirectory=$INSTALL_DIR
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable vproxy
    systemctl start vproxy
    echo -e "${GREEN}服务已启动！日志: $INSTALL_DIR/sing-box.log${PLAIN}"
}

# 防火墙规则
setup_firewall() {
    iptables -A INPUT -p tcp --dport 80 -j ACCEPT   # 为 acme
    iptables -A INPUT -p tcp --dport 443 -j ACCEPT
    iptables -A INPUT -p udp --dport 443 -j ACCEPT  # QUIC for hy2/tuic
    iptables-save > /etc/iptables.rules
    echo -e "${GREEN}防火墙规则已设置！${PLAIN}"
}

# 备份配置
backup_config() {
    tar -czf /root/vproxy_backup_$(date +%Y%m%d).tar.gz $INSTALL_DIR
    echo -e "${GREEN}配置已备份到 /root/！${PLAIN}"
}

# 健康检查
health_check() {
    if ! systemctl is-active --quiet vproxy; then
        echo -e "${YELLOW}服务未运行！尝试重启...${PLAIN}"
        systemctl restart vproxy
    fi
    $SING_BOX_BIN check -c $CONFIG_DIR/config.json
    echo -e "${GREEN}健康检查通过！${PLAIN}"
}

# 更新 sing-box
update_sing_box() {
    systemctl stop vproxy
    download_sing_box
    systemctl start vproxy
    echo -e "${GREEN}sing-box 已更新到最新版！${PLAIN}"
}

# 管理菜单（类似 vasma）
menu() {
    while true; do
        clear
        echo "VProxy 终极版管理菜单"
        echo "1. 安装/更新 sing-box"
        echo "2. 申请/续订 TLS 证书"
        echo "3. 添加 hy2 节点"
        echo "4. 添加 tuic 节点"
        echo "5. 添加 anytls 节点"
        echo "6. 查看订阅链接"
        echo "7. 更新脚本和核心"
        echo "8. 备份/恢复配置"
        echo "9. 健康检查和日志"
        echo "10. 卸载"
        echo "0. 退出"
        read -p "选择: " choice
        case $choice in
            1) download_sing_box; install_anytls ;;
            2) apply_tls ;;
            3) generate_config "hysteria2"; create_service ;;
            4) generate_config "tuic"; create_service ;;
            5) generate_config "anytls"; create_service ;;
            6) echo "订阅链接: sing-box://$UUID@$DOMAIN:$PORT?type=$PROTOCOL" ;;  # 示例，实际调整
            7) update_sing_box ;;
            8) backup_config ;;
            9) health_check; tail -n 20 $INSTALL_DIR/sing-box.log ;;
            10) systemctl stop vproxy; rm -rf $INSTALL_DIR /etc/systemd/system/vproxy.service; echo "${GREEN}已卸载！${PLAIN}" ;;
            0) exit 0 ;;
            *) echo -e "${RED}无效选择！${PLAIN}" ;;
        esac
        read -p "按回车继续..."
    done
}

# 主安装逻辑
main() {
    install_deps
    download_sing_box
    install_anytls
    apply_tls
    setup_firewall
    # 默认安装所有协议
    for proto in "${PROTOCOLS[@]}"; do
        generate_config $proto
    done
    create_service
    health_check
    # 添加 alias（修复版）
    SCRIPT_PATH="$INSTALL_DIR/install.sh"
    
    # 先保存脚本到固定位置
    cp "$0" "$SCRIPT_PATH" 2>/dev/null || curl -sL https://raw.githubusercontent.com/2670044605/htaOne-Click-Script/main/install.sh -o "$SCRIPT_PATH"
    chmod +x "$SCRIPT_PATH"
    
    # 添加 alias 到 .bashrc（避免重复添加）
    if ! grep -q "alias vproxy=" /root/.bashrc; then
        echo "alias vproxy='bash $SCRIPT_PATH menu'" >> /root/.bashrc
    fi
    
    echo -e "${GREEN}安装完成！${PLAIN}"
    echo -e "${YELLOW}请运行以下命令使 vproxy 命令生效：${PLAIN}"
    echo -e "${GREEN}source /root/.bashrc${PLAIN}"
    echo -e "${YELLOW}或者重新登录 SSH 后即可使用 'vproxy' 命令。${PLAIN}"
}

# 如果参数是 menu，则进入菜单；否则安装
if [ "$1" == "menu" ]; then
    menu
else
    main
fi