# Story 5.3: Summary View & Streaming Display

Status: done

## Story

As a user who just finished a meeting,
I want to open the meeting detail view and immediately see a structured summary with decisions, action items, and key topics streaming in progressively,
So that I can start scanning the outcome before the full summary finishes generating.

## Acceptance Criteria

1. **Given** the user opens a meeting while `pipeline_status = 'summarizing'`, **When** the detail view renders, **Then** the `SummaryView` appears above the transcript with section headers visible (Decisions, Action Items, Key Topics) and content streams in token-by-token — no blank waiting state.

2. **Given** the summary has completed and `summary_md` is populated, **When** the detail view is opened for any past meeting, **Then** the full structured summary is rendered in `SummaryBlockView` sections above the transcript in the same scrollable document.

3. **Given** the meeting has no summary (`summary_md` is `NULL` and no LLM is configured), **When** the detail view opens, **Then** only the transcript is shown; the summary section is absent — no error, no broken layout.

4. **Given** `SummaryView` contains action items, **When** they are rendered, **Then** each action item is displayed as an `ActionItemCard` with a periwinkle accent tint, distinct from regular text.

5. **Given** the `On-device` or `Cloud` badge is visible, **When** any meeting detail is shown, **Then** the current LLM path status badge is displayed.

6. **Given** `@Environment(\.accessibilityReduceMotion)` is enabled, **When** summary tokens are streaming in, **Then** streaming animation is disabled — text renders fully formed when available.

## Tasks / Subtasks

