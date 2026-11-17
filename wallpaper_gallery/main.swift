import AppKit
import WebKit
import Metal
import QuartzCore

// ── Models ───────────────────────────────────────────────────────────────────
struct WallpaperItem: Codable {
    let path: String
    let name: String
    let category: String
}

// ── Notification Name for IPC ────────────────────────────────────────────────
let kToggleNotification       = Notification.Name("com.mellvazoa.wallpaper.toggle")
let kOpenNotification         = Notification.Name("com.mellvazoa.wallpaper.open")
let kSetWallpaperNotification = Notification.Name("com.mellvazoa.wallpaper.set")
let kApplyThemeNotification   = Notification.Name("com.mellvazoa.wallpaper.theme")

// ── Transition Settings & Styles (Inspired by awww / 43PR dotfiles) ──────────
enum TransitionStyle: String, CaseIterable, Codable {
    case outer
    case grow
    case wave
    case wipe
    case center
    case any
    case fade
    case random

    var shaderMode: Int32 {
        switch self {
        case .outer:             return 0
        case .grow, .center, .any: return 1
        case .wave:              return 2
        case .wipe:              return 3
        case .fade:              return 4
        case .random:            return 0
        }
    }

    static func concreteStyles() -> [TransitionStyle] {
        return [.outer, .grow, .wave, .wipe, .center, .any, .fade]
    }
}

struct TransitionSettings: Codable {
    var style: String
    var duration: Double

    static let defaultSettings = TransitionSettings(style: TransitionStyle.outer.rawValue, duration: 1.0)

    private static var settingsURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return URL(fileURLWithPath: "\(home)/.config/wallpaper_gallery/settings.json")
    }

    static func load() -> TransitionSettings {
        guard let data = try? Data(contentsOf: settingsURL),
              var decoded = try? JSONDecoder().decode(TransitionSettings.self, from: data) else {
            return defaultSettings
        }
        if TransitionStyle(rawValue: decoded.style) == nil {
            decoded.style = defaultSettings.style
        }
        decoded.duration = max(0.25, min(3.0, decoded.duration))
        return decoded
    }

    func save() {
        let dir = TransitionSettings.settingsURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(self) {
            try? data.write(to: TransitionSettings.settingsURL)
        }
    }
}

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

    static func isPresetLocked() -> Bool {
        let statePath = "\(FileManager.default.homeDirectoryForCurrentUser.path)/.config/theme/state.json"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: statePath)),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        return (dict["locked"] as? Bool) ?? false
    }

    static func colorFromHex(_ hex: String, alpha: CGFloat = 1.0) -> NSColor? {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard clean.count == 6, let val = UInt64(clean, radix: 16) else { return nil }
        let r = CGFloat((val >> 16) & 0xFF) / 255.0
        let g = CGFloat((val >> 8) & 0xFF) / 255.0
        let b = CGFloat(val & 0xFF) / 255.0
        return NSColor(srgbRed: r, green: g, blue: b, alpha: alpha)
    }

    /// Reads the currently active system theme (covers both curated presets and dynamic wallpaper palettes).
    static func currentActivePalette() -> (accentHex: String, islandHex: String, textHex: String)? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let lockJsonPath = "\(home)/.config/lockscreen/current_theme.json"
        if let data = try? Data(contentsOf: URL(fileURLWithPath: lockJsonPath)),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let accent = dict["accentHex"] as? String,
           let island = dict["islandHex"] as? String {
            let text = (dict["textWhiteHex"] as? String) ?? "f0edfc"
            return (accent, island, text)
        }

        // Fallback: parse active Sketchybar colors.lua
        let colorsLuaPath = "\(home)/.config/sketchybar/colors.lua"
        if let lua = try? String(contentsOfFile: colorsLuaPath, encoding: .utf8) {
            var accent: String?
            var island: String?
            var white: String?
            for raw in lua.components(separatedBy: .newlines) {
                let parts = raw.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count == 2 else { continue }
                let val = parts[1].replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
                guard val.hasPrefix("0x"), val.count == 10 else { continue }
                let rgb = String(val.suffix(6))
                if parts[0] == "lavender" { accent = rgb }
                else if parts[0] == "island" { island = rgb }
                else if parts[0] == "white" { white = rgb }
            }
            if let a = accent, let i = island {
                return (a, i, white ?? "f0edfc")
            }
        }
        return nil
    }

    static func applyTheme(_ theme: ThemeColors, wallpaperName: String = "") {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let ws = "/Users/new/Documents/Antigravity/waybar"
        let themePyCandidates = ["\(home)/.config/theme/theme.py", "\(ws)/theme/theme.py"]
        if let themePy = themePyCandidates.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            let payload: [String: Any] = [
                "accentHex": theme.accentHex,
                "accentLightHex": theme.accentLightHex,
                "accentDimHex": theme.accentDimHex,
                "lilacHex": theme.lilacHex,
                "islandHex": theme.islandHex,
                "textWhiteHex": theme.textWhiteHex,
                "bg1Hex": theme.bg1Hex,
                "bg2Hex": theme.bg2Hex,
                "isArona": theme.isArona,
                "wallpaperName": wallpaperName
            ]
            if let jsonData = try? JSONSerialization.data(withJSONObject: payload, options: []),
               let jsonStr = String(data: jsonData, encoding: .utf8) {
                DispatchQueue.global(qos: .utility).async {
                    let task = Process()
                    task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                    task.arguments = ["python3", themePy, "--apply-dynamic", jsonStr]
                    try? task.run()
                    task.waitUntilExit()
                }
                return
            }
        }

        // Fallback if theme.py is absent
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

            // 3. Update Borders colors via live IPC (without killing yabai-owned daemon)
            let startTask = Process()
            startTask.executableURL = URL(fileURLWithPath: "\(home)/.config/borders/bordersrc")
            try? startTask.run()
            startTask.waitUntilExit()

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
func isDesktopEmpty(for nsRect: NSRect) -> Bool {
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
        "wallpaper_gallery",
        "tg_music",
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
        let x = screen.frame.minX + 16.0
        let y = screen.frame.minY + 12.0 // 12px above bottom edge, bottom-left corner

        setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        pillView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        pillView.needsDisplay = true
    }
}

