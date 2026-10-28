import AppKit

// ForkLift-parity theme model: a theme carries its own dark style plus
// content and sidebar colors. Built-ins ship; customs persist.
struct VataTheme: Codable, Equatable {
    var name: String
    var isDark: Bool
    var highlight: String
    var base: String
    var text: String
    var label: String
    var sidebarBackground: String
    var sidebarItem: String
    var sidebarText: String
    var sidebarSelection: String

    static let builtin: [VataTheme] = [
        VataTheme(name: "System", isDark: false, highlight: "#0A84FF", base: "#FFFFFF",
                  text: "#000000", label: "#6E6E6E", sidebarBackground: "#F5F5F5",
                  sidebarItem: "#0A84FF", sidebarText: "#000000", sidebarSelection: "#0A84FF"),
        VataTheme(name: "Light", isDark: false, highlight: "#0A84FF", base: "#FFFFFF",
                  text: "#1a1a1a", label: "#6E6E6E", sidebarBackground: "#EDEDED",
                  sidebarItem: "#0A84FF", sidebarText: "#1a1a1a", sidebarSelection: "#D8D8D8"),
        VataTheme(name: "Dark", isDark: true, highlight: "#0A84FF", base: "#1E1E1E",
                  text: "#FFFFFF", label: "#AAAAAA", sidebarBackground: "#262626",
                  sidebarItem: "#0A84FF", sidebarText: "#FFFFFF", sidebarSelection: "#3A3A3A"),
        VataTheme(name: "Vata", isDark: true, highlight: "#E8890C", base: "#232228",
                  text: "#FFFFFF", label: "#AAAAAA", sidebarBackground: "#2B2A30",
                  sidebarItem: "#E8890C", sidebarText: "#FFFFFF", sidebarSelection: "#3A3940"),
    ]
}

extension VataTheme {
    func color(_ hex: String) -> NSColor {
        var h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return .labelColor }
        return NSColor(calibratedRed: CGFloat((v >> 16) & 0xFF) / 255,
                       green: CGFloat((v >> 8) & 0xFF) / 255,
                       blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
    var highlightColor: NSColor { color(highlight) }
    var baseColor: NSColor { color(base) }
    var textColor: NSColor { color(text) }
    var sidebarBG: NSColor { color(sidebarBackground) }
    var sidebarSelectionColor: NSColor { color(sidebarSelection) }
}

final class ThemeManager {
    static let shared = ThemeManager()
    private let key = "vata.themes.custom"
    private let currentKey = "vata.theme.current"

    var custom: [VataTheme] {
        get {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let arr = try? JSONDecoder().decode([VataTheme].self, from: data) else { return [] }
            return arr
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: key)
        }
    }

    var all: [VataTheme] { VataTheme.builtin + custom }

    var current: VataTheme {
        let name = UserDefaults.standard.string(forKey: currentKey) ?? "System"
        return all.first(where: { $0.name == name }) ?? VataTheme.builtin[0]
    }

    func select(name: String) {
        UserDefaults.standard.set(name, forKey: currentKey)
        apply()
    }

    func apply() {
        let t = current
        if t.name == "System" {
            NSApp.appearance = nil
        } else {
            NSApp.appearance = NSAppearance(named: t.isDark ? .darkAqua : .aqua)
        }
        NotificationCenter.default.post(name: .vataThemeChanged, object: nil)
    }

    func saveCustom(_ theme: VataTheme) {
        var c = custom.filter { $0.name != theme.name }
        c.append(theme)
        custom = c
    }

    func deleteCustom(name: String) {
        custom = custom.filter { $0.name != name }
        if current.name == name { select(name: "System") }
    }

    func isCustom(name: String) -> Bool { custom.contains(where: { $0.name == name }) }
}

extension Notification.Name {
    static let vataThemeChanged = Notification.Name("VataThemeChanged")
}

// Table/outline row drawing the theme highlight instead of system selection.
final class VataRowView: NSTableRowView {
    var color: NSColor?
    override func drawSelection(in dirtyRect: NSRect) {
        if selectionHighlightStyle != .none {
            (color ?? ThemeManager.shared.current.highlightColor).setFill()
            bounds.fill()
        }
    }
}
