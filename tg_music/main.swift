import AVFoundation
import AppKit
import Foundation
import MediaPlayer
import QuartzCore

// MARK: - Paths & Notifications

private let kToggleMusicNotification = Notification.Name("com.mellvazoa.tg_music.toggle")
private let kOpenPlaylistsNotification = Notification.Name("com.mellvazoa.tg_music.playlists")
private let kThemeNotification       = Notification.Name("com.mellvazoa.wallpaper.theme")
private let kMusicThemeNotification  = Notification.Name("com.mellvazoa.tg_music.theme")
private let kRepoDir                 = "/Users/new/Documents/Antigravity/waybar"
private let kStateDir                = NSHomeDirectory() + "/.config/tg_music"
private let kTracksJsonPath          = kStateDir + "/tracks.json"
private let kPlaylistsJsonPath       = kStateDir + "/playlists.json"
private let kPidPath                 = "/tmp/tg_music.pid"

func resolveSyncPaths() -> (python: String, script: String)? {
    let candidates: [(String, String)] = [
        (kStateDir + "/.venv/bin/python", kStateDir + "/tg_sync.py"),
        (kRepoDir + "/tg_music/.venv/bin/python", kRepoDir + "/tg_music/tg_sync.py"),
    ]
    for (py, sc) in candidates {
        if FileManager.default.isExecutableFile(atPath: py), FileManager.default.fileExists(atPath: sc) {
            return (py, sc)
        }
    }
    return nil
}

// MARK: - Theme Palette

struct ThemePalette {
    let bg: NSColor
    let accent: NSColor
    let accentLight: NSColor

    static func load() -> ThemePalette {
        let fallbackBg = NSColor(hex: "14172f") ?? .black
        let fallbackAccent = NSColor(hex: "c8b4fa") ?? .systemPurple
        let fallbackLight = NSColor(hex: "e4d2fd") ?? .white

        let path = NSHomeDirectory() + "/.config/rofi/colors.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return ThemePalette(bg: fallbackBg, accent: fallbackAccent, accentLight: fallbackLight)
        }
        return ThemePalette(
            bg: NSColor(hex: dict["bg"] ?? "") ?? fallbackBg,
            accent: NSColor(hex: dict["accent"] ?? "") ?? fallbackAccent,
            accentLight: NSColor(hex: dict["accent_light"] ?? "") ?? fallbackLight
        )
    }
}

extension NSColor {
    convenience init?(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard clean.count == 6, let val = UInt64(clean, radix: 16) else { return nil }
        let r = CGFloat((val >> 16) & 0xFF) / 255.0
        let g = CGFloat((val >> 8) & 0xFF) / 255.0
        let b = CGFloat(val & 0xFF) / 255.0
        self.init(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }
}

// MARK: - Models

struct TgTrack: Codable, Equatable {
    let id: Int
    let title: String
    let artist: String
    let duration: Int
    let ext: String?
    let size: Int?
    let date: String?
    let thumb: String?
    var cached: Bool?
    var cached_path: String?
}

struct TgLibrary: Codable {
    let chat: String?
    let count: Int?
    let tracks: [TgTrack]
}

struct TgPlaylist: Codable, Equatable {
    let id: String
    let name: String
    let icon: String?
    let subtitle: String?
    let track_ids: [Int]
}

struct TgPlaylistsFile: Codable {
    let playlists: [TgPlaylist]
}

struct TgSyncStatus: Codable {
    let configured: Bool
    let authorized: Bool
    let chat: String
    let track_count: Int
}

func formatDuration(_ seconds: Double) -> String {
    guard seconds.isFinite && seconds >= 0 else { return "0:00" }
    let total = Int(seconds)
    let m = total / 60
    let s = total % 60
    return String(format: "%d:%02d", m, s)
}

// MARK: - Desktop Visibility Detector

func isDesktopAreaUncovered(for nsRect: NSRect) -> Bool {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
        return true
    }

    let mainHeight = NSScreen.screens.first?.frame.height ?? NSScreen.main?.frame.height ?? 0
    let targetRect = CGRect(
        x: nsRect.minX,
        y: mainHeight - nsRect.maxY,
        width: nsRect.width,
        height: nsRect.height
    ).insetBy(dx: -2, dy: -2)

    let ignoredOwners: Set<String> = [
        "tg_music",
        "wallpaper_gallery",
        "powermenu",
        "ocr_osd",
        "Window Server",
        "Dock",
        "borders",
        "square_corners",
        "sketchybar",
        "SystemUIServer",
        "ControlCenter",
        "NotificationCenter",
        "Центр уведомлени",
        "Центр уведомлений",
        "Центр управления",
        "Spotlight",
        "TextInputMenuAgent",
        "StatusMenu"
    ]

    for info in infoList {
        let layer = info[kCGWindowLayer as String] as? Int ?? 0
        let alpha = info[kCGWindowAlpha as String] as? Double ?? 1.0
        let owner = info[kCGWindowOwnerName as String] as? String ?? ""
        let bounds = info[kCGWindowBounds as String] as? [String: Any] ?? [:]
        let x = bounds["X"] as? Double ?? 0
        let y = bounds["Y"] as? Double ?? 0
        let w = bounds["Width"] as? Double ?? 0
        let h = bounds["Height"] as? Double ?? 0

        if layer >= 0 && layer <= 10 && w > 120 && h > 120 && alpha > 0.05 {
            if !ignoredOwners.contains(owner) {
                let winRect = CGRect(x: x, y: y, width: w, height: h)
                if winRect.intersects(targetRect) {
                    return false
                }
            }
        }
    }
    return true
}

// MARK: - Audio Playback Engine (AVPlayer + mpv fallback + NowPlaying)

final class MusicPlayerController {
    var palette = ThemePalette.load()
    private(set) var tracks: [TgTrack] = []
    private(set) var playlists: [TgPlaylist] = []
    private var playbackQueue: [TgTrack] = []
    private(set) var chatName: String = "Telegram Music"
    private(set) var currentTrack: TgTrack?
    private(set) var isPlaying: Bool = false
    private(set) var isDownloading: Bool = false
    private(set) var downloadProgress: Double = 0
    private(set) var downloadReceivedBytes: Int64 = 0
    private(set) var downloadTotalBytes: Int64 = 0
    private(set) var isSyncing: Bool = false
    private(set) var shuffleEnabled: Bool = false
    private(set) var repeatOne: Bool = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var statusError: String?

    private var avPlayer: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: Any?
    private var mpvProcess: Process?
    private var fetchProcess: Process?
    private var fetchGeneration: Int = 0
    private var cachedThumbCache: [String: NSImage] = [:]

    var onStateChanged: (() -> Void)?
    var onTimeUpdated: ((Double, Double) -> Void)?
    var onDownloadProgress: ((Int, Double, Int64, Int64) -> Void)?

    init() {
        setupRemoteCommands()
        loadCachedLibrary()
    }

    deinit {
        stopPlayback()
    }

    func thumbnail(for track: TgTrack) -> NSImage? {
        guard let path = track.thumb, !path.isEmpty else { return nil }
        if let img = cachedThumbCache[path] { return img }
        if let img = NSImage(contentsOfFile: path) {
            cachedThumbCache[path] = img
            return img
        }
        return nil
    }

