import AppKit
import Foundation
import ImageIO
import QuartzCore
import Vision

// MARK: - Theme Colors (~/.config/rofi/colors.json)

struct ThemePalette {
    let bg: NSColor
    let accent: NSColor
    let accentLight: NSColor

    static func load() -> ThemePalette {
        let fallbackBg = NSColor(hex: "1e1b2e") ?? .black
        let fallbackAccent = NSColor(hex: "c4b5fd") ?? .systemPurple
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

// MARK: - Vision OCR

enum OcrError: Error {
    case unreadableImage
}

func recognizeText(fromImageAt path: String, languages: [String]) throws -> String {
    let url = URL(fileURLWithPath: path)
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
        throw OcrError.unreadableImage
    }

    var recognizedLines: [String] = []
    var visionError: Error?

    let request = VNRecognizeTextRequest { req, err in
        if let err = err {
            visionError = err
            return
        }
        guard let observations = req.results as? [VNRecognizedTextObservation] else { return }
        for obs in observations {
            if let candidate = obs.topCandidates(1).first {
                let line = candidate.string.trimmingCharacters(in: .newlines)
                if !line.isEmpty {
                    recognizedLines.append(line)
                }
            }
        }
    }
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    if !languages.isEmpty {
        request.recognitionLanguages = languages
    }

    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    try handler.perform([request])
    if let err = visionError { throw err }

    return recognizedLines
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

func flattenPreview(_ text: String, maxChars: Int = 120) -> String {
    let collapsed = text
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    if collapsed.count <= maxChars { return collapsed }
    let idx = collapsed.index(collapsed.startIndex, offsetBy: maxChars)
    return String(collapsed[..<idx]) + "…"
}

// MARK: - Single-Instance PID Guard

let pidFilePath = "/tmp/ocr_osd.pid"

func terminatePreviousInstanceIfNeeded() {
    let myPid = getpid()
    if let content = try? String(contentsOfFile: pidFilePath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
       let oldPid = Int32(content),
       oldPid > 0,
       oldPid != myPid {
        kill(oldPid, SIGTERM)
        usleep(60_000)
    }
    try? "\(myPid)".write(toFile: pidFilePath, atomically: true, encoding: .utf8)
}

func cleanupPidFile() {
    let myPid = "\(getpid())"
    if let content = try? String(contentsOfFile: pidFilePath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
       content == myPid {
        try? FileManager.default.removeItem(atPath: pidFilePath)
    }
}

// MARK: - Floating OSD Toast UI

enum OsdState {
    case working
    case done(preview: String, lineCount: Int, charCount: Int)
    case empty
    case cancelled
    case error(String)
}

final class OsdContentView: NSView {
    private let effectView = NSVisualEffectView()
    private let overlayView = NSView()
    private let tintLayer = CALayer()
    private let borderLayer = CAShapeLayer()
    private let badgeView = NSView()
    private let badgeLabel = NSTextField(labelWithString: "Aa")
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let subLabel = NSTextField(labelWithString: "")
    private let stack = NSStackView()

    private let palette: ThemePalette
    private var trackingArea: NSTrackingArea?

    var onHoverChanged: ((Bool) -> Void)?
    var onDismissRequested: (() -> Void)?

    init(frame: NSRect, palette: ThemePalette) {
        self.palette = palette
        super.init(frame: frame)
        wantsLayer = true
        setupViews()
    }

    required init?(coder: NSCoder) { nil }

    private func setupViews() {
        let radius: CGFloat = 20

        effectView.frame = bounds
        effectView.autoresizingMask = [.width, .height]
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = radius
        effectView.layer?.masksToBounds = true
        addSubview(effectView)

        overlayView.frame = bounds
        overlayView.autoresizingMask = [.width, .height]
        overlayView.wantsLayer = true
        addSubview(overlayView)

        tintLayer.frame = bounds
        tintLayer.backgroundColor = palette.bg.withAlphaComponent(0.76).cgColor
        tintLayer.cornerRadius = radius
        overlayView.layer?.addSublayer(tintLayer)

        borderLayer.frame = bounds
        borderLayer.path = CGPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), cornerWidth: radius, cornerHeight: radius, transform: nil)
        borderLayer.fillColor = nil
        borderLayer.strokeColor = palette.accentLight.withAlphaComponent(0.24).cgColor
        borderLayer.lineWidth = 1.0
        overlayView.layer?.addSublayer(borderLayer)

        // Left icon badge
        badgeView.translatesAutoresizingMaskIntoConstraints = false
        badgeView.wantsLayer = true
        badgeView.layer?.cornerRadius = 13
        badgeView.layer?.backgroundColor = palette.accent.withAlphaComponent(0.18).cgColor
        badgeView.layer?.borderWidth = 1.0
        badgeView.layer?.borderColor = palette.accent.withAlphaComponent(0.36).cgColor
        addSubview(badgeView)

        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeLabel.font = NSFont.systemFont(ofSize: 17, weight: .bold)
        badgeLabel.alignment = .center
        badgeLabel.textColor = palette.accentLight
        badgeView.addSubview(badgeLabel)

        // Text stack
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        addSubview(stack)

        for label in [titleLabel, detailLabel, subLabel] {
            label.maximumNumberOfLines = 1
            label.usesSingleLineMode = true
            label.lineBreakMode = .byTruncatingTail
            label.cell?.truncatesLastVisibleLine = true
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        }

        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .white.withAlphaComponent(0.96)

        detailLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        detailLabel.textColor = palette.accentLight.withAlphaComponent(0.85)

        subLabel.font = NSFont.systemFont(ofSize: 10.5, weight: .regular)
        subLabel.textColor = .white.withAlphaComponent(0.58)

        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(detailLabel)
        stack.addArrangedSubview(subLabel)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: bounds.width),
            heightAnchor.constraint(equalToConstant: bounds.height),

            badgeView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            badgeView.centerYAnchor.constraint(equalTo: centerYAnchor),
            badgeView.widthAnchor.constraint(equalToConstant: 46),
            badgeView.heightAnchor.constraint(equalToConstant: 46),

            badgeLabel.centerXAnchor.constraint(equalTo: badgeView.centerXAnchor),
            badgeLabel.centerYAnchor.constraint(equalTo: badgeView.centerYAnchor),

            stack.leadingAnchor.constraint(equalTo: badgeView.trailingAnchor, constant: 13),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            detailLabel.widthAnchor.constraint(equalTo: stack.widthAnchor),
            subLabel.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    override func layout() {
        super.layout()
        let radius: CGFloat = 20
        tintLayer.frame = bounds
        borderLayer.frame = bounds
        borderLayer.path = CGPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
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
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
    }

    override func rightMouseUp(with event: NSEvent) {
        onDismissRequested?()
    }

    func apply(_ state: OsdState) {
        badgeView.layer?.removeAnimation(forKey: "pulse")
        switch state {
        case .working:
            badgeLabel.stringValue = "Aa"
            badgeLabel.textColor = palette.accentLight
            badgeView.layer?.backgroundColor = palette.accent.withAlphaComponent(0.20).cgColor
            titleLabel.stringValue = "Reading text…"
            detailLabel.isHidden = true
            subLabel.stringValue = "Apple Vision OCR"

            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1.0
            pulse.toValue = 0.45
            pulse.duration = 0.65
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            badgeView.layer?.add(pulse, forKey: "pulse")

        case let .done(preview, lineCount, charCount):
            badgeLabel.stringValue = "Aa"
            badgeLabel.textColor = palette.accentLight
            badgeView.layer?.backgroundColor = palette.accent.withAlphaComponent(0.22).cgColor
            titleLabel.stringValue = "Text copied"
            detailLabel.stringValue = preview
            detailLabel.isHidden = preview.isEmpty
            let lineUnit = lineCount == 1 ? "line" : "lines"
            subLabel.stringValue = "Copied to clipboard · \(lineCount) \(lineUnit) · \(charCount) chars"

        case .empty:
            badgeLabel.stringValue = "∅"
            badgeLabel.textColor = .white.withAlphaComponent(0.82)
            badgeView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
            titleLabel.stringValue = "No text found"
            detailLabel.isHidden = true
            subLabel.stringValue = "Try selecting a clearer region"

        case .cancelled:
            badgeLabel.stringValue = "✕"
            badgeLabel.textColor = .white.withAlphaComponent(0.78)
            badgeView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.10).cgColor
            titleLabel.stringValue = "OCR cancelled"
            detailLabel.isHidden = true
            subLabel.stringValue = "No area selected"

        case let .error(msg):
            badgeLabel.stringValue = "!"
            badgeLabel.textColor = NSColor.systemRed.withAlphaComponent(0.95)
            badgeView.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.18).cgColor
            titleLabel.stringValue = "OCR failed"
            detailLabel.stringValue = msg
            detailLabel.isHidden = msg.isEmpty
            subLabel.stringValue = "Could not process image"
        }
    }
}

