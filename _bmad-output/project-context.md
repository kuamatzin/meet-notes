---
project_name: 'meet-notes'
user_name: 'Cuamatzin'
date: '2026-02-24'
sections_completed: ['technology_stack', 'language_rules', 'framework_rules', 'testing_rules', 'code_quality_rules', 'workflow_rules', 'critical_rules']
status: 'complete'
rule_count: 42
optimized_for_llm: true
---

# Project Context for AI Agents

_This file contains critical rules and patterns that AI agents must follow when implementing code in this project. Focus on unobvious details that agents might otherwise miss._

---

## Technology Stack & Versions

- **Language:** Swift 6.0 — strict concurrency mode (`SWIFT_STRICT_CONCURRENCY = complete`)
- **UI:** SwiftUI + `MenuBarExtra` scene (macOS 13+ API); `@NSApplicationDelegateAdaptor` for AppDelegate bridge
- **Platform:** macOS 14.2+ minimum deployment target; **arm64 only** (no Intel support)
- **System Audio:** Core Audio Taps API (macOS 14.2+ required)
- **Microphone:** AVAudioEngine
- **Transcription:** WhisperKit (argmaxinc/WhisperKit) — CoreML/ANE inference; default model `base` (~145 MB), upgrade to `large-v3-turbo` in settings
- **Database:** GRDB.swift ≥ 7.10 — SQLite with `DatabasePool` in WAL mode
- **Local LLM:** OllamaKit (kevinhermawan/OllamaKit) — default endpoint `http://localhost:11434`
- **Cloud LLM (opt-in):** URLSession with OpenAI-compatible API format
- **Auto-update:** Sparkle ≥ 2.x — appcast hosted on GitHub Releases
- **Linting:** SwiftLint (realm/SwiftLint) — added as SPM build tool plugin
- **Testing:** XCTest + Swift Testing (Apple 2024 framework)
- **Build tool:** Xcode 16.3+ — SPM only; no CocoaPods or Carthage
- **CI/CD:** GitHub Actions on `macos-14` runner
- **App Sandbox:** DISABLED (`com.apple.security.app-sandbox = false`)
- **Hardened Runtime:** ENABLED (`ENABLE_HARDENED_RUNTIME = YES`) — required for notarization
- **Distribution:** Notarized DMG, outside App Store

## Critical Implementation Rules

### Swift 6 Concurrency Rules

- **Services are `actor` types — always.** Never use `@MainActor class`, `class`, or `struct` for a service.
  ```swift
  // CORRECT
  actor RecordingService { ... }
  // WRONG
  @MainActor class RecordingService { ... }
  ```

- **ViewModels are `@Observable @MainActor final class` — always.** Never use `actor`, `ObservableObject`, `@Published`, or `@StateObject`. These are completely prohibited in this codebase.
  ```swift
  // CORRECT
  @Observable @MainActor final class RecordingViewModel { ... }
  // WRONG — any of these
  actor RecordingViewModel { ... }
  class RecordingViewModel: ObservableObject { @Published var state = ... }
  ```

- **`@Observable` only, zero legacy patterns.** Never import or use `Combine` for ViewModel state. Never use `@StateObject` / `@ObservedObject` in views.

- **Real-time thread boundary — absolute rule.** The Core Audio tap callback runs on a real-time OS thread. The ONLY permitted operation inside it is `continuation.yield(buffer)`. No `await`, no actor calls, no database access, no `os_log`, no `NotificationCenter.default.post`.
  ```swift
  // ONLY this is allowed inside a tap callback:
  continuation.yield(buffer)
  ```

- **Services throw typed domain errors.** Use `throws(DomainError)` syntax (Swift 6 typed throws), not `throws` (untyped). ViewModels catch and never rethrow — they post to `AppErrorState`.
  ```swift
  // CORRECT
  func transcribe(...) async throws(TranscriptionError) -> [TranscriptSegment] { ... }
  // ViewModel catches, never rethrows:
  func stopRecording() async {
      do { try await recordingService.stop() } catch { appErrorState.post(.from(error)) }
  }
  ```

- **Service → ViewModel updates via `@MainActor` closure, never direct reference.** Services register a handler closure; they never hold a reference to a ViewModel.
  ```swift
  // CORRECT
  actor RecordingService {
      private var onStateChange: (@MainActor (RecordingState) -> Void)?
      private func updateState(_ s: RecordingState) async {
          await MainActor.run { onStateChange?(s) }
      }
  }
  ```

