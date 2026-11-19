import XCTest
@testable import OrkaCore

final class XMLTVTests: XCTestCase {

    /// Free-TV's real list of 101 guide files.
    private let freeTVGuides = ["https://epgshare01.online/epgshare01/epg_ripper_AL1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_ALJAZEERA1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_ALL_SOURCES1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_AR1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_ASIANTELEVISION1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_AT1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_AU1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_BA1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_BE2.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_BEIN1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_BG1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_BR1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_CA1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_CH1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_CL1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_CO1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_CR1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_CY1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_CZ1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_DE1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_DELUXEMUSIC1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_DIRECTVSPORTS1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_DISTROTV1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_DK1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_DO1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_DRAFTKINGS1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_DUMMY_CHANNELS.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_EC1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_EG1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_ES1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_FANDUEL1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_FI1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_FR1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_GR1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_HK1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_HR1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_HU1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_ID1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_IE1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_IL1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_IN1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_IN4.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_IT1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_JM1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_JP1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_JP2.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_KE1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_KR1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_LT1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_LV1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_MT1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_MX1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_MY1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_NG1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_NL1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_NO1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_NZ1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_PA1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_PAC-12.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_PE1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_PH1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_PH2.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_PK1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_PL1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_PLEX1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_POWERNATION1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_PT1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_RAKUTEN1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_RAKUTEN_DE1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_RAKUTEN_EN1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_RAKUTEN_ES1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_RAKUTEN_FR1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_RAKUTEN_IT1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_RAKUTEN_NL1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_RAKUTEN_PL1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_RALLY_TV1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_RO1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_RO2.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_RS1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_SA1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_SA2.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_SE1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_SG1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_SK1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_SPORTKLUB1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_SSPORTPLUS1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_SV1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_TBNPLUS1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_THESPORTPLUS1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_TR1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_TR3.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_UK1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_US1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_US_LOCALS2.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_US_SPORTS1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_UY1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_VN1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_VOA1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_ZA1.xml.gz", "https://epgshare01.online/epgshare01/epg_ripper_viva-russia.ru.xml.gz", "https://epgshare01.online/epgshare01/locomotiontv.xml.gz"]

    private func ch(_ id: String, _ name: String, epg: String?) -> Channel {
        Channel(playlistId: "p", streamId: id, num: 1, name: name, logo: nil, categoryId: "", epgId: epg)
    }

    func testFileCountryCode() {
        XCTAssertEqual(XMLTV.fileCountryCode("https://x/epg_ripper_IT1.xml.gz"), "IT")
        XCTAssertEqual(XMLTV.fileCountryCode("https://x/epg_ripper_BE2.xml.gz"), "BE")
        XCTAssertEqual(XMLTV.fileCountryCode("https://x/epg_ripper_viva-russia.ru.xml.gz"), "RU")
        XCTAssertEqual(XMLTV.fileCountryCode("https://x/guide.us.xml"), "US")
        XCTAssertNil(XMLTV.fileCountryCode("https://x/epg_ripper_ALJAZEERA1.xml.gz"))
        XCTAssertNil(XMLTV.fileCountryCode("https://x/epg_ripper_US_LOCALS2.xml.gz"))
        XCTAssertNil(XMLTV.fileCountryCode("https://x/locomotiontv.xml.gz"))
    }

    func testChooseSourcesForFreeTV() {
        XCTAssertEqual(freeTVGuides.count, 101)
        // Someone who kept Italian, US and UK channels
        let countries = ["IT": 138, "US": 56, "UK": 64, "ZZ": 3]
        let chosen = XMLTV.chooseSources(urls: freeTVGuides, countries: countries)
        XCTAssertEqual(chosen.map { XMLTV.fileCountryCode($0) ?? "?" }, ["IT", "UK", "US"])
        XCTAssertFalse(chosen.contains { $0.contains("ALL_SOURCES") })
        // Never more than maxFiles, even with everything shown
        var all: [String: Int] = [:]
        for u in freeTVGuides { if let c = XMLTV.fileCountryCode(u) { all[c] = 1 } }
        XCTAssertEqual(XMLTV.chooseSources(urls: freeTVGuides, countries: all).count, XMLTV.maxFiles)
        // No country info: nothing rather than random files
        XCTAssertTrue(XMLTV.chooseSources(urls: freeTVGuides, countries: [:]).isEmpty)
    }

    func testShortListsAreUsedWhole() {
        let urls = ["https://a/guide.xml", " https://b/epg_ripper_ALL_SOURCES1.xml.gz", "https://a/guide.xml"]
        XCTAssertEqual(XMLTV.chooseSources(urls: urls, countries: [:]), ["https://a/guide.xml"])
    }

