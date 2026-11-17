import Cocoa
import WebKit
import Carbon
import LocalAuthentication
import Darwin
import OpenDirectory

// ── C PAM Bridge ─────────────────────────────────────────────────────────────
@_silgen_name("pam_verify")
func pam_verify(_ user: UnsafePointer<CChar>, _ pass: UnsafePointer<CChar>) -> Int32

// ── Lock Screen Window ───────────────────────────────────────────────────────
class LockScreenWindow: NSWindow {
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return true }
}

// ── Application Delegate ─────────────────────────────────────────────────────
class AppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandler, WKNavigationDelegate {
    var primaryWindow: LockScreenWindow!
    var secondaryWindows: [LockScreenWindow] = []
    var webView: WKWebView!
    var mediaTimer: Timer?
    var layoutObserver: CFRunLoopObserver?
    var isUnlocked: Bool = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        setupUI()
        setupMediaMonitor()
        setupKeyboardLayoutMonitor()
        requestTouchIDIfAvailable()

        // Failsafe key monitor: Cmd + Ctrl + Opt + Escape
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags.contains([.command, .control, .option]) && event.keyCode == 53 {
                NSLog(">>> Failsafe unlock triggered")
                self?.unlock()
                return nil
            }
            return event
        }

        if CommandLine.arguments.contains("--preview") {
            NSLog(">>> Running in --preview mode: auto-dismiss in 4 seconds")
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
                self?.unlock()
            }
        }
    }

    func setupUI() {
        let screens = NSScreen.screens
        guard let mainScreen = NSScreen.main ?? screens.first else {
            exit(1)
        }

        // Configure WebKit
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        contentController.add(self, name: "lockscreen")
        config.userContentController = contentController
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")

        // 1. Primary Screen Window
        primaryWindow = LockScreenWindow(
            contentRect: mainScreen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        primaryWindow.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        primaryWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        primaryWindow.isOpaque = true
        primaryWindow.backgroundColor = NSColor.black
        primaryWindow.hasShadow = false

        webView = WKWebView(frame: primaryWindow.contentView!.bounds, configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")
        primaryWindow.contentView?.addSubview(webView)

        // Load lockscreen.html
        let fallbackPath = "/Users/new/Documents/Antigravity/waybar/lockscreen/lockscreen.html"
        let htmlURL = URL(fileURLWithPath: fallbackPath)
        webView.loadFileURL(htmlURL, allowingReadAccessTo: URL(fileURLWithPath: "/"))

        primaryWindow.makeKeyAndOrderFront(nil)

        // 2. Secondary Screens (if any)
        for screen in screens where screen != mainScreen {
            let secWindow = LockScreenWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            secWindow.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
            secWindow.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            secWindow.isOpaque = true
            secWindow.backgroundColor = NSColor.black

            let imgView = NSImageView(frame: secWindow.contentView!.bounds)
            imgView.autoresizingMask = [.width, .height]
            imgView.imageScaling = .scaleAxesIndependently
            if let wallURL = NSWorkspace.shared.desktopImageURL(for: screen) ?? NSWorkspace.shared.desktopImageURL(for: mainScreen),
               let origImg = NSImage(contentsOf: wallURL) {
                imgView.image = blurredImage(from: origImg)
            }
            secWindow.contentView?.addSubview(imgView)
            secWindow.orderFront(nil)
            secondaryWindows.append(secWindow)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        syncThemeAndWallpaper()
    }

    func syncThemeAndWallpaper() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let wallPath = NSWorkspace.shared.desktopImageURL(for: screen)?.resolvingSymlinksInPath().path ?? ""

        // Read saved theme if available
        let themeFile = "/Users/new/.config/lockscreen/current_theme.json"
        var accentHex = "fa898e"
        var islandHex = "rgba(20, 18, 25, 0.58)"
        let textWhiteHex = "#ffffff"

        if let data = try? Data(contentsOf: URL(fileURLWithPath: themeFile)),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let a = json["accentHex"] as? String { accentHex = a }
            if let i = json["islandHex"] as? String { islandHex = "#" + i }
        }

        // Avatar Data URI
        var avatarDataUri = ""
        let avatarPath = "/Users/new/.config/lockscreen/avatar_small.png"
        if let data = try? Data(contentsOf: URL(fileURLWithPath: avatarPath)) {
            avatarDataUri = "data:image/png;base64,\(data.base64EncodedString())"
        }

        // Wallpaper Data URI (use resampled cache if exists, otherwise wallPath)
        var wallDataUri = ""
        let wallJpgPath = "/Users/new/.config/lockscreen/current_wallpaper.jpg"
        if let data = try? Data(contentsOf: URL(fileURLWithPath: wallJpgPath)) {
            wallDataUri = "data:image/jpeg;base64,\(data.base64EncodedString())"
        } else if !wallPath.isEmpty, let data = try? Data(contentsOf: URL(fileURLWithPath: wallPath)) {
            wallDataUri = "data:image/jpeg;base64,\(data.base64EncodedString())"
        }

        let jsTheme = "window.setTheme('#\(accentHex)', '\(islandHex)', '\(textWhiteHex)');"
        let jsWall  = "window.setWallpaper('\(wallDataUri)');"
        let jsAvatar = "window.setAvatar('\(avatarDataUri)');"
        let jsLayout = "window.setLayout('\(getCurrentLayout())');"

        let bundleJS = "\(jsTheme) \(jsWall) \(jsAvatar) \(jsLayout)"
        webView.evaluateJavaScript(bundleJS) { _, err in
            if let err = err {
                NSLog(">>> JS error: \(err)")
            }
        }
    }

    func blurredImage(from image: NSImage) -> NSImage {
        guard let tiff = image.tiffRepresentation,
              let ciImage = CIImage(data: tiff) else { return image }
        let filter = CIFilter(name: "CIGaussianBlur")!
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(35.0, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage else { return image }
        let rep = NSCIImageRep(ciImage: output)
        let blurred = NSImage(size: image.size)
        blurred.addRepresentation(rep)
        return blurred
    }

    // ── WebKit Message Handler ───────────────────────────────────────────────
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }

        switch action {
        case "verifyPassword":
            let pass = body["password"] as? String ?? ""
            verifyPassword(pass)

        case "media":
            let cmd = body["cmd"] as? String ?? ""
            handleMedia(cmd)

        case "touchID":
            requestTouchIDIfAvailable()

        default:
            break
        }
    }

    func verifyPassword(_ pass: String) {
        guard !isUnlocked, !pass.isEmpty else {
            DispatchQueue.main.async { [weak self] in
                self?.webView.evaluateJavaScript("window.authFailed();", completionHandler: nil)
            }
            return
        }
        let username = NSUserName()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var success = false

            // 1. Primary: Native macOS OpenDirectory password validation
            do {
                let session = ODSession.default()
                let node = try ODNode(session: session, type: ODNodeType(kODNodeTypeLocalNodes))
                let record = try node.record(withRecordType: kODRecordTypeUsers, name: username, attributes: nil)
                try record.verifyPassword(pass)
                success = true
                NSLog(">>> OpenDirectory authentication succeeded!")
            } catch {
                NSLog(">>> OpenDirectory auth error: \(error)")
            }

            // 2. Fallback to PAM
            if !success {
                success = (pam_verify(username, pass) == 1)
            }

            DispatchQueue.main.async {
                if success {
                    self?.webView.evaluateJavaScript("window.authSuccess();", completionHandler: nil)
                    self?.unlock()
                } else {
                    self?.webView.evaluateJavaScript("window.authFailed();", completionHandler: nil)
                }
            }
        }
    }

    func requestTouchIDIfAvailable() {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else { return }

        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Unlock screen") { [weak self] success, _ in
            DispatchQueue.main.async {
                if success {
                    self?.webView.evaluateJavaScript("window.authSuccess();", completionHandler: nil)
                    self?.unlock()
                }
            }
        }
    }

    func unlock() {
        guard !isUnlocked else { return }
        isUnlocked = true

        mediaTimer?.invalidate()
        mediaTimer = nil

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.35
            self.primaryWindow.animator().alphaValue = 0.0
            for w in self.secondaryWindows {
                w.animator().alphaValue = 0.0
            }
        }, completionHandler: {
            self.primaryWindow.close()
            for w in self.secondaryWindows {
                w.close()
            }
            NSApp.terminate(nil)
        })
    }

    // ── Media Integration ────────────────────────────────────────────────────
    func setupMediaMonitor() {
        updateMediaState()
        mediaTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateMediaState()
        }
    }

    func updateMediaState() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/nowplaying-cli")
            process.arguments = ["get", "--json", "title", "artist", "playbackRate"]
            let pipe = Pipe()
            process.standardOutput = pipe
            try? process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let title = json["title"] as? String ?? ""
                let artist = json["artist"] as? String ?? ""
                let rate = json["playbackRate"] as? Double ?? 0.0
                let isPlaying = rate > 0.0

                DispatchQueue.main.async {
                    let escapedTitle = title.replacingOccurrences(of: "'", with: "\\'")
                    let escapedArtist = artist.replacingOccurrences(of: "'", with: "\\'")
                    let js = "window.setMedia('\(escapedTitle)', '\(escapedArtist)', \(isPlaying));"
                    self?.webView.evaluateJavaScript(js, completionHandler: nil)
                }
            }
        }
    }

    func handleMedia(_ cmd: String) {
        let arg: String
        switch cmd {
        case "prev":       arg = "previous"
        case "next":       arg = "next"
        case "play_pause": arg = "togglePlayPause"
        default: return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/nowplaying-cli")
            p.arguments = [arg]
            try? p.run()
            p.waitUntilExit()
            usleep(200000)
            self?.updateMediaState()
        }
    }

    // ── Keyboard Layout Monitor ──────────────────────────────────────────────
    func getCurrentLayout() -> String {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return "en" }
        guard let prop = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return "en" }
        let id = Unmanaged<CFString>.fromOpaque(prop).takeUnretainedValue() as String
        return id.contains("Russian") ? "ru" : "en"
    }

    func setupKeyboardLayoutMonitor() {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDistributedCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let obs = observer else { return }
                let mySelf = Unmanaged<AppDelegate>.fromOpaque(obs).takeUnretainedValue()
                let code = mySelf.getCurrentLayout()
                DispatchQueue.main.async {
                    mySelf.webView.evaluateJavaScript("window.setLayout('\(code)');", completionHandler: nil)
                }
            },
            kTISNotifySelectedKeyboardInputSourceChanged,
            nil,
            .deliverImmediately
        )
    }
}

// ── Main Entry ───────────────────────────────────────────────────────────────
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
