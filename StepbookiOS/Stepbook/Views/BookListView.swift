import SwiftUI
import UniformTypeIdentifiers

struct BookListView: View {
    @Binding var navigationPath: NavigationPath
    @Environment(AppDatabase.self) private var appDb
    @State private var showingNewBook = false
    @State private var newBookName = ""
    @State private var renamingBook: Book?
    @State private var renameText = ""
    @State private var showingImport = false
    @State private var importError: String?
    @State private var exportURL: URL?
    @State private var showShareSheet = false

    var body: some View {
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
        .navigationTitle("Books")
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
        .fileImporter(isPresented: $showingImport, allowedContentTypes: [UTType.zip]) { result in
            if case .success(let url) = result {
                importBook(from: url)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = exportURL {
                ShareSheet(url: url)
            }
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

    private func exportBook(_ book: Book) {
        do {
            exportURL = try appDb.exportBook(id: book.id)
            showShareSheet = true
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

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
