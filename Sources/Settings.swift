import AppKit

// User-visible settings, persisted in UserDefaults. Applied live.
final class Settings {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    enum Theme: String, CaseIterable {
        case system, light, dark
        var title: String { rawValue.capitalized }
    }

    /// Legacy simple theme; forwards to the full ThemeManager.
    var theme: Theme {
        get {
            let cur = ThemeManager.shared.current.name
            if cur == "Light" { return .light }
            if cur == "Dark" { return .dark }
            return .system
        }
        set {
            ThemeManager.shared.select(name: newValue == .light ? "Light" : newValue == .dark ? "Dark" : "System")
        }
    }

    var showHiddenFiles: Bool {
        get { defaults.bool(forKey: "vata.showHidden") }
        set { defaults.set(newValue, forKey: "vata.showHidden"); notifyChange() }
    }

    var quickActions: [QuickAction] {
        get {
            guard let arr = defaults.array(forKey: "vata.quickActions") as? [[String: String]] else {
                return QuickAction.defaults
            }
            return arr.compactMap(QuickAction.init(dict:))
        }
        set {
            defaults.set(newValue.map { $0.dict }, forKey: "vata.quickActions")
            notifyChange()
        }
    }

    func applyTheme() {
        // Migrated to ThemeManager; kept for old call sites.
        ThemeManager.shared.apply()
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: .vataSettingsChanged, object: nil)
    }
}

extension Notification.Name {
    static let vataSettingsChanged = Notification.Name("VataSettingsChanged")
}

// A user-configurable quick action: runs a shell command with the
// selected file path appended as the last argument.
struct QuickAction: Identifiable {
    var id: String
    var title: String
    var command: String

    static var defaults: [QuickAction] {
        [QuickAction(id: "terminal", title: "Open in Terminal", command: "open -a Terminal"),
         QuickAction(id: "reveal", title: "Reveal in Finder", command: "open -R")]
    }

    init(id: String = UUID().uuidString, title: String, command: String) {
        self.id = id; self.title = title; self.command = command
    }

    init?(dict: [String: String]) {
        guard let title = dict["title"], let command = dict["command"] else { return nil }
        self.id = dict["id"] ?? UUID().uuidString
        self.title = title; self.command = command
    }

    var dict: [String: String] { ["id": id, "title": title, "command": command] }

    func run(on path: String) {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/sh")
        proc.arguments = ["-c", "\(command) \(shEscape(path))"]
        try? proc.run()
    }
}

private func shEscape(_ s: String) -> String {
    "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}
