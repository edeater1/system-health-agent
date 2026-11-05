#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# System Health Agent — Setup
# ═══════════════════════════════════════════════════════════════
# Run this once on a new system to configure everything.
# Usage: ./setup.sh [--email you@email.com] [--day 5] [--hour 12]
#
# What it does:
#   1. Asks your email (or pass --email)
#   2. Updates config.sh with your settings
#   3. Creates the weekly launchd schedule
#   4. Creates report directories
#   5. Makes all scripts executable
#   6. Runs a test audit to verify everything works
#
# To change settings later: edit config.sh and re-run setup.sh
# ═══════════════════════════════════════════════════════════════

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# ─── Parse arguments ───
NEW_EMAIL=""
NEW_DAY=""
NEW_HOUR=""
NEW_MINUTE=""
NEW_SHEET=""
SKIP_TEST=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --email)   NEW_EMAIL="$2"; shift 2 ;;
    --day)     NEW_DAY="$2"; shift 2 ;;
    --hour)    NEW_HOUR="$2"; shift 2 ;;
    --minute)  NEW_MINUTE="$2"; shift 2 ;;
    --sheet)   NEW_SHEET="$2"; shift 2 ;;
    --no-test) SKIP_TEST=true; shift ;;
    --help|-h)
      echo "Usage: ./setup.sh [options]"
      echo ""
      echo "Options:"
      echo "  --email EMAIL    Your Google account email for the sheet"
      echo "  --sheet ID       Google Sheet ID (leave empty to create new)"
      echo "  --day N          Schedule day: 1=Mon .. 5=Fri .. 7=Sun (default: 5)"
      echo "  --hour N         Schedule hour in 24h format (default: 12)"
      echo "  --minute N       Schedule minute (default: 0)"
      echo "  --no-test        Skip the test audit at the end"
      echo "  --help           Show this help"
      exit 0
      ;;
    *) echo "Unknown option: $1. Use --help for usage."; exit 1 ;;
  esac
done

echo "═══════════════════════════════════════"
echo "  System Health Agent — Setup"
echo "═══════════════════════════════════════"
echo ""
echo "  Machine: $MACHINE_NAME"
echo "  Chip:    $CHIP"
echo "  RAM:     ${TOTAL_RAM}GB"
echo ""

# ─── Step 1: Email ───
if [ -z "$NEW_EMAIL" ]; then
  echo "Current email: $OWNER_EMAIL"
  read -p "Your Google account email (press Enter to keep current): " NEW_EMAIL
fi

if [ -n "$NEW_EMAIL" ]; then
  sed -i '' "s|^OWNER_EMAIL=.*|OWNER_EMAIL=\"$NEW_EMAIL\"|" "$SCRIPT_DIR/config.sh"
  OWNER_EMAIL="$NEW_EMAIL"
  echo "  Email set to: $OWNER_EMAIL"
else
  echo "  Email unchanged: $OWNER_EMAIL"
fi

# ─── Step 2: Sheet ID ───
if [ -n "$NEW_SHEET" ]; then
  sed -i '' "s|^SHEET_ID=.*|SHEET_ID=\"$NEW_SHEET\"|" "$SCRIPT_DIR/config.sh"
  SHEET_ID="$NEW_SHEET"
  echo "  Sheet ID set to: $SHEET_ID"
else
  echo "  Sheet ID unchanged: $SHEET_ID"
  echo "  (To use a different sheet, re-run with --sheet YOUR_SHEET_ID)"
  echo "  (To create a new sheet, clear the ID in config.sh and use Claude)"
fi

