#Requires -Version 5.1
<#
.SYNOPSIS
    System Health Agent — Smart Windows Health Check
.DESCRIPTION
    Acts like a technician: finds problems, explains why they matter,
    shows the best fix, tells you what changes, and asks before acting.
.EXAMPLE
    .\health-check.ps1                Check and report
    .\health-check.ps1 -Fix           Interactive fix (asks before each)
    .\health-check.ps1 -AutoFix       Unattended fix (for Task Scheduler)
#>

param(
    [switch]$Fix,
    [switch]$AutoFix
)

$ErrorActionPreference = "Continue"

. "$PSScriptRoot\config.ps1"

New-Item -ItemType Directory -Path $REPORT_DIR -Force | Out-Null

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm"
$reportFile = Join-Path $REPORT_DIR "health-$timestamp.md"
"" | Set-Content $reportFile

# ─── Finding storage ───
$findings = [System.Collections.ArrayList]::new()
$appliedFixes = [System.Collections.ArrayList]::new()

function Add-Finding {
    param(
        [string]$Severity,   # CRITICAL, WARNING, INFO, GOOD
        [string]$Title,
        [string]$Why = "",
        [string]$FixDesc = "",
        [string]$WhatChanges = "",
        [scriptblock]$FixAction = $null,
        [string]$Category = "General"
    )
    $script:findings.Add(@{
        Severity    = $Severity
        Title       = $Title
        Why         = $Why
        FixDesc     = $FixDesc
        WhatChanges = $WhatChanges
        FixAction   = $FixAction
        Category    = $Category
    }) | Out-Null
}

function Log($msg) { Add-Content -Path $reportFile -Value $msg }

function Ask-AndFix {
    param(
        [string]$Title,
        [string]$FixDesc,
        [string]$WhatChanges,
        [scriptblock]$FixAction
    )
    if (-not $FixAction) { return }

    if ($AutoFix) {
        try { & $FixAction; $script:appliedFixes.Add($Title) | Out-Null } catch {}
        return
    }

    Write-Host ""
    Write-Host "  Fix available: $FixDesc" -ForegroundColor Cyan
    Write-Host "  What changes: $WhatChanges" -ForegroundColor DarkGray
    $reply = Read-Host "  Apply this fix? [y/N]"
    if ($reply -match '^[Yy]') {
        try {
            & $FixAction
            $script:appliedFixes.Add($Title) | Out-Null
        } catch {
            Write-Host "  Fix failed: $_" -ForegroundColor Red
        }
    } else {
        Write-Host "  Skipped" -ForegroundColor DarkGray
    }
}

# ═══════════════════════════════════════════════════════════════
# COLLECT SYSTEM INFO
# ═══════════════════════════════════════════════════════════════

Write-Host ""
Write-Host "  Scanning your PC..." -ForegroundColor DarkGray

$osInfo = Get-CimInstance Win32_OperatingSystem
$totalMB = [math]::Round($osInfo.TotalVisibleMemorySize / 1024)
$freeMB = [math]::Round($osInfo.FreePhysicalMemory / 1024)
$usedMB = $totalMB - $freeMB
$totalGB = [math]::Round($totalMB / 1024)
$usedGB = [math]::Round($usedMB / 1024, 1)

$drive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
$totalGB_disk = [math]::Round($drive.Size / 1GB)
$freeGB_disk = [math]::Round($drive.FreeSpace / 1GB)
$usedPct = [math]::Round(($drive.Size - $drive.FreeSpace) / $drive.Size * 100)

$procCount = (Get-Process).Count
$cpuLoad = try { [math]::Round((Get-CimInstance Win32_Processor).LoadPercentage) } catch { 0 }

