import AppKit
import Quartz

// File operations backing menus, context menu, palette, and shortcuts.
// All mutations refresh the owning pane; failures surface as alerts.
struct FileOps {

    static func alert(_ message: String) {
        let a = NSAlert()
        a.messageText = message
        a.addButton(withTitle: "OK")
        a.runModal()
    }

    static func trash(items: [Fileinfo], in pane: PaneViewController) {
        for item in items {
            do {
                var result: NSURL?
                try FileManager.default.trashItem(at: URL(fileURLWithPath: item.fullPath), resultingItemURL: &result)
            } catch { alert("Couldn't move “\(item.name)” to Trash:\n\(error.localizedDescription)"); return }
        }
        pane.refresh()
    }

    static func duplicate(items: [Fileinfo], in pane: PaneViewController) {
        for item in items {
            let dir = (item.fullPath as NSString).deletingLastPathComponent
            let base = (item.name as NSString).deletingPathExtension
            let ext = (item.name as NSString).pathExtension
            var n = 1
            var target: String
            repeat {
                let name = ext.isEmpty ? "\(base) copy \(n)" : "\(base) copy \(n).\(ext)"
                target = (dir as NSString).appendingPathComponent(name)
                n += 1
            } while FileManager.default.fileExists(atPath: target)
            do { try FileManager.default.copyItem(atPath: item.fullPath, toPath: target) }
            catch { alert("Couldn't duplicate “\(item.name)”:\n\(error.localizedDescription)"); return }
        }
        pane.refresh()
    }

    static func makeAlias(items: [Fileinfo], in pane: PaneViewController) {
        for item in items {
            let dir = (item.fullPath as NSString).deletingLastPathComponent
            let target = (dir as NSString).appendingPathComponent("\(item.name) alias")
            do { try FileManager.default.createSymbolicLink(atPath: target, withDestinationPath: item.fullPath) }
            catch { alert("Couldn't make alias:\n\(error.localizedDescription)"); return }
        }
        pane.refresh()
    }

    static func rename(item: Fileinfo, to name: String, in pane: PaneViewController) {
        let dir = (item.fullPath as NSString).deletingLastPathComponent
        let target = (dir as NSString).appendingPathComponent(name)
        do { try FileManager.default.moveItem(atPath: item.fullPath, toPath: target) }
        catch { alert("Couldn't rename:\n\(error.localizedDescription)") }
        pane.refresh()
    }

    static func newFolder(in pane: PaneViewController) {
        let dir = pane.displayedPath
        var n = 1
        var target: String
        repeat {
            target = (dir as NSString).appendingPathComponent(n == 1 ? "untitled folder" : "untitled folder \(n)")
            n += 1
        } while FileManager.default.fileExists(atPath: target)
        do { try FileManager.default.createDirectory(atPath: target, withIntermediateDirectories: false) }
        catch { alert("Couldn't create folder:\n\(error.localizedDescription)") }
        pane.refresh()
    }

