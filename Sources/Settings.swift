import Cocoa

final class SettingsController: NSObject, NSTextFieldDelegate {
    let window: NSWindow
    let osKey = NSTextField()
    let subdlKey = NSTextField()
    let langs = NSTextField()
    let autoSubs = NSButton(checkboxWithTitle: "Download subtitles automatically when a video has none", target: nil, action: nil)
    let resume = NSButton(checkboxWithTitle: "Resume videos where I left off", target: nil, action: nil)
    let clickPause = NSButton(checkboxWithTitle: "Click on the video to play / pause", target: nil, action: nil)
    let subSize = NSPopUpButton()
    let sizes: [(String, Int)] = [("Small", 75), ("Normal", 100), ("Large", 130), ("Extra large", 170), ("Huge", 220)]

    override init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.title = "\(appName) Settings"
        window.isReleasedWhenClosed = false

        for f in [osKey, subdlKey, langs] {
            f.delegate = self
            f.widthAnchor.constraint(equalToConstant: 300).isActive = true
        }
        osKey.placeholderString = "Paste your OpenSubtitles API key"
        subdlKey.placeholderString = "Paste your SubDL API key"
        langs.placeholderString = "e.g. bn, en"
        osKey.stringValue = Prefs.openSubtitlesKey
        subdlKey.stringValue = Prefs.subdlKey
        langs.stringValue = Prefs.subLanguagesRaw
        autoSubs.state = Prefs.autoDownloadSubs ? .on : .off
        resume.state = Prefs.resume ? .on : .off
        clickPause.state = Prefs.clickToPause ? .on : .off
        for b in [autoSubs, resume, clickPause] { b.target = self; b.action = #selector(toggled(_:)) }
        subSize.addItems(withTitles: sizes.map(\.0))
        subSize.selectItem(at: sizes.firstIndex { $0.1 == Prefs.subSize } ?? 1)
        subSize.target = self
        subSize.action = #selector(sizeChanged)

        func link(_ title: String, _ url: String) -> NSButton {
            let b = NSButton(title: title, target: self, action: #selector(openLink(_:)))
            b.isBordered = false
            b.contentTintColor = .linkColor
            b.toolTip = url
            return b
        }
        func note(_ s: String) -> NSTextField {
            let t = NSTextField(wrappingLabelWithString: s)
            t.font = .systemFont(ofSize: 11)
            t.textColor = .secondaryLabelColor
            t.preferredMaxLayoutWidth = 420
            return t
        }

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "OpenSubtitles key:"), osKey],
            [NSGridCell.emptyContentView, link("Get a free key (sign up, then “API consumers”) →", "https://www.opensubtitles.com/en/consumers")],
            [NSTextField(labelWithString: "SubDL key:"), subdlKey],
            [NSGridCell.emptyContentView, link("Get a free key →", "https://subdl.com/panel/api")],
            [NSTextField(labelWithString: "Subtitle languages:"), langs],
            [NSGridCell.emptyContentView, note("Two-letter codes, most wanted first. bn = Bangla, en = English, hi = Hindi, ar = Arabic, es = Spanish…")],
            [NSTextField(labelWithString: "Subtitle size:"), subSize],
            [NSGridCell.emptyContentView, note("Size changes apply the next time you open \(appName).")],
            [NSGridCell.emptyContentView, autoSubs],
            [NSGridCell.emptyContentView, resume],
            [NSGridCell.emptyContentView, clickPause],
            [NSGridCell.emptyContentView, note("One key is enough. With OpenSubtitles, subtitles are matched to your exact video file by its fingerprint, so timing is right.")],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        grid.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            grid.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -24),
        ])
        window.contentView = content
        window.center()
    }

    func controlTextDidChange(_ obj: Notification) {
        Prefs.openSubtitlesKey = osKey.stringValue
        Prefs.subdlKey = subdlKey.stringValue
        Prefs.subLanguagesRaw = langs.stringValue
    }

    @objc func toggled(_ sender: NSButton) {
        Prefs.autoDownloadSubs = autoSubs.state == .on
        Prefs.resume = resume.state == .on
        Prefs.clickToPause = clickPause.state == .on
    }

    @objc func sizeChanged() { Prefs.subSize = sizes[subSize.indexOfSelectedItem].1 }

    @objc func openLink(_ sender: NSButton) {
        if let s = sender.toolTip, let u = URL(string: s) { NSWorkspace.shared.open(u) }
    }
}
