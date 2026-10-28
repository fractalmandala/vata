import AppKit

// ForkLift-parity settings: sidebar sections, grouped rows.
// Sections: General, Shortcuts, Themes, Tags, Tools (Quick Actions).
final class SettingsWindowController: NSWindowController {

    enum Tab { case general, quickActions }
    static let shared = SettingsWindowController()

    private let sectionList = NSTableView()
    private let contentHost = NSView()
    private var section: String = "General"
    private let sections = ["General", "Shortcuts", "Themes", "Tags", "Tools"]
    private let sectionIcons = ["General": "gearshape", "Shortcuts": "command",
                                "Themes": "paintbrush", "Tags": "tag", "Tools": "hammer"]

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Vata Settings"
        super.init(window: window)
        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("sec"))
        sectionList.addTableColumn(col)
        sectionList.delegate = self
        sectionList.dataSource = self
        sectionList.headerView = nil
        let sideScroll = NSScrollView()
        sideScroll.documentView = sectionList
        sideScroll.widthAnchor.constraint(equalToConstant: 180).isActive = true
        contentHost.translatesAutoresizingMaskIntoConstraints = false
        split.addArrangedSubview(sideScroll)
        split.addArrangedSubview(contentHost)
        window.contentView = split
        showSection("General")
    }

    required init?(coder: NSCoder) { nil }

    func show(tab: Tab = .general) {
        showSection(tab == .quickActions ? "Tools" : "General")
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showSection(_ name: String) {
        section = name
        contentHost.subviews.forEach { $0.removeFromSuperview() }
        let builders: [String: () -> NSView] = [
            "General": buildGeneral, "Shortcuts": buildShortcuts,
            "Themes": buildThemes, "Tags": buildTags, "Tools": buildTools,
        ]
        if let v = builders[name]?() {
            v.translatesAutoresizingMaskIntoConstraints = false
            contentHost.addSubview(v)
            NSLayoutConstraint.activate([
                v.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor, constant: 16),
                v.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor, constant: -16),
                v.topAnchor.constraint(equalTo: contentHost.topAnchor, constant: 16),
            ])
        }
        if let i = sections.firstIndex(of: name) {
            sectionList.selectRowIndexes([i], byExtendingSelection: false)
        }
    }

    // MARK: - Row helpers

    private func row(label: String, control: NSView) -> NSView {
        let l = NSTextField(labelWithString: label)
        l.translatesAutoresizingMaskIntoConstraints = false
        control.translatesAutoresizingMaskIntoConstraints = false
        let r = NSView()
        r.addSubview(l)
        r.addSubview(control)
        r.heightAnchor.constraint(equalToConstant: 34).isActive = true
        NSLayoutConstraint.activate([
            l.leadingAnchor.constraint(equalTo: r.leadingAnchor),
            l.centerYAnchor.constraint(equalTo: r.centerYAnchor),
            control.trailingAnchor.constraint(equalTo: r.trailingAnchor),
            control.centerYAnchor.constraint(equalTo: r.centerYAnchor),
            control.leadingAnchor.constraint(greaterThanOrEqualTo: l.trailingAnchor, constant: 12),
        ])
        return r
    }

    private func toggle(_ key: String, value: Bool, onChange: @escaping (Bool) -> Void) -> NSButton {
        let b = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        b.state = value ? .on : .off
        b.target = BlockTarget { [weak b] in onChange(b?.state == .on) }
        b.action = #selector(BlockTarget.fire)
        return b
    }

    private func stack(_ views: [NSView]) -> NSView {
        let s = NSStackView(views: views)
        s.orientation = .vertical
        s.spacing = 2
        return s
    }

    // MARK: - General

    private func buildGeneral() -> NSView {
        let s = Settings.shared
        let startDir = NSPopUpButton()
        startDir.addItems(withTitles: ["Home", "Desktop", "Documents", "Downloads", "Applications"])
        startDir.selectItem(withTitle: UserDefaults.standard.string(forKey: "vata.startDir") ?? "Home")
        startDir.target = BlockTarget { [weak startDir] in
            UserDefaults.standard.set(startDir?.selectedItem?.title, forKey: "vata.startDir")
        }
        startDir.action = #selector(BlockTarget.fire)
        func boolRow(_ label: String, key: String, def: Bool) -> NSView {
            row(label: label, control: toggle(key, value: UserDefaults.standard.object(forKey: key) == nil ? def : UserDefaults.standard.bool(forKey: key)) { v in
                UserDefaults.standard.set(v, forKey: key)
                NotificationCenter.default.post(name: .vataSettingsChanged, object: nil)
            })
        }
        return stack([
            row(label: "Starting Directory", control: startDir),
            boolRow("Restore windows on startup", key: "vata.restore", def: true),
            boolRow("Show hidden files", key: "vata.showHidden", def: false),
            boolRow("Handle archives in Vata", key: "vata.archives", def: true),
            boolRow("Confirm drag operations", key: "vata.confirmDrag", def: false),
        ])
    }

    // MARK: - Shortcuts (view + restore; editing records via click)

    private func buildShortcuts() -> NSView {
        let table = NSTableView()
        let c1 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("cmd"))
        c1.title = "Command"
        c1.width = 300
        let c2 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("key"))
        c2.title = "Shortcut"
        c2.width = 140
        table.addTableColumn(c1)
        table.addTableColumn(c2)
        let ds = ShortcutTable()
        table.dataSource = ds
        table.delegate = ds
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.heightAnchor.constraint(equalToConstant: 380).isActive = true
        let restore = NSButton(title: "Restore Defaults", target: BlockTarget {
            ShortcutStore.shared.reset()
            table.reloadData()
        }, action: #selector(BlockTarget.fire))
        let wrap = NSView()
        wrap.addSubview(scroll)
        wrap.addSubview(restore)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        restore.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: wrap.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: wrap.topAnchor),
            restore.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 8),
            restore.trailingAnchor.constraint(equalTo: wrap.trailingAnchor),
            restore.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
        ])
        objc_setAssociatedObject(wrap, "ds", ds, .OBJC_ASSOCIATION_RETAIN)
        return wrap
    }

    // MARK: - Themes

    private var themeTable: NSTableView?

    private func buildThemes() -> NSView {
        let table = NSTableView()
        themeTable = table
        let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("theme"))
        c.title = "Theme"
        c.width = 440
        table.addTableColumn(c)
        let ds = ThemeTable { [weak self] in self?.refreshThemes() }
        table.dataSource = ds
        table.delegate = ds
        objc_setAssociatedObject(table, "ds", ds, .OBJC_ASSOCIATION_RETAIN)
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.heightAnchor.constraint(equalToConstant: 360).isActive = true
        let add = NSButton(title: "Add", target: BlockTarget { [weak self] in
            ThemeEditor.show(existing: nil) { [weak self] in self?.refreshThemes() }
        }, action: #selector(BlockTarget.fire))
        let dup = NSButton(title: "Duplicate", target: BlockTarget { [weak self] in
            let r = table.selectedRow
            let all = ThemeManager.shared.all
            guard r >= 0, r < all.count else { return }
            var copy = all[r]
            copy.name += " Copy"
            ThemeManager.shared.saveCustom(copy)
            self?.refreshThemes()
        }, action: #selector(BlockTarget.fire))
        let del = NSButton(title: "Remove", target: BlockTarget { [weak self] in
            let r = table.selectedRow
            let all = ThemeManager.shared.all
            guard r >= 0, r < all.count, ThemeManager.shared.isCustom(name: all[r].name) else { return }
            ThemeManager.shared.deleteCustom(name: all[r].name)
            self?.refreshThemes()
        }, action: #selector(BlockTarget.fire))
        let edit = NSButton(title: "Edit…", target: BlockTarget { [weak self] in
            let r = table.selectedRow
            let all = ThemeManager.shared.all
            guard r >= 0, r < all.count else { return }
            ThemeEditor.show(existing: all[r]) { [weak self] in self?.refreshThemes() }
        }, action: #selector(BlockTarget.fire))
        let bar = NSStackView(views: [add, dup, del, edit])
        bar.spacing = 8
        return stack([scroll, bar])
    }

    private func refreshThemes() {
        themeTable?.reloadData()
    }

    // MARK: - Tags

    private func buildTags() -> NSView {
        let hint = NSTextField(labelWithString: "Show these tags in the sidebar:")
        var rows: [NSView] = [hint]
        let colors: [(String, NSColor)] = [
            ("Gray", .systemGray), ("Green", .systemGreen), ("Purple", .systemPurple),
            ("Blue", .systemBlue), ("Yellow", .systemYellow), ("Red", .systemRed),
            ("Orange", .systemOrange),
        ]
        let hidden = Set(UserDefaults.standard.stringArray(forKey: "vata.hiddenTags") ?? [])
        for (name, _) in colors {
            let b = NSButton(checkboxWithTitle: name, target: nil, action: nil)
            b.state = hidden.contains(name) ? .off : .on
            b.target = BlockTarget { [weak b] in
                var h = Set(UserDefaults.standard.stringArray(forKey: "vata.hiddenTags") ?? [])
                if b?.state == .on { h.remove(name) } else { h.insert(name) }
                UserDefaults.standard.set(Array(h), forKey: "vata.hiddenTags")
            }
            b.action = #selector(BlockTarget.fire)
            rows.append(b)
        }
        return stack(rows)
    }

    // MARK: - Tools (Quick Actions)

    private func buildTools() -> NSView {
        let hint = NSTextField(labelWithString: "Quick Actions run a shell command with the selected path appended.")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        let table = NSTableView()
        let c1 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("title"))
        c1.title = "Title"
        c1.width = 180
        let c2 = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("cmd"))
        c2.title = "Command"
        c2.width = 260
        table.addTableColumn(c1)
        table.addTableColumn(c2)
        let ds = QATable()
        table.dataSource = ds
        table.delegate = ds
        objc_setAssociatedObject(table, "ds", ds, .OBJC_ASSOCIATION_RETAIN)
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.heightAnchor.constraint(equalToConstant: 300).isActive = true
        let add = NSButton(title: "Add", target: BlockTarget {
            var a = Settings.shared.quickActions
            a.append(QuickAction(title: "New Action", command: "open "))
            Settings.shared.quickActions = a
            table.reloadData()
        }, action: #selector(BlockTarget.fire))
        let del = NSButton(title: "Remove", target: BlockTarget {
            let r = table.selectedRow
            guard r >= 0 else { return }
            var a = Settings.shared.quickActions
            a.remove(at: r)
            Settings.shared.quickActions = a
            table.reloadData()
        }, action: #selector(BlockTarget.fire))
        let bar = NSStackView(views: [add, del])
        bar.spacing = 8
        return stack([hint, scroll, bar])
    }
}

// MARK: - Section list

extension SettingsWindowController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        tableView === sectionList ? sections.count : 0
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard tableView === sectionList else { return nil }
        let id = NSUserInterfaceItemIdentifier("sec")
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = id
        if cell.imageView == nil {
            let iv = NSImageView()
            iv.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(iv)
            cell.imageView = iv
            let tf = NSTextField(labelWithString: "")
            tf.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(tf)
            cell.textField = tf
            NSLayoutConstraint.activate([
                iv.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                iv.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                iv.widthAnchor.constraint(equalToConstant: 20),
                iv.heightAnchor.constraint(equalToConstant: 20),
                tf.leadingAnchor.constraint(equalTo: iv.trailingAnchor, constant: 8),
                tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }
        cell.textField?.stringValue = sections[row]
        cell.imageView?.image = NSImage(systemSymbolName: sectionIcons[sections[row]] ?? "gearshape",
                                       accessibilityDescription: nil)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard notification.object as? NSTableView === sectionList else { return }
        let r = sectionList.selectedRow
        guard r >= 0 else { return }
        showSection(sections[r])
    }
}

// MARK: - Small tables

final class BlockTarget: NSObject {
    // NSControl holds targets weakly; inline-created targets would dealloc
    // instantly and silently kill every button. Self-retain for app lifetime.
    private static var live: [BlockTarget] = []
    private let fn: () -> Void
    init(_ fn: @escaping () -> Void) { self.fn = fn; super.init(); Self.live.append(self) }
    @objc func fire() { fn() }
}

final class QATable: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { Settings.shared.quickActions.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("title")
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = id
        if cell.textField == nil {
            let tf = NSTextField()
            tf.isEditable = true
            tf.isBordered = false
            tf.backgroundColor = .clear
            tf.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(tf)
            cell.textField = tf
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }
        let a = Settings.shared.quickActions[row]
        cell.textField?.stringValue = id.rawValue == "cmd" ? a.command : a.title
        return cell
    }
    func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
        guard row < Settings.shared.quickActions.count, let s = object as? String else { return }
        var a = Settings.shared.quickActions
        if tableColumn?.identifier.rawValue == "cmd" { a[row].command = s } else { a[row].title = s }
        Settings.shared.quickActions = a
    }
}

