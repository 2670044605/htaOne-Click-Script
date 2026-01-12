# htaOne-Click-Script

## 简介 / Introduction
这是一个基于 [sing-box](https://github.com/SagerNet/sing-box) 的终极一键搭建脚本，支持 **Hysteria2 (hy2)**、**TUIC v5** 和 **AnyTLS** 协议。
本脚本灵感来源于 `mack-a/v2ray-agent`，旨在提供一个简单、高效且功能强大的代理搭建解决方案。

**当前版本**: v1.0.0 (2026-01-12)

## 特性 / Features
- **多协议支持**: 一键部署 Hysteria2, TUIC v5, AnyTLS。
- **自动管理**: 包含自动证书申请与续期 (acme.sh)、自动安装 sing-box 核心。
- **管理面板**: 提供类似 `vasma` 的命令行管理菜单 (`vproxy`)。
- **安全性**: 自动配置防火墙规则，支持 Fail2ban。
- **分流规则**: 内置基础分流规则（如屏蔽 BT，Warp 分流等）。
- **备份与恢复**: 支持配置文件的备份与恢复。

## 系统要求 / Requirements
- **操作系统**: Ubuntu 20.04+, Debian 10+, CentOS 8+
- **架构**: x86_64 (amd64) 或 aarch64 (arm64)
- **权限**: root 用户

## 快速安装 / Quick Install

你可以使用以下命令直接下载并运行脚本：

```bash
wget -N --no-check-certificate https://raw.githubusercontent.com/2670044605/htaOne-Click-Script/main/install.sh && chmod +x install.sh && ./install.sh
```

或者手动步骤：

1.  下载脚本：
    ```bash
    wget https://raw.githubusercontent.com/2670044605/htaOne-Click-Script/main/install.sh
    ```
2.  添加执行权限：
    ```bash
    chmod +x install.sh
    ```
3.  运行安装：
    ```bash
    ./install.sh
    ```

## 使用说明 / Usage

安装完成后，你可以随时在终端输入以下命令调出管理菜单：

```bash
vproxy
```

### 菜单功能：
1.  **安装/更新 sing-box**: 更新核心组件。
2.  **申请/续订 TLS 证书**: 管理 SSL 证书。
3.  **添加 hy2/tuic/anytls 节点**: 快速添加新协议配置。
4.  **查看订阅链接**: 获取客户端连接信息。
5.  **更新脚本和核心**: 保持脚本最新。
6.  **备份/恢复配置**: 数据安全。
7.  **健康检查和日志**: 故障排查。
8.  **卸载**: 清除所有相关文件和服务。

## 注意事项 / Notes
- 请确保你的服务器已开放相应的端口（80/443 以及随机生成的 UDP 端口）。
- 首次安装时需要提供域名和邮箱用于申请证书。
- 建议在干净的系统环境下安装。
- 本脚本仅供学习交流使用，请勿用于非法用途。

## 免责声明 / Disclaimer
本项目仅供学习和技术研究使用。使用者在下载、安装、使用本软件时，即视为已阅读并同意本免责声明。作者不对使用本脚本造成的任何损失负责。