// LiveWallpaper — plays a muted, looping video behind the desktop icons on every display.
//
// Usage: LiveWallpaper /path/to/video.mov
// (defaults to ~/Library/Application Support/LiveWallpaper/wallpaper.mov)

import AppKit
import AVFoundation
import IOKit.pwr_mgt

@MainActor
final class WallpaperController: NSObject, NSApplicationDelegate {
    private let videoURL: URL
    // One player drives every screen's layer, so the video is decoded only once.
    private let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?
    private var windows: [NSWindow] = []
    private var statusItem: NSStatusItem?
    private var pauseItem: NSMenuItem?
    private var refreshItem: NSMenuItem?

    private var userPaused = false
    private var screensAsleep = false
    private var sessionInactive = false
    private var isPlaying = false

    // Lock-screen refresh: macOS's own video wallpaper (shown on the lock screen) can go
    // black after several locks. After each unlock — while our video covers the desktop —
    // restart Apple's wallpaper processes twice so the next lock screen starts fresh.
    private static let refreshDefaultsKey = "RefreshLockScreenOnUnlock"
    // Seconds after the desktop is visible again (not after the unlock event): killing
    // WallpaperAgent mid-unlock can bounce the lock screen, and right after a long sleep it
    // piles onto a system that is still catching up. The second pass waits for launchd to
    // relaunch the processes (an instant second kill would hit them mid-launch).
    private static let refreshDelays: [TimeInterval] = [3, 4.5]
    // A refresh can itself cause a lock/unlock bounce; don't let that start another cycle.
    private static let refreshCooldown: TimeInterval = 30
    private var screenLocked = false
    private var refreshAwaitingDesktop = false
    private var lastRefreshCycle = Date.distantPast
    private var pendingRefreshes: [DispatchWorkItem] = []

