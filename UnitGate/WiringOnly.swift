// Wiring-only allowlist: controls that MUST NOT execute headless because
// they present UI, touch the clipboard/Trash, or launch other apps.
// Each entry needs a reason. Entries with live proof reference the proof.
// Printed every build; if this list grows, look at it.
import Foundation

struct WiringOnly {
    struct Entry { let key: String; let reason: String; let liveProof: String }
    static let entries: [Entry] = [
        Entry(key: "menu:trash", reason: "moves files to the user's real Trash",
              liveProof: "none — manual"),
        Entry(key: "menu:copy", reason: "clobbers the user's clipboard", liveProof: "none — manual"),
        Entry(key: "menu:cut", reason: "clobbers the user's clipboard", liveProof: "none — manual"),
        Entry(key: "menu:paste", reason: "reads the user's clipboard, writes files", liveProof: "none — manual"),
        Entry(key: "menu:info", reason: "presents Get Info panel", liveProof: "none — manual"),
        Entry(key: "menu:quicklook", reason: "presents Quick Look panel", liveProof: "none — manual"),
        Entry(key: "menu:palette", reason: "presents command palette window", liveProof: "none — manual"),
        Entry(key: "menu:settings", reason: "presents Settings window", liveProof: "opened live 3x via AX (Add/Save proofs)"),
        Entry(key: "menu:newWindow", reason: "opens a visible window", liveProof: "none — manual"),        Entry(key: "menu:preview", reason: "covered by preview-toggle intent below instead", liveProof: "exercised headless"),
        Entry(key: "menu:open", reason: "launches other apps via NSWorkspace", liveProof: "none — manual"),
        Entry(key: "menu:rename", reason: "presents modal rename alert", liveProof: "none — manual"),
        Entry(key: "menu:copyPath", reason: "writes the user's clipboard", liveProof: "none — manual"),
        Entry(key: "settings:addTheme", reason: "presents theme editor window", liveProof: "Add+Save proven live 3x (editor opened, Custom persisted)"),
        Entry(key: "settings:editTheme", reason: "presents theme editor window", liveProof: "none — manual"),
        Entry(key: "settings:done", reason: "closes window; trivial orderOut", liveProof: "none — manual"),
        Entry(key: "settings:restoreShortcuts", reason: "executed headless (see intent restore-shortcuts)", liveProof: "gate"),
    ]
    static func reason(for key: String) -> String? {
        entries.first(where: { $0.key == key })?.reason
    }
}
