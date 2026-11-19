import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// TV guide for M3U playlists, from XMLTV files (often .xml.gz). Same rules as the TV app's
/// `data/Xmltv.kt`. Built to stay light: only the guide files your shown channels need, only your
/// channels, and only from 2 hours ago to 24 hours ahead.
public enum XMLTV {
    public static let maxFiles = 8
    public static let lookBack: TimeInterval = 2 * 3600
    public static let lookAhead: TimeInterval = 24 * 3600
    static let maxSummary = 400

    // MARK: Which guide files to download

    /// Country codes of the given channels, from their guide ids ("Rai1.it" -> IT, "ABC.us@East" -> US),
    /// with how many channels each has.
    public static func countryCodes(of channels: [Channel]) -> [String: Int] {
        var out: [String: Int] = [:]
        for ch in channels {
            guard let id = ch.epgId, let dot = id.lastIndex(of: ".") else { continue }
            let tail = id[id.index(after: dot)...].split(separator: "@").first.map(String.init) ?? ""
            guard tail.count == 2, tail.allSatisfy(\.isLetter) else { continue }
            let code = tail.uppercased()
            out[code, default: 0] += 1
            if code == "GB" { out["UK", default: 0] += 1 }
            if code == "UK" { out["GB", default: 0] += 1 }
        }
        return out
    }

