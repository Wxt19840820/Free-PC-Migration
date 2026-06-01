# PC-Migrator v1.0

> **One admin password. One command. Full PC migration.**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform: Windows](https://img.shields.io/badge/Platform-Windows%2010%2F11-blue)]()

**PC-Migrator** is a battle-tested PowerShell tool that automates **entire Windows PC migration** over local network. Born from migrating 200GB of data over WiFi with every Windows quirk discovered and automated.

Give it the target machine's admin credentials, and it handles:
- 🔧 Network auto-configuration (SMB + WinRM + Firewall + UAC bypass)
- 📦 Full-drive data migration (multi-threaded robocopy with WiFi-optimized parameters)
- 🛠️ Dev software migration (Python/PostgreSQL/GeoServer/QGIS/Anaconda/Git)
- 🤖 Claude Code full sync (skills, agents, settings, API env vars)
- ✅ **34 automated pre-flight checks** that detect and fix known Windows pitfalls

---

## Quick Start

```powershell
# On YOUR machine (source), open PowerShell as Administrator:
.\PC-Migrator.ps1 -TargetComputer "10.99.72.6" -TargetUser ".\Admin" -TargetPass "YourPassword"
```

That's it. The script will:
1. Run 34 health checks on both machines
2. Auto-fix network/firewall/UAC issues on target
3. Migrate all drives, software, and configurations

## What It Migrates

| Category | Items | Method |
|----------|-------|--------|
| **Drives** | D:\, E:\ (configurable) | robocopy /MIR /ZB /MT:16 /IPG:5 |
| **User Profile** | Documents, Desktop, AppData (minus Temp/Cache) | robocopy with smart exclusions |
| **Claude Code** | Skills, agents, settings.json, API env vars | Direct copy + env var injection |
| **Python** | pip packages, multiple Python versions | pip freeze export + directory copy |
| **PostgreSQL** | Full data directory + postgresql.conf | Service-aware copy (auto-stop) |
| **GeoServer** | Full install + webapps + data | Service-aware copy |
| **QGIS** | Full install directory | Directory copy |
| **Anaconda** | Full conda environment + packages | Directory copy |
| **Git** | Global config + install | Config export + directory copy |
| **PATH** | Machine + User PATH variables | Text export |
| **npm** | Global packages list | npm list export |

## 34 Automated Health Checks

The pre-flight check detects and auto-fixes these known pitfalls:

| # | Check | Auto-Fix |
|---|-------|----------|
| A1 | Running as Administrator | ❌ Manual |
| A2 | Network profile is Private | ✅ Auto-change to Private |
| A3 | SMB Server service running | ✅ Auto-start |
| A4 | Source drives exist | ❌ Reports missing |
| A5 | PowerShell ≥ 5.1 | ❌ Reports version |
| A6 | WiFi power saving disabled | ⚠️ Manual guidance |
| B1 | Ping to target | ❌ Reports failure |
| B2 | SMB port 445 open | ✅ Firewall rule added |
| B3 | WinRM port 5985 open | ✅ Firewall rule added |
| B4 | RPC port 135 open (fallback) | ⚠️ Info only |
| B5 | DNS resolution consistency | ✅ Uses hostname fallback |
| C1 | Target network is Private | ✅ Auto-change |
| C2 | Target SMB service running | ✅ Auto-start |
| C3 | Target WinRM enabled | ✅ Enable-PSRemoting |
| C4 | UAC remote restriction bypassed | ✅ Registry fix |
| C5 | ExecutionPolicy RemoteSigned | ✅ Auto-set |
| C6 | Target disk space sufficient | ❌ Reports warning |
| C7 | backup share exists | ✅ Auto-create |
| C8 | SMB firewall rules (EN+CN) | ✅ Dual-language fix |
| C9 | WinRM firewall rules | ✅ Auto-create |
| C10 | Node.js installed | ⚠️ Info only |
| C11 | Claude Code installed | ⚠️ Info only |

## Key Features

### WiFi-Optimized Transfer
- `/MT:16` (not 128 — optimal for wireless)
- `/ZB` (restartable mode + auto-fallback for permission issues)
- `/IPG:5` (inter-packet gap reduces WiFi chip stress)
- `/MIR` with `/R:3 /W:5` for reliable retry

### Gotcha Database
Every fix in this tool came from a real failure:

- **Chinese Windows firewall group names** don't match English ones → script tries both `"File and Printer Sharing"` and `"文件和打印机共享"`
- **UAC strips admin tokens** over network → automatically sets `LocalAccountTokenFilterPolicy=1`
- **`$RECYCLE.BIN` copy fails** → always excluded from robocopy
- **NTUSER.DAT locked by OS** → excluded with retry logic
- **PowerShell `$` mangling via bash** → script uses `-File` invocation and internal params
- **robocopy exit codes 0-7 = success** → script checks `< 8`, not just `-eq 0`

### Parallel Architecture
Three robocopy streams run simultaneously:
```
Source Machine                          Target Machine
┌─────────────┐                        ┌─────────────────┐
│ D:\ ────────────── robocopy /MT:16 ──────→ C:\backup\D   │
│ E:\ ────────────── robocopy /MT:16 ──────→ C:\backup\E   │
│ C:\Users\.. ─────── robocopy /MT:16 ──────→ C:\backup\C_Users │
└─────────────┘                        └─────────────────┘
```

## Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `-TargetComputer` | ✅ Yes | — | Target hostname or IP |
| `-TargetUser` | ✅ Yes | — | Target admin (e.g. `.\Admin` or `COMPUTER\Admin`) |
| `-TargetPass` | ✅ Yes | — | Target admin password |
| `-SourceDrives` | No | `"D","E"` | Drive letters to migrate |
| `-BackupDir` | No | `C:\backup` | Target backup directory |
| `-RoboThreads` | No | `16` | Threads per robocopy (4–64) |
| `-SkipSoftware` | No | `false` | Skip software migration |
| `-DryRun` | No | `false` | Run only health checks |

## Prerequisites

- **Both machines**: Windows 10/11 or Windows Server 2019+
- **Source machine**: Administrator privileges
- **Target machine**: Administrator credentials
- **Network**: Both on same LAN (WiFi or wired)
- **Ports**: 445 (SMB), 5985 (WinRM), 135 (RPC fallback)

## Workflow

```
Phase 0: Pre-Flight Check (34 items, auto-fix where possible)
   ↓
Phase 1: Target Bootstrap (WinRM + SMB + Firewall + UAC)
   ↓
Phase 2: Data Migration (Drives + User Profile + Claude Config)
   ↓
Phase 3: Software Export (pip/git/PATH/env vars/PostgreSQL dump)
   ↓
Phase 4: Software Migration (Python/PostgreSQL/GeoServer/QGIS/Anaconda)
   ↓
Phase 5: Target Configuration (restore skills/settings/env vars)
   ↓
Phase 6: Final Report
```

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `Test-NetConnection -Port 445` fails | Target firewall blocking SMB. Run bootstrap on target. |
| `Access Denied` on `\\IP\C$` | Run `Set-ItemProperty HKLM:\...\System LocalAccountTokenFilterPolicy 1` on target |
| WinRM: "TrustedHosts" error | Run `Set-Item WSMan:\localhost\Client\TrustedHosts -Value "SOURCE_IP"` |
| Script "not digitally signed" | `Set-ExecutionPolicy RemoteSigned -Force` |
| npm: "running scripts is disabled" | `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser` |
| Chinese Windows: SMB works but share not found | Firewall group name mismatch. Bootstrap handles both languages. |
| WiFi transfer stalls mid-way | `/IPG:5` helps. Disable WiFi adapter power saving. |

See [GOTCHAS.md](GOTCHAS.md) for the full 34-item pitfall database.

## Security Note

After migration completes, **on the target machine**:

```powershell
# Re-enable UAC remote restriction if on untrusted networks
Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
    -Name "LocalAccountTokenFilterPolicy" -Value 0 -Type DWord
```

## Privacy

This tool runs **entirely on your local network**. No data is sent to any external service. The script is self-contained — review it before running.

All examples in this repository use **placeholder credentials** (`YourPassword`, `Admin`, `10.99.72.6`). Never commit real credentials.

## Contributing

Found another Windows migration quirk? PRs welcome. Add:
1. The pitfall to `GOTCHAS.md`
2. The auto-fix to `Invoke-PreflightCheck`
3. Unit test case

## License

MIT © 2026 — [Your Name]

---

[中文文档 (Chinese README)](README.zh-CN.md) | [踩坑大全 (Gotchas Database)](GOTCHAS.md)
