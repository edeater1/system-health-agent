#Requires -Version 5.1
<#
.SYNOPSIS
    System Health Agent — Windows Security Status & Hardening
.DESCRIPTION
    Check security status, apply hardening, or undo changes.
    Acts like a technician: explains everything, asks before acting.
.EXAMPLE
    .\firewall.ps1                Show security status (default)
    .\firewall.ps1 -Status        Show security status
    .\firewall.ps1 -Harden        Apply full security hardening
    .\firewall.ps1 -Undo          Restore from backup
#>

param(
    [switch]$Status,
    [switch]$Harden,
    [switch]$Undo
)

$ErrorActionPreference = "Continue"

. "$PSScriptRoot\config.ps1"

$NC = [Console]::ResetColor
$backupDir = Join-Path $REPORT_DIR "security-backup"

function Good($msg) { Write-Host "  [OK] $msg" -ForegroundColor Green }
function Warn($msg) { Write-Host "  [!!] $msg" -ForegroundColor Yellow }
function Crit($msg) { Write-Host "  [XX] $msg" -ForegroundColor Red }
function Info($msg) { Write-Host "  [->] $msg" -ForegroundColor Cyan }

# ═══════════════════════════════════════════════════════════════
# STATUS
# ═══════════════════════════════════════════════════════════════

