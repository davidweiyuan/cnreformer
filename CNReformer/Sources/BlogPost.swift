import Foundation

struct BlogPost: Decodable, Identifiable {
    let id: Int
    let title: String
    let url: URL
    let date: String
    enum CodingKeys: String, CodingKey { case id = "ID", title, url = "URL", date }
    var publishedDate: Date? { ISO8601DateFormatter().date(from: date) }
    var isValidLink: Bool {
        url.scheme == "https" && url.host == "davidweiyuan.wordpress.com" && url.user == nil && url.password == nil
    }
    var displayTitle: String {
        var text = title.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        // WordPress titles may contain named or numeric HTML entities.
        let entities = ["&quot;": "\"", "&apos;": "'", "&lt;": "<", "&gt;": ">", "&nbsp;": " ", "&amp;": "&"]
        if let regex = try? NSRegularExpression(pattern: "&#(x[0-9a-fA-F]+|[0-9]+);") {
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
                guard let valueRange = Range(match.range(at: 1), in: text), let range = Range(match.range, in: text) else { continue }
                let value = String(text[valueRange])
                let number = value.hasPrefix("x") ? UInt32(value.dropFirst(), radix: 16) : UInt32(value)
                if let number, let scalar = UnicodeScalar(number) { text.replaceSubrange(range, with: String(scalar)) }
            }
        }
        for key in ["&quot;", "&apos;", "&lt;", "&gt;", "&nbsp;", "&amp;"] { text = text.replacingOccurrences(of: key, with: entities[key]!) }
        return text.isEmpty ? "Untitled post" : text
    }
}
struct BlogPage: Decodable {
    let found: Int
    let posts: [BlogPost]
}
enum BlogEndpoint {
    static let home = URL(string: "https://davidweiyuan.wordpress.com/")!
    static func posts(page: Int, search: String) -> URL {
        var components = URLComponents(string: "https://public-api.wordpress.com/rest/v1.1/sites/davidweiyuan.wordpress.com/posts/")!
        components.queryItems = [
            URLQueryItem(name: "number", value: "25"),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "fields", value: "ID,title,URL,date"),
            URLQueryItem(name: "order", value: "DESC"),
            URLQueryItem(name: "order_by", value: "date")
        ]
        if !search.isEmpty { components.queryItems?.append(URLQueryItem(name: "search", value: search)) }
        return components.url!
    }
}
