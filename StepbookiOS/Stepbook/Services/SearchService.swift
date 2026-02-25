import Foundation

struct SearchResult: Identifiable {
    let id: String
    let book: Book
    let sequence: Sequence
    let step: Step?
    let matchField: String  // "title", "description", or "notes"
    let matchText: String
}

final class SearchService {
    private let appDb: AppDatabase

    init(appDb: AppDatabase) {
        self.appDb = appDb
    }

    func search(query: String) -> [SearchResult] {
        let normalizedQuery = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !normalizedQuery.isEmpty else { return [] }

        var titleResults: [SearchResult] = []
        var descriptionResults: [SearchResult] = []
        var notesResults: [SearchResult] = []

        let previousBookId = appDb.activeBookId

        for book in appDb.books {
            guard let db = openBook(book) else { continue }

            guard let sequences = try? db.listSequences() else { continue }

            for seq in sequences {
                // Check title
                if seq.title.lowercased().contains(normalizedQuery) {
                    titleResults.append(SearchResult(
                        id: "title-\(seq.id)",
                        book: book, sequence: seq, step: nil,
                        matchField: "title", matchText: seq.title
                    ))
                }

                // Check description
                if !seq.description.isEmpty,
                   seq.description.lowercased().contains(normalizedQuery) {
                    descriptionResults.append(SearchResult(
                        id: "desc-\(seq.id)",
                        book: book, sequence: seq, step: nil,
                        matchField: "description", matchText: seq.description
                    ))
                }

                // Check step notes
                guard let steps = try? db.fetchSteps(sequenceId: seq.id) else { continue }
                for step in steps where !step.notes.isEmpty {
                    if step.notes.lowercased().contains(normalizedQuery) {
                        notesResults.append(SearchResult(
                            id: "notes-\(step.id)",
                            book: book, sequence: seq, step: step,
                            matchField: "notes", matchText: step.notes
                        ))
                    }
                }
            }
        }

        // Restore previous book
        try? appDb.switchBook(id: previousBookId)

        return titleResults + descriptionResults + notesResults
    }

    private func openBook(_ book: Book) -> BookDatabase? {
        let bookDir = appDb.rootDirectory.appendingPathComponent(book.path)
        return try? BookDatabase(directory: bookDir)
    }
}