final class ShortcutTable: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private var commands: [VataCommand] { ShortcutStore.shared.all }
    func numberOfRows(in tableView: NSTableView) -> Int { commands.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("cmd")
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = id
        if cell.textField == nil {
            let tf = NSTextField(labelWithString: "")
            tf.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(tf)
            cell.textField = tf
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }
        cell.textField?.stringValue = id.rawValue == "key"
            ? ShortcutStore.shared.shortcut(for: commands[row].id) : commands[row].title
        return cell
    }
}

final class ThemeTable: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private let onChange: () -> Void
    init(onChange: @escaping () -> Void) { self.onChange = onChange }
    func numberOfRows(in tableView: NSTableView) -> Int { ThemeManager.shared.all.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("theme")
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = id
        if cell.textField == nil {
            let tf = NSTextField(labelWithString: "")
            tf.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(tf)
            cell.textField = tf
            let sw = ThemeSwatch()
            sw.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(sw)
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                sw.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                sw.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                sw.widthAnchor.constraint(equalToConstant: 90),
                sw.heightAnchor.constraint(equalToConstant: 22),
            ])
        }
        let t = ThemeManager.shared.all[row]
        cell.textField?.stringValue = t.name + (ThemeManager.shared.current.name == t.name ? " ✓" : "")
        (cell.subviews.first(where: { $0 is ThemeSwatch }) as? ThemeSwatch)?.theme = t
        return cell
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let t = notification.object as? NSTableView else { return }
        let r = t.selectedRow
        let all = ThemeManager.shared.all
        guard r >= 0, r < all.count else { return }
        ThemeManager.shared.select(name: all[r].name)
        t.reloadData()
        // Reload clears selection; restore it so Remove/Edit act on this row.
        t.selectRowIndexes([r], byExtendingSelection: false)
        onChange()
    }
}

