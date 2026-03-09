# Story 6.2: Remaining App Settings

Status: done

## Story

As a user who wants to fine-tune how meet-notes behaves,
I want a complete settings panel where I can select my transcription model size and configure whether the app launches at login,
so that I can tailor performance, storage use, and startup behavior to my workflow.

## Acceptance Criteria

1. **Settings > Transcription: Active model checkmark** — Given the user opens Settings > Transcription, when the model size section is shown, then the currently active model is visually indicated with a checkmark AND the user can select a different downloaded model (FR31).

2. **Settings > Transcription: Undownloaded model guard** — Given the user selects a model that has not been downloaded yet, when they tap "Set as active", then a prompt clarifies the model must be downloaded first AND the "Download" button in the card is highlighted (FR31).

3. **Settings > General: Launch-at-login toggle display** — Given the user opens Settings > General, when the launch-at-login toggle is visible, then it correctly reflects the current `SMAppService` registration state (FR32).

4. **Settings > General: Enable launch-at-login** — Given the user toggles launch-at-login ON, when the toggle switches, then `SMAppService.mainApp.register()` is called AND the app is added to Login Items.

5. **Settings > General: Disable launch-at-login** — Given the user toggles launch-at-login OFF, when the toggle switches, then `SMAppService.mainApp.unregister()` is called AND the app is removed from Login Items.

6. **Settings > General: No telemetry in v1.0** — Given Settings is opened, when the General section is viewed, then there is no telemetry, crash reporting, or analytics opt-in toggle present (NFR-S5).

## Tasks / Subtasks

