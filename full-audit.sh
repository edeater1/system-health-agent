#!/bin/bash
# Full System Audit — comprehensive 100+ point check
# Outputs CSV data for Google Sheets integration
# Usage: ./full-audit.sh [--csv output.csv] [--fix]

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/config.sh"

FIX=false
CSV_FILE=""
mkdir -p "$REPORT_DIR"
TIMESTAMP=$(date +"%Y-%m-%d %H:%M")
DATE_SHORT=$(date +"%Y-%m-%d")

for arg in "$@"; do
  case "$arg" in
    --fix) FIX=true ;;
    --csv) shift_next=true ;;
    *) if [ "${shift_next:-false}" = true ]; then CSV_FILE="$arg"; shift_next=false; fi ;;
  esac
done

[ -z "$CSV_FILE" ] && CSV_FILE="$REPORT_DIR/audit-$DATE_SHORT.csv"

# ═══════════════════════════════════════
# Data collection functions
# ═══════════════════════════════════════

collect_memory() {
  local mem_line=$(top -l 1 -s 0 2>/dev/null | grep PhysMem)
  local total=$(sysctl -n hw.memsize | awk '{printf "%.0f", $1/1024/1024/1024}')
  local used=$(echo "$mem_line" | awk '{print $2}' | tr -d 'G')
  local free_raw=$(echo "$mem_line" | awk -F',' '{print $2}' | awk '{print $1}')
  local free_mb
  if echo "$free_raw" | grep -q 'G'; then
    free_mb=$(echo "$free_raw" | tr -d 'G' | awk '{printf "%.0f", $1*1024}')
  else
    free_mb=$(echo "$free_raw" | tr -d 'M ')
  fi
  local wired=$(vm_stat | grep "wired" | head -1 | awk '{print $4}' | tr -d '.')
  local wired_mb=$((wired * 16384 / 1024 / 1024))
  local compressed=$(vm_stat | grep "occupied by compressor" | awk '{print $5}' | tr -d '.')
  local compressed_mb=$((compressed * 16384 / 1024 / 1024))
  local proc_count=$(ps -e | wc -l | tr -d ' ')
  local thread_count=$(top -l 1 -s 0 | grep "Processes:" | awk -F',' '{for(i=1;i<=NF;i++) if($i ~ /thread/) print $i}' | awk '{print $1}')

  local status="OK"
  [ "${free_mb:-0}" -lt 2000 ] 2>/dev/null && status="CRITICAL"
  [ "${free_mb:-0}" -lt 4000 ] 2>/dev/null && [ "$status" = "OK" ] && status="WARNING"

  echo "Memory,Total RAM,${total}GB,,$status"
  echo "Memory,Used,${used}GB,,"
  echo "Memory,Free,${free_mb}MB,,"
  echo "Memory,Wired (kernel),${wired_mb}MB,Cannot be freed,"
  echo "Memory,Compressed,${compressed_mb}MB,,"
  echo "Memory,Processes,${proc_count},,"
  echo "Memory,Threads,${thread_count:-N/A},,"
}

collect_top_memory_apps() {
  ps -eo rss,comm -m | awk 'NR>1 {mb=$1/1024; if(mb>100) printf "Memory Apps,%s,%.0f MB,,\n", $2, mb}' | \
    sed 's|/Applications/||g; s|/Contents/.*||g; s|/System/Library/.*/||g; s|/Users/[^/]*/||g' | head -10
}