final class OsdToastController {
    private let panel: NSPanel
    private let contentView: OsdContentView
    private var hideTimer: Timer?
    private var hovered = false
    private var pendingDuration: TimeInterval = 2.4
    private var targetFrame: NSRect = .zero

    init() {
        let width: CGFloat = 344
        let height: CGFloat = 78
        let screen = Self.targetScreen()
        let frame = Self.computeFrame(width: width, height: height, on: screen)
        self.targetFrame = frame

        panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.alphaValue = 0.0

        let palette = ThemePalette.load()
        contentView = OsdContentView(frame: NSRect(origin: .zero, size: frame.size), palette: palette)
        panel.contentView = contentView
        panel.contentMinSize = frame.size
        panel.contentMaxSize = frame.size

        contentView.onHoverChanged = { [weak self] isHovered in
            self?.hovered = isHovered
            if isHovered {
                self?.hideTimer?.invalidate()
            } else {
                self?.scheduleHide(after: min(1.0, self?.pendingDuration ?? 1.0))
            }
        }
        contentView.onDismissRequested = { [weak self] in
            self?.dismissAndExit()
        }
    }

    private static func targetScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }

    private static func computeFrame(width: CGFloat, height: CGFloat, on screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame
        let full = screen.frame
        // Sit neatly below Sketchybar (height 40 + y_offset 4) / MacBook notch
        let topLimit = min(visible.maxY, full.maxY - 56)
        let x = full.midX - width / 2.0
        let y = topLimit - height - 10
        return NSRect(x: x, y: y, width: width, height: height)
    }

    func show(_ state: OsdState, duration: TimeInterval) {
        pendingDuration = duration
        contentView.apply(state)

        let wasHidden = !panel.isVisible || panel.alphaValue < 0.05
        if wasHidden {
            var startFrame = targetFrame
            startFrame.origin.y += 10
            panel.setFrame(startFrame, display: true)
            panel.alphaValue = 0.0
            panel.orderFrontRegardless()

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1.0
                panel.animator().setFrame(targetFrame, display: true)
            }
        } else {
            panel.orderFrontRegardless()
        }

        if !hovered {
            scheduleHide(after: duration)
        }
    }

    private func scheduleHide(after seconds: TimeInterval) {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            self?.dismissAndExit()
        }
    }

    func dismissAndExit() {
        hideTimer?.invalidate()
        var endFrame = panel.frame
        endFrame.origin.y += 8

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.16
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0.0
            panel.animator().setFrame(endFrame, display: true)
        }, completionHandler: {
            cleanupPidFile()
            NSApp.terminate(nil)
        })
    }
}

