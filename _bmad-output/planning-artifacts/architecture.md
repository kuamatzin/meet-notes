---
stepsCompleted: [1, 2, 3, 4, 5, 6, 7, 8]
inputDocuments:
  - _bmad-output/planning-artifacts/product-brief-meet-notes-2026-02-23.md
  - _bmad-output/planning-artifacts/prd.md
  - _bmad-output/planning-artifacts/ux-design-specification.md
  - _bmad-output/planning-artifacts/research/technical-macos-meeting-recording-transcription-research-2026-02-23.md
workflowType: 'architecture'
lastStep: 8
status: 'complete'
completedAt: '2026-02-24'
project_name: 'meet-notes'
user_name: 'Cuamatzin'
date: '2026-02-23'
---

# Architecture Decision Document

_This document builds collaboratively through step-by-step discovery. Sections are appended as we work through each architectural decision together._

## Project Context Analysis

### Requirements Overview

**Functional Requirements:**

39 functional requirements organized across 9 capability areas:

| Area | FRs | Architectural Implication |
|---|---|---|
| Recording Control (FR1–FR4) | 4 | MenuBarExtra + RecordingViewModel state machine |
| Audio Capture (FR5–FR9) | 5 | RecordingService actor + AsyncStream real-time bridge |
| Transcription (FR10–FR13) | 4 | TranscriptionService actor + WhisperKit + model download manager |
| AI Summarization (FR14–FR18) | 5 | SummaryService actor + protocol-based LLM provider |
| Meeting Library & Search (FR19–FR23) | 5 | GRDB DatabasePool + FTS5 full-text search |
| Onboarding & Permissions (FR24–FR27) | 4 | PermissionService + first-launch wizard view flow |
| Settings & Configuration (FR28–FR32) | 5 | SettingsStore (UserDefaults + Keychain) |
| Error Handling & Recovery (FR33–FR36) | 4 | Cross-cutting error propagation + Sparkle update integration |
| Application Lifecycle (FR37–FR39) | 3 | NSApp activation policy + AppDelegate bridge |

**Non-Functional Requirements:**

The NFRs that most strongly shape architectural decisions:

- **NFR-R3 (Real-time thread isolation):** The single hardest constraint. Enforced at the architecture level via AsyncStream bridge — no async calls, no actor calls, no I/O inside the Core Audio tap callback.
- **NFR-R2 (Recording isolation):** GRDB DatabasePool WAL mode ensures concurrent reads/writes never interrupt the audio pipeline.
- **NFR-S1 (Keychain-only API key storage):** Requires a dedicated `SecretsStore` that wraps Keychain — never UserDefaults.
- **NFR-S2 (Zero exfiltration by default):** Architecture must make cloud data transmission structurally opt-in, not just toggled.
- **NFR-A4 (Accessibility system prefs):** All SwiftUI transitions and materials must observe `@Environment(\.accessibilityReduceMotion)`, `\.accessibilityReduceTransparency`, and `\.accessibilityIncreaseContrast`.
- **NFR-I1 (OpenAI-compatible API format):** SummaryService uses a protocol; both Ollama and cloud providers conform to the same interface.
- **NFR-I4 (Resumable model downloads):** WhisperKit model download manager must track byte offsets, not restart from zero on interruption.

**Scale & Complexity:**

- Primary domain: Native macOS desktop application with real-time audio pipeline and local AI inference
- Complexity level: Medium
- Estimated architectural components: ~12 discrete modules (3 service actors, 4 ViewModels, 1 database layer, 1 permission service, 1 secrets store, 1 model download manager, 1 Sparkle integration)

### Technical Constraints & Dependencies

| Constraint | Architectural Impact |
|---|---|
| macOS 14.2+ deployment target | Core Audio Taps API availability; minimum SDK floor for all API usage |
| Apple Silicon only (arm64) | WhisperKit/CoreML/ANE inference; no Intel fallback path needed |
| No App Sandbox | Entitlements file: `com.apple.security.app-sandbox = false`; enables Core Audio Tap + screen recording |
| Hardened Runtime required | Notarization prerequisite; restricts arbitrary code execution; entitlements must be explicit |
| Swift 6 strict concurrency | All service types must be `actor` or `@MainActor`; no shared mutable state across isolation domains |
| SPM-only dependencies | WhisperKit, GRDB, OllamaKit, Sparkle — all SPM packages; no CocoaPods or Carthage |
| Outside App Store distribution | Notarized DMG + Sparkle appcast; no TestFlight or App Review gates |
| WhisperKit Intel exclusion | Must communicate clearly in onboarding for non-Apple-Silicon Macs (blocked at launch) |

**External Dependencies:**
- WhisperKit (Argmax) — CoreML inference engine; model storage in `~/Library/Application Support/meet-notes/Models/`
- GRDB.swift v7.10+ — SQLite with DatabasePool WAL; database at `~/Library/Application Support/meet-notes/meetings.db`
- OllamaKit — local Ollama HTTP client; endpoint configurable (default: `http://localhost:11434`)
- Sparkle — non-App Store auto-update; appcast hosted on GitHub Releases
- macOS Keychain — API key storage; accessed via `SecItem` APIs

### Cross-Cutting Concerns Identified

1. **Real-time thread safety** — The audio tap callback runs on a real-time OS thread. The entire architecture must treat the AsyncStream bridge as a hard boundary: nothing above the bridge (actors, database, ViewModels) may be called from below it.

2. **Permission lifecycle** — Microphone and screen recording permissions can be granted, revoked, or missing at launch. A centralized `PermissionService` observable by all consumers prevents scattered `AVCaptureDevice.authorizationStatus()` checks across the codebase.

3. **Multi-surface state synchronization** — The same recording state (idle / recording / processing) must be visible consistently in the `MenuBarExtra` menu item, the popover icon, and the main window title bar. A single `@Observable RecordingViewModel` shared across scenes solves this.

4. **Graceful degradation** — Five independent failure modes (Core Audio tap loss, model not downloaded, Ollama not running, invalid API key, network offline) must each produce a specific, actionable, non-blocking UI response. Error handling is not optional — it is a core product requirement (FR33–FR35).

5. **Accessibility compliance** — All SwiftUI transitions (sidebar auto-hide, waveform animation, state transforms) must check `@Environment(\.accessibilityReduceMotion)`. Material surfaces must check `\.accessibilityReduceTransparency`. This is a global constraint on every animated or material-based view.

6. **Security boundary** — API keys must never appear in UserDefaults, SQLite, or log output. A single `SecretsStore` abstraction wrapping Keychain is the only permitted path for credential read/write.

## Starter Template Evaluation

### Primary Technology Domain

Native macOS desktop application (Swift 6 + SwiftUI + Xcode), initialized via Xcode project wizard. No web-style CLI scaffold applies — the "starter" is the Xcode project configuration and initial SPM dependency setup.

### Starter Options Considered

| Option | Assessment |
|---|---|
| Xcode "macOS App" template (blank) | Valid starting point; requires manual menu bar, actor, and GRDB setup |
| Recap (open-source reference, github.com/RecapAI/Recap) | Identical stack (Core Audio Taps + WhisperKit + Ollama); confirms pipeline works; UI is poor — use as architecture reference, not a copy |
| swift package init --type executable | CLI-focused; not appropriate for a SwiftUI GUI app |
| Tauri / Electron | Cross-platform; explicitly rejected by PRD — macOS native is the product identity |

### Selected Starter: Xcode macOS App Template + SPM Dependencies

**Rationale:** The Xcode "macOS App (SwiftUI)" template is the canonical starting point for all native macOS apps. It generates the minimum required structure (`@main App`, `ContentView`, `Info.plist`, entitlements file) with zero unnecessary dependencies. The PRD-mandated reference implementation (Recap) validates the full technical pipeline independently — it should be cloned and studied before writing production code, but meet-notes starts fresh for clean architecture.

**Initialization Command:**

```bash
# Xcode: File → New → Project → macOS → App
# Interface: SwiftUI | Language: Swift | Include Tests: YES
# Product Name: MeetNotes | Bundle ID: com.<you>.meet-notes
#
# Build Settings:
#   MACOSX_DEPLOYMENT_TARGET = 14.2
#   ARCHS = arm64
#   SWIFT_VERSION = 6.0
#   ENABLE_HARDENED_RUNTIME = YES
#
# SPM Dependencies (File → Add Package Dependencies):
#   https://github.com/argmaxinc/WhisperKit
#   https://github.com/groue/GRDB.swift
#   https://github.com/kevinhermawan/OllamaKit
#   https://github.com/sparkle-project/Sparkle
#
# Entitlements (MeetNotes.entitlements):
#   com.apple.security.app-sandbox = false
#   com.apple.security.device.audio-input = true
#   com.apple.security.screen-recording = true
#   com.apple.security.network.client = true
```

**Architectural Decisions Provided by Starter:**

**Language & Runtime:**
Swift 6 strict concurrency mode. Actor isolation enforced at compile time. All async code uses structured concurrency (async/await + AsyncStream). No Objective-C bridging required beyond minimal Core Audio callback patterns.

**UI Framework:**
SwiftUI declarative UI with `@Observable` macro for all ViewModels. `MenuBarExtra` scene (macOS 13+) for menu bar icon and popover. `@NSApplicationDelegateAdaptor` bridge for `setActivationPolicy(.accessory)`.

**Build Tooling:**
Xcode 16.3+ required. Swift Package Manager for all dependencies — no CocoaPods, no Carthage. SwiftLint added as SPM plugin for code style enforcement.

**Testing Framework:**
XCTest + Swift Testing (Apple 2024) for unit and integration tests. XCUITest for UI automation. Protocol-based dependency injection on all services enables mock substitution in tests.

**Code Organization:**
Feature-based folder structure (see Architectural Decisions step for full layout). Each service is a Swift Actor in its own file. ViewModels are `@Observable` classes on `@MainActor`.

