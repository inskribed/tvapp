import Foundation

/// Keeps the parsed channel list on disk so the app opens instantly and only refreshes
/// in the background when the saved copy is old.
public struct LiveCacheStore: Sendable {
    public let directory: URL

    public init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Orka", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.directory = dir
    }

    private func url(_ playlistId: String) -> URL {
        directory.appendingPathComponent("live_\(playlistId).json")
    }

    public func load(playlistId: String) -> (data: LiveData, savedAt: Date)? {
        let u = url(playlistId)
        guard let bytes = try? Data(contentsOf: u),
              let data = try? JSONDecoder().decode(LiveData.self, from: bytes) else { return nil }
        let attrs = try? FileManager.default.attributesOfItem(atPath: u.path)
        let savedAt = attrs?[.modificationDate] as? Date
        return (data, savedAt ?? .distantPast)
    }

    public func save(_ data: LiveData, playlistId: String) {
        guard let bytes = try? JSONEncoder().encode(data) else { return }
        try? bytes.write(to: url(playlistId), options: .atomic)
    }

    public func remove(playlistId: String) {
        try? FileManager.default.removeItem(at: url(playlistId))
    }
}

/// The guide built from XMLTV files for one playlist, saved so it shows instantly next time.
public struct GuideCacheStore: Sendable {
    public let directory: URL

    public init(directory: URL? = nil) {
        self.directory = directory ?? LiveCacheStore().directory
    }

    private struct Saved: Codable {
        var savedAt: Date
        var programs: [String: [Program]]
    }

    private func url(_ playlistId: String) -> URL {
        directory.appendingPathComponent("guide_\(playlistId).json")
    }

    public func load(playlistId: String) -> (programs: [String: [Program]], savedAt: Date)? {
        guard let bytes = try? Data(contentsOf: url(playlistId)),
              let saved = try? JSONDecoder().decode(Saved.self, from: bytes) else { return nil }
        return (saved.programs, saved.savedAt)
    }

    public func save(_ programs: [String: [Program]], playlistId: String, at date: Date = Date()) {
        guard let bytes = try? JSONEncoder().encode(Saved(savedAt: date, programs: programs)) else { return }
        try? bytes.write(to: url(playlistId), options: .atomic)
    }

    public func remove(playlistId: String) {
        try? FileManager.default.removeItem(at: url(playlistId))
    }
}
