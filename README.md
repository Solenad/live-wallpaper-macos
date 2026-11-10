# LiveWallpaper

A tiny macOS app that plays a muted, looping video as your desktop wallpaper —
behind your desktop icons, on every display and every Space.

macOS's built-in aerial wallpapers only move on the lock screen / screen saver
and freeze to a still frame on the desktop. This fills that gap.

## Requirements

- **macOS 14 Sonoma or later**
- **Xcode Command Line Tools**, which provide `swiftc` and `codesign`. You
  don't need the full Xcode app.
- No admin password. Everything installs into your own user account.

## Installation

### 1. Install the Command Line Tools

Check whether they're already installed:

```bash
xcode-select -p
```

If that prints a path such as `/Library/Developer/CommandLineTools`, you're
set. If it prints an error, install them and follow the dialog:

```bash
xcode-select --install
```

### 2. Get the code

```bash
git clone https://github.com/Solenad/live-wallpaper-macos.git
cd live-wallpaper-macos
```

You can also use **Code → Download ZIP** on GitHub, unzip it, and `cd` into
the folder.

### 3. Run the installer

From Terminal, while logged in to your Mac (not over SSH):

```bash
./install.sh                              # uses ./sample.mov in this folder
./install.sh ~/Downloads/my-video.mp4     # or any video of your own
```

`sample.mov` is a short placeholder clip that loops. To use your own video,
pass its path as shown above, or replace `sample.mov` with your video under
the same name. Other `.mov`, `.mp4` and `.m4v` files in this folder are
git-ignored, so your videos won't get committed by accident.

You should see:

```
Built build/LiveWallpaper.app
Installed. LiveWallpaper is running and will start at login.
Video: /Users/you/Library/Application Support/LiveWallpaper/wallpaper.mov
Log:   /Users/you/Library/Logs/LiveWallpaper.log
```

The video starts playing on your desktop right away.

### 4. Check that it's running

- A **▶︎** icon appears in the menu bar.
- Or check from Terminal:

  ```bash
  launchctl print gui/$(id -u)/local.livewallpaper | grep 'state ='
  # state = running
  ```

### What gets installed

| Path | What it is |
| --- | --- |
| `~/Applications/LiveWallpaper.app` | The app (compiled locally and ad-hoc signed) |
| `~/Library/Application Support/LiveWallpaper/wallpaper.<ext>` | A copy of your video |
| `~/Library/LaunchAgents/local.livewallpaper.plist` | Starts the app at login and restarts it if it crashes |
| `~/Library/Logs/LiveWallpaper.log` | Log output, readable only by your account |

The installer also leaves a build copy in `./build/`, which is git-ignored.

### Changing the video or updating

Run `install.sh` again. It stops the running copy, replaces the app and video,
and starts it again.

```bash
./install.sh ~/Downloads/new-video.mov    # switch to a different video
git pull && ./install.sh                  # update to the latest code
```

> **Note:** If you run `./install.sh` without a path, it always uses
> `./sample.mov` from this folder and replaces whatever video you had
> before. To keep your current video when you update, pass its path again.
> The installed copy works too:
>
> ```bash
> ./install.sh ~/Library/Application\ Support/LiveWallpaper/wallpaper.mov
> ```

### Building without installing

To try it without installing anything:

```bash
./build.sh
build/LiveWallpaper.app/Contents/MacOS/LiveWallpaper /path/to/video.mov
```

Press `Ctrl-C` in Terminal to stop it.

### Troubleshooting

- **`xcrun: error: invalid active developer path` or `swiftc: command not
  found`**: the Command Line Tools aren't installed. Run
  `xcode-select --install`.
- **`permission denied: ./install.sh`**: the scripts lost their executable
  bit, which can happen with a ZIP download. Run `chmod +x *.sh`, or use
  `bash install.sh` instead.
- **`usage: ./install.sh /path/to/video.mov`**: the video path doesn't exist.
  Check the spelling, and put quotes around paths that contain spaces.
- **`launchctl bootstrap` fails**: run the installer from Terminal in your
  logged-in desktop session. The LaunchAgent only loads in the GUI session,
  so it won't load over SSH.
- **Desktop isn't moving**: look at the [log](#logs). If the video
  won't play, convert it to HEVC (see [Video tips](#video-tips)).

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

This stops the app and removes everything listed under
[What gets installed](#what-gets-installed). Your normal wallpaper shows again
right away. You can then delete the cloned folder.

## Video tips

- `.mov` or `.mp4`, ideally HEVC (H.265) at your display's resolution.
- Short clips that loop cleanly look best. Audio is always muted.
- Convert with the built-in tool:
  `avconvert --preset PresetHEVC3840x2160 --source in.mp4 --output out.mov`

## Logs

`~/Library/Logs/LiveWallpaper.log`. Open it in Console.app (under **Log
Reports**), or follow it from Terminal:

```bash
tail -f ~/Library/Logs/LiveWallpaper.log
```

Versions before this change wrote the log to `/tmp/livewallpaper.log`, where
other accounts on the Mac could read it. Running `install.sh` again moves
logging to the new location and deletes the old file.