**Development Experience:**
Xcode 16.3+ live previews for SwiftUI views. `os_signpost` instrumentation on the audio pipeline for Instruments profiling. GitHub Actions CI runs on `macos-14` runner.

**Note:** Project initialization using the above configuration should be the first implementation story (Sprint 1, Day 1). Study Recap source code before writing `RecordingService` — it resolves the Core Audio Tap implementation questions upfront.

## Core Architectural Decisions

### Decision Priority Analysis

**Critical Decisions (Block Implementation):**
- Real-time audio thread isolation boundary (AsyncStream bridge — non-negotiable, enforced by Swift 6)
- Service pipeline communication pattern (direct actor calls — decided: Option A)
- LLM provider abstraction (single `LLMProvider` protocol — required by NFR-I1)
- API key storage (Keychain-only via `SecretsStore` — required by NFR-S1)
- Database schema with FTS5 (required for FR22–FR23 search)

**Important Decisions (Shape Architecture):**
- Audio retention strategy (transcripts only in v1.0 — decided: Option B)
- ViewModel granularity and cross-scene sharing strategy
- Error propagation pattern (`@Observable AppErrorState` — required by UX spec)
- Onboarding launch gate (`hasCompletedOnboarding` UserDefaults flag)

**Deferred Decisions (Post-MVP):**
- Raw audio storage and M4A file management (deferred to v1.1 with timestamp navigation feature)
- Opt-in crash reporting (deferred; users file GitHub issues manually)
- Database-driven pipeline status observation (deferred to v1.1 when pipeline grows more complex)
- Speaker diarization data model (deferred to v1.2)

### Data Architecture

**Decision: SQLite Schema (GRDB.swift, DatabasePool + WAL)**

Rationale: GRDB `DatabasePool` with WAL mode provides concurrent reads during writes, which is required by NFR-R2 — database writes from `TranscriptionService` must never block SwiftUI reads in the meeting list. FTS5 virtual table provides the full-text search required by FR22–FR23 with Porter stemming for natural-language queries.

```sql
-- Core tables
CREATE TABLE meetings (
    id              TEXT PRIMARY KEY,          -- UUID string
    title           TEXT NOT NULL DEFAULT '',  -- AI-generated or user-edited
    started_at      DATETIME NOT NULL,
    ended_at        DATETIME,
    duration_seconds REAL,
    audio_quality   TEXT NOT NULL DEFAULT 'full', -- 'full' | 'mic_only' | 'partial'
    summary_md      TEXT,                      -- NULL until summarization completes
    pipeline_status TEXT NOT NULL DEFAULT 'recording', -- 'recording' | 'transcribing' | 'summarizing' | 'complete' | 'failed'
    created_at      DATETIME NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE segments (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    meeting_id      TEXT NOT NULL REFERENCES meetings(id) ON DELETE CASCADE,
    start_seconds   REAL NOT NULL,
    end_seconds     REAL NOT NULL,
    text            TEXT NOT NULL,
    confidence      REAL
);

CREATE TABLE settings (
    key             TEXT PRIMARY KEY,
    value           TEXT NOT NULL
);

-- FTS5 virtual table for full-text search across all transcript text
CREATE VIRTUAL TABLE segments_fts USING fts5(
    text,
    content='segments',
    content_rowid='id',
    tokenize='porter unicode61'
);

-- Triggers to keep FTS5 in sync
CREATE TRIGGER segments_ai AFTER INSERT ON segments BEGIN
    INSERT INTO segments_fts(rowid, text) VALUES (new.id, new.text);
END;
CREATE TRIGGER segments_ad AFTER DELETE ON segments BEGIN
    INSERT INTO segments_fts(segments_fts, rowid, text) VALUES ('delete', old.id, old.text);
END;
```

**Decision: Audio File Retention — Transcripts Only (v1.0)**

- Chosen: Option B — no raw audio files written or retained in v1.0
- Rationale: Simplifies `RecordingService` significantly (no file I/O path, no storage management, no delete cascade). Users on 8GB MacBooks are not burdened with multi-GB audio archives. Re-transcription and timestamp navigation (v1.1 features) will require re-architecting this when the time comes; the `Meeting` model's absence of `audioFilePath` is an explicit marker of this deferral.
- Impact: `RecordingService` streams PCM buffers directly through `AsyncStream` to `TranscriptionService`. No intermediate audio file is written. The `Recordings/` directory is not created.
- Future path: When v1.1 adds audio storage, `Meeting` gains an optional `audioFilePath TEXT` column via a numbered GRDB migration. No other schema changes required.

**Decision: Migration Strategy**

All schema changes are handled by a single `AppDatabase` class containing a `DatabaseMigrator` with numbered, append-only migrations. Migrations already shipped are never modified. The migrator runs on every app launch; idempotent by design.

```swift
// Pattern — never modify a registered migration, only add new ones
migrator.registerMigration("v1") { db in
    // initial schema creation
}
migrator.registerMigration("v2") { db in
    // additive changes only — e.g. new column with default value
}
```

### Authentication & Security

**Decision: Keychain-Only API Key Storage via `SecretsStore`**

- Chosen: Single `SecretsStore` struct wrapping `SecItem` APIs
- Rationale: NFR-S1 is absolute — API keys never appear in UserDefaults, SQLite, plist, or log output. A dedicated abstraction enforces this at the call site: there is no other place to read or write credentials.
- Pattern: `SecretsStore` is a value type (struct) with static methods — no instantiation needed, no shared state, no actor required (Keychain is inherently thread-safe).

```swift
// Usage pattern — the only way to touch credentials
SecretsStore.save(apiKey: key, for: .openAI)
let key = SecretsStore.load(for: .openAI)  // returns nil if not set
SecretsStore.delete(for: .openAI)
```

**Decision: LLM Provider Protocol**

- Chosen: Single `LLMProvider` protocol with two concrete conformances
- Rationale: NFR-I1 requires that any OpenAI-compatible provider works without code changes. NFR-S2 requires that cloud transmission is structurally opt-in. A protocol makes both provable at compile time: `SummaryService` holds a `any LLMProvider`, instantiated by `SettingsViewModel` based on user configuration. The cloud path (`CloudAPIProvider`) is only ever instantiated when the user has explicitly entered an API key.

```swift
protocol LLMProvider: Sendable {
    func summarize(transcript: String) async throws -> String
}

actor OllamaProvider: LLMProvider { ... }      // wraps OllamaKit
actor CloudAPIProvider: LLMProvider { ... }    // wraps URLSession, OpenAI-compatible
```

**Decision: No Telemetry or Crash Reporting (v1.0)**

- Chosen: Option A — no crash reporting framework
- Rationale: NFR-S5 prohibits telemetry without explicit opt-in. Implementing an opt-in consent dialog, privacy policy reference, and crash reporting dependency adds significant complexity for v1.0. Users experiencing crashes file GitHub issues with Console.app logs. This is consistent with the open-source positioning: the community is the support channel.
- Future path: If adoption reaches scale where crash volume justifies it, a minimal opt-in Sentry integration can be added in v1.2 behind a first-launch consent sheet.

### API & Communication Patterns

**Decision: Service Pipeline — Direct Actor Calls (Sequential)**

- Chosen: Option A — `RecordingService` calls `TranscriptionService` directly; `TranscriptionService` calls `SummaryService` directly on completion
- Rationale: The pipeline is inherently linear (record → transcribe → summarize). Direct actor calls are simple, traceable in Xcode's debugger, and correct for a solo-developed v1.0. The complexity of database-driven pipeline observation (Option B) is not justified until the pipeline needs to be more resilient or parallelized (v1.1+). The `pipeline_status` column in the `meetings` table provides observability and crash-recovery even with direct calls — if the app is killed mid-transcription, the status column shows `transcribing` on relaunch and the pipeline can be restarted.
- Pipeline call chain:

```swift
// RecordingService (actor)
func stopRecording() async {
    // finalize capture, create Meeting record in DB with status='recording'
    let meetingID = await database.saveMeeting(...)
    // hand off — direct actor call
    await transcriptionService.transcribe(meetingID: meetingID, audioStream: capturedStream)
}

// TranscriptionService (actor)
func transcribe(meetingID: UUID, audioStream: AsyncStream<AVAudioPCMBuffer>) async {
    // run WhisperKit, save segments to DB, update status='transcribing' → 'complete'
    await database.updateStatus(meetingID: meetingID, status: .transcribed)
    // hand off — direct actor call
    await summaryService.summarize(meetingID: meetingID)
}

// SummaryService (actor)
func summarize(meetingID: UUID) async {
    // call LLMProvider, save summary_md to DB, update status='complete'
}
```

**Decision: Error Propagation — `@Observable AppErrorState`**

- Chosen: Shared `@Observable AppErrorState` injected via SwiftUI `.environment()`
- Rationale: The UX spec mandates inline banners (not modals) for all error states. Services need to surface errors to the UI without coupling to specific views. `AppErrorState` is the single bus: services post `AppError` values to it; any view that observes it renders the appropriate non-blocking banner.

```swift
@Observable @MainActor
final class AppErrorState {
    var current: AppError? = nil

    func post(_ error: AppError) { current = error }
    func clear() { current = nil }
}

// Services post via MainActor hop:
Task { @MainActor in appErrorState.post(.ollamaNotRunning) }
```

**Decision: Internal Communication — AsyncStream Audio Bridge**

The Core Audio tap callback is the one location where the real-time thread boundary must be respected absolutely. The rule is architectural, not advisory:

```swift
// ONLY permitted operation inside a Core Audio tap callback:
continuation.yield(buffer)

// NEVER inside a tap callback:
// - await anything
// - call actor methods
// - access the database
// - call os_log (can block)
// - allocate memory beyond buffer copy
```

`os_signpost` markers are placed immediately outside the callback boundary (in the `TranscriptionService` consumer loop) for Instruments profiling without violating real-time constraints.

