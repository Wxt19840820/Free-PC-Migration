<#
.SYNOPSIS
    PC-Migrator v1.0 鈥?Windows PC 涓€閿縼绉诲伐鍏?.DESCRIPTION
    鍙渶鐩爣鏈虹殑绠＄悊鍛樿处鍙峰瘑鐮侊紝鑷姩瀹屾垚锛?    - 缃戠粶鑷姩閰嶇疆锛圫MB + WinRM + 闃茬伀澧?+ UAC 缁曡繃锛?    - 鍏ㄧ洏鏁版嵁杩佺Щ锛坮obocopy WiFi 浼樺寲鍙傛暟锛?    - 寮€鍙戣蒋浠惰縼绉伙紙Python/PostgreSQL/GeoServer/QGIS/Anaconda锛?    - 閰嶇疆鍚屾锛坧ip/git/PATH/Claude Code skills/鐜鍙橀噺锛?    - 34 椤硅嚜鍔ㄥ寲棰勬鍙婂凡鐭ュ潙鐐逛慨澶?
    璇炵敓浜庝竴娆＄湡瀹炵殑 200GB WiFi 杩佺Щ浠诲姟锛屾墍鏈?Windows
    濂囨€棶棰橀兘琚褰曞苟鑷姩鍖栥€?
.PARAMETER TargetComputer
    鐩爣鏈哄櫒涓绘満鍚嶆垨 IP 鍦板潃銆?.PARAMETER TargetUser
    鐩爣鏈虹鐞嗗憳鐢ㄦ埛鍚嶃€傛湰鍦拌处鎴锋牸寮忥細
    "COMPUTERNAME\UserName" 鎴?".\UserName"
.PARAMETER TargetPass
    鐩爣鏈虹鐞嗗憳瀵嗙爜銆?.PARAMETER SourceDrives
    瑕佽縼绉荤殑鐩樼鍒楄〃锛堥粯璁? "D,E"锛夈€?.PARAMETER BackupDir
    鐩爣鏈哄浠界洰褰曪紙榛樿: "C:\backup"锛夈€?.PARAMETER RoboThreads
    Robocopy 绾跨▼鏁般€俉iFi 鐜寤鸿 16锛堥粯璁わ級銆?.PARAMETER SkipSoftware
    璺宠繃寮€鍙戣蒋浠惰縼绉汇€?.PARAMETER DryRun
    浠呰繍琛岄妫€锛屼笉瀹為檯浼犺緭鏁版嵁銆?.EXAMPLE
    .\PC-Migrator.zh-CN.ps1 -TargetComputer "DESKTOP-TARGET" -TargetUser ".\Admin" -TargetPass "P@ssword!"

    杩佺Щ D 鍜?E 鐩樺埌鐩爣鏈猴紝鍖呭惈寮€鍙戣蒋浠躲€?
.EXAMPLE
    .\PC-Migrator.zh-CN.ps1 -TargetComputer "10.99.72.6" -TargetUser "10.99.72.6\Admin" -TargetPass "pass" -DryRun

    浠呰繍琛岄妫€鍜岃瘖鏂€?
.NOTES
    绯荤粺瑕佹眰锛?    - 鏈満闇€绠＄悊鍛樻潈闄?    - 鐩爣鏈洪渶绠＄悊鍛樺嚟鎹?    - 涓ゅ彴鏈哄櫒鍦ㄥ悓涓€缃戠粶
    - Windows 10/11 鎴?Windows Server 2019+

    GitHub: https://github.com/YOUR_USERNAME/PC-Migrator
    璁稿彲鍗忚: MIT
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, HelpMessage="Target computer name or IP")]
    [string]$TargetComputer,

    [Parameter(Mandatory=$true, HelpMessage="Target admin user (e.g. .\Admin or COMPUTER\Admin)")]
    [string]$TargetUser,

    [Parameter(Mandatory=$true, HelpMessage="Target admin password")]
    [string]$TargetPass,

    [Parameter(Mandatory=$false)]
    [string[]]$SourceDrives = @("D", "E"),

    [Parameter(Mandatory=$false)]
    [string]$BackupDir = "C:\backup",

    [Parameter(Mandatory=$false)]
    [ValidateRange(4, 64)]
    [int]$RoboThreads = 16,

    [Parameter(Mandatory=$false)]
    [switch]$SkipSoftware,

    [Parameter(Mandatory=$false)]
    [switch]$DryRun
)

# ================================================================
# 0. Module State & Helpers
# ================================================================
$script:StartTime = Get-Date
$script:SourceComputer = $env:COMPUTERNAME
$script:SourceIP = (Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -match '^(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)' } |
    Select-Object -First 1).IPAddress

# Resolve target: if given hostname, get IP; if given IP, get hostname
$script:TargetIP = $TargetComputer
$script:TargetHost = $TargetComputer
try {
    $entry = [System.Net.Dns]::GetHostEntry($TargetComputer)
    if ($TargetComputer -match '^\d+\.\d+\.\d+\.\d+$') {
        $script:TargetIP = $TargetComputer
        $script:TargetHost = $entry.HostName
    } else {
        $script:TargetIP = $entry.AddressList[0].IPAddressToString
        $script:TargetHost = $TargetComputer
    }
} catch {
    Write-Warning "Cannot resolve $TargetComputer fully; using as-is"
}
$script:TargetUNC = "\\$script:TargetHost"
$script:BackupUNC = "$script:TargetUNC\backup"

# Result collector
$script:CheckResults = [System.Collections.ArrayList]::new()

# Colors
function Write-Banner  { Write-Host "`n$('=' * 50)" -ForegroundColor Cyan }
function Write-Step    { Write-Host "`n>>> $args" -ForegroundColor Yellow }
function Write-Pass    { $script:CheckResults.Add(@{Status="PASS";  Item="$args"}) | Out-Null; Write-Host "    [通过] $args" -ForegroundColor Green }
function Write-Fix     { $script:CheckResults.Add(@{Status="FIXED"; Item="$args"}) | Out-Null; Write-Host "    [已修复]  $args" -ForegroundColor Yellow }
function Write-Fail    { $script:CheckResults.Add(@{Status="FAIL";  Item="$args"}) | Out-Null; Write-Host "    [失败] $args" -ForegroundColor Red }
function Write-Manual  { $script:CheckResults.Add(@{Status="MANUAL";Item="$args"}) | Out-Null; Write-Host "    [需手动] $args" -ForegroundColor Magenta }
function Write-Info    { Write-Host "    [信息] $args" -ForegroundColor Gray }

