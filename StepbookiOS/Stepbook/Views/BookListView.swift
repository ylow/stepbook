import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let stepbook = UTType(exportedAs: "com.stepbook.book")
    static let stepseq = UTType(exportedAs: "com.stepbook.sequence")
}

struct BookListView: View {
    @Binding var navigationPath: NavigationPath
    @Environment(AppDatabase.self) private var appDb
    @State private var showingNewBook = false
    @State private var newBookName = ""
    @State private var renamingBook: Book?
    @State private var renameText = ""
    @State private var showingImport = false
    @State private var importError: String?
    @State private var shareItem: ShareItem?
    @State private var searchText = ""
    @State private var searchResults: [SearchResult] = []
    @State private var isSearching = false

    var body: some View {
        Group {
            if isSearching && !searchText.isEmpty {
                searchResultsList
            } else {
                bookList
            }
        }
        .navigationTitle("Books")
        .searchable(text: $searchText, prompt: "Search sequences and steps")
        .onChange(of: searchText) { _, query in
            if query.isEmpty {
                searchResults = []
                isSearching = false
            } else {
                isSearching = true
                let service = SearchService(appDb: appDb)
                searchResults = service.search(query: query)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showingImport = true
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                Button {
                    newBookName = ""
                    showingNewBook = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .fileImporter(isPresented: $showingImport, allowedContentTypes: [.stepbook, .zip]) { result in
            if case .success(let url) = result {
                importBook(from: url)
            }
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(url: item.url)
        }
        .alert("Import Failed", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
        .alert("New Book", isPresented: $showingNewBook) {
            TextField("Book name", text: $newBookName)
            Button("Create") {
                guard !newBookName.isEmpty else { return }
                _ = try? appDb.createBook(name: newBookName)
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename Book", isPresented: Binding(
            get: { renamingBook != nil },
            set: { if !$0 { renamingBook = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Save") {
                if let book = renamingBook {
                    _ = try? appDb.renameBook(id: book.id, name: renameText)
                }
                renamingBook = nil
            }
            Button("Cancel", role: .cancel) { renamingBook = nil }
        }
    }

    private var bookList: some View {
        List {
            ForEach(appDb.books) { book in
                NavigationLink(value: book) {
                    HStack {
                        Image(systemName: "book.closed.fill")
                            .foregroundStyle(.blue)
                            .font(.title2)
                        VStack(alignment: .leading) {
                            Text(book.name)
                                .font(.headline)
                            if book.id == "default" {
                                Text("Default")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .contextMenu {
                    Button {
                        exportBook(book)
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    Button("Rename") {
                        renameText = book.name
                        renamingBook = book
                    }
                    if book.id != "default" {
                        Button("Delete", role: .destructive) {
                            try? appDb.deleteBook(id: book.id)
                        }
                    }
                }
            }
        }
    }

    private var searchResultsList: some View {
        Group {
            if searchResults.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                List(searchResults) { result in
                    Button {
                        navigateToResult(result)
                    } label: {
                        SearchResultRow(result: result)
                    }
                }
            }
        }
    }

    private func navigateToResult(_ result: SearchResult) {
        searchText = ""
        isSearching = false
        navigationPath.append(result.book)
        navigationPath.append(result.sequence)
    }

    private func exportBook(_ book: Book) {
        do {
            let url = try appDb.exportBook(id: book.id)
            shareItem = ShareItem(url: url)
        } catch {
            importError = error.localizedDescription
        }
    }

    private func importBook(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        do {
            _ = try appDb.importBook(from: url)
        } catch {
            importError = error.localizedDescription
        }
    }
}

struct SearchResultRow: View {
    let result: SearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(result.sequence.title)
                .font(.headline)
            HStack(spacing: 4) {
                Image(systemName: "book.closed.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(result.book.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let step = result.step {
                    Text("\u{00b7}")
                        .foregroundStyle(.secondary)
                    Text("Step \(step.orderIndex + 1)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if result.matchField == "description" || result.matchField == "notes" {
                Text(result.matchText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
