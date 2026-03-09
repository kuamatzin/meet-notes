# Story 4.4: Meeting Transcript Detail View & Navigation Routing

Status: done

## Story

As a user reviewing a past meeting or arriving from an external trigger (e.g., a notification tap),
I want to open any meeting and read its full timestamped transcript in a clean, scrollable view — and for the app to navigate directly to any specific meeting when triggered from outside the view hierarchy,
So that I can find and read the exact words spoken at any point in a meeting, and external sources like notifications can always open the correct meeting immediately.

## Acceptance Criteria

1. Clicking a meeting in the sidebar opens `MeetingDetailView` in the detail pane; `MeetingDetailViewModel` loads all `TranscriptSegment` rows for that meeting via GRDB `ValueObservation` and displays them chronologically in `TranscriptView`
2. Each transcript segment shows its timestamp (`0:12:34`) and transcribed text at 13pt; speaker labels (if present) render bold in periwinkle `#5B6CF6` at 11pt
3. Text selection in the transcript surfaces a popover with three actions: "Copy", "Create Action Item", "Highlight"
4. When `pipeline_status == .transcribing`, a processing indicator (animated ellipsis `···` trailing the last segment) is shown and segments appear progressively as they are saved to the database
5. When `audio_quality == .micOnly` or `.partial`, a status badge in the detail header reads "Microphone only — system audio was unavailable"
6. `MeetingDetailViewModel` is `@Observable @MainActor final class` — no `ObservableObject`, no `@Published`, no `actor`
7. `NavigationState` (already exists as empty `@Observable @MainActor final class` with `static let shared`) gains `selectedMeetingID: String?` and `func openMeeting(id: String)` that calls `NSApp.activate(ignoringOtherApps: true)` and sets `selectedMeetingID`
8. When `NavigationState.selectedMeetingID` changes, `MeetingListView` sidebar selection updates and `MeetingDetailView` loads in the detail pane — no additional user action required
9. If `NavigationState.openMeeting(id:)` is called with the already-displayed meeting ID, no navigation change occurs (idempotent)
10. All animations guarded with `@Environment(\.accessibilityReduceMotion)`; materials fall back to solid colors when `accessibilityReduceTransparency` is enabled

## Tasks / Subtasks