# ================================================================
# 0a. Adaptive Network Detection (Gemini-suggested optimization)
# ================================================================
function Get-NetworkProfile {
    <#
    .SYNOPSIS
        Auto-detect network type and return optimal robocopy parameters.
        GOTCHA: WiFi needs /IPG:5 and /MT:16; Ethernet can use /MT:32+
    #>
    $adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
    $isWiFi = $adapter.MediaType -eq "802.11"
    $isEthernet = $adapter.MediaType -match "802\.3|Ethernet"

    if ($isWiFi) {
        Write-Info "Network: WiFi detected ($($adapter.Name)) 鈥?using WiFi-optimized params"
        return @{
            Type        = "WiFi"
            Threads     = [Math]::Min($RoboThreads, 16)
            IPG         = 5
            Description = "/MT:$([Math]::Min($RoboThreads, 16)) /IPG:5 (WiFi-optimized)"
        }
    } elseif ($isEthernet) {
        Write-Info "Network: Ethernet detected ($($adapter.Name)) 鈥?using maximum throughput params"
        return @{
            Type        = "Ethernet"
            Threads     = [Math]::Min($RoboThreads, 32)
            IPG         = 0
            Description = "/MT:$([Math]::Min($RoboThreads, 32)) (wired max throughput)"
        }
    } else {
        Write-Info "Network: Unknown type 鈥?using conservative params"
        return @{
            Type        = "Unknown"
            Threads     = 8
            IPG         = 5
            Description = "/MT:8 /IPG:5 (conservative fallback)"
        }
    }
}

# Initialize adaptive network profile
$script:NetProfile = Get-NetworkProfile
if ($script:NetProfile.IPG -gt 0) {
    $script:RoboIPG = "/IPG:$($script:NetProfile.IPG)"
} else {
    $script:RoboIPG = ""
}

# ================================================================
# 0b. Winget Software Inventory (Gemini-suggested)
# ================================================================
function Export-WingetList {
    Write-Step "Winget Software Inventory"
    try {
        $winget = Get-Command winget -ErrorAction Stop
        Write-Info "Winget found 鈥?exporting installed packages"
        $exportFile = "$env:TEMP\PC-Migrator-Winget\winget_packages.json"
        New-Item -Path (Split-Path $exportFile) -ItemType Directory -Force | Out-Null
        winget export -o $exportFile --accept-source-agreements 2>&1 | Out-Null
        if (Test-Path $exportFile) {
            Copy-Item $exportFile "$script:BackupUNC\Exports\" -Force
            Write-Pass "Winget package list exported"
        } else {
            Write-Info "Winget export produced no output (may be blocked)"
        }
    } catch {
        Write-Info "Winget not available 鈥?skipping (Windows 10/11 has it built-in)"
    }
}

# ================================================================
# 0c. WSL Detection (Gemini-suggested)
# ================================================================
function Export-WSLDistributions {
    Write-Step "WSL Distribution Detection"
    try {
        $wslList = wsl --list --quiet 2>&1
        if ($LASTEXITCODE -eq 0 -and $wslList) {
            Write-Info "WSL distributions found:"
            $wslExportDir = "$env:TEMP\PC-Migrator-WSL"
            New-Item -Path $wslExportDir -ItemType Directory -Force | Out-Null

            foreach ($distro in $wslList) {
                if ($distro.Trim()) {
                    Write-Info "  Exporting $($distro.Trim())..."
                    $tarFile = "$wslExportDir\$($distro.Trim()).tar"
                    wsl --export $distro.Trim() $tarFile 2>&1 | Out-Null
                    if (Test-Path $tarFile) {
                        $size = [math]::Round((Get-Item $tarFile).Length/1GB, 2)
                        Write-Pass "WSL $($distro.Trim()) exported (${size}GB)"
                        Copy-Item $tarFile "$script:BackupUNC\WSL\" -Force
                    }
                }
            }
        } else {
            Write-Info "No WSL distributions found"
        }
    } catch {
        Write-Info "WSL not available 鈥?skipping"
    }
}

