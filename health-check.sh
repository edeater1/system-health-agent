#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# System Health Agent — Smart Health Check
# ═══════════════════════════════════════════════════════════════
# Acts like a technician: finds problems, explains why they
# matter, shows what the fix does, and asks before changing.
#
# Usage:
#   ./health-check.sh              Check and report
#   ./health-check.sh --fix        Check + fix (asks before each)
#   ./health-check.sh --auto-fix   Check + fix (no asking, for cron)
#   ./health-check.sh --json       Output as JSON
# ═══════════════════════════════════════════════════════════════

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/config.sh"

FIX=false
AUTO_FIX=false
JSON=false
mkdir -p "$REPORT_DIR"

for arg in "$@"; do
  case "$arg" in
    --fix)      FIX=true ;;
    --auto-fix) FIX=true; AUTO_FIX=true ;;
    --json)     JSON=true ;;
  esac
done

TIMESTAMP=$(date +"%Y-%m-%d_%H-%M")
REPORT_FILE="$REPORT_DIR/health-$TIMESTAMP.md"
: > "$REPORT_FILE"

# ─── Colors ───
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ─── Finding storage ───
# Each finding: SEVERITY|TITLE|WHY_IT_MATTERS|FIX_DESC|WHAT_CHANGES|FIX_CMD|CATEGORY
declare -a FINDINGS=()
declare -a APPLIED_FIXES=()
FINDING_NUM=0

add_finding() {
  local severity="$1"  # CRITICAL, WARNING, INFO, GOOD
  local title="$2"
  local why="$3"
  local fix_desc="${4:-}"
  local what_changes="${5:-}"
  local fix_cmd="${6:-}"
  local category="${7:-General}"
  FINDING_NUM=$((FINDING_NUM + 1))
  FINDINGS+=("${severity}|${title}|${why}|${fix_desc}|${what_changes}|${fix_cmd}|${category}")
}

log() { echo "$1" >> "$REPORT_FILE"; }

# ─── Ask permission for a fix ───
ask_and_fix() {
  local title="$1"
  local fix_desc="$2"
  local what_changes="$3"
  local fix_cmd="$4"

  if [[ -z "$fix_cmd" ]]; then return; fi

  if $AUTO_FIX; then
    eval "$fix_cmd" 2>/dev/null && APPLIED_FIXES+=("$title") || true
    return
  fi

  echo ""
  echo -e "  ${CYAN}Fix available:${NC} $fix_desc"
  echo -e "  ${DIM}What changes: $what_changes${NC}"
  read -p "  Apply this fix? [y/N] " -n 1 -r reply </dev/tty
  echo ""
  if [[ "$reply" =~ ^[Yy]$ ]]; then
    eval "$fix_cmd" 2>/dev/null && APPLIED_FIXES+=("$title") || echo -e "  ${RED}Fix failed${NC}"
  else
    echo -e "  ${DIM}Skipped${NC}"
  fi
}

# ═══════════════════════════════════════════════════════════════
# CHECKS — a technician would examine all of these
# ═══════════════════════════════════════════════════════════════

echo ""
echo -e "${DIM}Scanning your Mac...${NC}"

# ─── Collect system info ───
mem_line=$(top -l 1 -s 0 2>/dev/null | grep PhysMem)
mem_used=$(echo "$mem_line" | awk '{print $2}' | tr -d 'G')
mem_free_raw=$(echo "$mem_line" | awk -F',' '{print $2}' | awk '{print $1}')
if echo "$mem_free_raw" | grep -q 'G'; then
  mem_free=$(echo "$mem_free_raw" | tr -d 'G' | awk '{printf "%.0f", $1*1024}')
else
  mem_free=$(echo "$mem_free_raw" | tr -d 'M')
fi
total_ram=$(sysctl -n hw.memsize | awk '{printf "%.0f", $1/1024/1024/1024}')

disk_pct=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
disk_free=$(df -h / | awk 'NR==2 {print $4}')
proc_count=$(ps -e | wc -l | tr -d ' ')
load=$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}')

