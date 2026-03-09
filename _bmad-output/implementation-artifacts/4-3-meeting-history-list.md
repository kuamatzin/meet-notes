# Story 4.3: Meeting History List

Status: done

## Story

As a user who wants to review past meetings,
I want a sidebar showing all my meetings grouped by recency (Today, This Week, Older),
so that I can quickly find and open any past meeting.

## Acceptance Criteria

1. Main window displays a `NavigationSplitView` with a sidebar containing `MeetingListView` showing meetings sorted by `started_at` DESC
2. Meetings are grouped under section headers: "Today", "This Week", "Older" (with "[Month Year]" subgroups for older)
3. Each meeting row shows: bold AI-generated title (or date fallback) on line 1, date + duration on line 2 in secondary text
4. When no meetings exist, content area shows SF Symbol illustration + "Start Recording" CTA (or "Set Up meet-notes" if permissions missing)
5. `MeetingListViewModel` uses GRDB `ValueObservation` — list updates automatically when meetings are saved/changed
6. Hover over a meeting row reveals trailing action buttons: Export, Copy Summary, Delete
7. Right-click context menu provides: Copy Transcript, Copy Summary, Export as Markdown, Rename, Delete
8. Pipeline status indicators show current state (recording, transcribing, complete, failed) per meeting row
9. All interactive controls are accessible via VoiceOver and keyboard navigation

## Tasks / Subtasks