// MARK: - CLI & Entrypoint

struct CliOptions {
    var imagePath: String?
    var toastOnlyState: String?
    var toastOnlyText: String = ""
    var languages: [String] = ["ru-RU", "en-US"]
    var showOsd: Bool = true
}

func parseArgs() -> CliOptions {
    var opts = CliOptions()
    let args = Array(CommandLine.arguments.dropFirst())
    var i = 0
    while i < args.count {
        switch args[i] {
        case "--help", "-h":
            print("""
            ocr_osd — macOS Apple Vision screen OCR + themed OSD toast

            Usage:
              ocr_osd                         Interactive area capture -> OCR -> clipboard + OSD
              ocr_osd --image <path>          Run OCR on an image file (prints text to stdout)
              ocr_osd --lang ru-RU,en-US      Comma-separated recognition languages
              ocr_osd --no-osd                Skip showing the OSD toast (with --image)
              ocr_osd --toast-only <state> [text]
                                              Preview OSD (working|done|empty|cancelled)
            """)
            exit(0)
        case "--image":
            i += 1
            if i < args.count { opts.imagePath = args[i] }
        case "--lang":
            i += 1
            if i < args.count {
                opts.languages = args[i]
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }
        case "--no-osd":
            opts.showOsd = false
        case "--toast-only":
            i += 1
            if i < args.count { opts.toastOnlyState = args[i] }
            if i + 1 < args.count {
                i += 1
                opts.toastOnlyText = args[i]
            }
        default:
            break
        }
        i += 1
    }
    return opts
}

