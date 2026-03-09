# Story 2.1: Permission Service & Runtime Monitoring

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a developer building meet-notes,
I want a centralized `PermissionService` that tracks microphone and screen recording TCC authorization status — including runtime revocation — and publishes changes to all consumers,
So that every feature can react to permission state without scattered `AVCaptureDevice.authorizationStatus()` checks, and the app never silently fails due to a revoked permission.

## Acceptance Criteria

1. **Given** the app launches, **when** `PermissionService` initializes, **then** it checks and publishes the current authorization status for both microphone and screen recording.

2. **Given** microphone permission is not yet granted, **when** `PermissionService.requestMicrophone()` is called, **then** it triggers the system microphone permission prompt and updates its published status on resolution.

3. **Given** screen recording permission is not yet granted, **when** `PermissionService.requestScreenRecording()` is called, **then** it opens System Settings → Privacy & Security → Screen Recording and updates status when the app regains focus (FR25).

4. **Given** a permission is revoked by the user in System Settings while the app is running, **when** the app regains focus or a periodic status check fires, **then** `PermissionService` updates its published status to `.denied` and all observing views receive the update.

5. **Given** `PermissionService` is declared `@Observable @MainActor`, **when** the Swift 6 concurrency checker runs, **then** there are zero actor isolation warnings.

## Tasks / Subtasks

