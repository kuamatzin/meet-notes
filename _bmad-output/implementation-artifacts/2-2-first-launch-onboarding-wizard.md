# Story 2.2: First-Launch Onboarding Wizard

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a new user launching meet-notes for the first time,
I want a 3-step full-screen onboarding wizard that walks me through microphone and screen recording permission grants with plain-language explanations and an inline test recording,
So that I arrive ready for my first real meeting with full confidence that the app is working correctly — without needing any technical knowledge.

## Acceptance Criteria

1. **Given** the app launches and `hasCompletedOnboarding` is `false` in UserDefaults, **when** `MeetNotesApp` evaluates the launch gate, **then** the `OnboardingWizardView` is presented as a full-screen modal before the main window (FR24).

2. **Given** the wizard is on Step 1 (Welcome), **when** the user reads the screen, **then** they see the app name, the "Local only — your audio never leaves this Mac" privacy hero message, and a "Get started" CTA button.

3. **Given** the wizard is on Step 2 (Permissions), **when** it is presented, **then** microphone permission is requested first with a plain-English explanation of why it is needed (FR24), **and** after microphone is granted, screen recording permission is requested with an explicit explanation: "meet-notes uses Screen Recording to capture system audio from Zoom, Google Meet, and other apps. No screen is ever recorded." (FR25).

4. **Given** both permissions are granted on Step 2, **when** the user taps "Test Recording", **then** a short test recording starts, capturing a few seconds of microphone audio, and a live transcript snippet appears — confirming the pipeline works end-to-end before the first real meeting.
   - **SCOPE NOTE:** RecordingService (Epic 3) and TranscriptionService (Epic 4) do not exist yet. This AC is implemented as a **stub interface** (`OnboardingTestRecorder` protocol) with a simulated placeholder in this story. The real pipeline will be wired in when those services ship. The UI, button states, and progress flow must be fully functional — only the actual audio capture + transcription is stubbed.