log "# System Health Report — $(date '+%Y-%m-%d %H:%M')"
log "- Machine: $MACHINE_NAME | RAM: ${total_ram}GB | Chip: $CHIP"
log "- Memory: ${mem_used}GB used, ${mem_free}MB free"
log "- Disk: ${disk_pct}% used, ${disk_free} free"
log "- Processes: $proc_count | Load: $load"
log ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 1. SECURITY (a technician checks this FIRST)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Firewall
fw_output=$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>&1)
if echo "$fw_output" | grep -qi "enabled\|State = 1\|State = 2"; then
  add_finding "GOOD" "Firewall is ON" "" "" "" "" "Security"
else
  fw_state=$(defaults read /Library/Preferences/com.apple.alf globalstate 2>/dev/null || echo "0")
  if [[ "$fw_state" == "0" ]]; then
    add_finding "CRITICAL" "Firewall is OFF — your Mac is exposed to attacks" \
      "Without a firewall, anyone on the same WiFi network can try to connect to your Mac. On public WiFi (cafes, airports), this is especially dangerous — hackers scan for unprotected Macs." \
      "Turn on the firewall with stealth mode" \
      "Your Mac becomes invisible on networks. Apps you use still work normally. AirDrop, AirPlay, Finder sharing all keep working." \
      "sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on && sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on" \
      "Security"
  fi
fi

# Stealth mode
stealth_output=$(/usr/libexec/ApplicationFirewall/socketfilterfw --getstealthmode 2>&1)
if echo "$stealth_output" | grep -qi "on\|enabled"; then
  : # good
else
  stealth=$(defaults read /Library/Preferences/com.apple.alf stealthenabled 2>/dev/null || echo "0")
  if [[ "$stealth" != "1" ]]; then
    add_finding "WARNING" "Stealth mode is OFF — your Mac is visible to scans" \
      "When stealth mode is off, your Mac responds to 'ping' and port scans. Attackers use this to find targets on a network." \
      "Enable stealth mode" \
      "Your Mac stops responding to pings and port scans. Nobody on the network can see it. All your apps work the same." \
      "sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on" \
      "Security"
  fi
fi

# Remote Management (ARD)
if pgrep -q ARDAgent 2>/dev/null; then
  add_finding "CRITICAL" "Remote Management (ARD) is running — someone could control your Mac" \
    "Apple Remote Desktop agent is listening on port 3283. This lets anyone with the right credentials take full control of your Mac remotely — see your screen, move your mouse, access files." \
    "Deactivate Remote Management" \
    "Port 3283 closes. Nobody can remotely control your Mac. You can still use AirDrop, AirPlay, and screen sharing between your own devices via iCloud." \
    "sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart -deactivate -configure -access -off" \
    "Security"
fi

# VNC/Screen Sharing
if lsof -i :5900 -P -n 2>/dev/null | grep -q LISTEN; then
  add_finding "CRITICAL" "Screen Sharing (VNC) is open on port 5900" \
    "VNC lets someone view and control your screen remotely. If your password is weak or leaked, anyone on the internet could be watching your screen right now." \
    "Disable Screen Sharing" \
    "Port 5900 closes. No one can view your screen remotely. You can still share your screen in FaceTime and Zoom calls." \
    "sudo launchctl disable system/com.apple.screensharing" \
    "Security"
fi

# SSH
if launchctl list 2>/dev/null | grep -q "com.openssh.sshd"; then
  add_finding "WARNING" "Remote Login (SSH) is enabled" \
    "SSH lets someone access your Mac's terminal remotely. Unless you actively use SSH to connect to this Mac from another computer, it should be off." \
    "Disable Remote Login" \
    "Nobody can SSH into your Mac. You can still SSH OUT to servers from your terminal." \
    "sudo systemsetup -setremotelogin off" \
    "Security"
fi

