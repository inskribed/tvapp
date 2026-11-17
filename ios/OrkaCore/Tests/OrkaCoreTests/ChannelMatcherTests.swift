import XCTest
@testable import OrkaCore

final class ChannelMatcherTests: XCTestCase {

    private func ch(_ id: Int, _ name: String) -> Channel {
        Channel(playlistId: "p", streamId: String(id), num: id, name: name, logo: nil, categoryId: "", epgId: nil)
    }

    private func game(networks: [String]) -> Game {
        func team(_ id: String, _ full: String, _ nick: String) -> Team {
            Team(league: .nfl, teamId: id, displayName: full, shortName: nick, nickname: nick, abbr: nick.prefix(3).uppercased(), logo: nil)
        }
        return Game(
            gameId: "1", league: .nfl, start: Date(), state: .pre, detail: "",
            away: GameTeam(team: team("28", "Washington Commanders", "Commanders"), score: nil, home: false, record: nil),
            home: GameTeam(team: team("19", "New York Giants", "Giants"), score: nil, home: true, record: nil),
            networks: networks
        )
    }

    func testTokenizeAndNormalize() {
        XCTAssertEqual(ChannelMatcher.tokenize("US| ESPN 2 HD+"), ["us", "espn", "2", "hd", "plus"])
        XCTAssertEqual(ChannelMatcher.normalize("ESPN+"), "espnplus")
        XCTAssertEqual(ChannelMatcher.normalize("Fox, Sports"), "foxsports")
    }

    func testFindsEventChannelAndNetworkChannels() {
        let channels = [
            ch(1, "US: NBC News"),
            ch(2, "US: ESPN HD"),
            ch(3, "UK: ESPN"),
            ch(4, "NFL | 01 - Commanders vs Giants"),
            ch(5, "US: Random Movies"),
            ch(6, "US: FOX Sports 1"),
        ]
        let matcher = ChannelMatcher(channels: channels)
        let found = matcher.match(game(networks: ["ESPN", "NBC"]))
        let names = found.map(\.name)

        XCTAssertEqual(names.first, "NFL | 01 - Commanders vs Giants") // team-named channel ranks first
        XCTAssertTrue(names.contains("US: ESPN HD"))
        XCTAssertFalse(names.contains("US: NBC News"))      // "NBC" followed by "News" is excluded
        XCTAssertFalse(names.contains("US: Random Movies"))
        // US versions rank above foreign ones
        let us = names.firstIndex(of: "US: ESPN HD")!
        let uk = names.firstIndex(of: "UK: ESPN")!
        XCTAssertLessThan(us, uk)
    }

    func testAliasesForPrimeVideo() {
        let matcher = ChannelMatcher(channels: [ch(1, "NFL | 4k - TNF Prime Video"), ch(2, "Cooking Channel")])
        let found = matcher.match(game(networks: ["Prime Video"]))
        XCTAssertEqual(found.map(\.id), ["p:1"])
    }

    func testNoMatches() {
        let matcher = ChannelMatcher(channels: [ch(1, "Cartoons")])
        XCTAssertTrue(matcher.match(game(networks: [])).isEmpty)
    }
}
