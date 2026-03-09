# Story 3.1: Menu Bar Recording Controls & State Machine

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a meeting participant,
I want to start and stop recordings from the menu bar with visual state feedback,
so that I can capture meeting audio with zero friction and always know the recording status.

## Acceptance Criteria

1. Menu bar icon displays static SF Symbol `mic` glyph when idle (grayscale, 11pt)
2. Clicking menu bar icon opens popover with "Start Recording" button when idle
3. Starting a recording transitions menu bar icon to animated 3-bar waveform + red dot (1.2s cycle)
4. During recording, popover shows elapsed time counter (MM:SS), audio quality status, and "Stop Recording" button
5. `RecordingViewModel.state` enum drives ALL UI state transitions with cases: `.idle`, `.recording(startedAt:, audioQuality:)`, `.processing(meetingID:, phase:)`
6. Waveform animation is disabled when `accessibilityReduceMotion` is enabled (static icon shown instead)
7. Stopping a recording returns menu bar icon to static `mic` glyph immediately
8. Permission preflight check runs before recording starts — shows appropriate error banner if microphone or screen recording permission is denied
9. Recording state is observable across both MenuBarPopoverView and MainWindowView simultaneously
10. Title bar shows "Meeting Title . MM:SS" with red dot during recording when main window is visible

## Tasks / Subtasks