### Frontend (SwiftUI) Architecture

**Decision: ViewModel Map**

Four `@Observable @MainActor` ViewModels, each with a single clear ownership domain:

| ViewModel | Owns | Injected into |
|---|---|---|
| `RecordingViewModel` | Recording state machine (`RecordingState` enum), elapsed time timer, audio quality status, active error | `MenuBarExtraScene`, `MenuBarPopoverView`, `MainWindowView` title bar |
| `MeetingListViewModel` | Meeting list (sorted by `started_at` DESC), search query string, FTS5 search results, temporal grouping | `SidebarView`, `MeetingListView` |
| `MeetingDetailViewModel` | Selected meeting's segments, summary markdown, streaming progress indicator | `TranscriptView`, `SummaryView`, `PostMeetingView` |
| `SettingsViewModel` | LLM provider choice, Ollama endpoint URL, WhisperKit model selection, launch-at-login toggle | `SettingsView`, `OnboardingView` (LLM config step) |

`RecordingViewModel` is instantiated once at the `App` struct level and passed into all scenes via `.environment()`. It is the only ViewModel that crosses scene boundaries.

**Decision: Recording State Machine**

`RecordingState` is a Swift enum that drives all UI state across all three surfaces:

```swift
enum RecordingState: Equatable {
    case idle
    case recording(startedAt: Date, audioQuality: AudioQuality)
    case processing(meetingID: UUID, phase: ProcessingPhase)  // transcribing | summarizing
    case error(AppError)
}

enum AudioQuality { case full, micOnly, partial }
enum ProcessingPhase { case transcribing(progress: Double), summarizing }
```

**Decision: Onboarding Launch Gate**

First-launch detection via `UserDefaults` boolean `hasCompletedOnboarding`. The `App` struct checks this on launch and presents the onboarding `WindowGroup` as a full-screen sheet before the main window. On reinstall, if permissions are already granted and the flag is `true`, onboarding is skipped entirely.

**Decision: Cross-Scene State Sharing**

`RecordingViewModel` and `AppErrorState` are created once in `MeetNotesApp` and injected as environment objects into all scenes:

```swift
@main
struct MeetNotesApp: App {
    @State private var recordingVM = RecordingViewModel()
    @State private var appErrorState = AppErrorState()
    @State private var navigationState = NavigationState()
    private let notificationService = NotificationService.shared

    var body: some Scene {
        MenuBarExtra("meet-notes", systemImage: "mic") {
            MenuBarPopoverView()
                .environment(recordingVM)
                .environment(appErrorState)
                .environment(navigationState)
        }
        WindowGroup("Meetings") {
            MainWindowView()
                .environment(recordingVM)
                .environment(appErrorState)
                .environment(navigationState)
        }
        .commands {
            CommandMenu("Recording") {
                Button(recordingVM.isRecording ? "Stop Recording" : "Start Recording") {
                    recordingVM.toggleRecording()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])  // Cmd+Shift+R
            }
        }
    }
}
```

**Decision: Keyboard Shortcut Dispatch**

Keyboard shortcuts are registered using SwiftUI's `.commands` modifier on the `WindowGroup` scene. This keeps shortcut definitions co-located with scene registration in `MeetNotesApp.swift` and avoids `NSEvent` global monitors that require special accessibility permissions.

| Shortcut | Action | Implementation |
|---|---|---|
| `Cmd+Shift+R` | Toggle recording start/stop | `CommandMenu` in `MeetNotesApp.swift` → `recordingVM.toggleRecording()` |
| `Cmd+F` | Focus sidebar search field | `SidebarView` — `@FocusState<Bool>` on the search `TextField`; field responds to `.focusedValue` published key |

`Cmd+F` is handled entirely within `SidebarView`: a `@FocusState<Bool>` is bound to the search `TextField`, and a `.onKeyPress` modifier on the containing view programmatically sets focus. No global key monitor is needed.

**Decision: Notification Architecture (`NotificationService`)**

Post-meeting notifications are dispatched by a dedicated `NotificationService` actor in `Infrastructure/Notifications/`. This cleanly separates notification delivery from `SummaryService` / `TranscriptionService` business logic and centralises `UNUserNotificationCenterDelegate` conformance.

```swift
// Infrastructure/Notifications/NotificationService.swift
actor NotificationService: NSObject {
    static let shared = NotificationService()

    // Called once at app launch from AppDelegate.applicationDidFinishLaunching
    func configure() {
        UNUserNotificationCenter.current().delegate = self
    }

    // Called by SummaryService after pipeline_status transitions to 'complete'
    func postMeetingReady(meetingID: UUID, firstDecision: String, firstAction: String) async {
        guard await requestPermissionIfNeeded() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Meeting summary ready"
        content.body = "\(firstDecision) · \(firstAction)"
        content.userInfo = ["meetingID": meetingID.uuidString]
        let request = UNNotificationRequest(identifier: meetingID.uuidString,
                                            content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    // Called by TranscriptionService when no LLM is configured
    func postTranscriptReady(meetingID: UUID) async {
        guard await requestPermissionIfNeeded() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Transcript ready"
        content.body = "Your meeting transcript is saved and searchable."
        content.userInfo = ["meetingID": meetingID.uuidString]
        let request = UNNotificationRequest(identifier: meetingID.uuidString,
                                            content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    private func requestPermissionIfNeeded() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if settings.authorizationStatus == .authorized { return true }
        guard settings.authorizationStatus == .notDetermined else { return false }
        return (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])) ?? false
    }
}

// Notification tap → deep-link navigation
extension NotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let idString = response.notification.request.content
                .userInfo["meetingID"] as? String,
              let meetingID = UUID(uuidString: idString) else { return }
        await NavigationState.shared.openMeeting(id: meetingID)
    }
}
```

`NavigationState` is also promoted to a shared singleton (`NavigationState.shared`) so `NotificationService` can reach it without a SwiftUI environment lookup. The `@State` instance in `MeetNotesApp` remains the SwiftUI environment value for views; `NavigationState.shared` is the same instance passed as a reference.

`AppDelegate.applicationDidFinishLaunching` calls `Task { await NotificationService.shared.configure() }`. `SummaryService` and `TranscriptionService` hold a reference to `NotificationService.shared` and call the appropriate `post*` method at pipeline completion.

### Infrastructure & Deployment

**Decision: CI/CD Release Trigger — Every Merge to `main`**

- Chosen: Option B — every merge to `main` triggers a full release build (archive → sign → notarize → DMG → GitHub Release → Sparkle appcast update)
- Rationale: For a solo open-source project in active development, continuous delivery from `main` eliminates the manual overhead of remembering to tag releases. Feature branches contain in-progress work; `main` is always releasable. The branch protection rule is simple: PRs must pass CI before merging. Any merge that breaks the build fails loudly before it ships.
- Versioning: Use `agvtool` or a build number script in the GitHub Actions workflow to auto-increment `CFBundleVersion` on each merge; `CFBundleShortVersionString` is manually set in `Info.plist` when a meaningful version milestone is reached.
- Sparkle appcast: Updated automatically at the end of the release workflow by a script that generates `appcast.xml` from the GitHub Release metadata.

**Decision: No Crash Reporting (v1.0)**

As documented above under Authentication & Security — no crash reporting dependency, no telemetry, no opt-in dialog. Users file GitHub issues with Console.app crash logs.

**Decision: Monitoring and Logging Strategy**

- Development: `Logger` (unified logging, `os.log`) with subsystem `"com.{you}.meet-notes"` and per-category channels (`recording`, `transcription`, `summary`, `database`). Log levels: `.debug` for pipeline events, `.error` for failures, `.fault` for assertion violations.
- Production: Same `Logger` calls are present but `.debug` level entries are stripped by the OS in non-debug builds. No external log drain. No persistent log files written by the app.
- Instruments: `os_signpost` intervals on the transcription consumer loop enable precise profiling of WhisperKit inference time and audio buffer throughput without runtime cost in production.

### Decision Impact Analysis

**Implementation Sequence (order matters):**

1. Xcode project setup + entitlements + Build Settings (all other work depends on this)
2. `AppDatabase` + GRDB schema + migrations (services depend on the database)
3. `SecretsStore` (SettingsViewModel depends on it before any LLM call)
4. `PermissionService` (RecordingService depends on it before starting capture)
5. `RecordingService` actor + AsyncStream bridge (core pipeline entry point)
6. `TranscriptionService` actor + WhisperKit integration (depends on RecordingService output)
7. `SummaryService` actor + `LLMProvider` protocol + both conformances (depends on TranscriptionService output)
8. `RecordingViewModel` + recording state machine (UI depends on this)
9. `MenuBarExtra` scene + `MenuBarPopoverView` (primary user-facing control surface)
10. `MainWindowView` + `SidebarView` + `MeetingListViewModel` (meeting history)
11. `MeetingDetailViewModel` + `TranscriptView` + `SummaryView` (post-meeting review)
12. `SettingsViewModel` + `SettingsView` (configuration)
13. `OnboardingView` wizard (first-launch experience)
14. `AppErrorState` + inline error banners (cross-cutting, added as each service is wired up)
15. GitHub Actions CI/CD pipeline + notarization + Sparkle appcast

**Cross-Component Dependencies:**

```
AppDatabase ←── RecordingService, TranscriptionService, SummaryService, MeetingListViewModel, MeetingDetailViewModel
SecretsStore ←── SettingsViewModel, SummaryService (CloudAPIProvider)
PermissionService ←── RecordingService (gate), OnboardingView (status display)
RecordingService ──→ TranscriptionService ──→ SummaryService   (direct actor call pipeline)
RecordingViewModel ←── RecordingService (state updates via MainActor hop)
AppErrorState ←── all services (post errors), all views (render banners)
LLMProvider protocol ←── OllamaProvider, CloudAPIProvider (conformances)
                     ←── SummaryService (consumer, provider-agnostic)
RecordingViewModel ←── MenuBarExtraScene, MainWindowView, MenuBarPopoverView (shared via .environment)
```

