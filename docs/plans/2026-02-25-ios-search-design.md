# iOS Search Feature Design

## Goal

Add full-text search across all books, sequences, and steps. Users can search from
the top-level BookListView and navigate directly to matching results.

## Approach: In-Memory Search

Load all searchable text from SQLite into memory, normalize, and match. No DB
migration, no FTS index, no backwards-compatibility concerns. The expected data
sizes (dozens to hundreds of sequences, thousands of steps at most) make this
entirely practical.

## Searchable Fields

| Level    | Fields                          |
|----------|---------------------------------|
| Book     | name                            |
| Sequence | title, description              |
| Step     | notes                           |

## Search Algorithm

1. On search activation, load all books, their sequences, and step notes into a
   flat list of `SearchResult` items
2. Normalize query and content: lowercased, whitespace-trimmed
3. Match: check if the normalized query is a substring of the normalized content
4. Return results grouped by book, then by sequence
5. For step matches, include the parent sequence context so the user knows where
   the match lives

## Data Model

```swift
struct SearchResult: Identifiable {
    let id: String           // unique result id
    let book: Book
    let sequence: Sequence
    let step: Step?          // nil for sequence-level matches
    let matchField: String   // "title", "description", or "notes"
    let matchText: String    // the text that matched (for display)
}
```

## Search Service

A `SearchService` class that:
- Takes `AppDatabase` reference
- Has a `search(query:) -> [SearchResult]` method
- Iterates all books, opens each BookDatabase, loads sequences and steps
- Performs in-memory substring matching
- Returns results sorted by relevance (title matches first, then description,
  then notes)

## UI Design

### Where: BookListView with `.searchable()`

Add SwiftUI's `.searchable()` modifier to BookListView. When the search field is
active and has text, replace the normal book list with search results.

### Search Results View

- Results grouped by book (section headers)
- Each result row shows:
  - Sequence title (always)
  - Match context: the matching text snippet with the query highlighted
  - Step indicator if the match is in step notes (e.g. "Step 3")
- Tapping a result navigates to the SequenceEditorView, scrolled to the matching
  step if applicable

### Empty/No Results States

- Empty query: show normal book list (default behavior of `.searchable()`)
- No results: show `ContentUnavailableView` with "No Results" message
- Loading: not needed (in-memory search is synchronous and fast)

## Navigation

Tapping a search result needs to push two levels onto the NavigationStack:
1. SequenceListView (for the book)
2. SequenceEditorView (for the sequence, at the matched step)

Use `NavigationPath` programmatic navigation to push the correct destination.

## Scope

### In scope
- Search bar on BookListView
- In-memory substring search across all books/sequences/steps
- Results with navigation to matched content
- Case-insensitive matching

### Out of scope (future)
- Search within SequenceListView (can add later)
- Annotation text search
- Search history / recent searches
- Fuzzy matching / typo tolerance