// ── Desktop Cava Bar Visualizer (Bottom-Center Desktop Layer) ───────────────
class DesktopCavaView: NSView {
    static let rawBarCount = 28
    private var smoothed = [CGFloat](repeating: 0, count: rawBarCount)
    private var targets = [CGFloat](repeating: 0, count: rawBarCount)
    private var energyAlpha: CGFloat = 0.0
    private var silentFrames = 0

    var accentColor: NSColor = NSColor(red: 200/255.0, green: 180/255.0, blue: 250/255.0, alpha: 1.0) {
        didSet { needsDisplay = true }
    }
    var textColor: NSColor = NSColor(red: 240/255.0, green: 237/255.0, blue: 252/255.0, alpha: 1.0) {
        didSet { needsDisplay = true }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func resetLevels() {
        smoothed = [CGFloat](repeating: 0, count: DesktopCavaView.rawBarCount)
        targets = [CGFloat](repeating: 0, count: DesktopCavaView.rawBarCount)
        energyAlpha = 0.0
        silentFrames = 0
        needsDisplay = true
    }

    func pushFrame(_ values: [CGFloat]) {
        guard !values.isEmpty else { return }
        let n = DesktopCavaView.rawBarCount
        var peak: CGFloat = 0
        for i in 0..<n {
            let v = i < values.count ? max(0.0, min(1.0, values[i])) : 0.0
            targets[i] = v
            if v > peak { peak = v }
            let rate: CGFloat = v > smoothed[i] ? 0.58 : 0.28
            smoothed[i] += (v - smoothed[i]) * rate
        }

        if peak > 0.012 {
            silentFrames = 0
            energyAlpha = min(1.0, energyAlpha + 0.18)
        } else {
            silentFrames += 1
            if silentFrames > 36 {
                energyAlpha = max(0.0, energyAlpha - 0.06)
            }
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard energyAlpha > 0.01 else { return }

        let w = bounds.width
        let h = bounds.height
        guard w > 40, h > 8 else { return }

        let n = DesktopCavaView.rawBarCount
        // Symmetrical mirrored cava bars: bass near center, treble tapering to sides
        var mirrored = [CGFloat]()
        mirrored.reserveCapacity(n * 2)
        for i in stride(from: n - 1, through: 0, by: -1) {
            mirrored.append(smoothed[i])
        }
        for i in 0..<n {
            mirrored.append(smoothed[i])
        }

        let barCount = mirrored.count
        let horizontalPad: CGFloat = 6.0
        let usableW = max(20.0, w - horizontalPad * 2.0)
        let pitch = usableW / CGFloat(barCount)
        let barW = max(3.0, min(7.0, floor(pitch * 0.62)))
        let totalBarsW = CGFloat(barCount) * pitch
        let startX = (w - totalBarsW) * 0.5 + (pitch - barW) * 0.5
        let radius = min(barW * 0.48, 3.0)
        let maxH = h - 8.0

        let bottomFill = accentColor.withAlphaComponent(0.38 * energyAlpha)
        let midFill = (textColor.blended(withFraction: 0.45, of: accentColor) ?? accentColor)
            .withAlphaComponent(0.78 * energyAlpha)
        let topFill = textColor.withAlphaComponent(0.95 * energyAlpha)
        let barGradient = NSGradient(colorsAndLocations:
            (bottomFill, 0.0),
            (midFill, 0.55),
            (topFill, 1.0)
        )

        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow()
        glow.shadowColor = accentColor.withAlphaComponent(0.45 * energyAlpha)
        glow.shadowBlurRadius = 6.0
        glow.shadowOffset = .zero
        glow.set()

        for i in 0..<barCount {
            let t = CGFloat(i) / CGFloat(max(1, barCount - 1))
            let edge = min(t, 1.0 - t) / 0.14
            let edgeTaper = edge >= 1.0 ? 1.0 : (0.5 - 0.5 * cos(.pi * max(0.0, edge)))
            let centerBoost = 0.68 + 0.32 * sin(.pi * t)
            let norm = min(1.0, mirrored[i] * centerBoost * edgeTaper)
            let shaped = pow(norm, 0.85)

            let barH = max(2.5, 2.5 + shaped * (maxH - 2.5))
            let x = startX + CGFloat(i) * pitch
            let barRect = NSRect(x: x, y: 1.0, width: barW, height: barH)
            let barPath = NSBezierPath(roundedRect: barRect, xRadius: radius, yRadius: radius)

            if let grad = barGradient {
                grad.draw(in: barPath, angle: 90.0)
            } else {
                topFill.setFill()
                barPath.fill()
            }
        }

        NSGraphicsContext.restoreGraphicsState()
    }
}

class DesktopCavaWindow: NSPanel {
    let cavaView = DesktopCavaView()
    private var cavaProcess: Process?
    private var outputPipe: Pipe?
    private var lineBuffer = Data()
    private var isGalleryOpen = false
    private var isDesktopUncovered = false
    private var isSystemSleeping = false
    private var stopWorkItem: DispatchWorkItem?
    private var restartWorkItem: DispatchWorkItem?
    private var shouldRun: Bool {
        return !isGalleryOpen && isDesktopUncovered && !isSystemSleeping
    }

    private static var confPath: String {
        return "/tmp/wallpaper_desktop_cava.conf"
    }

    init() {
        let initialRect = NSRect(x: 0, y: 0, width: 540, height: 68)
        super.init(
            contentRect: initialRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        alphaValue = 0.0
        level = NSWindow.Level(NSWindow.Level.normal.rawValue - 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        contentView = cavaView
        reposition()
    }

    func reposition() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let width = min(560.0, max(320.0, screen.frame.width * 0.38))
        let height: CGFloat = 66.0
        let x = screen.frame.midX - (width / 2.0)
        let y = screen.frame.minY + 4.0
        setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        cavaView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        cavaView.needsDisplay = true
    }

    func updateColors(accent: NSColor, text: NSColor) {
        cavaView.accentColor = accent
        cavaView.textColor = text
    }

    func setGalleryOpen(_ open: Bool) {
        isGalleryOpen = open
        if open {
            stopWorkItem?.cancel()
            restartWorkItem?.cancel()
            alphaValue = 0.0
            orderOut(nil)
            stopCavaNow()
        } else {
            evaluateState()
        }
    }

    func setSystemSleeping(_ sleeping: Bool) {
        isSystemSleeping = sleeping
        if sleeping {
            stopWorkItem?.cancel()
            restartWorkItem?.cancel()
            alphaValue = 0.0
            stopCavaNow()
        } else {
            evaluateState()
        }
    }

    func setDesktopVisibility(empty: Bool) {
        isDesktopUncovered = empty
        evaluateState()
    }

    private func evaluateState() {
        if shouldRun {
            stopWorkItem?.cancel()
            stopWorkItem = nil
            if !isVisible {
                orderFrontRegardless()
            }
            if abs(alphaValue - 1.0) > 0.05 {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.2
                    self.animator().alphaValue = 1.0
                }
            }
            startCavaIfNeeded()
        } else {
            if abs(alphaValue) > 0.05 {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.18
                    self.animator().alphaValue = 0.0
                }
            }
            // Release cava quickly if gallery opened, or after 1.5s when covered by windows
            if isGalleryOpen || isSystemSleeping {
                stopCavaNow()
            } else if stopWorkItem == nil && cavaProcess != nil {
                let item = DispatchWorkItem { [weak self] in
                    guard let self = self, !self.shouldRun else { return }
                    self.stopCavaNow()
                }
                stopWorkItem = item
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: item)
            }
        }
    }

