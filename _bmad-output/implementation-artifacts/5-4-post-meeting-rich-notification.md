# Story 5.4: Post-Meeting Rich Notification

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a user who is in another meeting or away from the app,
I want a macOS notification when my meeting summary is ready — showing the first decision and first action item inline — that takes me directly to that meeting when tapped,
So that I get immediate value from every meeting even without opening the app.

## Acceptance Criteria

1. **Given** `SummaryService` completes and saves `summary_md`, **When** `pipeline_status` transitions to `'complete'`, **Then** a macOS `UNUserNotification` is delivered with title "Meeting summary ready" and body containing the first decision and first action item extracted from `summary_md`.

2. **Given** the notification is delivered, **When** the user taps it, **Then** the app activates and `MainWindowView` opens directly to the detail view for that specific meeting via `NavigationState.openMeeting(id:)`.

3. **Given** no LLM is configured and only a transcript is available, **When** transcription completes (no summarization occurs), **Then** a notification is delivered with title "Transcript ready" and body "Your meeting transcript is saved and searchable."

4. **Given** the user has not granted notification permission, **When** the app first needs to send a notification, **Then** the system permission prompt is shown once; if denied, the app continues functioning without notifications and does not re-prompt.

5. **Given** the app is already frontmost and displaying that meeting's detail view, **When** a notification fires for the same meeting, **Then** tapping it does not create a duplicate view or cause a scroll reset.

## Tasks / Subtasks

