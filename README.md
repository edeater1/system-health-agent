# System Health Agent

A self-improving system health monitor and **security hardener** for **macOS** and **Windows**.

Acts like a technician: finds problems, explains why they matter, shows the best fix, tells you what changes, and asks before acting.

**No external tools required** — uses only built-in OS commands.

Works on: macOS (Apple Silicon & Intel) | Windows 10/11

---

## What Makes This Different

Most system health tools dump technical data and leave you to figure it out. This agent:

| Feature | This Agent | Typical Tools |
|---------|-----------|---------------|
| **Explains findings** | "Your firewall is off — anyone on WiFi can try to connect" | "Firewall: 0" |
| **Says why it matters** | "On public WiFi, hackers scan for unprotected Macs" | (nothing) |
| **Shows the fix** | "Turn on firewall with stealth mode" | (nothing) |
| **Shows impact** | "Mac becomes invisible on networks. AirDrop still works." | (nothing) |
| **Asks before acting** | "Apply this fix? [y/N]" | Auto-changes or does nothing |
| **Gives a score** | HEALTHY / MOSTLY OK / NEEDS ATTENTION | Raw numbers |

---

## What It Checks

| Area | Mac | Windows | What It Looks At |
|------|:---:|:-------:|-----------------|
| **Firewall** | ✅ | ✅ | On/off, stealth mode, incoming blocks |
| **Remote Access** | ✅ | ✅ | ARD, VNC, SSH, Screen Sharing |
| **Encryption** | ✅ | ✅ | FileVault / BitLocker |
| **System Protection** | ✅ | — | SIP, Gatekeeper |
| **Failed Logins** | ✅ | ✅ | Brute force detection |
| **Memory** | ✅ | ✅ | RAM usage, per-app breakdown, memory pressure |
| **CPU** | ✅ | ✅ | Load, usage, core count, chip model |
| **Disk** | ✅ | ✅ | Space, SSD health, large files, temp/cache cleanup |
| **Battery** | ✅ | ✅ | Cycle count, health %, degradation |
| **Antivirus** | ✅ | ✅ | XProtect / Windows Defender status |
| **Network** | ✅ | ✅ | WiFi, IPs, DNS, open ports, foreign connections |
| **Temperature** | ✅ | — | Overheating warnings |
| **Chrome** | ✅ | — | Extension count, heavy extensions |
| **Backup** | ✅ | — | Time Machine status |
| **Updates** | ✅ | — | Pending macOS updates |
| **Large Files** | ✅ | ✅ | Files >100MB with keep/delete suggestions |
| **Startup Items** | ✅ | ✅ | Launch agents / startup programs |

---

## Quick Start

### macOS

```bash
git clone https://github.com/edeater1/system-health-agent.git
cd system-health-agent

# Interactive setup
./setup.sh

# Or one-liner (no prompts)
./setup.sh --email you@gmail.com --day 5 --hour 12
```

### Windows (PowerShell as Admin)

```powershell
git clone https://github.com/edeater1/system-health-agent.git
cd system-health-agent\windows

# Interactive setup
.\setup.ps1

# Or one-liner
.\setup.ps1 -Email "you@gmail.com" -Day "Friday" -Hour "12:00"
```

---

## Example Output

```
════════════════════════════════════════════════
  SYSTEM HEALTH CHECK — 2026-11-06 02:40
  Sachin's MacBook Pro | 24GB RAM | Apple M5 Pro
════════════════════════════════════════════════

  Memory: 23GB / 24GB (3883MB free)
  Disk:   2% used (642Gi free)
  Load:   1.81 | Processes: 783

  ━━━ WARNINGS — Should Fix Soon ━━━━━━━━━━━━━

  1. Comet has 34 processes using 7854MB
     Electron apps like Comet spawn many helper processes.
     34 is excessive.
     Fix: Quit Comet to free 7854MB

  2. No Time Machine backup configured
     If your Mac's drive fails or gets stolen, there's no
     backup to recover from.
     Fix: Connect an external drive and enable Time Machine

  ━━━ ALL GOOD ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  ✓ Firewall is ON
  ✓ FileVault disk encryption is ON
  ✓ System Integrity Protection (SIP) is ON
  ✓ Gatekeeper is ON (blocks unverified apps)
  ✓ Temperature normal — no overheating
  ✓ Battery healthy — 3 cycles, condition: Normal

  ─────────────────────────────────────────────
  Score: MOSTLY OK  (2 warnings, 6 checks passed)

  Run ./health-check.sh --fix to fix problems interactively
════════════════════════════════════════════════
```

---

## Security Hardening

One-command full lockdown:

```bash
sudo ./harden-now.sh
```

This enables:
- **Firewall + Stealth Mode** — invisible on networks
- **Closes ARD, VNC, SSH** — no remote access
- **Packet filter (pf)** — blocks dangerous ports, auto-blocks brute force
- **Network auto-guard** — re-hardens on every new WiFi connection
- **Privacy settings** — screen lock, file extensions, crash reports

What **still works** after hardening:
- AirDrop, AirPlay, Handoff, Universal Clipboard
- Finder file sharing on local network
- All your apps and internet

