---
stepsCompleted: [step-01-validate-prerequisites, step-02-design-epics, step-03-create-stories, step-04-final-validation]
status: complete
completedAt: '2026-02-24'
inputDocuments:
  - _bmad-output/planning-artifacts/prd.md
  - _bmad-output/planning-artifacts/architecture.md
  - _bmad-output/planning-artifacts/ux-design-specification.md
---

# meet-notes - Epic Breakdown

## Overview

This document provides the complete epic and story breakdown for meet-notes, decomposing the requirements from the PRD, UX Design, and Architecture documents into implementable stories.

## Requirements Inventory

### Functional Requirements

FR1: User can start an audio recording session from any context via the menu bar icon
FR2: User can stop an active recording session from any context via the menu bar icon
FR3: User can see the current application state (idle / recording / processing) via the menu bar icon at all times
FR4: User can see elapsed recording time while a session is active
FR5: The system can capture system audio from any active meeting application (Zoom, Google Meet, Microsoft Teams, and others) via per-process audio capture
FR6: The system can simultaneously capture microphone input during a recording session
FR7: The system can combine system audio and microphone input into a single stream for transcription
FR8: The system can detect loss of system audio capture during an active recording and alert the user without interrupting the session
FR9: The system can continue recording in microphone-only mode when system audio capture is unavailable
FR10: The system can transcribe recorded audio to text on-device after a recording session ends
FR11: User can select the Whisper transcription model size used for transcription
FR12: The system can download WhisperKit transcription models on demand with visible progress
FR13: User can see transcription status and progress after a recording session stops
FR14: User can configure a cloud LLM API key (OpenAI or Anthropic-compatible) for meeting summarization
FR15: User can configure a local Ollama endpoint for on-device meeting summarization
FR16: The system can generate a structured meeting summary (key decisions, action items, overview) after transcription completes
FR17: The system can operate in transcript-only mode when no LLM is configured, without blocking recording or transcription
FR18: User can view the AI-generated summary for any recorded meeting
FR19: User can browse a chronological list of all past meetings with date, duration, and title
FR20: User can open any past meeting to view its full transcript
FR21: User can open any past meeting to view its AI-generated summary
FR22: User can search across all transcripts and summaries by keyword
FR23: User can see which transcript segments match a search query
FR24: New users are guided through granting microphone permission during first launch
FR25: New users are guided through granting screen recording permission during first launch with a plain-language explanation of why it is required
FR26: User can be informed when a required permission is missing and directed to the correct System Settings location to grant it
FR27: User can skip LLM configuration during onboarding and use transcript-only mode without being blocked
FR28: User can choose their preferred LLM provider (Ollama or cloud API key) in settings
FR29: User can enter, update, and remove their cloud LLM API key in settings
FR30: User can configure the Ollama server endpoint URL in settings
FR31: User can select the WhisperKit model size in settings
FR32: User can configure whether the application launches at login
FR33: The system can detect and surface actionable error messages for common failure modes: Ollama not running, invalid API key, missing permissions, model still downloading
FR34: User can see the capture quality status of a completed recording (full system + mic capture vs microphone-only)
FR35: The system can provide step-by-step recovery instructions specific to the failure detected
FR36: User can view application update availability and install updates from within the app
FR37: The application runs as a persistent menu bar utility without a Dock icon
FR38: User can open the main meeting history window from the menu bar
FR39: User can quit the application from the menu bar

### NonFunctional Requirements

NFR-P1: App launch to record-ready must be < 3 seconds from cold launch
NFR-P2: Post-meeting processing time must be ≤ 60 seconds end-to-end (transcription + summary) after recording stops
NFR-P3: Transcription real-time factor must be < 1x (completes faster than audio duration) on any Apple Silicon Mac
NFR-P4: Transcription accuracy must be ≤ 5% WER on clear English meeting audio
NFR-P5: First transcript available must appear ≤ 10 seconds after recording stops
NFR-P6: Audio capture continuity must have zero perceptible glitches or dropouts during a recording session
NFR-P7: RAM during transcription must be < 2 GB total application memory footprint
NFR-P8: CPU during active recording must be < 15% additional CPU usage on Apple Silicon while recording
NFR-S1: API keys (OpenAI, Anthropic, etc.) are stored exclusively in the macOS Keychain; never persisted in UserDefaults, plist files, or the SQLite database
NFR-S2: No audio, transcript, or summary data is transmitted to external servers unless the user has explicitly configured and enabled a cloud LLM API key
NFR-S3: Hardened runtime is enabled for all distributed builds; no arbitrary code execution entitlements are granted
NFR-S4: All user data is stored only in ~/Library/Application Support/meet-notes/; no data is written outside this directory without user consent
NFR-S5: No usage telemetry, crash analytics, or behavioral data is collected without explicit user opt-in
NFR-S6: The application must clearly communicate at all times which LLM path is active (local Ollama vs cloud API)
NFR-R1: ≥ 99% of recording sessions must complete without application crash or forced termination
NFR-R2: Audio recording must not be interrupted by WhisperKit model loading, database write operations, or SwiftUI rendering cycles
NFR-R3: The real-time audio callback (Core Audio tap) must never perform blocking operations — only AsyncStream.continuation.yield() is permitted
NFR-R4: The application must survive macOS sleep/wake cycles without corrupting recording state or losing captured audio buffers
NFR-R5: WhisperKit model downloads must not block the UI; the app must remain fully interactive during download
NFR-A1: All interactive controls are fully operable via VoiceOver with meaningful accessibility labels
NFR-A2: All text elements meet WCAG 2.1 AA minimum contrast ratio (4.5:1 normal text, 3:1 large text)
NFR-A3: All interactive controls meet the minimum 44×44pt touch target size per macOS HIG
NFR-A4: The application respects macOS system accessibility preferences: Reduce Motion, Reduce Transparency, Increase Contrast, Dynamic Type
NFR-A5: The application is fully operable via keyboard alone; no interaction requires mouse or trackpad
NFR-I1: LLM summarization uses the OpenAI-compatible API format — any provider using this format works without code changes
NFR-I2: Ollama connectivity failures are detected within 5 seconds and surfaced to the user without blocking other app functions
NFR-I3: All Sparkle update payloads are verified against a Developer ID signature before installation; unsigned updates are rejected
NFR-I4: WhisperKit model downloads are resumable; an interrupted download can continue from the last byte received

### Additional Requirements

**From Architecture:**

