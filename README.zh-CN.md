# PC-Migrator v1.0 [中文]

> **一个管理员密码。一条命令。搞定 PC 全量迁移。**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform: Windows](https://img.shields.io/badge/平台-Windows%2010%2F11-blue)]()

**PC-Migrator** 是一个经过实战检验的 PowerShell 工具，能在局域网内**自动化完成整个 Windows PC 迁移**。诞生于一次真实的 200GB WiFi 迁移任务——所有踩过的坑都被记录并自动化。

给它目标机器的管理员账号密码，它帮你搞定：

- 🔧 网络自动打通（SMB + WinRM + 防火墙 + UAC 绕过）
- 📦 全盘数据迁移（多线程 robocopy + WiFi 优化参数）
- 🛠️ 开发软件迁移（Python/PostgreSQL/GeoServer/QGIS/Anaconda/Git）
- 🤖 Claude Code 全量同步（skills、agents、settings、API 环境变量）
- ✅ **34 项自动化预检**——自动发现并修复已知 Windows 坑点

---

## 快速开始

```powershell
# 在源机器上，以管理员身份打开 PowerShell：
.\PC-Migrator.ps1 -TargetComputer "10.99.72.6" -TargetUser ".\Admin" -TargetPass "你的密码"
```

就这么简单。脚本会自动：
1. 对两台机器运行 34 项健康检查
2. 自动修复目标机的网络/防火墙/UAC 问题
3. 迁移所有盘符、软件和配置

## 参数说明

| 参数 | 必填 | 默认值 | 说明 |
|-----------|----------|---------|-------------|
| `-TargetComputer` | ✅ 是 | — | 目标机主机名或 IP |
| `-TargetUser` | ✅ 是 | — | 目标机管理员（如 `.\Admin` 或 `COMPUTER\Admin`） |
| `-TargetPass` | ✅ 是 | — | 目标机管理员密码 |
| `-SourceDrives` | 否 | `"D","E"` | 要迁移的盘符列表 |
| `-BackupDir` | 否 | `C:\backup` | 目标机备份目录 |
| `-RoboThreads` | 否 | `16` | 每路 robocopy 线程数（4–64） |
| `-SkipSoftware` | 否 | `false` | 跳过软件迁移 |
| `-DryRun` | 否 | `false` | 仅运行健康检查不下发数据 |

## 迁移内容

| 类别 | 内容 | 方式 |
|----------|-------|--------|
| **盘符数据** | D:\、E:\（可自定义） | robocopy /MIR /ZB /MT:16 /IPG:5 |
| **用户配置** | 文档、桌面、AppData（排除临时/缓存） | robocopy 智能排除 |
| **Claude Code** | Skills、agents、settings、API 环境变量 | 直接复制 + 环境变量注入 |
| **Python** | pip 包、多版本 Python | pip freeze 导出 + 目录复制 |
| **PostgreSQL** | 完整数据目录 + postgresql.conf | 服务感知复制（自动暂停） |
| **GeoServer** | 完整安装 + webapps + 数据 | 服务感知复制 |
| **QGIS** | 完整安装目录 | 目录复制 |
| **Anaconda** | 完整 conda 环境 + 包 | 目录复制 |
| **Git** | 全局配置 + 安装 | 配置导出 + 目录复制 |
| **PATH** | 系统 + 用户 PATH 变量 | 文本导出 |
| **npm** | 全局包列表 | npm list 导出 |

## 34 项自动化健康检查

预检模块能自动发现并修复以下已知坑点：

### A. 源机器检查
| # | 检查项 | 自动修复 |
|---|-------|----------|
| A1 | 是否以管理员运行 | ❌ 需手动 |
| A2 | 网络配置文件为"专用" | ✅ 自动改为 Private |
| A3 | SMB Server 服务运行中 | ✅ 自动启动 |
| A4 | 源盘符存在 | ❌ 报告缺失 |
| A5 | PowerShell ≥ 5.1 | ❌ 报告版本 |
| A6 | WiFi 网卡节能已关闭 | ⚠️ 手动指引 |

### B. 网络连通性
| # | 检查项 | 自动修复 |
|---|-------|----------|
| B1 | Ping 到目标机 | ❌ 报告失败 |
| B2 | SMB 端口 445 已开启 | ✅ 添加防火墙规则 |
| B3 | WinRM 端口 5985 已开启 | ✅ 添加防火墙规则 |
| B4 | RPC 端口 135（备用通道） | ⚠️ 仅信息 |
| B5 | DNS 解析一致 | ✅ 使用主机名回退 |

### C. 目标机远程检查
| # | 检查项 | 自动修复 |
|---|-------|----------|
| C1 | 目标机网络为"专用" | ✅ 自动修改 |
| C2 | 目标机 SMB 服务运行 | ✅ 自动启动 |
| C3 | 目标机 WinRM 已启用 | ✅ Enable-PSRemoting |
| C4 | UAC 远程限制已绕过 | ✅ 注册表修复 |
| C5 | ExecutionPolicy RemoteSigned | ✅ 自动设置 |
| C6 | 目标机磁盘空间充足 | ❌ 报告警告 |
| C7 | backup 共享已创建 | ✅ 自动创建 |
| C8 | SMB 防火墙规则（中英文） | ✅ 双语修复 |
| C9 | WinRM 防火墙规则 | ✅ 自动创建 |
| C10 | Node.js 已安装 | ⚠️ 仅信息 |
| C11 | Claude Code 已安装 | ⚠️ 仅信息 |

## WiFi 优化传输参数

本工具针对无线网络做了专项优化：

- `/MT:16`（非 128——无线环境下最优）
- `/ZB`（断点续传 + 权限问题自动降级）
- `/IPG:5`（包间隔降低 WiFi 芯片压力）
- `/MIR` 配合 `/R:3 /W:5`（可靠重试）

## 踩坑数据库

本工具中的每个修复都来自真实失败场景：

- **中文 Windows 防火墙组名**与英文不匹配 → 脚本会同时尝试 `"File and Printer Sharing"` 和 `"文件和打印机共享"`
- **UAC 远程剥夺管理员令牌** → 自动设置 `LocalAccountTokenFilterPolicy=1`
- **`$RECYCLE.BIN` 复制失败** → robocopy 始终排除
- **NTUSER.DAT 被系统锁定** → 自动跳过并重试
- **PowerShell `$` 变量被 bash 吃掉** → 脚本使用 `-File` 调用和内部参数
- **robocopy 退出码 0-7 均表示成功** → 脚本检查 `< 8`，而非 `-eq 0`

详见 [GOTCHAS.md](GOTCHAS.md)。

## 故障排除

| 症状 | 修复方案 |
|---------|-----|
| `Test-NetConnection -Port 445` 失败 | 目标机防火墙阻止 SMB。在目标机上运行 bootstrap 脚本 |
| `\\IP\C$` 提示"拒绝访问" | 在目标机上运行 `Set-ItemProperty HKLM:\...\System LocalAccountTokenFilterPolicy 1` |
| WinRM 报 "TrustedHosts" 错误 | 运行 `Set-Item WSMan:\localhost\Client\TrustedHosts -Value "源IP"` |
| 脚本提示"未数字签名" | `Set-ExecutionPolicy RemoteSigned -Force` |
| npm 报 "running scripts is disabled" | `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser` |
| 中文系统：SMB 能通但共享无权限 | 防火墙组名不匹配。Bootstrap 已处理中英双语 |
| WiFi 传输中途卡死 | `/IPG:5` 可缓解。关闭网卡节能 |

## 安全提醒

迁移完成后，**在目标机上**：

```powershell
# 如果目标机处于不安全的网络环境，建议恢复 UAC 远程限制
Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
    -Name "LocalAccountTokenFilterPolicy" -Value 0 -Type DWord
```

## 隐私声明

本工具**完全在局域网内运行**。不会将任何数据发送到外部服务。脚本是自包含的——运行前请自行审查。

仓库中所有示例均使用**占位凭据**（`YourPassword`、`Admin`、`10.99.72.6`）。切勿提交真实密码。

## 许可协议

MIT © 2026

---

[English README](README.md) | [踩坑大全 (Gotchas Database)](GOTCHAS.md)