- **Swift 6 concurrency warnings are errors — zero tolerance.** Every file must compile with zero actor isolation warnings under `SWIFT_STRICT_CONCURRENCY = complete`.

### SwiftUI Rules

- **Environment injection pattern.** `RecordingViewModel`, `AppErrorState`, and `NavigationState` are created once in `MeetNotesApp` as `@State` properties and injected into ALL scenes via `.environment()`. Views consume them with `@Environment(SomeType.self)` — never instantiate ViewModels inside views.

- **ViewModel granularity.** Four ViewModels only: `RecordingViewModel` (shared across all scenes), `MeetingListViewModel`, `MeetingDetailViewModel`, `SettingsViewModel`. Do not create new ViewModels without architectural justification.

- **View nesting depth limit.** No SwiftUI `body` exceeds 3 levels of nesting before extracting a named subview. Prevents monolithic views and keeps `@Environment` injection points predictable.

- **`UI/Components/` is dependency-free.** Views placed in `UI/Components/` must have zero ViewModel dependencies. If a view needs a ViewModel, it belongs in its feature folder, not in Components.

- **Accessibility guard on every animation — no exceptions.** Every `withAnimation {}` and `.animation()` modifier must be guarded by `@Environment(\.accessibilityReduceMotion)`.
  ```swift
  // CORRECT
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: sidebarVisible)
  // WRONG — unguarded
  .animation(.easeInOut(duration: 0.25), value: sidebarVisible)
  ```

- **State machine over boolean flags.** Use `RecordingState` enum cases to represent all UI states. Never use parallel `isRecording: Bool`, `isTranscribing: Bool`, etc.

- **Design tokens only — no hardcoded color literals.** All colors come from the `Color` extension in `UI/Components/Color+DesignTokens.swift`. Never use `Color(red:green:blue:)` or `.black`/`.white` literals in views.

### GRDB Rules

- **GRDB writes in service actors only.** ViewModels never call `database.pool.write`. They are strictly read-only consumers via `ValueObservation`.

- **`ValueObservation` for live UI data — no polling.** Every ViewModel that displays live data uses `ValueObservation.tracking(...)`. Never use `Timer` to manually refresh from the database.
  ```swift
  // CORRECT
  ValueObservation.tracking(Meeting.fetchAll)
      .start(in: database.pool, scheduling: .mainActor) { [weak self] meetings in
          self?.meetings = meetings
      }
  ```

- **Explicit `Columns` enum — never rely on auto snake_case conversion.** Every GRDB record struct must declare a nested `Columns` enum mapping Swift `camelCase` properties to SQL `snake_case` column names.
  ```swift
  // CORRECT
  struct Meeting: Codable, FetchableRecord, PersistableRecord {
      var startedAt: Date
      enum Columns {
          static let startedAt = Column("started_at")
      }
  }
  // WRONG — relying on automatic conversion
  struct Meeting: Codable, FetchableRecord, PersistableRecord {
      var startedAt: Date  // do NOT rely on auto-conversion
  }
  ```

- **GRDB record types have no suffix.** The GRDB `FetchableRecord` / `PersistableRecord` structs are named after the domain entity only: `Meeting`, `TranscriptSegment`, `AppSetting`. No `Model`, `Record`, or `Entity` suffix.

- **Migrations are append-only.** The `AppDatabase` class holds a single `DatabaseMigrator`. Existing registered migrations (e.g., `"v1"`) are never modified. Only new numbered migrations are added.

- **FTS5 triggers must stay in sync.** The `segments_fts` virtual table is kept in sync via three triggers (`segments_ai`, `segments_ad`, `segments_au`). When inserting segments, use the standard `insert(db)` call — triggers fire automatically. Never manually insert into `segments_fts`.

### Testing Rules

- **Tests mirror source folder structure.** All tests live in `MeetNotesTests/` with subdirectories matching the source feature folder. Never co-locate test files next to source files.
  ```
  // Source:  MeetNotes/Features/Recording/RecordingService.swift
  // Test:    MeetNotesTests/Recording/RecordingServiceTests.swift
  ```

- **Protocol-based dependency injection enables mocking.** All services conform to a protocol (e.g., `AudioCaptureServiceProtocol`). Tests inject mock conformances — never test against the real `RecordingService` when a mock suffices.