## Implementation Patterns & Consistency Rules

### Critical Conflict Points Identified

8 areas where AI agents could make different, incompatible choices without explicit rules:

1. Swift type naming vs. file naming (type suffix conventions)
2. Actor vs. class vs. struct for service types
3. `@Observable` vs. `ObservableObject` (Swift 6 has both; only one is permitted here)
4. Database `snake_case` column naming vs. Swift `camelCase` property naming (mapping must be explicit)
5. `async throws` error type discipline (typed vs. untyped throws consistency)
6. Where GRDB model conformances live vs. service logic
7. Logging call sites (`Logger` vs. `print` vs. `os_log`)
8. SwiftUI view composition granularity (breaking `@Environment` injection chains)

### Naming Patterns

**Swift Type Naming — Suffixes Are Mandatory and Exact:**

| Type category | Required suffix | Example |
|---|---|---|
| Swift Actor wrapping a system service | `Service` | `RecordingService`, `TranscriptionService`, `SummaryService` |
| `@Observable @MainActor` class driving SwiftUI views | `ViewModel` | `RecordingViewModel`, `MeetingListViewModel` |
| GRDB `Record` / `FetchableRecord` struct | no suffix | `Meeting`, `TranscriptSegment`, `AppSetting` |
| SwiftUI `View` struct | `View` | `MeetingListView`, `TranscriptView`, `SidebarView` |
| Protocol | no suffix unless it describes a role | `LLMProvider`, `AudioCaptureServiceProtocol` |
| Enum of app-level states | `State` or `Phase` | `RecordingState`, `ProcessingPhase` |
| Enum of error cases | `Error` | `AppError`, `RecordingError` |
| Struct with only static methods (no state) | `Store` | `SecretsStore` |
| `@main` App struct | `App` | `MeetNotesApp` |

Agents MUST use the exact suffix above. Using `VM`, `Manager`, `Handler`, `Controller`, or abbreviating is a pattern violation.

**File Naming:**
Every Swift file is named exactly after the primary type it contains: `RecordingService.swift`, `MeetingListViewModel.swift`, `Meeting.swift`, `TranscriptView.swift`. One primary type per file. Nested helper types that are only used by that type may live in the same file.

**Database Column Naming:**
SQL schema uses `snake_case` for all table and column names. GRDB model structs use `camelCase` Swift properties. The mapping is explicit via a `Columns` enum — never rely on automatic name transformation.

```swift
// CORRECT — explicit mapping, no ambiguity
struct Meeting: Codable, FetchableRecord, PersistableRecord {
    var id: UUID
    var startedAt: Date        // maps to started_at column
    var audioQuality: String   // maps to audio_quality column

    enum Columns {
        static let id = Column("id")
        static let startedAt = Column("started_at")
        static let audioQuality = Column("audio_quality")
    }
}

// WRONG — relying on automatic snake_case conversion
struct Meeting: Codable, FetchableRecord, PersistableRecord {
    var startedAt: Date  // do NOT rely on auto-conversion
}
```

**Logging Channel Naming:**
One `Logger` instance per source file, declared at file scope (not inside a type). The `category` string matches the file's primary type name exactly.

```swift
// CORRECT — in RecordingService.swift
private let logger = Logger(subsystem: "com.{you}.meet-notes", category: "RecordingService")

// WRONG — generic categories
private let logger = Logger(subsystem: "com.{you}.meet-notes", category: "audio")
private let logger = Logger(subsystem: "com.{you}.meet-notes", category: "service")
```

### Structure Patterns

**Project Folder Organization — Feature-Based:**

```
MeetNotes/
├── App/
│   ├── MeetNotesApp.swift          # @main entry point, scene declarations
│   ├── AppDelegate.swift           # @NSApplicationDelegateAdaptor target
│   └── AppError.swift              # top-level AppError enum (all user-facing error cases)
├── Features/
│   ├── Recording/
│   │   ├── RecordingService.swift
│   │   ├── RecordingViewModel.swift
│   │   └── RecordingState.swift
│   ├── Transcription/
│   │   ├── TranscriptionService.swift
│   │   └── ModelDownloadManager.swift
│   ├── Summary/
│   │   ├── SummaryService.swift
│   │   ├── LLMProvider.swift           # protocol definition
│   │   ├── OllamaProvider.swift
│   │   └── CloudAPIProvider.swift
│   ├── MeetingList/
│   │   ├── MeetingListViewModel.swift
│   │   └── MeetingListView.swift
│   ├── MeetingDetail/
│   │   ├── MeetingDetailViewModel.swift
│   │   ├── TranscriptView.swift
│   │   └── SummaryView.swift
│   ├── Settings/
│   │   ├── SettingsViewModel.swift
│   │   └── SettingsView.swift
│   └── Onboarding/
│       └── OnboardingView.swift
├── Infrastructure/
│   ├── Database/
│   │   ├── AppDatabase.swift           # DatabasePool init, migrator
│   │   ├── Meeting.swift               # GRDB record type
│   │   └── TranscriptSegment.swift     # GRDB record type
│   ├── Permissions/
│   │   └── PermissionService.swift
│   └── Secrets/
│       └── SecretsStore.swift
├── UI/
│   ├── MenuBar/
│   │   └── MenuBarPopoverView.swift
│   ├── MainWindow/
│   │   ├── MainWindowView.swift
│   │   └── SidebarView.swift
│   └── Components/                     # reusable SwiftUI subviews only — no ViewModel dependencies
│       ├── WaveformView.swift
│       ├── ErrorBannerView.swift
│       └── StatusPillView.swift
└── MeetNotesTests/
    ├── Recording/
    │   └── RecordingServiceTests.swift
    ├── Transcription/
    │   └── TranscriptionServiceTests.swift
    └── Infrastructure/
        ├── AppDatabaseTests.swift
        └── SecretsStoreTests.swift
```

Rule: Tests live in `MeetNotesTests/` in a folder mirroring the source feature folder. Co-located test files (`.swift` next to the source) are not used.

Rule: The `UI/Components/` folder is exclusively for reusable subviews with no ViewModel dependency. Views that require ViewModel injection live in their feature folder, not in `Components/`.

### Format Patterns

**Swift Concurrency — Actor and `@MainActor` Discipline:**

Services are `actor` types. ViewModels are `@Observable @MainActor final class` types. These are not interchangeable.

```swift
// CORRECT — service is an actor
actor RecordingService {
    private var isRecording = false
    func start() async throws { ... }
}

// CORRECT — ViewModel is @Observable @MainActor final class
@Observable @MainActor
final class RecordingViewModel {
    var state: RecordingState = .idle
}

// WRONG — ViewModel as actor (breaks SwiftUI @Observable integration)
actor RecordingViewModel { ... }

// WRONG — service as @MainActor class (wrong isolation domain)
@MainActor class RecordingService { ... }
```

**`@Observable` Only — No `ObservableObject`:**

Swift 6 projects use `@Observable` macro exclusively. `ObservableObject`, `@Published`, and `@StateObject` are not used anywhere in this codebase.

```swift
// CORRECT
@Observable @MainActor final class MeetingListViewModel {
    var meetings: [Meeting] = []
}

// WRONG — legacy pattern, prohibited
class MeetingListViewModel: ObservableObject {
    @Published var meetings: [Meeting] = []
}
```

**`async throws` Typed Error Discipline:**

Services throw typed domain errors. ViewModels catch service errors and post to `AppErrorState` — they never rethrow to views.

```swift
// CORRECT — service throws typed domain error
actor TranscriptionService {
    func transcribe(...) async throws(TranscriptionError) -> [TranscriptSegment] { ... }
}

// CORRECT — ViewModel catches and routes to AppErrorState, never rethrows
@Observable @MainActor final class RecordingViewModel {
    func stopRecording() async {
        do {
            try await recordingService.stop()
        } catch {
            appErrorState.post(.from(error))
        }
    }
}

// WRONG — ViewModel rethrows to the view layer
func stopRecording() async throws { ... }
```

**`AsyncStream` Bridge — The Only Safe Real-Time Crossing:**

The Core Audio tap callback must only call `continuation.yield()`. No other operation is permitted. This rule has no exceptions.

```swift
// CORRECT — only yield inside the callback
audioEngine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [continuation] buffer, _ in
    continuation.yield(buffer)
}

// ALL of the following are WRONG inside a tap callback:
await someActor.process(buffer)    // async call on real-time thread
database.save(buffer)              // I/O on real-time thread
os_log("buffer received")         // can block
NotificationCenter.default.post(…) // synchronization overhead
```

### Communication Patterns

**Service → ViewModel State Updates — No Direct References:**

Services update ViewModel state by hopping to `@MainActor` via a registered closure. Services never hold a direct reference to a ViewModel.

```swift
// CORRECT — service notifies via MainActor hop through registered handler
actor RecordingService {
    private var onStateChange: (@MainActor (RecordingState) -> Void)?

    func setStateHandler(_ handler: @escaping @MainActor (RecordingState) -> Void) {
        onStateChange = handler
    }

    private func updateState(_ newState: RecordingState) async {
        await MainActor.run { onStateChange?(newState) }
    }
}

// WRONG — service holds direct ViewModel reference (retain cycle + isolation violation)
actor RecordingService {
    var viewModel: RecordingViewModel?
}
```

**GRDB `ValueObservation` for Live UI Updates:**

ViewModels that display live data use GRDB `ValueObservation`. Polling and manual refresh are not used.

```swift
// CORRECT — ValueObservation drives live meeting list
@Observable @MainActor final class MeetingListViewModel {
    var meetings: [Meeting] = []

    func startObserving(database: AppDatabase) {
        let observation = ValueObservation.tracking(Meeting.fetchAll)
        observation.start(in: database.pool, scheduling: .mainActor) { [weak self] meetings in
            self?.meetings = meetings
        } onError: { [weak self] error in
            // post to AppErrorState
        }
    }
}

// WRONG — polling
Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
    self.meetings = try? database.fetchAll()
}
```

