import AppKit

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    static var openWindows: [FileWindowController] = []

    private var mainWindow: FileWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        ThemeManager.shared.apply()
        MenuBuilder.build()
        if !UserDefaults.standard.bool(forKey: "setupDone") {
            UserDefaults.standard.set(true, forKey: "setupDone")
        }
        mainWindow = FileWindowController()
        Self.openWindows.append(mainWindow!)
        mainWindow?.showWindow(self)
        NSApp.activate(ignoringOtherApps: true)
    }

    // Unit-gate seam: the gate never shows windows, so it points menu
    // routing at its headless window here. Always nil in the app.
    static var headlessKeyWindow: FileWindowController?

    static func keyPane() -> PaneViewController? {
        if let wc = headlessKeyWindow { return wc.activePane ?? wc.leftPane }
        guard let win = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }),
              let wc = win.windowController as? FileWindowController else { return nil }
        return wc.activePane ?? wc.leftPane
    }

    @objc func runCommand(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let pane = Self.keyPane(),
              let cmd = CommandRegistry.commands(for: pane).first(where: { $0.id == id }) else { return }
        cmd.run(pane)
    }

    @objc func showAbout() {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let a = NSAlert()
        a.messageText = "Vātā \(v)"
        a.informativeText = "Dual-pane file manager.\nSlice 2: menus, palette, icons, settings."
        a.addButton(withTitle: "OK")
        a.runModal()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