- [x] **Task 1: Create PermissionStatus enum and PermissionChecking protocol** (AC: #1, #5)
  - [x] Create `PermissionStatus.swift` in `Infrastructure/Permissions/`
  - [x] Define enum cases: `.notDetermined`, `.authorized`, `.denied`, `.restricted`
  - [x] Add computed property `isGranted: Bool` (returns `true` only for `.authorized`)
  - [x] Create `PermissionChecking` protocol with `microphoneStatus`, `screenRecordingStatus` read properties and `requestMicrophone() async`, `requestScreenRecording()`, `refreshStatus()` methods

- [x] **Task 2: Create PermissionService with microphone permission support** (AC: #1, #2, #5)
  - [x] Create `PermissionService.swift` in `Infrastructure/Permissions/`
  - [x] Declare as `@Observable @MainActor final class PermissionService: PermissionChecking`
  - [x] Add `microphoneStatus: PermissionStatus` observable property (initial: `.notDetermined`)
  - [x] Add `screenRecordingStatus: PermissionStatus` observable property (initial: `.notDetermined`)
  - [x] Implement private `checkMicrophoneStatus()` mapping `AVCaptureDevice.authorizationStatus(for: .audio)` to `PermissionStatus`
  - [x] Implement `requestMicrophone() async` — calls `AVCaptureDevice.requestAccess(for: .audio)` and updates `microphoneStatus`
  - [x] Add `Logger(subsystem: "com.kuamatzin.meet-notes", category: "PermissionService")`
  - [x] Call `refreshStatus()` in `init()` for initial status check on creation

- [x] **Task 3: Add screen recording permission support** (AC: #3)
  - [x] Implement private `checkScreenRecordingStatus()` using `CGPreflightScreenCaptureAccess()` — maps `true` → `.authorized`, `false` → `.denied`
  - [x] Implement `requestScreenRecording()` — opens System Settings via `NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)`
  - [x] Wire into `refreshStatus()` alongside microphone check

- [x] **Task 4: Implement runtime permission monitoring** (AC: #4)
  - [x] Implement `startMonitoring()` that observes `NSApplication.didBecomeActiveNotification`
  - [x] On app activation, call `refreshStatus()` to re-check both permissions
  - [x] Detect transitions from `.authorized` to `.denied` and log revocation via Logger
  - [x] Implement `stopMonitoring()` to remove notification observer
  - [x] Store notification observer token for cleanup (omitted `deinit` due to Swift 6 strict concurrency — service lives for app lifetime, `stopMonitoring()` handles cleanup)

- [x] **Task 5: Integrate PermissionService into MeetNotesApp** (AC: #1)
  - [x] Add `@State private var permissionService = PermissionService()` in `MeetNotesApp`
  - [x] Inject via `.environment(permissionService)` into both `MenuBarExtra` and `WindowGroup` scenes
  - [x] Call `permissionService.startMonitoring()` via a `.task` modifier

- [x] **Task 6: Write comprehensive tests** (AC: #1–#5)
  - [x] Create `MeetNotesTests/Infrastructure/PermissionServiceTests.swift`
  - [x] Create `MockPermissionService` conforming to `PermissionChecking` for test injection
  - [x] Test: PermissionStatus enum `isGranted` returns correct values for all cases
  - [x] Test: MockPermissionService conforms to protocol and tracks state correctly
  - [x] Test: `requestMicrophone()` on mock updates `microphoneStatus`
  - [x] Test: `refreshStatus()` on mock can be called without error
  - [x] Test: status transitions are correctly tracked (authorized → denied detection)
  - [x] All tests use Swift Testing (`@Test`, `#expect`) — no XCTest

- [x] **Task 7: Verify build and all tests pass** (AC: #5)
  - [x] Build with zero warnings under `SWIFT_STRICT_CONCURRENCY = complete`
  - [x] Run full test suite — no regressions in existing tests (AppDatabase, SecretsStore)
  - [x] Verify zero actor isolation warnings

## Dev Notes

### Technical Requirements

**PermissionService Pattern — DELIBERATE ARCHITECTURE EXCEPTION:**

⚠️ `PermissionService` is `@Observable @MainActor final class`, NOT an `actor`. This is a deliberate exception to the "services are actors — always" rule from project-context.md. The architecture document explicitly specifies this because:
1. PermissionService must be directly observable by SwiftUI views (OnboardingView, error banners)
2. It wraps synchronous TCC check APIs — no long-running async work
3. It needs to publish status changes that SwiftUI can observe for automatic UI updates

**Microphone Permission API:**
```swift
import AVFoundation

// Check status (synchronous)
let status = AVCaptureDevice.authorizationStatus(for: .audio)
// Maps to: .notDetermined, .restricted, .denied, .authorized

// Request (async — Swift 6 compatible, do NOT use completion handler version)
let granted = await AVCaptureDevice.requestAccess(for: .audio)
```

**Screen Recording Permission API:**
```swift
import CoreGraphics

// Check status (synchronous) — returns Bool only, no .notDetermined distinction
let granted = CGPreflightScreenCaptureAccess()

// DO NOT use CGRequestScreenCaptureAccess() — deprecated in macOS 15.1
// Instead, open System Settings directly:
NSWorkspace.shared.open(URL(string:
    "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
```

Note: `CGPreflightScreenCaptureAccess()` was deprecated in macOS 15.1 but has **no replacement** for non-ScreenCaptureKit usage. meet-notes uses Core Audio Taps (not ScreenCaptureKit), so this remains the only available check API. Suppress deprecation warning if needed — the API still functions correctly on macOS 14.2+.

**System Settings Deep Links:**
```swift
// Microphone pane
URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
// Screen Recording pane
URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
```

**Runtime Monitoring Pattern:**
```swift
// No official revocation notification API before macOS 15.4
// Standard macOS pattern: re-check on app activation
NotificationCenter.default.addObserver(
    forName: NSApplication.didBecomeActiveNotification,
    object: nil,
    queue: .main
) { [weak self] _ in
    self?.refreshStatus()
}
```

### Architecture Compliance

**Mandatory patterns from architecture document:**

- **Type declaration:** `@Observable @MainActor final class PermissionService` — NOT `actor` (deliberate exception documented above)
- **Property naming:** `microphoneStatus`, `screenRecordingStatus` — use custom `PermissionStatus` enum, NOT boolean flags, NOT raw `AVAuthorizationStatus`
- **Logger:** `private let logger = Logger(subsystem: "com.kuamatzin.meet-notes", category: "PermissionService")` — file-scope, no `print()` ever
- **File location:** `Infrastructure/Permissions/PermissionService.swift` per architecture file tree
- **Protocol:** `PermissionChecking` protocol enables mock injection per testing rules
- **Environment injection:** Created once in `MeetNotesApp`, injected via `.environment()` into all scenes
- **Error boundary:** This service does NOT throw errors and does NOT post to `AppErrorState`. It purely tracks and publishes permission status. Error banners for denied permissions are handled by Story 2.3 (Missing Permission Recovery & Guidance). The `AppError.microphonePermissionDenied` / `.screenRecordingPermissionDenied` cases will be added when consumers need them.
- **No Combine:** Zero `import Combine`, zero `@Published`, zero `ObservableObject`. `@Observable` only.
- **Consumers (future stories):** `RecordingService` (gate check before starting capture — Story 3.x), `OnboardingView` (status display — Story 2.2). Both depend on the interface created here.

### Library & Framework Requirements

| Library | Import | Purpose | Notes |
|---|---|---|---|
| AVFoundation | `import AVFoundation` | Microphone authorization status + request | System framework, macOS 10.14+ |
| CoreGraphics | `import CoreGraphics` | `CGPreflightScreenCaptureAccess()` screen recording check | Deprecated macOS 15.1 but no replacement for Core Audio Taps |
| AppKit | `import AppKit` | `NSWorkspace.shared.open()` for System Settings, `NSApplication.didBecomeActiveNotification` | System framework |
| Observation | `import Observation` | `@Observable` macro | System framework, Swift 5.9+ |
| os | `import os` | `Logger` for structured logging | System framework |

**No external SPM dependencies needed for this story.** All APIs are system frameworks.

### File Structure Requirements

**New files to create:**

| File | Location | Type |
|---|---|---|
| `PermissionStatus.swift` | `MeetNotes/MeetNotes/MeetNotes/Infrastructure/Permissions/` | Swift enum + protocol |
| `PermissionService.swift` | `MeetNotes/MeetNotes/MeetNotes/Infrastructure/Permissions/` | `@Observable @MainActor final class` |
| `PermissionServiceTests.swift` | `MeetNotes/MeetNotes/MeetNotesTests/Infrastructure/` | Swift Testing tests |

**Files to modify:**

| File | Change |
|---|---|
| `MeetNotes/MeetNotes/MeetNotes/App/MeetNotesApp.swift` | Add `@State private var permissionService`, inject `.environment()`, start monitoring |

**Xcode auto-discovery:** `PBXFileSystemSynchronizedRootGroup` in Xcode 16+ auto-discovers new Swift files in existing directories. No manual pbxproj editing required (confirmed in Stories 1.2 and 1.3).

**Important:** The `Infrastructure/Permissions/` directory already exists in the project structure (created in Story 1.1). The `.gitkeep` placeholder was deleted in Story 1.2. Xcode maintains the directory via file synchronization.

### Testing Requirements

**Framework:** Swift Testing (`@Test`, `#expect`) — per project-context.md. Do NOT use XCTest.

**Test File:** `MeetNotesTests/Infrastructure/PermissionServiceTests.swift`

**Mock Pattern:**
```swift
@Observable @MainActor final class MockPermissionService: PermissionChecking {
    var microphoneStatus: PermissionStatus = .notDetermined
    var screenRecordingStatus: PermissionStatus = .notDetermined
    var requestMicrophoneCalled = false
    var requestScreenRecordingCalled = false
    var refreshStatusCalled = false

    func requestMicrophone() async {
        requestMicrophoneCalled = true
        microphoneStatus = .authorized
    }

    func requestScreenRecording() {
        requestScreenRecordingCalled = true
    }

    func refreshStatus() {
        refreshStatusCalled = true
    }
}
```

**Test cases to implement:**
1. `PermissionStatus.isGranted` returns `true` only for `.authorized`, `false` for all other cases
2. `MockPermissionService` conforms to `PermissionChecking` and tracks method calls
3. `requestMicrophone()` updates `microphoneStatus` on mock
4. `refreshStatus()` can be called and is trackable
5. Status transition detection: set `.authorized`, then change to `.denied`, verify transition

**Note:** Testing real TCC permission prompts is impossible in unit tests — `AVCaptureDevice.requestAccess(for:)` shows a system dialog. Tests validate the service's state management and protocol conformance using the mock. Real permission flow is validated manually or in UI tests (Story 2.2).

**Existing test patterns to follow:**
- `AppDatabaseTests.swift` — Swift Testing with `@Test`, `#expect`, `async` functions
- `SecretsStoreTests.swift` — tests for infrastructure services
- Test file naming: `{TypeName}Tests.swift`, one test file per source type

### Previous Story Intelligence

**From Story 1.3 (Automated Build & Distribution Pipeline):**
1. **PBXFileSystemSynchronizedRootGroup** — Xcode 16+ auto-discovers files. No manual pbxproj editing for new source files.
2. **Logger subsystem:** `"com.kuamatzin.meet-notes"` — established pattern, use exactly.
3. **Test target exists:** `MeetNotesTests` with Swift Testing framework. Tests go in `MeetNotesTests/Infrastructure/`.
4. **Info.plist was created** in Story 1.3 with Sparkle keys (`SUPublicEDKey`, `SUFeedURL`). Check if `NSMicrophoneUsageDescription` exists — if not, it must be added for microphone permission prompt to work.
5. **All builds use `SWIFT_STRICT_CONCURRENCY = complete`** — zero actor isolation warnings required.

**From Story 1.2 (App Database Foundation & Secrets Store):**
1. `.gitkeep` files removed from all directories including `Infrastructure/Permissions/`.
2. `SecretsStore` is a `struct` with static methods. `PermissionService` is different — it's an `@Observable` class with instance state.
3. Established `@Test` + `#expect` pattern in `SecretsStoreTests.swift` and `AppDatabaseTests.swift`.
4. **SwiftLintBuildToolPlugin** was fixed (not in Frameworks build phase). No action needed.

### Git Intelligence

**Recent commits (2 total):**
- `a1e7def` — Add Xcode project structure with code review fixes
- `5d57653` — Initial commit: project scaffold, planning artifacts, and Story 1.1 Swift source files

**Observations:**
- `Infrastructure/Permissions/` directory exists in project but is empty (`.gitkeep` deleted)
- No existing permission-related Swift code anywhere in the project
- Established `@Observable @MainActor final class` pattern visible in: `RecordingViewModel.swift`, `AppErrorState.swift`
- Environment injection pattern visible in `MeetNotesApp.swift`: `recordingVM`, `appErrorState`, `navigationState` all injected via `.environment()`
- Logger pattern used in `AppDatabase.swift`: `Logger(subsystem: "com.kuamatzin.meet-notes", category: "AppDatabase")`

### Latest Tech Information

**macOS Permission APIs (March 2026):**

1. **AVCaptureDevice (Microphone):** Stable, unchanged. `authorizationStatus(for: .audio)` + async `requestAccess(for: .audio)` are current. Fully Swift 6 concurrency compatible.

2. **CGPreflightScreenCaptureAccess():** Deprecated in macOS 15.1 (Sequoia) but has NO replacement for non-ScreenCaptureKit apps. meet-notes uses Core Audio Taps which require the TCC screen recording entry — ScreenCaptureKit's `SCContentSharingPicker` is NOT applicable. Continue using `CGPreflightScreenCaptureAccess()` and accept the deprecation warning.

3. **TCC Runtime Monitoring:** macOS 15.4+ introduced `ES_EVENT_TYPE_NOTIFY_TCC_MODIFY` in Endpoint Security framework, but it requires System Extension entitlement — not suitable for a normal app. The standard pattern remains: re-check on `NSApplication.didBecomeActiveNotification`. All production macOS apps use this approach.

4. **System Settings URL Schemes:** Stable since macOS 13+. Both `Privacy_Microphone` and `Privacy_ScreenCapture` anchors work on macOS 14.2+. URL format: `x-apple.systempreferences:com.apple.preference.security?<anchor>`.

### Project Structure Notes

- Aligns with architecture file tree: `Infrastructure/Permissions/PermissionService.swift`
- Uses the same environment injection pattern established in `MeetNotesApp.swift`
- Does NOT create or modify any database schemas
- Does NOT add any SPM dependencies
- Does NOT modify Info.plist (except possibly adding `NSMicrophoneUsageDescription` if missing) or entitlements
- This story creates the foundation — UI consumers (OnboardingView, error banners) come in Stories 2.2 and 2.3

### References

- PermissionService architecture: [Source: _bmad-output/planning-artifacts/architecture.md#Cross-Cutting Concerns Identified]
- PermissionService file tree: [Source: _bmad-output/planning-artifacts/architecture.md#Complete File Tree — "PermissionService.swift — @Observable @MainActor; TCC status for mic + screen recording; revocation detection"]
- Cross-component dependencies: [Source: _bmad-output/planning-artifacts/architecture.md — "PermissionService ←── RecordingService (gate), OnboardingView (status display)"]
- Implementation sequence step 4: [Source: _bmad-output/planning-artifacts/architecture.md — "PermissionService (RecordingService depends on it before starting capture)"]
- FR24–FR27 Onboarding & Permissions: [Source: _bmad-output/planning-artifacts/prd.md]
- Story 2.1 acceptance criteria: [Source: _bmad-output/planning-artifacts/epics.md#Story 2.1]
- UX onboarding journey: [Source: _bmad-output/planning-artifacts/ux-design-specification.md#Journey 1: First Launch & Onboarding]
- Permission error UX: [Source: _bmad-output/planning-artifacts/ux-design-specification.md#Error States — Permission Denied]
- Swift 6 concurrency rules: [Source: _bmad-output/project-context.md#Swift 6 Concurrency Rules]
- Testing rules: [Source: _bmad-output/project-context.md#Testing Rules]
- Environment injection pattern: [Source: _bmad-output/project-context.md#SwiftUI Rules]
- Previous story learnings: [Source: _bmad-output/implementation-artifacts/1-3-automated-build-distribution-pipeline.md#Dev Agent Record]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6

### Debug Log References

- Swift 6 `deinit` cannot access `@MainActor`-isolated properties. Removed `deinit` from PermissionService since it lives for the app's entire lifetime. `stopMonitoring()` provides explicit cleanup if ever needed.
- `CGPreflightScreenCaptureAccess()` deprecated in macOS 15.1 but no replacement exists for Core Audio Taps use case. Added `@available` annotation to suppress warning.

### Completion Notes List

- Created `PermissionStatus` enum with `.notDetermined`, `.authorized`, `.denied`, `.restricted` cases and `isGranted` computed property
- Created `PermissionChecking` protocol with `@MainActor` isolation for mock injection in tests
- Created `PermissionService` as `@Observable @MainActor final class` (deliberate architecture exception per spec)
- Implemented microphone permission check via `AVCaptureDevice.authorizationStatus(for: .audio)` and async request via `AVCaptureDevice.requestAccess(for: .audio)`
- Implemented screen recording check via `CGPreflightScreenCaptureAccess()` and request via System Settings deep link
- Implemented runtime monitoring via `NSApplication.didBecomeActiveNotification` with revocation detection and logging
- Integrated into `MeetNotesApp` with `@State` property, `.environment()` injection into both scenes, and `.task` modifier for monitoring startup
- Added `NSMicrophoneUsageDescription` to Info.plist (was missing — required for microphone permission prompt)
- All 6 new tests pass using Swift Testing (`@Test`, `#expect`), zero regressions in existing 13 tests (19 total)
- Zero actor isolation warnings under `SWIFT_STRICT_CONCURRENCY = complete`

### File List

**New files:**
- `MeetNotes/MeetNotes/MeetNotes/Infrastructure/Permissions/PermissionStatus.swift` — PermissionStatus enum + PermissionChecking protocol
- `MeetNotes/MeetNotes/MeetNotes/Infrastructure/Permissions/PermissionService.swift` — @Observable @MainActor PermissionService implementation
- `MeetNotes/MeetNotes/MeetNotesTests/Infrastructure/PermissionServiceTests.swift` — Tests + MockPermissionService

**Modified files:**
- `MeetNotes/MeetNotes/MeetNotes/App/MeetNotesApp.swift` — Added PermissionService @State, .environment() injection
- `MeetNotes/MeetNotes/MeetNotes/Info.plist` — Added NSMicrophoneUsageDescription (created in Story 1.3, modified here)
- `MeetNotes/MeetNotes/MeetNotes.xcodeproj/project.pbxproj` — Auto-updated by Xcode file synchronization

### Change Log

- 2026-03-03: Implemented Story 2.1 — Created PermissionService with microphone and screen recording permission checking, runtime monitoring via app activation notifications, and environment injection into MeetNotesApp. Added NSMicrophoneUsageDescription to Info.plist. 6 new tests, 19 total passing.
- 2026-03-04: Code review fixes — Moved startMonitoring() to PermissionService.init() (was tied to WindowGroup lifecycle, breaking AC4 for menu-bar-only launch). Removed force unwrap in requestScreenRecording() (SwiftLint violation). Added 4 real PermissionService integration tests. Renamed misleading test. Added explicit import Observation. Documented CGPreflightScreenCaptureAccess .notDetermined limitation for downstream stories. Updated File List with project.pbxproj. 10 new tests total (was 6).
