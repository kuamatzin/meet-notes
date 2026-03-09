# Story 3.2: Core Audio Capture Pipeline

Status: done
Story-ID: 3.2
Epic: 3 - Audio Recording
Created: 2026-03-04
Previous-Story: 3-1-menu-bar-recording-controls-state-machine

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a user recording a meeting,
I want system audio from my meeting app and my own microphone voice captured simultaneously and combined into a single audio stream,
so that the full meeting — both what I hear and what I say — is available for transcription with no setup required for each meeting app.

## Acceptance Criteria

1. When `RecordingService.start()` is called and screen recording permission is granted, a Core Audio Tap is installed on the target meeting process to capture system audio (FR5)
2. `AVAudioEngine` is started simultaneously to capture microphone input (FR6)
3. Inside the Core Audio tap IOProc callback, only `continuation.yield(buffer)` is called — no `await`, no actor calls, no database access, no `os_log` (NFR-R3 absolute rule)
4. System audio and microphone streams are resampled to 16kHz mono Float32 via `AVAudioConverter` and combined into a single `AsyncStream<AVAudioPCMBuffer>` for transcription (FR7)
5. The Core Audio tap callback is never blocked, delayed, or interrupted by WhisperKit model loading, database writes, or SwiftUI rendering on other threads/actors — zero audio dropouts (NFR-R2)
6. `RecordingService` is declared as a Swift `actor` and compiles with zero actor isolation warnings or errors under Swift 6 strict concurrency (SWIFT_STRICT_CONCURRENCY = complete)
7. When `RecordingService.stop()` is called, the Core Audio tap is removed, `AVAudioEngine` is stopped, the `AsyncStream` is finished, and the captured audio stream reference is available for `TranscriptionService` (stub handoff for Story 4.1)
8. Meeting app process is auto-detected from known bundle IDs (Zoom, Teams, Chrome/Meet, etc.) — falls back to global system audio tap if no known meeting app is running
9. `RecordingService` communicates state changes to `RecordingViewModel` via a registered `@MainActor` handler closure — never holds a direct ViewModel reference

## Tasks / Subtasks

