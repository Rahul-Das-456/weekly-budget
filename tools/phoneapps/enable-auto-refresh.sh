#!/bin/zsh
# Turns on automatic re-signing: every 6 hours the Mac runs `phoneapps refresh`, which re-signs any app
# that's 4+ days old (only when the iPhone is reachable). Also adds the `phoneapps` command.
# Undo with: ~/PhoneApps/enable-auto-refresh.sh --off
set -e
LABEL=com.rahuldas.phoneapps.refresh
PLIST=~/Library/LaunchAgents/$LABEL.plist

if [[ "$1" == "--off" ]]; then
  launchctl bootout gui/$(id -u) $PLIST 2>/dev/null || true
  rm -f $PLIST /usr/local/bin/phoneapps /opt/homebrew/bin/phoneapps
  echo "Auto refresh is off."
  exit 0
fi

mkdir -p ~/Library/LaunchAgents ~/PhoneApps/logs
cat > $PLIST <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>/usr/bin/python3</string><string>$HOME/PhoneApps/phoneapps</string><string>refresh</string></array>
  <key>StartInterval</key><integer>21600</integer>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$HOME/PhoneApps/logs/launchd.log</string>
  <key>StandardErrorPath</key><string>$HOME/PhoneApps/logs/launchd.log</string>
</dict>
</plist>
EOF
plutil -lint -s $PLIST
launchctl bootout gui/$(id -u) $PLIST 2>/dev/null || true
launchctl bootstrap gui/$(id -u) $PLIST
BIN=/usr/local/bin; [[ -w $BIN ]] || BIN=/opt/homebrew/bin
[[ -w $BIN ]] && ln -sf ~/PhoneApps/phoneapps $BIN/phoneapps || echo "Couldn't add the phoneapps command to PATH; use ~/PhoneApps/phoneapps"
echo "Auto refresh is on: checks every 6 hours, re-signs apps 4+ days old. Log: ~/PhoneApps/logs/phoneapps.log"
echo "Turn it off any time: ~/PhoneApps/enable-auto-refresh.sh --off"
