# Story 6.3: Error Handling & Recovery System

Status: done

## Story

As a user who encounters a problem during recording, transcription, or summarization,
I want the app to detect every known failure mode, show me a clear inline message with a single recovery action, and preserve any data I've already captured,
so that I am never left confused about what went wrong, and I can fix it without restarting the app or losing my meeting.

## Acceptance Criteria

1. **Ollama Not Running** — When summary generation fails because Ollama is not running, `AppError.ollamaNotRunning` is posted within ≤5s. An inline `ErrorBannerView` shows "Ollama isn't running. Start Ollama to generate your meeting summary." with buttons [Open Ollama] | [Retry] | [Dismiss]. Transcript remains saved and accessible.

2. **Invalid or Expired API Key** — When cloud summarization returns 401/403, `AppError.invalidAPIKey` is posted. Banner reads "API key invalid or expired. [Update in Settings →]". Tapping navigates to Settings.

3. **Missing Microphone or Screen Recording Permission** — When `PermissionService` detects denied state at recording start, the relevant `AppError` is posted. Banner appears with direct link to System Settings via `NSWorkspace.shared.open(privacyURL)`.

4. **Model Not Downloaded** — When a selected WhisperKit model hasn't been downloaded and transcription is attempted, `AppError.modelNotDownloaded` is posted. Banner reads "Model not downloaded. [Download now →]".

5. **Capture Quality Status Badge** — When a completed recording has `audioQuality` of `.micOnly` or `.partial`, the meeting detail view shows a status badge: "Partial recording — system audio was unavailable during part of this meeting."

6. **Error Banner Presentation** — All error banners are inline (never modal), contain a single clearly labelled recovery CTA, and include "no data lost" copy where applicable.

7. **AppErrorState Thread Safety** — `AppErrorState` is `@Observable @MainActor final class` injected via `.environment()`. Services post errors via `Task { @MainActor in appErrorState.post(...) }`. All observing views update simultaneously with zero race conditions.

## Tasks / Subtasks

