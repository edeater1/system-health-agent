#Requires -Version 5.1
<#
.SYNOPSIS
    System Health Agent — Windows Setup
.DESCRIPTION
    Run once on a new system to configure the health agent.
    Sets up email, Google Sheet, weekly schedule, and runs a test.
.EXAMPLE
    .\setup.ps1
    .\setup.ps1 -Email "you@gmail.com" -Day "Friday" -Hour "12:00"
    .\setup.ps1 -Email "you@gmail.com" -SheetId "your-sheet-id" -NoTest
#>

param(
    [string]$Email,
    [string]$SheetId,
    [string]$Day,
    [string]$Hour,
    [switch]$NoTest
)

$ErrorActionPreference = "Stop"

# Load config
. "$PSScriptRoot\config.ps1"

Write-Host ""
Write-Host "═══════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  System Health Agent — Setup (Windows)" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Machine: $MACHINE_NAME"
Write-Host "  CPU:     $CPU"
Write-Host "  RAM:     ${TOTAL_RAM}GB"
Write-Host "  OS:      $OS_VERSION"
Write-Host ""

# ─── Step 1: Email ───
if (-not $Email) {
    $Email = Read-Host "Your Google account email (Enter to keep '$OWNER_EMAIL')"
}
if ($Email) {
    (Get-Content "$PSScriptRoot\config.ps1") -replace '^\$OWNER_EMAIL = .*', "`$OWNER_EMAIL = `"$Email`"" | Set-Content "$PSScriptRoot\config.ps1"
    $OWNER_EMAIL = $Email
    Write-Host "  Email: $OWNER_EMAIL" -ForegroundColor Green
} else {
    Write-Host "  Email unchanged: $OWNER_EMAIL"
}

# ─── Step 2: Sheet ID ───
if ($SheetId) {
    (Get-Content "$PSScriptRoot\config.ps1") -replace '^\$SHEET_ID = .*', "`$SHEET_ID = `"$SheetId`"" | Set-Content "$PSScriptRoot\config.ps1"
    $SHEET_ID = $SheetId
    Write-Host "  Sheet: $SHEET_ID" -ForegroundColor Green
} else {
    Write-Host "  Sheet ID unchanged: $SHEET_ID"
    Write-Host "  (Re-run with -SheetId to set one)"
}

# ─── Step 3: Schedule ───
if ($Day) { $SCHEDULE_DAY = $Day }
if ($Hour) { $SCHEDULE_TIME = $Hour }

# Create Windows Scheduled Task
$scriptPath = Join-Path $PSScriptRoot "health-check.ps1"
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -Fix"
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $SCHEDULE_DAY -At $SCHEDULE_TIME
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -DontStopOnIdleEnd

# Remove old task if exists
Unregister-ScheduledTask -TaskName $TASK_NAME -Confirm:$false -ErrorAction SilentlyContinue

Register-ScheduledTask -TaskName $TASK_NAME -Action $action -Trigger $trigger -Settings $settings -Description "Weekly system health check" -ErrorAction SilentlyContinue | Out-Null

Write-Host "  Schedule: $SCHEDULE_DAY at $SCHEDULE_TIME" -ForegroundColor Green

# ─── Step 4: Create directories ───
New-Item -ItemType Directory -Path $REPORT_DIR -Force | Out-Null
Write-Host "  Reports: $REPORT_DIR"

# ─── Step 5: Save config ───
$configJson = @{
    sheet_id = $SHEET_ID
    sheet_url = "https://docs.google.com/spreadsheets/d/$SHEET_ID/edit"
    owner = $OWNER_EMAIL
    machine = $MACHINE_NAME
    schedule = "$SCHEDULE_DAY $SCHEDULE_TIME"
    setup_date = (Get-Date -Format "yyyy-MM-dd")
} | ConvertTo-Json

$configJson | Set-Content (Join-Path (Split-Path $PSScriptRoot) "sheet-config.json")
Write-Host "  Config saved"

# ─── Step 6: Test ───
if (-not $NoTest) {
    Write-Host ""
    Write-Host "Running test..." -ForegroundColor Yellow
    & "$PSScriptRoot\health-check.ps1"
}

Write-Host ""
Write-Host "═══════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Setup Complete!" -ForegroundColor Green
Write-Host "═══════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Email:    $OWNER_EMAIL"
if ($SHEET_ID) { Write-Host "  Sheet:    https://docs.google.com/spreadsheets/d/$SHEET_ID/edit" }
Write-Host "  Schedule: $SCHEDULE_DAY at $SCHEDULE_TIME"
Write-Host "  Reports:  $REPORT_DIR"
Write-Host ""
Write-Host "  Commands:"
Write-Host "    .\health-check.ps1         Quick health check"
Write-Host "    .\health-check.ps1 -Fix    Check + auto-fix"
Write-Host ""
