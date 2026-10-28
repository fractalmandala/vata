import AppKit

// Window sidebar, ForkLift parity: Devices, Recent Folders, Tags.
// Pins stay in the title bar per user direction — not here.
final class SidebarViewController: NSViewController {

    weak var windowController: FileWindowController?
    let outline = NSOutlineView()
    private var devices: [URL] = []
    private var recents: [String] = []
    private let tags: [(String, NSColor)] = [
        ("Gray", .systemGray), ("Green", .systemGreen), ("Purple", .systemPurple),
        ("Blue", .systemBlue), ("Yellow", .systemYellow), ("Red", .systemRed),
        ("Orange", .systemOrange),
    ]

    enum Section { case devices, recent, favorites, tags }
    struct Row {
        var section: Section
        var title: String
        var path: String?
        var tagColor: NSColor?
        var volume: URL?
    }
    private var rows: [Row] = []

    override func loadView() {
        view = NSView()
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("side"))
        outline.addTableColumn(col)
        outline.delegate = self
        outline.dataSource = self
        outline.headerView = nil
        outline.target = self
        outline.doubleAction = #selector(activated)
        outline.backgroundColor = .clear
        outline.registerForDraggedTypes([.fileURL])
        let favMenu = NSMenu()
        favMenu.delegate = self
        outline.menu = favMenu
        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        reload()
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme),
                                               name: .vataThemeChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reload),
                                               name: NSWorkspace.didMountNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reload),
                                               name: NSWorkspace.didUnmountNotification, object: nil)
    }

    @objc func reload() {
        devices = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeNameKey],
                                                        options: [.skipHiddenVolumes]) ?? []
        recents = RecentStore.shared.paths
        rows = devices.map { Row(section: .devices, title: $0.lastPathComponent, volume: $0) }
            + recents.map { Row(section: .recent, title: ($0 as NSString).lastPathComponent, path: $0) }
            + HeaderStore.shared.paths.map { Row(section: .favorites, title: ($0 as NSString).lastPathComponent, path: $0) }
            + tags.map { Row(section: .tags, title: $0.0, tagColor: $0.1) }
        outline.reloadData()
    }

    @objc private func applyTheme() {
        let t = ThemeManager.shared.current
        outline.backgroundColor = t.sidebarBG
        outline.enclosingScrollView?.backgroundColor = t.sidebarBG
        outline.reloadData()
    }

    @objc private func activated() {
        let row = outline.clickedRow >= 0 ? outline.clickedRow : outline.selectedRow
        guard row >= 0, let item = outline.item(atRow: row),
              let r = item as? Row, let wc = windowController else { return }
        if let vol = r.volume {
            wc.activePane?.navigate(to: vol.path, record: true)
        } else if r.section == .favorites, let path = r.path {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                wc.activePane?.navigate(to: path, record: true)
            } else {
                NSWorkspace.shared.open(URL(fileURLWithPath: path))
            }
        } else if let path = r.path {
            wc.activePane?.navigate(to: path, record: true)
        } else if let color = r.tagColor {
            wc.activePane?.navigateToTag(colorName: r.title, color: color)
        }
    }
}

