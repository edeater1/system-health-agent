# ═══════════════════════════════════════════════════════════════
# System Health Agent — Configuration (Windows)
# ═══════════════════════════════════════════════════════════════
# Edit this file OR run .\setup.ps1 to configure for your system.
# Every script sources this file. No hardcoded values elsewhere.
# ═══════════════════════════════════════════════════════════════

# Where this agent lives
$HEALTH_DIR = Split-Path -Parent $PSScriptRoot
if (-not $HEALTH_DIR) { $HEALTH_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path }

# Reports, logs, CSVs go here
$REPORT_DIR = Join-Path $HEALTH_DIR "reports"

# Learnings file
$LEARNINGS_FILE = Join-Path $HEALTH_DIR "learnings.md"

# ─── Google Sheet ───
$SHEET_ID = ""
$SHEET_URL = "https://docs.google.com/spreadsheets/d/$SHEET_ID/edit"
$OWNER_EMAIL = "your@email.com"

# ─── Schedule ───
# When the weekly task runs (used by setup.ps1 to create scheduled task)
$SCHEDULE_DAY = "Friday"
$SCHEDULE_TIME = "12:00"
$TASK_NAME = "SystemHealthWeekly"

# ─── What to kill in optimizer ───
$BLOATWARE_APPS = @("Comet", "ChatGPT", "Adobe Creative Cloud")

# ─── Thresholds ───
$MEM_CRITICAL_MB = 2000
$MEM_WARNING_MB = 4000
$DISK_CRITICAL_PCT = 90
$DISK_WARNING_PCT = 80
$CACHE_WARNING_MB = 2000
$PROC_WARNING = 300
$BATTERY_WARNING_CYCLES = 800

# ─── System info (auto-detected) ───
$MACHINE_NAME = $env:COMPUTERNAME
$TOTAL_RAM = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
$CPU = (Get-CimInstance Win32_Processor).Name
$OS_VERSION = (Get-CimInstance Win32_OperatingSystem).Caption
