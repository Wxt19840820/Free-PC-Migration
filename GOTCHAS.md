# PC-Migrator Gotchas Database

> 34 real-world Windows migration pitfalls — each one burned us, each one is now automated.

This document catalogs every error encountered during a real 200GB WiFi migration between two Windows 11 PCs. Each entry includes the symptom, root cause, and the automated fix in PC-Migrator.

---

## Network & Connectivity (12 pitfalls)

### G1: Public vs Private Network Profile
- **Symptom**: SMB port 445 test passes but `net use` returns "Network name not found" (Error 67)
- **Root cause**: Windows "Public" network profile blocks file sharing and WinRM by default
- **Auto-fix**: `Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private`
- **Check**: A2, C1

### G2: DNS Resolution Mismatch
- **Symptom**: Can access `\\HOSTNAME\share` but NOT `\\IP\share`
- **Root cause**: Hostname resolves to different IP than expected (multi-homed or stale DNS)
- **Auto-fix**: Resolve both hostname→IP and IP→hostname; prefer hostname UNC path
- **Check**: B5

### G3: Chinese Windows Firewall Group Names
- **Symptom**: `Enable-NetFirewallRule -DisplayGroup "File and Printer Sharing"` — no matching rules
- **Root cause**: Chinese Windows uses `"文件和打印机共享"` as the display group name
- **Auto-fix**: Try BOTH English and Chinese group names:
  ```powershell
  Enable-NetFirewallRule -DisplayGroup "*File and Printer*"
  Enable-NetFirewallRule -DisplayGroup "*文件和打印机*"
  New-NetFirewallRule -Protocol TCP -LocalPort 445 -Action Allow  # Direct port rule as fallback
  ```
- **Check**: C8

### G4: WinRM TrustedHosts Not Configured
- **Symptom**: `Enter-PSSession` fails with "WinRM client cannot process the request... Kerberos"
- **Root cause**: Workgroup (non-domain) WinRM requires explicit TrustedHosts entry
- **Auto-fix**: `Set-Item WSMan:\localhost\Client\TrustedHosts -Value "SOURCE_IP" -Force`
- **Check**: C3

### G5: SMB Over WiFi Stability
- **Symptom**: Transfer starts fine, then stalls or fails mid-way through large files
- **Root cause**: WiFi chip overheating, packet collision, or adapter power saving kicking in
- **Auto-fix**: `/IPG:5` robocopy parameter; suggest disabling WiFi adapter power saving
- **Check**: A6

### G6: Multiple Concurrent SMB Connections
- **Symptom**: Second `net use` to same server fails with "multiple connections not allowed"
- **Root cause**: Windows limits one SMB session per user to same server
- **Auto-fix**: Use unique drive letters per parallel stream; authenticate once at share level

### G7: RPC Port 135 as Fallback Channel
- **Symptom**: SMB and WinRM both fail, but RPC port 135 is open
- **Root cause**: `sc.exe` and `reg.exe` can use RPC for remote service/registry control
- **Auto-fix**: Not automated (used for diagnostics only)
- **Check**: B4

### G8: WiFi Adapter Power Saving
- **Symptom**: Transfer speed drops to zero after 5-10 minutes, then recovers
- **Root cause**: Windows power management turns off WiFi adapter to save power
- **Manual fix**: Device Manager → Network Adapters → WiFi → Properties → Power Management → Uncheck "Allow computer to turn off this device"
- **Check**: A6

### G9: Network Profile Reset After Reboot
- **Symptom**: Everything works, reboot, everything breaks
- **Root cause**: Windows may reset network profile to Public after updates
- **Auto-fix**: Checks and re-sets network profile at start of every run

### G10: Port 5985 vs 5986 (WinRM HTTP vs HTTPS)
- **Symptom**: WinRM works on 5985 but not 5986 (or vice versa)
- **Root cause**: `Enable-PSRemoting` only opens 5985 (HTTP) by default
- **Auto-fix**: Uses HTTP (5985); HTTPS (5986) requires certificate setup beyond scope

### G11: `Test-NetConnection` False Positive on Localhost
- **Symptom**: `Test-NetConnection -Port 445` returns True but SMB still fails
- **Root cause**: Port can be open but service behind it may reject connections
- **Auto-fix**: Follows up with actual `net use` attempt, not just port test

