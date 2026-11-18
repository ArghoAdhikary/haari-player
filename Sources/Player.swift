import Cocoa
import VLCKit
import MediaPlayer

final class PlayerController: NSObject, NSWindowDelegate, VLCMediaPlayerDelegate, NSTableViewDataSource, NSTableViewDelegate {
    let window: NSWindow
    let root = DropView()
    let videoView = VLCVideoView()
    let catcher = EventView()
    let controls = ControlBar()
    let osdLabel = NSTextField(labelWithString: "")
    let hint = NSStackView()
    let table = NSTableView()
    let tableScroll = NSScrollView()
    var playlistWidth: NSLayoutConstraint!
    let player: VLCMediaPlayer
    let finder = SubtitleFinder()
    var searchPanel: SubtitleSearchPanel?
    var settings: SettingsController?

    var playlist: [URL] = []
    var index = -1
    var currentURL: URL? { playlist.indices.contains(index) ? playlist[index] : nil }
    var speed: Float = 1
    var shuffle = false
    var loopA: Int?
    var loopB: Int?
    var pendingResume: Int?
    var volumeApplied = false
    var advancing = false
    var hideTimer: Timer?
    var clickWork: DispatchWorkItem?
    var osdWork: DispatchWorkItem?
    var activity: NSObjectProtocol?
    var lastSave = Date.distantPast
    var noKeyHintShown = false
    var scrollAccum: CGFloat = 0
    var aspectIndex = 0
    let aspects: [String?] = [nil, "16:9", "4:3", "21:9", "2.35:1", "1.85:1", "16:10", "5:4", "1:1"]
    var deinterlace = false

    var timeMs: Int { Int(player.time.intValue) }
    var lengthMs: Int { Int(player.media?.length.intValue ?? 0) }

    override init() {
        player = VLCMediaPlayer(options: [
            "--no-video-title-show",
            "--sub-text-scale=\(max(10, min(500, Prefs.subSize)))",
            "--sub-autodetect-fuzzy=3",
        ])
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 600),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        super.init()
        window.title = appName
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .black
        window.appearance = NSAppearance(named: .darkAqua)
        window.minSize = NSSize(width: 520, height: 320)
        window.collectionBehavior = [.fullScreenPrimary]
        window.delegate = self
        window.contentView = root
        window.center()
        window.setFrameAutosaveName("MainWindow")

