# System Health Agent

A self-improving system health monitor and security hardener for macOS and Windows.

Acts like a technician: finds problems, explains why they matter, shows the best fix, tells you what changes, and asks before acting.

## Architecture

```
config.sh           — All settings in one place (email, schedule, thresholds)
setup.sh            — Run once on new system to configure everything
health-check.sh     — Smart diagnostic: explains findings + recommends fixes
full-audit.sh       — 100+ point detailed audit → CSV
simplify-audit.sh   — Converts technical CSV → simple language
optimizer.sh        — Full pipeline: diagnose → fix → trend → learn → security → audit
firewall.sh         — Security status, hardening, network auto-guard
harden-now.sh       — One-command full security lockdown (sudo)
network-guard.sh    — Auto-hardens when you connect to any network
pf-rules.conf       — Advanced packet filter rules (brute force protection)
known-networks.txt  — Your trusted WiFi networks (auto-generated)
agent.md            — This file: capabilities + evolution roadmap
learnings.md        — Auto-updated knowledge base from past runs
reports/            — Timestamped reports, CSVs, security backups
windows/            — Windows PowerShell equivalents
```

## How It Runs

| Trigger | What Happens |
|---------|-------------|
| `./health-check.sh` | Smart health report with explanations |
| `./health-check.sh --fix` | Interactive: explains each fix, asks before applying |
| `./health-check.sh --auto-fix` | Unattended: fixes everything (for cron/launchd) |
| `./firewall.sh` | Show security status |
| `./firewall.sh --harden` | Apply full security hardening |
| `sudo ./harden-now.sh` | One-command security lockdown |
| `./optimizer.sh` | Full optimization pipeline (10 phases) |
| `./full-audit.sh` | Detailed 100+ point audit |
| `./setup.sh` | Configure for a new system |
| `/system-health` in Claude Code | Interactive health check via skill |
| **Weekly launchd** | Automatic optimization (day/time set in config.sh) |
| **Network change** | Auto-verifies firewall, kills bad services, alerts on unknown WiFi |

## Technician Philosophy

The agent doesn't just dump data. For every finding it:
1. **Explains what's wrong** in plain language
2. **Says why it matters** — the real-world impact
3. **Shows the best fix** available
4. **Tells you what changes** if the fix is applied
5. **Asks permission** before changing anything (--fix mode)
6. **Gives a health score**: HEALTHY / MOSTLY OK / NEEDS ATTENTION

## Capabilities

### Health Checks
- [x] Memory usage + top consumers + swap detection
- [x] Disk usage + cache sizes + Trash size
- [x] Electron app bloatware detection (configurable list)
- [x] Idle running apps (not used in 7+ days)
- [x] Launch agent audit
- [x] Thermal + battery health with replacement guidance
- [x] Chrome extension count + sync-back detection
- [x] SSD health + SMART status
- [x] Large file finder with keep/delete suggestions
- [x] Google Sheet integration (simple language reports)
- [x] Process count + load average
- [x] Never-opened installed apps
- [x] macOS update check

### Security Checks (new)
- [x] Application Firewall + stealth mode
- [x] Remote Management (ARD) detection
- [x] VNC/Screen Sharing detection
- [x] SSH status
- [x] FileVault encryption
- [x] System Integrity Protection (SIP)
- [x] Gatekeeper
- [x] Failed login attempt tracking
- [x] Foreign connection monitoring
- [x] Time Machine backup status
- [x] Open port audit

### Security Hardening (new)
- [x] One-command firewall + stealth mode activation
- [x] ARD/VNC/SSH deactivation
- [x] Advanced packet filter (pf) with brute force protection
- [x] Network auto-guard (re-hardens on every network change)
- [x] Unknown WiFi network alerts
- [x] Captive portal auto-join prevention
- [x] Privacy settings (screen lock, file extensions, crash reports)
- [x] Pre-hardening backup + undo support
- [x] AirDrop/AirPlay/Handoff preserved (smart blocking)

### Auto-Fix (--fix mode)
- [x] Kill configurable bloatware apps
- [x] Clean app caches (configurable list)
- [x] Empty trash above threshold
- [x] Quit apps unused for 7+ days
- [x] Re-disable Chrome extensions that sync back
- [x] Clean old logs
- [x] Re-enable firewall if turned off

### Self-Improvement
- [x] Trend analysis across recent reports
- [x] Learnings file auto-updated each run
- [x] Recommendations for next version generated
- [x] macOS notifications for critical alerts
- [x] Security verification on every weekly run (Phase 10)

## Portability
- All settings in config.sh — no hardcoded paths or emails
- setup.sh handles first-time configuration
- Each system gets its own Google Sheet and email
- Works on any macOS (Apple Silicon & Intel)
- Windows equivalents in windows/ directory

## Roadmap (Planned)

- [ ] Fan speed / CPU temperature tracking (via `powermetrics`)
- [ ] Memory pressure trend graphs
- [ ] Smart scheduling: run more often when issues detected, less when stable
- [ ] Disk I/O monitoring (detect thrashing)
- [ ] Auto-upload CSV to Google Sheet without Claude (using Google Sheets API)
- [x] Windows security hardening equivalent
- [ ] Network speed test integration
- [ ] DNS-over-HTTPS enforcement

## How to Evolve This Agent

When running `/system-health`, Claude should:
1. Read `learnings.md` for known patterns
2. Read recent reports for trends
3. If a recurring issue appears 3+ times, add a permanent fix
4. Update this `agent.md` to check off completed roadmap items
5. Add new roadmap items based on discovered issues
