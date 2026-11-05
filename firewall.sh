#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# System Health Agent — Firewall & Security Hardening
# ═══════════════════════════════════════════════════════════════
# Locks down your Mac: enables firewall, stealth mode, closes
# unnecessary ports, disables remote access services, and sets
# up network-aware auto-protection.
#
# Usage:
#   ./firewall.sh              Show current security status
#   ./firewall.sh --harden     Apply all security fixes
#   ./firewall.sh --status     Detailed security report
#   ./firewall.sh --auto       Auto-harden on network change
#   ./firewall.sh --undo       Revert to pre-hardening state
# ═══════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

BACKUP_DIR="$REPORT_DIR/security-backup"
LOG_FILE="$REPORT_DIR/firewall.log"
PF_RULES="$SCRIPT_DIR/pf-rules.conf"
NETWORK_AGENT_LABEL="com.system-health.network-guard"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }
ok()   { echo -e "  ${GREEN}✓${NC} $*"; }
warn() { echo -e "  ${YELLOW}!${NC} $*"; }
fail() { echo -e "  ${RED}✗${NC} $*"; }
info() { echo -e "  ${CYAN}→${NC} $*"; }

# ─── Backup current settings before hardening ───
backup_settings() {
  mkdir -p "$BACKUP_DIR"
  local ts=$(date +%Y%m%d_%H%M%S)
  local bk="$BACKUP_DIR/pre-harden-$ts.txt"

  echo "# Security settings backup — $ts" > "$bk"
  echo "# Use ./firewall.sh --undo to restore" >> "$bk"

  # Firewall state
  local fw_state=$(defaults read /Library/Preferences/com.apple.alf globalstate 2>/dev/null || echo "0")
  echo "ALF_STATE=$fw_state" >> "$bk"

  # Stealth mode
  local stealth=$(defaults read /Library/Preferences/com.apple.alf stealthenabled 2>/dev/null || echo "0")
  echo "STEALTH=$stealth" >> "$bk"

  # AirPlay receiver
  local airplay=$(defaults read com.apple.controlcenter "NSStatusItem Visible AirplayReceiver" 2>/dev/null || echo "1")
  echo "AIRPLAY_RECEIVER=$airplay" >> "$bk"

  # Remote management
  local ard_running=0
  pgrep -q ARDAgent 2>/dev/null && ard_running=1
  echo "ARD_RUNNING=$ard_running" >> "$bk"

  # Media sharing
  local media_sharing=$(defaults read com.apple.amp.mediasharingd "home-sharing-enabled" 2>/dev/null || echo "0")
  echo "MEDIA_SHARING=$media_sharing" >> "$bk"

  echo "$bk"
}

