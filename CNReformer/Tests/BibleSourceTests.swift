import XCTest
@testable import CNReformerCore

final class BibleSourceTests: XCTestCase {
    func testReadersHaveSeparateLocationsAndValidHomes() {
        XCTAssertNotEqual(BibleSource.english.savedURLKey, BibleSource.chinese.savedURLKey)
        XCTAssertEqual(BibleSource.english.savedURLKey, "bible.lastURL")
        for source in BibleSource.allCases { XCTAssertTrue(source.contains(source.home)) }
        XCTAssertFalse(BibleSource.english.contains(BibleSource.chinese.home))
        XCTAssertFalse(BibleSource.chinese.contains(BibleSource.english.home))
    }
    func testLegacyChineseLinksUpgradeWithoutLosingPassage() {
        let original = URL(string: "http://bible.fhl.net/new/read.php?chineses=Gen&chap=1#v3")!
        let secure = BibleSource.chinese.secureReaderURL(original)
        XCTAssertEqual(secure?.absoluteString, "https://bible.fhl.net/new/read.php?chineses=Gen&chap=1#v3")
    }
    func testReaderDoesNotAcceptForeignHostsOrCredentials() {
        for address in ["https://bible.fhl.net.example.com/", "https://example.com/", "https://user:password@bible.fhl.net/", "file:///tmp/bible.fhl.net", "javascript:alert(1)"] {
            XCTAssertNil(BibleSource.chinese.secureReaderURL(URL(string: address)!))
        }
    }
}
