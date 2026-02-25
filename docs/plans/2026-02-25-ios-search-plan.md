# iOS Search Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add full-text search across all books, sequences, and step notes with navigation to results.

**Architecture:** In-memory search. A `SearchService` loads all text from SQLite across all books, normalizes it, and performs substring matching. Results displayed via SwiftUI `.searchable()` on BookListView, with programmatic `NavigationPath` navigation to matched content.

**Tech Stack:** SwiftUI, GRDB.swift (existing), XCTest

---

### Task 1: Create SearchService with Tests

**Files:**
- Create: `StepbookiOS/Stepbook/Services/SearchService.swift`
- Create: `StepbookiOS/StepbookTests/SearchServiceTests.swift`

**Step 1: Write the failing test**

Create `StepbookiOS/StepbookTests/SearchServiceTests.swift`:

```swift
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
```

**Step 2: Run test to verify it fails**

Run: `cd StepbookiOS && xcodebuild test -scheme Stepbook -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:StepbookTests/SearchServiceTests 2>&1 | tail -20`
Expected: FAIL — `SearchService` does not exist

**Step 3: Write the SearchService implementation**

Create `StepbookiOS/Stepbook/Services/SearchService.swift`:

```swift
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
```

**Step 4: Run tests to verify they pass**

Run: `cd StepbookiOS && xcodebuild test -scheme Stepbook -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:StepbookTests/SearchServiceTests 2>&1 | tail -20`
Expected: All 8 tests PASS

**Step 5: Commit**

```bash
git add StepbookiOS/Stepbook/Services/SearchService.swift StepbookiOS/StepbookTests/SearchServiceTests.swift
git commit -m "feat(ios): add SearchService with in-memory full-text search"
```

---

### Task 2: Add Programmatic Navigation to ContentView

Currently `ContentView` uses an implicit NavigationPath. Search results need to
push `Book` then `Sequence` programmatically. Convert to an explicit `NavigationPath`.

**Files:**
- Modify: `StepbookiOS/Stepbook/ContentView.swift`

**Step 1: Update ContentView to use explicit NavigationPath**

Replace the contents of `ContentView.swift` with:

```swift
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
```

**Step 2: Update BookListView to accept navigationPath**

Add a `navigationPath` binding to `BookListView`. The existing NavigationLink(value:)
usage continues to work — the binding is only needed for programmatic search
navigation.

At the top of `BookListView`, add:

```swift
@Binding var navigationPath: NavigationPath
```

**Step 3: Update SequenceListView to accept navigationPath**

Add a `navigationPath` binding to `SequenceListView`. Same reason — needed for
search result navigation to push a sequence.

At the top of `SequenceListView`, add (alongside the existing `let book: Book`):

```swift
@Binding var navigationPath: NavigationPath
```

**Step 4: Build and verify no regressions**

Run: `cd StepbookiOS && xcodebuild build -scheme Stepbook -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 5: Commit**

```bash
git add StepbookiOS/Stepbook/ContentView.swift StepbookiOS/Stepbook/Views/BookListView.swift StepbookiOS/Stepbook/Views/SequenceListView.swift
git commit -m "refactor(ios): add explicit NavigationPath for programmatic navigation"
```

---

### Task 3: Add Search UI to BookListView

**Files:**
- Modify: `StepbookiOS/Stepbook/Views/BookListView.swift`

**Step 1: Add search state and `.searchable()` modifier**

Add these state properties to `BookListView`:

```swift
@Environment(AppDatabase.self) private var appDb
@State private var searchText = ""
@State private var searchResults: [SearchResult] = []
@State private var isSearching = false
```

Add the `.searchable()` modifier to the List (or the outer container), and add
an `.onChange(of: searchText)` handler that calls `SearchService`:

```swift
.searchable(text: $searchText, prompt: "Search sequences and steps")
.onChange(of: searchText) { _, query in
    if query.isEmpty {
        searchResults = []
        isSearching = false
    } else {
        isSearching = true
        let service = SearchService(appDb: appDb)
        searchResults = service.search(query: query)
    }
}
```

**Step 2: Add search results overlay**

When `isSearching` is true and `searchText` is non-empty, show search results
instead of the normal book list. Use a conditional in the body:

```swift
var body: some View {
    Group {
        if isSearching && !searchText.isEmpty {
            searchResultsList
        } else {
            bookList  // extract existing List into a computed property
        }
    }
    .navigationTitle("Books")
    .searchable(text: $searchText, prompt: "Search sequences and steps")
    // ... existing toolbar, alerts, etc.
}
```

The `searchResultsList` view:

```swift
private var searchResultsList: some View {
    Group {
        if searchResults.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            List(searchResults) { result in
                Button {
                    navigateToResult(result)
                } label: {
                    SearchResultRow(result: result)
                }
            }
        }
    }
}
```

**Step 3: Create SearchResultRow**

A simple row view showing the match context:

```swift
struct SearchResultRow: View {
    let result: SearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(result.sequence.title)
                .font(.headline)
            HStack(spacing: 4) {
                Image(systemName: "book.closed.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(result.book.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let step = result.step {
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text("Step \(step.orderIndex + 1)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if result.matchField == "description" {
                Text(result.matchText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else if result.matchField == "notes" {
                Text(result.matchText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}
```

**Step 4: Implement navigateToResult**

```swift
private func navigateToResult(_ result: SearchResult) {
    // Clear search
    searchText = ""
    isSearching = false

    // Navigate: push book, then sequence
    navigationPath.append(result.book)
    navigationPath.append(result.sequence)
}
```

**Step 5: Build and verify**

Run: `cd StepbookiOS && xcodebuild build -scheme Stepbook -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -5`
Expected: BUILD SUCCEEDED

**Step 6: Run all tests to verify no regressions**

Run: `cd StepbookiOS && xcodebuild test -scheme Stepbook -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -20`
Expected: All tests PASS

**Step 7: Commit**

```bash
git add StepbookiOS/Stepbook/Views/BookListView.swift
git commit -m "feat(ios): add search UI to BookListView with result navigation"
```

---

### Task 4: Run Full Test Suite and Verify

**Step 1: Run all tests**

Run: `cd StepbookiOS && xcodebuild test -scheme Stepbook -destination 'platform=iOS Simulator,name=iPhone 16' 2>&1 | tail -30`
Expected: All tests PASS (including new SearchServiceTests)

**Step 2: Final commit with docs**

```bash
git add docs/plans/2026-02-25-ios-search-design.md docs/plans/2026-02-25-ios-search-plan.md docs/plans/2026-02-25-ios-roadmap.md
git commit -m "docs: add iOS search design, plan, and feature roadmap"
```
