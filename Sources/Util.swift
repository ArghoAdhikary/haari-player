import Cocoa

let appName = "Haari Player"
let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"
let repoURL = URL(string: "https://github.com/ArghoAdhikary/haari-player")!

let videoExts: Set<String> = [
    "mkv", "mp4", "m4v", "mov", "qt", "avi", "wmv", "asf", "flv", "f4v", "webm", "ogv", "ts", "m2ts", "mts", "m2t",
    "mpg", "mpeg", "mpe", "m1v", "m2v", "vob", "3gp", "3g2", "rm", "rmvb", "divx", "xvid", "mxf", "dv", "evo", "hevc",
    "h264", "h265", "y4m", "nut", "amv", "wtv", "dvr-ms",
]
let audioExts: Set<String> = [
    "mp3", "m4a", "m4b", "aac", "flac", "wav", "aif", "aiff", "caf", "ogg", "oga", "opus", "wma", "ape", "alac",
    "ac3", "eac3", "dts", "mka", "amr", "mpc", "wv", "tta", "mid", "midi", "mod", "s3m", "xm", "it",
]
let playlistExts: Set<String> = ["m3u", "m3u8", "pls", "xspf", "cue"]
let mediaExts = videoExts.union(audioExts).union(playlistExts)
let subExts: Set<String> = ["srt", "ass", "ssa", "vtt", "sub", "idx", "smi", "sami", "usf", "mpl", "jss", "psb", "rt", "stl"]

func fmtMs(_ ms: Int) -> String {
    let s = max(0, ms / 1000)
    return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
                     : String(format: "%02d:%02d", s / 60, s % 60)
}

// MARK: - Settings

enum Prefs {
    static let d = UserDefaults.standard

    static func registerDefaults() {
        d.register(defaults: [
            "subLanguages": Locale.current.language.languageCode?.identifier == "bn" ? "bn, en" : "en",
            "autoDownloadSubs": true,
            "resume": true,
            "subSize": 100,
            "volume": 100,
            "clickToPause": true,
            "repeatMode": 0,
        ])
    }

    static var openSubtitlesKey: String {
        get { d.string(forKey: "openSubtitlesKey")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
        set { d.set(newValue, forKey: "openSubtitlesKey") }
    }
    static var subdlKey: String {
        get { d.string(forKey: "subdlKey")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
        set { d.set(newValue, forKey: "subdlKey") }
    }
    static var subLanguagesRaw: String {
        get { d.string(forKey: "subLanguages") ?? "en" }
        set { d.set(newValue, forKey: "subLanguages") }
    }
    /// Two-letter ISO 639-1 codes in order of preference.
    static var subLanguages: [String] {
        let list = subLanguagesRaw.lowercased().split(whereSeparator: { ", ;".contains($0) })
            .map { String($0.prefix(2)) }.filter { $0.count == 2 }
        return list.isEmpty ? ["en"] : list
    }
    static var autoDownloadSubs: Bool { get { d.bool(forKey: "autoDownloadSubs") } set { d.set(newValue, forKey: "autoDownloadSubs") } }
    static var resume: Bool { get { d.bool(forKey: "resume") } set { d.set(newValue, forKey: "resume") } }
    static var clickToPause: Bool { get { d.bool(forKey: "clickToPause") } set { d.set(newValue, forKey: "clickToPause") } }
    static var subSize: Int { get { d.integer(forKey: "subSize") } set { d.set(newValue, forKey: "subSize") } }
    static var volume: Int { get { d.integer(forKey: "volume") } set { d.set(newValue, forKey: "volume") } }
    /// 0 = off, 1 = repeat one, 2 = repeat all
    static var repeatMode: Int { get { d.integer(forKey: "repeatMode") } set { d.set(newValue, forKey: "repeatMode") } }

    static var screenshotDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/\(appName)", isDirectory: true)
    }
    static var subtitleCacheDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("\(appName)/Subtitles", isDirectory: true)
    }
}

// MARK: - Filename parsing (for subtitle search)

struct MediaGuess {
    var title: String
    var year: Int?
    var season: Int?
    var episode: Int?
    var isEpisode: Bool { season != nil && episode != nil }
}

private func groups(_ pattern: String, in s: String) -> (range: Range<String.Index>, groups: [String])? {
    guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
          let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
          let r = Range(m.range, in: s) else { return nil }
    var out: [String] = []
    for i in 1..<max(1, m.numberOfRanges) {
        if let gr = Range(m.range(at: i), in: s) { out.append(String(s[gr])) } else { out.append("") }
    }
    return (r, out)
}

func guessMedia(_ url: URL) -> MediaGuess {
    var name = url.deletingPathExtension().lastPathComponent
    name = name.replacingOccurrences(of: "[._]+", with: " ", options: .regularExpression)
    var cut = name.endIndex
    var season: Int?, episode: Int?, year: Int?
    if let m = groups("\\bS(\\d{1,2})\\s?E(\\d{1,3})", in: name) ?? groups("\\b(\\d{1,2})x(\\d{2,3})\\b", in: name) {
        season = Int(m.groups[0]); episode = Int(m.groups[1]); cut = min(cut, m.range.lowerBound)
    }
    if let m = groups("[\\(\\[ ]((?:19|20)\\d{2})[\\)\\] ]?", in: name), m.range.lowerBound > name.startIndex {
        year = Int(m.groups[0]); cut = min(cut, m.range.lowerBound)
    }
    if let m = groups("\\b(480p|576p|720p|1080p|2160p|4k|uhd|bluray|blu ray|brrip|bdrip|web ?dl|webrip|web|hdrip|dvdrip|dvdscr|hdtv|x264|x265|h264|h265|hevc|10bit|proper|repack|extended|remastered)\\b", in: name) {
        cut = min(cut, m.range.lowerBound)
    }
    var title = String(name[..<cut])
        .replacingOccurrences(of: "\\[[^\\]]*\\]", with: "", options: .regularExpression)
        .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "-([")))
    if title.isEmpty { title = name }
    return MediaGuess(title: title, year: year, season: season, episode: episode)
}

func tokens(_ s: String) -> Set<String> {
    Set(s.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count > 1 })
}

/// The OpenSubtitles "moviehash": file size + 64-bit sums of the first and last 64 KB.
func openSubtitlesHash(_ url: URL) -> String? {
    guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? h.close() }
    guard let size = try? h.seekToEnd(), size >= 131_072 else { return nil }
    var hash = size
    func add(_ d: Data) {
        d.withUnsafeBytes { raw in
            for i in 0..<(d.count / 8) { hash &+= UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: i * 8, as: UInt64.self)) }
        }
    }
    try? h.seek(toOffset: 0)
    add(h.readData(ofLength: 65_536))
    try? h.seek(toOffset: size - 65_536)
    add(h.readData(ofLength: 65_536))
    return String(format: "%016llx", hash)
}

func symbol(_ name: String, _ label: String, size: CGFloat = 15) -> NSImage? {
    NSImage(systemSymbolName: name, accessibilityDescription: label)?
        .withSymbolConfiguration(.init(pointSize: size, weight: .medium))
}
