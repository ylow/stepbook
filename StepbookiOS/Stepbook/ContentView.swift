import SwiftUI

struct ContentView: View {
    @State private var appDb = AppDatabase()
    @State private var navigationPath = NavigationPath()

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
    }
}