    private func ensureCavaConfig() {
        let conf = """
        [general]
        bars = \(DesktopCavaView.rawBarCount)
        framerate = 60
        sensitivity = 100

        [input]
        method = coreaudio
        source = "BlackHole 2ch"

        [output]
        method = raw
        channels = mono
        mono_option = average
        raw_target = /dev/stdout
        data_format = ascii
        ascii_max_range = 1000
        bar_delimiter = 59
        frame_delimiter = 10

        [smoothing]
        monstercat = 1
        waves = 0
        noise_reduction = 70
        """
        try? conf.write(toFile: DesktopCavaWindow.confPath, atomically: true, encoding: .utf8)
    }

    private func startCavaIfNeeded() {
        guard shouldRun, cavaProcess == nil else { return }
        let cavaBin = "/opt/homebrew/bin/cava"
        guard FileManager.default.isExecutableFile(atPath: cavaBin) else { return }

        ensureCavaConfig()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: cavaBin)
        proc.arguments = ["-p", DesktopCavaWindow.confPath]

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        lineBuffer.removeAll(keepingCapacity: true)

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self = self else { return }
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            DispatchQueue.main.async {
                self.consumeCavaData(data)
            }
        }

        proc.terminationHandler = { [weak self] finished in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if self.cavaProcess === finished {
                    self.outputPipe?.fileHandleForReading.readabilityHandler = nil
                    self.outputPipe = nil
                    self.cavaProcess = nil
                }
                if self.shouldRun {
                    self.restartWorkItem?.cancel()
                    let item = DispatchWorkItem { [weak self] in
                        self?.startCavaIfNeeded()
                    }
                    self.restartWorkItem = item
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: item)
                }
            }
        }

        do {
            try proc.run()
            cavaProcess = proc
            outputPipe = pipe
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
        }
    }

    private func consumeCavaData(_ chunk: Data) {
        guard shouldRun else { return }
        lineBuffer.append(chunk)
        let newline: UInt8 = 10
        var latestLine: String?
        while let idx = lineBuffer.firstIndex(of: newline) {
            let lineData = lineBuffer.subdata(in: 0..<idx)
            lineBuffer.removeSubrange(0...idx)
            if let s = String(data: lineData, encoding: .ascii), !s.isEmpty {
                latestLine = s
            }
        }
        guard let line = latestLine else { return }
        var vals: [CGFloat] = []
        vals.reserveCapacity(DesktopCavaView.rawBarCount)
        for token in line.split(separator: ";") {
            if let num = Int(token) {
                vals.append(CGFloat(num) / 1000.0)
            }
        }
        if !vals.isEmpty {
            cavaView.pushFrame(vals)
        }
    }

    func stopCavaNow() {
        stopWorkItem?.cancel()
        stopWorkItem = nil
        restartWorkItem?.cancel()
        restartWorkItem = nil
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        outputPipe = nil
        if let proc = cavaProcess, proc.isRunning {
            proc.terminate()
        }
        cavaProcess = nil
        lineBuffer.removeAll(keepingCapacity: false)
        cavaView.resetLevels()
    }
}

// ── Metal Wallpaper Transition Engine (awww-style Desktop Layer) ─────────────
private let kTransitionMetalShader = """
#include <metal_stdlib>
using namespace metal;

struct TransitionUniforms {
    float2 center;
    float progress;
    float aspect;
    float angle;
    float waveAmp;
    float waveFreq;
    float trailSpan;
    int mode;
    int pad0;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut transitionVertex(uint vid [[vertex_id]]) {
    float2 positions[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0)
    };
    float2 uvs[4] = {
        float2(0.0, 1.0),
        float2(1.0, 1.0),
        float2(0.0, 0.0),
        float2(1.0, 0.0)
    };
    VertexOut out;
    out.position = float4(positions[vid], 0.0, 1.0);
    out.uv = uvs[vid];
    return out;
}

fragment float4 transitionFragment(
    VertexOut in [[stage_in]],
    texture2d<float> oldTex [[texture(0)]],
    texture2d<float> newTex [[texture(1)]],
    constant TransitionUniforms& u [[buffer(0)]]
) {
    constexpr sampler s(mag_filter::linear, min_filter::linear, address::clamp_to_edge);
    float4 oldCol = oldTex.sample(s, in.uv);
    float4 newCol = newTex.sample(s, in.uv);

    if (u.progress <= 0.0001) {
        return oldCol;
    }

    // Mode 4: smooth crossfade
    if (u.mode == 4) {
        return mix(oldCol, newCol, clamp(u.progress, 0.0, 1.0));
    }

    float unlock = 0.0;
    if (u.mode == 0 || u.mode == 1) {
        float2 p = float2((in.uv.x - u.center.x) * u.aspect, in.uv.y - u.center.y);
        float d00 = length(float2((0.0 - u.center.x) * u.aspect, 0.0 - u.center.y));
        float d10 = length(float2((1.0 - u.center.x) * u.aspect, 0.0 - u.center.y));
        float d01 = length(float2((0.0 - u.center.x) * u.aspect, 1.0 - u.center.y));
        float d11 = length(float2((1.0 - u.center.x) * u.aspect, 1.0 - u.center.y));
        float maxR = max(max(d00, d10), max(d01, d11));
        float normDist = length(p) / max(maxR, 0.0001);
        unlock = (u.mode == 0) ? (1.0 - normDist) : normDist;
    } else {
        float2 dir = float2(cos(u.angle), sin(u.angle));
        float2 perp = float2(-dir.y, dir.x);
        float2 q = float2((in.uv.x - 0.5) * u.aspect, in.uv.y - 0.5);
        float maxProj = abs(dir.x) * (0.5 * u.aspect) + abs(dir.y) * 0.5;
        float proj = dot(q, dir);
        float waveOffset = (u.mode == 2) ? (u.waveAmp * sin(dot(q, perp) * u.waveFreq)) : 0.0;
        float span = maxProj + ((u.mode == 2) ? u.waveAmp : 0.0);
        unlock = (proj + waveOffset + span) / max(2.0 * span, 0.0001);
    }

    // awww signature 3-step trailing blend bands behind the moving boundary
    float edgeAA = max(fwidth(unlock) * 1.2, 0.002);
    float diff = u.progress - unlock;
    float s1 = smoothstep(0.0001, 0.0001 + edgeAA, diff);
    float s2 = smoothstep(0.333 * u.trailSpan, 0.333 * u.trailSpan + edgeAA, diff);
    float s3 = smoothstep(0.667 * u.trailSpan, 0.667 * u.trailSpan + edgeAA, diff);
    float blend = (s1 + s2 + s3) / 3.0;

    return mix(oldCol, newCol, blend);
}
"""

