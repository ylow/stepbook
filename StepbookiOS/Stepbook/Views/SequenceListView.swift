import SwiftUI
import UniformTypeIdentifiers

struct SequenceListView: View {
    let book: Book
    @Binding var navigationPath: NavigationPath
    @Environment(AppDatabase.self) private var appDb
    @State private var sequences: [Sequence] = []
    @State private var showingNewSequence = false
    @State private var newTitle = ""
    @State private var showingImport = false
    @State private var shareItem: ShareItem?

    var body: some View {
        Group {
            if sequences.isEmpty {
                ContentUnavailableView(
                    "No Sequences",
                    systemImage: "photo.stack",
                    description: Text("Tap + to create your first step-by-step guide.")
                )
            } else {
                List {
                    ForEach(sequences) { seq in
                        NavigationLink(value: seq) {
                            SequenceRow(sequence: seq, imageStore: imageStore)
                        }
                        .contextMenu {
                            Button {
                                exportSequence(seq)
                            } label: {
                                Label("Export", systemImage: "square.and.arrow.up")
                            }
                            Button("Delete", role: .destructive) {
                                deleteSequence(seq)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Delete", role: .destructive) {
                                deleteSequence(seq)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(book.name)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showingImport = true
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                Button {
                    newTitle = ""
                    showingNewSequence = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert("New Sequence", isPresented: $showingNewSequence) {
            TextField("Title", text: $newTitle)
            Button("Create") {
                guard !newTitle.isEmpty else { return }
                createSequence()
            }
            Button("Cancel", role: .cancel) {}
        }
        .fileImporter(isPresented: $showingImport, allowedContentTypes: [UTType.zip]) { result in
            if case .success(let url) = result {
                importSequence(from: url)
            }
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(url: item.url)
        }
        .task { await loadSequences() }
    }

    private var imageStore: ImageStore? {
        guard let db = appDb.activeDatabase else { return nil }
        return ImageStore(imagesDirectory: db.imagesDirectory)
    }

    private func loadSequences() async {
        try? appDb.switchBook(id: book.id)
        guard let db = appDb.activeDatabase else { return }
        sequences = (try? db.listSequences()) ?? []
    }

    private func createSequence() {
        guard let db = appDb.activeDatabase else { return }
        _ = try? db.createSequence(title: newTitle, description: "")
        Task { await loadSequences() }
    }

    private func deleteSequence(_ seq: Sequence) {
        guard let db = appDb.activeDatabase else { return }
        imageStore?.deleteSequenceImages(sequenceId: seq.id)
        try? db.deleteSequence(id: seq.id)
        Task { await loadSequences() }
    }

    private func exportSequence(_ seq: Sequence) {
        guard let db = appDb.activeDatabase, let store = imageStore else { return }
        let service = ImportExportService(database: db, imageStore: store)
        do {
            let url = try service.exportSequence(id: seq.id)
            shareItem = ShareItem(url: url)
        } catch {
            print("Export failed: \(error)")
        }
    }

    private func importSequence(from url: URL) {
        guard let db = appDb.activeDatabase, let store = imageStore else { return }
        let service = ImportExportService(database: db, imageStore: store)
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        _ = try? service.importSequence(from: url)
        Task { await loadSequences() }
    }
}

struct SequenceRow: View {
    let sequence: Sequence
    let imageStore: ImageStore?

    var body: some View {
        HStack(spacing: 12) {
            if let path = sequence.thumbnailPath,
               let store = imageStore,
               let thumb = store.loadThumbnail(path: path, maxSize: CGSize(width: 80, height: 60)) {
                Image(uiImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
                    .frame(width: 80, height: 60)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(sequence.title)
                    .font(.headline)
                if let count = sequence.stepCount {
                    Text("\(count) step\(count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