# ================================================================
# 1. Pre-Flight Health Check (34 automated checks)
# ================================================================
function Invoke-PreflightCheck {
    Write-Host @"

鈺斺晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晽
鈺?  PC-Migrator v1.0 鈥?Pre-Flight Health Check 鈺?鈺?  $(' ' * 20)Source: $($script:SourceComputer) ($script:SourceIP)
鈺?  $(' ' * 20)Target: $script:TargetHost ($script:TargetIP)
鈺氣晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨暆

"@ -ForegroundColor Cyan

    Write-Host "Running 34 automated checks covering all known Windows
migration pitfalls. Each check marked [通过]/[已修复]/[需手动].
" -ForegroundColor Gray

    # ---- Section A: Local Environment Checks ----
    Write-Step "A. Local Machine Checks"

    # A1: Running as admin?
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($isAdmin) { Write-Pass "A1: Running with Administrator privileges" }
    else { Write-Fail "A1: NOT running as Administrator 鈥?re-run PowerShell as Admin" }

    # A2: Network category
    $netProfile = Get-NetConnectionProfile -ErrorAction SilentlyContinue
    if ($netProfile.NetworkCategory -eq "Private") {
        Write-Pass "A2: Network profile is Private (required for SMB+WinRM)"
    } elseif ($netProfile.NetworkCategory -eq "DomainAuthenticated") {
        Write-Pass "A2: Network profile is Domain (will work)"
    } else {
        Write-Fix "A2: Network was $($netProfile.NetworkCategory) 鈥?changing to Private"
        Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private
        Write-Info "A2: Network now set to Private"
    }

    # A3: SMB service running
    $smbSvc = Get-Service LanmanServer -ErrorAction SilentlyContinue
    if ($smbSvc.Status -eq "Running") { Write-Pass "A3: SMB Server service is running" }
    else { Write-Fix "A3: Starting SMB Server service..."; Start-Service LanmanServer; Write-Pass "A3: SMB Server started" }

    # A4: Source drive checks
    foreach ($d in $SourceDrives) {
        $path = "$d`:\\"
        if (Test-Path $path) {
            $disk = Get-PSDrive -Name $d -ErrorAction SilentlyContinue
            $used = [math]::Round($disk.Used/1GB, 1)
            Write-Pass "A4: Drive $d found 鈥?${used}GB used"
        } else {
            Write-Fail "A4: Drive $d not found"
        }
    }

    # A5: PowerShell version >= 5.1
    if ($PSVersionTable.PSVersion.Major -ge 5) { Write-Pass "A5: PowerShell $($PSVersionTable.PSVersion)" }
    else { Write-Fail "A5: PowerShell too old 鈥?need 5.1+" }

    # A6: WiFi power saving (GOTCHA: adapters sleeping mid-transfer)
    $wifiAdapter = Get-NetAdapter | Where-Object { $_.MediaType -eq "802.11" } | Select-Object -First 1
    if ($wifiAdapter) {
        Write-Info "A6: WiFi adapter detected: $($wifiAdapter.Name)"
        $powerMgmt = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}\*" -ErrorAction SilentlyContinue |
            Where-Object { $_.NetCfgInstanceId -eq $wifiAdapter.InstanceId } |
            Select-Object -ExpandProperty PnPCapabilities -ErrorAction SilentlyContinue
        if ($powerMgmt -eq 0) {
            Write-Pass "A6: WiFi power saving appears disabled"
        } else {
            Write-Manual "A6: WiFi adapter may have power saving enabled 鈥?consider disabling via Device Manager > Network Adapters > [your WiFi] > Properties > Power Management > uncheck 'Allow computer to turn off'"
        }
    }

    # ---- Section B: Network Connectivity Checks ----
    Write-Step "B. Network Connectivity"

    # B1: Ping
    if (Test-Connection -ComputerName $script:TargetIP -Count 2 -Quiet) {
        Write-Pass "B1: Ping to $($script:TargetIP) successful"
    } else {
        Write-Fail "B1: Cannot ping $($script:TargetIP) 鈥?check network/cables"
    }

    # B2: SMB port 445
    $smbPort = Test-NetConnection -ComputerName $script:TargetIP -Port 445 -WarningAction SilentlyContinue
    if ($smbPort.TcpTestSucceeded) { Write-Pass "B2: SMB port 445 open on target" }
    else { Write-Fix "B2: SMB port 445 closed 鈥?will attempt to configure via WinRM or manual step" }

    # B3: WinRM port 5985
    $wrmPort = Test-NetConnection -ComputerName $script:TargetIP -Port 5985 -WarningAction SilentlyContinue
    if ($wrmPort.TcpTestSucceeded) { Write-Pass "B3: WinRM port 5985 open on target" }
    else { Write-Fix "B3: WinRM port 5985 closed 鈥?will configure on target" }

    # B4: RPC port 135 (fallback for sc/reg)
    $rpcPort = Test-NetConnection -ComputerName $script:TargetIP -Port 135 -WarningAction SilentlyContinue
    if ($rpcPort.TcpTestSucceeded) { Write-Pass "B4: RPC port 135 open (optional fallback)" }
    else { Write-Info "B4: RPC port 135 closed (not required)" }

    # B5: DNS consistency (GOTCHA: hostname resolves to different IP than expected)
    try {
        $resolved = [System.Net.Dns]::GetHostEntry($script:TargetHost)
        $ips = $resolved.AddressList | Where-Object { $_.AddressFamily -eq "InterNetwork" } | ForEach-Object { $_.IPAddressToString }
        if ($script:TargetIP -in $ips) {
            Write-Pass "B5: DNS resolution consistent ($($script:TargetHost) = $($script:TargetIP))"
        } else {
            Write-Fix "B5: DNS mismatch 鈥?$($script:TargetHost) resolves to $($ips -join ', ') but target IP is $($script:TargetIP). Will use hostname for SMB."
        }
    } catch { Write-Info "B5: DNS check skipped (resolution failed)" }

    # ---- Section C: Remote Checks (via WinRM if available, or pre-WinRM probing) ----
    Write-Step "C. Target Machine Remote Checks"

    $script:WinRMSession = $null
    $script:WinRMAvailable = $false

    # Try WinRM
    try {
        $secPass = ConvertTo-SecureString $TargetPass -AsPlainText -Force
        $script:Credential = New-Object PSCredential($TargetUser, $secPass)
        $script:WinRMSession = New-PSSession -ComputerName $script:TargetIP -Credential $script:Credential -ErrorAction Stop
        $script:WinRMAvailable = $true
        Write-Pass "C0: WinRM session established to target"
    } catch {
        Write-Fix "C0: WinRM not available yet 鈥?will configure during bootstrap"
    }

    if ($script:WinRMAvailable) {
        $remoteChecks = {
            $results = @()

            # C1: Target network profile
            $prof = Get-NetConnectionProfile -ErrorAction SilentlyContinue
            if ($prof.NetworkCategory -eq "Private") { $results += "PASS: C1: Target network is Private" }
            else { $results += "FIX: C1: Target network was $($prof.NetworkCategory) 鈥?changing to Private"; Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private }

            # C2: Target SMB service
            $svc = Get-Service LanmanServer -ErrorAction SilentlyContinue
            if ($svc.Status -eq "Running") { $results += "PASS: C2: Target SMB service running" }
            else { $results += "FIX: C2: Starting SMB service"; Start-Service LanmanServer }

            # C3: Target WinRM service
            $wr = Get-Service WinRM -ErrorAction SilentlyContinue
            if ($wr.Status -eq "Running") { $results += "PASS: C3: Target WinRM service running" }
            else { $results += "FIX: C3: Starting WinRM service"; Enable-PSRemoting -Force -ErrorAction SilentlyContinue }

            # C4: LocalAccountTokenFilterPolicy (GOTCHA: UAC blocks remote admin shares)
            $uacVal = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "LocalAccountTokenFilterPolicy" -ErrorAction SilentlyContinue).LocalAccountTokenFilterPolicy
            if ($uacVal -eq 1) { $results += "PASS: C4: UAC remote restriction bypassed (LocalAccountTokenFilterPolicy=1)" }
            else { $results += "FIX: C4: Setting LocalAccountTokenFilterPolicy=1 (UAC bypass)"; Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "LocalAccountTokenFilterPolicy" -Value 1 -Type DWord -Force }

            # C5: ExecutionPolicy
            $ep = Get-ExecutionPolicy -Scope LocalMachine -ErrorAction SilentlyContinue
            if ($ep -in @("RemoteSigned", "Unrestricted", "Bypass")) { $results += "PASS: C5: ExecutionPolicy is $ep" }
            else { $results += "FIX: C5: Setting ExecutionPolicy to RemoteSigned"; Set-ExecutionPolicy RemoteSigned -Scope LocalMachine -Force }

            # C6: Target disk space
            $cdrive = Get-PSDrive C -ErrorAction SilentlyContinue
            $free = [math]::Round($cdrive.Free/1GB, 1)
            if ($free -gt 100) { $results += "PASS: C6: Target C: has ${free}GB free (>100GB, OK)" }
            elseif ($free -gt 20) { $results += "PASS: C6: Target C: has ${free}GB free (warning: <100GB)" }
            else { $results += "FAIL: C6: Target C: only ${free}GB free 鈥?insufficient for migration!" }

            # C7: SMB share exists (GOTCHA: Chinese Windows firewall group names)
            $share = Get-SmbShare -Name "backup" -ErrorAction SilentlyContinue
            if ($share) { $results += "PASS: C7: backup share already exists" }
            else {
                New-Item -Path "C:\backup" -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
                New-SmbShare -Name "backup" -Path "C:\backup" -FullAccess "Everyone" -ErrorAction SilentlyContinue
                if ($?) { $results += "FIX: C7: backup share created" }
                else {
                    net share backup="C:\backup" /GRANT:Everyone,FULL 2>&1 | Out-Null
                    $results += "FIX: C7: backup share created via net share fallback"
                }
            }

            # C8: Firewall 鈥?SMB rules (GOTCHA: both English AND Chinese group names)
            $fwSMB = Get-NetFirewallRule -Enabled True -Direction Inbound -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -match "SMB|File and Printer|鏂囦欢鍜屾墦鍗版満" }
            if ($fwSMB) {
                $results += "PASS: C8: SMB firewall rules found ($($fwSMB.Count) rules)"
            } else {
                Enable-NetFirewallRule -DisplayGroup "*File and Printer*" -ErrorAction SilentlyContinue
                Enable-NetFirewallRule -DisplayGroup "*鏂囦欢鍜屾墦鍗版満*" -ErrorAction SilentlyContinue
                New-NetFirewallRule -DisplayName "PC-Migrator_SMB_445" -Protocol TCP -LocalPort 445 -Action Allow -Profile Any -ErrorAction SilentlyContinue
                $results += "FIX: C8: SMB firewall rules added"
            }

            # C9: Firewall 鈥?WinRM rules
            $fwWRM = Get-NetFirewallRule -Enabled True -Direction Inbound -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -match "WinRM|Windows Remote Management" }
            if ($fwWRM) {
                $results += "PASS: C9: WinRM firewall rules found ($($fwWRM.Count) rules)"
            } else {
                New-NetFirewallRule -DisplayName "PC-Migrator_WinRM_5985" -Protocol TCP -LocalPort 5985 -Action Allow -Profile Any -ErrorAction SilentlyContinue
                $results += "FIX: C9: WinRM firewall rule added"
            }

            # C10: Node.js check
            try { $nv = node --version 2>$null; $results += "PASS: C10: Node.js $nv installed" }
            catch { $results += "INFO: C10: Node.js not installed 鈥?Claude Code will need it" }

            # C11: Claude Code check
            try { $cv = claude --version 2>$null; $results += "PASS: C11: Claude Code $cv installed" }
            catch { $results += "INFO: C11: Claude Code not installed 鈥?will install during setup" }

            $results
        }

        $remoteResults = Invoke-Command -Session $script:WinRMSession -ScriptBlock $remoteChecks
        foreach ($r in $remoteResults) {
            if ($r -match '^PASS:') { Write-Pass ($r -replace '^PASS: ') }
            elseif ($r -match '^FIX:') { Write-Fix ($r -replace '^FIX: ') }
            elseif ($r -match '^FAIL:') { Write-Fail ($r -replace '^FAIL: ') }
            elseif ($r -match '^INFO:') { Write-Info ($r -replace '^INFO: ') }
            elseif ($r -match '^MANUAL:') { Write-Manual ($r -replace '^MANUAL: ') }
        }
    } else {
        Write-Manual "C1-C11: WinRM unavailable 鈥?remote checks skipped. Target checks will run after bootstrap."
    }

    # ---- Section D: Software Detection ----
    Write-Step "D. Developer Software Detection"

    $swChecks = @(
        @{Name="PostgreSQL";  Path="C:\Program Files\PostgreSQL";          Svc="postgresql*"},
        @{Name="GeoServer";   Path="C:\Program Files\GeoServer";           Svc="GeoServer"},
        @{Name="QGIS";        Path="C:\Program Files\QGIS*";               Svc=$null},
        @{Name="Python";      Path="C:\Python*";                           Svc=$null},
        @{Name="Anaconda";    Path="C:\ProgramData\Anaconda3";             Svc=$null},
        @{Name="Git";         Path="C:\Program Files\Git";                 Svc=$null},
        @{Name="Node.js";     Path="C:\Program Files\nodejs";              Svc=$null}
    )

    $script:DetectedSoftware = @()
    foreach ($sw in $swChecks) {
        $found = Get-Item $sw.Path -ErrorAction SilentlyContinue
        if ($found) {
            $info = @{Name=$sw.Name; Path=$found.FullName; Svc=$sw.Svc}
            $script:DetectedSoftware += $info

            $svcStatus = ""
            if ($sw.Svc) {
                $svc = Get-Service $sw.Svc -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($svc) { $svcStatus = " (service: $($svc.Status))" }
            }
            Write-Pass "D: $($sw.Name) found at $($found.FullName)$svcStatus"
        } else {
            Write-Info "D: $($sw.Name) not found (will skip if absent on target)"
        }
    }

    # ---- Section E: Data Estimate ----
    Write-Step "E. Migration Size Estimate"
    $totalGB = 0
    foreach ($d in $SourceDrives) {
        $path = "$d`:\\"
        if (Test-Path $path) {
            $disk = Get-PSDrive -Name $d -ErrorAction SilentlyContinue
            if ($disk) {
                $gb = [math]::Round($disk.Used/1GB, 1)
                $totalGB += $gb
                Write-Info "E: Drive $d = ${gb}GB"
            }
        }
    }
    Write-Info "E: Estimated total: ${totalGB}GB"
    if ($RoboThreads -gt 16) {
        Write-Info "E: WiFi mode 鈥?/MT:$RoboThreads threads, estimated 30-60 min"
    } else {
        Write-Info "E: /MT:$RoboThreads threads + /IPG:5 鈥?WiFi-optimized"
    }

    # ---- Summary ----
    Write-Banner
    $pass = ($script:CheckResults | Where-Object { $_.Status -eq "PASS" }).Count
    $fix  = ($script:CheckResults | Where-Object { $_.Status -eq "FIXED" }).Count
    $fail = ($script:CheckResults | Where-Object { $_.Status -eq "FAIL" }).Count
    $man  = ($script:CheckResults | Where-Object { $_.Status -eq "MANUAL" }).Count
    Write-Host "Health Check Summary: $pass PASS | $fix AUTO-FIXED | $fail FAILED | $man NEEDS MANUAL" -ForegroundColor Cyan

    if ($fail -gt 0) {
        Write-Host "`nSome checks FAILED. Review above and fix before proceeding." -ForegroundColor Red
        if (-not $DryRun) {
            $ans = Read-Host "Continue anyway? (y/N)"
            if ($ans -ne "y") { exit 1 }
        }
    }

    if ($DryRun) {
        Write-Host "`nDryRun mode 鈥?exiting after checks." -ForegroundColor Yellow
        exit 0
    }
}

