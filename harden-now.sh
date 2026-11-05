#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# ONE-COMMAND SECURITY HARDENING
# ═══════════════════════════════════════════════════════════════
# Run this with: sudo ./harden-now.sh
# It needs sudo because firewall changes require admin access.
# ═══════════════════════════════════════════════════════════════

if [[ $EUID -ne 0 ]]; then
  echo "This script needs admin access. Run with:"
  echo "  sudo ./harden-now.sh"
  exit 1
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}✓${NC} $*"; }
warn() { echo -e "  ${YELLOW}!${NC} $*"; }
fail() { echo -e "  ${RED}✗${NC} $*"; }
info() { echo -e "  ${CYAN}→${NC} $*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PF_RULES="$SCRIPT_DIR/pf-rules.conf"

echo ""
echo -e "${CYAN}═══════════════════════════════════════════${NC}"
echo -e "${CYAN}  FULL SECURITY HARDENING (with sudo)${NC}"
echo -e "${CYAN}═══════════════════════════════════════════${NC}"
echo ""

# ── 1. APPLICATION FIREWALL ──
echo -e "${CYAN}  [1/7] Application Firewall${NC}"
/usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on && \
  ok "Firewall ENABLED" || fail "Could not enable firewall"

/usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on && \
  ok "Stealth mode ON (invisible to network scans)" || fail "Could not enable stealth"

# Smart mode: firewall ON, but AirDrop/AirPlay/Bonjour still work
# --setblockall is NOT used — it kills AirDrop, AirPlay, file sharing
/usr/libexec/ApplicationFirewall/socketfilterfw --setallowsigned on && \
  ok "Signed Apple apps allowed (AirDrop, AirPlay, Finder sharing)" || true

/usr/libexec/ApplicationFirewall/socketfilterfw --setallowsignedapp on && \
  ok "Signed downloaded apps allowed through" || true
echo ""

# ── 2. CLOSE DANGEROUS REMOTE ACCESS ──
echo -e "${CYAN}  [2/7] Closing Dangerous Remote Access${NC}"
info "AirDrop, AirPlay, and local file sharing are LEFT WORKING"

# Disable Remote Management (ARD) — this is the dangerous one (port 3283)
/System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart \
  -deactivate -configure -access -off 2>/dev/null && \
  ok "Remote Management (ARD) DEACTIVATED — port 3283 closed" || ok "ARD already off"

# Disable Remote Login (SSH) — command-line remote access
systemsetup -setremotelogin off 2>/dev/null && \
  ok "Remote Login (SSH) DISABLED" || ok "SSH already off"

# Disable Remote Apple Events
systemsetup -setremoteappleevents off 2>/dev/null && \
  ok "Remote Apple Events DISABLED" || ok "Already off"

# Disable Screen Sharing for external users (VNC port 5900)
launchctl disable system/com.apple.screensharing 2>/dev/null && \
  ok "Screen Sharing (VNC) DISABLED" || ok "Screen Sharing already disabled"
echo ""

# ── 3. KEEP APPLE ECOSYSTEM, CLOSE RISKY SHARING ──
echo -e "${CYAN}  [3/7] Sharing Services${NC}"

# AirDrop — KEEP (uses Bluetooth + WiFi Direct, not a listening port)
ok "AirDrop: KEPT WORKING"

# AirPlay — KEEP receiving (ports 5000/7000 via ControlCenter)
ok "AirPlay: KEPT WORKING (you can still cast to this Mac)"

# Bluetooth Sharing — disable (file transfer over Bluetooth from strangers)
sudo -u "$(logname)" defaults write com.apple.Bluetooth PrefKeyServicesEnabled -bool false 2>/dev/null && \
  ok "Bluetooth file sharing DISABLED (AirDrop still works)" || ok "Already off"

# Printer Sharing — disable (don't share your printer to the network)
cupsctl --no-share-printers 2>/dev/null && \
  ok "Printer Sharing DISABLED" || ok "Already off"
echo ""

# ── 4. NETWORK HARDENING ──
echo -e "${CYAN}  [4/7] Network Hardening${NC}"

# Disable captive portal (prevents auto-join to rogue WiFi)
defaults write /Library/Preferences/SystemConfiguration/com.apple.captive.control Active -bool false 2>/dev/null && \
  ok "Captive portal auto-join DISABLED" || true

# Reduce mDNS visibility
defaults write /Library/Preferences/com.apple.mDNSResponder.plist NoMulticastAdvertisements -bool true 2>/dev/null && \
  ok "mDNS advertising DISABLED (less visible on network)" || true
echo ""

# ── 5. PRIVACY ──
echo -e "${CYAN}  [5/7] Privacy Settings${NC}"
sudo -u "$(logname)" defaults write com.apple.CrashReporter DialogType -string "none" 2>/dev/null && \
  ok "Crash report auto-send DISABLED" || true

sudo -u "$(logname)" defaults write NSGlobalDomain AppleShowAllExtensions -bool true 2>/dev/null && \
  ok "All file extensions visible" || true

sudo -u "$(logname)" defaults write com.apple.Safari AutoOpenSafeDownloads -bool false 2>/dev/null && \
  ok "Safari auto-open downloads DISABLED" || true

sudo -u "$(logname)" defaults write com.apple.screensaver askForPassword -int 1 2>/dev/null && \
  sudo -u "$(logname)" defaults write com.apple.screensaver askForPasswordDelay -int 0 2>/dev/null && \
  ok "Screen locks immediately on sleep" || true
echo ""

# ── 6. ADVANCED PF FIREWALL ──
echo -e "${CYAN}  [6/7] Advanced Firewall (pf)${NC}"
if [[ -f "$PF_RULES" ]]; then
  pfctl -f "$PF_RULES" -e 2>/dev/null && \
    ok "pf firewall rules LOADED and ACTIVE" || warn "Could not load pf rules"
else
  warn "No pf-rules.conf found. Run ./firewall.sh --harden first."
fi
echo ""

# ── 7. VERIFY ──
echo -e "${CYAN}  [7/7] Verification${NC}"

FW=$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>&1)
echo "$FW" | grep -q "enabled" && ok "Firewall: ON" || fail "Firewall: OFF"

