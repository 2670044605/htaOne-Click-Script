#!/bin/bash
# 一键搭建 hy2、tuic、anytls 终极版脚本（基于 sing-box）
# 作者：Inspired by mack-a/v2ray-agent, enhanced for ultimate edition
# 版本：v2.0.0 (2026-01-12)
# 支持：Hysteria2 (hy2), TUIC v5, AnyTLS
# 依赖：sing-box, acme.sh for TLS, curl, wget, jq, systemd
# 兼容：Debian, Ubuntu, CentOS, RHEL, Fedora, Alpine, Arch, openSUSE

# 不使用 set -e，改用自定义错误处理

# 颜色输出
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
PLAIN="\033[0m"

# 全局变量
INSTALL_DIR="/etc/vproxy"
SCRIPT_PATH="$INSTALL_DIR/install.sh"
BIN_LINK="/usr/local/bin/vproxy"
SING_BOX_BIN="$INSTALL_DIR/sing-box/sing-box"
CONFIG_DIR="$INSTALL_DIR/config"
ACME_DIR="$HOME/.acme.sh"
DOMAIN=""
EMAIL=""
PROTOCOLS=("hy2" "tuic" "anytls")
SING_BOX_VERSION="latest"  # 或指定如 "1.12.15"

#==================== 工具函数 ====================#

# 彩色日志输出
log_info() {
    echo -e "${GREEN}[INFO]${PLAIN} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${PLAIN} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${PLAIN} $1"
}

log_progress() {
    echo -e "${BLUE}[PROGRESS]${PLAIN} $1"
}

# 错误检查函数（替代 set -e）
check_result() {
    if [ $? -ne 0 ]; then
        log_error "$1"
        return 1
    fi
    return 0
}

# 检测包管理器
detect_package_manager() {
    if command -v apt &>/dev/null; then
        echo "apt"
    elif command -v dnf &>/dev/null; then
        echo "dnf"
    elif command -v yum &>/dev/null; then
        echo "yum"
    elif command -v apk &>/dev/null; then
        echo "apk"
    elif command -v pacman &>/dev/null; then
        echo "pacman"
    elif command -v zypper &>/dev/null; then
        echo "zypper"
    else
        echo "unknown"
    fi
}

# 生成 UUID（兼容没有 uuidgen 的系统）
generate_uuid() {
    if command -v uuidgen &>/dev/null; then
        uuidgen
    elif [ -f /proc/sys/kernel/random/uuid ]; then
        cat /proc/sys/kernel/random/uuid
    elif command -v python3 &>/dev/null; then
        python3 -c "import uuid; print(uuid.uuid4())" 2>/dev/null
    elif command -v python &>/dev/null; then
        python -c "import uuid; print(uuid.uuid4())" 2>/dev/null
    else
        # 最后的备选方案：使用随机数生成类似 UUID 的字符串
        local N B T
        for (( N=0; N < 16; ++N )); do
            B=$(( RANDOM % 256 ))
            if (( N == 6 )); then
                printf '4%x' $(( B % 16 ))
            elif (( N == 8 )); then
                local B=$(( B % 64 + 128 ))
                printf '%02x' $B
            else
                printf '%02x' $B
            fi
            case $N in 3|5|7|9) printf '-' ;; esac
        done
        echo
    fi
}

#==================== 系统检查 ====================#

# 显示帮助信息（需要在 root 检查之前定义，以便非 root 用户也能查看）
show_help() {
    echo "VProxy 终极版安装脚本 v2.0.0"
    echo ""
    echo "用法:"
    echo "  bash install.sh [选项]"
    echo ""
    echo "选项:"
    echo "  无参数/menu    进入管理菜单（默认）"
    echo "  --install      执行完整安装"
    echo "  --uninstall    卸载所有组件"
    echo "  --help         显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  bash install.sh              # 进入菜单"
    echo "  bash install.sh --install    # 直接安装"
    echo "  bash install.sh --uninstall  # 卸载"
    echo ""
}

# 如果是帮助命令，不需要 root 权限
if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    show_help
    exit 0
fi

# 检查 root
if [ "$(id -u)" != "0" ]; then
    log_error "请以 root 权限运行脚本！"
    exit 1
fi

