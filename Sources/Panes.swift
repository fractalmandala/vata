import AppKit
import Quartz

// One pane: path field + back/forward + table listing a Datasource.
// Listing always runs off the main thread; results stream in incrementally.
// Speed baseline: no synchronous filesystem access on main, ever.
class PaneViewController: NSViewController {

    enum ViewMode: String, CaseIterable { case list, columns, icons, gallery }

    let datasource: Datasource
    var viewMode: ViewMode = .list
    private var items: [Fileinfo] = []
    private var history: [String] = []
    private var historyIndex = -1
    private var loadGeneration = 0
    var sortKey: SortKey = .name
    var sortAscending = true

    private let pathControl = NSPathControl()
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let backButton = NSButton()
    private let forwardButton = NSButton()
    private let upButton = NSButton()
    private let modeSeg = NSSegmentedControl()
    private let spinner = NSProgressIndicator()
    private let statusLabel = NSTextField(labelWithString: "")
    private let container = NSView()
    private var content: (NSViewController & PaneContent)?

    enum SortKey { case name, size, date, kind, created, lastOpened, added, count }

    static let defaultColumns = ["name", "size", "date"]
    var visibleColumns: [String] {
        get { UserDefaults.standard.stringArray(forKey: "vata.columns") ?? Self.defaultColumns }
        set { UserDefaults.standard.set(newValue, forKey: "vata.columns") }
    }

    var headerMenu: NSMenu {
        let m = NSMenu()
        m.delegate = self
        return m
    }

