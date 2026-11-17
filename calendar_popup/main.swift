import AppKit
import Foundation
import QuartzCore

// MARK: - Theme Palette (~/.config/lockscreen/current_theme.json + ~/.config/rofi/colors.json)

struct CalendarTheme {
    let bg: NSColor
    let accent: NSColor
    let text: NSColor

    static func load() -> CalendarTheme {
        var bg = NSColor(hex: "14172f") ?? .black
        var accent = NSColor(hex: "c8b4fa") ?? .systemPurple
        var text = NSColor(hex: "f0edfc") ?? .white

        let rofiPath = NSHomeDirectory() + "/.config/rofi/colors.json"
        if let data = try? Data(contentsOf: URL(fileURLWithPath: rofiPath)),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            if let a = NSColor(hex: dict["accent"] ?? "") { accent = a }
            if let b = NSColor(hex: dict["bg"] ?? "") { bg = b }
        }

        let themePath = NSHomeDirectory() + "/.config/lockscreen/current_theme.json"
        if let data = try? Data(contentsOf: URL(fileURLWithPath: themePath)),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let hex = dict["islandHex"] as? String, let c = NSColor(hex: hex) { bg = c }
            if let hex = dict["accentHex"] as? String, let c = NSColor(hex: hex) { accent = c }
            if let hex = dict["textWhiteHex"] as? String, let c = NSColor(hex: hex) { text = c }
        }

        return CalendarTheme(bg: bg, accent: accent, text: text)
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

// MARK: - Single-Instance PID Toggle

private let kPidPath = "/tmp/calendar_popup.pid"

func toggleExistingInstanceIfRunning() -> Bool {
    guard let str = try? String(contentsOfFile: kPidPath, encoding: .utf8),
          let pid = Int32(str.trimmingCharacters(in: .whitespacesAndNewlines)),
          pid > 0, pid != getpid() else {
        return false
    }
    if kill(pid, 0) == 0 {
        kill(pid, SIGUSR1)
        return true
    }
    try? FileManager.default.removeItem(atPath: kPidPath)
    return false
}

func writePidFile() {
    try? "\(getpid())".write(toFile: kPidPath, atomically: true, encoding: .utf8)
}

func cleanupPidFile() {
    if let str = try? String(contentsOfFile: kPidPath, encoding: .utf8),
       let pid = Int32(str.trimmingCharacters(in: .whitespacesAndNewlines)),
       pid == getpid() {
        try? FileManager.default.removeItem(atPath: kPidPath)
    }
}

// MARK: - Keyable Borderless Popover Window

final class CalendarWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Minimalist Calendar View

final class MinimalCalendarView: NSView {
    private let theme: CalendarTheme
    private var isoCal: Calendar = {
        var c = Calendar(identifier: .iso8601)
        c.locale = Locale(identifier: "en_US_POSIX")
        c.firstWeekday = 2 // Monday
        return c
    }()

    private var displayMonthStart: Date
    private var hoveredCellIndex: Int? = nil
    private var hoveredHeaderControl: Int? = nil // 0 = title(today), 1 = prev, 2 = next
    private var trackingArea: NSTrackingArea?
    private var scrollAccum: CGFloat = 0

    var onRequestClose: (() -> Void)?

    // Layout rects updated in layout/draw
    private var prevRect: NSRect = .zero
    private var nextRect: NSRect = .zero
    private var titleRect: NSRect = .zero
    private var todayPillRect: NSRect = .zero
    private var cellRects: [NSRect] = Array(repeating: .zero, count: 42)
    private var cellDays: [(day: Int, inMonth: Bool, isToday: Bool, isWeekend: Bool, date: Date)] = []

    private let weekdayTitles = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

    private static func makeFont(size: CGFloat, bold: Bool = false, semibold: Bool = false) -> NSFont {
        let name = bold ? "JetBrainsMonoNF-Bold" : (semibold ? "JetBrainsMonoNF-SemiBold" : "JetBrainsMonoNF-Regular")
        if let f = NSFont(name: name, size: size) {
            return f
        }
        let weight: NSFont.Weight = bold ? .bold : (semibold ? .semibold : .medium)
        return NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
    }

    init(frame: NSRect, theme: CalendarTheme) {
        self.theme = theme
        let comps = isoCal.dateComponents([.year, .month], from: Date())
        self.displayMonthStart = isoCal.date(from: comps) ?? Date()
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        rebuildMonthGrid()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea {
            removeTrackingArea(ta)
        }
        let ta = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(ta)
        trackingArea = ta
    }