Log "# System Health Report — $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
Log "- Machine: $MACHINE_NAME | RAM: ${totalGB}GB | CPU: $CPU"
Log "- Memory: ${usedGB}GB used, ${freeMB}MB free"
Log "- Disk C: ${usedPct}% used, ${freeGB_disk}GB free"
Log "- Processes: $procCount | CPU: ${cpuLoad}%"
Log ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 1. SECURITY (technician checks this FIRST)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Windows Firewall
$fw = Get-NetFirewallProfile -ErrorAction SilentlyContinue
$fwOff = @($fw | Where-Object { -not $_.Enabled })
if ($fwOff.Count -gt 0) {
    $offNames = ($fwOff | ForEach-Object { $_.Name }) -join ", "
    Add-Finding -Severity "CRITICAL" -Title "Windows Firewall is OFF for: $offNames" `
        -Why "Without a firewall, anyone on the same network can try to connect to your PC. On public WiFi (cafes, airports), this is especially dangerous — hackers scan for unprotected machines." `
        -FixDesc "Turn on the firewall for all profiles" `
        -WhatChanges "Your PC blocks unsolicited incoming connections. Apps you use still work normally. File sharing on your home network still works." `
        -FixAction { Set-NetFirewallProfile -All -Enabled True } `
        -Category "Security"
} else {
    Add-Finding -Severity "GOOD" -Title "Windows Firewall is ON (all profiles)" -Category "Security"
}

# Windows Defender
$defender = Get-MpComputerStatus -ErrorAction SilentlyContinue
if ($defender) {
    if (-not $defender.RealTimeProtectionEnabled) {
        Add-Finding -Severity "CRITICAL" -Title "Windows Defender real-time protection is OFF" `
            -Why "Your PC has no active virus protection. Malware, ransomware, and spyware can install and run without being caught. This is the #1 security risk on Windows." `
            -FixDesc "Turn on Windows Defender real-time protection" `
            -WhatChanges "Defender starts scanning files as you open them. May slightly slow down file-heavy operations. All your apps work the same." `
            -FixAction { Set-MpPreference -DisableRealtimeMonitoring $false } `
            -Category "Security"
    } else {
        Add-Finding -Severity "GOOD" -Title "Windows Defender real-time protection is ON" -Category "Security"
    }

    $daysSinceScan = ((Get-Date) - $defender.QuickScanEndTime).Days
    if ($daysSinceScan -gt 7) {
        Add-Finding -Severity "WARNING" -Title "No virus scan in $daysSinceScan days" `
            -Why "Regular scans catch malware that slipped past real-time protection. Going $daysSinceScan days without a scan means threats could be hiding on your system." `
            -FixDesc "Run a quick scan now" `
            -WhatChanges "Defender scans your system in the background. Takes 5-15 minutes. Your PC stays usable during the scan." `
            -FixAction { Start-MpScan -ScanType QuickScan } `
            -Category "Security"
    } else {
        Add-Finding -Severity "GOOD" -Title "Virus scan up to date (last: $($defender.QuickScanEndTime.ToString('yyyy-MM-dd')))" -Category "Security"
    }

    # Check if Defender definitions are outdated
    $defAge = ((Get-Date) - $defender.AntivirusSignatureLastUpdated).Days
    if ($defAge -gt 3) {
        Add-Finding -Severity "WARNING" -Title "Virus definitions are $defAge days old" `
            -Why "New viruses are discovered daily. Outdated definitions mean Defender can't detect the latest threats." `
            -FixDesc "Update virus definitions" `
            -WhatChanges "Defender downloads the latest virus signatures. Takes 1-2 minutes." `
            -FixAction { Update-MpSignature } `
            -Category "Security"
    }
} else {
    Add-Finding -Severity "WARNING" -Title "Could not check Windows Defender status" `
        -Why "Windows Defender may not be installed, or another antivirus is managing protection. Verify you have active antivirus protection." `
        -Category "Security"
}

# BitLocker
$bl = Get-BitLockerVolume -MountPoint "C:" -ErrorAction SilentlyContinue
if ($bl) {
    if ($bl.ProtectionStatus -eq "On") {
        Add-Finding -Severity "GOOD" -Title "BitLocker disk encryption is ON" -Category "Security"
    } else {
        Add-Finding -Severity "CRITICAL" -Title "BitLocker is OFF — your files are NOT encrypted" `
            -Why "If your laptop is stolen, anyone can read your files by connecting the drive to another computer. Passwords, documents, photos — all accessible without your Windows password." `
            -FixDesc "Enable BitLocker in Settings > Privacy & Security > Device Encryption" `
            -WhatChanges "Your entire disk gets encrypted. Takes a few hours in the background. Your PC works normally during encryption. Only YOUR password can unlock the data." `
            -Category "Security"
    }
} else {
    Add-Finding -Severity "INFO" -Title "BitLocker not available (may need Windows Pro)" `
        -Why "BitLocker full disk encryption requires Windows Pro or Enterprise. Windows Home has Device Encryption if your hardware supports it." `
        -Category "Security"
}