collect_disk() {
  local disk_total=$(df -h / | awk 'NR==2 {print $2}')
  local disk_used=$(df -h / | awk 'NR==2 {print $3}')
  local disk_free=$(df -h / | awk 'NR==2 {print $4}')
  local disk_pct=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')

  local status="OK"
  [ "$disk_pct" -gt 90 ] && status="CRITICAL"
  [ "$disk_pct" -gt 80 ] && [ "$status" = "OK" ] && status="WARNING"

  echo "Disk,Total,$disk_total,,$status"
  echo "Disk,Used,$disk_used,${disk_pct}% used,"
  echo "Disk,Free,$disk_free,,"

  # Cache sizes
  local user_cache=$(du -sm ~/Library/Caches 2>/dev/null | cut -f1)
  local trash_size=$(du -sm ~/.Trash 2>/dev/null | cut -f1 || echo 0)
  local downloads=$(du -sm ~/Downloads 2>/dev/null | cut -f1)
  local logs_size=$(du -sm ~/Library/Logs 2>/dev/null | cut -f1)

  echo "Disk,User Caches,${user_cache}MB,$([ "$user_cache" -gt 2000 ] && echo "Clean recommended" || echo "Normal"),"
  echo "Disk,Trash,${trash_size:-0}MB,$([ "${trash_size:-0}" -gt 500 ] && echo "Empty recommended" || echo "Normal"),"
  echo "Disk,Downloads,${downloads}MB,,INFO"
  echo "Disk,Logs,${logs_size}MB,,INFO"
}

collect_large_files() {
  # Find large files in user directories
  find ~/Downloads ~/Desktop ~/Documents -maxdepth 2 -size +100M -type f 2>/dev/null | while read f; do
    local size=$(du -sh "$f" 2>/dev/null | cut -f1)
    local age=$(( ($(date +%s) - $(stat -f %m "$f" 2>/dev/null || echo $(date +%s))) / 86400 ))
    local suggestion="Keep"
    local ext="${f##*.}"
    case "$ext" in
      dmg|pkg|iso|zip|tar|gz) suggestion="Remove (installer)" ;;
      tmp|log|bak) suggestion="Remove (temp)" ;;
    esac
    [ "$age" -gt 90 ] && suggestion="Review (${age}d old)"
    echo "Large Files,$(basename "$f"),$size,${age}d old,$suggestion"
  done | head -15
}

collect_ssd_health() {
  local smart_status=$(system_profiler SPStorageDataType 2>/dev/null | grep "SMART Status" | awk -F': ' '{print $2}' | head -1)
  local disk_type=$(system_profiler SPStorageDataType 2>/dev/null | grep "Medium Type" | awk -F': ' '{print $2}' | head -1)
  local protocol=$(system_profiler SPNVMeDataType 2>/dev/null | grep "Link Width" | awk -F': ' '{print $2}' | head -1)

  local status="OK"
  [ "$smart_status" != "Verified" ] && status="WARNING"

  echo "SSD Health,SMART Status,${smart_status:-N/A},,$status"
  echo "SSD Health,Type,${disk_type:-SSD},,"
  echo "SSD Health,NVMe Link,${protocol:-N/A},,"

  # Read/Write stats
  local disk_reads=$(iostat -d 2>/dev/null | awk 'NR==3 {print $1}')
  local disk_writes=$(iostat -d 2>/dev/null | awk 'NR==3 {print $2}')
  echo "SSD Health,KB/s Read,${disk_reads:-N/A},,"
  echo "SSD Health,KB/s Write,${disk_writes:-N/A},,"
}

collect_battery() {
  local cycle_count=$(system_profiler SPPowerDataType 2>/dev/null | grep "Cycle Count" | awk '{print $NF}')
  local condition=$(system_profiler SPPowerDataType 2>/dev/null | grep "Condition" | awk -F': ' '{print $2}')
  local max_capacity=$(system_profiler SPPowerDataType 2>/dev/null | grep "Maximum Capacity" | awk -F': ' '{print $2}')
  local charging=$(system_profiler SPPowerDataType 2>/dev/null | grep "Charging" | head -1 | awk -F': ' '{print $2}')
  local charge_pct=$(pmset -g batt 2>/dev/null | grep -o '[0-9]*%' | head -1)
  local power_source=$(pmset -g batt 2>/dev/null | head -1 | grep -o "'.*'" | tr -d "'")

  local status="OK"
  [ -n "$cycle_count" ] && [ "$cycle_count" -gt 800 ] 2>/dev/null && status="WARNING"
  [ -n "$cycle_count" ] && [ "$cycle_count" -gt 1000 ] 2>/dev/null && status="CRITICAL"
  [ "$condition" != "Normal" ] 2>/dev/null && status="WARNING"

  echo "Battery,Cycle Count,${cycle_count:-N/A},Max 1000 recommended,$status"
  echo "Battery,Condition,${condition:-N/A},,"
  echo "Battery,Max Capacity,${max_capacity:-N/A},,"
  echo "Battery,Current Charge,${charge_pct:-N/A},,"
  echo "Battery,Power Source,${power_source:-N/A},,"
  echo "Battery,Charging,${charging:-N/A},,"
}