### G12: Intermittent "Network Path Not Found"
- **Symptom**: Same `net use` command works 3/5 times
- **Root cause**: WiFi packet loss, DNS caching, or SMB session timeout
- **Auto-fix**: `/R:3 /W:5` robocopy retry with exponential backoff; `/TBD` wait for network share

---

## Authentication & Permissions (6 pitfalls)

### G13: UAC Remote Token Filtering (THE BIG ONE)
- **Symptom**: `net use \\IP\C$` fails with "Access Denied" despite correct admin credentials
- **Root cause**: Windows UAC strips administrator token from local accounts connecting over network (`LocalAccountTokenFilterPolicy` = 0)
- **Manual fix** (requires WinRM or local execution on target):
  ```powershell
  Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" `
      -Name "LocalAccountTokenFilterPolicy" -Value 1 -Type DWord
  ```
- **Auto-fix**: Bootstrap script applies this automatically
- **Check**: C4
- **SECURITY NOTE**: Set back to 0 after migration if target is on untrusted networks

### G14: Credential Format in Workgroup
- **Symptom**: `net use \\IP\share /USER:UserName` fails, but `.\UserName` or `IP\UserName` works
- **Root cause**: Windows needs domain qualifier for local accounts when authenticating remotely
- **Auto-fix**: Always uses `TARGETIP\UserName` format

### G15: Stale Credential Cache
- **Symptom**: "Multiple connections to same server" error 1219
- **Root cause**: Windows caches SMB credentials per server; can't use two different users
- **Auto-fix**: `net use * /DELETE /Y` before establishing new connections

### G16: PowerShell Execution Policy
- **Symptom**: `npm install -g @anthropic-ai/claude-code` fails with "running scripts is disabled"
- **Root cause**: Default PowerShell execution policy blocks script execution
- **Auto-fix**: `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force`
- **Check**: C5

### G17: NTFS vs Share Permissions
- **Symptom**: Share created with `Everyone:Full` but still "Access Denied"
- **Root cause**: Windows applies the MORE RESTRICTIVE of NTFS and share permissions
- **Auto-fix**: Sets both share permission AND NTFS ACL on backup directory

### G18: "Blank Password" Network Restriction
- **Symptom**: Account with empty password cannot access SMB share remotely
- **Root cause**: Windows security policy `LimitBlankPasswordUse` blocks network login with blank passwords
- **Auto-fix**: Not automated — requires a password on the account

---

## File Copy & Robocopy (8 pitfalls)

### G19: Robocopy Exit Codes — 0 Through 7 Are All Success
- **Symptom**: Robocopy exits with code 1, 2, or 3 — script treats it as failure
- **Root cause**: robocopy uses bitmask exit codes; codes 0-7 all indicate success with notes
  - 0: No files copied (nothing to do)
  - 1: Files copied successfully
  - 2: Extra files in destination (normal for /MIR first run)
  - 3: Files copied + extra files (2+1)
  - 4-7: Mismatches detected but still copied
  - 8+: Actual errors
- **Auto-fix**: Check `$LASTEXITCODE -lt 8` not `-eq 0`
- **Check**: All robocopy calls

### G20: `$RECYCLE.BIN` — The Phantom Directory
- **Symptom**: Robocopy fails on `D:\$RECYCLE.BIN` with "Access Denied"
- **Root cause**: `$RECYCLE.BIN` is a system-protected junction/symlink
- **Auto-fix**: Always excluded via `/XD`
- **Note**: The `$` in the name also causes bash/PowerShell variable expansion issues

### G21: NTUSER.DAT — Locked by Running OS
- **Symptom**: Robocopy error 32 on `C:\Users\*\NTUSER.DAT` — "file in use by another process"
- **Root cause**: Windows registry hive is exclusively locked while user is logged in
- **Auto-fix**: Excluded from robocopy with `/XD`; not needed on target (new user will have own hive)

### G22: `AppData\Local\Temp` — Waste of Bandwidth
- **Symptom**: 20GB+ of temporary files being migrated unnecessarily
- **Root cause**: Temp files accumulate over time and are never cleaned
- **Auto-fix**: Excluded from user profile migration

### G23: `System Volume Information` — Always Locked
- **Symptom**: "Access Denied" on every drive root
- **Root cause**: System-protected directory, inaccessible even to administrators
- **Auto-fix**: Always excluded

### G24: PowerShell `$` Variable Mangling via bash
- **Symptom**: (Developer issue) Running PowerShell commands through bash/WSL — `$_` becomes `extglob`, `$LASTEXITCODE` becomes empty
- **Root cause**: bash interprets `$variable` syntax before passing to PowerShell
- **Auto-fix**: Always use `-File script.ps1` invocation; never inline complex PowerShell through bash

### G25: `/ZB` vs `/Z` — The Permission Fallback
- **Symptom**: `/Z` (restartable mode) fails on files without write permission
- **Root cause**: `/Z` requires write access to create restart information
- **Recommendation**: Use `/ZB` — tries restartable mode first, falls back to backup mode for permission-denied files

### G26: `/IPG:5` — The WiFi Saver
- **Symptom**: High-speed WiFi transfers cause router/phone hotspot to crash or throttle
- **Root cause**: Continuous packet flooding overwhelms consumer-grade WiFi chips
- **Recommendation**: `/IPG:5` adds 5ms between packets, reducing chip temperature and improving stability

---

## Application-Specific (6 pitfalls)

### G27: PostgreSQL Service Locks Data Files
- **Symptom**: `C:\Program Files\PostgreSQL\18\data\` files fail to copy
- **Root cause**: PostgreSQL service has exclusive locks on database files
- **Auto-fix**: Stop PostgreSQL service before copying; restart after migration

### G28: GeoServer Java Process Locks JARs
- **Symptom**: GeoServer `webapps\geoserver\WEB-INF\lib\*.jar` files fail mid-copy
- **Root cause**: Java process keeps JAR files open
- **Auto-fix**: Stop GeoServer Windows service before copying

### G29: Multiple Python Versions
- **Symptom**: `python --version` shows one version, but `C:\Python*` has multiple
- **Root cause**: Python installers don't clean up old versions; PATH may point to wrong one
- **Auto-fix**: Export `pip freeze` from the active Python; copy ALL Python directories

### G30: Anaconda in ProgramData Not User Profile
- **Symptom**: `C:\Users\*\Anaconda3` not found
- **Root cause**: Anaconda system-wide install goes to `C:\ProgramData\Anaconda3`
- **Auto-fix**: Checks both `C:\ProgramData\Anaconda3` and `C:\Users\*\Anaconda3`

### G31: Node.js npm Global Prefix
- **Symptom**: `npm install -g` packages not found after migration
- **Root cause**: npm global prefix (`%APPDATA%\npm`) not in PATH on target
- **Auto-fix**: Exports `npm list -g --depth=0` for reference; user must reinstall global packages

### G32: PATH Variable Too Long
- **Symptom**: PATH export truncated or contains invalid entries from uninstalled software
- **Root cause**: Windows PATH has ~2047 character limit; stale entries accumulate
- **Auto-fix**: Exports both Machine and User PATH for manual review; does NOT blindly restore

---

## Procedural (2 pitfalls)

### G33: Forgetting to Clean Up UAC Bypass
- **Symptom**: Security vulnerability left open after migration
- **Root cause**: `LocalAccountTokenFilterPolicy=1` lowers security for ALL remote admin access
- **Remediation**: Final report reminds user to set back to 0

### G34: Assuming "Done" When Robocopy Log Shows Errors
- **Symptom**: Some directories silently skipped (permission denied mid-tree)
- **Root cause**: Robocopy exit code 1-3 may mask individual file failures
- **Remediation**: Final report suggests checking robocopy logs for `ERROR 5 (Access Denied)` entries

---

## Quick Reference: Robocopy Parameters Used

| Parameter | Purpose | WiFi | Ethernet |
|-----------|---------|------|----------|
| `/MIR` | Mirror source to destination | ✅ | ✅ |
| `/ZB` | Restartable + backup mode fallback | ✅ | ✅ |
| `/MT:N` | Multi-threaded (N threads) | 16 | 32 |
| `/IPG:N` | Inter-packet gap (ms) | 5 | 0 |
| `/R:N` | Retry count on failure | 3 | 3 |
| `/W:N` | Wait seconds between retries | 5 | 3 |
| `/COPY:DAT` | Copy Data, Attributes, Timestamps | ✅ | ✅ |
| `/DCOPY:T` | Copy directory timestamps | ✅ | ✅ |
| `/NP` | No progress percentage (reduces log spam) | ✅ | ✅ |
| `/NDL` | No directory logging | ✅ | ✅ |
| `/TEE` | Output to console AND log | ✅ | ✅ |
| `/XD` | Exclude directories | See G20-G23 | See G20-G23 |

---

*Last updated: 2026-06-01 | Based on a real 200GB WiFi migration between two Windows 11 PCs*