# FileVault
filevault=$(fdesetup status 2>/dev/null | head -1 || echo "unknown")
if echo "$filevault" | grep -q "On"; then
  add_finding "GOOD" "FileVault disk encryption is ON" "" "" "" "" "Security"
else
  add_finding "CRITICAL" "FileVault is OFF — your files are NOT encrypted" \
    "If your laptop is stolen, anyone can read your files by connecting the drive to another computer. Passwords, documents, photos — all accessible." \
    "Enable FileVault encryption" \
    "Your entire disk gets encrypted. Takes a few hours in the background. Your Mac works normally during encryption. Only YOUR password can unlock the data." \
    "" \
    "Security"
fi

# SIP (System Integrity Protection)
sip_status=$(csrutil status 2>/dev/null || echo "unknown")
if echo "$sip_status" | grep -q "enabled"; then
  add_finding "GOOD" "System Integrity Protection (SIP) is ON" "" "" "" "" "Security"
else
  add_finding "CRITICAL" "System Integrity Protection (SIP) is DISABLED" \
    "SIP prevents malware from modifying core macOS system files. With SIP off, a virus could rewrite system components and become nearly impossible to remove." \
    "Re-enable SIP (requires Recovery Mode)" \
    "Restart → hold Power button → Recovery Mode → Terminal → 'csrutil enable' → restart. System files become protected again." \
    "" \
    "Security"
fi

# Gatekeeper
gatekeeper=$(spctl --status 2>/dev/null || echo "unknown")
if echo "$gatekeeper" | grep -q "enabled"; then
  add_finding "GOOD" "Gatekeeper is ON (blocks unverified apps)" "" "" "" "" "Security"
else
  add_finding "WARNING" "Gatekeeper is DISABLED — unverified apps can install freely" \
    "Gatekeeper checks that apps are from identified developers or the App Store. Without it, you could accidentally install malware disguised as a normal app." \
    "Re-enable Gatekeeper" \
    "Apps must be from identified developers to install. If you need a specific unsigned app, you can right-click → Open to allow just that one." \
    "sudo spctl --master-enable" \
    "Security"
fi

# Failed login attempts
failed_logins=0
failed_logins=$(log show --predicate 'eventMessage CONTAINS "Authentication failed"' --last 7d --style compact 2>/dev/null | wc -l | tr -d ' ')
if [[ "$failed_logins" -gt 50 ]]; then
  add_finding "CRITICAL" "$failed_logins failed login attempts in the last 7 days" \
    "This is far above normal (3-5 per week is typical). Could be a brute-force attack, a misconfigured app retrying authentication, or a stuck keychain prompt." \
    "Investigate the source of failed logins" \
    "Check which process is failing to authenticate. If it's an app, restart it. If it's external, the firewall + stealth mode will help." \
    "" \
    "Security"
elif [[ "$failed_logins" -gt 10 ]]; then
  add_finding "WARNING" "$failed_logins failed login attempts in the last 7 days" \
    "Slightly elevated. Usually caused by a mistyped password or an app with a saved wrong password. Worth watching." \
    "" "" "" "Security"
fi

# Foreign connections
foreign_conns=$(lsof -i -P -n 2>/dev/null | grep ESTABLISHED | grep -v "127.0.0.1\|::1\|192.168\|10\.\|172\.1[6-9]\.\|172\.2[0-9]\.\|172\.3[0-1]\." | wc -l | tr -d ' ')
if [[ "$foreign_conns" -gt 30 ]]; then
  add_finding "WARNING" "$foreign_conns connections to outside servers" \
    "Your Mac is talking to $foreign_conns external servers right now. This is high — could be normal (many browser tabs, Electron apps) or could include something unexpected." \
    "Run ./firewall.sh --status to see all connections" \
    "" "" "Security"
elif [[ "$foreign_conns" -gt 0 ]]; then
  add_finding "INFO" "$foreign_conns connections to outside servers" \
    "Normal. These are your apps talking to their servers (Chrome, Notion, Claude, etc.)." \
    "" "" "" "Security"
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 2. MEMORY & PERFORMANCE
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

