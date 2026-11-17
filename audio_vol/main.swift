import AppKit
import AudioToolbox
import CoreAudio
import Foundation
import QuartzCore

// MARK: - CoreAudio Helpers

private func getDevicePropertySize(_ device: AudioObjectID, selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> UInt32 {
    var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    var size: UInt32 = 0
    guard AudioObjectHasProperty(device, &addr) else { return 0 }
    let st = AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size)
    return st == noErr ? size : 0
}

private func getStringProp(_ obj: AudioObjectID, selector: AudioObjectPropertySelector) -> String? {
    var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    guard AudioObjectHasProperty(obj, &addr) else { return nil }
    var size = UInt32(MemoryLayout<CFString>.size)
    var cfStr: Unmanaged<CFString>?
    let st = AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, &cfStr)
    if st == noErr, let cfStr {
        return cfStr.takeRetainedValue() as String
    }
    return nil
}

private func getUInt32Prop(_ obj: AudioObjectID, selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> UInt32? {
    var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    guard AudioObjectHasProperty(obj, &addr) else { return nil }
    var val: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    let st = AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, &val)
    return st == noErr ? val : nil
}

private func allAudioDevices() -> [AudioDeviceID] {
    let sys = AudioObjectID(kAudioObjectSystemObject)
    let size = getDevicePropertySize(sys, selector: kAudioHardwarePropertyDevices)
    guard size > 0 else { return [] }
    let count = Int(size) / MemoryLayout<AudioDeviceID>.size
    var devs = [AudioDeviceID](repeating: 0, count: count)
    var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var actual = size
    guard AudioObjectGetPropertyData(sys, &addr, 0, nil, &actual, &devs) == noErr else { return [] }
    return devs
}

private func hasOutputStreams(_ dev: AudioDeviceID) -> Bool {
    return getDevicePropertySize(dev, selector: kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput) > 0
}

private func defaultOutputDevice() -> AudioDeviceID {
    var dev: AudioDeviceID = 0
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev)
    return dev
}

private func setDefaultOutputDevice(_ dev: AudioDeviceID) -> Bool {
    var id = dev
    let size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    return AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, size, &id) == noErr
}

private func isVirtualDevice(_ dev: AudioDeviceID) -> Bool {
    if let tr = getUInt32Prop(dev, selector: kAudioDevicePropertyTransportType),
       tr == kAudioDeviceTransportTypeVirtual {
        return true
    }
    let uid = getStringProp(dev, selector: kAudioDevicePropertyDeviceUID) ?? ""
    return uid.localizedCaseInsensitiveContains("BlackHole")
}

private func isAggregateDevice(_ dev: AudioDeviceID) -> Bool {
    if let tr = getUInt32Prop(dev, selector: kAudioDevicePropertyTransportType),
       tr == kAudioDeviceTransportTypeAggregate {
        return true
    }
    return getDevicePropertySize(dev, selector: kAudioAggregateDevicePropertyActiveSubDeviceList) > 0
}

private func activeSubDevices(_ dev: AudioDeviceID) -> [AudioDeviceID] {
    let size = getDevicePropertySize(dev, selector: kAudioAggregateDevicePropertyActiveSubDeviceList)
    guard size > 0 else { return [] }
    let count = Int(size) / MemoryLayout<AudioDeviceID>.size
    var subs = [AudioDeviceID](repeating: 0, count: count)
    var addr = AudioObjectPropertyAddress(mSelector: kAudioAggregateDevicePropertyActiveSubDeviceList, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var actual = size
    guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &actual, &subs) == noErr else { return [] }
    return subs
}

private func hasSettableVirtualMainVolume(_ dev: AudioDeviceID) -> Bool {
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    guard AudioObjectHasProperty(dev, &addr) else { return false }
    var settable: DarwinBoolean = false
    return AudioObjectIsPropertySettable(dev, &addr, &settable) == noErr && settable.boolValue
}

private func hasSettableScalarVolume(_ dev: AudioDeviceID, element: AudioObjectPropertyElement) -> Bool {
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyVolumeScalar,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: element
    )
    guard AudioObjectHasProperty(dev, &addr) else { return false }
    var settable: DarwinBoolean = false
    return AudioObjectIsPropertySettable(dev, &addr, &settable) == noErr && settable.boolValue
}

