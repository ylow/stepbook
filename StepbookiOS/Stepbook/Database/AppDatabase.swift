import Foundation

/// Manages the top-level book registry (books.json) and provides
/// access to individual book databases.
@Observable
final class AppDatabase {
    private(set) var books: [Book] = []
    private(set) var activeBookId: String = "default"
    private(set) var activeDatabase: BookDatabase?

    let rootDirectory: URL

    init() {
        self.rootDirectory = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Stepbook")
        try? FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        loadRegistry()
        ensureDefaultBook()
        try? switchBook(id: activeBookId)
    }

    /// Test-friendly initializer
    init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
        try? FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        loadRegistry()
        ensureDefaultBook()
        try? switchBook(id: activeBookId)
    }

    private var registryURL: URL {
        rootDirectory.appendingPathComponent("books.json")
    }

    // MARK: - Registry

    func loadRegistry() {
        guard let data = try? Data(contentsOf: registryURL),
              let decoded = try? JSONDecoder().decode([Book].self, from: data) else {
            books = []
            return
        }
        books = decoded
    }

    private func saveRegistry() {
        guard let data = try? JSONEncoder().encode(books) else { return }
        try? data.write(to: registryURL)
    }

    private func ensureDefaultBook() {
        if !books.contains(where: { $0.id == "default" }) {
            let defaultBook = Book(id: "default", name: "Default", path: "default")
            books.append(defaultBook)
            saveRegistry()
        }
    }

    // MARK: - Book Operations

    func createBook(name: String) throws -> Book {
        let id = UUID().uuidString
        let book = Book(id: id, name: name, path: id)
        books.append(book)
        saveRegistry()
        return book
    }

    func renameBook(id: String, name: String) throws -> Book {
        guard let index = books.firstIndex(where: { $0.id == id }) else {
            throw StepbookError(message: "Book not found")
        }
        books[index].name = name
        saveRegistry()
        return books[index]
    }

    func deleteBook(id: String) throws {
        guard id != "default" else {
            throw StepbookError(message: "Cannot delete default book")
        }
        books.removeAll { $0.id == id }
        saveRegistry()
    }

    func switchBook(id: String) throws {
        guard let book = books.first(where: { $0.id == id }) else {
            throw StepbookError(message: "Book not found")
        }
        let bookDir = rootDirectory.appendingPathComponent(book.path)
        activeDatabase = try BookDatabase(directory: bookDir)
        activeBookId = id
    }

    func bookDirectory(for book: Book) -> URL {
        rootDirectory.appendingPathComponent(book.path)
    }
}