- **Test file naming: `{TypeName}Tests.swift`.** One test file per source type. Test class is named `{TypeName}Tests`.

- **Use Swift Testing (`@Test`, `#expect`) for new tests.** XCTest is available but Swift Testing (Apple 2024) is the preferred framework for new test files. Do not mix both in the same file.

- **Actor services under test must be awaited.** All calls to actor methods in tests must be `await`ed. Never use `DispatchQueue` or `XCTestExpectation` to synchronize actor calls — use `async` test functions.
  ```swift
  // CORRECT
  @Test func recordingStartsSuccessfully() async throws {
      let service = RecordingService(...)
      try await service.start()
      #expect(await service.isRecording == true)
  }
  ```

- **Database tests use in-memory `AppDatabase`.** Tests that exercise GRDB logic instantiate `AppDatabase` with an in-memory SQLite store (`:memory:`), never a file path.

- **`AppDatabase` migrations run in tests.** Always run the full `DatabaseMigrator` on the in-memory database before testing — never insert raw SQL in tests that bypasses the migration schema.

- **No tests for `UI/Components/` views at this stage.** Reusable subviews are tested through their parent feature's integration tests. Isolated view snapshot tests are deferred to a future story.

### Code Quality & Style Rules

- **Mandatory type-name suffixes — exact, no abbreviations.**

  | Type | Required suffix | Example |
  |---|---|---|
  | Swift Actor wrapping a system service | `Service` | `RecordingService` |
  | `@Observable @MainActor` ViewModel | `ViewModel` | `RecordingViewModel` |
  | GRDB record struct | *(none)* | `Meeting`, `TranscriptSegment` |
  | SwiftUI View struct | `View` | `MeetingListView`, `SidebarView` |
  | Protocol describing a role | *(descriptive)* | `LLMProvider`, `AudioCaptureServiceProtocol` |
  | State/phase enum | `State` or `Phase` | `RecordingState`, `ProcessingPhase` |
  | Error enum | `Error` | `AppError`, `RecordingError` |
  | Static-only utility struct | `Store` | `SecretsStore` |
  | `@main` App struct | `App` | `MeetNotesApp` |

  Never use `VM`, `Manager`, `Handler`, `Controller`, or abbreviations.

- **One primary type per file.** File name = primary type name exactly: `RecordingService.swift`, `MeetingListViewModel.swift`, `Meeting.swift`. Nested helpers used only by that type may co-locate in the same file.

- **`Logger` at file scope, category = exact type name.**
  ```swift
  // CORRECT — in RecordingService.swift
  private let logger = Logger(subsystem: "com.{you}.meet-notes", category: "RecordingService")
  // WRONG
  private let logger = Logger(subsystem: "com.{you}.meet-notes", category: "audio")
  ```

- **Never use `print()` for logging.** Use `Logger` (unified logging, `os.log`) only. `print()` output is not visible in Console.app and is not filterable.

- **SwiftLint is enforced.** Zero violations allowed. The `.swiftlint.yml` at project root is the source of truth. `force_unwrapping` is enabled (flagged). Line length limit is 120.

- **No comments on obvious code.** Only add comments where the logic is non-obvious (e.g., explaining *why* the real-time thread boundary rule exists). Never add docstrings or parameter comments to straightforward functions.

- **`AppError` is the only error type views ever see.** All domain-specific errors (`RecordingError`, `TranscriptionError`, etc.) are converted to `AppError` at the service boundary before being posted to `AppErrorState`. Views only render `AppError` cases.

### Development Workflow Rules

- **🔑 MANDATORY: Use `context7` MCP for all library documentation.** Before writing ANY code that uses WhisperKit, GRDB, OllamaKit, Sparkle, or any SPM dependency, you MUST fetch current API docs via the `context7` MCP server. Do NOT rely on training data — library APIs change. The workflow is always:
  1. `mcp__context7__resolve-library-id` — find the library's context7 ID
  2. `mcp__context7__query-docs` — fetch specific, current documentation for the API you are implementing

  This applies to every story, every agent, every implementation session. There are no exceptions.

- **Branch strategy: feature branches → `main`.** `main` is always releasable. Every merge to `main` triggers a full release pipeline (archive → sign → notarize → DMG → GitHub Release → Sparkle appcast update). Never commit in-progress work directly to `main`.

