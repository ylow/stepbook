import Foundation
import GRDB
import ZIPFoundation

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

    // MARK: - Book Export & Import

    /// Export a book as a ZIP file (web-compatible format).
    /// Contains manifest.json, stepbook.db, and images/.
    func exportBook(id: String) throws -> URL {
        guard let book = books.first(where: { $0.id == id }) else {
            throw StepbookError(message: "Book not found")
        }
        let bookDir = bookDirectory(for: book)
        let dbURL = bookDir.appendingPathComponent("stepbook.db")
        let imagesDir = bookDir.appendingPathComponent("images")

        guard FileManager.default.fileExists(atPath: dbURL.path) else {
            throw StepbookError(message: "Book database not found")
        }

        // Create a clean standalone copy of the database using VACUUM INTO.
        // This avoids WAL checkpoint locking issues — VACUUM INTO reads the
        // database and writes a self-contained copy without needing exclusive access.
        let backupDbURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-\(UUID().uuidString).db")

        let dbPool: DatabasePool
        if id == activeBookId, let activeDb = activeDatabase {
            dbPool = activeDb.dbPool
        } else {
            dbPool = try BookDatabase(directory: bookDir).dbPool
        }
        try dbPool.writeWithoutTransaction { db in
            try db.execute(sql: "VACUUM INTO ?", arguments: [backupDbURL.path])
        }

        // Build manifest
        struct BookManifest: Codable {
            var version: Int
            var book: BookInfo
            struct BookInfo: Codable {
                var name: String
            }
        }
        let manifest = BookManifest(version: 1, book: .init(name: book.name))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifestData = try encoder.encode(manifest)

        // Create ZIP
        let safeName = book.name
            .replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "_", options: .regularExpression)
            .prefix(50)
        let zipURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeName).stepbook")
        try? FileManager.default.removeItem(at: zipURL)

        let archive = try Archive(url: zipURL, accessMode: .create)

        // Add manifest.json
        try archive.addEntry(
            with: "manifest.json",
            type: .file,
            uncompressedSize: Int64(manifestData.count)
        ) { (position: Int64, size: Int) -> Data in
            let start = Int(position)
            return manifestData[start..<start+size]
        }

        // Add stepbook.db (the clean backup copy)
        try archive.addEntry(with: "stepbook.db", fileURL: backupDbURL)

        // Add all images
        let fm = FileManager.default
        if fm.fileExists(atPath: imagesDir.path),
           let enumerator = fm.enumerator(at: imagesDir, includingPropertiesForKeys: nil) {
            while let fileURL = enumerator.nextObject() as? URL {
                guard fileURL.isFileURL else { continue }
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: fileURL.path, isDirectory: &isDir), !isDir.boolValue else { continue }
                let relativePath = fileURL.path.replacingOccurrences(
                    of: imagesDir.path + "/", with: ""
                )
                try archive.addEntry(with: "images/\(relativePath)", fileURL: fileURL)
            }
        }

        // Clean up the temporary database backup
        try? FileManager.default.removeItem(at: backupDbURL)

        return zipURL
    }

    /// Import a book from a ZIP file (web-compatible format).
    /// The ZIP must contain manifest.json, stepbook.db, and images/.
    func importBook(from zipURL: URL) throws -> Book {
        let archive = try Archive(url: zipURL, accessMode: .read)

        // Read manifest
        guard let manifestEntry = archive["manifest.json"] else {
            throw StepbookError(message: "Missing manifest.json in ZIP")
        }
        var manifestData = Data()
        _ = try archive.extract(manifestEntry) { data in
            manifestData.append(data)
        }

        struct BookManifest: Codable {
            var version: Int
            var book: BookInfo
            struct BookInfo: Codable {
                var name: String
            }
        }

        let manifest = try JSONDecoder().decode(BookManifest.self, from: manifestData)
        guard !manifest.book.name.isEmpty else {
            throw StepbookError(message: "Book name is empty")
        }

        // Verify stepbook.db exists in archive
        guard archive["stepbook.db"] != nil else {
            throw StepbookError(message: "Missing stepbook.db in ZIP")
        }

        // Create a new book
        let bookId = UUID().uuidString
        let bookDir = rootDirectory.appendingPathComponent(bookId)
        let imagesDir = bookDir.appendingPathComponent("images")
        try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)

        let allowedImageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "webp"]

        // Extract entries
        for entry in archive {
            let name = entry.path

            if name == "stepbook.db" {
                let destURL = bookDir.appendingPathComponent("stepbook.db")
                _ = try archive.extract(entry, to: destURL)
            } else if name.hasPrefix("images/") && entry.type == .file {
                let ext = URL(fileURLWithPath: name).pathExtension.lowercased()
                guard allowedImageExtensions.contains(ext) else { continue }
                // Guard against path traversal
                let relativePath = String(name.dropFirst("images/".count))
                guard !relativePath.contains("..") else { continue }
                let destURL = imagesDir.appendingPathComponent(relativePath)
                let parentDir = destURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
                _ = try archive.extract(entry, to: destURL)
            }
        }

        // Register the book
        let book = Book(id: bookId, name: manifest.book.name, path: bookId)
        books.append(book)
        saveRegistry()

        // Run migrations on the imported database to ensure schema compatibility
        _ = try BookDatabase(directory: bookDir)

        return book
    }
}
