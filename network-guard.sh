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
    # On unknown networks, ensure stealth mode is on (stay invisible)
    # Don't use --setblockall — it kills AirDrop/AirPlay
    sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on 2>/dev/null
    log "Stealth mode enforced for unknown network"
  fi
fi

log "Network guard check complete"