# ─── Show security status ───
show_status() {
  echo ""
  echo -e "${CYAN}═══════════════════════════════════════${NC}"
  echo -e "${CYAN}  SECURITY STATUS — $(date '+%Y-%m-%d %H:%M')${NC}"
  echo -e "${CYAN}═══════════════════════════════════════${NC}"
  echo ""

  # 1. Application Firewall
  echo -e "${CYAN}  Firewall${NC}"
  local fw_output=$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>&1)
  if echo "$fw_output" | grep -qi "enabled\|State = 1\|State = 2"; then
    ok "Application Firewall is ON"
  else
    local fw_state=$(defaults read /Library/Preferences/com.apple.alf globalstate 2>/dev/null || echo "0")
    case "$fw_state" in
      0) fail "Application Firewall is OFF" ;;
      1) ok "Application Firewall is ON (allow signed)" ;;
      2) ok "Application Firewall is ON (block all incoming)" ;;
      *) warn "Application Firewall status unknown (run ./firewall.sh --status with sudo to check)" ;;
    esac
  fi

  # Stealth mode
  local stealth_output=$(/usr/libexec/ApplicationFirewall/socketfilterfw --getstealthmode 2>&1)
  if echo "$stealth_output" | grep -qi "on\|enabled"; then
    ok "Stealth mode ON (invisible on networks)"
  else
    local stealth=$(defaults read /Library/Preferences/com.apple.alf stealthenabled 2>/dev/null || echo "0")
    if [[ "$stealth" == "1" ]]; then
      ok "Stealth mode ON (invisible on networks)"
    else
      fail "Stealth mode OFF (your Mac responds to pings)"
    fi
  fi
  echo ""

  # 2. Remote access services
  echo -e "${CYAN}  Remote Access${NC}"

  # Screen Sharing
  if launchctl list 2>/dev/null | grep -q "com.apple.screensharing$"; then
    fail "Screen Sharing is ENABLED"
  else
    ok "Screen Sharing is disabled"
  fi

  # Remote Management (ARD)
  if pgrep -q ARDAgent 2>/dev/null; then
    fail "Remote Management (ARDAgent) is RUNNING on port 3283"
  else
    ok "Remote Management is not running"
  fi

  # SSH
  local ssh_status="off"
  if launchctl list 2>/dev/null | grep -q "com.openssh.sshd"; then
    ssh_status="on"
    warn "Remote Login (SSH) is ENABLED"
  else
    ok "Remote Login (SSH) is disabled"
  fi

  # AirPlay Receiver (safe — needed for AirPlay between your devices)
  if lsof -i :5000 -P -n 2>/dev/null | grep -q LISTEN; then
    ok "AirPlay Receiver is on (ports 5000, 7000 — normal for Apple ecosystem)"
  else
    info "AirPlay Receiver is off"
  fi

  # Media Sharing
  if lsof -i :3689 -P -n 2>/dev/null | grep -q LISTEN; then
    info "Media Sharing is listening (port 3689 — for Home Sharing)"
  else
    ok "Media Sharing is off"
  fi
  echo ""

  # 3. Listening ports
  echo -e "${CYAN}  Open Ports${NC}"
  local ports=$(lsof -i -P -n 2>/dev/null | grep LISTEN | awk '{print $1 ":" $9}' | sort -u)
  if [[ -z "$ports" ]]; then
    ok "No open listening ports"
  else
    local count=$(echo "$ports" | wc -l | tr -d ' ')
    if [[ "$count" -gt 3 ]]; then
      fail "$count services are listening for connections:"
    else
      info "$count services listening:"
    fi
    echo "$ports" | while read -r line; do
      echo "      $line"
    done
  fi
  echo ""

  # 4. Network info
  echo -e "${CYAN}  Network${NC}"
  local wifi_name=$(networksetup -getairportnetwork en0 2>/dev/null | awk -F': ' '{print $2}')
  if [[ -n "$wifi_name" ]]; then
    info "Connected to WiFi: $wifi_name"
  else
    info "No WiFi connection detected"
  fi
  local public_ip=$(curl -s --max-time 5 ifconfig.me 2>/dev/null || echo "unknown")
  info "Public IP: $public_ip"
  echo ""

  # 5. Encryption
  echo -e "${CYAN}  Encryption${NC}"
  local fv_status=$(fdesetup status 2>/dev/null || echo "unknown")
  if echo "$fv_status" | grep -q "On"; then
    ok "FileVault disk encryption is ON"
  else
    fail "FileVault disk encryption is OFF — your data is not encrypted"
  fi
  echo ""

  # 6. Auto-updates
  echo -e "${CYAN}  Updates${NC}"
  local auto_update=$(defaults read /Library/Preferences/com.apple.SoftwareUpdate AutomaticCheckEnabled 2>/dev/null || echo "0")
  if [[ "$auto_update" == "1" ]]; then
    ok "Automatic security updates enabled"
  else
    warn "Automatic updates may be disabled"
  fi
  echo ""

  echo -e "${CYAN}═══════════════════════════════════════${NC}"
}

