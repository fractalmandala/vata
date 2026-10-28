// Build gate: compiled and run by build.sh before the app itself.
// Fails the build on any assertion. Covers the bug classes we've hit:
// dead control targets, theme persistence, command/menu integrity,
// icon-map coverage.
import AppKit

var failures: [String] = []
func check(_ cond: Bool, _ name: String) {
    if !cond { failures.append(name); print("FAIL: \(name)") }
}

_ = NSApplication.shared

// 1. Inline control targets must survive (BlockTarget self-retention).
do {
    weak var weakRef: NSObject?
    let btn = NSButton(title: "x", target: nil, action: nil)
    autoreleasepool {
        let t = BlockTarget {}
        weakRef = t
        btn.target = t
        btn.action = #selector(BlockTarget.fire)
    }
    check(weakRef != nil, "inline-target-retained")
    check((btn.target as? BlockTarget) != nil, "button-target-live")
}

// 2. ThemeManager round-trip.
do {
    let m = ThemeManager.shared
    let t = VataTheme(name: "GateX", isDark: true, highlight: "#FF0000", base: "#000000",
                      text: "#FFFFFF", label: "#888888", sidebarBackground: "#111111",
                      sidebarItem: "#FF0000", sidebarText: "#FFFFFF", sidebarSelection: "#222222")
    m.saveCustom(t)
    check(m.all.contains(where: { $0.name == "GateX" }), "theme-save")
    m.select(name: "GateX")
    check(m.current.name == "GateX", "theme-select")
    check(NSApp.appearance?.name == .darkAqua, "theme-dark-applied")
    check(t.highlightColor == NSColor(calibratedRed: 1, green: 0, blue: 0, alpha: 1), "theme-hex")
    m.deleteCustom(name: "GateX")
    check(!m.all.contains(where: { $0.name == "GateX" }), "theme-delete")
    check(m.current.name == "System", "theme-fallback")
}

// 3. Every menu-referenced command id must exist exactly once.
do {
    let cmds = CommandRegistry.commands(for: PaneViewController(datasource: LocalDatasource(initialPath: "/tmp")))
    let ids = cmds.map { $0.id }
    check(Set(ids).count == ids.count, "command-ids-unique")
    for want in ["newWindow", "cut", "copy", "paste", "trash", "info", "palette", "settings", "pin", "preview", "selectAll"] {
        check(ids.contains(want), "command-present:\(want)")
    }
}

// 4. Every icon-map stem must resolve to a rasterized PNG.
// (CLI tool has no app bundle; point at the source tree via VATA_ICON_DIR.)
do {
    let dir = ProcessInfo.processInfo.environment["VATA_ICON_DIR"] ?? "Sources/FileIcons"
    let fm = FileManager.default
    var missing: [String] = []
    for (_, stem) in FileIconMap.byExtension {
        if !fm.fileExists(atPath: dir + "/\(stem).png") { missing.append(stem) }
    }
    check(missing.isEmpty, "iconmap-resolves:\(missing.prefix(3).joined(separator: ","))")
    check(FileIconMap.byExtension["py"] != nil, "iconmap-py")
    check(FileIconMap.byExtension["swift"] != nil, "iconmap-swift")
}

// 5. HeaderStore add/remove round-trip.
do {
    HeaderStore.shared.add("/tmp/gate-test-pin")
    check(HeaderStore.shared.paths.contains("/tmp/gate-test-pin"), "pin-add")
    HeaderStore.shared.remove("/tmp/gate-test-pin")
    check(!HeaderStore.shared.paths.contains("/tmp/gate-test-pin"), "pin-remove")
}

// 6. Drop decisions (pure).
do {
    let a = URL(fileURLWithPath: "/a/f.txt")
    let b = URL(fileURLWithPath: "/b")
    check(FileOps.decideDrop(urls: [a], destDir: b, sourceDir: URL(fileURLWithPath: "/a"), optionKey: false, sameVolume: true) == .move([a], b), "drop-move")
    check(FileOps.decideDrop(urls: [a], destDir: b, sourceDir: URL(fileURLWithPath: "/a"), optionKey: true, sameVolume: true) == .copy([a], b), "drop-option-copy")
    check(FileOps.decideDrop(urls: [a], destDir: b, sourceDir: URL(fileURLWithPath: "/a"), optionKey: false, sameVolume: false) == .copy([a], b), "drop-xvol-copy")
    check(FileOps.decideDrop(urls: [URL(fileURLWithPath: "/b/f.txt")], destDir: b, sourceDir: b, optionKey: false, sameVolume: true) == .none, "drop-same-spot")
    check(FileOps.decideDrop(urls: [], destDir: b, sourceDir: nil, optionKey: false, sameVolume: true) == .none, "drop-empty")
}

if failures.isEmpty {
    print("UNIT-GATE-PASS")
} else {
    print("UNIT-GATE-FAIL: \(failures.count)")
    exit(1)
}

// ---- UI audit + command run (headless, no windows shown) ----
do {
    let wc = FileWindowController()
    RunLoop.main.run(until: Date().addingTimeInterval(1.0))
    UIAudit.auditWindow(wc)
    UIAudit.auditHeaderMenus(wc)
    failures += UIAudit.failures
    CommandRun.run(scratch: "/tmp/vata-gate-scratch")
    failures += CommandRun.failures
    ControlAudit.run()
    failures += ControlAudit.failures
    RenderAudit.run()
    failures += RenderAudit.failures
}

if failures.isEmpty {
    print("UNIT-GATE-FULL-PASS")
} else {
    print("UNIT-GATE-FAIL: \(failures.count)")
    exit(1)
}