    private func isShowingCurrentMonth() -> Bool {
        let nowComps = isoCal.dateComponents([.year, .month], from: Date())
        let dispComps = isoCal.dateComponents([.year, .month], from: displayMonthStart)
        return nowComps.year == dispComps.year && nowComps.month == dispComps.month
    }

    private func shiftMonth(by delta: Int) {
        if let next = isoCal.date(byAdding: .month, value: delta, to: displayMonthStart) {
            displayMonthStart = next
            hoveredCellIndex = nil
            rebuildMonthGrid()
            needsDisplay = true
        }
    }

    private func jumpToToday() {
        let comps = isoCal.dateComponents([.year, .month], from: Date())
        displayMonthStart = isoCal.date(from: comps) ?? Date()
        hoveredCellIndex = nil
        rebuildMonthGrid()
        needsDisplay = true
    }

    private func rebuildMonthGrid() {
        cellDays.removeAll(keepingCapacity: true)
        let weekday = isoCal.component(.weekday, from: displayMonthStart) // 1=Sun,2=Mon,...,7=Sat
        let leadingDays = (weekday + 5) % 7 // Mon=0..Sun=6
        guard let gridStart = isoCal.date(byAdding: .day, value: -leadingDays, to: displayMonthStart) else { return }

        let targetYear = isoCal.component(.year, from: displayMonthStart)
        let targetMonth = isoCal.component(.month, from: displayMonthStart)
        let today = Date()

        for offset in 0..<42 {
            guard let date = isoCal.date(byAdding: .day, value: offset, to: gridStart) else { continue }
            let y = isoCal.component(.year, from: date)
            let m = isoCal.component(.month, from: date)
            let d = isoCal.component(.day, from: date)
            let wd = isoCal.component(.weekday, from: date)
            let inMonth = (y == targetYear && m == targetMonth)
            let isToday = isoCal.isDate(date, inSameDayAs: today)
            let isWeekend = (wd == 1 || wd == 7)
            cellDays.append((day: d, inMonth: inMonth, isToday: isToday, isWeekend: isWeekend, date: date))
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let w = bounds.width
        let h = bounds.height
        let cardRect = NSRect(x: 1, y: 1, width: w - 2, height: h - 2)
        let cardPath = NSBezierPath(roundedRect: cardRect, xRadius: 11, yRadius: 11)

        // Card fill & border matching SketchyBar island popups
        theme.bg.withAlphaComponent(0.95).setFill()
        cardPath.fill()

        theme.accent.withAlphaComponent(0.35).setStroke()
        cardPath.lineWidth = 1.0
        cardPath.stroke()

        let padX: CGFloat = 14
        let padTop: CGFloat = 13

        // Header controls
        let btnSize: CGFloat = 22
        let headerY = h - padTop - btnSize
        nextRect = NSRect(x: w - padX - btnSize, y: headerY, width: btnSize, height: btnSize)
        prevRect = NSRect(x: nextRect.minX - 4 - btnSize, y: headerY, width: btnSize, height: btnSize)

        let showTodayBtn = !isShowingCurrentMonth()
        if showTodayBtn {
            todayPillRect = NSRect(x: prevRect.minX - 46, y: headerY + 2, width: 40, height: 18)
        } else {
            todayPillRect = .zero
        }

        let titleMaxW = (showTodayBtn ? todayPillRect.minX : prevRect.minX) - padX - 4
        titleRect = NSRect(x: padX, y: headerY, width: max(80, titleMaxW), height: btnSize)

        // Month & Year title
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "LLLL yyyy"
        let monthTitle = fmt.string(from: displayMonthStart)

        let titleColor = hoveredHeaderControl == 0
            ? theme.accent
            : theme.text.withAlphaComponent(0.96)
        drawCenteredText(
            monthTitle,
            in: titleRect,
            font: Self.makeFont(size: 12.5, bold: true),
            color: titleColor,
            alignment: .left
        )

        if showTodayBtn {
            let tPath = NSBezierPath(roundedRect: todayPillRect, xRadius: 5, yRadius: 5)
            let bgAlpha: CGFloat = hoveredHeaderControl == 3 ? 0.28 : 0.14
            theme.accent.withAlphaComponent(bgAlpha).setFill()
            tPath.fill()
            drawCenteredText(
                "Today",
                in: todayPillRect,
                font: Self.makeFont(size: 9.5, semibold: true),
                color: theme.accent
            )
        }

        // Prev / Next buttons
        drawArrowButton(rect: prevRect, symbol: "‹", hovered: hoveredHeaderControl == 1)
        drawArrowButton(rect: nextRect, symbol: "›", hovered: hoveredHeaderControl == 2)

        // Subtle divider line
        let divY = headerY - 9
        let divPath = NSBezierPath()
        divPath.move(to: NSPoint(x: padX, y: divY))
        divPath.line(to: NSPoint(x: w - padX, y: divY))
        theme.accent.withAlphaComponent(0.18).setStroke()
        divPath.lineWidth = 1.0
        divPath.stroke()

        // Weekday row
        let gridW = w - padX * 2
        let colW = gridW / 7.0
        let weekRowH: CGFloat = 18
        let weekRowY = divY - 6 - weekRowH

        for col in 0..<7 {
            let rect = NSRect(x: padX + CGFloat(col) * colW, y: weekRowY, width: colW, height: weekRowH)
            let isWknd = col >= 5
            let colColor = isWknd
                ? theme.accent.withAlphaComponent(0.65)
                : theme.text.withAlphaComponent(0.45)
            drawCenteredText(
                weekdayTitles[col],
                in: rect,
                font: Self.makeFont(size: 10.0, semibold: true),
                color: colColor
            )
        }

        // 6x7 day grid
        let gridTop = weekRowY - 4
        let gridBottom: CGFloat = 12
        let rowH = (gridTop - gridBottom) / 6.0

        for idx in 0..<min(42, cellDays.count) {
            let row = idx / 7
            let col = idx % 7
            let cellRect = NSRect(
                x: padX + CGFloat(col) * colW,
                y: gridTop - CGFloat(row + 1) * rowH,
                width: colW,
                height: rowH
            )
            cellRects[idx] = cellRect

            let item = cellDays[idx]
            let pillSize = min(colW - 4, rowH - 3)
            let pillRect = NSRect(
                x: cellRect.midX - pillSize / 2.0,
                y: cellRect.midY - pillSize / 2.0,
                width: pillSize,
                height: pillSize
            )

            if item.isToday {
                NSGraphicsContext.saveGraphicsState()
                let glow = NSShadow()
                glow.shadowColor = theme.accent.withAlphaComponent(0.42)
                glow.shadowBlurRadius = 6.0
                glow.shadowOffset = .zero
                glow.set()

                let p = NSBezierPath(roundedRect: pillRect, xRadius: 7, yRadius: 7)
                theme.accent.setFill()
                p.fill()
                NSGraphicsContext.restoreGraphicsState()
            } else if hoveredCellIndex == idx {
                let p = NSBezierPath(roundedRect: pillRect, xRadius: 7, yRadius: 7)
                theme.accent.withAlphaComponent(0.15).setFill()
                p.fill()
            }

            let textColor: NSColor
            if item.isToday {
                textColor = theme.bg
            } else if !item.inMonth {
                textColor = theme.text.withAlphaComponent(0.18)
            } else if item.isWeekend {
                textColor = theme.accent.withAlphaComponent(0.84)
            } else {
                textColor = theme.text.withAlphaComponent(0.90)
            }

            drawCenteredText(
                "\(item.day)",
                in: pillRect,
                font: Self.makeFont(size: 11.5, bold: item.isToday, semibold: item.inMonth),
                color: textColor
            )
        }
    }

    private func drawArrowButton(rect: NSRect, symbol: String, hovered: Bool) {
        let p = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        (hovered ? theme.accent.withAlphaComponent(0.22) : theme.text.withAlphaComponent(0.05)).setFill()
        p.fill()
        let color = hovered ? theme.accent : theme.text.withAlphaComponent(0.72)
        drawCenteredText(symbol, in: rect.offsetBy(dx: 0, dy: 0.5), font: Self.makeFont(size: 14.0, bold: true), color: color)
    }

    private func drawCenteredText(
        _ str: String,
        in rect: NSRect,
        font: NSFont,
        color: NSColor,
        alignment: NSTextAlignment = .center
    ) {
        let para = NSMutableParagraphStyle()
        para.alignment = alignment
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: para
        ]
        let attrStr = NSAttributedString(string: str, attributes: attrs)
        let textSize = attrStr.size()
        let drawRect = NSRect(
            x: rect.minX,
            y: rect.midY - textSize.height / 2.0,
            width: rect.width,
            height: textSize.height
        )
        attrStr.draw(in: drawRect)
    }

