#!/bin/bash
# Builds the app, copies your video into place, and starts it now + at every login.
# Uses ./wallpaper.mov unless you pass a different video.
#
#   ./install.sh                          # uses ./wallpaper.mov
#   ./install.sh ~/Downloads/other.mov    # use a different video
set -euo pipefail
cd "$(dirname "$0")"

VIDEO="${1:-wallpaper.mov}"
if [[ -z "$VIDEO" || ! -f "$VIDEO" ]]; then
    echo "usage: ./install.sh /path/to/video.mov" >&2
    exit 1
fi

LABEL=local.livewallpaper
APP_DST="$HOME/Applications/LiveWallpaper.app"
DATA="$HOME/Library/Application Support/LiveWallpaper"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
EXT="${VIDEO##*.}"
VIDEO_DST="$DATA/wallpaper.$EXT"

bash ./build.sh

# Stop any running copy before replacing files.
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true

mkdir -p "$HOME/Applications" "$DATA" "$HOME/Library/LaunchAgents"
rm -rf "$APP_DST"
cp -R build/LiveWallpaper.app "$APP_DST"
rm -f "$DATA"/wallpaper.*
cp "$VIDEO" "$VIDEO_DST"

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
    <string>/tmp/livewallpaper.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/livewallpaper.log</string>
</dict>
</plist>
EOF

launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Installed. LiveWallpaper is running and will start at login."
echo "Video: $VIDEO_DST"
