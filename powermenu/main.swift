import AppKit
import Foundation
import QuartzCore

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

// MARK: - Power Actions

enum PowerActionId: String, CaseIterable {
    case lock
    case sleep
    case restart
    case logout
    case shutdown
}

struct PowerActionItem {
    let id: PowerActionId
    let title: String
    let symbol: String
    let keyHint: String
    let dangerous: Bool
}

let powerActions: [PowerActionItem] = [
    PowerActionItem(id: .lock,     title: "Lock",      symbol: "lock.fill",                         keyHint: "L", dangerous: false),
    PowerActionItem(id: .sleep,    title: "Sleep",     symbol: "moon.fill",                         keyHint: "S", dangerous: false),
    PowerActionItem(id: .restart,  title: "Restart",   symbol: "arrow.clockwise",                   keyHint: "R", dangerous: true),
    PowerActionItem(id: .logout,   title: "Log Out",   symbol: "rectangle.portrait.and.arrow.right", keyHint: "U", dangerous: true),
    PowerActionItem(id: .shutdown, title: "Shut Down", symbol: "power",                             keyHint: "P", dangerous: true),
]

func executePowerAction(_ id: PowerActionId) {
    let home = NSHomeDirectory()
    let repo = "/Users/new/Documents/Antigravity/waybar"

    func spawn(_ exe: String, _ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }

    switch id {
    case .lock:
        let candidates = [
            "\(home)/.local/bin/lockscreen",
            "\(repo)/lockscreen/bin/lockscreen"
        ]
        if let bin = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            spawn(bin, [])
        } else {
            spawn("/usr/bin/pmset", ["displaysleepnow"])
        }
    case .sleep:
        spawn("/usr/bin/pmset", ["sleepnow"])
    case .restart:
        spawn("/usr/bin/osascript", ["-e", "tell application \"System Events\" to restart"])
    case .logout:
        spawn("/usr/bin/osascript", ["-e", "tell application \"System Events\" to log out"])
    case .shutdown:
        spawn("/usr/bin/osascript", ["-e", "tell application \"System Events\" to shut down"])
    }
}

// MARK: - Single-Instance Toggle Guard

let pidFilePath = "/tmp/powermenu.pid"

func toggleExistingInstanceIfRunning() -> Bool {
    let myPid = getpid()
    guard let raw = try? String(contentsOfFile: pidFilePath, encoding: .utf8) else {
        return false
    }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let oldPid = Int32(trimmed), oldPid > 0, oldPid != myPid else {
        return false
    }
    if kill(oldPid, 0) == 0 {
        kill(oldPid, SIGTERM)
        return true
    }
    return false
}

func writePidFile() {
    try? "\(getpid())".write(toFile: pidFilePath, atomically: true, encoding: .utf8)
}

func cleanupPidFile() {
    let myPid = "\(getpid())"
    if let raw = try? String(contentsOfFile: pidFilePath, encoding: .utf8),
       raw.trimmingCharacters(in: .whitespacesAndNewlines) == myPid {
        try? FileManager.default.removeItem(atPath: pidFilePath)
    }
}

// MARK: - Tile Button View

final class PowerTileView: NSView {
    let item: PowerActionItem
    private let palette: ThemePalette
    private let bgLayer = CALayer()
    private let borderLayer = CAShapeLayer()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let keyBadge = NSTextField(labelWithString: "")
    private let keyBadgeWrap = NSView()
    private var trackingArea: NSTrackingArea?

    var onHover: (() -> Void)?
    var onClick: (() -> Void)?

    init(item: PowerActionItem, palette: ThemePalette) {
        self.item = item
        self.palette = palette
        super.init(frame: NSRect(x: 0, y: 0, width: 96, height: 116))
        wantsLayer = true
        setupViews()
        render(selected: false, confirming: false)
    }

    required init?(coder: NSCoder) { nil }

