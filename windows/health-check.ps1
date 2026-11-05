#Requires -Version 5.1
<#
.SYNOPSIS
    System Health Agent — Quick Windows health check
.DESCRIPTION
    Checks memory, disk, CPU, battery, security, network, and running apps.
    Use -Fix to auto-fix common issues.
.EXAMPLE
    .\health-check.ps1
    .\health-check.ps1 -Fix
#>

param(
    [switch]$Fix
)

$ErrorActionPreference = "Continue"

# Load config
. "$PSScriptRoot\config.ps1"

New-Item -ItemType Directory -Path $REPORT_DIR -Force | Out-Null

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm"
$reportFile = Join-Path $REPORT_DIR "health-$timestamp.md"

$issues = @()
$warnings = @()
$fixes = @()

function Log($msg) { Add-Content -Path $reportFile -Value $msg }
function Issue($msg) { $script:issues += $msg; Log "- ISSUE: $msg" }
function Warn($msg) { $script:warnings += $msg; Log "- WARNING: $msg" }
function Fixed($msg) { $script:fixes += $msg; Log "- FIXED: $msg" }

Log "# System Health Report — $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
Log ""

# ─── 1. Memory ───
Log "## Memory"
$os = Get-CimInstance Win32_OperatingSystem
$totalMB = [math]::Round($os.TotalVisibleMemorySize / 1024)
$freeMB = [math]::Round($os.FreePhysicalMemory / 1024)
$usedMB = $totalMB - $freeMB
$totalGB = [math]::Round($totalMB / 1024)
$usedGB = [math]::Round($usedMB / 1024, 1)

Log "- Total: ${totalGB}GB | Used: ${usedGB}GB | Free: ${freeMB}MB"

if ($freeMB -lt $MEM_CRITICAL_MB) {
    Issue "LOW MEMORY: Only ${freeMB}MB free (< ${MEM_CRITICAL_MB}MB)"
} elseif ($freeMB -lt $MEM_WARNING_MB) {
    Warn "Memory getting tight: ${freeMB}MB free"
}

Log ""
Log "### Top Memory Consumers"
Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 10 | ForEach-Object {
    $mb = [math]::Round($_.WorkingSet64 / 1MB)
    Log "- $mb MB | $($_.ProcessName)"
}
Log ""

# ─── 2. Bloatware ───
Log "## Heavy Apps"
foreach ($app in $BLOATWARE_APPS) {
    $procs = Get-Process -Name "*$app*" -ErrorAction SilentlyContinue
    if ($procs -and $procs.Count -gt 5) {
        $memMB = [math]::Round(($procs | Measure-Object WorkingSet64 -Sum).Sum / 1MB)
        Issue "$app has $($procs.Count) processes using ${memMB}MB"
        if ($Fix) {
            $procs | Stop-Process -Force -ErrorAction SilentlyContinue
            Fixed "Killed $app ($($procs.Count) processes, ${memMB}MB)"
        }
    }
}

# ─── 3. Disk ───
Log ""
Log "## Disk"
$drive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
$totalGB_disk = [math]::Round($drive.Size / 1GB)
$freeGB_disk = [math]::Round($drive.FreeSpace / 1GB)
$usedPct = [math]::Round(($drive.Size - $drive.FreeSpace) / $drive.Size * 100)

Log "- C: Total: ${totalGB_disk}GB | Free: ${freeGB_disk}GB | Used: ${usedPct}%"

if ($usedPct -gt $DISK_CRITICAL_PCT) {
    Issue "DISK NEARLY FULL: ${usedPct}% used"
} elseif ($usedPct -gt $DISK_WARNING_PCT) {
    Warn "Disk usage high: ${usedPct}%"
}

# Temp files size
$tempSize = 0
if (Test-Path $env:TEMP) {
    $tempSize = [math]::Round((Get-ChildItem $env:TEMP -Recurse -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum / 1MB)
}
Log "- Temp files: ${tempSize}MB"

if ($Fix -and $tempSize -gt 500) {
    Remove-Item "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
    Fixed "Cleaned temp files (${tempSize}MB)"
}

# Downloads folder
$downloadsPath = [Environment]::GetFolderPath("UserProfile") + "\Downloads"
$dlSize = 0
$oldDl = 0
if (Test-Path $downloadsPath) {
    $dlSize = [math]::Round((Get-ChildItem $downloadsPath -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum / 1MB)
    $oldDl = (Get-ChildItem $downloadsPath -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) }).Count
}
if ($oldDl -gt 10) {
    Warn "$oldDl files in Downloads older than 30 days (${dlSize}MB total)"
}

# Recycle bin
$recycleBin = (New-Object -ComObject Shell.Application).Namespace(0xA)
$rbCount = $recycleBin.Items().Count
if ($rbCount -gt 50) {
    Warn "Recycle Bin has $rbCount items"
    if ($Fix) {
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
        Fixed "Emptied Recycle Bin ($rbCount items)"
    }
}

# ─── 4. CPU & Thermal ───
Log ""
Log "## CPU"
$cpuLoad = [math]::Round((Get-CimInstance Win32_Processor).LoadPercentage)
Log "- CPU: $CPU"
Log "- Load: ${cpuLoad}%"
if ($cpuLoad -gt 90) { Issue "CPU overloaded: ${cpuLoad}%" }

