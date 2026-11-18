import XCTest
@testable import OrkaCore

final class ChannelSearchTests: XCTestCase {

    private let names = [
        "|FR| Museum UHD",
        "|FR| BFM BUSINESS UHD",
        "|FR| F3 LIMOUSIN UHD",
        "|US| CBS 2 (KTVT)",
        "|US| ESPN 2 HD",
        "US: NFL Network",
        "|USA| Fox News",
        "|FR| Canal+ Cinema",
        "ESPNews",
    ]

    private func run(_ q: String) -> [String] {
        let words = names.map { ChannelSearch.words($0) }
        let squashed = names.map { ChannelMatcher.normalize($0) }
        return ChannelSearch.search(query: q, words: words, squashed: squashed).map { names[$0] }
    }

    func testCountryTagDoesNotMatchInsideWords() {
        let r = run("|us|")
        XCTAssertFalse(r.contains("|FR| Museum UHD"))
        XCTAssertFalse(r.contains("|FR| BFM BUSINESS UHD"))
        XCTAssertFalse(r.contains("|FR| F3 LIMOUSIN UHD"))
        XCTAssertTrue(r.contains("|US| CBS 2 (KTVT)"))
        XCTAssertTrue(r.contains("US: NFL Network"))
        XCTAssertTrue(r.contains("|USA| Fox News")) // "us" starts "usa"
    }

    func testMultipleWordsAndRanking() {
        XCTAssertEqual(run("cbs 2"), ["|US| CBS 2 (KTVT)"])
        XCTAssertEqual(run("us espn").first, "|US| ESPN 2 HD")
        XCTAssertEqual(run("canal+"), ["|FR| Canal+ Cinema"])
        XCTAssertEqual(run("net"), ["US: NFL Network"])
    }

    func testFallsBackToInsideWords() {
        XCTAssertEqual(run("espnew"), ["ESPNews"])  // prefix of a word
        XCTAssertTrue(run("news").contains("|USA| Fox News"))
        XCTAssertTrue(run("zz").isEmpty)
    }

    func testGroupPrefix() {
        XCTAssertEqual(ChannelSearch.groupPrefix("|US| SPORTS"), "US")
        XCTAssertEqual(ChannelSearch.groupPrefix("FR| CINEMA"), "FR")
        XCTAssertEqual(ChannelSearch.groupPrefix("UK: News"), "UK")
        XCTAssertEqual(ChannelSearch.groupPrefix("CA - Sports"), "CA")
        XCTAssertEqual(ChannelSearch.groupPrefix("[DE] Kids"), "DE")
        XCTAssertEqual(ChannelSearch.groupPrefix("NFL | Game Pass"), "NFL")
        XCTAssertNil(ChannelSearch.groupPrefix("Sports"))
        XCTAssertNil(ChannelSearch.groupPrefix("PPV Events"))
        XCTAssertNil(ChannelSearch.groupPrefix("X| one letter"))
    }
}