# ─── Step 3: Schedule ───
[ -n "$NEW_DAY" ] && sed -i '' "s|^SCHEDULE_DAY=.*|SCHEDULE_DAY=$NEW_DAY|" "$SCRIPT_DIR/config.sh" && SCHEDULE_DAY="$NEW_DAY"
[ -n "$NEW_HOUR" ] && sed -i '' "s|^SCHEDULE_HOUR=.*|SCHEDULE_HOUR=$NEW_HOUR|" "$SCRIPT_DIR/config.sh" && SCHEDULE_HOUR="$NEW_HOUR"
[ -n "$NEW_MINUTE" ] && sed -i '' "s|^SCHEDULE_MINUTE=.*|SCHEDULE_MINUTE=$NEW_MINUTE|" "$SCRIPT_DIR/config.sh" && SCHEDULE_MINUTE="$NEW_MINUTE"

DAYS=("" "Monday" "Tuesday" "Wednesday" "Thursday" "Friday" "Saturday" "Sunday")
echo "  Schedule: ${DAYS[$SCHEDULE_DAY]} at $(printf '%02d:%02d' "$SCHEDULE_HOUR" "$SCHEDULE_MINUTE")"

# ─── Step 4: Create directories ───
mkdir -p "$REPORT_DIR"
echo "  Reports dir: $REPORT_DIR"

# ─── Step 5: Make scripts executable ───
chmod +x "$SCRIPT_DIR"/*.sh
echo "  Scripts: made executable"

# ─── Step 6: Install launchd schedule ───
PLIST_PATH="$HOME/Library/LaunchAgents/${SCHEDULE_LABEL}.plist"

# Unload existing if present
launchctl unload "$PLIST_PATH" 2>/dev/null || true

cat > "$PLIST_PATH" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${SCHEDULE_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${SCRIPT_DIR}/optimizer.sh</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Weekday</key>
        <integer>${SCHEDULE_DAY}</integer>
        <key>Hour</key>
        <integer>${SCHEDULE_HOUR}</integer>
        <key>Minute</key>
        <integer>${SCHEDULE_MINUTE}</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>${REPORT_DIR}/launchd-stdout.log</string>
    <key>StandardErrorPath</key>
    <string>${REPORT_DIR}/launchd-stderr.log</string>
    <key>RunAtLoad</key>
    <false/>
</dict>
</plist>
PLIST

launchctl load "$PLIST_PATH" 2>/dev/null || true
echo "  launchd: installed at $PLIST_PATH"

# ─── Step 7: Update sheet-config.json ───
cat > "$SCRIPT_DIR/sheet-config.json" << JSON
{
  "sheet_id": "$SHEET_ID",
  "sheet_url": "https://docs.google.com/spreadsheets/d/$SHEET_ID/edit",
  "owner": "$OWNER_EMAIL",
  "machine": "$MACHINE_NAME",
  "schedule": "${DAYS[$SCHEDULE_DAY]} $(printf '%02d:%02d' "$SCHEDULE_HOUR" "$SCHEDULE_MINUTE")",
  "setup_date": "$(date +%Y-%m-%d)"
}
JSON
echo "  Config saved: sheet-config.json"

# ─── Step 8: Test run ───
if ! $SKIP_TEST; then
  echo ""
  echo "Running test audit..."
  echo ""
  bash "$SCRIPT_DIR/health-check.sh" 2>&1
  echo ""
  echo "Test complete. Check report above."
fi

echo ""
echo "═══════════════════════════════════════"
echo "  Setup Complete!"
echo "═══════════════════════════════════════"
echo ""
echo "  Email:    $OWNER_EMAIL"
echo "  Sheet:    https://docs.google.com/spreadsheets/d/$SHEET_ID/edit"
echo "  Schedule: ${DAYS[$SCHEDULE_DAY]} $(printf '%02d:%02d' "$SCHEDULE_HOUR" "$SCHEDULE_MINUTE")"
echo "  Reports:  $REPORT_DIR"
echo ""
echo "  Quick commands:"
echo "    ./health-check.sh          Run a quick health check"
echo "    ./health-check.sh --fix    Check + auto-fix issues"
echo "    ./optimizer.sh             Full optimization (what runs weekly)"
echo "    ./full-audit.sh            Detailed 100+ point audit"
echo ""
echo "  To change settings later:"
echo "    Edit config.sh, then re-run ./setup.sh"
echo ""
