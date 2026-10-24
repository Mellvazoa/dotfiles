import AppKit
import WebKit

// ── Models ───────────────────────────────────────────────────────────────────
struct WallpaperItem: Codable {
    let path: String
    let name: String
    let category: String
}

// ── Notification Name for IPC ────────────────────────────────────────────────
let kToggleNotification = Notification.Name("com.mellvazoa.wallpaper.toggle")
let kOpenNotification   = Notification.Name("com.mellvazoa.wallpaper.open")

// ── Scanner ──────────────────────────────────────────────────────────────────
class WallpaperScanner {
    static let validExtensions = Set(["jpg", "jpeg", "png", "webp", "heic", "tiff"])

    static func scan() -> [WallpaperItem] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidateDirs = [
            "\(home)/wallpapers",
            "\(home)/wallapers",
            "\(home)/Pictures/Wallpapers",
            "\(home)/Documents/Antigravity/waybar/wallpapers"
        ]

        var seenPaths = Set<String>()
        var items: [WallpaperItem] = []

        for dir in candidateDirs {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else {
                continue
            }

            let url = URL(fileURLWithPath: dir)
            let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )

            while let fileURL = enumerator?.nextObject() as? URL {
                let ext = fileURL.pathExtension.lowercased()
                if validExtensions.contains(ext) {
                    let standardPath = fileURL.resolvingSymlinksInPath().path
                    if !seenPaths.contains(standardPath) {
                        seenPaths.insert(standardPath)
                        let rawName = fileURL.deletingPathExtension().lastPathComponent
                        let parentFolder = fileURL.deletingLastPathComponent().lastPathComponent
                        let category = (parentFolder.lowercased() == "wallpapers" || parentFolder.lowercased() == "wallapers") ? "all" : parentFolder
                        items.append(WallpaperItem(path: standardPath, name: rawName, category: category))
                    }
                }
            }
        }

        return items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func currentWallpaperPath() -> String {
        if let screen = NSScreen.main, let url = NSWorkspace.shared.desktopImageURL(for: screen) {
            return url.resolvingSymlinksInPath().path
        }
        return ""
    }

    static func currentWallpaperName() -> String {
        let path = currentWallpaperPath()
        if !path.isEmpty {
            return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        }
        return "arona_blue_archive_hq"
    }
}

// ── Bottom Pill View (Matching Sketchybar Aesthetic) ─────────────────────────
class BottomPillView: NSView {
    var title: String = "" {
        didSet {
            needsDisplay = true
        }
    }
    var isHovered: Bool = false {
        didSet {
            needsDisplay = true
        }
    }

    var onClick: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func mouseUp(with event: NSEvent) {
        onClick?()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let pillRect = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: pillRect, xRadius: 10, yRadius: 10)

        // Island Background (#131630 @ 88% opacity, slightly brighter on hover)
        let bgColor = isHovered 
            ? NSColor(red: 25/255.0, green: 28/255.0, blue: 58/255.0, alpha: 0.94)
            : NSColor(red: 19/255.0, green: 22/255.0, blue: 48/255.0, alpha: 0.88)
        bgColor.setFill()
        path.fill()

        // Border: Lavender glow (#c8b4fa)
        let borderColor = isHovered
            ? NSColor(red: 200/255.0, green: 180/255.0, blue: 250/255.0, alpha: 0.85)
            : NSColor(red: 200/255.0, green: 180/255.0, blue: 250/255.0, alpha: 0.32)
        borderColor.setStroke()
        path.lineWidth = isHovered ? 1.5 : 1.0
        path.stroke()

        // Lavender Font
        let font = NSFont(name: "JetBrainsMono Nerd Font", size: 12.0)
            ?? NSFont(name: "JetBrainsMono-Bold", size: 12.0)
            ?? NSFont.systemFont(ofSize: 12.0, weight: .semibold)

        let textColor = isHovered
            ? NSColor(red: 240/255.0, green: 235/255.0, blue: 255/255.0, alpha: 1.0)
            : NSColor(red: 200/255.0, green: 180/255.0, blue: 250/255.0, alpha: 1.0)

        let iconStr = "󰸉 "
        let displayText = iconStr + (title.isEmpty ? "Wallpapers" : title)

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]

        let attrStr = NSAttributedString(string: displayText, attributes: attrs)
        let textSize = attrStr.size()
        let textRect = NSRect(
            x: (bounds.width - textSize.width) / 2.0,
            y: (bounds.height - textSize.height) / 2.0 - 0.5,
            width: textSize.width,
            height: textSize.height
        )

        attrStr.draw(in: textRect)
    }

    func computeOptimalWidth() -> CGFloat {
        let font = NSFont(name: "JetBrainsMono Nerd Font", size: 12.0)
            ?? NSFont.systemFont(ofSize: 12.0, weight: .semibold)
        let displayText = "󰸉 " + (title.isEmpty ? "Wallpapers" : title)
        let size = (displayText as NSString).size(withAttributes: [.font: font])
        return max(140.0, size.width + 36.0)
    }
}

// ── Bottom Pill Panel Window ─────────────────────────────────────────────────
class BottomPillWindow: NSPanel {
    let pillView = BottomPillView()

