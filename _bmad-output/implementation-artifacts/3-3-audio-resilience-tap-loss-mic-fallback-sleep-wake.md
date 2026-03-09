# Story 3.3: Audio Resilience — Tap Loss, Mic Fallback & Sleep/Wake

Status: done
Story-ID: 3.3
Epic: 3 - Audio Recording
Created: 2026-03-04
Previous-Story: 3-2-core-audio-capture-pipeline

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a user recording a meeting when something goes wrong,
I want the app to detect audio tap loss within 2 seconds, warn me without interrupting the meeting, automatically fall back to microphone-only recording, and survive Mac sleep/wake cycles intact,
So that I always get at least a partial transcript even under adverse conditions, and I am never left with silent, undetected recording failures.

## Acceptance Criteria

1. **Given** a recording is active **When** `RecordingService`'s 1-second repeating health monitor fires **Then** it checks whether the Core Audio tap is still delivering buffers within the expected cadence
2. **Given** the health monitor detects no system audio buffers for ≥2 seconds **When** tap loss is confirmed **Then** `RecordingViewModel.state` is updated to `.recording(..., audioQuality: .micOnly)` **And** an inline warning banner appears: "System audio capture lost. Recording microphone only." — the recording session is NOT stopped (FR8)
3. **Given** the tap-loss warning is shown **When** the recording continues **Then** microphone-only audio continues to be captured and streamed to `TranscriptionService` (FR9)
4. **Given** the recording stops after a tap-loss event **When** the meeting record is saved to the database **Then** the `audio_quality` column is set to `'mic_only'` or `'partial'` (FR34 prerequisite)
5. **Given** the Mac enters sleep while a recording is active **When** `AppDelegate` receives `NSWorkspace.willSleepNotification` **Then** the Core Audio tap is cleanly paused and the audio stream is suspended without losing buffered data (NFR-R4)
6. **Given** the Mac wakes from sleep **When** `AppDelegate` receives `NSWorkspace.didWakeNotification` **Then** the Core Audio tap is resumed and the recording continues from where it left off without corruption or crash (NFR-R4)
7. **Given** CPU usage is measured during an active recording (before transcription begins) **When** profiled on any Apple Silicon Mac **Then** the app's additional CPU contribution stays below 15% (NFR-P8)

## Tasks / Subtasks

