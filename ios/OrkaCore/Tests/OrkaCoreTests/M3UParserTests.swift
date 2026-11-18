import XCTest
@testable import OrkaCore

/// Lines taken from the real Free-TV and iptv-org playlists.
final class M3UParserTests: XCTestCase {

    private let freeTV = """
    #EXTM3U x-tvg-url="https://epgshare01.online/epgshare01/epg_ripper_AL1.xml.gz, https://epgshare01.online/epgshare01/epg_ripper_AT1.xml.gz"
    #EXTINF:-1 tvg-name="Kanali 7" tvg-logo="https://i.imgur.com/rL2v9pM.png" tvg-id="Kanali7.al" tvg-country="AL" group-title="Albania",Kanali 7 Ⓢ
    https://fe.tring.al/delta/105/out/u/1200_1.m3u8
    #EXTINF:-1 tvg-name="ABC News Albania" tvg-logo="https://i.imgur.com/aObcudw.png" tvg-id="ABCNewsAlbania.al" tvg-country="AL" group-title="Albania",ABC News Albania Ⓣ
    https://www.twitch.tv/abcnewsal
    #EXTINF:-1 tvg-name="Rai 1" tvg-logo="https://i.imgur.com/x.png" tvg-id="Rai1.it" group-title="Italy",Rai 1, HD
    https://example.it/rai1/index.m3u8
    #EXTINF:-1 tvg-name="Placeholder" group-title="Italy",Placeholder
    [NO PUBLIC STREAM]
    """

    private let iptvOrg = """
    #EXTM3U
    #EXTINF:-1 tvg-id="6WiseTv.us@SD",6 Wise Tv (720p)
    https://edge.enhdtv.com/8150/index.m3u8
    #EXTINF:-1 tvg-id="6WiseTv.us@SD",6 Wise Tv (720p)
    https://live.enhdtv.com:8081/8150/index.m3u8
    #EXTINF:-1 tvg-id="AE.us@East",A&E (1080p)
    #EXTVLCOPT:http-referrer=https://tvnow.st
    #EXTVLCOPT:http-user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) Edge/12.246
    https://cache0.wonvt.st/live/0c4r73315dt0we0fitn3j/master.m3u8
    #EXTINF:-1 tvg-id="48Hours.us@US" group-title="News;Documentary",48 Hours (1080p)
    https://dai.google.com/linear/hls/event/JUr94WL2QAiVpGNHY5n5dA/master.m3u8
    """

    func testFreeTV() {
        let r = M3UParser.parse(freeTV, playlistId: "p")
        let ch = r.data.channels
        XCTAssertEqual(ch.map(\.name), ["Kanali 7 Ⓢ", "Rai 1, HD"]) // Twitch page and placeholder skipped
        XCTAssertEqual(ch[0].logo, "https://i.imgur.com/rL2v9pM.png")
        XCTAssertEqual(ch[0].categoryId, "Albania")
        XCTAssertEqual(ch[0].epgId, "Kanali7.al")
        XCTAssertEqual(ch[0].url, "https://fe.tring.al/delta/105/out/u/1200_1.m3u8")
        XCTAssertEqual(ch[1].categoryId, "Italy")
        XCTAssertEqual(r.data.categories.map(\.name), ["Albania", "Italy"])
        XCTAssertEqual(r.guideURLs.count, 2)
        XCTAssertTrue(r.guideURLs[1].hasSuffix("epg_ripper_AT1.xml.gz"))
    }

    func testIptvOrg() {
        let r = M3UParser.parse(iptvOrg, playlistId: "p")
        let ch = r.data.channels
        XCTAssertEqual(ch.count, 4)
        // No group-title: grouped by the country in tvg-id
        XCTAssertEqual(ch[0].categoryId, "US")
        // Two copies of a channel at different addresses get different ids
        XCTAssertNotEqual(ch[0].id, ch[1].id)
        // Connection details are kept for the channel that needs them, and only that one
        XCTAssertEqual(ch[2].referrer, "https://tvnow.st")
        XCTAssertEqual(ch[2].userAgent?.hasPrefix("Mozilla/5.0"), true)
        XCTAssertNil(ch[3].referrer)
        // "News;Documentary" -> first category
        XCTAssertEqual(ch[3].categoryId, "News")
        XCTAssertEqual(r.data.categories.map(\.name), ["US", "News"])
    }

    func testIdsAreStableAcrossRefreshes() {
        let a = M3UParser.parse(iptvOrg, playlistId: "p").data.channels.map(\.id)
        let b = M3UParser.parse(iptvOrg, playlistId: "p").data.channels.map(\.id)
        XCTAssertEqual(a, b)
        XCTAssertTrue(a[0].hasPrefix("p:m"))
    }

    func testAttributesAndTitle() {
        let (attrs, title) = M3UParser.parseExtinf(#"#EXTINF:-1 tvg-chno="7" tvg-logo="http://x/a.png?w=1,h=2" group-title="A, B",My, Channel"#)
        XCTAssertEqual(attrs["tvg-chno"], "7")
        XCTAssertEqual(attrs["tvg-logo"], "http://x/a.png?w=1,h=2")
        XCTAssertEqual(attrs["group-title"], "A, B")
        XCTAssertEqual(title, "My, Channel")
        let r = M3UParser.parse("#EXTM3U\n#EXTINF:-1 tvg-chno=\"7\",Seven\nhttp://x/7.m3u8\n", playlistId: "p")
        XCTAssertEqual(r.data.channels.first?.num, 7)
    }

    func testEmptyAndBareEntries() {
        XCTAssertTrue(M3UParser.parse("", playlistId: "p").data.channels.isEmpty)
        let r = M3UParser.parse("#EXTM3U\r\n#EXTINF:-1,Plain\r\nhttp://x/plain.ts\r\n", playlistId: "p")
        XCTAssertEqual(r.data.channels.first?.name, "Plain")
        XCTAssertEqual(r.data.channels.first?.categoryId, "Other")
    }
}
