import AppKit

// Per-pane view modes. Every view renders pane.items, reports selection
// back, and opens through the pane — context menu, palette, and shortcuts
// stay unified (they only ever talk to PaneViewController).
protocol PaneContent: AnyObject {
    var selectedItems: [Fileinfo] { get }
    var clickedItem: Fileinfo? { get }
    var pane: PaneViewController? { get set }
    func show(items: [Fileinfo])
    func beginRename()
    func selectAll()
    var onSelectionChange: (() -> Void)? { get set }
    var onOpen: ((Fileinfo) -> Void)? { get set }
}

extension PaneContent {
    func selectAll() {}
}

func makeContentView(mode: PaneViewController.ViewMode) -> NSViewController & PaneContent {
    switch mode {
    case .list: return ListContentView()
    case .icons: return IconContentView()
    case .columns: return ColumnContentView()
    case .gallery: return GalleryContentView()
    }
}

func cellImage(for item: Fileinfo, dark: Bool) -> NSImage? {
    FileIcons.shared.icon(for: item, dark: dark)
}

// MARK: - List

final class ListContentView: NSViewController, PaneContent {
    let outline = NSOutlineView()
    let headerMenu = NSMenu()
    var onSelectionChange: (() -> Void)?
    var onOpen: ((Fileinfo) -> Void)?
    private var items: [Fileinfo] = []
    private var childCache: [String: [Fileinfo]] = [:]
    weak var pane: PaneViewController?

    var selectedItems: [Fileinfo] {
        outline.selectedRowIndexes.compactMap { outline.item(atRow: $0) as? Fileinfo }
    }
    var clickedItem: Fileinfo? {
        let r = outline.clickedRow
        return (r >= 0) ? (outline.item(atRow: r) as? Fileinfo) : nil
    }
    func beginRename() {
        guard let first = selectedItems.first else { return }
        let row = outline.row(forItem: first)
        guard row >= 0 else { return }
        outline.editColumn(0, row: row, with: nil, select: true)
    }

    func selectAll() {
        outline.selectAll(nil)
    }

    override func loadView() {
        view = NSView()
        for (id, title, w) in [("name", "Name", 220.0), ("size", "Size", 90.0),
                               ("date", "Modified", 150.0), ("kind", "Kind", 110.0),
                               ("created", "Created", 150.0), ("lastOpened", "Last Opened", 150.0),
                               ("added", "Added", 150.0), ("count", "Items", 70.0)] {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            col.title = title
            col.width = w
            col.sortDescriptorPrototype = NSSortDescriptor(key: id, ascending: true)
            outline.addTableColumn(col)
        }
        outline.outlineTableColumn = outline.tableColumns.first
        outline.delegate = self
        outline.dataSource = self
        outline.doubleAction = #selector(rowDoubleClicked)
        outline.target = self
        outline.allowsMultipleSelection = true
        outline.registerForDraggedTypes([.fileURL])
        outline.setDraggingSourceOperationMask([.move, .copy], forLocal: true)
        outline.setDraggingSourceOperationMask([.copy], forLocal: false)
        let scroll = NSScrollView()
        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private var expandedPaths = Set<String>()
    func show(items: [Fileinfo]) {
        self.items = items
        outline.reloadData()
        for item in items where item.type == .folder && expandedPaths.contains(item.fullPath) {
            outline.expandItem(item)
        }
        applyColumnVisibility()
    }

    func applyColumnVisibility() {
        guard let pane else { return }
        for col in outline.tableColumns {
            col.isHidden = !pane.visibleColumns.contains(col.identifier.rawValue)
        }
        outline.headerView?.menu = headerMenu
    }

    @objc private func rowDoubleClicked() {
        let r = outline.clickedRow
        guard r >= 0, let item = outline.item(atRow: r) as? Fileinfo else { return }
        onOpen?(item)
    }

    func setObjectValue(object: Any?, item: Fileinfo) {
        guard let name = object as? String, !name.isEmpty,
              name != item.name, let pane else { return }
        FileOps.rename(item: item, to: name, in: pane)
    }
}

extension ListContentView: NSOutlineViewDataSource, NSOutlineViewDelegate {
    func outlineView(_ ov: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let info = item as? Fileinfo else { return items.count }
        return childCache[info.fullPath]?.count ?? 0
    }

    func outlineView(_ ov: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let info = item as? Fileinfo else { return items[index] }
        return childCache[info.fullPath]![index]
    }

    func outlineView(_ ov: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? Fileinfo)?.type == .folder
    }