- [x] Task 1: Add tap health monitoring to SystemAudioCapture (AC: #1)
  - [x]Add `lastBufferTimestamp: Date?` property updated in IOProc callback via atomic write (no actor calls in real-time thread — use `os_unfair_lock` or `Atomic<Date?>`)
  - [x]Add `isTapHealthy() -> Bool` method: returns `true` if `lastBufferTimestamp` is within 2 seconds of now
  - [x]Add `SystemAudioCaptureProtocol.isTapHealthy() -> Bool` to protocol
  - [x]Update `MockSystemAudioCapture` in tests to conform

- [x] Task 2: Add health monitor task to RecordingService (AC: #1, #2)
  - [x]Add `tapMonitorTask: Task<Void, Never>?` property
  - [x]Implement `startTapHealthMonitor()`: 1-second repeating `Task` that calls `systemCapture.isTapHealthy()`
  - [x]On tap loss detected: call `handleTapLoss()` — stop system capture, update state to `.recording(startedAt:, audioQuality: .micOnly)`, post `AppError.audioTapLost` via state handler
  - [x]Start monitor in `start()` after system capture is active
  - [x]Cancel `tapMonitorTask` in `stop()`
  - [x]Add `handleTapLoss()` private method

- [x] Task 3: Add `audioTapLost` error case to AppError (AC: #2)
  - [x]Add `case audioTapLost` to `AppError` enum
  - [x]`bannerMessage`: "System audio capture lost. Recording microphone only."
  - [x]`recoveryLabel`: "Dismiss"
  - [x]`sfSymbol`: "waveform.slash"
  - [x]`systemSettingsURL`: `nil`

- [x] Task 4: Update RecordingService for mic-only fallback (AC: #2, #3)
  - [x]In `handleTapLoss()`: stop system capture only, keep mic capture and mixer running
  - [x]Update `AudioStreamMixer` / `MixerHandle` to handle system stream finishing while mic continues — the combined stream must continue yielding mic-only buffers
  - [x]Track `audioQuality` state within RecordingService (starts `.full`, degrades to `.micOnly` on tap loss)
  - [x]Ensure `combinedAudioStream` continues producing buffers after tap loss

- [x] Task 5: Add sleep/wake handling (AC: #5, #6)
  - [x]In `AppDelegate`: register for `NSWorkspace.willSleepNotification` and `NSWorkspace.didWakeNotification`
  - [x]Add `handleSleep()` and `handleWake()` methods to `RecordingServiceProtocol`
  - [x]`handleSleep()`: pause IOProc via `AudioDeviceStop()` (do NOT tear down aggregate device)
  - [x]`handleWake()`: attempt `AudioDeviceStart()` to resume — if it fails (tap invalidated by OS), call `handleTapLoss()` to degrade to mic-only
  - [x]Add `pause()` and `resume() throws(RecordingError)` to `SystemAudioCaptureProtocol`
  - [x]`AppDelegate` handlers dispatch: `Task { await recordingService.handleSleep() / handleWake() }`
  - [x]Update `StubRecordingService` and `MockRecordingService` to conform to extended protocol

- [x] Task 6: Track audio quality for database persistence (AC: #4)
  - [x]Add `private(set) var currentAudioQuality: AudioQuality = .full` to `RecordingService`
  - [x]Set to `.micOnly` in `handleTapLoss()`, to `.partial` if tap resumes after wake
  - [x]Expose via `RecordingServiceProtocol`: `var currentAudioQuality: AudioQuality { get async }`
  - [x]This will be consumed by Story 4.1 when saving the Meeting record — Story 3.3 only tracks it

- [x] Task 7: Update MixerHandle to survive system stream loss (AC: #3, #4)
  - [x]When system `AsyncStream` finishes (tap stopped), MixerHandle must continue forwarding mic-only buffers to `combinedStream`
  - [x]The system stream consumer task should exit cleanly without cancelling the mic stream consumer task
  - [x]Verify `combinedStream` remains open and producing mic-only audio after system stream ends

- [x] Task 8: Write unit tests for tap health monitoring (AC: #1, #2)
  - [x]Test `isTapHealthy()` returns `true` when buffers arriving
  - [x]Test `isTapHealthy()` returns `false` when no buffers for >2 seconds
  - [x]Test `RecordingService` calls `handleTapLoss()` when health check fails
  - [x]Test state transitions: `.recording(.full)` → `.recording(.micOnly)` on tap loss
  - [x]Test `AppError.audioTapLost` is posted on tap loss

- [x] Task 9: Write unit tests for sleep/wake (AC: #5, #6)
  - [x]Test `handleSleep()` pauses system capture (calls `pause()`)
  - [x]Test `handleWake()` resumes system capture (calls `resume()`)
  - [x]Test `handleWake()` degrades to mic-only when resume fails
  - [x]Test recording state is preserved across sleep/wake cycle

- [x] Task 10: Write unit tests for MixerHandle stream survival (AC: #3)
  - [x]Test `combinedStream` continues producing buffers after system stream finishes
  - [x]Test mic-only buffers arrive at target format (16kHz mono Float32)
  - [x]Test `combinedStream` finishes only when both inputs complete

## Dev Notes

### Architecture Constraints

- **RecordingService MUST remain a Swift `actor`** — all new methods (`handleTapLoss`, `handleSleep`, `handleWake`, `startTapHealthMonitor`) are actor-isolated. [Source: architecture.md#Service vs ViewModel Type Pattern]
- **Real-time thread boundary is absolute.** The `lastBufferTimestamp` update inside the IOProc callback must NOT use actor calls. Use `os_unfair_lock` or Swift Atomics for thread-safe timestamp writing. `continuation.yield(buffer)` remains the only async-crossing operation. [Source: architecture.md#Real-Time Thread Isolation]
- **Three-layer error rule**: `RecordingService` → `RecordingViewModel` (catches, maps to `AppError`, posts to `AppErrorState`) → View renders `ErrorBannerView`. The `audioTapLost` error is a **non-blocking inline banner** — it does NOT stop the recording session. [Source: project-context.md#Critical Implementation Rules]
- **Service → ViewModel communication via `@MainActor` closure** — tap loss state updates flow through the existing `onStateChange` handler. The service calls `await updateState(.recording(startedAt:, audioQuality: .micOnly))` to inform the ViewModel. [Source: architecture.md#MainActor Hop Communication Pattern]
- **No Combine, no ObservableObject, no @Published** — absolutely prohibited. [Source: project-context.md#Critical Don't-Miss Rules]
- **SWIFT_STRICT_CONCURRENCY = complete** — zero warnings/errors. All new code must compile cleanly under Swift 6. [Source: project-context.md#Swift 6 Concurrency Rules]
- **SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor** (Approachable Concurrency) — ALL new types default to @MainActor. Audio types must use `nonisolated` keyword. [Source: 3-2 story debug log]

### Tap Health Monitoring Implementation Pattern

The health monitor runs as a repeating `Task` inside `RecordingService` (actor context). It checks a timestamp that is updated from the real-time IOProc callback thread.

**Critical constraint:** The IOProc callback cannot use `await` or actor methods. The timestamp must be updated via a lock-free mechanism:

```swift
// In SystemAudioCapture — real-time safe timestamp update
import os // for os_unfair_lock

private var _lastBufferLock = os_unfair_lock()
private var _lastBufferTime: UInt64 = 0  // mach_absolute_time()

// Inside IOProc callback (real-time thread):
let now = mach_absolute_time()
os_unfair_lock_lock(&_lastBufferLock)
_lastBufferTime = now
os_unfair_lock_unlock(&_lastBufferLock)
continuation.yield(buffer)

// isTapHealthy() called from RecordingService (Swift concurrency):
func isTapHealthy() -> Bool {
    os_unfair_lock_lock(&_lastBufferLock)
    let lastTime = _lastBufferTime
    os_unfair_lock_unlock(&_lastBufferLock)
    guard lastTime > 0 else { return true } // No buffers yet = healthy (just started)
    let elapsed = machTimeToSeconds(mach_absolute_time() - lastTime)
    return elapsed < 2.0
}
```

**Why `mach_absolute_time()` instead of `Date()`:** `Date()` allocates and is not real-time safe. `mach_absolute_time()` is a single register read with zero allocation.

### Sleep/Wake Implementation Pattern

```swift
// AppDelegate.swift — registration in applicationDidFinishLaunching
NSWorkspace.shared.notificationCenter.addObserver(
    self, selector: #selector(systemWillSleep),
    name: NSWorkspace.willSleepNotification, object: nil)
NSWorkspace.shared.notificationCenter.addObserver(
    self, selector: #selector(systemDidWake),
    name: NSWorkspace.didWakeNotification, object: nil)

// Handlers dispatch to RecordingService
@objc private func systemWillSleep(_ notification: Notification) {
    Task { await recordingService?.handleSleep() }
}
@objc private func systemDidWake(_ notification: Notification) {
    Task { await recordingService?.handleWake() }
}
```

**AppDelegate needs a reference to RecordingService.** The `MeetNotesApp.init()` creates `RecordingService` — `AppDelegate` needs access to it. Use a property on `AppDelegate` set from `MeetNotesApp.init()` or access via `@NSApplicationDelegateAdaptor`. Since `AppDelegate` already exists via `@NSApplicationDelegateAdaptor`, the simplest pattern is to set `appDelegate.recordingService = recService` after initialization.

**Sleep behavior:** `AudioDeviceStop()` pauses the IOProc without tearing down the aggregate device or tap. On wake, `AudioDeviceStart()` resumes. If the OS invalidated the tap during sleep, `AudioDeviceStart()` returns an error → degrade to mic-only.

**AVAudioEngine sleep behavior:** `AVAudioEngine` is automatically paused/resumed by the OS on sleep/wake. The mic capture should survive sleep/wake without explicit handling. However, verify in testing — if the engine stops, call `engine.start()` again in `handleWake()`.

### MixerHandle Stream Survival Pattern

Current `MixerHandle` has two consumer tasks (one per stream). When the system stream finishes (tap loss), the system consumer task exits. The mic consumer task must continue independently.

**Key change:** The `combinedStream` continuation must NOT finish when only the system stream ends. It should finish only when BOTH streams end (or `stop()` is called).

```swift
// Current pattern (from Story 3.2): both tasks finishing → finish continuation
// Required change: track stream completion independently
private var systemStreamDone = false
private var micStreamDone = false

// System stream consumer exits → set systemStreamDone = true
// Only call continuation.finish() when BOTH are done
```

### Scope Boundaries — What Is NOT in This Story

- **Tap recovery/reconnection** — if the tap is lost, we degrade to mic-only; we do NOT attempt to re-create the tap. Reconnection is a future enhancement.
- **Database Meeting record insertion** → Story 4.1 (this story only tracks `audioQuality` state)
- **WhisperKit transcription** → Story 4.1
- **`audio_quality` column display in UI** → Story 4.4
- **Real waveform amplitude data** — WaveformView still uses animation, not real amplitude

### Anti-Patterns to Avoid

- **DO NOT** use `Date()` or `os_log` inside the IOProc callback for timestamp tracking — these allocate memory and are not real-time safe
- **DO NOT** use `Task.sleep` with nanosecond precision for the health monitor — use `Task.sleep(for: .seconds(1))` (Duration-based)
- **DO NOT** stop the entire recording session on tap loss — the session MUST continue with mic-only audio
- **DO NOT** cancel the mic stream consumer when system stream finishes — they are independent
- **DO NOT** use `DispatchTimer` or `Timer` for the health monitor — use a `Task` loop with `Task.sleep`
- **DO NOT** hold a strong reference to `RecordingService` from `AppDelegate` — use a `weak` or optional reference to avoid retain cycles
- **DO NOT** call `continuation.finish()` on `combinedStream` when only the system stream ends
- **DO NOT** use `DispatchSemaphore` or `NSLock` to synchronize between real-time thread and Swift concurrency — only `os_unfair_lock` for the timestamp, and `AsyncStream.Continuation.yield()` for buffers
- **DO NOT** import Combine anywhere
- **DO NOT** add `await` calls inside `os_unfair_lock` critical sections

### Project Structure Notes

All new/modified files in `MeetNotes/MeetNotes/MeetNotes/`:

**Modified files:**

| File | Change |
|------|--------|
| `Features/Recording/SystemAudioCapture.swift` | Add `lastBufferTimestamp`, `isTapHealthy()`, `pause()`, `resume()` |
| `Features/Recording/RecordingServiceProtocol.swift` | Add `handleSleep()`, `handleWake()`, `currentAudioQuality` to protocol |
| `Features/Recording/RecordingService.swift` | Add health monitor, `handleTapLoss()`, `handleSleep()`, `handleWake()`, `currentAudioQuality` |
| `Features/Recording/AudioStreamMixer.swift` | Update MixerHandle to survive system stream loss |
| `Features/Recording/StubRecordingService.swift` | Conform to extended protocol |
| `App/AppError.swift` | Add `case audioTapLost` |
| `App/MeetNotesApp.swift` | Pass `RecordingService` reference to `AppDelegate` |

**Files that need AppDelegate reference:**

| File | Change |
|------|--------|
| `AppDelegate.swift` (existing or create) | Add sleep/wake notification observers, reference to RecordingService |

**Test files in `MeetNotesTests/Recording/`:**

| File | Purpose |
|------|---------|
| `RecordingServiceTests.swift` | Add health monitor, tap loss, sleep/wake tests |
| `AudioStreamMixerTests.swift` | Add stream survival tests |

**No new source files needed** — all changes extend existing types.

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 3.3: Audio Resilience — Tap Loss, Mic Fallback & Sleep/Wake]
- [Source: _bmad-output/planning-artifacts/architecture.md#Tap Health Monitor Pattern]
- [Source: _bmad-output/planning-artifacts/architecture.md#AppDelegate Sleep/Wake Handling NFR-R4]
- [Source: _bmad-output/planning-artifacts/architecture.md#RecordingState Enum and AudioQuality]
- [Source: _bmad-output/planning-artifacts/architecture.md#Error Propagation — AppErrorState]
- [Source: _bmad-output/planning-artifacts/architecture.md#Real-Time Thread Isolation NFR-R3]
- [Source: _bmad-output/planning-artifacts/prd.md#FR8 Tap Loss Detection, FR9 Mic-Only Fallback]
- [Source: _bmad-output/planning-artifacts/prd.md#NFR-R4 Sleep/Wake Resilience, NFR-P8 CPU Budget]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md#Error Recovery Patterns]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md#Recording State Ambient Trust]
- [Source: _bmad-output/project-context.md#Swift 6 Concurrency Rules]
- [Source: _bmad-output/project-context.md#Critical Don't-Miss Rules]
- [Source: _bmad-output/implementation-artifacts/3-2-core-audio-capture-pipeline.md#Dev Notes]
- [Source: _bmad-output/implementation-artifacts/3-2-core-audio-capture-pipeline.md#Core Audio Taps Implementation Pattern]
- [Source: Apple Developer Docs: os_unfair_lock]
- [Source: Apple Developer Docs: mach_absolute_time]
- [Source: Apple Developer Docs: NSWorkspace.willSleepNotification / didWakeNotification]

### Previous Story Intelligence (from Story 3.2)

1. **Swift 6.2 compiler bug with file-scope loggers in actor files** — use `private static let logger` on the actor type instead of `nonisolated(unsafe)` file-scope logger in files containing actors. [Story 3.2 debug log]
2. **`AVAudioPCMBuffer` is not Sendable** — required `extension AVAudioPCMBuffer: @unchecked @retroactive Sendable {}` in AudioStreamMixer.swift. Already present — do not duplicate. [Story 3.2 debug log]
3. **`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`** — all types default to @MainActor. New audio types/extensions must use `nonisolated` keyword. [Story 3.2 debug log]
4. **`@preconcurrency import AVFAudio` and `@preconcurrency import CoreAudio`** — required because macOS 26 SDK adds @MainActor annotations. Already present in existing files. [Story 3.2 debug log]
5. **Protocol-based DI with factory closures** — `RecordingService` accepts factory closures for `SystemAudioCapture` and `MicrophoneCapture`. Extend with mock factories for new `isTapHealthy()`, `pause()`, `resume()` methods. [Story 3.2]
6. **RecordingService state handler pattern** — `ensureStateHandler()` lazy wiring in ViewModel. No changes needed for this story — tap loss state updates flow through the same `onStateChange` handler. [Story 3.2 code review]
7. **Teardown order is critical** — `AudioDeviceStop` → `AudioDeviceDestroyIOProcID` → `AudioHardwareDestroyAggregateDevice` → `AudioHardwareDestroyProcessTap`. Sleep/wake only stops/starts the device, not full teardown. [Story 3.2]
8. **MockRecordingService calls state handler in start/stop** — update mock to also support `handleSleep()`, `handleWake()`, `currentAudioQuality`. [Story 3.2]
9. **91 total tests pass** — baseline for regression. All new tests must maintain this count + additions. [Story 3.2]

### Git Intelligence

Recent commits:
- `a1e7def` — Add Xcode project structure with code review fixes
- `5d57653` — Initial commit: project scaffold, planning artifacts, and Story 1.1 Swift source files

Patterns: imperative mood commits, code review fixes as follow-ups, all code compiles under Swift 6 strict concurrency.

### Technology Notes (Latest — March 2026)

**Core Audio Taps sleep/wake behavior (macOS 14.2+):**
- After sleep, `AudioDeviceStart()` may fail with `kAudioHardwareBadDeviceError` if the OS invalidated the aggregate device
- The tap itself (`AudioObjectID` from `AudioHardwareCreateProcessTap`) may be invalidated
- Safe pattern: attempt `AudioDeviceStart()` → if failure, treat as tap loss and degrade to mic-only
- No need to handle sleep/wake for `AVAudioEngine` (mic) — the engine auto-resumes on wake

**`os_unfair_lock` for real-time timestamp:**
- Lock-free alternative to `NSLock`, safe for real-time threads
- Critical section must be extremely short (single assignment)
- Available in `os/lock.h`, imported via `import os`

**`mach_absolute_time()` for real-time safe timing:**
- Returns ticks of the CPU clock — requires `mach_timebase_info` conversion to seconds
- Zero allocation, safe in IOProc callbacks
- Standard pattern for real-time audio timestamp tracking

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6

### Debug Log References

- Swift 6.2 `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` required `nonisolated` keyword on `AudioQuality`, `RecordingState`, and `ProcessingPhase` enums since they're used across actor boundaries
- `os_unfair_lock` pointer capture in IOProc closure uses heap-allocated `UnsafeMutablePointer` for memory-safe pointer stability (fixed from initial `withUnsafeMutablePointer` escape)
- MixerHandle already had FinishCounter pattern supporting independent stream completion — Task 7 required no code changes

### Completion Notes List

- Implemented tap health monitoring using `os_unfair_lock` + `mach_absolute_time()` for real-time safe timestamp tracking in IOProc callback
- Added 1-second repeating `Task`-based health monitor in `RecordingService` that detects tap loss within 2 seconds
- On tap loss: system capture stops, mic capture continues, state transitions to `.recording(.micOnly)`, `AppError.audioTapLost` banner posted (non-blocking)
- Sleep/wake handling via `NSWorkspace` notifications in `AppDelegate`, dispatching to `RecordingService.handleSleep()/handleWake()`
- Sleep pauses IOProc via `AudioDeviceStop()`; wake resumes via `AudioDeviceStart()` — if resume fails, degrades to mic-only
- `currentAudioQuality` tracked in `RecordingService` for future database persistence (Story 4.1)
- Added `setErrorHandler` to `RecordingServiceProtocol` for service-to-ViewModel error propagation without direct reference
- 12 new tests added covering tap health monitoring, tap loss state transitions, sleep/wake handling, and MixerHandle stream survival
- All pre-existing tests pass (no regressions)

### Change Log

- 2026-03-04: Implemented Story 3.3 — Audio resilience: tap loss detection, mic-only fallback, sleep/wake handling
- 2026-03-04: Code review fixes — (H1) replaced unsafe `withUnsafeMutablePointer` escape with heap-allocated pointers; (H2) removed premature `currentAudioQuality` reset in `stop()` preserving quality for Story 4.1; (H3) injectable `healthCheckInterval` in `RecordingService` eliminates flaky 2s test sleeps; (M1) cached `mach_timebase_info` as static let; (M2) updated project-context.md IOProc rule

### File List

**Modified:**
- `MeetNotes/MeetNotes/MeetNotes/Features/Recording/SystemAudioCapture.swift` — Added heap-allocated `_lastBufferLockPtr`/`_lastBufferTimePtr`, `isTapHealthy()`, `pause()`, `resume()`, cached `timebaseInfo`, updated IOProc to record timestamp, extended `SystemAudioCaptureProtocol`
- `MeetNotes/MeetNotes/MeetNotes/Features/Recording/RecordingService.swift` — Added health monitor with injectable `healthCheckInterval`, `handleTapLoss()`, `handleSleep()`, `handleWake()`, `currentAudioQuality` (preserved across stop), `setErrorHandler()`, `tapMonitorTask`
- `MeetNotes/MeetNotes/MeetNotes/Features/Recording/RecordingServiceProtocol.swift` — Added `setErrorHandler`, `handleSleep`, `handleWake`, `currentAudioQuality` to protocol
- `MeetNotes/MeetNotes/MeetNotes/Features/Recording/RecordingState.swift` — Marked `RecordingState`, `AudioQuality`, `ProcessingPhase` as `nonisolated` and `Sendable`
- `MeetNotes/MeetNotes/MeetNotes/Features/Recording/StubRecordingService.swift` — Conformed to extended `RecordingServiceProtocol`
- `MeetNotes/MeetNotes/MeetNotes/App/AppError.swift` — Added `case audioTapLost` with banner message, recovery label, symbol
- `MeetNotes/MeetNotes/MeetNotes/App/AppDelegate.swift` — Added sleep/wake notification observers and `recordingService` reference
- `MeetNotes/MeetNotes/MeetNotes/App/MeetNotesApp.swift` — Passes `RecordingService` reference to `AppDelegate`
- `MeetNotes/MeetNotes/MeetNotes/Features/Recording/RecordingViewModel.swift` — Wires up error handler in `ensureStateHandler()`
- `MeetNotes/MeetNotes/MeetNotesTests/Recording/RecordingServiceTests.swift` — Added 9 new tests (tap health, tap loss, sleep/wake), updated `MockSystemAudioCapture` with new protocol methods
- `MeetNotes/MeetNotes/MeetNotesTests/Recording/AudioStreamMixerTests.swift` — Added 3 new tests (stream survival after system stream loss)
- `MeetNotes/MeetNotes/MeetNotesTests/Recording/RecordingViewModelTests.swift` — Updated `MockRecordingService` to conform to extended protocol
- `_bmad-output/project-context.md` — Updated IOProc real-time thread rule to allow `os_unfair_lock` + `mach_absolute_time()` for tap health monitoring
