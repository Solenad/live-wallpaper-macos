#!/bin/bash
# Compiles Sources/main.swift into build/LiveWallpaper.app
set -euo pipefail
cd "$(dirname "$0")"

APP=build/LiveWallpaper.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Resources/Info.plist "$APP/Contents/Info.plist"

swiftc -O \
    -framework AppKit -framework AVFoundation -framework IOKit \
    -o "$APP/Contents/MacOS/LiveWallpaper" \
    Sources/main.swift

codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"