**`AppError` — Single Exhaustive Enum, All User-Facing Errors:**

All errors that reach the UI are cases of the single `AppError` enum in `App/AppError.swift`. Domain-specific internal errors are converted to `AppError` at the service boundary before being posted to `AppErrorState`. Views only ever see `AppError`.

```swift
// CORRECT — single enum, exhaustive, in App/AppError.swift
enum AppError: LocalizedError {
    case microphonePermissionDenied
    case screenRecordingPermissionDenied
    case audioTapLost
    case modelNotDownloaded(modelName: String)
    case ollamaNotReachable(endpoint: String)
    case invalidAPIKey
    case networkUnavailable
    case transcriptionFailed(underlying: Error)
    case summarizationFailed(underlying: Error)
}

// WRONG — posting a raw system error directly
appErrorState.post(.init(rawError: someNSError))
```

### Process Patterns

**Error Handling — The Three-Layer Rule:**

Every error passes through exactly three layers before reaching the user:

1. **Service layer** — throws a typed domain error (`RecordingError`, `TranscriptionError`, etc.)
2. **ViewModel layer** — catches domain error, maps to `AppError`, posts to `AppErrorState`. Never rethrows.
3. **View layer** — reads `AppErrorState.current` and renders `ErrorBannerView`. Never calls `try`.

No layer skips another. Views never call throwing functions.

**Loading / Processing States — Encoded in `RecordingState` Enum, Not Boolean Flags:**

```swift
// CORRECT — state encodes phase, no ambiguity about combined states
case processing(meetingID: UUID, phase: ProcessingPhase)

// WRONG — parallel boolean flags create impossible states
var isRecording: Bool = false
var isTranscribing: Bool = false
var isLoading: Bool = false
```

**GRDB Writes — Service Actors Only, ViewModels Are Read-Only:**

Database writes are performed exclusively inside service actors. ViewModels observe via `ValueObservation` and never call `database.pool.write`.

```swift
// CORRECT — write inside the service actor
actor TranscriptionService {
    func saveSegments(_ segments: [TranscriptSegment], to database: AppDatabase) async throws {
        try await database.pool.write { db in
            for segment in segments { try segment.insert(db) }
        }
    }
}

// WRONG — ViewModel writing to the database
@MainActor final class MeetingDetailViewModel {
    func deleteSegment(_ segment: TranscriptSegment) async {
        try? await database.pool.write { db in try segment.delete(db) }  // PROHIBITED
    }
}
```

**SwiftUI View Composition — Maximum Nesting Depth:**

No SwiftUI view's `body` exceeds 3 levels of nesting before extracting a named subview. This prevents monolithic views and ensures `@Environment` injection points are predictable.

**Accessibility — Environment Check on Every Transition:**

Every `withAnimation {}` call and every `.animation()` modifier is guarded by `@Environment(\.accessibilityReduceMotion)`. No exceptions — this includes the waveform animation, sidebar slide, and all state-driven window transforms.

```swift
// CORRECT
@Environment(\.accessibilityReduceMotion) private var reduceMotion

var body: some View {
    sidebar
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: sidebarVisible)
}

// WRONG — unguarded animation (violates NFR-A4)
.animation(.easeInOut(duration: 0.25), value: sidebarVisible)
```

### Enforcement Guidelines

**All AI Agents MUST:**

- Use `@Observable @MainActor final class` for every ViewModel — never `ObservableObject`
- Use `actor` for every service type — never `@MainActor class`
- Place GRDB writes exclusively inside service actors — ViewModels are strictly read-only
- Use the exact type-name suffix table above — no abbreviations or alternatives
- Guard every animation and transition with `@Environment(\.accessibilityReduceMotion)`
- Declare `Logger` at file scope with `category` equal to the containing type's exact name
- Convert domain errors to `AppError` at the service boundary — views only ever see `AppError`
- Never call async functions, perform I/O, or log inside a Core Audio tap callback
- Map all SQL `snake_case` columns to Swift `camelCase` properties via an explicit `Columns` enum

**Anti-Patterns — Prohibited in This Codebase:**

| Anti-pattern | Why prohibited |
|---|---|
| `ObservableObject` / `@Published` / `@StateObject` | Legacy; incompatible with Swift 6 `@Observable` ownership model |
| `@MainActor class RecordingService` | Wrong isolation domain; services must be `actor` types |
| `actor RecordingViewModel` | Breaks `@Observable` SwiftUI integration |
| `print()` for logging | Not visible in Console.app; not filterable; inconsistently stripped |
| Boolean loading flags parallel to a state enum | Creates impossible states; the enum is the single source of truth |
| ViewModel calling `database.pool.write` | Breaks write-ownership invariant; potential data races under Swift 6 |
| Raw `NSError` / `Error` posted to `AppErrorState` | Views cannot render actionable messages from untyped errors |
| Unguarded `withAnimation` or `.animation()` | Violates NFR-A4 and macOS accessibility expectations |
| Co-located test files next to source | Tests live in `MeetNotesTests/` mirroring the source folder structure |
| Reusable view with ViewModel dependency in `UI/Components/` | Components folder is dependency-free subviews only |

## Project Structure & Boundaries

### Complete Project Directory Structure

```
meet-notes/                                      # repository root
├── README.md
├── CONTRIBUTING.md
├── .gitignore
├── .github/
│   └── workflows/
│       ├── ci.yml                               # PR check: build + test on macos-14
│       └── release.yml                          # main branch: archive → sign → notarize → DMG → GitHub Release → Sparkle appcast
├── MeetNotes.xcodeproj/
│   ├── project.pbxproj
│   └── xcshareddata/
│       └── xcschemes/
│           └── MeetNotes.xcscheme
├── MeetNotes/                                   # primary source target
│   ├── MeetNotes.entitlements
│   ├── Info.plist
│   │
│   ├── App/
│   │   ├── MeetNotesApp.swift                   # @main; MenuBarExtra + WindowGroup scenes; shared VM creation; .commands keyboard shortcuts
│   │   ├── AppDelegate.swift                    # @NSApplicationDelegateAdaptor; setActivationPolicy(.accessory); Sparkle init; NotificationService.configure()
│   │   ├── AppError.swift                       # exhaustive AppError enum; all user-facing error cases
│   │   └── NavigationState.swift                # @Observable @MainActor; selectedMeetingID: UUID?; openMeeting(id:) — shared singleton + SwiftUI env value
│   │
│   ├── Features/
│   │   ├── Recording/
│   │   │   ├── RecordingService.swift           # actor; Core Audio Tap + AVAudioEngine; AsyncStream bridge; direct pipeline handoff
│   │   │   ├── RecordingViewModel.swift         # @Observable @MainActor; RecordingState machine; elapsed timer; shared across all scenes
│   │   │   └── RecordingState.swift             # enum RecordingState { idle, recording, processing, error }
│   │   │
│   │   ├── Transcription/
│   │   │   ├── TranscriptionService.swift       # actor; WhisperKit integration; saves segments to DB; calls SummaryService on completion
│   │   │   └── ModelDownloadManager.swift       # actor; resumable WhisperKit model download; publishes progress
│   │   │
│   │   ├── Summary/
│   │   │   ├── SummaryService.swift             # actor; calls LLMProvider; saves summary_md to DB; updates pipeline_status
│   │   │   ├── LLMProvider.swift                # protocol LLMProvider: Sendable { func summarize(transcript:) async throws -> String }
│   │   │   ├── OllamaProvider.swift             # actor; LLMProvider conformance; wraps OllamaKit; default provider
│   │   │   └── CloudAPIProvider.swift           # actor; LLMProvider conformance; URLSession + OpenAI-compatible endpoint; opt-in
│   │   │
│   │   ├── MeetingList/
│   │   │   ├── MeetingListViewModel.swift       # @Observable @MainActor; GRDB ValueObservation; FTS5 search; temporal grouping
│   │   │   └── MeetingListView.swift            # sidebar list; Today / This Week / Older grouping; hover-reveal row actions
│   │   │
│   │   ├── MeetingDetail/
│   │   │   ├── MeetingDetailViewModel.swift     # @Observable @MainActor; loads segments + summary; streaming progress
│   │   │   ├── TranscriptView.swift             # scrollable segment list; timestamps; text selection popover
│   │   │   └── SummaryView.swift                # structured summary: Decisions / Actions / Key Topics; streaming token display
│   │   │
│   │   ├── Settings/
│   │   │   ├── SettingsViewModel.swift          # @Observable @MainActor; LLM provider; Ollama endpoint; model; launch-at-login
│   │   │   └── SettingsView.swift               # LLM section + Transcription model cards + General section
│   │   │
│   │   └── Onboarding/
│   │       ├── OnboardingViewModel.swift        # @Observable @MainActor; wizard step state; permission status; test recording
│   │       └── OnboardingView.swift             # 3-step full-screen wizard: Welcome → Permissions+Test → Done
│   │
│   ├── Infrastructure/
│   │   ├── Database/
│   │   │   ├── AppDatabase.swift                # DatabasePool init (WAL mode); DatabaseMigrator; shared access point
│   │   │   ├── Meeting.swift                    # GRDB FetchableRecord+PersistableRecord; Columns enum
│   │   │   └── TranscriptSegment.swift          # GRDB FetchableRecord+PersistableRecord; Columns enum
│   │   ├── Notifications/
│   │   │   └── NotificationService.swift        # actor + UNUserNotificationCenterDelegate; postMeetingReady/postTranscriptReady; permission request; tap → NavigationState.openMeeting
│   │   ├── Permissions/
│   │   │   └── PermissionService.swift          # @Observable @MainActor; TCC status for mic + screen recording; revocation detection
│   │   └── Secrets/
│   │       └── SecretsStore.swift               # struct (static methods only); SecItem Keychain read/write/delete
│   │
│   └── UI/
│       ├── MenuBar/
│       │   └── MenuBarPopoverView.swift         # status pill; Start/Stop button; elapsed time; open main window
│       ├── MainWindow/
│       │   ├── MainWindowView.swift             # NavigationSplitView root; state-driven transforms (idle/recording/post-meeting)
│       │   └── SidebarView.swift                # .ultraThinMaterial glass; 🔒 On-device badge; search; MeetingListView; record CTA
│       └── Components/
│           ├── WaveformView.swift               # 3-bar animated waveform; reduceMotion-aware
│           ├── ErrorBannerView.swift            # inline non-blocking banner; single recovery CTA; reads AppErrorState
│           ├── StatusPillView.swift             # glassmorphic pill: 🔒 On-device / ● Recording / ⚙ Processing
│           └── ModelDownloadCardView.swift      # model size/accuracy/speed card; download progress ring
│
├── MeetNotesTests/
│   ├── Recording/
│   │   ├── RecordingServiceTests.swift          # mock AudioCaptureServiceProtocol; state transition tests
│   │   └── RecordingStateTests.swift            # pure enum logic tests
│   ├── Transcription/
│   │   ├── TranscriptionServiceTests.swift      # mock WhisperKit; segment DB write tests
│   │   └── ModelDownloadManagerTests.swift      # mock URLSession; resumable download logic
│   ├── Summary/
│   │   ├── SummaryServiceTests.swift            # mock LLMProvider; summary DB write + error mapping
│   │   ├── OllamaProviderTests.swift            # integration test; @TestAvailability(requiresOllama)
│   │   └── CloudAPIProviderTests.swift          # mock URLSession; OpenAI-compatible request/response
│   ├── Infrastructure/
│   │   ├── AppDatabaseTests.swift               # in-memory pool; migration correctness; FTS5 round-trip
│   │   ├── MeetingTests.swift                   # GRDB CRUD; Columns mapping correctness
│   │   ├── TranscriptSegmentTests.swift         # FTS5 search; porter stemming; segment CRUD
│   │   ├── SecretsStoreTests.swift              # Keychain round-trip; all LLMProviderKey cases
│   │   └── NotificationServiceTests.swift       # mock UNUserNotificationCenter; permission flow; payload correctness; tap → NavigationState routing
│   └── UI/
│       └── RecordingViewModelTests.swift        # state machine transitions; error posting; cross-scene logic
│
└── MeetNotesUITests/
    ├── OnboardingFlowTests.swift                # wizard 3 steps; skip-on-reinstall path
    ├── RecordingFlowTests.swift                 # start → stop → processing → post-meeting view
    └── SearchFlowTests.swift                    # search bar → FTS5 results → meeting detail navigation
```