5. **Given** the user reaches Step 3 (You're Ready), **when** they click "Start your first meeting", **then** `hasCompletedOnboarding` is set to `true` in UserDefaults, the onboarding modal is dismissed, and the main app window is shown.

6. **Given** the app is reinstalled and `hasCompletedOnboarding` is already `true`, **when** the app launches, **then** the onboarding wizard is skipped entirely.

7. **Given** the user wants to skip LLM configuration during onboarding, **when** prompted for LLM setup, **then** they can proceed without entering an API key or Ollama endpoint, and the app functions in transcript-only mode (FR27).
   - **SCOPE NOTE:** LLM configuration UI is deferred to Epic 5. This AC is satisfied by the wizard NOT requiring any LLM setup — transcript-only mode is the default. No LLM configuration step is shown in the wizard.

## Tasks / Subtasks

- [x] **Task 1: Create OnboardingStep enum and OnboardingTestRecorder protocol** (AC: #1, #4)
  - [x] Create `OnboardingStep.swift` in `Features/Onboarding/`
  - [x] Define `OnboardingStep` enum: `.welcome`, `.permissions`, `.ready`
  - [x] Create `OnboardingTestRecorder` protocol with `func runTestRecording() async -> TestRecordingResult` and `var isRecording: Bool { get }`
  - [x] Define `TestRecordingResult` enum: `.success(transcriptSnippet: String)`, `.failed(reason: String)`, `.unavailable`
  - [x] Create `SimulatedTestRecorder` conforming to `OnboardingTestRecorder` — returns `.unavailable` with a placeholder message ("Test recording will be available after audio services are configured"). This stub is replaced when RecordingService + TranscriptionService ship (Epic 3+4).

- [x] **Task 2: Create OnboardingViewModel** (AC: #1–#7)
  - [x] Create `OnboardingViewModel.swift` in `Features/Onboarding/`
  - [x] Declare as `@Observable @MainActor final class OnboardingViewModel`
  - [x] Add `currentStep: OnboardingStep` (initial: `.welcome`)
  - [x] Add `@AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding = false` — **IMPORTANT:** this must be a separate `@AppStorage` property, NOT on the ViewModel. The ViewModel reads/writes via a binding or direct `UserDefaults.standard` access. `@AppStorage` is a SwiftUI property wrapper only valid in Views. Use `UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")` in the ViewModel instead.
  - [x] Add `micPermissionGranted: Bool` computed from injected `PermissionService.microphoneStatus.isGranted`
  - [x] Add `screenPermissionGranted: Bool` computed from injected `PermissionService.screenRecordingStatus.isGranted`
  - [x] Add `testRecordingState: TestRecordingState` enum (`.idle`, `.recording`, `.completed(String)`, `.unavailable(String)`)
  - [x] Implement `advanceStep()` — moves `.welcome → .permissions → .ready`
  - [x] Implement `requestMicrophonePermission() async` — delegates to `PermissionService.requestMicrophone()`
  - [x] Implement `requestScreenRecordingPermission()` — delegates to `PermissionService.requestScreenRecording()`
  - [x] Implement `runTestRecording() async` — delegates to injected `OnboardingTestRecorder`
  - [x] Implement `completeOnboarding()` — sets `UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")`
  - [x] Accept `PermissionService` and `OnboardingTestRecorder` via `init` for testability
  - [x] Add `Logger(subsystem: "com.kuamatzin.meet-notes", category: "OnboardingViewModel")`

- [x] **Task 3: Create OnboardingWizardView — Step 1 (Welcome)** (AC: #2)
  - [x] Create `OnboardingWizardView.swift` in `Features/Onboarding/`
  - [x] Full-screen layout with centered content
  - [x] ProgressDots indicator at top showing 3 steps, current step highlighted with `.accent` color
  - [x] App icon or SF Symbol `mic.fill` hero (48×48pt, `.accent` tint)
  - [x] App name "meet-notes" in `.largeTitle` weight
  - [x] Privacy hero message: "Local only — your audio never leaves this Mac" in `.title3`, `.secondary` color
  - [x] "Get Started" primary CTA button: `.accent` fill, `.headline` weight, 44pt min height, 10pt corner radius
  - [x] Guard all animations with `@Environment(\.accessibilityReduceMotion)`

- [x] **Task 4: Create OnboardingWizardView — Step 2 (Permissions)** (AC: #3, #4)
  - [x] Permission cards for microphone and screen recording, shown sequentially
  - [x] **Microphone card:** SF Symbol `mic.fill`, plain-English explanation ("meet-notes needs microphone access to hear and transcribe your meetings"), "Grant Microphone Access" button that calls `viewModel.requestMicrophonePermission()`
  - [x] Green checkmark indicator when `micPermissionGranted` is `true`
  - [x] **Screen recording card:** SF Symbol `rectangle.inset.filled.and.person.filled`, explanation: "meet-notes uses Screen Recording to capture system audio from Zoom, Google Meet, and other apps. No screen is ever recorded.", "Open System Settings" button that calls `viewModel.requestScreenRecordingPermission()`
  - [x] Green checkmark indicator when `screenPermissionGranted` is `true`
  - [x] Screen recording card appears after microphone is granted (sequential reveal)
  - [x] **Test Recording section:** Appears when both permissions granted. "Test Recording" button → shows recording state → shows transcript snippet or unavailable message
  - [x] "Continue" button enabled only after both permissions are granted (test recording is optional for proceeding)

- [x] **Task 5: Create OnboardingWizardView — Step 3 (You're Ready)** (AC: #5)
  - [x] Success state with checkmark SF Symbol `checkmark.circle.fill` in `.onDeviceGreen`
  - [x] "You're ready!" heading in `.largeTitle`
  - [x] Supportive message: "meet-notes is set up and ready to capture your meetings" in `.title3`, `.secondary`
  - [x] "Start your first meeting" primary CTA button
  - [x] On tap: calls `viewModel.completeOnboarding()` which sets `hasCompletedOnboarding = true`

- [x] **Task 6: Implement launch gate in MeetNotesApp** (AC: #1, #6)
  - [x] Add `@AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false` to `MeetNotesApp`
  - [x] Present `OnboardingWizardView` as `.sheet(isPresented:)` bound to `!hasCompletedOnboarding` on the WindowGroup
  - [x] The sheet must be non-dismissible (no swipe-to-dismiss, no Escape key) — use `.interactiveDismissDisabled(true)`
  - [x] Create `OnboardingViewModel` in `MeetNotesApp`, inject `permissionService` and `SimulatedTestRecorder()`
  - [x] Inject `OnboardingViewModel` via `.environment()` into the sheet

- [x] **Task 7: Write comprehensive tests** (AC: #1–#7)
  - [x] Create `MeetNotesTests/Onboarding/OnboardingViewModelTests.swift`
  - [x] Create `MockTestRecorder` conforming to `OnboardingTestRecorder` for test injection
  - [x] Test: `currentStep` starts at `.welcome`
  - [x] Test: `advanceStep()` transitions `.welcome → .permissions → .ready`
  - [x] Test: `advanceStep()` at `.ready` does not advance further
  - [x] Test: `requestMicrophonePermission()` delegates to `MockPermissionService`
  - [x] Test: `requestScreenRecordingPermission()` delegates to `MockPermissionService`
  - [x] Test: `completeOnboarding()` sets UserDefaults `hasCompletedOnboarding` to `true`
  - [x] Test: `runTestRecording()` delegates to `MockTestRecorder` and updates `testRecordingState`
  - [x] Test: computed `micPermissionGranted` / `screenPermissionGranted` reflect PermissionService state
  - [x] All tests use Swift Testing (`@Test`, `#expect`) — no XCTest
  - [x] Reuse `MockPermissionService` from `PermissionServiceTests.swift` (already exists)

- [x] **Task 8: Verify build and all tests pass** (AC: all)
  - [x] Build with zero warnings under `SWIFT_STRICT_CONCURRENCY = complete`
  - [x] Run full test suite — no regressions in existing tests (AppDatabase, SecretsStore, PermissionService)
  - [x] Verify zero actor isolation warnings

## Dev Notes

### Technical Requirements

**OnboardingViewModel Pattern:**

`OnboardingViewModel` is `@Observable @MainActor final class` — same pattern as `RecordingViewModel`. It is NOT an actor. It holds wizard step state, delegates permission requests to `PermissionService`, and coordinates the test recording stub.

```swift
@Observable @MainActor final class OnboardingViewModel {
    var currentStep: OnboardingStep = .welcome
    var testRecordingState: TestRecordingState = .idle

    private let permissionService: PermissionService
    private let testRecorder: any OnboardingTestRecorder

    init(permissionService: PermissionService, testRecorder: any OnboardingTestRecorder = SimulatedTestRecorder()) {
        self.permissionService = permissionService
        self.testRecorder = testRecorder
    }

    var micPermissionGranted: Bool { permissionService.microphoneStatus.isGranted }
    var screenPermissionGranted: Bool { permissionService.screenRecordingStatus.isGranted }
    var allPermissionsGranted: Bool { micPermissionGranted && screenPermissionGranted }
}
```

**Launch Gate Pattern:**

The onboarding modal is presented via `@AppStorage` + `.sheet` in `MeetNotesApp`. This is the standard SwiftUI pattern for first-launch gating.

```swift
// In MeetNotesApp
@AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

// In WindowGroup body:
.sheet(isPresented: Binding(
    get: { !hasCompletedOnboarding },
    set: { if !$0 { hasCompletedOnboarding = true } }
)) {
    OnboardingWizardView()
        .interactiveDismissDisabled(true)
        .environment(onboardingVM)
}
```

**CRITICAL: `@AppStorage` vs `UserDefaults` in ViewModel:**

- `@AppStorage` is a SwiftUI property wrapper — it ONLY works in `View` or `App` structs. Do NOT use it in `OnboardingViewModel`.
- The ViewModel writes to UserDefaults directly: `UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")`
- The `@AppStorage` in `MeetNotesApp` automatically reacts to the UserDefaults change, dismissing the sheet.

**Test Recording Stub Architecture:**

The test recording depends on services that don't exist yet (Epic 3 RecordingService, Epic 4 TranscriptionService). The stub pattern:

```swift
@MainActor
protocol OnboardingTestRecorder {
    var isRecording: Bool { get }
    func runTestRecording() async -> TestRecordingResult
}

enum TestRecordingResult {
    case success(transcriptSnippet: String)
    case failed(reason: String)
    case unavailable
}

enum TestRecordingState {
    case idle
    case recording
    case completed(String)
    case unavailable(String)
}

@Observable @MainActor final class SimulatedTestRecorder: OnboardingTestRecorder {
    var isRecording = false

    func runTestRecording() async -> TestRecordingResult {
        .unavailable
    }
}
```

When RecordingService + TranscriptionService ship, a `LiveTestRecorder` conforming to `OnboardingTestRecorder` will replace `SimulatedTestRecorder`. The ViewModel and View code require zero changes.

**Screen Recording `.notDetermined` Limitation:**

Per Story 2.1 dev notes: `CGPreflightScreenCaptureAccess()` returns Bool only — it cannot distinguish `.notDetermined` from `.denied`. First-time users will see `screenRecordingStatus == .denied` until they grant access. The onboarding wizard must treat `.denied` as "not yet granted" for screen recording — do NOT show error messaging, show the grant prompt instead.

**Permission Sequential Flow:**

The UX spec requires microphone permission first, then screen recording. The screen recording card should appear/become interactive only AFTER microphone is granted. This prevents overwhelming the user with two permission requests simultaneously.

### Architecture Compliance

**Mandatory patterns from architecture document:**

- **OnboardingViewModel type:** `@Observable @MainActor final class OnboardingViewModel` — per architecture file tree comment: "wizard step state; permission status; test recording"
- **OnboardingView type:** `struct OnboardingWizardView: View` — per architecture file tree
- **File locations:** `Features/Onboarding/OnboardingViewModel.swift` and `Features/Onboarding/OnboardingView.swift` — per architecture file tree
- **Environment injection:** `OnboardingViewModel` created in `MeetNotesApp` and injected via `.environment()` — same pattern as `RecordingViewModel`, `AppErrorState`, `NavigationState`
- **PermissionService consumption:** The ViewModel reads `permissionService.microphoneStatus` and `permissionService.screenRecordingStatus` directly. Since `PermissionService` is `@Observable`, SwiftUI views observing the ViewModel will automatically re-render when permission status changes.
- **No Combine:** Zero `import Combine`, zero `@Published`, zero `ObservableObject`. `@Observable` only.
- **No `@StateObject` / `@ObservedObject`:** Views consume the ViewModel via `@Environment(OnboardingViewModel.self)`.
- **Logger:** `private let logger = Logger(subsystem: "com.kuamatzin.meet-notes", category: "OnboardingViewModel")` — file-scope, exact type name as category.
- **No `print()`:** Use `Logger` exclusively.
- **Design tokens only:** All colors from `Color+DesignTokens.swift` — use `.accent`, `.windowBg`, `.onDeviceGreen`, `.cardBg`, `.cardBorder`. No hardcoded color literals.
- **Accessibility:** Every `withAnimation` and `.animation()` must be guarded by `@Environment(\.accessibilityReduceMotion)`. Each wizard step announces "Step N of 3" via `.accessibilityLabel`. All permission buttons fully labelled.
- **View nesting depth:** No SwiftUI `body` exceeds 3 levels of nesting before extracting a named subview.
- **`UI/Components/` is dependency-free:** The `OnboardingWizardView` belongs in `Features/Onboarding/`, NOT in `UI/Components/`, because it depends on `OnboardingViewModel`.
- **Error boundary:** This story does NOT throw errors and does NOT post to `AppErrorState`. Permission denial is handled by the wizard UI flow (show grant buttons), not by error banners. Error banners for denied permissions during normal app usage come in Story 2.3.
- **Four ViewModel limit:** Architecture specifies four ViewModels: `RecordingViewModel`, `MeetingListViewModel`, `MeetingDetailViewModel`, `SettingsViewModel`. `OnboardingViewModel` is a **fifth** ViewModel — this is explicitly justified by the architecture file tree which lists `OnboardingViewModel.swift`. It exists only for the first-launch wizard and is not instantiated after onboarding completes.
- **Launch gate decision:** Architecture specifies `UserDefaults` boolean `hasCompletedOnboarding`. The `App` struct checks this on launch and presents the onboarding modal. On reinstall with permissions already granted and flag `true`, onboarding is skipped entirely.

### Library & Framework Requirements

| Library | Import | Purpose | Notes |
|---|---|---|---|
| SwiftUI | `import SwiftUI` | All views, `@AppStorage`, `.sheet`, `.environment()` | System framework |
| Observation | `import Observation` | `@Observable` macro for `OnboardingViewModel` | System framework, Swift 5.9+ |
| os | `import os` | `Logger` for structured logging | System framework |

**No external SPM dependencies needed for this story.** All APIs are system frameworks.

`PermissionService` (already implemented in Story 2.1) provides all permission checking and requesting. No direct `AVFoundation`, `CoreGraphics`, or `AppKit` imports are needed in onboarding files — those are encapsulated inside `PermissionService`.

**Do NOT import:**
- `Combine` — prohibited in this codebase
- `AVFoundation` — permission APIs are accessed through `PermissionService`, not directly
- `CoreGraphics` — same as above
- `AppKit` — `NSWorkspace.shared.open()` for System Settings is encapsulated in `PermissionService.requestScreenRecording()`

### File Structure Requirements

**New files to create:**

| File | Location | Type | Description |
|---|---|---|---|
| `OnboardingStep.swift` | `MeetNotes/MeetNotes/MeetNotes/Features/Onboarding/` | Enum + Protocol | `OnboardingStep` enum, `OnboardingTestRecorder` protocol, `TestRecordingResult` enum, `TestRecordingState` enum, `SimulatedTestRecorder` class |
| `OnboardingViewModel.swift` | `MeetNotes/MeetNotes/MeetNotes/Features/Onboarding/` | `@Observable @MainActor final class` | Wizard step state, permission status, test recording coordination |
| `OnboardingWizardView.swift` | `MeetNotes/MeetNotes/MeetNotes/Features/Onboarding/` | SwiftUI View | 3-step full-screen wizard: Welcome → Permissions → Ready |
| `OnboardingViewModelTests.swift` | `MeetNotes/MeetNotes/MeetNotesTests/Onboarding/` | Swift Testing tests | ViewModel logic + mock test recorder |

**Files to modify:**

| File | Change |
|---|---|
| `MeetNotes/MeetNotes/MeetNotes/App/MeetNotesApp.swift` | Add `@AppStorage("hasCompletedOnboarding")`, create `OnboardingViewModel`, present `.sheet`, inject environment |

**Directory creation:**

- `MeetNotes/MeetNotes/MeetNotes/Features/Onboarding/` — directory exists in the project structure (created in Story 1.1) but is empty. The `.gitkeep` was deleted in Story 1.2. Xcode's `PBXFileSystemSynchronizedRootGroup` auto-discovers new files.
- `MeetNotes/MeetNotes/MeetNotesTests/Onboarding/` — **new directory**, must be created. Xcode auto-discovers it.

**Xcode auto-discovery:** `PBXFileSystemSynchronizedRootGroup` in Xcode 16+ auto-discovers new Swift files in existing directories. No manual `project.pbxproj` editing required (confirmed in Stories 1.2, 1.3, and 2.1).

**File naming convention:** One primary type per file. File name = primary type name exactly. `OnboardingStep.swift` contains the step enum plus closely related protocol/enums used only by the onboarding feature — this is acceptable per the "nested helpers used only by that type may co-locate" rule.

### Testing Requirements

**Framework:** Swift Testing (`@Test`, `#expect`) — per project-context.md. Do NOT use XCTest.

**Test File:** `MeetNotesTests/Onboarding/OnboardingViewModelTests.swift`

**Mock Dependencies:**

1. **`MockPermissionService`** — already exists in `MeetNotesTests/Infrastructure/PermissionServiceTests.swift`. Reuse it. It conforms to `PermissionChecking` and tracks `requestMicrophoneCalled`, `requestScreenRecordingCalled`, `refreshStatusCalled`. Import consideration: `MockPermissionService` is defined in the test target already, so it's directly accessible. However, `OnboardingViewModel` takes a concrete `PermissionService`, not the protocol. Two options:
   - **Option A (recommended):** Change `OnboardingViewModel.init` to accept `PermissionChecking` protocol instead of concrete `PermissionService`. This follows the project's protocol-based DI testing pattern.
   - **Option B:** Create `OnboardingViewModel` with concrete `PermissionService` and test with a real `PermissionService` instance. Less ideal — real TCC calls in tests.
   - **Choose Option A** — it follows the architecture's "protocol-based dependency injection enables mocking" rule.

2. **`MockTestRecorder`** — new mock conforming to `OnboardingTestRecorder`:
```swift
@Observable @MainActor final class MockTestRecorder: OnboardingTestRecorder {
    var isRecording = false
    var runTestRecordingCalled = false
    var resultToReturn: TestRecordingResult = .unavailable

    func runTestRecording() async -> TestRecordingResult {
        runTestRecordingCalled = true
        return resultToReturn
    }
}
```

**Test cases to implement:**

| # | Test | Validates |
|---|---|---|
| 1 | `currentStep` starts at `.welcome` | Initial state |
| 2 | `advanceStep()` from `.welcome` → `.permissions` | Step transition |
| 3 | `advanceStep()` from `.permissions` → `.ready` | Step transition |
| 4 | `advanceStep()` from `.ready` does not change step | Boundary guard |
| 5 | `requestMicrophonePermission()` delegates to mock and updates status | AC #3, permission flow |
| 6 | `requestScreenRecordingPermission()` delegates to mock | AC #3, permission flow |
| 7 | `micPermissionGranted` reflects mock service `.authorized` status | Computed property |
| 8 | `screenPermissionGranted` reflects mock service `.authorized` status | Computed property |
| 9 | `allPermissionsGranted` returns `true` only when both granted | Compound check |
| 10 | `completeOnboarding()` sets UserDefaults `hasCompletedOnboarding` to `true` | AC #5, launch gate |
| 11 | `runTestRecording()` delegates to mock and sets `testRecordingState` to `.unavailable` | AC #4, stub behavior |
| 12 | `runTestRecording()` with mock returning `.success` sets `testRecordingState` to `.completed` | AC #4, future wiring |

**UserDefaults isolation in tests:**

Tests that write to `UserDefaults.standard` must clean up after themselves. Use a `defer` block or a custom `UserDefaults(suiteName:)` for test isolation:

```swift
@Test func completeOnboardingSetsFlag() async {
    let suiteName = "test-onboarding-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { UserDefaults.removePersistentDomain(forName: suiteName) }

    let vm = OnboardingViewModel(
        permissionService: MockPermissionService(),
        testRecorder: MockTestRecorder(),
        userDefaults: defaults
    )
    vm.completeOnboarding()
    #expect(defaults.bool(forKey: "hasCompletedOnboarding") == true)
}
```

This means `OnboardingViewModel.init` should accept an optional `UserDefaults` parameter (defaulting to `.standard`) for testability.

**Existing test patterns to follow:**
- `PermissionServiceTests.swift` — Swift Testing with `@Test`, `#expect`, `@MainActor` functions, `MockPermissionService`
- `AppDatabaseTests.swift` — async tests, temp file cleanup in `defer`
- `SecretsStoreTests.swift` — infrastructure service tests
- Test file naming: `{TypeName}Tests.swift`

**No UI tests in this story.** `OnboardingFlowTests.swift` (listed in architecture file tree under `MeetNotesUITests/`) is a UI test for the full wizard flow — it is NOT part of this story's unit test scope. It may be created in a future QA story.

### Previous Story Intelligence

**From Story 2.1 (Permission Service & Runtime Monitoring) — DIRECT DEPENDENCY:**

1. **PermissionService is `@Observable @MainActor final class`** — deliberate architecture exception (NOT an actor). Already injected into all scenes via `.environment(permissionService)` in `MeetNotesApp.swift`. The onboarding wizard consumes it via `@Environment(PermissionService.self)` or by injecting into the ViewModel.

2. **PermissionChecking protocol** exists at `Infrastructure/Permissions/PermissionStatus.swift` — defines `microphoneStatus`, `screenRecordingStatus`, `requestMicrophone() async`, `requestScreenRecording()`, `refreshStatus()`. Use this for DI in `OnboardingViewModel`.

3. **MockPermissionService** exists in `MeetNotesTests/Infrastructure/PermissionServiceTests.swift` — conforms to `PermissionChecking`, tracks method calls. Reuse directly in `OnboardingViewModelTests`.

4. **`CGPreflightScreenCaptureAccess()` `.notDetermined` limitation** — returns Bool only. First-time users see `screenRecordingStatus == .denied` until they grant. The wizard must treat `.denied` as "not yet granted" and show the grant prompt, NOT an error state.

5. **`NSMicrophoneUsageDescription`** was added to `Info.plist` in Story 2.1. No further Info.plist changes needed.

6. **PermissionService.startMonitoring()** is called in `init()` — monitoring is active from app launch. When the user grants permissions in System Settings and returns to the app, `refreshStatus()` fires automatically via `didBecomeActiveNotification`, updating `microphoneStatus`/`screenRecordingStatus`. The wizard UI will react automatically via `@Observable`.

7. **Logger subsystem:** `"com.kuamatzin.meet-notes"` — established pattern across `AppDatabase`, `PermissionService`.

8. **Swift 6 `deinit` issue:** `deinit` cannot access `@MainActor`-isolated properties. If `OnboardingViewModel` holds any notification observers, use the same pattern as `PermissionService` — omit `deinit`, provide explicit `stopMonitoring()` if needed, or simply let the object be deallocated (wizard is short-lived).

9. **Test count baseline:** 23 tests currently passing (13 from Stories 1.x + 10 from Story 2.1). This story should add ~12 tests for a new total of ~35.

10. **Code review feedback from 2.1:** `startMonitoring()` was moved from `.task` modifier to `PermissionService.init()` because tying it to `WindowGroup` lifecycle broke menu-bar-only launch scenarios. Lesson: be careful about lifecycle assumptions — `OnboardingViewModel` should not rely on view lifecycle for critical initialization.

### Git Intelligence

**Recent commits (2 total):**
- `a1e7def` — Add Xcode project structure with code review fixes
- `5d57653` — Initial commit: project scaffold, planning artifacts, and Story 1.1 Swift source files

**Established patterns from codebase:**

1. **Environment injection in `MeetNotesApp.swift`:** Four `@State` properties (`permissionService`, `recordingVM`, `appErrorState`, `navigationState`) injected via `.environment()` into both `MenuBarExtra` and `WindowGroup`. The onboarding additions follow this exact pattern — add `OnboardingViewModel` as `@State`, inject via `.environment()`.

2. **ViewModel pattern:** `RecordingViewModel` is `@Observable @MainActor final class` with an empty body (placeholder). `AppErrorState` same pattern with a single `current: AppError?` property. `OnboardingViewModel` follows the same declaration style but with actual logic.

3. **View pattern:** `MainWindowView` uses `Color.windowBg` from design tokens, `.frame(minWidth:minHeight:)`. `OnboardingWizardView` should follow the same token usage.

4. **`Features/Onboarding/` directory:** Exists but empty — `.gitkeep` was deleted in Story 1.2. Ready for new files.

5. **Test directory structure:** `MeetNotesTests/Infrastructure/` contains `PermissionServiceTests.swift`. New `MeetNotesTests/Onboarding/` directory follows the same mirroring pattern.

6. **No uncommitted Story 2.1 code in git** — Story 2.1 files (`PermissionService.swift`, `PermissionStatus.swift`, etc.) appear in `git status` as modified/untracked but not committed. The dev agent must ensure these files exist on disk before building.

### Latest Tech Information

**SwiftUI macOS Sheet Presentation (March 2026):**

1. **`.sheet(isPresented:)` on macOS** presents a modal sheet attached to the window. For a full-screen onboarding experience, the sheet should use `.frame(minWidth: 800, minHeight: 600)` to fill the window, or use `.frame(maxWidth: .infinity, maxHeight: .infinity)` with a background color.

2. **`.interactiveDismissDisabled(true)`** — available since macOS 13+. Prevents the user from dismissing the sheet by pressing Escape or clicking outside. Essential for the onboarding wizard to ensure users complete the flow.

3. **`@AppStorage`** — stable SwiftUI property wrapper backed by `UserDefaults`. Works in `View` and `App` structs only. Automatically triggers view updates when the underlying UserDefaults value changes — including changes made by other code paths (e.g., ViewModel writing to `UserDefaults.standard`).

4. **`@Observable` macro (Observation framework)** — stable since Swift 5.9 / macOS 14+. Fully compatible with Swift 6 strict concurrency when combined with `@MainActor`. No known breaking changes or deprecations.

5. **SwiftUI `@Environment` with custom types** — the `@Environment(SomeType.self)` syntax (without a key path) requires macOS 14+ and the Observation framework. This is the correct pattern for this project (macOS 14.2+ minimum target).

6. **SF Symbols 6** — current version on macOS 15+. All symbols used in this story are available in SF Symbols 5+ (macOS 14+): `mic.fill`, `rectangle.inset.filled.and.person.filled`, `checkmark.circle.fill`, `chevron.right`.

### Project Structure Notes

- Aligns with architecture file tree: `Features/Onboarding/OnboardingViewModel.swift` and `Features/Onboarding/OnboardingView.swift`
- Uses the same environment injection pattern established in `MeetNotesApp.swift`
- Does NOT create or modify any database schemas
- Does NOT add any SPM dependencies
- Does NOT modify Info.plist or entitlements
- Does NOT touch `UI/Components/` (onboarding views have ViewModel dependencies)
- Consumes `PermissionService` from Story 2.1 — does not modify it
- The `hasCompletedOnboarding` UserDefaults key is a new piece of app state — no migration needed
- Test recording stub (`SimulatedTestRecorder`) will be replaced by a `LiveTestRecorder` when RecordingService (Epic 3) and TranscriptionService (Epic 4) ship. The replacement requires zero changes to `OnboardingViewModel` or `OnboardingWizardView`.

### References

- Story 2.2 acceptance criteria: [Source: _bmad-output/planning-artifacts/epics.md#Story 2.2]
- OnboardingViewModel file tree: [Source: _bmad-output/planning-artifacts/architecture.md#Complete File Tree — "OnboardingViewModel.swift — @Observable @MainActor; wizard step state; permission status; test recording"]
- OnboardingView file tree: [Source: _bmad-output/planning-artifacts/architecture.md#Complete File Tree — "OnboardingView.swift — 3-step full-screen wizard: Welcome → Permissions+Test → Done"]
- Launch gate decision: [Source: _bmad-output/planning-artifacts/architecture.md#Decision: Onboarding Launch Gate]
- UX Journey 1 flow: [Source: _bmad-output/planning-artifacts/ux-design-specification.md#Journey 1: First Launch & Onboarding]
- OnboardingWizardView component spec: [Source: _bmad-output/planning-artifacts/ux-design-specification.md#OnboardingWizardView]
- FR24–FR27 Onboarding & Permissions: [Source: _bmad-output/planning-artifacts/prd.md#Onboarding & Permissions]
- PermissionService implementation: [Source: _bmad-output/implementation-artifacts/2-1-permission-service-runtime-monitoring.md]
- Swift 6 concurrency rules: [Source: _bmad-output/project-context.md#Swift 6 Concurrency Rules]
- SwiftUI rules: [Source: _bmad-output/project-context.md#SwiftUI Rules]
- Testing rules: [Source: _bmad-output/project-context.md#Testing Rules]
- Design tokens: [Source: MeetNotes/MeetNotes/MeetNotes/UI/Components/Color+DesignTokens.swift]
- PermissionChecking protocol: [Source: MeetNotes/MeetNotes/MeetNotes/Infrastructure/Permissions/PermissionStatus.swift]

## Change Log

- 2026-03-04: Implemented full 3-step onboarding wizard with launch gate, permission flow, test recording stub, and 12 comprehensive unit tests. All 36 tests pass (12 new + 24 existing). Zero build errors, zero actor isolation warnings.
- 2026-03-04: Code review fixes — H1: Replaced `resolveOnboardingVM()` body mutation with eager `init()` initialization. H2: Removed dead `isRecording` from `OnboardingTestRecorder` protocol. M1: Added UserDefaults cleanup to all tests. M2: Added accessibility label to `TestRecordingCard`. M3: Added `.failed` result test case (13 tests total). M4: Added guarded transitions on sequential card reveals.

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6

### Debug Log References

- Build error: `UserDefaults` not in scope in test file — fixed by adding `import Foundation`
- Build error: `removePersistentDomain` is an instance method, not a class method — fixed by calling on `defaults` instance

### Completion Notes List

- **Task 1:** Created `OnboardingStep.swift` with `OnboardingStep` enum (`.welcome`, `.permissions`, `.ready`), `OnboardingTestRecorder` protocol, `TestRecordingResult` enum, `TestRecordingState` enum, and `SimulatedTestRecorder` stub class. All types are `Sendable` and `@MainActor`-isolated where appropriate.
- **Task 2:** Created `OnboardingViewModel.swift` as `@Observable @MainActor final class`. Uses protocol-based DI (`any PermissionChecking` + `any OnboardingTestRecorder` + injectable `UserDefaults`). Implements step advancement, permission delegation, test recording coordination, and onboarding completion via UserDefaults.
- **Task 3:** Created Welcome step in `OnboardingWizardView.swift` with `mic.fill` hero icon, app name in `.largeTitle`, privacy message, and "Get Started" CTA. All animations guarded by `reduceMotion`.
- **Task 4:** Created Permissions step with sequential microphone → screen recording cards, green checkmarks on grant, test recording section, and "Continue" button disabled until both permissions granted.
- **Task 5:** Created Ready step with `checkmark.circle.fill` in `.onDeviceGreen`, congratulatory message, and "Start your first meeting" CTA that calls `completeOnboarding()`.
- **Task 6:** Modified `MeetNotesApp.swift` to add `@AppStorage("hasCompletedOnboarding")`, present `OnboardingWizardView` via `.sheet` with `interactiveDismissDisabled(true)`, and inject `OnboardingViewModel` via `.environment()`.
- **Task 7:** Created 12 unit tests in `OnboardingViewModelTests.swift` using Swift Testing (`@Test`, `#expect`). Reused `MockPermissionService` from existing tests. Created `MockTestRecorder` for test injection. Tests cover all acceptance criteria: step transitions, permission delegation, computed properties, UserDefaults flag, and test recording states.
- **Task 8:** Build succeeds with zero errors and zero actor isolation warnings. Full test suite passes: 36 tests, 0 failures. No regressions in existing AppDatabase, SecretsStore, or PermissionService tests.

### File List

**New files:**
- `MeetNotes/MeetNotes/MeetNotes/Features/Onboarding/OnboardingStep.swift`
- `MeetNotes/MeetNotes/MeetNotes/Features/Onboarding/OnboardingViewModel.swift`
- `MeetNotes/MeetNotes/MeetNotes/Features/Onboarding/OnboardingWizardView.swift`
- `MeetNotes/MeetNotes/MeetNotesTests/Onboarding/OnboardingViewModelTests.swift`

**Modified files:**
- `MeetNotes/MeetNotes/MeetNotes/App/MeetNotesApp.swift`

**New directories:**
- `MeetNotes/MeetNotes/MeetNotesTests/Onboarding/`