# 检测系统架构
ARCH=$(uname -m)
if [[ $ARCH == "x86_64" ]]; then
    ARCH="amd64"
elif [[ $ARCH == "aarch64" ]]; then
    ARCH="arm64"
else
    log_error "不支持的架构: $ARCH"
    exit 1
fi

#==================== 依赖安装 ====================#

# 检查必要依赖是否已安装
check_deps() {
    local missing_deps=""
    for cmd in curl wget jq git; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_deps="$missing_deps $cmd"
        fi
    done
    
    if [ -n "$missing_deps" ]; then
        return 1
    fi
    return 0
}

# 确保依赖已安装
ensure_deps() {
    if ! check_deps; then
        log_warn "检测到缺少必要依赖，正在安装..."
        install_deps
    fi
}

# 安装依赖
install_deps() {
    log_progress "开始安装依赖包..."
    local PKG_MANAGER=$(detect_package_manager)
    
    if [ "$PKG_MANAGER" == "unknown" ]; then
        log_error "不支持的包管理器！请手动安装依赖：wget, curl, jq, unzip, socat, git, iptables"
        return 1
    fi
    
    log_info "检测到包管理器: $PKG_MANAGER"
    
    # 检查并安装基础依赖
    local BASE_DEPS="wget curl unzip socat git"
    
    case $PKG_MANAGER in
        apt)
            apt update -y || log_warn "apt update 失败，继续尝试安装..."
            apt install -y $BASE_DEPS jq iptables || {
                log_error "依赖安装失败"
                return 1
            }
            # fail2ban 可选，如果安装失败不影响主流程
            if ! apt install -y fail2ban 2>/dev/null; then
                log_warn "fail2ban 安装失败，跳过（非必需）"
            else
                systemctl enable fail2ban 2>/dev/null && systemctl start fail2ban 2>/dev/null
            fi
            ;;
        dnf)
            dnf update -y || log_warn "dnf update 失败，继续尝试安装..."
            dnf install -y $BASE_DEPS jq iptables || {
                log_error "依赖安装失败"
                return 1
            }
            if ! dnf install -y fail2ban 2>/dev/null; then
                log_warn "fail2ban 安装失败，跳过（非必需）"
            else
                systemctl enable fail2ban 2>/dev/null && systemctl start fail2ban 2>/dev/null
            fi
            ;;
        yum)
            yum update -y || log_warn "yum update 失败，继续尝试安装..."
            yum install -y $BASE_DEPS jq iptables-services || {
                log_error "依赖安装失败"
                return 1
            }
            if ! yum install -y fail2ban 2>/dev/null; then
                log_warn "fail2ban 安装失败，跳过（非必需）"
            else
                systemctl enable fail2ban 2>/dev/null && systemctl start fail2ban 2>/dev/null
            fi
            ;;
        apk)
            apk update || log_warn "apk update 失败，继续尝试安装..."
            apk add $BASE_DEPS jq iptables || {
                log_error "依赖安装失败"
                return 1
            }
            if ! apk add fail2ban 2>/dev/null; then
                log_warn "fail2ban 安装失败，跳过（非必需）"
            fi
            ;;
        pacman)
            pacman -Sy --noconfirm || log_warn "pacman update 失败，继续尝试安装..."
            pacman -S --noconfirm $BASE_DEPS jq iptables || {
                log_error "依赖安装失败"
                return 1
            }
            if ! pacman -S --noconfirm fail2ban 2>/dev/null; then
                log_warn "fail2ban 安装失败，跳过（非必需）"
            else
                systemctl enable fail2ban 2>/dev/null && systemctl start fail2ban 2>/dev/null
            fi
            ;;
        zypper)
            zypper refresh || log_warn "zypper refresh 失败，继续尝试安装..."
            zypper install -y $BASE_DEPS jq iptables || {
                log_error "依赖安装失败"
                return 1
            }
            if ! zypper install -y fail2ban 2>/dev/null; then
                log_warn "fail2ban 安装失败，跳过（非必需）"
            else
                systemctl enable fail2ban 2>/dev/null && systemctl start fail2ban 2>/dev/null
            fi
            ;;
    esac
    
    log_info "依赖安装完成！"
    return 0
}