collect_chip() {
  local chip=$(sysctl -n machdep.cpu.brand_string 2>/dev/null)
  local cores=$(sysctl -n hw.ncpu 2>/dev/null)
  local perf_cores=$(sysctl -n hw.perflevel0.physicalcpu 2>/dev/null || echo "N/A")
  local eff_cores=$(sysctl -n hw.perflevel1.physicalcpu 2>/dev/null || echo "N/A")
  local load=$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}')
  local cpu_usage=$(top -l 1 -s 0 | grep "CPU usage" | awk '{print $3}' | tr -d '%')

  local status="OK"
  # Load > cores count means overloaded
  [ -n "$load" ] && [ -n "$cores" ] && \
    python3 -c "exit(0 if float('$load') > float('$cores') else 1)" 2>/dev/null && status="WARNING"

  echo "Chip/CPU,Model,${chip:-N/A},,$status"
  echo "Chip/CPU,Total Cores,$cores,P:$perf_cores E:$eff_cores,"
  echo "Chip/CPU,Load Average,$load,,"
  echo "Chip/CPU,CPU Usage,${cpu_usage:-N/A}%,,"
}

collect_thermal() {
  local thermal_ok=$(pmset -g therm 2>/dev/null | grep -c "No thermal warning" || true)
  local status="OK"
  [ "$thermal_ok" -eq 0 ] && status="CRITICAL"

  echo "Thermal,Warning,$([ "$thermal_ok" -gt 0 ] && echo "None" || echo "ACTIVE"),,$status"

  # Fan speed if available
  local fan=$(pmset -g therm 2>/dev/null | grep "Fan" | head -1)
  echo "Thermal,Fan,${fan:-Auto},,"
}

collect_network() {
  local wifi_name=$(/System/Library/PrivateFrameworks/Apple80211.framework/Resources/airport -I 2>/dev/null | grep ' SSID' | awk -F': ' '{print $2}')
  local wifi_rssi=$(/System/Library/PrivateFrameworks/Apple80211.framework/Resources/airport -I 2>/dev/null | grep 'agrCtlRSSI' | awk -F': ' '{print $2}')
  local wifi_noise=$(/System/Library/PrivateFrameworks/Apple80211.framework/Resources/airport -I 2>/dev/null | grep 'agrCtlNoise' | awk -F': ' '{print $2}')
  local ip=$(ipconfig getifaddr en0 2>/dev/null || echo "N/A")
  local public_ip=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || echo "N/A")
  local dns=$(scutil --dns 2>/dev/null | grep "nameserver\[0\]" | head -1 | awk '{print $3}')

  local wifi_status="OK"
  [ -n "$wifi_rssi" ] && [ "$wifi_rssi" -lt -70 ] 2>/dev/null && wifi_status="WARNING"
  [ -n "$wifi_rssi" ] && [ "$wifi_rssi" -lt -80 ] 2>/dev/null && wifi_status="CRITICAL"

  echo "Network,WiFi SSID,${wifi_name:-Disconnected},,"
  echo "Network,Signal Strength,${wifi_rssi:-N/A} dBm,$([ -n "$wifi_rssi" ] && echo "Good: > -60 Fair: -60 to -70" || echo ""),${wifi_status}"
  echo "Network,Noise,${wifi_noise:-N/A} dBm,,"
  echo "Network,Local IP,$ip,,"
  echo "Network,Public IP,$public_ip,,"
  echo "Network,DNS Server,${dns:-N/A},,"

  # Open listening ports
  local open_ports=$(lsof -iTCP -sTCP:LISTEN -P -n 2>/dev/null | awk 'NR>1 {print $9}' | sort -u | tr '\n' ' ')
  echo "Network,Listening Ports,${open_ports:-None},,"
}

