import SwiftUI
import PDFKit
import QuickLook
import UniformTypeIdentifiers

@main
struct CNReformerApp: App {
    @StateObject private var store = LibraryStore()
    var body: some Scene { WindowGroup { RootView().environmentObject(store).tint(Color(red: 0.12, green: 0.30, blue: 0.48)) } }
}

private enum AppView: String, CaseIterable { case calendar = "Calendar", documents = "Documents", library = "Library"
    var icon: String { switch self { case .calendar: "calendar"; case .documents: "list.bullet"; case .library: "books.vertical" } }
}

struct RootView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var tab = AppView.calendar
    @State private var selected: RemoteDocument?
    @State private var search = ""
    @State private var language = "All languages"
    @State private var showConnection = false
    @State private var month = Date()
    private var filtered: [RemoteDocument] {
        store.documents.filter { item in
            (language == "All languages" || item.language == language) && (search.isEmpty || [item.title, item.category ?? "", item.language ?? ""].joined(separator: " ").localizedCaseInsensitiveContains(search))
        }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    var body: some View {
        TabView(selection: $tab) {
            ForEach(AppView.allCases, id: \.self) { page in
                NavigationSplitView {
                    VStack(spacing: 0) {
                        sourceBanner
                        if store.documents.isEmpty {
                            ContentUnavailableView {
                                Label("Your shared library", systemImage: "folder.badge.person.crop")
                            } description: {
                                Text("Connect a shared folder to browse teaching documents and presentations on iPhone and iPad.")
                            } actions: { Button("Connect Shared Folder") { showConnection = true }.buttonStyle(.borderedProminent) }
                        } else if page == .calendar { calendar }
                        else if filtered.isEmpty { ContentUnavailableView.search(text: search) }
                        else if page == .documents { documentList }
                        else { libraryGrid }
                    }
                    .navigationTitle(page == .calendar ? "Preaching Calendar" : page.rawValue)
                    .searchable(text: $search, prompt: "Title, category, or language")
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Menu {
                                Picker("Language", selection: $language) {
                                    Text("All languages").tag("All languages")
                                    ForEach(Array(Set(store.documents.compactMap(\.language))).sorted(), id: \.self) { Text($0).tag($0) }
                                }
                            } label: { Label("Filter", systemImage: "line.3.horizontal.decrease") }
                        }
                        ToolbarItemGroup(placement: .topBarTrailing) {
                            Button { Task { await store.refresh() } } label: { Label("Refresh Folder", systemImage: "arrow.clockwise") }.disabled(store.isLoading || store.documents.isEmpty)
                            Button { showConnection = true } label: { Label("Shared Folder", systemImage: "folder.badge.gearshape") }
                        }
                    }
                    .navigationDestination(item: $selected) { document in ReaderView(document: document) }
                } detail: {
                    ContentUnavailableView("cnreformer", systemImage: "book.closed", description: Text("Choose a document to begin reading."))
                }
                .tabItem { Label(page.rawValue, systemImage: page.icon) }.tag(page)
            }
        }
        .sheet(isPresented: $showConnection) { ConnectionView() }
        .alert("Shared Library", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
    }
    private var sourceBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "cloud").foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.sourceName).font(.subheadline.weight(.medium)).lineLimit(1)
                Text("\(store.documents.count) documents · Read-only source").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if store.isLoading { ProgressView() }
        }.padding().background(.thinMaterial)
    }
    private var documentList: some View {
        List(filtered) { document in
            Button { selected = document } label: { documentRow(document) }.buttonStyle(.plain)
        }.listStyle(.plain).refreshable { await store.refresh() }
    }
    private func documentRow(_ document: RemoteDocument) -> some View {
        HStack(spacing: 12) {
            Image(systemName: document.fileType == "pdf" ? "doc.richtext" : "rectangle.on.rectangle").font(.title2).foregroundStyle(.tint).frame(width: 38)
            VStack(alignment: .leading, spacing: 5) {
                Text(document.title).font(.headline)
                Text([document.fileType.uppercased(), document.language, document.category].compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }.padding(.vertical, 6)
    }
    private var libraryGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 155, maximum: 240))], spacing: 18) {
                ForEach(filtered) { document in
                    Button { selected = document } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            ThumbnailView(document: document).frame(height: 180).frame(maxWidth: .infinity).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                            Text(document.title).font(.headline).lineLimit(2).frame(height: 46, alignment: .topLeading)
                            Text(document.category ?? document.fileType.uppercased()).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }.padding(12).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                    }.buttonStyle(.plain)
                }
            }.padding()
        }.background(Color(.systemGroupedBackground)).refreshable { await store.refresh() }
    }
    private var calendar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Button { shiftMonth(-1) } label: { Label("Previous month", systemImage: "chevron.left").labelStyle(.iconOnly) }
                    Spacer()
                    Text(month, format: .dateTime.month(.wide).year()).font(.title3.bold())
                    Spacer()
                    Button { shiftMonth(1) } label: { Label("Next month", systemImage: "chevron.right").labelStyle(.iconOnly) }
                }
                let calendar = Calendar.current
                let start = calendar.date(from: calendar.dateComponents([.year, .month], from: month))!
                let days = calendar.range(of: .day, in: .month, for: month)!
                let offset = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7), spacing: 14) {
                    ForEach(0..<7) { index in Text(calendar.veryShortWeekdaySymbols[(index + calendar.firstWeekday - 1) % 7]).font(.caption).foregroundStyle(.secondary) }
                    ForEach(0..<offset, id: \.self) { _ in Color.clear.frame(height: 30) }
                    ForEach(Array(days), id: \.self) { day in
                        let date = calendar.date(byAdding: .day, value: day - 1, to: start)!
                        let hasDocument = filtered.contains { $0.eventDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false }
                        VStack(spacing: 3) {
                            Text("\(day)").font(.subheadline.weight(hasDocument ? .bold : .regular))
                            Circle().fill(hasDocument ? Color.accentColor : .clear).frame(width: 5, height: 5)
                        }.frame(height: 30).frame(maxWidth: .infinity).accessibilityLabel("\(date.formatted(date: .complete, time: .omitted))\(hasDocument ? ", has documents" : "")")
                    }
                }
                Text("THIS MONTH").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                let scheduled = filtered.filter { $0.eventDate.map { calendar.isDate($0, equalTo: month, toGranularity: .month) } ?? false }.sorted { $0.eventDate! < $1.eventDate! }
                if scheduled.isEmpty { Text("No dated documents this month. Dates come from the catalog or filenames such as 2026-09-13 Sermon.pdf.").foregroundStyle(.secondary) }
                ForEach(scheduled) { document in
                    Button { selected = document } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            if let date = document.eventDate { Text(date, format: .dateTime.weekday(.wide).month().day()).font(.caption).foregroundStyle(.tint) }
                            documentRow(document)
                        }.padding().background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain)
                }
                Button("Today") { month = Date() }.buttonStyle(.bordered)
            }.padding()
        }.background(Color(.systemGroupedBackground)).refreshable { await store.refresh() }
    }
    private func shiftMonth(_ amount: Int) { month = Calendar.current.date(byAdding: .month, value: amount, to: month) ?? month }
}

