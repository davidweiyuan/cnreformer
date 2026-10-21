import SwiftUI
import WebKit

/// Displays the publisher's reader directly, preserving its text, attribution and controls.
struct BibleReadingView: View {
    @AppStorage("bible.source") private var source = BibleSource.english
    @StateObject private var english = BibleBrowser(source: .english)
    @StateObject private var chinese = BibleBrowser(source: .chinese)

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Bible language / 聖經語言", selection: $source) {
                    ForEach(BibleSource.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal).padding(.vertical, 8)
                BibleReaderPane(reader: source == .english ? english : chinese)
                    .id(source)
            }
            .navigationTitle("Bible / 聖經")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct BibleReaderPane: View {
    @ObservedObject var reader: BibleBrowser

    var body: some View {
            VStack(spacing: 0) {
                HStack {
                    Label(reader.source.title, systemImage: "book.closed")
                    Spacer()
                    Text(reader.source.host).foregroundStyle(.secondary)
                }
                .font(.caption).padding(.horizontal).padding(.vertical, 8)
                .background(.thinMaterial)
                if reader.isLoading { ProgressView().accessibilityLabel("Loading Bible") }
                ZStack {
                    BibleWebView(browser: reader)
                    if let error = reader.error {
                        ContentUnavailableView {
                            Label("Bible reader unavailable", systemImage: "wifi.exclamationmark")
                        } description: {
                            Text("An internet connection is required. \(error)")
                        } actions: {
                            Button("Try Again") { reader.reload() }.buttonStyle(.borderedProminent)
                            Link("Open in Browser", destination: reader.currentURL)
                        }.background(Color(.systemBackground))
                    }
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button { reader.webView.goBack() } label: { Label("Back", systemImage: "chevron.left") }.disabled(!reader.canGoBack)
                    Button { reader.webView.goForward() } label: { Label("Forward", systemImage: "chevron.right") }.disabled(!reader.canGoForward)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { reader.load(reader.source.home) } label: { Label("Bible Home", systemImage: "house") }
                    Button { reader.reload() } label: { Label("Reload", systemImage: "arrow.clockwise") }
                    Menu {
                        ShareLink(item: reader.currentURL)
                        Link("Open in Browser", destination: reader.currentURL)
                    } label: { Label("More", systemImage: "ellipsis.circle") }
                }
            }
        .onAppear { reader.startIfNeeded() }
    }
}

@MainActor
final class BibleBrowser: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    let source: BibleSource
    let webView: WKWebView
    @Published var currentURL: URL
    @Published var isLoading = false
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var error: String?
    private var observations: [NSKeyValueObservation] = []
    private var started = false
    private var requestedURL: URL

    init(source: BibleSource) {
        self.source = source
        currentURL = source.home
        requestedURL = source.home
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        // Observe SPA navigation as well as ordinary document loads.
        observations = [
            webView.observe(\.url, options: [.new]) { [weak self] _, _ in self?.scheduleUpdate() },
            webView.observe(\.isLoading, options: [.new]) { [weak self] _, _ in self?.scheduleUpdate() },
            webView.observe(\.canGoBack, options: [.new]) { [weak self] _, _ in self?.scheduleUpdate() },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] _, _ in self?.scheduleUpdate() }
        ]
    }

    nonisolated private func scheduleUpdate() {
        Task { @MainActor [weak self] in self?.updateState() }
    }

    private func updateState() {
        isLoading = webView.isLoading
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        if let url = webView.url, source.contains(url) {
            currentURL = url
            if !isLoading && error == nil {
                UserDefaults.standard.set(url.absoluteString, forKey: source.savedURLKey)
            }
        }
    }

    func startIfNeeded() {
        guard !started else { return }
        started = true
        let saved = UserDefaults.standard.string(forKey: source.savedURLKey).flatMap(URL.init(string:))
        load(saved.flatMap { source.contains($0) ? $0 : nil } ?? source.home)
    }

    func load(_ url: URL) {
        error = nil
        requestedURL = url
        webView.load(URLRequest(url: url, timeoutInterval: 30))
    }

    func reload() { load(error == nil ? currentURL : requestedURL) }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        error = nil
        if let url = webView.url, source.contains(url) { requestedURL = url }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        updateState()
        UserDefaults.standard.set(currentURL.absoluteString, forKey: source.savedURLKey)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { handle(error) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { handle(error) }
    private func handle(_ failure: Error) {
        guard (failure as NSError).code != NSURLErrorCancelled else { return }
        error = failure.localizedDescription
        isLoading = false
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        error = "The reader was interrupted. Reload to continue."
        isLoading = false
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if let secureURL = source.secureReaderURL(url), secureURL != url {
            decisionHandler(.cancel)
            load(secureURL)
        } else if source.contains(url) {
            decisionHandler(.allow)
        } else {
            // Publisher links open outside the embedded reader; never launch arbitrary schemes.
            if navigationAction.navigationType == .linkActivated, ["https", "mailto"].contains(url.scheme ?? "") {
                UIApplication.shared.open(url)
            }
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if navigationResponse.isForMainFrame, let response = navigationResponse.response as? HTTPURLResponse, response.statusCode >= 400 {
            error = "The website returned an error (\(response.statusCode)). Please try again later."
            isLoading = false
            decisionHandler(.cancel)
        } else { decisionHandler(.allow) }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url, source.contains(url) { load(url) }
        return nil
    }
}

private struct BibleWebView: UIViewRepresentable {
    let browser: BibleBrowser
    func makeUIView(context: Context) -> WKWebView { browser.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