    private func setupViews() {
        let radius: CGFloat = 16

        bgLayer.frame = bounds
        bgLayer.cornerRadius = radius
        layer?.addSublayer(bgLayer)

        borderLayer.frame = bounds
        borderLayer.cornerRadius = radius
        borderLayer.fillColor = nil
        borderLayer.lineWidth = 1.5
        layer?.addSublayer(borderLayer)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        let cfg = NSImage.SymbolConfiguration(pointSize: 23, weight: .medium)
        iconView.image = NSImage(systemSymbolName: item.symbol, accessibilityDescription: item.title)?
            .withSymbolConfiguration(cfg)
        iconView.imageScaling = .scaleNone
        addSubview(iconView)

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.stringValue = item.title
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        titleLabel.alignment = .center
        titleLabel.maximumNumberOfLines = 1
        titleLabel.usesSingleLineMode = true
        addSubview(titleLabel)

        keyBadgeWrap.translatesAutoresizingMaskIntoConstraints = false
        keyBadgeWrap.wantsLayer = true
        keyBadgeWrap.layer?.cornerRadius = 6
        addSubview(keyBadgeWrap)

        keyBadge.translatesAutoresizingMaskIntoConstraints = false
        keyBadge.stringValue = item.keyHint
        keyBadge.font = NSFont.monospacedSystemFont(ofSize: 9.5, weight: .semibold)
        keyBadge.alignment = .center
        keyBadgeWrap.addSubview(keyBadge)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 96),
            heightAnchor.constraint(equalToConstant: 116),

            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            iconView.widthAnchor.constraint(equalToConstant: 34),
            iconView.heightAnchor.constraint(equalToConstant: 34),

            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),

            keyBadgeWrap.centerXAnchor.constraint(equalTo: centerXAnchor),
            keyBadgeWrap.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -11),
            keyBadgeWrap.heightAnchor.constraint(equalToConstant: 18),
            keyBadgeWrap.widthAnchor.constraint(greaterThanOrEqualToConstant: 22),

            keyBadge.leadingAnchor.constraint(equalTo: keyBadgeWrap.leadingAnchor, constant: 6),
            keyBadge.trailingAnchor.constraint(equalTo: keyBadgeWrap.trailingAnchor, constant: -6),
            keyBadge.centerYAnchor.constraint(equalTo: keyBadgeWrap.centerYAnchor)
        ])
    }

    override func layout() {
        super.layout()
        bgLayer.frame = bounds
        borderLayer.frame = bounds
        borderLayer.path = CGPath(
            roundedRect: bounds.insetBy(dx: 0.75, dy: 0.75),
            cornerWidth: 16,
            cornerHeight: 16,
            transform: nil
        )
    }

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
        onHover?()
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    func render(selected: Bool, confirming: Bool) {
        let dangerColor = NSColor(hex: "fc5d7c") ?? .systemRed
        if confirming {
            bgLayer.backgroundColor = dangerColor.withAlphaComponent(0.24).cgColor
            borderLayer.strokeColor = dangerColor.withAlphaComponent(0.92).cgColor
            iconView.contentTintColor = dangerColor
            titleLabel.stringValue = "Confirm?"
            titleLabel.textColor = .white
            keyBadge.stringValue = "Enter"
            keyBadge.textColor = dangerColor
            keyBadgeWrap.layer?.backgroundColor = dangerColor.withAlphaComponent(0.18).cgColor
        } else if selected {
            bgLayer.backgroundColor = palette.accent.withAlphaComponent(0.22).cgColor
            borderLayer.strokeColor = palette.accent.withAlphaComponent(0.88).cgColor
            iconView.contentTintColor = palette.accentLight
            titleLabel.stringValue = item.title
            titleLabel.textColor = .white
            keyBadge.stringValue = item.keyHint
            keyBadge.textColor = palette.accentLight
            keyBadgeWrap.layer?.backgroundColor = palette.accent.withAlphaComponent(0.20).cgColor
        } else {
            bgLayer.backgroundColor = NSColor.white.withAlphaComponent(0.05).cgColor
            borderLayer.strokeColor = palette.accentLight.withAlphaComponent(0.14).cgColor
            iconView.contentTintColor = palette.accentLight.withAlphaComponent(0.75)
            titleLabel.stringValue = item.title
            titleLabel.textColor = .white.withAlphaComponent(0.78)
            keyBadge.stringValue = item.keyHint
            keyBadge.textColor = .white.withAlphaComponent(0.55)
            keyBadgeWrap.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        }
    }
}