        player.delegate = self
        player.drawable = videoView
        videoView.backColor = .black
        buildUI()
        setupRemoteCommands()

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, e.window === self.window else { return e }
            return self.handleKey(e) ? nil : e
        }
    }

    // MARK: - UI

    func buildUI() {
        root.onDrop = { [weak self] urls in self?.open(urls) }
        root.onMouseMoved = { [weak self] in self?.userActivity() }
        catcher.onClick = { [weak self] in self?.singleClick() }
        catcher.onDoubleClick = { [weak self] in
            self?.clickWork?.cancel()
            self?.toggleFullScreen()
        }
        catcher.onScroll = { [weak self] dy in self?.scrolled(dy) }
        catcher.contextMenu = { [weak self] in self?.contextMenu() }

        let col = NSTableColumn(identifier: .init("name"))
        col.title = "Playlist"
        table.addTableColumn(col)
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 24
        table.allowsMultipleSelection = true
        table.target = self
        table.doubleAction = #selector(tableDoubleClick)
        tableScroll.documentView = table
        tableScroll.hasVerticalScroller = true
        tableScroll.isHidden = true

        osdLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        osdLabel.textColor = .white
        osdLabel.drawsBackground = true
        osdLabel.backgroundColor = NSColor.black.withAlphaComponent(0.6)
        osdLabel.isHidden = true

        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.widthAnchor.constraint(equalToConstant: 140).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 140).isActive = true
        let t1 = NSTextField(labelWithString: "Drop a video here, or press ⌘O")
        t1.font = .systemFont(ofSize: 18, weight: .semibold)
        t1.textColor = .white
        let t2 = NSTextField(labelWithString: "MKV, MP4, AVI, WebM, MOV, FLV, TS, audio… everything plays.  ⌘/ shows shortcuts.")
        t2.font = .systemFont(ofSize: 13)
        t2.textColor = .secondaryLabelColor
        hint.setViews([icon, t1, t2], in: .center)
        hint.orientation = .vertical
        hint.spacing = 10

        controls.playButton.target = self; controls.playButton.action = #selector(togglePlay)
        controls.prevButton.target = self; controls.prevButton.action = #selector(prev)
        controls.nextButton.target = self; controls.nextButton.action = #selector(next)
        controls.fullButton.target = self; controls.fullButton.action = #selector(toggleFullScreen)
        controls.playlistButton.target = self; controls.playlistButton.action = #selector(togglePlaylist)
        controls.muteButton.target = self; controls.muteButton.action = #selector(toggleMute)
        controls.subButton.target = self; controls.subButton.action = #selector(showSubMenu(_:))
        controls.audioButton.target = self; controls.audioButton.action = #selector(showAudioMenu(_:))
        controls.seek.target = self; controls.seek.action = #selector(seekSlid)
        controls.volume.target = self; controls.volume.action = #selector(volumeSlid)
        controls.volume.integerValue = Prefs.volume
        controls.setMuted(false, volume: Prefs.volume)

        for v in [videoView, catcher, hint, osdLabel, controls, tableScroll] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(v)
        }
        playlistWidth = tableScroll.widthAnchor.constraint(equalToConstant: 0)
        let barWidth = controls.widthAnchor.constraint(equalTo: videoView.widthAnchor, constant: -32)
        barWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            videoView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            videoView.topAnchor.constraint(equalTo: root.topAnchor),
            videoView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            videoView.trailingAnchor.constraint(equalTo: tableScroll.leadingAnchor),
            catcher.leadingAnchor.constraint(equalTo: videoView.leadingAnchor),
            catcher.trailingAnchor.constraint(equalTo: videoView.trailingAnchor),
            catcher.topAnchor.constraint(equalTo: videoView.topAnchor),
            catcher.bottomAnchor.constraint(equalTo: videoView.bottomAnchor),
            hint.centerXAnchor.constraint(equalTo: videoView.centerXAnchor),
            hint.centerYAnchor.constraint(equalTo: videoView.centerYAnchor),
            osdLabel.leadingAnchor.constraint(equalTo: videoView.leadingAnchor, constant: 20),
            osdLabel.topAnchor.constraint(equalTo: videoView.topAnchor, constant: 44),
            osdLabel.trailingAnchor.constraint(lessThanOrEqualTo: videoView.trailingAnchor, constant: -20),
            controls.centerXAnchor.constraint(equalTo: videoView.centerXAnchor),
            controls.bottomAnchor.constraint(equalTo: videoView.bottomAnchor, constant: -16),
            controls.widthAnchor.constraint(lessThanOrEqualToConstant: 880),
            controls.leadingAnchor.constraint(greaterThanOrEqualTo: videoView.leadingAnchor, constant: 16),
            barWidth,
            tableScroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            tableScroll.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor),
            tableScroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            playlistWidth,
        ])
        controls.isHidden = true
    }

    // MARK: - Opening

    func mediaFiles(in dir: URL) -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return items.filter { mediaExts.contains($0.pathExtension.lowercased()) && !playlistExts.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// Expands a local .m3u/.pls style list into entries (HLS streams are kept as a single item).
    func expandPlaylistFile(_ url: URL) -> [URL]? {
        guard url.isFileURL, ["m3u", "m3u8", "pls"].contains(url.pathExtension.lowercased()),
              let text = try? String(contentsOf: url, encoding: .utf8), !text.contains("#EXT-X-") else { return nil }
        let base = url.deletingLastPathComponent()
        return text.components(separatedBy: .newlines).compactMap { raw in
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.lowercased().hasPrefix("file"), let eq = line.firstIndex(of: "=") { line = String(line[line.index(after: eq)...]) }
            guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix("[") else { return nil }
            if let u = URL(string: line), u.scheme != nil, u.scheme != "file" { return u }
            return line.hasPrefix("/") ? URL(fileURLWithPath: line) : base.appendingPathComponent(line)
        }
    }

    func open(_ urls: [URL], append: Bool = false) {
        var media: [URL] = []
        var subFiles: [URL] = []
        for u in urls {
            var isDir: ObjCBool = false
            if u.isFileURL, FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir), isDir.boolValue {
                media += mediaFiles(in: u)
            } else if subExts.contains(u.pathExtension.lowercased()) {
                subFiles.append(u)
            } else if let list = expandPlaylistFile(u) {
                media += list
            } else {
                media.append(u)
            }
        }
        if append, !media.isEmpty {
            let wasEmpty = playlist.isEmpty
            playlist += media
            table.reloadData()
            if wasEmpty { load(0) } else { osd("Added \(media.count) to playlist") }
        } else if media.count == 1, media[0].isFileURL {
            // Queue up the rest of the folder too, so Next/Previous just work.
            let file = media[0]
            var siblings = mediaFiles(in: file.deletingLastPathComponent())
            if !siblings.contains(file) { siblings = [file] }
            playlist = siblings
            load(siblings.firstIndex(of: file) ?? 0)
        } else if !media.isEmpty {
            playlist = media
            load(0)
        }
        for s in subFiles { attachSubtitle(s) }
    }

    func load(_ i: Int) {
        guard playlist.indices.contains(i) else { return }
        saveResume()
        index = i
        let url = playlist[i]
        advancing = false
        volumeApplied = false
        loopA = nil
        loopB = nil
        pendingResume = Prefs.resume && url.isFileURL ? UserDefaults.standard.object(forKey: resumeKey(url)) as? Int : nil
        player.media = VLCMedia(url: url)
        player.play()
        window.title = url.isFileURL ? url.lastPathComponent : url.absoluteString
        window.representedURL = url.isFileURL ? url : nil
        hint.isHidden = true
        controls.isHidden = false
        userActivity()
        table.reloadData()
        table.scrollRowToVisible(i)
        if url.isFileURL { NSDocumentController.shared.noteNewRecentDocumentURL(url) }
        scheduleAutoSubtitles(for: url)
    }

    // MARK: - VLC events

    func mediaPlayerStateChanged(_ aNotification: Notification) {
        DispatchQueue.main.async { self.stateChanged() }
    }

    func mediaPlayerTimeChanged(_ aNotification: Notification) {
        DispatchQueue.main.async { self.timeChanged() }
    }

    func mediaPlayerSnapshot(_ aNotification: Notification) {
        DispatchQueue.main.async { self.osd("Screenshot saved to Pictures/\(appName)") }
    }

    func stateChanged() {
        switch player.state {
        case .playing:
            if !volumeApplied {
                volumeApplied = true
                player.audio?.volume = Int32(Prefs.volume)
            }
            if player.rate != speed { player.rate = speed }
            beginActivity()
        case .ended:
            endActivity()
            finished()
        case .error:
            endActivity()
            osd("Couldn't play \(currentURL?.lastPathComponent ?? "this file")", 4)
        case .paused, .stopped:
            endActivity()
        default: break
        }
        let playing = [.playing, .buffering, .opening].contains(player.state)
        controls.setPlaying(playing)
        if !playing { showControls() }
        updateNowPlaying()
    }

    func timeChanged() {
        let t = timeMs, len = lengthMs
        if let r = pendingResume, len > 0 {
            pendingResume = nil
            if r < len - 10_000 {
                player.time = VLCTime(int: Int32(r))
                osd("Resumed at \(fmtMs(r))  •  press ← ← or 0 to start over")
            }
        }
        if let a = loopA, let b = loopB, t >= b { player.time = VLCTime(int: Int32(a)) }
        controls.update(time: t, length: len)
        if Date().timeIntervalSince(lastSave) > 5 {
            lastSave = Date()
            saveResume()
        }
    }

    func finished() {
        guard !advancing else { return }
        advancing = true
        if let u = currentURL { UserDefaults.standard.removeObject(forKey: resumeKey(u)) }
        switch Prefs.repeatMode {
        case 1: load(index)
        case 2: playlist.count > 0 ? load(nextIndex(wrap: true)) : ()
        default:
            let n = nextIndex(wrap: false)
            if playlist.indices.contains(n) { load(n) } else { osd("End of playlist") }
        }
    }

    func nextIndex(wrap: Bool) -> Int {
        if shuffle, playlist.count > 1 {
            var r = index
            while r == index { r = Int.random(in: 0..<playlist.count) }
            return r
        }
        if index + 1 < playlist.count { return index + 1 }
        return wrap ? 0 : playlist.count
    }

    // MARK: - Resume

    func resumeKey(_ url: URL) -> String { "resume:" + url.path }

    func saveResume() {
        guard Prefs.resume, let url = currentURL, url.isFileURL, player.media != nil else { return }
        let t = timeMs, len = lengthMs
        if len > 0, t > 15_000, t < len - 15_000 { UserDefaults.standard.set(t, forKey: resumeKey(url)) }
        else if len > 0 { UserDefaults.standard.removeObject(forKey: resumeKey(url)) }
    }

    // MARK: - Subtitles

    func hasSubtitleTrack() -> Bool {
        ((player.videoSubTitlesIndexes as? [NSNumber]) ?? []).contains { $0.intValue >= 0 }
    }

    func attachSubtitle(_ url: URL, announce: Bool = true) {
        guard player.media != nil else { osd("Open a video first"); return }
        player.addPlaybackSlave(url, type: .subtitle, enforce: true)
        if announce { osd("Subtitle: \(url.lastPathComponent)") }
    }

    func scheduleAutoSubtitles(for url: URL) {
        guard url.isFileURL, videoExts.contains(url.pathExtension.lowercased()) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in self?.autoSubtitles(for: url) }
    }

    func autoSubtitles(for url: URL) {
        guard currentURL == url, Prefs.autoDownloadSubs, !hasSubtitleTrack() else { return }
        guard SubtitleFinder.hasAnyKey else {
            if !noKeyHintShown {
                noKeyHintShown = true
                osd("No subtitles here. Add a free API key in Settings (⌘,) to auto-download them.", 5)
            }
            return
        }
        osd("Searching subtitles online…", 15)
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let results = try await self.finder.search(for: url, languages: Prefs.subLanguages)
                guard let best = results.first else { throw SubError.noResults }
                let file = try await self.finder.download(best, for: url)
                guard self.currentURL == url else { return }
                self.attachSubtitle(file, announce: false)
                self.osd("Subtitle downloaded: \(best.language.uppercased())\(best.hashMatch ? " • exact match" : "") • \(best.source.rawValue)", 3)
            } catch {
                if self.currentURL == url { self.osd(error.localizedDescription, 4) }
            }
        }
    }

    @objc func findSubtitlesOnline() {
        guard let url = currentURL, url.isFileURL else { osd("Open a video file first"); return }
        guard SubtitleFinder.hasAnyKey else { showSettings(); osd("Add an API key first", 3); return }
        searchPanel = SubtitleSearchPanel(video: url) { [weak self] r in
            guard let self else { return }
            self.osd("Downloading subtitle…", 10)
            Task { @MainActor in
                do {
                    let file = try await self.finder.download(r, for: url)
                    if self.currentURL == url { self.attachSubtitle(file, announce: false); self.osd("Subtitle loaded: \(r.release)") }
                } catch { self.osd(error.localizedDescription, 4) }
            }
        }
        searchPanel?.show(over: window)
    }

    // MARK: - Playback actions

    func osd(_ text: String, _ seconds: Double = 1.6) {
        osdLabel.stringValue = "  \(text)  "
        osdLabel.isHidden = false
        osdWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.osdLabel.isHidden = true }
        osdWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    @objc func togglePlay() {
        guard player.media != nil else { openFile(); return }
        if player.isPlaying {
            player.pause()
            osd("❚❚ Paused")
        } else {
            if player.state == .ended || player.state == .stopped { load(index); return }
            player.play()
            osd("▶ Play")
        }
    }

    @objc func next() { if !playlist.isEmpty { let n = nextIndex(wrap: Prefs.repeatMode == 2); if playlist.indices.contains(n) { load(n) } else { osd("Last file") } } }
    @objc func prev() {
        guard !playlist.isEmpty else { return }
        if timeMs > 5_000 { player.time = VLCTime(int: 0); return }
        if index > 0 { load(index - 1) } else { osd("First file") }
    }

    func seek(by seconds: Int) {
        guard player.media != nil else { return }
        guard player.isSeekable else { osd("This stream can't be seeked"); return }
        var target = timeMs + seconds * 1000
        if lengthMs > 0 { target = min(target, lengthMs - 500) }
        target = max(0, target)
        player.time = VLCTime(int: Int32(target))
        osd("\(seconds > 0 ? "▶▶ +" : "◀◀ ")\(seconds)s   \(fmtMs(target)) / \(fmtMs(lengthMs))")
        updateNowPlaying()
    }

    func seek(toFraction f: Double) {
        guard player.media != nil, player.isSeekable else { return }
        player.position = Float(f)
        osd("\(fmtMs(Int(Double(lengthMs) * f))) / \(fmtMs(lengthMs))")
    }

    @objc func seekSlid() {
        guard player.media != nil, player.isSeekable else { return }
        player.position = Float(controls.seek.doubleValue / 1000)
        controls.timeLabel.stringValue = fmtMs(Int(Double(lengthMs) * controls.seek.doubleValue / 1000))
    }

    func setSpeed(_ v: Float) {
        speed = min(8, max(0.1, (v * 100).rounded() / 100))
        player.rate = speed
        controls.speedLabel.stringValue = speed == 1 ? "" : String(format: "%.2fx", speed)
        osd(String(format: "Speed %.2fx", speed))
    }

    func setVolume(_ v: Int, announce: Bool = true) {
        let vol = min(200, max(0, v))
        player.audio?.isMuted = false
        player.audio?.volume = Int32(vol)
        Prefs.volume = vol
        controls.volume.integerValue = vol
        controls.setMuted(false, volume: vol)
        if announce { osd("Volume \(vol)%\(vol > 100 ? " (boost)" : "")") }
    }

    @objc func volumeSlid() { setVolume(controls.volume.integerValue, announce: false) }

    @objc func toggleMute() {
        guard let audio = player.audio else { return }
        audio.isMuted.toggle()
        controls.setMuted(audio.isMuted, volume: Prefs.volume)
        osd(audio.isMuted ? "Muted" : "Volume \(Prefs.volume)%")
    }

    func scrolled(_ dy: CGFloat) {
        scrollAccum += dy
        while abs(scrollAccum) >= 1 {
            let step = scrollAccum > 0 ? 2 : -2
            scrollAccum -= scrollAccum > 0 ? 1 : -1
            setVolume(Prefs.volume + step)
        }
    }

    func singleClick() {
        guard Prefs.clickToPause, player.media != nil else { return }
        clickWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.togglePlay() }
        clickWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: work)
    }

    func frameStep() {
        guard player.media != nil else { return }
        player.gotoNextFrame()
        osd("Next frame ▸")
    }

    @objc func screenshot() {
        guard let url = currentURL, player.hasVideoOut else { osd("No video to capture"); return }
        let dir = Prefs.screenshotDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let base = url.deletingPathExtension().lastPathComponent
        let file = dir.appendingPathComponent("\(base) \(fmtMs(timeMs).replacingOccurrences(of: ":", with: "-")).png")
        player.saveVideoSnapshot(at: file.path, withWidth: 0, andHeight: 0)
    }

    func setLoopPoint() {
        guard player.media != nil else { return }
        if loopA == nil || loopB != nil {
            loopA = timeMs; loopB = nil
            osd("A-B repeat: A = \(fmtMs(loopA!)). Press [ again to set B")
        } else if let a = loopA, timeMs > a + 500 {
            loopB = timeMs
            osd("A-B repeat: \(fmtMs(a)) → \(fmtMs(loopB!))  (\\ to clear)")
        }
    }

    func clearLoop() { loopA = nil; loopB = nil; osd("A-B repeat off") }

    func shiftSubDelay(_ ms: Int) {
        player.currentVideoSubTitleDelay += ms * 1000
        osd(String(format: "Subtitle delay %+.1fs", Double(player.currentVideoSubTitleDelay) / 1_000_000))
    }

    func shiftAudioDelay(_ ms: Int) {
        player.currentAudioPlaybackDelay += ms * 1000
        osd(String(format: "Audio delay %+.0f ms", Double(player.currentAudioPlaybackDelay) / 1000))
    }

    func tracks(_ idx: [Any]?, _ names: [Any]?) -> [(Int, String)] {
        zip((idx as? [NSNumber]) ?? [], (names as? [String]) ?? []).map { ($0.intValue, $1) }
    }
    var audioTracks: [(Int, String)] { tracks(player.audioTrackIndexes, player.audioTrackNames) }
    var subTracks: [(Int, String)] { tracks(player.videoSubTitlesIndexes, player.videoSubTitlesNames) }

    func cycleAudio() {
        let t = audioTracks.filter { $0.0 >= 0 }
        guard t.count > 1 else { osd(t.isEmpty ? "No audio" : "Only one audio track"); return }
        let i = t.firstIndex { $0.0 == Int(player.currentAudioTrackIndex) } ?? -1
        let n = t[(i + 1) % t.count]
        player.currentAudioTrackIndex = Int32(n.0)
        osd("Audio: \(n.1)")
    }

    func cycleSubtitle() {
        let t = subTracks
        guard t.contains(where: { $0.0 >= 0 }) else { osd("No subtitles — press O to search online"); return }
        let i = t.firstIndex { $0.0 == Int(player.currentVideoSubTitleIndex) } ?? -1
        let n = t[(i + 1) % t.count]
        player.currentVideoSubTitleIndex = Int32(n.0)
        osd(n.0 < 0 ? "Subtitles off" : "Subtitle: \(n.1)")
    }

    func cycleAspect() {
        aspectIndex = (aspectIndex + 1) % aspects.count
        setAspect(aspects[aspectIndex])
    }

    func setAspect(_ a: String?) {
        aspectIndex = aspects.firstIndex(of: a) ?? 0
        player.videoAspectRatio = a.map { strdup($0) }
        osd("Aspect ratio: \(a ?? "Default")")
    }

    func toggleFill() {
        videoView.fillScreen.toggle()
        osd(videoView.fillScreen ? "Zoom: fill window (crop)" : "Zoom: fit")
    }

    func toggleDeinterlace() {
        deinterlace.toggle()
        player.setDeinterlaceFilter(deinterlace ? "yadif" : nil)
        osd(deinterlace ? "Deinterlace on" : "Deinterlace off")
    }

    func adjustVideo(_ key: String, by delta: Float) {
        let f = player.adjustFilter
        f.isEnabled = true
        let param: VLCFilterParameterProtocol? = key == "brightness" ? f.brightness : key == "contrast" ? f.contrast : key == "saturation" ? f.saturation : f.gamma
        guard let p = param, let cur = (p.value as? NSNumber)?.floatValue,
              let lo = (p.minValue as? NSNumber)?.floatValue, let hi = (p.maxValue as? NSNumber)?.floatValue else { return }
        let v = min(hi, max(lo, cur + delta))
        p.value = NSNumber(value: v)
        osd(String(format: "%@ %.2f", key.capitalized, v))
    }

    func resetVideoAdjust() {
        _ = player.adjustFilter.resetParametersIfNeeded()
        player.adjustFilter.isEnabled = false
        osd("Picture reset")
    }

    func showInfo() {
        guard let url = currentURL else { return }
        var parts = [url.lastPathComponent, "\(fmtMs(timeMs)) / \(fmtMs(lengthMs))"]
        let size = player.videoSize
        if size.width > 0 { parts.append("\(Int(size.width))×\(Int(size.height))") }
        parts.append(String(format: "%.2fx", speed))
        parts.append("\(index + 1)/\(playlist.count)")
        if let a = audioTracks.first(where: { $0.0 == Int(player.currentAudioTrackIndex) }) { parts.append("Audio: \(a.1)") }
        if let s = subTracks.first(where: { $0.0 == Int(player.currentVideoSubTitleIndex) && $0.0 >= 0 }) { parts.append("Sub: \(s.1)") }
        osd(parts.joined(separator: "  •  "), 4)
    }

    // MARK: - Keyboard

    func handleKey(_ e: NSEvent) -> Bool {
        let f = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if f.contains(.command) || f.contains(.control) { return false }
        if let fr = window.firstResponder as? NSText, fr.isEditable { return false }
        if window.firstResponder === table, [51, 117].contains(e.keyCode) { removeSelectedFromPlaylist(); return true }
        let shift = f.contains(.shift), opt = f.contains(.option)
        let jump = shift ? 30 : opt ? 60 : 5
        userActivity()
        switch e.keyCode {
        case 49: togglePlay(); return true                  // space
        case 123: seek(by: -jump); return true              // ←
        case 124: seek(by: jump); return true               // →
        case 126: setVolume(Prefs.volume + 5); return true  // ↑
        case 125: setVolume(Prefs.volume - 5); return true  // ↓
        case 36, 76: toggleFullScreen(); return true        // return / enter
        case 116: prev(); return true                       // page up
        case 121: next(); return true                       // page down
        case 53:                                            // esc
            if window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil); return true }
            return false
        default: break
        }
        let ch = e.charactersIgnoringModifiers?.lowercased() ?? ""
        if let d = Int(ch), ch.count == 1 { seek(toFraction: Double(d) / 10); return true }
        switch ch {
        case "c": setSpeed(speed + 0.1)
        case "x": setSpeed(speed - 0.1)
        case "z": setSpeed(1)
        case "m": toggleMute()
        case "f": frameStep()
        case "s": screenshot()
        case "i": showInfo()
        case "p": togglePlaylist()
        case "n": next()
        case "b": prev()
        case "[": setLoopPoint()
        case "]": setLoopPoint()
        case "\\": clearLoop()
        case ",", "<": shiftSubDelay(-500)
        case ".", ">": shiftSubDelay(500)
        case "-", "_": shiftAudioDelay(-50)
        case "=", "+": shiftAudioDelay(50)
        case "v": cycleSubtitle()
        case "a": cycleAudio()
        case "o": findSubtitlesOnline()
        case "r": cycleAspect()
        case "w": toggleFill()
        case "l": cycleRepeat()
        default: return false
        }
        return true
    }

    func cycleRepeat() {
        Prefs.repeatMode = (Prefs.repeatMode + 1) % 3
        osd(["Repeat off", "Repeat this file", "Repeat playlist"][Prefs.repeatMode])
    }

    // MARK: - Controls auto-hide

    func userActivity() {
        showControls()
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in self?.maybeHideControls() }
    }

    func showControls() {
        guard player.media != nil else { return }
        controls.isHidden = false
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; controls.animator().alphaValue = 1 }
    }

    func maybeHideControls() {
        guard player.isPlaying else { return }
        let mouse = root.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        if controls.frame.contains(mouse) { userActivity(); return }
        NSAnimationContext.runAnimationGroup { $0.duration = 0.4; controls.animator().alphaValue = 0 }
        if window.isKeyWindow { NSCursor.setHiddenUntilMouseMoves(true) }
    }

    // MARK: - Panels and windows

    @objc func openFile() { runOpenPanel(append: false) }
    @objc func addToPlaylist() { runOpenPanel(append: true) }

    func runOpenPanel(append: Bool) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.message = append ? "Add files or folders to the playlist" : "Choose videos, music or a folder"
        panel.beginSheetModal(for: window) { [weak self] r in
            if r == .OK { self?.open(panel.urls, append: append) }
        }
    }

    @objc func openURLPrompt() {
        let alert = NSAlert()
        alert.messageText = "Open Network Stream"
        alert.informativeText = "Paste a link to a video or stream (http, https, HLS .m3u8, rtsp, rtmp…)."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 24))
        field.placeholderString = "https://example.com/video.mp4"
        if let s = NSPasteboard.general.string(forType: .string), s.contains("://") { field.stringValue = s }
        alert.accessoryView = field
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] r in
            guard r == .alertFirstButtonReturn, let u = URL(string: field.stringValue.trimmingCharacters(in: .whitespaces)), u.scheme != nil else { return }
            self?.playlist = [u]
            self?.load(0)
        }
    }

    @objc func loadSubtitleFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = subExts.compactMap { .init(filenameExtension: $0) }
        panel.beginSheetModal(for: window) { [weak self] r in
            if r == .OK, let u = panel.url { self?.attachSubtitle(u) }
        }
    }

    @objc func showSettings() {
        if settings == nil { settings = SettingsController() }
        settings?.window.makeKeyAndOrderFront(nil)
    }

    @objc func togglePlaylist() {
        let show = tableScroll.isHidden
        tableScroll.isHidden = false
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            ctx.allowsImplicitAnimation = true
            playlistWidth.animator().constant = show ? 280 : 0
            root.layoutSubtreeIfNeeded()
        }, completionHandler: { [weak self] in
            if !show { self?.tableScroll.isHidden = true }
        })
    }

    @objc func toggleFullScreen() { window.toggleFullScreen(nil) }

    @objc func showSubMenu(_ sender: NSButton) {
        let m = NSMenu()
        fillSubtitleMenu(m)
        m.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc func showAudioMenu(_ sender: NSButton) {
        let m = NSMenu()
        fillAudioTrackMenu(m)
        m.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc func tableDoubleClick() { if table.clickedRow >= 0 { load(table.clickedRow) } }

    func removeSelectedFromPlaylist() {
        let rows = table.selectedRowIndexes
        guard !rows.isEmpty else { return }
        let current = currentURL
        playlist = playlist.enumerated().filter { !rows.contains($0.offset) }.map(\.element)
        index = current.flatMap { playlist.firstIndex(of: $0) } ?? -1
        table.reloadData()
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int { playlist.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cell")
        let tf = (tableView.makeView(withIdentifier: id, owner: self) as? NSTextField) ?? {
            let t = NSTextField(labelWithString: "")
            t.identifier = id
            t.lineBreakMode = .byTruncatingMiddle
            return t
        }()
        let current = row == index
        let u = playlist[row]
        tf.stringValue = (current ? "▶ " : "    ") + (u.isFileURL ? u.lastPathComponent : u.absoluteString)
        tf.font = current ? .boldSystemFont(ofSize: 13) : .systemFont(ofSize: 13)
        tf.textColor = current ? .systemOrange : .labelColor
        return tf
    }

    // MARK: - System integration

    func beginActivity() {
        guard activity == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(options: [.idleDisplaySleepDisabled, .userInitiated], reason: "Playing media")
    }

    func endActivity() {
        if let a = activity { ProcessInfo.processInfo.endActivity(a) }
        activity = nil
    }

    func setupRemoteCommands() {
        let cc = MPRemoteCommandCenter.shared()
        cc.togglePlayPauseCommand.addTarget { [weak self] _ in self?.togglePlay(); return .success }
        cc.playCommand.addTarget { [weak self] _ in self?.player.play(); return .success }
        cc.pauseCommand.addTarget { [weak self] _ in self?.player.pause(); return .success }
        cc.nextTrackCommand.addTarget { [weak self] _ in self?.next(); return .success }
        cc.previousTrackCommand.addTarget { [weak self] _ in self?.prev(); return .success }
        cc.changePlaybackPositionCommand.addTarget { [weak self] e in
            guard let self, let e = e as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self.player.time = VLCTime(int: Int32(e.positionTime * 1000))
            return .success
        }
    }

    func updateNowPlaying() {
        guard let url = currentURL else { return }
        let playing = player.isPlaying
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: url.deletingPathExtension().lastPathComponent,
            MPMediaItemPropertyPlaybackDuration: Double(lengthMs) / 1000,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: Double(timeMs) / 1000,
            MPNowPlayingInfoPropertyPlaybackRate: playing ? Double(speed) : 0,
        ]
        MPNowPlayingInfoCenter.default().playbackState = playing ? .playing : .paused
    }

    // MARK: - Window

    func windowWillClose(_ notification: Notification) {
        saveResume()
        player.stop()
    }

    func windowDidEnterFullScreen(_ notification: Notification) { userActivity() }
}