function Show-Status {
    Write-Host ""
    Write-Host "════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  SECURITY STATUS — $MACHINE_NAME" -ForegroundColor Cyan
    Write-Host "  $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -ForegroundColor Cyan
    Write-Host "════════════════════════════════════════════════" -ForegroundColor Cyan

    # --- Firewall ---
    Write-Host ""
    Write-Host "  ━━━ FIREWALL ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    $fw = Get-NetFirewallProfile -ErrorAction SilentlyContinue
    foreach ($p in $fw) {
        if ($p.Enabled) {
            Good "$($p.Name) profile: ON (Default Inbound: $($p.DefaultInboundAction))"
        } else {
            Crit "$($p.Name) profile: OFF"
        }
    }

    # --- Defender ---
    Write-Host ""
    Write-Host "  ━━━ ANTIVIRUS ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    $def = Get-MpComputerStatus -ErrorAction SilentlyContinue
    if ($def) {
        if ($def.RealTimeProtectionEnabled) { Good "Windows Defender real-time: ON" }
        else { Crit "Windows Defender real-time: OFF" }

        $defAge = ((Get-Date) - $def.AntivirusSignatureLastUpdated).Days
        if ($defAge -le 3) { Good "Virus definitions: $defAge day(s) old" }
        else { Warn "Virus definitions: $defAge days old" }

        $scanAge = ((Get-Date) - $def.QuickScanEndTime).Days
        if ($scanAge -le 7) { Good "Last scan: $scanAge day(s) ago" }
        else { Warn "Last scan: $scanAge days ago" }
    } else {
        Warn "Cannot read Defender status (may need admin)"
    }

    # --- Encryption ---
    Write-Host ""
    Write-Host "  ━━━ ENCRYPTION ━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    $bl = Get-BitLockerVolume -MountPoint "C:" -ErrorAction SilentlyContinue
    if ($bl) {
        if ($bl.ProtectionStatus -eq "On") { Good "BitLocker C: ON ($($bl.EncryptionMethod))" }
        else { Crit "BitLocker C: OFF — disk not encrypted" }
    } else {
        Info "BitLocker not available (Windows Pro/Enterprise required)"
    }

    # --- Remote Access ---
    Write-Host ""
    Write-Host "  ━━━ REMOTE ACCESS ━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan

    $rdp = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" -Name fDenyTSConnections -ErrorAction SilentlyContinue
    if ($rdp -and $rdp.fDenyTSConnections -eq 0) {
        Crit "Remote Desktop: ENABLED"
    } else {
        Good "Remote Desktop: Disabled"
    }

    $ssh = Get-Service sshd -ErrorAction SilentlyContinue
    if ($ssh -and $ssh.Status -eq "Running") {
        Warn "SSH server: Running"
    } else {
        Good "SSH server: Not running"
    }

    $winrm = Get-Service WinRM -ErrorAction SilentlyContinue
    if ($winrm -and $winrm.Status -eq "Running") {
        Warn "WinRM (remote management): Running"
    } else {
        Good "WinRM: Not running"
    }

    # --- SMB ---
    Write-Host ""
    Write-Host "  ━━━ FILE SHARING ━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    $smbv1 = Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -ErrorAction SilentlyContinue
    if ($smbv1 -and $smbv1.State -eq "Enabled") {
        Crit "SMB v1: Enabled (WannaCry vulnerable)"
    } elseif ($smbv1) {
        Good "SMB v1: Disabled"
    }

    $shares = Get-SmbShare -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch '^\$|^IPC\$|^ADMIN\$' }
    if ($shares -and $shares.Count -gt 0) {
        Warn "Open shares: $(($shares | ForEach-Object { $_.Name }) -join ', ')"
    } else {
        Good "No user file shares"
    }

    # --- UAC ---
    Write-Host ""
    Write-Host "  ━━━ SYSTEM PROTECTION ━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    $uac = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name EnableLUA -ErrorAction SilentlyContinue
    if ($uac -and $uac.EnableLUA -eq 1) { Good "UAC: ON" }
    else { Crit "UAC: OFF" }

    $autoplay = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers" -Name DisableAutoplay -ErrorAction SilentlyContinue
    if ($autoplay -and $autoplay.DisableAutoplay -eq 1) { Good "AutoPlay: Disabled" }
    else { Warn "AutoPlay: Enabled" }

    # --- Open ports ---
    Write-Host ""
    Write-Host "  ━━━ NETWORK ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    $listeners = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Select-Object -ExpandProperty LocalPort -Unique | Sort-Object)
    Info "$($listeners.Count) listening ports"

    $foreign = @(Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue |
        Where-Object { $_.RemoteAddress -notmatch '^127\.|^::1$|^0\.|^192\.168\.|^10\.|^172\.(1[6-9]|2[0-9]|3[01])\.' })
    Info "$($foreign.Count) external connections"

    $wifi = netsh wlan show interfaces 2>$null
    if ($wifi) {
        $ssid = ($wifi | Select-String "^\s+SSID\s+:\s+(.+)").Matches.Groups[1].Value
        $auth = ($wifi | Select-String "Authentication\s+:\s+(.+)").Matches.Groups[1].Value
        if ($ssid) { Info "WiFi: $ssid ($auth)" }
    }

    # --- Updates ---
    Write-Host ""
    Write-Host "  ━━━ UPDATES ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    try {
        $us = New-Object -ComObject Microsoft.Update.Session
        $pending = $us.CreateUpdateSearcher().Search("IsInstalled=0").Updates.Count
        if ($pending -eq 0) { Good "Windows is up to date" }
        else { Warn "$pending update(s) available" }
    } catch {
        Info "Cannot check updates (may need admin)"
    }

    Write-Host ""
    Write-Host "════════════════════════════════════════════════" -ForegroundColor Cyan
}

# ═══════════════════════════════════════════════════════════════
# HARDEN
# ═══════════════════════════════════════════════════════════════

