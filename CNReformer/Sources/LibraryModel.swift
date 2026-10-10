import Foundation

struct RemoteDocument: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var url: URL
    var date: String?
    var language: String?
    var category: String?
    var fileType: String { url.pathExtension.lowercased() }
    var eventDate: Date? { Self.parseDate(date ?? title) }
    static func parseDate(_ text: String) -> Date? {
        guard let range = text.range(of: #"\d{4}[-_.=]?\d{2}[-_.=]?\d{2}"#, options: .regularExpression) else { return nil }
        let digits = text[range].filter(\.isNumber)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        formatter.isLenient = false
        guard let result = formatter.date(from: digits), formatter.string(from: result) == digits else { return nil }
        return result
    }
}

struct WebCatalog: Codable {
    let version: Int
    let documents: [RemoteDocument]
    func validated(relativeTo base: URL) throws -> [RemoteDocument] {
        guard version == 1 else { throw LibraryError.message("This catalog version is not supported.") }
        guard Set(documents.map(\.id)).count == documents.count else { throw LibraryError.message("The catalog contains duplicate document IDs.") }
        return try documents.map { item in
            var item = item
            guard !item.id.isEmpty, !item.title.isEmpty,
                  let url = URL(string: item.url.relativeString, relativeTo: base)?.absoluteURL,
                  url.scheme == "https", url.host != nil, url.user == nil, url.password == nil else {
                throw LibraryError.message("Each catalog entry needs an ID, title, and HTTPS document URL.")
            }
            item.url = url
            guard ["pdf", "ppt", "pptx", "key"].contains(item.fileType) else {
                throw LibraryError.message("Unsupported document: \(item.title). Use PDF, Keynote, or PowerPoint.")
            }
            return item
        }
    }
}

enum LibraryError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}