    func loadCachedLibrary() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: kTracksJsonPath)),
              let lib = try? JSONDecoder().decode(TgLibrary.self, from: data) else {
            return
        }
        self.tracks = lib.tracks
        if let c = lib.chat, !c.isEmpty {
            self.chatName = c
        }
        if let plData = try? Data(contentsOf: URL(fileURLWithPath: kPlaylistsJsonPath)),
           let plFile = try? JSONDecoder().decode(TgPlaylistsFile.self, from: plData) {
            self.playlists = plFile.playlists
        }
        if playbackQueue.isEmpty {
            playbackQueue = lib.tracks
        } else {
            let map = Dictionary(uniqueKeysWithValues: lib.tracks.map { ($0.id, $0) })
            playbackQueue = playbackQueue.compactMap { map[$0.id] }
            if playbackQueue.isEmpty { playbackQueue = lib.tracks }
        }
        onStateChanged?()
    }

    func tracks(for playlist: TgPlaylist) -> [TgTrack] {
        let map = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        return playlist.track_ids.compactMap { map[$0] }
    }

    func checkStatus(completion: @escaping (TgSyncStatus?) -> Void) {
        guard let (py, sc) = resolveSyncPaths() else {
            completion(nil)
            return
        }
        DispatchQueue.global(qos: .utility).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: py)
            p.arguments = [sc, "--status"]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = FileHandle.nullDevice
            try? p.run()
            p.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let status = try? JSONDecoder().decode(TgSyncStatus.self, from: data)
            DispatchQueue.main.async {
                completion(status)
            }
        }
    }

    func syncLibrary() {
        guard !isSyncing, let (py, sc) = resolveSyncPaths() else { return }
        isSyncing = true
        statusError = nil
        onStateChanged?()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: py)
            p.arguments = [sc, "--sync"]
            let errPipe = Pipe()
            p.standardOutput = FileHandle.nullDevice
            p.standardError = errPipe
            do {
                try p.run()
                p.waitUntilExit()
                let errText = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.isSyncing = false
                    if p.terminationStatus == 0 {
                        self.loadCachedLibrary()
                    } else {
                        self.statusError = errText.isEmpty ? "Sync failed" : errText
                        self.onStateChanged?()
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.isSyncing = false
                    self?.statusError = error.localizedDescription
                    self?.onStateChanged?()
                }
            }
        }
    }

    func cancelDownload() {
        guard isDownloading else { return }
        fetchGeneration += 1
        fetchProcess?.terminate()
        fetchProcess = nil
        isDownloading = false
        downloadProgress = 0
        downloadReceivedBytes = 0
        downloadTotalBytes = 0
        onStateChanged?()
    }

    func play(track: TgTrack, queue: [TgTrack]? = nil) {
        if let q = queue, !q.isEmpty {
            playbackQueue = q
        }
        if currentTrack?.id == track.id, isDownloading {
            cancelDownload()
            return
        }
        if currentTrack?.id == track.id, !isDownloading {
            if avPlayer != nil || mpvProcess != nil {
                togglePlayPause()
                return
            }
        }

        fetchProcess?.terminate()
        fetchProcess = nil
        fetchGeneration += 1
        let gen = fetchGeneration

        currentTrack = track
        statusError = nil
        currentTime = 0
        duration = Double(max(1, track.duration))

        // Fast path: already downloaded in cache
        if let localPath = existingLocalPath(for: track) {
            isDownloading = false
            downloadProgress = 0
            downloadReceivedBytes = 0
            downloadTotalBytes = 0
            startPlayingFile(path: localPath, track: track)
            return
        }

        // Download on demand via tg_sync.py --fetch <id> --progress
        guard let (py, sc) = resolveSyncPaths() else {
            statusError = "tg_sync.py not found"
            onStateChanged?()
            return
        }

        isDownloading = true
        downloadProgress = 0
        downloadReceivedBytes = 0
        downloadTotalBytes = Int64(max(0, track.size ?? 0))
        isPlaying = false
        stopAudioOnly()
        onStateChanged?()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: py)
            p.arguments = [sc, "--fetch", "\(track.id)", "--progress"]
            let outPipe = Pipe()
            let errPipe = Pipe()
            p.standardOutput = outPipe
            p.standardError = errPipe

            let errLock = NSLock()
            var partialLine = ""
            var errMessages: [String] = []

            func processErrChunk(_ text: String) {
                errLock.lock()
                partialLine += text
                let lines = partialLine.components(separatedBy: "\n")
                partialLine = lines.last ?? ""
                let complete = lines.dropLast()
                errLock.unlock()

                for raw in complete {
                    let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                    if line.isEmpty { continue }
                    if line.hasPrefix("PROGRESS ") {
                        let parts = line.split(separator: " ")
                        if parts.count >= 3,
                           let rec = Int64(parts[1]),
                           let tot = Int64(parts[2]) {
                            let pct = tot > 0 ? min(1.0, max(0.0, Double(rec) / Double(tot))) : 0.0
                            DispatchQueue.main.async {
                                guard let self = self, self.fetchGeneration == gen, self.isDownloading else { return }
                                self.downloadProgress = pct
                                self.downloadReceivedBytes = rec
                                self.downloadTotalBytes = tot
                                self.onDownloadProgress?(track.id, pct, rec, tot)
                            }
                        }
                    } else {
                        errLock.lock()
                        errMessages.append(line)
                        errLock.unlock()
                    }
                }
            }

            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                processErrChunk(chunk)
            }

            DispatchQueue.main.async {
                if self?.fetchGeneration == gen {
                    self?.fetchProcess = p
                }
            }

            do {
                try p.run()
                p.waitUntilExit()
                errPipe.fileHandleForReading.readabilityHandler = nil
                let remData = errPipe.fileHandleForReading.readDataToEndOfFile()
                if !remData.isEmpty, let remText = String(data: remData, encoding: .utf8) {
                    processErrChunk(remText + "\n")
                }

                let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                errLock.lock()
                let tail = partialLine.trimmingCharacters(in: .whitespacesAndNewlines)
                if !tail.isEmpty && !tail.hasPrefix("PROGRESS ") {
                    errMessages.append(tail)
                }
                let err = errMessages.joined(separator: "\n")
                errLock.unlock()

                DispatchQueue.main.async {
                    guard let self = self, self.fetchGeneration == gen else { return }
                    self.fetchProcess = nil
                    self.isDownloading = false
                    self.downloadProgress = 0
                    self.downloadReceivedBytes = 0
                    self.downloadTotalBytes = 0
                    if p.terminationStatus == 0, !out.isEmpty, FileManager.default.fileExists(atPath: out) {
                        if let idx = self.tracks.firstIndex(where: { $0.id == track.id }) {
                            self.tracks[idx].cached = true
                            self.tracks[idx].cached_path = out
                        }
                        self.startPlayingFile(path: out, track: track)
                    } else {
                        self.statusError = err.isEmpty ? "Download failed" : err
                        self.onStateChanged?()
                    }
                }
            } catch {
                errPipe.fileHandleForReading.readabilityHandler = nil
                DispatchQueue.main.async {
                    guard let self = self, self.fetchGeneration == gen else { return }
                    self.isDownloading = false
                    self.downloadProgress = 0
                    self.downloadReceivedBytes = 0
                    self.downloadTotalBytes = 0
                    self.statusError = error.localizedDescription
                    self.onStateChanged?()
                }
            }
        }
    }

    private func existingLocalPath(for track: TgTrack) -> String? {
        if let p = track.cached_path, !p.isEmpty, FileManager.default.fileExists(atPath: p) {
            return p
        }
        let cacheDir = kStateDir + "/cache"
        let ext = track.ext ?? ".mp3"
        let p = "\(cacheDir)/\(track.id)\(ext)"
        if FileManager.default.fileExists(atPath: p) {
            return p
        }
        return nil
    }

    private func startPlayingFile(path: String, track: TgTrack) {
        stopAudioOnly()
        let url = URL(fileURLWithPath: path)
        let asset = AVURLAsset(url: url)

        if asset.isPlayable {
            let item = AVPlayerItem(asset: asset)
            let player = AVPlayer(playerItem: item)
            avPlayer = player

            let assetDur = CMTimeGetSeconds(asset.duration)
            if assetDur.isFinite && assetDur > 0 {
                duration = assetDur
            } else {
                duration = Double(max(1, track.duration))
            }

            let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
            timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
                guard let self = self else { return }
                let sec = CMTimeGetSeconds(time)
                if sec.isFinite {
                    self.currentTime = sec
                    if let d = self.avPlayer?.currentItem?.duration {
                        let ds = CMTimeGetSeconds(d)
                        if ds.isFinite && ds > 0 {
                            self.duration = ds
                        }
                    }
                    self.onTimeUpdated?(self.currentTime, self.duration)
                    self.updateNowPlayingInfo()
                }
            }

            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                self?.handleTrackFinished()
            }

            player.play()
            isPlaying = true
            updateNowPlayingInfo()
            onStateChanged?()
        } else if FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/mpv") {
            // Fallback for .ogg/.opus tracks
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/mpv")
            p.arguments = ["--no-video", "--really-quiet", path]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            p.terminationHandler = { [weak self] proc in
                DispatchQueue.main.async {
                    guard let self = self, self.mpvProcess === proc else { return }
                    self.mpvProcess = nil
                    if self.isPlaying {
                        self.handleTrackFinished()
                    }
                }
            }
            try? p.run()
            mpvProcess = p
            duration = Double(max(1, track.duration))
            isPlaying = true
            updateNowPlayingInfo()
            onStateChanged?()
        } else {
            statusError = "Unsupported audio format"
            isPlaying = false
            onStateChanged?()
        }
    }

    private func handleTrackFinished() {
        if repeatOne, let cur = currentTrack {
            if let player = avPlayer {
                player.seek(to: .zero)
                player.play()
                isPlaying = true
                currentTime = 0
                updateNowPlayingInfo()
                onStateChanged?()
            } else {
                play(track: cur)
            }
            return
        }
        nextTrack()
    }

    private var activeQueue: [TgTrack] {
        return playbackQueue.isEmpty ? tracks : playbackQueue
    }

    func togglePlayPause() {
        if let player = avPlayer {
            if isPlaying {
                player.pause()
                isPlaying = false
            } else {
                player.play()
                isPlaying = true
            }
            updateNowPlayingInfo()
            onStateChanged?()
        } else if let cur = currentTrack {
            play(track: cur)
        } else if let first = activeQueue.first {
            play(track: first)
        }
    }

    func nextTrack() {
        let q = activeQueue
        guard !q.isEmpty else { return }
        if shuffleEnabled, q.count > 1 {
            let candidates = q.filter { $0.id != currentTrack?.id }
            if let picked = candidates.randomElement() {
                play(track: picked)
                return
            }
        }
        if let cur = currentTrack, let idx = q.firstIndex(where: { $0.id == cur.id }) {
            let nextIdx = (idx + 1) % q.count
            play(track: q[nextIdx])
        } else {
            play(track: q[0])
        }
    }

    func prevTrack() {
        let q = activeQueue
        guard !q.isEmpty else { return }
        if let player = avPlayer, currentTime > 4.0 {
            player.seek(to: .zero)
            currentTime = 0
            onTimeUpdated?(currentTime, duration)
            return
        }
        if let cur = currentTrack, let idx = q.firstIndex(where: { $0.id == cur.id }) {
            let prevIdx = (idx - 1 + q.count) % q.count
            play(track: q[prevIdx])
        } else {
            play(track: q[0])
        }
    }

    func seek(to fraction: Double) {
        guard let player = avPlayer, duration > 0 else { return }
        let clamped = max(0.0, min(1.0, fraction))
        let sec = clamped * duration
        let cm = CMTime(seconds: sec, preferredTimescale: 600)
        player.seek(to: cm)
        currentTime = sec
        updateNowPlayingInfo()
        onTimeUpdated?(currentTime, duration)
    }

    func toggleShuffle() {
        shuffleEnabled.toggle()
        onStateChanged?()
    }

    func toggleRepeat() {
        repeatOne.toggle()
        onStateChanged?()
    }

    func stopPlayback() {
        fetchProcess?.terminate()
        fetchProcess = nil
        stopAudioOnly()
        isPlaying = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }

    private func stopAudioOnly() {
        if let obs = timeObserver, let player = avPlayer {
            player.removeTimeObserver(obs)
        }
        timeObserver = nil
        if let endObs = endObserver {
            NotificationCenter.default.removeObserver(endObs)
        }
        endObserver = nil
        avPlayer?.pause()
        avPlayer = nil

        if let mpv = mpvProcess {
            mpvProcess = nil
            mpv.terminate()
        }
    }

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            if !self.isPlaying { self.togglePlayPause() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            if self.isPlaying { self.togglePlayPause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.nextTrack()
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.prevTrack()
            return .success
        }
    }

    private func updateNowPlayingInfo() {
        guard let track = currentTrack else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if let img = thumbnail(for: track) {
            let artwork = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
            info[MPMediaItemPropertyArtwork] = artwork
        }
        let np = MPNowPlayingInfoCenter.default()
        np.nowPlayingInfo = info
        np.playbackState = isPlaying ? .playing : .paused
    }
}