### Architectural Boundaries

**Real-Time Boundary (hardest constraint):**

The Core Audio tap callback is the only location in the entire codebase that runs on a real-time OS thread. This boundary is enforced by Swift 6 actor isolation — nothing inside the callback may cross into any actor or MainActor context except via `AsyncStream.continuation.yield()`. Everything above `RecordingService`'s `AsyncStream` consumer loop is in standard Swift concurrency.

```
┌─────────────────────────────────────────────────────────────────┐
│  REAL-TIME THREAD (Core Audio tap callback)                     │
│  Only permitted operation: continuation.yield(buffer)           │
└──────────────────────────────┬──────────────────────────────────┘
                               │ AsyncStream<AVAudioPCMBuffer>
                               │ ← THE ONLY SAFE CROSSING ←
┌──────────────────────────────▼──────────────────────────────────┐
│  SWIFT CONCURRENCY (actor / async-await)                        │
│  RecordingService → TranscriptionService → SummaryService       │
│  AppDatabase (GRDB DatabasePool WAL)                            │
│  @MainActor ViewModels → SwiftUI views                          │
└─────────────────────────────────────────────────────────────────┘
```

**Service Layer Boundary:**

Each service actor owns its domain completely and exposes only async methods. No service holds a reference to another service's internals or to any ViewModel. The pipeline is a directed chain with no cycles.

```
RecordingService  ──(direct actor call)──▶  TranscriptionService
                                                    │
                                         (direct actor call)
                                                    ▼
                                            SummaryService
```

All three services write to `AppDatabase` directly. No service reads from the database what another service wrote — each reads only its own output domain.

**ViewModel / View Boundary:**

ViewModels are `@MainActor` — they own the UI thread. Services are actors on cooperative thread pool threads. The handoff from service to ViewModel always uses `await MainActor.run {}` or a registered `@MainActor` closure. Views never call service methods directly — they call ViewModel methods only.

```
Services (actor thread pool) ──[MainActor hop]──▶ ViewModels (@MainActor) ──▶ Views (SwiftUI)
```

**Privacy / Security Boundary:**

The `CloudAPIProvider` actor is the only location in the entire codebase where data leaves the device. It is instantiated exclusively when the user has an API key in `SecretsStore`. `OllamaProvider` communicates only with `localhost`. The `NFR-S2` privacy boundary is enforced structurally, not by a runtime check.

```
Local processing path (default):
  RecordingService → TranscriptionService → OllamaProvider → AppDatabase
  ↑ No network, no exfiltration, no exceptions

Cloud opt-in path (user must configure API key):
  RecordingService → TranscriptionService → CloudAPIProvider → external HTTPS endpoint
  ↑ Only reachable if SecretsStore.load(for: .openAI/anthropic) returns non-nil
```

### Requirements to Structure Mapping

**FR Category → Primary File(s):**

| FR | Requirement | Primary file(s) |
|---|---|---|
| FR1–FR2 | Start/stop recording from any context | `RecordingViewModel.swift`, `MenuBarPopoverView.swift` |
| FR3–FR4 | Menu bar state + elapsed time | `RecordingState.swift`, `WaveformView.swift`, `StatusPillView.swift` |
| FR5–FR7 | System audio + mic capture + mix | `RecordingService.swift` |
| FR8–FR9 | Tap loss detection + mic-only fallback | `RecordingService.swift`, `RecordingState.swift` |
| FR10 | On-device transcription | `TranscriptionService.swift` |
| FR11–FR12 | Model selection + on-demand download | `ModelDownloadManager.swift`, `SettingsView.swift`, `ModelDownloadCardView.swift` |
| FR13 | Transcription status + progress | `RecordingViewModel.swift`, `MeetingDetailViewModel.swift` |
| FR14–FR15 | API key config + Ollama endpoint config | `SettingsViewModel.swift`, `SettingsView.swift`, `SecretsStore.swift` |
| FR16 | Structured summary generation | `SummaryService.swift`, `OllamaProvider.swift`, `CloudAPIProvider.swift` |
| FR17 | Transcript-only mode (no LLM) | `SummaryService.swift` (graceful nil-provider path) |
| FR18 | View AI summary + post-meeting notification | `SummaryView.swift`, `MeetingDetailViewModel.swift`, `NotificationService.swift` |
| FR19–FR21 | Meeting list + open transcript/summary | `MeetingListView.swift`, `MeetingListViewModel.swift`, `MeetingDetailViewModel.swift` |
| FR22–FR23 | Full-text search + highlight matches | `MeetingListViewModel.swift` (FTS5 query), `TranscriptSegment.swift` (FTS5 table) |
| FR24–FR27 | First-launch permissions wizard | `OnboardingView.swift`, `OnboardingViewModel.swift`, `PermissionService.swift` |
| FR28–FR32 | Settings panel (all config) | `SettingsView.swift`, `SettingsViewModel.swift` |
| FR33–FR35 | Error detection + actionable recovery | `AppError.swift`, `AppErrorState` (in `MeetNotesApp.swift`), `ErrorBannerView.swift` |
| FR36 | In-app update availability | `AppDelegate.swift` (Sparkle `SPUUpdater` init + check) |
| FR37–FR38 | Menu bar utility lifecycle + open window + deep-link navigation | `MeetNotesApp.swift`, `AppDelegate.swift`, `NavigationState.swift` |
| FR39 | Quit from menu bar | `MenuBarPopoverView.swift` |

**Cross-Cutting Concerns → Files:**

| Concern | Files |
|---|---|
| Real-time thread safety | `RecordingService.swift` (AsyncStream bridge) |
| Permission lifecycle | `PermissionService.swift`, `OnboardingView.swift`, `RecordingService.swift` (pre-flight check) |
| Multi-surface state sync | `RecordingViewModel.swift` (single instance via `.environment()`), `MeetNotesApp.swift` |
| Graceful degradation | `AppError.swift`, `ErrorBannerView.swift`, all service `catch` blocks |
| Accessibility compliance | Every file in `UI/` (reduceMotion checks), `SidebarView.swift` (reduceTransparency), `Components/` |
| Security boundary | `SecretsStore.swift`, `CloudAPIProvider.swift` (only network-touching file) |

### Integration Points

**Internal Component Communication:**

```
MeetNotesApp (creates shared instances)
    │
    ├── injects RecordingViewModel ──────────────────────────────┐
    │   via .environment() into:                                  │
    │   ├── MenuBarPopoverView                                    │
    │   └── MainWindowView ──▶ SidebarView ──▶ MeetingListView   │
    │                                                             │
    ├── injects AppErrorState                                     │
    │   via .environment() into all scenes                        │
    │                                                             │
    └── RecordingViewModel ◀── RecordingService ◀─ (MainActor hop)
        RecordingService ──▶ TranscriptionService ──▶ SummaryService
        All services ──▶ AppDatabase (GRDB DatabasePool)
        MeetingListViewModel ◀── GRDB ValueObservation (live)
        MeetingDetailViewModel ◀── GRDB one-shot fetch + streaming
```

**External Integrations:**