    private var refreshEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.refreshDefaultsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.refreshDefaultsKey) }
    }

    // Keep display on when locked: macOS turns the display off ~30s after locking,
    // ignoring the normal "Turn display off" timer. While locked, hold a
    // display-sleep assertion (what `caffeinate -d` does) for up to the chosen time.
    private static let keepAwakeDefaultsKey = "KeepDisplayOnWhenLockedMinutes"
    private static let keepAwakeChoices: [(title: String, minutes: Int)] = [
        ("Off", 0), ("5 Minutes", 5), ("15 Minutes", 15), ("30 Minutes", 30),
        ("1 Hour", 60), ("Until Unlocked", -1),
    ]
    private var keepAwakeItems: [NSMenuItem] = []
    private var displayAssertion: IOPMAssertionID?
    private var displayReleaseWork: DispatchWorkItem?

    /// 0 = off, -1 = until unlocked, otherwise minutes.
    private var keepAwakeMinutes: Int {
        get { UserDefaults.standard.object(forKey: Self.keepAwakeDefaultsKey) as? Int ?? 5 }
        set { UserDefaults.standard.set(newValue, forKey: Self.keepAwakeDefaultsKey) }
    }

    init(videoURL: URL) {
        self.videoURL = videoURL
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        startLooping()

        buildWindows()
        buildStatusItem()
        observeSystem()
        updatePlayback()
        log("started with \(videoURL.path) on \(windows.count) screen(s); lock-screen refresh \(refreshEnabled ? "on" : "off"); keep display on when locked: \(keepAwakeDescription)")
    }

    // MARK: Looping

    // Loop only the part of the file that has picture. Some exporters and upscalers leave
    // an empty stretch (an "empty edit") at the start or end of the video track. Looping
    // the whole file would show the black window behind it there, a blink on every loop.
    private func startLooping() {
        let asset = AVURLAsset(url: videoURL)
        Task {
            let range = await Self.pictureRange(of: asset)
            let duration = (try? await asset.load(.duration)) ?? .invalid
            looper = AVPlayerLooper(
                player: player, templateItem: AVPlayerItem(asset: asset),
                timeRange: range ?? .invalid)
            if isPlaying { player.play() }

            if let range, duration.isValid,
               range.start > .zero || range.end < duration {
                log(String(format: "looping %.3fs–%.3fs of %.3fs (skipping empty video frames)",
                           range.start.seconds, range.end.seconds, duration.seconds))
            }
        }
    }

    /// From the start of the video track's first non-empty edit to the end of its last.
    /// nil if that can't be read; the caller then loops the whole file.
    private static func pictureRange(of asset: AVURLAsset) async -> CMTimeRange? {
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let segments = try? await track.load(.segments) else { return nil }
        let filled = segments.filter { !$0.isEmpty }.map(\.timeMapping.target)
        guard let first = filled.first, let last = filled.last,
              last.end > first.start else { return nil }
        return CMTimeRange(start: first.start, end: last.end)
    }

    // MARK: Windows

    private func buildWindows() {
        NotificationCenter.default.removeObserver(
            self, name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        windows.forEach { $0.orderOut(nil) }

        windows = NSScreen.screens.map { screen in
            let window = NSWindow(
                contentRect: screen.frame, styleMask: .borderless,
                backing: .buffered, defer: false)
            window.setFrame(screen.frame, display: false)
            // Desktop level: above the system wallpaper, below the desktop icons.
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            window.ignoresMouseEvents = true
            window.isOpaque = true
            window.hasShadow = false
            window.backgroundColor = .black
            window.isReleasedWhenClosed = false

            let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.wantsLayer = true
            let playerLayer = AVPlayerLayer(player: player)
            playerLayer.videoGravity = .resizeAspectFill
            playerLayer.frame = view.bounds
            playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            view.layer?.addSublayer(playerLayer)
            window.contentView = view
            window.orderFront(nil)

            NotificationCenter.default.addObserver(
                self, selector: #selector(occlusionChanged),
                name: NSWindow.didChangeOcclusionStateNotification, object: window)
            return window
        }
    }

    // MARK: Menu bar

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "play.rectangle", accessibilityDescription: "LiveWallpaper")

        let menu = NSMenu()
        let pause = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)

        let refresh = NSMenuItem(
            title: "Refresh Lock Screen on Unlock", action: #selector(toggleRefresh), keyEquivalent: "")
        refresh.target = self
        refresh.state = refreshEnabled ? .on : .off
        menu.addItem(refresh)

        let keepAwake = NSMenuItem(title: "Keep Display On When Locked", action: nil, keyEquivalent: "")
        let keepAwakeMenu = NSMenu()
        for (index, choice) in Self.keepAwakeChoices.enumerated() {
            let choiceItem = NSMenuItem(
                title: choice.title, action: #selector(chooseKeepAwake(_:)), keyEquivalent: "")
            choiceItem.target = self
            choiceItem.tag = index
            keepAwakeMenu.addItem(choiceItem)
            keepAwakeItems.append(choiceItem)
        }
        keepAwake.submenu = keepAwakeMenu
        menu.addItem(keepAwake)
        updateKeepAwakeChecks()

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit LiveWallpaper", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        item.menu = menu

        statusItem = item
        pauseItem = pause
        refreshItem = refresh
    }

    @objc private func togglePause() {
        userPaused.toggle()
        pauseItem?.title = userPaused ? "Resume" : "Pause"
        updatePlayback()
    }

    @objc private func toggleRefresh() {
        refreshEnabled.toggle()
        refreshItem?.state = refreshEnabled ? .on : .off
        if !refreshEnabled {
            refreshAwaitingDesktop = false
            cancelPendingRefreshes()
        }
        log("lock-screen refresh \(refreshEnabled ? "on" : "off")")
    }

    @objc private func chooseKeepAwake(_ sender: NSMenuItem) {
        keepAwakeMinutes = Self.keepAwakeChoices[sender.tag].minutes
        updateKeepAwakeChecks()
        log("keep display on when locked: \(keepAwakeDescription)")
    }

    private func updateKeepAwakeChecks() {
        let current = keepAwakeMinutes
        for item in keepAwakeItems {
            item.state = Self.keepAwakeChoices[item.tag].minutes == current ? .on : .off
        }
    }

    private var keepAwakeDescription: String {
        switch keepAwakeMinutes {
        case 0: return "off"
        case -1: return "until unlocked"
        case let m: return "up to \(m) min"
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: System events

    private func observeSystem() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(screensSlept), name: NSWorkspace.screensDidSleepNotification, object: nil)
        ws.addObserver(self, selector: #selector(screensWoke), name: NSWorkspace.screensDidWakeNotification, object: nil)
        ws.addObserver(self, selector: #selector(sessionResigned), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        ws.addObserver(self, selector: #selector(sessionActivated), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)

        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(self, selector: #selector(didLock), name: .init("com.apple.screenIsLocked"), object: nil)
        dnc.addObserver(self, selector: #selector(didUnlock), name: .init("com.apple.screenIsUnlocked"), object: nil)
    }

    @objc private func screensChanged() { buildWindows(); updatePlayback() }
    @objc private func screensSlept() { screensAsleep = true; updatePlayback() }
    @objc private func screensWoke() { screensAsleep = false; updatePlayback() }
    @objc private func sessionResigned() { sessionInactive = true; updatePlayback() }
    @objc private func sessionActivated() { sessionInactive = false; updatePlayback() }
    @objc private func occlusionChanged() { updatePlayback(); scheduleRefreshIfDesktopVisible() }

    // MARK: Lock-screen refresh

    @objc private func didLock() {
        screenLocked = true
        refreshAwaitingDesktop = false
        // Never restart Apple's wallpaper while the lock screen is showing it.
        cancelPendingRefreshes()
        holdDisplayOn()
    }

    @objc private func didUnlock() {
        screenLocked = false
        releaseDisplay(reason: "unlocked")
        guard refreshEnabled else { return }
        refreshAwaitingDesktop = true
        scheduleRefreshIfDesktopVisible()
    }

    /// Starts the refresh passes once the unlock has finished and the desktop is on screen.
    private func scheduleRefreshIfDesktopVisible() {
        guard refreshAwaitingDesktop, !screenLocked, desktopVisible else { return }
        refreshAwaitingDesktop = false
        guard Date().timeIntervalSince(lastRefreshCycle) >= Self.refreshCooldown else {
            log("skipped lock-screen refresh (last one was under \(Int(Self.refreshCooldown))s ago)")
            return
        }
        lastRefreshCycle = Date()
        cancelPendingRefreshes()
        for (index, delay) in Self.refreshDelays.enumerated() {
            let pass = index + 1
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { self?.restartSystemWallpaper(pass: pass) }
            }
            pendingRefreshes.append(work)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    private func cancelPendingRefreshes() {
        pendingRefreshes.forEach { $0.cancel() }
        pendingRefreshes.removeAll()
    }

    private func restartSystemWallpaper(pass: Int) {
        guard !screenLocked else { return }
        // launchd relaunches both processes automatically within a second.
        let killall = Process()
        killall.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        killall.arguments = ["WallpaperAerialsExtension", "WallpaperAgent"]
        killall.standardOutput = FileHandle.nullDevice
        killall.standardError = FileHandle.nullDevice
        do {
            try killall.run()
            log("refreshed system wallpaper (\(pass)/\(Self.refreshDelays.count))")
        } catch {
            log("refresh failed: \(error.localizedDescription)")
        }
    }

    // MARK: Keep display on when locked

    private func holdDisplayOn() {
        let minutes = keepAwakeMinutes
        guard minutes != 0, displayAssertion == nil else { return }

        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "LiveWallpaper: keep display on while locked" as CFString,
            &id)
        guard result == kIOReturnSuccess else {
            log("could not keep display on (IOKit error \(result))")
            return
        }
        displayAssertion = id
        log("locked: keeping display on (\(keepAwakeDescription))")

        if minutes > 0 {
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { self?.releaseDisplay(reason: "\(minutes) min limit reached") }
            }
            displayReleaseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(minutes * 60), execute: work)
        }
    }

    private func releaseDisplay(reason: String) {
        displayReleaseWork?.cancel()
        displayReleaseWork = nil
        guard let id = displayAssertion else { return }
        IOPMAssertionRelease(id)
        displayAssertion = nil
        log("display may turn off again (\(reason))")
    }

    // MARK: Playback — only play while the desktop can actually be seen

    private var desktopVisible: Bool {
        windows.contains { $0.occlusionState.contains(.visible) }
    }

    private func updatePlayback() {
        let shouldPlay = !userPaused && !screensAsleep && !sessionInactive && desktopVisible
        guard shouldPlay != isPlaying else { return }
        isPlaying = shouldPlay
        if shouldPlay { player.play() } else { player.pause() }
        log(shouldPlay ? "playing" : "paused")
    }

    private static let timestamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    private func log(_ message: String) {
        print("\(Self.timestamp.string(from: Date())) [LiveWallpaper] \(message)")
        fflush(stdout)
    }
}

let defaultVideo = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/LiveWallpaper/wallpaper.mov").path
let videoPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : defaultVideo

guard FileManager.default.fileExists(atPath: videoPath) else {
    FileHandle.standardError.write("[LiveWallpaper] video not found: \(videoPath)\n".data(using: .utf8)!)
    exit(1)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)  // no Dock icon
    let controller = WallpaperController(videoURL: URL(fileURLWithPath: videoPath))
    app.delegate = controller
    app.run()
    _ = controller  // keep the delegate alive for the life of the app
}