extension SidebarViewController: NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
    // Grouped sections: Devices / Recent Folders / Favorites / Tags.
    private var grouped: [(title: String, rows: [Row])] {
        let dev = devices.map { Row(section: .devices, title: $0.lastPathComponent, volume: $0) }
        let rec = recents.map { Row(section: .recent, title: ($0 as NSString).lastPathComponent, path: $0) }
        let fav = HeaderStore.shared.paths.map { Row(section: .favorites, title: ($0 as NSString).lastPathComponent, path: $0) }
        let tag = tags.map { Row(section: .tags, title: $0.0, tagColor: $0.1) }
        return [("Devices", dev), ("Recent Folders", rec), ("Favorites", fav), ("Tags", tag)]
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let row = outline.clickedRow >= 0 ? outline.clickedRow : outline.selectedRow
        guard let item = row >= 0 ? outline.item(atRow: row) : nil,
              let r = item as? Row, r.section == .favorites else { return }
        let mi = menu.addItem(withTitle: "Remove from Favorites", action: #selector(removeFavorite), keyEquivalent: "")
        mi.target = self
    }

    @objc private func removeFavorite() {
        let row = outline.clickedRow >= 0 ? outline.clickedRow : outline.selectedRow
        guard let item = row >= 0 ? outline.item(atRow: row) : nil,
              let r = item as? Row, r.section == .favorites, let path = r.path else { return }
        HeaderStore.shared.remove(path)
        reload()
    }

    func outlineView(_ ov: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil { return grouped.count }
        if let title = item as? String { return grouped.first(where: { $0.title == title })?.rows.count ?? 0 }
        return 0
    }

    func outlineView(_ ov: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil { return grouped[index].title }
        if let title = item as? String { return grouped.first(where: { $0.title == title })!.rows[index] }
        return grouped[index].title
    }

    func outlineView(_ ov: NSOutlineView, isItemExpandable item: Any) -> Bool {
        item is String
    }

    func outlineView(_ ov: NSOutlineView, isGroupItem item: Any) -> Bool {
        item is String
    }

    func outlineView(_ ov: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        item is Row
    }

    private func dropRow(at info: NSDraggingInfo) -> Row? {
        let row = outline.row(at: info.draggingLocation)
        guard row >= 0, let item = outline.item(atRow: row) as? Row else { return nil }
        return item
    }

    func outlineView(_ ov: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        guard dropRow(at: info) != nil,
              let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty else {
            // Background of a section: pin into Favorites.
            return []
        }
        return .move
    }

    func outlineView(_ ov: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        guard let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
              let wc = windowController, let pane = wc.activePane else { return false }
        if let target = dropRow(at: info) {
            if target.section == .favorites || target.section == .tags {
                for u in urls { HeaderStore.shared.add(u.path) }
                reload()
                return true
            }
            let destPath = target.volume?.path ?? target.path
            guard let destPath else { return false }
            let dest = URL(fileURLWithPath: destPath)
            let opt = NSEvent.modifierFlags.contains(.option)
            let sameVol = urls.first.map { FileOps.sameVolume($0, dest) } ?? false
            FileOps.performDrop(FileOps.decideDrop(urls: urls, destDir: dest, sourceDir: nil, optionKey: opt, sameVolume: sameVol), in: pane)
            return true
        }
        return false
    }

    func outlineView(_ ov: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        if let title = item as? String {
            let id = NSUserInterfaceItemIdentifier("sidegroup")
            let cell = ov.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? NSTableCellView()
            cell.identifier = id
            if cell.textField == nil {
                let tf = NSTextField(labelWithString: "")
                tf.font = .systemFont(ofSize: 11, weight: .semibold)
                tf.textColor = .secondaryLabelColor
                tf.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(tf)
                cell.textField = tf
                NSLayoutConstraint.activate([
                    tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                    tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                    tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                ])
            }
            cell.textField?.stringValue = title
            return cell
        }
        guard let row = item as? Row else { return nil }
        let id = NSUserInterfaceItemIdentifier("siderow")
        let cell = ov.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = id
        if cell.textField == nil {
            let tf = NSTextField(labelWithString: "")
            tf.font = .systemFont(ofSize: 12)
            tf.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(tf)
            cell.textField = tf
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 22),
                tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            let dot = NSImageView()
            dot.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(dot)
            NSLayoutConstraint.activate([
                dot.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                dot.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                dot.widthAnchor.constraint(equalToConstant: 12),
                dot.heightAnchor.constraint(equalToConstant: 12),
            ])
        }
        cell.textField?.stringValue = row.title
        for sub in cell.subviews where sub is NSImageView {
            let iv = sub as! NSImageView
            if let c = row.tagColor {
                iv.image = tagDot(color: c)
            } else if row.volume != nil {
                iv.image = NSImage(systemSymbolName: "externaldrive", accessibilityDescription: nil)
            } else {
                iv.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
            }
        }
        return cell
    }

    func outlineView(_ ov: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        let r = VataRowView()
        r.color = ThemeManager.shared.current.sidebarSelectionColor
        return r
    }

    private func tagDot(color: NSColor) -> NSImage {
        let img = NSImage(size: NSSize(width: 12, height: 12))
        img.lockFocus()
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: 10, height: 10)).fill()
        img.unlockFocus()
        return img
    }
}

// Recent folders, persisted, fed by every navigation.
final class RecentStore {
    static let shared = RecentStore()
    private let key = "vata.recentFolders"
    var paths: [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? [NSHomeDirectory()]
    }
    func visited(_ path: String) {
        var p = paths.filter { $0 != path }
        p.insert(path, at: 0)
        UserDefaults.standard.set(Array(p.prefix(10)), forKey: key)
    }
}

// In-memory listing for tag searches (Spotlight-backed).
final class MemoryDatasource: Datasource {
    private var preset: [Fileinfo] = []
    func setItems(_ items: [Fileinfo]) { preset = items }
    override func doList(_ path: String) throws -> [Fileinfo] { preset }
}
