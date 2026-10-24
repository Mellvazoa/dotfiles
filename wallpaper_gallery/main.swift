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

// ── Theme Extractor (Dynamic Color Adaptation for Sketchybar & Gallery) ──────
struct ThemeColors {
    let accentHex: String       // e.g. "fa5f61"
    let accentLightHex: String  // e.g. "fd8c8e"
    let accentDimHex: String    // e.g. "d14749"
    let lilacHex: String        // e.g. "fa7a5f"
    let islandHex: String       // e.g. "211112"
    let textWhiteHex: String    // e.g. "f6f2f2"
    let bg1Hex: String          // e.g. "2d191a"
    let bg2Hex: String          // e.g. "3f2527"
    
    let accentNSColor: NSColor
    let islandNSColor: NSColor
    let isArona: Bool
}

class ThemeExtractor {
    // Original signature theme for Arona
    static let aronaTheme = ThemeColors(
        accentHex: "c8b4fa",
        accentLightHex: "e4d2fd",
        accentDimHex: "aba0f5",
        lilacHex: "928dfb",
        islandHex: "14172f",
        textWhiteHex: "f0edfc",
        bg1Hex: "1c203f",
        bg2Hex: "292e59",
        accentNSColor: NSColor(red: 200/255.0, green: 180/255.0, blue: 250/255.0, alpha: 1.0),
        islandNSColor: NSColor(red: 20/255.0, green: 23/255.0, blue: 47/255.0, alpha: 0.88),
        isArona: true
    )

    static func extract(from path: String, name: String) -> ThemeColors {
        let lower = name.lowercased()
        if lower.contains("arona") || lower.contains("arcona") {
            return aronaTheme
        }

        guard let img = NSImage(contentsOfFile: path) else {
            return aronaTheme
        }

        let size = 48
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: size,
            pixelsHigh: size,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: size * 4,
            bitsPerPixel: 32
        )
        guard let bitmap = rep else { return aronaTheme }

        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current = context
        img.draw(in: NSRect(x: 0, y: 0, width: size, height: size), from: .zero, operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        guard let data = bitmap.bitmapData else { return aronaTheme }

        var bestHue: Double = 260.0
        var bestSat: Double = 0.60
        var bestScore: Double = -1.0

        for i in 0..<(size * size) {
            let r = Double(data[i * 4]) / 255.0
            let g = Double(data[i * 4 + 1]) / 255.0
            let b = Double(data[i * 4 + 2]) / 255.0
            let a = Double(data[i * 4 + 3]) / 255.0
            if a > 0.5 {
                let maxV = max(r, g, b)
                let minV = min(r, g, b)
                let l = (maxV + minV) / 2.0
                if maxV != minV && l > 0.15 && l < 0.88 {
                    let d = maxV - minV
                    let s = l > 0.5 ? d / (2.0 - maxV - minV) : d / (maxV + minV)
                    if s > 0.15 {
                        var h: Double = 0
                        if maxV == r { h = (g - b) / d + (g < b ? 6.0 : 0.0) }
                        else if maxV == g { h = (b - r) / d + 2.0 }
                        else { h = (r - g) / d + 4.0 }
                        h *= 60.0

                        let score = s * 1.6 + (1.0 - abs(l - 0.58))
                        if score > bestScore {
                            bestScore = score
                            bestHue = h
                            bestSat = s
                        }
                    }
                }
            }
        }

        func hslToHex(h: Double, s: Double, l: Double) -> (String, NSColor) {
            let c = (1.0 - abs(2.0 * l - 1.0)) * s
            let x = c * (1.0 - abs((h / 60.0).truncatingRemainder(dividingBy: 2.0) - 1.0))
            let m = l - c / 2.0
            var r1: Double = 0, g1: Double = 0, b1: Double = 0
            if h < 60 { r1 = c; g1 = x; b1 = 0 }
            else if h < 120 { r1 = x; g1 = c; b1 = 0 }
            else if h < 180 { r1 = 0; g1 = c; b1 = x }
            else if h < 240 { r1 = 0; g1 = x; b1 = c }
            else if h < 300 { r1 = x; g1 = 0; b1 = c }
            else { r1 = c; g1 = 0; b1 = x }

            let rByte = UInt8(clamping: Int((r1 + m) * 255.0))
            let gByte = UInt8(clamping: Int((g1 + m) * 255.0))
            let bByte = UInt8(clamping: Int((b1 + m) * 255.0))
            let hex = String(format: "%02x%02x%02x", rByte, gByte, bByte)
            let color = NSColor(red: CGFloat(rByte)/255.0, green: CGFloat(gByte)/255.0, blue: CGFloat(bByte)/255.0, alpha: 1.0)
            return (hex, color)
        }

        let sat = max(0.55, min(0.92, bestSat))
        let (accentHex, accentNSColor) = hslToHex(h: bestHue, s: sat, l: 0.76)
        let (accentLightHex, _)        = hslToHex(h: bestHue, s: sat * 0.9, l: 0.86)
        let (accentDimHex, _)          = hslToHex(h: bestHue, s: sat, l: 0.62)
        let (lilacHex, _)              = hslToHex(h: (bestHue + 25.0).truncatingRemainder(dividingBy: 360.0), s: sat, l: 0.72)
        let (islandHex, islandNSColor) = hslToHex(h: bestHue, s: 0.28, l: 0.10)
        let (textWhiteHex, _)          = hslToHex(h: bestHue, s: 0.18, l: 0.96)
        let (bg1Hex, _)                = hslToHex(h: bestHue, s: 0.28, l: 0.14)
        let (bg2Hex, _)                = hslToHex(h: bestHue, s: 0.28, l: 0.20)

        return ThemeColors(
            accentHex: accentHex,
            accentLightHex: accentLightHex,
            accentDimHex: accentDimHex,
            lilacHex: lilacHex,
            islandHex: islandHex,
            textWhiteHex: textWhiteHex,
            bg1Hex: bg1Hex,
            bg2Hex: bg2Hex,
            accentNSColor: accentNSColor,
            islandNSColor: islandNSColor,
            isArona: false
        )
    }

