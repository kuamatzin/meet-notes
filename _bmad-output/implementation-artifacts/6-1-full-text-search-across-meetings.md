# Story 6.1: Full-Text Search Across Meetings

Status: done

## Story

As a user trying to find a specific decision or topic from a past meeting,
I want to type a keyword in the sidebar search field and instantly see all meetings and transcript segments that contain it — with matching text highlighted,
so that I can surface any specific moment from any meeting in under 10 seconds.

## Acceptance Criteria

1. **Given** the main window is open **When** the user presses `Cmd+F` **Then** the cursor moves to the sidebar search field with placeholder "Search transcripts..." (FR22)

2. **Given** the user types a search query **When** each keystroke fires after a 200ms debounce **Then** `MeetingListViewModel` executes an FTS5 Porter-stemmed query against `segments_fts` and updates the meeting list to show only meetings with matching segments (FR22)

3. **Given** search results are displayed **When** the user opens a matching meeting **Then** `TranscriptView` scrolls to the first matching segment and highlights all matching terms with accent color `#5B6CF6` (FR23)

4. **Given** a search query returns no results **When** the results list renders **Then** an empty state reads "No meetings found for '[query]'" — not a blank list

5. **Given** the user clears the search field **When** the field is empty **Then** the full meeting list is restored immediately with no reload delay

6. **Given** FTS5 Porter stemming is active **When** the user searches "decided" **Then** meetings containing "decide", "deciding", or "decided" are all returned (note: "decision" has a different Porter stem and is not matched)

## Tasks / Subtasks

