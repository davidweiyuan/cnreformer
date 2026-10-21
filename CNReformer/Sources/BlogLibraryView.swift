import SwiftUI
import SafariServices

@MainActor
final class BlogLibrary: ObservableObject {
    @Published var posts: [BlogPost] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var hasMore = false
    private var page = 0
    private var search = ""
    private var requestID = UUID()

    func refresh(search: String) async {
        let normalized = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if self.search != normalized { posts = []; page = 0; hasMore = false }
        self.search = normalized
        await fetch(page: 1)
    }
    func loadMore() async {
        guard !isLoading, hasMore else { return }
        await fetch(page: page + 1)
    }
    private func fetch(page nextPage: Int) async {
        let id = UUID()
        requestID = id
        isLoading = true
        error = nil
        defer { if requestID == id { isLoading = false } }
        do {
            let (data, response) = try await URLSession.shared.data(from: BlogEndpoint.posts(page: nextPage, search: search))
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
                throw LibraryError.message("WordPress is unavailable. Please try again.")
            }
            let result = try JSONDecoder().decode(BlogPage.self, from: data)
            try Task.checkCancellation()
            guard requestID == id else { return }
            let valid = result.posts.filter(\.isValidLink)
            if nextPage == 1 { posts = [] }
            var seen = Set(posts.map(\.id))
            posts.append(contentsOf: valid.filter { seen.insert($0.id).inserted })
            page = nextPage
            hasMore = !result.posts.isEmpty && nextPage * 25 < result.found
        } catch {
            guard requestID == id, !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
    }
}

struct BlogLibraryView: View {
    @StateObject private var library = BlogLibrary()
    @State private var query = ""
    @State private var submittedQuery = ""
    @State private var selectedPost: BlogPost?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("朝聖之旅").font(.title2.bold())
                        Text("一個天路客的腳蹤").foregroundStyle(.secondary)
                        Link("davidweiyuan.wordpress.com", destination: BlogEndpoint.home).font(.caption)
                    }.padding(.vertical, 8)
                }
                if let error = library.error {
                    Section {
                        Label(error, systemImage: "wifi.exclamationmark").foregroundStyle(.secondary)
                        Button("Try Again") { Task { await library.refresh(search: submittedQuery) } }
                    }
                }
                Section(submittedQuery.isEmpty ? "Latest posts / 最新文章" : "Search results / 搜尋結果") {
                    ForEach(library.posts) { post in
                        Button { selectedPost = post } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(post.displayTitle).font(.headline).foregroundStyle(.primary).multilineTextAlignment(.leading)
                                    if let date = post.publishedDate {
                                        Text(date, style: .date).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 7)
                        }.accessibilityHint("Open blog post")
                    }
                    if library.isLoading {
                        HStack { Spacer(); ProgressView("Loading posts…"); Spacer() }
                    } else if library.posts.isEmpty && library.error == nil {
                        ContentUnavailableView("No posts found", systemImage: "doc.text.magnifyingglass", description: Text("Try another search or refresh the blog."))
                    } else if library.hasMore {
                        Button("Load older posts / 較舊的文章") { Task { await library.loadMore() } }
                    }
                }
            }
            .navigationTitle("Library")
            .searchable(text: $query, prompt: "Search blog posts / 搜尋文章")
            .onSubmit(of: .search) { submittedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines) }
            .onChange(of: query) { _, value in if value.isEmpty { submittedQuery = "" } }
            .task(id: submittedQuery) { await library.refresh(search: submittedQuery) }
            .refreshable { await library.refresh(search: submittedQuery) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await library.refresh(search: submittedQuery) } } label: { Label("Refresh posts", systemImage: "arrow.clockwise") }.disabled(library.isLoading)
                }
            }
            .sheet(item: $selectedPost) { BlogPostBrowser(url: $0.url).ignoresSafeArea() }
        }
    }
}

private struct BlogPostBrowser: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = true
        return SFSafariViewController(url: url, configuration: configuration)
    }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