# ─── 5. Battery ───
Log ""
Log "## Battery"
$battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
if ($battery) {
    $charge = $battery.EstimatedChargeRemaining
    $status = switch ($battery.BatteryStatus) {
        1 { "Discharging" }; 2 { "Plugged in" }; 3 { "Fully charged" }
        4 { "Low" }; 5 { "Critical" }; default { "Unknown" }
    }
    Log "- Charge: ${charge}%"
    Log "- Status: $status"

    if ($charge -lt 20 -and $status -eq "Discharging") {
        Warn "Battery low: ${charge}%"
    }

    # Battery health via powercfg
    $battReport = Join-Path $REPORT_DIR "battery-report.html"
    powercfg /batteryreport /output $battReport 2>$null
    if (Test-Path $battReport) {
        $content = Get-Content $battReport -Raw
        if ($content -match 'DESIGN CAPACITY.*?(\d[\d,]+)\s*mWh') {
            $designCap = $Matches[1] -replace ','
        }
        if ($content -match 'FULL CHARGE CAPACITY.*?(\d[\d,]+)\s*mWh') {
            $fullCap = $Matches[1] -replace ','
        }
        if ($designCap -and $fullCap -and [int]$designCap -gt 0) {
            $healthPct = [math]::Round([int]$fullCap / [int]$designCap * 100)
            Log "- Battery health: ${healthPct}% of original capacity"
            if ($healthPct -lt 80) { Warn "Battery degraded to ${healthPct}%" }
        }
    }
} else {
    Log "- No battery detected (desktop)"
}

# ─── 6. Security ───
Log ""
Log "## Security"

# Windows Firewall
$fw = Get-NetFirewallProfile -ErrorAction SilentlyContinue
$fwOff = ($fw | Where-Object { -not $_.Enabled }).Count
if ($fwOff -gt 0) {
    Warn "Windows Firewall: $fwOff profile(s) disabled"
} else {
    Log "- Firewall: All profiles enabled"
}

# Windows Defender
$defender = Get-MpComputerStatus -ErrorAction SilentlyContinue
if ($defender) {
    Log "- Defender: $(if ($defender.RealTimeProtectionEnabled) {'ON'} else {'OFF'})"
    Log "- Last scan: $($defender.QuickScanEndTime)"
    $daysSinceScan = ((Get-Date) - $defender.QuickScanEndTime).Days
    if ($daysSinceScan -gt 7) { Warn "No virus scan in $daysSinceScan days" }
    if (-not $defender.RealTimeProtectionEnabled) { Issue "Windows Defender real-time protection is OFF!" }
} else {
    Warn "Could not check Windows Defender status"
}

# BitLocker
$bl = Get-BitLockerVolume -MountPoint "C:" -ErrorAction SilentlyContinue
if ($bl) {
    Log "- BitLocker: $($bl.ProtectionStatus)"
    if ($bl.ProtectionStatus -ne "On") { Warn "BitLocker is not enabled on C:" }
} else {
    Log "- BitLocker: Not available"
}

# Failed logins (last 7 days)
$failedLogins = 0
try {
    $failedLogins = (Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4625; StartTime=(Get-Date).AddDays(-7)} -ErrorAction SilentlyContinue).Count
} catch { $failedLogins = 0 }
Log "- Failed logins (7d): $failedLogins"
if ($failedLogins -gt 50) { Issue "HIGH failed login attempts: $failedLogins in 7 days!" }
elseif ($failedLogins -gt 10) { Warn "Multiple failed logins: $failedLogins in 7 days" }

# ─── 7. Network ───
Log ""
Log "## Network"
$adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
if ($adapter) {
    Log "- Connected via: $($adapter.Name) ($($adapter.InterfaceDescription))"
    $ip = (Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress
    Log "- Local IP: $ip"
}
$dns = (Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1).ServerAddresses -join ", "
Log "- DNS: $dns"

# Open listening ports
$listeners = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Select-Object -ExpandProperty LocalPort -Unique | Sort-Object
Log "- Listening ports: $($listeners.Count)"

# ─── 8. Startup Items ───
Log ""
Log "## Startup Items"
$startups = Get-CimInstance Win32_StartupCommand -ErrorAction SilentlyContinue
Log "- Startup programs: $($startups.Count)"

# ─── 9. Process Count ───
Log ""
Log "## System Load"
$procCount = (Get-Process).Count
Log "- Processes: $procCount"
if ($procCount -gt $PROC_WARNING) { Warn "High process count: $procCount" }

# ─── Summary ───
Log ""
Log "---"
Log "## Summary"
Log "- Issues: $($issues.Count)"
Log "- Warnings: $($warnings.Count)"
Log "- Auto-fixed: $($fixes.Count)"

# Console output
Write-Host ""
Write-Host "════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  SYSTEM HEALTH — $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -ForegroundColor Cyan
Write-Host "════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Memory: ${usedGB}GB / ${totalGB}GB | Free: ${freeMB}MB"
Write-Host "  Disk:   ${usedPct}% used | Free: ${freeGB_disk}GB"
Write-Host "  CPU:    ${cpuLoad}% | Procs: $procCount"
Write-Host ""

if ($issues.Count -gt 0) {
    Write-Host "  ISSUES ($($issues.Count)):" -ForegroundColor Red
    foreach ($i in $issues) { Write-Host "    ! $i" -ForegroundColor Red }
    Write-Host ""
}
if ($warnings.Count -gt 0) {
    Write-Host "  WARNINGS ($($warnings.Count)):" -ForegroundColor Yellow
    foreach ($w in $warnings) { Write-Host "    ~ $w" -ForegroundColor Yellow }
    Write-Host ""
}
if ($fixes.Count -gt 0) {
    Write-Host "  FIXED ($($fixes.Count)):" -ForegroundColor Green
    foreach ($f in $fixes) { Write-Host "    + $f" -ForegroundColor Green }
    Write-Host ""
}
if ($issues.Count -eq 0 -and $warnings.Count -eq 0) {
    Write-Host "  System is healthy." -ForegroundColor Green
    Write-Host ""
}
Write-Host "  Report: $reportFile"
Write-Host "════════════════════════════════════════" -ForegroundColor Cyan
