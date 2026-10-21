import Foundation

enum BibleSource: String, CaseIterable, Identifiable {
    case english, chinese
    var id: String { rawValue }
    var label: String { self == .english ? "English · LSB" : "中文 · 信望愛" }
    var title: String { self == .english ? "Legacy Standard Bible" : "信望愛聖經" }
    var host: String { self == .english ? "read.lsbible.org" : "bible.fhl.net" }
    var home: URL {
        URL(string: self == .english ? "https://read.lsbible.org/" : "https://bible.fhl.net/NNUI/_rwd/")!
    }
    // Preserve the existing English reader's saved location.
    var savedURLKey: String { self == .english ? "bible.lastURL" : "bible.chinese.lastURL" }
    func contains(_ url: URL) -> Bool {
        url.scheme == "https" && url.host?.lowercased() == host && url.user == nil && url.password == nil
    }
    /// Some older FHL links use HTTP; keep navigation on the same host over HTTPS.
    func secureReaderURL(_ url: URL) -> URL? {
        if contains(url) { return url }
        guard url.scheme == "http", url.host?.lowercased() == host, url.user == nil, url.password == nil,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.scheme = "https"
        return components.url
    }
}
