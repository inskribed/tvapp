import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum League: String, CaseIterable, Codable, Hashable, Sendable {
    case nfl = "NFL"
    case nba = "NBA"
    case mlb = "MLB"
    case nhl = "NHL"
    case ncaaf = "NCAAF"

    public var label: String { rawValue }

    public var path: String {
        switch self {
        case .nfl: return "football/nfl"
        case .nba: return "basketball/nba"
        case .mlb: return "baseball/mlb"
        case .nhl: return "hockey/nhl"
        case .ncaaf: return "football/college-football"
        }
    }

    /// Leagues that play most days also fetch tomorrow's games.
    public var daily: Bool {
        switch self {
        case .nba, .mlb, .nhl: return true
        case .nfl, .ncaaf: return false
        }
    }
}

public struct Team: Codable, Hashable, Identifiable, Sendable {
    public var league: League
    public var teamId: String
    public var displayName: String
    public var shortName: String
    public var nickname: String
    public var abbr: String
    public var logo: String?

    /// e.g. "NFL:19"
    public var key: String { "\(league.rawValue):\(teamId)" }
    public var id: String { key }

    public init(league: League, teamId: String, displayName: String, shortName: String, nickname: String, abbr: String, logo: String?) {
        self.league = league
        self.teamId = teamId
        self.displayName = displayName
        self.shortName = shortName
        self.nickname = nickname
        self.abbr = abbr
        self.logo = logo
    }
}

public struct GameTeam: Codable, Hashable, Sendable {
    public var team: Team
    public var score: String?
    public var home: Bool
    public var record: String?

    public init(team: Team, score: String?, home: Bool, record: String?) {
        self.team = team
        self.score = score
        self.home = home
        self.record = record
    }
}

public enum GameState: String, Codable, Sendable {
    case pre, live, post
}

public struct Game: Codable, Hashable, Identifiable, Sendable {
    public var gameId: String
    public var league: League
    public var start: Date
    public var state: GameState
    public var detail: String
    public var away: GameTeam
    public var home: GameTeam
    public var networks: [String]

    public var id: String { "\(league.rawValue)-\(gameId)" }
    public var title: String { "\(away.team.shortName) at \(home.team.shortName)" }

    public func involves(_ teamKeys: Set<String>) -> Bool {
        teamKeys.contains(away.team.key) || teamKeys.contains(home.team.key)
    }

    public init(gameId: String, league: League, start: Date, state: GameState, detail: String,
                away: GameTeam, home: GameTeam, networks: [String]) {
        self.gameId = gameId
        self.league = league
        self.start = start
        self.state = state
        self.detail = detail
        self.away = away
        self.home = home
        self.networks = networks
    }
}

/// Reads ESPN's public scoreboard and team lists. Fast and small, and independent of the IPTV provider.
public struct SportsClient: Sendable {
    static let base = "https://site.api.espn.com/apis/site/v2/sports"

    public let session: URLSession

    public init(session: URLSession = XtreamClient.makeSession()) {
        self.session = session
    }

    private func getData(_ urlString: String) async throws -> Data {
        guard let url = URL(string: urlString) else { throw OrkaError.badAddress }
        var req = URLRequest(url: url)
        req.setValue(XtreamClient.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw OrkaError.http(http.statusCode)
        }
        return data
    }

    public func games(for league: League, now: Date = Date()) async throws -> [Game] {
        let urls: [String]
        if league.daily {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyyMMdd"
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
            urls = ["\(Self.base)/\(league.path)/scoreboard", "\(Self.base)/\(league.path)/scoreboard?dates=\(f.string(from: tomorrow))"]
        } else if league == .ncaaf {
            urls = ["\(Self.base)/\(league.path)/scoreboard?groups=80&limit=300"]
        } else {
            urls = ["\(Self.base)/\(league.path)/scoreboard"]
        }

        // Both days load at once.
        var results: [(Int, Data)] = []
        var lastError: Error?
        await withTaskGroup(of: (Int, Data?, Error?).self) { group in
            for (i, u) in urls.enumerated() {
                group.addTask {
                    do {
                        return (i, try await self.getData(u), nil)
                    } catch {
                        return (i, nil, error)
                    }
                }
            }
            for await (i, data, error) in group {
                if let data { results.append((i, data)) }
                if let error { lastError = error }
            }
        }
        results.sort { $0.0 < $1.0 }

        var ordered: [String] = []
        var byId: [String: Game] = [:]
        for (_, data) in results {
            for g in Self.parseScoreboard(data, league: league) {
                if byId[g.id] == nil { ordered.append(g.id) }
                byId[g.id] = g
            }
        }
        if ordered.isEmpty, let lastError { throw lastError }
        return ordered.compactMap { byId[$0] }
    }

