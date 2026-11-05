#!/bin/bash
# System Health Agent — Quick laptop health check
# Usage: ./health-check.sh [--fix] [--json]

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/config.sh"

FIX=false
JSON=false
mkdir -p "$REPORT_DIR"

for arg in "$@"; do
  case "$arg" in
    --fix)  FIX=true ;;
    --json) JSON=true ;;
  esac
done

TIMESTAMP=$(date +"%Y-%m-%d_%H-%M")
REPORT_FILE="$REPORT_DIR/health-$TIMESTAMP.md"
: > "$REPORT_FILE"  # truncate

ISSUES=()
WARNINGS=()
FIXES=()

log() { echo "$1" >> "$REPORT_FILE"; }
issue() { ISSUES+=("$1"); log "- ISSUE: $1"; }
warning() { WARNINGS+=("$1"); log "- WARNING: $1"; }
fixed() { FIXES+=("$1"); log "- FIXED: $1"; }

# ─── Header ───
log "# System Health Report — $(date '+%Y-%m-%d %H:%M')"
log ""

# ─── 1. Memory Check ───
log "## Memory"
mem_line=$(top -l 1 -s 0 2>/dev/null | grep PhysMem)
mem_used=$(echo "$mem_line" | awk '{print $2}' | tr -d 'G')
mem_free_raw=$(echo "$mem_line" | awk -F',' '{print $2}' | awk '{print $1}')
# Convert to MB regardless of unit
if echo "$mem_free_raw" | grep -q 'G'; then
  mem_free=$(echo "$mem_free_raw" | tr -d 'G' | awk '{printf "%.0f", $1*1024}')
else
  mem_free=$(echo "$mem_free_raw" | tr -d 'M')
fi
total_ram=$(sysctl -n hw.memsize | awk '{printf "%.0f", $1/1024/1024/1024}')
log "- Total: ${total_ram}GB | Used: ${mem_used}GB | Free: ${mem_free}MB"

if [ "${mem_free}" -lt "$MEM_CRITICAL_MB" ] 2>/dev/null; then
  issue "LOW MEMORY: Only ${mem_free}MB free (< ${MEM_CRITICAL_MB}MB threshold)"
elif [ "${mem_free}" -lt "$MEM_WARNING_MB" ] 2>/dev/null; then
  warning "Memory getting tight: ${mem_free}MB free"
fi

log ""
log "### Top Memory Consumers"
ps -eo rss,comm -m | awk 'NR>1 {mb=$1/1024; if(mb>100) printf "- %.0f MB | %s\n", mb, $2}' | head -10 >> "$REPORT_FILE"
log ""

# ─── 2. Bloatware Detection ───
log "## Bloatware & Idle Processes"

# Electron apps with excessive processes — exclude "claude" since we're running it
for app_name in Comet ChatGPT Codex Slack Discord Figma; do
  count=$(ps -eo comm 2>/dev/null | grep -ic "$app_name" || true)
  if [ "$count" -gt 10 ]; then
    mem=$(ps -eo rss,comm | grep -i "$app_name" | awk '{sum+=$1} END {printf "%.0f", sum/1024}')
    issue "$app_name has $count processes using ${mem}MB — excessive"
    if $FIX; then
      pkill -f "$app_name" 2>/dev/null || true
      fixed "Killed $app_name ($count processes, ${mem}MB)"
    fi
  fi
done

# ─── 3. Disk Health ───
log ""
log "## Disk"
disk_pct=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
disk_free=$(df -h / | awk 'NR==2 {print $4}')
log "- Free: $disk_free | Used: ${disk_pct}%"

if [ "$disk_pct" -gt "$DISK_CRITICAL_PCT" ]; then
  issue "DISK NEARLY FULL: ${disk_pct}% used"
elif [ "$disk_pct" -gt "$DISK_WARNING_PCT" ]; then
  warning "Disk usage high: ${disk_pct}%"
fi

