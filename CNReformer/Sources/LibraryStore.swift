import SwiftUI
import CryptoKit
import PDFKit

@MainActor
final class LibraryStore: ObservableObject {
    @Published var documents: [RemoteDocument] = []
    @Published var sourceName = "No folder connected"
    @Published var isLoading = false
    @Published var error: String?
    @Published var lastRefresh: Date?
    private var folder: URL?
    private var webURL: URL?
    private let root: URL
    private var scopeActive = false

    struct Snapshot: Codable {
        var documents: [RemoteDocument]
        var sourceName: String
        var webURL: URL?
        var bookmark: Data?
        var lastRefresh: Date?
    }

    init() {
        root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("CNReformer", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: root.appendingPathComponent("library.json").path) {
                let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: root.appendingPathComponent("library.json")))
                documents = snapshot.documents; sourceName = snapshot.sourceName; webURL = snapshot.webURL; lastRefresh = snapshot.lastRefresh
                if let bookmark = snapshot.bookmark {
                    var stale = false
                    folder = try URL(resolvingBookmarkData: bookmark, options: [], bookmarkDataIsStale: &stale)
                    scopeActive = folder?.startAccessingSecurityScopedResource() ?? false
                    if stale { try persist() }
                }
            }
        } catch { self.error = "Could not restore the folder: \(error.localizedDescription). Reconnect it in Shared Folder." }
    }

    func connectWeb(_ text: String) async {
        guard !isLoading else { return }
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil else {
            error = "Enter an HTTPS URL to a cnreformer.json catalog."; return
        }
        error = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let items = try await fetchCatalog(url)
            if scopeActive { folder?.stopAccessingSecurityScopedResource() }
            folder = nil; scopeActive = false; webURL = url; sourceName = url.host ?? "Web folder"
            documents = items; lastRefresh = Date(); try persist()
        } catch { self.error = error.localizedDescription }
    }

    func connectFolder(_ url: URL) async {
        guard !isLoading else { return }
        error = nil
        isLoading = true
        defer { isLoading = false }
        let accessed = url.startAccessingSecurityScopedResource()
        do {
            let items = try await Task.detached { try Self.scan(url) }.value
            if scopeActive { folder?.stopAccessingSecurityScopedResource() }
            folder = url; scopeActive = accessed; webURL = nil; sourceName = url.lastPathComponent
            documents = items; lastRefresh = Date(); try persist()
        } catch {
            if accessed { url.stopAccessingSecurityScopedResource() }
            self.error = error.localizedDescription
        }
    }

    func refresh() async {
        if let webURL { await connectWeb(webURL.absoluteString) }
        else if let folder { await connectFolder(folder) }
    }

    private func fetchCatalog(_ url: URL) async throws -> [RemoteDocument] {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode), response.url?.scheme == "https" else { throw LibraryError.message("The web folder could not be loaded. Check the link and access permissions.") }
        guard data.count <= 5_000_000 else { throw LibraryError.message("The catalog is too large (maximum 5 MB).") }
        do { return try JSONDecoder().decode(WebCatalog.self, from: data).validated(relativeTo: response.url ?? url) }
        catch let error as LibraryError { throw error }
        catch { throw LibraryError.message("This link did not return a cnreformer.json catalog. A OneDrive sharing webpage is not a catalog; connect its folder through Files instead.") }
    }

    nonisolated static func scan(_ folder: URL) throws -> [RemoteDocument] {
        var coordinationError: NSError?
        var result: Result<[RemoteDocument], Error> = .success([])
        NSFileCoordinator().coordinate(readingItemAt: folder, options: .withoutChanges, error: &coordinationError) { location in
            result = Result {
                var scanError: Error?
                guard let enumerator = FileManager.default.enumerator(at: location, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, error in scanError = error; return false }) else { throw LibraryError.message("This provider could not list the folder.") }
                var items: [RemoteDocument] = []
                for case let file as URL in enumerator {
                    guard ["pdf", "ppt", "pptx", "key"].contains(file.pathExtension.lowercased()) else { continue }
                    let relative = String(file.path.dropFirst(location.path.count))
                    items.append(RemoteDocument(id: relative, title: file.deletingPathExtension().lastPathComponent, url: file))
                }
                if let scanError { throw scanError }
                return items.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    func cachedURL(for document: RemoteDocument) -> URL {
        let hash = SHA256.hash(data: Data(document.url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent(hash).appendingPathExtension(document.fileType)
    }

    func load(_ document: RemoteDocument, force: Bool = false) async throws -> URL {
        let destination = cachedURL(for: document)
        if !force, FileManager.default.fileExists(atPath: destination.path) { return destination }
        if document.url.isFileURL {
            try await Task.detached {
                var coordinationError: NSError?
                var readError: Error?
                NSFileCoordinator().coordinate(readingItemAt: document.url, options: .withoutChanges, error: &coordinationError) { url in
                    do { try Data(contentsOf: url).write(to: destination, options: .atomic) } catch { readError = error }
                }
                if let error = coordinationError ?? readError as NSError? { throw error }
            }.value
        } else {
            let (temporary, response) = try await URLSession.shared.download(from: document.url)
            defer { try? FileManager.default.removeItem(at: temporary) }
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode), response.url?.scheme == "https" else { throw LibraryError.message("Download failed. Check your connection and the document permissions.") }
            if document.fileType == "pdf", PDFDocument(url: temporary) == nil { throw LibraryError.message("The server returned an invalid PDF, possibly a sign-in page.") }
            let data = try Data(contentsOf: temporary, options: .mappedIfSafe)
            try data.write(to: destination, options: .atomic)
        }
        return destination
    }

    private func persist() throws {
        let bookmark = try folder?.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        let snapshot = Snapshot(documents: documents, sourceName: sourceName, webURL: webURL, bookmark: bookmark, lastRefresh: lastRefresh)
        try JSONEncoder().encode(snapshot).write(to: root.appendingPathComponent("library.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