if [[ "${mem_free}" -lt "$MEM_CRITICAL_MB" ]] 2>/dev/null; then
  add_finding "CRITICAL" "Memory almost full — only ${mem_free}MB free out of ${total_ram}GB" \
    "Your Mac is running out of working memory. Apps will freeze, become slow, and the system uses disk as overflow (called 'swap') which is 100x slower than RAM." \
    "Kill the biggest memory hog" \
    "" "" "Performance"

  # Find the biggest memory hog (from bloatware list)
  for app_name in "${BLOATWARE_APPS[@]}"; do
    count=$(ps -eo comm 2>/dev/null | grep -ic "$app_name" || true)
    if [[ "$count" -gt 5 ]]; then
      mem=$(ps -eo rss,comm | grep -i "$app_name" | awk '{sum+=$1} END {printf "%.0f", sum/1024}')
      add_finding "CRITICAL" "$app_name is eating ${mem}MB of memory ($count processes)" \
        "$app_name has spawned $count separate processes — this is an Electron app bug. It's using ${mem}MB, which is why your Mac feels slow." \
        "Force-quit $app_name" \
        "$app_name closes and you get ~${mem}MB of memory back. You can reopen it anytime — it will start fresh with less memory." \
        "pkill -f '$app_name'" \
        "Performance"
    fi
  done
elif [[ "${mem_free}" -lt "$MEM_WARNING_MB" ]] 2>/dev/null; then
  add_finding "WARNING" "Memory getting tight — ${mem_free}MB free" \
    "Not critical yet, but if you open more apps it will slow down. Close any apps you're not actively using." \
    "" "" "" "Performance"
else
  add_finding "GOOD" "Memory healthy — ${mem_free}MB free of ${total_ram}GB" "" "" "" "" "Performance"
fi

# Also check bloatware even if memory isn't critical
for app_name in Comet ChatGPT Codex Slack Discord Figma; do
  count=$(ps -eo comm 2>/dev/null | grep -ic "$app_name" || true)
  if [[ "$count" -gt 10 ]]; then
    mem=$(ps -eo rss,comm | grep -i "$app_name" | awk '{sum+=$1} END {printf "%.0f", sum/1024}')
    # Only add if we haven't already from the bloatware loop above
    exists=false
    for f in "${FINDINGS[@]}"; do
      echo "$f" | grep -q "$app_name is eating" && exists=true
    done
    if ! $exists; then
      add_finding "WARNING" "$app_name has $count processes using ${mem}MB" \
        "Electron apps like $app_name spawn many helper processes. $count is excessive." \
        "Quit $app_name to free ${mem}MB" \
        "$app_name closes. You get ~${mem}MB back. Reopen it when needed." \
        "pkill -f '$app_name'" \
        "Performance"
    fi
  fi
done

# Process count
if [[ "$proc_count" -gt "$PROC_WARNING" ]]; then
  add_finding "WARNING" "$proc_count processes running (normal is 300-400)" \
    "High process count slows everything down. Usually caused by Electron apps (Chrome, Slack, VS Code etc.) each spawning dozens of helper processes." \
    "" "" "" "Performance"
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 3. DISK & STORAGE
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

if [[ "$disk_pct" -gt "$DISK_CRITICAL_PCT" ]]; then
  add_finding "CRITICAL" "Disk nearly full — ${disk_pct}% used, only ${disk_free} left" \
    "Your Mac needs free disk space to work. When the disk fills up, apps crash, the system can't create temporary files, and macOS updates can't install." \
    "Clean up large files, caches, and Trash" \
    "" "" "Storage"
elif [[ "$disk_pct" -gt "$DISK_WARNING_PCT" ]]; then
  add_finding "WARNING" "Disk usage high — ${disk_pct}% used" \
    "Getting close to full. Time to clean up old files, empty Trash, and remove unused apps." \
    "" "" "" "Storage"