- [x] Task 1: Add FTS5 search method to `AppDatabase` (AC: #2, #6)
  - [x] 1.1 Add `searchSegments(query:)` method returning `[(meetingId: String, segmentId: Int64, snippet: String)]`
  - [x] 1.2 Use FTS5 MATCH with Porter stemming: `SELECT segments.meeting_id, segments.id, snippet(segments_fts, 0, '<mark>', '</mark>', '...', 32) FROM segments_fts JOIN segments ON segments.id = segments_fts.rowid WHERE segments_fts MATCH ? ORDER BY rank`
  - [x] 1.3 Group results by meeting_id for list display

- [x] Task 2: Add search to `MeetingListViewModel` (AC: #2, #4, #5)
  - [x] 2.1 Add `searchQuery: String` property (already exists — verify wired to `.searchable`)
  - [x] 2.2 Add 200ms debounce using `Task.sleep(nanoseconds:)` + cancellation pattern on `searchQuery` changes
  - [x] 2.3 When query is non-empty: call `AppDatabase.shared.searchSegments(query:)`, filter `sections` to only matching meetings, store matched segment IDs per meeting
  - [x] 2.4 When query is empty: restore full meeting list from `allMeetings` via `recomputeSections()`
  - [x] 2.5 Add `searchResults: [String: [Int64]]` dictionary (meetingId → matched segmentIds) for highlight pass-through

- [x] Task 3: Wire `Cmd+F` focus to search field (AC: #1)
  - [x] 3.1 Add `@FocusState` to `MeetingListView` (or `SidebarView` if it wraps the list) bound to search `TextField`
  - [x] 3.2 Add `.commands { CommandMenu }` or `.onKeyPress` for `Cmd+F` to set focus — architecture says use `@FocusState<Bool>` on search `TextField` in `SidebarView`
  - [x] 3.3 Verify `.searchable(text: $viewModel.searchQuery)` modifier is present (already exists in `MeetingListView`)

- [x] Task 4: Add search-result highlighting in `TranscriptView` (AC: #3)
  - [x] 4.1 Accept `matchedSegmentIDs: Set<Int64>` and `searchQuery: String` from parent
  - [x] 4.2 Highlight matching terms in segment text using `AttributedString` with foreground color `#5B6CF6`
  - [x] 4.3 Auto-scroll to first matched segment using `ScrollViewReader.scrollTo(id:anchor:)` when detail loads with active search

- [x] Task 5: Add empty search state (AC: #4)
  - [x] 5.1 In `MeetingListView`, when `searchQuery` is non-empty and `sections` is empty, show "No meetings found for '[query]'" text

- [x] Task 6: Write tests (all ACs)
  - [x] 6.1 `AppDatabaseSearchTests` — FTS5 search round-trip: insert segments, search, verify Porter stemming returns "decide"/"deciding"/"decided"
  - [x] 6.2 `MeetingListViewModelSearchTests` — search filters meetings correctly, empty query restores full list, no-results state
  - [x] 6.3 `AppDatabaseSearchTests` — FTS5 snippet generation with mark tags (searchReturnsSnippetWithMarkTags test)

## Dev Notes

### Architecture Compliance

- **FTS5 is already set up.** The `segments_fts` virtual table with Porter stemming and sync triggers (`segments_ai`, `segments_ad`, `segments_au`) are created in AppDatabase migration "v1". Do NOT create a new migration for FTS5 — it already exists.
- **GRDB writes in service actors only.** The search query is a read operation — safe to call from ViewModel via `pool.read { db in }`. However, if adding a search convenience method to `AppDatabase`, keep it as an `async` method returning results.
- **ValueObservation for live data.** The existing `MeetingListViewModel.startObservation()` uses `ValueObservation.tracking(Meeting.fetchAll)`. Search results should NOT replace this observation — instead, search filtering should work on top of the observed data OR use a separate read query. The architecture data flow specifies: `MeetingListViewModel.search(query:)` → FTS5 query → results grouped by meeting_id.
- **No new ViewModels.** Architecture limits to 4 ViewModels. Search lives in `MeetingListViewModel`.

### FTS5 Query Pattern

The architecture specifies this exact query pattern:
```sql
SELECT segments.meeting_id, snippet(segments_fts, 0, '<mark>', '</mark>', '...', 32)
FROM segments_fts
JOIN segments ON segments.id = segments_fts.rowid
WHERE segments_fts MATCH ?
ORDER BY rank
```
Results are grouped by `meeting_id` and ranked by relevance. Use GRDB's raw SQL interface for this — FTS5 queries don't map cleanly to GRDB's query builder.

### Debounce Pattern (Swift 6 Concurrency)

Use a cancellable `Task` for debounce — do NOT use Combine:
```swift
private var searchTask: Task<Void, Never>?

// Called from onChange of searchQuery
func performSearch() {
    searchTask?.cancel()
    searchTask = Task { [weak self] in
        try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
        guard !Task.isCancelled else { return }
        await self?.executeSearch()
    }
}
```

### Highlight Pattern

Use `AttributedString` for term highlighting in `TranscriptSegmentRow`. The accent color is `#5B6CF6`. Since `TranscriptView` already uses `SelectableTextView` (NSViewRepresentable wrapping NSTextView), highlighting must work within that bridge. Consider:
- Passing highlighted `AttributedString` to `SelectableTextView`
- Or using the FTS5 `snippet()` with `<mark>` tags and parsing them into attributed text

### Cmd+F Implementation

Architecture specifies: `Cmd+F` handled in `SidebarView` via `@FocusState<Bool>` bound to search `TextField`. The `.searchable` modifier on `MeetingListView` already provides a search field — verify if `Cmd+F` natively focuses it. If not, add `.onKeyPress(.f, modifiers: .command)` or use SwiftUI `.commands` modifier.

### Existing Code to Reuse — Do NOT Reinvent

- `MeetingListViewModel.searchQuery` — already declared, wired to `.searchable` modifier
- `MeetingListViewModel.recomputeSections()` — use for restoring full list on clear
- `TranscriptView` scroll infrastructure — `ScrollViewReader` + `ScrollOffsetPreferenceKey` already exist
- `AppDatabase.shared` singleton — add search method here
- `TranscriptSegment.Columns` enum — use for query construction
- FTS5 triggers — already in "v1" migration, segments are already indexed

### Files to Modify

| File | Change |
|---|---|
| `Infrastructure/Database/AppDatabase.swift` | Add `searchSegments(query:)` method |
| `Features/MeetingList/MeetingListViewModel.swift` | Add debounced search logic, search results storage, filtered sections |
| `Features/MeetingList/MeetingListView.swift` | Add empty search state, pass search context to detail |
| `Features/MeetingDetail/TranscriptView.swift` | Add highlight + auto-scroll for matched segments |
| `Features/MeetingDetail/MeetingDetailViewModel.swift` | Accept and pass matched segment IDs + query from list |

### Files to Create

| File | Purpose |
|---|---|
| `MeetNotesTests/Infrastructure/AppDatabaseSearchTests.swift` | FTS5 search round-trip tests |
| `MeetNotesTests/MeetingList/MeetingListViewModelSearchTests.swift` | Search filtering + debounce tests |

### Testing Strategy

- **Swift Testing framework** (`@Test`, `#expect`) — not XCTest
- **Database tests:** temp file-backed `AppDatabase` with UUID name, full migrator run, insert test meetings + segments, verify FTS5 returns correct results with Porter stemming
- **ViewModel tests:** mock `AppDatabase` or use real temp DB, verify search filtering, empty state, clear behavior
- **Known pre-existing failures:** 5 failures in `MeetingListViewModelTests`, 2 in `TranscriptionServiceTests` — unrelated, do not fix

### Project Structure Notes

- All changes align with established folder structure
- No new feature folders needed — search is part of MeetingList feature
- Test files go in `MeetNotesTests/Infrastructure/` and `MeetNotesTests/MeetingList/`
- No new dependencies required — GRDB FTS5 is built-in SQLite

### References

- [Source: _bmad-output/planning-artifacts/architecture.md#Data Architecture] — FTS5 schema, triggers, query pattern
- [Source: _bmad-output/planning-artifacts/architecture.md#Communication Patterns] — ValueObservation for MeetingListViewModel
- [Source: _bmad-output/planning-artifacts/architecture.md#Keyboard Shortcuts] — Cmd+F focus implementation
- [Source: _bmad-output/planning-artifacts/architecture.md#Data Flow] — Search flow FR22-FR23
- [Source: _bmad-output/planning-artifacts/epics.md#Epic 6 Story 6.1] — Acceptance criteria, BDD scenarios
- [Source: _bmad-output/project-context.md] — Swift 6 rules, GRDB rules, testing rules, anti-patterns
- [Source: _bmad-output/implementation-artifacts/5-4-post-meeting-rich-notification.md] — Previous story patterns, pre-existing test failures

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6

### Debug Log References

- Porter stemming test initially included "decision" which has a different Porter stem ("decis") than "decided"/"decide" ("decid"). Fixed to use "deciding" instead.

### Completion Notes List

- Task 1: Added `searchSegments(query:)` to `AppDatabase` using FTS5 MATCH with raw SQL, Porter stemming, snippet generation with `<mark>` tags. Input is sanitized to alphanumeric tokens.
- Task 2: Added debounced search in `MeetingListViewModel` using cancellable `Task.sleep(nanoseconds:)` pattern. Search filters `allMeetings` to matching IDs. `searchResults` dictionary maps meetingId to matched segmentIds for highlight pass-through. Clear restores full list immediately.
- Task 3: `.searchable(text:prompt:)` with "Search transcripts..." placeholder. SwiftUI's `.searchable` on macOS natively handles Cmd+F focus.
- Task 4: `TranscriptView` accepts `matchedSegmentIDs` and `searchQuery`. `SelectableTextView` highlights terms with bold + accent color #5B6CF6. Auto-scroll to first matched segment via `ScrollViewReader`.
- Task 5: `EmptySearchResultsView` shows "No meetings found for '[query]'" when search returns no results.
- Task 6: 7 tests in `AppDatabaseSearchTests` (FTS5 round-trip, stemming, snippets, grouping, empty query) + 5 tests in `MeetingListViewModelSearchTests` (filter, clear, results dict, no-results, clear results).

### Change Log

- 2026-03-05: Implemented full-text search across meetings (Story 6.1) — FTS5 search method, debounced search in ViewModel, Cmd+F support, term highlighting, empty state, 12 new tests.
- 2026-03-05: Code review fixes — moved `.searchable` to Group level (was disappearing on empty results), replaced hardcoded NSColor with design token `Color.accent`, added `searchFailed` AppError case with user-facing error posting, increased test sleep durations for CI stability, removed dead `hasScrolledToMatch` state, updated AC#6 for Porter stemming accuracy.

### File List

New files:
- MeetNotes/MeetNotes/MeetNotesTests/Infrastructure/AppDatabaseSearchTests.swift
- MeetNotes/MeetNotes/MeetNotesTests/MeetingList/MeetingListViewModelSearchTests.swift

Modified files:
- MeetNotes/MeetNotes/MeetNotes/Infrastructure/Database/AppDatabase.swift
- MeetNotes/MeetNotes/MeetNotes/Features/MeetingList/MeetingListViewModel.swift
- MeetNotes/MeetNotes/MeetNotes/Features/MeetingList/MeetingListView.swift
- MeetNotes/MeetNotes/MeetNotes/Features/MeetingDetail/TranscriptView.swift
- MeetNotes/MeetNotes/MeetNotes/Features/MeetingDetail/MeetingDetailViewModel.swift
- MeetNotes/MeetNotes/MeetNotes/Features/MeetingDetail/MeetingDetailView.swift
- MeetNotes/MeetNotes/MeetNotes/App/AppError.swift
