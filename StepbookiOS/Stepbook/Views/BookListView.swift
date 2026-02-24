import SwiftUI

struct BookListView: View {
    @Environment(AppDatabase.self) private var appDb
    @State private var showingNewBook = false
    @State private var newBookName = ""
    @State private var renamingBook: Book?
    @State private var renameText = ""

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
            ToolbarItem(placement: .primaryAction) {
                Button {
                    newBookName = ""
                    showingNewBook = true
                } label: {
                    Image(systemName: "plus")
                }
            }
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
}