// MARK: - Window & Controller

final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class PowerMenuController: NSView {
    private let palette = ThemePalette.load()
    private let cardContainer = NSView()
    private let effectView = NSVisualEffectView()
    private let overlayView = NSView()
    private let tintLayer = CALayer()
    private let borderLayer = CAShapeLayer()
    private let hintLabel = NSTextField(labelWithString: "")
    private var tiles: [PowerTileView] = []

    private var selectedIndex: Int = 0
    private var confirmingId: PowerActionId?
    private var isClosing = false
    var onDismiss: ((PowerActionId?) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.28).cgColor
        setupCard()
        refreshSelection()
    }

    required init?(coder: NSCoder) { nil }

    private func setupCard() {
        let cardW: CGFloat = 556
        let cardH: CGFloat = 172
        let radius: CGFloat = 24

        cardContainer.translatesAutoresizingMaskIntoConstraints = false
        cardContainer.wantsLayer = true
        cardContainer.layer?.cornerRadius = radius
        cardContainer.shadow = {
            let s = NSShadow()
            s.shadowBlurRadius = 28
            s.shadowOffset = NSSize(width: 0, height: -8)
            s.shadowColor = NSColor.black.withAlphaComponent(0.45)
            return s
        }()
        addSubview(cardContainer)

        effectView.translatesAutoresizingMaskIntoConstraints = false
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = radius
        effectView.layer?.masksToBounds = true
        cardContainer.addSubview(effectView)

        overlayView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.wantsLayer = true
        cardContainer.addSubview(overlayView)

        tintLayer.backgroundColor = palette.bg.withAlphaComponent(0.78).cgColor
        tintLayer.cornerRadius = radius
        overlayView.layer?.addSublayer(tintLayer)

        borderLayer.fillColor = nil
        borderLayer.strokeColor = palette.accentLight.withAlphaComponent(0.26).cgColor
        borderLayer.lineWidth = 1.0
        overlayView.layer?.addSublayer(borderLayer)

        let row = NSStackView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        cardContainer.addSubview(row)

        for (idx, item) in powerActions.enumerated() {
            let tile = PowerTileView(item: item, palette: palette)
            tile.onHover = { [weak self] in
                guard let self = self else { return }
                if self.selectedIndex != idx {
                    self.selectedIndex = idx
                    if self.confirmingId != item.id {
                        self.confirmingId = nil
                    }
                    self.refreshSelection()
                }
            }
            tile.onClick = { [weak self] in
                self?.selectedIndex = idx
                self?.triggerSelected()
            }
            tiles.append(tile)
            row.addArrangedSubview(tile)
        }

        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        hintLabel.textColor = .white.withAlphaComponent(0.56)
        hintLabel.alignment = .center
        cardContainer.addSubview(hintLabel)

        NSLayoutConstraint.activate([
            cardContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            cardContainer.centerYAnchor.constraint(equalTo: centerYAnchor),
            cardContainer.widthAnchor.constraint(equalToConstant: cardW),
            cardContainer.heightAnchor.constraint(equalToConstant: cardH),

            effectView.leadingAnchor.constraint(equalTo: cardContainer.leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: cardContainer.trailingAnchor),
            effectView.topAnchor.constraint(equalTo: cardContainer.topAnchor),
            effectView.bottomAnchor.constraint(equalTo: cardContainer.bottomAnchor),

            overlayView.leadingAnchor.constraint(equalTo: cardContainer.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: cardContainer.trailingAnchor),
            overlayView.topAnchor.constraint(equalTo: cardContainer.topAnchor),
            overlayView.bottomAnchor.constraint(equalTo: cardContainer.bottomAnchor),

            row.centerXAnchor.constraint(equalTo: cardContainer.centerXAnchor),
            row.topAnchor.constraint(equalTo: cardContainer.topAnchor, constant: 16),

            hintLabel.centerXAnchor.constraint(equalTo: cardContainer.centerXAnchor),
            hintLabel.bottomAnchor.constraint(equalTo: cardContainer.bottomAnchor, constant: -12)
        ])
    }

    override func layout() {
        super.layout()
        let b = overlayView.bounds
        tintLayer.frame = b
        borderLayer.frame = b
        borderLayer.path = CGPath(roundedRect: b.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 24, cornerHeight: 24, transform: nil)
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        if !cardContainer.frame.contains(pt) {
            close(with: nil)
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Esc
            if confirmingId != nil {
                confirmingId = nil
                refreshSelection()
            } else {
                close(with: nil)
            }
        case 123: // Left arrow
            moveSelection(delta: -1)
        case 124, 48: // Right arrow or Tab
            moveSelection(delta: 1)
        case 36, 76, 49: // Return, Enter, Space
            triggerSelected()
        default:
            if let ch = event.charactersIgnoringModifiers?.lowercased() {
                switch ch {
                case "h": moveSelection(delta: -1)
                case "l": selectAndTrigger(.lock)
                case "s": selectAndTrigger(.sleep)
                case "r": selectAndTrigger(.restart)
                case "u": selectAndTrigger(.logout)
                case "p": selectAndTrigger(.shutdown)
                case "q": close(with: nil)
                default: super.keyDown(with: event)
                }
            } else {
                super.keyDown(with: event)
            }
        }
    }

    private func moveSelection(delta: Int) {
        let count = powerActions.count
        selectedIndex = (selectedIndex + delta + count) % count
        confirmingId = nil
        refreshSelection()
    }

    private func selectAndTrigger(_ id: PowerActionId) {
        guard let idx = powerActions.firstIndex(where: { $0.id == id }) else { return }
        selectedIndex = idx
        triggerSelected()
    }

    private func triggerSelected() {
        let item = powerActions[selectedIndex]
        if item.dangerous && confirmingId != item.id {
            confirmingId = item.id
            refreshSelection()
            return
        }
        close(with: item.id)
    }

    private func refreshSelection() {
        for (idx, tile) in tiles.enumerated() {
            let isSel = idx == selectedIndex
            let isConf = confirmingId == tile.item.id
            tile.render(selected: isSel, confirming: isConf)
        }
        if let cid = confirmingId,
           let item = powerActions.first(where: { $0.id == cid }) {
            hintLabel.stringValue = "Click or press Enter again to confirm \(item.title) · Esc to cancel"
            hintLabel.textColor = NSColor(hex: "fc5d7c")?.withAlphaComponent(0.95) ?? .systemRed
        } else {
            hintLabel.stringValue = "←/→ Move · Enter / L S R U P Execute · Esc Close"
            hintLabel.textColor = .white.withAlphaComponent(0.56)
        }
    }

    func close(with action: PowerActionId?) {
        guard !isClosing else { return }
        isClosing = true
        onDismiss?(action)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: KeyableWindow!
    private var menuView: PowerMenuController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        writePidFile()

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens[0]

        window = KeyableWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .statusBar + 10
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        window.alphaValue = 0.0

        menuView = PowerMenuController(frame: NSRect(origin: .zero, size: screen.frame.size))
        menuView.onDismiss = { [weak self] action in
            self?.animateCloseAndExit(action: action)
        }
        window.contentView = menuView

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(menuView)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.14
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1.0
        }
    }

    private func animateCloseAndExit(action: PowerActionId?) {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0.0
        }, completionHandler: {
            cleanupPidFile()
            if let action = action {
                executePowerAction(action)
            }
            NSApp.terminate(nil)
        })
    }
}

// MARK: - Entrypoint

if CommandLine.arguments.contains("--help") || CommandLine.arguments.contains("-h") {
    print("""
    powermenu — macOS themed PowerMenu overlay

    Usage:
      powermenu             Open (or toggle closed if already open)
      powermenu --toggle    Toggle the PowerMenu overlay
    """)
    exit(0)
}

if toggleExistingInstanceIfRunning() {
    exit(0)
}

signal(SIGTERM) { _ in
    cleanupPidFile()
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
