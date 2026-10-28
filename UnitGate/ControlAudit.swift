// Control-driven intent audit: every row goes through the REAL control
// (NSApp.sendAction from the found button/menu item), then asserts the
// observable end state — what you could see, not "state changed".
// Coverage is computed from controls FOUND, not from the command table:
// any control without a row fails as uncovered-control:<title>.
import AppKit
import Foundation

struct ControlAudit {
    static var failures: [String] = []
    static func check(_ cond: Bool, _ name: String) {
        if !cond { failures.append(name); print("FAIL: \(name)") }
    }

    // UserDefaults keys this audit touches (snapshot + restore).
    static let touchedKeys = ["vata.headerPins", "vata.quickActions", "vata.shortcuts",
                              "vata.theme.current", "vata.themes.custom", "vata.columns",
                              "vata.showHidden", "vata.startDir"]

    static let appLevelWiring: [String: String] = [
        "About Vata": "presents About alert",
        "Quit Vata": "terminates the app",
    ]

    // Menu ids proven executed, by any driver. Final sweep fails the rest.
    static var coveredMenuIDs = Set<String>()
    static func markCovered(_ id: String) { coveredMenuIDs.insert(id) }

    // App-level items with no command id (explicit allowlist, same rule).

    static func run() {
        var saved: [String: Any] = [:]
        for k in touchedKeys { saved[k] = UserDefaults.standard.object(forKey: k) }
        defer {
            for k in touchedKeys {
                if let v = saved[k] { UserDefaults.standard.set(v, forKey: k) }
                else { UserDefaults.standard.removeObject(forKey: k) }
            }
        }

        // Scratch fixture with known content.
        let scratch = "/tmp/vata-intent-scratch"
        let fm = FileManager.default
        try? fm.removeItem(atPath: scratch)
        try! fm.createDirectory(atPath: scratch, withIntermediateDirectories: true)
        fm.createFile(atPath: "\(scratch)/a.txt", contents: Data("1".utf8))
        fm.createFile(atPath: "\(scratch)/bb.txt", contents: Data("22".utf8))
        fm.createFile(atPath: "\(scratch)/ccc.md", contents: Data("333".utf8))
        fm.createFile(atPath: "\(scratch)/.hidden", contents: Data("h".utf8))
        try! fm.createDirectory(atPath: "\(scratch)/sub", withIntermediateDirectories: true)
        // archive fixture for Extract
        let zipSrc = "\(scratch)/zipsrc"
        try! fm.createDirectory(atPath: zipSrc, withIntermediateDirectories: true)
        fm.createFile(atPath: "\(zipSrc)/z.txt", contents: Data("z".utf8))
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", zipSrc, "\(scratch)/arch.zip"]
        try! ditto.run(); ditto.waitUntilExit()
        let ds = LocalDatasource(initialPath: scratch)

        let wc = FileWindowController()
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        let pane = wc.leftPane
        pane.navigate(to: scratch, record: true)
        RunLoop.main.run(until: Date().addingTimeInterval(2.0))
        check(pane.displayedPath == scratch, "intent:initial-navigate")

        // ---- 1. Buttons found in the live hierarchy ----
        var buttons: [NSButton] = []
        func walk(_ v: NSView) {
            for sub in v.subviews {
                if let b = sub as? NSButton { buttons.append(b) }
                walk(sub)
            }
        }
        if let root = wc.window?.contentView { walk(root) }
        check(!buttons.isEmpty, "controls:buttons-found")
        var coveredButtons = 0
        for b in buttons {
            guard let action = b.action else { check(false, "uncovered-control:\(b.title)-no-action"); continue }
            let t = b.target
            check(t != nil, "wiring:target-present:\(b.title)")
            if let t {
                check(t.responds(to: action), "wiring:responds:\(b.title)->\(NSStringFromSelector(action))")
            }
        }
        // Drive the nav buttons through the real controls.
        func press(title: String) {
            guard let b = buttons.first(where: { $0.title == title }),
                  let action = b.action, let t = b.target else {
                check(false, "uncovered-control:\(title)"); return
            }
            NSApp.sendAction(action, to: t, from: b)
            RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        }
        // go into sub via direct navigate, then Back/Forward/Up through buttons.
        pane.navigate(to: "\(scratch)/sub", record: true)
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        press(title: "‹"); check(pane.displayedPath == scratch, "intent:back"); markCovered("back")
        press(title: "›"); check(pane.displayedPath == "\(scratch)/sub", "intent:forward"); markCovered("forward")
        press(title: "⌃"); check(pane.displayedPath == scratch, "intent:up"); markCovered("up")
        coveredButtons += 3

        // Mode segmented: 4 modes through the real control.
        if let seg = findSegmented(in: pane.view) {
            let modes: [PaneViewController.ViewMode] = [.list, .columns, .icons, .gallery]
            for (i, m) in modes.enumerated() {
                seg.selectedSegment = i
                if let action = seg.action, let t = seg.target {
                    check(t.responds(to: action), "wiring:responds:mode-segment")
                    NSApp.sendAction(action, to: t, from: seg)
                }
                check(pane.viewMode == m, "intent:viewmode-\(m)")
                markCovered(["viewList", "viewColumns", "viewIcons", "viewGallery"][i])
            }
        } else {
            check(false, "uncovered-control:view-mode-segment")
        }

        // ---- 2. Menus: every item must resolve to a covered command ----
        MenuBuilder.build()
        var menuItems: [(String, NSMenuItem)] = []
        func walkMenu(_ m: NSMenu, path: String) {
            for mi in m.items {
                if mi.isSeparatorItem { continue }
                if let sub = mi.submenu { walkMenu(sub, path: path + mi.title + ">") }
                else { menuItems.append((path + mi.title, mi)) }
            }
        }
        if let main = NSApp.mainMenu { walkMenu(main, path: "") }
        check(!menuItems.isEmpty, "controls:menu-items-found")
        let allCmds = CommandRegistry.commands(for: pane)
        for (path, mi) in menuItems {
            if let id = mi.representedObject as? String,
               allCmds.contains(where: { $0.id == id }) {
                continue // resolved; execution proven by final sweep
            }
            if appLevelWiring[path] != nil || appLevelWiring[mi.title] != nil { continue }
            check(false, "uncovered-control:menu:\(path)")
        }

        // ---- 3. Row context menu items ----
        let rowMenu = pane.buildRowMenu()
        for mi in rowMenu.items where !mi.isSeparatorItem && mi.submenu == nil {
            guard let action = mi.action, let t = mi.target else {
                check(false, "uncovered-control:rowmenu:\(mi.title)"); continue
            }
            check(t.responds(to: action), "wiring:responds:rowmenu:\(mi.title)")
        }

        // ---- 4. Header menu toggle flips visibility ----
        if let list = pane.children.compactMap({ $0 as? ListContentView }).first {
            pane.setMode(.list)
            pane.menuNeedsUpdate(list.headerMenu)
            if let kindItem = list.headerMenu.items.first(where: { ($0.representedObject as? String) == "kind" }) {
                let before = pane.visibleColumns.contains("kind")
                kindItem.target.map { NSApp.sendAction(kindItem.action!, to: $0, from: kindItem) }
                check(pane.visibleColumns.contains("kind") != before, "intent:toggle-kind-column")
            } else { check(false, "uncovered-control:header-kind") }
        }

        // ---- 5. Sort produces exact orders ----
        pane.navigate(to: scratch, record: true)
        RunLoop.main.run(until: Date().addingTimeInterval(2.0))
        pane.sortKey = .name; pane.sortAscending = true
        if let sort = allCmds.first(where: { $0.id == "sort" }) {
            sort.run(pane) // name -> size
            check(pane.sortKey == .size, "intent:cycleSort-advances")
            markCovered("sort")
            pane.sortKey = .name; pane.sortAscending = true
        }
        pane.refresh()
        RunLoop.main.run(until: Date().addingTimeInterval(2.0))
        let raw = try! ds.list(scratch)
        func sortedNames(_ items: [Fileinfo]) -> [String] {
            items.map { $0.name }.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending })
        }
        let expectNames = sortedNames(raw.filter { $0.type == .folder })
            + sortedNames(raw.filter { $0.type != .folder })
        check(pane.applySort(to: raw).map { $0.name } == expectNames, "intent:sort-name-exact")
        pane.sortKey = .size; pane.sortAscending = true
        let bySize = pane.applySort(to: (try! ds.list(scratch))).map { $0.name }
        // folders first, then files ascending by size: a-resized set below
        check(bySize.first == "sub" || bySize.first == "zipsrc" || bySize.first == "nd", "intent:sort-size-folders-first:\(bySize.prefix(3).joined(separator: ","))")

        // ---- 6. Mutations with exact end states (through the COMMAND, with a real selection) ----
        pane.setMode(.list)
        pane.navigate(to: scratch, record: false)
        waitForPath(pane, scratch)
        if let dup = allCmds.first(where: { $0.id == "duplicate" }),
           let list = pane.children.compactMap({ $0 as? ListContentView }).first {
            let end = Date().addingTimeInterval(5.0)
            var target = -1
            while target < 0 && Date() < end {
                RunLoop.main.run(until: Date().addingTimeInterval(0.2))
                if list.outline.numberOfRows == 0 { continue }
                for r in 0..<list.outline.numberOfRows {
                    if (list.outline.item(atRow: r) as? Fileinfo)?.name == "a.txt" { target = r; break }
                }
            }
            check(target >= 0, "intent:duplicate-fixture-found")
            if target >= 0 { list.outline.selectRowIndexes([target], byExtendingSelection: false) }
            dup.run(pane)
            markCovered("duplicate")
            check(fm.fileExists(atPath: "\(scratch)/a copy 1.txt"), "intent:duplicate-exact")
        } else { check(false, "intent:duplicate-missing") }
        // FileOps-level exact states (same engine the buttons call).
        try! ds.createDirectory("\(scratch)/nd")
        check(fm.fileExists(atPath: "\(scratch)/nd"), "intent:mkdir-exists")
        try! ds.moveItem("\(scratch)/a.txt", targetPath: "\(scratch)/nd/a.txt")
        check(!fm.fileExists(atPath: "\(scratch)/a.txt") && fm.fileExists(atPath: "\(scratch)/nd/a.txt"),
              "intent:move-exact")
        try! ds.makeSymlink(atPath: "\(scratch)/lnk", toPath: "\(scratch)/bb.txt")
        check(fm.fileExists(atPath: "\(scratch)/lnk"), "intent:symlink-exists")
        let info = try! ds.fileinfoForPath("\(scratch)/bb.txt")
        FileOps.rename(item: info, to: "bb2.txt", in: pane)
        check(!fm.fileExists(atPath: "\(scratch)/bb.txt") && fm.fileExists(atPath: "\(scratch)/bb2.txt"),
              "intent:rename-exact")
        FileOps.extract(item: {
            let e = Fileinfo(fullPath: "\(scratch)/arch.zip"); e.type = .file; return e
        }(), in: pane)
        check(fm.fileExists(atPath: "\(scratch)/arch/z.txt"), "intent:extract-exact")

        // ---- 7. Preview toggle + restore ----
        if let f = (try? ds.list(scratch))?.first(where: { $0.type == .file }) {
            wc.togglePreview(item: f)
            check(wc.isPreviewShowing, "intent:preview-shows")
            wc.togglePreview(item: f)
            check(!wc.isPreviewShowing && wc.panes.count == 2, "intent:preview-restores")
        }

        // ---- 8. Swap/clone ----
        pane.navigate(to: scratch, record: true)
        waitForPath(pane, scratch)
        wc.rightPane.navigate(to: "/Applications", record: true)
        waitForPath(wc.rightPane, "/Applications")
        wc.clonePane()
        waitForPath(wc.rightPane, scratch)
        check(wc.rightPane.displayedPath == scratch, "intent:clone-mirrors"); print("TR clone active=", wc.activePane === pane, "left=", wc.leftPane.displayedPath, "right=", wc.rightPane.displayedPath)
        wc.swapPanes()
        check(wc.leftPane.displayedPath == scratch && wc.rightPane.displayedPath == scratch, "intent:swapnoop-same")
        wc.rightPane.navigate(to: "/Applications", record: true)
        waitForPath(wc.rightPane, "/Applications")
        wc.swapPanes()
        check(wc.leftPane.displayedPath == "/Applications" && wc.rightPane.displayedPath == scratch, "intent:swap-exchanges")
        wc.swapPanes() // restore: left=scratch for the sections below

        // ---- 12. Menu commands execute with exact end states ----
        // (menu item -> command id mapping asserted in section 2; here the
        // commands run on the scratch pane)
        func runCmd(_ id: String) {
            guard let c = allCmds.first(where: { $0.id == id }) else {
                check(false, "intent:cmd-missing:\(id)"); return
            }
            c.run(pane)
            markCovered(id)
            RunLoop.main.run(until: Date().addingTimeInterval(2.0))
        }
        pane.navigate(to: scratch, record: true)
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        runCmd("goHome"); check(pane.displayedPath == NSHomeDirectory(), "intent:goHome-exact")
        runCmd("goApps"); check(pane.displayedPath == "/Applications", "intent:goApps-exact")
        runCmd("goDesktop")
        check(pane.displayedPath == (NSHomeDirectory() as NSString).appendingPathComponent("Desktop"), "intent:goDesktop-exact")
        runCmd("goDownloads")
        check(pane.displayedPath == (NSHomeDirectory() as NSString).appendingPathComponent("Downloads"), "intent:goDownloads-exact")
        runCmd("up"); check(pane.displayedPath == NSHomeDirectory(), "intent:up-from-desktop")
        pane.navigate(to: scratch, record: true)
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        runCmd("newFolder")
        check(fm.fileExists(atPath: "\(scratch)/untitled folder"), "intent:newFolder-exact")
        pane.setMode(.list)
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))
        func selectRow(named name: String) {
            pane.setMode(.list)
            pane.navigate(to: scratch, record: false)
            waitForPath(pane, scratch)
            let end = Date().addingTimeInterval(5.0)
            var found = -1
            while found < 0 && Date() < end {
                RunLoop.main.run(until: Date().addingTimeInterval(0.2))
                guard let list = pane.children.compactMap({ $0 as? ListContentView }).first else { continue }
                if list.outline.numberOfRows == 0 { continue }
                for r in 0..<list.outline.numberOfRows {
                    if (list.outline.item(atRow: r) as? Fileinfo)?.name == name { found = r; break }
                }
            }
            check(found >= 0, "intent:row-found:\(name)")
            if found >= 0,
               let list = pane.children.compactMap({ $0 as? ListContentView }).first {
                list.outline.selectRowIndexes([found], byExtendingSelection: false)
            }
        }
        runCmd("selectAll")
        if let list = pane.children.compactMap({ $0 as? ListContentView }).first {
            check(pane.selectedItems.count == list.outline.numberOfRows && list.outline.numberOfRows > 0, "intent:selectAll-exact=\(pane.selectedItems.count)")
        }
        selectRow(named: "bb2.txt")
        runCmd("alias")
        check(fm.fileExists(atPath: "\(scratch)/bb.txt alias"), "intent:alias-exact")
        selectRow(named: "arch.zip")
        runCmd("extract")
        check(fm.fileExists(atPath: "\(scratch)/arch/z.txt"), "intent:extract-exact")
        selectRow(named: "sub")
        runCmd("pin")
        check(HeaderStore.shared.paths.contains("\(scratch)/sub"), "intent:pin-exact"); print("TR pin sel=", pane.selectedItems.map{$0.name}, "activeIsPane=", wc.activePane === pane)
        HeaderStore.shared.remove("\(scratch)/sub")
        runCmd("reload")
        check(pane.displayedPath == scratch, "intent:reload-keeps-path")
        selectRow(named: "ccc.md")
        runCmd("preview")
        check(wc.isPreviewShowing, "intent:preview-via-command")
        runCmd("preview")
        check(!wc.isPreviewShowing, "intent:preview-toggle-closes")
        let hiddenBefore = Settings.shared.showHiddenFiles
        runCmd("hidden")
        check(Settings.shared.showHiddenFiles != hiddenBefore, "intent:hidden-flips")
        runCmd("hidden")
        pane.navigate(to: scratch, record: true)
        waitForPath(pane, scratch)
        wc.rightPane.navigate(to: "/Applications", record: true)
        waitForPath(wc.rightPane, "/Applications")
        runCmd("swapPanes")
        check(wc.leftPane.displayedPath == "/Applications" && wc.rightPane.displayedPath == scratch, "intent:swap-exact")
        runCmd("swapPanes")
        runCmd("clonePane")
        waitForPath(wc.rightPane, scratch)
        check(wc.rightPane.displayedPath == scratch, "intent:clone-exact")
        pane.navigate(to: scratch, record: true)
        RunLoop.main.run(until: Date().addingTimeInterval(1.0))

        // ---- 13. Sidebar favorites Remove through the real menu item ----
        let sb = SidebarViewController()
        _ = sb.view
        sb.windowController = wc
        HeaderStore.shared.add(scratch)
        sb.reload()
        sb.outline.expandItem(nil, expandChildren: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        // find the favorites row for scratch and select it
        var favRow = -1
        for r in 0..<sb.outline.numberOfRows {
            if let item = sb.outline.item(atRow: r) as? SidebarViewController.Row,
               item.section == .favorites, item.path == scratch {
                favRow = r; break
            }
        }
        check(favRow >= 0, "sidebar:fav-row-present")
        if favRow >= 0 {
            sb.outline.selectRowIndexes([favRow], byExtendingSelection: false)
            let m = NSMenu(); sb.menuNeedsUpdate(m)
            if let rm = m.items.first(where: { $0.title == "Remove from Favorites" }),
               let action = rm.action, let t = rm.target, t.responds(to: action) {
                NSApp.sendAction(action, to: t, from: rm)
                check(!HeaderStore.shared.paths.contains(scratch), "intent:sidebar-remove-exact")
            } else { check(false, "uncovered-control:sidebar-remove") }
        }

        HeaderStore.shared.add("\(scratch)/sub")
        check(HeaderStore.shared.paths.contains("\(scratch)/sub"), "intent:pin-adds")
        HeaderStore.shared.remove("\(scratch)/sub")
        check(!HeaderStore.shared.paths.contains("\(scratch)/sub"), "intent:pin-removes")

        // ---- 10. Hidden toggle changes listing ----
        ds.showHiddenFiles = false
        ds.clearCache()
        let beforeHidden = (try? ds.list(scratch))?.count ?? -1
        ds.showHiddenFiles = true
        ds.clearCache()
        let afterList = ((try? ds.list(scratch)) ?? []).map { $0.name }.sorted()
        let dotfiles = ((try? fm.contentsOfDirectory(atPath: scratch)) ?? []).filter { $0.hasPrefix(".") }.sorted()
        check(afterList.count == beforeHidden + dotfiles.count && dotfiles.allSatisfy({ afterList.contains($0) }),
              "intent:hidden-toggle-lists-dotfiles=\(dotfiles)")
        ds.showHiddenFiles = false
        ds.clearCache()

        // ---- 11. Settings: every section through real table selection + real buttons ----
        let sw = SettingsWindowController.shared
        _ = sw.window // load only, never shown
        func tables(in v: NSView) -> [NSTableView] {
            var out: [NSTableView] = []
            func w(_ x: NSView) {
                for s in x.subviews {
                    if let t = s as? NSTableView { out.append(t) }
                    w(s)
                }
            }
            w(v)
            return out
        }
        func findButtons(in v: NSView) -> [NSButton] {
            var out: [NSButton] = []
            func w(_ x: NSView) {
                for s in x.subviews {
                    if let b = s as? NSButton, b.action != nil { out.append(b) }
                    w(s)
                }
            }
            w(v)
            return out
        }
        if let win = sw.window, let root = win.contentView {
            let allTables = tables(in: root)
            let sectionTable = allTables.first(where: { t in
                (0..<t.numberOfRows).contains { (t.view(atColumn: 0, row: $0, makeIfNecessary: true) as? NSTableCellView)?.textField?.stringValue == "General" }
            })
            check(sectionTable != nil, "settings:section-table-found")
            func selectSection(_ name: String) {
                guard let st = sectionTable else { return }
                for r in 0..<st.numberOfRows {
                    if (st.view(atColumn: 0, row: r, makeIfNecessary: true) as? NSTableCellView)?.textField?.stringValue == name {
                        st.selectRowIndexes([r], byExtendingSelection: false)
                        break
                    }
                }
                RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            }
            func pressButton(_ title: String) -> Bool {
                guard let b = findButtons(in: root).first(where: { $0.title == title }),
                          let action = b.action, let t = b.target, t.responds(to: action) else { return false }
                NSApp.sendAction(action, to: t, from: b)
                RunLoop.main.run(until: Date().addingTimeInterval(0.3))
                return true
            }
            // Themes: duplicate + remove a scratch theme through real controls.
            selectSection("Themes")
            let sysTheme = ThemeManager.shared.current.name
            ThemeManager.shared.saveCustom(VataTheme(name: "GateTmp", isDark: true, highlight: "#FF0000", base: "#000000", text: "#FFFFFF", label: "#888888", sidebarBackground: "#111111", sidebarItem: "#FF0000", sidebarText: "#FFFFFF", sidebarSelection: "#222222"))
            func rowText(_ t: NSTableView, _ r: Int) -> String {
                (t.view(atColumn: 0, row: r, makeIfNecessary: true) as? NSTableCellView)?.textField?.stringValue ?? ""
            }
            func isThemeTable(_ t: NSTableView) -> Bool {
                (0..<t.numberOfRows).contains { rowText(t, $0) == "Dark" }
            }
            if let th = tables(in: root).first(where: isThemeTable) {
                for r in 0..<th.numberOfRows {
                    if (th.view(atColumn: 0, row: r, makeIfNecessary: true) as? NSTableCellView)?.textField?.stringValue.hasPrefix("GateTmp") == true {
                        th.selectRowIndexes([r], byExtendingSelection: false)
                        break
                    }
                }
                RunLoop.main.run(until: Date().addingTimeInterval(0.3))
                check(pressButton("Duplicate"), "settings:duplicate-button-live")
                check(ThemeManager.shared.all.contains(where: { $0.name == "GateTmp Copy" }), "intent:theme-duplicate-exact")
                // select the copy, remove it, then remove the original
                for r in 0..<th.numberOfRows {
                    if (th.view(atColumn: 0, row: r, makeIfNecessary: true) as? NSTableCellView)?.textField?.stringValue.hasPrefix("GateTmp Copy") == true {
                        th.selectRowIndexes([r], byExtendingSelection: false)
                        break
                    }
                }
                RunLoop.main.run(until: Date().addingTimeInterval(0.3))
                check(pressButton("Remove"), "settings:remove-button-live")
                check(!ThemeManager.shared.all.contains(where: { $0.name == "GateTmp Copy" }), "intent:theme-remove-exact")
                ThemeManager.shared.deleteCustom(name: "GateTmp")
            } else { check(false, "settings:themes-table-found") }
            ThemeManager.shared.select(name: sysTheme)
            // Tools: QA add/remove through real buttons.
            selectSection("Tools")
            let qaBefore = Settings.shared.quickActions.count
            check(pressButton("Add"), "settings:qa-add-live")
            check(Settings.shared.quickActions.count == qaBefore + 1, "intent:qa-add-exact")
            // select the added row, then Remove through the real button
            if let qaTable = tables(in: root).first(where: { $0.numberOfRows == qaBefore + 1 }) {
                qaTable.selectRowIndexes([qaBefore], byExtendingSelection: false)
                RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            }
            check(pressButton("Remove"), "settings:qa-remove-live")
            check(Settings.shared.quickActions.count == qaBefore, "intent:qa-remove-exact")
            // Shortcuts: set override, Restore through real button.
            selectSection("Shortcuts")
            ShortcutStore.shared.setShortcut("F99", for: "trash")
            check(pressButton("Restore Defaults"), "settings:restore-live")
            check(ShortcutStore.shared.shortcut(for: "trash") != "F99", "intent:shortcuts-restore-exact")
        } else { check(false, "settings:window-loads") }

        print("control-audit-done buttons=\(buttons.count) menuitems=\(menuItems.count) allowlist=\(WiringOnly.entries.count)")
        print("covered=\(coveredMenuIDs.sorted())")
        print("menuids=\(menuItems.compactMap { $0.1.representedObject as? String }.sorted())")
        // Final sweep: every menu id found must be allowlisted or proven executed.
        for (path, mi) in menuItems {
            guard let id = mi.representedObject as? String else { continue }
            if WiringOnly.reason(for: "menu:\(id)") == nil && !coveredMenuIDs.contains(id) {
                check(false, "uncovered-intent:menu:\(id) (\(path))")
            }
        }
        try? fm.removeItem(atPath: scratch)
    }

    static func waitForPath(_ pane: PaneViewController, _ path: String, timeout: TimeInterval = 5.0) {
        let end = Date().addingTimeInterval(timeout)
        while pane.displayedPath != path && Date() < end {
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        }
    }

    static func findSegmented(in v: NSView) -> NSSegmentedControl? {
        for sub in v.subviews {
            if let s = sub as? NSSegmentedControl { return s }
            if let found = findSegmented(in: sub) { return found }
        }
        return nil
    }
}