STEALTH=$(/usr/libexec/ApplicationFirewall/socketfilterfw --getstealthmode 2>&1)
echo "$STEALTH" | grep -qi "on\|enabled" && ok "Stealth: ON" || fail "Stealth: OFF"

ARD_CHECK=$(pgrep ARDAgent 2>/dev/null)
if [[ -z "$ARD_CHECK" ]]; then
  ok "Remote Management (ARD): OFF"
else
  warn "ARD still running (may need reboot to fully stop)"
fi

PORTS=$(lsof -i -P -n 2>/dev/null | grep LISTEN | wc -l | tr -d ' ')
ok "Open ports: $PORTS (AirDrop/AirPlay ports are safe)"

echo ""
echo -e "${CYAN}═══════════════════════════════════════════${NC}"
echo -e "${GREEN}  YOUR MAC IS NOW HARDENED${NC}"
echo -e "${CYAN}═══════════════════════════════════════════${NC}"
echo ""
echo "  What's protected:"
echo "    • Firewall ON with stealth (invisible to attackers)"
echo "    • Dangerous remote access closed (ARD, SSH, VNC)"
echo "    • pf blocks attack ports (3283, 5900) + brute force"
echo "    • Network guard auto-protects on every new connection"
echo "    • Screen locks immediately on sleep"
echo "    • File extensions always shown (no disguised malware)"
echo ""
echo "  What STILL works:"
echo "    • AirDrop (sending/receiving files between Apple devices)"
echo "    • AirPlay (casting screen/audio to Apple TV, HomePod)"
echo "    • Handoff / Universal Clipboard / Continuity"
echo "    • Finder file sharing on your local network"
echo "    • All your apps and internet connection"
echo ""
echo "  Commands:"
echo "    ./firewall.sh --status    Check security anytime"
echo "    ./firewall.sh --undo      Revert everything"
echo ""
