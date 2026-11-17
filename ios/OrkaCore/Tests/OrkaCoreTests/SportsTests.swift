import XCTest
@testable import OrkaCore

let sampleScoreboard = """
{"events":[
 {"id":"401","date":"2026-11-12T22:15Z",
  "status":{"type":{"state":"pre","shortDetail":"Thu, 11/12 5:15 PM"}},
  "competitions":[{
    "competitors":[
      {"homeAway":"home","score":"0","records":[{"summary":"5-2-1"}],
       "team":{"id":"19","displayName":"New York Giants","shortDisplayName":"Giants","name":"Giants","abbreviation":"NYG","logo":"https://x/nyg.png"}},
      {"homeAway":"away","score":"0","records":[{"summary":"2-5-1"}],
       "team":{"id":"28","displayName":"Washington Commanders","shortDisplayName":"Commanders","name":"Commanders","abbreviation":"WSH","logos":[{"href":"https://x/wsh.png"}]}}
    ],
    "broadcasts":[{"names":["Prime Video"]}],
    "geoBroadcasts":[{"media":{"shortName":"Prime Video"}},{"media":{"shortName":"NFL+"}}]
  }]},
 {"id":"402","date":"2026-11-12T22:15Z","status":{"type":{"state":"in","shortDetail":"Q3 8:12"}},
  "competitions":[{"competitors":[{"homeAway":"home","score":14,"team":{"id":"1","displayName":"A","name":"A"}}]}]}
]}
"""

final class SportsTests: XCTestCase {

    func testParseScoreboard() {
        let games = SportsClient.parseScoreboard(Data(sampleScoreboard.utf8), league: .nfl)
        XCTAssertEqual(games.count, 1) // the second event has only one team
        let g = games[0]
        XCTAssertEqual(g.id, "NFL-401")
        XCTAssertEqual(g.state, .pre)
        XCTAssertEqual(g.home.team.nickname, "Giants")
        XCTAssertEqual(g.away.team.nickname, "Commanders")
        XCTAssertEqual(g.away.team.logo, "https://x/wsh.png")
        XCTAssertEqual(g.home.record, "5-2-1")
        XCTAssertEqual(g.networks, ["Prime Video", "NFL+"])
        XCTAssertEqual(g.home.team.key, "NFL:19")
        XCTAssertTrue(g.involves(["NFL:28"]))
        XCTAssertFalse(g.involves(["NBA:28"]))
        XCTAssertGreaterThan(g.start.timeIntervalSince1970, 1_700_000_000)
    }

    func testParseDateFormats() {
        let a = SportsClient.parseDate("2026-11-12T22:15Z")
        let b = SportsClient.parseDate("2026-11-12T22:15:00Z")
        let c = SportsClient.parseDate("2026-11-12T22:15:00.000Z")
        XCTAssertEqual(a, b)
        XCTAssertEqual(b, c)
        XCTAssertGreaterThan(a.timeIntervalSince1970, 0)
        XCTAssertEqual(SportsClient.parseDate(nil).timeIntervalSince1970, 0)
        XCTAssertEqual(SportsClient.parseDate("nonsense").timeIntervalSince1970, 0)
    }

    func testParseTeams() {
        let json = #"{"sports":[{"leagues":[{"teams":[{"team":{"id":"2","displayName":"Buffalo Bills","name":"Bills"}},{"team":{"id":"1","displayName":"Atlanta Falcons","name":"Falcons"}}]}]}]}"#
        let teams = SportsClient.parseTeams(Data(json.utf8), league: .nfl)
        XCTAssertEqual(teams.map(\.displayName), ["Atlanta Falcons", "Buffalo Bills"])
        XCTAssertEqual(teams.first?.abbr, "ATL") // made from the name when ESPN sends none
    }
}
