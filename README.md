# System Health Agent

A self-improving system health monitor for **macOS** and **Windows**. Checks 100+ data points, auto-fixes common issues, explains everything in simple language, and sends weekly reports to a Google Sheet.

**No external tools required** — uses only built-in OS commands.

Works on: macOS (Apple Silicon & Intel) | Windows 10/11

---

## What It Checks

| Area | Mac | Windows | What It Looks At |
|------|:---:|:-------:|-----------------|
| **Memory** | ✅ | ✅ | RAM usage, per-app breakdown, memory pressure |
| **CPU** | ✅ | ✅ | Load, usage, core count, chip model |
| **Disk** | ✅ | ✅ | Space, SSD health, large files, temp/cache cleanup |
| **Battery** | ✅ | ✅ | Cycle count, health %, charge, degradation |
| **Security** | ✅ | ✅ | Firewall, encryption (FileVault/BitLocker), failed logins |
| **Antivirus** | ✅ | ✅ | XProtect / Windows Defender status + last scan |
| **Network** | ✅ | ✅ | WiFi signal, IPs, DNS, open ports |
| **Temperature** | ✅ | — | Overheating warnings, fan status |
| **Intrusion** | ✅ | ✅ | Failed logins, new accounts, late-night logins |
| **Chrome** | ✅ | — | Extension count, heavy extension detection |
| **Startup Items** | ✅ | ✅ | Launch agents / startup programs |
| **Large Files** | ✅ | ✅ | Files >100MB with keep/delete suggestions |

---

## Quick Start

### macOS

```bash
git clone https://github.com/AISachin/system-health-agent.git
cd system-health-agent

# Interactive setup
./setup.sh

# Or one-liner (no prompts)
./setup.sh --email you@gmail.com --day 5 --hour 12
```

### Windows (PowerShell as Admin)

```powershell
git clone https://github.com/AISachin/system-health-agent.git
cd system-health-agent\windows

# Interactive setup
.\setup.ps1

# Or one-liner
.\setup.ps1 -Email "you@gmail.com" -Day "Friday" -Hour "12:00"
```

---

## Example Output

### What you see in Terminal / PowerShell:

```
════════════════════════════════════════
  SYSTEM HEALTH — 2026-11-06 12:00
════════════════════════════════════════

  Memory: 21GB / 24GB | Free: 2862MB
  Disk:   45% used | Free: 510GB
  CPU:    8% | Procs: 612

  ISSUES (1):
    ! Comet has 25 processes using 4251MB — excessive

  WARNINGS (2):
    ~ 15 files in Downloads older than 30 days (2.1GB total)
    ~ Battery cycle count is 847 (consider service after 1000)

  FIXED (2):
    + Killed Comet (25 processes, 4251MB)
    + Cleaned temp files (380MB)

  Report: ./reports/health-2026-11-06_12-00.md
════════════════════════════════════════
```

### What you see in the Google Sheet:

| Section | What We Checked | Result | What It Means | Health |
|---------|----------------|--------|---------------|--------|
| About Your Laptop | Laptop Model | MacBook Pro M5 Pro | This is your laptop type | |
| Brain Power (CPU) | How Busy Is It | 8% used | Your laptop brain is mostly relaxed | GOOD |
| Temperature | Is It Overheating? | No | Your laptop is cool - no heat problems | GOOD |
| Storage Space | Space Free | 510 GB | Plenty of room for more files | GOOD |
| Memory (RAM) | Memory Free | Only 2.8 GB free | Getting tight - close some apps | WARNING |
| Apps Eating Memory | Perplexity (Comet) | 4.2 GB! | BIGGEST memory eater! | PROBLEM! |
| Battery | Times Charged | 847 out of 1000 | Battery getting older but still fine | OK |
| Battery | Battery Health | Normal - 92% | Still holds 92% of original charge | GOOD |
| Security - Locks | Firewall | ON | Protection wall active - hackers blocked | GOOD |
| Security - Alerts | Failed Login Attempts | 3 in 7 days | Very few failed attempts - normal | GOOD |
| Big Files Taking Space | DaVinci installer | 7.0 GB (old) | HUGE! 7 GB wasted - DELETE if installed | DELETE |

> Every row explained in plain English — no technical jargon.

---

## Commands

### macOS

```bash
./health-check.sh              # Quick health check
./health-check.sh --fix        # Check + auto-fix issues
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
| `MEM_CRITICAL_MB` | Free RAM below this = PROBLEM | 2000 MB |
| `DISK_CRITICAL_PCT` | Disk usage above this = PROBLEM | 90% |
| `BATTERY_WARNING_CYCLES` | Battery cycles above this = WARNING | 800 |

### Change Settings

```bash
# macOS: edit config.sh, then re-apply
nano config.sh
./setup.sh

# Windows: edit windows/config.ps1, then re-apply
notepad windows\config.ps1
.\windows\setup.ps1
```

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

Each gets:
- Its **own Google Sheet**
- Its **own email**
- Its **own schedule**
- **Zero connection** between systems

---

## How Auto-Fix Works (--fix / -Fix)

| What It Fixes | Mac | Windows |
|--------------|:---:|:-------:|
| Kill memory-hogging Electron apps | ✅ | ✅ |
| Clean app caches that regrow | ✅ | ✅ |
| Empty large trash / recycle bin | ✅ | ✅ |
| Quit apps unused for 7+ days | ✅ | — |
| Re-disable Chrome extensions that sync back | ✅ | — |
| Clean old log files | ✅ | ✅ |

---

## Self-Improvement

The agent learns from its own history:

1. **Trend analysis** — Compares last 4 reports to spot recurring issues
2. **Learnings file** — Auto-updated with patterns and recommendations
3. **Permanent fixes** — When an issue appears 3+ times, a fix is added automatically
4. **macOS notifications** — Critical alerts pop up as system notifications

---

## Google Sheet Integration

Reports use **simple, plain English** — designed so anyone can understand.

- Each weekly run adds rows with a week number (2026-W45, W46, etc.)
- Upload requires [Claude Code](https://claude.com/claude-code) with Google Drive MCP
- Or export the CSV manually from the `reports/` folder

---

## File Structure

```
system-health-agent/
├── config.sh              ← macOS settings (edit this)
├── setup.sh               ← macOS one-time setup
├── health-check.sh        ← macOS quick check
├── full-audit.sh          ← macOS 100+ point audit
├── simplify-audit.sh      ← Tech CSV → simple language
├── optimizer.sh           ← macOS full weekly pipeline
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
| **Admin** | Not required (except setup.sh for launchd) | Required for scheduled task setup |
| **Google Sheet** | Optional (needs Claude Code) | Optional (needs Claude Code) |

---

## License

MIT — use it, share it, modify it.

---

Made with care by [Sachin](https://theboredmonkey.com) and Claude.