    /// The country code in a guide file's name: "epg_ripper_IT1.xml.gz" -> IT. Nil for network files.
    static func fileCountryCode(_ url: String) -> String? {
        let name = (url.split(separator: "/").last.map(String.init) ?? url).lowercased()
        guard let re = try? NSRegularExpression(pattern: "(?:^|[_\\-.])([a-z]{2})\\d*\\.xml(?:\\.gz)?$"),
              let m = re.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)),
              let r = Range(m.range(at: 1), in: name) else { return nil }
        return name[r].uppercased()
    }

    /// Picks the guide files to download. Small lists are used whole (minus "all sources" and dummy
    /// files, which are huge or useless). Long lists, like Free-TV's 100+ files, are cut down to the
    /// countries your shown channels come from, most channels first, at most `maxFiles`.
    public static func chooseSources(urls: [String], countries: [String: Int]) -> [String] {
        var seen = Set<String>()
        let usable = urls
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { u in
                let l = u.lowercased()
                return l.hasPrefix("http") && !l.contains("all_sources") && !l.contains("dummy") && seen.insert(u).inserted
            }
        if usable.count <= 3 { return usable }
        // For each country keep only its plainest file(s): "epg_ripper_IT1" over "epg_ripper_RAKUTEN_IT1".
        func fileName(_ u: String) -> String { (u.split(separator: "/").last.map(String.init) ?? u).lowercased() }
        var shortest: [String: Int] = [:]
        for u in usable {
            if let code = fileCountryCode(u) { shortest[code] = min(shortest[code] ?? .max, fileName(u).count) }
        }
        let scored = usable.compactMap { u -> (String, Int)? in
            guard let code = fileCountryCode(u), let n = countries[code], fileName(u).count == shortest[code] else { return nil }
            return (u, n)
        }
        return scored
            .enumerated()
            .sorted { a, b in a.element.1 != b.element.1 ? a.element.1 > b.element.1 : a.offset < b.offset }
            .prefix(maxFiles)
            .map(\.element.0)
    }

    // MARK: Matching guide channels to playlist channels

    /// Finds which playlist channels a guide channel belongs to: by guide id, then the id with
    /// punctuation removed ("Rai.1.it" = "Rai1.it"), then by name ("Rai 1 HD" = "RAI 1").
    public final class Matcher: @unchecked Sendable {
        private var byId: [String: [String]] = [:]
        private var byLooseId: [String: [String]] = [:]
        private var byName: [String: [String]] = [:]

        public init(channels: [Channel]) {
            func add(_ map: inout [String: [String]], _ key: String, _ value: String) {
                guard !key.isEmpty else { return }
                if map[key]?.contains(value) != true { map[key, default: []].append(value) }
            }
            for ch in channels {
                if let e = ch.epgId?.trimmingCharacters(in: .whitespaces), !e.isEmpty {
                    let l = e.lowercased()
                    add(&byId, l, ch.id)
                    let base = l.split(separator: "@").first.map(String.init) ?? l
                    add(&byId, base, ch.id)
                    add(&byLooseId, XMLTV.looseId(base), ch.id)
                }
                add(&byName, XMLTV.looseName(ch.name), ch.id)
            }
        }

        public func keys(xmlId: String, names: [String]) -> [String] {
            let l = xmlId.trimmingCharacters(in: .whitespaces).lowercased()
            if let k = byId[l] { return k }
            let base = l.split(separator: "@").first.map(String.init) ?? l
            if let k = byId[base] { return k }
            if let k = byLooseId[XMLTV.looseId(base)] { return k }
            for n in names {
                if let k = byName[XMLTV.looseName(n)] { return k }
            }
            return []
        }
    }

    static func looseId(_ s: String) -> String {
        String(s.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    private static let qualityWords: Set<String> = ["hd", "fhd", "uhd", "sd", "4k", "8k", "hevc", "h265", "1080p", "720p", "576p", "480p", "backup"]

    /// "Rai 1 HD (1080p) Ⓢ" -> "rai1". Words in brackets and picture-quality words are ignored.
    static func looseName(_ s: String) -> String {
        var cleaned = ""
        var depth = 0
        for c in s {
            if c == "(" || c == "[" { depth += 1; continue }
            if c == ")" || c == "]" { depth = max(0, depth - 1); continue }
            if depth == 0 { cleaned.append(c) }
        }
        return ChannelMatcher.tokenize(cleaned).filter { !qualityWords.contains($0) }.joined()
    }

    // MARK: Reading a guide file

    /// "20261119120000 +0100" (or without the offset, meaning UTC) -> Date.
    public static func parseTime(_ s: String) -> Date? {
        let chars = Array(s.trimmingCharacters(in: .whitespaces))
        guard chars.count >= 12 else { return nil }
        func num(_ from: Int, _ len: Int) -> Int? {
            guard from + len <= chars.count else { return nil }
            var v = 0
            for c in chars[from..<(from + len)] {
                guard let d = c.wholeNumberValue else { return nil }
                v = v * 10 + d
            }
            return v
        }
        guard let y = num(0, 4), let mo = num(4, 2), let d = num(6, 2), let h = num(8, 2), let mi = num(10, 2) else { return nil }
        let sec = num(12, 2) ?? 0
        var offset = 0
        if let signIndex = chars.firstIndex(where: { $0 == "+" || $0 == "-" }), signIndex >= 12,
           let oh = num(signIndex + 1, 2), let om = num(signIndex + 3, 2) {
            offset = (oh * 3600 + om * 60) * (chars[signIndex] == "-" ? -1 : 1)
        }
        let days = daysFromCivil(y, mo, d)
        let epoch = days * 86400 + h * 3600 + mi * 60 + sec - offset
        return Date(timeIntervalSince1970: TimeInterval(epoch))
    }

    /// Days since 1970-01-01 for a calendar date (no Calendar needed, so reading is fast).
    static func daysFromCivil(_ year: Int, _ month: Int, _ day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    /// Adds the programs for matched channels in [from, to] to `into` (keyed by channel id).
    /// Returns how many guide channels matched.
    @discardableResult
    public static func parse(_ data: Data, matcher: Matcher, from: Date, to: Date, into: inout [String: [Program]]) -> Int {
        let collector = Collector(matcher: matcher, from: from, to: to)
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = collector
        parser.parse() // a broken file still keeps what was read before the error
        for (k, v) in collector.programs { into[k, default: []].append(contentsOf: v) }
        return collector.matchedChannels
    }

    /// Sorts each channel's programs and drops overlapping duplicates (two files can cover one channel).
    public static func tidy(_ guide: inout [String: [Program]]) {
        for (k, list) in guide {
            var clean: [Program] = []
            for p in list.sorted(by: { $0.start < $1.start }) {
                if let last = clean.last, p.start < last.end { continue }
                clean.append(p)
            }
            guide[k] = clean
        }
    }

    private final class Collector: NSObject, XMLParserDelegate {
        let matcher: Matcher
        let from: Date
        let to: Date
        var programs: [String: [Program]] = [:]
        var matchedChannels = 0

        private var channelKeys: [String: [String]] = [:]
        private var channelId: String?
        private var names: [String] = []
        private var inProgramme = false
        private var progChannel = ""
        private var progStart: Date?
        private var progStop: Date?
        private var title: String?
        private var summary: String?
        private var text = ""
        private var capturing = false

        init(matcher: Matcher, from: Date, to: Date) {
            self.matcher = matcher
            self.from = from
            self.to = to
        }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            switch name {
            case "channel":
                channelId = attributes["id"]
                names = []
            case "display-name" where channelId != nil:
                text = ""; capturing = true
            case "programme":
                inProgramme = true
                progChannel = attributes["channel"] ?? ""
                progStart = attributes["start"].flatMap(XMLTV.parseTime)
                progStop = attributes["stop"].flatMap(XMLTV.parseTime)
                title = nil
                summary = nil
            case "title" where inProgramme && title == nil, "desc" where inProgramme && summary == nil:
                text = ""; capturing = true
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if capturing { text += string }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            switch name {
            case "display-name":
                if capturing, channelId != nil { names.append(text.trimmingCharacters(in: .whitespacesAndNewlines)) }
                capturing = false
            case "channel":
                if let id = channelId {
                    let keys = matcher.keys(xmlId: id, names: names)
                    channelKeys[id] = keys
                    if !keys.isEmpty { matchedChannels += 1 }
                }
                channelId = nil
            case "title":
                if capturing { title = text.trimmingCharacters(in: .whitespacesAndNewlines) }
                capturing = false
            case "desc":
                if capturing { summary = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(XMLTV.maxSummary)) }
                capturing = false
            case "programme":
                inProgramme = false
                guard let start = progStart, let stop = progStop, stop > start, stop > from, start < to else { return }
                let keys: [String]
                if let known = channelKeys[progChannel] {
                    keys = known
                } else {
                    // A guide may list programmes for channels it didn't describe first.
                    keys = matcher.keys(xmlId: progChannel, names: [])
                    channelKeys[progChannel] = keys
                }
                guard !keys.isEmpty else { return }
                let program = Program(title: (title?.isEmpty == false ? title : nil) ?? "Untitled",
                                      summary: summary?.isEmpty == false ? summary : nil,
                                      start: start, end: stop)
                for k in keys { programs[k, default: []].append(program) }
            default:
                break
            }
        }
    }

    // MARK: Unzipping .gz guide files

    /// Unzips gzip data (guide files are usually .xml.gz); returns plain data unchanged.
    public static func gunzipIfNeeded(_ data: Data) -> Data? {
        let bytes = [UInt8](data.prefix(10))
        guard bytes.count >= 10, bytes[0] == 0x1f, bytes[1] == 0x8b else { return data }
        #if canImport(Darwin)
        let all = [UInt8](data)
        guard all[2] == 8 else { return nil } // deflate
        let flags = all[3]
        var pos = 10
        if flags & 0x04 != 0, pos + 2 <= all.count { pos += 2 + Int(all[pos]) + Int(all[pos + 1]) << 8 }
        if flags & 0x08 != 0 { while pos < all.count, all[pos] != 0 { pos += 1 }; pos += 1 }
        if flags & 0x10 != 0 { while pos < all.count, all[pos] != 0 { pos += 1 }; pos += 1 }
        if flags & 0x02 != 0 { pos += 2 }
        guard pos < all.count - 8 else { return nil }
        let deflate = Data(all[pos..<(all.count - 8)])
        return try? (deflate as NSData).decompressed(using: .zlib) as Data
        #else
        return nil
        #endif
    }
}