collect_security() {
  # Firewall
  local firewall=$(defaults read /Library/Preferences/com.apple.alf globalstate 2>/dev/null || echo "unknown")
  local fw_text
  case "$firewall" in
    0) fw_text="OFF"; fw_status="CRITICAL" ;;
    1) fw_text="ON (specific services)"; fw_status="OK" ;;
    2) fw_text="ON (block all)"; fw_status="OK" ;;
    *) fw_text="Unknown"; fw_status="WARNING" ;;
  esac
  echo "Security,Firewall,$fw_text,,$fw_status"

  # FileVault
  local fv=$(fdesetup status 2>/dev/null | head -1)
  local fv_status="OK"
  echo "$fv" | grep -q "Off" && fv_status="CRITICAL"
  echo "Security,FileVault,${fv:-Unknown},,$fv_status"

  # SIP (System Integrity Protection)
  local sip=$(csrutil status 2>/dev/null | awk -F': ' '{print $2}' | tr -d '.')
  local sip_status="OK"
  echo "$sip" | grep -qi "disabled" && sip_status="CRITICAL"
  echo "Security,SIP,${sip:-Unknown},,$sip_status"

  # Gatekeeper
  local gk=$(spctl --status 2>/dev/null)
  local gk_status="OK"
  echo "$gk" | grep -q "disabled" && gk_status="WARNING"
  echo "Security,Gatekeeper,${gk:-Unknown},,$gk_status"

  # XProtect last update
  local xprotect_ver=$(system_profiler SPInstallHistoryDataType 2>/dev/null | grep -A2 "XProtect" | grep "Version" | tail -1 | awk -F': ' '{print $2}')
  echo "Security,XProtect Version,${xprotect_ver:-N/A},,"

  # Failed login attempts
  local failed_logins=$(log show --predicate 'eventMessage CONTAINS "Authentication failed"' --last 7d 2>/dev/null | grep -c "Authentication failed" || echo "0")
  local login_status="OK"
  [ "$failed_logins" -gt 10 ] && login_status="WARNING"
  [ "$failed_logins" -gt 50 ] && login_status="CRITICAL"
  echo "Security,Failed Logins (7d),$failed_logins,,$login_status"

  # SSH access check
  local ssh_enabled=$(systemsetup -getremotelogin 2>/dev/null | grep -c "On" || echo "0")
  echo "Security,Remote Login (SSH),$([ "$ssh_enabled" -gt 0 ] && echo "ENABLED" || echo "Disabled"),$([ "$ssh_enabled" -gt 0 ] && echo "Disable if not needed" || echo ""),$([ "$ssh_enabled" -gt 0 ] && echo "WARNING" || echo "OK")"

  # Screen sharing
  local screen_sharing=$(launchctl list 2>/dev/null | grep -c "com.apple.screensharing" || echo "0")
  echo "Security,Screen Sharing,$([ "$screen_sharing" -gt 0 ] && echo "ENABLED" || echo "Disabled"),,"

  # Recent sudo usage
  local sudo_count=$(log show --predicate 'process == "sudo"' --last 7d 2>/dev/null | grep -c "sudo" || echo "N/A")
  echo "Security,Sudo Events (7d),${sudo_count},,"

  # Unsigned/suspicious processes
  local unsigned=$(ps -eo comm | while read cmd; do
    [ -f "$cmd" ] && codesign -v "$cmd" 2>&1 | grep -q "not signed" && echo "$cmd"
  done 2>/dev/null | wc -l | tr -d ' ')
  echo "Security,Unsigned Processes,${unsigned:-0},,"
}