    static func copyToPasteboard(items: [Fileinfo], cut: Bool) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(items.map { URL(fileURLWithPath: $0.fullPath) as NSURL })
        pb.setString(cut ? "cut" : "copy", forType: .init("com.vata.cutCopy"))
    }

    static func paste(into pane: PaneViewController) {
        let pb = NSPasteboard.general
        guard let urls = pb.readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty else { return }
        let cut = pb.string(forType: .init("com.vata.cutCopy")) == "cut"
        for url in urls {
            let target = (pane.displayedPath as NSString).appendingPathComponent(url.lastPathComponent)
            do {
                if cut { try FileManager.default.moveItem(at: url, to: URL(fileURLWithPath: target)) }
                else if url.path != target { try FileManager.default.copyItem(at: url, to: URL(fileURLWithPath: target)) }
            } catch { alert("Couldn't paste “\(url.lastPathComponent)”:\n\(error.localizedDescription)"); return }
        }
        if cut { pb.clearContents() }
        pane.refresh()
    }

    static func copyPaths(items: [Fileinfo]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(items.map { $0.fullPath }.joined(separator: "\n"), forType: .string)
    }

    static let archiveExtensions: Set<String> = ["zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar"]

    static func isArchive(_ item: Fileinfo) -> Bool {
        archiveExtensions.contains((item.name as NSString).pathExtension.lowercased())
    }

    static func extract(item: Fileinfo, in pane: PaneViewController) {
        let dir = ((item.fullPath as NSString).deletingLastPathComponent as NSString)
            .appendingPathComponent((item.name as NSString).deletingPathExtension)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        let ext = (item.name as NSString).pathExtension.lowercased()
        if ext == "zip" {
            proc.arguments = ["-c", "mkdir -p \(__shEscaped(dir)) && /usr/bin/ditto -x -k \(__shEscaped(item.fullPath)) \(__shEscaped(dir))"]
        } else if ["tar", "gz", "tgz", "bz2", "xz"].contains(ext) {
            proc.arguments = ["-c", "mkdir -p \(__shEscaped(dir)) && /usr/bin/tar -xf \(__shEscaped(item.fullPath)) -C \(__shEscaped(dir))"]
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: item.fullPath))
            return
        }
        do {
            try proc.run()
            proc.waitUntilExit()
            if proc.terminationStatus != 0 { alert("Couldn't extract “\(item.name)”.") }
        } catch { alert("Couldn't extract “\(item.name)”.\n\(error.localizedDescription)") }
        pane.refresh()
    }

    private static func __shEscaped(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
    static func hasPasteboardURLs() -> Bool {
        NSPasteboard.general.canReadObject(forClasses: [NSURL.self], options: nil)
    }

    // MARK: - Drag and drop (pure decision + execution)

    enum DropAction: Equatable {
        case move([URL], URL)
        case copy([URL], URL)
        case pin([URL])
        case none
    }

    /// Decides a file drop without touching the filesystem (unit-tested).
    /// - optionKey: copy even on the same volume. Cross-volume always copies.
    static func decideDrop(urls: [URL], destDir: URL, sourceDir: URL?, optionKey: Bool, sameVolume: Bool) -> DropAction {
        let files = urls.filter { $0.isFileURL }
        guard !files.isEmpty else { return .none }
        if files.allSatisfy({ $0.path == destDir.appendingPathComponent($0.lastPathComponent).path }) { return .none }
        if !sameVolume || optionKey { return .copy(files, destDir) }
        _ = sourceDir
        return .move(files, destDir)
    }

    static func sameVolume(_ a: URL, _ b: URL) -> Bool {
        let va = try? a.resourceValues(forKeys: [.volumeIdentifierKey])
        let vb = try? b.resourceValues(forKeys: [.volumeIdentifierKey])
        guard let ia = va?.volumeIdentifier as? NSObject, let ib = vb?.volumeIdentifier as? NSObject else { return false }
        return ia.isEqual(ib)
    }

    static func performDrop(_ action: DropAction, in pane: PaneViewController) {
        switch action {
        case .none: return
        case .pin(let urls):
            for u in urls { HeaderStore.shared.add(u.path) }
            (pane.view.window?.windowController as? FileWindowController)?.sidebarReload()
        case .move(let urls, let dest), .copy(let urls, let dest):
            let isMove: Bool
            if case .move = action { isMove = true } else { isMove = false }
            for url in urls {
                let target = dest.appendingPathComponent(url.lastPathComponent)
                guard url.path != target.path else { continue }
                do {
                    if isMove { try FileManager.default.moveItem(at: url, to: target) }
                    else if !FileManager.default.fileExists(atPath: target.path) {
                        try FileManager.default.copyItem(at: url, to: target)
                    }
                } catch { alert("Couldn't \(isMove ? "move" : "copy") “\(url.lastPathComponent)”:\n\(error.localizedDescription)"); return }
            }
            pane.refresh()
        }
    }

    static func showGetInfo(for items: [Fileinfo]) {
        guard let item = items.first else { return }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 220),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "\(item.name) Info"
        let text = NSTextView(frame: NSRect(x: 12, y: 12, width: 296, height: 196))
        text.isEditable = false
        text.font = .systemFont(ofSize: 12)
        var lines = ["Name: \(item.name)", "Path: \(item.fullPath)"]
        lines.append("Kind: \(item.type == .folder ? "Folder" : item.type == .symlink ? "Alias" : "File")")
        if item.type != .folder {
            lines.append("Size: \(ByteCountFormatter.string(fromByteCount: max(item.size, 0), countStyle: .file))")
        }
        if let d = item.modificationDate {
            lines.append("Modified: \(DateFormatter.localizedString(from: d, dateStyle: .medium, timeStyle: .short))")
        }
        if let m = item.posixPermissions {
            lines.append("Permissions: \(String(m, radix: 8))")
        }
        text.string = lines.joined(separator: "\n")
        panel.contentView?.addSubview(text)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
    }
}

// Quick Look support: the active pane vends selected URLs.
final class PreviewDelegate: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = PreviewDelegate()
    weak var pane: PaneViewController?

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        pane?.selectedItems.count ?? 0
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard let item = pane?.selectedItems[index] else { return nil }
        return URL(fileURLWithPath: item.fullPath) as QLPreviewItem
    }
}