    init(datasource: Datasource) {
        self.datasource = datasource
        datasource.showHiddenFiles = Settings.shared.showHiddenFiles
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let root = PaneRootView()
        root.pane = self
        view = root

        let toolbar = NSStackView()
        toolbar.orientation = .horizontal
        toolbar.spacing = 6
        for (btn, title, action) in [
            (backButton, "‹", #selector(goBackward)),
            (forwardButton, "›", #selector(goForward)),
            (upButton, "⌃", #selector(goUp)),
        ] as [(NSButton, String, Selector)] {
            btn.title = title
            btn.bezelStyle = .inline
            btn.controlSize = .small
            btn.target = self
            btn.action = action
        }
        pathControl.target = self
        pathControl.action = #selector(pathChosen)
        pathControl.pathStyle = .popUp
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor
        modeSeg.segmentCount = 4
        modeSeg.setLabel("List", forSegment: 0)
        modeSeg.setLabel("Columns", forSegment: 1)
        modeSeg.setLabel("Icons", forSegment: 2)
        modeSeg.setLabel("Gallery", forSegment: 3)
        modeSeg.selectedSegment = 0
        modeSeg.target = self
        modeSeg.action = #selector(modeChanged)
        modeSeg.setContentHuggingPriority(.required, for: .horizontal)
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        toolbar.addArrangedSubview(backButton)
        toolbar.addArrangedSubview(forwardButton)
        toolbar.addArrangedSubview(upButton)
        toolbar.addArrangedSubview(pathControl)
        toolbar.addArrangedSubview(modeSeg)
        toolbar.addArrangedSubview(spinner)

        container.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [toolbar, subtitleLabel, container, statusLabel])
        stack.orientation = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
        ])
        setMode(.list)

        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged),
                                               name: .vataSettingsChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(themeChanged),
                                               name: .vataThemeChanged, object: nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        navigate(to: datasource.initialPath, record: true)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        (view.window?.windowController as? FileWindowController)?.activePane = self
    }

    func setMode(_ mode: ViewMode) {
        viewMode = mode
        if let old = content {
            old.view.removeFromSuperview()
            old.removeFromParent()
        }
        let vc = makeContentView(mode: mode)
        vc.pane = self
        vc.onSelectionChange = { [weak self] in
            guard let self else { return }
            (self.view.window?.windowController as? FileWindowController)?.activePane = self
            self.updateChrome()
        }
        vc.onOpen = { [weak self] in self?.openItem($0) }
        addChild(vc)
        if let list = vc as? ListContentView { list.headerMenu.delegate = self }
        vc.view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(vc.view)
        NSLayoutConstraint.activate([
            vc.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            vc.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            vc.view.topAnchor.constraint(equalTo: container.topAnchor),
            vc.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        content = vc
        modeSeg.selectedSegment = ViewMode.allCases.firstIndex(of: mode) ?? 0
        if !items.isEmpty { vc.show(items: items) }
    }

    @objc private func modeChanged() {
        setMode(ViewMode.allCases[modeSeg.selectedSegment])
    }

    var displayedPath: String { historyIndex >= 0 ? history[historyIndex] : datasource.initialPath }
    var selectedItems: [Fileinfo] { content?.selectedItems ?? [] }

    func selectAllContent() { content?.selectAll() }

    // MARK: - Listing (background; incremental insert)

    func navigate(to path: String, record: Bool) {
        loadGeneration += 1
        let gen = loadGeneration
        spinner.startAnimation(nil)
        pathControl.url = URL(fileURLWithPath: path)
        RecentStore.shared.visited(path)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let listed: [Fileinfo]
            do { listed = try self.datasource.list(path, useCache: true) }
            catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self, gen == self.loadGeneration else { return }
                    self.spinner.stopAnimation(nil)
                    NSSound.beep()
                }
                return
            }
            let sorted = self.applySort(to: listed)
            DispatchQueue.main.async { [weak self] in
                guard let self, gen == self.loadGeneration else { return }
                self.display(sorted, path: path, record: record, generation: gen)
            }
        }
    }

    /// Shows pre-listed items (tag searches, archives) without a datasource round-trip.
    func display(_ sorted: [Fileinfo], path: String, record: Bool, generation gen: Int? = nil) {
        let gen = gen ?? loadGeneration
        if record {
            if historyIndex < history.count - 1 {
                history.removeSubrange(historyIndex + 1 ..< history.count)
            }
            history.append(path)
            historyIndex = history.count - 1
        }
        datasource.lastVisitedPath = path
        pathControl.url = URL(fileURLWithPath: path, isDirectory: true)
        items = []
        content?.show(items: [])
        let chunk = 500
        var i = 0
        func insertNext() {
            guard gen == self.loadGeneration else { return }
            let end = min(i + chunk, sorted.count)
            self.items.append(contentsOf: sorted[i..<end])
            self.content?.show(items: self.items)
            i = end
            if i < sorted.count {
                DispatchQueue.main.async(execute: insertNext)
            } else {
                self.spinner.stopAnimation(nil)
            }
        }
        insertNext()
        updateChrome()
        fillChildCounts(sorted)
    }

    /// Direct-children counts (non-recursive), filled off-main after the
    /// listing lands so the first paint never waits on extra stats.
    private func fillChildCounts(_ listed: [Fileinfo]) {
        let gen = loadGeneration
        let folders = listed.filter { $0.type == .folder && $0.childCount == nil }
        guard !folders.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let fm = FileManager.default
            for f in folders {
                f.childCount = (try? fm.contentsOfDirectory(atPath: f.fullPath).count) ?? 0
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, gen == self.loadGeneration else { return }
                self.content?.show(items: self.items)
            }
        }
    }

    func navigateToTag(colorName: String, color: NSColor) {
        loadGeneration += 1
        let gen = loadGeneration
        spinner.startAnimation(nil)
        let query = NSMetadataQuery()
        query.predicate = NSPredicate(format: "%K CONTAINS %@",
                                      "kMDItemUserTags", colorName.lowercased())
        query.searchScopes = [NSMetadataQueryLocalComputerScope]
        let nc = NotificationCenter.default
        var token: NSObjectProtocol?
        token = nc.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query, queue: nil) { [weak self] _ in
            guard let self else { return }
            if let t = token { nc.removeObserver(t) }
            query.stop()
            var results: [Fileinfo] = []
            for item in (query.results as? [NSMetadataItem] ?? []).prefix(2000) {
                if let p = item.value(forAttribute: "kMDItemPath") as? String {
                    let info = Fileinfo(fullPath: p)
                    info.local = true
                    info.type = FileManager.default.fileExists(atPath: p, isDirectory: nil) ? .file : .file
                    var isDir: ObjCBool = false
                    if FileManager.default.fileExists(atPath: p, isDirectory: &isDir), isDir.boolValue {
                        info.type = .folder
                    }
                    results.append(info)
                }
            }
            let sorted = self.applySort(to: results)
            DispatchQueue.main.async { [weak self] in
                guard let self, gen == self.loadGeneration else { return }
                self.spinner.stopAnimation(nil)
                self.display(sorted, path: "tag:\(colorName.lowercased())", record: true, generation: gen)
            }
        }
        query.start()
    }

    func refresh() {
        datasource.clearCache()
        navigate(to: displayedPath, record: false)
    }

    func applySort(to list: [Fileinfo]) -> [Fileinfo] {
        list.sorted { a, b in
            if (a.type == .folder) != (b.type == .folder) { return a.type == .folder }
            let cmp: ComparisonResult
            switch sortKey {
            case .name: cmp = a.name.localizedStandardCompare(b.name)
            case .kind: cmp = a.kindLabel.localizedStandardCompare(b.kindLabel)
            case .created:
                cmp = (a.createdDate ?? .distantPast).compare(b.createdDate ?? .distantPast)
            case .lastOpened:
                cmp = (a.lastOpenedDate ?? .distantPast).compare(b.lastOpenedDate ?? .distantPast)
            case .added:
                cmp = (a.addedDate ?? .distantPast).compare(b.addedDate ?? .distantPast)
            case .count:
                cmp = (a.childCount ?? -1) == (b.childCount ?? -1) ? .orderedSame : ((a.childCount ?? -1) < (b.childCount ?? -1) ? .orderedAscending : .orderedDescending)
            case .size: cmp = a.size == b.size ? .orderedSame : (a.size < b.size ? .orderedAscending : .orderedDescending)
            case .date:
                let da = a.modificationDate ?? .distantPast
                let db = b.modificationDate ?? .distantPast
                cmp = da.compare(db)
            }
            return sortAscending ? cmp == .orderedAscending : cmp == .orderedDescending
        }
    }

    func applySortDescriptor(_ sd: NSSortDescriptor?) {
        guard let key = sd?.key else { return }
        switch key {
        case "size": sortKey = .size
        case "date": sortKey = .date
        case "kind": sortKey = .kind
        case "created": sortKey = .created
        case "lastOpened": sortKey = .lastOpened
        case "added": sortKey = .added
        case "count": sortKey = .count
        default: sortKey = .name
        }
        sortAscending = sd?.ascending ?? true
        refresh()
    }

    private func updateChrome() {
        backButton.isEnabled = historyIndex > 0
        forwardButton.isEnabled = historyIndex < history.count - 1
        let sel = selectedItems
        let free = availableSpace(at: displayedPath)
        if sel.isEmpty {
            statusLabel.stringValue = "\(items.count) items" + (free.map { ", \($0) available" } ?? "")
        } else {
            let bytes = sel.reduce(0) { $0 + max($1.size, 0) }
            statusLabel.stringValue = "\(sel.count) of \(items.count) selected" + (free.map { ", \($0) available" } ?? "") + " — \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))"
        }
        subtitleLabel.stringValue = statusLabel.stringValue
    }

    private func availableSpace(at path: String) -> String? {
        guard let vals = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.volumeAvailableCapacityKey]),
              let bytes = vals.volumeAvailableCapacity else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    @objc private func settingsChanged() {
        datasource.showHiddenFiles = Settings.shared.showHiddenFiles
        refresh()
    }

    @objc private func themeChanged() {
        content?.show(items: items)
    }
    @objc private func pathChosen() {
        guard let url = pathControl.url, url.isFileURL else { return }
        navigate(to: url.path, record: true)
    }

    @objc func goBackward() {
        guard historyIndex > 0 else { return }
        historyIndex -= 1
        navigate(to: history[historyIndex], record: false)
    }

    @objc func goForward() {
        guard historyIndex < history.count - 1 else { return }
        historyIndex += 1
        navigate(to: history[historyIndex], record: false)
    }

    @objc func goUp() {
        let parent = (displayedPath as NSString).deletingLastPathComponent
        guard parent != displayedPath else { return }
        navigate(to: parent, record: true)
    }

    @objc func cycleSort() {
        switch sortKey {
        case .name: sortKey = .size
        case .size: sortKey = .date
        case .date: sortKey = .kind
        case .kind: sortKey = .created
        case .created: sortKey = .lastOpened
        case .lastOpened: sortKey = .added
        case .added: sortKey = .count
        case .count: sortKey = .name; sortAscending.toggle()
        }
        refresh()
    }

    func openItem(_ item: Fileinfo) {
        if item.type == .folder { navigate(to: item.fullPath, record: true) }
        else if FileOps.isArchive(item) { FileOps.extract(item: item, in: self) }
        else { NSWorkspace.shared.open(URL(fileURLWithPath: item.fullPath)) }
    }

    func promptRename(items: [Fileinfo]) {
        guard let item = items.first else { return }
        let alert = NSAlert()
        alert.messageText = "Rename “\(item.name)”"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = item.name
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn, !field.stringValue.isEmpty,
           field.stringValue != item.name {
            FileOps.rename(item: item, to: field.stringValue, in: self)
        }
    }

    // MARK: - Context menu

    private func buildContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        return menu
    }

    func contextMenu() -> NSMenu { buildContextMenu() }

    func toggleQuickLook() {
        PreviewDelegate.shared.pane = self
        if QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible {
            QLPreviewPanel.shared().orderOut(nil)
        } else {
            QLPreviewPanel.shared().makeKeyAndOrderFront(nil)
        }
    }

    func showPreviewPane() {
        guard let item = selectedOrClicked().first,
              let wc = view.window?.windowController as? FileWindowController else { return }
        wc.showPreview(item: item)
    }
}