private func supportsVolumeControl(_ dev: AudioDeviceID) -> Bool {
    if hasSettableVirtualMainVolume(dev) { return true }
    return hasSettableScalarVolume(dev, element: 0) || hasSettableScalarVolume(dev, element: 1)
}

private func readVolumeScalar(_ dev: AudioDeviceID) -> Float32? {
    var val: Float32 = 0
    var size = UInt32(MemoryLayout<Float32>.size)
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput,
        mElement: kAudioObjectPropertyElementMain
    )
    if AudioObjectHasProperty(dev, &addr),
       AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &val) == noErr {
        return val
    }
    for elem: UInt32 in [0, 1, 2] {
        addr.mSelector = kAudioDevicePropertyVolumeScalar
        addr.mElement = elem
        if AudioObjectHasProperty(dev, &addr),
           AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &val) == noErr {
            return val
        }
    }
    return nil
}

@discardableResult
private func writeVolumeScalar(_ dev: AudioDeviceID, value: Float32) -> Bool {
    var clamped = max(0.0, min(1.0, value))
    let size = UInt32(MemoryLayout<Float32>.size)
    if hasSettableVirtualMainVolume(dev) {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        if AudioObjectSetPropertyData(dev, &addr, 0, nil, size, &clamped) == noErr {
            return true
        }
    }
    var ok = false
    for elem: UInt32 in [0, 1, 2] where hasSettableScalarVolume(dev, element: elem) {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: elem
        )
        if AudioObjectSetPropertyData(dev, &addr, 0, nil, size, &clamped) == noErr {
            ok = true
        }
    }
    return ok
}

private func readMute(_ dev: AudioDeviceID) -> Bool {
    for elem: UInt32 in [0, 1] {
        if let m = getUInt32Prop(dev, selector: kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput, element: elem) {
            return m != 0
        }
    }
    return false
}

@discardableResult
private func writeMute(_ dev: AudioDeviceID, muted: Bool) -> Bool {
    var val: UInt32 = muted ? 1 : 0
    let size = UInt32(MemoryLayout<UInt32>.size)
    for elem: UInt32 in [0, 1] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: elem
        )
        var settable: DarwinBoolean = false
        if AudioObjectHasProperty(dev, &addr),
           AudioObjectIsPropertySettable(dev, &addr, &settable) == noErr,
           settable.boolValue {
            if AudioObjectSetPropertyData(dev, &addr, 0, nil, size, &val) == noErr {
                return true
            }
        }
    }
    return false
}

/// Resolves which real hardware device(s) should be adjusted when controlling output volume.
/// For a Multi-Output / Aggregate device, skips virtual loopback devices (e.g. BlackHole 2ch)
/// so cava keeps full digital signal while physical speakers change volume cleanly.
private func resolveTargetDevices(for outputDev: AudioDeviceID) -> [AudioDeviceID] {
    if !isAggregateDevice(outputDev) && supportsVolumeControl(outputDev) {
        return [outputDev]
    }
    let subs = activeSubDevices(outputDev)
    let physical = subs.filter { !isVirtualDevice($0) && supportsVolumeControl($0) }
    if !physical.isEmpty {
        return physical
    }
    if supportsVolumeControl(outputDev) {
        return [outputDev]
    }
    return subs.filter { supportsVolumeControl($0) }
}

/// Ensures virtual loopback sub-devices (like BlackHole 2ch) inside an aggregate output stay at
/// 100% unmuted digital gain so cava visualizers receive consistent full-scale audio.
private func ensureLoopbackFullScale(in outputDev: AudioDeviceID) {
    guard isAggregateDevice(outputDev) else { return }
    for sub in activeSubDevices(outputDev) where isVirtualDevice(sub) {
        if let cur = readVolumeScalar(sub), cur < 0.99 {
            writeVolumeScalar(sub, value: 1.0)
        }
        if readMute(sub) {
            writeMute(sub, muted: false)
        }
    }
}

private struct AudioState {
    let percent: Int
    let muted: Bool
    let deviceName: String
    let isAggregate: Bool
}