private struct TransitionUniforms {
    var center: SIMD2<Float>
    var progress: Float
    var aspect: Float
    var angle: Float
    var waveAmp: Float
    var waveFreq: Float
    var trailSpan: Float
    var mode: Int32
    var pad0: Int32 = 0
}

private class MetalTransitionView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func makeBackingLayer() -> CALayer {
        return CAMetalLayer()
    }

    var metalLayer: CAMetalLayer? {
        return layer as? CAMetalLayer
    }
}

private class TransitionWindow: NSWindow {
    let metalView: MetalTransitionView

    init(screen: NSScreen, device: MTLDevice) {
        metalView = MetalTransitionView(frame: NSRect(origin: .zero, size: screen.frame.size))
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = true
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        // Placed strictly above macOS Wallpaper window (desktopWindow) and below icons/windows/bar
        level = NSWindow.Level(Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        contentView = metalView
        if let layer = metalView.metalLayer {
            layer.device = device
            layer.pixelFormat = .bgra8Unorm
            layer.framebufferOnly = true
            layer.isOpaque = true
            layer.displaySyncEnabled = true
            configure(for: screen)
        }
    }

    func configure(for screen: NSScreen) {
        setFrame(screen.frame, display: false)
        metalView.frame = NSRect(origin: .zero, size: screen.frame.size)
        if let layer = metalView.metalLayer {
            let scale = screen.backingScaleFactor
            layer.contentsScale = scale
            layer.drawableSize = CGSize(
                width: max(1, screen.frame.width * scale),
                height: max(1, screen.frame.height * scale)
            )
            layer.colorspace = screen.colorSpace?.cgColorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)
        }
    }
}

class WallpaperTransitionController: NSObject {
    private let device: MTLDevice?
    private let commandQueue: MTLCommandQueue?
    private let pipelineState: MTLRenderPipelineState?
    private let texQueue = DispatchQueue(label: "com.mellvazoa.wallpaper.texloader", qos: .userInitiated)

    private var windows: [TransitionWindow] = []
    private var textureCache: [String: MTLTexture] = [:]
    private var cacheOrder: [String] = []
    private let maxCachedTextures = 4

    private struct ActiveTransition {
        let generation: UInt64
        let style: TransitionStyle
        let duration: Double
        let startTime: CFTimeInterval
        let center: SIMD2<Float>
        let angle: Float
        let oldTextures: [MTLTexture]
        let newTextures: [MTLTexture]
    }

    private var activeTransition: ActiveTransition?
    private var displayLink: CADisplayLink?
    private var generation: UInt64 = 0

    override init() {
        let dev = MTLCreateSystemDefaultDevice()
        self.device = dev
        self.commandQueue = dev?.makeCommandQueue()

        var builtPipeline: MTLRenderPipelineState? = nil
        if let dev = dev {
            do {
                let library = try dev.makeLibrary(source: kTransitionMetalShader, options: nil)
                let desc = MTLRenderPipelineDescriptor()
                desc.vertexFunction = library.makeFunction(name: "transitionVertex")
                desc.fragmentFunction = library.makeFunction(name: "transitionFragment")
                desc.colorAttachments[0].pixelFormat = .bgra8Unorm
                builtPipeline = try dev.makeRenderPipelineState(descriptor: desc)
            } catch {
                NSLog(">>> Metal transition shader compile error: \(error)")
            }
        }
        self.pipelineState = builtPipeline
        super.init()
    }

    var isAvailable: Bool {
        return device != nil && commandQueue != nil && pipelineState != nil
    }

    func prewarm(path: String) {
        guard isAvailable, !path.isEmpty, let screen = NSScreen.main else { return }
        let scale = screen.backingScaleFactor
        let w = max(1, Int(screen.frame.width * scale))
        let h = max(1, Int(screen.frame.height * scale))
        let cs = screen.colorSpace?.cgColorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        texQueue.async { [weak self] in
            _ = self?.loadOrCachedTexture(path: path, width: w, height: h, colorSpace: cs)
        }
    }

    func transition(
        from oldPath: String,
        to newPath: String,
        style: TransitionStyle,
        duration: Double,
        onOverlayReady: @escaping () -> Void
    ) {
        guard isAvailable,
              !oldPath.isEmpty,
              !newPath.isEmpty,
              oldPath != newPath else {
            NSLog(">>> transition skipped: avail=\(isAvailable) old=\(oldPath) new=\(newPath)")
            onOverlayReady()
            return
        }
        NSLog(">>> transition starting: \(style.rawValue) \(duration)s from \(oldPath) -> \(newPath)")

        generation &+= 1
        let currentGen = generation
        stopDisplayLink()

        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            onOverlayReady()
            return
        }

        let resolvedStyle: TransitionStyle = (style == .random)
            ? (TransitionStyle.concreteStyles().randomElement() ?? .outer)
            : style

