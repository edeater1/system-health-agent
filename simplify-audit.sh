#!/bin/bash
# Converts the technical audit CSV into simple, easy-to-read language
# Usage: ./simplify-audit.sh input.csv output.csv

INPUT="$1"
OUTPUT="$2"

if [ -z "$INPUT" ] || [ ! -f "$INPUT" ]; then
  echo "Usage: $0 <input-audit.csv> <output-simple.csv>"
  exit 1
fi

[ -z "$OUTPUT" ] && OUTPUT="${INPUT%.csv}-simple.csv"

WEEK=$(date +"%Y-W%V")
DATE=$(date +"%Y-%m-%d")

{
  echo "MacBook Health Report - Simple Version,,,,,,"
  echo "Week,Date,Section,What We Checked,Result,What It Means,Health"

  while IFS=',' read -r cat item value details status; do
    # Skip header and blank lines
    [[ "$cat" == "Category" ]] && continue
    [[ -z "$cat" ]] && continue

    section=""
    check=""
    result=""
    meaning=""
    health=""

    case "$cat" in
      Report) continue ;;

      Hardware)
        section="About Your Laptop"
        case "$item" in
          Model) check="Laptop Model"; result="$value"; meaning="This is your laptop type" ;;
          macOS) check="Software Version"; result="$value"; meaning="Your laptop's main software version" ;;
          Uptime) check="How Long It's Been On"; result="$value"; meaning="Time since you last restarted" ;;
          GPU) check="Graphics Chip"; result="$value"; meaning="The part that draws things on screen" ;;
          Display) check="Screen"; result="$value"; meaning="Your screen resolution - sharp and clear" ;;
          Bluetooth) check="Bluetooth"; result="$value"; meaning="Wireless connections (AirPods etc)" ;;
          Thunderbolt) check="Thunderbolt Port"; result="$value"; meaning="Fast connection port" ;;
          "USB Devices") check="USB Devices Connected"; result="$value"; meaning="Things plugged in via USB" ;;
          *) check="$item"; result="$value"; meaning="$details" ;;
        esac
        ;;

      "Chip/CPU")
        section="Brain Power (CPU)"
        case "$item" in
          Model) check="Chip Model"; result="$value"; meaning="The brain of your laptop"; health="${status:-}" ;;
          "Total Cores") check="Brain Cores"; result="$value total"; meaning="Mini-brains working together ($details)" ;;
          "Load Average")
            check="How Busy Is It"
            result="$value"
            if python3 -c "exit(0 if float('${value:-0}') < 5 else 1)" 2>/dev/null; then
              meaning="Your laptop brain is mostly relaxed"; health="GOOD"
            else
              meaning="Your laptop is working hard right now"; health="BUSY"
            fi
            ;;
          "CPU Usage") check="Brain Usage"; result="$value"; meaning="How much brain power is being used right now"; health="GOOD" ;;
          *) check="$item"; result="$value"; meaning="$details" ;;
        esac
        ;;

      Thermal)
        section="Temperature"
        case "$item" in
          Warning)
            check="Is It Overheating?"
            if [[ "$value" == "None" ]]; then
              result="No"; meaning="Your laptop is cool - no heat problems"; health="GOOD"
            else
              result="YES!"; meaning="Your laptop is too hot! Close some apps"; health="PROBLEM!"
            fi
            ;;
          Fan) check="Fan"; result="$value"; meaning="Fan turns on only when needed"; health="GOOD" ;;
          *) check="$item"; result="$value"; meaning="$details" ;;
        esac
        ;;

      "SSD Health")
        section="Hard Drive Health"
        case "$item" in
          "SMART Status")
            check="Drive Condition"
            if [[ "$value" == "Verified" ]]; then
              result="Healthy"; meaning="Your storage drive is in good shape"; health="GOOD"
            elif [[ "$value" == "N/A" ]]; then
              result="Could not check"; meaning="Sensor not readable (normal on new Macs)"; health="CHECK LATER"
            else
              result="$value"; meaning="Drive might have issues - back up your data!"; health="WARNING"
            fi
            ;;
          Type) check="Drive Type"; result="SSD (Fast Drive)"; meaning="You have the fast type of storage" ;;
          *) check="$item"; result="$value"; meaning="Technical drive detail" ;;
        esac
        ;;

      Disk)
        section="Storage Space"
        case "$item" in
          Total) check="Total Space"; result="$value"; meaning="Your laptop can hold this much stuff"; health="${status:-GOOD}" ;;
          Used) check="Space Used"; result="$value ($details)"; meaning="How much storage you've filled up"; health="${status:-}" ;;
          Free) check="Space Free"; result="$value"; meaning="Room still available for more files"; health="GOOD" ;;
          "User Caches") check="Temporary Files"; result="$value"; meaning="Apps save small temp files - $details"; health="GOOD" ;;
          Trash)
            check="Trash Bin"
            if [[ "$value" == "0MB" ]]; then
              result="Empty"; meaning="Your trash is empty - nice and clean!"; health="GOOD"
            else
              result="$value"; meaning="Files in trash - empty it to save space"; health="INFO"
            fi
            ;;
          Downloads) check="Downloads Folder"; result="$value"; meaning="Check if you still need these files"; health="INFO" ;;
          Logs) check="System Logs"; result="$value"; meaning="Normal system log files"; health="INFO" ;;
          *) check="$item"; result="$value"; meaning="$details" ;;
        esac
        ;;

      Caches)
        section="Temporary App Data"
        check="$item"
        result="${value}"
        case "$item" in
          GeoServices) check="Maps Data" ;;
          com.apple.helpd) check="Help Files" ;;
          Google) check="Google/Chrome" ;;
          claude*) check="Claude (AI Assistant)" ;;
          Comet) check="Perplexity (Comet)" ;;
          com.apple.*) check="Apple System ($(echo "$item" | sed 's/com.apple.//'))" ;;
          PassKit) check="Apple Wallet Data" ;;
        esac
        meaning="App saved data - safe to keep"
        health="${status:-Keep}"
        ;;

      "Large Files")
        section="Big Files Taking Space"
        check="$item"
        result="$value ($details)"
        local ext="${item##*.}"
        case "$status" in
          *installer*|*Remove*)
            meaning="Installer file - DELETE if app is already installed"
            health="DELETE"
            ;;
          *Keep*)
            meaning="Important file - keep it"
            health="KEEP"
            ;;
          *)
            age_days=$(echo "$details" | grep -o '[0-9]*' | head -1)
            if [ "${age_days:-0}" -gt 365 ] 2>/dev/null; then
              meaning="Very old file - back up to Google Drive then delete"
            elif [ "${age_days:-0}" -gt 90 ] 2>/dev/null; then
              meaning="Old file - check if you still need it"
            else
              meaning="Recent file - probably still needed"
            fi
            health="REVIEW"
            ;;
        esac
        # Make large sizes scary
        if echo "$value" | grep -q "G"; then
          gb=$(echo "$value" | tr -d 'G')
          meaning="HUGE! ${gb} GB wasted - $meaning"
        fi
        ;;

      Memory)
        section="Memory (RAM)"
        case "$item" in
          "Total RAM") check="Total Memory"; result="$value"; meaning="Your laptop has $value of memory (like a desk to work on)"; health="${status:-}" ;;
          Used)
            check="Memory Being Used"; result="$value"
            used_num=$(echo "$value" | tr -d 'GB')
            if [ "${used_num:-0}" -gt 20 ] 2>/dev/null; then
              meaning="$value out of 24 GB used - your desk is ALMOST FULL!"; health="PROBLEM!"
            else
              meaning="$value being used - normal"; health="GOOD"
            fi
            ;;
          Free)
            check="Memory Free"; result="Only $value free"
            free_num=$(echo "$value" | tr -d 'MB')
            if [ "${free_num:-0}" -lt 2000 ] 2>/dev/null; then
              meaning="Very little memory left - this is why laptop feels slow"; health="PROBLEM!"
            else
              meaning="Enough free memory"; health="GOOD"
            fi
            ;;
          "Wired (kernel)") check="System Reserved"; result="$value"; meaning="MacOS keeps this for itself - you can't change it" ;;
          Compressed) check="Compressed Memory"; result="$value"; meaning="Mac is squeezing data to save space - sign of pressure" ;;
          Processes) check="Running Programs"; result="$value programs"; meaning="Number of tiny programs running - more = slower" ;;
          Threads) check="Background Tasks"; result="$value tasks"; meaning="Background tasks running" ;;
          *) check="$item"; result="$value"; meaning="$details" ;;
        esac
        ;;

      "Memory Apps")
        section="Apps Eating Memory"
        check="$item"
        result="$value"
        mb_num=$(echo "$value" | grep -o '[0-9]*' | head -1)
        if [ "${mb_num:-0}" -gt 3000 ] 2>/dev/null; then
          meaning="Using a LOT of memory!"; health="PROBLEM!"
        elif [ "${mb_num:-0}" -gt 1000 ] 2>/dev/null; then
          meaning="Using quite a bit of memory"
        else
          meaning="Normal memory usage"
        fi
        case "$item" in
          *claude*|*Claude*) check="Claude (AI Assistant)"; meaning="Claude is using $value right now" ;;
          *Comet*|*comet*) check="Perplexity (Comet)"; meaning="Perplexity AI using $value - biggest eater!" ;;
          *Notion*) check="Notion"; meaning="Notion using $value - heavy for a notes app" ;;
          *WhatsApp*) check="WhatsApp"; meaning="WhatsApp using $value - normal" ;;
          *Safari*) check="Safari"; meaning="Safari using $value - normal" ;;
          *Chrome*) check="Chrome"; meaning="Chrome using $value" ;;
        esac
        ;;

      "Running Apps")
        section="Apps Running Right Now"
        check="$item"
        result="$value"
        meaning="Currently open on your laptop"
        ;;

      Battery)
        section="Battery"
        case "$item" in
          "Cycle Count")
            check="Times Charged"
            result="$value out of 1000"
            if [ "${value:-0}" -lt 100 ] 2>/dev/null; then
              meaning="Your battery is basically BRAND NEW!"; health="GREAT"
            elif [ "${value:-0}" -lt 500 ] 2>/dev/null; then
              meaning="Battery is healthy - plenty of life left"; health="GOOD"
            elif [ "${value:-0}" -lt 800 ] 2>/dev/null; then
              meaning="Battery getting older but still fine"; health="OK"
            else
              meaning="Battery is aging - consider replacement soon"; health="WARNING"
            fi
            ;;
          Condition)
            check="Battery Health"; result="$value"
            if [[ "$value" == "Normal" ]]; then
              meaning="Battery in perfect condition"; health="GREAT"
            else
              meaning="Battery condition: $value"; health="CHECK"
            fi
            ;;
          "Max Capacity") check="Battery Capacity"; result="$value"; meaning="How much charge your battery can hold vs when new" ;;
          "Current Charge") check="Current Charge"; result="$value"; meaning="How much battery you have right now" ;;
          "Power Source") check="Power Source"; result="$value"; meaning="$([ "$value" = "Battery Power" ] && echo "Not plugged in right now" || echo "Plugged in and charging")" ;;
          Charging) check="Is It Charging?"; result="$value"; meaning="$([ "$value" = "No" ] && echo "Not connected to charger" || echo "Currently charging")" ;;
          *) check="$item"; result="$value"; meaning="$details" ;;
        esac
        ;;

      Network)
        section="Internet"
        case "$item" in
          "WiFi SSID") check="WiFi"; result="${value:-Disconnected}"; meaning="$([ "$value" = "Disconnected" ] && echo "Not connected to WiFi" || echo "Connected to $value")" ;;
          "Signal Strength")
            check="WiFi Signal"
            result="$value"
            rssi=$(echo "$value" | grep -o '\-[0-9]*')
            if [ -n "$rssi" ]; then
              if [ "$rssi" -gt -60 ] 2>/dev/null; then
                meaning="Strong signal - fast internet"; health="GOOD"
              elif [ "$rssi" -gt -70 ] 2>/dev/null; then
                meaning="OK signal - might be slow sometimes"; health="OK"
              else
                meaning="Weak signal - move closer to router"; health="WEAK"
              fi
            else
              meaning="No WiFi signal data"
            fi
            ;;
          Noise) check="WiFi Noise"; result="$value"; meaning="Interference level on your WiFi" ;;
          "Local IP") check="Your Home Address (IP)"; result="$value"; meaning="Your laptop's address on your home network" ;;
          "Public IP") check="Your Public Address (IP)"; result="$value"; meaning="Your address on the internet" ;;
          "DNS Server") check="DNS Server"; result="$value"; meaning="The phonebook your internet uses to find websites" ;;
          "Listening Ports")
            check="Open Doors (Ports)"
            port_count=$(echo "$value" | wc -w | tr -d ' ')
            result="$port_count doors open"
            meaning="$port_count services accepting connections"
            health="INFO"
            ;;
          *) check="$item"; result="$value"; meaning="$details" ;;
        esac
        ;;

      Security)
        case "$item" in
          Firewall)
            section="Security - Locks"
            check="Firewall (Protection Wall)"
            case "$value" in
              *OFF*) result="OFF!"; meaning="Your laptop's shield against hackers is OFF!"; health="FIX THIS!" ;;
              *ON*) result="ON"; meaning="Your protection wall is active - hackers blocked"; health="GOOD" ;;
              *) result="Unknown - might be OFF"; meaning="Could not check firewall - might be OFF!"; health="FIX THIS!" ;;
            esac
            ;;
          FileVault)
            section="Security - Locks"
            check="FileVault (Drive Encryption)"
            if echo "$value" | grep -qi "on"; then
              result="ON"; meaning="Your files are encrypted - if laptop is stolen nobody can read them"; health="GOOD"
            else
              result="OFF!"; meaning="Your files are NOT encrypted - anyone who steals your laptop can read everything!"; health="FIX THIS!"
            fi
            ;;
          SIP)
            section="Security - Locks"
            check="System Protection (SIP)"
            if echo "$value" | grep -qi "enabled"; then
              result="ON"; meaning="MacOS core files are protected from changes"; health="GOOD"
            else
              result="OFF!"; meaning="System protection is disabled - risky!"; health="FIX THIS!"
            fi
            ;;
          Gatekeeper)
            section="Security - Locks"
            check="App Checker (Gatekeeper)"
            if echo "$value" | grep -qi "enabled"; then
              result="ON"; meaning="Only verified apps can install - you're protected"; health="GOOD"
            else
              result="OFF!"; meaning="Unverified apps can install freely - risky!"; health="WARNING"
            fi
            ;;
          "XProtect Version")
            section="Security - Locks"
            check="Virus Protection (XProtect)"
            result="Version $value"
            meaning="Apple's built-in virus scanner is active"
            health="GOOD"
            ;;
          "Failed Logins (7d)")
            section="Security - Alerts"
            check="Failed Login Attempts"
            fl="${value:-0}"
            if [ "$fl" -gt 50 ] 2>/dev/null; then
              result="$fl in 7 days!!"
              meaning="Someone or something tried to log in $fl times and FAILED"
              health="DANGER!"
            elif [ "$fl" -gt 10 ] 2>/dev/null; then
              result="$fl in 7 days"
              meaning="Multiple failed login attempts detected"
              health="WARNING"
            else
              result="$fl in 7 days"
              meaning="Very few failed attempts - normal"
              health="GOOD"
            fi
            ;;
          "Remote Login (SSH)")
            section="Security - Alerts"
            check="Remote Login (SSH)"
            if echo "$value" | grep -qi "enabled\|ENABLED"; then
              result="ON!"; meaning="Someone could log into your laptop remotely!"; health="WARNING"
            else
              result="OFF"; meaning="Nobody can log into your laptop remotely - good"; health="GOOD"
            fi
            ;;
          "Screen Sharing")
            section="Security - Alerts"
            check="Screen Sharing"
            if echo "$value" | grep -qi "enabled\|ENABLED"; then
              result="ON!"; meaning="Someone could see your screen remotely - turn this OFF!"; health="FIX THIS!"
            else
              result="OFF"; meaning="Screen sharing disabled - good"; health="GOOD"
            fi
            ;;
          "Sudo Events (7d)")
            section="Security - Alerts"
            check="Admin Commands (7 days)"
            result="$value commands"
            meaning="Admin-level commands that ran - mostly from our optimization work"
            health="INFO"
            ;;
          "Unsigned Processes")
            section="Security - Alerts"
            check="Suspicious Programs"
            if [ "${value:-0}" -eq 0 ] 2>/dev/null; then
              result="0 found"; meaning="No suspicious programs found - clean!"; health="GOOD"
            else
              result="$value found!"; meaning="Some programs aren't verified - check them"; health="WARNING"
            fi
            ;;
          *) section="Security"; check="$item"; result="$value"; meaning="$details" ;;
        esac
        ;;

      Intrusion)
        section="Who's Using Your Laptop?"
        case "$item" in
          "User Accounts") check="User Accounts"; result="$value accounts"; meaning="Number of user accounts on this Mac"; health="INFO" ;;
          "Modified System Files")
            check="System File Changes"; result="$value changes"
            if [ "${value:-0}" -eq 0 ] 2>/dev/null; then
              meaning="No one tampered with important system files - good"; health="GOOD"
            else
              meaning="Some system files were changed - investigate!"; health="WARNING"
            fi
            ;;
          "Active Connections") check="Active Connections"; result="$value"; meaning="Internet connections active right now"; health="INFO" ;;
          "Foreign Connections") check="Foreign Connections"; result="$value connections"; meaning="Connections to outside servers - check if all expected"; health="INFO" ;;
          "New Apps (7d)")
            check="New Apps Installed"; result="$value in 7 days"
            if [ "${value:-0}" -eq 0 ] 2>/dev/null; then
              meaning="No new apps installed this week"; health="GOOD"
            else
              meaning="$value new apps installed this week"; health="INFO"
            fi
            ;;
          "Odd-Hour Logins")
            check="Late Night Logins"
            result="$value logins (12am-5am)"
            if [ "${value:-0}" -gt 0 ] 2>/dev/null; then
              meaning="Someone logged in between midnight and 5am"; health="INFO"
            else
              meaning="No late night logins - good"; health="GOOD"
            fi
            ;;
          *) check="$item"; result="$value"; meaning="$details" ;;
        esac
        ;;

      Chrome)
        section="Chrome Browser"
        case "$item" in
          "Active Extensions") check="Active Add-ons"; result="$value"; meaning="Chrome extensions running - some slow down your browser" ;;
          "Disabled Extensions") check="Disabled Add-ons"; result="$value"; meaning="Heavy extensions we turned off to save memory"; health="GOOD" ;;
          *) check="$item"; result="$value"; meaning="$details" ;;
        esac
        ;;

      *)
        section="$cat"
        check="$item"
        result="$value"
        meaning="$details"
        health="$status"
        ;;
    esac

    [ -z "$section" ] && continue
    echo "$WEEK,$DATE,$section,$check,$result,$meaning,$health"

  done < "$INPUT"

} > "$OUTPUT"

echo "Simple report saved: $OUTPUT"
echo "Rows: $(wc -l < "$OUTPUT")"