- [x] Task 1: Create MeetingListViewModel (AC: #1, #5)
  - [x] 1.1 `@Observable @MainActor final class` with GRDB `ValueObservation.tracking` for live meeting data
  - [x] 1.2 Temporal grouping logic: compute "Today", "This Week", "Older" sections from `startedAt`
  - [x] 1.3 `selectedMeetingID: String?` for navigation state
  - [x] 1.4 Error handling: catch DB errors, post to `AppErrorState`
- [x] Task 2: Create MeetingListView (AC: #1, #2, #3)
  - [x] 2.1 `NavigationSplitView` sidebar with grouped `List` using `ForEach` + section headers
  - [x] 2.2 `MeetingRowView` component: 2-line layout (title + date/duration)
  - [x] 2.3 Wire selection to `selectedMeetingID` for detail panel navigation
- [x] Task 3: Empty state view (AC: #4)
  - [x] 3.1 SF Symbol + CTA based on permission status
  - [x] 3.2 Integrate with `PermissionService` for conditional CTA text
- [x] Task 4: Hover actions + context menu (AC: #6, #7)
  - [x] 4.1 Hover-reveal trailing buttons (Export, Copy Summary, Delete)
  - [x] 4.2 Right-click `.contextMenu` with full action set
  - [x] 4.3 Delete confirmation dialog
- [x] Task 5: Pipeline status indicators (AC: #8)
  - [x] 5.1 Status badge/icon per row based on `Meeting.PipelineStatus`
- [x] Task 6: Accessibility (AC: #9)
  - [x] 6.1 VoiceOver labels: `"{title}, {date}, {duration}"`
  - [x] 6.2 Keyboard navigation: arrow keys, Return to open, Delete to remove
  - [x] 6.3 Guard all animations with `@Environment(\.accessibilityReduceMotion)`
- [x] Task 7: Wire into MainWindowView + MeetNotesApp (AC: #1)
  - [x] 7.1 Replace current idle-state content with `NavigationSplitView` layout
  - [x] 7.2 Create `MeetingListViewModel` in `MeetNotesApp.init()`, inject via `.environment()`
  - [x] 7.3 Pass `AppDatabase.shared` to ViewModel for observation
- [x] Task 8: Tests (all ACs)
  - [x] 8.1 `MeetingListViewModelTests.swift`: temporal grouping, observation, selection
  - [x] 8.2 Verify empty state detection
  - [x] 8.3 Verify pipeline status mapping

## Dev Notes

### Architecture Constraints

- **ViewModel pattern**: `@Observable @MainActor final class MeetingListViewModel` — NEVER `ObservableObject`, `@Published`, or `actor`
- **Database reads**: Use `ValueObservation.tracking` for live reactive data. NEVER poll with `Timer`. ViewModels are strictly read-only — no `pool.write`
- **Error handling**: Three-layer rule — service throws → ViewModel catches → posts to `AppErrorState` → View renders `ErrorBannerView`
- **Swift 6 concurrency**: `SWIFT_STRICT_CONCURRENCY = complete`. No Combine. No `@StateObject`
- **Logging**: `private let logger = Logger(subsystem: "com.kuamatzin.meet-notes", category: "MeetingListViewModel")` — never `print()`

### Database Model (Already Exists)

`Infrastructure/Database/Meeting.swift` — GRDB record with:
- `id: String`, `title: String`, `startedAt: Date`, `endedAt: Date?`, `durationSeconds: Double?`
- `audioQuality: AudioQuality` (`.full`, `.micOnly`, `.partial`)
- `pipelineStatus: PipelineStatus` (`.recording`, `.transcribing`, `.transcribed`, `.summarizing`, `.complete`, `.failed`)
- `createdAt: Date`
- Explicit `Columns` enum and `CodingKeys` for snake_case mapping — already implemented

### ValueObservation Pattern

```swift
// CORRECT — live observation in ViewModel
let observation = ValueObservation.tracking { db in
    try Meeting.order(Meeting.Columns.startedAt.desc).fetchAll(db)
}
cancellable = observation.start(in: database.pool, scheduling: .immediate) { [weak self] meetings in
    Task { @MainActor in
        self?.allMeetings = meetings
        self?.recomputeSections()
    }
}
```

Use GRDB's `ValueObservation` with `scheduling: .immediate` so updates arrive on the cooperative thread pool, then hop to `@MainActor` to update `@Observable` properties. The `cancellable` must be stored to keep the observation alive.

### Temporal Grouping Logic

Compute sections client-side from `Meeting.startedAt`:
- **Today**: `Calendar.current.isDateInToday(meeting.startedAt)`
- **This Week**: Within last 7 days (use `Calendar.current.dateComponents`)
- **Older**: Group by month/year using `DateFormatter` with `"MMMM yyyy"` format
- Sections: `[(title: String, meetings: [Meeting])]` — computed property that recalculates when `allMeetings` changes

### UI Layout

```
NavigationSplitView {
    // Sidebar (240pt standard, collapses at <900pt)
    List(selection: $viewModel.selectedMeetingID) {
        ForEach(viewModel.sections) { section in
            Section(section.title) {
                ForEach(section.meetings) { meeting in
                    MeetingRowView(meeting: meeting)
                }
            }
        }
    }
    .searchable(text: $viewModel.searchQuery) // FTS5 search (Story 6.1 scope, stub binding now)
} detail: {
    if viewModel.selectedMeetingID != nil {
        // Placeholder for Story 4.4
        Text("Meeting Detail (Story 4.4)")
    } else {
        EmptyMeetingSelectionView()
    }
}
```

### MainWindowView Refactor

Current `MainWindowView` uses a simple `ZStack` + `VStack` for content. This story must replace the idle-state content area with `NavigationSplitView`. The recording and processing states should still show their existing views (hide sidebar during recording per UX spec).

**Key change**: When `recordingVM.state == .idle`, show `NavigationSplitView` with meeting list sidebar. When recording/processing, show existing recording/processing views.

### MeetingRowView (Dependency-Free Component)

Place in `UI/Components/MeetingRowView.swift` — must NOT depend on any ViewModel:

```swift
struct MeetingRowView: View {
    let title: String
    let date: Date
    let durationSeconds: Double?
    let pipelineStatus: Meeting.PipelineStatus
    // Closures for hover actions
    var onExport: (() -> Void)?
    var onCopySummary: (() -> Void)?
    var onDelete: (() -> Void)?
}
```

### Wiring in MeetNotesApp.swift

```swift
// In MeetNotesApp.init():
let meetingListVM = MeetingListViewModel(database: db, appErrorState: errorState)
_meetingListVM = State(initialValue: meetingListVM)

// In WindowGroup:
MainWindowView()
    .environment(meetingListVM)  // Add to existing environment chain
```

### Design Tokens

- All colors from `Color` extension (`.windowBg`, `.accent`, `.recordingRed`, `.onDeviceGreen`, `.warningAmber`)
- Row hover background: `Color(.sRGB, red: 0.137, green: 0.141, blue: 0.227)` — extract as `.rowHover` token if not exists
- Selected row: accent color at 15% opacity + 2pt left border
- Animations: ALWAYS guard with `@Environment(\.accessibilityReduceMotion)`

### Hover-Reveal Actions Pattern

```swift
@State private var isHovering = false

.onHover { hovering in isHovering = hovering }
.overlay(alignment: .trailing) {
    if isHovering {
        HStack(spacing: 4) {
            Button(action: onExport) { Image(systemName: "square.and.arrow.up") }
            Button(action: onCopySummary) { Image(systemName: "doc.on.doc") }
            Button(action: onDelete) { Image(systemName: "trash") }
        }
        .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .trailing)))
    }
}
```

### Previous Story Learnings (4.1 & 4.2)

- **Logger pattern**: Use `private nonisolated static let logger` on actor types (Swift 6.2 workaround). For `@MainActor` classes, use instance-level `private let logger`
- **Handler closure pattern**: Services communicate to ViewModels via `@MainActor @Sendable` handler closures, not direct references
- **AppDatabase convenience**: `readSetting(key:)` and `writeSetting(key:value:)` already exist
- **WhisperKit `@preconcurrency` import**: Already handled in TranscriptionService
- **`AVAudioPCMBuffer: @unchecked @retroactive Sendable`**: Already declared in Story 3.2, DO NOT redeclare
- **UI/Components rule**: Components must be dependency-free — pass data as value types and closures
- **ModelDownloadCard pattern**: Good reference for hover-action UI pattern in MeetingRowView
- **Test database**: Use `AppDatabase(try DatabasePool(path: ""))` for in-memory test databases
- **PipelineStatus enum**: Includes `.transcribed` case (added in 4.1, not in original schema)

### Project Structure Notes

Files to create:
```
Features/MeetingList/MeetingListViewModel.swift    # @Observable @MainActor final class
Features/MeetingList/MeetingListView.swift          # NavigationSplitView sidebar
UI/Components/MeetingRowView.swift                  # Dependency-free row component
MeetNotesTests/MeetingList/MeetingListViewModelTests.swift
```

Files to modify:
```
UI/MainWindow/MainWindowView.swift                  # Replace idle content with NavigationSplitView
App/MeetNotesApp.swift                              # Create + inject MeetingListViewModel
App/NavigationState.swift                           # Add selectedMeetingID if used for deep linking
```

Existing files (DO NOT recreate):
```
Infrastructure/Database/Meeting.swift               # Already has all needed fields + enums
Infrastructure/Database/AppDatabase.swift            # Already has pool + migrations
App/AppErrorState.swift                              # Already exists for error routing
UI/Components/ErrorBannerView.swift                  # Already exists for inline errors
```

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Epic-4-Story-4.3] — User story, acceptance criteria, technical requirements
- [Source: _bmad-output/planning-artifacts/architecture.md] — ViewModel pattern, GRDB ValueObservation, NavigationSplitView, three-layer error rule
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md] — Meeting row layout, temporal grouping, hover actions, empty state, search placement
- [Source: _bmad-output/planning-artifacts/prd.md#FR19-FR23] — Functional requirements for meeting history and search
- [Source: _bmad-output/project-context.md] — Swift 6 rules, @Observable pattern, design tokens, accessibility requirements
- [Source: _bmad-output/implementation-artifacts/4-1-whisperkit-transcription-pipeline.md] — Logger workaround, PipelineStatus.transcribed, segment pattern
- [Source: _bmad-output/implementation-artifacts/4-2-model-management-transcription-settings.md] — Handler closure pattern, UI/Components dependency-free rule, SettingsViewModel wiring

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6

### Debug Log References

- Pre-existing flaky tests in TranscriptionServiceTests (transcribeSavesSegmentsToDatabase, transcribeUpdatesPipelineStatusToTranscribing) — timing-related, not caused by this story

### Completion Notes List

- Created `MeetingListViewModel` with GRDB `ValueObservation` for live meeting data, temporal grouping (Today/This Week/Older by month-year), selection state, and delete functionality
- Created `MeetingListView` with `NavigationSplitView` sidebar, grouped sections, empty state, context menu, and delete confirmation dialog
- Created `MeetingRowView` as a dependency-free UI component with 2-line layout, pipeline status badge, hover-reveal action buttons, and VoiceOver accessibility labels
- Created `PipelineStatusBadge` component with per-status icons and color tokens
- Refactored `MainWindowView` to show `NavigationSplitView` when idle/error, existing recording/processing views otherwise
- Wired `MeetingListViewModel` into `MeetNotesApp.init()` with environment injection
- Added `databaseObservationFailed` case to `AppError` for DB observation error routing
- Added `deleteMeeting(id:)` to `AppDatabase` for write-ownership compliance
- All animations guarded with `@Environment(\.accessibilityReduceMotion)`
- Keyboard navigation via native `List(selection:)` with arrow keys and Return

### Change Log

- 2026-03-04: Implemented Story 4.3 — Meeting History List with NavigationSplitView sidebar, temporal grouping, hover actions, context menu, pipeline status indicators, accessibility, and comprehensive tests
- 2026-03-04: Code Review — Fixed 7 issues: added missing Rename context menu action (H1), added actionable CTA button to empty state (H2), added keyboard Delete support via onDeleteCommand (H3), changed delete error from databaseObservationFailed to meetingUpdateFailed (M2), added renameMeeting to ViewModel/AppDatabase, fixed misleading test name and added rename+delete tests (M3), added meetingUpdateFailed AppError case

### File List

New files:
- MeetNotes/MeetNotes/MeetNotes/Features/MeetingList/MeetingListViewModel.swift
- MeetNotes/MeetNotes/MeetNotes/Features/MeetingList/MeetingListView.swift
- MeetNotes/MeetNotes/MeetNotes/UI/Components/MeetingRowView.swift
- MeetNotes/MeetNotes/MeetNotesTests/MeetingList/MeetingListViewModelTests.swift

Modified files:
- MeetNotes/MeetNotes/MeetNotes/App/MeetNotesApp.swift (added MeetingListViewModel creation + environment injection)
- MeetNotes/MeetNotes/MeetNotes/UI/MainWindow/MainWindowView.swift (replaced idle content with NavigationSplitView, removed old ContentAreaView/ReadyToRecordView/PermissionsRequiredView)
- MeetNotes/MeetNotes/MeetNotes/App/AppError.swift (added databaseObservationFailed + meetingUpdateFailed cases)
- MeetNotes/MeetNotes/MeetNotes/Infrastructure/Database/AppDatabase.swift (added deleteMeeting + renameMeeting helpers)
- MeetNotes/MeetNotes/MeetNotes.xcodeproj/project.pbxproj (added new file references)