private func currentAudioState() -> AudioState {
    let out = defaultOutputDevice()
    let outName = getStringProp(out, selector: kAudioObjectPropertyName) ?? "Audio"
    let targets = resolveTargetDevices(for: out)
    let target = targets.first ?? out
    let vol = readVolumeScalar(target) ?? 0
    let muted = readMute(target)
    let pct = max(0, min(100, Int((Double(vol) * 100.0).rounded())))
    let displayName: String
    if isAggregateDevice(out), let physName = getStringProp(target, selector: kAudioObjectPropertyName) {
        displayName = "\(physName) + Cava"
    } else {
        displayName = outName
    }
    return AudioState(percent: pct, muted: muted, deviceName: displayName, isAggregate: isAggregateDevice(out))
}

private func triggerSketchybar(_ state: AudioState) {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/sketchybar")
    task.arguments = [
        "--trigger", "volume_change",
        "INFO=\(state.percent)",
        "MUTED=\(state.muted ? 1 : 0)",
        "DEVICE=\(state.deviceName)"
    ]
    task.standardOutput = FileHandle.nullDevice
    task.standardError = FileHandle.nullDevice
    try? task.run()
}

// MARK: - Device Listing & Switching

private struct OutputDeviceEntry {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let isCurrent: Bool
    let score: Int
}

private func listOutputDevices() -> [OutputDeviceEntry] {
    let cur = defaultOutputDevice()
    var raw: [OutputDeviceEntry] = []
    for dev in allAudioDevices() where hasOutputStreams(dev) {
        let uid = getStringProp(dev, selector: kAudioDevicePropertyDeviceUID) ?? "\(dev)"
        let name = getStringProp(dev, selector: kAudioObjectPropertyName) ?? "Device \(dev)"
        let subs = activeSubDevices(dev)
        // Prefer aggregate devices whose first subdevice is physical (hardware clock master)
        let firstIsPhysical = subs.first.map { !isVirtualDevice($0) } ?? true
        let score = (dev == cur ? 100 : 0) + (firstIsPhysical ? 10 : 0)
        raw.append(OutputDeviceEntry(id: dev, uid: uid, name: name, isCurrent: dev == cur, score: score))
    }

    // Deduplicate identical aggregate device names (e.g. multiple "Многовыходное устройство")
    // while keeping the currently active or hardware-clocked primary one.
    var byKey: [String: OutputDeviceEntry] = [:]
    var order: [String] = []
    for item in raw {
        let key = isAggregateDevice(item.id) ? "agg:\(item.name)" : "uid:\(item.uid)"
        if let existing = byKey[key] {
            if item.score > existing.score {
                byKey[key] = OutputDeviceEntry(
                    id: item.id,
                    uid: item.uid,
                    name: item.name,
                    isCurrent: existing.isCurrent || item.isCurrent,
                    score: item.score
                )
            }
        } else {
            byKey[key] = item
            order.append(key)
        }
    }
    return order.compactMap { byKey[$0] }
}

private func selectDevice(query: String) -> Bool {
    let devs = allAudioDevices().filter { hasOutputStreams($0) }
    if let exactUID = devs.first(where: { getStringProp($0, selector: kAudioDevicePropertyDeviceUID) == query }) {
        guard setDefaultOutputDevice(exactUID) else { return false }
        ensureLoopbackFullScale(in: exactUID)
        return true
    }
    // Fallback to matching deduplicated list by name
    let deduped = listOutputDevices()
    if let match = deduped.first(where: { $0.name == query }) {
        guard setDefaultOutputDevice(match.id) else { return false }
        ensureLoopbackFullScale(in: match.id)
        return true
    }
    return false
}

// MARK: - Dynamic Palette from Sketchybar colors.lua

private struct ThemePalette {
    var bg: NSColor = NSColor(srgbRed: 0.125, green: 0.071, blue: 0.071, alpha: 0.90)
    var border: NSColor = NSColor(srgbRed: 0.980, green: 0.553, blue: 0.537, alpha: 0.45)
    var accent: NSColor = NSColor(srgbRed: 0.980, green: 0.553, blue: 0.537, alpha: 1.0)
    var text: NSColor = NSColor(srgbRed: 0.965, green: 0.953, blue: 0.949, alpha: 1.0)
    var track: NSColor = NSColor(srgbRed: 0.255, green: 0.145, blue: 0.141, alpha: 1.0)
    var muted: NSColor = NSColor(srgbRed: 0.969, green: 0.290, blue: 0.267, alpha: 1.0)
}

