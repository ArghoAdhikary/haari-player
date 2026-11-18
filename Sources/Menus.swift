import Cocoa
import VLCKit

/// Menu item that runs a closure.
final class ClosureItem: NSMenuItem {
    private let handler: (ClosureItem) -> Void
    init(_ title: String, _ key: String = "", _ mods: NSEvent.ModifierFlags = .command, on: Bool = false,
         _ handler: @escaping (ClosureItem) -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        target = self
        keyEquivalentModifierMask = mods
        state = on ? .on : .off
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func fire() { handler(self) }
}

/// Submenu that rebuilds itself each time it opens (for track lists, chapters, etc.).
final class DynamicMenu: NSMenu, NSMenuDelegate {
    private let builder: (NSMenu) -> Void
    init(_ title: String, _ builder: @escaping (NSMenu) -> Void) {
        self.builder = builder
        super.init(title: title)
        delegate = self
    }
    required init(coder: NSCoder) { fatalError() }
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        builder(menu)
    }
}

extension NSMenu {
    @discardableResult
    func add(_ title: String, _ key: String = "", _ mods: NSEvent.ModifierFlags = .command, on: Bool = false,
             _ handler: @escaping (ClosureItem) -> Void) -> ClosureItem {
        let i = ClosureItem(title, key, mods, on: on, handler)
        addItem(i)
        return i
    }
    func addSub(_ title: String, _ builder: @escaping (NSMenu) -> Void) {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.submenu = DynamicMenu(title, builder)
        addItem(i)
    }
    func addStd(_ title: String, _ sel: Selector, _ key: String = "", _ mods: NSEvent.ModifierFlags = .command) {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        i.keyEquivalentModifierMask = mods
        addItem(i)
    }
}

extension PlayerController {
    // MARK: Dynamic submenus

    func fillAudioTrackMenu(_ m: NSMenu) {
        let t = audioTracks
        if t.isEmpty { m.addItem(withTitle: "No audio tracks", action: nil, keyEquivalent: ""); return }
        for (idx, name) in t {
            m.add(name, on: idx == Int(player.currentAudioTrackIndex)) { [weak self] _ in
                self?.player.currentAudioTrackIndex = Int32(idx)
                self?.osd("Audio: \(name)")
            }
        }
    }

    func fillSubtitleMenu(_ m: NSMenu) {
        let t = subTracks
        if t.isEmpty { m.addItem(withTitle: "No subtitles in this video", action: nil, keyEquivalent: "") }
        for (idx, name) in t {
            m.add(idx < 0 ? "Off" : name, on: idx == Int(player.currentVideoSubTitleIndex)) { [weak self] _ in
                self?.player.currentVideoSubTitleIndex = Int32(idx)
                self?.osd(idx < 0 ? "Subtitles off" : "Subtitle: \(name)")
            }
        }
        m.addItem(.separator())
        m.add("Find Subtitles Online… (O)") { [weak self] _ in self?.findSubtitlesOnline() }
        m.add("Load Subtitle File…") { [weak self] _ in self?.loadSubtitleFile() }
    }

    func fillChapterMenu(_ m: NSMenu) {
        let chapters = (player.chapterDescriptions(ofTitle: player.currentTitleIndex) as? [[String: Any]]) ?? []
        if chapters.isEmpty { m.addItem(withTitle: "No chapters", action: nil, keyEquivalent: ""); return }
        for (i, c) in chapters.enumerated() {
            let name = (c[VLCChapterDescriptionName] as? String) ?? "Chapter \(i + 1)"
            let off = (c[VLCChapterDescriptionTimeOffset] as? NSNumber)?.intValue ?? 0
            m.add("\(fmtMs(off))  \(name)", on: i == Int(player.currentChapterIndex)) { [weak self] _ in
                self?.player.currentChapterIndex = Int32(i)
            }
        }
    }

