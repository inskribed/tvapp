import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum StreamFormat: String, Codable, Sendable {
    /// iPhones play HLS natively. (Raw .ts streams are not supported by AVPlayer.)
    case hls = "m3u8"
    case ts = "ts"
}

/// Talks to an Xtream Codes compatible server (player_api.php).
///
/// Live TV only: this is the part that runs at launch. Movies and Series get their own
/// calls later and are never part of the launch sync.
public struct XtreamClient: Sendable {
    public static let userAgent = "Orka-iOS/0.1"

    public let session: URLSession

    public init(session: URLSession = XtreamClient.makeSession()) {
        self.session = session
    }

    public static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 180
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }

    // MARK: Addresses

    public static func normalizeServer(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = s.lowercased()
        if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") { s = "http://" + s }
        if let r = s.range(of: "/player_api.php") { s = String(s[..<r.lowerBound]) }
        if let r = s.range(of: "/get.php") { s = String(s[..<r.lowerBound]) }
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    func apiURL(_ p: Playlist, action: String?, extra: [URLQueryItem] = []) throws -> URL {
        guard var comps = URLComponents(string: p.server + "/player_api.php") else { throw OrkaError.badAddress }
        var items = [
            URLQueryItem(name: "username", value: p.username),
            URLQueryItem(name: "password", value: p.password),
        ]
        if let action { items.append(URLQueryItem(name: "action", value: action)) }
        items.append(contentsOf: extra)
        comps.queryItems = items
        guard let url = comps.url else { throw OrkaError.badAddress }
        return url
    }

    /// `/live/{user}/{pass}/{id}.m3u8`
    public static func streamURL(_ p: Playlist, _ ch: Channel, format: StreamFormat = .hls) -> URL? {
        var segment = CharacterSet.urlPathAllowed
        segment.remove("/")
        func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: segment) ?? s }
        return URL(string: "\(p.server)/live/\(enc(p.username))/\(enc(p.password))/\(enc(ch.streamId)).\(format.rawValue)")
    }

    // MARK: Requests

    func get(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url)
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw OrkaError.http(http.statusCode)
        }
        return data
    }

    public func authenticate(_ p: Playlist) async throws -> AccountInfo {
        let data = try await get(try apiURL(p, action: nil))
        return try Self.parseAccount(data)
    }

    /// Channels and categories only. This is everything the app needs to start.
    public func fetchLive(_ p: Playlist) async throws -> LiveData {
        let catsURL = try apiURL(p, action: "get_live_categories")
        let streamsURL = try apiURL(p, action: "get_live_streams")
        async let cats = get(catsURL)
        async let streams = get(streamsURL)
        let (c, s) = try await (cats, streams)
        return LiveData(
            categories: try Self.parseCategories(c),
            channels: try Self.parseStreams(s, playlistId: p.id)
        )
    }

    /// Guide entries for one channel, from now on.
    public func shortEpg(_ p: Playlist, streamId: String, limit: Int = 24) async throws -> [Program] {
        let url = try apiURL(p, action: "get_short_epg", extra: [
            URLQueryItem(name: "stream_id", value: streamId),
            URLQueryItem(name: "limit", value: String(limit)),
        ])
        return Self.parseEpg(try await get(url))
    }

    // MARK: Parsing

    struct RawUser: Decodable {
        let auth: FlexString?
        let status: FlexString?
        let exp_date: FlexString?
        let max_connections: FlexString?
        let active_cons: FlexString?
        let message: FlexString?
    }

    struct RawAuthResponse: Decodable {
        let user_info: RawUser?
    }

    public static func parseAccount(_ data: Data) throws -> AccountInfo {
        guard let root = try? JSONDecoder().decode(RawAuthResponse.self, from: data) else {
            throw OrkaError.notXtream
        }
        guard let user = root.user_info else {
            return AccountInfo(ok: false, status: nil, expiresAt: nil, maxConnections: nil, activeConnections: nil,
                               message: "Login failed. Check username and password.")
        }
        let ok = user.auth?.value == "1"
        return AccountInfo(
            ok: ok,
            status: user.status?.value,
            expiresAt: user.exp_date?.value.flatMap { Double($0) }.map { Date(timeIntervalSince1970: $0) },
            maxConnections: user.max_connections?.value.flatMap { Int($0) },
            activeConnections: user.active_cons?.value.flatMap { Int($0) },
            message: ok ? nil : (user.message?.value ?? "Login failed. Check username and password.")
        )
    }

    struct RawCategory: Decodable {
        let category_id: FlexString?
        let category_name: FlexString?
    }

    public static func parseCategories(_ data: Data) throws -> [ChannelCategory] {
        let raw = try JSONDecoder().decode([Lossy<RawCategory>].self, from: data)
        var out: [ChannelCategory] = []
        out.reserveCapacity(raw.count)
        for item in raw {
            guard let o = item.value, let id = o.category_id?.value else { continue }
            out.append(ChannelCategory(id: id, name: o.category_name?.value ?? "Category \(id)"))
        }
        return out
    }

    struct RawStream: Decodable {
        let stream_id: FlexString?
        let num: FlexString?
        let name: FlexString?
        let stream_icon: FlexString?
        let category_id: FlexString?
        let epg_channel_id: FlexString?
    }

    public static func parseStreams(_ data: Data, playlistId: String) throws -> [Channel] {
        let raw = try JSONDecoder().decode([Lossy<RawStream>].self, from: data)
        var seen = Set<String>()
        var out: [Channel] = []
        out.reserveCapacity(raw.count)
        for (i, item) in raw.enumerated() {
            guard let o = item.value, let id = o.stream_id?.value, seen.insert(id).inserted else { continue }
            let logo = o.stream_icon?.value.flatMap { $0.hasPrefix("http") ? $0 : nil }
            out.append(Channel(
                playlistId: playlistId,
                streamId: id,
                num: o.num?.value.flatMap { Int($0) } ?? (i + 1),
                name: o.name?.value ?? "Channel \(id)",
                logo: logo,
                categoryId: o.category_id?.value ?? "",
                epgId: o.epg_channel_id?.value
            ))
        }
        return out
    }

    struct RawListing: Decodable {
        let title: FlexString?
        let description: FlexString?
        let start: FlexString?
        let end: FlexString?
        let stop: FlexString?
        let start_timestamp: FlexString?
        let stop_timestamp: FlexString?
        let end_timestamp: FlexString?
    }

    struct RawEpg: Decodable {
        let epg_listings: [Lossy<RawListing>]?
    }

    public static func parseEpg(_ data: Data) -> [Program] {
        // Servers with no data sometimes answer with [] instead of an object.
        guard let root = try? JSONDecoder().decode(RawEpg.self, from: data),
              let listings = root.epg_listings else { return [] }
        var out: [Program] = []
        for item in listings {
            guard let o = item.value else { continue }
            let startFromEpoch = epoch(o.start_timestamp?.value)
            guard let start = startFromEpoch ?? parseClock(o.start?.value) else { continue }
            let endFromEpoch = epoch(o.stop_timestamp?.value ?? o.end_timestamp?.value)
            guard let end = endFromEpoch ?? parseClock(o.end?.value ?? o.stop?.value) else { continue }
            if end <= start { continue }
            out.append(Program(
                title: decodeText(o.title?.value) ?? "Untitled",
                summary: decodeText(o.description?.value),
                start: start,
                end: end
            ))
        }
        out.sort { $0.start < $1.start }
        // Drop overlapping duplicates so lists line up.
        var clean: [Program] = []
        for p in out {
            if let last = clean.last, p.start < last.end { continue }
            clean.append(p)
        }
        return clean
    }

    /// Xtream sends guide text base64-encoded. Falls back to the raw text if it isn't.
    static func decodeText(_ s: String?) -> String? {
        guard let s = s, !s.isEmpty else { return nil }
        if let data = Data(base64Encoded: s, options: .ignoreUnknownCharacters),
           let text = String(data: data, encoding: .utf8), !text.contains("\u{FFFD}") {
            return text.trimmedOrNil
        }
        return s.trimmedOrNil
    }

    private static func epoch(_ s: String?) -> Date? {
        guard let s = s, let seconds = Double(s) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    private static func parseClock(_ s: String?) -> Date? {
        guard let s = s else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.date(from: s)
    }
}
