# Story 5.1: LLM Settings Configuration

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a user who wants to configure how my meetings are summarized,
I want a settings panel where I can choose between local Ollama and a cloud API key, enter and manage my credentials securely, and clearly see which path is active at all times,
So that I am fully in control of whether my meeting data leaves my machine — with local always as the default.

## Acceptance Criteria

1. **Given** the user opens Settings → Summary, **When** the section renders, **Then** a provider picker shows two options: "Ollama (local)" and "Cloud API (OpenAI-compatible)" — Ollama is the default selection (FR28)

2. **Given** the user selects "Ollama (local)", **When** the settings panel updates, **Then** a text field for the Ollama endpoint URL is shown, pre-populated with `http://localhost:11434` (FR15, FR30) **And** a `🔒 On-device` status pill is visible, indicating no data will leave the machine (NFR-S6)

3. **Given** the user selects "Cloud API", **When** the settings panel updates, **Then** a secure text field for the API key is shown with a placeholder: "sk-…" (FR14, FR29) **And** a `☁️ Cloud` status pill is visible, indicating data will be sent externally (NFR-S6)

4. **Given** the user enters and saves an API key, **When** the save action completes, **Then** the key is stored exclusively in the macOS Keychain via `SecretsStore.save(apiKey:for:)` — not in UserDefaults, SQLite, or any log (NFR-S1)

5. **Given** the user clears the API key field and saves, **When** the action completes, **Then** `SecretsStore.delete(for:)` removes the key from the Keychain (FR29)

6. **Given** the user has not configured any LLM provider, **When** the settings panel is viewed, **Then** a notice reads: "No AI provider configured — transcripts will be saved without summaries." (FR17) **And** this state does not block recording or transcription from functioning

7. **Given** `SettingsViewModel` is `@Observable @MainActor final class`, **When** the Swift 6 concurrency checker runs, **Then** there are zero actor isolation warnings

## Tasks / Subtasks