    func fillSpeedMenu(_ m: NSMenu) {
        for s: Float in [0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 3, 4] {
            m.add(String(format: "%.2gx", s), on: abs(speed - s) < 0.01) { [weak self] _ in self?.setSpeed(s) }
        }
    }

    func fillAspectMenu(_ m: NSMenu) {
        for a in aspects {
            m.add(a ?? "Default", on: aspects[aspectIndex] == a) { [weak self] _ in self?.setAspect(a) }
        }
        m.addItem(.separator())
        m.add("Fill Window (crop)  W", on: videoView.fillScreen) { [weak self] _ in self?.toggleFill() }
    }

    func fillEqualizerMenu(_ m: NSMenu) {
        m.add("Off", on: player.equalizer == nil) { [weak self] _ in self?.player.equalizer = nil; self?.osd("Equalizer off") }
        m.addItem(.separator())
        for p in VLCAudioEqualizer.presets {
            m.add(p.name) { [weak self] item in
                self?.player.equalizer = VLCAudioEqualizer(preset: p)
                self?.osd("Equalizer: \(p.name)")
            }
        }
    }

    func fillRepeatMenu(_ m: NSMenu) {
        for (i, name) in ["Repeat Off", "Repeat This File", "Repeat Playlist"].enumerated() {
            m.add(name, on: Prefs.repeatMode == i) { _ in Prefs.repeatMode = i }
        }
        m.addItem(.separator())
        m.add("Shuffle", on: shuffle) { [weak self] _ in
            guard let self else { return }
            self.shuffle.toggle()
            self.osd(self.shuffle ? "Shuffle on" : "Shuffle off")
        }
    }

    func contextMenu() -> NSMenu {
        let m = NSMenu()
        m.add(player.isPlaying ? "Pause" : "Play") { [weak self] _ in self?.togglePlay() }
        m.add("Open…") { [weak self] _ in self?.openFile() }
        m.addItem(.separator())
        m.addSub("Subtitles", fillSubtitleMenu)
        m.addSub("Audio Track", fillAudioTrackMenu)
        m.addSub("Speed", fillSpeedMenu)
        m.addSub("Aspect Ratio", fillAspectMenu)
        m.addSub("Chapters", fillChapterMenu)
        m.addSub("Equalizer", fillEqualizerMenu)
        m.addSub("Repeat / Shuffle", fillRepeatMenu)
        m.addItem(.separator())
        m.add("Take Screenshot") { [weak self] _ in self?.screenshot() }
        m.add("Show Playlist") { [weak self] _ in self?.togglePlaylist() }
        m.add(window.level == .floating ? "Turn Off Always on Top" : "Always on Top") { [weak self] _ in self?.toggleOnTop() }
        m.add("Full Screen") { [weak self] _ in self?.toggleFullScreen() }
        return m
    }

    func toggleOnTop() {
        window.level = window.level == .floating ? .normal : .floating
        osd(window.level == .floating ? "Always on top" : "Normal window")
    }

    // MARK: Main menu