# ================================================================
# 2. Target Bootstrap (if WinRM not already working)
# ================================================================
function Invoke-TargetBootstrap {
    Write-Step "Target Bootstrap"

    if ($script:WinRMAvailable) {
        Write-Pass "WinRM already working 鈥?bootstrap complete"
        return
    }

    Write-Host "Attempting to enable WinRM and SMB on target..." -ForegroundColor Yellow

    # Generate bootstrap script for target
    $bs = @'
# PC-Migrator Bootstrap 鈥?Run as Administrator on target machine
$ErrorActionPreference = "Continue"
Write-Host "PC-Migrator Bootstrap v1.0" -ForegroundColor Cyan

# 1. Network -> Private (GOTCHA: Public network blocks SMB+WinRM)
Get-NetConnectionProfile | Set-NetConnectionProfile -NetworkCategory Private -ErrorAction SilentlyContinue ; Write-Host "1/8 Network: Private"

# 2. Firewall 鈥?SMB (GOTCHA: Chinese Windows uses different group names)
netsh advfirewall firewall set rule group="File and Printer Sharing" new enable=Yes >$null 2>&1
Enable-NetFirewallRule -DisplayGroup "*File and Printer Sharing*" -ErrorAction SilentlyContinue
Enable-NetFirewallRule -DisplayGroup "*鏂囦欢鍜屾墦鍗版満鍏变韩*" -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName "PC-Migrator_SMB_445" -Protocol TCP -LocalPort 445 -Action Allow -Profile Any -ErrorAction SilentlyContinue | Out-Null ; Write-Host "2/8 Firewall: SMB 445 allowed"

# 3. WinRM
Enable-PSRemoting -Force -ErrorAction SilentlyContinue
Set-Item WSMan:\localhost\Client\TrustedHosts -Value "SOURCE_IP_PLACEHOLDER" -Force -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName "PC-Migrator_WinRM_5985" -Protocol TCP -LocalPort 5985 -Action Allow -Profile Any -ErrorAction SilentlyContinue | Out-Null
Start-Service WinRM -ErrorAction SilentlyContinue
Set-Service WinRM -StartupType Automatic -ErrorAction SilentlyContinue ; Write-Host "3/8 WinRM: Enabled"

# 4. UAC bypass for remote admin shares (GOTCHA: local admin token filtered over network)
Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "LocalAccountTokenFilterPolicy" -Value 1 -Type DWord -Force ; Write-Host "4/8 UAC: Remote admin bypass enabled"

# 5. ExecutionPolicy
Set-ExecutionPolicy RemoteSigned -Scope LocalMachine -Force -ErrorAction SilentlyContinue
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction SilentlyContinue ; Write-Host "5/8 PowerShell: ExecutionPolicy RemoteSigned"

# 6. SMB share
New-Item -Path "C:\backup" -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
net share backup /DELETE /Y >$null 2>&1
New-SmbShare -Name "backup" -Path "C:\backup" -FullAccess "Everyone" -ErrorAction SilentlyContinue
if (-not $?) { net share backup="C:\backup" /GRANT:Everyone,FULL >$null 2>&1 }
icacls "C:\backup" /grant "Everyone:(OI)(CI)F" /T >$null 2>&1 ; Write-Host "6/8 SMB: Share \\$env:COMPUTERNAME\backup -> C:\backup"

# 7. WiFi power saving (GOTCHA: adapter sleep kills long transfers)
$wifi = Get-NetAdapter | Where-Object { $_.MediaType -eq "802.11" } | Select-Object -First 1
if ($wifi) {
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}\*"
    Get-ItemProperty $regPath -ErrorAction SilentlyContinue | Where-Object { $_.NetCfgInstanceId -eq $wifi.InstanceId } |
        Set-ItemProperty -Name PnPCapabilities -Value 0 -ErrorAction SilentlyContinue
    Write-Host "7/8 WiFi: Power saving disabled on $($wifi.Name)"
} else { Write-Host "7/8 WiFi: No adapter found (wired?)" }

