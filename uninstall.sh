#!/bin/bash
# Stops LiveWallpaper and removes everything install.sh added.
set -euo pipefail

LABEL=local.livewallpaper
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
rm -rf "$HOME/Applications/LiveWallpaper.app"
rm -rf "$HOME/Library/Application Support/LiveWallpaper"
rm -f "$HOME/Library/Logs/LiveWallpaper.log"
# Log location used by older versions.
rm -f /tmp/livewallpaper.log 2>/dev/null || true
echo "LiveWallpaper removed. Your normal wallpaper will show again."
