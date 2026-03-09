# Story 4.2: Model Management & Transcription Settings

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a user who wants higher transcription accuracy,
I want to choose between WhisperKit model sizes, see download progress, and switch models without the UI freezing,
So that I can balance transcription speed and accuracy for my needs, with the base model always immediately available.

## Acceptance Criteria

1. **Base model ready at first launch:** The WhisperKit base model (~145MB) is already downloaded and ready after onboarding completes — no wait before the first recording (FR12).

2. **Model selection UI in Settings:** Settings → Transcription shows `ModelDownloadCard` entries for each available model size displaying: model name, file size, accuracy badge, and speed badge (FR11).

3. **On-demand model download with progress:** When the user taps "Download" on a model not yet downloaded, `ModelDownloadManager` begins a resumable download with a visible progress bar in the card (FR12, NFR-R5).

4. **Non-blocking download:** Model downloads continue in the background when the user navigates away from Settings or starts a recording. The UI remains fully interactive (NFR-R5).

5. **Resumable downloads:** If a model download is interrupted (network loss, app quit), it resumes from the last byte received rather than restarting from zero (NFR-I4).

6. **Active model switching:** When the user selects a fully-downloaded model as active in Settings, `TranscriptionService` uses it for all subsequent transcriptions (FR11).

7. **Safe model usage during download:** If a recording stops while a model download is in progress, `TranscriptionService` uses the currently active (already-downloaded) model, not the one still downloading.

8. **Model download retry policy:** Failed downloads retry up to 3 times with exponential backoff (1s, 2s, 4s). After 3 failures, `AppError.modelDownloadFailed` is posted to `AppErrorState`.

9. **Settings persisted in database:** The selected model name is stored in the `settings` table via `AppSetting` (key: `"whisperkit_model"`). Default value: `"base"`.

10. **SettingsViewModel created:** `SettingsViewModel` is an `@Observable @MainActor final class` managing transcription model selection, model download state, and wiring to `ModelDownloadManager` (architecture: one of four permitted ViewModels).

## Tasks / Subtasks