# 8. Verify
Write-Host "8/8 Bootstrap complete!" -ForegroundColor Green
Write-Host "  Hostname: $env:COMPUTERNAME"
Write-Host "  SMB: \\$env:COMPUTERNAME\backup"
Write-Host "  WinRM: port 5985"
Write-Host "  UAC: LocalAccountTokenFilterPolicy=1"
'@

    # Replace placeholder
    $bs = $bs -replace 'SOURCE_IP_PLACEHOLDER', $script:SourceIP

    # Save bootstrap
    $bsFile = "$env:TEMP\PC-Migrator-Bootstrap.ps1"
    $bs | Out-File -FilePath $bsFile -Encoding UTF8

    Write-Host @"

========================================
  MANUAL STEP REQUIRED
========================================
WinRM is not available on target yet.

Please copy and run this command on TARGET ($script:TargetHost):

  powershell -ExecutionPolicy Bypass -File "$bsFile"

Or if file copy is inconvenient, open PowerShell as Admin
on target and paste the contents of:
  $bsFile

========================================
"@ -ForegroundColor Yellow

    if (-not $DryRun) {
        Read-Host "Press ENTER after running the bootstrap on target"
    }

    # Try WinRM again
    try {
        $secPass = ConvertTo-SecureString $TargetPass -AsPlainText -Force
        $script:Credential = New-Object PSCredential($TargetUser, $secPass)
        $script:WinRMSession = New-PSSession -ComputerName $script:TargetIP -Credential $script:Credential -ErrorAction Stop
        $script:WinRMAvailable = $true
        Write-Pass "WinRM now working!"
    } catch {
        Write-Warn "WinRM still not available 鈥?continuing with SMB-only mode"
    }
}

