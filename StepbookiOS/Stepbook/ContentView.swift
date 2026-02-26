import SwiftUI

struct ContentView: View {
    @State private var appDb = AppDatabase()
    @State private var navigationPath = NavigationPath()
    @State private var importError: String?
    @State private var pendingSequenceURL: URL?

    var body: some View {
        NavigationStack(path: $navigationPath) {
            BookListView(navigationPath: $navigationPath)
                .navigationDestination(for: Book.self) { book in
                    SequenceListView(book: book, navigationPath: $navigationPath)
                        .navigationDestination(for: Sequence.self) { seq in
                            SequenceEditorView(sequenceId: seq.id, book: book)
                        }
                }
        }
        .environment(appDb)
        .onOpenURL { url in
            handleOpenFile(url: url)
        }
        .sheet(isPresented: Binding(
            get: { pendingSequenceURL != nil },
            set: { if !$0 { cleanUpPendingFile() } }
        )) {
            BookPickerSheet(books: appDb.books) { book in
                if let url = pendingSequenceURL {
                    importSequenceFile(from: url, into: book)
                }
                cleanUpPendingFile()
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
    }

    private func handleOpenFile(url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        // Copy to temp location since the source URL may be ephemeral
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("import-\(UUID().uuidString)-\(url.lastPathComponent)")
        do {
            try FileManager.default.copyItem(at: url, to: tempURL)
        } catch {
            importError = "Could not read file: \(error.localizedDescription)"
            return
        }

        let ext = url.pathExtension.lowercased()

        if ext == "stepseq" || ext == "zip" {
            pendingSequenceURL = tempURL
        } else if ext == "stepbook" {
            importBookFile(from: tempURL)
            try? FileManager.default.removeItem(at: tempURL)
        } else {
            importError = "Unsupported file type: .\(ext)"
            try? FileManager.default.removeItem(at: tempURL)
        }
    }

    private func cleanUpPendingFile() {
        if let url = pendingSequenceURL {
            try? FileManager.default.removeItem(at: url)
        }
        pendingSequenceURL = nil
    }

    private func importSequenceFile(from url: URL, into book: Book) {
        do {
            try appDb.switchBook(id: book.id)
            guard let db = appDb.activeDatabase else {
                importError = "Could not open book database"
                return
            }
            let store = ImageStore(imagesDirectory: db.imagesDirectory)
            let service = ImportExportService(database: db, imageStore: store)
            let sequence = try service.importSequence(from: url)

            navigationPath = NavigationPath()
            navigationPath.append(book)
            navigationPath.append(sequence)
        } catch {
            importError = error.localizedDescription
        }
    }

    private func importBookFile(from url: URL) {
        do {
            let book = try appDb.importBook(from: url)
            navigationPath = NavigationPath()
            navigationPath.append(book)
        } catch {
            importError = error.localizedDescription
        }
    }
}

// MARK: - Book Picker

struct BookPickerSheet: View {
    let books: [Book]
    let onSelect: (Book) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(books) { book in
                Button {
                    onSelect(book)
                    dismiss()
                } label: {
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
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Import to Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