    func outlineView(_ ov: NSOutlineView, shouldExpandItem item: Any) -> Bool {
        guard let info = item as? Fileinfo, childCache[info.fullPath] == nil,
              let pane else { return true }
        let path = info.fullPath
        DispatchQueue.global(qos: .userInitiated).async { [weak self, weak pane] in
            guard let list = try? pane?.datasource.list(path, useCache: true) else { return }
            let sorted = pane?.applySort(to: list) ?? list
            DispatchQueue.main.async {
                self?.childCache[path] = sorted
                self?.outline.reloadItem(item, reloadChildren: true)
                self?.outline.expandItem(item)
            }
        }
        return false
    }

    func outlineView(_ ov: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let info = item as? Fileinfo else { return nil }
        let id = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("name")
        let cell = ov.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = id
        if cell.textField == nil {
            let tf = RowTextField(labelWithString: "")
            tf.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(tf)
            cell.textField = tf
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 22),
                tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            let iv = NSImageView()
            iv.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(iv)
            NSLayoutConstraint.activate([
                iv.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                iv.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                iv.widthAnchor.constraint(equalToConstant: 16),
                iv.heightAnchor.constraint(equalToConstant: 16),
            ])
        }
        let dark = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        for sub in cell.subviews where sub is NSImageView && id.rawValue == "name" {
            (sub as? NSImageView)?.image = cellImage(for: info, dark: dark)
        }
        switch id.rawValue {
        case "size":
            cell.textField?.stringValue = info.type == .folder ? "—" : ByteCountFormatter.string(fromByteCount: max(info.size, 0), countStyle: .file)
        case "date":
            cell.textField?.stringValue = info.modificationDate.map {
                DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .short) } ?? "—"
        case "kind": cell.textField?.stringValue = info.kindLabel
        case "created":
            cell.textField?.stringValue = info.createdDate.map {
                DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .short) } ?? "—"
        case "lastOpened":
            cell.textField?.stringValue = info.lastOpenedDate.map {
                DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .short) } ?? "—"
        case "added":
            cell.textField?.stringValue = info.addedDate.map {
                DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .short) } ?? "—"
        case "count":
            if info.type == .folder, let n = info.childCount {
                cell.textField?.stringValue = "\(n)"
            } else {
                cell.textField?.stringValue = "—"
            }
        default:
            cell.textField?.stringValue = info.name
            cell.textField?.isEditable = true
        }
        return cell
    }

    func outlineView(_ ov: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        VataRowView()
    }

    func outlineView(_ ov: NSOutlineView, writeItems items: [Any], to pb: NSPasteboard) -> Bool {
        let urls = items.compactMap { ($0 as? Fileinfo).map { URL(fileURLWithPath: $0.fullPath) } }
        guard !urls.isEmpty else { return false }
        pb.writeObjects(urls as [NSURL])
        return true
    }

    private func dropTarget(for ov: NSOutlineView, info: NSDraggingInfo) -> URL? {
        guard let pane, pane.displayedPath.hasPrefix("/") else { return nil }
        let row = ov.row(at: info.draggingLocation)
        if row >= 0, let item = ov.item(atRow: row) as? Fileinfo, item.type == .folder {
            return URL(fileURLWithPath: item.fullPath)
        }
        return URL(fileURLWithPath: pane.displayedPath)
    }

    func outlineView(_ ov: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        guard dropTarget(for: ov, info: info) != nil,
              let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty else {
            return []
        }
        ov.setDropItem(nil, dropChildIndex: NSOutlineViewDropOnItemIndex)
        return NSEvent.modifierFlags.contains(.option) ? .copy : .move
    }

    func outlineView(_ ov: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        guard let pane,
              let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
              let dest = dropTarget(for: ov, info: info) else { return false }
        let opt = NSEvent.modifierFlags.contains(.option)
        let sameVol = urls.first.map { FileOps.sameVolume($0, dest) } ?? false
        FileOps.performDrop(FileOps.decideDrop(urls: urls, destDir: dest, sourceDir: nil, optionKey: opt, sameVolume: sameVol), in: pane)
        return true
    }

    func outlineViewSelectionDidChange(_ notification: Notification) { onSelectionChange?() }

    func outlineViewItemDidExpand(_ notification: Notification) {
        if let info = notification.userInfo?["NSObject"] as? Fileinfo { expandedPaths.insert(info.fullPath) }
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        if let info = notification.userInfo?["NSObject"] as? Fileinfo { expandedPaths.remove(info.fullPath) }
    }

    func outlineView(_ ov: NSOutlineView, sortDescriptorsDidChange old: [NSSortDescriptor]) {
        pane?.applySortDescriptor(ov.sortDescriptors.first)
    }

    func outlineView(_ ov: NSOutlineView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, byItem item: Any?) {
        if let info = item as? Fileinfo { setObjectValue(object: object, item: info) }
    }
}