| Integration | File | Network? | Notes |
|---|---|---|---|
| WhisperKit (CoreML/ANE) | `TranscriptionService.swift`, `ModelDownloadManager.swift` | Download only | Model inference is fully local after download |
| OllamaKit (localhost) | `OllamaProvider.swift` | localhost only | `http://localhost:11434`; no internet |
| OpenAI-compatible API | `CloudAPIProvider.swift` | Yes (opt-in) | Only when API key present in Keychain |
| Sparkle auto-update | `AppDelegate.swift` | Yes (update check) | GitHub Releases appcast; user can disable |
| macOS Keychain | `SecretsStore.swift` | No | SecItem API; local device only |
| macOS TCC (permissions) | `PermissionService.swift` | No | AVCaptureDevice + NSBundle authorization |

**Data Flow — Complete Recording Session:**

```
1. User taps Start Recording (MenuBarPopoverView)
   → RecordingViewModel.startRecording()
   → PermissionService.checkAll() → guard permissions granted
   → RecordingService.start()
       → Core Audio Tap installed on meeting app process
       → AVAudioEngine mic tap installed
       → Both taps yield AVAudioPCMBuffer into AsyncStream
       → AppDatabase: INSERT meeting (status='recording')
       → RecordingViewModel state → .recording(startedAt:, audioQuality: .full)

2. Audio flows (real-time → Swift concurrency boundary)
   → AsyncStream<AVAudioPCMBuffer> consumed by RecordingService
   → AVAudioConverter: resample to 16kHz mono Float32

3. User taps Stop (MenuBarPopoverView or SidebarView)
   → RecordingService.stop()
       → Tears down Core Audio Tap + AVAudioEngine tap
       → Finalizes AVAudioPCMBuffer accumulation
       → AppDatabase: UPDATE meeting SET ended_at, duration_seconds
       → direct actor call → TranscriptionService.transcribe(meetingID:, audioStream:)
   → RecordingViewModel state → .processing(phase: .transcribing(progress: 0))

4. Transcription pipeline
   → TranscriptionService feeds chunks to WhisperKit (CoreML/ANE)
   → WhisperKit yields TranscriptSegment values
   → AppDatabase: INSERT segments; INSERT into segments_fts (via trigger)
   → RecordingViewModel state ← (MainActor hop) → .processing(phase: .transcribing(progress: x))
   → On completion: AppDatabase UPDATE meeting SET pipeline_status='transcribed'
   → direct actor call → SummaryService.summarize(meetingID:)

5. Summarization pipeline
   → SummaryService fetches all segments for meetingID from AppDatabase
   → Calls active LLMProvider.summarize(transcript:)
       Path A (Ollama): OllamaProvider → POST localhost:11434 → streaming response
       Path B (Cloud):  CloudAPIProvider → POST api.openai.com → streaming response
       Path C (none):   SummaryService returns early; meeting marked complete with nil summary_md
   → AppDatabase: UPDATE meeting SET summary_md, pipeline_status='complete'
   → RecordingViewModel state ← (MainActor hop) → .idle
   → macOS notification posted: "Meeting ready — [first decision or action item]"

6. Post-meeting view
   → MeetingListViewModel GRDB ValueObservation fires (new meeting row visible)
   → User taps meeting → MeetingDetailViewModel.load(meetingID:)
       → Fetch segments from AppDatabase
       → Fetch summary_md from AppDatabase
       → Render TranscriptView + SummaryView

7. Search (FR22–FR23)
   → MeetingListViewModel.search(query:)
   → GRDB FTS5 query: SELECT segments.meeting_id, snippet(...) WHERE segments_fts MATCH ?
   → Results grouped by meeting_id, ranked by relevance
   → MeetingListView updates with highlighted match rows
```

### File Organization Patterns

**Configuration Files (repository root):**

| File | Purpose |
|---|---|
| `.github/workflows/ci.yml` | PR build + test gate; runs on every PR to `main` |
| `.github/workflows/release.yml` | Full release pipeline; runs on every merge to `main` |
| `.gitignore` | Excludes `DerivedData/`, `*.xcuserstate`, `build/`, `.DS_Store` |
| `README.md` | Install instructions, system requirements (Apple Silicon, macOS 14.2+), screenshots |
| `CONTRIBUTING.md` | Codebase architecture overview, PR process, code style guide (links to patterns section) |

**Source Organization Rules:**

- One primary Swift type per file; file named after that type
- Feature folders are self-contained; cross-feature dependencies go through `Infrastructure/` or `App/`
- `UI/Components/` contains only pure display components with no service or ViewModel dependencies
- All GRDB record types live in `Infrastructure/Database/`; no GRDB imports in `Features/` files
- `App/AppError.swift` is the only file in the codebase that `Features/` and `Infrastructure/` files may import for error types

**Test Organization Rules:**

- Test folder mirrors source folder structure under `MeetNotesTests/`
- Tests that require real hardware (Ollama, real Keychain, AVAudioEngine) are marked with a custom `@TestAvailability` trait and excluded from CI unless explicitly enabled
- `AppDatabaseTests.swift` always uses an in-memory `DatabasePool` — never the real file
- Mock types are defined inline in the test file that uses them, not in a shared `Mocks/` folder (prevents invisible cross-test dependencies)

**Asset Organization:**

- WhisperKit base model bundled in app at `MeetNotes/Resources/whisperkit-base/` — loaded at first launch without download
- WhisperKit large-v3-turbo downloaded on-demand to `~/Library/Application Support/meet-notes/Models/` by `ModelDownloadManager`
- App icon at `MeetNotes/Assets.xcassets/AppIcon.appiconset/`
- SF Symbols used exclusively for all iconography — no custom image assets for UI icons

### Development Workflow Integration

**CI Pipeline (`ci.yml`) — runs on every PR:**

```yaml
# Triggers: pull_request targeting main
# Runner: macos-14 (Apple Silicon)
# Steps:
#   1. actions/checkout
#   2. xcodebuild -scheme MeetNotes -destination 'platform=macOS' build
#   3. xcodebuild test -scheme MeetNotes (excludes @TestAvailability hardware tests)
```

**Release Pipeline (`release.yml`) — runs on every merge to `main`:**

```yaml
# Triggers: push to main
# Runner: macos-14
# Steps:
#   1. actions/checkout
#   2. Import Developer ID certificate from GitHub Secret (base64 p12)
#   3. xcodebuild archive -scheme MeetNotes -archivePath MeetNotes.xcarchive
#   4. xcodebuild -exportArchive → MeetNotes.app (Developer ID signed)
#   5. Auto-increment CFBundleVersion via agvtool
#   6. Create DMG: hdiutil create with MeetNotes.app
#   7. xcrun notarytool submit MeetNotes.dmg --wait
#   8. xcrun stapler staple MeetNotes.dmg
#   9. gh release create v{build_number} MeetNotes.dmg
#  10. Generate appcast.xml from release metadata → commit to gh-pages branch
```

**Local Development Flow:**

```
1. Clone repo → open MeetNotes.xcodeproj in Xcode 16.3+
2. Sign with your own Developer ID (or ad-hoc for local testing)
3. Run scheme MeetNotes → app launches in menu bar
4. Test Core Audio Tap: run any meeting app (Zoom/Meet) alongside meet-notes
5. Run tests: Cmd+U → skips hardware-dependent tests automatically
6. Study Recap source (github.com/RecapAI/Recap) before implementing RecordingService
```

## Architecture Validation Results

### Coherence Validation

**Decision Compatibility:** PASS
All 10 technology pairings validated as compatible. Swift 6 strict concurrency, GRDB DatabasePool WAL, WhisperKit CoreML/ANE, Sparkle 2.x under hardened runtime, and OllamaKit via localhost coexist without conflicts. No contradictory decisions identified.

**Pattern Consistency:** PASS
The naming suffix table is internally consistent and matches every file in the project tree. Every `*Service.swift` is an `actor`, every `*ViewModel.swift` is `@Observable @MainActor final class`, every `*View.swift` is a SwiftUI `View` struct. The three-layer error rule, GRDB write-ownership invariant, and AsyncStream bridge rule are mutually reinforcing — no pattern conflicts with another.

**Structure Alignment:** PASS
All FR categories map to specific feature folders. `Infrastructure/` cleanly separates persistence, permissions, and secrets from feature logic. The `UI/Components/` dependency-free rule is consistent with the constraint that views only call ViewModel methods. Cross-scene `RecordingViewModel` sharing via `.environment()` is correctly architected at the `MeetNotesApp` level.

### Requirements Coverage Validation

**Functional Requirements Coverage:** ALL 39 FRs COVERED

Every FR in the PRD maps to one or more specific files in the project tree. No FR is unaddressed.

| FR range | Status | Primary mechanism |
|---|---|---|
| FR1–FR4 Recording Control | COVERED | `RecordingViewModel` state machine + `MenuBarPopoverView` + `RecordingState` elapsed timer |
| FR5–FR7 Audio Capture | COVERED | `RecordingService` Core Audio Tap + AVAudioEngine + AVAudioConverter mix |
| FR8–FR9 Tap loss + mic fallback | COVERED | `RecordingService` tap health monitor (1s cadence) + `AudioQuality` enum + `ErrorBannerView` |
| FR10–FR13 Transcription | COVERED | `TranscriptionService` + WhisperKit + `ModelDownloadManager` + processing phase in `RecordingState` |
| FR14–FR18 AI Summarization | COVERED | `SummaryService` + `LLMProvider` protocol + `OllamaProvider` + `CloudAPIProvider` + nil-provider skip |
| FR19–FR23 Library & Search | COVERED | `MeetingListViewModel` + GRDB `ValueObservation` + FTS5 virtual table + `segments_fts` triggers |
| FR24–FR27 Onboarding | COVERED | `OnboardingView` 3-step wizard + `PermissionService` + `hasCompletedOnboarding` flag |
| FR28–FR32 Settings | COVERED | `SettingsViewModel` + `SettingsView` + `SecretsStore` + `ModelDownloadCardView` |
| FR33–FR35 Error Handling | COVERED | `AppError` enum + `AppErrorState` + `ErrorBannerView` + three-layer error rule |
| FR36 Updates | COVERED | Sparkle `SPUUpdater` initialized in `AppDelegate` |
| FR37–FR39 App Lifecycle | COVERED | `MeetNotesApp` scenes + `AppDelegate` `setActivationPolicy(.accessory)` |

