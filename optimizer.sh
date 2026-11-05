#!/bin/bash
# System Optimizer Agent — full optimization pipeline
# Runs weekly via launchd, or manually anytime.
# Usage: ./optimizer.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/config.sh"

LOG="$REPORT_DIR/optimizer-$(date +%Y-%m-%d).log"
mkdir -p "$REPORT_DIR"

exec > >(tee -a "$LOG") 2>&1

echo "=== System Optimizer Agent — $(date) ==="
echo ""

# ─── Phase 1: Run health check with auto-fix ───
echo "[Phase 1] Running health check with auto-fix..."
bash "$HEALTH_DIR/health-check.sh" --fix 2>&1
echo ""

# ─── Phase 2: Deep cleanup ───
echo "[Phase 2] Deep cleanup..."

# Clean application caches that regrow
for cache_dir in "${CLEANUP_CACHES[@]}"; do
  if [ -d "$cache_dir" ]; then
    size=$(du -sm "$cache_dir" 2>/dev/null | cut -f1)
    rm -rf "$cache_dir"
    echo "  Cleaned: $(basename "$cache_dir") (${size}MB)"
  fi
done

# Clean old Adobe logs
find ~/Library/Logs/CreativeCloud -name "*.log" -mtime +3 -delete 2>/dev/null && echo "  Cleaned: old Adobe logs"

# Clean old health reports (keep last 30)
report_count=$(ls "$REPORT_DIR"/health-*.md 2>/dev/null | wc -l | tr -d ' ')
if [ "$report_count" -gt 30 ]; then
  ls -t "$REPORT_DIR"/health-*.md | tail -n +31 | xargs rm -f
  echo "  Cleaned: old health reports (kept last 30)"
fi

echo ""

# ─── Phase 3: Process optimization ───
echo "[Phase 3] Process optimization..."

# Kill known resource-heavy apps that auto-launch
for bloat in "${BLOATWARE_APPS[@]}"; do
  count=$(pgrep -fic "$bloat" 2>/dev/null || echo "0")
  if [ "${count:-0}" -gt 0 ] 2>/dev/null; then
    mem=$(ps -eo rss,comm | grep -i "$bloat" | awk '{sum+=$1} END {printf "%.0f", sum/1024}')
    pkill -f "$bloat" 2>/dev/null
    echo "  Killed: $bloat ($count procs, ${mem}MB)"
  fi
done

echo ""

# ─── Phase 4: Trend analysis ───
echo "[Phase 4] Analyzing trends from past reports..."

recent_reports=$(ls -t "$REPORT_DIR"/health-*.md 2>/dev/null | head -4)
recurring_issues=""

if [ -n "$recent_reports" ]; then
  # Find issues that appeared in multiple recent reports
  recurring_issues=$(cat $recent_reports 2>/dev/null | grep "^- ISSUE:" | sort | uniq -c | sort -rn | head -5)
  if [ -n "$recurring_issues" ]; then
    echo "  Recurring issues across recent reports:"
    echo "$recurring_issues" | while read count issue; do
      echo "    [$count occurrences] $issue"
    done
  else
    echo "  No recurring issues found."
  fi
fi

echo ""

# ─── Phase 5: Self-improvement — update learnings ───
echo "[Phase 5] Updating learnings..."

cat > "$LEARNINGS_FILE" << 'LEARN'
# System Health Agent — Learnings

Auto-updated by the optimizer after each run.

## Known Patterns
LEARN

# Append current learnings based on what we found
{
  echo ""
  echo "### Last updated: $(date '+%Y-%m-%d %H:%M')"
  echo ""

  # Check what apps keep respawning
  for app in Comet ChatGPT Adobe; do
    if grep -q "$app" "$LOG" 2>/dev/null; then
      echo "- **$app** keeps auto-launching. Consider deeper disabling."
    fi
  done

  # Memory trend
  mem_free=$(top -l 1 -s 0 | grep PhysMem | awk -F',' '{print $2}' | awk '{print $1}' | tr -d 'M')
  echo "- Post-optimization free memory: ${mem_free}MB"

  # Cache regrowth
  cache_size=$(du -sm ~/Library/Caches 2>/dev/null | cut -f1)
  echo "- Cache size after cleanup: ${cache_size}MB"

  if [ -n "$recurring_issues" ]; then
    echo ""
    echo "## Recurring Issues (needs permanent fix)"
    echo "$recurring_issues" | while read count issue; do
      echo "- [$count times] $issue"
    done
  fi

  echo ""
  echo "## Recommendations for Next Version"
  echo "- Monitor which killed apps respawn and add permanent launch agent disabling"
  echo "- Track memory/disk trends over time to predict issues"
  echo "- Add network connection audit (open ports, suspicious connections)"
  echo "- Add software update check"

} >> "$LEARNINGS_FILE"