- [x] Task 1: Create RecordingState enum and AudioQuality types (AC: #5)
  - [x] Define `RecordingState` enum with `.idle`, `.recording(startedAt:, audioQuality:)`, `.processing(meetingID:, phase:)`, `.error(AppError)` cases
  - [x] Define `AudioQuality` enum: `.full`, `.micOnly`, `.partial`
  - [x] Define `ProcessingPhase` enum: `.transcribing(progress:)`, `.summarizing`
  - [x] Ensure `Equatable` conformance for SwiftUI diffing
- [x] Task 2: Create RecordingViewModel (AC: #5, #9)
  - [x] `@Observable @MainActor final class RecordingViewModel`
  - [x] `state: RecordingState` property (initially `.idle`)
  - [x] `startRecording()` async method with permission preflight
  - [x] `stopRecording()` async method
  - [x] `elapsedTime: TimeInterval` computed from `state.startedAt`
  - [x] `formattedElapsedTime: String` computed (MM:SS format)
  - [x] Inject `any PermissionChecking` for permission preflight
  - [x] Inject placeholder `RecordingServiceProtocol` (stub for Story 3.2)
- [x] Task 3: Create RecordingServiceProtocol and stub (AC: #8)
  - [x] Define `RecordingServiceProtocol` with `start() async throws` and `stop() async`
  - [x] Create `StubRecordingService` that simulates state transitions (replaced in Story 3.2)
- [x] Task 4: Create WaveformView for animated menu bar icon (AC: #1, #3, #6)
  - [x] 3-bar animated waveform with amplitude variation
  - [x] Red recording dot (`recordingRed: #FF3B30`)
  - [x] 1.2-second animation cycle
  - [x] Respect `@Environment(\.accessibilityReduceMotion)` — disable animation entirely
- [x] Task 5: Update MenuBarPopoverView for recording states (AC: #2, #4, #7)
  - [x] Idle state: "Start Recording" button (permission-gated)
  - [x] Recording state: elapsed timer, audio quality badge, "Stop Recording" button
  - [x] Permission warning rows when permissions denied (reuse existing pattern from Story 2.3)
- [x] Task 6: Update menu bar icon rendering (AC: #1, #3, #7)
  - [x] Idle: static `mic` SF Symbol
  - [x] Recording: WaveformView + red dot
  - [x] Processing: static mic + spinner overlay
- [x] Task 7: Update MainWindowView title bar for recording state (AC: #10)
  - [x] Show "Meeting Title . MM:SS" with red dot during `.recording` state
  - [x] Show processing phase indicator during `.processing` state
- [x] Task 8: Wire RecordingViewModel into app environment (AC: #9)
  - [x] Create shared instance in MeetNotesApp
  - [x] Inject via `@Environment(RecordingViewModel.self)` to both MenuBarExtra and WindowGroup
- [x] Task 9: Write unit tests for RecordingViewModel (AC: all)
  - [x] Test idle → recording state transition
  - [x] Test recording → idle on stop
  - [x] Test permission denied prevents recording start
  - [x] Test elapsed time formatting
  - [x] Test state propagation (observable changes)
- [x] Task 10: Write unit tests for RecordingState types
  - [x] Test Equatable conformance
  - [x] Test AudioQuality cases
  - [x] Test ProcessingPhase cases

## Dev Notes

### Architecture Constraints

- **RecordingViewModel** is `@Observable @MainActor final class` — follows ViewModel pattern from Stories 2.1-2.3
- **RecordingService** (real implementation in Story 3.2) will be a Swift `actor`, NOT `@MainActor class` — the stub here should use a protocol so the real actor can conform later
- **State machine is the source of truth** — RecordingViewModel.state drives ALL UI rendering across menu bar and main window
- **Permission preflight** in `startRecording()` must check PermissionService before attempting any audio work
- **Error propagation** follows three-layer rule: Service throws → ViewModel catches & posts to AppErrorState → View renders banner

### Key Implementation Patterns

**RecordingState enum (file: `Features/Recording/RecordingState.swift`):**
```swift
enum RecordingState: Equatable {
    case idle
    case recording(startedAt: Date, audioQuality: AudioQuality)
    case processing(meetingID: UUID, phase: ProcessingPhase)
    case error(AppError)
}

enum AudioQuality: Equatable {
    case full       // system audio + mic
    case micOnly    // microphone only (tap lost)
    case partial    // degraded capture
}

enum ProcessingPhase: Equatable {
    case transcribing(progress: Double)
    case summarizing
}
```

**RecordingViewModel (file: `Features/Recording/RecordingViewModel.swift`):**
```swift
@Observable @MainActor final class RecordingViewModel {
    private(set) var state: RecordingState = .idle
    private let permissionService: any PermissionChecking
    private let recordingService: any RecordingServiceProtocol
    private let appErrorState: AppErrorState

    var elapsedTime: TimeInterval {
        guard case .recording(let startedAt, _) = state else { return 0 }
        return Date().timeIntervalSince(startedAt)
    }

    var formattedElapsedTime: String {
        let total = Int(elapsedTime)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    func startRecording() async {
        guard await permissionService.microphoneStatus == .granted else {
            appErrorState.post(.microphonePermissionDenied)
            return
        }
        guard await permissionService.screenRecordingStatus == .granted else {
            appErrorState.post(.screenRecordingPermissionDenied)
            return
        }
        do {
            try await recordingService.start()
            state = .recording(startedAt: Date(), audioQuality: .full)
        } catch {
            appErrorState.post(.from(error))
        }
    }

    func stopRecording() async {
        await recordingService.stop()
        state = .idle
    }
}
```

**Timer display — use `Text(timerInterval:)` for the popover elapsed time:**
```swift
// In MenuBarPopoverView, when recording:
if case .recording(let startedAt, _) = viewModel.state {
    Text(timerInterval: startedAt...Date.now, countsDown: false)
        .monospacedDigit()
}
```

**Menu bar icon — MenuBarExtra label:**
```swift
MenuBarExtra {
    MenuBarPopoverView()
} label: {
    switch recordingViewModel.state {
    case .idle:
        Image(systemName: "mic")
    case .recording:
        WaveformView() // animated 3-bar + red dot
    case .processing:
        Image(systemName: "mic")
            .overlay(ProgressView().scaleEffect(0.5))
    case .error:
        Image(systemName: "mic.slash")
    }
}
.menuBarExtraStyle(.window)
```

**Waveform animation guard:**
```swift
struct WaveformView: View {
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<3) { i in
                RoundedRectangle(cornerRadius: 1)
                    .frame(width: 2, height: reduceMotion ? 8 : animatedHeight(for: i))
            }
            Circle()
                .fill(Color.recordingRed)
                .frame(width: 4, height: 4)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 1.2).repeatForever(), value: phase)
    }
}
```

### File Structure

All new files go in `MeetNotes/MeetNotes/MeetNotes/Features/Recording/`:

| File | Type | Purpose |
|------|------|---------|
| `RecordingState.swift` | Enum | State machine types (RecordingState, AudioQuality, ProcessingPhase) |
| `RecordingServiceProtocol.swift` | Protocol | Interface for RecordingService (real impl in Story 3.2) |
| `StubRecordingService.swift` | Class | Stub implementation for testing and Story 3.1 development |
| `RecordingViewModel.swift` | ViewModel | `@Observable @MainActor` state machine driver |
| `WaveformView.swift` | View | Animated 3-bar waveform for menu bar icon |

Files to modify:

| File | Change |
|------|--------|
| `UI/MenuBar/MenuBarPopoverView.swift` | Add recording state UI (timer, stop button, quality badge) |
| `UI/MainWindow/MainWindowView.swift` | Add title bar recording indicator |
| `App/MeetNotesApp.swift` | Create & inject RecordingViewModel into environment |

Test files in `MeetNotesTests/Recording/`:

| File | Purpose |
|------|---------|
| `RecordingStateTests.swift` | Enum behavior and Equatable conformance |
| `RecordingViewModelTests.swift` | State transitions, permission gating, elapsed time |

### Previous Story Learnings (CRITICAL)

1. **Protocol-based DI** — ViewModels accept protocols (`any PermissionChecking`) not concrete types. Follow same pattern for `RecordingServiceProtocol` (Story 2.1, 2.2)
2. **@AppStorage in Views only** — if you need persistent state, use UserDefaults in ViewModel (Story 2.2)
3. **Animation guards** — ALL SwiftUI animations must check `@Environment(\.accessibilityReduceMotion)` (Story 2.2)
4. **ErrorBannerView is pure display** — takes all data via parameters, no @Environment dependencies. Reuse from Story 2.3 (Story 2.3)
5. **Permission banners are REACTIVE** — read PermissionService state directly for persistent errors, use AppErrorState only for transient errors (Story 2.3)
6. **Logger category** — use exact type name: `Logger(subsystem: "com.kuamatzin.meet-notes", category: "RecordingViewModel")` (All stories)
7. **View nesting limit** — extract subviews to keep `body` ≤ 3 levels deep (Story 2.2)
8. **Test isolation** — custom UserDefaults suite names and cleanup via `removePersistentDomain` (Story 2.2)
9. **CGPreflightScreenCaptureAccess()** returns Bool only — cannot distinguish `.notDetermined` from `.denied` (Story 2.1)
10. **Remove .gitkeep files** — PBXFileSystemSynchronizedRootGroup causes duplicate resource errors with .gitkeep (Story 1.2)

### Technology Notes (Latest Research)

- **MenuBarExtra** supports `.menuBarExtraStyle(.window)` for custom popover content — no third-party dependency needed for basic use
- **SF Symbol animation** — use `.symbolEffect(.pulse)` for recording indicator if waveform approach proves complex in MenuBarExtra
- **Text(timerInterval:)** is preferred over Timer publisher for elapsed time display — auto-updates, cleaner code
- **@Observable + @MainActor** — stable pattern in Swift 6; no known issues with strict concurrency checking

### Anti-Patterns to Avoid

- **DO NOT** create RecordingService as `@MainActor class` — it must be an `actor` (real impl in Story 3.2)
- **DO NOT** use `Timer.publish` for elapsed time when `Text(timerInterval:)` works
- **DO NOT** post permission errors to `AppErrorState` — read PermissionService state reactively for persistent banners
- **DO NOT** put recording logic in the ViewModel — ViewModel only manages state; all audio logic goes in RecordingService (Story 3.2)
- **DO NOT** add Core Audio or AVAudioEngine code — that's Story 3.2. This story is UI + state machine only
- **DO NOT** use `@StateObject` or `ObservableObject` — project uses `@Observable` macro exclusively

### Project Structure Notes

- New `Features/Recording/` directory follows established pattern from `Features/Onboarding/`
- RecordingState types should be standalone file (not nested in ViewModel) for reuse by RecordingService actor in Story 3.2
- WaveformView goes in `Features/Recording/` (not `UI/Components/`) because it's recording-feature-specific
- Test files mirror source structure: `MeetNotesTests/Recording/`

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Epic 3 - Story 3.1]
- [Source: _bmad-output/planning-artifacts/architecture.md#RecordingService Actor Architecture]
- [Source: _bmad-output/planning-artifacts/architecture.md#RecordingViewModel State Machine]
- [Source: _bmad-output/planning-artifacts/architecture.md#Menu Bar Icon State Feedback]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md#Core Recording Loop]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md#Menu Bar Icon Animation]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md#Sidebar Behavior During Recording]
- [Source: _bmad-output/planning-artifacts/prd.md#FR1-FR4]
- [Source: _bmad-output/planning-artifacts/architecture.md#Error Propagation Three-Layer Rule]
- [Source: _bmad-output/implementation-artifacts/2-1-permission-service-runtime-monitoring.md#Dev Notes]
- [Source: _bmad-output/implementation-artifacts/2-2-first-launch-onboarding-wizard.md#Dev Notes]
- [Source: _bmad-output/implementation-artifacts/2-3-missing-permission-recovery-guidance.md#Dev Notes]

## Dev Agent Record

### Agent Model Used
Claude Opus 4.6

### Debug Log References
- Fixed pre-existing Swift 6 Sendable issue in OnboardingViewModelTests.swift (UserDefaults capture in @Sendable closure)
- Added `.recordingFailed` case to AppError to support error propagation from RecordingService failures

### Completion Notes List
- Implemented full RecordingState enum with `.idle`, `.recording`, `.processing`, `.error` cases plus `AudioQuality` and `ProcessingPhase` supporting enums
- Created RecordingViewModel as `@Observable @MainActor final class` with protocol-based DI for PermissionChecking and RecordingServiceProtocol
- Permission preflight in startRecording() checks both microphone and screen recording before attempting to record
- Created RecordingServiceProtocol and StubRecordingService (to be replaced by real actor in Story 3.2)
- Built WaveformView with 3-bar animation, red recording dot, accessibility reduceMotion guard
- Updated MenuBarPopoverView with full recording state UI: idle (start button), recording (timer + quality badge + stop), processing indicator
- Updated MeetNotesApp MenuBarExtra label to switch between static mic icon, WaveformView, processing overlay, and error icon based on state
- Updated MainWindowView with recording-aware content area, toolbar recording indicator with live timer, and navigation title changes
- Wired RecordingViewModel with shared PermissionService and AppErrorState instances in MeetNotesApp init()
- Added keyboard shortcut commands for Start/Stop Recording (⌘⇧R)
- 71 tests pass including 19 new Recording tests (9 RecordingState + 10 RecordingViewModel)
- All animations guarded by `@Environment(\.accessibilityReduceMotion)`
- Used `Text(timerInterval:)` for live elapsed time display (no Timer publisher)

### Change Log
- 2026-03-04: Story 3.1 implementation complete — recording state machine, UI controls, and tests
- 2026-03-04: Code review fixes — typed throws, error state activation, state guards, shortcut consolidation

### File List
New files:
- MeetNotes/MeetNotes/MeetNotes/Features/Recording/RecordingServiceProtocol.swift (RecordingError enum + protocol)
- MeetNotes/MeetNotes/MeetNotes/Features/Recording/StubRecordingService.swift
- MeetNotes/MeetNotes/MeetNotes/Features/Recording/WaveformView.swift
- MeetNotes/MeetNotes/MeetNotesTests/Recording/RecordingStateTests.swift
- MeetNotes/MeetNotes/MeetNotesTests/Recording/RecordingViewModelTests.swift

Modified files:
- MeetNotes/MeetNotes/MeetNotes/Features/Recording/RecordingState.swift (added convenience properties)
- MeetNotes/MeetNotes/MeetNotes/Features/Recording/RecordingViewModel.swift (state machine driver with permission preflight)
- MeetNotes/MeetNotes/MeetNotes/App/AppError.swift (added .recordingFailed case)
- MeetNotes/MeetNotes/MeetNotes/App/AppErrorState.swift (added post/clear methods)
- MeetNotes/MeetNotes/MeetNotes/App/MeetNotesApp.swift (wired RecordingViewModel, updated MenuBarExtra label, toggle shortcut)
- MeetNotes/MeetNotes/MeetNotes/UI/MenuBar/MenuBarPopoverView.swift (added recording state UI)
- MeetNotes/MeetNotes/MeetNotes/UI/MainWindow/MainWindowView.swift (added recording indicator + state-aware content)
- MeetNotes/MeetNotes/MeetNotesTests/Onboarding/OnboardingViewModelTests.swift (fixed Swift 6 Sendable warning)

### Notes
- AC #10 partially implemented: title bar shows "Recording" + toolbar timer. Full meeting title display deferred until Meeting creation is implemented in a later story.