private func parseLuaHexColor(_ hex: String, overrideAlpha: CGFloat? = nil) -> NSColor? {
    var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if cleaned.hasPrefix("0x") || cleaned.hasPrefix("0X") {
        cleaned = String(cleaned.dropFirst(2))
    }
    guard cleaned.count == 8, let argb = UInt32(cleaned, radix: 16) else { return nil }
    let a = overrideAlpha ?? (CGFloat((argb >> 24) & 0xff) / 255.0)
    let r = CGFloat((argb >> 16) & 0xff) / 255.0
    let g = CGFloat((argb >> 8) & 0xff) / 255.0
    let b = CGFloat(argb & 0xff) / 255.0
    return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}

private func loadThemePalette() -> ThemePalette {
    var palette = ThemePalette()
    let path = NSString(string: "~/.config/sketchybar/colors.lua").expandingTildeInPath
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return palette }
    for rawLine in text.split(separator: "\n") {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2 else { continue }
        let key = parts[0]
        let val = parts[1].replacingOccurrences(of: ",", with: "")
        switch key {
        case "island":
            if let c = parseLuaHexColor(val, overrideAlpha: 0.92) { palette.bg = c }
        case "lavender":
            if let c = parseLuaHexColor(val) {
                palette.accent = c
                palette.border = c.withAlphaComponent(0.45)
            }
        case "white":
            if let c = parseLuaHexColor(val) { palette.text = c }
        case "bg2":
            if let c = parseLuaHexColor(val) { palette.track = c }
        case "red":
            if let c = parseLuaHexColor(val) { palette.muted = c }
        default:
            break
        }
    }
    return palette
}

// MARK: - Lightweight Volume OSD Daemon

private let osdSocketPath = "/tmp/audio_vol_osd.sock"

private func sendOSDUpdate(_ state: AudioState) -> Bool {
    let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return false }
    defer { Darwin.close(fd) }

    var tv = timeval(tv_sec: 0, tv_usec: 100_000)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(osdSocketPath.utf8)
    guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return false }
    withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
        ptr.withMemoryRebound(to: UInt8.self, capacity: bytes.count + 1) { dst in
            for (i, b) in bytes.enumerated() { dst[i] = b }
            dst[bytes.count] = 0
        }
    }

    let len = socklen_t(MemoryLayout<sockaddr_un>.size)
    let conn = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, len) }
    }
    guard conn == 0 else { return false }

    let payload = "\(state.percent)|\(state.muted ? 1 : 0)|\(state.deviceName)\n"
    let ok = payload.withCString { cstr in
        let n = strlen(cstr)
        return Darwin.send(fd, cstr, n, 0) == n
    }
    return ok
}

private func spawnOSDDaemon(initial state: AudioState) {
    let exe = ProcessInfo.processInfo.arguments[0]
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: exe)
    proc.arguments = ["--osd-daemon", "\(state.percent)|\(state.muted ? 1 : 0)|\(state.deviceName)"]
    proc.standardInput = FileHandle.nullDevice
    proc.standardOutput = FileHandle.nullDevice
    proc.standardError = FileHandle.nullDevice
    try? proc.run()
}

private func showOSD(_ state: AudioState) {
    if !sendOSDUpdate(state) {
        spawnOSDDaemon(initial: state)
    }
}

private final class VolumeHUDPanel: NSPanel {
    private let palette = loadThemePalette()
    private let iconView = NSImageView()
    private let pctLabel = NSTextField(labelWithString: "0%")
    private let devLabel = NSTextField(labelWithString: "")
    private let barBg = NSView()
    private let barFill = NSView()
    private var barFillWidthConstraint: NSLayoutConstraint!
    private var hideTimer: Timer?
    private var exitTimer: Timer?

