#!/bin/bash
# Builds the app, copies your video into place, and starts it now + at every login.
# Uses ./sample.mov unless you pass a different video.
#
#   ./install.sh                          # uses ./sample.mov
#   ./install.sh ~/Downloads/other.mov    # use a different video
set -euo pipefail
cd "$(dirname "$0")"

VIDEO="${1:-sample.mov}"
if [[ -z "$VIDEO" || ! -f "$VIDEO" ]]; then
    echo "usage: ./install.sh /path/to/video.mov" >&2
    exit 1
fi

LABEL=local.livewallpaper
APP_DST="$HOME/Applications/LiveWallpaper.app"
DATA="$HOME/Library/Application Support/LiveWallpaper"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
# Inside ~/Library, which only you can read. Not /tmp: other users could read
# it there (it records when you lock and unlock) or create it before you do.
LOG_DIR="$HOME/Library/Logs"
LOG="$LOG_DIR/LiveWallpaper.log"
EXT="${VIDEO##*.}"
VIDEO_DST="$DATA/wallpaper.$EXT"

bash ./build.sh

# Stop any running copy before replacing files.
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true

mkdir -p "$HOME/Applications" "$DATA" "$HOME/Library/LaunchAgents" "$LOG_DIR"
rm -rf "$APP_DST"
cp -R build/LiveWallpaper.app "$APP_DST"
# Copy the new video in before removing the old one. That way, reinstalling
# with the already-installed video as the path can't delete it.
cp "$VIDEO" "$DATA/.incoming.$EXT"
rm -f "$DATA"/wallpaper.*
mv "$DATA/.incoming.$EXT" "$VIDEO_DST"

# Remove the log older versions wrote to /tmp. This fails harmlessly if
# another user owns a file with that name.
rm -f /tmp/livewallpaper.log 2>/dev/null || true

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$APP_DST/Contents/MacOS/LiveWallpaper</string>
        <string>$VIDEO_DST</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>Crashed</key>
        <true/>
    </dict>
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
    <key>StandardOutPath</key>
    <string>$LOG</string>
    <key>StandardErrorPath</key>
    <string>$LOG</string>
</dict>
</plist>
EOF

launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Installed. LiveWallpaper is running and will start at login."
echo "Video: $VIDEO_DST"
echo "Log:   $LOG"
