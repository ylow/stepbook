import XCTest
@testable import Stepbook

final class SearchServiceTests: XCTestCase {

    var appDb: AppDatabase!
    var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        appDb = AppDatabase(rootDirectory: tempDir)
    }

    override func tearDown() async throws {
        appDb = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testSearchBySequenceTitle() throws {
        try appDb.switchBook(id: "default")
        let db = appDb.activeDatabase!
        _ = try db.createSequence(title: "Chocolate Cake Recipe", description: "A delicious cake")
        _ = try db.createSequence(title: "Oil Change Guide", description: "Car maintenance")

        let service = SearchService(appDb: appDb)
        let results = service.search(query: "chocolate")

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].sequence.title, "Chocolate Cake Recipe")
        XCTAssertNil(results[0].step)
    }

    func testSearchBySequenceDescription() throws {
        try appDb.switchBook(id: "default")
        let db = appDb.activeDatabase!
        _ = try db.createSequence(title: "My Guide", description: "How to fix a bicycle tire")

        let service = SearchService(appDb: appDb)
        let results = service.search(query: "bicycle")

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].matchField, "description")
    }

    func testSearchByStepNotes() throws {
        try appDb.switchBook(id: "default")
        let db = appDb.activeDatabase!
        let seq = try db.createSequence(title: "Cooking Guide", description: "")
        let step = try db.createStep(sequenceId: seq.id, imagePath: "s/1.jpg")
        _ = try db.updateStep(id: step.id, annotations: nil, notes: "Preheat oven to 350 degrees")

        let service = SearchService(appDb: appDb)
        let results = service.search(query: "preheat")

        XCTAssertEqual(results.count, 1)
        XCTAssertNotNil(results[0].step)
        XCTAssertEqual(results[0].matchField, "notes")
    }

    func testSearchIsCaseInsensitive() throws {
        try appDb.switchBook(id: "default")
        let db = appDb.activeDatabase!
        _ = try db.createSequence(title: "UPPER CASE TITLE", description: "")

        let service = SearchService(appDb: appDb)
        let results = service.search(query: "upper case")

        XCTAssertEqual(results.count, 1)
    }

    func testSearchAcrossMultipleBooks() throws {
        // Default book
        try appDb.switchBook(id: "default")
        let db1 = appDb.activeDatabase!
        _ = try db1.createSequence(title: "Book1 Pancake Recipe", description: "")

        // Second book
        let book2 = try appDb.createBook(name: "Second Book")
        try appDb.switchBook(id: book2.id)
        let db2 = appDb.activeDatabase!
        _ = try db2.createSequence(title: "Book2 Pancake Recipe", description: "")

        let service = SearchService(appDb: appDb)
        let results = service.search(query: "pancake")

        XCTAssertEqual(results.count, 2)
    }

    func testSearchEmptyQueryReturnsNoResults() throws {
        try appDb.switchBook(id: "default")
        let db = appDb.activeDatabase!
        _ = try db.createSequence(title: "Test", description: "")

        let service = SearchService(appDb: appDb)
        let results = service.search(query: "")

        XCTAssertTrue(results.isEmpty)
    }

    func testSearchNoMatchReturnsEmpty() throws {
        try appDb.switchBook(id: "default")
        let db = appDb.activeDatabase!
        _ = try db.createSequence(title: "Cake Recipe", description: "")

        let service = SearchService(appDb: appDb)
        let results = service.search(query: "zzzznotfound")

        XCTAssertTrue(results.isEmpty)
    }

    func testSearchResultsOrderTitleBeforeDescriptionBeforeNotes() throws {
        try appDb.switchBook(id: "default")
        let db = appDb.activeDatabase!
        let seq1 = try db.createSequence(title: "Other Guide", description: "")
        let step = try db.createStep(sequenceId: seq1.id, imagePath: "s/1.jpg")
        _ = try db.updateStep(id: step.id, annotations: nil, notes: "Special keyword here")

        _ = try db.createSequence(title: "Other Thing", description: "Special keyword in desc")
        _ = try db.createSequence(title: "Special keyword in title", description: "")

        let service = SearchService(appDb: appDb)
        let results = service.search(query: "special keyword")

        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results[0].matchField, "title")
        XCTAssertEqual(results[1].matchField, "description")
        XCTAssertEqual(results[2].matchField, "notes")
    }
}