final class ThemeSwatch: NSView {
    var theme: VataTheme? { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        guard let t = theme else { return }
        let cols = [t.baseColor, t.highlightColor, t.textColor]
        let w = bounds.width / 3
        for (i, c) in cols.enumerated() {
            c.setFill()
            NSBezierPath(roundedRect: NSRect(x: CGFloat(i) * w + 1, y: 1, width: w - 2, height: bounds.height - 2),
                         xRadius: 4, yRadius: 4).fill()
        }
    }
}

// MARK: - Theme editor (add / duplicate / edit, like ForkLift)

final class ThemeEditor: NSWindowController {
    // NSWindowController is not retained by its window; without this the
    // controller (Cancel/Save target) deallocs while the editor is open.
    private static var open: [ThemeEditor] = []
    static func show(existing: VataTheme?, done: @escaping () -> Void) {
        let ed = ThemeEditor(existing: existing, done: done)
        open.append(ed)
        ed.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private var theme: VataTheme
    private let isNew: Bool
    private let done: () -> Void
    private let nameField = NSTextField()
    private let darkToggle = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private var wells: [String: NSColorWell] = [:]

    init(existing: VataTheme?, done: @escaping () -> Void) {
        theme = existing ?? VataTheme(name: "Custom", isDark: true, highlight: "#E8890C",
                                     base: "#232228", text: "#FFFFFF", label: "#AAAAAA",
                                     sidebarBackground: "#2B2A30", sidebarItem: "#E8890C",
                                     sidebarText: "#FFFFFF", sidebarSelection: "#3A3940")
        isNew = existing == nil
        self.done = done
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 480),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = isNew ? "New Theme" : "Edit Theme"
        super.init(window: window)
        build()
    }