collect_intrusion_check() {
  # Check for unauthorized access attempts
  local ssh_attempts=$(grep -c "Failed" /var/log/system.log 2>/dev/null || echo "0")

  # Check for new user accounts
  local user_count=$(dscl . -list /Users | grep -v "^_" | wc -l | tr -d ' ')
  echo "Intrusion,User Accounts,$user_count,,"

  # Check for recently modified system files
  local sys_modified=$(find /usr/local/bin /usr/local/sbin -newer /etc/passwd -type f 2>/dev/null | wc -l | tr -d ' ')
  echo "Intrusion,Modified System Files,${sys_modified:-0},Since last passwd change,"

  # Check for unusual network connections
  local active_connections=$(netstat -an 2>/dev/null | grep ESTABLISHED | wc -l | tr -d ' ')
  local foreign_connections=$(netstat -an 2>/dev/null | grep ESTABLISHED | awk '{print $5}' | grep -v "127.0.0.1\|::1\|\*\." | sort -u | wc -l | tr -d ' ')
  echo "Intrusion,Active Connections,$active_connections,,"
  echo "Intrusion,Foreign Connections,$foreign_connections,Review if unexpected,$([ "$foreign_connections" -gt 20 ] && echo "WARNING" || echo "INFO")"

  # Check for recently installed apps (last 7 days)
  local new_apps=$(find /Applications -maxdepth 1 -name "*.app" -newer /tmp -mtime -7 -type d 2>/dev/null | wc -l | tr -d ' ')
  echo "Intrusion,New Apps (7d),${new_apps:-0},,"

  # Check for login at unusual hours (midnight-5am)
  local odd_logins=$(last -10 2>/dev/null | grep -E "0[0-4]:" | wc -l | tr -d ' ')
  echo "Intrusion,Odd-Hour Logins,${odd_logins:-0},Between 12am-5am,$([ "${odd_logins:-0}" -gt 0 ] && echo "INFO" || echo "OK")"
}

collect_hardware() {
  # Model info
  local model=$(sysctl -n hw.model 2>/dev/null)
  local os_ver=$(sw_vers -productVersion 2>/dev/null)
  local os_build=$(sw_vers -buildVersion 2>/dev/null)
  local uptime_str=$(uptime | awk -F'up ' '{print $2}' | awk -F',' '{print $1}')

  echo "Hardware,Model,$model,,"
  echo "Hardware,macOS,$os_ver ($os_build),,"
  echo "Hardware,Uptime,$uptime_str,,"

  # GPU
  local gpu=$(system_profiler SPDisplaysDataType 2>/dev/null | grep "Chipset Model" | awk -F': ' '{print $2}')
  local gpu_cores=$(system_profiler SPDisplaysDataType 2>/dev/null | grep "Total Number of Cores" | awk -F': ' '{print $2}')
  echo "Hardware,GPU,${gpu:-Integrated},${gpu_cores:-N/A} cores,"

  # Display
  local resolution=$(system_profiler SPDisplaysDataType 2>/dev/null | grep "Resolution" | head -1 | awk -F': ' '{print $2}')
  echo "Hardware,Display,${resolution:-N/A},,"

  # Bluetooth
  local bt=$(system_profiler SPBluetoothDataType 2>/dev/null | grep "State" | head -1 | awk -F': ' '{print $2}')
  echo "Hardware,Bluetooth,${bt:-N/A},,"

  # USB devices
  local usb_count=$(system_profiler SPUSBDataType 2>/dev/null | grep -c "Product ID" || echo "0")
  echo "Hardware,USB Devices,$usb_count,,"

  # Thunderbolt
  local tb=$(system_profiler SPThunderboltDataType 2>/dev/null | grep "Device Name" | head -1 | awk -F': ' '{print $2}')
  echo "Hardware,Thunderbolt,${tb:-No devices},,"
}