        let screenParams: [(Int, Int, CGColorSpace, CGRect)] = screens.map { s in
            let scale = s.backingScaleFactor
            let w = max(1, Int(s.frame.width * scale))
            let h = max(1, Int(s.frame.height * scale))
            let cs = s.colorSpace?.cgColorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
            return (w, h, cs, s.frame)
        }

        let mouseLoc = NSEvent.mouseLocation

        texQueue.async { [weak self] in
            guard let self = self else { return }
            var oldTexs: [MTLTexture] = []
            var newTexs: [MTLTexture] = []

            for (w, h, cs, _) in screenParams {
                guard let ot = self.loadOrCachedTexture(path: oldPath, width: w, height: h, colorSpace: cs),
                      let nt = self.loadOrCachedTexture(path: newPath, width: w, height: h, colorSpace: cs) else {
                    DispatchQueue.main.async {
                        if self.generation == currentGen {
                            self.hideWindows()
                            onOverlayReady()
                        }
                    }
                    return
                }
                oldTexs.append(ot)
                newTexs.append(nt)
            }

            DispatchQueue.main.async {
                guard self.generation == currentGen else { return }
                self.beginAnimation(
                    generation: currentGen,
                    screens: screens,
                    style: resolvedStyle,
                    duration: max(0.25, duration),
                    mouseLoc: mouseLoc,
                    oldTextures: oldTexs,
                    newTextures: newTexs,
                    onOverlayReady: onOverlayReady
                )
            }
        }
    }

    private func beginAnimation(
        generation currentGen: UInt64,
        screens: [NSScreen],
        style: TransitionStyle,
        duration: Double,
        mouseLoc: NSPoint,
        oldTextures: [MTLTexture],
        newTextures: [MTLTexture],
        onOverlayReady: @escaping () -> Void
    ) {
        guard let dev = device else {
            onOverlayReady()
            return
        }

        let wasAlreadyVisible = windows.contains { $0.isVisible }

        // Ensure one TransitionWindow per screen
        while windows.count < screens.count {
            windows.append(TransitionWindow(screen: screens[windows.count], device: dev))
        }
        while windows.count > screens.count {
            let extra = windows.removeLast()
            extra.orderOut(nil)
        }
        for (i, screen) in screens.enumerated() {
            windows[i].configure(for: screen)
        }

        let center: SIMD2<Float>
        switch style {
        case .grow:
            if let primary = screens.first, primary.frame.contains(mouseLoc) {
                let nx = Float((mouseLoc.x - primary.frame.minX) / primary.frame.width)
                let ny = Float(1.0 - (mouseLoc.y - primary.frame.minY) / primary.frame.height)
                center = SIMD2<Float>(min(max(nx, 0.05), 0.95), min(max(ny, 0.05), 0.95))
            } else {
                center = SIMD2<Float>(0.5, 0.5)
            }
        case .any:
            center = SIMD2<Float>(Float.random(in: 0.15...0.85), Float.random(in: 0.15...0.85))
        default:
            center = SIMD2<Float>(0.5, 0.5)
        }

        let angle: Float = (style == .wave) ? 0.65 : 0.45

        let state = ActiveTransition(
            generation: currentGen,
            style: style,
            duration: duration,
            startTime: CACurrentMediaTime(),
            center: center,
            angle: angle,
            oldTextures: oldTextures,
            newTextures: newTextures
        )
        activeTransition = state

        // Render frame 0 (100% old image) and bring desktop-level overlay on screen first
        render(state: state, rawProgress: 0.0)
        for win in windows {
            win.orderFrontRegardless()
            NSLog(">>> TransitionWindow ordered front: num=\(win.windowNumber) visible=\(win.isVisible) level=\(win.level.rawValue) frame=\(win.frame)")
        }

        // Wait ~50ms so WindowServer composites old image before macOS swaps desktop wallpaper underneath
        let delay: TimeInterval = wasAlreadyVisible ? 0.01 : 0.05
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, self.generation == currentGen else { return }
            onOverlayReady()

            // Reset startTime right when animation ticks start
            self.activeTransition = ActiveTransition(
                generation: currentGen,
                style: style,
                duration: duration,
                startTime: CACurrentMediaTime(),
                center: center,
                angle: angle,
                oldTextures: oldTextures,
                newTextures: newTextures
            )
            self.startDisplayLink(for: screens.first)
        }
    }

    private func startDisplayLink(for screen: NSScreen?) {
        stopDisplayLink()
        guard let screen = screen ?? NSScreen.main else { return }
        let link = screen.displayLink(target: self, selector: #selector(handleDisplayLink(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func handleDisplayLink(_ link: CADisplayLink) {
        guard let state = activeTransition, state.generation == generation else {
            stopDisplayLink()
            return
        }

        let elapsed = CACurrentMediaTime() - state.startTime
        let rawProgress = min(max(elapsed / state.duration, 0.0), 1.0)
        render(state: state, rawProgress: rawProgress)

        if rawProgress >= 1.0 {
            stopDisplayLink()
            let doneGen = state.generation
            // Hold final 100% new-image frame briefly so NSWorkspace desktop swap settles underneath
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
                guard let self = self, self.generation == doneGen else { return }
                self.activeTransition = nil
                self.hideWindows()
            }
        }
    }

    private func hideWindows() {
        for win in windows {
            win.orderOut(nil)
        }
    }

    private func render(state: ActiveTransition, rawProgress: Double) {
        guard let queue = commandQueue, let pipeline = pipelineState else { return }

        let eased = cubicBezierY(p1x: 0.54, p1y: 0.0, p2x: 0.34, p2y: 0.99, t: rawProgress)
        let trailSpan: Float = 0.14
        let shaderProgress: Float
        if state.style == .fade {
            shaderProgress = Float(eased)
        } else {
            shaderProgress = Float(eased) * (1.0 + trailSpan)
        }

        for (i, win) in windows.enumerated() {
            guard i < state.oldTextures.count,
                  i < state.newTextures.count,
                  let layer = win.metalView.metalLayer,
                  let drawable = layer.nextDrawable(),
                  let cmdBuf = queue.makeCommandBuffer() else {
                continue
            }

            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = drawable.texture
            pass.colorAttachments[0].loadAction = .dontCare
            pass.colorAttachments[0].storeAction = .store

            guard let enc = cmdBuf.makeRenderCommandEncoder(descriptor: pass) else { continue }
            enc.setRenderPipelineState(pipeline)

            let aspect = Float(win.frame.width / max(win.frame.height, 1.0))
            var uniforms = TransitionUniforms(
                center: state.center,
                progress: shaderProgress,
                aspect: aspect,
                angle: state.angle,
                waveAmp: 0.065,
                waveFreq: 14.0,
                trailSpan: trailSpan,
                mode: state.style.shaderMode,
                pad0: 0
            )

            enc.setFragmentTexture(state.oldTextures[i], index: 0)
            enc.setFragmentTexture(state.newTextures[i], index: 1)
            enc.setFragmentBytes(&uniforms, length: MemoryLayout<TransitionUniforms>.stride, index: 0)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            enc.endEncoding()

            cmdBuf.present(drawable)
            cmdBuf.commit()
        }
    }

    // Solve cubic-bezier(p1x, p1y, p2x, p2y) y(t) where x(u) = t
    private func cubicBezierY(p1x: Double, p1y: Double, p2x: Double, p2y: Double, t: Double) -> Double {
        if t <= 0.0 { return 0.0 }
        if t >= 1.0 { return 1.0 }

        func sampleX(_ u: Double) -> Double {
            let inv = 1.0 - u
            return 3.0 * inv * inv * u * p1x + 3.0 * inv * u * u * p2x + u * u * u
        }
        func sampleDX(_ u: Double) -> Double {
            let inv = 1.0 - u
            return 3.0 * inv * inv * p1x + 6.0 * inv * u * (p2x - p1x) + 3.0 * u * u * (1.0 - p2x)
        }
        func sampleY(_ u: Double) -> Double {
            let inv = 1.0 - u
            return 3.0 * inv * inv * u * p1y + 3.0 * inv * u * u * p2y + u * u * u
        }

        var u = t
        for _ in 0..<6 {
            let err = sampleX(u) - t
            let dx = sampleDX(u)
            if abs(err) < 1e-6 || abs(dx) < 1e-6 { break }
            u = min(max(u - err / dx, 0.0), 1.0)
        }
        return min(max(sampleY(u), 0.0), 1.0)
    }

    private func loadOrCachedTexture(path: String, width: Int, height: Int, colorSpace: CGColorSpace) -> MTLTexture? {
        let key = "\(path)|\(width)x\(height)"
        if let hit = textureCache[key] {
            return hit
        }

        guard let dev = device, let img = NSImage(contentsOfFile: path) else { return nil }
        let imgSize = img.size
        guard imgSize.width > 0, imgSize.height > 0 else { return nil }

        let bytesPerRow = width * 4
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ), let data = ctx.data else {
            return nil
        }

        // Exact aspect-fill ("Fill Screen") matching NSWorkspace.setDesktopImageURL
        let scale = max(CGFloat(width) / imgSize.width, CGFloat(height) / imgSize.height)
        let drawW = imgSize.width * scale
        let drawH = imgSize.height * scale
        let drawRect = NSRect(
            x: (CGFloat(width) - drawW) / 2.0,
            y: (CGFloat(height) - drawH) / 2.0,
            width: drawW,
            height: drawH
        )

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        img.draw(in: drawRect, from: .zero, operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        let texDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        texDesc.usage = [.shaderRead]
        guard let tex = dev.makeTexture(descriptor: texDesc) else { return nil }

        tex.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: data,
            bytesPerRow: bytesPerRow
        )

        textureCache[key] = tex
        cacheOrder.removeAll { $0 == key }
        cacheOrder.append(key)
        while cacheOrder.count > maxCachedTextures {
            let oldest = cacheOrder.removeFirst()
            textureCache.removeValue(forKey: oldest)
        }

        return tex
    }
}