// MARK: - Minimalist Desktop Corner Button (Bottom-Right)

final class CornerMusicButtonView: NSView {
    var palette = ThemePalette.load()
    var isPlaying: Bool = false { didSet { needsDisplay = true } }
    var isOpen: Bool = false { didSet { needsDisplay = true } }
    private var isHovered: Bool = false { didSet { needsDisplay = true } }
    private var trackingArea: NSTrackingArea?
    var onClick: (() -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        NSCursor.pointingHand.push()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        NSCursor.pop()
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1.5, dy: 1.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: 15, yRadius: 15)

        let bgAlpha: CGFloat = (isHovered || isOpen) ? 0.90 : 0.78
        palette.bg.withAlphaComponent(bgAlpha).setFill()
        path.fill()

        let borderColor = (isPlaying || isOpen || isHovered)
            ? palette.accent.withAlphaComponent(0.82)
            : palette.accentLight.withAlphaComponent(0.28)
        borderColor.setStroke()
        path.lineWidth = (isPlaying || isOpen) ? 1.5 : 1.0
        path.stroke()

        let symbolName = isPlaying ? "waveform" : "music.note"
        let cfg = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        if let sym = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Music")?
            .withSymbolConfiguration(cfg) {
            let tint = (isHovered || isPlaying || isOpen) ? palette.accentLight : palette.accent
            let tinted = NSImage(size: sym.size, flipped: false) { drawRect in
                sym.draw(in: drawRect)
                tint.set()
                drawRect.fill(using: .sourceAtop)
                return true
            }
            let sz = sym.size
            let dst = NSRect(
                x: (bounds.width - sz.width) / 2.0,
                y: (bounds.height - sz.height) / 2.0,
                width: sz.width,
                height: sz.height
            )
            tinted.draw(in: dst)
        }

        if isPlaying {
            let dotRect = NSRect(x: bounds.maxX - 11, y: bounds.maxY - 11, width: 6, height: 6)
            palette.accent.setFill()
            NSBezierPath(ovalIn: dotRect).fill()
        }
    }
}

final class CornerButtonWindow: NSPanel {
    let buttonView = CornerMusicButtonView()

    init() {
        let size: CGFloat = 44
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: size, height: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = NSWindow.Level(NSWindow.Level.normal.rawValue - 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        contentView = buttonView
        reposition()
    }

    func reposition() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let size: CGFloat = 44
        let x = screen.frame.maxX - size - 16
        let y = screen.frame.minY + 12
        setFrame(NSRect(x: x, y: y, width: size, height: size), display: true)
    }

    func setDesktopVisibility(empty: Bool, forceVisible: Bool) {
        let show = empty || forceVisible
        let targetAlpha: CGFloat = show ? 1.0 : 0.0
        if abs(alphaValue - targetAlpha) > 0.05 {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                self.animator().alphaValue = targetAlpha
            }
        }
        ignoresMouseEvents = !show
    }
}

// MARK: - Telegram Download Badge & Ring Overlay

private func formatCompactBytes(_ bytes: Int64) -> String {
    if bytes >= 1_048_576 {
        return String(format: "%.1f MB", Double(bytes) / 1_048_576.0)
    }
    return String(format: "%.0f KB", max(1.0, Double(bytes) / 1024.0))
}

final class TelegramDownloadBadgeView: NSView {
    private let backdropLayer = CALayer()
    private let trackRingLayer = CAShapeLayer()
    private let progressRingLayer = CAShapeLayer()
    private let iconView = NSImageView()
    private var isSpinning = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) { nil }

    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        layer?.isGeometryFlipped = true

        backdropLayer.masksToBounds = true
        layer?.addSublayer(backdropLayer)

        trackRingLayer.fillColor = nil
        trackRingLayer.lineWidth = 2.0
        trackRingLayer.strokeColor = NSColor.white.withAlphaComponent(0.24).cgColor
        layer?.addSublayer(trackRingLayer)

        progressRingLayer.fillColor = nil
        progressRingLayer.lineWidth = 2.0
        progressRingLayer.lineCap = .round
        progressRingLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer?.addSublayer(progressRingLayer)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentTintColor = .white
        addSubview(iconView)

        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        updateRingFrames()
    }

    override func layout() {
        super.layout()
        updateRingFrames()
    }

    private func updateRingFrames() {
        let w = bounds.width
        let h = bounds.height
        guard w > 0, h > 0 else { return }

        let circleSize: CGFloat = 24
        let origin = CGPoint(x: (w - circleSize) * 0.5, y: (h - circleSize) * 0.5)
        let ringRect = CGRect(origin: origin, size: CGSize(width: circleSize, height: circleSize))

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdropLayer.frame = ringRect
        backdropLayer.cornerRadius = circleSize * 0.5

        trackRingLayer.frame = ringRect
        progressRingLayer.frame = ringRect
        let ringBounds = CGRect(x: 0, y: 0, width: circleSize, height: circleSize)
        let path = CGMutablePath()
        path.addArc(
            center: CGPoint(x: ringBounds.midX, y: ringBounds.midY),
            radius: 9.5,
            startAngle: -.pi / 2,
            endAngle: 1.5 * .pi,
            clockwise: false
        )
        trackRingLayer.path = path
        progressRingLayer.path = path
        CATransaction.commit()
    }

    private func setSpinning(_ spin: Bool) {
        if spin == isSpinning { return }
        isSpinning = spin
        if spin {
            let anim = CABasicAnimation(keyPath: "transform.rotation.z")
            anim.fromValue = 0
            anim.toValue = Double.pi * 2
            anim.duration = 1.05
            anim.repeatCount = .infinity
            anim.isRemovedOnCompletion = false
            progressRingLayer.add(anim, forKey: "tgSpin")
        } else {
            progressRingLayer.removeAnimation(forKey: "tgSpin")
        }
    }

    func update(cached: Bool, isDownloading: Bool, progress: Double, accent: NSColor) {
        if cached && !isDownloading {
            isHidden = true
            setSpinning(false)
            return
        }

        isHidden = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if isDownloading {
            backdropLayer.backgroundColor = NSColor.black.withAlphaComponent(0.68).cgColor
            backdropLayer.borderWidth = 0
            trackRingLayer.isHidden = false
            progressRingLayer.isHidden = false
            progressRingLayer.strokeColor = accent.cgColor

            let cfg = NSImage.SymbolConfiguration(pointSize: 8.5, weight: .bold)
            iconView.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Cancel download")?
                .withSymbolConfiguration(cfg)
            iconView.contentTintColor = .white.withAlphaComponent(0.95)

            if progress <= 0.005 {
                progressRingLayer.strokeEnd = 0.28
                setSpinning(true)
            } else {
                setSpinning(false)
                progressRingLayer.strokeEnd = CGFloat(max(0.06, min(1.0, progress)))
            }
        } else {
            setSpinning(false)
            backdropLayer.backgroundColor = NSColor.black.withAlphaComponent(0.54).cgColor
            backdropLayer.borderWidth = 0.8
            backdropLayer.borderColor = NSColor.white.withAlphaComponent(0.24).cgColor
            trackRingLayer.isHidden = true
            progressRingLayer.isHidden = true

            let cfg = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
            iconView.image = NSImage(systemSymbolName: "arrow.down", accessibilityDescription: "Download")?
                .withSymbolConfiguration(cfg)
            iconView.contentTintColor = .white.withAlphaComponent(0.92)
        }
        CATransaction.commit()
    }
}