- [x] Task 1: Add General section to SettingsView with launch-at-login toggle (AC: #3, #6)
  - [x] 1.1 Add `ServiceManagement` import and `SMAppService` integration in `SettingsViewModel`
  - [x] 1.2 Add `launchAtLogin: Bool` property to `SettingsViewModel` that reads current `SMAppService.mainApp.status`
  - [x] 1.3 Add `toggleLaunchAtLogin(_:)` method calling `register()`/`unregister()`
  - [x] 1.4 Add "General" section to `SettingsView` with Toggle bound to `launchAtLogin`
  - [x] 1.5 Ensure no telemetry/analytics toggles exist in General section (NFR-S5)

- [x] Task 2: Verify and fix active model checkmark behavior (AC: #1)
  - [x] 2.1 Audit `ModelDownloadCard` to confirm checkmark renders for `isSelected == true`
  - [x] 2.2 Verify `SettingsViewModel.selectedModel` correctly drives `isSelected` on each card
  - [x] 2.3 Test switching active model updates checkmark immediately

- [x] Task 3: Verify and fix undownloaded model guard (AC: #2)
  - [x] 3.1 Audit `selectModel(name:)` to confirm it blocks activation of undownloaded models
  - [x] 3.2 Verify UI shows prompt/highlight when user tries to set undownloaded model as active
  - [x] 3.3 Ensure "Download" button is visually highlighted in that scenario

- [x] Task 4: Write tests for launch-at-login (AC: #3, #4, #5)
  - [x] 4.1 Create protocol `LaunchAtLoginService` for testability (wraps SMAppService)
  - [x] 4.2 Create `StubLaunchAtLoginService` for unit tests
  - [x] 4.3 Write tests: initial state reflects registration, toggle ON calls register, toggle OFF calls unregister
  - [x] 4.4 Write test: error handling when register/unregister fails

- [x] Task 5: Write tests for model selection guard (AC: #1, #2)
  - [x] 5.1 Verify existing tests cover active model checkmark behavior
  - [x] 5.2 Add test for undownloaded model guard if missing

## Dev Notes

### What Already Exists (DO NOT REWRITE)

The settings infrastructure is extensively built out. These components are COMPLETE and tested:

- **`SettingsViewModel`** (`Features/Settings/SettingsViewModel.swift`): `@Observable @MainActor final class` with model selection, LLM provider config, Ollama endpoint, Cloud API key management. Has 27 passing tests.
- **`SettingsView`** (`Features/Settings/SettingsView.swift`): Two sections — Transcription (model cards) and Summary/LLM (provider picker, endpoint, API key). Uses design tokens, accessibility labels.
- **`ModelDownloadCard`** (`UI/Components/ModelDownloadCard.swift`): Reusable card showing model name, size, accuracy/speed badges, download progress, state machine (notDownloaded/downloading/downloaded/failed).
- **`ModelDownloadManager`** (`Features/Transcription/ModelDownloadManager.swift`): Actor managing downloads with retry, progress, speed/ETA.
- **`AppDatabase`** (`Infrastructure/Database/AppDatabase.swift`): `readSetting(key:)`/`writeSetting(key:value:)` async methods. Settings table with UPSERT.
- **`SecretsStore`** (`Infrastructure/Secrets/SecretsStore.swift`): Static struct for Keychain API key storage. `save`/`load`/`delete` for `LLMProviderKey`.
- **`AppError`** (`App/AppError.swift`): Enum with `bannerMessage`, `recoveryLabel`, `sfSymbol` for all error cases.

### What Needs to Be Added

**Primary work: Launch-at-login toggle (FR32)**

1. **SMAppService Integration** — Use `ServiceManagement.SMAppService` (macOS 13+):
   - Read state: `SMAppService.mainApp.status` returns `.enabled`, `.notRegistered`, `.notFound`, or `.requiresApproval`
   - Enable: `try SMAppService.mainApp.register()` — adds app to Login Items
   - Disable: `try SMAppService.mainApp.unregister()` — removes app from Login Items
   - State is OS-managed (not UserDefaults, not database)

2. **Protocol for testability** — `SMAppService` cannot be mocked directly. Create:
   ```swift
   protocol LaunchAtLoginService: Sendable {
       func isEnabled() -> Bool
       func register() throws
       func unregister() throws
   }
   ```
   Production impl wraps `SMAppService.mainApp`. Stub impl for tests.

3. **SettingsViewModel additions** — Add to existing class (DO NOT create new ViewModel):
   - `var launchAtLogin: Bool` — initialized from `SMAppService.mainApp.status == .enabled`
   - `func toggleLaunchAtLogin(_ enabled: Bool)` — calls register/unregister, posts `AppError` on failure
   - Accept `LaunchAtLoginService` as init dependency

4. **SettingsView General section** — Add third section below existing two:
   - Section header: "General"
   - Toggle: "Launch at login" with descriptive subtitle
   - No telemetry toggles (NFR-S5 compliance)

**Secondary work: Verify model selection AC compliance (FR31)**

The model selection UI (`ModelDownloadCard`) already shows checkmarks for selected models and has download state guards. Tasks 2-3 are verification + minor fixes if needed. The existing 27 tests in `SettingsViewModelTests` should cover most cases.

### Architecture Constraints (MUST FOLLOW)

- **Swift 6 strict concurrency** — All code must compile with `SWIFT_STRICT_CONCURRENCY = complete`
- **@Observable pattern only** — No `@Published`, no `ObservableObject`, no Combine
- **@MainActor on ViewModels** — SettingsViewModel is `@Observable @MainActor final class`
- **Three-layer error handling** — Service throws typed error -> ViewModel catches + maps to `AppError` -> View renders `ErrorBannerView`
- **Protocol-based DI** — All services injected via protocols for testability
- **Actor for services** — System service wrappers are actors or protocols (not `@MainActor`)
- **No UserDefaults for launch-at-login** — SMAppService manages its own state at OS level
- **Design tokens** — Use `Color.windowBg`, `Color.cardBg`, `Color.accent` etc. from design system
- **Accessibility** — All controls need `accessibilityLabel`, respect `reduceMotion`/`reduceTransparency`, minimum 44x44pt targets, keyboard navigable

### File Locations (MUST USE)

| File | Purpose |
|------|---------|
| `Features/Settings/SettingsViewModel.swift` | ADD launch-at-login properties and methods |
| `Features/Settings/SettingsView.swift` | ADD General section with toggle |
| `Features/Settings/LaunchAtLoginService.swift` | NEW: Protocol + production impl |
| `Features/Settings/StubLaunchAtLoginService.swift` | NEW: Test stub |
| `App/MeetNotesApp.swift` | ADD LaunchAtLoginService creation + injection into SettingsViewModel |
| `App/AppError.swift` | ADD `launchAtLoginFailed` case if needed |
| `MeetNotesTests/Settings/SettingsViewModelTests.swift` | ADD launch-at-login tests |

### Testing Standards

- **Framework**: Swift Testing (`@Test`, `#expect`) — NOT XCTest
- **Pattern**: Protocol-based mocks/stubs injected into ViewModel
- **Database**: Temp file-backed `AppDatabase` with UUID name, full migrator run
- **Naming**: `test<Feature>_<scenario>` or descriptive `@Test func` names
- **Existing stubs**: `StubModelDownloadManager`, `StubTranscriptionService` — follow same pattern for `StubLaunchAtLoginService`
- **Known failures**: 5 pre-existing failures in `MeetingListViewModelTests`, 2 in `TranscriptionServiceTests` — these are unrelated, ignore them

### Previous Story Intelligence (Story 6.1)

**Learnings to apply:**
- Move SwiftUI modifiers to Group level if they disappear on empty state
- Use design tokens (`Color.accent`) instead of hardcoded colors
- Add `AppError` cases for all failure modes with user-facing messages
- Increase test sleep durations for CI stability if using async delays
- Remove dead state properties immediately

**Code patterns established:**
- Cancellable `Task` pattern for debounced operations
- `@Environment(\.appErrorState)` for error display
- Tests use Swift Testing framework exclusively

### Project Structure Notes

- All file paths relative to `MeetNotes/MeetNotes/MeetNotes/`
- Tests at `MeetNotes/MeetNotes/MeetNotesTests/Settings/`
- One primary type per file, file named after type
- Entitlements may need `com.apple.developer.service-management` for SMAppService (verify in existing entitlements file)
- No `Info.plist` entry needed for SMAppService on macOS 13+

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Epic-6-Story-6.2]
- [Source: _bmad-output/planning-artifacts/architecture.md#Settings-Architecture]
- [Source: _bmad-output/planning-artifacts/architecture.md#NFR-S5-No-Telemetry]
- [Source: _bmad-output/implementation-artifacts/6-1-full-text-search-across-meetings.md#Dev-Notes]
- [Source: Features/Settings/SettingsViewModel.swift — existing 27-test suite]
- [Source: Features/Settings/SettingsView.swift — existing Transcription + LLM sections]
- [Source: Apple Developer Documentation: SMAppService]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6

### Debug Log References

None required.

### Completion Notes List

- Implemented `LaunchAtLoginService` protocol with `SMAppLaunchAtLoginService` production implementation wrapping `SMAppService.mainApp`
- Added `launchAtLogin` property and `toggleLaunchAtLogin(_:)` method to `SettingsViewModel` with protocol-based DI
- Added "General" section to `SettingsView` with launch-at-login toggle and descriptive subtitle
- No telemetry/analytics toggles present (NFR-S5 compliance verified)
- Added `launchAtLoginFailed` case to `AppError` with banner message, recovery label, SF symbol
- Created `StubLaunchAtLoginService` for unit tests following existing stub patterns
- Added 6 new tests: initial state reflection, toggle ON/OFF, error handling for register/unregister failures
- All 33 SettingsViewModel tests pass (27 existing + 6 new)
- Verified model checkmark renders correctly via `ModelDownloadCard` (AC #1)
- Verified undownloaded model guard blocks activation; Download button highlighted with `.borderedProminent` (AC #2)
- Existing test `selectModelIgnoresNotDownloadedModel` covers guard behavior (AC #2)
- Full regression suite: all pre-existing failures remain unchanged, no new regressions

### File List

- MeetNotes/MeetNotes/MeetNotes/Features/Settings/LaunchAtLoginService.swift (NEW)
- MeetNotes/MeetNotes/MeetNotes/Features/Settings/SettingsViewModel.swift (NEW — replaced .gitkeep)
- MeetNotes/MeetNotes/MeetNotes/Features/Settings/SettingsView.swift (NEW — replaced .gitkeep)
- MeetNotes/MeetNotes/MeetNotes/App/AppError.swift (MODIFIED)
- MeetNotes/MeetNotes/MeetNotes/App/MeetNotesApp.swift (MODIFIED — explicit LaunchAtLoginService DI)
- MeetNotes/MeetNotes/MeetNotes/UI/Components/ModelDownloadCard.swift (MODIFIED — AC#2 download prompt)
- MeetNotes/MeetNotes/MeetNotesTests/Settings/StubLaunchAtLoginService.swift (NEW)
- MeetNotes/MeetNotes/MeetNotesTests/Settings/SettingsViewModelTests.swift (NEW — replaced .gitkeep)
- _bmad-output/implementation-artifacts/sprint-status.yaml (MODIFIED)

## Change Log

- 2026-03-05: Implemented launch-at-login toggle with SMAppService integration, General settings section, protocol-based DI for testability, and 6 new unit tests. Verified model selection AC compliance.
- 2026-03-05: Code review fixes — (H1) Added download prompt + Select button to ModelDownloadCard for AC#2 compliance, (H2) Explicit LaunchAtLoginService DI in MeetNotesApp.swift composition root, (M1) Corrected File List NEW/MODIFIED classifications, (M2) Added lock protection to StubLaunchAtLoginService mutable properties.
