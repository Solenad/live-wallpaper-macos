# LiveWallpaper

A tiny macOS app that plays a muted, looping video as your desktop wallpaper —
behind your desktop icons, on every display and every Space.

macOS's built-in aerial wallpapers only move on the lock screen / screen saver
and freeze to a still frame on the desktop. This fills that gap.

## Install

```bash
./install.sh                        # uses ./wallpaper.mov in this folder
./install.sh ~/Downloads/other.mov  # or any other video
```

This builds the app, copies the video to
`~/Library/Application Support/LiveWallpaper/`, installs the app to
`~/Applications/`, and registers a LaunchAgent so it starts at every login.

To change the video, replace `wallpaper.mov` (or pass a path) and run
`install.sh` again.

## Use

- A ▶︎ icon in the menu bar has **Pause/Resume**, **Refresh Lock Screen on
  Unlock**, **Keep Display On When Locked**, and **Quit**.
- **Keep Display On When Locked** (default: 5 minutes): macOS turns the
  display off ~30 seconds after you lock, ignoring your normal "Turn display
  off" timer. While locked, LiveWallpaper asks macOS to keep the display on
  (the same thing `caffeinate -d` does) for the time you choose: Off, 5/15/30
  minutes, 1 hour, or Until Unlocked. After the limit the display turns off as
  usual. Closing the lid or choosing Sleep still sleeps immediately.
- **Refresh Lock Screen on Unlock** (on by default): macOS's own video
  wallpaper on the lock screen can go black after several locks. After each
  unlock, LiveWallpaper restarts Apple's wallpaper processes twice
  (`killall WallpaperAerialsExtension WallpaperAgent` 3s after the desktop is
  visible again, then again 1.5s later). Waiting for the desktop keeps the
  restart out of the unlock animation and out of the busy first moments after
  a long sleep. It runs at most once every 30s, so a lock/unlock bounce can't
  trigger a second round. Your video covers the desktop, so you don't see the
  restart. It never runs while the screen is locked.
- Playback pauses automatically when the desktop is fully covered, the
  displays sleep, or you switch users — so it doesn't burn battery in the
  background.
- Quitting stops it until the next login. To start it again without logging out:
  `launchctl kickstart gui/$(id -u)/local.livewallpaper`

## Uninstall

```bash
./uninstall.sh
```

## Video tips

- `.mov` or `.mp4`, ideally HEVC (H.265) at your display's resolution.
- Short clips that loop cleanly look best. Audio is always muted.
- Convert with the built-in tool:
  `avconvert --preset PresetHEVC3840x2160 --source in.mp4 --output out.mov`

## Logs

`/tmp/livewallpaper.log`