    required init?(coder: NSCoder) { nil }

    private func colorRow(_ label: String, key: String, get: NSColor, set: @escaping (NSColor) -> Void) -> NSView {
        let l = NSTextField(labelWithString: label)
        l.translatesAutoresizingMaskIntoConstraints = false
        let well = NSColorWell()
        well.color = get
        well.target = BlockTarget { [weak well] in if let c = well?.color { set(c) } }
        well.action = #selector(BlockTarget.fire)
        wells[key] = well
        well.translatesAutoresizingMaskIntoConstraints = false
        let r = NSView()
        r.addSubview(l)
        r.addSubview(well)
        r.heightAnchor.constraint(equalToConstant: 32).isActive = true
        NSLayoutConstraint.activate([
            l.leadingAnchor.constraint(equalTo: r.leadingAnchor),
            l.centerYAnchor.constraint(equalTo: r.centerYAnchor),
            well.trailingAnchor.constraint(equalTo: r.trailingAnchor),
            well.centerYAnchor.constraint(equalTo: r.centerYAnchor),
        ])
        return r
    }

    private func build() {
        guard let v = window?.contentView else { return }
        nameField.stringValue = theme.name
        darkToggle.state = theme.isDark ? .on : .off
        var rows: [NSView] = []
        let nameRow = NSView()
        let nl = NSTextField(labelWithString: "Name")
        nl.translatesAutoresizingMaskIntoConstraints = false
        nameField.translatesAutoresizingMaskIntoConstraints = false
        nameRow.addSubview(nl)
        nameRow.addSubview(nameField)
        nameRow.heightAnchor.constraint(equalToConstant: 32).isActive = true
        NSLayoutConstraint.activate([
            nl.leadingAnchor.constraint(equalTo: nameRow.leadingAnchor),
            nl.centerYAnchor.constraint(equalTo: nameRow.centerYAnchor),
            nameField.trailingAnchor.constraint(equalTo: nameRow.trailingAnchor),
            nameField.centerYAnchor.constraint(equalTo: nameRow.centerYAnchor),
            nameField.widthAnchor.constraint(equalToConstant: 280),
        ])
        rows.append(nameRow)
        let darkRow = NSView()
        let dl = NSTextField(labelWithString: "Dark style")
        dl.translatesAutoresizingMaskIntoConstraints = false
        darkToggle.translatesAutoresizingMaskIntoConstraints = false
        darkRow.addSubview(dl)
        darkRow.addSubview(darkToggle)
        darkRow.heightAnchor.constraint(equalToConstant: 32).isActive = true
        NSLayoutConstraint.activate([
            dl.leadingAnchor.constraint(equalTo: darkRow.leadingAnchor),
            dl.centerYAnchor.constraint(equalTo: darkRow.centerYAnchor),
            darkToggle.trailingAnchor.constraint(equalTo: darkRow.trailingAnchor),
            darkToggle.centerYAnchor.constraint(equalTo: darkRow.centerYAnchor),
        ])
        rows.append(darkRow)
        let keys: [(String, WritableKeyPath<VataTheme, String>)] = [
            ("Highlight Color", \.highlight), ("Base Color", \.base),
            ("Text Color", \.text), ("Label Color", \.label),
            ("Sidebar Background", \.sidebarBackground), ("Sidebar Item", \.sidebarItem),
            ("Sidebar Text", \.sidebarText), ("Sidebar Selection", \.sidebarSelection),
        ]
        for (label, kp) in keys {
            rows.append(colorRow(label, key: label, get: theme.color(theme[keyPath: kp])) { [weak self] c in
                self?.setHex(kp, c)
            })
        }
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(closeWin))
        let save = NSButton(title: "Save", target: self, action: #selector(saveTheme))
        save.keyEquivalent = "\r"
        let bar = NSStackView(views: [cancel, save])
        bar.spacing = 8
        bar.alignment = .trailing
        rows.append(bar)
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: v.topAnchor, constant: 16),
        ])
    }

    private func setHex(_ kp: WritableKeyPath<VataTheme, String>, _ c: NSColor) {
        var rgb = NSColor(deviceRed: 0, green: 0, blue: 0, alpha: 1)
        c.getRed(nil, green: nil, blue: nil, alpha: nil)
        if let conv = c.usingColorSpace(.deviceRGB) {
            rgb = conv
        }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        rgb.getRed(&r, green: &g, blue: &b, alpha: &a)
        theme[keyPath: kp] = String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }

    @objc private func closeWin() {
        window?.orderOut(nil)
        Self.open.removeAll(where: { $0 === self })
    }

    @objc private func saveTheme() {
        theme.name = nameField.stringValue.isEmpty ? "Custom" : nameField.stringValue
        theme.isDark = darkToggle.state == .on
        ThemeManager.shared.saveCustom(theme)
        ThemeManager.shared.select(name: theme.name)
        window?.orderOut(nil)
        Self.open.removeAll(where: { $0 === self })
        done()
    }
}

// MARK: - Shortcut store (recordable overrides)

final class ShortcutStore {
    static let shared = ShortcutStore()
    private let key = "vata.shortcuts"
    private let commands: [VataCommand] = CommandRegistry.commands(for: PaneViewController(datasource: LocalDatasource(initialPath: "/")))

    var all: [VataCommand] { commands }

    func shortcut(for id: String) -> String {
        if let o = (UserDefaults.standard.dictionary(forKey: key) as? [String: String])?[id] { return o }
        return commands.first(where: { $0.id == id })?.shortcut ?? ""
    }

    func setShortcut(_ s: String, for id: String) {
        var d = (UserDefaults.standard.dictionary(forKey: key) as? [String: String]) ?? [:]
        d[id] = s
        UserDefaults.standard.set(d, forKey: key)
    }

    func reset() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