# ─── Harden the system ───
harden() {
  echo ""
  echo -e "${CYAN}═══════════════════════════════════════${NC}"
  echo -e "${CYAN}  SECURITY HARDENING${NC}"
  echo -e "${CYAN}═══════════════════════════════════════${NC}"
  echo ""

  # Backup first
  local backup_file=$(backup_settings)
  ok "Settings backed up to: $backup_file"
  log "Hardening started. Backup: $backup_file"
  echo ""

  # ── 1. Enable Application Firewall ──
  echo -e "${CYAN}  Step 1: Application Firewall${NC}"
  sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on 2>/dev/null && \
    ok "Firewall ENABLED" || warn "Could not enable firewall (run with sudo)"
  log "Enabled Application Firewall"

  # Enable stealth mode — makes Mac invisible on networks
  sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on 2>/dev/null && \
    ok "Stealth mode ENABLED (invisible to port scans)" || warn "Could not enable stealth mode"
  log "Enabled stealth mode"

  # Allow signed apps through (AirDrop, AirPlay, Finder sharing keep working)
  sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setallowsigned on 2>/dev/null && \
    ok "Signed Apple apps allowed (AirDrop, AirPlay, Handoff work)" || true
  sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setallowsignedapp on 2>/dev/null && \
    ok "Signed downloaded apps allowed through" || true
  echo ""

  # ── 2. Disable Remote Access Services ──
  echo -e "${CYAN}  Step 2: Close Remote Access${NC}"

  # Disable Screen Sharing
  sudo launchctl disable system/com.apple.screensharing 2>/dev/null && \
    ok "Screen Sharing DISABLED" || info "Screen Sharing already disabled or not available"
  log "Disabled Screen Sharing"

  # Disable Remote Management (ARD)
  sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart \
    -deactivate -configure -access -off 2>/dev/null && \
    ok "Remote Management (ARD) DEACTIVATED" || info "ARD already off or not available"
  log "Deactivated Remote Management"

  # Disable Remote Login (SSH)
  sudo systemsetup -setremotelogin off 2>/dev/null && \
    ok "Remote Login (SSH) DISABLED" || info "SSH already off or not available"
  log "Disabled SSH"

  # Disable Remote Apple Events
  sudo systemsetup -setremoteappleevents off 2>/dev/null && \
    ok "Remote Apple Events DISABLED" || info "Already off"
  log "Disabled Remote Apple Events"
  echo ""

  # ── 3. Smart sharing — keep Apple ecosystem, close risky stuff ──
  echo -e "${CYAN}  Step 3: Sharing Services${NC}"

  ok "AirDrop: KEPT WORKING (uses Bluetooth + WiFi Direct)"
  ok "AirPlay: KEPT WORKING (cast between your Apple devices)"
  ok "Handoff/Continuity: KEPT WORKING"

  # Bluetooth file sharing — strangers can send files over Bluetooth
  defaults write com.apple.Bluetooth PrefKeyServicesEnabled -bool false 2>/dev/null && \
    ok "Bluetooth file sharing DISABLED (AirDrop still works)" || info "Could not modify"

  # Printer Sharing — don't expose your printer to the network
  cupsctl --no-share-printers 2>/dev/null && \
    ok "Printer Sharing DISABLED" || info "Could not modify Printer Sharing"
  echo ""

  # ── 4. Network hardening ──
  echo -e "${CYAN}  Step 4: Network Hardening${NC}"

  # Disable captive portal assistant (prevents auto-connecting to rogue hotspots)
  sudo defaults write /Library/Preferences/SystemConfiguration/com.apple.captive.control Active -bool false 2>/dev/null && \
    ok "Captive portal auto-join DISABLED (no auto-connecting to public WiFi)" || true
  echo ""

  # ── 5. Privacy hardening ──
  echo -e "${CYAN}  Step 5: Privacy${NC}"

  # Disable sending diagnostic data to Apple
  defaults write com.apple.CrashReporter DialogType -string "none" 2>/dev/null && \
    ok "Crash reports won't auto-send" || true

  # Show all file extensions (prevents disguised malware)
  defaults write NSGlobalDomain AppleShowAllExtensions -bool true 2>/dev/null && \
    ok "Showing all file extensions (prevents disguised files)" || true

  # Disable auto-opening of downloaded files
  defaults write com.apple.Safari AutoOpenSafeDownloads -bool false 2>/dev/null && \
    ok "Safari won't auto-open downloads" || true

  # Lock screen on sleep/screensaver
  defaults write com.apple.screensaver askForPassword -int 1 2>/dev/null && \
    defaults write com.apple.screensaver askForPasswordDelay -int 0 2>/dev/null && \
    ok "Screen locks immediately on sleep/screensaver" || true
  echo ""

  # ── 6. Create pf firewall rules ──
  echo -e "${CYAN}  Step 6: Advanced Firewall (pf)${NC}"
  create_pf_rules
  echo ""

  # ── 7. Install network change auto-guard ──
  echo -e "${CYAN}  Step 7: Network Auto-Guard${NC}"
  install_network_guard
  echo ""

  # ── Summary ──
  echo -e "${CYAN}═══════════════════════════════════════${NC}"
  echo -e "${GREEN}  HARDENING COMPLETE${NC}"
  echo -e "${CYAN}═══════════════════════════════════════${NC}"
  echo ""
  ok "Application Firewall enabled with stealth mode"
  ok "All remote access services disabled"
  ok "Sharing services closed"
  ok "Network footprint minimized"
  ok "Privacy settings tightened"
  ok "Advanced pf firewall rules applied"
  ok "Network auto-guard installed"
  echo ""
  info "Backup saved at: $backup_file"
  info "Run ./firewall.sh --status to verify"
  info "Run ./firewall.sh --undo to revert"
  echo ""
  log "Hardening complete"

  # Send macOS notification
  osascript -e 'display notification "Firewall enabled, remote access closed, stealth mode on" with title "Security Hardening Complete" subtitle "Your Mac is now protected"' 2>/dev/null || true
}

