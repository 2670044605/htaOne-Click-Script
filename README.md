# htaOne-Click-Script

![Version](https://img.shields.io/badge/version-v2.1.0-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Platform](https://img.shields.io/badge/platform-Linux-lightgrey)

## 简介 / Introduction

这是一个基于 [sing-box](https://github.com/SagerNet/sing-box) 的终极一键搭建脚本，支持 **Hysteria2 (hy2)**、**TUIC v5** 和 **AnyTLS** 协议。
本脚本灵感来源于 `mack-a/v2ray-agent`，旨在提供一个简单、高效且功能强大的代理搭建解决方案。

**当前版本**: v2.1.0 (2026-01-12)

## ✨ 特性 / Features

- **多协议支持**: 一键部署 Hysteria2, TUIC v5, AnyTLS
- **广泛兼容**: 支持 Debian, Ubuntu, CentOS, RHEL, Fedora, Alpine, Arch, openSUSE 等主流 Linux 发行版
- **智能安装**: 首次运行自动检测并提示完整安装，避免依赖缺失问题
- **自动管理**: 包含自动证书申请与续期 (acme.sh)、自动安装 sing-box 核心
- **管理面板**: 提供命令行管理菜单，安装后直接使用 `vproxy` 命令
- **安全性**: 自动配置防火墙规则，支持 Fail2ban
- **分流规则**: 内置基础分流规则（如屏蔽 BT，Warp 分流等）
- **备份与恢复**: 支持配置文件的备份与恢复
- **健壮性**: 完善的错误处理，多重备用方案，安装过程不会因小问题中断

## 📋 系统要求 / Requirements

| 发行版 | 最低版本 | 包管理器 |
|--------|----------|----------|
| Debian | 10+ | apt |
| Ubuntu | 18.04+ | apt |
| CentOS | 7+ | yum |
| RHEL | 7+ | yum |
| Fedora | 30+ | dnf |
| Alpine | 3.12+ | apk |
| Arch Linux | - | pacman |
| openSUSE | 15+ | zypper |

- **架构**: x86_64 (amd64) 或 aarch64 (arm64)
- **权限**: root 用户

## 🚀 快速安装 / Quick Install

**一键完整安装（推荐）**：

```bash
bash <(curl -sL https://raw.githubusercontent.com/2670044605/htaOne-Click-Script/main/install.sh) --install
```

或者使用 wget：

```bash
bash <(wget -qO- https://raw.githubusercontent.com/2670044605/htaOne-Click-Script/main/install.sh) --install
```

**交互式安装**（首次运行会自动提示）：

```bash
bash <(curl -sL https://raw.githubusercontent.com/2670044605/htaOne-Click-Script/main/install.sh)
```

> 💡 首次运行时，脚本会自动检测是否已安装，如未安装会提示 "是否现在进行完整安装？"

## 📖 使用说明 / Usage

安装完成后，**立即**可以在终端使用以下命令（无需重新登录）：

```bash
# 打开管理菜单
vproxy

# 或者使用以下参数
vproxy menu        # 打开管理菜单
vproxy --install   # 执行完整安装
vproxy --uninstall # 快速卸载
vproxy --help      # 显示帮助信息
```

### 📋 菜单功能

| 选项 | 功能 |
|------|------|
| 1 | 安装/更新 sing-box 核心 |
| 2 | 申请/续订 TLS 证书 |
| 3 | 添加 Hysteria2 节点 |
| 4 | 添加 TUIC 节点 |
| 5 | 添加 AnyTLS 节点 |
| 6 | 查看订阅链接 |
| 7 | 更新脚本和核心 |
| 8 | 备份/恢复配置 |
| 9 | 健康检查和日志 |
| 10 | 卸载 |

## 📁 文件结构 / File Structure

```
/etc/vproxy/
├── install.sh          # 主脚本
├── sing-box/
│   └── sing-box        # sing-box 核心
├── config/
│   ├── config.json     # 配置文件
│   └── certs/          # TLS 证书
└── sing-box.log        # 运行日志

/usr/local/bin/vproxy   # 命令链接（指向 /etc/vproxy/install.sh）
```

## ⚠️ 注意事项 / Notes
- 请确保你的服务器已开放相应的端口（80/443 以及随机生成的 UDP 端口）
- 首次安装时需要提供域名和邮箱用于申请证书
- 建议在干净的系统环境下安装
- 本脚本仅供学习交流使用，请勿用于非法用途

## 🔧 故障排查 / Troubleshooting

### `vproxy` 命令不可用

```bash
# 手动创建链接
ln -sf /etc/vproxy/install.sh /usr/local/bin/vproxy

# 或直接运行脚本
bash /etc/vproxy/install.sh
```

### `jq: command not found` 错误

如果在菜单中选择 "安装/更新 sing-box" 时遇到此错误：

```bash
# 方法1：先执行完整安装
bash <(curl -sL https://raw.githubusercontent.com/2670044605/htaOne-Click-Script/main/install.sh) --install

# 方法2：手动安装 jq
apt install -y jq        # Debian/Ubuntu
yum install -y jq        # CentOS/RHEL
dnf install -y jq        # Fedora
apk add jq               # Alpine
pacman -S jq             # Arch
zypper install jq        # openSUSE
```

### 查看服务状态

```bash
systemctl status vproxy
```

### 查看日志

```bash
tail -f /etc/vproxy/sing-box.log
```

### 重启服务

```bash
systemctl restart vproxy
```

## 📝 更新日志 / Changelog

### v2.1.0 (2026-01-12)
- ✨ 新增：首次运行智能检测，自动提示完整安装
- ✨ 新增：菜单选项自动检查并安装缺失依赖
- ✨ 新增：sing-box 版本获取备用方案（无需 jq）
- 🐛 修复：`jq: command not found` 错误
- 🐛 修复：菜单选项 1 未安装依赖直接下载的问题

### v2.0.0 (2026-01-12)
- ✨ 新增：支持更多 Linux 发行版（Alpine, Arch, openSUSE）
- ✨ 新增：使用符号链接，`vproxy` 命令安装后立即可用
- ✨ 新增：UUID 生成兼容方案
- ✨ 新增：命令行参数支持（--install, --uninstall, --help）
- 🐛 修复：移除 `set -e`，使用自定义错误处理
- 🐛 修复：JSON 配置语法错误（移除注释）
- 🐛 修复：`vproxy: command not found` 问题

### v1.0.0 (2026-01-12)
- 🎉 初始版本发布
- ✨ 支持 Hysteria2, TUIC v5, AnyTLS
- ✨ 自动 TLS 证书申请
- ✨ 命令行管理菜单

## 📜 免责声明 / Disclaimer
本项目仅供学习和技术研究使用。使用者在下载、安装、使用本软件时，即视为已阅读并同意本免责声明。作者不对使用本脚本造成的任何损失负责。

## 📄 许可证 / License
MIT License