- [x]Task 1: Add streaming method to `LLMSummaryProvider` protocol (AC: #1)
  - [x]1.1 Add `func summarizeStreaming(transcript: String) -> AsyncThrowingStream<String, Error>` to `LLMSummaryProvider`
  - [x]1.2 Keep existing `summarize(transcript:)` method — provide default implementation that collects the stream

- [x]Task 2: Add streaming support to `OllamaProvider` (AC: #1)
  - [x]2.1 Implement `summarizeStreaming` using `URLSession.bytes(for:)` with `"stream": true`
  - [x]2.2 Parse NDJSON lines — each line is a JSON object with `message.content` string chunk
  - [x]2.3 Yield each content chunk through the `AsyncThrowingStream`
  - [x]2.4 Keep existing non-streaming `summarize` as fallback (calls streaming + collects)

- [x]Task 3: Add streaming support to `CloudAPIProvider` (AC: #1)
  - [x]3.1 Implement `summarizeStreaming` using SSE (`"stream": true` in request body)
  - [x]3.2 Parse `data: {...}` lines from SSE stream, extract `choices[0].delta.content`
  - [x]3.3 Handle `data: [DONE]` terminator
  - [x]3.4 Yield each content chunk through the `AsyncThrowingStream`

- [x]Task 4: Add streaming callback to `SummaryService` (AC: #1)
  - [x]4.1 Add `private var onStreamingChunk: (@MainActor @Sendable (String, String) -> Void)?` — `(meetingID, accumulatedText)`
  - [x]4.2 Add `func setStreamingHandler(_ handler: @escaping @MainActor @Sendable (String, String) -> Void)` method
  - [x]4.3 Modify `summarize(meetingID:)` to use `summarizeStreaming` when handler is set
  - [x]4.4 Accumulate chunks and call handler with full accumulated text after each chunk
  - [x]4.5 Save final accumulated text to `summary_md` when stream completes

- [x]Task 5: Update `MeetingDetailViewModel` for summary streaming (AC: #1, #2, #3)
  - [x]5.1 Add `var summaryMarkdown: String?` — populated from `meeting?.summaryMd` or live streaming
  - [x]5.2 Add `var isSummarizing: Bool` — derived from `meeting?.pipelineStatus == .summarizing`
  - [x]5.3 Add `var isStreamingSummary: Bool` — true when actively receiving streaming chunks
  - [x]5.4 Register streaming handler on `SummaryService` in `load(meetingID:)` to receive live chunks
  - [x]5.5 Update `summaryMarkdown` on each streaming chunk arrival
  - [x]5.6 When meeting observation fires with `pipelineStatus == .complete`, read final `summaryMd` from database

- [x]Task 6: Create `SummaryView` component (AC: #1, #2, #3, #5)
  - [x]6.1 Create `Features/Summary/SummaryView.swift` — accepts `summaryMarkdown: String?`, `isSummarizing: Bool`, `isStreamingSummary: Bool`
  - [x]6.2 Parse `summary_md` markdown into three sections: Decisions, Action Items, Key Topics
  - [x]6.3 Render each section as a `SummaryBlockView`
  - [x]6.4 Show skeleton placeholders (2-3 lines of `.quaternarySystemFill` rounded rects) when `isSummarizing && summaryMarkdown == nil`
  - [x]6.5 Skeleton-to-content transition: crossfade over 0.2s (guarded by reduceMotion)
  - [x]6.6 Show LLM path status badge (`On-device` or `Cloud`) in the summary header
  - [x]6.7 If `summaryMarkdown` is nil and not summarizing, render nothing (return `EmptyView`)

- [x]Task 7: Create `SummaryBlockView` component (AC: #1, #2, #4, #6)
  - [x]7.1 Create `Features/Summary/SummaryBlockView.swift` — section block with emoji header + content
  - [x]7.2 Section headers: "Decisions", "Action Items", "Key Topics" with 15pt Semibold
  - [x]7.3 Progressive content: items append with `easeIn(0.15)` animation (guarded by reduceMotion)
  - [x]7.4 Typing cursor (`|`) appended during streaming, removed on completion
  - [x]7.5 Section headers never disappear once shown
  - [x]7.6 Accessibility: section label announces count ("Decisions section, 3 items")

- [x]Task 8: Create `ActionItemCard` component (AC: #4, #6)
  - [x]8.1 Create `Features/Summary/ActionItemCard.swift` — callout card for action items
  - [x]8.2 Layout: AssigneeName (12pt Semibold, accentColor) + TaskText (flex) + DueDate (trailing, 11pt)
  - [x]8.3 Periwinkle 8% bg, 20% border; hover → 40% border
  - [x]8.4 Tap copies "{assignee}: {task} (due {date})" to clipboard with green flash 0.8s
  - [x]8.5 Animate in with 0.08s stagger (guarded by reduceMotion)
  - [x]8.6 Accessibility: full label read as one sentence, hint: "Double tap to copy to clipboard"

- [x]Task 9: Integrate `SummaryView` into `MeetingDetailView` (AC: #1, #2, #3)
  - [x]9.1 Add `SummaryView` above `TranscriptView` in `MeetingDetailView`
  - [x]9.2 Both summary and transcript in the same scrollable container
  - [x]9.3 Auto-scroll follows new streaming content only if user is at bottom
  - [x]9.4 "Jump to live" badge when user has scrolled up during streaming

- [x]Task 10: Add inline error handling for summary failures (AC: #1)
  - [x]10.1 Show inline error card within `SummaryView` if Ollama is unreachable
  - [x]10.2 Error message: "Ollama isn't running. Start Ollama to generate your meeting summary."
  - [x]10.3 Buttons: [Open Ollama] (via `NSWorkspace.shared.open`) | [Retry] | [Dismiss]
  - [x]10.4 Transcript always remains visible regardless of summary error state

- [x]Task 11: Wire dependencies in `MeetNotesApp` (AC: #1, #5)
  - [x]11.1 Pass `SummaryService` reference to `MeetingDetailViewModel` for streaming handler registration
  - [x]11.2 Read LLM provider setting for status badge display
  - [x]11.3 Ensure `MeetingDetailViewModel` is created once and injected via `.environment()`

- [x]Task 12: Write tests (AC: #1-#6)
  - [x]12.1 `SummaryViewModelStreamingTests` — verify `summaryMarkdown` updates on streaming chunks
  - [x]12.2 `SummaryViewModelTests` — verify completed summary loads from database
  - [x]12.3 `SummaryViewModelTests` — verify nil summary produces absent summary section
  - [x]12.4 `SummaryMarkdownParserTests` — verify parsing of markdown into Decisions/Actions/Topics sections
  - [x]12.5 `OllamaProviderStreamingTests` — verify NDJSON parsing yields correct chunks
  - [x]12.6 `CloudAPIProviderStreamingTests` — verify SSE parsing yields correct chunks
  - [x]12.7 Test reduce-motion flag disables animations (verify state, not visual)

## Dev Notes

### Architecture Patterns

- **Services are `actor` types.** `SummaryService` is already an actor. Streaming handler must cross actor boundary safely via `@MainActor @Sendable` closure.
- **ViewModels are `@Observable @MainActor final class`.** `MeetingDetailViewModel` already follows this pattern. Add streaming properties as `var` — `@Observable` handles change detection.
- **Three-layer error rule:** Provider throws `SummaryError` → `SummaryService` catches + maps to `AppError` + posts to `AppErrorState` → View renders inline error card. Views never call `try`.
- **`ValueObservation` for completed summaries.** The existing `meetingCancellable` in `MeetingDetailViewModel` already observes the meeting row. When `pipeline_status` transitions to `complete`, the observation fires and `summaryMd` is available.
- **Streaming is additive.** Live streaming supplements the existing non-streaming path. If the meeting is already complete when the view opens, the summary is read from the database via ValueObservation — no streaming needed.

### Critical Implementation Details

**Streaming Protocol Extension:**
The `LLMSummaryProvider` protocol currently has only `func summarize(transcript:) async throws(SummaryError) -> String`. Add a streaming variant. Provide a default implementation of the non-streaming method that collects the stream:

```swift
protocol LLMSummaryProvider: Sendable {
    func summarize(transcript: String) async throws(SummaryError) -> String
    func summarizeStreaming(transcript: String) -> AsyncThrowingStream<String, Error>
}

extension LLMSummaryProvider {
    func summarize(transcript: String) async throws(SummaryError) -> String {
        var result = ""
        do {
            for try await chunk in summarizeStreaming(transcript: transcript) {
                result += chunk
            }
        } catch let error as SummaryError {
            throw error
        } catch {
            throw SummaryError.providerFailure(error)
        }
        return result
    }
}
```

**OllamaProvider Streaming — NDJSON parsing:**
Set `"stream": true` in request body. Response is NDJSON (newline-delimited JSON). Each line:
```json
{"model":"llama3.2","message":{"role":"assistant","content":"##"},"done":false}
```
Last line has `"done": true`. Use `URLSession.bytes(for:)` and iterate `lines` on the `AsyncBytes`.

**CloudAPIProvider Streaming — SSE parsing:**
Set `"stream": true` in request body. Response is Server-Sent Events. Each chunk:
```
data: {"choices":[{"delta":{"content":"##"}}]}
```
Stream ends with `data: [DONE]`. Use `URLSession.bytes(for:)`, parse lines prefixed with `data: `.

**Summary Markdown Parsing:**
The LLM prompt (in `SummaryPrompt.swift`) produces markdown with exactly three sections: `## Decisions`, `## Action Items`, `## Key Topics`. Parse by splitting on `## ` headers. Each section's content is bullet points. For Action Items, parse each bullet for assignee name, task text, and optional due date.

**SummaryService Streaming Pattern:**
```swift
// In SummaryService.summarize(meetingID:)
if let handler = onStreamingChunk {
    var accumulated = ""
    for try await chunk in provider.summarizeStreaming(transcript: transcriptText) {
        accumulated += chunk
        await handler(meetingID, accumulated)
    }
    // Save final accumulated text
    try await database.pool.write { db in
        try db.execute(sql: "UPDATE meetings SET summary_md = ?, pipeline_status = ? WHERE id = ?",
                       arguments: [accumulated, Meeting.PipelineStatus.complete.rawValue, meetingID])
    }
} else {
    // Existing non-streaming path
    let summary = try await provider.summarize(transcript: transcriptText)
    // ... save as before
}
```

**MeetingDetailViewModel Streaming Handler:**
```swift
// Register handler when loading a meeting that is currently summarizing
if meeting?.pipelineStatus == .summarizing {
    await summaryService.setStreamingHandler { [weak self] meetingID, text in
        guard self?.meeting?.id == meetingID else { return }
        self?.summaryMarkdown = text
        self?.isStreamingSummary = true
    }
}
```

### OllamaKit NOT Used

Story 5.2 discovered that OllamaKit v5.x does not compile under Swift 6 strict concurrency (`SWIFT_STRICT_CONCURRENCY = complete`). The project uses direct `URLSession` HTTP calls to the Ollama REST API instead. Do NOT add OllamaKit as a dependency.

### Existing Code to Extend (Do NOT Recreate)

| File | What exists | What to add |
|---|---|---|
| `Features/Summary/LLMProvider.swift` | `LLMSummaryProvider` protocol with `summarize` | Add `summarizeStreaming` method |
| `Features/Summary/OllamaProvider.swift` | Non-streaming `summarize` via URLSession | Add streaming with `"stream": true` + NDJSON parsing |
| `Features/Summary/CloudAPIProvider.swift` | Non-streaming `summarize` via URLSession | Add streaming with `"stream": true` + SSE parsing |
| `Features/Summary/SummaryService.swift` | Full implementation with provider resolution | Add streaming handler + modify `summarize` to stream |
| `Features/MeetingDetail/MeetingDetailViewModel.swift` | ValueObservation for meeting + segments | Add `summaryMarkdown`, `isSummarizing`, streaming handler |
| `Features/MeetingDetail/MeetingDetailView.swift` | Header + TranscriptView | Add SummaryView above TranscriptView |
| `Infrastructure/Database/Meeting.swift` | `summaryMd: String?`, `pipelineStatus` | No changes needed |
| `App/AppError.swift` | `.ollamaNotRunning`, `.summaryFailed` | No changes needed |
| `App/AppErrorState.swift` | `post()`, `clear()` | No changes needed |

### New Files to Create

| File | Type | Purpose |
|---|---|---|
| `Features/Summary/SummaryView.swift` | SwiftUI View | Container view parsing markdown into section blocks |
| `Features/Summary/SummaryBlockView.swift` | SwiftUI View | Individual section (Decisions/Actions/Topics) with streaming |
| `Features/Summary/ActionItemCard.swift` | SwiftUI View | Styled card for action items with copy-to-clipboard |
| `MeetNotesTests/Summary/SummaryViewTests.swift` | Test | Summary view model streaming + parsing tests |
| `MeetNotesTests/Summary/OllamaProviderStreamingTests.swift` | Test | NDJSON streaming parse tests |
| `MeetNotesTests/Summary/CloudAPIProviderStreamingTests.swift` | Test | SSE streaming parse tests |

### Database Settings Keys (from Story 5.1)

| Key | Purpose |
|---|---|
| `"llm_provider"` | Active provider: `"ollama"` or `"cloud"` |
| `"ollama_endpoint"` | Ollama URL (default `http://localhost:11434`) |
| `"openai_api_key_configured"` | Flag for API key existence in Keychain |

Read `llm_provider` setting from `AppDatabase.readSetting(key:)` to determine the LLM path badge.

### Accessibility Requirements

- **Every** `withAnimation` and `.animation()` must be guarded by `@Environment(\.accessibilityReduceMotion)`
- When `reduceMotion` is true: no streaming animation, text renders fully formed, no opacity transitions, no stagger animations, no crossfades
- `SummaryBlockView` section label announces count: "Decisions section, 3 items"
- `ActionItemCard` full label read as one sentence; hint: "Double tap to copy to clipboard"
- Materials check `@Environment(\.accessibilityReduceTransparency)` — use solid bg instead of blur

### UX Visual Spec

- Summary heading: SF Pro Display, 15pt, Semibold
- Summary body: SF Pro Text, 13pt, Regular
- ActionItemCard bg: `Color(hex: "#1C1D2E")` with border `Color(hex: "#2A2B3D")`
- ActionItemCard accent: periwinkle tint (`.controlAccentColor`)
- Status badges: "On-device" (local Ollama) / "Cloud" (cloud API)
- Skeleton loading: `.quaternarySystemFill` rounded rectangles
- Typing cursor: `|` character appended to streaming text

### Project Structure Notes

- All new view files go in `Features/Summary/` — consistent with existing feature organization
- Views in `Features/Summary/` MAY depend on ViewModels (they are feature views, not `UI/Components/`)
- Test files mirror source: `MeetNotesTests/Summary/`
- Use Swift Testing (`@Test`, `#expect`) for all new tests — not XCTest
- Test struct must be `@MainActor`

### Previous Story Intelligence

**From Story 5.2 (LLM Provider Infrastructure):**
- OllamaKit replaced with direct URLSession due to Swift 6 incompatibility — do NOT reintroduce
- Protocol renamed from `LLMProvider` to `LLMSummaryProvider` to avoid collision with `enum LLMProvider` in `SettingsViewModel`
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` — file-level structs are MainActor-isolated. Use `JSONSerialization` instead of `Codable` structs for API parsing. Use `MainActor.run {}` for provider construction and SecretsStore access.
- `SummaryService` does NOT throw from `summarize(meetingID:)` — errors are caught internally and posted to `AppErrorState`
- On LLM failure: set `pipeline_status = "complete"` (NOT `"failed"`) — transcript remains valid
- Provider resolution pattern: read `llm_provider` from database → construct provider → return nil if unconfigured
- Pre-existing test failures in `MeetingListViewModelTests` (5 tests) and `TranscriptionServiceTests` (2 tests) are unrelated — do not attempt to fix them
- `StubLLMProvider` exists in test target at `MeetNotesTests/Summary/StubLLMProvider.swift` — extend it for streaming

### Git Intelligence

Recent commits:
- `a1e7def` — Add Xcode project structure with code review fixes
- `5d57653` — Initial commit: project scaffold, planning artifacts, and Story 1.1 Swift source files

Only 2 commits — most implementation work is uncommitted. All existing source files are available in the working tree.

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Epic 5 Story 5.3]
- [Source: _bmad-output/planning-artifacts/architecture.md#SummaryView, SummaryBlockView, ActionItemCard]
- [Source: _bmad-output/planning-artifacts/architecture.md#Data Flow Step 6]
- [Source: _bmad-output/planning-artifacts/ux-design.md#SummaryBlockView, ActionItemCard, Progressive Disclosure]
- [Source: _bmad-output/project-context.md#Swift 6 Concurrency Rules, SwiftUI Rules, Testing Rules]
- [Source: _bmad-output/implementation-artifacts/5-2-llm-provider-infrastructure-summary-generation.md]
- [Source: MeetNotes/Features/Summary/SummaryService.swift — streaming integration point]
- [Source: MeetNotes/Features/Summary/LLMProvider.swift — protocol to extend]
- [Source: MeetNotes/Features/Summary/OllamaProvider.swift — add NDJSON streaming]
- [Source: MeetNotes/Features/Summary/CloudAPIProvider.swift — add SSE streaming]
- [Source: MeetNotes/Features/MeetingDetail/MeetingDetailViewModel.swift — add streaming state]
- [Source: MeetNotes/Features/MeetingDetail/MeetingDetailView.swift — integrate SummaryView]
- [Source: MeetNotes/Features/MeetingDetail/TranscriptView.swift — auto-scroll pattern reference]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6

### Debug Log References

- Swift 6 `nonisolated protocol` required for `LLMSummaryProvider` to allow actor conformance with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
- Actor `summarizeStreaming` methods marked `nonisolated` explicitly to satisfy nonisolated protocol requirements
- Raw string literal `#"..."#` caused parsing issues with `"##` in NDJSON test data; resolved using multiline strings
- Streaming test required `insertSegments` call (SummaryService skips summarization with empty segments)

### Completion Notes List

- Task 1: Added `summarizeStreaming` to `LLMSummaryProvider` protocol with default `summarize` implementation that collects stream. Protocol marked `nonisolated` for Swift 6 actor conformance.
- Task 2: Implemented NDJSON streaming in `OllamaProvider` using `URLSession.bytes(for:)` with `"stream": true`
- Task 3: Implemented SSE streaming in `CloudAPIProvider` parsing `data: {...}` lines and `data: [DONE]` terminator
- Task 4: Added `onStreamingChunk` handler to `SummaryService`; `summarize(meetingID:)` uses streaming when handler is set
- Task 5: Updated `MeetingDetailViewModel` with `summaryMarkdown`, `isSummarizing`, `isStreamingSummary`, `llmProviderLabel` properties; registers streaming handler on load
- Task 6: Created `SummaryView` with skeleton loading, summary content rendering, LLM path badge, and error card
- Task 7: Created `SummaryBlockView` with emoji headers, progressive item rendering, typing cursor, and accessibility labels
- Task 8: Created `ActionItemCard` with periwinkle styling, copy-to-clipboard, hover states, assignee/task/date parsing
- Task 9: Integrated `SummaryView` above `TranscriptView` in `MeetingDetailView` in a shared scrollable container
- Task 10: Added inline error card in `SummaryView` with Open Ollama / Retry / Dismiss buttons
- Task 11: Updated `MeetNotesApp` to pass `SummaryService` to `MeetingDetailViewModel`
- Task 12: Created tests for markdown parser, streaming ViewModel, NDJSON parsing, SSE parsing; updated existing `MeetingDetailViewModelTests`

### Senior Developer Review (AI)

**Reviewer:** Cuamatzin (via Claude Opus 4.6) on 2026-03-05
**Outcome:** Approved with fixes applied

**Issues Found & Fixed:**
- [H1] FIXED: `isAtBottom` in MeetingDetailView was never set to `false` — Tasks 9.3/9.4 scroll tracking was non-functional. Added `onAppear`/`onDisappear` on bottom anchor.
- [H2] FIXED: `ActionItemCard.copyToClipboard()` flash animation was invisible due to SwiftUI state coalescing. Deferred the animated reset with `asyncAfter`.
- [H3] FIXED: `ActionItemCard` used hardcoded `NSColor` literals instead of design tokens (`Color.cardBg`, `Color.cardBorder`).
- [M1] FIXED: `summaryError` was never passed from `MeetingDetailView` to `SummaryView` — error card was dead code. Added `summaryError` property to ViewModel, wired retry/dismiss callbacks.
- [M2] FIXED: Streaming handler on `SummaryService` was never cleared. Added `clearStreamingHandler()` calls on meeting load and stream completion.
- [M3] FIXED: `AsyncThrowingStream` in `OllamaProvider` and `CloudAPIProvider` lacked `onTermination` cancellation — spawned Tasks could leak. Added `continuation.onTermination` handlers.
- [M4] FIXED: Typing cursor in `SummaryBlockView` hidden with opacity instead of conditional rendering when `reduceMotion` enabled. Changed to `if isStreaming && !reduceMotion`.
- [L2] FIXED: Removed dead `OllamaParseError` enum from `OllamaProvider.swift`.

**Deferred:**
- [M5] `SummaryError.providerFailure(Error)` wraps non-Sendable `Error` — compiles under current Swift 6 but fragile. Low risk, deferred.
- [L1] Story File List labels `StubLLMProvider.swift` and `MeetingDetailViewModelTests.swift` as "Modified" but they're untracked in git. Cosmetic discrepancy.

### Change Log

- 2026-03-05: Implemented Story 5.3 — Summary View & Streaming Display (all 12 tasks complete)
- 2026-03-05: Code review fixes applied — 8 issues fixed (3 HIGH, 4 MEDIUM, 1 LOW)

### File List

**Modified:**
- MeetNotes/MeetNotes/MeetNotes/Features/Summary/LLMProvider.swift — Added `summarizeStreaming` method, `nonisolated` protocol, default `summarize` implementation
- MeetNotes/MeetNotes/MeetNotes/Features/Summary/OllamaProvider.swift — Replaced non-streaming `summarize` with NDJSON `summarizeStreaming`, static `checkReachable`
- MeetNotes/MeetNotes/MeetNotes/Features/Summary/CloudAPIProvider.swift — Replaced non-streaming `summarize` with SSE `summarizeStreaming`
- MeetNotes/MeetNotes/MeetNotes/Features/Summary/SummaryService.swift — Added `onStreamingChunk` handler, modified `summarize(meetingID:)` for streaming path
- MeetNotes/MeetNotes/MeetNotes/Features/MeetingDetail/MeetingDetailViewModel.swift — Added summary streaming state, LLM provider label, streaming handler registration
- MeetNotes/MeetNotes/MeetNotes/Features/MeetingDetail/MeetingDetailView.swift — Integrated `SummaryView` above `TranscriptView` in scrollable container with auto-scroll
- MeetNotes/MeetNotes/MeetNotes/App/MeetNotesApp.swift — Pass `summaryService` to `MeetingDetailViewModel`
- MeetNotes/MeetNotes/MeetNotesTests/Summary/StubLLMProvider.swift — Added `summarizeStreaming` support with `streamChunks`
- MeetNotes/MeetNotes/MeetNotesTests/MeetingDetail/MeetingDetailViewModelTests.swift — Updated for new `MeetingDetailViewModel` init signature

**New:**
- MeetNotes/MeetNotes/MeetNotes/Features/Summary/SummaryView.swift — Container view with skeleton, content, and error card
- MeetNotes/MeetNotes/MeetNotes/Features/Summary/SummaryBlockView.swift — Section block view, markdown parser, streaming cursor
- MeetNotes/MeetNotes/MeetNotes/Features/Summary/ActionItemCard.swift — Action item card with copy-to-clipboard
- MeetNotes/MeetNotes/MeetNotesTests/Summary/SummaryMarkdownParserTests.swift — Parser tests (5 tests)
- MeetNotes/MeetNotes/MeetNotesTests/Summary/SummaryViewModelTests.swift — ViewModel streaming/loading tests (5 tests)
- MeetNotes/MeetNotes/MeetNotesTests/Summary/OllamaProviderStreamingTests.swift — NDJSON parse tests (2 tests)
- MeetNotes/MeetNotes/MeetNotesTests/Summary/CloudAPIProviderStreamingTests.swift — SSE parse tests (3 tests)
