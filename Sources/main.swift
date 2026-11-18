// Haari Player — a free, keyboard-friendly media player for macOS that plays everything.
import Cocoa
import VLCKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var ctl: PlayerController!

    func applicationWillFinishLaunching(_ notification: Notification) {
        Prefs.registerDefaults()
        ctl = PlayerController()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        ctl.buildMainMenu()
        ctl.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        let args = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") && FileManager.default.fileExists(atPath: $0) }
        if !args.isEmpty { ctl.open(args.map { URL(fileURLWithPath: $0) }) }
        if let dir = ProcessInfo.processInfo.environment["HAARI_SELFTEST"] { selfTest(URL(fileURLWithPath: dir)) }
    }

    /// Developer self-test: logs player state and writes a frame snapshot + UI render to `dir`, then quits.
    func selfTest(_ dir: URL) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) { [self] in
            let p = ctl.player
            ctl.userActivity()
            print("SELFTEST state=\(VLCMediaPlayerStateToString(p.state)) playing=\(p.isPlaying) time=\(ctl.timeMs) length=\(ctl.lengthMs) size=\(p.videoSize)")
            print("SELFTEST audio=\(ctl.audioTracks) current=\(p.currentAudioTrackIndex)")
            print("SELFTEST subs=\(ctl.subTracks) current=\(p.currentVideoSubTitleIndex)")
            print("SELFTEST osd=\(ctl.osdLabel.isHidden ? "-" : ctl.osdLabel.stringValue)")
            p.saveVideoSnapshot(at: dir.appendingPathComponent("frame.png").path, withWidth: 0, andHeight: 0)
            let v = ctl.root
            if let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                v.cacheDisplay(in: v.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("ui.png"))
            }
            fflush(stdout)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.5) { NSApp.terminate(nil) }
    }

    func application(_ application: NSApplication, open urls: [URL]) { ctl.open(urls) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { ctl.saveResume() }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