func copyToClipboard(_ text: String) {
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(text, forType: .string)
}

func runInteractiveCapture(to path: String) -> Bool {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    proc.arguments = ["-i", "-x", path]
    do {
        try proc.run()
        proc.waitUntilExit()
    } catch {
        return false
    }
    return proc.terminationStatus == 0 && FileManager.default.fileExists(atPath: path)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let opts: CliOptions
    private var toast: OsdToastController?

    init(opts: CliOptions) {
        self.opts = opts
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let stateName = opts.toastOnlyState {
            let osd = OsdToastController()
            self.toast = osd
            switch stateName {
            case "working":
                osd.show(.working, duration: 2.0)
            case "empty":
                osd.show(.empty, duration: 1.8)
            case "cancelled":
                osd.show(.cancelled, duration: 1.2)
            default:
                let sample = opts.toastOnlyText.isEmpty ? "Hello from Apple Vision OCR!" : opts.toastOnlyText
                let lines = max(1, sample.components(separatedBy: .newlines).count)
                osd.show(.done(preview: flattenPreview(sample), lineCount: lines, charCount: sample.count), duration: 2.6)
            }
            return
        }

        if let imgPath = opts.imagePath {
            processImage(at: imgPath, deleteAfter: false, printOutput: true)
            return
        }

        // Interactive screen capture on background thread so AppKit remains responsive
        let tmpPath = "/tmp/ocr_osd_\(UUID().uuidString).png"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let captured = runInteractiveCapture(to: tmpPath)
            DispatchQueue.main.async {
                if !captured {
                    try? FileManager.default.removeItem(atPath: tmpPath)
                    let osd = OsdToastController()
                    self.toast = osd
                    osd.show(.cancelled, duration: 1.1)
                    return
                }

                let osd = OsdToastController()
                self.toast = osd
                osd.show(.working, duration: 15.0)
                self.processImage(at: tmpPath, deleteAfter: true, printOutput: false)
            }
        }
    }

    private func processImage(at path: String, deleteAfter: Bool, printOutput: Bool) {
        let langs = opts.languages
        let showOsd = opts.showOsd

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            defer {
                if deleteAfter {
                    try? FileManager.default.removeItem(atPath: path)
                }
            }

            do {
                let text = try recognizeText(fromImageAt: path, languages: langs)
                DispatchQueue.main.async {
                    if text.isEmpty {
                        if showOsd {
                            let osd = self?.toast ?? OsdToastController()
                            self?.toast = osd
                            osd.show(.empty, duration: 1.8)
                        } else {
                            cleanupPidFile()
                            NSApp.terminate(nil)
                        }
                        return
                    }

                    copyToClipboard(text)
                    if printOutput {
                        print(text)
                    }

                    if showOsd {
                        let osd = self?.toast ?? OsdToastController()
                        self?.toast = osd
                        let lines = text.components(separatedBy: .newlines).count
                        osd.show(
                            .done(preview: flattenPreview(text), lineCount: lines, charCount: text.count),
                            duration: 2.6
                        )
                    } else {
                        cleanupPidFile()
                        NSApp.terminate(nil)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    if showOsd {
                        let osd = self?.toast ?? OsdToastController()
                        self?.toast = osd
                        osd.show(.error(error.localizedDescription), duration: 2.4)
                    } else {
                        fputs("OCR error: \(error)\n", stderr)
                        cleanupPidFile()
                        exit(1)
                    }
                }
            }
        }
    }
}

let opts = parseArgs()
if opts.imagePath == nil && opts.toastOnlyState == nil {
    terminatePreviousInstanceIfNeeded()
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate(opts: opts)
app.delegate = delegate
app.run()