- [x] Task 1: Create `ModelDownloadManager` actor (AC: #3, #4, #5, #8)
  - [x] 1.1: Create `Features/Transcription/ModelDownloadManager.swift` as `actor ModelDownloadManager`
  - [x] 1.2: Define `ModelInfo` struct (must be `Sendable`): name, displayName, sizeBytes, accuracyLabel, speedLabel, isDefault
  - [x] 1.3: Define `ModelDownloadState` enum (must be `Sendable`): `notDownloaded`, `downloading(progress: Double)`, `downloaded`, `failed(String)`
  - [x] 1.4: Implement `availableModels` — static list of supported WhisperKit models (base, small, medium, large-v3-turbo) with metadata
  - [x] 1.5: Implement `downloadModel(name:) async throws(ModelDownloadError)` — uses WhisperKit's model download API to download to `~/Library/Application Support/meet-notes/Models/`
  - [x] 1.6: Implement resumable download tracking — use WhisperKit's built-in resumable download support. Track download state (modelName, bytesDownloaded, totalBytes) in the `settings` table via AppSetting keys like `"download_progress_{modelName}"`. Do NOT use UserDefaults for multi-GB download state (NFR-I4)
  - [x] 1.7: Implement retry logic: 3 retries, exponential backoff (1s, 2s, 4s), post `AppError.modelDownloadFailed` after exhaustion
  - [x] 1.8: Implement `cancelDownload(name:)` to allow user cancellation
  - [x] 1.9: Expose progress handler registration: `func setProgressHandler(_ handler: @escaping @MainActor @Sendable (String, ModelDownloadState) -> Void)` — actor calls `await MainActor.run { handler(modelName, state) }` to cross isolation boundary
  - [x] 1.10: Implement `isModelDownloaded(name:) -> Bool` — check if model files exist at expected path
  - [x] 1.11: Implement `deleteModel(name:) async` — remove downloaded model files (cannot delete base model)

- [x] Task 2: Create `ModelDownloadManagerProtocol` and `ModelDownloadError` (AC: #8)
  - [x] 2.1: Create `ModelDownloadManagerProtocol` with methods: `downloadModel(name:)`, `cancelDownload(name:)`, `isModelDownloaded(name:)`, `deleteModel(name:)`, `setProgressHandler(_:)`, `availableModels` — enables stub injection for testing
  - [x] 2.2: Add `ModelDownloadError` enum: `networkFailed`, `diskSpaceInsufficient`, `downloadInterrupted`, `invalidModelData` — all cases map to `AppError.modelDownloadFailed(modelName:)` in SettingsViewModel
  - [x] 2.3: Use Swift 6 typed throws: `throws(ModelDownloadError)`

- [x] Task 3: Create `SettingsViewModel` (AC: #6, #9, #10)
  - [x] 3.1: Create `Features/Settings/SettingsViewModel.swift` as `@Observable @MainActor final class SettingsViewModel`
  - [x] 3.2: Properties: `selectedModel: String` (from AppSetting), `modelStates: [String: ModelDownloadState]`, `availableModels: [ModelInfo]`
  - [x] 3.3: Implement `loadSettings()` — read `whisperkit_model` from `settings` table via `AppDatabase`
  - [x] 3.4: Implement `selectModel(name:) async` — sequencing: (1) call `await transcriptionService.setModel(name)`, (2) if successful, `await database.writeSetting(key: "whisperkit_model", value: name)`, (3) update local `selectedModel` property. If step 1 throws, do NOT persist — old model stays active
  - [x] 3.5: Implement `downloadModel(name:) async` — delegate to `ModelDownloadManager`, update `modelStates`
  - [x] 3.6: Implement `cancelDownload(name:)` — delegate to `ModelDownloadManager`
  - [x] 3.7: Implement `deleteModel(name:) async` — delegate to `ModelDownloadManager`, revert to base if active model deleted
  - [x] 3.8: Wire `ModelDownloadManager` progress handler to update `modelStates` on `@MainActor`

- [x] Task 4: Create `SettingsView` with Transcription section (AC: #2)
  - [x] 4.1: Create `Features/Settings/SettingsView.swift` as SwiftUI View
  - [x] 4.2: Implement Transcription section with `ModelDownloadCard` for each available model
  - [x] 4.3: Each card shows: model name + emoji, description, badge row (size/accuracy/speed), action area (Download/Progress/Ready/Selected)
  - [x] 4.4: Card states: `available` (download button), `downloading` (progress bar + cancel), `ready` (green dot + select button), `selected` (accent border + checkmark)
  - [x] 4.5: Add warningAmber (#FF9F0A) progress bar color per UX design tokens
  - [x] 4.6: Corner radius 12pt for cards (large token per UX spec)
  - [x] 4.7: Guard all animations with `@Environment(\.accessibilityReduceMotion)`

- [x] Task 5: Create `ModelDownloadCard` reusable view (AC: #2)
  - [x] 5.1: Create `UI/Components/ModelDownloadCard.swift` — dependency-free reusable view (UI/Components rule)
  - [x] 5.2: Props: modelName, displayName, sizeLabel, accuracyLabel, speedLabel, state (enum), onDownload closure, onCancel closure, onSelect closure, onDelete closure, isSelected bool
  - [x] 5.3: Implement all 4 visual states: available, downloading, ready, selected
  - [x] 5.4: Accessibility: full state described — model name, specs, current state per UX spec
  - [x] 5.5: Download progress: percentage + estimated time remaining (rolling average speed)

- [x] Task 6: Update `TranscriptionService` for model switching (AC: #6, #7)
  - [x] 6.1: Add `func setModel(_ modelName: String) async` to `TranscriptionServiceProtocol`
  - [x] 6.2: Implement in `TranscriptionService`: store model name, reinitialize WhisperKit with new model on next transcription (lazy reload)
  - [x] 6.3: Read initial model from `AppSetting` in `TranscriptionService.init` or on first use
  - [x] 6.4: Ensure model switch never interrupts an in-progress transcription — queue the change for next transcription

- [x] Task 7: Add `AppDatabase` helper methods (AC: #9)
  - [x] 7.1: Add `func readSetting(key: String) async -> String?` to `AppDatabase`
  - [x] 7.2: Add `func writeSetting(key: String, value: String) async` to `AppDatabase`
  - [x] 7.3: These use the existing `settings` table and `AppSetting` record type

- [x] Task 8: Update `AppError` with model download cases (AC: #8)
  - [x] 8.1: Add `modelDownloadFailed(modelName: String)` case to `AppError`
  - [x] 8.2: Add `bannerMessage`, `recoveryLabel`, `sfSymbol` for the new case

- [x] Task 9: Update `MeetNotesApp` wiring (AC: #10)
  - [x] 9.1: Create `ModelDownloadManager` instance in `MeetNotesApp`
  - [x] 9.2: Create `SettingsViewModel` instance with dependencies (AppDatabase, ModelDownloadManager, TranscriptionService)
  - [x] 9.3: Inject `SettingsViewModel` into environment for SettingsView
  - [x] 9.4: Add Settings window scene or navigation to Settings from menu bar

- [x] Task 10: Write tests (AC: all)
  - [x] 10.1: `ModelDownloadManagerTests.swift` — test download state transitions, retry logic, resumable download tracking, cancellation
  - [x] 10.2: `SettingsViewModelTests.swift` — test model selection persistence, download delegation, state updates
  - [x] 10.3: `TranscriptionServiceTests.swift` updates — test `setModel()`, verify model switch doesn't interrupt active transcription
  - [x] 10.4: `StubModelDownloadManager.swift` — protocol-conforming stub for SettingsViewModel tests

## Dev Notes

### Architecture Constraints

- **ModelDownloadManager MUST be `actor`** — per project-context.md, all services are actor types
- **SettingsViewModel MUST be `@Observable @MainActor final class`** — one of the four permitted ViewModels (RecordingViewModel, MeetingListViewModel, MeetingDetailViewModel, SettingsViewModel)
- **Typed throws:** `func downloadModel(...) async throws(ModelDownloadError)` — Swift 6 typed error pattern
- **Three-layer error rule:** ModelDownloadManager throws → SettingsViewModel catches → maps to `AppError` → posts to `AppErrorState` → View renders ErrorBannerView
- **Service-to-ViewModel updates:** Use registered `@MainActor @Sendable` handler closure from ModelDownloadManager to SettingsViewModel, never direct ViewModel reference
- **No Combine/ObservableObject** — `@Observable` + `@MainActor` only
- **Database writes in service actors only** — SettingsViewModel reads settings via AppDatabase helpers; model download state managed by ModelDownloadManager actor
- **`UI/Components/` is dependency-free** — ModelDownloadCard in UI/Components must have zero ViewModel dependencies; pass data via closures and value types
- **Logger:** `private nonisolated static let logger = Logger(subsystem: "com.kuamatzin.meet-notes", category: "ModelDownloadManager")` — file-scope logger bug workaround from Story 3.2

### WhisperKit Model Management Details

- **Package:** WhisperKit (argmaxinc/WhisperKit) — already in SPM dependencies from Story 4.1
- **MANDATORY: Use `context7` MCP for WhisperKit documentation** — verify exact download API signatures, model listing API, and folder conventions before implementation. Do NOT rely on training data alone.

**WhisperKit Model Specifications:**

| Model | Download Size | Accuracy (relative) | Speed (relative) | Notes |
|-------|--------------|---------------------|-------------------|-------|
| `base` | ~145MB | Baseline | Fastest | Bundled in app; always available |
| `small` | ~465MB | +15% vs base | ~2x slower | Good balance for most users |
| `medium` | ~1.5GB | +25% vs base | ~4x slower | High accuracy, slower |
| `large-v3-turbo` | ~3.1GB | Best available | ~3x slower (turbo-optimized) | Highest accuracy with turbo speed optimization |

- **Model storage paths:**
  - Base model: bundled at `MeetNotes/Resources/whisperkit-base/` (Story 4.1 already set this up — do NOT re-bundle)
  - Downloaded models: `~/Library/Application Support/meet-notes/Models/{modelName}/`
- **Model initialization:** `WhisperKit(WhisperKitConfig(model: modelName, modelFolder: modelPath))` — specify both model name and custom folder for downloaded models

### Actor → MainActor Handler Pattern (Critical)

ModelDownloadManager (actor) communicates with SettingsViewModel (@MainActor) via handler closure:

```swift
// In ModelDownloadManager actor:
actor ModelDownloadManager {
    private var progressHandler: (@MainActor @Sendable (String, ModelDownloadState) -> Void)?

    func setProgressHandler(_ handler: @escaping @MainActor @Sendable (String, ModelDownloadState) -> Void) {
        self.progressHandler = handler
    }

    private func reportProgress(_ modelName: String, _ state: ModelDownloadState) async {
        guard let handler = progressHandler else { return }
        await MainActor.run { handler(modelName, state) }
    }
}

// In SettingsViewModel (wiring):
func wireDownloadManager() async {
    await modelDownloadManager.setProgressHandler { [weak self] modelName, state in
        self?.modelStates[modelName] = state
    }
}
```

### Updated WhisperKitProviding Factory Pattern

```swift
// BEFORE (Story 4.1):
whisperKitFactory: @escaping @Sendable () async throws -> WhisperKitProviding

// AFTER (Story 4.2):
whisperKitFactory: @escaping @Sendable (String) async throws -> WhisperKitProviding

// Usage in TranscriptionService.transcribe():
let provider = try await whisperKitFactory(currentModelName)
```

### TranscriptionService Model Switching

- **Current implementation:** `TranscriptionService` initializes WhisperKit lazily with `base` model via `WhisperKitProviding` protocol
- **Required change:** Add stored `modelName` property, read from `AppSetting` on init; `setModel()` sets the name and invalidates the cached WhisperKit instance so it reinitializes on next transcription
- **Safety rule:** Never switch models during active transcription. `setModel()` only takes effect on the NEXT `transcribe()` call. Add `isTranscribing: Bool` guard.
- **WhisperKitProviding factory:** Updated signature shown in "Updated WhisperKitProviding Factory Pattern" section above

### SettingsViewModel Design

- **Dependencies:** `AppDatabase`, `ModelDownloadManager`, `TranscriptionServiceProtocol`
- **Reads `whisperkit_model` setting** from `settings` table on load
- **Writes `whisperkit_model` setting** when user selects a new model
- **Calls `transcriptionService.setModel(name:)`** after persisting selection
- **Observes ModelDownloadManager** progress via `@MainActor @Sendable` handler closure
- **Does NOT write to database directly for model downloads** — only reads/writes `AppSetting` for model preference

### Settings Table Usage

The `settings` table already exists (created in v1 migration). Key-value pairs used:
- `"whisperkit_model"` → active model name (default: `"base"`)
- `"has_completed_onboarding"` → currently uses `@AppStorage` UserDefaults; settings table available for future migration

### ModelDownloadCard UX Specification

Per UX design spec:
- **Anatomy:** ModelName + emoji, description, badge row (size / accuracy / speed), action area
- **States:** `available` (download button), `downloading` (0–1 progress bar, warningAmber color), `ready` (green dot), `selected` (accent border)
- **Corner radius:** 12pt (large token)
- **Progress bar:** warningAmber (#FF9F0A) fill color
- **Download progress text:** percentage + estimated time remaining (rolling average speed) + speed in human format ("1.2 MB/s")
- **On completion:** checkmark animation (guarded by reduceMotion), card updates to `ready` state
- **Accessibility:** Full state described — "Downloading [model name], [N]% complete" / "[model name], ready, selected" etc.

### Audio Data Flow (unchanged from Story 4.1)

```
RecordingService.stop()
  → MixerHandle.finalizeBuffers() → [AVAudioPCMBuffer]
  → TranscriptionService.transcribe(meetingID:, audioBuffers:)
    → Uses ACTIVE model (from AppSetting, NOT a downloading model)
    → WhisperKit.transcribe(audioArray:) with SegmentDiscoveryCallback
    → Segments saved to DB → FTS5 trigger indexes
  → SummaryService.summarize(meetingID:) (stub)
```

### Existing Code to Modify

| File | Change |
|------|--------|
| `Features/Transcription/TranscriptionService.swift` | Add `setModel()`, read model from AppSetting, update WhisperKit factory to accept model name |
| `Features/Transcription/TranscriptionServiceProtocol.swift` | Add `setModel(_ modelName: String) async` to protocol |
| `App/AppError.swift` | Add `modelDownloadFailed(modelName:)` case |
| `App/MeetNotesApp.swift` | Create ModelDownloadManager, SettingsViewModel; add Settings window/navigation; inject into environment |
| `Infrastructure/Database/AppDatabase.swift` | Add `readSetting(key:)` and `writeSetting(key:value:)` convenience methods |

### New Files to Create

| File | Type | Purpose |
|------|------|---------|
| `Features/Transcription/ModelDownloadManager.swift` | `actor` | Resumable WhisperKit model download; progress publishing; retry logic |
| `Features/Settings/SettingsViewModel.swift` | `@Observable @MainActor final class` | Model selection, download orchestration, settings persistence |
| `Features/Settings/SettingsView.swift` | SwiftUI View | Settings window with Transcription section showing model cards |
| `UI/Components/ModelDownloadCard.swift` | SwiftUI View | Dependency-free model card with states: available/downloading/ready/selected |
| `MeetNotesTests/Transcription/ModelDownloadManagerTests.swift` | Tests | Download state, retry, resume, cancel tests |
| `MeetNotesTests/Settings/SettingsViewModelTests.swift` | Tests | Model selection, persistence, download delegation tests |
| `MeetNotesTests/Transcription/StubModelDownloadManager.swift` | Stub | Protocol-conforming stub for SettingsViewModel tests |

### Swift 6 Concurrency Notes (from Story 4.1)

- **SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor** — new types default to @MainActor; ModelDownloadManager must use `actor` keyword explicitly
- **`@preconcurrency import WhisperKit`** — already in codebase from Story 4.1
- **`extension AVAudioPCMBuffer: @unchecked @retroactive Sendable {}`** — already declared in Story 3.2, do NOT redeclare
- **File-scope logger bug in Swift 6.2** — use `private nonisolated static let logger` pattern on actor types
- **ModelInfo and ModelDownloadState must be `Sendable`** — use structs/enums with Sendable conformance for cross-actor communication

### Previous Story Intelligence (Story 4.1)

- `TranscriptionService` uses `WhisperKitProviding` protocol for DI — extend this pattern for model switching
- `WhisperKitProvider` struct wraps WhisperKit — needs to accept model name parameter
- `WhisperKitConfig(model: "base")` is current hardcoded init — must become configurable
- Pipeline status transitions work: `recording` → `transcribing` → `transcribed` → `complete`
- `SummaryService` stub updates status to `complete` immediately
- `AppDatabase.shared` singleton pattern — add convenience methods, don't change initialization
- State handler pattern established: `setStateHandler(_ handler: @escaping @MainActor @Sendable (RecordingState) -> Void)`
- `RecordingViewModel` state machine handles `.processing(meetingID:, phase:)` transitions

### Git Intelligence

- Only 2 commits in repo — project is early stage
- `a1e7def` — Xcode project structure with code review fixes (includes Story 4.1 implementation)
- SPM dependencies already configured: WhisperKit, GRDB.swift
- Project structure: `MeetNotes/MeetNotes/MeetNotes/` (triple-nested due to Xcode workspace)

### Project Structure Notes

- New Settings feature folder: `MeetNotes/MeetNotes/MeetNotes/Features/Settings/`
- ModelDownloadManager goes in existing: `MeetNotes/MeetNotes/MeetNotes/Features/Transcription/`
- ModelDownloadCard goes in: `MeetNotes/MeetNotes/MeetNotes/UI/Components/`
- Tests mirror source: `MeetNotes/MeetNotes/MeetNotesTests/Settings/`, `MeetNotesTests/Transcription/`
- All files must be added to `MeetNotes.xcodeproj/project.pbxproj` (Xcode project file)
- One-primary-type-per-file rule applies
- Mandatory suffixes: `ModelDownloadManager` (Service→actor uses no suffix but this is a Manager), `SettingsViewModel`, `SettingsView`, `ModelDownloadCard` (View)

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Epic 4, Story 4.2]
- [Source: _bmad-output/planning-artifacts/architecture.md#Service Pipeline, ModelDownloadManager, SettingsViewModel, Database Schema]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md#ModelDownloadCard, Design Tokens, Corner Radius]
- [Source: _bmad-output/project-context.md#Critical Implementation Rules, Swift 6 Concurrency, SwiftUI Rules]
- [Source: _bmad-output/implementation-artifacts/4-1-whisperkit-transcription-pipeline.md#Dev Notes, WhisperKit Integration]
- [Source: WhisperKit GitHub — https://github.com/argmaxinc/WhisperKit]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6

### Debug Log References

- Pre-existing flaky tests: `transcribeSavesSegmentsToDatabase` and `transcribeUpdatesPipelineStatusToTranscribing` fail intermittently when run in parallel (DB isolation issue). Both pass individually. Not introduced by this story.
- Fixed pre-existing build error: `WhisperKitProvider.transcribe` segmentCallback needed `@Sendable` annotation for Swift 6 strict concurrency.

### Completion Notes List

- Implemented `ModelDownloadManager` actor with WhisperKit download API integration, retry logic (3 retries, exponential backoff), cancellation support, and progress handler pattern
- Created `ModelDownloadManagerProtocol` with `ModelDownloadError` (typed throws) and `ModelDownloadState` enum for cross-actor communication
- Created `ModelInfo` struct with all model metadata (name, size, accuracy, speed labels)
- Implemented `SettingsViewModel` as `@Observable @MainActor final class` with model selection, download delegation, and settings persistence via `AppDatabase`
- Created `SettingsView` with Transcription section displaying `ModelDownloadCard` for each available model
- Created `ModelDownloadCard` as dependency-free reusable view in `UI/Components/` with all 4 visual states (available, downloading, ready, selected), proper accessibility labels, and design token compliance
- Updated `TranscriptionService` with `setModel()` for model switching — invalidates cached WhisperKit instance, uses `isTranscribing` guard to prevent mid-transcription switches
- Updated `whisperKitFactory` signature from `() async throws ->` to `(String) async throws ->` for model-aware initialization
- Added `loadInitialModel()` to read saved model preference from `AppSetting` on startup
- Added `readSetting(key:)` and `writeSetting(key:value:)` convenience methods to `AppDatabase`
- Added `modelDownloadFailed(modelName:)` case to `AppError` with banner message, recovery label, and SF Symbol
- Updated `MeetNotesApp` to create `ModelDownloadManager`, `SettingsViewModel`, and add Settings window scene
- Fixed `@Sendable` annotation on `segmentCallback` in `WhisperKitProviding` protocol
- Added `setModel(_ modelName: String) async` to `TranscriptionServiceProtocol`
- Created comprehensive test suites: ModelDownloadManagerTests (9 tests), SettingsViewModelTests (14 tests), TranscriptionService model switching tests (3 tests)
- Created `StubModelDownloadManager` for test injection
- Updated `StubTranscriptionService` with `setModel()` conformance
- Updated existing `TranscriptionServiceTests` for new factory signature

### File List

**New files:**
- `MeetNotes/MeetNotes/MeetNotes/Features/Transcription/ModelDownloadManager.swift`
- `MeetNotes/MeetNotes/MeetNotes/Features/Transcription/ModelDownloadManagerProtocol.swift`
- `MeetNotes/MeetNotes/MeetNotes/Features/Settings/SettingsViewModel.swift`
- `MeetNotes/MeetNotes/MeetNotes/Features/Settings/SettingsView.swift`
- `MeetNotes/MeetNotes/MeetNotes/UI/Components/ModelDownloadCard.swift`
- `MeetNotes/MeetNotes/MeetNotesTests/Transcription/ModelDownloadManagerTests.swift`
- `MeetNotes/MeetNotes/MeetNotesTests/Transcription/StubModelDownloadManager.swift`
- `MeetNotes/MeetNotes/MeetNotesTests/Settings/SettingsViewModelTests.swift`

**Modified files:**
- `MeetNotes/MeetNotes/MeetNotes/Features/Transcription/TranscriptionService.swift`
- `MeetNotes/MeetNotes/MeetNotes/Features/Transcription/TranscriptionServiceProtocol.swift`
- `MeetNotes/MeetNotes/MeetNotes/App/AppError.swift`
- `MeetNotes/MeetNotes/MeetNotes/App/MeetNotesApp.swift`
- `MeetNotes/MeetNotes/MeetNotes/Infrastructure/Database/AppDatabase.swift`
- `MeetNotes/MeetNotes/MeetNotes.xcodeproj/project.pbxproj`
- `MeetNotes/MeetNotes/MeetNotesTests/Transcription/TranscriptionServiceTests.swift`
- `MeetNotes/MeetNotes/MeetNotesTests/Transcription/StubTranscriptionService.swift`

## Change Log

- 2026-03-04: Implemented Story 4.2 — Model Management & Transcription Settings. Added ModelDownloadManager actor, SettingsViewModel, SettingsView, ModelDownloadCard, updated TranscriptionService for model switching, added AppDatabase helpers, updated AppError, wired Settings window in MeetNotesApp. 26 new tests added.
