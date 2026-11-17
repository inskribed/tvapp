import Foundation

/// Finds channels in the playlist that are likely carrying a game, using the
/// broadcast network names and event-style channel names ("NBA 03: Warriors vs Lakers").
/// Built once per channel list (off the main thread), then each lookup takes milliseconds.
public final class ChannelMatcher: @unchecked Sendable {

    private let channels: [Channel]
    private let tokens: [[String]]
    private let index: [String: [Int]]

    public init(channels: [Channel]) {
        self.channels = channels
        let toks = channels.map { ChannelMatcher.tokenize($0.name) }
        self.tokens = toks
        var map: [String: [Int]] = [:]
        for (i, t) in toks.enumerated() {
            for word in Set(t) { map[word, default: []].append(i) }
        }
        self.index = map
    }

    public func match(_ game: Game, limit: Int = 12) -> [Channel] {
        var scores: [Int: Int] = [:]
        func bump(_ i: Int, _ s: Int) {
            if (scores[i] ?? 0) < s { scores[i] = s }
        }

        // Event or team channels named after the teams.
        let awayHits = findSequence(Self.tokenize(game.away.team.nickname))
        let homeHits = findSequence(Self.tokenize(game.home.team.nickname))
        let leagueTokens = Self.leagueTokens[game.league] ?? []
        for i in awayHits.intersection(homeHits) { bump(i, 100) }
        for i in awayHits.union(homeHits) where tokens[i].contains(where: { leagueTokens.contains($0) }) {
            bump(i, 80)
        }

        // Broadcast networks.
        for network in game.networks {
            let aliases = Self.aliases[Self.normalize(network)] ?? [Self.tokenize(network)]
            for alias in aliases where !alias.isEmpty {
                let strict = alias.count == 1 && Self.generic.contains(alias[0])
                for i in findSequence(alias, strict: strict) { bump(i, 50) }
            }
        }

        let ranked = scores
            .map { (i: $0.key, score: $0.value + quality(tokens[$0.key])) }
            .sorted { a, b in
                if a.score != b.score { return a.score > b.score }
                let la = channels[a.i].name.count
                let lb = channels[b.i].name.count
                if la != lb { return la < lb }
                return a.i < b.i
            }
        return ranked.prefix(limit).map { channels[$0.i] }
    }

    /// Channel indices whose name contains `seq` as consecutive words.
    private func findSequence(_ seq: [String], strict: Bool = false) -> Set<Int> {
        guard let first = seq.first, let candidates = index[first] else { return [] }
        var out = Set<Int>()
        for i in candidates {
            let t = tokens[i]
            if t.count < seq.count { continue }
            for start in 0...(t.count - seq.count) {
                var ok = true
                for k in 0..<seq.count where t[start + k] != seq[k] { ok = false; break }
                if !ok { continue }
                if strict {
                    let nextIndex = start + seq.count
                    if nextIndex < t.count, Self.excludeAfter.contains(t[nextIndex]) { continue }
                }
                out.insert(i)
                break
            }
        }
        return out
    }

    private func quality(_ t: [String]) -> Int {
        var s = 0
        if t.contains("4k") || t.contains("uhd") { s += 3 }
        else if t.contains("fhd") { s += 2 }
        else if t.contains("hd") { s += 1 }
        if t.contains("us") || t.contains("usa") { s += 5 }
        if t.contains(where: { Self.foreign.contains($0) }) { s -= 20 }
        return s
    }

    // MARK: Words

    public static func tokenize(_ s: String) -> [String] {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789")
        return s.lowercased()
            .replacingOccurrences(of: "+", with: " plus ")
            .components(separatedBy: allowed.inverted)
            .filter { !$0.isEmpty }
    }

    public static func normalize(_ s: String) -> String {
        String(s.lowercased().replacingOccurrences(of: "+", with: "plus").filter { $0.isLetter || $0.isNumber })
    }

    private static let leagueTokens: [League: Set<String>] = [
        .nfl: ["nfl"],
        .nba: ["nba"],
        .mlb: ["mlb"],
        .nhl: ["nhl"],
        .ncaaf: ["ncaaf", "ncaa", "cfb", "college"],
    ]

    private static let generic: Set<String> = ["fox", "abc", "cbs", "nbc", "espn", "tnt", "tbs"]
    private static let excludeAfter: Set<String> = [
        "news", "business", "sports", "sport", "soccer", "deportes", "life", "kids", "weather",
        "classic", "nation", "music", "movies", "docs", "now", "2", "u", "plus", "network", "comedy",
    ]
    private static let foreign: Set<String> = ["uk", "ca", "mx", "es", "latino", "ar", "br", "fr", "de", "it", "pt", "au", "nz", "in"]

    private static func seqs(_ s: String...) -> [[String]] { s.map { tokenize($0) } }

    private static let aliases: [String: [[String]]] = [
        "espn": seqs("espn"),
        "espn2": seqs("espn2", "espn 2"),
        "espnu": seqs("espnu", "espn u"),
        "espnews": seqs("espnews", "espn news"),
        "espnplus": seqs("espn plus", "espnplus"),
        "abc": seqs("abc"),
        "cbs": seqs("cbs"),
        "nbc": seqs("nbc"),
        "fox": seqs("fox"),
        "fs1": seqs("fs1", "fox sports 1"),
        "fs2": seqs("fs2", "fox sports 2"),
        "tnt": seqs("tnt"),
        "tbs": seqs("tbs"),
        "trutv": seqs("trutv", "tru tv"),
        "nbatv": seqs("nba tv", "nbatv"),
        "nflnet": seqs("nfl network", "nfl net"),
        "nflnetwork": seqs("nfl network", "nfl net"),
        "nflredzone": seqs("redzone", "red zone"),
        "mlbnet": seqs("mlb network", "mlb net"),
        "mlbnetwork": seqs("mlb network", "mlb net"),
        "nhlnet": seqs("nhl network", "nhl net"),
        "nhlnetwork": seqs("nhl network", "nhl net"),
        "cbssn": seqs("cbs sports network", "cbssn", "cbs sports net"),
        "cbssportsnetwork": seqs("cbs sports network", "cbssn"),
        "btn": seqs("btn", "big ten network", "big 10 network"),
        "bigtennetwork": seqs("btn", "big ten network"),
        "secn": seqs("sec network", "secn"),
        "secnetwork": seqs("sec network", "secn"),
        "accn": seqs("acc network", "accn"),
        "accnetwork": seqs("acc network", "accn"),
        "mwn": seqs("mountain west", "mw network"),
        "mountainwestnetwork": seqs("mountain west", "mw network"),
        "nbcsba": seqs("nbc sports bay area", "nbcs bay area", "nbcsba", "nbcs ba", "nbc bay area sports"),
        "nbcsbayarea": seqs("nbc sports bay area", "nbcs bay area", "nbcsba"),
        "nbcsportsbayarea": seqs("nbc sports bay area", "nbcs bay area", "nbcsba"),
        "nbcscal": seqs("nbc sports california", "nbcs california", "nbcs ca"),
        "nbcsportscalifornia": seqs("nbc sports california", "nbcs california"),
        "primevideo": seqs("prime video", "amazon prime", "prime"),
        "prime": seqs("prime video", "amazon prime"),
        "peacock": seqs("peacock"),
        "netflix": seqs("netflix"),
        "kmcc": seqs("vegas 34", "kmcc", "knighttime", "knight time"),
        "vegas34": seqs("vegas 34", "kmcc", "knighttime"),
        "scripps": seqs("vegas 34", "kmcc", "knighttime", "scripps"),
        "knighttimeplus": seqs("knighttime", "knight time"),
    ]
}