    static func applyTheme(_ theme: ThemeColors) {
        // ── 1. Sketchybar Theme ──────────────────────────────────────────────
        let sketchybarContent = """
return {
  black       = 0xff14172f,
  white       = 0xff\(theme.textWhiteHex),
  red         = 0xfffc5d7c,
  green       = 0xffa3e49b,
  blue        = 0xff9ccdfb,
  yellow      = 0xfff6df94,
  orange      = 0xfffca07a,
  magenta     = 0xff\(theme.accentHex),
  grey        = 0xff8a8eb5,
  transparent = 0x00000000,

  -- Dynamic wallpaper palette (accent: #\(theme.accentHex))
  lavender       = 0xff\(theme.accentHex),
  lavender_light = 0xff\(theme.accentLightHex),
  lavender_dim   = 0xff\(theme.accentDimHex),
  lilac          = 0xff\(theme.lilacHex),
  arch           = 0xff\(theme.accentHex),
  arch_dark      = 0xff\(theme.bg2Hex),

  -- Island pill background
  island         = 0xd9\(theme.islandHex),
  island_border  = 0x44\(theme.accentHex),

  bar = {
    bg     = 0x00000000,
    border = 0x00000000,
  },
  popup = {
    bg     = 0xf2\(theme.islandHex),
    border = 0x55\(theme.accentHex),
  },
  bg1 = 0xff\(theme.bg1Hex),
  bg2 = 0xff\(theme.bg2Hex),

  with_alpha = function(color, alpha)
    if alpha > 1.0 or alpha < 0.0 then return color end
    return (color & 0x00ffffff) | (math.floor(alpha * 255.0) << 24)
  end,
}
"""

        // ── 2. Kitty Current Theme ───────────────────────────────────────────
        let kittyContent: String
        if theme.isArona {
            kittyContent = """
# Soft Lavender - Blue Archive Arona Classroom Theme
# Matching Sketchybar, Borders and Kitty

# The basic colors
foreground              #f0edfc
background              #14172f
selection_foreground    #14172f
selection_background    #c8b4fa

# Cursor colors
cursor                  #e4d2fd
cursor_text_color       #14172f

# URL underline color when hovering with mouse
url_color               #c8b4fa

# Kitty window border colors
active_border_color     #c8b4fa
inactive_border_color   #292e59
bell_border_color       #fca5d0

# OS Window titlebar colors
wayland_titlebar_color  system
macos_titlebar_color    system

# Tab bar colors
active_tab_foreground   #14172f
active_tab_background   #c8b4fa
inactive_tab_foreground #8a8eb5
inactive_tab_background #1c203f
tab_bar_background      #111538

# Colors for marks
mark1_foreground        #14172f
mark1_background        #9ccdfb
mark2_foreground        #14172f
mark2_background        #c8b4fa
mark3_foreground        #14172f
mark3_background        #928dfb

# 16 Terminal Colors

# Black
color0 #1c203f
color8 #4d5280

# Red
color1 #fc5d7c
color9 #fc7a95

# Green (Harmonious Soft Lavender / Sage tint instead of neon green)
color2  #aba0f5
color10 #c8b4fa

# Yellow
color3  #f6df94
color11 #f9e9ad

# Blue (Pastel Periwinkle)
color4  #9ccdfb
color12 #bce0fd

# Magenta (Soft Lavender / Lilac)
color5  #c8b4fa
color13 #e4d2fd

# Cyan (Arona Halo Cyan)
color6  #8ae1e8
color14 #a9eff5

# White
color7  #d8d3f5
color15 #f5f2fe
"""
        } else {
            kittyContent = """
# Dynamic Wallpaper Palette (accent: #\(theme.accentHex))
# Matching Sketchybar, Borders and Kitty

# The basic colors
foreground              #\(theme.textWhiteHex)
background              #\(theme.islandHex)
selection_foreground    #\(theme.islandHex)
selection_background    #\(theme.accentHex)

# Cursor colors
cursor                  #\(theme.accentLightHex)
cursor_text_color       #\(theme.islandHex)

# URL underline color when hovering with mouse
url_color               #\(theme.accentHex)

# Kitty window border colors
active_border_color     #\(theme.accentHex)
inactive_border_color   #\(theme.bg2Hex)
bell_border_color       #\(theme.accentLightHex)

# OS Window titlebar colors
wayland_titlebar_color  system
macos_titlebar_color    system

# Tab bar colors
active_tab_foreground   #\(theme.islandHex)
active_tab_background   #\(theme.accentHex)
inactive_tab_foreground #\(theme.accentDimHex)
inactive_tab_background #\(theme.bg1Hex)
tab_bar_background      #\(theme.islandHex)

# Colors for marks
mark1_foreground        #\(theme.islandHex)
mark1_background        #\(theme.accentLightHex)
mark2_foreground        #\(theme.islandHex)
mark2_background        #\(theme.accentHex)
mark3_foreground        #\(theme.islandHex)
mark3_background        #\(theme.lilacHex)

# 16 Terminal Colors

# Black
color0 #\(theme.bg1Hex)
color8 #\(theme.bg2Hex)

# Red
color1 #fc5d7c
color9 #fc7a95

# Green
color2  #a3e49b
color10 #baf0b3

# Yellow
color3  #f6df94
color11 #f9e9ad

# Blue
color4  #9ccdfb
color12 #bce0fd

# Magenta (Accent)
color5  #\(theme.accentHex)
color13 #\(theme.accentLightHex)

# Cyan (Lilac / Secondary)
color6  #\(theme.lilacHex)
color14 #\(theme.accentLightHex)

# White
color7  #\(theme.accentDimHex)
color15 #\(theme.textWhiteHex)
"""
        }

        // ── 3. Borders Config ────────────────────────────────────────────────
        let bordersContent: String
        if theme.isArona {
            bordersContent = """
#!/bin/bash

options=(
  "style=round"
  "hidpi=on"
  "ax_focus=on"
  "active_color=gradient(top_left=0xffe4d2fd,bottom_right=0xff928dfb)"
  "inactive_color=0x221d2356"
  "width=4.0"
  "order=above"
)

borders "${options[@]}"
"""
        } else {
            bordersContent = """
#!/bin/bash

options=(
  "style=round"
  "hidpi=on"
  "ax_focus=on"
  "active_color=gradient(top_left=0xff\(theme.accentLightHex),bottom_right=0xff\(theme.accentHex))"
  "inactive_color=0x22\(theme.bg2Hex)"
  "width=4.0"
  "order=above"
)

borders "${options[@]}"
"""
        }

        // ── 4. Rofi / Choose Colors JSON ─────────────────────────────────────
        let rofiContent = """
{
  "bg": "\(theme.bg2Hex)",
  "accent_light": "\(theme.accentLightHex)",
  "accent": "\(theme.accentHex)"
}
"""

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let ws = "/Users/new/Documents/Antigravity/waybar"

        // Write Sketchybar
        let sketchybarPaths = [
            "\(home)/.config/sketchybar/colors.lua",
            "\(ws)/sketchybar_src/colors.lua"
        ]
        for p in sketchybarPaths {
            try? sketchybarContent.write(toFile: p, atomically: true, encoding: .utf8)
        }

        // Write Kitty
        let kittyPaths = [
            "\(home)/.config/kitty/current-theme.conf",
            "\(ws)/kitty/current-theme.conf"
        ]
        for p in kittyPaths {
            try? kittyContent.write(toFile: p, atomically: true, encoding: .utf8)
        }

        // Write Borders
        let bordersPaths = [
            "\(home)/.config/borders/bordersrc",
            "\(ws)/borders/bordersrc"
        ]
        for p in bordersPaths {
            try? bordersContent.write(toFile: p, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: p)
        }

        // Write Rofi
        let rofiPaths = [
            "\(home)/.config/rofi/colors.json",
            "\(ws)/rofi/colors.json"
        ]
        for p in rofiPaths {
            try? rofiContent.write(toFile: p, atomically: true, encoding: .utf8)
        }

        // Update Yabai yabairc
        let yabaiPaths = [
            "\(home)/.config/yabai/yabairc",
            "\(ws)/yabai/yabairc"
        ]
        for p in yabaiPaths {
            if let existing = try? String(contentsOfFile: p, encoding: .utf8) {
                if let regex = try? NSRegularExpression(pattern: "insert_feedback_color\\s+0xff[0-9a-fA-F]+") {
                    let range = NSRange(location: 0, length: existing.utf16.count)
                    let updated = regex.stringByReplacingMatches(in: existing, options: [], range: range, withTemplate: "insert_feedback_color      0xff\(theme.accentHex)")
                    try? updated.write(toFile: p, atomically: true, encoding: .utf8)
                }
            }
        }

        // ── 5. Asynchronously reload external utilities ───────────────────────
        DispatchQueue.global(qos: .utility).async {
            // 1. Reload Sketchybar
            let task1 = Process()
            task1.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            task1.arguments = ["sketchybar", "--reload"]
            try? task1.run()
            task1.waitUntilExit()

            // 2. Reload Kitty without quitting
            let task2 = Process()
            task2.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            task2.arguments = ["killall", "-SIGUSR1", "kitty"]
            try? task2.run()
            task2.waitUntilExit()

            // 3. Restart Borders with new gradient/inactive colors
            let task3 = Process()
            task3.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            task3.arguments = ["killall", "borders"]
            try? task3.run()
            task3.waitUntilExit()

            // Ensure borders process is alive
            usleep(150_000)
            let checkTask = Process()
            checkTask.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            checkTask.arguments = ["pgrep", "-x", "borders"]
            let pipe = Pipe()
            checkTask.standardOutput = pipe
            try? checkTask.run()
            checkTask.waitUntilExit()
            if checkTask.terminationStatus != 0 {
                let startTask = Process()
                startTask.executableURL = URL(fileURLWithPath: "\(home)/.config/borders/bordersrc")
                try? startTask.run()
            }

            // 4. Update Yabai insert_feedback_color dynamically
            let task4 = Process()
            task4.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            task4.arguments = ["yabai", "-m", "config", "insert_feedback_color", "0xff\(theme.accentHex)"]
            try? task4.run()
            task4.waitUntilExit()
        }
    }
}

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

    var accentColor: NSColor = NSColor(red: 200/255.0, green: 180/255.0, blue: 250/255.0, alpha: 1.0)
    var islandColor: NSColor = NSColor(red: 19/255.0, green: 22/255.0, blue: 48/255.0, alpha: 0.88)

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

        // Island Background (Adapts dynamically to theme)
        let bgColor = isHovered 
            ? islandColor.withAlphaComponent(0.96)
            : islandColor.withAlphaComponent(0.88)
        bgColor.setFill()
        path.fill()

        // Border: Dynamic accent glow
        let borderColor = isHovered
            ? accentColor.withAlphaComponent(0.85)
            : accentColor.withAlphaComponent(0.35)
        borderColor.setStroke()
        path.lineWidth = isHovered ? 1.5 : 1.0
        path.stroke()

        // Font
        let font = NSFont(name: "JetBrainsMono Nerd Font", size: 12.0)
            ?? NSFont(name: "JetBrainsMono-Bold", size: 12.0)
            ?? NSFont.systemFont(ofSize: 12.0, weight: .semibold)

        let textColor = isHovered
            ? NSColor.white
            : accentColor

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

    func updateColors(accent: NSColor, island: NSColor) {
        pillView.accentColor = accent
        pillView.islandColor = island
        pillView.needsDisplay = true
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

        // Hide desktop bottom pill while gallery is open so it never peeks out underneath!
        AppDelegate.shared?.pillWindow.setDesktopVisibility(empty: false)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123, 126: // Left / Up arrow
            webView.evaluateJavaScript("window.prev();", completionHandler: nil)
        case 124, 125: // Right / Down arrow
            webView.evaluateJavaScript("window.next();", completionHandler: nil)
        case 36: // Return
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

        // Restore desktop bottom pill check
        AppDelegate.shared?.checkDesktopState()
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

            switch event.keyCode {
            case 123, 126: // Left / Up arrow
                gallery.webView.evaluateJavaScript("window.prev();", completionHandler: nil)
                return nil
            case 124, 125: // Right / Down arrow
                gallery.webView.evaluateJavaScript("window.next();", completionHandler: nil)
                return nil
            case 36: // Return
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

            switch event.keyCode {
            case 123, 126: // Left / Up arrow
                gallery.webView.evaluateJavaScript("window.prev();", completionHandler: nil)
            case 124, 125: // Right / Down arrow
                gallery.webView.evaluateJavaScript("window.next();", completionHandler: nil)
            case 36: // Return
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

        // Initialize colors from current wallpaper if available
        let currentPath = WallpaperScanner.currentWallpaperPath()
        let currentName = WallpaperScanner.currentWallpaperName()
        if !currentPath.isEmpty {
            let theme = ThemeExtractor.extract(from: currentPath, name: currentName)
            pillWindow.updateColors(accent: theme.accentNSColor, island: theme.islandNSColor)
            ThemeExtractor.applyTheme(theme)
        }

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
        // If gallery window is open, never show the bottom pill
        if galleryWindow.isVisible && galleryWindow.alphaValue > 0.4 {
            pillWindow.setDesktopVisibility(empty: false)
            return
        }
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

        // Dynamic theme extraction & Sketchybar reload
        let theme = ThemeExtractor.extract(from: path, name: name)
        ThemeExtractor.applyTheme(theme)

        // Update bottom pill colors
        pillWindow.updateColors(accent: theme.accentNSColor, island: theme.islandNSColor)
        pillWindow.updatePill(title: name)

        // Update gallery CSS variables in real time
        let js = "if (window.setTheme) { window.setTheme('#\(theme.accentHex)', '#\(theme.islandHex)', '#\(theme.textWhiteHex)'); }"
        galleryWindow.webView.evaluateJavaScript(js, completionHandler: nil)
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