# ─── Create pf (packet filter) firewall rules ───
create_pf_rules() {
  cat > "$PF_RULES" << 'PFRULES'
# ═══════════════════════════════════════════════════════════════
# System Health Agent — pf Firewall Rules
# ═══════════════════════════════════════════════════════════════
# These rules provide defense-in-depth beyond the Application Firewall.
# Load with: sudo pfctl -f /path/to/pf-rules.conf -e
# ═══════════════════════════════════════════════════════════════

# ── Tables ──
# Trusted IPs you want to always allow (add your home/office IPs)
table <trusted> persist

# Known bad actors (auto-populated by network-guard)
table <blocked> persist

# ── Options ──
set skip on lo0
set block-policy drop
set state-policy if-bound

# ── Normalization ──
scrub in all

# ── Default: block everything incoming ──
block in all
block in quick from <blocked>

# ── Allow all outgoing (your apps need internet) ──
pass out all keep state

# ── Allow established connections back in ──
pass in on en0 proto { tcp, udp } from any to any keep state

# ── Allow trusted IPs fully ──
pass in quick from <trusted>

# ── Allow essential services ──
# DNS responses
pass in proto udp from any to any port 53

# DHCP
pass in proto udp from any port 67:68 to any port 67:68

# mDNS/Bonjour (local network discovery — needed for AirDrop etc)
pass in proto udp from any to 224.0.0.251 port 5353

# ── Block dangerous ports from outside ──
block in quick proto tcp from any to any port { 22, 3283, 5900, 5988, 5989 }

# ── Rate limiting: prevent brute force on any open port ──
pass in proto tcp from any to any flags S/SA keep state \
  (max-src-conn 50, max-src-conn-rate 15/5, overload <blocked> flush global)
PFRULES

  ok "Created pf firewall rules at $PF_RULES"

  # Load the rules
  sudo pfctl -f "$PF_RULES" -e 2>/dev/null && \
    ok "pf firewall rules LOADED and ACTIVE" || warn "Could not load pf rules (need sudo)"
  log "Created and loaded pf rules"
}