else
  add_finding "GOOD" "Disk healthy — ${disk_pct}% used, ${disk_free} free" "" "" "" "" "Storage"
fi

# Caches
user_cache=$(du -sm ~/Library/Caches 2>/dev/null | cut -f1)
if [[ "$user_cache" -gt "$CACHE_WARNING_MB" ]]; then
  add_finding "WARNING" "App caches are ${user_cache}MB" \
    "Apps store temporary data in caches to load faster. But over time they grow large and waste disk space. They rebuild automatically when cleaned." \
    "Clean app caches (${user_cache}MB)" \
    "Caches are deleted. Apps may load slightly slower the first time you open them, then return to normal. No data is lost." \
    "rm -rf ~/Library/Caches/Comet/ ~/Library/Caches/Adobe/ ~/Library/Caches/Codex/ ~/Library/Caches/com.openai.chat/ ~/Library/Caches/com.anthropic.claude/" \
    "Storage"
fi

# Trash
trash_size=$(du -sm ~/.Trash 2>/dev/null | cut -f1 || echo 0)
if [[ "${trash_size:-0}" -gt "$TRASH_AUTO_EMPTY_MB" ]]; then
  add_finding "INFO" "Trash has ${trash_size}MB of deleted files" \
    "Files in Trash still take up disk space until you empty it." \
    "Empty the Trash (free ${trash_size}MB)" \
    "Deleted files are permanently removed. You won't be able to recover them after this." \
    "rm -rf ~/.Trash/*" \
    "Storage"
fi

# Old downloads
old_downloads=$(find ~/Downloads -maxdepth 1 -mtime +30 -type f 2>/dev/null | wc -l | tr -d ' ')
if [[ "$old_downloads" -gt 10 ]]; then
  dl_size=$(du -sm ~/Downloads 2>/dev/null | cut -f1)
  add_finding "INFO" "$old_downloads old files in Downloads (${dl_size}MB total)" \
    "These files have been sitting in Downloads for over 30 days. Most are probably installers, PDFs, or images you already used." \
    "Review and delete old downloads" \
    "" "" "Storage"
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 4. BATTERY & HARDWARE
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Thermal
thermal_ok=$(pmset -g therm 2>/dev/null | grep -c "No thermal warning" || true)
if [[ "$thermal_ok" -eq 0 ]]; then
  add_finding "CRITICAL" "Your Mac is OVERHEATING" \
    "High temperature damages internal components and throttles performance. Your Mac slows itself down to avoid permanent damage." \
    "Close heavy apps, check if vents are blocked" \
    "CPU-heavy apps close. Your Mac cools down and returns to normal speed. Check that nothing is blocking the bottom or back vents." \
    "" \
    "Hardware"
else
  add_finding "GOOD" "Temperature normal — no overheating" "" "" "" "" "Hardware"
fi

# Battery
battery_cycles=$(system_profiler SPPowerDataType 2>/dev/null | grep "Cycle Count" | awk '{print $NF}' || echo "0")
battery_condition=$(system_profiler SPPowerDataType 2>/dev/null | grep "Condition" | awk -F': ' '{print $2}' || echo "Unknown")
battery_max=$(system_profiler SPPowerDataType 2>/dev/null | grep "Maximum Capacity" | awk -F': ' '{print $2}' || echo "Unknown")

if [[ -n "$battery_cycles" && "$battery_cycles" != "0" && "$battery_cycles" -gt "$BATTERY_CRITICAL_CYCLES" ]] 2>/dev/null; then
  add_finding "WARNING" "Battery has $battery_cycles charge cycles (max recommended: $BATTERY_CRITICAL_CYCLES)" \
    "Apple rates MacBook batteries for about $BATTERY_CRITICAL_CYCLES cycles. After that, the battery holds less charge. Condition: $battery_condition, Max capacity: $battery_max" \
    "Consider getting the battery replaced at Apple or an authorized service provider" \
    "A new battery costs ~₹15,000-20,000 and gives you back full battery life. Your Mac works fine on power until then." \
    "" "Hardware"
