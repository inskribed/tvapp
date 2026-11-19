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
    var categories: [ChannelCategory] = []
    var channels: [Channel] = []
    var normalizedNames: [String] = []
    var words: [[String]] = []
    var counts: [String: Int] = [:]
    var guideURLs: [String] = []

    static func build(_ data: LiveData) -> Library {
        var counts: [String: Int] = [:]
        for ch in data.channels { counts[ch.categoryId, default: 0] += 1 }
        return Library(
            categories: data.categories,
            channels: data.channels,
            normalizedNames: data.channels.map { ChannelMatcher.normalize($0.name) },
            words: data.channels.map { ChannelSearch.words($0.name) },
            counts: counts,
            guideURLs: data.guideURLs ?? []
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
    @ObservationIgnored private var sportsLoop: Task<Void, Never>?
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
    /// Group (category) ids hidden in Settings > Channel groups, per playlist.
    private(set) var hiddenGroups: Set<String> = []
    /// Channels from groups that aren't hidden. Guide, Search and game matching all use this.
    private(set) var visibleChannels: [Channel] = []
    @ObservationIgnored private var visibleIndex: [Int] = []
    private(set) var channelsVersion = 0
    private(set) var liveSyncedAt: Date?
    private(set) var syncStates: [ContentKind: SyncState] = [.live: .idle, .movies: .idle, .series: .idle]
    private(set) var matcher: ChannelMatcher?
    var channels: [Channel] { visibleChannels }
    var allChannelCount: Int { library.channels.count }
    var categories: [ChannelCategory] { library.categories }

    // MARK: Favorites and recents
    private(set) var favorites: [Channel] = []
    private(set) var favoriteIDs: Set<String> = []
    private(set) var recents: [Channel] = []

    // MARK: Guide
    private(set) var epg: [String: EpgEntry] = [:]
    /// M3U guide (XMLTV) status, shown in Settings > Library.
    private(set) var guideState: SyncState = .idle
    private(set) var guideUpdated: Date?
    private(set) var guideChannelCount = 0
    private(set) var guideHasSource = false
    @ObservationIgnored private let guideCache = GuideCacheStore()
    @ObservationIgnored private var guideTask: Task<Void, Never>?
    @ObservationIgnored private var guideLoadedFor: String?
    @ObservationIgnored private var refreshedForGuideLinks: String?

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
        if let id = active?.id {
            hiddenGroups = Set(store.load("hidden_groups_\(id)", as: [String].self) ?? [])
        }

        player.urlProvider = { [weak self] channel in self?.streamURL(for: channel) }
        player.headersProvider = { [weak self] channel in self?.streamHeaders(for: channel) ?? [:] }
        player.onTuned = { [weak self] channel in self?.noteWatched(channel) }
        player.onPictureInPictureStarted = { [weak self] in self?.showPlayer = false }
        player.onRestoreFromPictureInPicture = { [weak self] in self?.showPlayer = true }
    }

    private func streamURL(for channel: Channel) -> URL? {
        // M3U channels carry their own address.
        if let s = channel.url { return URL(string: s) }
        guard let p = playlists.first(where: { $0.id == channel.playlistId }) else { return nil }
        return XtreamClient.streamURL(p, channel)
    }

    /// Extra connection details some M3U channels need (iptv-org lists name them per channel).
    private func streamHeaders(for channel: Channel) -> [String: String] {
        var h: [String: String] = [:]
        if let ua = channel.userAgent, !ua.isEmpty { h["User-Agent"] = ua }
        if let ref = channel.referrer, !ref.isEmpty { h["Referer"] = ref }
        return h
    }

    // MARK: Launch

    /// Quick start: scores begin loading at once; saved channels come from disk; the provider is only
    /// asked for a fresh list when the saved one is old. Movies and Series are never touched here.
    func bootstrap() async {
        if booted { return }
        booted = true
        startSportsUpdates()
        await loadActive()
    }

    /// Back in the foreground: scores resume, and a channel list older than 12 hours refreshes quietly.
    func appBecameActive() {
        guard booted else { return }
        startSportsUpdates()
        if active != nil, Date().timeIntervalSince(liveSyncedAt ?? .distantPast) > 12 * 3600 {
            Task { await refreshLive() }
        } else if active?.isM3U == true, let updated = guideUpdated, Date().timeIntervalSince(updated) > 12 * 3600 {
            loadGuide(force: true)
        }
    }

    func appWentToBackground() {
        sportsLoop?.cancel()
        sportsLoop = nil
    }

    /// Keeps scores fresh everywhere (Home included): every 30 seconds while a game is live,
    /// every 2 minutes otherwise. Paused while the app is in the background.
    private func startSportsUpdates() {
        guard sportsLoop == nil else { return }
        sportsLoop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refreshSports()
                let wait: Double = self.anyLive ? 30 : 120
                try? await Task.sleep(for: .seconds(wait))
            }
        }
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
                let data: LiveData
                if p.isM3U {
                    data = try await client.fetchM3U(p).data
                } else {
                    data = try await client.fetchLive(p)
                }
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
        refreshSnapshots()
        rebuildVisible()
        if active?.isM3U == true { loadGuide() }
    }

    /// Recomputes the visible channels after a sync or a change to hidden groups.
    private func rebuildVisible() {
        let hidden = hiddenGroups
        var idx: [Int] = []
        idx.reserveCapacity(library.channels.count)
        for (i, ch) in library.channels.enumerated() where !hidden.contains(ch.categoryId) { idx.append(i) }
        visibleIndex = idx
        visibleChannels = idx.map { library.channels[$0] }
        if guideGroup != Self.allGroup && guideGroup != Self.favoritesGroup && hidden.contains(guideGroup) {
            guideGroup = Self.allGroup
        }
        channelsVersion += 1
        matchCache.removeAll()
        matcher = nil

        // Game-to-channel matching is prepared in the background; counts appear when it's ready.
        let version = channelsVersion
        let list = visibleChannels
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
        // Account details (status, expiry, connections) only exist for Xtream logins.
        guard let p = active, !p.isM3U else {
            account = nil
            return
        }
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

    /// Saves changes to an existing playlist after checking the new details work. The playlist keeps
    /// its id, so favorites, hidden groups and recents stay attached to it.
    func updatePlaylist(_ old: Playlist, name: String, server: String, username: String, password: String,
                        link: String, guideLink: String) async -> String? {
        let trim = CharacterSet.whitespacesAndNewlines
        let n = name.trimmingCharacters(in: trim)
        var updated = old
        updated.name = n.isEmpty ? old.name : n
        do {
            if old.isM3U {
                let l = link.trimmingCharacters(in: trim)
                if l.isEmpty { return "Please enter the playlist link." }
                let url = XtreamClient.normalizeLink(l)
                updated.server = url
                updated.m3uURL = url
                let g = guideLink.trimmingCharacters(in: trim)
                updated.epgURL = g.isEmpty ? nil : XtreamClient.normalizeLink(g)
                let result = try await xtream.fetchM3U(updated)
                if result.data.channels.isEmpty { return "That playlist has no channels Orka can play." }
                cache.save(result.data, playlistId: old.id)
                guideCache.remove(playlistId: old.id) // links may have changed; rebuild the guide
            } else {
                let s = server.trimmingCharacters(in: trim)
                let u = username.trimmingCharacters(in: trim)
                let p = password.trimmingCharacters(in: trim)
                if s.isEmpty || u.isEmpty || p.isEmpty { return "Please fill in the server, username and password." }
                updated.server = XtreamClient.normalizeServer(s)
                updated.username = u
                updated.password = p
                let info = try await xtream.authenticate(updated)
                if !info.ok { return info.message ?? "Login failed." }
                // A different server or account: the saved channel list belongs to the old one.
                if updated.server != old.server || updated.username != old.username {
                    cache.remove(playlistId: old.id)
                }
            }
        } catch {
            return (old.isM3U ? "Couldn't load that playlist: " : "Couldn't connect: ") + friendly(error)
        }
        if let i = playlists.firstIndex(where: { $0.id == old.id }) { playlists[i] = updated }
        store.savePlaylists(playlists)
        if active?.id == old.id { setActive(old.id) }
        return nil
    }

    /// Adds an M3U playlist (Free-TV, iptv-org, HDHomeRun, Plex...). It's downloaded once to check it.
    func addM3UPlaylist(name: String, link: String, guideLink: String) async -> String? {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Please enter the playlist link." }
        let url = XtreamClient.normalizeLink(trimmed)
        let guide = guideLink.trimmingCharacters(in: .whitespacesAndNewlines)
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = String(UUID().uuidString.prefix(8)).lowercased()
        let playlist = Playlist(
            id: id,
            name: n.isEmpty ? (URL(string: url)?.host ?? "Playlist \(playlists.count + 1)") : n,
            server: url,
            username: "",
            password: "",
            m3uURL: url,
            epgURL: guide.isEmpty ? nil : XtreamClient.normalizeLink(guide)
        )
        do {
            let result = try await xtream.fetchM3U(playlist)
            if result.data.channels.isEmpty { return "That playlist has no channels Orka can play." }
            let saved = playlist
            cache.save(result.data, playlistId: saved.id)
            playlists.append(saved)
            store.savePlaylists(playlists)
            account = nil
            setActive(saved.id)
            return nil
        } catch {
            return "Couldn't load that playlist: \(friendly(error))"
        }
    }

    func setActive(_ id: String) {
        activeID = id
        store.activeID = id
        library = Library()
        visibleChannels = []
        visibleIndex = []
        hiddenGroups = Set(store.load("hidden_groups_\(id)", as: [String].self) ?? [])
        liveSyncedAt = nil
        account = nil
        epg.removeAll()
        guideTask?.cancel()
        guideTask = nil
        guideLoadedFor = nil
        guideState = .idle
        guideUpdated = nil
        guideChannelCount = 0
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
        guideCache.remove(playlistId: id)
        UserDefaults.standard.removeObject(forKey: "hidden_groups_\(id)")
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
                visibleChannels = []
                visibleIndex = []
                hiddenGroups = []
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
        case Self.allGroup: return visibleChannels
        default: return visibleChannels.filter { $0.categoryId == id }
        }
    }

    func groupName(_ id: String) -> String {
        switch id {
        case Self.favoritesGroup: return "Favorites"
        case Self.allGroup: return "All channels"
        default: return library.categories.first { $0.id == id }?.name ?? "Channels"
        }
    }

    /// Whole-word search over visible channels ("|us|" finds |US| channels, not "Museum").
    /// Runs off the main thread; the word lists were prepared when the channels loaded.
    func search(_ query: String) async -> [Channel] {
        let idx = visibleIndex
        let lib = library
        return await Task.detached(priority: .userInitiated) { () -> [Channel] in
            let words = idx.map { lib.words[$0] }
            let squashed = idx.map { lib.normalizedNames[$0] }
            return ChannelSearch.search(query: query, words: words, squashed: squashed).map { lib.channels[idx[$0]] }
        }.value
    }

    // MARK: Channel groups

    /// Groups that have channels, in the provider's order.
    var groupsWithChannels: [ChannelCategory] {
        library.categories.filter { (library.counts[$0.id] ?? 0) > 0 }
    }

    func isGroupVisible(_ id: String) -> Bool { !hiddenGroups.contains(id) }

    func setGroups(_ ids: [String], visible: Bool) {
        if visible { hiddenGroups.subtract(ids) } else { hiddenGroups.formUnion(ids) }
        if let id = active?.id { store.save(Array(hiddenGroups), key: "hidden_groups_\(id)") }
        rebuildVisible()
    }

    /// Region tags found in group names ("US", "FR", ...) with their group ids, biggest first.
    func groupPrefixes() -> [(tag: String, ids: [String])] {
        var map: [String: [String]] = [:]
        for c in groupsWithChannels {
            if let tag = ChannelSearch.groupPrefix(c.name) { map[tag, default: []].append(c.id) }
        }
        return map.map { ($0.key, $0.value) }.sorted { a, b in
            a.ids.count != b.ids.count ? a.ids.count > b.ids.count : a.tag < b.tag
        }
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
        if let p = playlists.first(where: { $0.id == ch.playlistId }), p.isM3U {
            // M3U guides come from XMLTV files, loaded for the whole playlist at once.
            if guideLoadedFor != p.id && guideTask == nil { loadGuide() }
            return
        }
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

    // MARK: M3U guide (XMLTV)

    /// Which guide files to use: a link you typed wins; otherwise the playlist's own list, cut down to
    /// the countries of the channels you've kept shown (Free-TV lists 100+ files).
    private func guideSources(for p: Playlist) -> [String] {
        let header = library.guideURLs
        if let typed = p.epgURL, !typed.isEmpty, !header.contains(typed) {
            return typed.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.hasPrefix("http") }
        }
        let urls = header.isEmpty ? [p.epgURL].compactMap { $0 } : header
        return XMLTV.chooseSources(urls: urls, countries: XMLTV.countryCodes(of: visibleChannels))
    }

    /// Shows the saved guide right away, and downloads a fresh one when it's missing, older than
    /// 12 hours, or `force` is set. Runs in the background; never holds up the app.
    func loadGuide(force: Bool = false) {
        guard let p = active, p.isM3U, guideTask == nil else { return }
        // Playlists saved before guide support didn't keep their guide links: download the playlist
        // once more to get them (this calls loadGuide again when done).
        if library.guideURLs.isEmpty, refreshedForGuideLinks != p.id, !library.channels.isEmpty {
            refreshedForGuideLinks = p.id
            Task { await refreshLive() }
            return
        }
        let sources = guideSources(for: p)
        guideHasSource = !sources.isEmpty
        let channels = library.channels
        let store = guideCache
        let session = xtream.session
        guideTask = Task { [weak self] in
            // 1. The saved guide, if any (instant).
            let saved = await Task.detached(priority: .userInitiated) { store.load(playlistId: p.id) }.value
            if let saved, let self, self.active?.id == p.id {
                self.applyGuide(saved.programs, savedAt: saved.savedAt, for: p.id)
            }
            let stale = saved.map { Date().timeIntervalSince($0.savedAt) > 12 * 3600 } ?? true
            guard force || stale else {
                self?.guideTask = nil
                return
            }
            guard !sources.isEmpty else {
                if let self, self.active?.id == p.id {
                    self.applyGuide([:], savedAt: nil, for: p.id)
                    self.guideTask = nil
                }
                return
            }
            // 2. Download and read the guide files, one at a time, off the main thread.
            self?.guideState = .syncing
            let result = await Task.detached(priority: .utility) { () -> (programs: [String: [Program]], failures: Int) in
                let matcher = XMLTV.Matcher(channels: channels)
                let now = Date()
                var guide: [String: [Program]] = [:]
                var failures = 0
                for s in sources {
                    if Task.isCancelled { break }
                    guard let url = URL(string: s),
                          let fetched = try? await session.data(from: url),
                          (fetched.1 as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
                          let xml = XMLTV.gunzipIfNeeded(fetched.0) else {
                        failures += 1
                        continue
                    }
                    XMLTV.parse(xml, matcher: matcher, from: now.addingTimeInterval(-XMLTV.lookBack),
                                to: now.addingTimeInterval(XMLTV.lookAhead), into: &guide)
                }
                XMLTV.tidy(&guide)
                return (guide, failures)
            }.value
            guard let self, !Task.isCancelled, self.active?.id == p.id else { return }
            if result.failures == sources.count {
                self.guideState = .failed("Couldn't download the guide.")
            } else {
                store.save(result.programs, playlistId: p.id)
                self.applyGuide(result.programs, savedAt: Date(), for: p.id)
                self.guideState = .idle
            }
            self.guideTask = nil
        }
    }

    /// Puts the guide on every channel of the playlist (channels it doesn't cover show "No guide info").
    private func applyGuide(_ programs: [String: [Program]], savedAt: Date?, for playlistId: String) {
        let now = Date()
        var next = epg
        for ch in library.channels where ch.playlistId == playlistId {
            next[ch.id] = EpgEntry(programs: programs[ch.id] ?? [], fetched: now, failed: false)
        }
        epg = next
        guideLoadedFor = playlistId
        guideUpdated = savedAt
        guideChannelCount = programs.values.filter { !$0.isEmpty }.count
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
