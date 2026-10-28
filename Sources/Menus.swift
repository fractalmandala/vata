import AppKit

// One shared command table drives the main menu, the palette, and
// shortcuts — a command exists once, with one title and one shortcut.
struct VataCommand {
    let id: String
    let title: String
    let shortcut: String
    let run: (PaneViewController) -> Void
}

final class CommandRegistry {
    static func commands(for pane: PaneViewController) -> [VataCommand] {
        func sel(_ items: [Fileinfo]) -> [Fileinfo] { items.isEmpty ? [] : items }
        return [
            VataCommand(id: "newWindow", title: "New Vata Window", shortcut: "⌘N") { p in
                (p.view.window?.windowController as? FileWindowController)?.openNewWindow(path: p.displayedPath)
            },
            VataCommand(id: "newFolder", title: "New Folder", shortcut: "⇧⌘N") { FileOps.newFolder(in: $0) },
            VataCommand(id: "duplicate", title: "Duplicate", shortcut: "⌘D") {
                FileOps.duplicate(items: sel($0.selectedItems), in: $0)
            },
            VataCommand(id: "alias", title: "Make Alias", shortcut: "⌃⌘A") {
                FileOps.makeAlias(items: sel($0.selectedItems), in: $0)
            },
            VataCommand(id: "trash", title: "Move to Trash", shortcut: "⌘⌫") {
                FileOps.trash(items: sel($0.selectedItems), in: $0)
            },
            VataCommand(id: "cut", title: "Cut", shortcut: "⌘X") {
                FileOps.copyToPasteboard(items: sel($0.selectedItems), cut: true)
            },
            VataCommand(id: "copy", title: "Copy", shortcut: "⌘C") {
                FileOps.copyToPasteboard(items: sel($0.selectedItems), cut: false)
            },
            VataCommand(id: "paste", title: "Paste Item", shortcut: "⌘V") { FileOps.paste(into: $0) },
            VataCommand(id: "info", title: "Get Info", shortcut: "⌘I") {
                FileOps.showGetInfo(for: sel($0.selectedItems))
            },
            VataCommand(id: "quicklook", title: "Quick Look", shortcut: "Space") { $0.toggleQuickLook() },
            VataCommand(id: "reload", title: "Reload Pane", shortcut: "⌘R") { $0.refresh() },
            VataCommand(id: "swapPanes", title: "Swap Panes", shortcut: "") {
                ($0.view.window?.windowController as? FileWindowController)?.swapPanes()
            },
            VataCommand(id: "clonePane", title: "Clone Pane", shortcut: "") {
                ($0.view.window?.windowController as? FileWindowController)?.clonePane()
            },
            VataCommand(id: "pin", title: "Add to Favorites", shortcut: "⌃⌘H") {
                ($0.view.window?.windowController as? FileWindowController)?.pinSelected()
            },
            VataCommand(id: "selectAll", title: "Select All", shortcut: "⌘A") { $0.selectAllContent() },
            VataCommand(id: "hidden", title: "Show Invisible Files", shortcut: "⇧⌘.") {
                _ in Settings.shared.showHiddenFiles.toggle()
            },
            VataCommand(id: "back", title: "Back", shortcut: "⌘[") { $0.goBackward() },
            VataCommand(id: "forward", title: "Forward", shortcut: "⌘]") { $0.goForward() },
            VataCommand(id: "up", title: "Enclosing Folder", shortcut: "⌘↑") { $0.goUp() },
            VataCommand(id: "goHome", title: "Home", shortcut: "⇧⌘H") { $0.navigate(to: NSHomeDirectory(), record: true) },
            VataCommand(id: "goApps", title: "Applications", shortcut: "⇧⌘A") { $0.navigate(to: "/Applications", record: true) },
            VataCommand(id: "goDesktop", title: "Desktop", shortcut: "⇧⌘D") { $0.navigate(to: (NSHomeDirectory() as NSString).appendingPathComponent("Desktop"), record: true) },
            VataCommand(id: "goDownloads", title: "Downloads", shortcut: "⇧⌘L") { $0.navigate(to: (NSHomeDirectory() as NSString).appendingPathComponent("Downloads"), record: true) },
            VataCommand(id: "sort", title: "Cycle Sort Order", shortcut: "⌃⌘S") { $0.cycleSort() },
            VataCommand(id: "viewList", title: "as List", shortcut: "⌘2") { $0.setMode(.list) },
            VataCommand(id: "viewColumns", title: "as Columns", shortcut: "⌘3") { $0.setMode(.columns) },
            VataCommand(id: "viewIcons", title: "as Icons", shortcut: "⌘1") { $0.setMode(.icons) },
            VataCommand(id: "viewGallery", title: "View as Gallery", shortcut: "") { $0.setMode(.gallery) },
            VataCommand(id: "extract", title: "Extract Here", shortcut: "") {
                for item in $0.selectedItems where FileOps.isArchive(item) {
                    FileOps.extract(item: item, in: $0)
                }
            },
            VataCommand(id: "preview", title: "Preview Pane", shortcut: "⇧⌘Y") {
                guard let wc = $0.view.window?.windowController as? FileWindowController else { return }
                wc.togglePreview(item: $0.selectedItems.first)
            },
            VataCommand(id: "palette", title: "Command Palette…", shortcut: "⇧⌘P") {
                _ in PaletteWindowController.shared.show()
            },
            VataCommand(id: "settings", title: "Settings…", shortcut: "⌘,") {
                _ in SettingsWindowController.shared.show()
            },
        ]
    }
}