// MARK: - Icons

final class IconCellView: NSCollectionViewItem {
    static let id = NSUserInterfaceItemIdentifier("iconCell")
    override func loadView() {
        view = NSView()
        let iv = NSImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(iv)
        let tf = NSTextField(labelWithString: "")
        tf.alignment = .center
        tf.font = .systemFont(ofSize: 11)
        tf.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tf)
        NSLayoutConstraint.activate([
            iv.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
            iv.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            iv.widthAnchor.constraint(equalToConstant: 48),
            iv.heightAnchor.constraint(equalToConstant: 48),
            tf.topAnchor.constraint(equalTo: iv.bottomAnchor, constant: 2),
            tf.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tf.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }
    func configure(_ item: Fileinfo, dark: Bool) {
        ((view.subviews.first { $0 is NSImageView }) as? NSImageView)?.image = cellImage(for: item, dark: dark)
        ((view.subviews.first { !($0 is NSImageView) }) as? NSTextField)?.stringValue = item.name
    }
    override var isSelected: Bool {
        didSet { view.layer?.backgroundColor = isSelected ? NSColor.selectedContentBackgroundColor.cgColor : nil }
    }
}

final class IconContentView: NSViewController, PaneContent {
    private var collection: NSCollectionView!
    private var items: [Fileinfo] = []
    var onSelectionChange: (() -> Void)?
    var onOpen: ((Fileinfo) -> Void)?
    weak var pane: PaneViewController?

    var selectedItems: [Fileinfo] {
        collection.selectionIndexPaths.compactMap { $0.item < items.count ? items[$0.item] : nil }
    }
    var clickedItem: Fileinfo? {
        guard let ev = NSApp.currentEvent, ev.type == .rightMouseDown else { return nil }
        let pt = collection.convert(ev.locationInWindow, from: nil)
        guard let ip = collection.indexPathForItem(at: pt), ip.item < items.count else { return nil }
        return items[ip.item]
    }
    func beginRename() { pane?.promptRename(items: selectedItems) }

    override func loadView() {
        view = NSView()
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 96, height: 84)
        layout.minimumInteritemSpacing = 8
        layout.minimumLineSpacing = 8
        layout.sectionInset = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        collection = NSCollectionView()
        collection.collectionViewLayout = layout
        collection.register(IconCellView.self, forItemWithIdentifier: IconCellView.id)
        collection.dataSource = self
        collection.delegate = self
        collection.allowsMultipleSelection = true
        collection.isSelectable = true
        let scroll = NSScrollView()
        scroll.documentView = collection
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    func show(items: [Fileinfo]) {
        self.items = items
        collection.reloadData()
    }
}

extension IconContentView: NSCollectionViewDataSource, NSCollectionViewDelegate {
    func collectionView(_ cv: NSCollectionView, numberOfItemsInSection s: Int) -> Int { items.count }
    func collectionView(_ cv: NSCollectionView, itemForRepresentedObjectAt ip: IndexPath) -> NSCollectionViewItem {
        let cell = cv.makeItem(withIdentifier: IconCellView.id, for: ip) as! IconCellView
        let dark = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        cell.configure(items[ip.item], dark: dark)
        return cell
    }
    func collectionView(_ cv: NSCollectionView, didSelectItemsAt paths: Set<IndexPath>) { onSelectionChange?() }
    func collectionView(_ cv: NSCollectionView, didDeselectItemsAt paths: Set<IndexPath>) { onSelectionChange?() }
}

// MARK: - Columns (Miller: parent | current | selected-children)

final class ColumnContentView: NSViewController, PaneContent {
    var browser: NSBrowser!
    private var parentItems: [Fileinfo] = []
    private var currentItems: [Fileinfo] = []
    private var childItems: [Fileinfo] = []
    private var currentPath = "/"
    var onSelectionChange: (() -> Void)?
    var onOpen: ((Fileinfo) -> Void)?
    weak var pane: PaneViewController?

    private var selectedInCurrent: Fileinfo?
    private var selectedInChild: Fileinfo?

    var selectedItems: [Fileinfo] {
        if let s = selectedInChild { return [s] }
        if let s = selectedInCurrent { return [s] }
        return []
    }
    var clickedItem: Fileinfo? { selectedItems.first }
    func beginRename() { pane?.promptRename(items: selectedItems) }