    func testCountryCodes() {
        let c = XMLTV.countryCodes(of: [ch("1", "a", epg: "Rai1.it"), ch("2", "b", epg: "ABC.us@East"), ch("3", "c", epg: "BBCOne.uk"), ch("4", "d", epg: nil)])
        XCTAssertEqual(c["IT"], 1)
        XCTAssertEqual(c["US"], 1)
        XCTAssertEqual(c["UK"], 1)
        XCTAssertEqual(c["GB"], 1)
    }

    func testMatcher() {
        let m = XMLTV.Matcher(channels: [
            ch("1", "Rai 1 Ⓢ", epg: "Rai1.it"),
            ch("2", "A&E (1080p)", epg: "AE.us@East"),
            ch("3", "Canale 5 HD", epg: nil),
        ])
        XCTAssertEqual(m.keys(xmlId: "Rai1.it", names: []), ["p:1"])
        XCTAssertEqual(m.keys(xmlId: "rai.1.it", names: []), ["p:1"])          // punctuation differs
        XCTAssertEqual(m.keys(xmlId: "AE.us", names: []), ["p:2"])             // without @East
        XCTAssertEqual(m.keys(xmlId: "C5.it", names: ["Canale 5"]), ["p:3"])   // by name
        XCTAssertEqual(m.keys(xmlId: "Other.it", names: ["Something"]), [])
    }

    func testParseTime() {
        XCTAssertEqual(XMLTV.parseTime("20261119120000 +0000"), Date(timeIntervalSince1970: 1_795_089_600))
        XCTAssertEqual(XMLTV.parseTime("20261119130000 +0100"), Date(timeIntervalSince1970: 1_795_089_600))
        XCTAssertEqual(XMLTV.parseTime("20261119070000 -0500"), Date(timeIntervalSince1970: 1_795_089_600))
        XCTAssertEqual(XMLTV.parseTime("20261119120000"), Date(timeIntervalSince1970: 1_795_089_600))
        XCTAssertNil(XMLTV.parseTime("soon"))
    }

    func testParseKeepsMatchedChannelsInTheWindow() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE tv SYSTEM "xmltv.dtd">
        <tv>
          <channel id="Rai.1.it"><display-name>Rai 1</display-name></channel>
          <channel id="Unknown.it"><display-name>Nobody</display-name></channel>
          <programme start="20261119100000 +0000" stop="20261119110000 +0000" channel="Rai.1.it">
            <title lang="it">Old show</title>
          </programme>
          <programme start="20261119120000 +0000" stop="20261119130000 +0000" channel="Rai.1.it">
            <title lang="it">Tg1 &amp; Meteo</title><sub-title>Ignored</sub-title>
            <desc lang="it">Notizie del giorno.</desc>
          </programme>
          <programme start="20261119130000 +0000" stop="20261119140000 +0000" channel="Unknown.it">
            <title>Not ours</title>
          </programme>
        </tv>
        """
        let m = XMLTV.Matcher(channels: [ch("1", "Rai 1", epg: "Rai1.it")])
        var guide: [String: [Program]] = [:]
        let from = Date(timeIntervalSince1970: 1_795_089_600 - 1800) // 11:30
        let matched = XMLTV.parse(Data(xml.utf8), matcher: m, from: from, to: from.addingTimeInterval(86400), into: &guide)
        XMLTV.tidy(&guide)
        XCTAssertEqual(matched, 1)
        XCTAssertEqual(guide["p:1"]?.map(\.title), ["Tg1 & Meteo"]) // 10:00-11:00 is before the window
        XCTAssertEqual(guide["p:1"]?.first?.summary, "Notizie del giorno.")
        XCTAssertNil(guide["p:2"])
    }

    func testGunzip() throws {
        let gz = try XCTUnwrap(Data(base64Encoded: "H4sIAAAAAAAC/12P3QrCMAyFX6X0VlzXCg4h7R5AXyK4opX0h7YMfXsrGzLNxSHJR04SGJ+e2GxzcTFoLruejwbqbOB6xxAsMTdpfsaA5IYOiRuYXEmEr31Ab81C2ADipw1iHTeQcrxl9N6yUjFXzVWvjlLKk1R9C7b7KG8wpg07bNnq9XdHdZWsueDDWxBLAeK7reXtizeqBT/q3wAAAA=="))
        let plain = try XCTUnwrap(XMLTV.gunzipIfNeeded(gz))
        XCTAssertTrue(String(decoding: plain, as: UTF8.self).contains("<title>Lajme</title>"))
        // Not zipped: returned as is
        XCTAssertEqual(XMLTV.gunzipIfNeeded(Data("<tv/>".utf8)), Data("<tv/>".utf8))
        var guide: [String: [Program]] = [:]
        let m = XMLTV.Matcher(channels: [ch("1", "Kanali 7", epg: "Kanali7.al")])
        XMLTV.parse(plain, matcher: m, from: .distantPast, to: .distantFuture, into: &guide)
        XCTAssertEqual(guide["p:1"]?.first?.title, "Lajme")
    }
}
