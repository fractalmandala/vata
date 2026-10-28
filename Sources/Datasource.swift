import Foundation

// Mirrors the observed ForkLift.Datasource base class.
// Template methods (list/useCache/fileinfoForPath) serialize on accessQueue
// and validate the UUID; backend primitives (doList + mutators) trap with
// "<name> not implemented" so subclasses must override — exactly the
// contract observed in the shipped binary (ev_28aba29f…, strings @0x10070bd20+).
open class Datasource: NSObject {

    public let accessQueue: DispatchQueue
    public private(set) var uuid: UUID
    public var initialPath: String
    public var lastVisitedPath: String?
    public var recentPaths: [String] = []
    /// Set by the UI layer (Settings). Engine stays AppKit-free and testable.
    public var showHiddenFiles = false
    open var createsURL: Bool { false }

    public init(initialPath: String) {
        self.accessQueue = DispatchQueue(label: "com.guppylift.datasource.access")
        self.uuid = UUID()
        self.initialPath = initialPath
    }

    // MARK: - Template methods (final in behavior; serialized + validated)

    public func list(_ path: String) throws -> [Fileinfo] {
        try accessQueue.sync {
            try validateUUID()
            return try doList(path)
        }
    }

    public func list(_ path: String, useCache: Bool) throws -> [Fileinfo] {
        if !useCache { clearCache() }
        return try list(path)
    }

    public func fileinfoForPath(_ path: String) throws -> Fileinfo {
        // Observed fast path (ev_7ef74418…): "/" synthesizes a local folder.
        if path == "/" {
            let info = Fileinfo(fullPath: path)
            info.type = .folder
            info.local = true
            return info
        }
        return try accessQueue.sync {
            try validateUUID()
            return try resolveFileinfo(path)
        }
    }

    // MARK: - Backend primitives (override; base traps)

    open func doList(_ path: String) throws -> [Fileinfo] {
        throw backendError("doList(_:)")
    }

    open func resolveFileinfo(_ path: String) throws -> Fileinfo {
        let items = try doList((path as NSString).deletingLastPathComponent)
        let name = (path as NSString).lastPathComponent
        if let hit = items.first(where: { $0.name == name }) { return hit }
        throw NSError(domain: "GuppyLift", code: 404,
                      userInfo: [NSLocalizedDescriptionKey: "The item \"\(name)\" can't be resolved"])
    }

    open func createDirectory(_ path: String) throws { throw backendError("createDirectory(_:)") }
    open func deleteFile(_ path: String) throws { throw backendError("deleteFile(_:)") }
    open func deleteDirectory(_ path: String) throws { throw backendError("deleteDirectory(_:)") }
    open func moveItem(_ path: String, targetPath: String) throws { throw backendError("moveItem(_:targetPath:)") }
    open func makeSymlink(atPath path: String, toPath: String) throws { throw backendError("makeSymlinkAtPath(_:toPath:)") }

    open func clearCache() {}
    open func disconnect() {}

    private func validateUUID() throws {
        // Observed: every serialized entry re-checks the connection UUID.
        guard uuid.uuidString.count == 36 else {
            throw NSError(domain: "GuppyLift", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Stale datasource connection"])
        }
    }

    private func backendError(_ name: String) -> NSError {
        NSError(domain: "GuppyLift", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "\(name) not implemented"])
    }
}