// MARK: - Track Row Cell View

final class TrackRowCellView: NSTableCellView {
    private let thumbView = NSImageView()
    private let thumbPlaceholder = NSImageView()
    private let dlBadge = TelegramDownloadBadgeView()
    private let titleField = NSTextField(labelWithString: "")
    private let artistField = NSTextField(labelWithString: "")
    private let rightField = NSTextField(labelWithString: "")
    private let bgBox = NSView()

    private(set) var trackId: Int = 0
    private var badgeAccent: NSColor = .white

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) { nil }

    private func setup() {
        bgBox.translatesAutoresizingMaskIntoConstraints = false
        bgBox.wantsLayer = true
        bgBox.layer?.cornerRadius = 10
        addSubview(bgBox)

        thumbView.translatesAutoresizingMaskIntoConstraints = false
        thumbView.wantsLayer = true
        thumbView.layer?.cornerRadius = 8
        thumbView.layer?.masksToBounds = true
        thumbView.imageScaling = .scaleAxesIndependently
        bgBox.addSubview(thumbView)

        thumbPlaceholder.translatesAutoresizingMaskIntoConstraints = false
        let cfg = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        thumbPlaceholder.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg)
        bgBox.addSubview(thumbPlaceholder)

        dlBadge.translatesAutoresizingMaskIntoConstraints = false
        bgBox.addSubview(dlBadge)

        for lbl in [titleField, artistField, rightField] {
            lbl.translatesAutoresizingMaskIntoConstraints = false
            lbl.maximumNumberOfLines = 1
            lbl.usesSingleLineMode = true
            lbl.lineBreakMode = .byTruncatingTail
            lbl.cell?.truncatesLastVisibleLine = true
        }
        titleField.font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        artistField.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        artistField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        rightField.font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
        rightField.alignment = .right
        rightField.setContentCompressionResistancePriority(.required, for: .horizontal)
        rightField.setContentHuggingPriority(.required, for: .horizontal)

        bgBox.addSubview(titleField)
        bgBox.addSubview(artistField)
        bgBox.addSubview(rightField)

        NSLayoutConstraint.activate([
            bgBox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            bgBox.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            bgBox.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            bgBox.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),

            thumbView.leadingAnchor.constraint(equalTo: bgBox.leadingAnchor, constant: 8),
            thumbView.centerYAnchor.constraint(equalTo: bgBox.centerYAnchor),
            thumbView.widthAnchor.constraint(equalToConstant: 34),
            thumbView.heightAnchor.constraint(equalToConstant: 34),

            thumbPlaceholder.centerXAnchor.constraint(equalTo: thumbView.centerXAnchor),
            thumbPlaceholder.centerYAnchor.constraint(equalTo: thumbView.centerYAnchor),

            dlBadge.leadingAnchor.constraint(equalTo: thumbView.leadingAnchor),
            dlBadge.trailingAnchor.constraint(equalTo: thumbView.trailingAnchor),
            dlBadge.topAnchor.constraint(equalTo: thumbView.topAnchor),
            dlBadge.bottomAnchor.constraint(equalTo: thumbView.bottomAnchor),

            titleField.leadingAnchor.constraint(equalTo: thumbView.trailingAnchor, constant: 10),
            titleField.trailingAnchor.constraint(equalTo: rightField.leadingAnchor, constant: -8),
            titleField.topAnchor.constraint(equalTo: bgBox.topAnchor, constant: 7),

            artistField.leadingAnchor.constraint(equalTo: titleField.leadingAnchor),
            artistField.trailingAnchor.constraint(equalTo: rightField.leadingAnchor, constant: -8),
            artistField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 1),

            rightField.trailingAnchor.constraint(equalTo: bgBox.trailingAnchor, constant: -10),
            rightField.centerYAnchor.constraint(equalTo: bgBox.centerYAnchor)
        ])
    }

    func updateDownloadProgress(_ progress: Double) {
        dlBadge.update(cached: false, isDownloading: true, progress: progress, accent: badgeAccent)
        rightField.stringValue = progress > 0.005 ? "\(Int(progress * 100))%" : "…"
        rightField.textColor = badgeAccent
    }

    func configure(
        track: TgTrack,
        thumb: NSImage?,
        isCurrent: Bool,
        isDownloading: Bool,
        downloadProgress: Double,
        palette: ThemePalette
    ) {
        trackId = track.id
        badgeAccent = palette.accentLight
        titleField.stringValue = track.title
        artistField.stringValue = track.artist

        if isCurrent {
            bgBox.layer?.backgroundColor = palette.accent.withAlphaComponent(0.18).cgColor
            bgBox.layer?.borderWidth = 1.0
            bgBox.layer?.borderColor = palette.accent.withAlphaComponent(0.45).cgColor
            titleField.textColor = palette.accentLight
            artistField.textColor = .white.withAlphaComponent(0.75)
        } else {
            bgBox.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.03).cgColor
            bgBox.layer?.borderWidth = 0
            titleField.textColor = .white.withAlphaComponent(0.92)
            artistField.textColor = .white.withAlphaComponent(0.55)
        }

        if let img = thumb {
            thumbView.image = img
            thumbView.layer?.backgroundColor = NSColor.clear.cgColor
            thumbPlaceholder.isHidden = true
        } else {
            thumbView.image = nil
            thumbView.layer?.backgroundColor = palette.accent.withAlphaComponent(0.14).cgColor
            thumbPlaceholder.contentTintColor = palette.accentLight.withAlphaComponent(0.85)
            thumbPlaceholder.isHidden = false
        }

        let isCached = (track.cached == true)
        dlBadge.update(cached: isCached, isDownloading: isDownloading, progress: downloadProgress, accent: palette.accentLight)

        if isDownloading {
            rightField.stringValue = downloadProgress > 0.005 ? "\(Int(downloadProgress * 100))%" : "…"
            rightField.textColor = palette.accentLight
        } else {
            let dot = isCached ? "• " : ""
            rightField.stringValue = dot + formatDuration(Double(track.duration))
            rightField.textColor = isCached
                ? palette.accentLight.withAlphaComponent(0.72)
                : .white.withAlphaComponent(0.42)
        }
    }
}

// MARK: - Popover Playlist Player Window

final class PlaylistRowCellView: NSTableCellView {
    private let bgBox = NSView()
    private let iconBox = NSView()
    private let iconView = NSImageView()
    private let titleField = NSTextField(labelWithString: "")
    private let subtitleField = NSTextField(labelWithString: "")
    private let countField = NSTextField(labelWithString: "")
    private let chevronView = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) { nil }

    private func setup() {
        bgBox.translatesAutoresizingMaskIntoConstraints = false
        bgBox.wantsLayer = true
        bgBox.layer?.cornerRadius = 11
        addSubview(bgBox)

        iconBox.translatesAutoresizingMaskIntoConstraints = false
        iconBox.wantsLayer = true
        iconBox.layer?.cornerRadius = 9
        bgBox.addSubview(iconBox)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconBox.addSubview(iconView)

        for lbl in [titleField, subtitleField, countField] {
            lbl.translatesAutoresizingMaskIntoConstraints = false
            lbl.maximumNumberOfLines = 1
            lbl.usesSingleLineMode = true
            lbl.lineBreakMode = .byTruncatingTail
            lbl.cell?.truncatesLastVisibleLine = true
        }
        titleField.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        subtitleField.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        subtitleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        countField.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        countField.alignment = .right
        countField.setContentCompressionResistancePriority(.required, for: .horizontal)
        countField.setContentHuggingPriority(.required, for: .horizontal)

        chevronView.translatesAutoresizingMaskIntoConstraints = false
        let chevCfg = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        chevronView.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)?
            .withSymbolConfiguration(chevCfg)
        chevronView.setContentHuggingPriority(.required, for: .horizontal)

        bgBox.addSubview(titleField)
        bgBox.addSubview(subtitleField)
        bgBox.addSubview(countField)
        bgBox.addSubview(chevronView)

        NSLayoutConstraint.activate([
            bgBox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            bgBox.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            bgBox.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            bgBox.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3),

            iconBox.leadingAnchor.constraint(equalTo: bgBox.leadingAnchor, constant: 9),
            iconBox.centerYAnchor.constraint(equalTo: bgBox.centerYAnchor),
            iconBox.widthAnchor.constraint(equalToConstant: 36),
            iconBox.heightAnchor.constraint(equalToConstant: 36),

            iconView.centerXAnchor.constraint(equalTo: iconBox.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconBox.centerYAnchor),

            titleField.leadingAnchor.constraint(equalTo: iconBox.trailingAnchor, constant: 10),
            titleField.trailingAnchor.constraint(equalTo: countField.leadingAnchor, constant: -8),
            titleField.topAnchor.constraint(equalTo: bgBox.topAnchor, constant: 8),

            subtitleField.leadingAnchor.constraint(equalTo: titleField.leadingAnchor),
            subtitleField.trailingAnchor.constraint(equalTo: countField.leadingAnchor, constant: -8),
            subtitleField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 1),

            chevronView.trailingAnchor.constraint(equalTo: bgBox.trailingAnchor, constant: -10),
            chevronView.centerYAnchor.constraint(equalTo: bgBox.centerYAnchor),

            countField.trailingAnchor.constraint(equalTo: chevronView.leadingAnchor, constant: -6),
            countField.centerYAnchor.constraint(equalTo: bgBox.centerYAnchor),
        ])
    }

    func configure(playlist: TgPlaylist, isActiveQueue: Bool, palette: ThemePalette) {
        titleField.stringValue = playlist.name
        subtitleField.stringValue = playlist.subtitle ?? "\(playlist.track_ids.count) tracks"
        countField.stringValue = "\(playlist.track_ids.count)"

        let symName = playlist.icon ?? "music.note.list"
        let cfg = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        iconView.image = NSImage(systemSymbolName: symName, accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg)

        if isActiveQueue {
            bgBox.layer?.backgroundColor = palette.accent.withAlphaComponent(0.18).cgColor
            bgBox.layer?.borderWidth = 1.0
            bgBox.layer?.borderColor = palette.accent.withAlphaComponent(0.45).cgColor
            iconBox.layer?.backgroundColor = palette.accent.withAlphaComponent(0.28).cgColor
            iconView.contentTintColor = palette.accentLight
            titleField.textColor = palette.accentLight
            subtitleField.textColor = .white.withAlphaComponent(0.70)
            countField.textColor = palette.accentLight
            chevronView.contentTintColor = palette.accentLight
        } else {
            bgBox.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.04).cgColor
            bgBox.layer?.borderWidth = 0
            iconBox.layer?.backgroundColor = palette.accent.withAlphaComponent(0.15).cgColor
            iconView.contentTintColor = palette.accentLight.withAlphaComponent(0.92)
            titleField.textColor = .white.withAlphaComponent(0.94)
            subtitleField.textColor = .white.withAlphaComponent(0.54)
            countField.textColor = palette.accentLight.withAlphaComponent(0.80)
            chevronView.contentTintColor = .white.withAlphaComponent(0.38)
        }
    }
}