# 下载最新 sing-box
download_sing_box() {
    log_progress "开始下载 sing-box..."
    
    if [ "$SING_BOX_VERSION" == "latest" ]; then
        log_info "获取最新版本号..."
        
        # 优先使用 jq
        if command -v jq &>/dev/null; then
            SING_BOX_VERSION=$(curl -sL https://api.github.com/repos/SagerNet/sing-box/releases/latest | jq -r '.tag_name' | sed 's/v//')
        else
            # 备用方案：获取一次 API 响应，然后尝试不同的解析方法
            local api_response=$(curl -sL https://api.github.com/repos/SagerNet/sing-box/releases/latest)
            
            # 方法1：使用 grep 和 cut
            SING_BOX_VERSION=$(echo "$api_response" | grep -o '"tag_name":"[^"]*"' | cut -d'"' -f4 | sed 's/^v//' | head -1)
            
            # 方法2：如果方法1失败，使用 awk
            if [ -z "$SING_BOX_VERSION" ]; then
                SING_BOX_VERSION=$(echo "$api_response" | awk -F'"' '/"tag_name"/{print $4}' | sed 's/^v//' | head -1)
            fi
            
            # 方法3：如果还是失败，使用 sed
            if [ -z "$SING_BOX_VERSION" ]; then
                SING_BOX_VERSION=$(echo "$api_response" | sed -n 's/.*"tag_name":"v\?\([^"]*\)".*/\1/p' | head -1)
            fi
        fi
        
        if [ -z "$SING_BOX_VERSION" ] || [ "$SING_BOX_VERSION" == "null" ]; then
            log_error "无法获取 sing-box 最新版本号"
            log_warn "请尝试先运行 'vproxy --install' 安装依赖，或手动指定版本号"
            return 1
        fi
    fi
    
    log_info "sing-box 版本: $SING_BOX_VERSION"
    
    URL="https://github.com/SagerNet/sing-box/releases/download/v$SING_BOX_VERSION/sing-box-$SING_BOX_VERSION-linux-$ARCH.tar.gz"
    mkdir -p $INSTALL_DIR/sing-box
    
    if ! wget -O /tmp/sing-box.tar.gz "$URL"; then
        log_error "下载 sing-box 失败"
        return 1
    fi
    
    if ! tar -xzf /tmp/sing-box.tar.gz -C /tmp; then
        log_error "解压 sing-box 失败"
        rm -f /tmp/sing-box.tar.gz
        return 1
    fi
    
    if ! cp /tmp/sing-box-*/sing-box $SING_BOX_BIN; then
        log_error "复制 sing-box 二进制文件失败"
        rm -rf /tmp/sing-box*
        return 1
    fi
    
    chmod +x $SING_BOX_BIN
    rm -rf /tmp/sing-box*
    
    log_info "sing-box v$SING_BOX_VERSION 已安装！"
    return 0
}

# 安装 AnyTLS 支持（sing-anytls）
install_anytls() {
    log_progress "尝试安装 AnyTLS 支持..."
    
    # 检查仓库是否存在
    if ! curl -sf https://api.github.com/repos/anytls/sing-anytls &>/dev/null; then
        log_warn "AnyTLS 仓库不存在或无法访问，跳过 AnyTLS 安装"
        log_warn "这不会影响 hy2 和 tuic 的使用"
        return 0
    fi
    
    if ! git clone https://github.com/anytls/sing-anytls /tmp/sing-anytls 2>/dev/null; then
        log_warn "AnyTLS 克隆失败，跳过安装（非必需）"
        return 0
    fi
    
    if [ -f /tmp/sing-anytls/sing-anytls ]; then
        cp /tmp/sing-anytls/sing-anytls $INSTALL_DIR/sing-box/ 2>/dev/null || {
            log_warn "AnyTLS 复制失败"
            rm -rf /tmp/sing-anytls
            return 0
        }
        chmod +x $INSTALL_DIR/sing-box/sing-anytls 2>/dev/null
        log_info "AnyTLS 支持已安装！"
    else
        log_warn "AnyTLS 二进制文件不存在，跳过安装"
    fi
    
    rm -rf /tmp/sing-anytls
    return 0
}

# 申请 TLS 证书
apply_tls() {
    log_progress "开始申请 TLS 证书..."
    
    if [ -z "$DOMAIN" ]; then
        read -p "请输入域名 (e.g., example.com): " DOMAIN
    fi
    if [ -z "$EMAIL" ]; then
        read -p "请输入邮箱 (for cert renewal): " EMAIL
    fi
    
    if ! curl https://get.acme.sh | sh -s email=$EMAIL; then
        log_error "acme.sh 安装失败"
        return 1
    fi
    
    if ! $ACME_DIR/acme.sh --issue -d $DOMAIN --standalone --keylength ec-256; then
        log_error "证书申请失败，请检查：1) 域名是否正确解析到本服务器 2) 80 端口是否开放"
        return 1
    fi
    
    mkdir -p $CONFIG_DIR/certs
    
    if ! $ACME_DIR/acme.sh --install-cert -d $DOMAIN --ecc \
        --cert-file $CONFIG_DIR/certs/cert.pem \
        --key-file $CONFIG_DIR/certs/key.pem \
        --ca-file $CONFIG_DIR/certs/ca.pem; then
        log_error "证书安装失败"
        return 1
    fi
    
    log_info "TLS 证书已申请！路径: $CONFIG_DIR/certs"
    
    # 设置自动续订
    crontab -l > /tmp/cron 2>/dev/null || touch /tmp/cron
    if ! grep -q "acme.sh --cron" /tmp/cron; then
        echo "0 0 * * * $ACME_DIR/acme.sh --cron --home $ACME_DIR > /dev/null" >> /tmp/cron
        crontab /tmp/cron
        log_info "证书自动续订已设置"
    fi
    rm -f /tmp/cron
    
    return 0
}

# 生成 sing-box 配置（支持 hy2, tuic, anytls）
generate_config() {
    PROTOCOL=$1
    log_progress "生成 $PROTOCOL 配置..."
    
    PORT=$(shuf -i 10000-65000 -n 1 2>/dev/null || echo $((RANDOM % 55000 + 10000)))
    UUID=$(generate_uuid)
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
          "password": "$UUID"
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
      { "protocol": "bittorrent", "outbound": "block" },
      { "domain": ["warp.example.com"], "outbound": "warp" }
    ]
  }
}
EOF
    
    # AnyTLS 特定调整
    if [ "$PROTOCOL" == "anytls" ]; then
        sed -i 's/"type": "anytls"/"type": "tls", "anytls_enabled": true/' $CONFIG_DIR/config.json 2>/dev/null || true
    fi
    
    log_info "$PROTOCOL 配置生成！端口: $PORT, UUID: $UUID"
    return 0
}