    init() {
        let initialRect = NSRect(x: 0, y: 0, width: 200, height: 28)
        super.init(
            contentRect: initialRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        contentView = pillView
        updatePill(title: WallpaperScanner.currentWallpaperName())
    }

    func updatePill(title: String) {
        pillView.title = title
        reposition()
    }

    func reposition() {
        guard let screen = NSScreen.main else { return }
        let width = pillView.computeOptimalWidth()
        let height: CGFloat = 28.0
        let x = screen.frame.midX - (width / 2.0)
        let y = screen.frame.minY + 12.0 // 12px above bottom edge of screen

        setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        pillView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        pillView.needsDisplay = true
    }
}

// ── Coverflow Modal Gallery Window ───────────────────────────────────────────
class GalleryWindow: NSPanel, WKScriptMessageHandler {
    var webView: WKWebView!
    var onWallpaperSelected: ((String, String) -> Void)?
    var onClose: (() -> Void)?

    init() {
        guard let screen = NSScreen.main else {
            super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
            return
        }

        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .modalPanel
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        controller.add(self, name: "bridge")
        config.userContentController = controller

        webView = WKWebView(frame: screen.frame, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.autoresizingMask = [.width, .height]
        contentView = webView

        loadGalleryHTML()
    }

    func loadGalleryHTML() {
        let appDir = Bundle.main.bundlePath
        let possiblePaths = [
            "\(appDir)/gallery.html",
            "\(CommandLine.arguments[0])/../gallery.html",
            "/Users/new/Documents/Antigravity/waybar/wallpaper_gallery/gallery.html"
        ]

        var htmlURL: URL?
        for p in possiblePaths {
            let u = URL(fileURLWithPath: (p as NSString).standardizingPath)
            if FileManager.default.fileExists(atPath: u.path) {
                htmlURL = u
                break
            }
        }

        if let url = htmlURL {
            let homeURL = FileManager.default.homeDirectoryForCurrentUser
            webView.loadFileURL(url, allowingReadAccessTo: homeURL)
        }
    }

    func open() {
        guard let screen = NSScreen.main else { return }
        setFrame(screen.frame, display: true)

        let items = WallpaperScanner.scan()
        let currentPath = WallpaperScanner.currentWallpaperPath()

        if let jsonData = try? JSONEncoder().encode(items),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            let js = "window.loadWallpapers(\(jsonString), '\(currentPath)');"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        alphaValue = 0.0
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1.0
        }
    }

    override func close() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0.0
        }) {
            self.orderOut(nil)
            self.onClose?()
        }
    }

    // WKScriptMessageHandler
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }

        if action == "select" {
            let path = body["path"] as? String ?? ""
            let name = body["name"] as? String ?? ""
            close()
            onWallpaperSelected?(path, name)
        } else if action == "close" {
            close()
        }
    }
}

// ── Application Delegate ─────────────────────────────────────────────────────
class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate!

    var pillWindow: BottomPillWindow!
    var galleryWindow: GalleryWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        NSApp.setActivationPolicy(.accessory) // No dock icon, runs seamlessly in background

        pillWindow = BottomPillWindow()
        galleryWindow = GalleryWindow()

        pillWindow.pillView.onClick = { [weak self] in
            self?.toggleGallery()
        }

        galleryWindow.onWallpaperSelected = { [weak self] path, name in
            self?.applyWallpaper(path: path, name: name)
        }

        pillWindow.makeKeyAndOrderFront(nil)

        // Listen for screen resize/resolution changes
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.pillWindow.reposition()
        }

        // Listen for IPC Notifications (e.g. from hotkeys / skhd)
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleToggleNotification),
            name: kToggleNotification,
            object: nil
        )

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleOpenNotification),
            name: kOpenNotification,
            object: nil
        )
    }

    @objc func handleToggleNotification() {
        DispatchQueue.main.async {
            self.toggleGallery()
        }
    }

    @objc func handleOpenNotification() {
        DispatchQueue.main.async {
            if !self.galleryWindow.isVisible {
                self.galleryWindow.open()
            }
        }
    }

    func toggleGallery() {
        if galleryWindow.isVisible && galleryWindow.alphaValue > 0.5 {
            galleryWindow.close()
        } else {
            galleryWindow.open()
        }
    }

    func applyWallpaper(path: String, name: String) {
        let fileURL = URL(fileURLWithPath: path)
        if let screen = NSScreen.main {
            do {
                try NSWorkspace.shared.setDesktopImageURL(fileURL, for: screen, options: [:])
            } catch {
                print("Failed to set desktop image: \(error)")
            }
        }

        // Fallback for all spaces / monitors via AppleScript
        let escapedPath = path.replacingOccurrences(of: "\"", with: "\\\"")
        let script = "tell application \"System Events\" to tell every desktop to set picture to \"\(escapedPath)\""
        if let appleScript = NSAppleScript(source: script) {
            var err: NSDictionary?
            appleScript.executeAndReturnError(&err)
        }

        pillWindow.updatePill(title: name)
    }
}

// ── Main Entry Point ─────────────────────────────────────────────────────────
if CommandLine.arguments.contains("--toggle") {
    DistributedNotificationCenter.default().postNotificationName(
        kToggleNotification,
        object: nil,
        userInfo: nil,
        deliverImmediately: true
    )
    exit(0)
}

if CommandLine.arguments.contains("--open") {
    DistributedNotificationCenter.default().postNotificationName(
        kOpenNotification,
        object: nil,
        userInfo: nil,
        deliverImmediately: true
    )
    exit(0)
}

if CommandLine.arguments.contains("--help") {
    print("""
    Wallpaper Gallery & Bottom Pill Widget for macOS
    Usage:
      wallpaper_gallery          Run the background daemon (pill + gallery)
      wallpaper_gallery --toggle Toggle the Coverflow gallery
      wallpaper_gallery --open   Open the Coverflow gallery
      wallpaper_gallery --help   Show this help message
    """)
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