**Non-Functional Requirements Coverage:** ALL NFRs COVERED

| Category | Status | Mechanism |
|---|---|---|
| Performance (launch, processing, RTF, RAM, CPU) | COVERED | WhisperKit ANE inference; GRDB WAL; bundled base model (zero download on first launch) |
| NFR-R2 Recording isolation | COVERED | GRDB DatabasePool WAL; actor threads never block AVAudioEngine tap |
| NFR-R3 Real-time thread | COVERED | AsyncStream bridge; Swift 6 actor isolation enforces the rule at compile time |
| NFR-R4 Sleep/wake | COVERED | `AppDelegate` `NSWorkspace` sleep/wake observers signal `RecordingService` |
| NFR-R5 Non-blocking model download | COVERED | `ModelDownloadManager` actor; `@Observable` progress publishing |
| NFR-S1–S6 Security & Privacy | COVERED | `SecretsStore` Keychain-only; `CloudAPIProvider` structurally opt-in; no telemetry dependency |
| NFR-A1–A5 Accessibility | COVERED | `reduceMotion` guards on all animations; `reduceTransparency` on material surfaces; VoiceOver labels |
| NFR-I1–I4 Integration | COVERED | `LLMProvider` protocol; 5s Ollama timeout; Sparkle signature verification; resumable `URLSessionDownloadTask` |

### Implementation Readiness Validation

**Decision Completeness:** READY
All critical decisions are documented with rationale and Swift code patterns. User-chosen decisions (1.3=B transcripts-only, 3.1=A direct actor calls, 5.1=B branch-based CI, 5.2=A no crash reporting) are recorded with context. Technology versions specified throughout.

**Structure Completeness:** READY
Complete project tree with per-file purpose annotations covering 40+ files. Zero placeholder entries. All 39 FRs mapped to specific files. All NFRs mapped to architectural mechanisms.

**Pattern Completeness:** READY
All 8 identified AI-agent conflict points resolved with explicit rules, correct code examples, and prohibited anti-pattern examples. Enforcement guidelines documented with a comprehensive prohibition table.

### Gap Analysis Results

**Critical Gaps:** None — no missing decisions block implementation.

**Important Gaps Resolved:**

**Gap 1 — `AppDelegate` sleep/wake handling (NFR-R4):**
`AppDelegate` registers for `NSWorkspace` sleep/wake notifications. On `willSleepNotification`, it signals `RecordingService` to pause the Core Audio tap. On `didWakeNotification`, it signals resume. If the tap cannot resume (context invalidated by macOS after sleep), `RecordingService` transitions to `.error(.audioTapLost)` and the session is saved with whatever audio was captured before sleep.

```swift
// AppDelegate.swift — required registration pattern
func applicationDidFinishLaunching(_ notification: Notification) {
    NSWorkspace.shared.notificationCenter.addObserver(
        self, selector: #selector(systemWillSleep),
        name: NSWorkspace.willSleepNotification, object: nil)
    NSWorkspace.shared.notificationCenter.addObserver(
        self, selector: #selector(systemDidWake),
        name: NSWorkspace.didWakeNotification, object: nil)
}
// Both @objc handlers dispatch: Task { await recordingService.handleSleep() / handleWake() }
```

**Gap 2 — Core Audio tap loss detection mechanism (FR8, within 2 seconds):**
`RecordingService` runs a 1-second repeating `Task` that checks whether the Core Audio tap's process audio unit is still active. On failure, it transitions `AudioQuality` to `.micOnly` and posts `AppError.audioTapLost` via `AppErrorState`. The 1-second cadence satisfies FR8's "within 2 seconds" requirement.

```swift
// RecordingService.swift — tap health monitor pattern
private func startTapHealthMonitor() {
    tapMonitorTask = Task { [weak self] in
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            guard let self else { return }
            if !(await self.isTapHealthy()) {
                await self.handleTapLoss()
            }
        }
    }
}
```

**Nice-to-Have Gaps (documented, not blocking):**
- `ModelDownloadManager` retry policy: max 3 retries with exponential backoff (1s, 2s, 4s). After 3 failures, post `AppError.modelNotDownloaded(modelName:)`.
- GRDB WAL checkpoint policy: use `.passive` (default). Agents must not change this without explicit approval — passive checkpointing minimises write-latency spikes during transcription.

### Architecture Completeness Checklist

**Requirements Analysis**
- [x] Project context thoroughly analysed (39 FRs, complete NFR set, UX spec)
- [x] Scale and complexity assessed (Medium; ~12 discrete modules)
- [x] Technical constraints identified (macOS 14.2+, arm64 only, no sandbox, hardened runtime)
- [x] Cross-cutting concerns mapped (6 concerns, each with an architectural resolution)

**Architectural Decisions**
- [x] Critical decisions documented with rationale (data architecture, security, pipeline, CI/CD)
- [x] Technology stack fully specified (Swift 6, SwiftUI, Core Audio Taps, WhisperKit, GRDB, OllamaKit, Sparkle)
- [x] Integration patterns defined (AsyncStream bridge, `LLMProvider` protocol, GRDB `ValueObservation`)
- [x] Performance considerations addressed (WAL, ANE inference, bundled base model, non-blocking downloads)
- [x] User-chosen decisions recorded with rationale (1.3=B, 3.1=A, 5.1=B, 5.2=A)

**Implementation Patterns**
- [x] Naming conventions established (suffix table, file naming, SQL-to-Swift mapping, Logger category)
- [x] Structure patterns defined (feature-based folders, test mirror structure, Components rules)
- [x] Communication patterns specified (service→ViewModel MainActor hop, ValueObservation, AppError enum)
- [x] Process patterns documented (three-layer error rule, state enum over booleans, write-ownership invariant)
- [x] All 8 conflict points resolved with code examples and anti-pattern prohibition table

**Project Structure**
- [x] Complete directory structure defined (40+ files named with purpose annotations)
- [x] Component boundaries established (real-time boundary, service layer, privacy boundary)
- [x] Integration points mapped (6 external integrations documented with network status)
- [x] Requirements-to-structure mapping complete (all 39 FRs mapped to specific files)
- [x] Full data flow documented (7-step end-to-end recording session)
- [x] CI/CD pipeline structure specified (ci.yml and release.yml step sequences)

**Validation**
- [x] Coherence validated — no contradictions across all decisions
- [x] All 39 FRs and all NFRs confirmed covered
- [x] 2 important gaps identified and resolved inline
- [x] Implementation readiness confirmed

### Architecture Readiness Assessment

**Overall Status:** READY FOR IMPLEMENTATION

**Confidence Level:** High — all technology pairs validated as compatible; complete FR coverage with file-level mapping; concrete code patterns for every conflict point; full alignment with the production-proven Recap reference implementation that uses the identical stack.

**Key Strengths:**

1. **Real-time thread safety is compile-enforced.** Swift 6 actor isolation makes AsyncStream bridge violations compile errors, not runtime bugs. The hardest constraint in the system is the most automatic to enforce.
2. **Privacy guarantee is structural, not behavioural.** `CloudAPIProvider` is unreachable without an API key in Keychain. There is no runtime setting that can accidentally exfiltrate data.
3. **GRDB DatabasePool WAL + write-ownership invariant** ensures the audio pipeline never competes with the UI for database access, satisfying NFR-R2 without explicit synchronisation code.
4. **Greenfield project with a validated reference implementation.** No legacy constraints, no migration debt. Recap confirms the full pipeline works end-to-end on identical technology.
5. **Implementation sequence is explicit and dependency-ordered.** Every module knows what it depends on and what depends on it. No agent needs to infer build order.

**Areas for Future Enhancement (post-MVP):**
- v1.1: Raw audio M4A retention + timestamp navigation (`Meeting.audioFilePath` migration + `RecordingService` file writer)
- v1.1: Real-time transcript streaming (WhisperKit streaming API; `TranscriptionService` chunk-emission changes)
- v1.1: Calendar integration (auto-title meetings; new `CalendarService` actor)
- v1.2: Speaker diarization (new ML model; new `DiarizationService`; `speakerLabel` on `TranscriptSegment`)
- v1.2: Opt-in crash reporting (Sentry behind first-launch consent sheet)
- v2.0: Plugin export system (Notion, Obsidian, Markdown file)

### Implementation Handoff

**AI Agent Guidelines:**
- Follow all architectural decisions exactly as documented — do not invent alternatives
- Use the Implementation Patterns section as the authoritative style guide for every file written
- Respect the project structure exactly — file names, folder locations, and the one-type-per-file rule are not suggestions
- The three-layer error rule and AsyncStream bridge rule are non-negotiable — violations cause runtime crashes or audio glitches

**First Implementation Priority:**

```bash
# 1. Xcode project creation (all other work depends on this)
#    File → New → Project → macOS → App
#    Interface: SwiftUI | Language: Swift | Include Tests: YES
#    Product Name: MeetNotes | Bundle ID: com.<you>.meet-notes
#    MACOSX_DEPLOYMENT_TARGET = 14.2 | ARCHS = arm64
#    SWIFT_VERSION = 6.0 | ENABLE_HARDENED_RUNTIME = YES

# 2. Before writing any production code:
#    git clone https://github.com/RecapAI/Recap && open Recap.xcodeproj
#    Study RecordingService.swift and Core Audio Tap patterns.
#    This resolves implementation questions before they become blockers.
```