// ── Coverflow Modal Gallery Window ───────────────────────────────────────────
class GalleryWindow: NSPanel, WKScriptMessageHandler, WKNavigationDelegate {
    var webView: WKWebView!
    var onWallpaperSelected: ((String, String) -> Void)?
    var onClose: (() -> Void)?
    var isHTMLLoaded = false
    var currentThemeTuple: (accentHex: String, islandHex: String, textHex: String)?

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

    func applyTheme(accentHex: String, islandHex: String, textHex: String) {
        currentThemeTuple = (accentHex, islandHex, textHex)
        guard isHTMLLoaded else { return }
        let js = "if (window.setTheme) { window.setTheme('#\(accentHex)', '#\(islandHex)', '#\(textHex)'); }"
        DispatchQueue.main.async { [weak self] in
            self?.webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    func syncThemeFromDisk() {
        if let active = ThemeExtractor.currentActivePalette() {
            applyTheme(accentHex: active.accentHex, islandHex: active.islandHex, textHex: active.textHex)
        } else if let stored = currentThemeTuple {
            applyTheme(accentHex: stored.accentHex, islandHex: stored.islandHex, textHex: stored.textHex)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isHTMLLoaded = true
        syncThemeFromDisk()
        if isVisible && alphaValue > 0.5 {
            injectWallpapers()
        }
    }

    func injectWallpapers() {
        let items = WallpaperScanner.scan()
        let currentPath = AppDelegate.shared?.activeWallpaperPath.isEmpty == false
            ? AppDelegate.shared!.activeWallpaperPath
            : WallpaperScanner.currentWallpaperPath()
        let settings = AppDelegate.shared?.transitionSettings ?? TransitionSettings.defaultSettings
        if let jsonData = try? JSONEncoder().encode(items),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            let escapedPath = currentPath.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
            let js = """
            if (window.loadWallpapers) { window.loadWallpapers(\(jsonString), '\(escapedPath)'); }
            if (window.setTransitionConfig) { window.setTransitionConfig('\(settings.style)', \(settings.duration)); }
            """
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

        syncThemeFromDisk()
        injectWallpapers()
        webView.evaluateJavaScript("window.focus();", completionHandler: nil)

        // Hide desktop bottom pill and stop desktop cava while gallery is open!
        AppDelegate.shared?.pillWindow.setDesktopVisibility(empty: false)
        AppDelegate.shared?.cavaWindow.setGalleryOpen(true)
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

        // Restore desktop bottom pill & desktop cava check
        AppDelegate.shared?.cavaWindow.setGalleryOpen(false)
        AppDelegate.shared?.checkDesktopState()
    }

    // WKScriptMessageHandler
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String else { return }
        NSLog(">>> WebKit bridge message: \(action)")

        if action == "ready" {
            isHTMLLoaded = true
            syncThemeFromDisk()
            if isVisible && alphaValue > 0.5 {
                injectWallpapers()
            }
        } else if action == "apply" || action == "select" {
            let path = body["path"] as? String ?? ""
            let name = body["name"] as? String ?? ""
            onWallpaperSelected?(path, name)
            // Keep gallery open so user sees desktop update in real time!
        } else if action == "setTransition" {
            let style = body["style"] as? String
            let duration = body["duration"] as? Double
            AppDelegate.shared?.updateTransitionSettings(style: style, duration: duration)
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
    var cavaWindow: DesktopCavaWindow!
    var galleryWindow: GalleryWindow!
    var transitionController: WallpaperTransitionController!
    var transitionSettings: TransitionSettings = TransitionSettings.load()
    var activeWallpaperPath: String = ""
    var stateTimer: Timer?
    var sig1Source: DispatchSourceSignal?
    var sig2Source: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        NSApp.setActivationPolicy(.accessory) // No dock icon when running in background

        pillWindow = BottomPillWindow()
        cavaWindow = DesktopCavaWindow()
        galleryWindow = GalleryWindow()
        transitionController = WallpaperTransitionController()

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

        // Listen for screen resize/resolution changes
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.pillWindow.reposition()
            self?.cavaWindow.reposition()
        }

        // Listen for space change, app activation, and sleep/wake events
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
        wsCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.cavaWindow.setSystemSleeping(true)
        }
        wsCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.cavaWindow.setSystemSleeping(false)
            self?.checkDesktopState()
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

        // Initialize colors & prewarm GPU texture from active system theme / current wallpaper
        let currentPath = WallpaperScanner.currentWallpaperPath()
        let currentName = WallpaperScanner.currentWallpaperName()
        activeWallpaperPath = currentPath
        if !currentPath.isEmpty {
            transitionController.prewarm(path: currentPath)
            if ThemeExtractor.isPresetLocked(), let active = ThemeExtractor.currentActivePalette() {
                if let accent = ThemeExtractor.colorFromHex(active.accentHex),
                   let island = ThemeExtractor.colorFromHex(active.islandHex) {
                    pillWindow.updateColors(accent: accent, island: island)
                    let textCol = ThemeExtractor.colorFromHex(active.textHex) ?? .white
                    cavaWindow.updateColors(accent: accent, text: textCol)
                }
                galleryWindow.applyTheme(accentHex: active.accentHex, islandHex: active.islandHex, textHex: active.textHex)
            } else {
                let theme = ThemeExtractor.extract(from: currentPath, name: currentName)
                pillWindow.updateColors(accent: theme.accentNSColor, island: theme.islandNSColor)
                let textCol = ThemeExtractor.colorFromHex(theme.textWhiteHex) ?? .white
                cavaWindow.updateColors(accent: theme.accentNSColor, text: textCol)
                galleryWindow.applyTheme(accentHex: theme.accentHex, islandHex: theme.islandHex, textHex: theme.textWhiteHex)
                ThemeExtractor.applyTheme(theme, wallpaperName: currentName)
                syncLockscreen(path: currentPath, name: currentName, theme: theme)
            }
        } else {
            if let active = ThemeExtractor.currentActivePalette(),
               let accent = ThemeExtractor.colorFromHex(active.accentHex) {
                let textCol = ThemeExtractor.colorFromHex(active.textHex) ?? .white
                cavaWindow.updateColors(accent: accent, text: textCol)
            }
            galleryWindow.syncThemeFromDisk()
        }

        // Listen for IPC Notifications (e.g. from hotkeys / skhd / CLI --set)
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

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleSetWallpaperNotification(_:)),
            name: kSetWallpaperNotification,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleApplyThemeNotification(_:)),
            name: kApplyThemeNotification,
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