- Starter: Xcode "macOS App (SwiftUI)" template — no CLI scaffold; project initialized via Xcode project wizard with SPM dependencies (WhisperKit, GRDB.swift, OllamaKit, Sparkle)
- Build settings: MACOSX_DEPLOYMENT_TARGET=14.2, ARCHS=arm64, SWIFT_VERSION=6.0, ENABLE_HARDENED_RUNTIME=YES
- Entitlements: com.apple.security.app-sandbox=false, com.apple.security.device.audio-input=true, com.apple.security.screen-recording=true, com.apple.security.network.client=true
- SQLite schema via GRDB DatabasePool + WAL: meetings table, segments table, settings table, segments_fts (FTS5 virtual table with Porter stemming), and sync triggers — all set up via numbered DatabaseMigrator migrations at first launch
- SecretsStore struct (static methods only) wrapping macOS Keychain SecItem APIs — the sole permitted path for API key read/write/delete
- PermissionService: @Observable @MainActor; detects and monitors microphone + screen recording TCC status including runtime revocation
- RecordingService actor: Core Audio Tap + AVAudioEngine; AsyncStream<AVAudioPCMBuffer> bridge; direct pipeline handoff to TranscriptionService on stop
- TranscriptionService actor: WhisperKit integration; saves segments to DB; calls SummaryService on completion
- ModelDownloadManager actor: resumable WhisperKit model download; publishes progress; base model (~145MB) bundled/pre-downloaded in onboarding
- SummaryService actor: calls LLMProvider protocol; saves summary_md to DB; updates pipeline_status
- LLMProvider protocol: OllamaProvider (default, OllamaKit) and CloudAPIProvider (URLSession, OpenAI-compatible) conformances
- AppErrorState: @Observable @MainActor; single error bus; services post AppError values; views render ErrorBannerView inline (no modals)
- RecordingState enum: idle / recording(startedAt:audioQuality:) / processing(meetingID:phase:) / error(AppError)
- Four ViewModels: RecordingViewModel, MeetingListViewModel, MeetingDetailViewModel, SettingsViewModel — all @Observable @MainActor final class
- Onboarding launch gate: hasCompletedOnboarding UserDefaults boolean; skipped on reinstall if permissions already granted
- CI/CD: GitHub Actions — ci.yml (PR: build + test on macos-14), release.yml (main merge: archive → sign → notarize → DMG → GitHub Release → Sparkle appcast)
- Logging: os.log Logger per-file; category = containing type name; os_signpost on transcription consumer loop for Instruments profiling
- No raw audio files in v1.0 — PCM buffers stream directly from RecordingService to TranscriptionService via AsyncStream; no M4A written to disk
- Database migrations: append-only numbered migrations via DatabaseMigrator; migrations run on every launch; idempotent by design
- Implementation sequence: project setup → AppDatabase → SecretsStore → PermissionService → RecordingService → TranscriptionService → SummaryService → RecordingViewModel → MenuBarExtra → MainWindow → MeetingDetail → Settings → Onboarding → AppErrorState banners → CI/CD

**From UX Design Specification:**

