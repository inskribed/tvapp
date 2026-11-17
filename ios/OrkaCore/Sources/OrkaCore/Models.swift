import Foundation

/// The kinds of content a provider offers. Only `live` is synced at launch.
/// Movies and Series are synced on demand, each on its own (see SyncState in the app).
public enum ContentKind: String, Codable, CaseIterable, Sendable {
    case live, movies, series

    public var label: String {
        switch self {
        case .live: return "Live TV"
        case .movies: return "Movies"
        case .series: return "Series"
        }
    }
}

public struct Playlist: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var server: String
    public var username: String
    public var password: String

    public init(id: String, name: String, server: String, username: String, password: String) {
        self.id = id
        self.name = name
        self.server = server
        self.username = username
        self.password = password
    }
}

public struct Category: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct Channel: Codable, Hashable, Identifiable, Sendable {
    public var playlistId: String
    public var streamId: String
    public var num: Int
    public var name: String
    public var logo: String?
    public var categoryId: String
    public var epgId: String?

    /// Unique across all playlists.
    public var id: String { "\(playlistId):\(streamId)" }

    public init(playlistId: String, streamId: String, num: Int, name: String, logo: String?, categoryId: String, epgId: String?) {
        self.playlistId = playlistId
        self.streamId = streamId
        self.num = num
        self.name = name
        self.logo = logo
        self.categoryId = categoryId
        self.epgId = epgId
    }
}

public struct LiveData: Codable, Sendable {
    public var categories: [Category]
    public var channels: [Channel]

    public init(categories: [Category], channels: [Channel]) {
        self.categories = categories
        self.channels = channels
    }
}

/// One TV guide entry.
public struct Program: Codable, Hashable, Sendable {
    public var title: String
    public var summary: String?
    public var start: Date
    public var end: Date

    public init(title: String, summary: String?, start: Date, end: Date) {
        self.title = title
        self.summary = summary
        self.start = start
        self.end = end
    }

    public func isOn(at date: Date) -> Bool { date >= start && date < end }

    /// 0...1 of how far into the program `date` is.
    public func progress(at date: Date) -> Double {
        let total = end.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        return min(1, max(0, date.timeIntervalSince(start) / total))
    }
}

public struct AccountInfo: Sendable {
    public var ok: Bool
    public var status: String?
    public var expiresAt: Date?
    public var maxConnections: Int?
    public var activeConnections: Int?
    public var message: String?

    public init(ok: Bool, status: String?, expiresAt: Date?, maxConnections: Int?, activeConnections: Int?, message: String?) {
        self.ok = ok
        self.status = status
        self.expiresAt = expiresAt
        self.maxConnections = maxConnections
        self.activeConnections = activeConnections
        self.message = message
    }
}

public enum OrkaError: LocalizedError {
    case http(Int)
    case badAddress
    case notXtream
    case emptyResponse

    public var errorDescription: String? {
        switch self {
        case .http(let code): return "The server returned HTTP \(code)."
        case .badAddress: return "The server address doesn't look right."
        case .notXtream: return "That address didn't respond like an Xtream server."
        case .emptyResponse: return "The server sent an empty response."
        }
    }
}