collect_chrome_extensions() {
  local active=$(ls ~/Library/Application\ Support/Google/Chrome/Default/Extensions/ 2>/dev/null | wc -l | tr -d ' ')
  local disabled=$(ls ~/Library/Application\ Support/Google/Chrome/Disabled-Extensions/ 2>/dev/null | wc -l | tr -d ' ')
  echo "Chrome,Active Extensions,$active,,"
  echo "Chrome,Disabled Extensions,${disabled:-0},,"
}

collect_running_apps() {
  local apps=$(osascript -e 'tell application "System Events" to get name of every application process whose background only is false' 2>/dev/null || echo "")
  echo "$apps" | tr ',' '\n' | sed 's/^ //' | while IFS= read -r app; do
    [ -z "$app" ] && continue
    local mem=$(ps -eo rss,comm | grep -i "$(echo "$app" | head -c 15)" | awk '{sum+=$1} END {printf "%.0f", sum/1024}' 2>/dev/null)
    echo "Running Apps,$app,${mem:-0}MB,,"
  done
}

collect_caches_detail() {
  du -sm ~/Library/Caches/*/ 2>/dev/null | sort -rn | head -10 | while read size dir; do
    local name=$(basename "$dir")
    local suggestion="Keep"
    [ "$size" -gt 500 ] && suggestion="Clean recommended"
    [ "$size" -gt 1000 ] && suggestion="Clean strongly recommended"
    echo "Caches,$name,${size}MB,,$suggestion"
  done
}

# ═══════════════════════════════════════
# Run all checks and generate CSV
# ═══════════════════════════════════════

echo "Running full system audit..."

{
  echo "Category,Item,Value,Details,Status"
  echo "Report,Date,$TIMESTAMP,,"
  echo "Report,Type,Full System Audit,,"
  echo ""

  echo "# --- HARDWARE ---"
  collect_hardware
  collect_chip
  collect_thermal
  echo ""

  echo "# --- STORAGE ---"
  collect_ssd_health
  collect_disk
  collect_caches_detail
  collect_large_files
  echo ""

  echo "# --- MEMORY ---"
  collect_memory
  collect_top_memory_apps
  collect_running_apps
  echo ""

  echo "# --- BATTERY ---"
  collect_battery
  echo ""

  echo "# --- NETWORK ---"
  collect_network
  echo ""

  echo "# --- SECURITY ---"
  collect_security
  collect_intrusion_check
  echo ""

  echo "# --- BROWSER ---"
  collect_chrome_extensions

} | grep -v "^#" | grep -v "^$" > "$CSV_FILE"

echo ""
echo "Audit complete. CSV saved: $CSV_FILE"
echo "Rows: $(wc -l < "$CSV_FILE")"

# ═══════════════════════════════════════
# Auto-fix if requested
# ═══════════════════════════════════════

if $FIX; then
  echo ""
  echo "Running auto-fixes..."

  # Clean caches >500MB
  for d in ~/Library/Caches/Comet ~/Library/Caches/Adobe ~/Library/Caches/Codex; do
    [ -d "$d" ] && rm -rf "$d" && echo "  Cleaned: $(basename "$d")"
  done

  # Clean old logs
  find ~/Library/Logs -name "*.log" -mtime +7 -delete 2>/dev/null && echo "  Cleaned: old logs"

  # Empty trash if large
  local trash_mb=$(du -sm ~/.Trash 2>/dev/null | cut -f1 || echo 0)
  [ "${trash_mb:-0}" -gt 500 ] && rm -rf ~/.Trash/* 2>/dev/null && echo "  Emptied: Trash (${trash_mb}MB)"

  echo "Auto-fixes complete."
fi