- [x] Task 1: Implement NavigationState routing (AC: #7, #8, #9)
  - [x] 1.1 Add `selectedMeetingID: String?` property and `func openMeeting(id: String)` to existing `NavigationState` class
  - [x] 1.2 `openMeeting` calls `NSApp.activate(ignoringOtherApps: true)`, sets `selectedMeetingID` (no-op if already set to same ID)
  - [x] 1.3 Wire `NavigationState.selectedMeetingID` to `MeetingListViewModel.selectedMeetingID` via binding sync in `MainWindowView` or `MeetingListView`

- [x] Task 2: Create MeetingDetailViewModel (AC: #1, #4, #5, #6)
  - [x] 2.1 `@Observable @MainActor final class MeetingDetailViewModel` with `database: AppDatabase`, `appErrorState: AppErrorState`
  - [x] 2.2 Properties: `meeting: Meeting?`, `segments: [TranscriptSegment]`, `isTranscribing: Bool`
  - [x] 2.3 `func load(meetingID: String)` — starts `ValueObservation` on `TranscriptSegment` filtered by `meetingId == meetingID`, ordered by `startSeconds ASC`
  - [x] 2.4 Separate `ValueObservation` on `Meeting` row for live `pipelineStatus` and `audioQuality` updates
  - [x] 2.5 Cancel previous observations when loading a new meeting (store `DatabaseCancellable` refs)
  - [x] 2.6 Error handling: catch DB errors → post to `AppErrorState`

- [x] Task 3: Create TranscriptView (AC: #1, #2, #4)
  - [x] 3.1 `ScrollView` + `LazyVStack` displaying segments with timestamp + text
  - [x] 3.2 Timestamp formatting: `formatTimestamp(_ seconds: Double) -> String` producing `"0:12:34"` or `"12:34"` format
  - [x] 3.3 Processing indicator: when `isTranscribing`, show animated ellipsis `···` below last segment
  - [x] 3.4 Auto-scroll: follow new segments only when user is at bottom; show "Jump to live" badge when scrolled up (guarded by `reduceMotion`)
  - [x] 3.5 Segment entrance animation: `.opacity` fade in with `.easeIn(duration: 0.15)` (guarded by `reduceMotion`)

- [x] Task 4: Create MeetingDetailView (AC: #1, #5, #10)
  - [x] 4.1 Header: meeting title, date, duration, audio quality badge if `.micOnly`/`.partial`
  - [x] 4.2 Body: `TranscriptView` filling available space
  - [x] 4.3 Guard all materials with `accessibilityReduceTransparency` fallback

- [x] Task 5: Text selection popover (AC: #3)
  - [x] 5.1 Detect text selection in transcript and show popover with Copy / Create Action Item / Highlight
  - [x] 5.2 Copy action copies selected text to clipboard
  - [x] 5.3 Create Action Item and Highlight are stub actions (log intent, future story scope)

- [x] Task 6: Wire into MainWindowView + MeetingListView (AC: #1, #8)
  - [x] 6.1 Replace `Text("Meeting Detail (Story 4.4)")` placeholder in `MainWindowView` detail pane with `MeetingDetailView`
  - [x] 6.2 When `selectedMeetingID` changes, call `meetingDetailVM.load(meetingID:)` via `.onChange`
  - [x] 6.3 Sync `NavigationState.selectedMeetingID` ↔ `MeetingListViewModel.selectedMeetingID`

- [x] Task 7: Wire MeetingDetailViewModel in MeetNotesApp (AC: #6)
  - [x] 7.1 Create `MeetingDetailViewModel` in `MeetNotesApp.init()` and inject via `.environment()`

- [x] Task 8: Tests (all ACs)
  - [x] 8.1 `MeetingDetailViewModelTests.swift`: load segments, live observation, transcribing state, error handling
  - [x] 8.2 `NavigationStateTests.swift`: openMeeting sets selectedMeetingID, idempotent call, initial nil state
  - [x] 8.3 Verify audio quality badge logic (micOnly → badge shown, full → no badge)

## Dev Notes

### Architecture Constraints

- **ViewModel pattern**: `@Observable @MainActor final class MeetingDetailViewModel` — NEVER `ObservableObject`, `@Published`, or `actor`
- **Database reads**: Use `ValueObservation.tracking` for live reactive data. NEVER poll with `Timer`. ViewModels are strictly read-only — no `pool.write`
- **Error handling**: Three-layer rule — service throws → ViewModel catches → posts to `AppErrorState` → View renders `ErrorBannerView`
- **Swift 6 concurrency**: `SWIFT_STRICT_CONCURRENCY = complete`. No Combine. No `@StateObject`
- **Logging**: `private let logger = Logger(subsystem: "com.kuamatzin.meet-notes", category: "MeetingDetailViewModel")` — never `print()`
- **context7 MCP**: Before writing ANY GRDB code, fetch current GRDB docs via `mcp__context7__resolve-library-id` then `mcp__context7__query-docs`

### Database Models (Already Exist — DO NOT Recreate)

**`Infrastructure/Database/TranscriptSegment.swift`:**
```swift
struct TranscriptSegment: Codable, Identifiable, FetchableRecord, PersistableRecord, Sendable {
    var id: Int64?
    var meetingId: String
    var startSeconds: Double
    var endSeconds: Double
    var text: String
    var confidence: Double?

    enum CodingKeys: String, CodingKey {
        case id, text, confidence
        case meetingId = "meeting_id"
        case startSeconds = "start_seconds"
        case endSeconds = "end_seconds"
    }

    static let databaseTableName = "segments"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let meetingId = Column(CodingKeys.meetingId)
        static let startSeconds = Column(CodingKeys.startSeconds)
        static let endSeconds = Column(CodingKeys.endSeconds)
        static let text = Column(CodingKeys.text)
        static let confidence = Column(CodingKeys.confidence)
    }
}
```

**`Infrastructure/Database/Meeting.swift`:**
```swift
struct Meeting: Codable, Identifiable, FetchableRecord, PersistableRecord, Sendable {
    var id: String
    var title: String
    var startedAt: Date
    var endedAt: Date?
    var durationSeconds: Double?
    var audioQuality: AudioQuality
    var summaryMd: String?
    var pipelineStatus: PipelineStatus
    var createdAt: Date

    enum AudioQuality: String, Codable, Sendable { case full; case micOnly = "mic_only"; case partial }
    enum PipelineStatus: String, Codable, Sendable { case recording; case transcribing; case transcribed; case summarizing; case complete; case failed }
}
```

### ValueObservation Pattern for Segments

```swift
// Load segments for a specific meeting — live observation
let observation = ValueObservation.tracking { db in
    try TranscriptSegment
        .filter(TranscriptSegment.Columns.meetingId == meetingID)
        .order(TranscriptSegment.Columns.startSeconds.asc)
        .fetchAll(db)
}
segmentsCancellable = observation.start(in: database.pool, scheduling: .immediate) { [weak self] segments in
    Task { @MainActor in
        self?.segments = segments
    }
}

// Observe meeting row for pipelineStatus changes
let meetingObservation = ValueObservation.tracking { db in
    try Meeting.fetchOne(db, id: meetingID)
}
meetingCancellable = meetingObservation.start(in: database.pool, scheduling: .immediate) { [weak self] meeting in
    Task { @MainActor in
        self?.meeting = meeting
        self?.isTranscribing = meeting?.pipelineStatus == .transcribing
    }
}
```

Store both `DatabaseCancellable` refs as instance properties. Cancel them in `load(meetingID:)` before starting new observations (prevents stale data from a previously selected meeting).

### NavigationState Implementation

**File**: `App/NavigationState.swift` (already exists — modify, do NOT recreate)

Current state is an empty class:
```swift
@Observable @MainActor final class NavigationState {
    @MainActor static let shared = NavigationState()
}
```

Add:
```swift
@Observable @MainActor final class NavigationState {
    @MainActor static let shared = NavigationState()

    var selectedMeetingID: String?

    func openMeeting(id: String) {
        guard selectedMeetingID != id else { return }  // Idempotent
        selectedMeetingID = id
        NSApp.activate(ignoringOtherApps: true)
    }
}
```

This is already injected into the environment in `MeetNotesApp.swift` (line 14: `navigationState: NavigationState.shared`). The `openMeeting(id:)` method will be called by `NotificationService` in Story 5.4 for deep-link routing.

### Navigation Sync Pattern

`MeetingListViewModel.selectedMeetingID` currently drives sidebar selection. `NavigationState.selectedMeetingID` is the app-wide navigation target (used by external triggers like notifications). These must stay in sync:

**Option**: In `MeetingListView` or `MainWindowView`, use `.onChange(of:)` to sync bidirectionally:
```swift
.onChange(of: navigationState.selectedMeetingID) { _, newValue in
    if let newValue, viewModel.selectedMeetingID != newValue {
        viewModel.selectedMeetingID = newValue
    }
}
.onChange(of: viewModel.selectedMeetingID) { _, newValue in
    navigationState.selectedMeetingID = newValue
}
```

This ensures sidebar clicks update `NavigationState`, and external triggers (notifications) update the sidebar selection.

### MainWindowView Detail Pane Replacement

Current placeholder at `MainWindowView.swift` line ~62:
```swift
Text("Meeting Detail (Story 4.4)")
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .foregroundStyle(.secondary)
```

Replace with:
```swift
if let selectedID = viewModel.selectedMeetingID {
    MeetingDetailView()
        .onChange(of: selectedID) { _, newID in
            meetingDetailVM.load(meetingID: newID)
        }
        .onAppear { meetingDetailVM.load(meetingID: selectedID) }
} else {
    EmptyMeetingSelectionView()
}
```

### Transcript Timestamp Formatting

```swift
func formatTimestamp(_ totalSeconds: Double) -> String {
    let hours = Int(totalSeconds) / 3600
    let minutes = (Int(totalSeconds) % 3600) / 60
    let seconds = Int(totalSeconds) % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
    return String(format: "%d:%02d", minutes, seconds)
}
```

### UX Layout Specifications

**Detail View Layout (Standard mode 900-1399pt):**
- Header: meeting title (13pt Medium), date + duration (11pt Regular secondary), audio quality badge if applicable
- Body: Scrollable transcript with `LazyVStack`
- Summary section will be added in Story 5.3 (above transcript) — do NOT create `SummaryView` now

**Transcript Segment Row:**
- Timestamp: 11pt Regular, secondary color, leading aligned
- Text: 13pt Regular, primary color
- Confidence < 0.7: render in `.tertiaryLabel` color
- Entrance animation: `.opacity` with `.easeIn(duration: 0.15)` (guarded by `reduceMotion`)

**Processing Indicator:**
- Animated ellipsis `···` below last segment when `isTranscribing == true`
- No blocking modal — transcript grows in real time

**Audio Quality Badge:**
- Show when `meeting.audioQuality == .micOnly || .partial`
- Text: "Microphone only — system audio was unavailable"
- Style: `warningAmber` color, small badge

### Design Tokens (Already Defined in Color+DesignTokens.swift)

- `.windowBg`, `.cardBg`, `.accent` (#5B6CF6 periwinkle), `.recordingRed`, `.onDeviceGreen`, `.warningAmber`
- Elevated/hover background: `#23243A`
- Card border: `#2A2B3D`
- Text: use `.label`, `.secondaryLabel`, `.tertiaryLabel` (semantic)

### Text Selection Popover — Scope Note

SwiftUI does not have native text selection callback APIs. Implementation options:
1. **NSViewRepresentable wrapping NSTextView** — gives full selection delegate control, can detect selection range and show popover
2. **`.textSelection(.enabled)` + custom overlay** — limited, may not detect selection events reliably

Recommended: Use `NSViewRepresentable` with `NSTextView` for the transcript text, which provides `textViewDidChangeSelection(_:)` delegate. The popover shows Copy / Create Action Item / Highlight. "Create Action Item" and "Highlight" are stubs (log intent for future implementation).

If NSTextView integration proves too complex, an acceptable MVP is: make transcript text selectable with `.textSelection(.enabled)` and defer the popover to a follow-up. Document the decision.

### Previous Story Learnings (4.3 and earlier)

- **Logger pattern**: For `@MainActor` classes, use instance-level `private let logger` (not `nonisolated static`)
- **Handler closure pattern**: Services communicate to ViewModels via `@MainActor @Sendable` handler closures, not direct references
- **UI/Components rule**: Components must be dependency-free — pass data as value types and closures
- **Test database**: Use temp file-backed `AppDatabase` for tests requiring WAL mode (GRDB `DatabasePool` needs real files)
- **PipelineStatus enum**: Includes `.transcribed` case (added in Story 4.1, not in original schema)
- **ValueObservation scheduling**: Use `scheduling: .immediate` so updates arrive on cooperative thread pool, then hop to `@MainActor`
- **DatabaseCancellable**: Must be stored to keep observation alive; set to `nil` or reassign to cancel
- **MeetingRowView pattern**: Good reference for how dependency-free components receive data via value types + closures
- **MeetingListViewModel wiring**: Created in `MeetNotesApp.init()`, injected via `.environment()` — follow same pattern for `MeetingDetailViewModel`
- **AppDatabase write helpers**: `deleteMeeting(id:)` and `renameMeeting(id:newTitle:)` already exist — no new write methods needed for this story (read-only ViewModel)
- **Empty NavigationState**: Already exists at `App/NavigationState.swift` with `static let shared` and environment injection — just add properties

### Project Structure Notes

Files to create:
```
Features/MeetingDetail/MeetingDetailViewModel.swift     # @Observable @MainActor final class
Features/MeetingDetail/MeetingDetailView.swift           # Detail pane with header + transcript
Features/MeetingDetail/TranscriptView.swift              # Scrollable transcript segments
MeetNotesTests/MeetingDetail/MeetingDetailViewModelTests.swift
MeetNotesTests/MeetingDetail/NavigationStateTests.swift
```

Files to modify:
```
App/NavigationState.swift                                # Add selectedMeetingID + openMeeting(id:)
UI/MainWindow/MainWindowView.swift                       # Replace placeholder with MeetingDetailView
Features/MeetingList/MeetingListView.swift                # Sync NavigationState ↔ selectedMeetingID
App/MeetNotesApp.swift                                   # Create + inject MeetingDetailViewModel
```

Existing files (DO NOT recreate):
```
Infrastructure/Database/TranscriptSegment.swift          # Already has all fields + Columns enum
Infrastructure/Database/Meeting.swift                     # Already has PipelineStatus + AudioQuality enums
Infrastructure/Database/AppDatabase.swift                 # Already has pool + migrations
App/AppErrorState.swift                                   # Already exists for error routing
App/NavigationState.swift                                 # Already exists (empty shell) — MODIFY only
UI/Components/ErrorBannerView.swift                       # Already exists for inline errors
UI/Components/Color+DesignTokens.swift                    # Already has all design token colors
Features/MeetingList/MeetingListViewModel.swift            # Already has selectedMeetingID
```

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Epic-4-Story-4.4] — User story, acceptance criteria (BDD format)
- [Source: _bmad-output/planning-artifacts/architecture.md] — MeetingDetailViewModel spec, NavigationState pattern, ValueObservation, three-layer error rule, testing standards
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md] — Transcript segment layout (13pt text, 11pt timestamps), processing indicator, audio quality badge, text selection popover, responsive breakpoints, animation durations, accessibility requirements
- [Source: _bmad-output/planning-artifacts/prd.md#FR13,FR19-FR23] — Functional requirements for transcript display, meeting detail, search
- [Source: _bmad-output/project-context.md] — Swift 6 rules, @Observable pattern, GRDB rules, design tokens, accessibility requirements, context7 MCP mandate
- [Source: _bmad-output/implementation-artifacts/4-3-meeting-history-list.md] — Previous story learnings, ValueObservation pattern, MeetingListViewModel wiring, NavigationSplitView detail pane placeholder location

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6

### Debug Log References

- Initial build failed due to scroll ID type mismatch (String vs Int64?) and Timer.publish requiring Combine import (prohibited). Fixed by using string IDs for scroll anchors and TimelineView for animated ellipsis.

### Completion Notes List

- Task 1: Added `selectedMeetingID` and `openMeeting(id:)` to NavigationState with idempotent guard. Wired bidirectional sync between NavigationState and MeetingListViewModel via `.onChange` modifiers in MeetingListView.
- Task 2: Created MeetingDetailViewModel as `@Observable @MainActor final class` with dual ValueObservation (segments + meeting). Cancels previous observations on new meeting load. Error handling posts to AppErrorState.
- Task 3: Created TranscriptView with ScrollView + LazyVStack, timestamp formatting, processing indicator using TimelineView (no Combine), auto-scroll on new segments, and opacity transitions guarded by reduceMotion.
- Task 4: Created MeetingDetailView with header (title, date, duration, audio quality badge) and TranscriptView body. Materials guarded by accessibilityReduceTransparency.
- Task 5: Implemented text selection via NSViewRepresentable wrapping NSTextView with delegate for selection detection. Popover shows Copy (functional), Create Action Item (stub), Highlight (stub).
- Task 6: Replaced placeholder text in MeetingListView detail pane with MeetingDetailView. Added `.onChange` and `.onAppear` to trigger `load(meetingID:)`.
- Task 7: Created MeetingDetailViewModel in MeetNotesApp.init() and injected via `.environment()`.
- Task 8: Created 11 MeetingDetailViewModelTests (initial state, load segments, ordering, live observation, transcribing state, meeting loading, switching, error handling, audio quality) and 6 NavigationStateTests (initial nil, set ID, idempotent, change ID, direct set, clear to nil). All 17 tests pass.

### Change Log

- 2026-03-04: Implemented Story 4.4 — Meeting Transcript Detail View & Navigation Routing (all 8 tasks, 17 new tests)
- 2026-03-04: Code review fixes — H1: Added scroll position monitoring + "Jump to live" badge; H2: Fixed popover not dismissing on deselection; H3: Fixed segment entrance animation with `.animation` modifier; M1: Made `formatTimestamp` private; M2: Removed unnecessary NSScrollView wrapper from SelectableTextView; M4: Added missing MainWindowView.swift to File List; L1: Fixed test method typo; L2: Made DateFormatter static; L3: Replaced deprecated NSApp.activate(ignoringOtherApps:)

### File List

New files:
- MeetNotes/MeetNotes/MeetNotes/Features/MeetingDetail/MeetingDetailViewModel.swift
- MeetNotes/MeetNotes/MeetNotes/Features/MeetingDetail/MeetingDetailView.swift
- MeetNotes/MeetNotes/MeetNotes/Features/MeetingDetail/TranscriptView.swift
- MeetNotes/MeetNotes/MeetNotesTests/MeetingDetail/MeetingDetailViewModelTests.swift
- MeetNotes/MeetNotes/MeetNotesTests/MeetingDetail/NavigationStateTests.swift

Modified files:
- MeetNotes/MeetNotes/MeetNotes/App/NavigationState.swift
- MeetNotes/MeetNotes/MeetNotes/App/MeetNotesApp.swift
- MeetNotes/MeetNotes/MeetNotes/UI/MainWindow/MainWindowView.swift
- MeetNotes/MeetNotes/MeetNotes/Features/MeetingList/MeetingListView.swift
- _bmad-output/implementation-artifacts/sprint-status.yaml