    // MARK: - Pointer & Keyboard Interaction

    override func mouseMoved(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        var newHdr: Int? = nil
        if prevRect.contains(pt) { newHdr = 1 }
        else if nextRect.contains(pt) { newHdr = 2 }
        else if todayPillRect != .zero && todayPillRect.contains(pt) { newHdr = 3 }
        else if titleRect.contains(pt) { newHdr = 0 }

        var newCell: Int? = nil
        if newHdr == nil {
            for (idx, r) in cellRects.enumerated() where r.contains(pt) {
                newCell = idx
                break
            }
        }

        if newHdr != hoveredHeaderControl || newCell != hoveredCellIndex {
            hoveredHeaderControl = newHdr
            hoveredCellIndex = newCell
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        if hoveredHeaderControl != nil || hoveredCellIndex != nil {
            hoveredHeaderControl = nil
            hoveredCellIndex = nil
            needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        if prevRect.contains(pt) {
            shiftMonth(by: -1)
            return
        }
        if nextRect.contains(pt) {
            shiftMonth(by: 1)
            return
        }
        if (todayPillRect != .zero && todayPillRect.contains(pt)) || titleRect.contains(pt) {
            jumpToToday()
            return
        }
        for (idx, r) in cellRects.enumerated() where r.contains(pt) && idx < cellDays.count {
            let item = cellDays[idx]
            if !item.inMonth {
                let comps = isoCal.dateComponents([.year, .month], from: item.date)
                if let monthStart = isoCal.date(from: comps) {
                    displayMonthStart = monthStart
                    rebuildMonthGrid()
                    needsDisplay = true
                }
            }
            return
        }
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX)
            ? event.scrollingDeltaY
            : event.scrollingDeltaX
        scrollAccum += delta
        let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 28.0 : 1.0
        if scrollAccum <= -threshold {
            scrollAccum = 0
            shiftMonth(by: 1)
        } else if scrollAccum >= threshold {
            scrollAccum = 0
            shiftMonth(by: -1)
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Esc
            onRequestClose?()
        case 123: // Left
            shiftMonth(by: -1)
        case 124: // Right
            shiftMonth(by: 1)
        case 49: // Space
            jumpToToday()
        default:
            let ch = (event.charactersIgnoringModifiers ?? "").lowercased()
            if ch == "q" { onRequestClose?() }
            else if ch == "h" || ch == "k" { shiftMonth(by: -1) }
            else if ch == "l" || ch == "j" { shiftMonth(by: 1) }
            else if ch == "t" || ch == "0" { jumpToToday() }
        }
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: CalendarWindow!
    private var calView: MinimalCalendarView!
    private var sig1Source: DispatchSourceSignal?
    private var globalMouseMonitor: Any?
    private var isClosing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        writePidFile()

        signal(SIGUSR1, SIG_IGN)
        let s1 = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        s1.setEventHandler { [weak self] in
            self?.closeAndExit()
        }
        s1.resume()
        sig1Source = s1

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens[0]
        let width: CGFloat = 248
        let height: CGFloat = 244
        let x = screen.frame.maxX - width - 12
        let y = screen.frame.maxY - 45 - height

        window = CalendarWindow(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .statusBar + 5
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        window.alphaValue = 0.0

        let theme = CalendarTheme.load()
        calView = MinimalCalendarView(frame: NSRect(x: 0, y: 0, width: width, height: height), theme: theme)
        calView.onRequestClose = { [weak self] in
            self?.closeAndExit()
        }
        window.contentView = calView

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(calView)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.14
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1.0
        }

        // Click anywhere outside card (except top-right cal island which toggles via sketchybar) closes popover
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self = self, !self.isClosing else { return }
            let loc = NSEvent.mouseLocation
            if self.window.frame.contains(loc) { return }
            let calHitRect = NSRect(
                x: screen.frame.maxX - 180,
                y: screen.frame.maxY - 46,
                width: 180,
                height: 46
            )
            if calHitRect.contains(loc) { return }
            self.closeAndExit()
        }
    }

    func applicationDidResignActive(_ notification: Notification) {
        closeAndExit()
    }

    func closeAndExit() {
        guard !isClosing else { return }
        isClosing = true
        if let mon = globalMouseMonitor {
            NSEvent.removeMonitor(mon)
            globalMouseMonitor = nil
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.10
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0.0
        }, completionHandler: {
            cleanupPidFile()
            NSApp.terminate(nil)
        })
    }
}

// MARK: - Entrypoint

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