- [x] Task 1: Extend RecordingServiceProtocol and RecordingError (AC: #6, #9)
  - [x] Add `setStateHandler(_ handler: @escaping @MainActor @Sendable (RecordingState) -> Void)` to `RecordingServiceProtocol`
  - [x] Add specific error cases to `RecordingError`: `.audioTapCreationFailed`, `.microphoneSetupFailed`, `.aggregateDeviceCreationFailed`, `.audioFormatError`
  - [x] Update `StubRecordingService` to conform to extended protocol (no-op `setStateHandler`)
  - [x] Update `AppError` with new mapping cases for the additional `RecordingError` variants
  - [x] Verify all existing tests still pass after protocol changes

- [x] Task 2: Create AudioProcessDiscovery utility (AC: #8)
  - [x] Create `AudioProcessDiscovery` struct with static methods (no instantiation — utility type)
  - [x] Implement `translatePID(_ pid: pid_t) -> AudioObjectID?` using `kAudioHardwarePropertyTranslatePIDToProcessObject`
  - [x] Implement `discoverRunningAudioProcesses() -> [(pid: pid_t, bundleID: String?, objectID: AudioObjectID)]` using `kAudioHardwarePropertyProcessObjectList`
  - [x] Implement `findMeetingAppProcess() -> AudioObjectID?` — filters for known meeting app bundle IDs
  - [x] Define `knownMeetingAppBundleIDs` constant: `us.zoom.xos`, `com.microsoft.teams`, `com.microsoft.teams2`, `com.google.Chrome`, `com.cisco.webex.meetings`, `com.tinyspeck.slackmacgap`, `com.discord.discord`

- [x] Task 3: Implement SystemAudioCapture component (AC: #1, #3, #5)
  - [x] Create `SystemAudioCapture` class (NOT actor — called from RecordingService actor context)
  - [x] Implement `CATapDescription` creation for per-process tap (`stereoMixdownOfProcesses:`)
  - [x] Implement aggregate device creation with tap list configuration
  - [x] Implement IOProc callback via `AudioDeviceCreateIOProcIDWithBlock` — callback ONLY calls `continuation.yield(buffer)` to bridge into `AsyncStream`
  - [x] Expose `audioStream: AsyncStream<AVAudioPCMBuffer>` for consumer
  - [x] Implement `start(processObjectID:)` and `stop()` methods
  - [x] Implement global tap fallback: `CATapDescription(stereoGlobalTapButExcludeProcesses: [])` when no target process
  - [x] Teardown in correct order: stop device → destroy IOProc → destroy aggregate → destroy tap

- [x] Task 4: Implement MicrophoneCapture component (AC: #2, #3)
  - [x] Create `MicrophoneCapture` class wrapping `AVAudioEngine`
  - [x] Install input node tap with `installTap(onBus:bufferSize:format:)` — callback ONLY calls `continuation.yield(buffer)`
  - [x] Expose `audioStream: AsyncStream<AVAudioPCMBuffer>` for consumer
  - [x] Implement `start()` and `stop()` methods
  - [x] Handle `AVAudioEngine` configuration and format negotiation

- [x] Task 5: Implement AudioStreamMixer for resampling and combining (AC: #4)
  - [x] Create `MixerHandle` class (nonisolated, @unchecked Sendable) that consumes two `AsyncStream<AVAudioPCMBuffer>` sources
  - [x] Implement `AVAudioConverter` resampling: system audio (typically 48kHz stereo) → 16kHz mono Float32
  - [x] Implement `AVAudioConverter` resampling: mic audio (typically 44.1kHz/48kHz) → 16kHz mono Float32
  - [x] Implement simple mixing of resampled system + mic buffers into combined `AsyncStream<AVAudioPCMBuffer>`
  - [x] Target output format: 16kHz, mono, Float32 (WhisperKit input requirement)
  - [x] Expose `combinedStream: AsyncStream<AVAudioPCMBuffer>` for TranscriptionService

- [x] Task 6: Create RecordingService actor (AC: #1-9)
  - [x] Declare as `actor RecordingService: RecordingServiceProtocol`
  - [x] Create `SystemAudioCapture`, `MicrophoneCapture`, `MixerHandle` internally
  - [x] `start()`: discover target process → create system capture → create mic capture → start mixer → update state via handler
  - [x] `stop()`: tear down system capture → stop mic → finish mixer stream
  - [x] `setStateHandler()`: store `@MainActor` closure for state communication
  - [x] All errors thrown as `RecordingError` typed throws
  - [x] Note: Logger removed from actor file due to Swift 6.2 compiler bug with nonisolated(unsafe) in actor files

- [x] Task 7: Wire RecordingService into MeetNotesApp (AC: #9)
  - [x] Replace `StubRecordingService()` with `RecordingService()` in `MeetNotesApp.init()`
  - [x] Call `recordingService.setStateHandler { [weak recordingVM] state in recordingVM?.state = state }` to wire state updates
  - [x] Update `RecordingViewModel` to use state handler for service-driven state changes — removed duplicate state assignments in startRecording/stopRecording, changed `private(set)` to `internal(set)` on state property
  - [x] Updated MockRecordingService to call state handler in start/stop, updated all tests to wire handler
  - [x] All 74 tests pass

- [x] Task 8: Add Info.plist audio capture usage description (AC: #1)
  - [x] Add `NSAudioCaptureUsageDescription` key to `MeetNotes/MeetNotes/MeetNotes/Info.plist`: "meet-notes needs to capture system audio to transcribe your meetings."
  - [x] Verified key in built app bundle (BUILD SUCCEEDED)

- [x] Task 9: Write unit tests for RecordingService (AC: all)
  - [x] Used existing `SystemAudioCaptureProtocol` and `MicrophoneCaptureProtocol` for testability
  - [x] Created `MockSystemAudioCapture` and `MockMicrophoneCapture` in test file
  - [x] Refactored RecordingService to accept factory closures for DI (defaults to concrete types)
  - [x] Test `RecordingService.start()` calls system capture + mic capture
  - [x] Test `RecordingService.stop()` tears down both captures
  - [x] Test state handler receives `.recording(startedAt:, audioQuality: .full)` on start
  - [x] Test state handler receives `.idle` on stop
  - [x] Test error propagation: system capture failure → `RecordingError.audioTapCreationFailed`
  - [x] Test error propagation: mic failure → `RecordingError.microphoneSetupFailed`
  - [x] Test Swift 6 concurrency: zero warnings with `SWIFT_STRICT_CONCURRENCY = complete` — 91 total tests pass

- [x] Task 10: Write unit tests for AudioStreamMixer (AC: #4)
  - [x] Test target format is 16kHz mono Float32
  - [x] Test combined stream produces resampled buffers from both 48kHz stereo and 44.1kHz mono sources
  - [x] Test stream finishes when both inputs complete
  - [x] Test stop cancels tasks cleanly

- [x] Task 11: Write unit tests for AudioProcessDiscovery (AC: #8)
  - [x] Test `knownMeetingAppBundleIDs` contains all 10 expected entries
  - [x] Test `findMeetingAppProcess()` runs without crash in test environment
  - [x] Test `discoverRunningAudioProcesses()` returns valid array

## Dev Notes

### Architecture Constraints

- **RecordingService MUST be a Swift `actor`** — not `@MainActor class`. This is the most critical constraint. The service runs on the cooperative thread pool, not the main actor. [Source: architecture.md#Service vs ViewModel Type Pattern]
- **Real-time thread boundary is absolute.** The Core Audio IOProc callback runs on a real-time OS thread. The ONLY permitted operation inside it is `continuation.yield(buffer)`. No `await`, no actor calls, no database access, no `os_log`, no `NotificationCenter.default.post()`. [Source: architecture.md#Real-Time Thread Isolation]
- **AsyncStream is the ONLY safe crossing** from real-time thread to Swift concurrency. [Source: architecture.md#AsyncStream Audio Bridge Decision]
- **Service → ViewModel communication via `@MainActor` closure** — RecordingService registers a handler; it never holds a reference to RecordingViewModel. [Source: architecture.md#MainActor Hop Communication Pattern]
- **Three-layer error rule**: Service throws `RecordingError` → ViewModel catches + maps to `AppError` + posts to `AppErrorState` → View renders. Views never call `try`. [Source: project-context.md#Critical Implementation Rules]
- **Typed throws**: `func start() async throws(RecordingError)` — Swift 6 typed throws syntax. [Source: project-context.md#Swift 6 Concurrency Rules]
- **No Combine, no ObservableObject, no @Published** — these are absolutely prohibited in this codebase. [Source: project-context.md#Critical Don't-Miss Rules]
- **Logger category must be exact type name**: `Logger(subsystem: "com.kuamatzin.meet-notes", category: "RecordingService")`. Never use generic names like "audio". [Source: project-context.md#Code Quality & Style Rules]

### Core Audio Taps Implementation Pattern

The Core Audio Taps API (macOS 14.2+) requires a 3-layer setup:

1. **CATapDescription** — describes what audio to capture (which process, mute behavior)
2. **AudioHardwareCreateProcessTap** — creates the tap, returns `AudioObjectID`
3. **Aggregate Device** — virtual audio device that includes the tap as input source. You CANNOT read from a tap directly — you MUST create an aggregate device containing the tap, then install an IOProc on the aggregate device.

**Critical implementation sequence:**
```
PID → AudioObjectID (kAudioHardwarePropertyTranslatePIDToProcessObject)
    → CATapDescription (stereoMixdownOfProcesses: [objectID])
    → AudioHardwareCreateProcessTap(tapDesc, &tapID)
    → Read tap format (kAudioTapPropertyFormat → AudioStreamBasicDescription)
    → Get system output device UID (kAudioHardwarePropertyDefaultSystemOutputDevice → kAudioDevicePropertyDeviceUID)
    → AudioHardwareCreateAggregateDevice(description, &aggregateDeviceID)
    → AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateDeviceID, queue) { ... continuation.yield(buffer) }
    → AudioDeviceStart(aggregateDeviceID, procID)
```

**Aggregate device dictionary keys:**
```swift
let description: [String: Any] = [
    kAudioAggregateDeviceNameKey: "MeetNotes-Tap-\(processName)",
    kAudioAggregateDeviceUIDKey: UUID().uuidString,
    kAudioAggregateDeviceMainSubDeviceKey: outputDeviceUID,
    kAudioAggregateDeviceIsPrivateKey: true,
    kAudioAggregateDeviceIsStackedKey: false,
    kAudioAggregateDeviceTapAutoStartKey: true,
    kAudioAggregateDeviceSubDeviceListKey: [
        [kAudioSubDeviceUIDKey: outputDeviceUID]
    ],
    kAudioAggregateDeviceTapListKey: [
        [
            kAudioSubTapDriftCompensationKey: true,
            kAudioSubTapUIDKey: tapDescription.uuid.uuidString
        ]
    ]
]
```

**Teardown order is critical — must be exactly:**
1. `AudioDeviceStop(aggregateDeviceID, procID)`
2. `AudioDeviceDestroyIOProcID(aggregateDeviceID, procID)`
3. `AudioHardwareDestroyAggregateDevice(aggregateDeviceID)`
4. `AudioHardwareDestroyProcessTap(processTapID)`

**IOProc callback (AsyncStream bridge):**
```swift
AudioDeviceCreateIOProcIDWithBlock(&deviceProcID, aggregateDeviceID, ioQueue) {
    inNow, inInputData, inInputTime, outOutputData, inOutputTime in
    // REAL-TIME THREAD — absolutely nothing else here
    guard let buffer = AVAudioPCMBuffer(
        pcmFormat: tapFormat,
        bufferListNoCopy: inInputData,
        deallocator: nil
    ) else { return }
    continuation.yield(buffer)
}
```

### Microphone Capture Pattern

```swift
let engine = AVAudioEngine()
let inputNode = engine.inputNode
let inputFormat = inputNode.outputFormat(forBus: 0)

let (stream, continuation) = AsyncStream<AVAudioPCMBuffer>.makeStream()
inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
    continuation.yield(buffer)  // ONLY this — real-time thread rule
}
try engine.start()
```

### Audio Resampling Pattern

Resampling happens OUTSIDE the real-time callback, inside the Swift concurrency boundary (in the `AudioStreamMixer` actor):

```swift
// Create converter: source format → 16kHz mono Float32
let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
let converter = AVAudioConverter(from: sourceFormat, to: targetFormat)!

// For each buffer from AsyncStream:
let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
let outputFrameCount = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio)
let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount)!

var error: NSError?
converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
    outStatus.pointee = .haveData
    return inputBuffer
}
```

### Known Meeting App Bundle IDs

```swift
static let knownMeetingAppBundleIDs: Set<String> = [
    "us.zoom.xos",                   // Zoom
    "com.microsoft.teams",           // Microsoft Teams (old)
    "com.microsoft.teams2",          // Microsoft Teams (new)
    "com.google.Chrome",             // Google Meet (runs in Chrome)
    "com.brave.Browser",             // Google Meet (Brave)
    "com.apple.Safari",              // Google Meet (Safari)
    "org.mozilla.firefox",           // Google Meet (Firefox)
    "com.cisco.webex.meetings",      // Webex
    "com.tinyspeck.slackmacgap",     // Slack
    "com.discord.discord",           // Discord
]
```

**Process discovery strategy:**
1. Query `kAudioHardwarePropertyProcessObjectList` for all audio processes
2. Read each process's `kAudioProcessPropertyBundleID` and `kAudioProcessPropertyIsRunning`
3. Filter for processes in `knownMeetingAppBundleIDs` that are actively running audio
4. Return the first match (or all matches for future multi-source support)
5. If no known meeting app found → fall back to global tap: `CATapDescription(stereoGlobalTapButExcludeProcesses: [])`

### Scope Boundaries — What Is NOT in This Story

- **Tap loss detection and mic-only fallback** → Story 3.3
- **Sleep/wake handling** → Story 3.3
- **Health monitor (1-second repeating check)** → Story 3.3
- **WhisperKit transcription consumption** → Story 4.1
- **Meeting record database insertion** → Story 4.1
- **Audio file persistence (M4A recording)** → deferred/optional
- **Real-time waveform amplitude data for WaveformView** → enhancement (WaveformView currently uses animation, not real amplitude)

### Key Implementation Patterns from Story 3.1

**RecordingServiceProtocol (current — to be extended):**
```swift
enum RecordingError: Error, Equatable, Sendable {
    case startFailed
}

protocol RecordingServiceProtocol: Sendable {
    func start() async throws(RecordingError)
    func stop() async
}
```

**RecordingViewModel (current — state management):**
```swift
@Observable @MainActor final class RecordingViewModel {
    private(set) var state: RecordingState = .idle
    private let permissionService: any PermissionChecking
    private let recordingService: any RecordingServiceProtocol
    private let appErrorState: AppErrorState

    func startRecording() async {
        guard state.isIdle else { return }
        guard permissionService.microphoneStatus == .authorized else { ... }
        guard permissionService.screenRecordingStatus == .authorized else { ... }
        do {
            try await recordingService.start()
            state = .recording(startedAt: Date(), audioQuality: .full)
        } catch {
            state = .error(.recordingFailed)
            appErrorState.post(.recordingFailed)
        }
    }

    func stopRecording() async {
        guard state.isRecording else { return }
        await recordingService.stop()
        state = .idle
    }
}
```

**MeetNotesApp wiring (current — StubRecordingService):**
```swift
_recordingVM = State(initialValue: RecordingViewModel(
    permissionService: ps,
    recordingService: StubRecordingService(),  // ← Replace with RecordingService()
    appErrorState: errorState
))
```

### How State Communication Works After This Story

After Story 3.2, the flow becomes:
1. ViewModel calls `recordingService.start()` (existing pattern)
2. RecordingService installs tap + mic, starts streaming
3. RecordingService calls `await MainActor.run { onStateChange?(.recording(startedAt: Date(), audioQuality: .full)) }`
4. ViewModel receives state update via handler closure
5. On stop: ViewModel calls `recordingService.stop()`
6. RecordingService tears down, finishes streams
7. RecordingService calls handler with appropriate state

**Important change to RecordingViewModel:** After wiring the state handler, the ViewModel should let the SERVICE drive state transitions rather than setting state directly after `start()`/`stop()` calls. The ViewModel's `startRecording()` should call `start()` and let the handler update state, rather than manually setting `state = .recording(...)`.

### Anti-Patterns to Avoid

- **DO NOT** call any async function, perform I/O, or log inside the Core Audio IOProc callback — this is a real-time thread violation that WILL cause audio glitches or crashes
- **DO NOT** use `AVAudioEngine.installTap()` for system audio — it only works for microphone; system audio requires the Core Audio Tap → Aggregate Device → IOProc pattern
- **DO NOT** use `ScreenCaptureKit` for audio-only capture — Core Audio Taps is the correct API for per-process audio
- **DO NOT** create RecordingService as `@MainActor class` — it MUST be an `actor`
- **DO NOT** store `AVAudioPCMBuffer` references long-term — the buffer memory is owned by the audio system and will be reused; copy data if needed beyond the callback scope
- **DO NOT** write audio to a file as an intermediate step — stream directly via `AsyncStream` to TranscriptionService (Story 4.1)
- **DO NOT** hold a direct reference to RecordingViewModel from RecordingService — use the registered `@MainActor` handler closure only
- **DO NOT** use `DispatchSemaphore` or `NSLock` to synchronize between real-time thread and Swift concurrency — `AsyncStream.Continuation.yield()` is the only safe bridge
- **DO NOT** allocate memory inside the IOProc callback — `AVAudioPCMBuffer(pcmFormat:bufferListNoCopy:deallocator:)` wraps existing memory without allocation
- **DO NOT** import Combine anywhere — this project uses `@Observable` + `AsyncStream` exclusively

### Info.plist Requirement

The `NSAudioCaptureUsageDescription` key MUST be present in Info.plist for `AudioHardwareCreateProcessTap` to work. This key is NOT in Xcode's dropdown menu — it must be typed manually. The OS will show the permission dialog the first time the tap is created.

```xml
<key>NSAudioCaptureUsageDescription</key>
<string>meet-notes needs to capture system audio to transcribe your meetings.</string>
```

### Project Structure Notes

All new files go in `MeetNotes/MeetNotes/MeetNotes/Features/Recording/`:

| File | Type | Purpose |
|------|------|---------|
| `RecordingService.swift` | Actor | Real Core Audio + mic capture implementation |
| `SystemAudioCapture.swift` | Class | Core Audio Tap + aggregate device + IOProc management |
| `MicrophoneCapture.swift` | Class | AVAudioEngine microphone capture wrapper |
| `AudioStreamMixer.swift` | Actor | Resampling + mixing of two audio streams |
| `AudioProcessDiscovery.swift` | Struct | Meeting app process discovery utility |

Files to modify:

| File | Change |
|------|--------|
| `Features/Recording/RecordingServiceProtocol.swift` | Add `setStateHandler()` to protocol, extend `RecordingError` |
| `Features/Recording/StubRecordingService.swift` | Conform to extended protocol |
| `App/MeetNotesApp.swift` | Replace `StubRecordingService()` with `RecordingService()`, wire state handler |
| `App/AppError.swift` | Add mapping cases for new `RecordingError` variants |
| `Features/Recording/RecordingViewModel.swift` | Adjust to support service-driven state via handler (service calls handler instead of VM setting state directly) |
| `MeetNotes/Info.plist` | Add `NSAudioCaptureUsageDescription` |

Test files in `MeetNotesTests/Recording/`:

| File | Purpose |
|------|---------|
| `RecordingServiceTests.swift` | Actor lifecycle, start/stop, error propagation, state handler |
| `AudioStreamMixerTests.swift` | Resampling, mixing, stream completion |
| `AudioProcessDiscoveryTests.swift` | Bundle ID list, process filtering |

### Entitlements Reminder

The app already has (from Story 1.1 setup):
- `com.apple.security.device.audio-input = true` (microphone)
- `com.apple.security.app-sandbox = false` (required for Core Audio Taps)
- Hardened Runtime enabled

Verify `com.apple.security.network.client = true` is present (needed for Ollama, but also ensures no entitlement blocks).

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Story 3.2: Core Audio Capture Pipeline]
- [Source: _bmad-output/planning-artifacts/architecture.md#RecordingService Actor Architecture]
- [Source: _bmad-output/planning-artifacts/architecture.md#AsyncStream Audio Bridge Decision]
- [Source: _bmad-output/planning-artifacts/architecture.md#Real-Time Thread Isolation NFR-R3]
- [Source: _bmad-output/planning-artifacts/architecture.md#MainActor Hop Communication Pattern]
- [Source: _bmad-output/planning-artifacts/architecture.md#End-to-End Recording Session Flow]
- [Source: _bmad-output/planning-artifacts/architecture.md#Service Layer Pipeline Boundary]
- [Source: _bmad-output/planning-artifacts/prd.md#FR5-FR9 Audio Capture]
- [Source: _bmad-output/planning-artifacts/prd.md#NFR-R2 NFR-R3 Reliability]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md#Recording State Ambient Trust]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md#WaveformView Component Specification]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md#Error Recovery Patterns]
- [Source: _bmad-output/project-context.md#Swift 6 Concurrency Rules]
- [Source: _bmad-output/project-context.md#Critical Don't-Miss Rules]
- [Source: _bmad-output/implementation-artifacts/3-1-menu-bar-recording-controls-state-machine.md#Dev Notes]
- [Source: _bmad-output/implementation-artifacts/3-1-menu-bar-recording-controls-state-machine.md#Previous Story Learnings]
- [Source: Apple Developer Docs: CATapDescription]
- [Source: Apple Developer Docs: AudioHardwareCreateProcessTap]
- [Source: Apple Developer Docs: NSAudioCaptureUsageDescription]
- [Source: GitHub insidegui/AudioCap — BSD-2-Clause reference implementation]
- [Source: GitHub RecapAI/Recap — open-source meeting recorder using Core Audio Taps]

### Previous Story Intelligence (from Story 3.1)

1. **Protocol-based DI** — ViewModels accept protocols (`any PermissionChecking`, `any RecordingServiceProtocol`) not concrete types. Follow same pattern: create `SystemAudioCaptureProtocol` and `MicrophoneCaptureProtocol` for testability. [Story 2.1, 2.2, 3.1]
2. **@Observable + @MainActor** — stable pattern; no known issues with strict concurrency. [Story 3.1]
3. **Animation guards** — ALL SwiftUI animations check `@Environment(\.accessibilityReduceMotion)`. No new views in this story, but verify existing views still work. [Story 2.2]
4. **ErrorBannerView is pure display** — takes all data via parameters, no @Environment dependencies. New error cases must map to `AppError` for banner display. [Story 2.3]
5. **Permission banners are REACTIVE** — read PermissionService state directly for persistent errors, use AppErrorState only for transient errors. [Story 2.3]
6. **Logger category = exact type name** — `RecordingService`, `SystemAudioCapture`, `MicrophoneCapture`, `AudioStreamMixer`, `AudioProcessDiscovery`. [All stories]
7. **Test isolation** — custom UserDefaults suite names and cleanup via `removePersistentDomain`. For audio tests, use protocol mocks rather than real hardware. [Story 2.2]
8. **CGPreflightScreenCaptureAccess()** returns Bool only — cannot distinguish `.notDetermined` from `.denied`. Permission checks already handled by RecordingViewModel from Story 3.1. [Story 2.1]
9. **Remove .gitkeep files** — PBXFileSystemSynchronizedRootGroup causes duplicate resource errors with .gitkeep. [Story 1.2]
10. **RecordingServiceProtocol typed throws** — `func start() async throws(RecordingError)` — must use Swift 6 typed throws, not untyped `throws`. [Story 3.1]

### Git Intelligence

Recent commits:
- `a1e7def` — Add Xcode project structure with code review fixes
- `5d57653` — Initial commit: project scaffold, planning artifacts, and Story 1.1 Swift source files

**Patterns from commits:**
- Commit messages use imperative mood
- Code review fixes are applied as follow-up commits
- All code compiles under Swift 6 strict concurrency

### Technology Notes (Latest Research — March 2026)

**Core Audio Taps API — macOS 14.2+ (stable, no deprecations through macOS 16):**
- API surface unchanged in macOS 15 (Sequoia) and macOS 16 (Tahoe)
- No deprecation notices issued for `CATapDescription`, `AudioHardwareCreateProcessTap`, or related aggregate device APIs
- Known macOS 15 bug: ~12 dB attenuation on devices with multiple stereo output pairs (e.g., RME Fireface). Built-in speakers and AirPods show ~0 dB. Not a blocker for meet-notes.
- `ScreenCaptureKit` is an alternative for screen+audio, but Core Audio Taps remain recommended for audio-only per-process capture

**AVAudioEngine — stable, no changes:**
- `installTap(onBus:bufferSize:format:)` continues to work as expected
- Note from AudioTee source: `installTap()` fires every ~100ms minimum — for system audio IOProc fires at hardware buffer rate (~5-10ms). This means mic buffers arrive less frequently than system audio buffers — the mixer must handle different cadences.

**AVAudioConverter — stable:**
- `convert(to:error:inputBlock:)` pattern for on-demand conversion
- Works correctly for 48kHz stereo → 16kHz mono Float32 conversion

**Reference implementations:**
- `insidegui/AudioCap` (BSD-2-Clause) — clean Swift implementation of Core Audio Taps
- `RecapAI/Recap` — open-source meeting recorder using identical stack
- `makeusabrew/audiotee` — CLI tool demonstrating the aggregate device pattern
- Study these BEFORE writing production code to resolve implementation questions

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6

### Debug Log References

- Swift 6.2 compiler bug: `nonisolated(unsafe)` on file-scope loggers triggers "pattern that the region based isolation checker does not understand" when in same file as an actor. Workaround: used `private static let logger` on the actor type instead of file-scope logger.
- Swift 6.2 `sending` parameter constraint: `Task.detached` closures capturing `AsyncStream<AVAudioPCMBuffer>` fail because `AVAudioPCMBuffer` (ObjC class) is not Sendable, making `AsyncStream<AVAudioPCMBuffer>` not Sendable. Fix: `extension AVAudioPCMBuffer: @unchecked @retroactive Sendable {}` in AudioStreamMixer.swift.
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (Approachable Concurrency): ALL types default to @MainActor. New audio types must use `nonisolated` keyword on class/struct/protocol declarations.
- `@preconcurrency import AVFAudio` and `@preconcurrency import CoreAudio` required because macOS 26 SDK adds @MainActor annotations to Apple framework types.

### Completion Notes List

- All 11 tasks complete
- 91 total tests pass (17 new: 8 RecordingService + 4 AudioStreamMixer + 4 AudioProcessDiscovery + 1 protocol conformance)
- Zero Swift 6 concurrency warnings/errors
- AudioStreamMixer implemented as `MixerHandle` class (not actor) due to Swift 6.2 concurrency constraints
- RecordingService refactored with factory-based DI for testability
- RecordingViewModel updated: service-driven state via handler, `internal(set)` on state property
- MockRecordingService updated to call state handler in start/stop

### Code Review Fixes Applied (2026-03-04)

- **[H1] Fixed resource leak**: RecordingService.start() now cleans up system capture if mic capture fails
- **[H2] Fixed error mapping**: RecordingViewModel now maps specific RecordingError variants to specific AppError cases instead of generic .recordingFailed
- **[H3] Fixed race condition**: State handler wiring moved from fire-and-forget Task in MeetNotesApp.init() to lazy ensureStateHandler() in RecordingViewModel.startRecording()
- **[M1] Exposed combinedAudioStream**: Added `var combinedAudioStream` property to RecordingService for Story 4.1 TranscriptionService handoff
- **[M2] Improved discovery tests**: AudioProcessDiscoveryTests now assert meaningful invariants (non-zero objectIDs) instead of placeholder assertions
- **[M3] Added cleanup test**: New test `startCleansUpSystemCaptureWhenMicFails` verifies system capture teardown on mic failure
- **[M4] Restored logging**: Used `private static let logger` on the actor type to work around Swift 6.2 file-scope logger bug
- **[M5] File List corrected**: Updated paths and noted files correctly as new vs modified
- Added 3 new tests: 1 RecordingService cleanup test + 2 RecordingViewModel error mapping tests

### File List

New files created (in `MeetNotes/MeetNotes/MeetNotes/`):
- `Features/Recording/AudioProcessDiscovery.swift` — Meeting app process discovery utility
- `Features/Recording/SystemAudioCapture.swift` — Core Audio Tap + aggregate device + IOProc
- `Features/Recording/MicrophoneCapture.swift` — AVAudioEngine microphone capture
- `Features/Recording/AudioStreamMixer.swift` — MixerHandle: resampling + combining streams
- `Features/Recording/RecordingService.swift` — Actor orchestrating all audio capture
- `Features/Recording/RecordingServiceProtocol.swift` — Protocol + RecordingError (new, not committed in prior stories)
- `Features/Recording/StubRecordingService.swift` — Stub conformance (new, not committed in prior stories)
- `Info.plist` — Added NSAudioCaptureUsageDescription

New test files (in `MeetNotes/MeetNotes/MeetNotesTests/`):
- `Recording/RecordingServiceTests.swift` — RecordingService unit tests (9 tests)
- `Recording/AudioStreamMixerTests.swift` — MixerHandle unit tests (4 tests)
- `Recording/AudioProcessDiscoveryTests.swift` — Discovery unit tests (4 tests)

Modified files:
- `App/AppError.swift` — New error cases (.audioCaptureFailed, .microphoneSetupFailed, .audioFormatError)
- `App/MeetNotesApp.swift` — Replaced StubRecordingService with RecordingService
- `Features/Recording/RecordingViewModel.swift` — Service-driven state via ensureStateHandler(), specific error mapping, internal(set) on state
- `MeetNotesTests/Recording/RecordingViewModelTests.swift` — Updated mock with errorToThrow, added error mapping tests