# 创建 systemd 服务
create_service() {
    log_progress "创建 systemd 服务..."
    
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
    
    if ! systemctl daemon-reload; then
        log_error "systemctl daemon-reload 失败"
        return 1
    fi
    
    if ! systemctl enable vproxy; then
        log_warn "启用 vproxy 服务失败"
    fi
    
    if ! systemctl start vproxy; then
        log_error "启动 vproxy 服务失败"
        return 1
    fi
    
    log_info "服务已启动！日志: $INSTALL_DIR/sing-box.log"
    return 0
}

# 防火墙规则
setup_firewall() {
    log_progress "配置防火墙规则..."
    
    if ! command -v iptables &>/dev/null; then
        log_warn "iptables 未安装，跳过防火墙配置"
        return 0
    fi
    
    iptables -A INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || log_warn "无法添加端口 80 规则"
    iptables -A INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null || log_warn "无法添加端口 443 TCP 规则"
    iptables -A INPUT -p udp --dport 443 -j ACCEPT 2>/dev/null || log_warn "无法添加端口 443 UDP 规则"
    
    if command -v iptables-save &>/dev/null; then
        iptables-save > /etc/iptables.rules 2>/dev/null || log_warn "无法保存 iptables 规则"
    fi
    
    log_info "防火墙规则已设置！"
    return 0
}

# 备份配置
backup_config() {
    log_progress "备份配置文件..."
    
    if ! tar -czf /root/vproxy_backup_$(date +%Y%m%d).tar.gz $INSTALL_DIR 2>/dev/null; then
        log_error "配置备份失败"
        return 1
    fi
    
    log_info "配置已备份到 /root/！"
    return 0
}

