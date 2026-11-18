import Cocoa

/// Searches OpenSubtitles.com and SubDL for subtitles, ranks them against the video and downloads the best one.
struct SubResult {
    enum Source: String { case openSubtitles = "OpenSubtitles", subdl = "SubDL" }
    let source: Source
    let id: String          // OpenSubtitles file_id, or SubDL download path
    let release: String
    let language: String    // two-letter code
    let hashMatch: Bool
    let downloads: Int
    var score: Double = 0
}

enum SubError: LocalizedError {
    case noKey, http(Int, String), noResults, badData(String)
    var errorDescription: String? {
        switch self {
        case .noKey: return "Add a free OpenSubtitles or SubDL API key in Settings (⌘,) to search online."
        case .http(let code, let msg): return msg.isEmpty ? "Server error \(code)" : msg
        case .noResults: return "No subtitles found online."
        case .badData(let s): return s
        }
    }
}

final class SubtitleFinder {
    static let userAgent = "HaariPlayer v\(appVersion)"
    static var hasAnyKey: Bool { !Prefs.openSubtitlesKey.isEmpty || !Prefs.subdlKey.isEmpty }

    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 20
        return URLSession(configuration: c)
    }()

    // MARK: Search

    func search(for video: URL, languages: [String]) async throws -> [SubResult] {
        guard Self.hasAnyKey else { throw SubError.noKey }
        let guess = guessMedia(video)
        let hash = video.isFileURL ? openSubtitlesHash(video) : nil
        var all: [SubResult] = []
        var firstError: Error?

        if !Prefs.openSubtitlesKey.isEmpty {
            do { all += try await searchOpenSubtitles(guess: guess, hash: hash, languages: languages) }
            catch { firstError = firstError ?? error }
        }
        if !Prefs.subdlKey.isEmpty {
            do { all += try await searchSubDL(guess: guess, languages: languages) }
            catch { firstError = firstError ?? error }
        }
        if all.isEmpty, let firstError { throw firstError }

        // Rank: preferred language first, then exact hash match, then release-name similarity, then popularity.
        let fileTokens = tokens(video.deletingPathExtension().lastPathComponent)
        all = all.map { r in
            var r = r
            var s = 0.0
            if let li = languages.firstIndex(of: r.language) { s += Double(languages.count - li) * 2000 }
            if r.hashMatch { s += 1000 }
            let rt = tokens(r.release)
            if !rt.isEmpty, !fileTokens.isEmpty {
                s += Double(rt.intersection(fileTokens).count) / Double(max(rt.count, fileTokens.count)) * 100
            }
            s += log10(Double(r.downloads + 1)) * 3
            r.score = s
            return r
        }
        return all.sorted { $0.score > $1.score }
    }

    private func searchOpenSubtitles(guess: MediaGuess, hash: String?, languages: [String]) async throws -> [SubResult] {
        var q: [String: String] = ["languages": languages.sorted().joined(separator: ",")]
        if let hash { q["moviehash"] = hash }
        if guess.isEpisode {
            q["query"] = guess.title.lowercased()
            q["season_number"] = String(guess.season!)
            q["episode_number"] = String(guess.episode!)
        } else {
            q["query"] = guess.title.lowercased()
            if let y = guess.year { q["year"] = String(y) }
        }
        var c = URLComponents(string: "https://api.opensubtitles.com/api/v1/subtitles")!
        c.queryItems = q.keys.sorted().map { URLQueryItem(name: $0, value: q[$0]) }
        var req = URLRequest(url: c.url!)
        osHeaders(&req)
        let json = try await fetchJSON(req)
        guard let data = json["data"] as? [[String: Any]] else { return [] }
        return data.compactMap { item in
            guard let a = item["attributes"] as? [String: Any],
                  let files = a["files"] as? [[String: Any]], let f = files.first,
                  let fid = (f["file_id"] as? Int).map(String.init) ?? (f["file_id"] as? String) else { return nil }
            let lang = String(((a["language"] as? String) ?? "").lowercased().prefix(2))
            return SubResult(source: .openSubtitles, id: fid,
                             release: (a["release"] as? String) ?? (f["file_name"] as? String) ?? "",
                             language: lang,
                             hashMatch: (a["moviehash_match"] as? Bool) ?? false,
                             downloads: (a["download_count"] as? Int) ?? 0)
        }
    }

    private func searchSubDL(guess: MediaGuess, languages: [String]) async throws -> [SubResult] {
        var c = URLComponents(string: "https://api.subdl.com/api/v1/subtitles")!
        var items = [
            URLQueryItem(name: "api_key", value: Prefs.subdlKey),
            URLQueryItem(name: "film_name", value: guess.title),
            URLQueryItem(name: "languages", value: languages.map { $0.uppercased() }.joined(separator: ",")),
            URLQueryItem(name: "subs_per_page", value: "30"),
        ]
        if guess.isEpisode {
            items += [URLQueryItem(name: "type", value: "tv"),
                      URLQueryItem(name: "season_number", value: String(guess.season!)),
                      URLQueryItem(name: "episode_number", value: String(guess.episode!))]
        } else {
            items.append(URLQueryItem(name: "type", value: "movie"))
            if let y = guess.year { items.append(URLQueryItem(name: "year", value: String(y))) }
        }
        c.queryItems = items
        var req = URLRequest(url: c.url!)
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let json = try await fetchJSON(req)
        if let ok = json["status"] as? Bool, !ok {
            let msg = (json["error"] as? String) ?? (json["message"] as? String) ?? ""
            if msg.lowercased().contains("can't find") || msg.lowercased().contains("not found") { return [] }
            throw SubError.badData("SubDL: \(msg)")
        }
        guard let subs = json["subtitles"] as? [[String: Any]] else { return [] }
        return subs.compactMap { s in
            guard let path = s["url"] as? String else { return nil }
            let lang = String(((s["language"] as? String) ?? "").lowercased().prefix(2))
            return SubResult(source: .subdl, id: path, release: (s["release_name"] as? String) ?? (s["name"] as? String) ?? "",
                             language: lang, hashMatch: false, downloads: 0)
        }
    }

    // MARK: Download

    /// Downloads a result and saves it beside the video (or in the app's cache folder if that isn't writable).
    func download(_ r: SubResult, for video: URL) async throws -> URL {
        let guess = guessMedia(video)
        var data: Data
        var ext = "srt"
        switch r.source {
        case .openSubtitles:
            var req = URLRequest(url: URL(string: "https://api.opensubtitles.com/api/v1/download")!)
            req.httpMethod = "POST"
            osHeaders(&req)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: ["file_id": Int(r.id) ?? 0, "sub_format": "srt"])
            let json = try await fetchJSON(req)
            guard let link = json["link"] as? String, let url = URL(string: link) else {
                throw SubError.badData((json["message"] as? String) ?? "OpenSubtitles gave no download link.")
            }
            data = try await fetchData(URLRequest(url: url))
        case .subdl:
            let zip = try await fetchData(URLRequest(url: URL(string: "https://dl.subdl.com" + r.id)!))
            (data, ext) = try unzipBestSubtitle(zip, guess: guess)
        }
        guard !data.isEmpty else { throw SubError.badData("Downloaded subtitle was empty.") }

        let base = video.deletingPathExtension().lastPathComponent
        let name = "\(base).\(r.language.isEmpty ? "sub" : r.language).\(ext)"
        let besideVideo = video.deletingLastPathComponent().appendingPathComponent(name)
        if (try? data.write(to: besideVideo)) != nil { return besideVideo }
        try FileManager.default.createDirectory(at: Prefs.subtitleCacheDir, withIntermediateDirectories: true)
        let cached = Prefs.subtitleCacheDir.appendingPathComponent(name)
        try data.write(to: cached)
        return cached
    }

    private func unzipBestSubtitle(_ zip: Data, guess: MediaGuess) throws -> (Data, String) {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let zipFile = tmp.appendingPathComponent("s.zip")
        try zip.write(to: zipFile)
        let out = tmp.appendingPathComponent("out", isDirectory: true)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-x", "-k", zipFile.path, out.path]
        try p.run()
        p.waitUntilExit()
        let files = (FileManager.default.enumerator(at: out, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? [])
            .filter { subExts.contains($0.pathExtension.lowercased()) }
        guard !files.isEmpty else { throw SubError.badData("The subtitle archive had no subtitle files.") }
        var pick = files[0]
        if let s = guess.season, let e = guess.episode {
            let tag = String(format: "s%02de%02d", s, e)
            pick = files.first { $0.lastPathComponent.lowercased().replacingOccurrences(of: " ", with: "").contains(tag) } ?? pick
        }
        return (try Data(contentsOf: pick), pick.pathExtension.lowercased())
    }

    // MARK: HTTP

    private func osHeaders(_ req: inout URLRequest) {
        req.setValue(Prefs.openSubtitlesKey, forHTTPHeaderField: "Api-Key")
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
    }

    private func fetchData(_ req: URLRequest) async throws -> Data {
        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let msg = (obj?["message"] as? String) ?? (obj?["error"] as? String) ?? ""
            throw SubError.http(code, code == 401 || code == 403 ? "API key was rejected. Check it in Settings." : msg)
        }
        return data
    }

    private func fetchJSON(_ req: URLRequest) async throws -> [String: Any] {
        let data = try await fetchData(req)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SubError.badData("Unexpected response from subtitle server.")
        }
        return obj
    }
}

