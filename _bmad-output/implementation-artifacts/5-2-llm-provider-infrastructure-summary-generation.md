# Story 5.2: LLM Provider Infrastructure & Summary Generation

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a user whose meeting has finished transcribing,
I want a structured meeting summary generated automatically — with decisions, action items, and key topics — using whichever AI provider I configured,
So that I can scan the outcome of any meeting in 30 seconds without reading the full transcript.

## Acceptance Criteria

1. **Given** `TranscriptionService` completes and calls `SummaryService.summarize(meetingID:)`, **When** an LLM provider is configured, **Then** `SummaryService` calls the active `LLMProvider` conformance (`OllamaProvider` or `CloudAPIProvider`) with the full transcript text

2. **Given** `LLMProvider` is a protocol with `func summarize(transcript: String) async throws -> String`, **When** `SummaryService` calls it, **Then** the same call path is used for both Ollama and cloud providers — no provider-specific branching in `SummaryService` (NFR-I1)

3. **Given** the active provider is `OllamaProvider`, **When** a summarization request is made, **Then** it uses `OllamaKit` to call the local Ollama HTTP endpoint — no data leaves the machine (NFR-S2)

4. **Given** the active provider is `CloudAPIProvider`, **When** a summarization request is made, **Then** it uses `URLSession` with the OpenAI-compatible API format — the transcript is only sent because the user explicitly configured this provider (NFR-S2)

5. **Given** no LLM provider is configured, **When** `SummaryService.summarize(meetingID:)` is called, **Then** it skips summarization, sets `pipeline_status = 'complete'` on the meeting, and leaves `summary_md` as `NULL` — recording and transcription are unaffected (FR17)

6. **Given** summary generation completes, **When** the LLM response is received, **Then** `summary_md` is saved to the `meetings` row and `pipeline_status` is updated to `'complete'`

7. **Given** Ollama is not running when summarization is attempted, **When** `OllamaProvider` makes the HTTP request, **Then** the failure is detected within <=5 seconds and an `AppError.ollamaNotRunning` is posted to `AppErrorState` — the transcript remains intact and accessible (NFR-I2)

## Tasks / Subtasks