    init() {
        let w: CGFloat = 292
        let h: CGFloat = 62
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: w, height: h),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]

        let root = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        root.wantsLayer = true
        root.layer?.backgroundColor = palette.bg.cgColor
        root.layer?.cornerRadius = 16
        root.layer?.borderWidth = 1.25
        root.layer?.borderColor = palette.border.cgColor
        contentView = root

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
        iconView.contentTintColor = palette.accent

        pctLabel.translatesAutoresizingMaskIntoConstraints = false
        pctLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .bold)
        pctLabel.textColor = palette.text
        pctLabel.alignment = .right

        devLabel.translatesAutoresizingMaskIntoConstraints = false
        devLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        devLabel.textColor = palette.text.withAlphaComponent(0.72)
        devLabel.lineBreakMode = .byTruncatingTail

        barBg.translatesAutoresizingMaskIntoConstraints = false
        barBg.wantsLayer = true
        barBg.layer?.backgroundColor = palette.track.cgColor
        barBg.layer?.cornerRadius = 3.5

        barFill.translatesAutoresizingMaskIntoConstraints = false
        barFill.wantsLayer = true
        barFill.layer?.backgroundColor = palette.accent.cgColor
        barFill.layer?.cornerRadius = 3.5

        barBg.addSubview(barFill)
        root.addSubview(iconView)
        root.addSubview(devLabel)
        root.addSubview(pctLabel)
        root.addSubview(barBg)

        barFillWidthConstraint = barFill.widthAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),

            devLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            devLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            devLabel.trailingAnchor.constraint(lessThanOrEqualTo: pctLabel.leadingAnchor, constant: -8),

            pctLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            pctLabel.centerYAnchor.constraint(equalTo: devLabel.centerYAnchor),
            pctLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 40),

            barBg.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            barBg.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            barBg.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14),
            barBg.heightAnchor.constraint(equalToConstant: 7),

            barFill.leadingAnchor.constraint(equalTo: barBg.leadingAnchor),
            barFill.topAnchor.constraint(equalTo: barBg.topAnchor),
            barFill.bottomAnchor.constraint(equalTo: barBg.bottomAnchor),
            barFillWidthConstraint,
        ])
    }

    func update(percent: Int, muted: Bool, device: String) {
        let activePct = muted ? 0 : max(0, min(100, percent))
        let symbolName: String
        if muted || activePct == 0 {
            symbolName = "speaker.slash.fill"
        } else if activePct <= 33 {
            symbolName = "speaker.wave.1.fill"
        } else if activePct <= 66 {
            symbolName = "speaker.wave.2.fill"
        } else {
            symbolName = "speaker.wave.3.fill"
        }

        iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        iconView.contentTintColor = muted ? palette.muted : palette.accent
        barFill.layer?.backgroundColor = (muted ? palette.muted : palette.accent).cgColor
        pctLabel.stringValue = muted ? "MUTE" : "\(percent)%"
        devLabel.stringValue = device

        let maxTrackW = barBg.bounds.width > 0 ? barBg.bounds.width : ((contentView?.bounds.width ?? 292) - 66)
        let targetW = maxTrackW * CGFloat(activePct) / 100.0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.08
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            barFillWidthConstraint.constant = targetW
            contentView?.layoutSubtreeIfNeeded()
        }

        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let vf = screen.visibleFrame
            let x = vf.midX - frame.width / 2
            let y = vf.minY + 46
            setFrameOrigin(NSPoint(x: x, y: y))
        }

        alphaValue = 1.0
        orderFrontRegardless()

        hideTimer?.invalidate()
        exitTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 1.25, repeats: false) { [weak self] _ in
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.22
                self?.animator().alphaValue = 0.0
            }, completionHandler: {
                self?.orderOut(nil)
            })
        }
        exitTimer = Timer.scheduledTimer(withTimeInterval: 6.0, repeats: false) { _ in
            unlink(osdSocketPath)
            NSApp.terminate(nil)
        }
    }
}

private func runOSDDaemon(initialPayload: String) -> Never {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let panel = VolumeHUDPanel()

    func applyLine(_ line: String) {
        let parts = line.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "|", maxSplits: 2)
        guard parts.count == 3, let pct = Int(parts[0]) else { return }
        let muted = parts[1] == "1"
        let dev = String(parts[2])
        DispatchQueue.main.async {
            panel.update(percent: pct, muted: muted, device: dev)
        }
    }

    unlink(osdSocketPath)
    let listenFD = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
    if listenFD >= 0 {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(osdSocketPath.utf8)
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: UInt8.self, capacity: bytes.count + 1) { dst in
                for (i, b) in bytes.enumerated() { dst[i] = b }
                dst[bytes.count] = 0
            }
        }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(listenFD, $0, len) }
        }
        if bound == 0 && Darwin.listen(listenFD, 16) == 0 {
            DispatchQueue.global(qos: .userInteractive).async {
                while true {
                    let client = Darwin.accept(listenFD, nil, nil)
                    if client < 0 { break }
                    var buf = [UInt8](repeating: 0, count: 512)
                    let n = Darwin.recv(client, &buf, buf.count, 0)
                    Darwin.close(client)
                    if n > 0, let str = String(bytes: buf[0..<n], encoding: .utf8) {
                        for line in str.split(separator: "\n") {
                            applyLine(String(line))
                        }
                    }
                }
            }
        }
    }

    applyLine(initialPayload)
    app.run()
    exit(0)
}

