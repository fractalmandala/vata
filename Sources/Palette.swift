import AppKit

// Fuzzy command palette (⇧⌘P): every registry command, filter-as-you-type.
final class PaletteWindowController: NSWindowController {

    static let shared = PaletteWindowController()

    private let search = NSSearchField()
    private let table = NSTableView()
    private var all: [VataCommand] = []
    private var shown: [VataCommand] = []
    private weak var pane: PaneViewController?

    private init() {
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 320),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Vata Commands"
        super.init(window: window)
        search.frame = NSRect(x: 12, y: 278, width: 496, height: 30)
        search.target = self
        search.action = #selector(filterChanged)
        window.contentView?.addSubview(search)
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("cmd"))
        col.width = 480
        table.addTableColumn(col)
        table.delegate = self
        table.dataSource = self
        table.doubleAction = #selector(runSelected)
        table.target = self
        let scroll = NSScrollView(frame: NSRect(x: 12, y: 12, width: 496, height: 258))
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        window.contentView?.addSubview(scroll)
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        guard let pane = AppDelegate.keyPane() else { return }
        self.pane = pane
        all = CommandRegistry.commands(for: pane)
        shown = all
        search.stringValue = ""
        table.reloadData()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(search)
    }

    @objc private func filterChanged() {
        let q = search.stringValue.lowercased()
        shown = q.isEmpty ? all : all.filter { $0.title.lowercased().contains(q) || $0.id.contains(q) }
        table.reloadData()
        if !shown.isEmpty { table.selectRowIndexes([0], byExtendingSelection: false) }
    }

    @objc private func runSelected() {
        let row = table.selectedRow
        guard row >= 0, row < shown.count, let pane else { return }
        window?.orderOut(nil)
        shown[row].run(pane)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 { runSelected() }
        else if event.keyCode == 53 { window?.orderOut(nil) }
        else { super.keyDown(with: event) }
    }
}

extension PaletteWindowController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { shown.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cmd")
        let cell = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView ?? NSTableCellView()
        cell.identifier = id
        if cell.textField == nil {
            let tf = NSTextField(labelWithString: "")
            tf.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(tf)
            cell.textField = tf
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                tf.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }
        let c = shown[row]
        cell.textField?.stringValue = "\(c.title)   —   \(c.shortcut)"
        return cell
    }
}