final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class PlayerPopoverWindow: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private enum LibraryTab {
        case tracks
        case playlists
    }

    private let player: MusicPlayerController
    private let panel: KeyablePanel
    private let effectView = NSVisualEffectView()
    private let overlayView = NSView()
    private let tintLayer = CALayer()
    private let borderLayer = CAShapeLayer()

    private let headerTitle = NSTextField(labelWithString: "Telegram Music")
    private let headerSub = NSTextField(labelWithString: "0 tracks")
    private let syncButton = NSButton()

    private let tabContainer = NSView()
    private let tracksTabBtn = NSButton()
    private let playlistsTabBtn = NSButton()
    private let searchField = NSSearchField()

    private let playlistBackBar = NSView()
    private let playlistBackBtn = NSButton()
    private let playlistBackTitle = NSTextField(labelWithString: "")
    private let playlistPlayBtn = NSButton()
    private var scrollTopToSearch: NSLayoutConstraint!
    private var scrollTopToBackBar: NSLayoutConstraint!

    private let scrollView = NSScrollView()
    private let tableView = NSTableView()

    // Setup placeholder view
    private let setupContainer = NSView()
    private let setupLabel = NSTextField(wrappingLabelWithString: "Connect Telegram to sync your music library.")
    private let setupButton = NSButton()

    // Now-Playing Footer
    private let footerDivider = NSView()
    private let npTitle = NSTextField(labelWithString: "Select a track")
    private let npArtist = NSTextField(labelWithString: "Click any song to play")
    private let progressSlider = NSSlider()
    private let elapsedLabel = NSTextField(labelWithString: "0:00")
    private let totalLabel = NSTextField(labelWithString: "0:00")
    private let shuffleBtn = NSButton()
    private let prevBtn = NSButton()
    private let playBtn = NSButton()
    private let nextBtn = NSButton()
    private let repeatBtn = NSButton()

    private var activeTab: LibraryTab = .tracks
    private var selectedPlaylist: TgPlaylist? = nil
    private var filteredTracks: [TgTrack] = []
    private var filteredPlaylists: [TgPlaylist] = []
    private var isUserScrubbing = false
    private var isAuthorized = true
    var onVisibilityChanged: ((Bool) -> Void)?

    var isOpen: Bool { panel.isVisible && panel.alphaValue > 0.1 }

    init(player: MusicPlayerController) {
        self.player = player
        let width: CGFloat = 356
        let height: CGFloat = 496
        panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.alphaValue = 0.0

        super.init()
        setupUI(width: width, height: height)
        applyPalette()
        filteredTracks = player.tracks
        filteredPlaylists = player.playlists
        reloadTableAndHeader()
        updateFooter()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResignKey),
            name: NSWindow.didResignKeyNotification,
            object: panel
        )
    }

    private func setupUI(width: CGFloat, height: CGFloat) {
        let radius: CGFloat = 20
        let root = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        root.wantsLayer = true
        panel.contentView = root

        effectView.frame = root.bounds
        effectView.autoresizingMask = [.width, .height]
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = radius
        effectView.layer?.masksToBounds = true
        root.addSubview(effectView)

        overlayView.frame = root.bounds
        overlayView.autoresizingMask = [.width, .height]
        overlayView.wantsLayer = true
        root.addSubview(overlayView)

        tintLayer.frame = root.bounds
        tintLayer.cornerRadius = radius
        overlayView.layer?.addSublayer(tintLayer)

        borderLayer.frame = root.bounds
        borderLayer.path = CGPath(roundedRect: root.bounds.insetBy(dx: 0.5, dy: 0.5), cornerWidth: radius, cornerHeight: radius, transform: nil)
        borderLayer.fillColor = nil
        borderLayer.lineWidth = 1.0
        overlayView.layer?.addSublayer(borderLayer)

        // Header
        headerTitle.translatesAutoresizingMaskIntoConstraints = false
        headerTitle.font = NSFont.systemFont(ofSize: 13.5, weight: .bold)
        headerTitle.textColor = .white.withAlphaComponent(0.95)
        headerTitle.lineBreakMode = .byTruncatingTail
        root.addSubview(headerTitle)

        headerSub.translatesAutoresizingMaskIntoConstraints = false
        headerSub.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        headerSub.textColor = .white.withAlphaComponent(0.55)
        root.addSubview(headerSub)

        syncButton.translatesAutoresizingMaskIntoConstraints = false
        syncButton.isBordered = false
        syncButton.title = ""
        syncButton.toolTip = "Sync tracks from Telegram"
        syncButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Sync")
        syncButton.target = self
        syncButton.action = #selector(onSyncClicked)
        root.addSubview(syncButton)

        // Segmented Tabs: Tracks | Playlists
        tabContainer.translatesAutoresizingMaskIntoConstraints = false
        tabContainer.wantsLayer = true
        tabContainer.layer?.cornerRadius = 9
        tabContainer.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.06).cgColor
        root.addSubview(tabContainer)

        for (btn, title, action) in [
            (tracksTabBtn, "Tracks", #selector(onTracksTabClicked)),
            (playlistsTabBtn, "Playlists", #selector(onPlaylistsTabClicked)),
        ] {
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.isBordered = false
            btn.wantsLayer = true
            btn.layer?.cornerRadius = 7
            btn.title = title
            btn.font = NSFont.systemFont(ofSize: 11.5, weight: .semibold)
            btn.target = self
            btn.action = action
            tabContainer.addSubview(btn)
        }

        // Search field
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "Search tracks…"
        searchField.delegate = self
        searchField.focusRingType = .none
        searchField.font = NSFont.systemFont(ofSize: 12)
        root.addSubview(searchField)

        // Playlist detail back bar (hidden unless inside a playlist)
        playlistBackBar.translatesAutoresizingMaskIntoConstraints = false
        playlistBackBar.wantsLayer = true
        playlistBackBar.layer?.cornerRadius = 8
        playlistBackBar.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.05).cgColor
        playlistBackBar.isHidden = true
        root.addSubview(playlistBackBar)

        playlistBackBtn.translatesAutoresizingMaskIntoConstraints = false
        playlistBackBtn.isBordered = false
        playlistBackBtn.title = " Playlists"
        let backCfg = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        playlistBackBtn.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Back")?
            .withSymbolConfiguration(backCfg)
        playlistBackBtn.imagePosition = .imageLeading
        playlistBackBtn.font = NSFont.systemFont(ofSize: 11.5, weight: .semibold)
        playlistBackBtn.target = self
        playlistBackBtn.action = #selector(onPlaylistBackClicked)
        playlistBackBar.addSubview(playlistBackBtn)

        playlistBackTitle.translatesAutoresizingMaskIntoConstraints = false
        playlistBackTitle.font = NSFont.systemFont(ofSize: 11.5, weight: .bold)
        playlistBackTitle.alignment = .center
        playlistBackTitle.lineBreakMode = .byTruncatingTail
        playlistBackTitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        playlistBackBar.addSubview(playlistBackTitle)

        playlistPlayBtn.translatesAutoresizingMaskIntoConstraints = false
        playlistPlayBtn.isBordered = false
        playlistPlayBtn.wantsLayer = true
        playlistPlayBtn.layer?.cornerRadius = 6
        let playSmallCfg = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
        playlistPlayBtn.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Play playlist")?
            .withSymbolConfiguration(playSmallCfg)
        playlistPlayBtn.title = " Play"
        playlistPlayBtn.imagePosition = .imageLeading
        playlistPlayBtn.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        playlistPlayBtn.target = self
        playlistPlayBtn.action = #selector(onPlayPlaylistClicked)
        playlistBackBar.addSubview(playlistPlayBtn)

        // Track table
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("track"))
        col.width = width - 16
        tableView.addTableColumn(col)
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .none
        tableView.rowHeight = 48
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(onRowClicked)

        scrollView.documentView = tableView
        root.addSubview(scrollView)

        // Setup empty state
        setupContainer.translatesAutoresizingMaskIntoConstraints = false
        setupContainer.isHidden = true
        root.addSubview(setupContainer)

        setupLabel.translatesAutoresizingMaskIntoConstraints = false
        setupLabel.alignment = .center
        setupLabel.font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        setupLabel.textColor = .white.withAlphaComponent(0.75)
        setupContainer.addSubview(setupLabel)

        setupButton.translatesAutoresizingMaskIntoConstraints = false
        setupButton.bezelStyle = .rounded
        setupButton.title = "Setup Telegram in Terminal"
        setupButton.target = self
        setupButton.action = #selector(onSetupClicked)
        setupContainer.addSubview(setupButton)

        // Footer
        footerDivider.translatesAutoresizingMaskIntoConstraints = false
        footerDivider.wantsLayer = true
        footerDivider.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
        root.addSubview(footerDivider)

        for lbl in [npTitle, npArtist] {
            lbl.translatesAutoresizingMaskIntoConstraints = false
            lbl.maximumNumberOfLines = 1
            lbl.usesSingleLineMode = true
            lbl.lineBreakMode = .byTruncatingTail
            lbl.cell?.truncatesLastVisibleLine = true
            lbl.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        npTitle.font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        npTitle.textColor = .white.withAlphaComponent(0.95)
        npArtist.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        npArtist.textColor = .white.withAlphaComponent(0.58)
        root.addSubview(npTitle)
        root.addSubview(npArtist)

        progressSlider.translatesAutoresizingMaskIntoConstraints = false
        progressSlider.minValue = 0.0
        progressSlider.maxValue = 1.0
        progressSlider.doubleValue = 0.0
        progressSlider.controlSize = .mini
        progressSlider.isContinuous = true
        progressSlider.target = self
        progressSlider.action = #selector(onSliderChanged)
        root.addSubview(progressSlider)

        for lbl in [elapsedLabel, totalLabel] {
            lbl.translatesAutoresizingMaskIntoConstraints = false
            lbl.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
            lbl.textColor = .white.withAlphaComponent(0.50)
        }
        totalLabel.alignment = .right
        root.addSubview(elapsedLabel)
        root.addSubview(totalLabel)

        func configureBtn(_ b: NSButton, symbol: String, size: CGFloat, action: Selector) {
            b.translatesAutoresizingMaskIntoConstraints = false
            b.isBordered = false
            b.title = ""
            let cfg = NSImage.SymbolConfiguration(pointSize: size, weight: .medium)
            b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(cfg)
            b.target = self
            b.action = action
        }

        configureBtn(shuffleBtn, symbol: "shuffle", size: 12.5, action: #selector(onShuffleClicked))
        configureBtn(prevBtn, symbol: "backward.fill", size: 15, action: #selector(onPrevClicked))
        configureBtn(playBtn, symbol: "play.circle.fill", size: 28, action: #selector(onPlayClicked))
        configureBtn(nextBtn, symbol: "forward.fill", size: 15, action: #selector(onNextClicked))
        configureBtn(repeatBtn, symbol: "repeat", size: 12.5, action: #selector(onRepeatClicked))

        let controls = NSStackView(views: [shuffleBtn, prevBtn, playBtn, nextBtn, repeatBtn])
        controls.translatesAutoresizingMaskIntoConstraints = false
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 18
        root.addSubview(controls)

        scrollTopToSearch = scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8)
        scrollTopToBackBar = scrollView.topAnchor.constraint(equalTo: playlistBackBar.bottomAnchor, constant: 6)

        NSLayoutConstraint.activate([
            headerTitle.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            headerTitle.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            headerTitle.trailingAnchor.constraint(lessThanOrEqualTo: syncButton.leadingAnchor, constant: -8),

            headerSub.leadingAnchor.constraint(equalTo: headerTitle.leadingAnchor),
            headerSub.topAnchor.constraint(equalTo: headerTitle.bottomAnchor, constant: 1),

            syncButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            syncButton.centerYAnchor.constraint(equalTo: headerTitle.bottomAnchor),
            syncButton.widthAnchor.constraint(equalToConstant: 26),
            syncButton.heightAnchor.constraint(equalToConstant: 26),

            tabContainer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            tabContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            tabContainer.topAnchor.constraint(equalTo: headerSub.bottomAnchor, constant: 8),
            tabContainer.heightAnchor.constraint(equalToConstant: 28),

            tracksTabBtn.leadingAnchor.constraint(equalTo: tabContainer.leadingAnchor, constant: 3),
            tracksTabBtn.topAnchor.constraint(equalTo: tabContainer.topAnchor, constant: 3),
            tracksTabBtn.bottomAnchor.constraint(equalTo: tabContainer.bottomAnchor, constant: -3),

            playlistsTabBtn.leadingAnchor.constraint(equalTo: tracksTabBtn.trailingAnchor, constant: 3),
            playlistsTabBtn.trailingAnchor.constraint(equalTo: tabContainer.trailingAnchor, constant: -3),
            playlistsTabBtn.topAnchor.constraint(equalTo: tabContainer.topAnchor, constant: 3),
            playlistsTabBtn.bottomAnchor.constraint(equalTo: tabContainer.bottomAnchor, constant: -3),
            playlistsTabBtn.widthAnchor.constraint(equalTo: tracksTabBtn.widthAnchor),

            searchField.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            searchField.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            searchField.topAnchor.constraint(equalTo: tabContainer.bottomAnchor, constant: 8),

            playlistBackBar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            playlistBackBar.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            playlistBackBar.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 6),
            playlistBackBar.heightAnchor.constraint(equalToConstant: 28),

            playlistBackBtn.leadingAnchor.constraint(equalTo: playlistBackBar.leadingAnchor, constant: 8),
            playlistBackBtn.centerYAnchor.constraint(equalTo: playlistBackBar.centerYAnchor),

            playlistPlayBtn.trailingAnchor.constraint(equalTo: playlistBackBar.trailingAnchor, constant: -6),
            playlistPlayBtn.centerYAnchor.constraint(equalTo: playlistBackBar.centerYAnchor),
            playlistPlayBtn.widthAnchor.constraint(equalToConstant: 56),
            playlistPlayBtn.heightAnchor.constraint(equalToConstant: 20),

            playlistBackTitle.leadingAnchor.constraint(greaterThanOrEqualTo: playlistBackBtn.trailingAnchor, constant: 6),
            playlistBackTitle.trailingAnchor.constraint(lessThanOrEqualTo: playlistPlayBtn.leadingAnchor, constant: -6),
            playlistBackTitle.centerXAnchor.constraint(equalTo: playlistBackBar.centerXAnchor),
            playlistBackTitle.centerYAnchor.constraint(equalTo: playlistBackBar.centerYAnchor),

            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 6),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -6),
            scrollTopToSearch,
            scrollView.bottomAnchor.constraint(equalTo: footerDivider.topAnchor, constant: -6),

            setupContainer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            setupContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            setupContainer.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),

            setupLabel.topAnchor.constraint(equalTo: setupContainer.topAnchor),
            setupLabel.leadingAnchor.constraint(equalTo: setupContainer.leadingAnchor),
            setupLabel.trailingAnchor.constraint(equalTo: setupContainer.trailingAnchor),

            setupButton.topAnchor.constraint(equalTo: setupLabel.bottomAnchor, constant: 12),
            setupButton.centerXAnchor.constraint(equalTo: setupContainer.centerXAnchor),
            setupButton.bottomAnchor.constraint(equalTo: setupContainer.bottomAnchor),

            footerDivider.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            footerDivider.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            footerDivider.heightAnchor.constraint(equalToConstant: 1),
            footerDivider.bottomAnchor.constraint(equalTo: npTitle.topAnchor, constant: -8),

            npTitle.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            npTitle.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            npArtist.leadingAnchor.constraint(equalTo: npTitle.leadingAnchor),
            npArtist.trailingAnchor.constraint(equalTo: npTitle.trailingAnchor),
            npArtist.topAnchor.constraint(equalTo: npTitle.bottomAnchor, constant: 1),

            elapsedLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            elapsedLabel.topAnchor.constraint(equalTo: npArtist.bottomAnchor, constant: 7),
            totalLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            totalLabel.centerYAnchor.constraint(equalTo: elapsedLabel.centerYAnchor),

            progressSlider.leadingAnchor.constraint(equalTo: elapsedLabel.trailingAnchor, constant: 8),
            progressSlider.trailingAnchor.constraint(equalTo: totalLabel.leadingAnchor, constant: -8),
            progressSlider.centerYAnchor.constraint(equalTo: elapsedLabel.centerYAnchor),

            controls.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            controls.topAnchor.constraint(equalTo: progressSlider.bottomAnchor, constant: 6),
            controls.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12)
        ])
    }

    func applyPalette() {
        let pal = ThemePalette.load()
        player.palette = pal
        tintLayer.backgroundColor = pal.bg.withAlphaComponent(0.84).cgColor
        borderLayer.strokeColor = pal.accentLight.withAlphaComponent(0.24).cgColor
        syncButton.contentTintColor = pal.accentLight
        prevBtn.contentTintColor = .white.withAlphaComponent(0.86)
        nextBtn.contentTintColor = .white.withAlphaComponent(0.86)
        playBtn.contentTintColor = pal.accentLight
        shuffleBtn.contentTintColor = player.shuffleEnabled ? pal.accent : .white.withAlphaComponent(0.45)
        repeatBtn.contentTintColor = player.repeatOne ? pal.accent : .white.withAlphaComponent(0.45)
        updateTabButtonsUI()
        tableView.reloadData()
    }

    private func updateTabButtonsUI() {
        let pal = player.palette
        let isTracks = (activeTab == .tracks)

        func styleTab(_ btn: NSButton, active: Bool) {
            btn.layer?.backgroundColor = active ? pal.accent.withAlphaComponent(0.26).cgColor : NSColor.clear.cgColor
            btn.layer?.borderWidth = active ? 1.0 : 0.0
            btn.layer?.borderColor = active ? pal.accent.withAlphaComponent(0.48).cgColor : NSColor.clear.cgColor
            let titleColor = active ? pal.accentLight : NSColor.white.withAlphaComponent(0.60)
            let attr = NSAttributedString(
                string: btn.title,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11.5, weight: active ? .bold : .medium),
                    .foregroundColor: titleColor,
                ]
            )
            btn.attributedTitle = attr
        }

        let plCount = player.playlists.count
        tracksTabBtn.title = "Tracks (\(player.tracks.count))"
        playlistsTabBtn.title = plCount > 0 ? "Playlists (\(plCount))" : "Playlists"
        styleTab(tracksTabBtn, active: isTracks)
        styleTab(playlistsTabBtn, active: !isTracks)

        let showBackBar = (!isTracks && selectedPlaylist != nil)
        playlistBackBar.isHidden = !showBackBar
        scrollTopToSearch.isActive = !showBackBar
        scrollTopToBackBar.isActive = showBackBar

        if let pl = selectedPlaylist, !isTracks {
            playlistBackTitle.stringValue = "\(pl.name) (\(pl.track_ids.count))"
            playlistBackTitle.textColor = pal.accentLight
            playlistBackBtn.contentTintColor = .white.withAlphaComponent(0.78)
            playlistBackBtn.attributedTitle = NSAttributedString(
                string: " Playlists",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11.5, weight: .semibold),
                    .foregroundColor: NSColor.white.withAlphaComponent(0.78),
                ]
            )
            playlistPlayBtn.layer?.backgroundColor = pal.accent.withAlphaComponent(0.24).cgColor
            playlistPlayBtn.contentTintColor = pal.accentLight
            playlistPlayBtn.attributedTitle = NSAttributedString(
                string: " Play",
                attributes: [
                    .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                    .foregroundColor: pal.accentLight,
                ]
            )
            searchField.placeholderString = "Search in \(pl.name)…"
        } else if !isTracks {
            searchField.placeholderString = "Filter playlists…"
        } else {
            searchField.placeholderString = "Search tracks…"
        }
    }

    func openPlaylistsTab(anchorCornerFrame: NSRect) {
        activeTab = .playlists
        selectedPlaylist = nil
        searchField.stringValue = ""
        open(anchorCornerFrame: anchorCornerFrame)
        tableView.scrollRowToVisible(0)
    }

    func toggle(anchorCornerFrame: NSRect) {
        if isOpen {
            close()
        } else {
            open(anchorCornerFrame: anchorCornerFrame)
        }
    }

    func open(anchorCornerFrame: NSRect) {
        applyPalette()
        player.loadCachedLibrary()
        applyFilter()

        let w = panel.frame.width
        let h = panel.frame.height
        let x = anchorCornerFrame.maxX - w
        let y = anchorCornerFrame.maxY + 10
        panel.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)

        NSApp.activate(ignoringOtherApps: true)
        panel.alphaValue = 0.0
        panel.makeKeyAndOrderFront(nil)
        onVisibilityChanged?(true)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1.0
        }

        player.checkStatus { [weak self] st in
            guard let self = self else { return }
            if let st = st {
                self.isAuthorized = st.configured && st.authorized
            } else {
                self.isAuthorized = !self.player.tracks.isEmpty
            }
            self.reloadTableAndHeader()
        }
    }

    func close() {
        guard panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0.0
        }, completionHandler: {
            self.panel.orderOut(nil)
            self.onVisibilityChanged?(false)
        })
    }

    @objc private func windowDidResignKey() {
        close()
    }

    private func applyFilter() {
        let q = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if activeTab == .playlists {
            if let pl = selectedPlaylist {
                let updated = player.playlists.first(where: { $0.id == pl.id }) ?? pl
                selectedPlaylist = updated
                let source = player.tracks(for: updated)
                filteredTracks = q.isEmpty ? source : source.filter {
                    $0.title.lowercased().contains(q) || $0.artist.lowercased().contains(q)
                }
            } else {
                filteredPlaylists = q.isEmpty ? player.playlists : player.playlists.filter {
                    $0.name.lowercased().contains(q) || ($0.subtitle?.lowercased().contains(q) ?? false)
                }
            }
            return
        }

        filteredTracks = q.isEmpty ? player.tracks : player.tracks.filter {
            $0.title.lowercased().contains(q) || $0.artist.lowercased().contains(q)
        }
    }

    func reloadTableAndHeader() {
        applyFilter()
        updateTabButtonsUI()
        headerTitle.stringValue = "Telegram Music"
        if player.isSyncing {
            headerSub.stringValue = "Syncing from Telegram…"
        } else if let err = player.statusError {
            headerSub.stringValue = err
        } else {
            let cachedCount = player.tracks.reduce(0) { $0 + ($1.cached == true ? 1 : 0) }
            headerSub.stringValue = cachedCount > 0
                ? "\(player.tracks.count) tracks • \(cachedCount) cached"
                : "\(player.tracks.count) tracks"
        }

        let showSetup = player.tracks.isEmpty && !isAuthorized
        setupContainer.isHidden = !showSetup
        scrollView.isHidden = showSetup
        tableView.reloadData()
    }

    private func downloadingStatusText(progress: Double, received: Int64, total: Int64) -> String {
        if received <= 0 {
            return "Downloading from Telegram…"
        }
        if total > 0 {
            let pct = Int(progress * 100)
            return "Downloading \(pct)% • \(formatCompactBytes(received)) / \(formatCompactBytes(total))"
        }
        return "Downloading • \(formatCompactBytes(received))"
    }

    func updateDownloadProgress(trackId: Int, progress: Double, received: Int64, total: Int64) {
        if player.currentTrack?.id == trackId, player.isDownloading {
            npArtist.stringValue = downloadingStatusText(progress: progress, received: received, total: total)
        }
        tableView.enumerateAvailableRowViews { rowView, _ in
            if let cell = rowView.view(atColumn: 0) as? TrackRowCellView, cell.trackId == trackId {
                cell.updateDownloadProgress(progress)
            }
        }
    }

    func updateFooter() {
        let pal = player.palette
        if let t = player.currentTrack {
            npTitle.stringValue = t.title
            npArtist.stringValue = player.isDownloading
                ? downloadingStatusText(
                    progress: player.downloadProgress,
                    received: player.downloadReceivedBytes,
                    total: player.downloadTotalBytes
                )
                : t.artist
        } else {
            npTitle.stringValue = "Select a track"
            npArtist.stringValue = player.tracks.isEmpty ? "No tracks loaded yet" : "Click any song to play"
        }

        let symbol = player.isPlaying ? "pause.circle.fill" : "play.circle.fill"
        let cfg = NSImage.SymbolConfiguration(pointSize: 28, weight: .medium)
        playBtn.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Play/Pause")?.withSymbolConfiguration(cfg)
        playBtn.contentTintColor = pal.accentLight
        shuffleBtn.contentTintColor = player.shuffleEnabled ? pal.accent : .white.withAlphaComponent(0.45)
        repeatBtn.contentTintColor = player.repeatOne ? pal.accent : .white.withAlphaComponent(0.45)

        updateTime(current: player.currentTime, total: player.duration)
    }

    func updateTime(current: Double, total: Double) {
        guard !isUserScrubbing else { return }
        elapsedLabel.stringValue = formatDuration(current)
        totalLabel.stringValue = formatDuration(total)
        progressSlider.doubleValue = (total > 0) ? max(0, min(1, current / total)) : 0
    }

    // MARK: Actions

    @objc private func onSyncClicked() {
        player.syncLibrary()
    }

    @objc private func onSetupClicked() {
        guard let (py, sc) = resolveSyncPaths() else { return }
        close()
        let cmd = "'\(py)' '\(sc)' --setup"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-n", "-a", "Kitty", "--args", "zsh", "-lc", "\(cmd); echo; read -k 1 '?Press any key to close...'"]
        try? p.run()
    }

    @objc private func onTracksTabClicked() {
        guard activeTab != .tracks else { return }
        activeTab = .tracks
        searchField.stringValue = ""
        reloadTableAndHeader()
        tableView.scrollRowToVisible(0)
    }

    @objc private func onPlaylistsTabClicked() {
        if activeTab == .playlists && selectedPlaylist != nil {
            selectedPlaylist = nil
            searchField.stringValue = ""
            reloadTableAndHeader()
            tableView.scrollRowToVisible(0)
            return
        }
        guard activeTab != .playlists else { return }
        activeTab = .playlists
        searchField.stringValue = ""
        reloadTableAndHeader()
        tableView.scrollRowToVisible(0)
    }

    @objc private func onPlaylistBackClicked() {
        selectedPlaylist = nil
        searchField.stringValue = ""
        reloadTableAndHeader()
        tableView.scrollRowToVisible(0)
    }

    @objc private func onPlayPlaylistClicked() {
        guard let pl = selectedPlaylist else { return }
        let queue = player.tracks(for: pl)
        guard !queue.isEmpty else { return }
        let start = player.shuffleEnabled ? (queue.randomElement() ?? queue[0]) : queue[0]
        player.play(track: start, queue: queue)
    }

    @objc private func onRowClicked() {
        let row = tableView.clickedRow
        if activeTab == .playlists, selectedPlaylist == nil {
            guard row >= 0, row < filteredPlaylists.count else { return }
            selectedPlaylist = filteredPlaylists[row]
            searchField.stringValue = ""
            reloadTableAndHeader()
            if !filteredTracks.isEmpty {
                tableView.scrollRowToVisible(0)
            }
            return
        }

        guard row >= 0, row < filteredTracks.count else { return }
        let queue: [TgTrack]
        if activeTab == .playlists, let pl = selectedPlaylist {
            queue = player.tracks(for: pl)
        } else {
            queue = player.tracks
        }
        player.play(track: filteredTracks[row], queue: queue)
    }

    @objc private func onSliderChanged() {
        let event = NSApp.currentEvent
        if event?.type == .leftMouseUp {
            isUserScrubbing = false
            player.seek(to: progressSlider.doubleValue)
        } else {
            isUserScrubbing = true
            elapsedLabel.stringValue = formatDuration(progressSlider.doubleValue * player.duration)
        }
    }

    @objc private func onPlayClicked() { player.togglePlayPause() }
    @objc private func onNextClicked() { player.nextTrack() }
    @objc private func onPrevClicked() { player.prevTrack() }
    @objc private func onShuffleClicked() { player.toggleShuffle() }
    @objc private func onRepeatClicked() { player.toggleRepeat() }

    // MARK: NSSearchFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        reloadTableAndHeader()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            close()
            return true
        }
        return false
    }

    // MARK: NSTableViewDataSource / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int {
        if activeTab == .playlists, selectedPlaylist == nil {
            return filteredPlaylists.count
        }
        return filteredTracks.count
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if activeTab == .playlists, selectedPlaylist == nil {
            return 56
        }
        return 48
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if activeTab == .playlists, selectedPlaylist == nil {
            guard row < filteredPlaylists.count else { return nil }
            let id = NSUserInterfaceItemIdentifier("PlaylistRowCell")
            let cell = (tableView.makeView(withIdentifier: id, owner: self) as? PlaylistRowCellView) ?? PlaylistRowCellView()
            cell.identifier = id
            let pl = filteredPlaylists[row]
            let isCurInPlaylist = player.currentTrack.map { pl.track_ids.contains($0.id) } ?? false
            cell.configure(playlist: pl, isActiveQueue: isCurInPlaylist, palette: player.palette)
            return cell
        }

        guard row < filteredTracks.count else { return nil }
        let id = NSUserInterfaceItemIdentifier("TrackRowCell")
        let cell = (tableView.makeView(withIdentifier: id, owner: self) as? TrackRowCellView) ?? TrackRowCellView()
        cell.identifier = id

        let track = filteredTracks[row]
        let isCur = player.currentTrack?.id == track.id
        let isDl = isCur && player.isDownloading
        cell.configure(
            track: track,
            thumb: player.thumbnail(for: track),
            isCurrent: isCur,
            isDownloading: isDl,
            downloadProgress: isDl ? player.downloadProgress : 0,
            palette: player.palette
        )
        return cell
    }
}

