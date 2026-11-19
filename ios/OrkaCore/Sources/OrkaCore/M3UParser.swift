import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Reads M3U playlists (the format legal IPTV sources use: Free-TV, iptv-org, HDHomeRun,
/// Plex/Jellyfin live TV...). Same rules as the TV app's `data/M3uParser.kt`.
public enum M3UParser {

    public struct Result: Sendable {
        public var data: LiveData
        /// Guide (XMLTV) links named in the playlist header (`url-tvg` / `x-tvg-url`).
        public var guideURLs: [String]
    }

    public static func parse(_ text: String, playlistId: String) -> Result {
        var guideURLs: [String] = []
        var groups: [String] = []          // first-seen order
        var groupSet = Set<String>()
        var channels: [Channel] = []
        var usedIds = Set<String>()

        var info: (attrs: [String: String], title: String)?
        var userAgent: String?
        var referrer: String?
        var extGroup: String?

        for raw in text.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("\u{FEFF}") { line.removeFirst() }
            if line.isEmpty { continue }

            if line.hasPrefix("#EXTM3U") {
                let attrs = attributes(in: line)
                for key in ["url-tvg", "x-tvg-url"] {
                    for u in (attrs[key] ?? "").split(separator: ",") {
                        let t = u.trimmingCharacters(in: .whitespaces)
                        if t.hasPrefix("http"), !guideURLs.contains(t) { guideURLs.append(t) }
                    }
                }
            } else if line.hasPrefix("#EXTINF") {
                info = parseExtinf(line)
                userAgent = nil
                referrer = nil
                extGroup = nil
            } else if line.hasPrefix("#EXTVLCOPT:") {
                let opt = line.dropFirst("#EXTVLCOPT:".count)
                if let eq = opt.firstIndex(of: "=") {
                    let key = opt[..<eq].lowercased()
                    let value = String(opt[opt.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
                    if key == "http-user-agent" { userAgent = value }
                    if key == "http-referrer" || key == "http-referer" { referrer = value }
                }
            } else if line.hasPrefix("#EXTGRP:") {
                extGroup = String(line.dropFirst("#EXTGRP:".count)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("#") {
                continue // #KODIPROP, #EXTVLCOPT we don't use, comments
            } else {
                // A stream address. Only the entry right after an #EXTINF counts.
                guard let entry = info else { continue }
                info = nil
                guard isPlayable(line) else { continue }

                let attrs = entry.attrs
                let group = groupName(attrs: attrs, extGroup: extGroup)
                if groupSet.insert(group).inserted { groups.append(group) }

                var id = stableId(line)
                var n = 2
                while usedIds.contains(id) { id = stableId(line + "#\(n)"); n += 1 }
                usedIds.insert(id)

                let title = entry.title.isEmpty ? (attrs["tvg-name"] ?? "Channel \(channels.count + 1)") : entry.title
                let logo = attrs["tvg-logo"].flatMap { $0.hasPrefix("http") ? $0 : nil }
                channels.append(Channel(
                    playlistId: playlistId,
                    streamId: id,
                    num: attrs["tvg-chno"].flatMap { Int($0) } ?? (channels.count + 1),
                    name: title,
                    logo: logo,
                    categoryId: group,
                    epgId: attrs["tvg-id"]?.trimmedOrNil,
                    url: line,
                    userAgent: userAgent,
                    referrer: referrer
                ))
            }
        }
        let cats = groups.map { ChannelCategory(id: $0, name: $0) }
        return Result(data: LiveData(categories: cats, channels: channels, guideURLs: guideURLs), guideURLs: guideURLs)
    }

    // MARK: Pieces

    /// `#EXTINF:-1 tvg-id="x" group-title="News, Sports",Channel Name` -> attributes + title.
    /// The title starts after the first comma that isn't inside quotes.
    static func parseExtinf(_ line: String) -> (attrs: [String: String], title: String) {
        var inQuotes = false
        var split: String.Index?
        for i in line.indices {
            let c = line[i]
            if c == "\"" { inQuotes.toggle() }
            if c == "," && !inQuotes { split = i; break }
        }
        guard let comma = split else { return (attributes(in: line), "") }
        let head = String(line[..<comma])
        let title = String(line[line.index(after: comma)...]).trimmingCharacters(in: .whitespaces)
        return (attributes(in: head), title)
    }

    /// key="value" pairs (keys lowercased).
    static func attributes(in s: String) -> [String: String] {
        var out: [String: String] = [:]
        let scalars = Array(s)
        var i = 0
        while i < scalars.count {
            // find key=" ... "
            guard let eq = scalars[i...].firstIndex(of: "=") else { break }
            guard eq + 1 < scalars.count, scalars[eq + 1] == "\"" else { i = eq + 1; continue }
            var k = eq - 1
            while k >= 0, scalars[k].isLetter || scalars[k].isNumber || scalars[k] == "-" || scalars[k] == "_" { k -= 1 }
            let key = String(scalars[(k + 1)..<eq]).lowercased()
            guard let close = scalars[(eq + 2)...].firstIndex(of: "\"") else { break }
            let value = String(scalars[(eq + 2)..<close]).trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { out[key] = value }
            i = close + 1
        }
        return out
    }

    /// group-title (first of "A;B"), then #EXTGRP, then the country (tvg-country or the ".us" in tvg-id).
    static func groupName(attrs: [String: String], extGroup: String?) -> String {
        if let g = attrs["group-title"]?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces), !g.isEmpty {
            return g
        }
        if let g = extGroup?.trimmedOrNil { return g }
        if let c = attrs["tvg-country"]?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces), !c.isEmpty {
            return c.uppercased()
        }
        // iptv-org: tvg-id="ABC.us@East" -> "US"
        if let id = attrs["tvg-id"], let dot = id.lastIndex(of: ".") {
            let rest = id[id.index(after: dot)...]
            let code = rest.split(separator: "@").first.map(String.init) ?? ""
            if (2...3).contains(code.count), code.allSatisfy(\.isLetter) { return code.uppercased() }
        }
        return "Other"
    }

    /// Real stream addresses only; video web pages (YouTube, Twitch) and placeholders are skipped.
    static func isPlayable(_ url: String) -> Bool {
        let lower = url.lowercased()
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("rtmp://") || lower.hasPrefix("rtsp://") else {
            return false
        }
        for page in ["youtube.com/", "youtu.be/", "twitch.tv/", "dailymotion.com/video"] where lower.contains(page) {
            return false
        }
        return true
    }

    /// Same address -> same id across refreshes, so favorites stick. ("m" + 12 hex of SHA-1.)
    public static func stableId(_ s: String) -> String {
        #if canImport(CryptoKit)
        let digest = Insecure.SHA1.hash(data: Data(s.utf8))
        return "m" + digest.prefix(6).map { String(format: "%02x", $0) }.joined()
        #else
        var h: UInt64 = 1469598103934665603
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return "m" + String(h, radix: 16)
        #endif
    }
}
