# System Health Agent

A self-improving system health monitor for macOS (Apple Silicon).

## Architecture

```
config.sh         — All settings in one place (email, schedule, thresholds)
setup.sh          — Run once on new system to configure everything
health-check.sh   — Quick diagnostic (--fix for auto-repair)
full-audit.sh     — 100+ point detailed audit → CSV
simplify-audit.sh — Converts technical CSV → simple language
optimizer.sh      — Full pipeline: diagnose → fix → trend → learn → notify → audit
agent.md          — This file: capabilities + evolution roadmap
learnings.md      — Auto-updated knowledge base from past runs
reports/          — Timestamped health reports, CSVs, optimizer logs
```

## How It Runs

| Trigger | What Happens |
|---------|-------------|
| `./health-check.sh` | Quick health report |
| `./health-check.sh --fix` | Report + auto-fix |
| `./optimizer.sh` | Full optimization pipeline (9 phases) |
| `./full-audit.sh` | Detailed 100+ point audit |
| `./setup.sh` | Configure for a new system |
| `/system-health` in Claude Code | Interactive health check via skill |
| **Weekly launchd** | Automatic optimization (day/time set in config.sh) |

## Capabilities (v1)

### Checks
- [x] Memory usage + top consumers
- [x] Disk usage + cache sizes
- [x] Electron app bloatware detection (configurable list)
- [x] Idle running apps (not used in 7+ days)
- [x] Launch agent audit
- [x] Thermal + battery health
- [x] Security: firewall, FileVault, SIP, Gatekeeper, XProtect
- [x] Failed login detection + intrusion checks
- [x] Network: WiFi, IPs, DNS, open ports
- [x] Chrome extension count + sync-back detection
- [x] SSD health + SMART status
- [x] Large file finder with keep/delete suggestions
- [x] Google Sheet integration (simple language reports)
- [x] Process count + load average
- [x] Never-opened installed apps

### Auto-Fix (--fix mode)
- [x] Kill configurable bloatware apps
- [x] Clean app caches (configurable list)
- [x] Empty trash above threshold
- [x] Quit apps unused for 7+ days
- [x] Re-disable Chrome extensions that sync back
- [x] Clean old logs

### Self-Improvement
- [x] Trend analysis across recent reports
- [x] Learnings file auto-updated each run
- [x] Recommendations for next version generated
- [x] macOS notifications for critical alerts

## Portability
- All settings in config.sh — no hardcoded paths or emails
- setup.sh handles first-time configuration
- Each system gets its own Google Sheet and email
- Works on any macOS with Apple Silicon (no external tools needed)

## Evolution Roadmap (v2+)

- [ ] Software update check (macOS, Chrome, installed apps)
- [ ] Fan speed / CPU temperature tracking (via `powermetrics`)
- [ ] Memory pressure trend graphs
- [ ] Smart scheduling: run more often when issues detected, less when stable
- [ ] Disk I/O monitoring (detect thrashing)
- [ ] Login item cleanup recommendations
- [ ] Auto-upload CSV to Google Sheet without Claude (using Google Sheets API)

## How to Evolve This Agent

When running `/system-health`, Claude should:
1. Read `learnings.md` for known patterns
2. Read recent reports for trends
3. If a recurring issue appears 3+ times, add a permanent fix to `optimizer.sh`
4. Update this `agent.md` to check off completed roadmap items
5. Add new roadmap items based on discovered issues