- [x] Task 1: Add LLM settings properties and methods to SettingsViewModel (AC: #1, #2, #3, #4, #5, #6, #7)
  - [x] 1.1 Add properties: `selectedLLMProvider` (String, default "ollama"), `ollamaEndpoint` (String, default "http://localhost:11434"), `isAPIKeyConfigured` (Bool), `apiKeyInput` (String, transient — never persisted)
  - [x] 1.2 Add `loadLLMSettings()` method — reads `llm_provider` and `ollama_endpoint` from database via `AppDatabase.readSetting(key:)`, checks Keychain for API key presence via `SecretsStore.load(for:)`
  - [x] 1.3 Add `setLLMProvider(_ provider: String)` — writes to database via `AppDatabase.writeSetting(key:value:)`
  - [x] 1.4 Add `setOllamaEndpoint(_ url: String)` — validates URL, writes to database
  - [x] 1.5 Add `saveCloudAPIKey(_ key: String)` — saves to Keychain via `SecretsStore.save(apiKey:for:)`, updates `isAPIKeyConfigured` flag, writes `"openai_api_key_configured" = "true"` to database settings
  - [x] 1.6 Add `deleteCloudAPIKey()` — calls `SecretsStore.delete(for:)`, sets `isAPIKeyConfigured = false`, writes `"openai_api_key_configured" = "false"` to database settings
  - [x] 1.7 Call `loadLLMSettings()` from existing `loadSettings()` method

- [x] Task 2: Add Summary section to SettingsView (AC: #1, #2, #3, #6)
  - [x] 2.1 Add `summarySection` computed property with provider picker (Picker with two options)
  - [x] 2.2 Add conditional Ollama endpoint TextField (shown when "ollama" selected)
  - [x] 2.3 Add conditional Cloud API SecureField for API key (shown when "cloud" selected)
  - [x] 2.4 Add Save/Delete API key buttons for cloud configuration
  - [x] 2.5 Add status pill view: `🔒 On-device` (green, `Color.onDeviceGreen`) for Ollama, `☁️ Cloud` for Cloud API
  - [x] 2.6 Add "No AI provider configured" notice when neither is configured
  - [x] 2.7 Guard all transitions/animations with `@Environment(\.accessibilityReduceMotion)` (NFR-A4)
  - [x] 2.8 Add VoiceOver accessibility labels to all controls (NFR-A1)

- [x] Task 3: Add LLM-related AppError cases (AC: #4, #5)
  - [x] 3.1 Add `keychainSaveFailed` case to `AppError` enum
  - [x] 3.2 Add `bannerMessage`, `recoveryLabel`, `sfSymbol`, `systemSettingsURL` for new cases
  - [x] 3.3 Update any exhaustive switch statements in AppError

- [x] Task 4: Write tests for LLM settings functionality (AC: #1-#7)
  - [x] 4.1 Test initial state: `selectedLLMProvider == "ollama"`, `ollamaEndpoint == "http://localhost:11434"`, `isAPIKeyConfigured == false`
  - [x] 4.2 Test `loadLLMSettings()` reads from database correctly
  - [x] 4.3 Test `setLLMProvider("cloud")` persists to database
  - [x] 4.4 Test `setOllamaEndpoint()` persists to database
  - [x] 4.5 Test `saveCloudAPIKey()` updates `isAPIKeyConfigured` flag (Keychain tests hardware-dependent — mark with appropriate availability)
  - [x] 4.6 Test `deleteCloudAPIKey()` resets `isAPIKeyConfigured` flag
  - [x] 4.7 Test that transcript-only mode is unaffected (no LLM does not block recording)

## Dev Notes

### Architecture Patterns and Constraints

- **SettingsViewModel** is already `@Observable @MainActor final class` — this story EXTENDS it, not replaces it. The existing transcription model management code stays untouched.
- **SecretsStore** already exists at `Infrastructure/Secrets/SecretsStore.swift` with `save(apiKey:for:)`, `load(for:)`, `delete(for:)` using `LLMProviderKey` enum (`.openAI`, `.anthropic`). Use it directly — do NOT create a new secrets abstraction.
- **AppDatabase** already has `readSetting(key:)` and `writeSetting(key:value:)` methods using the `settings` table. Use these for all LLM preferences (provider choice, endpoint URL). API keys go to Keychain ONLY.
- **SummaryService** exists as a stub actor at `Features/Summary/SummaryService.swift` — it currently just updates `pipeline_status` to `complete`. This story does NOT implement actual LLM calls — that's Story 5.2. This story only configures which provider the user wants.
- **Three-layer error rule**: SettingsViewModel catches errors from SecretsStore, maps to `AppError`, posts to `AppErrorState`. Never rethrow from ViewModel.
- **Swift 6 strict concurrency**: All new code must compile with zero warnings under `SWIFT_STRICT_CONCURRENCY = complete`.

### Database Settings Keys

| Key | Type | Default | Purpose |
|-----|------|---------|---------|
| `"llm_provider"` | String | `"ollama"` | Active LLM provider (`"ollama"` or `"cloud"`) |
| `"ollama_endpoint"` | String | `"http://localhost:11434"` | Ollama server endpoint URL |
| `"openai_api_key_configured"` | String | `"false"` | Flag indicating if API key is set (actual key in Keychain) |

### Security Rules (NFR-S1, NFR-S2)

- API keys EXCLUSIVELY in macOS Keychain via `SecretsStore` — NEVER in UserDefaults, SQLite, plist, or logs
- Never log the API key value; `logger.info("API key saved")` is fine, `logger.info("API key: \(key)")` is a security violation
- `CloudAPIProvider` instantiation is Story 5.2 scope — this story only stores/manages the key

### UX Design Constraints

- **Design tokens**: Use `Color.windowBg`, `Color.cardBg`, `Color.cardBorder`, `Color.accent`, `Color.onDeviceGreen`, `Color.recordingRed` from `UI/Components/Color+DesignTokens.swift`
- **Typography**: SF Pro only; sizes 11/13/15pt per role
- **Spacing**: 4pt base grid — xs:4, sm:8, md:12, lg:16, xl:24, 2xl:32
- **Corner radii**: 6pt buttons, 10pt list rows, 12pt cards, 16pt settings sections
- **Status pills**: `🔒 On-device` with `Color.onDeviceGreen` tint for Ollama; `☁️ Cloud` for Cloud API
- **All animations guarded** by `@Environment(\.accessibilityReduceMotion)`
- **All materials fall back** to solid `Color.cardBg` when `accessibilityReduceTransparency` enabled
- **44x44pt minimum touch targets** (NFR-A3)
- Raycast-inspired AI provider settings pattern — simplified to 2 providers only

### Source Tree Components to Touch

**Modify:**
- `Features/Settings/SettingsViewModel.swift` — Add LLM settings properties and methods
- `Features/Settings/SettingsView.swift` — Add Summary section with provider picker, conditional fields, status pills
- `App/AppError.swift` — Add `keychainSaveFailed` case
- `MeetNotesTests/Settings/SettingsViewModelTests.swift` — Add LLM settings test cases (extend existing `@MainActor struct`)

**No new files needed** — all changes extend existing types. SettingsView and SettingsViewModel are the primary targets.

### Testing Standards

- Use **Swift Testing** (`@Test`, `#expect`) — not XCTest
- Test struct is `@MainActor` (already exists as `SettingsViewModelTests`)
- Use **temp file-backed AppDatabase** for database tests (pattern already established in existing tests)
- **SecretsStore Keychain tests** are hardware-dependent — mark appropriately or test only the flag-based logic (database `openai_api_key_configured` flag updates)
- Mock/stub pattern: existing `StubModelDownloadManager` and `StubTranscriptionService` show the injection pattern

### Previous Story Learnings (Story 4.4)

- Logger pattern for `@MainActor` classes: `private let logger = Logger(subsystem:category:)` at instance level
- SettingsViewModel already uses `private let logger` — follow same pattern
- ValueObservation not needed here (settings are read-on-demand, not live-observed)
- Environment injection: SettingsViewModel is already wired in `MeetNotesApp.init()` and injected via `.environment(settingsVM)` into `Settings` scene

### What This Story Does NOT Do (Scope Boundaries)

- Does NOT implement actual LLM API calls (Story 5.2)
- Does NOT create `LLMProvider` protocol, `OllamaProvider`, or `CloudAPIProvider` actors (Story 5.2)
- Does NOT show summary views or streaming display (Story 5.3)
- Does NOT implement notifications (Story 5.4)
- Does NOT add OllamaKit dependency usage — that's Story 5.2
- ONLY configures user preferences and securely stores credentials

### Project Structure Notes

- Alignment with unified project structure: all changes in `Features/Settings/` and `App/` — consistent with existing patterns
- No new folders or file structure changes needed
- Design token colors referenced from `UI/Components/Color+DesignTokens.swift` (verify `onDeviceGreen` token exists; if not, add it: `#34C759`)

### References

- [Source: _bmad-output/planning-artifacts/epics.md#Epic 5 Story 5.1]
- [Source: _bmad-output/planning-artifacts/architecture.md#SecretsStore, SettingsViewModel, LLMProvider]
- [Source: _bmad-output/planning-artifacts/prd.md#FR14, FR15, FR17, FR28, FR29, FR30, NFR-S1, NFR-S2, NFR-S6]
- [Source: _bmad-output/planning-artifacts/ux-design-specification.md#AI Provider Settings Pattern, Design Tokens]
- [Source: MeetNotes/Infrastructure/Secrets/SecretsStore.swift — existing Keychain implementation]
- [Source: MeetNotes/Features/Settings/SettingsViewModel.swift — existing ViewModel to extend]
- [Source: MeetNotes/Features/Settings/SettingsView.swift — existing view to extend]
- [Source: MeetNotes/Infrastructure/Database/AppDatabase.swift — readSetting/writeSetting methods]
- [Source: MeetNotes/App/AppError.swift — existing error enum to extend]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6

### Debug Log References

None required — clean implementation with all tests passing on first run.

### Completion Notes List

- Extended `SettingsViewModel` with LLM provider selection (ollama/cloud), endpoint configuration, and API key management via SecretsStore/Keychain
- Added `summarySection` to `SettingsView` with segmented provider picker, conditional Ollama endpoint/Cloud API key fields, status pills, and "no provider configured" notice
- Added `keychainSaveFailed` case to `AppError` with all required switch branches
- Three-layer error rule followed: SecretsStore throws -> SettingsViewModel catches -> posts to AppErrorState
- API keys stored exclusively in macOS Keychain via SecretsStore; only a boolean flag persisted in database
- All 12 new LLM tests pass; all 17 existing SettingsViewModelTests pass (29 total); no regressions introduced
- VoiceOver accessibility labels on all interactive controls; `reduceMotion` environment already present in view
- Swift 6 strict concurrency: `@Observable @MainActor final class` pattern maintained; zero warnings

### Change Log

- 2026-03-04: Implemented Story 5.1 — LLM Settings Configuration (all 4 tasks complete)
- 2026-03-04: Code review — Fixed 4 issues: (H1) Cloud status pill now shows whenever Cloud selected, not just when key configured; (M1+M2) Replaced magic strings with `LLMProvider` enum for type-safe provider selection; (M3) Added CI-fragility note on Keychain tests. 3 LOW issues deferred (unused env declarations, public loadLLMSettings, permissive URL validation).

### File List

- MeetNotes/MeetNotes/MeetNotes/Features/Settings/SettingsViewModel.swift (modified — added LLM properties and methods)
- MeetNotes/MeetNotes/MeetNotes/Features/Settings/SettingsView.swift (modified — added Summary section with provider picker, status pills, conditional fields)
- MeetNotes/MeetNotes/MeetNotes/App/AppError.swift (modified — added keychainSaveFailed case)
- MeetNotes/MeetNotes/MeetNotesTests/Settings/SettingsViewModelTests.swift (modified — added 12 LLM settings tests)
