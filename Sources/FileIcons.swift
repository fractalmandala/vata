import AppKit

// File-type icons rasterized at build time from assets/fileicons (see
// gen-icons.py). Memory-cached; dark mode prefers file-type-light variants.
final class FileIcons {
    static let shared = FileIcons()
    private let cache = NSCache<NSString, NSImage>()
    private let folderImage: NSImage?
    private let fileImage: NSImage?

    private init() {
        folderImage = FileIcons.loadIcon(named: "default-folder")
        fileImage = FileIcons.loadIcon(named: "default-file")
    }

    private static func loadIcon(named: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: named, withExtension: "png", subdirectory: "FileIcons") else { return nil }
        return NSImage(contentsOf: url)
    }

    func icon(for item: Fileinfo, dark: Bool) -> NSImage? {
        if item.type == .folder {
            let lower = item.name.lowercased()
            if let stem = FileIconMap.byFolder[lower], let img = cached(stem, dark: dark) { return img }
            return folderImage
        }
        let ext = (item.name as NSString).pathExtension.lowercased()
        if !ext.isEmpty, let stem = FileIconMap.byExtension[ext], let img = cached(stem, dark: dark) {
            return img
        }
        // Compound extensions: archive.tar.gz -> try "tar.gz", then "gz".
        let parts = item.name.lowercased().split(separator: ".")
        if parts.count > 2 {
            let compound = parts.suffix(2).joined(separator: ".")
            if let stem = FileIconMap.byExtension[compound] { return cached(stem, dark: dark) }
        }
        return fileImage
    }

    private func cached(_ stem: String, dark: Bool) -> NSImage? {
        // Prefer light variant in dark mode (vscode-icons convention).
        let names = dark
            ? [stem.replacingOccurrences(of: "file-type-", with: "file-type-light-"), stem]
            : [stem]
        for name in names {
            if let hit = cache.object(forKey: name as NSString) { return hit }
            if let img = bundledIcon(named: name) {
                cache.setObject(img, forKey: name as NSString)
                return img
            }
        }
        return nil
    }

    private func bundledIcon(named: String) -> NSImage? {
        Self.loadIcon(named: named)
    }
}