elif [[ -n "$battery_cycles" && "$battery_cycles" != "0" && "$battery_cycles" -gt "$BATTERY_WARNING_CYCLES" ]] 2>/dev/null; then
  add_finding "INFO" "Battery at $battery_cycles cycles — getting older but still fine" \
    "Current condition: $battery_condition, Max capacity: $battery_max. Apple rates batteries for about $BATTERY_CRITICAL_CYCLES cycles." \
    "" "" "" "Hardware"
else
  add_finding "GOOD" "Battery healthy — $battery_cycles cycles, condition: ${battery_condition:-Normal}" "" "" "" "" "Hardware"
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 5. SOFTWARE & UPDATES
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# macOS updates
updates_available=$(softwareupdate -l 2>&1 | grep -c "Label:" || echo "0")
if [[ "$updates_available" -gt 0 ]]; then
  add_finding "WARNING" "$updates_available macOS update(s) available" \
    "Updates often include security patches that fix known vulnerabilities. Delaying updates leaves your Mac exposed to attacks that Apple has already fixed." \
    "Install updates from System Settings → General → Software Update" \
    "Updates download and install. May require a restart. All your files and apps stay the same." \
    "" "Software"
fi

# Chrome extensions
ext_count=0
if [[ -d "$CHROME_EXT_DIR" ]]; then
  ext_count=$(ls "$CHROME_EXT_DIR" 2>/dev/null | wc -l | tr -d ' ')
fi
if [[ "$ext_count" -gt 20 ]]; then
  add_finding "WARNING" "Chrome has $ext_count extensions installed" \
    "Each extension can read your browsing data, slow Chrome down, and use memory. Some extensions are malware in disguise. Only keep ones you actively use." \
    "Review extensions at chrome://extensions" \
    "" "" "Software"
fi

# Idle running apps
running_apps=$(osascript -e 'tell application "System Events" to get name of every application process whose background only is false' 2>/dev/null || echo "")
idle_apps=""
if [[ -n "$running_apps" ]]; then
  while IFS= read -r app; do
    app=$(echo "$app" | xargs)
    [[ -z "$app" ]] && continue
    case "$app" in Finder|Terminal|"System Settings"|"Claude Code"|"Claude") continue ;; esac
    app_path="/Applications/$app.app"
    [[ ! -d "$app_path" ]] && continue
    last_used=$(mdls -name kMDItemLastUsedDate "$app_path" 2>/dev/null | awk -F'"' '{print $2}')
    if [[ -n "$last_used" && "$last_used" != "" ]]; then
      days_ago=$(( ($(date +%s) - $(date -j -f "%Y-%m-%d %H:%M:%S %z" "$last_used" +%s 2>/dev/null || echo $(date +%s))) / 86400 )) 2>/dev/null || continue
      if [[ "$days_ago" -gt 7 ]] 2>/dev/null; then
        idle_apps="$idle_apps, $app (${days_ago}d)"
      fi
    fi
  done <<< "$(echo "$running_apps" | tr ',' '\n' | sed 's/^ //')"
fi

if [[ -n "$idle_apps" ]]; then
  idle_apps="${idle_apps#, }"
  add_finding "INFO" "Apps running but not used in 7+ days: $idle_apps" \
    "These apps are open but you haven't actively used them in over a week. They're using memory and CPU in the background for nothing." \
    "Quit idle apps to free memory" \
    "These apps close. Any unsaved work in them would be lost (usually there isn't any for idle apps). You can reopen them anytime." \
    "" "Software"
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 6. BACKUP (a good technician always checks this)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

tm_status=$(tmutil currentphase 2>/dev/null || echo "unknown")
tm_dest=$(tmutil destinationinfo 2>/dev/null | grep "Name" | head -1 || echo "")
last_backup=$(tmutil latestbackup 2>/dev/null || echo "")

