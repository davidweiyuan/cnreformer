import XCTest
@testable import CNReformerCore
final class LibraryModelTests: XCTestCase {
    func testDatesValidateCalendarAndRecognizeCornerstoneNames() {
        for name in ["2026-09-13 Sermon", "2026_09_13 Sermon", "20260913", "2026=09=13"] { XCTAssertNotNil(RemoteDocument.parseDate(name)) }
        XCTAssertNil(RemoteDocument.parseDate("2026-02-30 Sermon"))
        XCTAssertNil(RemoteDocument.parseDate("Undated sermon"))
    }
    func testCatalogResolvesRelativeURL() throws {
        let catalog = WebCatalog(version: 1, documents: [.init(id: "sermon", title: "Sermon", url: URL(string: "slides/sermon.pdf")!)])
        let result = try catalog.validated(relativeTo: URL(string: "https://example.org/library/cnreformer.json")!)
        XCTAssertEqual(result[0].url.absoluteString, "https://example.org/library/slides/sermon.pdf")
    }
    func testCatalogRejectsUnsafeURLsAndDuplicateIDs() {
        let base = URL(string: "https://example.org/cnreformer.json")!
        for path in ["http://example.org/file.pdf", "file:///etc/file.pdf", "https://user:secret@example.org/file.pdf", "https://example.org/file.exe"] {
            XCTAssertThrowsError(try WebCatalog(version: 1, documents: [.init(id: "a", title: "A", url: URL(string: path)!)]).validated(relativeTo: base))
        }
        let document = RemoteDocument(id: "a", title: "A", url: URL(string: "a.pdf")!)
        XCTAssertThrowsError(try WebCatalog(version: 1, documents: [document, document]).validated(relativeTo: base))
        XCTAssertThrowsError(try WebCatalog(version: 2, documents: []).validated(relativeTo: base))
    }
}
