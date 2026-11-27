#if DEBUG
import Foundation
import OrkaCore

/// Debug builds only (compiled out of release builds). Launch arguments that let
/// .github/workflows/screenshots.yml set the app up with a free playlist and arrange a screen:
///
///   -orkaDemoM3U <link>         playlist to add on a fresh install
///   -orkaKeepGroups A,B         groups to keep shown (the rest are hidden)
///   -orkaFavorites N            mark N channels as favorites
///   -orkaRecents N              fill "Recently watched" with N channels
///   -orkaTeams "NFL:Name|NBA:Name"
///   -orkaTab home|guide|sports|favorites|search
///   -orkaGuideGroup <name>      group shown in the Guide
///   -orkaSearch <text>          Search tab query
///   -orkaSettings 1             open Settings
///
/// When everything is loaded it writes tmp/orka_demo_ready, which the script waits for.
@MainActor
enum DemoMode {
    private static func value(_ name: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// Before the app loads anything: add the demo playlist on a fresh install.
    static func prepare(_ model: AppModel) async {
        guard model.playlists.isEmpty, let link = value("-orkaDemoM3U") else { return }
        let error = await model.addM3UPlaylist(name: "Free-TV", link: link, guideLink: "")
        print("OrkaDemo: playlist added: \(error ?? "ok")")
    }

    /// After the app has started: arrange what's on screen.
    static func arrange(_ model: AppModel) async {
        let marker = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("orka_demo_ready")
        try? FileManager.default.removeItem(at: marker)
        defer { try? "ready".write(to: marker, atomically: true, encoding: .utf8) }
        guard !model.playlists.isEmpty else { return } // the welcome screen

        var waited = 0.0
        while model.allChannelCount == 0 && waited < 90 {
            try? await Task.sleep(for: .milliseconds(250))
            waited += 0.25
        }

        // Only the groups to keep (this also decides which guide files get downloaded).
        var changedGroups = false
        if let keep = value("-orkaKeepGroups")?.split(separator: ",").map({ String($0).trimmingCharacters(in: .whitespaces) }),
           model.hiddenGroups.isEmpty {
            let hide = model.groupsWithChannels.filter { !keep.contains($0.name) }.map(\.id)
            if !hide.isEmpty {
                model.setGroups(hide, visible: false)
                changedGroups = true
            }
        }
        let visibleGroups = model.groupsWithChannels.filter { model.isGroupVisible($0.id) }
        if model.favorites.isEmpty, let n = Int(value("-orkaFavorites") ?? ""), n > 0 {
            let picks = visibleGroups.flatMap { g in model.channels(inGroup: g.id).filter { $0.logo != nil }.prefix(2) }.prefix(n)
            for ch in picks { model.toggleFavorite(ch) }
        }
        if model.recents.isEmpty, let n = Int(value("-orkaRecents") ?? ""), n > 0 {
            let picks = visibleGroups.flatMap { g in model.channels(inGroup: g.id).filter { $0.logo != nil }.dropFirst(2).prefix(2) }.prefix(n)
            model.demoSetRecents(Array(picks))
        }
        if let spec = value("-orkaTeams") {
            for part in spec.split(separator: "|") {
                let pieces = part.split(separator: ":", maxSplits: 1).map(String.init)
                guard pieces.count == 2, let league = League(rawValue: pieces[0]) else { continue }
                await model.loadTeams(league)
                if let team = model.teams[league]?.first(where: { $0.displayName == pieces[1] }), !model.isFavoriteTeam(team) {
                    model.toggleTeam(team)
                }
            }
        }

        switch value("-orkaTab") {
        case "guide": model.tab = .guide
        case "sports": model.tab = .sports
        case "favorites": model.tab = .favorites
        case "search": model.tab = .search
        case "home": model.tab = .home
        default: break
        }
        if let g = value("-orkaGuideGroup"), let c = model.groupsWithChannels.first(where: { $0.name == g }) { model.guideGroup = c.id }
        if let q = value("-orkaSearch") { model.searchQuery = q }
        if value("-orkaSettings") != nil { model.showSettings = true }

        if model.active?.isM3U == true {
            if changedGroups { model.reloadGuide() }
            var g = 0.0
            while model.guideUpdated == nil && g < 150 {
                try? await Task.sleep(for: .milliseconds(500))
                g += 0.5
            }
            print("OrkaDemo: guide has \(model.guideChannelCount) channels")
        }
        try? await Task.sleep(for: .seconds(2))
    }
}
#endif