user_cache=$(du -sm ~/Library/Caches 2>/dev/null | cut -f1)
log "- User caches: ${user_cache}MB"
if [ "$user_cache" -gt "$CACHE_WARNING_MB" ]; then
  warning "User caches are ${user_cache}MB (> ${CACHE_WARNING_MB}MB)"
  if $FIX; then
    rm -rf ~/Library/Caches/Comet/ ~/Library/Caches/Adobe/ ~/Library/Caches/Codex/ 2>/dev/null
    fixed "Cleaned app caches"
  fi
fi

trash_size=$(du -sm ~/.Trash 2>/dev/null | cut -f1 || echo 0)
if [ "${trash_size:-0}" -gt "$TRASH_AUTO_EMPTY_MB" ]; then
  warning "Trash is ${trash_size}MB"
  if $FIX; then
    rm -rf ~/.Trash/* 2>/dev/null || true
    fixed "Emptied Trash (${trash_size}MB)"
  fi
fi

downloads_size=$(du -sm ~/Downloads 2>/dev/null | cut -f1)
old_downloads=$(find ~/Downloads -maxdepth 1 -mtime +30 -type f 2>/dev/null | wc -l | tr -d ' ')
if [ "$old_downloads" -gt 10 ]; then
  warning "$old_downloads files in Downloads older than 30 days (${downloads_size}MB total)"
fi

# ─── 4. Apps Not Used in 7+ Days ───
log ""
log "## Idle Running Apps"

running_apps=$(osascript -e 'tell application "System Events" to get name of every application process whose background only is false' 2>/dev/null || echo "")
if [ -n "$running_apps" ]; then
  echo "$running_apps" | tr ',' '\n' | sed 's/^ //' | while IFS= read -r app; do
    app=$(echo "$app" | xargs)
    [ -z "$app" ] && continue
    # Skip essential apps
    case "$app" in Finder|Terminal|"System Settings"|"Claude Code") continue ;; esac
    app_path="/Applications/$app.app"
    [ ! -d "$app_path" ] && continue
    last_used=$(mdls -name kMDItemLastUsedDate "$app_path" 2>/dev/null | awk -F'"' '{print $2}')
    if [ -n "$last_used" ] && [ "$last_used" != "" ]; then
      days_ago=$(( ($(date +%s) - $(date -j -f "%Y-%m-%d %H:%M:%S %z" "$last_used" +%s 2>/dev/null || echo $(date +%s))) / 86400 )) 2>/dev/null || continue
      if [ "$days_ago" -gt 7 ] 2>/dev/null; then
        warning "$app is running but last opened $days_ago days ago"
        if $FIX; then
          osascript -e "tell application \"$app\" to quit" 2>/dev/null || true
          fixed "Quit idle app: $app (unused for ${days_ago}d)"
        fi
      fi
    fi
  done
fi

# ─── 5. Launch Agents Check ───
log ""
log "## Auto-Start Items"
agent_count=$(ls ~/Library/LaunchAgents/*.plist 2>/dev/null | wc -l | tr -d ' ')
disabled_count=$(ls ~/Library/LaunchAgents/*.plist.disabled 2>/dev/null | wc -l | tr -d ' ')
log "- Active agents: $agent_count | Disabled: $disabled_count"

# ─── 6. Thermal & Battery ───
log ""
log "## Thermal & Battery"
thermal_ok=$(pmset -g therm 2>/dev/null | grep -c "No thermal warning" || true)
if [ "$thermal_ok" -eq 0 ]; then
  issue "THERMAL WARNING detected — laptop is overheating"
else
  log "- Thermal: Normal"
fi

battery_health=$(system_profiler SPPowerDataType 2>/dev/null | grep "Cycle Count" | awk '{print $NF}' || echo "N/A")
battery_condition=$(system_profiler SPPowerDataType 2>/dev/null | grep "Condition" | awk -F': ' '{print $2}' || echo "N/A")
log "- Battery cycles: ${battery_health:-N/A} | Condition: ${battery_condition:-N/A}"

if [ -n "$battery_health" ] && [ "$battery_health" != "N/A" ] && [ "$battery_health" -gt "$BATTERY_WARNING_CYCLES" ] 2>/dev/null; then
  warning "Battery cycle count is $battery_health (consider service after $BATTERY_CRITICAL_CYCLES)"
fi

# ─── 7. Security Quick Check ───
log ""
log "## Security"
firewall=$(defaults read /Library/Preferences/com.apple.alf globalstate 2>/dev/null || echo "unknown")
case "$firewall" in
  0) warning "Firewall is OFF" ;;
  1) log "- Firewall: ON (specific services)" ;;
  2) log "- Firewall: ON (block all incoming)" ;;
  *) log "- Firewall: unknown" ;;
esac

filevault=$(fdesetup status 2>/dev/null | head -1 || echo "unknown")
log "- FileVault: ${filevault:-unknown}"

# ─── 8. Chrome Extension Audit ───
log ""
log "## Chrome Extensions"
ext_count=$(ls "$CHROME_EXT_DIR" 2>/dev/null | wc -l | tr -d ' ')
disabled_ext=$(ls "$CHROME_DISABLED_DIR" 2>/dev/null | wc -l | tr -d ' ')
log "- Active: $ext_count | Disabled: ${disabled_ext:-0}"

# ─── 9. Process Count ───
log ""
log "## System Load"
proc_count=$(ps -e | wc -l | tr -d ' ')
load=$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2, $3, $4}')
log "- Processes: $proc_count"
log "- Load average: $load"

if [ "$proc_count" -gt "$PROC_WARNING" ]; then
  warning "High process count: $proc_count (threshold: $PROC_WARNING)"
fi

# ─── 10. Never-opened apps taking disk space ───
log ""
log "## Unused Installed Apps (never opened)"
find /Applications -maxdepth 1 -name "*.app" -exec sh -c '
  last=$(mdls -name kMDItemLastUsedDate "$1" 2>/dev/null | awk -F"= " "{print \$2}")
  if [ "$last" = "(null)" ]; then
    size=$(du -sm "$1" 2>/dev/null | cut -f1)
    echo "- $(basename "$1"): ${size}MB (never opened)"
  fi
' _ {} \; 2>/dev/null >> "$REPORT_FILE"

# ─── Summary ───
log ""
log "---"
log "## Summary"
log "- Issues: ${#ISSUES[@]}"
log "- Warnings: ${#WARNINGS[@]}"
log "- Auto-fixed: ${#FIXES[@]}"

if [ ${#ISSUES[@]} -eq 0 ] && [ ${#WARNINGS[@]} -eq 0 ]; then
  log "- System is healthy."
fi

# ─── Console Output ───
echo ""
echo "════════════════════════════════════════"
echo "  SYSTEM HEALTH — $(date '+%Y-%m-%d %H:%M')"
echo "════════════════════════════════════════"
echo ""
echo "  Memory: ${mem_used}GB / ${total_ram}GB | Free: ${mem_free}MB"
echo "  Disk:   ${disk_pct}% used | Free: $disk_free"
echo "  Procs:  $proc_count | Load: $load"
echo ""
if [ ${#ISSUES[@]} -gt 0 ]; then
  echo "  ISSUES (${#ISSUES[@]}):"
  for i in "${ISSUES[@]}"; do echo "    ! $i"; done
  echo ""
fi
if [ ${#WARNINGS[@]} -gt 0 ]; then
  echo "  WARNINGS (${#WARNINGS[@]}):"
  for w in "${WARNINGS[@]}"; do echo "    ~ $w"; done
  echo ""
fi
if [ ${#FIXES[@]} -gt 0 ]; then
  echo "  FIXED (${#FIXES[@]}):"
  for f in "${FIXES[@]}"; do echo "    + $f"; done
  echo ""
fi
if [ ${#ISSUES[@]} -eq 0 ] && [ ${#WARNINGS[@]} -eq 0 ]; then
  echo "  System is healthy."
  echo ""
fi
echo "  Report: $REPORT_FILE"
echo "════════════════════════════════════════"