struct ConnectionView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var picking = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Shared teaching, wherever you are", systemImage: "cloud").font(.headline)
                    Text("Connect once, then refresh to discover changes. Opened documents are cached for offline reading.")
                }
                Section("OneDrive or another Files provider") {
                    Button("Choose Shared Folder…") { picking = true }.disabled(store.isLoading)
                    Text("Enable OneDrive in the Files app and sign in there first. Folder selection depends on your provider; if a shared folder is unavailable, use a web catalog.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Web folder") {
                    TextField("https://example.org/cnreformer.json", text: $url).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Connect Web Catalog") { Task { await store.connectWeb(url); if store.error == nil { dismiss() } } }.disabled(url.isEmpty || store.isLoading)
                    Text("Use a public HTTPS JSON catalog with direct document URLs. Ordinary OneDrive sharing pages require Microsoft authentication and cannot be used here.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Current connection") {
                    Text(store.sourceName)
                    if let date = store.lastRefresh { LabeledContent("Last refreshed", value: date.formatted()) }
                    if store.isLoading { ProgressView("Loading folder…") }
                    if let error = store.error { Text(error).foregroundStyle(.red).font(.callout) }
                }
            }.navigationTitle("Shared Folder").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $picking) { FolderPicker { result in
                picking = false
                if let result { Task { await store.connectFolder(result); if store.error == nil { dismiss() } } }
            } }
        }
    }
}
struct FolderPicker: UIViewControllerRepresentable {
    var completion: (URL?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        var completion: (URL?) -> Void
        init(_ completion: @escaping (URL?) -> Void) { self.completion = completion }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { completion(urls.first) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { completion(nil) }
    }
}
struct ThumbnailView: View {
    @EnvironmentObject private var store: LibraryStore
    let document: RemoteDocument
    @State private var thumbnail: UIImage?
    var body: some View {
        Group {
            if let thumbnail { Image(uiImage: thumbnail).resizable().scaledToFit() }
            else { VStack(spacing: 12) { Image(systemName: "doc.richtext").font(.system(size: 44, weight: .light)); Text(document.fileType.uppercased()).font(.caption.bold()) }.foregroundStyle(.tint) }
        }.task(id: document) {
            let url = store.cachedURL(for: document)
            if document.fileType == "pdf", let pdf = PDFDocument(url: url), let page = pdf.page(at: 0) { thumbnail = page.thumbnail(of: CGSize(width: 300, height: 400), for: .cropBox) }
        }
    }
}
struct ReaderView: View {
    @EnvironmentObject private var store: LibraryStore
    let document: RemoteDocument
    @State private var url: URL?
    @State private var error: String?
    @State private var loading = false
    @State private var revision = UUID()
    var body: some View {
        Group {
            if loading { ProgressView("Loading document…") }
            else if let error { ContentUnavailableView { Label("Unable to open document", systemImage: "exclamationmark.triangle") } description: { Text(error) } actions: { Button("Try Again") { Task { await open(force: true) } } } }
            else if let url {
                if document.fileType == "pdf" { PDFReader(url: url).id(revision) }
                else { QuickLookReader(url: url).id(revision) }
            }
        }
        .navigationTitle(document.title).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let url { ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") } }
                Button { Task { await open(force: true) } } label: { Label("Reload from source", systemImage: "arrow.clockwise") }.disabled(loading)
            }
        }.task(id: document) { await open() }
    }
    private func open(force: Bool = false) async {
        loading = true; error = nil
        defer { loading = false }
        do {
            let loaded = try await store.load(document, force: force)
            if document.fileType == "pdf", PDFDocument(url: loaded) == nil { throw LibraryError.message("This file is not a readable PDF. Export it again from the source application.") }
            url = loaded; revision = UUID()
        } catch { self.error = error.localizedDescription }
    }
}
struct PDFReader: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> PDFView { let view = PDFView(); view.autoScales = true; view.displayMode = .singlePageContinuous; view.document = PDFDocument(url: url); return view }
    func updateUIView(_ view: PDFView, context: Context) { if view.document?.documentURL != url { view.document = PDFDocument(url: url) } }
}
struct QuickLookReader: UIViewControllerRepresentable {
    let url: URL
    func makeCoordinator() -> Coordinator { Coordinator(url) }
    func makeUIViewController(context: Context) -> QLPreviewController { let view = QLPreviewController(); view.dataSource = context.coordinator; return view }
    func updateUIViewController(_ view: QLPreviewController, context: Context) { if context.coordinator.url != url { context.coordinator.url = url; view.reloadData() } }
    class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL
        init(_ url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { url as NSURL }
    }
}
