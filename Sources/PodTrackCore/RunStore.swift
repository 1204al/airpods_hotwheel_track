import Foundation

public struct RunStore: Sendable {
    public let directory: URL
    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
            .appendingPathComponent("PodTrack/Runs",isDirectory:true)
    }
    public func save(_ session: RunSession) throws {
        try session.metadata.validate()
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(session)
        try data.write(to:directory.appendingPathComponent(session.id.uuidString).appendingPathExtension("json"),options:.atomic)
    }
    public func load() throws -> (runs: [RunSession], warnings: [String]) {
        try load(from:directory)
    }
    public var recentlyDeletedDirectory: URL { directory.appendingPathComponent("RecentlyDeleted",isDirectory:true) }

    /// Recoverable removal. Save the current in-memory revision before moving it, including
    /// any edits that previously failed to persist. A failed write/move leaves the run active.
    public func moveToRecentlyDeleted(_ session: RunSession) throws {
        let target = recentlyDeletedDirectory.appendingPathComponent(session.id.uuidString).appendingPathExtension("json")
        guard !FileManager.default.fileExists(atPath:target.path) else {
            throw PodTrackError.invalid("A deleted recording with this ID already exists. Restore it before removing this recording again.")
        }
        try FileManager.default.createDirectory(at:recentlyDeletedDirectory,withIntermediateDirectories:true)
        try save(session)
        try FileManager.default.moveItem(at:directory.appendingPathComponent(session.id.uuidString).appendingPathExtension("json"),to:target)
    }

    public func loadRecentlyDeleted() throws -> (runs: [RunSession], warnings: [String]) {
        try load(from:recentlyDeletedDirectory)
    }

    public func restore(_ id: UUID) throws {
        let source = recentlyDeletedDirectory.appendingPathComponent(id.uuidString).appendingPathExtension("json")
        let target = directory.appendingPathComponent(id.uuidString).appendingPathExtension("json")
        guard !FileManager.default.fileExists(atPath:target.path) else {
            throw PodTrackError.invalid("This recording already exists in the library. Restoring will not overwrite it.")
        }
        try FileManager.default.moveItem(at:source,to:target)
    }

    private func load(from location: URL) throws -> (runs: [RunSession], warnings: [String]) {
        guard FileManager.default.fileExists(atPath:location.path) else { return ([],[]) }
        let urls = try FileManager.default.contentsOfDirectory(at:location,includingPropertiesForKeys:nil).filter { $0.pathExtension == "json" }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        var runs: [RunSession] = [], warnings: [String] = []
        for url in urls {
            do {
                let run = try decoder.decode(RunSession.self,from:Data(contentsOf:url))
                guard run.schemaVersion == 1 else { throw PodTrackError.invalid("Unsupported schema \(run.schemaVersion)") }
                try run.metadata.validate()
                guard run.samples.allSatisfy(\.isValid) else { throw PodTrackError.invalid("Invalid motion samples") }
                runs.append(run)
            } catch { warnings.append("Could not load \(url.lastPathComponent): \(error.localizedDescription)") }
        }
        return (runs.sorted { $0.createdAt > $1.createdAt },warnings)
    }
}
