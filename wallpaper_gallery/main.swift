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
            "\(home)/wallapers",
            "\(home)/wallpapers"
        ]

        var seenPaths = Set<String>()
        var seenNames = Set<String>()
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
                    let rawName = fileURL.deletingPathExtension().lastPathComponent
                    let normalizedName = rawName.lowercased()

                    // Ensure deduplication by both resolved path and normalized filename
                    if !seenPaths.contains(standardPath) && !seenNames.contains(normalizedName) {
                        seenPaths.insert(standardPath)
                        seenNames.insert(normalizedName)

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
        return "mashiro_kanon_archlinux"
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

// ── Desktop State Detector ───────────────────────────────────────────────────
func isDesktopEmpty() -> Bool {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
        return true
    }

    let ignoredOwners: Set<String> = [
        "wallpaper_gallery",
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
        let w = bounds["Width"] as? Double ?? 0
        let h = bounds["Height"] as? Double ?? 0

        // If any standard application window is on-screen
        if layer == 0 && w > 120 && h > 120 && alpha > 0.05 {
            if !ignoredOwners.contains(owner) {
                return false
            }
        }
    }
    return true
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
        // Positioned on desktop layer below all normal application windows
        level = NSWindow.Level(NSWindow.Level.normal.rawValue - 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        contentView = pillView
        updatePill(title: WallpaperScanner.currentWallpaperName())
    }

    func updatePill(title: String) {
        pillView.title = title
        reposition()
    }

    func setDesktopVisibility(empty: Bool) {
        let targetAlpha: CGFloat = empty ? 1.0 : 0.0
        if abs(alphaValue - targetAlpha) > 0.05 {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                self.animator().alphaValue = targetAlpha
            }
            ignoresMouseEvents = !empty
        }
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
class GalleryWindow: NSPanel, WKScriptMessageHandler, WKNavigationDelegate {
    var webView: WKWebView!
    var onWallpaperSelected: ((String, String) -> Void)?
    var onClose: (() -> Void)?
    var isHTMLLoaded = false

    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return true }

    init() {
        guard let screen = NSScreen.main else {
            super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
            return
        }

        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
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

        // Allow loading local file:// image resources
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")

        webView = WKWebView(frame: screen.frame, configuration: config)
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        webView.autoresizingMask = [.width, .height]
        contentView = webView

        loadGalleryHTML()
    }

    func loadGalleryHTML() {
        let execURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let execDir = execURL.deletingLastPathComponent().path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let possiblePaths = [
            "\(execDir)/gallery.html",
            "\(execDir)/../gallery.html",
            "\(home)/.local/bin/gallery.html",
            "\(home)/bin/gallery.html",
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
            let rootURL = URL(fileURLWithPath: "/")
            webView.loadFileURL(url, allowingReadAccessTo: rootURL)
            NSLog(">>> Loaded gallery from URL: \(url.path) with root access")
        } else {
            NSLog(">>> ERROR: gallery.html not found in any expected location!")
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isHTMLLoaded = true
        if isVisible && alphaValue > 0.5 {
            injectWallpapers()
        }
    }

    func injectWallpapers() {
        let items = WallpaperScanner.scan()
        let currentPath = WallpaperScanner.currentWallpaperPath()
        if let jsonData = try? JSONEncoder().encode(items),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            let js = "if (window.loadWallpapers) { window.loadWallpapers(\(jsonString), '\(currentPath)'); }"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    func open() {
        NSLog(">>> GalleryWindow.open() called")
        guard let screen = NSScreen.main else { return }
        setFrame(screen.frame, display: true)

        NSApp.setActivationPolicy(.regular)
        alphaValue = 1.0
        orderFrontRegardless()
        makeKeyAndOrderFront(nil)
        makeFirstResponder(webView)
        NSApp.activate(ignoringOtherApps: true)

        injectWallpapers()
        webView.evaluateJavaScript("window.focus();", completionHandler: nil)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123, 126, 4: // Left / Up arrow, 'h'
            webView.evaluateJavaScript("window.prev();", completionHandler: nil)
        case 124, 125, 37: // Right / Down arrow, 'l'
            webView.evaluateJavaScript("window.next();", completionHandler: nil)
        case 36, 49: // Return or Space
            webView.evaluateJavaScript("window.selectCurrent();", completionHandler: nil)
        case 53: // Escape
            close()
        default:
            super.keyDown(with: event)
        }
    }

    override func close() {
        NSLog(">>> GalleryWindow.close() called!")
        alphaValue = 0.0
        orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
        onClose?()
    }

    // WKScriptMessageHandler
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }
        NSLog(">>> WebKit bridge message: \(action)")

        if action == "ready" {
            isHTMLLoaded = true
            if isVisible && alphaValue > 0.5 {
                injectWallpapers()
            }
        } else if action == "apply" || action == "select" {
            let path = body["path"] as? String ?? ""
            let name = body["name"] as? String ?? ""
            onWallpaperSelected?(path, name)
            // Keep gallery open so user sees desktop update in real time!
        } else if action == "close" {
            let reason = body["reason"] as? String ?? "unknown"
            NSLog(">>> GalleryWindow.close() requested from WebKit, reason: \(reason)")
            close()
        }
    }
}