// Root view intercepts right-clicks and shows OUR menu panel — never an
// NSMenu, so the system has nothing to inject into.
final class PaneRootView: NSView {
    weak var pane: PaneViewController?
    override func rightMouseDown(with event: NSEvent) {
        pane?.showManualMenu(event: event)
    }
    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { nil }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        validatePaneDrop(sender)
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        validatePaneDrop(sender)
    }
    private func validatePaneDrop(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard pane != nil,
              let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
              !urls.isEmpty else { return [] }
        return NSEvent.modifierFlags.contains(.option) ? .copy : .move
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let pane,
              let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] else { return false }
        let dest = URL(fileURLWithPath: pane.displayedPath)
        let opt = NSEvent.modifierFlags.contains(.option)
        let sameVol = urls.first.map { FileOps.sameVolume($0, dest) } ?? false
        FileOps.performDrop(FileOps.decideDrop(urls: urls, destDir: dest, sourceDir: nil, optionKey: opt, sameVolume: sameVol), in: pane)
        return true
    }
}

// Cell text field that lets right-clicks fall through to the table row,
// so the ONLY context menu is ours. See menuWillOpen tag/strip below.
final class RowTextField: NSTextField {
    override func rightMouseDown(with event: NSEvent) {
        superview?.rightMouseDown(with: event)
    }
}