// MARK: - CLI Entrypoint

var args = Array(CommandLine.arguments.dropFirst())
let useOSD = args.contains("--osd")
args.removeAll { $0 == "--osd" }

guard let cmd = args.first else {
    fputs("Usage: audio_vol <get|state|devices|select <uid|name>|set <0-100>|step <delta>|up [step]|down [step]|mute> [--osd]\n", stderr)
    exit(1)
}

if cmd == "--osd-daemon" {
    runOSDDaemon(initialPayload: args.dropFirst().first ?? "0|0|Audio")
}

switch cmd {
case "get":
    let st = currentAudioState()
    print(st.muted ? 0 : st.percent)

case "state":
    ensureLoopbackFullScale(in: defaultOutputDevice())
    let st = currentAudioState()
    print("\(st.percent)\t\(st.muted ? 1 : 0)\t\(st.deviceName)")

case "devices":
    for d in listOutputDevices() {
        print("\(d.uid)\t\(d.name)\t\(d.isCurrent ? 1 : 0)")
    }

case "select":
    guard args.count >= 2 else { exit(1) }
    let target = args.dropFirst().joined(separator: " ")
    guard selectDevice(query: target) else { exit(1) }
    let st = currentAudioState()
    triggerSketchybar(st)

case "set":
    guard args.count >= 2, let raw = Double(args[1]) else { exit(1) }
    let out = defaultOutputDevice()
    ensureLoopbackFullScale(in: out)
    let clamped = max(0.0, min(100.0, raw))
    let targets = resolveTargetDevices(for: out)
    for t in targets {
        writeVolumeScalar(t, value: Float32(clamped / 100.0))
        writeMute(t, muted: clamped <= 0.0)
    }
    let st = currentAudioState()
    triggerSketchybar(st)
    if useOSD { showOSD(st) }

case "step", "up", "down":
    let defaultStep = 6.25
    let delta: Double
    if cmd == "step" {
        guard args.count >= 2, let d = Double(args[1]) else { exit(1) }
        delta = d
    } else if cmd == "up" {
        delta = args.count >= 2 ? (Double(args[1]) ?? defaultStep) : defaultStep
    } else {
        delta = -(args.count >= 2 ? (Double(args[1]) ?? defaultStep) : defaultStep)
    }

    let out = defaultOutputDevice()
    ensureLoopbackFullScale(in: out)
    let targets = resolveTargetDevices(for: out)
    let primary = targets.first ?? out
    let curVol = Double(readVolumeScalar(primary) ?? 0) * 100.0
    let curMuted = readMute(primary)

    let nextVol: Double
    let nextMuted: Bool
    if curMuted && delta > 0 {
        nextMuted = false
        nextVol = curVol > 1.0 ? curVol : delta
    } else {
        let sum = curVol + delta
        nextVol = max(0.0, min(100.0, sum))
        nextMuted = nextVol <= 0.4
    }

    for t in targets {
        writeVolumeScalar(t, value: Float32((nextMuted && nextVol <= 0.4 ? 0.0 : nextVol) / 100.0))
        writeMute(t, muted: nextMuted)
    }
    let st = currentAudioState()
    triggerSketchybar(st)
    if useOSD { showOSD(st) }

case "mute":
    let out = defaultOutputDevice()
    ensureLoopbackFullScale(in: out)
    let targets = resolveTargetDevices(for: out)
    let primary = targets.first ?? out
    let nextMuted = !readMute(primary)
    for t in targets {
        writeMute(t, muted: nextMuted)
    }
    let st = currentAudioState()
    triggerSketchybar(st)
    if useOSD { showOSD(st) }

default:
    fputs("Unknown command: \(cmd)\n", stderr)
    exit(1)
}