function Apply-Hardening {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host ""
        Crit "This command needs Administrator privileges."
        Write-Host "  Right-click PowerShell > 'Run as administrator', then try again." -ForegroundColor Yellow
        return
    }

    Write-Host ""
    Write-Host "════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  SECURITY HARDENING — $MACHINE_NAME" -ForegroundColor Cyan
    Write-Host "════════════════════════════════════════════════" -ForegroundColor Cyan

    # --- Backup ---
    Write-Host ""
    Write-Host "  Step 1: Creating backup..." -ForegroundColor White
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

    netsh advfirewall export "$backupDir\firewall-backup.wfw" 2>$null
    reg export "HKLM\SYSTEM\CurrentControlSet\Control\Terminal Server" "$backupDir\rdp-backup.reg" /y 2>$null
    reg export "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" "$backupDir\uac-backup.reg" /y 2>$null
    reg export "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers" "$backupDir\autoplay-backup.reg" /y 2>$null

    Good "Backup saved to $backupDir"

    # --- Firewall ---
    Write-Host ""
    Write-Host "  Step 2: Windows Firewall..." -ForegroundColor White
    Set-NetFirewallProfile -All -Enabled True -DefaultInboundAction Block -DefaultOutboundAction Allow -NotifyOnListen True
    Good "Firewall ON — all profiles, inbound blocked by default"
    Info "Outbound traffic allowed. Apps you use work normally."

    # --- Remote access ---
    Write-Host ""
    Write-Host "  Step 3: Closing remote access..." -ForegroundColor White

    Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" -Name fDenyTSConnections -Value 1
    Good "Remote Desktop: Disabled"

    $sshSvc = Get-Service sshd -ErrorAction SilentlyContinue
    if ($sshSvc -and $sshSvc.Status -eq "Running") {
        Stop-Service sshd -Force -ErrorAction SilentlyContinue
        Set-Service sshd -StartupType Disabled -ErrorAction SilentlyContinue
        Good "SSH server: Stopped and disabled"
    } else {
        Good "SSH server: Already off"
    }

    $winrmSvc = Get-Service WinRM -ErrorAction SilentlyContinue
    if ($winrmSvc -and $winrmSvc.Status -eq "Running") {
        Stop-Service WinRM -Force -ErrorAction SilentlyContinue
        Set-Service WinRM -StartupType Disabled -ErrorAction SilentlyContinue
        Good "WinRM: Stopped and disabled"
    } else {
        Good "WinRM: Already off"
    }

    # --- SMB v1 ---
    Write-Host ""
    Write-Host "  Step 4: Removing legacy protocols..." -ForegroundColor White
    $smb1 = Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -ErrorAction SilentlyContinue
    if ($smb1 -and $smb1.State -eq "Enabled") {
        Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart -ErrorAction SilentlyContinue | Out-Null
        Good "SMB v1: Disabled (WannaCry protection)"
    } else {
        Good "SMB v1: Already disabled"
    }

    # --- UAC ---
    Write-Host ""
    Write-Host "  Step 5: System protection..." -ForegroundColor White
    Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name EnableLUA -Value 1
    Good "UAC: ON"

    # Disable AutoPlay
    New-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers" -Name DisableAutoplay -Value 1 -PropertyType DWord -Force | Out-Null
    Good "AutoPlay: Disabled (USB drives won't auto-run)"

    # --- Firewall rules for dangerous ports ---
    Write-Host ""
    Write-Host "  Step 6: Blocking dangerous ports..." -ForegroundColor White

    $dangerousPorts = @(
        @{ Name = "Block-RDP-In"; Port = 3389; Desc = "Remote Desktop" },
        @{ Name = "Block-Telnet-In"; Port = 23; Desc = "Telnet" },
        @{ Name = "Block-FTP-In"; Port = 21; Desc = "FTP" },
        @{ Name = "Block-NetBIOS-139"; Port = 139; Desc = "NetBIOS" },
        @{ Name = "Block-SMB-445"; Port = 445; Desc = "SMB from outside" }
    )

    foreach ($rule in $dangerousPorts) {
        $existing = Get-NetFirewallRule -DisplayName "HealthAgent-$($rule.Name)" -ErrorAction SilentlyContinue
        if (-not $existing) {
            New-NetFirewallRule -DisplayName "HealthAgent-$($rule.Name)" `
                -Direction Inbound -Action Block -Protocol TCP `
                -LocalPort $rule.Port -Profile Public,Private `
                -Description "System Health Agent: Block $($rule.Desc) from outside" `
                -ErrorAction SilentlyContinue | Out-Null
        }
        Good "Blocked port $($rule.Port) ($($rule.Desc))"
    }

    # --- Privacy ---
    Write-Host ""
    Write-Host "  Step 7: Privacy settings..." -ForegroundColor White

    # Require Ctrl+Alt+Del for login (prevents credential interception)
    Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name DisableCAD -Value 0 -ErrorAction SilentlyContinue
    Good "Ctrl+Alt+Del required at login"

    # Screen lock timeout
    $lockTimeout = Get-ItemProperty "HKCU:\Control Panel\Desktop" -Name ScreenSaveTimeOut -ErrorAction SilentlyContinue
    if (-not $lockTimeout -or [int]$lockTimeout.ScreenSaveTimeOut -gt 600) {
        Set-ItemProperty "HKCU:\Control Panel\Desktop" -Name ScreenSaveTimeOut -Value "300"
        Set-ItemProperty "HKCU:\Control Panel\Desktop" -Name ScreenSaverIsSecure -Value "1"
        Good "Screen locks after 5 minutes of inactivity"
    } else {
        Good "Screen lock already configured"
    }

    # --- Verify ---
    Write-Host ""
    Write-Host "  Step 8: Verifying..." -ForegroundColor White
    $fwOn = @(Get-NetFirewallProfile | Where-Object { $_.Enabled }).Count
    $rdpOff = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" -Name fDenyTSConnections).fDenyTSConnections -eq 1
    $uacOn = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name EnableLUA).EnableLUA -eq 1

    if ($fwOn -eq 3 -and $rdpOff -and $uacOn) {
        Good "All security checks passed"
    } else {
        if ($fwOn -ne 3) { Warn "Firewall: only $fwOn/3 profiles enabled" }
        if (-not $rdpOff) { Warn "RDP still enabled" }
        if (-not $uacOn) { Warn "UAC still off" }
    }

    # --- Summary ---
    Write-Host ""
    Write-Host "  ─────────────────────────────────────────────"
    Write-Host "  What's protected:" -ForegroundColor Green
    Write-Host "    - Firewall ON (all 3 profiles)" -ForegroundColor Green
    Write-Host "    - Remote Desktop disabled" -ForegroundColor Green
    Write-Host "    - SSH and WinRM disabled" -ForegroundColor Green
    Write-Host "    - SMB v1 disabled" -ForegroundColor Green
    Write-Host "    - Dangerous ports blocked" -ForegroundColor Green
    Write-Host "    - UAC active" -ForegroundColor Green
    Write-Host "    - AutoPlay disabled" -ForegroundColor Green
    Write-Host "    - Screen lock enabled" -ForegroundColor Green
    Write-Host ""
    Write-Host "  What STILL works:" -ForegroundColor Cyan
    Write-Host "    - All your apps and internet" -ForegroundColor Cyan
    Write-Host "    - File sharing on local network (SMB v2/v3)" -ForegroundColor Cyan
    Write-Host "    - Bluetooth, printers, peripherals" -ForegroundColor Cyan
    Write-Host "    - Windows Store and updates" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  To undo: .\firewall.ps1 -Undo" -ForegroundColor DarkGray
    Write-Host "════════════════════════════════════════════════" -ForegroundColor Cyan
}