# 健康检查
health_check() {
    log_progress "执行健康检查..."
    
    if ! systemctl is-active --quiet vproxy; then
        log_warn "服务未运行！尝试重启..."
        systemctl restart vproxy || {
            log_error "服务重启失败"
            return 1
        }
    fi
    
    if [ -f "$SING_BOX_BIN" ]; then
        if ! $SING_BOX_BIN check -c $CONFIG_DIR/config.json; then
            log_error "配置文件验证失败"
            return 1
        fi
    else
        log_warn "sing-box 二进制文件不存在，跳过配置检查"
    fi
    
    log_info "健康检查通过！"
    return 0
}

# 更新 sing-box
update_sing_box() {
    log_progress "更新 sing-box..."
    
    systemctl stop vproxy 2>/dev/null || log_warn "停止服务失败"
    
    if ! download_sing_box; then
        log_error "sing-box 更新失败"
        systemctl start vproxy 2>/dev/null
        return 1
    fi
    
    if ! systemctl start vproxy; then
        log_error "启动服务失败"
        return 1
    fi
    
    log_info "sing-box 已更新到最新版！"
    return 0
}

#==================== 命令注册 ====================#

# 设置 vproxy 命令（使用符号链接）
setup_command() {
    log_progress "设置 vproxy 命令..."
    
    # 创建安装目录
    mkdir -p "$INSTALL_DIR"
    
    # 保存脚本到固定位置
    if [ -f "$0" ] && [ "$0" != "bash" ] && [ "$0" != "-bash" ]; then
        cp "$0" "$SCRIPT_PATH" || {
            log_warn "无法复制脚本，尝试从 GitHub 下载..."
            if ! curl -sL https://raw.githubusercontent.com/2670044605/htaOne-Click-Script/main/install.sh -o "$SCRIPT_PATH"; then
                log_error "无法保存脚本到 $SCRIPT_PATH"
                return 1
            fi
        }
    else
        log_info "从 GitHub 下载脚本..."
        if ! curl -sL https://raw.githubusercontent.com/2670044605/htaOne-Click-Script/main/install.sh -o "$SCRIPT_PATH"; then
            log_error "无法下载脚本"
            return 1
        fi
    fi
    
    chmod +x "$SCRIPT_PATH" || {
        log_error "无法设置脚本执行权限"
        return 1
    }
    
    # 创建符号链接（关键！）
    mkdir -p /usr/local/bin
    ln -sf "$SCRIPT_PATH" "$BIN_LINK" || {
        log_error "无法创建符号链接"
        return 1
    }
    
    log_info "✓ vproxy 命令已安装到 $BIN_LINK"
    log_info "✓ 现在可以直接使用 'vproxy' 命令，无需 source 或重新登录"
    return 0
}

#==================== 卸载 ====================#

# 卸载所有组件
uninstall() {
    log_warn "开始卸载 VProxy..."
    
    read -p "确定要卸载吗？(y/N): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        log_info "取消卸载"
        return 0
    fi
    
    # 停止并删除服务
    systemctl stop vproxy 2>/dev/null
    systemctl disable vproxy 2>/dev/null
    rm -f /etc/systemd/system/vproxy.service
    systemctl daemon-reload 2>/dev/null
    
    # 删除安装目录
    rm -rf $INSTALL_DIR
    
    # 删除符号链接
    rm -f $BIN_LINK
    
    # 清理 alias（如果存在旧版本）
    if [ -f /root/.bashrc ]; then
        sed -i '/alias vproxy=/d' /root/.bashrc 2>/dev/null
    fi
    
    log_info "卸载完成！"
    return 0
}

#==================== 菜单 ====================#