// Builds the menu bar once; every item routes through the key window's
// active pane so shortcuts work no matter which pane is focused.
final class MenuBuilder {
    static func build() {
        let bar = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Vata", action: #selector(AppDelegate.showAbout), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(AppDelegate.runCommand(_:)), keyEquivalent: ",")
        appMenu.items.last?.representedObject = "settings"
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Vata", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        bar.addItem(appItem)

        func menu(_ title: String, _ entries: [(String, String, String?)]) -> NSMenuItem {
            let item = NSMenuItem()
            let sub = NSMenu(title: title)
            for (t, key, cmdID) in entries {
                if t == "-" { sub.addItem(.separator()); continue }
                let mi = sub.addItem(withTitle: t, action: #selector(AppDelegate.runCommand(_:)), keyEquivalent: key)
                mi.representedObject = cmdID as NSString?
            }
            item.submenu = sub
            return item
        }

        bar.addItem(menu("File", [
            ("New Window", "n", "newWindow"),
            ("New Folder", "N", "newFolder"),
            ("-", "", nil),
            ("Duplicate", "d", "duplicate"),
            ("Make Alias", "a", "alias"),
            ("-", "", nil),
            ("Move to Trash", "\u{8}", "trash"),
        ]))
        bar.addItem(menu("Edit", [
            ("Cut", "x", "cut"),
            ("Copy", "c", "copy"),
            ("Paste Item", "v", "paste"),
            ("Select All", "a", "selectAll"),
            ("-", "", nil),
            ("Get Info", "i", "info"),
        ]))
        bar.addItem(menu("View", [
            ("Reload Pane", "r", "reload"),
            ("Swap Panes", "", "swapPanes"),
            ("Clone Pane", "", "clonePane"),
            ("Add to Favorites", "h", "pin"),
            ("Toggle Hidden Files", ".", "hidden"),
            ("Cycle Sort Order", "s", "sort"),
            ("as Icons", "1", "viewIcons"),
            ("as List", "2", "viewList"),
            ("as Columns", "3", "viewColumns"),
            ("View as Gallery", "", "viewGallery"),
            ("Preview Pane", "Y", "preview"),
            ("-", "", nil),
            ("Quick Look", "y", "quicklook"),
            ("Command Palette…", "P", "palette"),
        ]))
        bar.addItem(menu("Go", [
            ("Back", "[", "back"),
            ("Forward", "]", "forward"),
            ("Enclosing Folder", "\u{F700}", "up"),
            ("-", "", nil),
            ("Home", "H", "goHome"),
            ("Applications", "A", "goApps"),
            ("Desktop", "D", "goDesktop"),
            ("Downloads", "L", "goDownloads"),
        ]))
        NSApplication.shared.mainMenu = bar
        fixModifiers(bar)
    }

    /// Option-modified shortcuts can't be expressed by keyEquivalent alone.
    static func fixModifiers(_ bar: NSMenu) {
        func find(_ id: String, _ modifiers: NSEvent.ModifierFlags) {
            for item in bar.items {
                for mi in item.submenu?.items ?? [] {
                    if (mi.representedObject as? String) == id {
                        mi.keyEquivalentModifierMask = modifiers
                    }
                }
            }
        }
        find("pin", [.control, .command])
        find("hidden", [.shift, .command])
        find("goHome", [.shift, .command])
        find("goApps", [.shift, .command])
        find("goDesktop", [.shift, .command])
        find("goDownloads", [.shift, .command])
        find("sort", [.control, .command])
        find("palette", [.shift, .command])
        find("preview", [.shift, .command])
        find("newFolder", [.shift, .command])
        find("alias", [.control, .command])
    }
}