# ═══════════════════════════════════════════════════════════════
# UNDO
# ═══════════════════════════════════════════════════════════════

function Undo-Hardening {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Crit "This command needs Administrator privileges."
        return
    }

    $backupFw = "$backupDir\firewall-backup.wfw"
    if (-not (Test-Path $backupFw)) {
        Crit "No backup found at $backupDir"
        Write-Host "  Hardening was not applied, or backup was deleted." -ForegroundColor DarkGray
        return
    }

    Write-Host ""
    Write-Host "  Restoring from backup..." -ForegroundColor Yellow

    netsh advfirewall import "$backupFw" 2>$null
    Good "Firewall rules restored"

    $rdpReg = "$backupDir\rdp-backup.reg"
    if (Test-Path $rdpReg) { reg import $rdpReg 2>$null; Good "RDP settings restored" }

    $uacReg = "$backupDir\uac-backup.reg"
    if (Test-Path $uacReg) { reg import $uacReg 2>$null; Good "UAC settings restored" }

    $autoReg = "$backupDir\autoplay-backup.reg"
    if (Test-Path $autoReg) { reg import $autoReg 2>$null; Good "AutoPlay settings restored" }

    # Remove custom firewall rules
    Get-NetFirewallRule -DisplayName "HealthAgent-*" -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue
    Good "Custom firewall rules removed"

    Write-Host ""
    Good "All settings restored to pre-hardening state"
    Write-Host "════════════════════════════════════════════════" -ForegroundColor Cyan
}

# ═══════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════

if ($Harden) {
    Apply-Hardening
} elseif ($Undo) {
    Undo-Hardening
} else {
    Show-Status
}