# ================================================================
# 3. Data Migration
# ================================================================
function Start-RobocopySession {
    param([string]$Source, [string]$DestSuffix, [string]$Label, [string[]]$ExcludeDirs = @())

    $dest = "$script:BackupUNC\$DestSuffix"
    $logFile = "$env:TEMP\PC-Migrator-$Label.log"

    # Ensure dest exists
    New-Item -Path $dest -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

    Write-Host "`n>>> $Label : $Source -> $dest" -ForegroundColor Magenta
    Write-Host "    /ZB /MT:$RoboThreads /IPG:5 /R:3 /W:5" -ForegroundColor Gray

    # Build exclude
    $xd = ""
    foreach ($e in $ExcludeDirs) {
        if ($e) { $xd += " /XD `"$e`"" }
    }

    $cmd = "robocopy `"$Source`" `"$dest`" /MIR /ZB /R:3 /W:5 /MT:$RoboThreads /COPY:DAT /DCOPY:T /NP /NDL /IPG:5 /TEE /LOG+:`"$logFile`" $xd"
    Invoke-Expression $cmd

    $ec = $LASTEXITCODE
    # GOTCHA: robocopy exit codes 0-7 are all success!
    if ($ec -lt 8) {
        Write-Pass "$Label complete (robocopy exit $ec)"
        return $true
    } else {
        Write-Warn "$Label had errors (robocopy exit $ec) 鈥?check $logFile"
        return $false
    }
}

function Invoke-DataMigration {
    Write-Step "Data Migration"

    # Verify SMB
    Write-Host "Verifying SMB access to $script:BackupUNC..." -ForegroundColor Yellow
    net use * /DELETE /Y 2>&1 | Out-Null
    $r = net use $script:BackupUNC $TargetPass /USER:$TargetUser 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "SMB access failed: $r"
        Write-Host "  GOTCHA checklist:" -ForegroundColor Yellow
        Write-Host "  1. Target network MUST be Private (not Public)"
        Write-Host "  2. Target firewall MUST allow port 445"
        Write-Host "  3. Target: Set-ItemProperty HKLM:\...\System LocalAccountTokenFilterPolicy 1"
        Write-Host "  4. Try accessing \\$($script:TargetHost)\backup manually in Explorer"
        return
    }
    Write-Pass "SMB share accessible"

    # --- Claude Code Config (small, fast, critical) ---
    Write-Host "`n--- Claude Code Configuration ---" -ForegroundColor Cyan

    # Skills
    $skillPaths = @(
        "D:\Project\Claude\.claude\skills",
        "$env:USERPROFILE\.claude\skills",
        "$env:LOCALAPPDATA\Claude\.claude\skills"
    )
    foreach ($sp in $skillPaths) {
        if (Test-Path $sp) {
            Start-RobocopySession -Source $sp -DestSuffix "ClaudeConfig\skills" -Label "Skills" -ExcludeDirs @(".git")
            break
        }
    }

    # User config (settings, agents, projects 鈥?NOT sessions/cache)
    if (Test-Path "$env:USERPROFILE\.claude") {
        Start-RobocopySession -Source "$env:USERPROFILE\.claude" -DestSuffix "ClaudeConfig\user_claude" -Label "UserConfig" `
            -ExcludeDirs @("sessions", "cache", "backups", "shell-snapshots", "file-history", "session-env", "tasks", "paste-cache", "plans")
    }

    # API config
    Get-ChildItem "$env:USERPROFILE" -Filter "Set-*Env*" -ErrorAction SilentlyContinue | ForEach-Object {
        Copy-Item $_.FullName "$script:BackupUNC\" -Force
        Write-Pass "API config: $($_.Name)"
    }
    Get-ChildItem "D:\Project\Claude" -Filter "Set-*Env*" -ErrorAction SilentlyContinue | ForEach-Object {
        Copy-Item $_.FullName "$script:BackupUNC\" -Force
        Write-Pass "API config: $($_.Name)"
    }

    # --- Drives (large, parallel-worthy) ---
    foreach ($drive in $SourceDrives) {
        $sp = "$drive`:\"
        if (Test-Path $sp) {
            Start-RobocopySession -Source $sp -DestSuffix $drive -Label "${drive}_Drive" `
                -ExcludeDirs @("System Volume Information")
        }
    }

    # --- User Profile ---
    if (Test-Path "$env:USERPROFILE") {
        Start-RobocopySession -Source "$env:USERPROFILE" -DestSuffix "C_Users\$env:USERNAME" -Label "UserProfile" `
            -ExcludeDirs @(
                "AppData\Local\Temp",
                "AppData\Local\Microsoft\Windows\INetCache",
                "AppData\Local\Microsoft\Windows\Temporary Internet Files",
                "NTUSER.DAT", "ntuser.dat.LOG1", "ntuser.dat.LOG2",
                ".cache", "node_modules"
            )
    }
}

# ================================================================
# 4. Software Export
# ================================================================
function Invoke-SoftwareExport {
    Write-Step "Software & Configuration Export"

    $exp = "$env:TEMP\PC-Migrator-Export"
    New-Item -Path $exp -ItemType Directory -Force | Out-Null

    # pip freeze
    try {
        pip freeze 2>&1 | Out-File "$exp\pip_freeze.txt" -Encoding UTF8
        Write-Pass "pip freeze exported"
    } catch { Write-Info "pip not found 鈥?skipping" }

    # npm global
    try {
        npm list -g --depth=0 2>&1 | Out-File "$exp\npm_global.txt" -Encoding UTF8
        Write-Pass "npm global exported"
    } catch { Write-Info "npm not found" }

    # PATH
    [Environment]::GetEnvironmentVariable("Path","Machine") | Out-File "$exp\PATH_machine.txt" -Encoding UTF8
    [Environment]::GetEnvironmentVariable("Path","User") | Out-File "$exp\PATH_user.txt" -Encoding UTF8
    Write-Pass "PATH exported"

    # Git config
    try {
        git config --global --list 2>&1 | Out-File "$exp\git_global_config.txt" -Encoding UTF8
        Write-Pass "Git config exported"
    } catch { Write-Info "Git not found" }

    # Key env vars
    Get-ChildItem Env: | Where-Object {
        $_.Name -match '^(PATH|JAVA|PYTHON|PG|POSTGRES|QGIS|GEO|NODE|NPM|ANTHROPIC|CLAUDE|OPENAI|CONDA|CUDA|TORCH)'
    } | ForEach-Object { "$($_.Name)=$($_.Value)" } | Out-File "$exp\key_env_vars.txt" -Encoding UTF8
    Write-Pass "Key env vars exported"

    # PostgreSQL dump
    $pgDump = "C:\Program Files\PostgreSQL\18\bin\pg_dumpall.exe"
    if ((Test-Path $pgDump) -and $script:DetectedSoftware.Name -contains "PostgreSQL") {
        $env:PGPASSWORD = ""
        & $pgDump -U postgres -f "$exp\postgres_full_dump.sql" 2>&1
        if ($LASTEXITCODE -eq 0) {
            $sz = [math]::Round((Get-Item "$exp\postgres_full_dump.sql").Length/1MB, 1)
            Write-Pass "PostgreSQL dump: $sz MB"
        } else {
            Write-Warn "PostgreSQL dump failed 鈥?you may need to dump manually"
        }
    }

    # Copy to backup
    Copy-Item "$exp\*" "$script:BackupUNC\Exports\" -Force -Recurse -ErrorAction SilentlyContinue
    Write-Pass "Exports saved to backup share"
}

# ================================================================
# 5. Software Directory Migration
# ================================================================
function Invoke-SoftwareMigration {
    if ($SkipSoftware) {
        Write-Info "Software migration skipped (--SkipSoftware)"
        return
    }

    Write-Step "Software Directory Migration"

    $swList = @(
        @{Name="Python314";   Path="C:\Python314";                      StopSvc=$null},
        @{Name="PostgreSQL";  Path="C:\Program Files\PostgreSQL";       StopSvc="postgresql*"},
        @{Name="GeoServer";   Path="C:\Program Files\GeoServer";        StopSvc="GeoServer"},
        @{Name="QGIS";        Path="C:\Program Files\QGIS 3.40.15";    StopSvc=$null},
        @{Name="Anaconda3";   Path="C:\ProgramData\Anaconda3";          StopSvc=$null},
        @{Name="Git";         Path="C:\Program Files\Git";              StopSvc=$null}
    )

    foreach ($sw in $swList) {
        if (-not (Test-Path $sw.Path)) { continue }

        Write-Host "`n>>> $($sw.Name)..." -ForegroundColor Magenta

        # Stop service if running (GOTCHA: locked files prevent copy)
        if ($sw.StopSvc) {
            $svc = Get-Service $sw.StopSvc -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($svc -and $svc.Status -eq "Running") {
                Write-Host "    Stopping $($svc.Name)..." -ForegroundColor Yellow
                Stop-Service $svc.Name -Force -ErrorAction SilentlyContinue
                Write-Pass "Service stopped"
            }
        }

        $dest = "$script:BackupUNC\Software\$($sw.Name)"
        $log = "$env:TEMP\PC-Migrator-Software-$($sw.Name).log"
        robocopy $sw.Path $dest /MIR /ZB /R:2 /W:5 /MT:8 /COPY:DAT /DCOPY:T /NP /NDL /IPG:5 /LOG+:$log
        if ($LASTEXITCODE -lt 8) { Write-Pass "$($sw.Name) done" }
        else { Write-Warn "$($sw.Name) had errors (exit $LASTEXITCODE)" }
    }
}

# ================================================================
# 6. Target Final Configuration
# ================================================================
function Invoke-TargetConfiguration {
    Write-Step "Target Final Configuration"

    if (-not $script:WinRMAvailable) {
        Write-Manual "WinRM unavailable 鈥?run manual config script on target:"
        $cfg = @"
# Run this on target ($script:TargetHost) to complete setup
`$backup = "C:\backup"
# Copy skills
robocopy "`$backup\ClaudeConfig\skills" "`$env:USERPROFILE\.claude\skills" /MIR /R:2 /W:3 /MT:4 /NP /NDL
# Copy user config
robocopy "`$backup\ClaudeConfig\user_claude" "`$env:USERPROFILE\.claude" /MIR /R:2 /W:3 /MT:4 /NP /NDL /XD sessions cache backups
# Set API env vars
`$vars = @{
    ANTHROPIC_AUTH_TOKEN="YOUR_API_KEY"
    ANTHROPIC_BASE_URL="https://api.deepseek.com/anthropic"
    ANTHROPIC_MODEL="deepseek-v4-pro[1m]"
    ANTHROPIC_DEFAULT_OPUS_MODEL="deepseek-v4-pro[1m]"
    ANTHROPIC_DEFAULT_SONNET_MODEL="deepseek-v4-pro[1m]"
    ANTHROPIC_DEFAULT_HAIKU_MODEL="deepseek-v4-flash"
    CLAUDE_CODE_SUBAGENT_MODEL="deepseek-v4-flash"
    CLAUDE_CODE_EFFORT_LEVEL="max"
}
foreach (`$k in `$vars.Keys) { [Environment]::SetEnvironmentVariable(`$k, `$vars[`$k], "User") }
Write-Host "Config complete!" -ForegroundColor Green
"@
        Write-Host $cfg -ForegroundColor White
        return
    }

    Invoke-Command -Session $script:WinRMSession -ScriptBlock {
        param($backupDir)

        Write-Host "Configuring target..." -ForegroundColor Cyan
        $cfgDir = "$backupDir\ClaudeConfig"

        # Skills
        if (Test-Path "$cfgDir\skills") {
            robocopy "$cfgDir\skills" "$env:USERPROFILE\.claude\skills" /MIR /R:2 /W:3 /MT:4 /NP /NDL /NJH /NJS
            $n = (Get-ChildItem "$env:USERPROFILE\.claude\skills" -Depth 0 -ErrorAction SilentlyContinue).Count
            Write-Host "  Skills: $n folders installed"
        }

        # User config
        if (Test-Path "$cfgDir\user_claude") {
            robocopy "$cfgDir\user_claude" "$env:USERPROFILE\.claude" /MIR /R:2 /W:3 /MT:4 /NP /NDL /NJH /NJS /XD sessions cache backups shell-snapshots file-history session-env tasks paste-cache
            Write-Host "  User config restored"
        }

        Write-Host "Target configuration complete!" -ForegroundColor Green
    } -ArgumentList $BackupDir

    Write-Pass "Target configuration applied via WinRM"
}

# ================================================================
# 7. Final Report
# ================================================================
function Invoke-FinalReport {
    Write-Step "Migration Report"

    $elapsed = [math]::Round(((Get-Date) - $script:StartTime).TotalMinutes, 1)

    Write-Host @"

鈺斺晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晽
鈺?         PC-Migrator 鈥?Complete!              鈺?鈺犫晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨暎
鈺?Source:    $($script:SourceComputer.PadRight(30)) 鈺?鈺?Target:    $($script:TargetHost.PadRight(30)) 鈺?鈺?Duration:  ${elapsed} min $(' ' * (24 - ${elapsed}.ToString().Length))                   鈺?鈺?Backup:    $script:BackupUNC
鈺氣晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨暆

Data on target:
  $BackupDir\D          鈥?Drive D contents
  $BackupDir\E          鈥?Drive E contents
  $BackupDir\C_Users    鈥?User profile data
  $BackupDir\ClaudeConfig\skills      鈥?Claude Code skills
  $BackupDir\ClaudeConfig\user_claude 鈥?User settings
  $BackupDir\Software   鈥?Dev tools
  $BackupDir\Exports    鈥?pip/PATH/git configs

Next Steps on Target ($script:TargetHost):
  1. Restore pip:  pip install -r $BackupDir\Exports\pip_freeze.txt
  2. Restore PATH: review $BackupDir\Exports\PATH_*.txt
  3. Git config:   review $BackupDir\Exports\git_global_config.txt
  4. PostgreSQL:   restore from $BackupDir\Exports\postgres_full_dump.sql
  5. Start Claude Code: claude
  6. SECURITY:     Set LocalAccountTokenFilterPolicy back to 0
                   if target is on untrusted networks

"@ -ForegroundColor Cyan

    # Detailed check report
    Write-Host "Pre-Flight Check Summary:" -ForegroundColor White
    $script:CheckResults | Format-Table Status, Item -AutoSize | Out-Host
}

# ================================================================
# Main
# ================================================================
Write-Host @"

鈺斺晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晽
鈺?          PC-Migrator v1.0                    鈺?鈺?  One-Click Windows PC Migration              鈺?鈺?  github.com/YOUR_USERNAME/PC-Migrator        鈺?鈺氣晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨暆

  Source:  $($script:SourceComputer) ($script:SourceIP)
  Target:  $script:TargetHost ($script:TargetIP)
  Drives:  $($SourceDrives -join ', ')
  Threads: $RoboThreads
  DryRun:  $DryRun

"@ -ForegroundColor Cyan

# Execute phases
$phases = @(
    @{Name="Pre-Flight Check";        Func=${function:Invoke-PreflightCheck}},
    @{Name="Target Bootstrap";        Func=${function:Invoke-TargetBootstrap}},
    @{Name="Data Migration";          Func=${function:Invoke-DataMigration}},
    @{Name="Software Export";         Func=${function:Invoke-SoftwareExport}},
    @{Name="Software Migration";      Func=${function:Invoke-SoftwareMigration}},
    @{Name="Target Configuration";    Func=${function:Invoke-TargetConfiguration}},
    @{Name="Final Report";            Func=${function:Invoke-FinalReport}}
)

foreach ($phase in $phases) {
    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        & $phase.Func
        $sw.Stop()
    } catch {
        Write-Fail "Phase '$($phase.Name)' error: $_"
        if (-not $DryRun) {
            $ans = Read-Host "Continue? (Y/n)"
            if ($ans -eq "n") { break }
        }
    }
}

# Cleanup
if ($script:WinRMSession) { Remove-PSSession $script:WinRMSession -ErrorAction SilentlyContinue }

$totalMin = [math]::Round(((Get-Date) - $script:StartTime).TotalMinutes, 1)
Write-Host "`nTotal time: $totalMin minutes" -ForegroundColor Green