    override func loadView() {
        view = NSView()
        browser = NSBrowser()
        browser.delegate = self
        browser.doubleAction = #selector(leafDoubleClicked)
        browser.target = self
        browser.separatesColumns = true
        browser.minColumnWidth = 180
        browser.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(browser)
        NSLayoutConstraint.activate([
            browser.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            browser.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            browser.topAnchor.constraint(equalTo: view.topAnchor),
            browser.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    func show(items: [Fileinfo]) {
        guard let pane else { return }
        currentPath = pane.displayedPath
        currentItems = items
        let parent = (currentPath as NSString).deletingLastPathComponent
        parentItems = (try? pane.datasource.list(parent == currentPath ? "/" : parent, useCache: true)) ?? []
        if parent == currentPath { parentItems = [] }
        selectedInCurrent = nil
        selectedInChild = nil
        childItems = []
        browser.loadColumnZero()
    }

    private func children(of item: Fileinfo) -> [Fileinfo] {
        guard let pane, item.type == .folder else { return [] }
        return (try? pane.datasource.list(item.fullPath, useCache: true)) ?? []
    }

    @objc private func leafDoubleClicked() {
        if let item = selectedItems.first { onOpen?(item) }
    }
}

extension ColumnContentView: NSBrowserDelegate {
    func browser(_ b: NSBrowser, numberOfRowsInColumn c: Int) -> Int {
        switch c {
        case 0: return parentItems.count
        case 1: return currentItems.count
        case 2: return childItems.count
        default: return 0
        }
    }

    func browser(_ sender: NSBrowser, willDisplayCell cell: Any, atRow row: Int, column col: Int) {
        guard let c = cell as? NSBrowserCell else { return }
        let item: Fileinfo?
        switch col {
        case 0: item = row < parentItems.count ? parentItems[row] : nil
        case 1: item = row < currentItems.count ? currentItems[row] : nil
        case 2: item = row < childItems.count ? childItems[row] : nil
        default: item = nil
        }
        guard let item else { return }
        c.title = item.name
        c.image = cellImage(for: item, dark: false)
        c.isLeaf = item.type != .folder
    }

    func browser(_ sender: NSBrowser, isColumnValid col: Int) -> Bool {
        col == 0 || col == 1 || (col == 2 && !childItems.isEmpty)
    }

    func browser(_ sender: NSBrowser, didChangeLastColumn col: Int, toRow row: Int) {
        if col == 1, row >= 0, row < currentItems.count {
            selectedInCurrent = currentItems[row]
            selectedInChild = nil
            childItems = children(of: currentItems[row])
            sender.reloadColumn(2)
        } else if col == 2, row >= 0, row < childItems.count {
            selectedInChild = childItems[row]
        } else if col == 0 {
            selectedInCurrent = nil
            selectedInChild = nil
            childItems = []
            sender.reloadColumn(2)
        }
        onSelectionChange?()
    }
}

// MARK: - Gallery (filmstrip + preview)

final class GalleryContentView: NSViewController, PaneContent {
    private var previewImage = NSImageView()
    private var previewText = NSTextView()
    private var previewInfo = NSTextField(labelWithString: "")
    private var strip: NSCollectionView!
    private var items: [Fileinfo] = []
    private var selected = IndexSet()
    var onSelectionChange: (() -> Void)?
    var onOpen: ((Fileinfo) -> Void)?
    weak var pane: PaneViewController?

    var selectedItems: [Fileinfo] { selected.compactMap { $0 < items.count ? items[$0] : nil } }
    var clickedItem: Fileinfo? { selectedItems.first }
    func beginRename() { pane?.promptRename(items: selectedItems) }

    override func loadView() {
        view = NSView()
        previewImage.translatesAutoresizingMaskIntoConstraints = false
        previewImage.imageScaling = .scaleProportionallyUpOrDown
        previewImage.setContentHuggingPriority(.defaultLow, for: .vertical)
        previewText.isEditable = false
        previewText.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        let previewScroll = NSScrollView()
        previewScroll.documentView = previewText
        previewScroll.hasVerticalScroller = true
        previewScroll.translatesAutoresizingMaskIntoConstraints = false
        previewScroll.heightAnchor.constraint(equalToConstant: 260).isActive = true
        previewInfo.font = .systemFont(ofSize: 12)
        previewInfo.translatesAutoresizingMaskIntoConstraints = false
        let top = NSStackView(views: [previewImage, previewScroll, previewInfo])
        top.orientation = .vertical
        top.spacing = 8
        top.translatesAutoresizingMaskIntoConstraints = false
        previewImage.heightAnchor.constraint(lessThanOrEqualToConstant: 340).isActive = true

        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 72, height: 64)
        layout.scrollDirection = .horizontal
        layout.minimumInteritemSpacing = 6
        layout.sectionInset = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        strip = NSCollectionView()
        strip.collectionViewLayout = layout
        strip.register(IconCellView.self, forItemWithIdentifier: IconCellView.id)
        strip.dataSource = self
        strip.delegate = self
        strip.allowsMultipleSelection = true
        strip.isSelectable = true
        let stripScroll = NSScrollView()
        stripScroll.documentView = strip
        stripScroll.translatesAutoresizingMaskIntoConstraints = false
        stripScroll.heightAnchor.constraint(equalToConstant: 96).isActive = true

        let stack = NSStackView(views: [top, stripScroll])
        stack.orientation = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.topAnchor),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    func show(items: [Fileinfo]) {
        self.items = items
        selected = items.isEmpty ? [] : [0]
        strip.reloadData()
        renderPreview()
        onSelectionChange?()
    }

    private func renderPreview() {
        guard let item = selectedItems.first else {
            previewImage.image = nil; previewText.string = ""; previewInfo.stringValue = ""
            previewImage.isHidden = true
            previewText.enclosingScrollView?.isHidden = true
            return
        }
        previewInfo.stringValue = "\(item.name) — \(item.kindLabel)"
        let scroll = previewText.enclosingScrollView
        if item.type != .folder, let img = NSImage(contentsOfFile: item.fullPath) {
            previewImage.image = img
            previewText.string = ""
            previewImage.isHidden = false
            scroll?.isHidden = true
        } else if item.type != .folder,
                  let text = try? String(contentsOfFile: item.fullPath, encoding: .utf8),
                  text.count < 200_000 {
            previewText.string = String(text.prefix(8000))
            previewImage.isHidden = true
            scroll?.isHidden = false
        } else {
            previewImage.image = cellImage(for: item, dark: false)
            previewText.string = ""
            previewImage.isHidden = false
            scroll?.isHidden = true
        }
    }
}

extension GalleryContentView: NSCollectionViewDataSource, NSCollectionViewDelegate {
    func collectionView(_ cv: NSCollectionView, numberOfItemsInSection s: Int) -> Int { items.count }
    func collectionView(_ cv: NSCollectionView, itemForRepresentedObjectAt ip: IndexPath) -> NSCollectionViewItem {
        let cell = cv.makeItem(withIdentifier: IconCellView.id, for: ip) as! IconCellView
        let dark = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        cell.configure(items[ip.item], dark: dark)
        return cell
    }
    func collectionView(_ cv: NSCollectionView, didSelectItemsAt paths: Set<IndexPath>) {
        selected = IndexSet(paths.map { $0.item })
        strip.reloadData()
        renderPreview()
        onSelectionChange?()
    }
}

// MARK: - Preview pane (a real pane slot; closes back to the folder)

final class PreviewPaneController: PaneViewController {
    let item: Fileinfo
    init(item: Fileinfo) {
        self.item = item
        super.init(datasource: LocalDatasource(initialPath: (item.fullPath as NSString).deletingLastPathComponent))
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        view = NSView()
        let title = NSTextField(labelWithString: "Preview — \(item.name)")
        title.font = .boldSystemFont(ofSize: 13)
        title.translatesAutoresizingMaskIntoConstraints = false
        let iv = NSImageView()
        iv.imageScaling = .scaleProportionallyUpOrDown
        iv.translatesAutoresizingMaskIntoConstraints = false
        let info = NSTextField(labelWithString: "\(item.kindLabel)\n\(item.fullPath)")
        info.font = .systemFont(ofSize: 11)
        info.textColor = .secondaryLabelColor
        info.translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView(views: [title, iv, info])
        stack.orientation = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
        ])
        if item.type != .folder, let img = NSImage(contentsOfFile: item.fullPath) {
            iv.image = img
            iv.heightAnchor.constraint(equalToConstant: 300).isActive = true
        } else if item.type != .folder,
                  let text = try? String(contentsOfFile: item.fullPath, encoding: .utf8) {
            let tv = NSTextView()
            tv.string = String(text.prefix(4000))
            tv.isEditable = false
            tv.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            tv.translatesAutoresizingMaskIntoConstraints = false
            tv.heightAnchor.constraint(equalToConstant: 300).isActive = true
            stack.insertArrangedSubview(tv, at: 1)
        } else {
            iv.image = FileIcons.shared.icon(for: item, dark: false)
            iv.heightAnchor.constraint(equalToConstant: 128).isActive = true
        }
    }

    override func viewDidLoad() {
        // No folder listing: this pane shows one item.
    }
}
