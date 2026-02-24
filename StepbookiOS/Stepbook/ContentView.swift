import SwiftUI

struct ContentView: View {
    @State private var appDb = AppDatabase()

    var body: some View {
        NavigationStack {
            BookListView()
                .navigationDestination(for: Book.self) { book in
                    SequenceListView(book: book)
                        .navigationDestination(for: Sequence.self) { seq in
                            SequenceEditorView(sequenceId: seq.id, book: book)
                        }
                }
        }
        .environment(appDb)
    }
}