// MARK: - Manual search window

final class SubtitleSearchPanel: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let panel: NSPanel
    let table = NSTableView()
    let status = NSTextField(labelWithString: "Searching…")
    let downloadButton = NSButton(title: "Download", target: nil, action: nil)
    var results: [SubResult] = []
    let video: URL
    let onPick: (SubResult) -> Void

    init(video: URL, onPick: @escaping (SubResult) -> Void) {
        self.video = video
        self.onPick = onPick
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 720, height: 420),
                        styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        super.init()
        panel.title = "Find Subtitles — \(video.lastPathComponent)"
        let cols: [(String, String, CGFloat)] = [("lang", "Language", 70), ("release", "Release", 420), ("src", "Source", 110), ("match", "Match", 80)]
        for (id, title, w) in cols {
            let c = NSTableColumn(identifier: .init(id))
            c.title = title
            c.width = w
            table.addTableColumn(c)
        }
        table.dataSource = self
        table.delegate = self
        table.usesAlternatingRowBackgroundColors = true
        table.target = self
        table.doubleAction = #selector(download)
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        downloadButton.target = self
        downloadButton.action = #selector(download)
        downloadButton.keyEquivalent = "\r"
        downloadButton.isEnabled = false
        let cancel = NSButton(title: "Close", target: self, action: #selector(close))
        cancel.keyEquivalent = "\u{1b}"
        let bar = NSStackView(views: [status, NSView(), cancel, downloadButton])
        let stack = NSStackView(views: [scroll, bar])
        stack.orientation = .vertical
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        panel.contentView = stack
    }

    func show(over window: NSWindow) {
        window.beginSheet(panel)
        Task { @MainActor in
            do {
                results = try await SubtitleFinder().search(for: video, languages: Prefs.subLanguages)
                status.stringValue = results.isEmpty ? "No subtitles found." : "\(results.count) results — best match first"
            } catch {
                status.stringValue = error.localizedDescription
            }
            table.reloadData()
            if !results.isEmpty { table.selectRowIndexes([0], byExtendingSelection: false); downloadButton.isEnabled = true }
        }
    }

    @objc func download() {
        let row = table.selectedRow
        guard results.indices.contains(row) else { return }
        onPick(results[row])
        close()
    }

    @objc func close() { panel.sheetParent?.endSheet(panel) }

    func numberOfRows(in tableView: NSTableView) -> Int { results.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let r = results[row]
        let text: String
        switch tableColumn?.identifier.rawValue {
        case "lang": text = r.language.uppercased()
        case "release": text = r.release
        case "src": text = r.source.rawValue
        default: text = r.hashMatch ? "✓ exact" : ""
        }
        let tf = NSTextField(labelWithString: text)
        tf.lineBreakMode = .byTruncatingMiddle
        return tf
    }
}