- **CI gate: PRs must pass before merging.** The `ci.yml` GitHub Actions workflow runs build + test on `macos-14`. A failing CI build blocks the merge. Never use `--no-verify` or skip CI.

- **Version numbering: `CFBundleShortVersionString` is set manually** at meaningful milestones. `CFBundleVersion` (build number) is auto-incremented by the release workflow via `agvtool` on every `main` merge.

- **Commit message style: imperative mood, concise.** Examples: `Add RecordingService actor`, `Fix AudioTap continuation leak`, `Update GRDB schema to v2`. No ticket numbers required (solo project).

- **Secrets never in source.** API keys, signing certificates, and notarization credentials are stored in GitHub Actions secrets, never committed to the repository. The app reads credentials at runtime from macOS Keychain only.

- **No crash reporting framework in v1.0.** Do not add Sentry, Crashlytics, or any telemetry dependency. Users file GitHub issues with Console.app crash logs. This is a deliberate architectural decision (NFR-S5).

- **SPM only — no CocoaPods or Carthage.** All new dependencies must be added via `File → Add Package Dependencies` in Xcode. Never introduce a `Podfile` or `Cartfile`.

### Critical Don't-Miss Rules

**Absolute prohibitions — these break the architecture:**

| Anti-pattern | Why prohibited |
|---|---|
| `ObservableObject` / `@Published` / `@StateObject` | Legacy; incompatible with Swift 6 `@Observable` ownership model |
| `@MainActor class RecordingService` | Wrong isolation domain; services must be `actor` types |
| `actor RecordingViewModel` | Breaks `@Observable` SwiftUI integration |
| `print()` for logging | Not visible in Console.app; not filterable |
| Boolean loading flags alongside a state enum | Creates impossible states; `RecordingState` enum is the single source of truth |
| ViewModel calling `database.pool.write` | Breaks write-ownership invariant; potential data races |
| Raw `NSError` / untyped `Error` posted to `AppErrorState` | Views cannot render actionable messages from untyped errors |
| Unguarded `withAnimation` / `.animation()` | Violates NFR-A4 accessibility requirement |
| Co-located test files next to source | Tests live in `MeetNotesTests/` mirroring source folder structure |
| Reusable view with ViewModel dependency in `UI/Components/` | Components folder is dependency-free subviews only |
| Any async call, I/O, or logging inside a Core Audio tap callback | Real-time thread violation; will cause audio glitches or crashes |
| Storing API keys in UserDefaults, SQLite, plist, or log output | Security violation (NFR-S1); use `SecretsStore` + Keychain exclusively |
| Instantiating `CloudAPIProvider` without a user-configured API key | Violates NFR-S2 zero-exfiltration-by-default; cloud path is structurally opt-in |
| Modifying an already-registered GRDB migration | Breaks idempotent migration invariant; creates schema divergence on existing installs |
| Using `NSEvent` global monitor for keyboard shortcuts | Requires special accessibility permissions; use SwiftUI `.commands` instead |

**Security rules:**
- `SecretsStore` is the **only** permitted path for reading or writing credentials. It is a struct with static methods — no instantiation, no subclassing.
- `CloudAPIProvider` is **only** instantiated when the user has explicitly entered an API key in Settings. It must never be created as a default or fallback.

**Architecture boundary rules:**
- The three-layer error rule has no shortcuts: Service throws → ViewModel catches + maps to `AppError` + posts to `AppErrorState` → View renders. Views never call `try`. ViewModels never rethrow.
- `NavigationState.shared` is the singleton used by `NotificationService` for deep-link navigation from notification taps. The `@State` instance in `MeetNotesApp` is the same object passed as a SwiftUI environment value — they must be the same instance.
- `os_signpost` markers for Instruments profiling belong in the `TranscriptionService` consumer loop, **outside** the Core Audio tap callback — never inside it.

---

## Usage Guidelines

**For AI Agents:**

- Read this file before implementing any code in this project
- Follow ALL rules exactly as documented — they are non-negotiable architecture decisions
- When in doubt, prefer the more restrictive option
- Use `context7` MCP to fetch current library docs before using any SPM dependency
- Update this file if new patterns emerge during implementation

**For Humans:**

- Keep this file lean and focused on agent needs — avoid documenting obvious things
- Update when technology stack, dependencies, or architectural patterns change
- Review after each epic completes to remove outdated rules
- Add rules when you catch an agent making the same mistake twice

Last Updated: 2026-02-24