    func buildMainMenu() {
        let main = NSMenu()
        func top(_ title: String) -> NSMenu {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let m = NSMenu(title: title)
            item.submenu = m
            main.addItem(item)
            return m
        }

        let app = top(appName)
        app.addStd("About \(appName)", #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
        app.add("Check for Updates on GitHub…") { _ in NSWorkspace.shared.open(repoURL.appendingPathComponent("releases")) }
        app.addItem(.separator())
        app.add("Settings…", ",") { [weak self] _ in self?.showSettings() }
        app.addItem(.separator())
        app.addStd("Hide \(appName)", #selector(NSApplication.hide(_:)), "h")
        app.addStd("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option])
        app.addStd("Show All", #selector(NSApplication.unhideAllApplications(_:)))
        app.addItem(.separator())
        app.addStd("Quit \(appName)", #selector(NSApplication.terminate(_:)), "q")

        let file = top("File")
        file.add("Open…", "o") { [weak self] _ in self?.openFile() }
        file.add("Add to Playlist…", "o", [.command, .shift]) { [weak self] _ in self?.addToPlaylist() }
        file.add("Open Network Stream…", "u") { [weak self] _ in self?.openURLPrompt() }
        file.addItem(.separator())
        file.add("Load Subtitle File…", "o", [.command, .option]) { [weak self] _ in self?.loadSubtitleFile() }
        file.add("Find Subtitles Online…", "f", [.command, .shift]) { [weak self] _ in self?.findSubtitlesOnline() }
        file.addItem(.separator())
        file.add("Show in Finder", "r", [.command, .shift]) { [weak self] _ in
            if let u = self?.currentURL, u.isFileURL { NSWorkspace.shared.activateFileViewerSelecting([u]) }
        }
        file.add("Show Screenshots Folder") { _ in
            try? FileManager.default.createDirectory(at: Prefs.screenshotDir, withIntermediateDirectories: true)
            NSWorkspace.shared.open(Prefs.screenshotDir)
        }
        file.addItem(.separator())
        file.addStd("Close Window", #selector(NSWindow.performClose(_:)), "w")

        let play = top("Playback")
        play.add("Play / Pause    Space") { [weak self] _ in self?.togglePlay() }
        play.add("Stop", ".") { [weak self] _ in self?.saveResume(); self?.player.stop() }
        play.add("Next File", String(UnicodeScalar(NSRightArrowFunctionKey)!), [.command, .option]) { [weak self] _ in self?.next() }
        play.add("Previous File", String(UnicodeScalar(NSLeftArrowFunctionKey)!), [.command, .option]) { [weak self] _ in self?.prev() }
        play.addItem(.separator())
        play.add("Jump Forward 5s    →") { [weak self] _ in self?.seek(by: 5) }
        play.add("Jump Back 5s    ←") { [weak self] _ in self?.seek(by: -5) }
        play.add("Next Frame    F") { [weak self] _ in self?.frameStep() }
        play.addSub("Speed", fillSpeedMenu)
        play.addSub("Chapters", fillChapterMenu)
        play.add("Next Chapter", "]", [.command]) { [weak self] _ in self?.player.nextChapter() }
        play.add("Previous Chapter", "[", [.command]) { [weak self] _ in self?.player.previousChapter() }
        play.addItem(.separator())
        play.add("Set A-B Repeat Point    [") { [weak self] _ in self?.setLoopPoint() }
        play.add("Clear A-B Repeat    \\") { [weak self] _ in self?.clearLoop() }
        play.addSub("Repeat / Shuffle", fillRepeatMenu)

        let audio = top("Audio")
        audio.addSub("Audio Track", fillAudioTrackMenu)
        audio.add("Volume Up    ↑") { [weak self] _ in guard let s = self else { return }; s.setVolume(Prefs.volume + 5) }
        audio.add("Volume Down    ↓") { [weak self] _ in guard let s = self else { return }; s.setVolume(Prefs.volume - 5) }
        audio.add("Mute    M") { [weak self] _ in self?.toggleMute() }
        audio.addItem(.separator())
        audio.add("Audio Delay +50 ms    =") { [weak self] _ in self?.shiftAudioDelay(50) }
        audio.add("Audio Delay −50 ms    -") { [weak self] _ in self?.shiftAudioDelay(-50) }
        audio.add("Reset Audio Delay") { [weak self] _ in self?.player.currentAudioPlaybackDelay = 0; self?.osd("Audio delay reset") }
        audio.addSub("Equalizer", fillEqualizerMenu)

        let subs = top("Subtitles")
        subs.addSub("Subtitle Track", fillSubtitleMenu)
        subs.add("Next Subtitle Track    V") { [weak self] _ in self?.cycleSubtitle() }
        subs.add("Find Subtitles Online…    O") { [weak self] _ in self?.findSubtitlesOnline() }
        subs.add("Load Subtitle File…") { [weak self] _ in self?.loadSubtitleFile() }
        subs.addItem(.separator())
        subs.add("Subtitle Delay +0.5s    .") { [weak self] _ in self?.shiftSubDelay(500) }
        subs.add("Subtitle Delay −0.5s    ,") { [weak self] _ in self?.shiftSubDelay(-500) }
        subs.add("Reset Subtitle Delay") { [weak self] _ in self?.player.currentVideoSubTitleDelay = 0; self?.osd("Subtitle delay reset") }

        let video = top("Video")
        video.add("Full Screen    Return", "f", [.command, .control]) { [weak self] _ in self?.toggleFullScreen() }
        video.add("Always on Top", "t") { [weak self] item in
            self?.toggleOnTop()
            item.state = self?.window.level == .floating ? .on : .off
        }
        video.add("Show / Hide Playlist    P", "l") { [weak self] _ in self?.togglePlaylist() }
        video.addItem(.separator())
        video.addSub("Aspect Ratio", fillAspectMenu)
        video.add("Deinterlace") { [weak self] item in
            self?.toggleDeinterlace()
            item.state = self?.deinterlace == true ? .on : .off
        }
        let adjust = NSMenu(title: "Picture")
        for (key, label) in [("brightness", "Brightness"), ("contrast", "Contrast"), ("saturation", "Saturation"), ("gamma", "Gamma")] {
            adjust.add("\(label) +") { [weak self] _ in self?.adjustVideo(key, by: 0.05) }
            adjust.add("\(label) −") { [weak self] _ in self?.adjustVideo(key, by: -0.05) }
        }
        adjust.addItem(.separator())
        adjust.add("Reset Picture") { [weak self] _ in self?.resetVideoAdjust() }
        let adjustItem = NSMenuItem(title: "Picture", action: nil, keyEquivalent: "")
        adjustItem.submenu = adjust
        video.addItem(adjustItem)
        video.addItem(.separator())
        video.add("Take Screenshot    S", "s", [.command, .shift]) { [weak self] _ in self?.screenshot() }
        video.add("Media Info    I") { [weak self] _ in self?.showInfo() }

        let win = top("Window")
        win.addStd("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")
        win.addStd("Zoom", #selector(NSWindow.performZoom(_:)))
        NSApp.windowsMenu = win

        let help = top("Help")
        help.add("Keyboard Shortcuts", "/") { [weak self] _ in self?.showShortcuts() }
        help.add("\(appName) on GitHub") { _ in NSWorkspace.shared.open(repoURL) }
        NSApp.helpMenu = help

        NSApp.mainMenu = main
    }

    @objc func showShortcuts() {
        let alert = NSAlert()
        alert.messageText = "Keyboard & Mouse Shortcuts"
        alert.informativeText = """
        Space / click — Play / Pause
        ← / → — Seek 5s  (⇧ 30s, ⌥ 60s)
        0 … 9 — Jump to 0% … 90%
        ↑ / ↓ or scroll — Volume (up to 200%)
        M — Mute
        C / X / Z — Faster / Slower / Normal speed
        F — Next frame
        Return or double-click — Full screen
        N / B, PgDn / PgUp — Next / Previous file
        P — Playlist (Delete removes selected)
        L — Repeat: off / file / playlist
        S — Screenshot (Pictures/\(appName))
        [ … [ / \\ — A-B repeat: set A then B / clear
        V — Next subtitle track,  A — Next audio track
        O — Find subtitles online
        , / . — Subtitle delay −/+ 0.5s
        - / = — Audio delay −/+ 50ms
        R — Aspect ratio,  W — Fill window
        I — Media info
        ⌘O Open  •  ⌘U Stream  •  ⌘, Settings  •  ⌘T On top
        Right-click the video for more.
        """
        alert.beginSheetModal(for: window)
    }
}