// MARK: - AppDelegate & Entrypoint

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var player: MusicPlayerController!
    private var cornerWindow: CornerButtonWindow!
    private var popover: PlayerPopoverWindow!
    private var stateTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        try? "\(getpid())".write(toFile: kPidPath, atomically: true, encoding: .utf8)

        player = MusicPlayerController()
        cornerWindow = CornerButtonWindow()
        popover = PlayerPopoverWindow(player: player)

        cornerWindow.buttonView.onClick = { [weak self] in
            guard let self = self else { return }
            self.popover.toggle(anchorCornerFrame: self.cornerWindow.frame)
        }

        popover.onVisibilityChanged = { [weak self] open in
            self?.cornerWindow.buttonView.isOpen = open
            self?.checkDesktopState()
        }

        player.onStateChanged = { [weak self] in
            guard let self = self else { return }
            self.cornerWindow.buttonView.isPlaying = self.player.isPlaying
            self.popover.reloadTableAndHeader()
            self.popover.updateFooter()
        }

        player.onTimeUpdated = { [weak self] cur, dur in
            self?.popover.updateTime(current: cur, total: dur)
        }

        player.onDownloadProgress = { [weak self] trackId, progress, received, total in
            self?.popover.updateDownloadProgress(trackId: trackId, progress: progress, received: received, total: total)
        }

        cornerWindow.orderFront(nil)
        checkDesktopState()

        let wsCenter = NSWorkspace.shared.notificationCenter
        let wsNotes: [NSNotification.Name] = [
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didDeactivateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification
        ]
        for name in wsNotes {
            wsCenter.addObserver(self, selector: #selector(checkDesktopState), name: name, object: nil)
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.cornerWindow.reposition()
            self?.checkDesktopState()
        }

        stateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkDesktopState()
        }

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleToggle),
            name: kToggleMusicNotification,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleOpenPlaylists),
            name: kOpenPlaylistsNotification,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleThemeChanged),
            name: kThemeNotification,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleThemeChanged),
            name: kMusicThemeNotification,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53, self?.popover.isOpen == true {
                self?.popover.close()
                return nil
            }
            return event
        }
    }

    @objc private func handleToggle() {
        DispatchQueue.main.async {
            self.popover.toggle(anchorCornerFrame: self.cornerWindow.frame)
        }
    }

    @objc private func handleOpenPlaylists() {
        DispatchQueue.main.async {
            self.popover.openPlaylistsTab(anchorCornerFrame: self.cornerWindow.frame)
        }
    }

    @objc private func handleThemeChanged() {
        DispatchQueue.main.async {
            let pal = ThemePalette.load()
            self.cornerWindow.buttonView.palette = pal
            self.cornerWindow.buttonView.needsDisplay = true
            self.popover.applyPalette()
        }
    }

    @objc private func checkDesktopState() {
        let empty = isDesktopAreaUncovered(for: cornerWindow.frame)
        cornerWindow.setDesktopVisibility(empty: empty, forceVisible: popover.isOpen)
    }
}

if CommandLine.arguments.contains("--help") || CommandLine.arguments.contains("-h") {
    print("""
    tg_music — Minimalist desktop music player synced with Telegram (Telethon)

    Usage:
      tg_music                Start desktop corner icon daemon
      tg_music --toggle       Toggle the playlist popover
      tg_music --reload-theme Reload theme colors from ~/.config/rofi/colors.json
    """)
    exit(0)
}

if CommandLine.arguments.contains("--reload-theme") {
    DistributedNotificationCenter.default().postNotificationName(
        kMusicThemeNotification,
        object: nil,
        userInfo: nil,
        deliverImmediately: true
    )
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    exit(0)
}

if CommandLine.arguments.contains("--playlists") {
    DistributedNotificationCenter.default().postNotificationName(
        kOpenPlaylistsNotification,
        object: nil,
        userInfo: nil,
        deliverImmediately: true
    )
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    exit(0)
}

if CommandLine.arguments.contains("--toggle") {
    DistributedNotificationCenter.default().postNotificationName(
        kToggleMusicNotification,
        object: nil,
        userInfo: nil,
        deliverImmediately: true
    )
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
