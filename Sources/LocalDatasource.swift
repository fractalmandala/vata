import Foundation

// FileManager-backed Datasource: the Local backend. Overrides every
// primitive the base traps on, so no "not implemented" error can surface.
public final class LocalDatasource: Datasource {

    private let fm = FileManager.default
    private var cache: [String: [Fileinfo]] = [:]

    public override func doList(_ path: String) throws -> [Fileinfo] {
        if let hit = cache[path] { return hit }
        var options: FileManager.DirectoryEnumerationOptions = []
        if !showHiddenFiles { options.insert(.skipsHiddenFiles) }
        let urls = try fm.contentsOfDirectory(at: URL(fileURLWithPath: path),
                                              includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey,
                                                                          .contentModificationDateKey],
                                              options: options)
        let items = urls.map { makeFileinfo(url: $0) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        cache[path] = items
        return items
    }

    public override func clearCache() { cache.removeAll() }

    public override func createDirectory(_ path: String) throws {
        try fm.createDirectory(atPath: path, withIntermediateDirectories: true)
        clearCache()
    }

    public override func deleteFile(_ path: String) throws {
        try fm.removeItem(atPath: path)
        clearCache()
    }

    public override func deleteDirectory(_ path: String) throws {
        try fm.removeItem(atPath: path)
        clearCache()
    }

    public override func moveItem(_ path: String, targetPath: String) throws {
        try fm.moveItem(atPath: path, toPath: targetPath)
        clearCache()
    }

    public override func makeSymlink(atPath path: String, toPath: String) throws {
        try fm.createSymbolicLink(atPath: path, withDestinationPath: toPath)
        clearCache()
    }

    private func makeFileinfo(url: URL) -> Fileinfo {
        let info = Fileinfo(fullPath: url.path)
        info.local = true
        let vals = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey,
                                                     .contentModificationDateKey, .creationDateKey,
                                                     .contentAccessDateKey, .addedToDirectoryDateKey])
        if let attrs = try? fm.attributesOfItem(atPath: url.path),
           let mode = attrs[.posixPermissions] as? Int {
            info.posixPermissions = mode
        }
        if vals?.isSymbolicLink == true { info.type = .symlink }
        else if vals?.isDirectory == true { info.type = .folder }
        else { info.type = .file }
        if let size = vals?.fileSize { info.size = Int64(size) }
        info.modificationDate = vals?.contentModificationDate
        info.createdDate = vals?.creationDate
        info.lastOpenedDate = vals?.contentAccessDate
        info.addedDate = vals?.addedToDirectoryDate
        info.kindLabel = kindLabel(for: url, isDir: info.type == .folder, isLink: info.type == .symlink)
        return info
    }

    private func kindLabel(for url: URL, isDir: Bool, isLink: Bool) -> String {
        if isLink { return "Alias" }
        if isDir { return url.pathExtension.lowercased() == "app" ? "Application" : "Folder" }
        switch url.pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "webp", "avif", "bmp", "tiff", "tif", "heic", "svg", "ico":
            return "Image"
        case "mp3", "wav", "flac", "ogg", "m4a", "aac": return "Music"
        case "mp4", "mov", "mkv", "avi", "webm": return "Movie"
        case "zip", "tar", "gz", "bz2", "xz", "7z", "rar", "dmg": return "Archive"
        case "pdf": return "PDF"
        case "txt", "md", "markdown", "log", "csv": return "Text"
        default: return "Document"
        }
    }
}