if [[ -z "$tm_dest" || -z "$last_backup" ]]; then
  add_finding "WARNING" "No Time Machine backup configured" \
    "If your Mac's drive fails, gets stolen, or a file is accidentally deleted, there's no backup to recover from. All your work, photos, and documents could be lost permanently." \
    "Connect an external drive and enable Time Machine in System Settings" \
    "Your Mac automatically backs up every hour when the drive is connected. If anything goes wrong, you can restore your entire Mac or individual files." \
    "" "Backup"
else
  # Check if backup is recent
  if [[ -n "$last_backup" ]]; then
    backup_date=$(basename "$last_backup" 2>/dev/null | head -c 10)
    add_finding "GOOD" "Time Machine backup active (last: $backup_date)" "" "" "" "" "Backup"
  fi
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# PRESENTATION — show findings like a technician
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo ""
echo -e "${BOLD}════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  SYSTEM HEALTH CHECK — $(date '+%Y-%m-%d %H:%M')${NC}"
echo -e "${BOLD}  $MACHINE_NAME | ${total_ram}GB RAM | $CHIP${NC}"
echo -e "${BOLD}════════════════════════════════════════════════${NC}"
echo ""
echo -e "  Memory: ${mem_used}GB / ${total_ram}GB (${mem_free}MB free)"
echo -e "  Disk:   ${disk_pct}% used (${disk_free} free)"
echo -e "  Load:   ${load} | Processes: $proc_count"

# Count by severity
critical=0; warnings=0; info_count=0; good=0
for f in "${FINDINGS[@]}"; do
  sev=$(echo "$f" | cut -d'|' -f1)
  case "$sev" in
    CRITICAL) critical=$((critical+1)) ;;
    WARNING) warnings=$((warnings+1)) ;;
    INFO) info_count=$((info_count+1)) ;;
    GOOD) good=$((good+1)) ;;
  esac
done

# ─── CRITICAL findings ───
if [[ $critical -gt 0 ]]; then
  echo ""
  echo -e "${RED}${BOLD}  ━━━ CRITICAL — Fix These Now ━━━━━━━━━━━━━━━${NC}"
  num=0
  for f in "${FINDINGS[@]}"; do
    sev=$(echo "$f" | cut -d'|' -f1)
    [[ "$sev" != "CRITICAL" ]] && continue
    num=$((num+1))

    title=$(echo "$f" | cut -d'|' -f2)
    why=$(echo "$f" | cut -d'|' -f3)
    fix_desc=$(echo "$f" | cut -d'|' -f4)
    what_changes=$(echo "$f" | cut -d'|' -f5)
    fix_cmd=$(echo "$f" | cut -d'|' -f6)

    echo ""
    echo -e "  ${RED}${BOLD}$num. $title${NC}"
    echo -e "  ${DIM}Why it matters: $why${NC}"
    if [[ -n "$fix_desc" ]]; then
      echo -e "  ${GREEN}Recommended fix: $fix_desc${NC}"
    fi
    if [[ -n "$what_changes" ]]; then
      echo -e "  ${DIM}What changes: $what_changes${NC}"
    fi

    log ""
    log "## CRITICAL: $title"
    log "Why: $why"
    [[ -n "$fix_desc" ]] && log "Fix: $fix_desc"

    if $FIX && [[ -n "$fix_cmd" ]]; then
      ask_and_fix "$title" "$fix_desc" "$what_changes" "$fix_cmd"
    fi
  done
fi