final class HeaderStore {
    static let shared = HeaderStore()
    private let key = "vata.headerPins"
    var paths: [String] {
        get {
            if UserDefaults.standard.object(forKey: key) == nil { return HeaderStore.defaults }
            return UserDefaults.standard.stringArray(forKey: key) ?? []
        }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
    static var defaults: [String] {
        var pins = [NSHomeDirectory(), "/Applications",
                      (NSHomeDirectory() as NSString).appendingPathComponent("Desktop"),
                      (NSHomeDirectory() as NSString).appendingPathComponent("Downloads")]
        let icloud = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        if FileManager.default.fileExists(atPath: icloud) { pins.append(icloud) }
        return pins
    }
    func add(_ path: String) {
        var p = paths
        if !p.contains(path) { p.append(path); paths = p }
    }
    func remove(_ path: String) { paths = paths.filter { $0 != path } }
}

extension PaneViewController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        stripUntagged(menu)
    }

    private func stripUntagged(_ menu: NSMenu) {
        for item in menu.items {
            if let sub = item.submenu { stripUntagged(sub); continue }
            if item.identifier?.rawValue != "vata" { menu.removeItem(item) }
        }
    }

    private func tag(_ menu: NSMenu) {
        for item in menu.items {
            if let sub = item.submenu { tag(sub); continue }
            item.identifier = NSUserInterfaceItemIdentifier("vata")
        }
    }

    // Header (column) menu stays an NSMenu — the system doesn't inject there.
    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === (content as? ListContentView)?.headerMenu {
            buildHeaderMenu(menu)
        }
    }

    // Row context menu: popped up manually (not via view.menu auto-display).
    // ForkLift's own menu proves a manually-shown NSMenu stays clean;
    // the tag/strip in menuWillOpen remains as belt-and-braces.
    func showManualMenu(event: NSEvent) {
        let menu = buildRowMenu()
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    func buildRowMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        let items = selectedOrClicked()
        let one = items.count == 1
        func add(_ title: String, _ sel: Selector, enabled: Bool = true) {
            let mi = menu.addItem(withTitle: title, action: sel, keyEquivalent: "")
            mi.target = self
            mi.isEnabled = enabled
        }
        add("Open", #selector(ctxOpen))
        add("Open in New Window", #selector(ctxNewWindow))
        add("Show Preview", #selector(ctxPreview))
        menu.addItem(.separator())
        add("Cut", #selector(ctxCut))
        add("Copy", #selector(ctxCopy))
        add("Copy Path", #selector(ctxCopyPath))
        add("Paste Item", #selector(ctxPaste), enabled: FileOps.hasPasteboardURLs())
        menu.addItem(.separator())
        add("Rename", #selector(ctxRename), enabled: one)
        add("Duplicate", #selector(ctxDuplicate))
        add("Make Alias", #selector(ctxAlias))
        add("Extract Here", #selector(ctxExtract), enabled: items.contains(where: { FileOps.isArchive($0) }))
        add("Move to Trash", #selector(ctxTrash))
        menu.addItem(.separator())
        add("Get Info", #selector(ctxInfo))
        add("Add to Favorites", #selector(ctxPin))
        add("Quick Look", #selector(ctxQuickLook))
        let qa = NSMenuItem(title: "Quick Actions", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for action in Settings.shared.quickActions {
            let mi = sub.addItem(withTitle: action.title, action: #selector(ctxQuickAction(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = action.id
        }
        sub.addItem(.separator())
        let cfg = sub.addItem(withTitle: "Configure…", action: #selector(ctxConfigureQA), keyEquivalent: "")
        cfg.target = self
        qa.submenu = sub
        menu.addItem(qa)
        tag(menu)
        return menu
    }


    private func buildHeaderMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let titles = ["name": "Name", "size": "Size", "date": "Modified",
                        "kind": "Kind", "created": "Created", "lastOpened": "Last Opened",
                        "added": "Added", "count": "Items"]
        for id in ["name", "size", "date", "kind", "created", "lastOpened", "added", "count"] {
            let mi = menu.addItem(withTitle: titles[id]!, action: #selector(toggleColumn(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = id
            mi.identifier = NSUserInterfaceItemIdentifier("vata")
            mi.state = visibleColumns.contains(id) ? .on : .off
            if id == "name" { mi.isEnabled = false }
        }
    }

    @objc private func toggleColumn(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, id != "name" else { return }
        var vis = visibleColumns
        if vis.contains(id) { vis.removeAll(where: { $0 == id }) }
        else { vis.append(id) }
        visibleColumns = vis
        (content as? ListContentView)?.applyColumnVisibility()
    }

    private func selectedOrClicked() -> [Fileinfo] {
        if let clicked = content?.clickedItem,
           !selectedItems.contains(where: { $0.fullPath == clicked.fullPath }) {
            return [clicked]
        }
        return selectedItems
    }

    @objc private func ctxOpen() { if let i = selectedOrClicked().first { openItem(i) } }
    @objc private func ctxPreview() { showPreviewPane() }
    @objc private func ctxNewWindow() {
        guard let item = selectedOrClicked().first else { return }
        let path = item.type == .folder ? item.fullPath : (item.fullPath as NSString).deletingLastPathComponent
        (view.window?.windowController as? FileWindowController)?.openNewWindow(path: path)
    }
    @objc private func ctxCut() { FileOps.copyToPasteboard(items: selectedOrClicked(), cut: true) }
    @objc private func ctxCopy() { FileOps.copyToPasteboard(items: selectedOrClicked(), cut: false) }
    @objc private func ctxCopyPath() { FileOps.copyPaths(items: selectedOrClicked()) }
    @objc private func ctxPaste() { FileOps.paste(into: self) }
    @objc private func ctxTrash() { FileOps.trash(items: selectedOrClicked(), in: self) }
    @objc private func ctxDuplicate() { FileOps.duplicate(items: selectedOrClicked(), in: self) }
    @objc private func ctxAlias() { FileOps.makeAlias(items: selectedOrClicked(), in: self) }
    @objc private func ctxExtract() {
        for item in selectedOrClicked() where FileOps.isArchive(item) {
            FileOps.extract(item: item, in: self)
        }
    }
    @objc private func ctxInfo() { FileOps.showGetInfo(for: selectedOrClicked()) }
    @objc private func ctxPin() {
        guard let wc = view.window?.windowController as? FileWindowController else { return }
        for item in selectedOrClicked() { HeaderStore.shared.add(item.fullPath) }
        wc.sidebarReload()
    }
    @objc private func ctxQuickLook() { toggleQuickLook() }
    @objc private func ctxRename() { content?.beginRename() }
    @objc private func ctxQuickAction(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let action = Settings.shared.quickActions.first(where: { $0.id == id }),
              let item = selectedOrClicked().first else { return }
        action.run(on: item.fullPath)
    }
    @objc private func ctxConfigureQA() {
        SettingsWindowController.shared.show(tab: .quickActions)
    }
}

// Window with 1–4 panes plus header pins.
// Pins live in the window TITLE BAR (NSToolbar), not in content.
// Two-pane window, ForkLift parity: sidebar (Devices/Recent/Tags),
// title-bar toolbar (pins + actions), breadcrumb panes in an H-split.
final class FileWindowController: NSWindowController {

    private(set) var panes: [PaneViewController] = []
    weak var activePane: PaneViewController?
    var leftPane: PaneViewController { panes[0] }
    var rightPane: PaneViewController { panes.count > 1 ? panes[1] : panes[0] }
    private var sidebar: SidebarViewController?

    static func startDirectory() -> String {
        switch UserDefaults.standard.string(forKey: "vata.startDir") ?? "Home" {
        case "Desktop": return (NSHomeDirectory() as NSString).appendingPathComponent("Desktop")
        case "Documents": return (NSHomeDirectory() as NSString).appendingPathComponent("Documents")
        case "Downloads": return (NSHomeDirectory() as NSString).appendingPathComponent("Downloads")
        case "Applications": return "/Applications"
        default: return NSHomeDirectory()
        }
    }

    init(initialPath: String? = nil) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1300, height: 750),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Vātā"
        window.minSize = NSSize(width: 800, height: 500)
        super.init(window: window)
        panes = [
            PaneViewController(datasource: LocalDatasource(initialPath: initialPath ?? Self.startDirectory())),
            PaneViewController(datasource: LocalDatasource(initialPath: "/Applications")),
        ]
        activePane = panes[0]
        rebuildContent()
        window.center()
    }

    required init?(coder: NSCoder) { nil }

    private func rebuildContent() {
        guard let window else { return }
        for pane in panes { _ = pane.view }
        sidebar = sidebar ?? SidebarViewController()
        sidebar?.windowController = self
        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.addArrangedSubview(sidebar!.view)
        sidebar!.view.widthAnchor.constraint(greaterThanOrEqualToConstant: 170).isActive = true
        sidebar!.view.widthAnchor.constraint(lessThanOrEqualToConstant: 260).isActive = true
        for pane in panes { split.addArrangedSubview(pane.view) }
        split.autosaveName = "VataMainSplit"
        split.setPosition(220, ofDividerAt: 0)
        let host = NSViewController()
        host.view = NSView()
        split.translatesAutoresizingMaskIntoConstraints = false
        host.view.addSubview(split)
        NSLayoutConstraint.activate([
            split.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: host.view.trailingAnchor),
            split.topAnchor.constraint(equalTo: host.view.topAnchor),
            split.bottomAnchor.constraint(equalTo: host.view.bottomAnchor),
        ])
        window.contentViewController = host
        if activePane == nil { activePane = panes.first }
    }

    func sidebarReload() { sidebar?.reload() }

    func pinSelected() {
        guard let item = activePane?.selectedItems.first else { return }
        HeaderStore.shared.add(item.fullPath)
        sidebar?.reload()
    }

    func swapPanes() {
        guard panes.count == 2 else { return }
        panes.swapAt(0, 1)
        rebuildContent()
    }

    func clonePane() {
        guard let active = activePane else { return }
        let other = panes.first(where: { $0 !== active }) ?? active
        other.navigate(to: active.displayedPath, record: true)
    }

    // MARK: - Preview pane slot (replaces the inactive pane temporarily)

    private var stashedPane: (Int, PaneViewController)?
    private var prePreviewActive: PaneViewController?

    var isPreviewShowing: Bool { panes.contains(where: { $0 is PreviewPaneController }) }

    func showPreview(item: Fileinfo) {
        if isPreviewShowing { closePreview() }
        prePreviewActive = activePane
        let at: Int
        if let active = activePane, let i = panes.firstIndex(where: { $0 === active }) {
            at = (i + 1) % max(panes.count, 1)
        } else {
            at = panes.count - 1
        }
        stashedPane = (at, panes[at])
        panes[at] = PreviewPaneController(item: item)
        activePane = panes[at == 0 ? 1 : 0]
        rebuildContent()
    }

    func closePreview() {
        if let (i, original) = stashedPane, i < panes.count {
            panes[i] = original
            stashedPane = nil
        } else {
            panes.removeAll(where: { $0 is PreviewPaneController })
        }
        activePane = prePreviewActive ?? panes.first
        prePreviewActive = nil
        rebuildContent()
    }

    func togglePreview(item: Fileinfo?) {
        if isPreviewShowing { closePreview() }
        else if let item { showPreview(item: item) }
    }

    func openNewWindow(path: String) {
        let wc = FileWindowController(initialPath: path)
        wc.showWindow(nil)
        AppDelegate.openWindows.append(wc)
    }
}
