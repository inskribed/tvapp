import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension XtreamClient {
    /// Downloads and reads an M3U playlist. Like the Xtream channel list, this is all the app
    /// needs at launch; it's saved on the phone and refreshed in the background.
    public func fetchM3U(_ p: Playlist) async throws -> M3UParser.Result {
        guard let s = p.m3uURL, let url = URL(string: s) else { throw OrkaError.badAddress }
        let data = try await get(url)
        let text = String(decoding: data, as: UTF8.self)
        guard text.contains("#EXTINF") else { throw OrkaError.notM3U }
        return M3UParser.parse(text, playlistId: p.id)
    }

    /// "example.com/list.m3u" -> "http://example.com/list.m3u"
    public static func normalizeLink(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = s.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") { return s }
        return "http://" + s
    }
}