- Liquid Glass design language: GlassSidebarView (.ultraThinMaterial + real NSVisualEffectView vibrancy), RecordingCapsuleView (.regularMaterial, capsule 28pt radius), SummaryBlockView (cardBg #1C1D2E), ActionItemCard (periwinkle 8% tint)
- Design system color tokens: accent #5B6CF6, recordingRed #FF3B30, onDeviceGreen #34C759, warningAmber #FF9F0A, windowBg #13141F (dark), cardBg #1C1D2E, cardBorder #2A2B3D
- Typography: SF Pro only; no custom fonts; sizes 11/13/15pt per role
- Spacing: 4pt base grid — xs:4, sm:8, md:12, lg:16, xl:24, 2xl:32
- Corner radii: 6pt buttons, 10pt list rows, 12pt cards, 16pt settings sections, 28pt capsule
- Window dimensions: sidebar 240pt expanded / 52pt collapsed; min window 760×520pt; meeting row height 56pt
- PrivacyBadge: persistent 🔒 On-device badge in sidebar header at all times across all states
- Menu bar icon: static mic glyph at idle; animated 3-bar waveform + red dot while recording (1.2s cycle, reduceMotion-aware)
- Sidebar auto-hides to 52pt icon rail during recording; returns on Stop; first occurrence shows subtle tooltip
- State-driven window transform: idle layout / recording layout (sidebar hidden, title bar timer) / post-meeting layout
- Window title bar repurposed as live recording clock ("Sprint Review · 12:34 ●") during recording state
- Post-meeting view: structured summary leads (✅ Decisions / ⚡ Action Items / 📌 Key Topics), full transcript expandable below — one scrollable document, no tabs
- Summary tokens stream incrementally as LLM generates; section headers render first; skeleton shimmer before content
- Rich macOS notification fires on processing complete: first decision + first action item inline; tapping opens direct to that meeting's view
- Meeting list: temporal grouping (Today / This Week / Older / [Month Year]); hover-reveal trailing actions (Export / Copy Summary / Delete)
- MeetingRowView: 2-line row (topic label 13pt Medium + date/duration 11pt Regular); context menu with Copy Transcript, Copy Summary, Export as Markdown, Rename, Delete
- Text selection popover on transcript text: Copy / Create Action Item / Highlight
- Cmd+Shift+R global hotkey for start/stop recording (works from any app); Cmd+F focus search
- All SwiftUI transitions and animations guarded by @Environment(\.accessibilityReduceMotion); all materials fall back to solid cardBg when accessibilityReduceTransparency enabled
- Custom component inventory: GlassSidebarView, PrivacyBadge, RecordingCapsuleView, WaveformView, MeetingRowView, SummaryBlockView, ActionItemCard, ModelDownloadCard, OnboardingWizardView
- Onboarding wizard: 3-step full-screen modal (Welcome → Permissions+Test Recording → You're Ready); permissions granted inline; test recording with live transcript confirms everything works before first real meeting
- WhisperKit base model bundled (or downloaded during onboarding) for zero-wait first recording
- Empty state: SF Symbol illustration + "Start Recording" CTA (or "Set Up meet-notes" if permissions missing)
- Error recovery: inline banners only (never modal alerts); single recovery CTA per error; explicit "no data lost" copy where relevant

### FR Coverage Map

FR1: Epic 3 - Start recording from menu bar
FR2: Epic 3 - Stop recording from menu bar
FR3: Epic 3 - App state visible via menu bar icon
FR4: Epic 3 - Elapsed recording time display
FR5: Epic 3 - System audio capture via Core Audio Tap
FR6: Epic 3 - Microphone capture
FR7: Epic 3 - Combined audio stream
FR8: Epic 3 - Tap-loss detection + alert
FR9: Epic 3 - Microphone-only fallback mode
FR10: Epic 4 - On-device WhisperKit transcription
FR11: Epic 4 - Whisper model size selection
FR12: Epic 4 - Model download with visible progress
FR13: Epic 4 - Transcription status and progress
FR14: Epic 5 - Cloud LLM API key configuration
FR15: Epic 5 - Ollama endpoint configuration
FR16: Epic 5 - Structured meeting summary generation
FR17: Epic 5 - Transcript-only mode (no LLM)
FR18: Epic 5 - View AI-generated summary
FR19: Epic 4 - Browse meeting history list
FR20: Epic 4 - View full transcript for any meeting
FR21: Epic 5 - View AI summary for any meeting
FR22: Epic 6 - Full-text search across transcripts
FR23: Epic 6 - Highlighted matching transcript segments
FR24: Epic 2 - Microphone permission onboarding
FR25: Epic 2 - Screen recording permission onboarding with explanation
FR26: Epic 2 - Missing permission guidance + System Settings link
FR27: Epic 2 - Skip LLM config during onboarding
FR28: Epic 5 - LLM provider selection in settings
FR29: Epic 5 - Cloud LLM API key management
FR30: Epic 5 - Ollama endpoint URL configuration
FR31: Epic 6 - WhisperKit model size setting
FR32: Epic 6 - Launch-at-login setting
FR33: Epic 6 - Actionable error messages for all failure modes
FR34: Epic 6 - Capture quality status display
FR35: Epic 6 - Step-by-step recovery instructions
FR36: Epic 6 - In-app update availability + install (Sparkle)
FR37: Epic 1 - Menu bar utility, no Dock icon
FR38: Epic 1 - Open main window from menu bar
FR39: Epic 1 - Quit from menu bar

## Epic List

### Epic 1: Application Foundation
The app boots reliably as a persistent menu bar utility with no Dock icon, a main window users can open, and a CI/CD pipeline that ships every merge to `main` as a notarized DMG.
**FRs covered:** FR37, FR38, FR39

### Epic 2: Permissions & First-Launch Onboarding
New users complete a 3-step wizard that grants microphone and screen recording permissions inline with a test recording — arriving ready for their first real meeting, with no developer knowledge required.
**FRs covered:** FR24, FR25, FR26, FR27

### Epic 3: Audio Recording
Users can start and stop recording any meeting from the menu bar in one click, with system audio + microphone captured together, real-time status always visible, and graceful handling of audio tap loss — all without any window interaction.
**FRs covered:** FR1, FR2, FR3, FR4, FR5, FR6, FR7, FR8, FR9

### Epic 4: Transcription & Meeting Library
After a recording stops, the meeting is automatically transcribed on-device by WhisperKit. Users can browse their complete meeting history, open any past meeting, and read its full transcript — with model selection and download progress for larger models.
**FRs covered:** FR10, FR11, FR12, FR13, FR19, FR20

### Epic 5: AI Summarization & Settings
After transcription, a structured summary (Decisions, Action Items, Key Topics) is generated automatically via local Ollama or a cloud API key. Users can configure their preferred LLM path, view any meeting's summary, and the app functions in transcript-only mode when no LLM is configured.
**FRs covered:** FR14, FR15, FR16, FR17, FR18, FR21, FR28, FR29, FR30

### Epic 6: Search, Full Settings & Error Recovery
Users can search across all past transcripts and summaries by keyword with FTS5 instant results and segment highlighting. Remaining settings (model size, launch-at-login) are configurable. All failure modes surface actionable inline banners. Sparkle handles in-app updates.
**FRs covered:** FR22, FR23, FR31, FR32, FR33, FR34, FR35, FR36

---

## Epic 1: Application Foundation

The app boots reliably as a persistent menu bar utility with no Dock icon, a main window users can open, and a CI/CD pipeline that ships every merge to `main` as a notarized DMG.

### Story 1.1: Xcode Project Initialization & Runnable Shell

As a developer building meet-notes,
I want the Xcode project correctly configured with all required build settings, entitlements, SPM dependencies, and feature-based project structure,
So that the app runs as a stable menu bar utility from day one and all subsequent stories have a consistent, well-configured foundation to build on.

**Acceptance Criteria:**

**Given** the repository is cloned and opened in Xcode 16.3+
**When** the project is built and run on an Apple Silicon Mac with macOS 14.2+
**Then** it compiles without errors under Swift 6 strict concurrency mode
**And** MACOSX_DEPLOYMENT_TARGET = 14.2, ARCHS = arm64, SWIFT_VERSION = 6.0, ENABLE_HARDENED_RUNTIME = YES are confirmed in Build Settings

**Given** the project is initialized
**When** the entitlements file is inspected
**Then** it contains: `com.apple.security.app-sandbox = false`, `com.apple.security.device.audio-input = true`, `com.apple.security.screen-recording = true`, `com.apple.security.network.client = true`

**Given** the project is initialized
**When** the SPM package list is inspected
**Then** WhisperKit (Argmax), GRDB.swift, OllamaKit, and Sparkle are all present as SPM dependencies, and SwiftLint is added as an SPM plugin

**Given** the app launches on an Apple Silicon Mac
**When** it appears in the system
**Then** no Dock icon is shown (NSApp activation policy = `.accessory`) and a meet-notes icon appears in the macOS menu bar (FR37)

**Given** the menu bar icon is visible
**When** the user clicks it
**Then** a popover appears containing an "Open meet-notes" item and a "Quit" item

**Given** the popover is open
**When** the user clicks "Open meet-notes"
**Then** the main window opens and becomes frontmost (FR38)

**Given** the popover is open
**When** the user clicks "Quit"
**Then** the application terminates cleanly (FR39)

**Given** the system appearance is dark
**When** the app window is visible
**Then** all surfaces render with design token colors (windowBg `#13141F`, cardBg `#1C1D2E`, accent `#5B6CF6`) and there are no hardcoded color literals in SwiftUI views

**Given** the project folder structure is established
**Then** it contains the directories: `App/`, `Features/Recording/`, `Features/Transcription/`, `Features/Summary/`, `Features/MeetingList/`, `Features/MeetingDetail/`, `Features/Settings/`, `Features/Onboarding/`, `Infrastructure/Database/`, `Infrastructure/Permissions/`, `Infrastructure/Secrets/`, `UI/MenuBar/`, `UI/MainWindow/`, `UI/Components/`, `MeetNotesTests/`

### Story 1.2: App Database Foundation & Secrets Store

As a developer building meet-notes,
I want the SQLite database initialized with the full schema (meetings, segments, settings, FTS5) via GRDB DatabasePool + WAL mode, and API keys stored exclusively in the macOS Keychain,
So that all subsequent features have a reliable, secure data layer that never blocks the audio pipeline and never exposes credentials.

**Acceptance Criteria:**

**Given** the app launches for the first time
**When** AppDatabase initializes
**Then** a GRDB DatabasePool opens (WAL mode) at `~/Library/Application Support/meet-notes/meetings.db`
**And** the v1 migration runs, creating: `meetings` table, `segments` table, `settings` table, `segments_fts` FTS5 virtual table with Porter stemming and `content='segments'`

**Given** the v1 migration creates the sync triggers
**When** a segment is inserted into the `segments` table
**Then** the `segments_ai` trigger automatically inserts the segment's `text` into `segments_fts`

**Given** a segment is deleted from `segments`
**When** the `segments_ad` trigger fires
**Then** the deleted row is removed from `segments_fts`

**Given** the app launches when the database already exists
**When** the DatabaseMigrator runs
**Then** it is idempotent — already-applied migrations are skipped without error or data loss

**Given** `SecretsStore.save(apiKey:for:)` is called with a credential
**When** the operation completes
**Then** the key is stored in the macOS Keychain via `SecItem` APIs
**And** the key is NOT present in UserDefaults, any SQLite table, any plist file, or any log output (NFR-S1)

**Given** `SecretsStore.load(for:)` is called when no key has been saved
**Then** it returns `nil` without throwing

**Given** `SecretsStore.delete(for:)` is called
**Then** the key is removed from the Keychain and subsequent `load(for:)` calls return `nil`

**Given** the Swift 6 concurrency checker runs
**When** the entire AppDatabase and SecretsStore codebase is analyzed
**Then** there are zero actor isolation warnings or errors

### Story 1.3: Automated Build & Distribution Pipeline

As a developer building meet-notes,
I want every PR to run a CI build and every merge to `main` to automatically produce a code-signed, notarized DMG and update the Sparkle appcast,
So that releases are always current, correctly signed for Gatekeeper, and secure against tampering — with zero manual shipping steps.

**Acceptance Criteria:**

**Given** a pull request is opened against `main`
**When** the `ci.yml` GitHub Actions workflow runs on `macos-14`
**Then** the project builds successfully, all unit tests pass, and SwiftLint reports no violations
**And** the PR cannot be merged until CI passes (branch protection rule)

**Given** a commit is merged to `main`
**When** the `release.yml` workflow runs
**Then** it archives the app with Xcode, signs it with the Developer ID Application certificate, and notarizes with `xcrun notarytool`

**Given** notarization succeeds
**When** the workflow continues
**Then** it staples the notarization ticket, packages the app into a `.dmg`, uploads the DMG to GitHub Releases, and updates `appcast.xml` with the new release entry including the download URL, version, and `sparkle:edSignature`

**Given** the Sparkle appcast is updated
**When** a running instance of meet-notes checks for updates
**Then** Sparkle validates the downloaded DMG's signature against the embedded `SUPublicEDKey` before installing — unsigned or mismatched payloads are rejected (NFR-I3)

**Given** the release workflow runs
**When** `CFBundleVersion` needs incrementing
**Then** `agvtool` or a build number script auto-increments the build number on each merge; `CFBundleShortVersionString` is managed manually in `Info.plist`

---

## Epic 2: Permissions & First-Launch Onboarding

New users complete a 3-step wizard that grants microphone and screen recording permissions inline with a test recording — arriving ready for their first real meeting, with no developer knowledge required.

### Story 2.1: Permission Service & Runtime Monitoring

As a developer building meet-notes,
I want a centralized `PermissionService` that tracks microphone and screen recording TCC authorization status — including runtime revocation — and publishes changes to all consumers,
So that every feature can react to permission state without scattered `AVCaptureDevice.authorizationStatus()` checks, and the app never silently fails due to a revoked permission.

**Acceptance Criteria:**

**Given** the app launches
**When** `PermissionService` initializes
**Then** it checks and publishes the current authorization status for both microphone and screen recording

**Given** microphone permission is not yet granted
**When** `PermissionService.requestMicrophone()` is called
**Then** it triggers the system microphone permission prompt and updates its published status on resolution

**Given** screen recording permission is not yet granted
**When** `PermissionService.requestScreenRecording()` is called
**Then** it opens System Settings → Privacy & Security → Screen Recording and updates status when the app regains focus (FR25)

**Given** a permission is revoked by the user in System Settings while the app is running
**When** the app regains focus or a periodic status check fires
**Then** `PermissionService` updates its published status to `.denied` and all observing views receive the update

**Given** `PermissionService` is declared `@Observable @MainActor`
**When** the Swift 6 concurrency checker runs
**Then** there are zero actor isolation warnings

### Story 2.2: First-Launch Onboarding Wizard

As a new user launching meet-notes for the first time,
I want a 3-step full-screen onboarding wizard that walks me through microphone and screen recording permission grants with plain-language explanations and an inline test recording,
So that I arrive ready for my first real meeting with full confidence that the app is working correctly — without needing any technical knowledge.

**Acceptance Criteria:**

**Given** the app launches and `hasCompletedOnboarding` is `false` in UserDefaults
**When** `MeetNotesApp` evaluates the launch gate
**Then** the `OnboardingWizardView` is presented as a full-screen modal before the main window (FR24)

**Given** the wizard is on Step 1 (Welcome)
**When** the user reads the screen
**Then** they see the app name, the "Local only — your audio never leaves this Mac" privacy hero message, and a "Get started" CTA button

**Given** the wizard is on Step 2 (Permissions)
**When** it is presented
**Then** microphone permission is requested first with a plain-English explanation of why it is needed (FR24)
**And** after microphone is granted, screen recording permission is requested with an explicit explanation: "meet-notes uses Screen Recording to capture system audio from Zoom, Google Meet, and other apps. No screen is ever recorded." (FR25)

**Given** both permissions are granted on Step 2
**When** the user taps "Test Recording"
**Then** a short test recording starts, capturing a few seconds of microphone audio, and a live transcript snippet appears — confirming the pipeline works end-to-end before the first real meeting

**Given** the user reaches Step 3 (You're Ready)
**When** they click "Start your first meeting"
**Then** `hasCompletedOnboarding` is set to `true` in UserDefaults, the onboarding modal is dismissed, and the main app window is shown

**Given** the app is reinstalled and `hasCompletedOnboarding` is already `true`
**When** the app launches
**Then** the onboarding wizard is skipped entirely

**Given** the user wants to skip LLM configuration during onboarding
**When** prompted for LLM setup
**Then** they can proceed without entering an API key or Ollama endpoint, and the app functions in transcript-only mode (FR27)

### Story 2.3: Missing Permission Recovery & Guidance

As a user whose permissions were denied or revoked,
I want the app to detect missing permissions, show me a clear explanation of what is missing, and give me a single-tap path to the correct System Settings location to fix it,
So that I never get silently stuck and can recover without needing to search for solutions.

**Acceptance Criteria:**

**Given** microphone permission is denied when the user attempts to start a recording
**When** `PermissionService` detects the denied state
**Then** an inline banner is shown: "Microphone access required. [Open System Settings →]" — no modal dialog (FR26)
**And** tapping the link opens System Settings → Privacy & Security → Microphone directly

**Given** screen recording permission is denied when the user attempts to start a recording
**When** `PermissionService` detects the denied state
**Then** an inline banner is shown: "Screen Recording permission is required to capture audio from meeting apps. [Open System Settings →]" (FR26)
**And** tapping the link opens System Settings → Privacy & Security → Screen Recording directly

**Given** a permission is revoked while the app is running
**When** `PermissionService` detects the revocation
**Then** the relevant inline banner appears immediately without crashing or silently continuing

**Given** the main window empty state is shown when permissions are missing
**When** the user sees it
**Then** the CTA reads "Set Up meet-notes" instead of "Start Recording"

**Given** both permissions are granted after following recovery instructions
**When** the app regains focus
**Then** the warning banners disappear and the app returns to normal state without requiring a restart

---

## Epic 3: Audio Recording

Users can start and stop recording any meeting from the menu bar in one click, with system audio + microphone captured together, real-time status always visible, and graceful handling of audio tap loss — all without any window interaction.

### Story 3.1: Menu Bar Recording Controls & State Machine

As a user in the middle of any app,
I want a menu bar icon that shows the current recording state and lets me start or stop a recording in one click without switching focus,
So that recording any meeting takes zero deliberate effort and I always know what the app is doing.

**Acceptance Criteria:**

**Given** the app is idle
**When** the menu bar icon is visible
**Then** it shows a static microphone glyph (SF Symbol `mic`)

**Given** the user clicks the menu bar icon and taps "Start Recording"
**When** recording begins
**Then** the menu bar icon transitions to an animated 3-bar waveform with a red dot (1.2s cycle) (FR1, FR3)
**And** `RecordingViewModel.state` transitions to `.recording(startedAt: Date, audioQuality: .full)`
**And** the elapsed time counter starts from `0:00` and increments every second (FR4)

**Given** a recording is active
**When** the user clicks the menu bar icon
**Then** the popover shows the elapsed time, an audio quality status indicator, and a prominent "Stop Recording" button (FR2, FR3)

**Given** the user taps "Stop Recording"
**When** the action is processed
**Then** `RecordingViewModel.state` transitions to `.processing(...)` and the menu bar icon returns to the static mic glyph with a subtle spinner overlay (FR3)

**Given** the `@Environment(\.accessibilityReduceMotion)` preference is enabled
**When** the recording state is active
**Then** the waveform animation does not play; only the static red dot + mic glyph are shown (NFR-A4)

**Given** `RecordingViewModel` is `@Observable @MainActor final class`
**When** state changes are observed from `MenuBarPopoverView` and `MainWindowView`
**Then** both surfaces update simultaneously from the single shared `RecordingViewModel` instance — no `@StateObject` or `ObservableObject` patterns used

### Story 3.2: Core Audio Capture Pipeline

As a user recording a meeting,
I want system audio from my meeting app and my own microphone voice captured simultaneously and combined into a single audio stream,
So that the full meeting — both what I hear and what I say — is available for transcription with no setup required for each meeting app.

**Acceptance Criteria:**

**Given** recording starts and screen recording permission is granted
**When** `RecordingService.start()` is called
**Then** a Core Audio Tap is installed on the target meeting process to capture system audio (FR5)
**And** `AVAudioEngine` is started to capture microphone input simultaneously (FR6)

**Given** both audio sources are running
**When** buffers arrive from the Core Audio tap callback
**Then** only `continuation.yield(buffer)` is called inside the callback — no `await`, no actor calls, no database access, no `os_log` (NFR-R3 absolute rule)

**Given** buffers are yielded into the `AsyncStream`
**When** `RecordingService` consumes them on its actor executor
**Then** system audio and microphone streams are resampled to 16kHz mono Float32 via `AVAudioConverter` and combined into a single `AsyncStream<AVAudioPCMBuffer>` for transcription (FR7)

**Given** a recording is active and WhisperKit model loading, database writes, or SwiftUI rendering occur
**When** these operations run on their respective threads/actors
**Then** the Core Audio tap callback is never blocked, delayed, or interrupted — zero audio dropouts are produced (NFR-R2, NFR-P6)

**Given** `RecordingService` is declared as a Swift `actor`
**When** the Swift 6 concurrency checker runs
**Then** there are zero actor isolation warnings or errors

**Given** the user stops a recording
**When** `RecordingService.stop()` is called
**Then** the Core Audio tap is removed, `AVAudioEngine` is stopped, the `AsyncStream` is finished, and the captured audio stream is passed to `TranscriptionService`

### Story 3.3: Audio Resilience — Tap Loss, Mic Fallback & Sleep/Wake

As a user recording a meeting when something goes wrong,
I want the app to detect audio tap loss within 2 seconds, warn me without interrupting the meeting, automatically fall back to microphone-only recording, and survive Mac sleep/wake cycles intact,
So that I always get at least a partial transcript even under adverse conditions, and I am never left with silent, undetected recording failures.

**Acceptance Criteria:**

**Given** a recording is active
**When** `RecordingService`'s 1-second repeating health monitor fires
**Then** it checks whether the Core Audio tap is still delivering buffers within the expected cadence

**Given** the health monitor detects that no system audio buffers have arrived for ≥2 seconds
**When** tap loss is confirmed
**Then** `RecordingViewModel.state` is updated to `.recording(..., audioQuality: .micOnly)`
**And** an inline warning banner appears: "System audio capture lost. Recording microphone only." — the recording session is NOT stopped (FR8)

**Given** the tap-loss warning is shown
**When** the recording continues
**Then** microphone-only audio continues to be captured and streamed to `TranscriptionService` (FR9)

**Given** the recording stops after a tap-loss event
**When** the meeting record is saved to the database
**Then** the `audio_quality` column is set to `'mic_only'` or `'partial'` (FR34 prerequisite)

**Given** the Mac enters sleep while a recording is active
**When** `AppDelegate` receives the `NSWorkspace.willSleepNotification`
**Then** the Core Audio tap is cleanly paused and the audio stream is suspended without losing buffered data (NFR-R4)

**Given** the Mac wakes from sleep
**When** `AppDelegate` receives the `NSWorkspace.didWakeNotification`
**Then** the Core Audio tap is resumed and the recording continues from where it left off without corruption or crash (NFR-R4)

**Given** CPU usage is measured during an active recording (before transcription begins)
**When** profiled on any Apple Silicon Mac
**Then** the app's additional CPU contribution stays below 15% (NFR-P8)

---

## Epic 4: Transcription & Meeting Library

After a recording stops, the meeting is automatically transcribed on-device by WhisperKit. Users can browse their complete meeting history, open any past meeting, and read its full transcript — with model selection and download progress for larger models.

### Story 4.1: WhisperKit Transcription Pipeline

As a user who just stopped a recording,
I want my meeting automatically transcribed on-device — with the first transcript segment appearing within 10 seconds and the full transcript ready within 60 seconds — without any action on my part,
So that I have a complete text record of every meeting the moment it ends.

**Acceptance Criteria:**

**Given** `RecordingService.stop()` completes and hands off the audio stream
**When** `TranscriptionService.transcribe(meetingID:audioStream:)` is called
**Then** it processes the `AsyncStream<AVAudioPCMBuffer>` through WhisperKit on the Apple Neural Engine
**And** the `meetings` row for this session has `pipeline_status` updated from `'recording'` to `'transcribing'`

**Given** WhisperKit produces transcript segments
**When** each segment is generated
**Then** it is saved as a row in the `segments` table (with `meeting_id`, `start_seconds`, `end_seconds`, `text`, `confidence`)
**And** the `segments_ai` FTS5 trigger runs automatically, indexing the text for search

**Given** transcription completes
**When** the final segment is saved
**Then** `pipeline_status` on the `meetings` row is updated to `'transcribed'`
**And** `TranscriptionService` directly calls `SummaryService.summarize(meetingID:)` (direct actor call pipeline)

**Given** the first transcript segment is produced
**When** measured from the moment `RecordingService.stop()` was called
**Then** it appears in the database within ≤10 seconds (NFR-P5)

**Given** a 1-hour meeting recording is transcribed
**When** measured from recording stop to final segment saved
**Then** total transcription time is less than the meeting duration (real-time factor <1x on any Apple Silicon Mac) (NFR-P3)
**And** total end-to-end processing (transcription + summary) completes within ≤60 seconds for a typical 30-minute meeting (NFR-P2)

**Given** transcription is running
**When** total application memory is measured
**Then** it stays below 2 GB (NFR-P7)

**Given** the app is killed mid-transcription and relaunched
**When** the app starts and finds a meeting with `pipeline_status = 'transcribing'`
**Then** it can restart transcription for that meeting (crash recovery via `pipeline_status` column)

### Story 4.2: Model Management & Transcription Settings

As a user who wants higher transcription accuracy,
I want to choose between WhisperKit model sizes, see download progress, and switch models without the UI freezing,
So that I can balance transcription speed and accuracy for my needs, with the base model always immediately available.

**Acceptance Criteria:**

**Given** the app launches for the first time
**When** the onboarding wizard completes
**Then** the WhisperKit base model (~145MB) is already downloaded and ready — no wait required before the first recording (FR12)

**Given** the user opens Settings → Transcription
**When** they view the model selection section
**Then** they see `ModelDownloadCard` entries for each available model size, each showing name, file size, accuracy badge, and speed badge (FR11)

**Given** the user selects a larger model (e.g. large-v3-turbo) that has not been downloaded
**When** they tap "Download"
**Then** `ModelDownloadManager` begins a resumable download with a visible progress bar in the card (FR12, NFR-R5)

**Given** a model download is in progress
**When** the user navigates away from Settings or starts a recording
**Then** the download continues in the background and the UI remains fully interactive — no blocking (NFR-R5)

**Given** a model download is interrupted (network loss, app quit)
**When** the download is resumed
**Then** it continues from the last byte received rather than restarting from zero (NFR-I4)

**Given** a model has finished downloading
**When** the user selects it as their active model in Settings
**Then** `TranscriptionService` uses it for all subsequent transcriptions (FR11)

**Given** a recording stops while a model download is in progress
**When** `TranscriptionService` is invoked
**Then** it uses the currently active (already-downloaded) model, not the one still downloading

### Story 4.3: Meeting History List

As a user who wants to review past meetings,
I want a sidebar showing all my meetings grouped by recency — Today, This Week, Older — with each row showing a title, date, and duration,
So that I can quickly find and open any past meeting without scrolling through a flat undifferentiated list.

**Acceptance Criteria:**

**Given** at least one meeting has been recorded and transcribed
**When** the main window is open
**Then** the sidebar shows a `MeetingListView` with meetings sorted by `started_at` DESC (FR19)

**Given** meetings exist from today, this week, and older dates
**When** the list is rendered
**Then** meetings are grouped under section headers: "Today", "This Week", "Older", and "[Month Year]" for older groups

**Given** a meeting row is displayed
**When** the user sees it
**Then** it shows a bold AI-generated topic label (or date as fallback) on line 1, and date + duration (`42 min`) on line 2 in secondary text — 2-line max (FR19)

**Given** no meetings have been recorded yet
**When** the main window opens
**Then** the content area shows the empty state: an SF Symbol illustration and a "Start Recording" CTA button (or "Set Up meet-notes" if permissions are missing)

**Given** `MeetingListViewModel` uses GRDB `ValueObservation`
**When** a new meeting is saved to the database after recording stops
**Then** the meeting list updates automatically without a manual refresh

**Given** the user hovers over a meeting row
**When** the cursor enters the row
**Then** trailing action buttons appear: Export, Copy Summary, Delete

**Given** the user right-clicks a meeting row
**When** the context menu appears
**Then** it shows: Copy Transcript, Copy Summary, Export as Markdown, Rename, Delete

### Story 4.4: Meeting Transcript Detail View & Navigation Routing

As a user reviewing a past meeting or arriving from an external trigger (e.g., a notification tap),
I want to open any meeting and read its full timestamped transcript in a clean, scrollable view — and for the app to navigate directly to any specific meeting when triggered from outside the view hierarchy,
So that I can find and read the exact words spoken at any point in a meeting, and external sources like notifications can always open the correct meeting immediately.

**Acceptance Criteria:**

**Given** the user clicks a meeting in the sidebar
**When** the detail view opens
**Then** `MeetingDetailViewModel` loads all `segments` for that meeting from the database and displays them in `TranscriptView` in chronological order (FR20)

**Given** the transcript is displayed
**When** the user reads it
**Then** each segment shows its timestamp (`0:12:34`) and transcribed text, rendered at 13pt

**Given** the user selects a word or phrase in the transcript
**When** the selection is made
**Then** a popover appears with three actions: "Copy", "Create Action Item", and "Highlight"

**Given** the meeting is still in `pipeline_status = 'transcribing'`
**When** the user opens the detail view
**Then** a processing status indicator is shown (e.g. "Transcribing… 34%") and segments appear progressively as they are saved (FR13)

**Given** the meeting has `audio_quality = 'mic_only'` or `'partial'`
**When** the detail view header is shown
**Then** a status badge reads "Microphone only — system audio was unavailable" (FR34 prerequisite)

**Given** `MeetingDetailViewModel` is `@Observable @MainActor final class`
**When** the `TranscriptView` renders new segments
**Then** it uses `@Observable` properties only — no `ObservableObject`, no `@Published`

**Given** `NavigationState` is a `@Observable @MainActor final class` created at the app root in `MeetNotesApp` and injected into the SwiftUI environment via `.environment(navigationState)`
**When** any actor or AppDelegate calls `NavigationState.openMeeting(id: UUID)` on the main actor
**Then** `NSApp.activate(ignoringOtherApps: true)` is called, `MainWindowView` becomes frontmost, and `selectedMeetingID` is set to the given UUID — causing `ContentView` to navigate to that meeting's detail view

**Given** `NavigationState.selectedMeetingID` is set to a valid meeting UUID
**When** `ContentView` observes the change
**Then** the sidebar selection updates and `MeetingDetailView` for that meeting is displayed in the detail pane — no additional user action required

**Given** the app is already frontmost and displaying the target meeting's detail view
**When** `NavigationState.openMeeting(id:)` is called with the same meeting UUID
**Then** no navigation change occurs and the view remains stable (no duplicate push or scroll reset)

---

## Epic 5: AI Summarization & Settings

After transcription, a structured summary (Decisions, Action Items, Key Topics) is generated automatically via local Ollama or a cloud API key. Users can configure their preferred LLM path, view any meeting's summary, and the app functions in transcript-only mode when no LLM is configured.

### Story 5.1: LLM Settings Configuration

As a user who wants to configure how my meetings are summarized,
I want a settings panel where I can choose between local Ollama and a cloud API key, enter and manage my credentials securely, and clearly see which path is active at all times,
So that I am fully in control of whether my meeting data leaves my machine — with local always as the default.

**Acceptance Criteria:**

**Given** the user opens Settings → Summary
**When** the section renders
**Then** a provider picker shows two options: "Ollama (local)" and "Cloud API (OpenAI-compatible)" — Ollama is the default selection (FR28)

**Given** the user selects "Ollama (local)"
**When** the settings panel updates
**Then** a text field for the Ollama endpoint URL is shown, pre-populated with `http://localhost:11434` (FR15, FR30)
**And** a `🔒 On-device` status pill is visible, indicating no data will leave the machine (NFR-S6)

**Given** the user selects "Cloud API"
**When** the settings panel updates
**Then** a secure text field for the API key is shown with a placeholder: "sk-…" (FR14, FR29)
**And** a `☁️ Cloud` status pill is visible, indicating data will be sent externally (NFR-S6)

**Given** the user enters and saves an API key
**When** the save action completes
**Then** the key is stored exclusively in the macOS Keychain via `SecretsStore.save(apiKey:for:)` — not in UserDefaults, SQLite, or any log (NFR-S1)

**Given** the user clears the API key field and saves
**When** the action completes
**Then** `SecretsStore.delete(for:)` removes the key from the Keychain (FR29)

**Given** the user has not configured any LLM provider
**When** the settings panel is viewed
**Then** a notice reads: "No AI provider configured — transcripts will be saved without summaries." (FR17)
**And** this state does not block recording or transcription from functioning

**Given** `SettingsViewModel` is `@Observable @MainActor final class`
**When** the Swift 6 concurrency checker runs
**Then** there are zero actor isolation warnings

### Story 5.2: LLM Provider Infrastructure & Summary Generation

As a user whose meeting has finished transcribing,
I want a structured meeting summary generated automatically — with decisions, action items, and key topics — using whichever AI provider I configured,
So that I can scan the outcome of any meeting in 30 seconds without reading the full transcript.

**Acceptance Criteria:**

**Given** `TranscriptionService` completes and calls `SummaryService.summarize(meetingID:)`
**When** an LLM provider is configured
**Then** `SummaryService` calls the active `LLMProvider` conformance (`OllamaProvider` or `CloudAPIProvider`) with the full transcript text

**Given** `LLMProvider` is a protocol with `func summarize(transcript: String) async throws -> String`
**When** `SummaryService` calls it
**Then** the same call path is used for both Ollama and cloud providers — no provider-specific branching in `SummaryService` (NFR-I1)

**Given** the active provider is `OllamaProvider`
**When** a summarization request is made
**Then** it uses `OllamaKit` to call the local Ollama HTTP endpoint — no data leaves the machine (NFR-S2)

**Given** the active provider is `CloudAPIProvider`
**When** a summarization request is made
**Then** it uses `URLSession` with the OpenAI-compatible API format — the transcript is only sent because the user explicitly configured this provider (NFR-S2)

**Given** no LLM provider is configured
**When** `SummaryService.summarize(meetingID:)` is called
**Then** it skips summarization, sets `pipeline_status = 'complete'` on the meeting, and leaves `summary_md` as `NULL` — recording and transcription are unaffected (FR17)

**Given** summary generation completes
**When** the LLM response is received
**Then** `summary_md` is saved to the `meetings` row and `pipeline_status` is updated to `'complete'`

**Given** Ollama is not running when summarization is attempted
**When** `OllamaProvider` makes the HTTP request
**Then** the failure is detected within ≤5 seconds and an `AppError.ollamaNotRunning` is posted to `AppErrorState` — the transcript remains intact and accessible (NFR-I2)

### Story 5.3: Summary View & Streaming Display

As a user who just finished a meeting,
I want to open the meeting detail view and immediately see a structured summary with decisions, action items, and key topics streaming in progressively — not a blank "processing…" screen,
So that I can start scanning the outcome before the full summary finishes generating.

**Acceptance Criteria:**

**Given** the user opens a meeting while `pipeline_status = 'summarizing'`
**When** the detail view renders
**Then** the `SummaryView` appears first (above the transcript), with section headers already visible: ✅ Decisions, ⚡ Action Items, 📌 Key Topics (FR18, FR21)
**And** content streams in token-by-token — no blank waiting state is shown at any point

**Given** the summary has completed and `summary_md` is populated
**When** the detail view is opened for any past meeting
**Then** the full structured summary is rendered in `SummaryBlockView` sections above the transcript in the same scrollable document (FR18, FR21)

**Given** the meeting has no summary (`summary_md` is `NULL` and no LLM is configured)
**When** the detail view opens
**Then** only the transcript is shown; the summary section is absent — no error message, no broken layout (FR17)

**Given** `SummaryView` contains action items
**When** they are rendered
**Then** each action item is displayed as an `ActionItemCard` with a periwinkle accent tint, distinct from regular text content

**Given** the `🔒 On-device` or `☁️ Cloud` badge is visible
**When** any meeting detail or the sidebar header is shown
**Then** the current LLM path status badge is displayed at all times (NFR-S6)

**Given** `@Environment(\.accessibilityReduceMotion)` is enabled
**When** summary tokens are streaming in
**Then** the streaming animation is disabled — text renders fully formed when available (NFR-A4)

### Story 5.4: Post-Meeting Rich Notification

**Depends on:** Story 4.4 (`NavigationState` and `NavigationState.openMeeting(id:)` deep-link routing infrastructure must be in place before this story can be implemented)

As a user who is in another meeting or away from the app,
I want a macOS notification when my meeting summary is ready — showing the first decision and first action item inline — that takes me directly to that meeting when tapped,
So that I get immediate value from every meeting even without opening the app.

**Acceptance Criteria:**

**Given** `SummaryService` completes and saves `summary_md`
**When** `pipeline_status` transitions to `'complete'`
**Then** a macOS `UNUserNotification` is delivered with title "Meeting summary ready" and body containing the first decision and first action item extracted from `summary_md`

**Given** the notification is delivered
**When** the user taps it
**Then** the app activates and `MainWindowView` opens directly to the detail view for that specific meeting (FR18)

**Given** no LLM is configured and only a transcript is available
**When** transcription completes
**Then** a notification is delivered with title "Transcript ready" and body "Your meeting transcript is saved and searchable."

**Given** the user has not granted notification permission
**When** the app first needs to send a notification
**Then** the system permission prompt is shown once; if denied, the app continues functioning without notifications and does not re-prompt

**Given** the app is already frontmost and displaying that meeting's detail view
**When** a notification fires for the same meeting
**Then** tapping it does not create a duplicate view

---

## Epic 6: Search, Full Settings & Error Recovery

Users can search across all past transcripts and summaries by keyword with FTS5 instant results and segment highlighting. Remaining settings (model size, launch-at-login) are configurable. All failure modes surface actionable inline banners. Sparkle handles in-app updates.

### Story 6.1: Full-Text Search Across Meetings

As a user trying to find a specific decision or topic from a past meeting,
I want to type a keyword in the sidebar search field and instantly see all meetings and transcript segments that contain it — with matching text highlighted,
So that I can surface any specific moment from any meeting in under 10 seconds.

**Acceptance Criteria:**

**Given** the main window is open
**When** the user focuses the search field (`Cmd+F`)
**Then** the cursor moves to the sidebar search field with placeholder "Search transcripts…" (FR22)

**Given** the user types a search query
**When** each keystroke fires after a 200ms debounce
**Then** `MeetingListViewModel` executes an FTS5 Porter-stemmed query against `segments_fts` and updates the meeting list to show only meetings with matching segments (FR22)

**Given** search results are displayed
**When** the user opens a matching meeting
**Then** `TranscriptView` scrolls to the first matching segment and highlights all matching terms with the accent color `#5B6CF6` (FR23)

**Given** a search query returns no results
**When** the results list renders
**Then** an empty state reads "No meetings found for '[query]'" — not a blank list

**Given** the user clears the search field
**When** the field is empty
**Then** the full meeting list is restored immediately with no reload delay

**Given** FTS5 Porter stemming is active
**When** the user searches "decided"
**Then** meetings containing "decide", "decision", or "decided" are all returned

### Story 6.2: Remaining App Settings

As a user who wants to fine-tune how meet-notes behaves,
I want a complete settings panel where I can select my transcription model size and configure whether the app launches at login,
So that I can tailor performance, storage use, and startup behavior to my workflow.

**Acceptance Criteria:**

**Given** the user opens Settings → Transcription
**When** the model size section is shown
**Then** the currently active model is visually indicated with a checkmark and the user can select a different downloaded model (FR31)

**Given** the user selects a model that has not been downloaded yet
**When** they tap "Set as active"
**Then** a prompt clarifies the model must be downloaded first, and the "Download" button in the card is highlighted (FR31)

**Given** the user opens Settings → General
**When** the launch-at-login toggle is visible
**Then** it correctly reflects the current `SMAppService` registration state (FR32)

**Given** the user toggles launch-at-login ON
**When** the toggle switches
**Then** `SMAppService.mainApp.register()` is called and the app is added to Login Items

**Given** the user toggles launch-at-login OFF
**When** the toggle switches
**Then** `SMAppService.mainApp.unregister()` is called and the app is removed from Login Items

**Given** Settings is opened
**When** the General section is viewed
**Then** there is no telemetry, crash reporting, or analytics opt-in toggle present in v1.0 (NFR-S5)

### Story 6.3: Error Handling & Recovery System

As a user who encounters a problem during recording, transcription, or summarization,
I want the app to detect every known failure mode, show me a clear inline message with a single recovery action, and preserve any data I've already captured,
So that I am never left confused about what went wrong, and I can fix it without restarting the app or losing my meeting.

**Acceptance Criteria:**

**Given** Ollama is not running when summary generation is attempted
**When** the failure is detected within ≤5 seconds (NFR-I2)
**Then** an `AppError.ollamaNotRunning` is posted to `AppErrorState` and an `ErrorBannerView` appears inline: "Ollama is not running. [Start Ollama →]" (FR33, FR35)
**And** the transcript remains saved and accessible; only the summary is skipped

**Given** an invalid or expired API key is used for cloud summarization
**When** the provider returns a 401/403 response
**Then** `AppError.invalidAPIKey` is posted and an inline banner reads: "API key invalid or expired. [Update in Settings →]" (FR33, FR35)

**Given** microphone or screen recording permission is missing at recording start
**When** `PermissionService` detects the denied state
**Then** the relevant error is posted and the banner appears with a direct link to System Settings (FR33, FR35)

**Given** a WhisperKit model is selected that has not been downloaded
**When** a recording stops and transcription is attempted
**Then** `AppError.modelNotDownloaded` is posted and a banner reads: "Model not downloaded. [Download now →]" (FR33)

**Given** the capture quality of a completed recording is `'mic_only'` or `'partial'`
**When** the meeting detail view is opened
**Then** a status badge reads: "Partial recording — system audio was unavailable during part of this meeting." (FR34)

**Given** any error banner is shown
**When** the user reads it
**Then** it is displayed inline (never as a modal alert), contains a single clearly labelled recovery CTA, and includes "no data lost" copy where applicable (FR35)

**Given** `AppErrorState` is `@Observable @MainActor final class` injected via `.environment()`
**When** any service posts an error via `Task { @MainActor in appErrorState.post(...) }`
**Then** all observing views update simultaneously with zero race conditions

### Story 6.4: In-App Updates & Final Accessibility Pass

As a user who wants to stay on the latest version of meet-notes,
I want to be notified of available updates and install them from within the app — with all updates verified for authenticity before installing,
So that I always have the latest features and fixes without manual DMG downloads, and the app is fully accessible to all users.

**Acceptance Criteria:**

**Given** the app launches or 24 hours have elapsed since the last check
**When** the Sparkle update checker runs
**Then** it silently checks the GitHub Releases appcast for a newer version

**Given** a new version is available
**When** Sparkle detects it
**Then** an in-app update banner or the Sparkle standard sheet is shown, offering "Update Now" and "Later" options (FR36)

**Given** the user initiates an update
**When** Sparkle downloads the new DMG
**Then** it verifies the `sparkle:edSignature` against the embedded `SUPublicEDKey` before installing — an update with a mismatched or missing signature is rejected (NFR-I3)

**Given** the user opens Settings → General
**When** the auto-update section is visible
**Then** a toggle allows disabling automatic update checks and the current app version is displayed

**Given** the app is fully built
**When** a VoiceOver accessibility audit is run on all screens
**Then** every interactive control has a meaningful accessibility label (NFR-A1)
**And** all text meets WCAG 2.1 AA contrast ratios (NFR-A2)
**And** all interactive controls are ≥44×44pt (NFR-A3)
**And** all SwiftUI transitions and animations check `@Environment(\.accessibilityReduceMotion)` (NFR-A4)
**And** all material surfaces fall back to solid `cardBg` when `\.accessibilityReduceTransparency` is enabled (NFR-A4)
**And** every user flow is completable via keyboard alone (NFR-A5)