    func applicationWillTerminate(_ notification: Notification) {
        cavaWindow?.stopCavaNow()
    }

    @objc func checkDesktopState() {
        // If gallery window is open, never show the bottom pill or desktop cava
        if galleryWindow.isVisible && galleryWindow.alphaValue > 0.4 {
            pillWindow.setDesktopVisibility(empty: false)
            cavaWindow.setGalleryOpen(true)
            return
        }
        pillWindow.setDesktopVisibility(empty: isDesktopEmpty(for: pillWindow.frame))
        cavaWindow.setDesktopVisibility(empty: isDesktopEmpty(for: cavaWindow.frame))
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

    @objc func handleSetWallpaperNotification(_ notification: Notification) {
        let info = notification.userInfo
        let path = (info?["path"] as? String) ?? ""
        let styleStr = info?["style"] as? String
        let durationVal = info?["duration"] as? Double

        DispatchQueue.main.async {
            if let s = styleStr, TransitionStyle(rawValue: s) != nil {
                self.updateTransitionSettings(style: s, duration: durationVal)
            } else if let d = durationVal {
                self.updateTransitionSettings(style: nil, duration: d)
            }

            if !path.isEmpty && FileManager.default.fileExists(atPath: path) {
                let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                let styleOverride = styleStr.flatMap { TransitionStyle(rawValue: $0) }
                self.applyWallpaper(path: path, name: name, styleOverride: styleOverride, durationOverride: durationVal)
            }
        }
    }

    @objc func handleApplyThemeNotification(_ notification: Notification) {
        let info = notification.userInfo
        let accentHex = (info?["accentHex"] as? String) ?? "c8b4fa"
        let islandHex = (info?["islandHex"] as? String) ?? "14172f"
        let fgHex = (info?["fgHex"] as? String) ?? "f0edfc"

        DispatchQueue.main.async {
            if let accent = ThemeExtractor.colorFromHex(accentHex),
               let island = ThemeExtractor.colorFromHex(islandHex) {
                self.pillWindow.updateColors(accent: accent, island: island)
                let textCol = ThemeExtractor.colorFromHex(fgHex) ?? .white
                self.cavaWindow.updateColors(accent: accent, text: textCol)
            }
            self.galleryWindow.applyTheme(accentHex: accentHex, islandHex: islandHex, textHex: fgHex)
        }
    }

    func updateTransitionSettings(style: String?, duration: Double?) {
        if let s = style, TransitionStyle(rawValue: s) != nil {
            transitionSettings.style = s
        }
        if let d = duration {
            transitionSettings.duration = max(0.25, min(3.0, d))
        }
        transitionSettings.save()
    }

    func toggleGallery() {
        NSLog(">>> toggleGallery() called. isVisible: \(galleryWindow.isVisible), alpha: \(galleryWindow.alphaValue)")
        if galleryWindow.isVisible && galleryWindow.alphaValue > 0.5 {
            galleryWindow.close()
        } else {
            galleryWindow.open()
        }
    }

    private func setSystemDesktopWallpaper(path: String) {
        let fileURL = URL(fileURLWithPath: path)
        for screen in NSScreen.screens {
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
    }

    func applyWallpaper(
        path: String,
        name: String,
        styleOverride: TransitionStyle? = nil,
        durationOverride: Double? = nil
    ) {
        let oldPath = activeWallpaperPath.isEmpty ? WallpaperScanner.currentWallpaperPath() : activeWallpaperPath
        activeWallpaperPath = path

        let style = styleOverride ?? TransitionStyle(rawValue: transitionSettings.style) ?? .outer
        let duration = durationOverride ?? transitionSettings.duration

        if !oldPath.isEmpty && oldPath != path && transitionController.isAvailable {
            transitionController.transition(
                from: oldPath,
                to: path,
                style: style,
                duration: duration
            ) { [weak self] in
                self?.setSystemDesktopWallpaper(path: path)
            }
        } else {
            setSystemDesktopWallpaper(path: path)
        }

        // Dynamic theme extraction & Sketchybar reload
        let theme = ThemeExtractor.extract(from: path, name: name)
        ThemeExtractor.applyTheme(theme, wallpaperName: name)

        if !ThemeExtractor.isPresetLocked() {
            pillWindow.updateColors(accent: theme.accentNSColor, island: theme.islandNSColor)
            let textCol = ThemeExtractor.colorFromHex(theme.textWhiteHex) ?? .white
            cavaWindow.updateColors(accent: theme.accentNSColor, text: textCol)
            galleryWindow.applyTheme(accentHex: theme.accentHex, islandHex: theme.islandHex, textHex: theme.textWhiteHex)
        } else {
            galleryWindow.syncThemeFromDisk()
        }
        pillWindow.updatePill(title: name)

        // Sync native macOS lockscreen image & custom lockscreen theme
        syncLockscreen(path: path, name: name, theme: theme)
    }

    func syncLockscreen(path: String, name: String, theme: ThemeColors) {
        DispatchQueue.global(qos: .utility).async {
            // 1. Native macOS lockscreen cache
            let lockDir = "/Library/Caches/Desktop Pictures/37579F49-0F5B-4592-BA52-74FAED6783F2"
            let lockFile = "\(lockDir)/lockscreen.png"
            if FileManager.default.fileExists(atPath: lockDir) {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
                p.arguments = ["-s", "format", "png", path, "--out", lockFile]
                try? p.run()
            }

            // 2. Custom Lockscreen theme state
            let configDir = "/Users/new/.config/lockscreen"
            try? FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)
            let jsonPath = "\(configDir)/current_theme.json"
            var themeJson: [String: Any] = [:]
            if let existingData = try? Data(contentsOf: URL(fileURLWithPath: jsonPath)),
               let existingDict = try? JSONSerialization.jsonObject(with: existingData) as? [String: Any] {
                themeJson = existingDict
            }
            if !ThemeExtractor.isPresetLocked() {
                themeJson["accentHex"] = theme.accentHex
                themeJson["islandHex"] = theme.islandHex
                themeJson["textWhiteHex"] = theme.textWhiteHex
            }
            themeJson["wallpaperPath"] = path
            themeJson["wallpaperName"] = name
            if let data = try? JSONSerialization.data(withJSONObject: themeJson, options: .prettyPrinted) {
                try? data.write(to: URL(fileURLWithPath: jsonPath))
            }
        }
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

if CommandLine.arguments.contains("--set") || CommandLine.arguments.contains("--transition") || CommandLine.arguments.contains("--duration") {
    func argValue(for flag: String) -> String? {
        guard let idx = CommandLine.arguments.firstIndex(of: flag), idx + 1 < CommandLine.arguments.count else {
            return nil
        }
        return CommandLine.arguments[idx + 1]
    }

    var userInfo: [AnyHashable: Any] = [:]
    if let p = argValue(for: "--set") {
        let absPath = URL(fileURLWithPath: (p as NSString).expandingTildeInPath).resolvingSymlinksInPath().path
        userInfo["path"] = absPath
    }
    if let t = argValue(for: "--transition") {
        userInfo["style"] = t
    }
    if let dStr = argValue(for: "--duration"), let d = Double(dStr) {
        userInfo["duration"] = d
    }

    DistributedNotificationCenter.default().postNotificationName(
        kSetWallpaperNotification,
        object: nil,
        userInfo: userInfo,
        deliverImmediately: true
    )
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    exit(0)
}

if let idx = CommandLine.arguments.firstIndex(of: "--theme"), idx + 3 < CommandLine.arguments.count {
    let userInfo: [AnyHashable: Any] = [
        "accentHex": CommandLine.arguments[idx + 1],
        "islandHex": CommandLine.arguments[idx + 2],
        "fgHex": CommandLine.arguments[idx + 3]
    ]
    DistributedNotificationCenter.default().postNotificationName(
        kApplyThemeNotification,
        object: nil,
        userInfo: userInfo,
        deliverImmediately: true
    )
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    exit(0)
}

if CommandLine.arguments.contains("--help") {
    print("""
    Wallpaper Gallery & Bottom Pill Widget for macOS
    Usage:
      wallpaper_gallery                               Run the background daemon (pill + gallery)
      wallpaper_gallery --toggle                      Toggle the Coverflow gallery
      wallpaper_gallery --open                        Open the Coverflow gallery
      wallpaper_gallery --set <path> [--transition <style>] [--duration <sec>]
                                                      Apply wallpaper with animated transition
      wallpaper_gallery --transition <style>          Set transition style (outer, grow, wave, wipe, center, any, fade, random)
      wallpaper_gallery --help                        Show this help message
    """)
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
