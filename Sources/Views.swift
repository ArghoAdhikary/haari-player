import Cocoa

/// Window background that accepts dropped files and reports mouse movement.
final class DropView: NSView {
    var onDrop: (([URL]) -> Void)?
    var onMouseMoved: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        registerForDraggedTypes([.fileURL, .URL])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect, .mouseEnteredAndExited],
                                       owner: self, userInfo: nil))
    }
    override func mouseMoved(with event: NSEvent) { onMouseMoved?() }
    override func mouseEntered(with event: NSEvent) { onMouseMoved?() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty else { return false }
        onDrop?(urls)
        return true
    }
}

/// Transparent layer over the video that turns clicks, double-clicks, drags and scrolls into player actions.
final class EventView: NSView {
    var onClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?
    var onScroll: ((CGFloat) -> Void)?
    var contextMenu: (() -> NSMenu?)?
    private var dragged = false

    override func mouseDown(with event: NSEvent) {
        dragged = false
        if event.clickCount == 2 { onDoubleClick?() }
    }
    override func mouseDragged(with event: NSEvent) {
        dragged = true
        if window?.styleMask.contains(.fullScreen) == false { window?.performDrag(with: event) }
    }
    override func mouseUp(with event: NSEvent) {
        if event.clickCount == 1 && !dragged { onClick?() }
    }
    override func scrollWheel(with event: NSEvent) { onScroll?(event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 0.25 : 2)) }
    override func menu(for event: NSEvent) -> NSMenu? { contextMenu?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Slider that knows when the user is dragging it, so playback updates don't fight the drag.
final class TrackingSlider: NSSlider {
    private(set) var isDragging = false
    override func mouseDown(with event: NSEvent) {
        isDragging = true
        super.mouseDown(with: event)
        isDragging = false
    }
}

final class ControlBar: NSVisualEffectView {
    let prevButton = ControlBar.button("backward.end.fill", "Previous (B)")
    let playButton = ControlBar.button("play.fill", "Play / Pause (Space)", size: 20)
    let nextButton = ControlBar.button("forward.end.fill", "Next (N)")
    let subButton = ControlBar.button("captions.bubble", "Subtitles (V)")
    let audioButton = ControlBar.button("waveform", "Audio track (A)")
    let muteButton = ControlBar.button("speaker.wave.2.fill", "Mute (M)")
    let playlistButton = ControlBar.button("list.bullet", "Playlist (P)")
    let fullButton = ControlBar.button("arrow.up.left.and.arrow.down.right", "Full screen (Return)")
    let seek = TrackingSlider(value: 0, minValue: 0, maxValue: 1000, target: nil, action: nil)
    let volume = NSSlider(value: 100, minValue: 0, maxValue: 200, target: nil, action: nil)
    let timeLabel = ControlBar.label("00:00")
    let remainLabel = ControlBar.label("00:00")
    let speedLabel = ControlBar.label("")

    static func button(_ sym: String, _ tip: String, size: CGFloat = 15) -> NSButton {
        let b = NSButton(image: symbol(sym, tip, size: size) ?? NSImage(), target: nil, action: nil)
        b.isBordered = false
        b.contentTintColor = .white
        b.toolTip = tip
        b.setButtonType(.momentaryChange)
        b.widthAnchor.constraint(equalToConstant: size + 14).isActive = true
        return b
    }

    static func label(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        l.textColor = NSColor.white.withAlphaComponent(0.85)
        return l
    }

    init() {
        super.init(frame: .zero)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        appearance = NSAppearance(named: .vibrantDark)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.masksToBounds = true
        translatesAutoresizingMaskIntoConstraints = false

        seek.isContinuous = true
        seek.controlSize = .small
        volume.isContinuous = true
        volume.controlSize = .small
        volume.toolTip = "Volume (↑ / ↓, up to 200%)"
        volume.widthAnchor.constraint(equalToConstant: 90).isActive = true
        remainLabel.alignment = .right
        speedLabel.textColor = .systemOrange

        let row1 = NSStackView(views: [timeLabel, seek, remainLabel])
        row1.spacing = 10
        let row2 = NSStackView()
        row2.setViews([prevButton, playButton, nextButton, speedLabel], in: .leading)
        row2.setViews([subButton, audioButton, muteButton, volume, playlistButton, fullButton], in: .trailing)
        row2.spacing = 8
        let stack = NSStackView(views: [row1, row2])
        stack.orientation = .vertical
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            row1.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -28),
            row2.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -28),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func setPlaying(_ playing: Bool) {
        playButton.image = symbol(playing ? "pause.fill" : "play.fill", "Play / Pause", size: 20)
    }

    func setMuted(_ muted: Bool, volume v: Int) {
        let name = muted || v == 0 ? "speaker.slash.fill" : v < 50 ? "speaker.wave.1.fill" : v <= 100 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
        muteButton.image = symbol(name, "Mute")
    }

    func update(time: Int, length: Int) {
        timeLabel.stringValue = fmtMs(time)
        remainLabel.stringValue = length > 0 ? "-" + fmtMs(max(0, length - time)) : "--:--"
        if !seek.isDragging, length > 0 { seek.doubleValue = Double(time) / Double(length) * 1000 }
    }
}