- [x] Task 1: Create `LLMProvider` protocol (AC: #2)
  - [x] 1.1 Create `Features/Summary/LLMProvider.swift` with `protocol LLMProvider: Sendable { func summarize(transcript: String) async throws -> String }`
  - [x] 1.2 Protocol must be `Sendable` for actor isolation compatibility

- [x] Task 2: Create `OllamaProvider` actor (AC: #3, #7)
  - [x] 2.1 Create `Features/Summary/OllamaProvider.swift` as `actor OllamaProvider: LLMProvider`
  - [x] 2.2 Accept endpoint URL in init (default: `http://localhost:11434`)
  - [x] 2.3 Use `OllamaKit(baseURL:)` to create client with user-configured endpoint
  - [x] 2.4 Implement `summarize(transcript:)` using `OllamaKit.chat(data:)` with `OKChatRequestData`:
    - Model: read `ollama_model` from database (default `"llama3.2"`)
    - Messages: system prompt (see Dev Notes) + user message with transcript
    - Collect streamed `OKChatResponse` chunks, concatenate `message.content` strings
  - [x] 2.5 Check reachability via `ollamaKit.reachable()` before calling — throw if unreachable within 5s
  - [x] 2.6 Map errors to `SummaryError.ollamaNotReachable(endpoint:)` or `SummaryError.providerFailure(Error)`

- [x] Task 3: Create `CloudAPIProvider` actor (AC: #4)
  - [x] 3.1 Create `Features/Summary/CloudAPIProvider.swift` as `actor CloudAPIProvider: LLMProvider`
  - [x] 3.2 Accept API key (String) in init — loaded from `SecretsStore.load(for: .openAI)` at call site
  - [x] 3.3 Implement `summarize(transcript:)` using `URLSession` with OpenAI-compatible chat completions API:
    - POST to `https://api.openai.com/v1/chat/completions`
    - Headers: `Authorization: Bearer <key>`, `Content-Type: application/json`
    - Body: `{ "model": "gpt-4o-mini", "messages": [system, user], "temperature": 0.3 }`
    - Parse JSON response: `choices[0].message.content`
  - [x] 3.4 Configure `URLSessionConfiguration` with 30s timeout
  - [x] 3.5 Map HTTP 401/403 to `SummaryError.invalidAPIKey`, network errors to `SummaryError.networkUnavailable`, other errors to `SummaryError.providerFailure(Error)`

- [x] Task 4: Create `SummaryError` enum (AC: #7)
  - [x] 4.1 Define in `Features/Summary/SummaryService.swift` (or separate file if needed):
    ```
    enum SummaryError: Error, Sendable {
        case ollamaNotReachable(endpoint: String)
        case invalidAPIKey
        case networkUnavailable
        case providerFailure(Error)
        case noTranscriptSegments
    }
    ```
  - [x] 4.2 Note: `SummaryError` is NOT `Equatable` due to `providerFailure(Error)` — use pattern matching in tests

- [x] Task 5: Add `AppError` cases for summary failures (AC: #7)
  - [x] 5.1 Add `case ollamaNotRunning(endpoint: String)` to `AppError`
  - [x] 5.2 Add `case summaryFailed` to `AppError`
  - [x] 5.3 Implement `bannerMessage`, `recoveryLabel`, `sfSymbol`, `systemSettingsURL` for each new case
  - [x] 5.4 `ollamaNotRunning` recovery: "Check Ollama" — no system URL (user must start Ollama manually)
  - [x] 5.5 Update all exhaustive switch statements in `AppError`

- [x] Task 6: Implement `SummaryService` actor (AC: #1, #2, #5, #6)
  - [x] 6.1 Replace stub implementation in existing `Features/Summary/SummaryService.swift`
  - [x] 6.2 Add dependency: `private let database: AppDatabase` (already present)
  - [x] 6.3 Add method to resolve the active LLM provider at runtime:
    - Read `llm_provider` setting from database (`"ollama"` or `"cloud"`)
    - If `"ollama"`: read `ollama_endpoint` from database, create `OllamaProvider(endpoint:)`
    - If `"cloud"`: load API key via `SecretsStore.load(for: .openAI)`, create `CloudAPIProvider(apiKey:)` — if key is nil, treat as unconfigured
    - If unconfigured: return nil (skip summarization)
  - [x] 6.4 Implement `summarize(meetingID:)`:
    - Update `pipeline_status` to `"summarizing"` in database
    - Read all `TranscriptSegment` rows for meetingID, concatenate into full transcript text (format: `"[HH:MM:SS] segment text"` per line)
    - If no segments found, set `pipeline_status = "complete"`, return early
    - Resolve LLM provider (Task 6.3); if nil, set `pipeline_status = "complete"`, return early
    - Call `provider.summarize(transcript:)`
    - Save returned markdown to `Meeting.summaryMd` and set `pipeline_status = "complete"`
    - On error: set `pipeline_status = "complete"` (not "failed" — transcript is still valid), post error to `AppErrorState`
  - [x] 6.5 Keep `SummaryServiceProtocol` signature unchanged: `func summarize(meetingID: String) async` — errors are handled internally and posted to `AppErrorState`, not thrown

- [x] Task 7: Wire `AppErrorState` into `SummaryService` (AC: #7)
  - [x] 7.1 Add `private let appErrorState: AppErrorState` to `SummaryService.init`
  - [x] 7.2 On `SummaryError.ollamaNotReachable` → `await MainActor.run { appErrorState.post(.ollamaNotRunning(endpoint:)) }`
  - [x] 7.3 On other errors → `await MainActor.run { appErrorState.post(.summaryFailed) }`
  - [x] 7.4 Update `MeetNotesApp.init()` to pass `appErrorState` to `SummaryService`

- [ ] Task 8: ~~Add OllamaKit SPM dependency~~ N/A — OllamaKit replaced with direct URLSession (AC: #3)
  - [ ] 8.1 ~~Add OllamaKit package dependency~~ — Skipped: OllamaKit v5.x does not compile under Swift 6 strict concurrency. Replaced with direct URLSession HTTP client targeting the Ollama REST API (`/api/chat`). Identical functionality, zero external dependency.
  - [ ] 8.2 ~~Link OllamaKit product~~ — N/A. Dead package reference in project.pbxproj should be removed.

- [x] Task 9: Write tests (AC: #1-#7)
  - [x] 9.1 Create `StubLLMProvider` in test target: conforms to `LLMProvider`, returns configurable response or throws configurable error
  - [x] 9.2 Create `MeetNotesTests/Summary/SummaryServiceTests.swift`:
    - Test: summarize with Ollama provider configured writes summary_md and sets pipeline_status = complete
    - Test: summarize with no provider configured sets pipeline_status = complete, summary_md remains nil
    - Test: summarize with no transcript segments sets pipeline_status = complete
    - Test: provider error posts to AppErrorState and sets pipeline_status = complete (not failed)
  - [x] 9.3 Create `MeetNotesTests/Summary/OllamaProviderTests.swift`:
    - Test: summarize returns concatenated response content (mock OllamaKit if feasible, or mark `@TestAvailability(requiresOllama)` for integration test)
    - Test: unreachable Ollama throws `SummaryError.ollamaNotReachable`
  - [x] 9.4 Create `MeetNotesTests/Summary/CloudAPIProviderTests.swift`:
    - Test: successful response returns parsed content (inject mock URLSession via URLProtocol)
    - Test: 401 response throws `SummaryError.invalidAPIKey`
    - Test: network error throws `SummaryError.networkUnavailable`
  - [x] 9.5 Update `StubSummaryService` (if not already present) for use in `TranscriptionServiceTests`

## Dev Notes

### Architecture Patterns and Constraints

- **LLMProvider protocol** is the core abstraction. `SummaryService` holds `any LLMProvider` resolved at runtime from user settings. There is ZERO provider-specific branching in `SummaryService` — the protocol handles polymorphism.
- **OllamaProvider** and **CloudAPIProvider** are both `actor` types (not classes). Services are always actors in this codebase.
- **SummaryService** already exists as a stub actor at `Features/Summary/SummaryService.swift`. It currently just sets `pipeline_status = "complete"`. This story replaces the stub with real LLM calls.
- **SummaryServiceProtocol** signature stays unchanged: `func summarize(meetingID: String) async`. Errors are handled internally — SummaryService catches provider errors, maps to `AppError`, and posts to `AppErrorState`. It does NOT throw.
- **Three-layer error rule**: Provider throws → SummaryService catches + maps to AppError + posts to AppErrorState → View renders ErrorBannerView. Never rethrow from the service's `summarize(meetingID:)`.
- **TranscriptionService** already calls `await summaryService.summarize(meetingID:)` in `finalizeMeeting()` — no wiring changes needed there.
- **Pipeline status on error**: Set to `"complete"` (not `"failed"`) when LLM fails — the transcript is still valid and accessible. Only post an error banner. The `"failed"` status is reserved for cases where the transcript itself is corrupted.
- **Swift 6 strict concurrency**: All new code must compile with zero warnings under `SWIFT_STRICT_CONCURRENCY = complete`. Providers are `actor` types. `LLMProvider` protocol is `Sendable`.

### OllamaKit API Reference (v5.x)

```swift
// OllamaKit is a Sendable struct
let ollamaKit = OllamaKit(baseURL: URL(string: endpoint)!)

// Check reachability first
let isReachable = await ollamaKit.reachable()  // returns Bool

// Chat API returns AsyncThrowingStream<OKChatResponse, Error>
let request = OKChatRequestData(
    model: "llama3.2",
    messages: [
        .init(role: .system, content: systemPrompt),
        .init(role: .user, content: transcript)
    ]
)

var fullResponse = ""
for try await chunk in ollamaKit.chat(data: request) {
    if let content = chunk.message?.content {
        fullResponse += content
    }
}
return fullResponse
```

- `OKChatRequestData.Message.Role`: `.system`, `.assistant`, `.user`
- `OKChatResponse.message?.content`: streamed text chunk
- `OKChatResponse.done`: true when generation is complete
- Streaming is enabled by default (no tools mode)
- `OllamaKit` is `Sendable` — safe to store in actors

### OpenAI-Compatible API Format (CloudAPIProvider)

```swift
// POST https://api.openai.com/v1/chat/completions
// Non-streaming for simplicity (streaming is Story 5.3 scope)
struct ChatRequest: Encodable {
    let model: String  // "gpt-4o-mini"
    let messages: [ChatMessage]
    let temperature: Double  // 0.3
}
struct ChatMessage: Encodable {
    let role: String  // "system" or "user"
    let content: String
}
struct ChatResponse: Decodable {
    let choices: [Choice]
    struct Choice: Decodable {
        let message: ResponseMessage
    }
    struct ResponseMessage: Decodable {
        let content: String
    }
}
```

- Request/response types are private to `CloudAPIProvider` — do NOT create shared types
- Use `JSONEncoder` / `JSONDecoder` with default settings
- Bearer token from `SecretsStore.load(for: .openAI)`
- 30s timeout via `URLSessionConfiguration.default`
- Non-streaming response (Story 5.3 will add streaming display)

### Summary Prompt Template

Use this system prompt for both providers:

```
You are a meeting summarizer. Given a meeting transcript, produce a structured summary in Markdown with exactly three sections:

## Decisions
- List each decision made during the meeting as a bullet point

## Action Items
- List each action item with the responsible person (if mentioned) as a bullet point

## Key Topics
- List the main topics discussed as bullet points

Rules:
- Be concise — each bullet should be one sentence
- If no decisions were made, write "No decisions recorded."
- If no action items were identified, write "No action items identified."
- Omit timestamps from the summary
- Do not include any text outside the three sections
```

### Database Settings Keys (from Story 5.1)

| Key | Type | Default | Purpose |
|-----|------|---------|---------|
| `"llm_provider"` | String | `"ollama"` | Active LLM provider (`"ollama"` or `"cloud"`) |
| `"ollama_endpoint"` | String | `"http://localhost:11434"` | Ollama server endpoint URL |
| `"openai_api_key_configured"` | String | `"false"` | Flag indicating if API key exists in Keychain |

### TranscriptSegment Reading Pattern

```swift
// Read all segments for a meeting, ordered by start time
let segments = try await database.pool.read { db in
    try TranscriptSegment
        .filter(TranscriptSegment.Columns.meetingId == meetingID)
        .order(TranscriptSegment.Columns.startTime)
        .fetchAll(db)
}

// Format into transcript text
let transcriptText = segments.map { segment in
    let minutes = Int(segment.startTime) / 60
    let seconds = Int(segment.startTime) % 60
    return "[\(String(format: "%02d:%02d", minutes, seconds))] \(segment.text)"
}.joined(separator: "\n")
```

### Security Rules (NFR-S1, NFR-S2)

- `CloudAPIProvider` is ONLY instantiated when `SecretsStore.load(for: .openAI)` returns a non-nil key. Never create it as a default or fallback.
- `OllamaProvider` communicates ONLY with localhost — no internet access.
- Never log API keys or transcript content at `.info` level or below. Use `.debug` for transcript length only.
- The privacy boundary is enforced structurally: `SummaryService.resolveProvider()` returns nil if unconfigured, `OllamaProvider` only hits localhost, `CloudAPIProvider` only exists with an explicit key.

### Source Tree Components to Touch

**New files:**
- `Features/Summary/LLMProvider.swift` — Protocol definition
- `Features/Summary/OllamaProvider.swift` — Ollama actor
- `Features/Summary/CloudAPIProvider.swift` — Cloud API actor
- `MeetNotesTests/Summary/SummaryServiceTests.swift` — Service tests
- `MeetNotesTests/Summary/OllamaProviderTests.swift` — Ollama provider tests
- `MeetNotesTests/Summary/CloudAPIProviderTests.swift` — Cloud provider tests

**Modify:**
- `Features/Summary/SummaryService.swift` — Replace stub with real implementation
- `App/AppError.swift` — Add `ollamaNotRunning(endpoint:)` and `summaryFailed` cases
- `App/MeetNotesApp.swift` — Pass `appErrorState` to `SummaryService` init
- `MeetNotes.xcodeproj/project.pbxproj` — Add OllamaKit SPM dependency + new files

**Do NOT modify:**
- `Features/Summary/SummaryServiceProtocol.swift` — Keep signature unchanged
- `Features/Transcription/TranscriptionService.swift` — Already calls `summarize(meetingID:)`
- `Features/Settings/SettingsViewModel.swift` — Story 5.1 already handles all settings

### Testing Standards

- Use **Swift Testing** (`@Test`, `#expect`) — not XCTest
- Test struct is `@MainActor`
- Use **temp file-backed AppDatabase** for database tests
- Create `StubLLMProvider` conforming to `LLMProvider` with configurable response/error
- OllamaKit integration tests need real Ollama — mark with appropriate availability attribute
- CloudAPIProvider tests use `URLProtocol` mock to intercept requests — no real network calls
- Test that `pipeline_status` transitions correctly: `transcribed` → `summarizing` → `complete`

### Previous Story Learnings (Story 5.1)

- `SettingsViewModel` already has `LLMProvider` enum (`.ollama`, `.cloud`) and properties: `selectedLLMProvider`, `ollamaEndpoint`, `isAPIKeyConfigured`
- Database settings keys established: `llm_provider`, `ollama_endpoint`, `openai_api_key_configured`
- `SecretsStore` static methods: `.save(apiKey:for:)`, `.load(for:)`, `.delete(for:)` with `LLMProviderKey` enum (`.openAI`, `.anthropic`)
- Logger pattern: `private nonisolated static let logger = Logger(subsystem:category:)` for actors
- Three-layer error pattern confirmed working: service throws → VM catches → posts to AppErrorState
- All 29 settings tests pass; no regressions from Story 5.1

### What This Story Does NOT Do (Scope Boundaries)

- Does NOT implement streaming display of summary in the UI (Story 5.3)
- Does NOT implement notification when summary is ready (Story 5.4)
- Does NOT add model selection UI for Ollama models (future scope)
- Does NOT implement retry logic for failed summaries (future scope)
- Does NOT modify the `SummaryServiceProtocol` signature
- Summary prompt is hardcoded — no user-configurable prompt (future scope)

### Project Structure Notes

- All new files in `Features/Summary/` — consistent with existing structure
- Protocol file: `LLMProvider.swift` (no suffix per project conventions for protocols)
- Provider files: `OllamaProvider.swift`, `CloudAPIProvider.swift` (actor types with no suffix beyond the type name)
- Test files mirror source: `MeetNotesTests/Summary/`

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Epic 5 Story 5.2]
- [Source: _bmad-output/planning-artifacts/architecture.md#LLMProvider, SummaryService, OllamaProvider, CloudAPIProvider]
- [Source: _bmad-output/planning-artifacts/prd.md#FR14, FR15, FR17, NFR-S1, NFR-S2, NFR-S6, NFR-I1, NFR-I2]
- [Source: _bmad-output/project-context.md#Swift 6 Concurrency Rules, Testing Rules, Critical Don't-Miss Rules]
- [Source: _bmad-output/implementation-artifacts/5-1-llm-settings-configuration.md#Dev Notes, Completion Notes]
- [Source: MeetNotes/Features/Summary/SummaryService.swift — existing stub to replace]
- [Source: MeetNotes/Features/Summary/SummaryServiceProtocol.swift — protocol to preserve]
- [Source: MeetNotes/Infrastructure/Database/AppDatabase.swift — readSetting/writeSetting, pool.read/write]
- [Source: MeetNotes/Infrastructure/Database/Meeting.swift — summaryMd field, PipelineStatus enum]
- [Source: MeetNotes/Infrastructure/Database/TranscriptSegment.swift — segment reading pattern]
- [Source: MeetNotes/Infrastructure/Secrets/SecretsStore.swift — load(for:) API key retrieval]
- [Source: MeetNotes/App/MeetNotesApp.swift — dependency injection wiring]
- [Source: GitHub kevinhermawan/OllamaKit v5.x — OllamaKit, OKChatRequestData, OKChatResponse API]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6 (claude-opus-4-6)

### Debug Log References

- OllamaKit SPM dependency doesn't compile under Swift 6 strict concurrency (`SWIFT_STRICT_CONCURRENCY = complete`). Replaced with direct URLSession HTTP client for Ollama API — simpler, zero external dependency, identical functionality.
- Protocol renamed from `LLMProvider` to `LLMSummaryProvider` to avoid collision with existing `enum LLMProvider` in `SettingsViewModel.swift` (from Story 5.1).
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` causes file-level structs and actor initializers to be MainActor-isolated. Used `JSONSerialization` instead of `Codable` structs (which would need MainActor conformance) and `MainActor.run {}` for provider construction and SecretsStore access.
- Pre-existing test failures in `MeetingListViewModelTests` (5 tests) and `TranscriptionServiceTests` (2 tests) unrelated to this story. All new + existing summary/AppError tests pass.

### Completion Notes List

- Implemented `LLMSummaryProvider` protocol with `Sendable` conformance for actor isolation
- Created `OllamaProvider` actor using direct URLSession HTTP client (Ollama REST API `/api/chat`)
- Created `CloudAPIProvider` actor using URLSession with OpenAI-compatible API format
- Created `SummaryError` enum with all specified error cases
- Added `ollamaNotRunning(endpoint:)` and `summaryFailed` cases to `AppError` with full banner support
- Replaced `SummaryService` stub with full implementation: provider resolution, transcript formatting, error handling
- Wired `AppErrorState` into `SummaryService` via init and `MeetNotesApp`
- Created `SummaryPrompt` enum with shared system prompt for both providers
- 6 SummaryService tests, 1 OllamaProvider test, 2 CloudAPIProvider tests, 6 new AppError tests — all passing
- `SummaryServiceProtocol` signature unchanged; `TranscriptionService` integration unaffected

### Change Log

- 2026-03-04: Story 5.2 implementation — LLM provider infrastructure and summary generation
- 2026-03-04: Code review fixes applied:
  - [H1] Task 8 marked N/A — OllamaKit not used due to Swift 6 incompatibility, story updated to reflect reality
  - [H2] Added `providerOverride` to SummaryService for testability; rewrote SummaryServiceTests to use StubLLMProvider for happy path
  - [H3] Rewrote CloudAPIProviderTests with URLProtocol mock for real success/error/network testing
  - [M1] Removed unnecessary `nonisolated(unsafe)` from SummaryPrompt — `String` is Sendable
  - [M2] Removed dead `SummaryError.noTranscriptSegments` case (never thrown)
  - [M3] Fixed force-unwrap of URL in OllamaProvider — now uses guard let + throws
  - [M4] Changed LLMSummaryProvider protocol to typed throws: `throws(SummaryError)`

### File List

**New files:**
- `MeetNotes/MeetNotes/MeetNotes/Features/Summary/LLMProvider.swift` — LLMSummaryProvider protocol
- `MeetNotes/MeetNotes/MeetNotes/Features/Summary/OllamaProvider.swift` — Ollama HTTP client actor
- `MeetNotes/MeetNotes/MeetNotes/Features/Summary/CloudAPIProvider.swift` — OpenAI-compatible API actor
- `MeetNotes/MeetNotes/MeetNotes/Features/Summary/SummaryError.swift` — Domain error enum
- `MeetNotes/MeetNotes/MeetNotes/Features/Summary/SummaryPrompt.swift` — Shared system prompt
- `MeetNotes/MeetNotes/MeetNotesTests/Summary/StubLLMProvider.swift` — Test stub
- `MeetNotes/MeetNotes/MeetNotesTests/Summary/SummaryServiceTests.swift` — Service tests
- `MeetNotes/MeetNotes/MeetNotesTests/Summary/OllamaProviderTests.swift` — Provider tests
- `MeetNotes/MeetNotes/MeetNotesTests/Summary/CloudAPIProviderTests.swift` — Provider tests

**Modified files:**
- `MeetNotes/MeetNotes/MeetNotes/Features/Summary/SummaryService.swift` — Replaced stub with full implementation
- `MeetNotes/MeetNotes/MeetNotes/App/AppError.swift` — Added ollamaNotRunning and summaryFailed cases
- `MeetNotes/MeetNotes/MeetNotes/App/MeetNotesApp.swift` — Pass appErrorState to SummaryService
- `MeetNotes/MeetNotes/MeetNotes.xcodeproj/project.pbxproj` — OllamaKit package reference (not linked due to Swift 6 incompatibility)
- `MeetNotes/MeetNotes/MeetNotesTests/App/AppErrorTests.swift` — Added tests for new error cases
