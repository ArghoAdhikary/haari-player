<p align="center">
  <img src="Assets/icon.png" width="160" alt="Haari Player icon">
</p>

<h1 align="center">Haari Player</h1>

<p align="center">
  A free, fast, keyboard-friendly media player for macOS that plays <b>everything</b> — MKV, MP4, AVI, WebM, MOV, FLV, TS, and every audio format —
  and finds subtitles for you automatically.
</p>

<p align="center">
  <a href="https://github.com/ArghoAdhikary/haari-player/releases/latest"><b>⬇️ Download the latest version</b></a>
</p>

---

## বাংলায়

**Haari Player** (হাঁড়ি প্লেয়ার) Mac এর জন্য একটা ফ্রি ভিডিও প্লেয়ার। MKV, AVI, MP4, WebM, যেকোনো ভিডিও বা গান চলে। ভিডিওর পাশে সাবটাইটেল ফাইল থাকলে নিজে থেকে লোড হয়, আর না থাকলে ইন্টারনেট থেকে খুঁজে নামিয়ে আনে, তোমার ভিডিওর সাথে মিলিয়ে।

**ইনস্টল করা:**
1. [Releases](https://github.com/ArghoAdhikary/haari-player/releases/latest) থেকে `HaariPlayer-…-mac.zip` নামাও, আনজিপ করো।
2. **Haari Player** অ্যাপটা **Applications** ফোল্ডারে টেনে রাখো।
3. প্রথমবার খুললে macOS বলবে অ্যাপটা যাচাই করা যায়নি (কারণ এটা Apple এর পেইড সাইনিং ছাড়া বানানো)। তখন **System Settings → Privacy & Security** এ গিয়ে নিচে **Open Anyway** চাপো। একবারই করতে হবে।

**অটো সাবটাইটেল চালু করা (একবারই):**
1. [opensubtitles.com](https://www.opensubtitles.com/en/consumers) এ ফ্রি অ্যাকাউন্ট খুলে একটা API key নাও (অথবা [subdl.com](https://subdl.com/panel/api) থেকে)।
2. Haari Player খুলে **⌘ ,** (Settings) চাপো, key টা পেস্ট করো, আর ভাষা লেখো, যেমন `bn, en` (আগে বাংলা, না পেলে ইংরেজি)।
3. ব্যস! এখন যে ভিডিওতে সাবটাইটেল নেই, সেটা চালালে নিজে থেকেই সাবটাইটেল নেমে আসবে।

---

## Features

**Plays everything** — powered by VideoLAN's VLCKit engine: MKV, MP4, AVI, WebM, MOV, WMV, FLV, TS/M2TS, MPEG, VOB, 3GP, RMVB, HEVC/H.265, AV1, VP9, and audio (MP3, FLAC, AAC, WAV, OGG, Opus, WMA, APE, AC3, DTS…). Network streams too (HTTP, HLS, RTSP).

**Subtitles, automatically**
- Subtitles next to the video (`movie.srt`, `movie.en.srt`, `Subs/` folder…) load on their own. SRT, ASS/SSA (with styling), VTT, SUB/IDX, SMI and embedded MKV subtitles all work.
- No subtitles? Haari Player searches **OpenSubtitles** and **SubDL**, picks the best one and loads it. With OpenSubtitles it matches by the file's fingerprint (moviehash), so timing fits your exact release.
- Choose your languages in order (e.g. `bn, en`). Press **O** to pick a result yourself.
- Fix timing with **,** and **.** (±0.5 s). Change size in Settings.

**Player**
- Clean auto-hiding controls, full screen, click-to-pause, double-click for full screen, scroll for volume
- Playlist: opening one file queues the rest of its folder. Repeat (file / playlist) and shuffle
- Remembers where you stopped in every video
- Speed 0.1× – 8×, frame stepping, jump to 0–90 % with number keys
- A-B repeat, chapters, audio track and subtitle track switching
- Volume boost up to 200 %, audio delay, 18-preset equalizer
- Aspect ratio, fill/crop, deinterlace, brightness/contrast/saturation/gamma
- Screenshots in full resolution (saved to `Pictures/Haari Player`)
- Always on top, media keys and Now Playing support, keeps the display awake while playing
- Universal app: Apple Silicon and Intel, macOS 13 or newer

## Keyboard shortcuts

| Key | Action |
|---|---|
| Space / click | Play / pause |
| ← / → | Seek 5 s (⇧ 30 s, ⌥ 60 s) |
| 0 … 9 | Jump to 0 % … 90 % |
| ↑ / ↓ or scroll | Volume (up to 200 %) |
| M | Mute |
| C / X / Z | Faster / slower / normal speed |
| F | Next frame |
| Return / double-click | Full screen |
| N / B, PgDn / PgUp | Next / previous file |
| P | Playlist (Delete removes selected) |
| L | Repeat: off / file / playlist |
| S | Screenshot |
| [ then [ / \ | A-B repeat: set A, set B / clear |
| V / A | Next subtitle track / next audio track |
| O | Find subtitles online |
| , / . | Subtitle delay −/+ 0.5 s |
| - / = | Audio delay −/+ 50 ms |
| R / W | Aspect ratio / fill window |
| I | Media info |
| ⌘O / ⌘U / ⌘, / ⌘T | Open / open stream / settings / always on top |

Right-click the video for every other option.

## Build from source

Needs the Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/ArghoAdhikary/haari-player.git
cd haari-player
./build.sh          # downloads + verifies VLCKit on first run, then builds "Haari Player.app"
./build.sh --zip    # also creates dist/HaariPlayer-<version>-mac.zip
```

Code layout: `Sources/Player.swift` (playback), `Sources/SubtitleFinder.swift` (online subtitles), `Sources/Menus.swift`, `Sources/Views.swift`, `Sources/Settings.swift`, `Assets/icon.svg` (app icon).

## Privacy

Haari Player has no tracking or analytics. It only goes online when it searches for subtitles: it sends the video's file name and fingerprint to the subtitle service you set up, using your own API key. Keys are stored locally in the app's preferences.

## License

Haari Player is MIT licensed — see [LICENSE](LICENSE).
It uses [VLCKit](https://code.videolan.org/videolan/VLCKit) by VideoLAN, licensed under the LGPL 2.1, which is downloaded unmodified from videolan.org and bundled as a separate framework. Its license is included inside the app (`Contents/Resources/Licenses`).
Haari Player is not affiliated with VideoLAN, OpenSubtitles, SubDL, or any other media player.