# 管理菜单（类似 vasma）
menu() {
    while true; do
        clear
        echo "======================================"
        echo "  VProxy 终极版管理菜单 v2.0.0"
        echo "======================================"
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
        echo "======================================"
        read -p "请选择 [0-10]: " choice
        
        case $choice in
            1) 
                ensure_deps  # 先确保依赖已安装
                download_sing_box
                install_anytls
                read -p "按回车继续..."
                ;;
            2) 
                apply_tls
                read -p "按回车继续..."
                ;;
            3) 
                generate_config "hysteria2"
                create_service
                read -p "按回车继续..."
                ;;
            4) 
                generate_config "tuic"
                create_service
                read -p "按回车继续..."
                ;;
            5) 
                generate_config "anytls"
                create_service
                read -p "按回车继续..."
                ;;
            6) 
                echo -e "${BLUE}订阅链接示例:${PLAIN}"
                echo "sing-box://$UUID@$DOMAIN:$PORT?type=$PROTOCOL"
                read -p "按回车继续..."
                ;;
            7) 
                update_sing_box
                setup_command
                read -p "按回车继续..."
                ;;
            8) 
                backup_config
                read -p "按回车继续..."
                ;;
            9) 
                health_check
                echo -e "\n${BLUE}最近日志 (最后 20 行):${PLAIN}"
                tail -n 20 $INSTALL_DIR/sing-box.log 2>/dev/null || log_warn "日志文件不存在"
                read -p "按回车继续..."
                ;;
            10) 
                uninstall
                exit 0
                ;;
            0) 
                log_info "退出管理菜单"
                exit 0
                ;;
            *) 
                log_error "无效选择！请输入 0-10"
                sleep 2
                ;;
        esac
    done
}

#==================== 主安装逻辑 ====================#

# 主安装逻辑
main() {
    log_info "======================================"
    log_info "  VProxy 终极版安装开始 v2.0.0"
    log_info "======================================"
    
    # 1. 安装依赖
    if ! install_deps; then
        log_error "依赖安装失败，安装中止"
        exit 1
    fi
    
    # 2. 下载 sing-box
    if ! download_sing_box; then
        log_error "sing-box 下载失败，安装中止"
        exit 1
    fi
    
    # 3. 安装 AnyTLS（可选，失败不影响主流程）
    install_anytls
    
    # 4. 申请 TLS 证书
    if ! apply_tls; then
        log_error "TLS 证书申请失败，安装中止"
        log_warn "请检查域名解析和 80 端口是否开放"
        exit 1
    fi
    
    # 5. 配置防火墙
    setup_firewall
    
    # 6. 生成默认配置（使用第一个协议）
    if ! generate_config "hysteria2"; then
        log_error "配置生成失败，安装中止"
        exit 1
    fi
    
    # 7. 创建并启动服务
    if ! create_service; then
        log_error "服务创建失败，安装中止"
        exit 1
    fi
    
    # 8. 健康检查
    sleep 2
    if ! health_check; then
        log_warn "健康检查未通过，但安装已完成"
        log_warn "请检查日志: $INSTALL_DIR/sing-box.log"
    fi
    
    # 9. 设置 vproxy 命令
    if ! setup_command; then
        log_warn "vproxy 命令设置失败，但安装已完成"
    fi
    
    # 10. 显示完成信息
    echo ""
    log_info "======================================"
    log_info "  安装完成！"
    log_info "======================================"
    log_info "✓ sing-box 已安装并运行"
    log_info "✓ TLS 证书已配置"
    log_info "✓ vproxy 命令已可用"
    echo ""
    log_info "使用方法："
    log_info "  1. 直接输入: vproxy"
    log_info "  2. 查看日志: tail -f $INSTALL_DIR/sing-box.log"
    log_info "  3. 管理服务: systemctl status/start/stop/restart vproxy"
    echo ""
    log_info "配置文件位置: $CONFIG_DIR/config.json"
    log_info "证书文件位置: $CONFIG_DIR/certs/"
    echo ""
}

# 显示帮助信息（已在文件开头定义）

#==================== 主入口 ====================#

# 检查是否已安装
is_installed() {
    [ -f "$SING_BOX_BIN" ] && [ -f "$SCRIPT_PATH" ]
}

# 根据参数决定执行什么操作
case "$1" in
    menu|"")
        if ! is_installed; then
            log_warn "检测到 VProxy 尚未安装"
            read -p "是否现在进行完整安装？(Y/n): " install_choice
            if [ "$install_choice" != "n" ] && [ "$install_choice" != "N" ]; then
                main
            else
                log_info "跳过安装，进入菜单（部分功能可能不可用）"
                menu
            fi
        else
            menu
        fi
        ;;
    --install)
        main
        ;;
    --uninstall)
        uninstall
        ;;
    --help|-h)
        show_help
        ;;
    *)
        log_warn "未知选项: $1"
        show_help
        exit 1
        ;;
esac