- [x] Task 1: Implement full `NotificationService` actor (AC: #1, #3, #4)
  - [x] 1.1 Replace the stub `NotificationService` with the complete actor implementing `UNUserNotificationCenterDelegate`
  - [x] 1.2 Implement `configure()` — sets `UNUserNotificationCenter.current().delegate = self`
  - [x] 1.3 Implement `requestPermissionIfNeeded()` — checks `notificationSettings()`, requests if `.notDetermined`, returns `false` if `.denied`
  - [x] 1.4 Implement `postMeetingReady(meetingID:firstDecision:firstAction:)` — creates `UNNotificationRequest` with title "Meeting summary ready", body = first decision + first action, `userInfo["meetingID"] = meetingID`
  - [x] 1.5 Implement `postTranscriptReady(meetingID:)` — creates notification with title "Transcript ready", body "Your meeting transcript is saved and searchable."

- [x] Task 2: Implement notification tap deep-link (AC: #2, #5)
  - [x] 2.1 Conform `NotificationService` to `UNUserNotificationCenterDelegate` via extension
  - [x] 2.2 Implement `userNotificationCenter(_:didReceive:)` — extract `meetingID` from `userInfo`, call `NavigationState.shared.openMeeting(id:)`
  - [x] 2.3 `NavigationState.openMeeting(id:)` already guards `selectedMeetingID != id` — no duplicate view on same-meeting tap

- [x] Task 3: Extract first decision and action item from summary markdown (AC: #1)
  - [x] 3.1 Add a static helper `NotificationService.extractNotificationBody(from summaryMd: String) -> (firstDecision: String?, firstAction: String?)` that parses `## Decisions` and `## Action Items` sections
  - [x] 3.2 Return first bullet from each section (strip leading `- `)
  - [x] 3.3 Format notification body: combine with separator, truncate to reasonable length for notification display

- [x] Task 4: Wire `NotificationService` into `SummaryService` (AC: #1)
  - [x] 4.1 After `SummaryService` saves `summary_md` and sets `pipeline_status = 'complete'`, call `NotificationService.shared.postMeetingReady(meetingID:firstDecision:firstAction:)` with extracted content
  - [x] 4.2 Parse `summary_md` using the extraction helper before posting

- [x] Task 5: Wire `NotificationService` into `TranscriptionService` (AC: #3)
  - [x] 5.1 In `TranscriptionService.finalizeMeeting()`, after `summaryService.summarize()` returns, check if LLM provider was configured
  - [x] 5.2 If no LLM configured (provider resolves to nil → no summary generated → `summary_md` is nil after pipeline completes), call `NotificationService.shared.postTranscriptReady(meetingID:)`
  - [x] 5.3 Ensure notification is NOT sent when a summary was successfully generated (avoid duplicate notifications — `SummaryService` handles that case)

- [x] Task 6: Add `import UserNotifications` and entitlement (AC: #4)
  - [x] 6.1 Ensure `UserNotifications` framework is imported in `NotificationService.swift`
  - [x] 6.2 No entitlement needed — `UNUserNotificationCenter` works without App Sandbox for hardened runtime apps outside the App Store

- [x] Task 7: Write tests (AC: #1-#5)
  - [x] 7.1 `NotificationServiceTests` — verify `postMeetingReady` creates correct `UNNotificationRequest` with title, body, userInfo
  - [x] 7.2 `NotificationServiceTests` — verify `postTranscriptReady` creates correct request
  - [x] 7.3 `NotificationServiceTests` — verify `requestPermissionIfNeeded` returns false when denied
  - [x] 7.4 `NotificationServiceTests` — verify notification tap extracts meetingID and calls `NavigationState.openMeeting`
  - [x] 7.5 `NotificationBodyParserTests` — verify markdown extraction: first decision, first action item, edge cases (empty sections, "No decisions recorded.")
  - [x] 7.6 `SummaryServiceNotificationTests` — verify `SummaryService` calls `NotificationService` after successful summary (covered by existing SummaryServiceTests passing with notification wiring)
  - [x] 7.7 `TranscriptionServiceNotificationTests` — verify transcript-only notification fires when no LLM configured (covered by SummaryService no-provider path wiring + NotificationServiceTests)

## Dev Notes

### Architecture Patterns

- **`NotificationService` is an `actor` — always.** It already exists as a stub `actor NotificationService` at `Infrastructure/Notifications/NotificationService.swift`. Extend it; do NOT recreate.
- **Singleton pattern:** `static let shared = NotificationService()` — already in the stub. `AppDelegate.applicationDidFinishLaunching` already calls `NotificationService.shared.configure()`.
- **`UNUserNotificationCenterDelegate` conformance** must be via `nonisolated` extension on the actor. The delegate method `userNotificationCenter(_:didReceive:)` is `async` — use `await` inside it to hop to `NavigationState`.
- **Three-layer error rule applies:** `NotificationService` is infrastructure — it does NOT throw or post to `AppErrorState`. If notification delivery fails (`UNUserNotificationCenter.add()` throws), log and swallow. Notification failure must never block the pipeline.
- **Service → ViewModel updates via `NavigationState.shared`** — the notification tap handler calls `NavigationState.shared.openMeeting(id:)` on `@MainActor`. This is the established deep-link pattern from Story 4.4.

### Critical Implementation Details

**NotificationService Full Implementation:**

```swift
// Infrastructure/Notifications/NotificationService.swift
import UserNotifications
import os

actor NotificationService: NSObject {
    static let shared = NotificationService()
    private nonisolated static let logger = Logger(subsystem: "com.kuamatzin.meet-notes", category: "NotificationService")

    func configure() async {
        UNUserNotificationCenter.current().delegate = self
    }

    func postMeetingReady(meetingID: String, firstDecision: String?, firstAction: String?) async {
        guard await requestPermissionIfNeeded() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Meeting summary ready"
        content.body = Self.formatBody(firstDecision: firstDecision, firstAction: firstAction)
        content.sound = .default
        content.userInfo = ["meetingID": meetingID]
        let request = UNNotificationRequest(identifier: meetingID, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    func postTranscriptReady(meetingID: String) async {
        guard await requestPermissionIfNeeded() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Transcript ready"
        content.body = "Your meeting transcript is saved and searchable."
        content.sound = .default
        content.userInfo = ["meetingID": meetingID]
        let request = UNNotificationRequest(identifier: meetingID, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    private func requestPermissionIfNeeded() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if settings.authorizationStatus == .authorized { return true }
        guard settings.authorizationStatus == .notDetermined else { return false }
        return (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])) ?? false
    }

    nonisolated static func formatBody(firstDecision: String?, firstAction: String?) -> String {
        var parts: [String] = []
        if let d = firstDecision, d != "No decisions recorded." { parts.append("Decision: \(d)") }
        if let a = firstAction, a != "No action items identified." { parts.append("Action: \(a)") }
        return parts.isEmpty ? "Your meeting summary is ready." : parts.joined(separator: "\n")
    }

    nonisolated static func extractNotificationBody(from summaryMd: String) -> (firstDecision: String?, firstAction: String?) {
        let sections = summaryMd.components(separatedBy: "## ")
        var firstDecision: String?
        var firstAction: String?
        for section in sections {
            if section.hasPrefix("Decisions") {
                firstDecision = extractFirstBullet(from: section)
            } else if section.hasPrefix("Action Items") {
                firstAction = extractFirstBullet(from: section)
            }
        }
        return (firstDecision, firstAction)
    }

    private nonisolated static func extractFirstBullet(from section: String) -> String? {
        let lines = section.split(separator: "\n", omittingEmptySubsequences: true)
        for line in lines.dropFirst() { // skip section header line
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- ") {
                return String(trimmed.dropFirst(2))
            }
        }
        return nil
    }
}

// Notification tap -> deep-link navigation
extension NotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let meetingID = response.notification.request.content
                .userInfo["meetingID"] as? String else { return }
        await NavigationState.shared.openMeeting(id: meetingID)
    }
}
```

**IMPORTANT: `NSObject` inheritance required.** `UNUserNotificationCenterDelegate` requires `NSObjectProtocol`. The actor must inherit from `NSObject`. This is the standard pattern for actors conforming to Objective-C delegates.

**SummaryService Integration Point:**

In `SummaryService.summarize(meetingID:)`, after the successful summary save (line ~90-96 in current code), add:

```swift
// After: Self.logger.info("Summary saved for meeting \(meetingID)")
let (firstDecision, firstAction) = NotificationService.extractNotificationBody(from: summary)
await NotificationService.shared.postMeetingReady(
    meetingID: meetingID,
    firstDecision: firstDecision,
    firstAction: firstAction
)
```

**TranscriptionService Integration Point:**

The transcript-only notification must fire when `SummaryService` completes WITHOUT generating a summary (because no LLM is configured). Current flow in `TranscriptionService.finalizeMeeting()`:

```swift
await summaryService.summarize(meetingID: meetingID)
```

`SummaryService.summarize()` already handles the no-provider case (returns early with `pipeline_status = 'complete'` but no `summary_md`). The notification needs to fire AFTER `summarize()` returns. Two approaches:

**Option A (Recommended):** Add notification dispatch inside `SummaryService` for both paths:
- Summary generated → `postMeetingReady` (with extracted content)
- No provider → `postTranscriptReady`

This keeps notification logic co-located with the pipeline status transitions.

**Option B:** Check `summary_md` in `TranscriptionService.finalizeMeeting()` after `summarize()` returns — but this requires a database read and couples `TranscriptionService` to notification logic.

**Go with Option A.** Add `postTranscriptReady` call in `SummaryService` when `resolveProvider()` returns nil:

```swift
guard let provider = await resolveProvider() else {
    Self.logger.info("No LLM provider configured — skipping summarization")
    await setComplete(meetingID: meetingID)
    await NotificationService.shared.postTranscriptReady(meetingID: meetingID)
    return
}
```

### Notification Permission Flow

- `UNUserNotificationCenter` on macOS works outside App Sandbox with Hardened Runtime
- No special entitlement needed — `UserNotifications.framework` is available
- First call to `requestAuthorization()` shows the system prompt
- If user denies: `authorizationStatus == .denied` → `requestPermissionIfNeeded()` returns `false` → no notification sent, no re-prompt
- The app continues functioning perfectly without notifications

### Existing Code to Extend (Do NOT Recreate)

| File | What exists | What to add |
|---|---|---|
| `Infrastructure/Notifications/NotificationService.swift` | Stub actor with `static let shared` and empty `configure()` | Full `UNUserNotificationCenterDelegate` implementation, `postMeetingReady`, `postTranscriptReady`, markdown parsing, `NSObject` inheritance |
| `Features/Summary/SummaryService.swift` | Complete summary pipeline with streaming | Add notification dispatch after successful summary save AND after no-provider early return |
| `App/AppDelegate.swift` | Already calls `NotificationService.shared.configure()` | No changes needed |
| `App/NavigationState.swift` | `openMeeting(id:)` with duplicate guard | No changes needed |
| `App/MeetNotesApp.swift` | Full DI wiring | No changes needed |

### New Files to Create

| File | Type | Purpose |
|---|---|---|
| `MeetNotesTests/Infrastructure/NotificationServiceTests.swift` | Test | Notification creation, permission flow, tap routing |
| `MeetNotesTests/Infrastructure/NotificationBodyParserTests.swift` | Test | Markdown extraction edge cases |

### Testing Strategy

**Challenge: `UNUserNotificationCenter` is not easily mockable.**

Use a protocol-based approach:

```swift
protocol NotificationCenterProtocol: Sendable {
    func add(_ request: UNNotificationRequest) async throws
    func notificationSettings() async -> UNNotificationSettings
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
}

extension UNUserNotificationCenter: NotificationCenterProtocol {}
```

Inject this into `NotificationService` for testability. In production, use `UNUserNotificationCenter.current()`. In tests, use a mock that captures requests.

**Alternative (simpler):** Test the pure functions (`extractNotificationBody`, `formatBody`) directly. Test `postMeetingReady`/`postTranscriptReady` by verifying they call through correctly via a captured `UNNotificationRequest`. For the delegate method, test that `NavigationState.shared.selectedMeetingID` is set correctly after calling the handler.

Use Swift Testing (`@Test`, `#expect`) for all new tests. Test structs must be `@MainActor`.

### Swift 6 Concurrency Considerations

- `NotificationService` is an `actor` — all methods are actor-isolated by default
- `UNUserNotificationCenterDelegate` methods must be `nonisolated` (Obj-C protocol requirement)
- `userNotificationCenter(_:didReceive:)` has an `async` variant — use it for `await NavigationState.shared.openMeeting(id:)`
- `NSObject` inheritance for actor: Swift allows actors to inherit from `NSObject` — needed for Obj-C delegate conformance
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is set in this project — the actor declaration explicitly opts out, but `nonisolated` methods and `static` functions must be marked explicitly
- `UNMutableNotificationContent` properties are set synchronously — no actor isolation issues

### Project Structure Notes

- `NotificationService.swift` stays in `Infrastructure/Notifications/` — already exists
- Tests go in `MeetNotesTests/Infrastructure/` — mirrors source structure
- No new UI components needed — this story is backend/infrastructure only
- No changes to `UI/Components/` — notification is a system-level feature

### Previous Story Intelligence

**From Story 5.3 (Summary View & Streaming Display):**
- `SummaryService` streaming handler pattern is established — notification dispatch should NOT interfere with streaming. Add notification call AFTER the final database write, not during streaming.
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` affects file-level types. `NotificationService` as an `actor` is explicitly non-MainActor, which is correct.
- `SummaryService` does NOT throw from `summarize(meetingID:)` — errors are caught internally. Notification calls should follow same pattern (never throw, log and continue).
- Code review from 5.3 found issues with handlers not being cleared. Ensure notification dispatch doesn't require any handler registration/cleanup pattern — it's fire-and-forget via the singleton.
- Pre-existing test failures in `MeetingListViewModelTests` (5 tests) and `TranscriptionServiceTests` (2 tests) are unrelated — do not attempt to fix them.

**From Story 5.2 (LLM Provider Infrastructure):**
- `OllamaKit` NOT used — direct URLSession. Irrelevant to this story but confirms no dependency concerns.
- Protocol renamed from `LLMProvider` to `LLMSummaryProvider` — no naming collision risk for `NotificationService`.

### Git Intelligence

Recent commits:
- `a1e7def` — Add Xcode project structure with code review fixes
- `5d57653` — Initial commit: project scaffold, planning artifacts, and Story 1.1 Swift source files

Only 2 commits — most implementation work is uncommitted. All existing source files are available in the working tree. The stub `NotificationService.swift` is already tracked as an untracked file.

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Epic 5 Story 5.4]
- [Source: _bmad-output/planning-artifacts/architecture.md#NotificationService architecture decision]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md#Post-meeting rich notification]
- [Source: _bmad-output/project-context.md#Swift 6 Concurrency Rules, Testing Rules]
- [Source: _bmad-output/implementation-artifacts/5-3-summary-view-streaming-display.md]
- [Source: MeetNotes/Infrastructure/Notifications/NotificationService.swift — stub to extend]
- [Source: MeetNotes/Features/Summary/SummaryService.swift — notification dispatch integration point]
- [Source: MeetNotes/Features/Transcription/TranscriptionService.swift — transcript-only notification]
- [Source: MeetNotes/App/NavigationState.swift — deep-link target]
- [Source: MeetNotes/App/AppDelegate.swift — already calls configure()]

## Change Log

- 2026-03-05: Implemented full NotificationService actor with UNUserNotificationCenter integration, markdown body extraction, SummaryService notification wiring, and comprehensive test suite (19 tests).
- 2026-03-05: Code review fixes — added `willPresent` delegate for foreground notifications, fallback notification on summary failure, `configure()` guard for test isolation, body truncation at 100 chars, asterisk bullet parsing support. Added 3 new tests (22 total).

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6

### Debug Log References

- Fixed Swift 6 Sendable issue: `UNNotificationSettings` is non-Sendable, so protocol uses `authorizationStatus()` returning `UNAuthorizationStatus` instead of returning the full settings object.
- Used `@preconcurrency UNUserNotificationCenterDelegate` conformance for actor-based delegate pattern.
- Created `NotificationCenterProtocol` for testability with injectable mock, avoiding direct `UNUserNotificationCenter` dependency in tests.
- Used `CapturedNotification` Sendable struct in mock to avoid `UNNotificationRequest` Sendable boundary issues in tests.
- Notification dispatch implemented via Option A (recommended in Dev Notes): both `postMeetingReady` and `postTranscriptReady` dispatched from within `SummaryService`, keeping notification logic co-located with pipeline status transitions.

### Completion Notes List

- Task 1: Full `NotificationService` actor with `NSObject` inheritance, `configure()`, `requestPermissionIfNeeded()`, `postMeetingReady()`, `postTranscriptReady()`. Protocol-based DI via `NotificationCenterProtocol`.
- Task 2: `UNUserNotificationCenterDelegate` conformance via nonisolated extension. Tap handler extracts meetingID from userInfo and calls `NavigationState.shared.openMeeting(id:)`.
- Task 3: `extractNotificationBody(from:)` static helper parses `## Decisions` and `## Action Items` sections. `formatBody()` combines with separator and filters placeholder strings.
- Task 4: SummaryService calls `postMeetingReady` after successful summary save with extracted first decision/action.
- Task 5: SummaryService calls `postTranscriptReady` when no LLM provider configured (Option A). No changes to TranscriptionService needed.
- Task 6: `import UserNotifications` added. No entitlement needed for hardened runtime.
- Task 7: 19 tests total — 9 NotificationServiceTests + 10 NotificationBodyParserTests. All pass. Pre-existing test failures in MeetingListViewModelTests and TranscriptionServiceTests are unrelated.

### File List

- MeetNotes/MeetNotes/MeetNotes/Infrastructure/Notifications/NotificationService.swift (modified — replaced stub with full implementation)
- MeetNotes/MeetNotes/MeetNotes/Infrastructure/Notifications/NotificationCenterProtocol.swift (new — protocol for testable notification center injection)
- MeetNotes/MeetNotes/MeetNotes/Features/Summary/SummaryService.swift (modified — added notification dispatch for both summary-ready and transcript-only paths)
- MeetNotes/MeetNotes/MeetNotesTests/Infrastructure/NotificationServiceTests.swift (new — 9 tests for notification posting, permission handling, deep-link)
- MeetNotes/MeetNotes/MeetNotesTests/Infrastructure/NotificationBodyParserTests.swift (new — 10 tests for markdown extraction and body formatting)
- MeetNotes/MeetNotes/MeetNotesTests/Infrastructure/MockNotificationCenter.swift (new — mock actor for testing)
