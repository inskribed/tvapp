import XCTest
@testable import OrkaCore

final class XtreamTests: XCTestCase {

    func testNormalizeServer() {
        XCTAssertEqual(XtreamClient.normalizeServer("example.com:8080"), "http://example.com:8080")
        XCTAssertEqual(XtreamClient.normalizeServer(" https://example.com/ "), "https://example.com")
        XCTAssertEqual(XtreamClient.normalizeServer("http://example.com:80/player_api.php?username=a"), "http://example.com:80")
        XCTAssertEqual(XtreamClient.normalizeServer("http://example.com/get.php?x=1"), "http://example.com")
    }

    func testParseCategoriesWithNumbersAndText() throws {
        let json = #"[{"category_id":"12","category_name":"US | Sports"},{"category_id":7,"category_name":"News"},{"category_name":"no id"},5]"#
        let cats = try XtreamClient.parseCategories(Data(json.utf8))
        XCTAssertEqual(cats.map(\.id), ["12", "7"])
        XCTAssertEqual(cats.first?.name, "US | Sports")
    }

    func testParseStreamsSkipsBadAndDuplicates() throws {
        let json = """
        [
          {"num":1,"name":"ESPN HD","stream_id":101,"stream_icon":"http://x/e.png","category_id":"12","epg_channel_id":"ESPN.us"},
          {"num":"2","name":"Dup","stream_id":"101"},
          {"name":"No logo","stream_id":"102","stream_icon":"not-a-url","category_id":3,"epg_channel_id":null},
          "garbage",
          {"name":"No id"}
        ]
        """
        let chans = try XtreamClient.parseStreams(Data(json.utf8), playlistId: "p1")
        XCTAssertEqual(chans.count, 2)
        XCTAssertEqual(chans[0].id, "p1:101")
        XCTAssertEqual(chans[0].num, 1)
        XCTAssertEqual(chans[0].logo, "http://x/e.png")
        XCTAssertEqual(chans[0].epgId, "ESPN.us")
        XCTAssertNil(chans[1].logo)
        XCTAssertNil(chans[1].epgId)
        XCTAssertEqual(chans[1].categoryId, "3")
    }

    func testStreamURL() {
        let p = Playlist(id: "p", name: "n", server: "http://host:8080", username: "us er", password: "p/w")
        let ch = Channel(playlistId: "p", streamId: "55", num: 1, name: "x", logo: nil, categoryId: "", epgId: nil)
        XCTAssertEqual(XtreamClient.streamURL(p, ch)?.absoluteString, "http://host:8080/live/us%20er/p%2Fw/55.m3u8")
        XCTAssertTrue(XtreamClient.streamURL(p, ch, format: .ts)?.absoluteString.hasSuffix("/55.ts") == true)
    }

    func testAccount() throws {
        let ok = #"{"user_info":{"auth":1,"status":"Active","exp_date":"1800000000","max_connections":"2","active_cons":"0"}}"#
        let info = try XtreamClient.parseAccount(Data(ok.utf8))
        XCTAssertTrue(info.ok)
        XCTAssertEqual(info.status, "Active")
        XCTAssertEqual(info.maxConnections, 2)
        XCTAssertEqual(info.expiresAt, Date(timeIntervalSince1970: 1_800_000_000))

        let bad = #"{"user_info":{"auth":0,"message":"Expired"}}"#
        let failed = try XtreamClient.parseAccount(Data(bad.utf8))
        XCTAssertFalse(failed.ok)
        XCTAssertEqual(failed.message, "Expired")

        XCTAssertThrowsError(try XtreamClient.parseAccount(Data("<html>".utf8)))
    }

    func testParseEpgDecodesBase64AndDropsOverlaps() {
        func b64(_ s: String) -> String { Data(s.utf8).base64EncodedString() }
        let json = """
        {"epg_listings":[
          {"title":"\(b64("Evening News"))","description":"\(b64("Top stories"))","start_timestamp":"1000","stop_timestamp":"2000"},
          {"title":"\(b64("Overlap"))","start_timestamp":"1500","stop_timestamp":"2500"},
          {"title":"\(b64("Late Show"))","start_timestamp":"2000","stop_timestamp":"3000"},
          {"title":"Plain Title","start_timestamp":3000,"stop_timestamp":4000},
          {"title":"Backwards","start_timestamp":"9000","stop_timestamp":"8000"}
        ]}
        """
        let progs = XtreamClient.parseEpg(Data(json.utf8))
        XCTAssertEqual(progs.map(\.title), ["Evening News", "Late Show", "Plain Title"])
        XCTAssertEqual(progs[0].summary, "Top stories")
        XCTAssertEqual(progs[0].start, Date(timeIntervalSince1970: 1000))
        XCTAssertTrue(progs[0].isOn(at: Date(timeIntervalSince1970: 1500)))
        XCTAssertEqual(progs[0].progress(at: Date(timeIntervalSince1970: 1500)), 0.5, accuracy: 0.001)
    }

    func testParseEpgEmptyArrayAnswer() {
        XCTAssertTrue(XtreamClient.parseEpg(Data("[]".utf8)).isEmpty)
        XCTAssertTrue(XtreamClient.parseEpg(Data(#"{"epg_listings":[]}"#.utf8)).isEmpty)
    }

    func testCacheRoundTrip() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("orka-test-\(UUID().uuidString)")
        let store = LiveCacheStore(directory: dir)
        let data = LiveData(
            categories: [ChannelCategory(id: "1", name: "Sports")],
            channels: [Channel(playlistId: "p", streamId: "9", num: 3, name: "ESPN", logo: nil, categoryId: "1", epgId: nil)]
        )
        XCTAssertNil(store.load(playlistId: "p"))
        store.save(data, playlistId: "p")
        let loaded = store.load(playlistId: "p")
        XCTAssertEqual(loaded?.data.channels.first?.name, "ESPN")
        XCTAssertNotNil(loaded?.savedAt)
        store.remove(playlistId: "p")
        XCTAssertNil(store.load(playlistId: "p"))
    }
}