    public func teams(for league: League) async throws -> [Team] {
        let data = try await getData("\(Self.base)/\(league.path)/teams?limit=1000")
        return Self.parseTeams(data, league: league)
    }

    // MARK: Parsing

    public static func parseScoreboard(_ data: Data, league: League) -> [Game] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let events = root["events"] as? [[String: Any]] else { return [] }
        return events.compactMap { parseGame($0, league: league) }
    }

    static func parseGame(_ ev: [String: Any], league: League) -> Game? {
        guard let comps = ev["competitions"] as? [[String: Any]], let comp = comps.first else { return nil }
        let status = (ev["status"] as? [String: Any]) ?? (comp["status"] as? [String: Any])
        let type = status?["type"] as? [String: Any]
        let state: GameState
        switch type?.str("state") {
        case "in": state = .live
        case "post": state = .post
        default: state = .pre
        }
        let detail = type?.str("shortDetail") ?? type?.str("detail") ?? ""

        guard let competitors = comp["competitors"] as? [[String: Any]] else { return nil }
        var home: GameTeam?
        var away: GameTeam?
        for c in competitors {
            guard let t = c["team"] as? [String: Any], let team = parseTeam(t, league: league) else { continue }
            let record = ((c["records"] as? [[String: Any]])?.first)?.str("summary")
            let gt = GameTeam(team: team, score: c.str("score"), home: c.str("homeAway") == "home", record: record)
            if gt.home { home = gt } else { away = gt }
        }
        guard let h = home, let a = away, let id = ev.str("id") else { return nil }

        var networks: [String] = []
        func add(_ n: String?) {
            guard let n = n?.trimmedOrNil, !networks.contains(n) else { return }
            networks.append(n)
        }
        for b in (comp["broadcasts"] as? [[String: Any]]) ?? [] {
            for name in (b["names"] as? [String]) ?? [] { add(name) }
        }
        for b in (comp["geoBroadcasts"] as? [[String: Any]]) ?? [] {
            add((b["media"] as? [String: Any])?.str("shortName"))
        }

        return Game(
            gameId: id,
            league: league,
            start: parseDate(ev.str("date") ?? comp.str("date")),
            state: state,
            detail: detail,
            away: a,
            home: h,
            networks: networks
        )
    }

    static func parseTeam(_ t: [String: Any], league: League) -> Team? {
        guard let id = t.str("id"), let display = t.str("displayName") ?? t.str("name") else { return nil }
        let logo = t.str("logo") ?? ((t["logos"] as? [[String: Any]])?.first)?.str("href")
        return Team(
            league: league,
            teamId: id,
            displayName: display,
            shortName: t.str("shortDisplayName") ?? display,
            nickname: t.str("name") ?? t.str("shortDisplayName") ?? display,
            abbr: t.str("abbreviation") ?? String(display.prefix(3)).uppercased(),
            logo: logo
        )
    }

    public static func parseTeams(_ data: Data, league: League) -> [Team] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let sports = root["sports"] as? [[String: Any]],
              let leagues = sports.first?["leagues"] as? [[String: Any]],
              let teams = leagues.first?["teams"] as? [[String: Any]] else { return [] }
        return teams
            .compactMap { ($0["team"] as? [String: Any]).flatMap { parseTeam($0, league: league) } }
            .sorted { $0.displayName < $1.displayName }
    }

    /// ESPN dates look like "2026-11-12T22:15Z" (no seconds), so a few formats are tried.
    static func parseDate(_ s: String?) -> Date {
        let none = Date(timeIntervalSince1970: 0)
        guard let s = s else { return none }
        let iso = ISO8601DateFormatter()
        let options: [ISO8601DateFormatter.Options] = [
            [.withInternetDateTime],
            [.withInternetDateTime, .withFractionalSeconds],
        ]
        for o in options {
            iso.formatOptions = o
            if let d = iso.date(from: s) { return d }
        }
        for format in ["yyyy-MM-dd'T'HH:mmX", "yyyy-MM-dd'T'HH:mm:ssX"] {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = format
            if let d = f.date(from: s) { return d }
        }
        return none
    }
}