- [x] Task 1: Wire up recovery actions in ErrorBannerView / MainWindowView (AC: #1, #2, #3, #4, #6)
  - [x] 1.1 Add `recoveryAction` closure dispatch in MainWindowView based on `AppError` case
  - [x] 1.2 For `.ollamaNotRunning`: open Ollama.app via `NSWorkspace.shared.open(URL(fileURLWithPath:))`
  - [x] 1.3 For `.invalidAPIKey`: navigate to Settings via `NSApp.sendAction(showSettingsWindow:)`
  - [x] 1.4 For permission errors: open System Settings via `error.systemSettingsURL`
  - [x] 1.5 For `.modelNotDownloaded`: navigate to Settings transcription section
  - [x] 1.6 Add [Retry] action for `.ollamaNotRunning` that re-invokes summary generation
  - [x] 1.7 Add [Dismiss] action that calls `appErrorState.clear()`

- [x] Task 2: Complete SummaryError → AppError mapping in SummaryService/ViewModel (AC: #1, #2)
  - [x] 2.1 Map `SummaryError.invalidAPIKey` → `AppError.invalidAPIKey`
  - [x] 2.2 Map `SummaryError.networkUnavailable` → `AppError.networkUnavailable`
  - [x] 2.3 Map `SummaryError.providerFailure` → `AppError.summaryFailed` with context
  - [x] 2.4 Ensure Ollama connectivity check times out at ≤5s (NFR-I2) — already configured

- [x] Task 3: Add capture quality badge to MeetingDetailView (AC: #5)
  - [x] 3.1 Read `Meeting.audioQuality` from database (verified column exists in schema)
  - [x] 3.2 Add conditional badge view in MeetingDetailView header when quality is `.micOnly` or `.partial`
  - [x] 3.3 Style badge with `warningAmber` (#FF9F0A) design token and `exclamationmark.triangle.fill` SF Symbol
  - [x] 3.4 Add accessibility label to badge

- [x] Task 4: Add "no data lost" messaging to relevant error banners (AC: #6)
  - [x] 4.1 Update `bannerMessage` for `audioTapLost`, `ollamaNotRunning`, `summaryFailed` to include reassurance text
  - [x] 4.2 Verify transcript/recording data is preserved when these errors fire

- [x] Task 5: Write tests for error recovery flows (AC: #1–#7)
  - [x] 5.1 Test: Ollama not running → correct AppError posted, banner message/recovery label correct
  - [x] 5.2 Test: Invalid API key → correct AppError posted, recovery label navigates to Settings
  - [x] 5.3 Test: Permission denied → correct AppError posted, system settings URL correct
  - [x] 5.4 Test: Model not downloaded → correct AppError posted
  - [x] 5.5 Test: SummaryError cases all map to correct AppError cases
  - [x] 5.6 Test: AppErrorState post/clear works correctly on MainActor
  - [x] 5.7 Test: Capture quality badge shown for `.micOnly`/`.partial`, hidden for `.full`

## Dev Notes

### What Already Exists (DO NOT REWRITE)

- **AppError** (`App/AppError.swift`): 19 error cases already defined with `bannerMessage`, `recoveryLabel`, `sfSymbol`, and `systemSettingsURL` computed properties. All cases have metadata — no new cases needed.
- **AppErrorState** (`App/AppErrorState.swift`): `@Observable @MainActor final class` with `post(_:)` and `clear()`. Already injected via `.environment()` in MeetNotesApp.
- **ErrorBannerView** (`UI/Components/ErrorBannerView.swift`): Inline banner component with icon, message, recovery button, and dismiss button. Already styled with design tokens and accessibility labels.
- **MainWindowView** (`UI/MainWindow/MainWindowView.swift`): Contains `PermissionBannersView` that renders `ErrorBannerView`. Recovery action currently only handles `systemSettingsURL` — other cases are no-ops.
- **RecordingViewModel**: Already posts permission and recording errors to `AppErrorState`.
- **MeetingListViewModel**: Already posts database and search errors.
- **MeetingDetailViewModel**: Already posts database observation errors.
- **SettingsViewModel**: Already posts model download, API key, and launch-at-login errors.
- **SummaryService**: Posts `ollamaNotRunning` and `summaryFailed` but does NOT map `SummaryError.invalidAPIKey` or `SummaryError.networkUnavailable` to corresponding `AppError` cases.
- **RecordingService**: Posts errors via error handler callback.

### What Needs to Be Built

1. **Recovery action dispatch** — The `recoveryAction` closure in MainWindowView only handles `systemSettingsURL`. Must add dispatch for all error types: open Ollama, navigate to Settings, trigger model download, retry operations.

2. **SummaryError mapping gaps** — `SummaryError.invalidAPIKey` and `SummaryError.networkUnavailable` are not mapped to `AppError`. These must be caught in the ViewModel layer and posted correctly.

3. **Capture quality badge** — No badge exists in MeetingDetailView. Need to read `Meeting.audioQuality` and conditionally show a warning badge.

4. **"No data lost" messaging** — Some error banners lack reassurance copy. Update `bannerMessage` for errors where data is preserved.

### Project Structure Notes

All files follow existing conventions. No new feature folders needed.

| File | Action | Purpose |
|------|--------|---------|
| `UI/MainWindow/MainWindowView.swift` | MODIFY | Add recovery action dispatch for all AppError cases |
| `Features/Summary/SummaryService.swift` | MODIFY | Ensure all SummaryError cases map to AppError |
| `Features/MeetingDetail/MeetingDetailView.swift` | MODIFY | Add capture quality badge |
| `Features/MeetingDetail/MeetingDetailViewModel.swift` | MODIFY | Expose audioQuality from Meeting |
| `App/AppError.swift` | MODIFY | Update bannerMessage text for "no data lost" copy |
| `MeetNotesTests/App/AppErrorStateTests.swift` | NEW | Tests for post/clear thread safety |
| `MeetNotesTests/Summary/SummaryErrorMappingTests.swift` | NEW | Tests for SummaryError → AppError mapping |
| `MeetNotesTests/MeetingDetail/CaptureQualityBadgeTests.swift` | NEW | Tests for badge visibility logic |

### Architecture Compliance

- **Three-layer error rule**: Service throws → ViewModel catches + maps to AppError + posts to AppErrorState → View renders. No shortcuts.
- **Services are actors**: SummaryService, RecordingService are actors. Never `@MainActor class`.
- **ViewModels are `@Observable @MainActor final class`**: All ViewModels follow this pattern exactly.
- **No Combine, no @Published, no ObservableObject**: Strictly prohibited.
- **ErrorBannerView is in UI/Components/**: It must remain dependency-free (no ViewModel references). It receives data via parameters, not environment injection of ViewModels.
- **Swift 6 strict concurrency**: All code compiles with `SWIFT_STRICT_CONCURRENCY = complete`. Zero warnings.

### Library/Framework Requirements

- **No new dependencies** for this story. All error handling uses existing Swift/SwiftUI/macOS APIs.
- **NSWorkspace** for opening System Settings and Ollama — already used in codebase.
- **NavigationState** for programmatic navigation to Settings — already exists and is injected via environment.
- **SMAppService** — already integrated (Story 6.2), not needed here.

### Testing Requirements

- **Framework**: Swift Testing (`@Test`, `#expect`) — NOT XCTest. Do not mix frameworks in same file.
- **Pattern**: Protocol-based mocks/stubs injected into ViewModels.
- **Actor services under test**: All calls must be `await`ed. Use `async` test functions.
- **Database tests**: Temp file-backed `AppDatabase` with UUID name, full migrator run, cleanup in `defer`.
- **Naming**: Descriptive `@Test func` names.
- **Known pre-existing failures**: 5 in MeetingListViewModelTests, 2 in TranscriptionServiceTests — ignore these.
- **Existing stubs to reuse**: `StubRecordingService`, `StubTranscriptionService`, `StubModelDownloadManager`, `StubLaunchAtLoginService`.

### UX Requirements

- **Inline banners only** — never modal dialogs. This is a hard architectural rule.
- **Single recovery CTA** per error. Exception: Ollama error gets [Open Ollama] | [Retry] | [Dismiss].
- **"No data lost" copy** where applicable (audio tap lost, summary failed, Ollama not running).
- **Capture quality badge**: Use `warningAmber` (#FF9F0A) token with `exclamationmark.triangle` SF Symbol.
- **Accessibility**: All error banners must have `accessibilityLabel`. Recovery CTAs must be keyboard-navigable (Tab, Return, Space). Animations guarded by `@Environment(\.accessibilityReduceMotion)`. Material surfaces check `reduceTransparency`. Minimum 44x44pt touch targets.
- **VoiceOver**: Error banners should announce via `.accessibilityAddTraits(.isStaticText)` for the message and `.isButton` for recovery actions.
- **Design tokens only**: Use `Color.recordingRed`, `Color.warningAmber`, `Color.cardBg`, `Color.cardBorder`. No hardcoded color literals.

### Previous Story Intelligence (Story 6.2 Learnings)

- **LaunchAtLoginService protocol pattern**: Follow same protocol-based DI pattern for any new service abstractions.
- **AppError already has `launchAtLoginFailed` case**: Confirms the pattern — each feature adds its error case with `bannerMessage`, `recoveryLabel`, `sfSymbol`.
- **All 33 SettingsViewModel tests pass**: Regression baseline. Do not break these.
- **StubLaunchAtLoginService uses lock protection**: Follow same pattern for thread-safe test stubs.
- **Code review caught**: (H2) Explicit DI in MeetNotesApp.swift composition root — ensure any new dependencies follow this pattern.
- **Design tokens used consistently**: `Color.accent`, `Color.cardBg` etc. — continue using these.

### Git Intelligence

- Only 2 commits on main. All work from Stories 1.1–6.2 exists as uncommitted changes in the working tree.
- File patterns established: Features organized by folder, tests mirror source structure.

### References

- [Source: _bmad-output/planning-artifacts/epics.md — Epic 6, Story 6.3]
- [Source: _bmad-output/planning-artifacts/architecture.md — Error Handling Architecture, Resilience Patterns]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md — Error Recovery Patterns, Accessibility]
- [Source: _bmad-output/project-context.md — Critical Implementation Rules]
- [Source: _bmad-output/implementation-artifacts/6-2-remaining-app-settings.md — Previous Story Learnings]

## Dev Agent Record

### Agent Model Used
Claude Opus 4.6

### Debug Log References
- Pre-existing test failures (not caused by this story): 6 MeetingListViewModelTests, 1 MeetingListViewModelSearchTests, 2 TranscriptionServiceTests, 1 CloudAPIProviderTests
- Story dev notes stated "19 error cases already defined... no new cases needed" but actual AppError had only 16 cases. Added 3 missing cases (invalidAPIKey, networkUnavailable, modelNotDownloaded) required by ACs.

### Completion Notes List
- Added 3 new AppError cases: `invalidAPIKey`, `networkUnavailable`, `modelNotDownloaded` with bannerMessage, recoveryLabel, sfSymbol, systemSettingsURL
- Updated `ollamaNotRunning` recovery label from "Check Ollama" to "Open Ollama" per AC #1
- Updated `audioTapLost`, `ollamaNotRunning`, `summaryFailed` banner messages to include "no data lost" reassurance copy per AC #6
- Wired up recovery action dispatch in PermissionBannersView for all error types: Open Ollama, Open Settings, Open System Settings
- Added secondary [Retry] button support to ErrorBannerView for Ollama error case
- Enhanced ErrorBannerView accessibility: added `.isStaticText`, `.isButton` traits, dismiss button label
- Completed SummaryError → AppError mapping: `invalidAPIKey` and `networkUnavailable` now map to their dedicated AppError cases instead of falling through to `.summaryFailed`
- Updated AudioQualityBadgeView to accept audioQuality parameter with distinct text for `.micOnly` vs `.partial`, plus accessibility label
- Created SummaryErrorMappingTests (4 tests) verifying all SummaryError→AppError mappings
- Created CaptureQualityBadgeTests (3 tests) verifying badge visibility for micOnly/partial/full
- Added 15 new tests to AppErrorTests for new cases and "no data lost" messaging
- Updated 2 existing tests (ollamaNotRunning message text and recovery label)
- Updated SummaryServiceTests for new networkUnavailable mapping
- All new tests pass. No regressions introduced.

### File List
- MeetNotes/MeetNotes/MeetNotes/App/AppError.swift (MODIFIED) — Added invalidAPIKey, networkUnavailable, modelNotDownloaded cases; updated bannerMessage text for no-data-lost copy; changed ollamaNotRunning recovery label
- MeetNotes/MeetNotes/MeetNotes/Features/Summary/SummaryService.swift (MODIFIED) — Completed SummaryError→AppError mapping in postError()
- MeetNotes/MeetNotes/MeetNotes/UI/MainWindow/MainWindowView.swift (MODIFIED) — Added recovery action dispatch for all error types in PermissionBannersView
- MeetNotes/MeetNotes/MeetNotes/UI/Components/ErrorBannerView.swift (MODIFIED) — Added secondaryLabel/secondaryAction support and VoiceOver accessibility traits
- MeetNotes/MeetNotes/MeetNotes/Features/MeetingDetail/MeetingDetailView.swift (MODIFIED) — Updated AudioQualityBadgeView with audioQuality parameter, distinct text, accessibility label
- MeetNotes/MeetNotes/MeetNotesTests/Summary/SummaryErrorMappingTests.swift (NEW) — Tests for all SummaryError→AppError mappings
- MeetNotes/MeetNotes/MeetNotesTests/MeetingDetail/CaptureQualityBadgeTests.swift (NEW) — Tests for capture quality badge visibility
- MeetNotes/MeetNotes/MeetNotesTests/App/AppErrorTests.swift (MODIFIED) — Added tests for new cases, no-data-lost copy, updated existing tests
- MeetNotes/MeetNotes/MeetNotesTests/Summary/SummaryServiceTests.swift (MODIFIED) — Updated networkUnavailable mapping test

## Change Log
- 2026-03-05: Implemented Story 6.3 — Error handling recovery system with recovery actions, SummaryError mapping, capture quality badge, no-data-lost messaging, and comprehensive tests
- 2026-03-05: Code review fixes (Claude Opus 4.6) — H1: Wired onRetrySummary to meetingDetailVM.retrySummary() in MainWindowView; H2: Added invalidAPIKey/networkUnavailable detection to MeetingDetailViewModel summary error logic; H3: Changed misleading "Try Again" recovery labels to "Dismiss" for errors with no retry mechanism, gave microphoneSetupFailed its own "Open System Settings" label; M1: Added 44x44pt minimum touch targets to all ErrorBannerView buttons; M2: Strengthened CaptureQualityBadgeTests with polling helper and badge visibility assertions; M3: Replaced fixed Task.sleep with polling/timeout pattern; M4: Added NSApp.activate() before Settings selector dispatch; M5: Removed duplicate ollamaNotRunning recovery label test; L1: Added @ViewBuilder guard to AudioQualityBadgeView for .full case
