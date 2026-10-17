#!/usr/bin/env bash
# Keeps the free-signed iPhone app from expiring: once 5 of its 7 days have passed,
# rebuilds it and installs it on the iPhone over Wi-Fi or cable, without opening it.
# Usage: ./auto-install.sh            run once (what the daily job does)
#        ./auto-install.sh --now      install now, whatever the age
#        ./auto-install.sh --enable   run it every day at 05:00 (or on wake, if asleep then)
#        ./auto-install.sh --disable  stop running it
# Log: ~/Library/Logs/Stagehand-install.log
set -uo pipefail
cd "$(dirname "$0")"

LABEL=local.bandbox-stagehand.auto-install
AGENT=~/Library/LaunchAgents/$LABEL.plist
LOG=~/Library/Logs/Stagehand-install.log
STAMP=~/Library/Application\ Support/Stagehand/last-install
RENEW_DAYS=5   # reinstall after this many days
WARN_DAYS=6    # a day before expiry, say so even when the iPhone is just out of reach

case "${1:-}" in
  --enable)
    mkdir -p ~/Library/LaunchAgents "$(dirname "$LOG")"
    cat > "$AGENT" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array>
    <string>/bin/bash</string><string>$PWD/auto-install.sh</string>
  </array>
  <key>StartCalendarInterval</key><dict>
    <key>Hour</key><integer>5</integer><key>Minute</key><integer>0</integer>
  </dict>
  <key>EnvironmentVariables</key><dict>
    <key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
</dict></plist>
EOF
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
    launchctl bootstrap "gui/$(id -u)" "$AGENT" && echo "enabled: runs daily at 05:00, log in $LOG"
    exit ;;
  --disable)
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
    rm -f "$AGENT"
    echo "disabled"
    exit ;;
esac

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
notify() {
  osascript -e "display notification \"$1\" with title \"Stagehand\" subtitle \"iPhone app reinstall\"" 2>/dev/null
}

age_days=999
if [[ -f "$STAMP" ]]; then
  age_days=$(( ($(date +%s) - $(stat -f %m "$STAMP")) / 86400 ))
fi

if [[ "${1:-}" != "--now" && $age_days -lt $RENEW_DAYS ]]; then
  log "installed $age_days days ago; nothing to do"
  exit 0
fi

if ! xcrun devicectl list devices 2>/dev/null | grep -qE 'iPhone.* (available|connected)'; then
  log "iPhone not reachable (installed $age_days days ago); trying again tomorrow"
  if [[ $age_days -ge $WARN_DAYS ]]; then
    notify "The app expires within a day and the iPhone isn't reachable. Connect it to the Mac's Wi-Fi or cable."
  fi
  exit 1
fi

log "installing (last install $age_days days ago)"
if BANDBOX_LAUNCH=0 ./ios-build.sh --install; then
  mkdir -p "$(dirname "$STAMP")" && touch "$STAMP"
  log "installed"
else
  log "install failed"
  notify "Reinstalling the app failed. See ~/Library/Logs/Stagehand-install.log."
  exit 1
fi