```bash
./firewall.sh --status    # Check security anytime
./firewall.sh --undo      # Revert all changes
```

---

## Commands

### macOS

```bash
./health-check.sh              # Smart health check with explanations
./health-check.sh --fix        # Interactive fix (asks before each change)
./health-check.sh --auto-fix   # Unattended fix (for cron/automation)
./firewall.sh                  # Security status
./firewall.sh --harden         # Apply security hardening
sudo ./harden-now.sh           # One-command full lockdown
./full-audit.sh                # Detailed 100+ point audit → CSV
./optimizer.sh                 # Full optimization (what runs weekly)
./setup.sh                     # Configure for a new system
```

### Windows (PowerShell)

```powershell
.\health-check.ps1             # Quick health check
.\health-check.ps1 -Fix        # Check + auto-fix issues
.\setup.ps1                    # Configure for a new system
```

---

## Configuration

All settings live in **one file** per platform:

- **macOS**: `config.sh`
- **Windows**: `windows/config.ps1`

### Key Settings

| Setting | What It Controls | Default |
|---------|-----------------|---------|
| `OWNER_EMAIL` | Google account for the sheet | (set during setup) |
| `SHEET_ID` | Google Sheet ID for reports | (set during setup) |
| `SCHEDULE_DAY` | Which day to run weekly | Friday |
| `SCHEDULE_HOUR` | What time to run | 12 (noon) |
| `BLOATWARE_APPS` | Apps to kill when hogging memory | Comet, ChatGPT, Adobe |
| `MEM_CRITICAL_MB` | Free RAM below this = CRITICAL | 2000 MB |
| `DISK_CRITICAL_PCT` | Disk usage above this = CRITICAL | 90% |
| `BATTERY_WARNING_CYCLES` | Battery cycles above this = WARNING | 800 |

---

## Setting Up on Multiple Systems

Each system runs independently — **no shared data, no conflicts**.

```bash
# System 1 (your MacBook)
./setup.sh --email sachin@gmail.com --sheet SHEET_ID_1

# System 2 (office Windows PC)
.\windows\setup.ps1 -Email "sachin@work.com" -SheetId "SHEET_ID_2"

# System 3 (friend's Mac)
./setup.sh --email friend@gmail.com --sheet SHEET_ID_3
```

Each gets its own Google Sheet, email, schedule, and zero connection between systems.

---

## How Auto-Fix Works

In `--fix` mode, the agent shows each problem, explains the fix and its impact, and asks for your permission:

```
  CRITICAL: Comet is eating 7854MB of memory (34 processes)
  Why: Electron app bug — spawned 34 separate processes.
  Fix: Force-quit Comet
  What changes: Comet closes, you get ~7854MB back. Reopen anytime.
  Apply this fix? [y/N]
```

In `--auto-fix` mode (for weekly cron), it applies fixes without asking.

| What It Fixes | Mac | Windows |
|--------------|:---:|:-------:|
| Kill memory-hogging Electron apps | ✅ | ✅ |
| Clean app caches that regrow | ✅ | ✅ |
| Empty large trash / recycle bin | ✅ | ✅ |
| Quit apps unused for 7+ days | ✅ | — |
| Re-disable Chrome extensions that sync back | ✅ | — |
| Re-enable firewall if turned off | ✅ | — |

---

## Self-Improvement

The agent learns from its own history:

1. **Trend analysis** — Compares last 4 reports to spot recurring issues
2. **Learnings file** — Auto-updated with patterns and recommendations
3. **Permanent fixes** — When an issue appears 3+ times, a fix is added
4. **Security verification** — Every weekly run checks firewall + remote access
5. **macOS notifications** — Critical alerts pop up as system notifications

---

## File Structure

```
system-health-agent/
├── config.sh              ← macOS settings (edit this)
├── setup.sh               ← macOS one-time setup
├── health-check.sh        ← Smart health check + interactive fix
├── firewall.sh            ← Security status + hardening
├── harden-now.sh          ← One-command lockdown (sudo)
├── network-guard.sh       ← Auto-hardens on network change
├── pf-rules.conf          ← Packet filter firewall rules
├── full-audit.sh          ← 100+ point detailed audit
├── simplify-audit.sh      ← Tech CSV → simple language
├── optimizer.sh           ← Full weekly pipeline (10 phases)
├── agent.md               ← Agent capabilities + roadmap
├── README.md              ← This file
├── .gitignore
│
└── windows/
    ├── config.ps1         ← Windows settings (edit this)
    ├── setup.ps1          ← Windows one-time setup
    └── health-check.ps1   ← Windows quick check
```

---

## Requirements

| | macOS | Windows |
|--|-------|---------|
| **OS** | macOS 13+ (Ventura or later) | Windows 10/11 |
| **Shell** | bash (built-in) | PowerShell 5.1+ (built-in) |
| **Tools** | None — all built-in | None — all built-in |
| **Admin** | Needed for security hardening | Required for scheduled task |
| **Google Sheet** | Optional (needs Claude Code) | Optional (needs Claude Code) |

---

## License

MIT — use it, share it, modify it.

---

Made with care by [Sachin](https://theboredmonkey.com) and Claude.
