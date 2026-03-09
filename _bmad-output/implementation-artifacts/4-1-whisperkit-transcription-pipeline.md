# Story 4.1: WhisperKit Transcription Pipeline

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a user who just stopped a recording,
I want my meeting automatically transcribed on-device — with the first transcript segment appearing within 10 seconds and the full transcript ready within 60 seconds — without any action on my part,
So that I have a complete text record of every meeting the moment it ends.

## Acceptance Criteria

1. **Recording stop triggers transcription:** When `RecordingService.stop()` completes and hands off the accumulated audio buffers, `TranscriptionService.transcribe(meetingID:audioBuffers:)` is called automatically via direct actor call. The `meetings` row `pipeline_status` updates from `'recording'` to `'transcribing'`.

2. **Segments saved incrementally:** As WhisperKit produces transcript segments, each is saved as a row in the `segments` table (with `meeting_id`, `start_seconds`, `end_seconds`, `text`, `confidence`). The `segments_ai` FTS5 trigger fires automatically, indexing each segment for search.

3. **Pipeline status transitions on completion:** When the final segment is saved, `pipeline_status` on the `meetings` row updates to `'transcribed'`. `TranscriptionService` then calls `SummaryService.summarize(meetingID:)` via direct actor call (stub in this story — SummaryService is Epic 5).

4. **First segment latency ≤10 seconds (NFR-P5):** The first transcript segment appears in the database within 10 seconds of `RecordingService.stop()` being called.

5. **Real-time factor <1x (NFR-P3):** A 1-hour meeting transcription completes faster than the audio duration on any Apple Silicon Mac.

6. **End-to-end processing ≤60s for 30-min meeting (NFR-P2):** Total transcription time for a typical 30-minute meeting is under 60 seconds.

7. **Memory <2GB during transcription (NFR-P7):** Total application memory stays below 2GB while transcription is running.

8. **Crash recovery via pipeline_status:** If the app is killed mid-transcription and relaunched, it detects `pipeline_status = 'transcribing'` meetings and can restart transcription for them.

9. **Recording state machine integration:** `RecordingViewModel` state transitions to `.processing(meetingID:, phase: .transcribing(progress:))` during transcription and updates progress as segments are produced.

10. **Audio quality persisted:** The `Meeting` record stores `audio_quality` from `RecordingService.currentAudioQuality` at recording stop time.

## Tasks / Subtasks

