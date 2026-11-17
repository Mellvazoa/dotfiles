import AppKit
import Foundation

func main() {
    let rawArgs = Array(CommandLine.arguments.dropFirst())
    let paths = rawArgs.filter { !$0.isEmpty }
    if paths.isEmpty {
        fputs("Usage: filecopy <file1> [file2 ...]\n", stderr)
        exit(1)
    }

    var urls: [NSURL] = []
    let fm = FileManager.default
    let cwd = URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true)

    for p in paths {
        let url: URL
        if p.hasPrefix("/") {
            url = URL(fileURLWithPath: p).standardizedFileURL
        } else {
            url = cwd.appendingPathComponent(p).standardizedFileURL
        }
        if fm.fileExists(atPath: url.path) {
            urls.append(url as NSURL)
        } else {
            fputs("filecopy: path not found: \(url.path)\n", stderr)
        }
    }

    if urls.isEmpty {
        fputs("filecopy: no valid paths provided\n", stderr)
        exit(1)
    }

    let pb = NSPasteboard.general
    pb.clearContents()
    if !pb.writeObjects(urls) {
        fputs("filecopy: failed to write file URLs to NSPasteboard\n", stderr)
        exit(1)
    }

    // Also populate NSFilenamesPboardType so Electron/Chromium apps (Antigravity, Chrome, etc.)
    // receive all selected files instead of only the first/last single-item URL.
    let validPaths = urls.compactMap { $0.path }
    let filenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
    pb.addTypes([filenamesType], owner: nil)
    pb.setPropertyList(validPaths, forType: filenamesType)

    let joined = validPaths.joined(separator: "\n") + "\n"
    try? joined.write(toFile: "/tmp/yazi_last_files", atomically: true, encoding: .utf8)

    print("Copied \(urls.count) file(s) to clipboard")
}

main()