# Remote Desktop
$rdp = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" -Name fDenyTSConnections -ErrorAction SilentlyContinue
if ($rdp -and $rdp.fDenyTSConnections -eq 0) {
    Add-Finding -Severity "CRITICAL" -Title "Remote Desktop is ENABLED — someone could control your PC" `
        -Why "Remote Desktop lets anyone with your credentials take full control of your PC remotely — see your screen, use your mouse, access your files. On a network, this is a top attack target." `
        -FixDesc "Disable Remote Desktop" `
        -WhatChanges "Nobody can RDP into your PC. You can still use remote tools like TeamViewer or AnyDesk if you choose to install them." `
        -FixAction { Set-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server" -Name fDenyTSConnections -Value 1 } `
        -Category "Security"
} else {
    Add-Finding -Severity "GOOD" -Title "Remote Desktop is disabled" -Category "Security"
}

# SMB v1 (legacy file sharing — massive security risk)
$smbv1 = Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -ErrorAction SilentlyContinue
if ($smbv1 -and $smbv1.State -eq "Enabled") {
    Add-Finding -Severity "CRITICAL" -Title "SMB v1 is ENABLED — vulnerable to WannaCry-type attacks" `
        -Why "SMB v1 is the protocol exploited by WannaCry ransomware. It's outdated and full of security holes. Microsoft recommends disabling it." `
        -FixDesc "Disable SMB v1" `
        -WhatChanges "Very old network devices (pre-2010) may lose file sharing access. Modern devices use SMB v2/v3 which stay active." `
        -FixAction { Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart -ErrorAction SilentlyContinue } `
        -Category "Security"
} elseif ($smbv1) {
    Add-Finding -Severity "GOOD" -Title "SMB v1 is disabled (WannaCry-safe)" -Category "Security"
}

# Failed logins
$failedLogins = 0
try {
    $events = Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4625; StartTime=(Get-Date).AddDays(-7)} -ErrorAction SilentlyContinue
    if ($events) { $failedLogins = $events.Count }
} catch { $failedLogins = 0 }

if ($failedLogins -gt 50) {
    Add-Finding -Severity "CRITICAL" -Title "$failedLogins failed login attempts in the last 7 days" `
        -Why "This is far above normal (3-5 per week is typical). Could be a brute-force attack, a misconfigured app, or someone trying to guess your password." `
        -FixDesc "Check the source of failed logins in Event Viewer > Security" `
        -WhatChanges "" `
        -Category "Security"
} elseif ($failedLogins -gt 10) {
    Add-Finding -Severity "WARNING" -Title "$failedLogins failed login attempts in the last 7 days" `
        -Why "Slightly elevated. Usually caused by a mistyped password or a service with wrong saved credentials." `
        -Category "Security"
} else {
    Add-Finding -Severity "GOOD" -Title "Failed logins normal ($failedLogins in 7 days)" -Category "Security"
}

# User Account Control (UAC)
$uac = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name EnableLUA -ErrorAction SilentlyContinue
if ($uac -and $uac.EnableLUA -eq 0) {
    Add-Finding -Severity "CRITICAL" -Title "User Account Control (UAC) is DISABLED" `
        -Why "UAC is your last line of defense — it asks for confirmation before apps make system changes. Without it, malware can silently install itself with admin privileges." `
        -FixDesc "Re-enable UAC" `
        -WhatChanges "You'll see confirmation prompts when apps try to make system changes. This is normal and protects you." `
        -FixAction { Set-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name EnableLUA -Value 1 } `
        -Category "Security"
} else {
    Add-Finding -Severity "GOOD" -Title "User Account Control (UAC) is ON" -Category "Security"
}

# AutoPlay (can auto-run malware from USB drives)
$autoplay = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers" -Name DisableAutoplay -ErrorAction SilentlyContinue
if (-not $autoplay -or $autoplay.DisableAutoplay -ne 1) {
    Add-Finding -Severity "WARNING" -Title "AutoPlay is enabled — USB drives can auto-run programs" `
        -Why "When you plug in a USB drive, Windows can automatically run programs on it. Malware spreads this way — an infected USB drive can compromise your PC instantly." `
        -FixDesc "Disable AutoPlay" `
        -WhatChanges "USB drives and CDs won't auto-run. You can still open them manually in File Explorer." `
        -FixAction { Set-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers" -Name DisableAutoplay -Value 1 } `
        -Category "Security"
}

# Check for open shares
$shares = Get-SmbShare -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch '^\$|^IPC\$|^ADMIN\$' }
if ($shares -and $shares.Count -gt 0) {
    $shareNames = ($shares | ForEach-Object { $_.Name }) -join ", "
    Add-Finding -Severity "WARNING" -Title "Network shares open: $shareNames" `
        -Why "Anyone on the same network can see these shared folders. If no password is set on the share, they can read or write your files." `
        -FixDesc "Review shares: run 'net share' in Command Prompt and remove any you don't need" `
        -WhatChanges "" `
        -Category "Security"
}

# Foreign connections
$foreignConns = @(Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue |
    Where-Object { $_.RemoteAddress -notmatch '^127\.|^::1$|^0\.|^192\.168\.|^10\.|^172\.(1[6-9]|2[0-9]|3[01])\.' })
if ($foreignConns.Count -gt 30) {
    Add-Finding -Severity "WARNING" -Title "$($foreignConns.Count) connections to outside servers" `
        -Why "Your PC is talking to $($foreignConns.Count) external servers right now. High count — could be normal (many browser tabs) or could include unexpected connections." `
        -Category "Security"
} elseif ($foreignConns.Count -gt 0) {
    Add-Finding -Severity "INFO" -Title "$($foreignConns.Count) connections to outside servers" `
        -Why "Normal. These are your apps talking to their servers (browser, Teams, etc.)." `
        -Category "Security"
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 2. MEMORY & PERFORMANCE
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

if ($freeMB -lt $MEM_CRITICAL_MB) {
    Add-Finding -Severity "CRITICAL" -Title "Memory almost full — only ${freeMB}MB free out of ${totalGB}GB" `
        -Why "Your PC is running out of working memory. Apps will freeze, become slow, and the system uses disk as overflow (called 'paging') which is 100x slower than RAM." `
        -Category "Performance"

    foreach ($app in $BLOATWARE_APPS) {
        $procs = Get-Process -Name "*$app*" -ErrorAction SilentlyContinue
        if ($procs -and $procs.Count -gt 5) {
            $memMB = [math]::Round(($procs | Measure-Object WorkingSet64 -Sum).Sum / 1MB)
            $pCount = $procs.Count
            Add-Finding -Severity "CRITICAL" -Title "$app is eating ${memMB}MB of memory ($pCount processes)" `
                -Why "$app has spawned $pCount separate processes — this is an Electron app bug. It's using ${memMB}MB, which is why your PC feels slow." `
                -FixDesc "Force-quit $app" `
                -WhatChanges "$app closes and you get ~${memMB}MB of memory back. You can reopen it anytime — it will start fresh with less memory." `
                -FixAction ([scriptblock]::Create("Get-Process -Name '*$app*' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue")) `
                -Category "Performance"
        }
    }
} elseif ($freeMB -lt $MEM_WARNING_MB) {
    Add-Finding -Severity "WARNING" -Title "Memory getting tight — ${freeMB}MB free" `
        -Why "Not critical yet, but if you open more apps it will slow down. Close any apps you're not actively using." `
        -Category "Performance"
} else {
    Add-Finding -Severity "GOOD" -Title "Memory healthy — ${freeMB}MB free of ${totalGB}GB" -Category "Performance"
}

# Check for bloatware even when memory isn't critical
foreach ($app in @("Comet", "ChatGPT", "Codex", "Slack", "Discord", "Figma", "Teams")) {
    $procs = Get-Process -Name "*$app*" -ErrorAction SilentlyContinue
    if ($procs -and $procs.Count -gt 10) {
        $memMB = [math]::Round(($procs | Measure-Object WorkingSet64 -Sum).Sum / 1MB)
        $exists = $findings | Where-Object { $_.Title -match "$app is eating" }
        if (-not $exists) {
            Add-Finding -Severity "WARNING" -Title "$app has $($procs.Count) processes using ${memMB}MB" `
                -Why "Electron apps like $app spawn many helper processes. $($procs.Count) is excessive." `
                -FixDesc "Quit $app to free ${memMB}MB" `
                -WhatChanges "$app closes. You get ~${memMB}MB back. Reopen it when needed." `
                -FixAction ([scriptblock]::Create("Get-Process -Name '*$app*' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue")) `
                -Category "Performance"
        }
    }
}

# CPU
if ($cpuLoad -gt 90) {
    Add-Finding -Severity "CRITICAL" -Title "CPU overloaded at ${cpuLoad}%" `
        -Why "Your processor is maxed out. Everything will feel slow — apps lag, typing delays, windows take forever to open." `
        -FixDesc "Check Task Manager for the app using the most CPU" `
        -WhatChanges "" `
        -Category "Performance"
}

# Process count
if ($procCount -gt $PROC_WARNING) {
    Add-Finding -Severity "WARNING" -Title "$procCount processes running (normal is 150-250)" `
        -Why "High process count slows everything down. Usually caused by Electron apps (Teams, Slack, VS Code) each spawning dozens of helper processes." `
        -Category "Performance"
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 3. DISK & STORAGE
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

if ($usedPct -gt $DISK_CRITICAL_PCT) {
    Add-Finding -Severity "CRITICAL" -Title "Disk nearly full — ${usedPct}% used, only ${freeGB_disk}GB left" `
        -Why "Your PC needs free disk space to work. When the disk fills up, apps crash, Windows can't create temporary files, and updates can't install." `
        -FixDesc "Run Disk Cleanup or Settings > Storage > Cleanup recommendations" `
        -WhatChanges "" `
        -Category "Storage"
} elseif ($usedPct -gt $DISK_WARNING_PCT) {
    Add-Finding -Severity "WARNING" -Title "Disk usage high — ${usedPct}% used" `
        -Why "Getting close to full. Time to clean up old files, empty Recycle Bin, and remove unused apps." `
        -Category "Storage"
} else {
    Add-Finding -Severity "GOOD" -Title "Disk healthy — ${usedPct}% used, ${freeGB_disk}GB free" -Category "Storage"
}

# Temp files
$tempSize = 0
if (Test-Path $env:TEMP) {
    $tempSize = [math]::Round((Get-ChildItem $env:TEMP -Recurse -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum / 1MB)
}
if ($tempSize -gt 1000) {
    Add-Finding -Severity "WARNING" -Title "Temp files are ${tempSize}MB" `
        -Why "Windows and apps store temporary data that piles up over time. It's safe to clean — it rebuilds automatically." `
        -FixDesc "Clean temp files (${tempSize}MB)" `
        -WhatChanges "Temp files are deleted. Apps may rebuild some of them. No data is lost." `
        -FixAction { Remove-Item "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue } `
        -Category "Storage"
}

# Recycle Bin
try {
    $recycleBin = (New-Object -ComObject Shell.Application).Namespace(0xA)
    $rbCount = $recycleBin.Items().Count
    if ($rbCount -gt 50) {
        Add-Finding -Severity "INFO" -Title "Recycle Bin has $rbCount items" `
            -Why "Deleted files still take up space until you empty the Recycle Bin." `
            -FixDesc "Empty the Recycle Bin" `
            -WhatChanges "Deleted files are permanently removed. You won't be able to recover them after this." `
            -FixAction { Clear-RecycleBin -Force -ErrorAction SilentlyContinue } `
            -Category "Storage"
    }
} catch {}

# Old downloads
$downloadsPath = [Environment]::GetFolderPath("UserProfile") + "\Downloads"
$oldDl = 0; $dlSize = 0
if (Test-Path $downloadsPath) {
    $dlSize = [math]::Round((Get-ChildItem $downloadsPath -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum / 1MB)
    $oldDl = @(Get-ChildItem $downloadsPath -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) }).Count
}
if ($oldDl -gt 10) {
    Add-Finding -Severity "INFO" -Title "$oldDl old files in Downloads (${dlSize}MB total)" `
        -Why "These files have been sitting in Downloads for over 30 days. Most are probably installers or PDFs you already used." `
        -FixDesc "Review and delete old downloads" `
        -Category "Storage"
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 4. BATTERY & HARDWARE
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

$battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
if ($battery) {
    $charge = $battery.EstimatedChargeRemaining
    $status = switch ($battery.BatteryStatus) {
        1 { "Discharging" }; 2 { "Plugged in" }; 3 { "Fully charged" }
        4 { "Low" }; 5 { "Critical" }; default { "Unknown" }
    }

    if ($charge -lt 20 -and $status -eq "Discharging") {
        Add-Finding -Severity "WARNING" -Title "Battery low: ${charge}% and not plugged in" `
            -Why "Your laptop will shut down soon if you don't plug it in. Unsaved work will be lost." `
            -FixDesc "Plug in your charger" `
            -WhatChanges "" `
            -Category "Hardware"
    }

    # Battery health via powercfg
    $battReport = Join-Path $REPORT_DIR "battery-report.html"
    powercfg /batteryreport /output $battReport 2>$null
    if (Test-Path $battReport) {
        $content = Get-Content $battReport -Raw
        $designCap = 0; $fullCap = 0
        if ($content -match 'DESIGN CAPACITY.*?(\d[\d,]+)\s*mWh') { $designCap = [int]($Matches[1] -replace ',') }
        if ($content -match 'FULL CHARGE CAPACITY.*?(\d[\d,]+)\s*mWh') { $fullCap = [int]($Matches[1] -replace ',') }
        if ($designCap -gt 0 -and $fullCap -gt 0) {
            $healthPct = [math]::Round($fullCap / $designCap * 100)
            if ($healthPct -lt 50) {
                Add-Finding -Severity "CRITICAL" -Title "Battery severely degraded — only ${healthPct}% of original capacity" `
                    -Why "Your battery holds less than half its original charge. It will die quickly when unplugged." `
                    -FixDesc "Get the battery replaced" `
                    -WhatChanges "A new battery restores full charge capacity. Contact your laptop manufacturer for service." `
                    -Category "Hardware"
            } elseif ($healthPct -lt 80) {
                Add-Finding -Severity "WARNING" -Title "Battery degraded to ${healthPct}% of original capacity" `
                    -Why "Your battery is aging. It holds less charge than when it was new. This is normal wear over time." `
                    -Category "Hardware"
            } else {
                Add-Finding -Severity "GOOD" -Title "Battery healthy — ${healthPct}% of original capacity, ${charge}% charged" -Category "Hardware"
            }
        }
    }
} else {
    Add-Finding -Severity "INFO" -Title "No battery detected (desktop PC)" -Why "This is normal for a desktop computer." -Category "Hardware"
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 5. SOFTWARE & UPDATES
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Windows Updates
try {
    $updateSession = New-Object -ComObject Microsoft.Update.Session
    $updateSearcher = $updateSession.CreateUpdateSearcher()
    $pendingUpdates = $updateSearcher.Search("IsInstalled=0").Updates.Count
    if ($pendingUpdates -gt 0) {
        Add-Finding -Severity "WARNING" -Title "$pendingUpdates Windows update(s) available" `
            -Why "Updates often include security patches that fix known vulnerabilities. Delaying updates leaves your PC exposed to attacks that Microsoft has already fixed." `
            -FixDesc "Install updates from Settings > Windows Update" `
            -WhatChanges "Updates download and install. May require a restart. All your files and apps stay the same." `
            -Category "Software"
    } else {
        Add-Finding -Severity "GOOD" -Title "Windows is up to date" -Category "Software"
    }
} catch {
    Add-Finding -Severity "INFO" -Title "Could not check Windows Updates" -Why "Update check requires admin privileges or the update service may be paused." -Category "Software"
}

# Startup programs
$startups = Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue
if ($startups -and $startups.Count -gt 15) {
    Add-Finding -Severity "WARNING" -Title "$($startups.Count) programs start when you turn on your PC" `
        -Why "Each startup program slows down your boot time and uses memory in the background. Most people only need 5-8 startup items." `
        -FixDesc "Open Task Manager > Startup and disable ones you don't need" `
        -WhatChanges "Disabled apps won't auto-start. You can still open them manually. Your PC boots faster." `
        -Category "Software"
} elseif ($startups) {
    Add-Finding -Severity "GOOD" -Title "Startup programs: $($startups.Count)" -Category "Software"
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 6. BACKUP
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Check File History / Windows Backup
$backupStatus = Get-WBSummary -ErrorAction SilentlyContinue
$fileHistory = Get-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\FileHistory" -ErrorAction SilentlyContinue
if (-not $backupStatus -and -not $fileHistory) {
    Add-Finding -Severity "WARNING" -Title "No backup configured" `
        -Why "If your PC's drive fails, gets stolen, or a file is accidentally deleted, there's no backup to recover from. All your work, photos, and documents could be lost permanently." `
        -FixDesc "Set up Windows Backup in Settings > Accounts > Windows backup, or connect an external drive for File History" `
        -WhatChanges "Your PC automatically backs up files. If anything goes wrong, you can restore your files." `
        -Category "Backup"
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 7. NETWORK
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Open listening ports
$listeners = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Select-Object -ExpandProperty LocalPort -Unique)
if ($listeners.Count -gt 20) {
    Add-Finding -Severity "WARNING" -Title "$($listeners.Count) services listening for incoming connections" `
        -Why "Each listening port is a potential entry point. Most PCs need only 5-10 listening services." `
        -FixDesc "Run 'netstat -an | findstr LISTEN' to see what's listening and close unnecessary services" `
        -Category "Security"
}

# WiFi security
$wifi = netsh wlan show interfaces 2>$null | Select-String "SSID|Authentication|Cipher"
if ($wifi -match "Open") {
    Add-Finding -Severity "CRITICAL" -Title "Connected to an OPEN (unencrypted) WiFi network" `
        -Why "On an open network, anyone nearby can see all your internet traffic — passwords, emails, everything. It's like having a conversation in a crowded room." `
        -FixDesc "Switch to a WPA2/WPA3 encrypted network, or use a VPN" `
        -WhatChanges "" `
        -Category "Security"
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# PRESENTATION — show findings like a technician
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Write-Host ""
Write-Host "════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  SYSTEM HEALTH CHECK — $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -ForegroundColor Cyan
Write-Host "  $MACHINE_NAME | ${totalGB}GB RAM | $CPU" -ForegroundColor Cyan
Write-Host "════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Memory: ${usedGB}GB / ${totalGB}GB (${freeMB}MB free)"
Write-Host "  Disk:   ${usedPct}% used (${freeGB_disk}GB free)"
Write-Host "  CPU:    ${cpuLoad}% | Processes: $procCount"

$critical = @($findings | Where-Object { $_.Severity -eq "CRITICAL" })
$warns = @($findings | Where-Object { $_.Severity -eq "WARNING" })
$infos = @($findings | Where-Object { $_.Severity -eq "INFO" })
$goods = @($findings | Where-Object { $_.Severity -eq "GOOD" })

# CRITICAL
if ($critical.Count -gt 0) {
    Write-Host ""
    Write-Host "  ━━━ CRITICAL — Fix These Now ━━━━━━━━━━━━━━━" -ForegroundColor Red
    $num = 0
    foreach ($f in $critical) {
        $num++
        Write-Host ""
        Write-Host "  $num. $($f.Title)" -ForegroundColor Red
        if ($f.Why) { Write-Host "     Why it matters: $($f.Why)" -ForegroundColor DarkGray }
        if ($f.FixDesc) { Write-Host "     Recommended fix: $($f.FixDesc)" -ForegroundColor Green }
        if ($f.WhatChanges) { Write-Host "     What changes: $($f.WhatChanges)" -ForegroundColor DarkGray }

        Log ""; Log "## CRITICAL: $($f.Title)"; Log "Why: $($f.Why)"
        if ($f.FixDesc) { Log "Fix: $($f.FixDesc)" }

        if (($Fix -or $AutoFix) -and $f.FixAction) {
            Ask-AndFix -Title $f.Title -FixDesc $f.FixDesc -WhatChanges $f.WhatChanges -FixAction $f.FixAction
        }
    }
}

# WARNINGS
if ($warns.Count -gt 0) {
    Write-Host ""
    Write-Host "  ━━━ WARNINGS — Should Fix Soon ━━━━━━━━━━━━━" -ForegroundColor Yellow
    $num = 0
    foreach ($f in $warns) {
        $num++
        Write-Host ""
        Write-Host "  $num. $($f.Title)" -ForegroundColor Yellow
        if ($f.Why) { Write-Host "     $($f.Why)" -ForegroundColor DarkGray }
        if ($f.FixDesc) { Write-Host "     Fix: $($f.FixDesc)" -ForegroundColor Green }

        Log ""; Log "## WARNING: $($f.Title)"; Log "Why: $($f.Why)"

        if (($Fix -or $AutoFix) -and $f.FixAction) {
            Ask-AndFix -Title $f.Title -FixDesc $f.FixDesc -WhatChanges $f.WhatChanges -FixAction $f.FixAction
        }
    }
}

# INFO
if ($infos.Count -gt 0) {
    Write-Host ""
    Write-Host "  ━━━ INFO — Worth Knowing ━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    foreach ($f in $infos) {
        Write-Host "  -> $($f.Title)" -ForegroundColor Cyan
        if ($f.Why) { Write-Host "     $($f.Why)" -ForegroundColor DarkGray }
        Log "- INFO: $($f.Title)"
    }
}

# GOOD
if ($goods.Count -gt 0) {
    Write-Host ""
    Write-Host "  ━━━ ALL GOOD ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
    foreach ($f in $goods) {
        Write-Host "  OK $($f.Title)" -ForegroundColor Green
        Log "- GOOD: $($f.Title)"
    }
}

# Applied fixes
if ($appliedFixes.Count -gt 0) {
    Write-Host ""
    Write-Host "  ━━━ FIXES APPLIED ━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Green
    foreach ($fx in $appliedFixes) {
        Write-Host "  OK Fixed: $fx" -ForegroundColor Green
        Log "- FIXED: $fx"
    }
}

# Score
Write-Host ""
Write-Host "  ─────────────────────────────────────────────"
if ($critical.Count -eq 0 -and $warns.Count -eq 0) {
    Write-Host "    Score: HEALTHY  ($($goods.Count) checks passed)" -ForegroundColor Green
} elseif ($critical.Count -eq 0) {
    Write-Host "    Score: MOSTLY OK  ($($warns.Count) warning(s), $($goods.Count) checks passed)" -ForegroundColor Yellow
} else {
    Write-Host "    Score: NEEDS ATTENTION  ($($critical.Count) critical, $($warns.Count) warning(s))" -ForegroundColor Red
}

if (-not $Fix -and -not $AutoFix -and ($critical.Count + $warns.Count) -gt 0) {
    Write-Host ""
    Write-Host "  Run .\health-check.ps1 -Fix to fix problems interactively" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "  Report saved: $reportFile"
Write-Host "════════════════════════════════════════════════" -ForegroundColor Cyan

# Log summary
Log ""; Log "---"; Log "## Summary"
Log "- Critical: $($critical.Count) | Warnings: $($warns.Count) | Info: $($infos.Count) | Good: $($goods.Count)"
Log "- Fixes applied: $($appliedFixes.Count)"
