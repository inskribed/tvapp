import Foundation

/// Channel search that matches whole words, so "|us|" finds "|US| CBS 2" but not
/// "Museum" or "Business" (the old search ignored word boundaries).
public enum ChannelSearch {

    /// "|US| ESPN 2 HD+" -> ["us", "espn", "2", "hd", "plus"]
    public static func words(_ s: String) -> [String] { ChannelMatcher.tokenize(s) }

    /// Every query word must be the start of a word in the name.
    /// ("cbs 2" matches "|US| CBS 2 (KTVT)"; "net" matches "NFL Network".)
    public static func matches(nameWords: [String], queryWords: [String]) -> Bool {
        guard !queryWords.isEmpty else { return false }
        for q in queryWords where !nameWords.contains(where: { $0.hasPrefix(q) }) { return false }
        return true
    }

    /// True when the name begins with the query's words in order ("us cbs" ranks "|US| CBS 2" first).
    public static func startsWith(nameWords: [String], queryWords: [String]) -> Bool {
        guard queryWords.count <= nameWords.count else { return false }
        for (i, q) in queryWords.enumerated() where !nameWords[i].hasPrefix(q) { return false }
        return true
    }

    /// Filters and ranks `names` (indexes into the caller's list). If no whole-word match exists,
    /// falls back to matching inside words, so "espnews"-style squashed names are still found.
    public static func search(query: String, words nameWords: [[String]], squashed: [String], limit: Int = 300) -> [Int] {
        let q = words(query)
        if q.isEmpty { return [] }
        var first: [Int] = []
        var rest: [Int] = []
        for i in nameWords.indices {
            let w = nameWords[i]
            if startsWith(nameWords: w, queryWords: q) {
                first.append(i)
            } else if matches(nameWords: w, queryWords: q) {
                rest.append(i)
            }
            if first.count >= limit { break }
        }
        if first.isEmpty && rest.isEmpty {
            let s = ChannelMatcher.normalize(query)
            guard s.count >= 3 else { return [] }
            return Array(squashed.indices.filter { squashed[$0].contains(s) }.prefix(limit))
        }
        return Array((first + rest).prefix(limit))
    }

    /// The country/region tag at the start of a group name: "|US| SPORTS" -> "US",
    /// "FR: Cinema" -> "FR", "UK - News" -> "UK". Nil when the name has no such tag.
    public static func groupPrefix(_ name: String) -> String? {
        var s = Substring(name.trimmingCharacters(in: .whitespaces))
        while let f = s.first, "|[(".contains(f) { s = s.dropFirst() }
        let tag = s.prefix { $0.isLetter || $0.isNumber }
        guard (2...4).contains(tag.count) else { return nil }
        var rest = s.dropFirst(tag.count)
        while rest.first == " " { rest = rest.dropFirst() }
        guard let sep = rest.first, "|:])-".contains(sep) else { return nil }
        return tag.uppercased()
    }
}