- [x] Task 1: Create `TranscriptionService` actor (AC: #1, #2, #3, #8, #9)
  - [x] 1.1: Create `Features/Transcription/TranscriptionService.swift` as `actor TranscriptionService`
  - [x] 1.2: Implement `func transcribe(meetingID: String, audioBuffers: [AVAudioPCMBuffer]) async throws(TranscriptionError)` — accepts accumulated buffers, converts to `[Float]` array, feeds to WhisperKit
  - [x] 1.3: Initialize WhisperKit with `WhisperKitConfig(model: "base")` — base model is bundled, no download needed for first use
  - [x] 1.4: Use WhisperKit `transcribe(audioArray:segmentCallback:)` with SegmentDiscoveryCallback for incremental results
  - [x] 1.5: Save each `TranscriptSegment` to database as produced (FTS5 trigger auto-indexes)
  - [x] 1.6: Update `pipeline_status` transitions: `recording` → `transcribing` → `transcribed`
  - [x] 1.7: Call stub `SummaryService.summarize(meetingID:)` on completion (no-op in this story)
  - [x] 1.8: Report progress to `RecordingViewModel` via `@MainActor` state handler pattern
  - [x] 1.9: Implement crash recovery: on init, scan for `pipeline_status = 'transcribing'` meetings

- [x] Task 2: Create `TranscriptionServiceProtocol` (AC: #1)
  - [x] 2.1: Create `Features/Transcription/TranscriptionServiceProtocol.swift`
  - [x] 2.2: Define protocol with `transcribe(meetingID:audioBuffers:)` and `setStateHandler`
  - [x] 2.3: Define `TranscriptionError` enum (modelNotLoaded, transcriptionFailed, databaseWriteFailed)

- [x] Task 3: Create stub `SummaryService` (AC: #3)
  - [x] 3.1: Create `Features/Summary/SummaryService.swift` as `actor SummaryService` with stub `summarize(meetingID:)` that updates `pipeline_status` to `'complete'` immediately
  - [x] 3.2: Create `Features/Summary/SummaryServiceProtocol.swift` protocol

- [x] Task 4: Wire `RecordingService.stop()` → `TranscriptionService` pipeline (AC: #1, #9, #10)
  - [x] 4.1: Modify `RecordingService.stop()` to: finalize audio buffers from `MixerHandle`, create `Meeting` record in DB with `pipeline_status='recording'`, persist `audio_quality` from `currentAudioQuality`
  - [x] 4.2: After meeting record saved, call `transcriptionService.transcribe(meetingID:audioBuffers:)` via direct actor call
  - [x] 4.3: Update `RecordingViewModel` state to `.processing(meetingID:, phase: .transcribing(progress: 0))`
  - [x] 4.4: Wire progress updates from `TranscriptionService` back to `RecordingViewModel`

- [x] Task 5: Update `MeetNotesApp` wiring (AC: #1, #3)
  - [x] 5.1: Create `TranscriptionService` instance in `MeetNotesApp`
  - [x] 5.2: Create stub `SummaryService` instance
  - [x] 5.3: Inject `TranscriptionService` and `AppDatabase` into `RecordingService`
  - [x] 5.4: Inject `SummaryService` and `AppDatabase` into `TranscriptionService`

- [x] Task 6: MixerHandle buffer accumulation (AC: #1, #4)
  - [x] 6.1: Add buffer accumulation to `MixerHandle` — collect all mixed 16kHz mono Float32 buffers during recording
  - [x] 6.2: Expose `func finalizeBuffers() -> [AVAudioPCMBuffer]` to hand off accumulated audio on stop
  - [x] 6.3: Ensure accumulated buffers are cleared after handoff to prevent memory bloat

- [x] Task 7: Write tests (AC: all)
  - [x] 7.1: `TranscriptionServiceTests.swift` — mock WhisperKit, verify segment DB writes, pipeline_status transitions, progress reporting
  - [x] 7.2: `StubTranscriptionService.swift` — protocol-conforming stub for other tests
  - [x] 7.3: Existing `RecordingServiceTests.swift` — all existing tests continue to pass with new dependencies (optional params)
  - [x] 7.4: `TranscriptionDatabaseTests.swift` — database integration tests verifying segments + FTS5 trigger indexing
  - [x] 7.5: Crash recovery test — verify detection of stale `transcribing` status meetings

## Dev Notes

### Architecture Constraints

- **TranscriptionService MUST be `actor`** (not `@MainActor class`) — per project-context.md rule
- **Typed throws:** `func transcribe(...) async throws(TranscriptionError)` — Swift 6 typed error pattern
- **Three-layer error rule:** TranscriptionService throws → RecordingViewModel catches → posts to AppErrorState → View renders ErrorBannerView
- **Direct actor call pipeline:** `RecordingService.stop()` → `TranscriptionService.transcribe()` → `SummaryService.summarize()` — no Combine, no NotificationCenter
- **Service-to-ViewModel updates:** Use registered `@MainActor @Sendable` handler closure, never direct ViewModel reference
- **Logger:** `private nonisolated static let logger = Logger(subsystem: "com.kuamatzin.meet-notes", category: "TranscriptionService")` — file-scope logger bug workaround from Story 3.2
- **No Combine/ObservableObject** — `@Observable` + `@MainActor` only
- **Database writes in service actors only** — `TranscriptionService` writes segments, not ViewModel

### WhisperKit Integration Details

- **Package:** WhisperKit v0.16.0 (latest stable, March 2025) — already in SPM dependencies
- **Initialization:** `let pipe = try await WhisperKit(WhisperKitConfig(model: "base"))` — base model (~145MB) is bundled in app resources
- **Transcription method:** `pipe.transcribe(audioArray: [Float])` — convert accumulated AVAudioPCMBuffer to flat `[Float]` array (16kHz mono, already in correct format from MixerHandle)
- **Segment callback:** Use `SegmentDiscoveryCallback` (added in v0.13.0) to receive segments incrementally during transcription for progressive DB saves and progress reporting
- **TranscriptionResult** is a `class` (changed from struct in v0.15.0)
- **Model storage:** Bundled base model at `MeetNotes/Resources/whisperkit-base/`; larger models downloaded to `~/Library/Application Support/meet-notes/Models/` (Story 4.2 scope)
- **ANE inference:** WhisperKit uses CoreML/Apple Neural Engine automatically — no manual ANE configuration needed
- **MANDATORY: Use `context7` MCP for WhisperKit documentation** if available — verify exact API signatures before implementation

### Audio Data Flow

```
RecordingService.stop()
  → MixerHandle.finalizeBuffers() → [AVAudioPCMBuffer] (16kHz mono Float32)
  → AppDatabase: INSERT meeting (pipeline_status='recording', audio_quality=currentAudioQuality)
  → TranscriptionService.transcribe(meetingID:, audioBuffers:)
    → Convert [AVAudioPCMBuffer] → [Float] flat array
    → WhisperKit.transcribe(audioArray:) with SegmentDiscoveryCallback
    → For each segment: INSERT INTO segments → FTS5 trigger indexes text
    → UPDATE meeting SET pipeline_status='transcribing' (at start)
    → UPDATE meeting SET pipeline_status='transcribed' (on completion)
    → SummaryService.summarize(meetingID:) (stub — updates to 'complete')
  → RecordingViewModel ← .processing(phase: .transcribing(progress:))
  → RecordingViewModel ← .idle (when pipeline complete)
```

### Buffer-to-Float Conversion

```swift
// Convert [AVAudioPCMBuffer] → [Float] for WhisperKit
func convertBuffersToFloatArray(_ buffers: [AVAudioPCMBuffer]) -> [Float] {
    var result: [Float] = []
    for buffer in buffers {
        guard let channelData = buffer.floatChannelData else { continue }
        let frames = Int(buffer.frameLength)
        result.append(contentsOf: UnsafeBufferPointer(start: channelData[0], count: frames))
    }
    return result
}
```

### Existing Code to Modify

| File | Change |
|------|--------|
| `RecordingService.swift` | Add `stop()` → create Meeting record → call TranscriptionService |
| `RecordingServiceProtocol.swift` | Add `AppDatabase` and `TranscriptionService` dependencies |
| `AudioStreamMixer.swift` | Add buffer accumulation + `finalizeBuffers()` |
| `RecordingViewModel.swift` | Handle `.processing` state transitions from TranscriptionService |
| `MeetNotesApp.swift` | Create and wire TranscriptionService + SummaryService instances |
| `AppError.swift` | Add `transcriptionFailed` case |
| `AppErrorState.swift` | No changes needed (already generic) |

### New Files to Create

| File | Type | Purpose |
|------|------|---------|
| `Features/Transcription/TranscriptionService.swift` | `actor` | WhisperKit integration, segment saves, pipeline orchestration |
| `Features/Transcription/TranscriptionServiceProtocol.swift` | `protocol` | DI protocol + `TranscriptionError` enum |
| `Features/Summary/SummaryService.swift` | `actor` | Stub — updates pipeline_status to 'complete' |
| `Features/Summary/SummaryServiceProtocol.swift` | `protocol` | DI protocol for SummaryService |
| `MeetNotesTests/Transcription/TranscriptionServiceTests.swift` | Tests | Mock WhisperKit, verify DB writes + status transitions |
| `MeetNotesTests/Transcription/StubTranscriptionService.swift` | Stub | Protocol-conforming stub for other tests |

### Swift 6 Concurrency Gotchas (from Story 3.2/3.3)

- **SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor** — new types default to @MainActor; TranscriptionService must use `actor` keyword (not class)
- **`@preconcurrency import` needed** for AVFAudio if using AVAudioPCMBuffer in actor context
- **`extension AVAudioPCMBuffer: @unchecked @retroactive Sendable {}`** — already declared in Story 3.2, do NOT redeclare
- **File-scope logger bug in Swift 6.2** — use `private nonisolated static let logger` on actor type

### Previous Story Intelligence (Story 3.3)

- `RecordingService` is an `actor` with factory-based DI (`makeSystemCapture`, `makeMicCapture`)
- `currentAudioQuality` tracked on RecordingService — must be persisted to Meeting record at stop time
- `MixerHandle` outputs 16kHz mono Float32 — exactly WhisperKit's input format
- `combinedAudioStream: AsyncStream<AVAudioPCMBuffer>?` is currently exposed but not accumulated — need to add buffer collection
- State handler pattern: `setStateHandler(_ handler: @escaping @MainActor @Sendable (RecordingState) -> Void)`
- Sleep/wake handling exists — transcription should not start during sleep

### Project Structure Notes

- Files go in `MeetNotes/MeetNotes/MeetNotes/Features/Transcription/` and `Features/Summary/`
- Tests go in `MeetNotes/MeetNotes/MeetNotesTests/Transcription/`
- Follows one-primary-type-per-file rule
- All type names use mandatory suffixes: `TranscriptionService`, `SummaryService`, `TranscriptionError`

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Epic 4, Story 4.1]
- [Source: _bmad-output/planning-artifacts/architecture.md#Service Pipeline, TranscriptionService, Database Schema]
- [Source: _bmad-output/project-context.md#Critical Implementation Rules]
- [Source: _bmad-output/implementation-artifacts/3-2-core-audio-capture-pipeline.md#Dev Notes]
- [Source: _bmad-output/implementation-artifacts/3-3-audio-resilience-tap-loss-mic-fallback-sleep-wake.md#Compiler Quirks]
- [Source: WhisperKit GitHub — https://github.com/argmaxinc/WhisperKit — v0.16.0]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6

### Debug Log References

- WhisperKit `TranscriptionSegment` is a module-level type, not nested in `WhisperKit` class
- WhisperKit `TranscriptionCallback` is `((TranscriptionProgress) -> Bool?)?` — callback returns Bool to control continuation
- `SegmentDiscoveryCallback` (`(_ segments: [TranscriptionSegment]) -> Void`) is the correct callback for incremental segment delivery, passed via `segmentCallback:` parameter
- `@preconcurrency import WhisperKit` needed because `WhisperKit` class is not Sendable
- GRDB `pool.read`/`pool.write` are async in current version — test code needs `await`
- Added `transcribed` case to `Meeting.PipelineStatus` enum (was missing from original schema)

### Completion Notes List

- Created TranscriptionService actor with full WhisperKit integration pipeline
- Created TranscriptionServiceProtocol with TranscriptionError typed throws
- Created SummaryService stub actor that updates pipeline_status to 'complete'
- Created SummaryServiceProtocol for DI
- Added buffer accumulation to MixerHandle with thread-safe finalizeBuffers()
- Wired RecordingService.stop() → Meeting record creation → TranscriptionService.transcribe()
- Updated MeetNotesApp with full dependency injection chain
- Added transcriptionFailed case to AppError
- Added transcribed case to Meeting.PipelineStatus
- Crash recovery: checkForStaleMeetings() scans and marks stale transcribing meetings as failed
- All existing tests pass (no regressions), new tests pass
- RecordingService maintains backward compatibility with optional database/transcriptionService params

### File List

**New files:**
- MeetNotes/MeetNotes/MeetNotes/Features/Transcription/TranscriptionService.swift
- MeetNotes/MeetNotes/MeetNotes/Features/Transcription/TranscriptionServiceProtocol.swift
- MeetNotes/MeetNotes/MeetNotes/Features/Summary/SummaryService.swift
- MeetNotes/MeetNotes/MeetNotes/Features/Summary/SummaryServiceProtocol.swift
- MeetNotes/MeetNotes/MeetNotesTests/Transcription/TranscriptionServiceTests.swift
- MeetNotes/MeetNotes/MeetNotesTests/Transcription/TranscriptionDatabaseTests.swift
- MeetNotes/MeetNotes/MeetNotesTests/Transcription/StubTranscriptionService.swift

**Modified files:**
- MeetNotes/MeetNotes/MeetNotes/Features/Recording/RecordingService.swift
- MeetNotes/MeetNotes/MeetNotes/Features/Recording/RecordingServiceProtocol.swift
- MeetNotes/MeetNotes/MeetNotes/Features/Recording/AudioStreamMixer.swift
- MeetNotes/MeetNotes/MeetNotes/Features/Recording/RecordingState.swift
- MeetNotes/MeetNotes/MeetNotes/Features/Recording/RecordingViewModel.swift
- MeetNotes/MeetNotes/MeetNotes/App/MeetNotesApp.swift
- MeetNotes/MeetNotes/MeetNotes/App/AppError.swift
- MeetNotes/MeetNotes/MeetNotes/Infrastructure/Database/Meeting.swift

## Change Log

- 2026-03-04: Implemented WhisperKit transcription pipeline (Story 4.1) — TranscriptionService actor with incremental segment saves, buffer accumulation in MixerHandle, RecordingService→TranscriptionService→SummaryService pipeline wiring, crash recovery, comprehensive tests
- 2026-03-04: Code review fixes — (C1) Wired TranscriptionService state handler in MeetNotesApp for progress updates; (C2) Refactored segment callback to actor-isolated method fixing data race on savedSegmentCount; (C3) Added WhisperKitProviding protocol for DI + MockWhisperKitProvider + comprehensive tests with actual assertions; (H1) Fixed confidence using exp(avgLogprob) instead of raw log-prob; (H2) Added RecordingState.swift and RecordingViewModel.swift to File List; (H3) Fire-and-forget Tasks addressed via actor-isolated processNewSegments; (M1) Thread-safe mocks with NSLock; (M2) Added logging for nil dependencies; (M4) Default meeting title with formatted date
