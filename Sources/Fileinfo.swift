import Foundation

// Mirrors ForkLift.Fileinfo (observed: init(fullPath:), type, local fields).
public enum FileType: Int {
    case unknown = 0
    case folder = 1
    case file = 2
    case symlink = 3
    case archive = 4
}

public final class Fileinfo: NSObject {
    public let fullPath: String
    public var type: FileType
    public var local: Bool
    public var size: Int64
    public var modificationDate: Date?
    public var createdDate: Date?
    public var lastOpenedDate: Date?
    public var addedDate: Date?
    public var kindLabel: String
    public var posixPermissions: Int?
    public var childCount: Int?

    public init(fullPath: String) {
        self.fullPath = fullPath
        self.type = .unknown
        self.local = false
        self.size = -1
        self.kindLabel = "Document"
    }

    public var name: String { URL(fileURLWithPath: fullPath).lastPathComponent }
    public var displayName: String { name.isEmpty ? fullPath : name }
}