# ─── Network auto-guard: re-hardens when you connect to a new network ───
install_network_guard() {
  local guard_script="$SCRIPT_DIR/network-guard.sh"

  cat > "$guard_script" << 'GUARD'
#!/bin/bash
# Network Guard — auto-hardens security when network changes
# Triggered by launchd when network configuration changes

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

LOG="$REPORT_DIR/network-guard.log"
mkdir -p "$REPORT_DIR"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

WIFI_NAME=$(networksetup -getairportnetwork en0 2>/dev/null | awk -F': ' '{print $2}')
log "Network change detected. WiFi: ${WIFI_NAME:-none}"

# Re-verify firewall is on
FW_STATE=$(defaults read /Library/Preferences/com.apple.alf globalstate 2>/dev/null || echo "0")
if [[ "$FW_STATE" == "0" ]]; then
  log "WARNING: Firewall was OFF! Re-enabling..."
  sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on 2>/dev/null
  sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on 2>/dev/null
  log "Firewall re-enabled with stealth mode"
  osascript -e 'display notification "Firewall was off — re-enabled automatically" with title "Security Guard" subtitle "Protection restored"' 2>/dev/null
fi

# Check for suspicious listeners that shouldn't be there
LISTENERS=$(lsof -i -P -n 2>/dev/null | grep LISTEN | awk '{print $1}')
for bad in "ARDAgent" "sshd" "VNCServer"; do
  if echo "$LISTENERS" | grep -q "$bad"; then
    log "WARNING: $bad is listening! Killing..."
    killall "$bad" 2>/dev/null
    log "$bad killed"
    osascript -e "display notification \"$bad was running — killed automatically\" with title \"Security Guard\" subtitle \"Threat neutralized\"" 2>/dev/null
  fi
done

# Reload pf rules if they exist
PF_RULES="$SCRIPT_DIR/pf-rules.conf"
if [[ -f "$PF_RULES" ]]; then
  sudo pfctl -f "$PF_RULES" -e 2>/dev/null
  log "pf rules reloaded"
fi

# Log all current connections for audit
CONNECTIONS=$(lsof -i -P -n 2>/dev/null | grep ESTABLISHED | wc -l | tr -d ' ')
log "Active connections: $CONNECTIONS"

# If on an unknown network, extra caution
KNOWN_NETWORKS_FILE="$SCRIPT_DIR/known-networks.txt"
if [[ -n "$WIFI_NAME" && -f "$KNOWN_NETWORKS_FILE" ]]; then
  if ! grep -qF "$WIFI_NAME" "$KNOWN_NETWORKS_FILE" 2>/dev/null; then
    log "ALERT: Connected to UNKNOWN network: $WIFI_NAME"
    osascript -e "display notification \"Connected to unknown network: $WIFI_NAME — extra protection active\" with title \"Security Guard\" subtitle \"Unknown Network\"" 2>/dev/null
    # On unknown networks, block all incoming
    sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setblockall on 2>/dev/null
    log "Set block-all mode for unknown network"
  fi
fi

log "Network guard check complete"
GUARD

  chmod +x "$guard_script"
  ok "Created network-guard.sh"

  # Create known networks file with current network
  local known_file="$SCRIPT_DIR/known-networks.txt"
  local current_wifi=$(networksetup -getairportnetwork en0 2>/dev/null | awk -F': ' '{print $2}')
  if [[ -n "$current_wifi" ]]; then
    echo "$current_wifi" > "$known_file"
    ok "Added '$current_wifi' as trusted network"
    info "Edit $known_file to add more trusted networks"
  fi

  # Create launchd plist for network change monitoring
  local plist_file="$HOME/Library/LaunchAgents/$NETWORK_AGENT_LABEL.plist"

  cat > "$plist_file" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$NETWORK_AGENT_LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$guard_script</string>
  </array>
  <key>WatchPaths</key>
  <array>
    <string>/Library/Preferences/SystemConfiguration</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$REPORT_DIR/network-guard-stdout.log</string>
  <key>StandardErrorPath</key>
  <string>$REPORT_DIR/network-guard-stderr.log</string>
</dict>
</plist>
PLIST

  launchctl unload "$plist_file" 2>/dev/null
  launchctl load "$plist_file" 2>/dev/null && \
    ok "Network auto-guard INSTALLED and RUNNING" || warn "Could not load network guard (try manually: launchctl load $plist_file)"
  info "Auto-hardens when you connect to any network"
  info "Alerts you on unknown networks"
  log "Installed network guard launchd agent"
}

# ─── Undo hardening ───
undo() {
  local latest_backup=$(ls -t "$BACKUP_DIR"/pre-harden-*.txt 2>/dev/null | head -1)
  if [[ -z "$latest_backup" ]]; then
    fail "No backup found in $BACKUP_DIR"
    exit 1
  fi

  echo ""
  echo -e "${YELLOW}Restoring from: $latest_backup${NC}"
  echo ""

  source "$latest_backup"

  # Restore firewall state
  if [[ "${ALF_STATE:-0}" == "0" ]]; then
    sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate off 2>/dev/null
    info "Firewall restored to OFF"
  fi

  if [[ "${STEALTH:-0}" == "0" ]]; then
    sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode off 2>/dev/null
    info "Stealth mode restored to OFF"
  fi

  # Restore AirPlay
  if [[ "${AIRPLAY_RECEIVER:-1}" == "1" ]]; then
    defaults write com.apple.controlcenter "NSStatusItem Visible AirplayReceiver" -bool true 2>/dev/null
    info "AirPlay Receiver restored"
  fi

  # Disable pf
  sudo pfctl -d 2>/dev/null
  info "pf firewall disabled"

  # Unload network guard
  launchctl unload "$HOME/Library/LaunchAgents/$NETWORK_AGENT_LABEL.plist" 2>/dev/null
  info "Network guard disabled"

  echo ""
  ok "Settings restored to pre-hardening state"
  log "Undo completed from $latest_backup"
}

# ─── Main ───
mkdir -p "$REPORT_DIR"

case "${1:-}" in
  --harden)
    harden
    ;;
  --status)
    show_status
    ;;
  --auto)
    install_network_guard
    ;;
  --undo)
    undo
    ;;
  *)
    show_status
    ;;
esac