// ── Application Delegate ─────────────────────────────────────────────────────
class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate!

    var pillWindow: BottomPillWindow!
    var galleryWindow: GalleryWindow!
    var stateTimer: Timer?
    var sig1Source: DispatchSourceSignal?
    var sig2Source: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        NSApp.setActivationPolicy(.accessory) // No dock icon when running in background

        pillWindow = BottomPillWindow()
        galleryWindow = GalleryWindow()

        pillWindow.pillView.onClick = { [weak self] in
            self?.toggleGallery()
        }

        galleryWindow.onWallpaperSelected = { [weak self] path, name in
            self?.applyWallpaper(path: path, name: name)
        }

        pillWindow.makeKeyAndOrderFront(nil)

        // Setup signal-based IPC & write PID file
        setupSignals()

        // Setup local key monitor for gallery navigation
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self,
                  let gallery = self.galleryWindow,
                  gallery.isVisible && gallery.alphaValue > 0.4 else {
                return event
            }

            NSLog(">>> Local key down: keyCode=\(event.keyCode)")
            switch event.keyCode {
            case 123, 126, 4: // Left / Up arrow, 'h'
                gallery.webView.evaluateJavaScript("window.prev();", completionHandler: nil)
                return nil
            case 124, 125, 37: // Right / Down arrow, 'l'
                gallery.webView.evaluateJavaScript("window.next();", completionHandler: nil)
                return nil
            case 36, 49: // Return or Space
                gallery.webView.evaluateJavaScript("window.selectCurrent();", completionHandler: nil)
                return nil
            case 53: // Escape
                gallery.close()
                return nil
            default:
                return event
            }
        }

        // Setup global key monitor as fallback
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self,
                  let gallery = self.galleryWindow,
                  gallery.isVisible && gallery.alphaValue > 0.4 else {
                return
            }

            NSLog(">>> Global key down: keyCode=\(event.keyCode)")
            switch event.keyCode {
            case 123, 126: // Left / Up arrow
                gallery.webView.evaluateJavaScript("window.prev();", completionHandler: nil)
            case 124, 125: // Right / Down arrow
                gallery.webView.evaluateJavaScript("window.next();", completionHandler: nil)
            case 36, 49: // Return or Space
                gallery.webView.evaluateJavaScript("window.selectCurrent();", completionHandler: nil)
            case 53: // Escape
                gallery.close()
            default:
                break
            }
        }

        // Listen for screen resize/resolution changes
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.pillWindow.reposition()
        }

        // Listen for space change and app activation events to hide/show pill
        let wsCenter = NSWorkspace.shared.notificationCenter
        let notifications: [NSNotification.Name] = [
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didDeactivateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification
        ]
        for name in notifications {
            wsCenter.addObserver(self, selector: #selector(checkDesktopState), name: name, object: nil)
        }

        // Periodic timer to guarantee state sync
        stateTimer = Timer.scheduledTimer(
            timeInterval: 0.5,
            target: self,
            selector: #selector(checkDesktopState),
            userInfo: nil,
            repeats: true
        )

        // Check desktop state immediately
        checkDesktopState()

        // Listen for IPC Notifications (e.g. from hotkeys / skhd)
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleToggleNotification),
            name: kToggleNotification,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleOpenNotification),
            name: kOpenNotification,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    func setupSignals() {
        signal(SIGUSR1, SIG_IGN)
        signal(SIGUSR2, SIG_IGN)

        let s1 = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        s1.setEventHandler { [weak self] in
            NSLog(">>> SIGUSR1 signal caught!")
            self?.toggleGallery()
        }
        s1.resume()
        sig1Source = s1

        let s2 = DispatchSource.makeSignalSource(signal: SIGUSR2, queue: .main)
        s2.setEventHandler { [weak self] in
            NSLog(">>> SIGUSR2 signal caught!")
            self?.openGallery()
        }
        s2.resume()
        sig2Source = s2

        // Write PID file
        let pid = ProcessInfo.processInfo.processIdentifier
        let pidPath = "/tmp/wallpaper_gallery.pid"
        try? "\(pid)".write(toFile: pidPath, atomically: true, encoding: .utf8)
        NSLog(">>> Daemon started with PID: \(pid)")
    }

    func openGallery() {
        NSLog(">>> openGallery() called. isVisible: \(galleryWindow.isVisible), alpha: \(galleryWindow.alphaValue)")
        galleryWindow.open()
    }

    @objc func checkDesktopState() {
        let empty = isDesktopEmpty()
        pillWindow.setDesktopVisibility(empty: empty)
    }

    @objc func handleToggleNotification() {
        NSLog(">>> handleToggleNotification() called")
        DispatchQueue.main.async {
            self.toggleGallery()
        }
    }

    @objc func handleOpenNotification() {
        NSLog(">>> handleOpenNotification() called")
        DispatchQueue.main.async {
            self.openGallery()
        }
    }

    func toggleGallery() {
        NSLog(">>> toggleGallery() called. isVisible: \(galleryWindow.isVisible), alpha: \(galleryWindow.alphaValue)")
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

        // Background AppleScript for all desktops and spaces
        DispatchQueue.global(qos: .utility).async {
            let escapedPath = path.replacingOccurrences(of: "\"", with: "\\\"")
            let script = "tell application \"System Events\" to tell every desktop to set picture to \"\(escapedPath)\""
            if let appleScript = NSAppleScript(source: script) {
                var err: NSDictionary?
                appleScript.executeAndReturnError(&err)
            }
        }

        pillWindow.updatePill(title: name)
    }
}

// ── Main Entry Point ─────────────────────────────────────────────────────────
let pidPath = "/tmp/wallpaper_gallery.pid"

if CommandLine.arguments.contains("--toggle") {
    if let pidStr = try? String(contentsOfFile: pidPath, encoding: .utf8),
       let pid = Int32(pidStr.trimmingCharacters(in: .whitespacesAndNewlines)) {
        kill(pid, SIGUSR1)
    }
    DistributedNotificationCenter.default().postNotificationName(
        kToggleNotification,
        object: nil,
        userInfo: nil,
        deliverImmediately: true
    )
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    exit(0)
}

if CommandLine.arguments.contains("--open") {
    if let pidStr = try? String(contentsOfFile: pidPath, encoding: .utf8),
       let pid = Int32(pidStr.trimmingCharacters(in: .whitespacesAndNewlines)) {
        kill(pid, SIGUSR2)
    }
    DistributedNotificationCenter.default().postNotificationName(
        kOpenNotification,
        object: nil,
        userInfo: nil,
        deliverImmediately: true
    )
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
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