echo "  Learnings saved to: $LEARNINGS_FILE"
echo ""

# ─── Phase 6: Notifications for critical issues ───
echo "[Phase 6] Checking for critical alerts..."

LATEST_REPORT=$(ls -t "$REPORT_DIR"/health-*.md 2>/dev/null | head -1)
ALERT_MSG=""

if [ -n "$LATEST_REPORT" ]; then
  if grep -q "ISSUE: LOW MEMORY" "$LATEST_REPORT"; then
    ALERT_MSG="$ALERT_MSG\nLow memory detected!"
  fi
  if grep -q "ISSUE: DISK NEARLY FULL" "$LATEST_REPORT"; then
    ALERT_MSG="$ALERT_MSG\nDisk nearly full!"
  fi
  if grep -q "ISSUE: THERMAL WARNING" "$LATEST_REPORT"; then
    ALERT_MSG="$ALERT_MSG\nLaptop overheating!"
  fi
fi

if [ -n "$ALERT_MSG" ]; then
  osascript -e "display notification \"$ALERT_MSG\" with title \"System Health Alert\" subtitle \"Issues found — run /system-health for details\" sound name \"Basso\"" 2>/dev/null || true
  echo "  ALERT sent via macOS notification"
else
  osascript -e 'display notification "No critical issues found" with title "System Health" subtitle "Weekly check complete" sound name "Glass"' 2>/dev/null || true
  echo "  All clear — notification sent"
fi

# ─── Phase 7: Chrome extension re-sync check ───
echo ""
echo "[Phase 7] Chrome extension sync check..."
EXT_DIR="$CHROME_EXT_DIR"
DISABLED_DIR="$CHROME_DISABLED_DIR"

active_count=$(ls "$EXT_DIR" 2>/dev/null | wc -l | tr -d ' ')
disabled_count=$(ls "$DISABLED_DIR" 2>/dev/null | wc -l | tr -d ' ')

# Check if any disabled extension IDs reappeared in the active folder
if [ -d "$DISABLED_DIR" ]; then
  for disabled_ext in "$DISABLED_DIR"/*/; do
    ext_id=$(basename "$disabled_ext")
    if [ -d "$EXT_DIR/$ext_id" ]; then
      echo "  WARNING: Chrome re-synced disabled extension $ext_id — removing again"
      rm -rf "$EXT_DIR/$ext_id" 2>/dev/null
    fi
  done
fi
echo "  Active: $active_count | Disabled: $disabled_count"

# ─── Phase 8: Run full audit and save CSV for Google Sheet ───
echo ""
echo "[Phase 8] Running full audit for weekly sheet..."
bash "$HEALTH_DIR/full-audit.sh" --fix 2>&1

# ─── Phase 9: Simplify the audit for the easy-to-read sheet ───
echo ""
echo "[Phase 9] Creating simple language version..."
AUDIT_CSV="$REPORT_DIR/audit-$(date +%Y-%m-%d).csv"
SIMPLE_CSV="$REPORT_DIR/audit-$(date +%Y-%m-%d)-simple.csv"
if [ -f "$AUDIT_CSV" ]; then
  bash "$HEALTH_DIR/simplify-audit.sh" "$AUDIT_CSV" "$SIMPLE_CSV" 2>&1
  echo "  Simple report: $SIMPLE_CSV"
fi

echo ""
echo "=== Optimizer complete — $(date) ==="
echo "Technical CSV: $AUDIT_CSV"
echo "Simple CSV: $SIMPLE_CSV"
[ -n "$SHEET_ID" ] && echo "Google Sheet: $SHEET_URL"
