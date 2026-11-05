#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# System Health Agent — Configuration
# ═══════════════════════════════════════════════════════════════
# Edit this file OR run ./setup.sh to configure for your system.
# Every script sources this file. No hardcoded values elsewhere.
# ═══════════════════════════════════════════════════════════════

# Where this agent lives (auto-detected from this file's location)
HEALTH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Reports, logs, CSVs go here
REPORT_DIR="$HEALTH_DIR/reports"

# Learnings file (auto-updated by optimizer)
LEARNINGS_FILE="$HEALTH_DIR/learnings.md"

# ─── Google Sheet ───
# The single sheet where all reports go (simple language format)
# Each audit creates a new tab named by date (e.g. "2026-11-06")
# Set to empty string "" if you don't want Google Sheet integration
SHEET_ID="1VCP4yvSJiQDFa2l_wRLEdPS5zhC5Zc6PhWEVqj-zHZk"
SHEET_URL="https://docs.google.com/spreadsheets/d/$SHEET_ID/edit"

# Owner email — the Google account that owns the sheet
# Change this when setting up on a different system
OWNER_EMAIL="sachin@theboredmonkey.com"

# ─── Schedule ───
# When the weekly optimizer runs (used by setup.sh to create launchd job)
# Day: 1=Mon, 2=Tue, 3=Wed, 4=Thu, 5=Fri, 6=Sat, 7=Sun
SCHEDULE_DAY=5
SCHEDULE_HOUR=12
SCHEDULE_MINUTE=0
SCHEDULE_LABEL="com.system-health-weekly"

# ─── What to kill in Phase 3 (optimizer) ───
# Apps that auto-launch and eat memory. Add your own.
BLOATWARE_APPS=("Comet" "ChatGPT" "Adobe")

# ─── Caches to clean in Phase 2 ───
CLEANUP_CACHES=(
  "$HOME/Library/Caches/Comet"
  "$HOME/Library/Caches/Adobe"
  "$HOME/Library/Caches/Codex"
  "$HOME/Library/Caches/com.openai.chat"
  "$HOME/Library/Caches/com.anthropic.claude"
)

# ─── Chrome extension management ───
CHROME_EXT_DIR="$HOME/Library/Application Support/Google/Chrome/Default/Extensions"
CHROME_DISABLED_DIR="$HOME/Library/Application Support/Google/Chrome/Disabled-Extensions"

# ─── Thresholds ───
# Memory: alert if free memory drops below this (in MB)
MEM_CRITICAL_MB=2000
MEM_WARNING_MB=4000

# Disk: alert if usage goes above this (percentage)
DISK_CRITICAL_PCT=90
DISK_WARNING_PCT=80

# Cache: recommend cleanup above this (in MB)
CACHE_WARNING_MB=2000

# Trash: auto-empty above this (in MB) when --fix is used
TRASH_AUTO_EMPTY_MB=500

# Process count: warn above this
PROC_WARNING=700

# Battery: warn above this cycle count
BATTERY_WARNING_CYCLES=800
BATTERY_CRITICAL_CYCLES=1000

# Files older than this many days are flagged as idle
IDLE_DAYS=7

# ─── System info (auto-detected, don't edit) ───
MACHINE_NAME=$(scutil --get ComputerName 2>/dev/null || hostname)
TOTAL_RAM=$(sysctl -n hw.memsize 2>/dev/null | awk '{printf "%.0f", $1/1024/1024/1024}')
CHIP=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Unknown")
