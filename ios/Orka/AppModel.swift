import Foundation
import Observation
import SwiftUI
import OrkaCore

enum AppTab: Hashable {
    case home, guide, sports, favorites, search
}

/// Where each kind of content stands. Only Live TV syncs on its own; Movies and Series are
/// synced by hand (Settings > Library) so the app opens fast.
enum SyncState: Equatable {
    case idle
    case syncing
    case failed(String)
}

struct EpgEntry {
    var programs: [Program]
    var fetched: Date
    var failed: Bool
}

/// Everything Live TV needs, prepared off the main thread.
struct Library: Sendable {
    var categories: [Category] = []
    var channels: [Channel] = []
    var normalizedNames: [String] = []
    var counts: [String: Int] = [:]

    static func build(_ data: LiveData) -> Library {
        var counts: [String: Int] = [:]
        for ch in data.channels { counts[ch.categoryId, default: 0] += 1 }
        return Library(
            categories: data.categories,
            channels: data.channels,
            normalizedNames: data.channels.map { ChannelMatcher.normalize($0.name) },
            counts: counts
        )
    }
}

/// Lets only a few guide requests run at once.
actor Limiter {
    private let limit: Int
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(_ limit: Int) { self.limit = limit }

    func acquire() async {
        if running < limit {
            running += 1
        } else {
            await withCheckedContinuation { waiters.append($0) }
        }
    }

    func release() {
        if waiters.isEmpty {
            running -= 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}

@MainActor
@Observable
final class AppModel {
    static let favoritesGroup = "__fav__"
    static let allGroup = "__all__"

    // MARK: Services
    @ObservationIgnored private let store = Store()
    @ObservationIgnored private let cache = LiveCacheStore()
    @ObservationIgnored private let xtream: XtreamClient
    @ObservationIgnored private let sportsClient: SportsClient
    @ObservationIgnored private let limiter = Limiter(4)
    @ObservationIgnored private var booted = false
    @ObservationIgnored private var matchCache: [String: [Channel]] = [:]
    let player = PlayerModel()

    // MARK: Navigation
    var tab: AppTab = .home
    var showPlayer = false
    var showSettings = false
    var searchQuery = ""
    var guideGroup = AppModel.allGroup

    // MARK: Playlists
    private(set) var playlists: [Playlist] = []
    private(set) var activeID: String?
    private(set) var account: AccountInfo?
    var active: Playlist? { playlists.first { $0.id == activeID } ?? playlists.first }

    // MARK: Live TV
    private(set) var library = Library()
    private(set) var channelsVersion = 0
    private(set) var liveSyncedAt: Date?
    private(set) var syncStates: [ContentKind: SyncState] = [.live: .idle, .movies: .idle, .series: .idle]
    private(set) var matcher: ChannelMatcher?
    var channels: [Channel] { library.channels }
    var categories: [Category] { library.categories }

    // MARK: Favorites and recents
    private(set) var favorites: [Channel] = []
    private(set) var favoriteIDs: Set<String> = []
    private(set) var recents: [Channel] = []

    // MARK: Guide
    private(set) var epg: [String: EpgEntry] = [:]

    // MARK: Sports
    private(set) var games: [League: [Game]] = [:]
    private(set) var sportsLoading = false
    private(set) var sportsError: String?
    private(set) var sportsUpdated: Date?
    private(set) var favoriteTeams: Set<String> = []
    private(set) var teams: [League: [Team]] = [:]
    private(set) var teamsError: String?
    private(set) var showScores = true

    // MARK: Appearance
    private(set) var accentName = Brand.presets[0].name
    var preset: AccentPreset { Brand.presets.first { $0.name == accentName } ?? Brand.presets[0] }
    var accent: Color { preset.color }
    var highlight: Color { preset.highlight }

    init() {
        let session = XtreamClient.makeSession()
        xtream = XtreamClient(session: session)
        sportsClient = SportsClient(session: session)

        playlists = store.playlists()
        activeID = store.activeID
        favorites = store.load("favorites", as: [Channel].self) ?? []
        favoriteIDs = Set(favorites.map(\.id))
        recents = store.load("recents", as: [Channel].self) ?? []
        favoriteTeams = Set(store.load("favorite_teams", as: [String].self) ?? [])
        showScores = store.showScores
        if let name = store.accentName, Brand.presets.contains(where: { $0.name == name }) { accentName = name }
        guideGroup = favorites.isEmpty ? Self.allGroup : Self.favoritesGroup

        player.urlProvider = { [weak self] channel in self?.streamURL(for: channel) }
        player.onTuned = { [weak self] channel in self?.noteWatched(channel) }
    }

    private func streamURL(for channel: Channel) -> URL? {
        guard let p = playlists.first(where: { $0.id == channel.playlistId }) else { return nil }
        return XtreamClient.streamURL(p, channel)
    }

    // MARK: Launch

    /// Quick start: scores begin loading at once; saved channels come from disk; the provider is only
    /// asked for a fresh list when the saved one is old. Movies and Series are never touched here.
    func bootstrap() async {
        if booted { return }
        booted = true
        Task { await refreshSports() }
        await loadActive()
    }

    private func loadActive() async {
        guard let p = active else { return }
        let cache = self.cache
        let hit = await Task.detached(priority: .userInitiated) { () -> (Library, Date)? in
            guard let saved = cache.load(playlistId: p.id) else { return nil }
            return (Library.build(saved.data), saved.savedAt)
        }.value
        if let hit { apply(hit.0, savedAt: hit.1) }

        let age = Date().timeIntervalSince(liveSyncedAt ?? .distantPast)
        if channels.isEmpty || age > 12 * 3600 {
            await refreshLive()
        }
    }

    func refreshLive() async {
        guard let p = active, syncStates[.live] != .syncing else { return }
        syncStates[.live] = .syncing
        let client = xtream
        let cache = self.cache
        do {
            let lib = try await Task.detached(priority: .userInitiated) { () async throws -> Library in
                let data = try await client.fetchLive(p)
                cache.save(data, playlistId: p.id)
                return Library.build(data)
            }.value
            apply(lib, savedAt: Date())
            syncStates[.live] = .idle
        } catch {
            syncStates[.live] = .failed(friendly(error))
        }
    }

    private func apply(_ lib: Library, savedAt: Date) {
        library = lib
        liveSyncedAt = savedAt
        channelsVersion += 1
        matchCache.removeAll()
        matcher = nil
        refreshSnapshots()

        // Game-to-channel matching is prepared in the background; counts appear when it's ready.
        let version = channelsVersion
        let list = lib.channels
        Task.detached(priority: .utility) { [weak self] in
            let built = ChannelMatcher(channels: list)
            await MainActor.run {
                if let self, self.channelsVersion == version { self.matcher = built }
            }
        }
    }

    /// Keeps saved favorites and recents up to date with the fresh channel list.
    private func refreshSnapshots() {
        guard !favorites.isEmpty || !recents.isEmpty else { return }
        let byId = Dictionary(library.channels.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        favorites = favorites.map { byId[$0.id] ?? $0 }
        recents = recents.map { byId[$0.id] ?? $0 }
    }

    func refreshAccount() async {
        guard let p = active else { return }
        account = try? await xtream.authenticate(p)
    }

    func friendly(_ error: Error) -> String {
        if let u = error as? URLError {
            switch u.code {
            case .notConnectedToInternet: return "You're offline."
            case .timedOut: return "The server took too long to respond."
            case .cannotFindHost, .dnsLookupFailed: return "Can't find that server. Check the address."
            default: break
            }
        }
        return error.localizedDescription
    }

    // MARK: Playlists

    func addPlaylist(name: String, server: String, username: String, password: String) async -> String? {
        let trim = CharacterSet.whitespacesAndNewlines
        let s = server.trimmingCharacters(in: trim)
        let u = username.trimmingCharacters(in: trim)
        let p = password.trimmingCharacters(in: trim)
        let n = name.trimmingCharacters(in: trim)
        if s.isEmpty || u.isEmpty || p.isEmpty { return "Please fill in the server, username and password." }

        let playlist = Playlist(
            id: String(UUID().uuidString.prefix(8)).lowercased(),
            name: n.isEmpty ? "Playlist \(playlists.count + 1)" : n,
            server: XtreamClient.normalizeServer(s),
            username: u,
            password: p
        )
        do {
            let info = try await xtream.authenticate(playlist)
            if !info.ok { return info.message ?? "Login failed." }
            playlists.append(playlist)
            store.savePlaylists(playlists)
            account = info
            setActive(playlist.id)
            return nil
        } catch {
            return "Couldn't connect: \(friendly(error))"
        }
    }

    func setActive(_ id: String) {
        activeID = id
        store.activeID = id
        library = Library()
        liveSyncedAt = nil
        account = nil
        epg.removeAll()
        matcher = nil
        matchCache.removeAll()
        channelsVersion += 1
        guideGroup = Self.allGroup
        Task { await loadActive() }
    }

    func removePlaylist(_ id: String) {
        playlists.removeAll { $0.id == id }
        store.savePlaylists(playlists)
        cache.remove(playlistId: id)
        favorites.removeAll { $0.playlistId == id }
        recents.removeAll { $0.playlistId == id }
        favoriteIDs = Set(favorites.map(\.id))
        persistFavorites()
        store.save(recents, key: "recents")
        if activeID == id || !playlists.contains(where: { $0.id == activeID }) {
            if let next = playlists.first {
                setActive(next.id)
            } else {
                activeID = nil
                store.activeID = nil
                library = Library()
                liveSyncedAt = nil
                account = nil
                channelsVersion += 1
                player.stop()
                showPlayer = false
            }
        }
    }

    // MARK: Channels

    func channels(inGroup id: String) -> [Channel] {
        switch id {
        case Self.favoritesGroup: return favorites
        case Self.allGroup: return library.channels
        default: return library.channels.filter { $0.categoryId == id }
        }
    }

    func groupName(_ id: String) -> String {
        switch id {
        case Self.favoritesGroup: return "Favorites"
        case Self.allGroup: return "All channels"
        default: return library.categories.first { $0.id == id }?.name ?? "Channels"
        }
    }

    func search(_ query: String) -> [Channel] {
        let q = ChannelMatcher.normalize(query)
        if q.isEmpty { return [] }
        let names = library.normalizedNames
        let list = library.channels
        var starts: [Channel] = []
        var contains: [Channel] = []
        for i in 0..<min(names.count, list.count) {
            let n = names[i]
            if n.hasPrefix(q) {
                starts.append(list[i])
            } else if n.contains(q) {
                contains.append(list[i])
            }
            if starts.count >= 300 { break }
        }
        return Array((starts + contains).prefix(300))
    }

    // MARK: Favorites and recents

    func isFavorite(_ ch: Channel) -> Bool { favoriteIDs.contains(ch.id) }

    func toggleFavorite(_ ch: Channel) {
        if favoriteIDs.contains(ch.id) {
            favorites.removeAll { $0.id == ch.id }
            favoriteIDs.remove(ch.id)
        } else {
            favorites.append(ch)
            favoriteIDs.insert(ch.id)
        }
        persistFavorites()
    }

    private func persistFavorites() {
        store.save(favorites, key: "favorites")
    }

    private func noteWatched(_ ch: Channel) {
        recents.removeAll { $0.id == ch.id }
        recents.insert(ch, at: 0)
        if recents.count > 20 { recents.removeLast(recents.count - 20) }
        store.save(recents, key: "recents")
    }

    // MARK: Playback

    func play(_ channel: Channel, in queue: [Channel]) {
        if player.current?.id == channel.id {
            showPlayer = true
            return
        }
        if let i = queue.firstIndex(where: { $0.id == channel.id }) {
            player.start(queue: queue, index: i)
        } else {
            player.start(queue: [channel], index: 0)
        }
        showPlayer = true
    }

    func stopPlayback() {
        player.stop()
        showPlayer = false
    }

    // MARK: Guide

    private func isFresh(_ e: EpgEntry?) -> Bool {
        guard let e else { return false }
        let age = Date().timeIntervalSince(e.fetched)
        return age < (e.failed ? 5 * 60 : 30 * 60)
    }

    /// Loads guide data for one channel when it's missing or stale. At most 4 requests run at once.
    func ensureEpg(_ ch: Channel) async {
        guard let eid = ch.epgId, !eid.isEmpty,
              let p = playlists.first(where: { $0.id == ch.playlistId }) else { return }
        if isFresh(epg[ch.id]) { return }
        await limiter.acquire()
        if Task.isCancelled || isFresh(epg[ch.id]) {
            await limiter.release()
            return
        }
        let client = xtream
        var entry: EpgEntry?
        do {
            let programs = try await client.shortEpg(p, streamId: ch.streamId)
            entry = EpgEntry(programs: programs, fetched: Date(), failed: false)
        } catch {
            // A row scrolling off screen cancels its request; that isn't a failure.
            if !Task.isCancelled { entry = EpgEntry(programs: [], fetched: Date(), failed: true) }
        }
        await limiter.release()
        guard let entry else { return }
        if epg.count > 800 {
            for key in epg.keys.prefix(200) { epg.removeValue(forKey: key) }
        }
        epg[ch.id] = entry
    }

    /// The program on now and the one after it, if the guide has them.
    func nowNext(_ ch: Channel, at now: Date = Date()) -> (now: Program?, next: Program?) {
        guard let list = epg[ch.id]?.programs else { return (nil, nil) }
        if let i = list.firstIndex(where: { $0.isOn(at: now) }) {
            return (list[i], i + 1 < list.count ? list[i + 1] : nil)
        }
        return (nil, list.first { $0.start > now })
    }

    // MARK: Sports

    func refreshSports() async {
        if sportsLoading { return }
        sportsLoading = true
        defer { sportsLoading = false }
        let client = sportsClient
        var next = games
        var failures = 0
        await withTaskGroup(of: (League, [Game]?).self) { group in
            for league in League.allCases {
                group.addTask { (league, try? await client.games(for: league)) }
            }
            for await (league, result) in group {
                if let result { next[league] = result } else { failures += 1 }
            }
        }
        games = next
        matchCache.removeAll()
        sportsError = failures == League.allCases.count ? "Couldn't reach the scores service." : nil
        sportsUpdated = Date()
    }

    var anyLive: Bool { games.values.contains { list in list.contains { $0.state == .live } } }

    func sorted(_ list: [Game]) -> [Game] {
        list.sorted { a, b in
            func rank(_ g: Game) -> Int {
                switch g.state {
                case .live: return 0
                case .pre: return 1
                case .post: return 2
                }
            }
            if rank(a) != rank(b) { return rank(a) < rank(b) }
            return a.state == .post ? a.start > b.start : a.start < b.start
        }
    }

    func liveGames() -> [Game] { sorted(games.values.flatMap { $0 }.filter { $0.state == .live }) }

    func myGames() -> [Game] { sorted(games.values.flatMap { $0 }.filter { $0.involves(favoriteTeams) }) }

    /// The short summary on Home: live games (your teams first), or what's coming up if nothing is live.
    func homeGames() -> (title: String, games: [Game]) {
        let live = liveGames()
        if !live.isEmpty {
            let mine = live.filter { $0.involves(favoriteTeams) }
            let others = live.filter { !$0.involves(favoriteTeams) }
            return ("Live now", Array((mine + others).prefix(4)))
        }
        let upcoming = sorted(games.values.flatMap { $0 }.filter { $0.state == .pre })
        let mine = upcoming.filter { $0.involves(favoriteTeams) }
        return ("Coming up", Array((mine + upcoming.filter { !$0.involves(favoriteTeams) }).prefix(3)))
    }

    /// The freshest copy of a game (scores update while a detail screen is open).
    func currentGame(_ game: Game) -> Game {
        games[game.league]?.first { $0.gameId == game.gameId } ?? game
    }

    func channels(for game: Game) -> [Channel] {
        guard let matcher else { return [] }
        let key = game.id + "|" + game.networks.joined(separator: ",")
        if let hit = matchCache[key] { return hit }
        let found = matcher.match(game)
        matchCache[key] = found
        return found
    }

    func loadTeams(_ league: League) async {
        if teams[league] != nil { return }
        teamsError = nil
        let client = sportsClient
        do {
            teams[league] = try await client.teams(for: league)
        } catch {
            teamsError = "Couldn't load teams: \(friendly(error))"
        }
    }

    func isFavoriteTeam(_ t: Team) -> Bool { favoriteTeams.contains(t.key) }

    func toggleTeam(_ t: Team) {
        if favoriteTeams.contains(t.key) { favoriteTeams.remove(t.key) } else { favoriteTeams.insert(t.key) }
        store.save(Array(favoriteTeams), key: "favorite_teams")
    }

    func setShowScores(_ value: Bool) {
        showScores = value
        store.showScores = value
    }

    // MARK: Appearance

    func setAccent(_ p: AccentPreset) {
        accentName = p.name
        store.accentName = p.name
    }
}
