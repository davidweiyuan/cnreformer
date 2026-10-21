import XCTest
@testable import CNReformerCore
final class BlogPostTests: XCTestCase {
    func testWordPressResponseAndTitleDecoding() throws {
        let data = Data(#"{"found":1,"posts":[{"ID":12,"title":"<em>信心</em> &amp; Hope &#8212; &#x611B;","URL":"https://davidweiyuan.wordpress.com/2026/10/18/example/","date":"2026-10-18T07:00:00-08:00"}]}"#.utf8)
        let page = try JSONDecoder().decode(BlogPage.self, from: data)
        XCTAssertEqual(page.posts.first?.displayTitle, "信心 & Hope — 愛")
        XCTAssertNotNil(page.posts.first?.publishedDate)
        XCTAssertEqual(page.posts.first?.isValidLink, true)
    }
    func testSearchEncodingAndPagination() throws {
        let query = "信心 & hope?"
        let url = BlogEndpoint.posts(page: 2, search: query)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems?.first { $0.name == "search" }?.value, query)
        XCTAssertEqual(components.queryItems?.first { $0.name == "page" }?.value, "2")
    }
    func testRejectForeignAndUnsafePostLinks() {
        for address in ["http://davidweiyuan.wordpress.com/", "https://davidweiyuan.wordpress.com.evil.test/", "https://user:secret@davidweiyuan.wordpress.com/"] {
            XCTAssertFalse(BlogPost(id: 1, title: "Title", url: URL(string: address)!, date: "").isValidLink)
        }
    }
}