# ─── WARNING findings ───
if [[ $warnings -gt 0 ]]; then
  echo ""
  echo -e "${YELLOW}${BOLD}  ━━━ WARNINGS — Should Fix Soon ━━━━━━━━━━━━━${NC}"
  num=0
  for f in "${FINDINGS[@]}"; do
    sev=$(echo "$f" | cut -d'|' -f1)
    [[ "$sev" != "WARNING" ]] && continue
    num=$((num+1))

    title=$(echo "$f" | cut -d'|' -f2)
    why=$(echo "$f" | cut -d'|' -f3)
    fix_desc=$(echo "$f" | cut -d'|' -f4)
    what_changes=$(echo "$f" | cut -d'|' -f5)
    fix_cmd=$(echo "$f" | cut -d'|' -f6)

    echo ""
    echo -e "  ${YELLOW}${BOLD}$num. $title${NC}"
    echo -e "  ${DIM}$why${NC}"
    if [[ -n "$fix_desc" ]]; then
      echo -e "  ${GREEN}Fix: $fix_desc${NC}"
    fi

    log ""
    log "## WARNING: $title"
    log "Why: $why"

    if $FIX && [[ -n "$fix_cmd" ]]; then
      ask_and_fix "$title" "$fix_desc" "$what_changes" "$fix_cmd"
    fi
  done
fi

# ─── INFO findings ───
if [[ $info_count -gt 0 ]]; then
  echo ""
  echo -e "${CYAN}${BOLD}  ━━━ INFO — Worth Knowing ━━━━━━━━━━━━━━━━━━━${NC}"
  for f in "${FINDINGS[@]}"; do
    sev=$(echo "$f" | cut -d'|' -f1)
    [[ "$sev" != "INFO" ]] && continue
    title=$(echo "$f" | cut -d'|' -f2)
    why=$(echo "$f" | cut -d'|' -f3)
    echo -e "  ${CYAN}→${NC} $title"
    [[ -n "$why" ]] && echo -e "    ${DIM}$why${NC}"
    log "- INFO: $title"
  done
fi

# ─── GOOD findings ───
if [[ $good -gt 0 ]]; then
  echo ""
  echo -e "${GREEN}${BOLD}  ━━━ ALL GOOD ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  for f in "${FINDINGS[@]}"; do
    sev=$(echo "$f" | cut -d'|' -f1)
    [[ "$sev" != "GOOD" ]] && continue
    title=$(echo "$f" | cut -d'|' -f2)
    echo -e "  ${GREEN}✓${NC} $title"
    log "- GOOD: $title"
  done
fi

# ─── Applied fixes ───
if [[ ${#APPLIED_FIXES[@]} -gt 0 ]]; then
  echo ""
  echo -e "${GREEN}${BOLD}  ━━━ FIXES APPLIED ━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  for fix in "${APPLIED_FIXES[@]}"; do
    echo -e "  ${GREEN}✓${NC} Fixed: $fix"
    log "- FIXED: $fix"
  done
fi

# ─── Score ───
echo ""
echo -e "${BOLD}  ─────────────────────────────────────────────${NC}"
total=$((critical + warnings + info_count + good))
if [[ $critical -eq 0 && $warnings -eq 0 ]]; then
  echo -e "  ${GREEN}${BOLD}  Score: HEALTHY${NC}  ($good checks passed)"
elif [[ $critical -eq 0 ]]; then
  echo -e "  ${YELLOW}${BOLD}  Score: MOSTLY OK${NC}  ($warnings warning(s), $good checks passed)"
else
  echo -e "  ${RED}${BOLD}  Score: NEEDS ATTENTION${NC}  ($critical critical, $warnings warning(s))"
fi

if ! $FIX && [[ $((critical + warnings)) -gt 0 ]]; then
  echo ""
  echo -e "  ${CYAN}Run ${BOLD}./health-check.sh --fix${NC}${CYAN} to fix problems interactively${NC}"
fi

echo ""
echo -e "  Report saved: $REPORT_FILE"
echo -e "${BOLD}════════════════════════════════════════════════${NC}"

# Log summary
log ""
log "---"
log "## Summary"
log "- Critical: $critical | Warnings: $warnings | Info: $info_count | Good: $good"
log "- Fixes applied: ${#APPLIED_FIXES[@]}"

# macOS notification for critical issues
if [[ $critical -gt 0 ]]; then
  osascript -e "display notification \"$critical critical issue(s) found. Run health-check.sh --fix\" with title \"System Health\" subtitle \"Action Required\"" 2>/dev/null || true
fi
