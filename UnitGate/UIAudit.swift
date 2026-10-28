// In-process UI audit, compiled into the unit gate (never shipped).
// Instantiates real controllers WITHOUT showing windows: no screen,
// no prompts, no focus. Fails the build on dead controls.
import AppKit
import Foundation

struct UIAudit {
    static var failures: [String] = []
    static func check(_ cond: Bool, _ name: String) {
        if !cond { failures.append(name); print("FAIL: \(name)") }
    }

    // Walk a live window controller's hierarchy (views load, nothing shows).
    static func auditWindow(_ wc: FileWindowController) {
        var buttons = 0
        func walk(_ v: NSView) {
            for sub in v.subviews {
                if let b = sub as? NSButton {
                    buttons += 1
                    check(b.target != nil && b.action != nil, "button-live:\(b.title)")
                }
                walk(sub)
            }
        }
        if let root = wc.window?.contentView { walk(root) }
        check(buttons > 0, "buttons-exist")
        print("audited-buttons=\(buttons)")
    }

    // Header (column) menus build with live targets.
    static func auditHeaderMenus(_ wc: FileWindowController) {
        for pane in wc.panes {
            guard let list = pane.children.compactMap({ $0 as? ListContentView }).first else {
                check(false, "pane-has-list-content"); continue
            }
            pane.menuNeedsUpdate(list.headerMenu)
            check(!list.headerMenu.items.isEmpty, "header-menu-built")
            for mi in list.headerMenu.items where !mi.isSeparatorItem {
                check(mi.target != nil && mi.action != nil, "header-item-live:\(mi.title)")
            }
        }
    }
}
