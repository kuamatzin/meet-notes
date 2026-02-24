---
stepsCompleted: [step-01-init, step-02-discovery, step-02b-vision, step-02c-executive-summary, step-03-success, step-04-journeys, step-05-domain, step-06-innovation, step-07-project-type, step-08-scoping, step-09-functional, step-10-nonfunctional, step-11-polish, step-12-complete]
completedAt: '2026-02-23'
status: complete
classification:
  projectType: desktop_app
  domain: general
  complexity: medium
  projectContext: greenfield
inputDocuments:
  - _bmad-output/planning-artifacts/product-brief-meet-notes-2026-02-23.md
  - _bmad-output/planning-artifacts/research/technical-macos-meeting-recording-transcription-research-2026-02-23.md
  - _bmad-output/planning-artifacts/ux-design-specification.md
workflowType: 'prd'
briefCount: 1
researchCount: 1
brainstormingCount: 0
projectDocsCount: 0
---

# Product Requirements Document - meet-notes

**Author:** Cuamatzin
**Date:** 2026-02-23

## Executive Summary

meet-notes is a free, open-source macOS native application that gives meeting-heavy professionals a searchable, AI-powered memory of every conversation. It captures system audio and microphone from any meeting platform (Zoom, Google Meet, Microsoft Teams) via Core Audio Taps, transcribes entirely on-device using WhisperKit on Apple Silicon, and generates structured meeting summaries through local Ollama or a user-supplied API key. All recordings, transcripts, and notes are stored locally in SQLite. No cloud uploads. No subscriptions. No recurring cost.

**Target Users:** Individual knowledge workers — software engineers, product managers, consultants, designers, freelancers — who attend 1–10 meetings daily across any platform and use macOS as their primary work machine. They want to recall decisions, action items, and context from past meetings without paying a monthly fee or trusting sensitive audio to a third-party server.

**Problem:** Meeting-heavy professionals forget decisions and must re-ask colleagues, scrub recordings to find specific moments, and either pay ongoing subscription fees ($10–30/month) or accept cloud-based privacy trade-offs. No serious, free, native macOS option exists that keeps audio fully on-device.

**Solution:** A native macOS menu bar application delivering the complete core loop — record → transcribe → summarize → review — running entirely on the user's machine, with no required external services.

### What Makes This Special

The defining insight: tools like Otter.ai, Fireflies, and Granola solved the transcription problem well but created two new ones — a subscription tax and the requirement to upload sensitive meeting audio to a third party. meet-notes treats privacy and price as the same feature: zero cost and zero data exfiltration are achieved simultaneously by processing everything locally.

**Why this is possible now:** Three technologies reached production maturity simultaneously in 2023–2024:
- **Core Audio Taps** (macOS 14.2, Dec 2023) — eliminates virtual audio drivers; per-process capture with a single permission grant
- **WhisperKit** (Argmax, 2024) — ~1% WER on Apple Silicon via CoreML/ANE, faster than real-time
- **Ollama + OllamaKit** — local LLM summarization with a five-line Swift API

Before late 2023, a fully local, high-quality meeting recorder was not buildable without significant technical compromise. The window to ship the first polished, free, native macOS option is open now.

**Key differentiators:**
1. Always free — no subscription, no tiers, no paywalls, ever
2. Full privacy by default — audio never leaves the machine
3. Native macOS performance — Swift 6, Core Audio Taps, WhisperKit for best-in-class speed and battery efficiency
4. User sovereignty — bring your own API key or run Ollama for 100% local AI

**Deployment target:** macOS 14.2+ (required for Core Audio Taps), Apple Silicon only (WhisperKit constraint), distributed as a notarized DMG outside the App Store.

## Project Classification

| Dimension | Value |
|---|---|
| **Project Type** | Desktop application (native macOS) |
| **Domain** | General / productivity utility |
| **Complexity** | Medium — productivity software with non-trivial technical stack (real-time audio pipeline, CoreML inference, Swift Actor concurrency, local LLM integration) |
| **Project Context** | Greenfield — net-new application |
| **Distribution** | Outside Mac App Store; notarized DMG; Sparkle auto-update |
| **Platform Constraint** | macOS 14.2+, Apple Silicon only |

## Success Criteria

### User Success

Users are succeeding when meet-notes has become a passive, automatic part of their meeting workflow — not a tool they have to remember to use:

- **Complete core loop reliability:** The app records, transcribes, and summarizes every meeting without crashes, audio dropouts, or failed transcriptions. Users stop thinking about whether it "worked."
- **Recall over memory:** Users regularly return to search past meetings and find specific decisions, commitments, or context within seconds — without scrubbing recordings or asking colleagues to repeat themselves.
- **Subscription replacement:** Users cancel or downgrade paid tools (Otter.ai, Fireflies, Granola) because meet-notes covers their needs at zero cost.
- **"Aha!" moment:** Occurs when a user finds the exact moment from a past call — a specific decision, a commitment made — in under 30 seconds. This typically happens within the first 2 weeks of use.
- **Trust in privacy:** Users actively recommend meet-notes to colleagues specifically because audio never leaves the machine — privacy is a selling point, not just a footnote.

### Business Success

As a free, open-source project, success is measured by adoption health and community momentum:

| Metric | Target | Timeframe |
|---|---|---|
| Active installs | 200+ | 3 months post-launch |
| GitHub Stars | 500+ | 3 months post-launch |
| External contributors | 5+ | 6 months post-launch |
| Crash-free session rate | ≥ 99% | Ongoing from launch |
| Word-of-mouth conversions | Measurable referral mentions on HN, Reddit, Product Hunt | 3 months post-launch |

**What "working" looks like at 3 months:** meet-notes is cited in developer and professional communities as the go-to free, private macOS meeting recorder. Users are actively sharing it without being prompted.

### Technical Success

| Metric | Target | Rationale |
|---|---|---|
| Transcription accuracy (WER) | ≤ 5% on clear English meeting audio | Usable without manual correction |
| Transcription speed | Faster than real-time (< 1x) on any Apple Silicon Mac | Non-blocking post-meeting workflow |
| First transcript segment latency | ≤ 10 seconds from meeting end | Feels instant to users |
| Post-meeting processing time | ≤ 60 seconds end-to-end (transcription + summary) | Fits between consecutive meetings |
| App launch to record-ready | < 3 seconds | Frictionless start |
| Onboarding to first recording | < 5 minutes (including permissions) | Low barrier for new users |
| RAM usage during transcription | < 2 GB | Compatible with 8GB base M-series Macs |
| CPU impact during meeting | < 15% additional on Apple Silicon | Battery-safe for all-day use |

### Measurable Outcomes

**Leading indicators (weekly):**
- Active recording sessions per week per user ≥ 3
- Transcript search queries performed (users mining past meetings)
- Settings configured with API key or Ollama endpoint (LLM adoption rate)

**Lagging indicators (3–6 months):**
- GitHub stars trajectory (viral coefficient)
- Issue resolution rate and PR acceptance (community health)
- User retention: percentage of users still recording 30 days after install

## User Journeys

### Journey 1: Sofia — The Privacy-Conscious Remote PM (Happy Path)

**Who she is:** Sofia is a senior product manager at a mid-size SaaS company. She's in 6–8 video calls per day — syncs, design reviews, stakeholder calls, quarterly planning. She uses macOS, owns an M2 MacBook Pro, and pays $18/month for Otter.ai, which she resents.

**Opening scene:** It's a Tuesday. Sofia just finished a 45-minute architectural review with engineering. An hour later, a developer DMs her: "Wait, what did we decide about the API versioning?" She opens Otter.ai — the transcript is there, but she has to scrub through a 45-minute recording to find the two-minute exchange. On her way out of the app, she notices her next billing cycle charged. Again.

**Discovery:** She sees meet-notes mentioned in a Hacker News thread titled "Show HN: free, private meeting recorder for macOS." The comment reads: "no Otter, no Fireflies, audio never leaves your machine." She clicks. The GitHub README shows a DMG download link, no sign-up.

**Onboarding:** Sofia downloads the DMG, drags it to Applications, and launches. A permissions screen walks her through microphone + screen recording grants. She opens Preferences, adds her OpenAI API key, sets the Whisper model to "base" for now. The menu bar icon appears — a small waveform. Total time: 3 minutes.

**First meeting:** The next morning she opens Zoom for her 10am standup, glances at the menu bar, taps the meet-notes icon, and clicks "Start Recording." The icon turns red. She forgets about it for 20 minutes.

**The core loop delivers:** Meeting ends. She clicks "Stop." The icon pulses while processing. 40 seconds later, a notification: "Transcript ready." She opens the meeting view — a clean transcript, timestamped. Scrolls to the bottom: an AI summary with three decisions and two action items, already formatted. She copies the action items into Notion.

**The "Aha!" moment — two weeks later:** It's a Thursday afternoon. Someone asks what was agreed in the API architecture call from two weeks prior. Sofia opens meet-notes, types "API versioning" in the search bar. The exact call surfaces. She clicks to the segment: 12 minutes, 34 seconds — the exact exchange. She pastes the timestamp link in Slack. Total time: 22 seconds. She cancels Otter.ai the next day.

**Revealed requirements:** Menu bar icon with status, one-click record/stop, post-meeting transcript + summary view, searchable meeting library, copy/share from transcript, API key settings.

---

### Journey 2: Alex — The Non-Technical Marketing Manager (Onboarding Friction)

**Who he is:** Alex is a marketing manager at an agency, not a developer. He has an M1 MacBook Air, uses Zoom and Google Meet, and his company doesn't provide transcription tools. He found meet-notes via a coworker's recommendation.

**Opening scene:** Alex downloads the DMG, installs it, and sees the first-launch permissions screen. Microphone: easy. "Screen Recording" permission triggers a macOS dialog he's never seen before. He's confused — why does a recorder need screen recording? He clicks away without granting it.

**Friction point:** The app launches but shows a banner: "System audio capture requires screen recording permission. Click here to open System Settings." Alex clicks through, finds the toggle, enables it. The app works. But during setup, he sees the settings panel asking about "Ollama" — he has no idea what that is.

**Resolution path:** The settings panel has a tooltip: "Ollama runs AI summaries locally on your Mac. Don't have it? Use an API key instead, or skip for now — transcripts will still work." Alex adds his OpenAI API key (he uses ChatGPT Plus). Summaries start working.

**Long-term:** Alex never installs Ollama. The cloud API path is his permanent configuration. He records meetings, gets summaries, and never thinks about the infrastructure again.

**Revealed requirements:** Clear permission explainer screens (especially for screen recording), graceful onboarding for non-technical users, Ollama as optional (not required), API key as the accessible path, inline help text in settings, "skip for now" fallback, transcript-only mode when no LLM is configured.

---

### Journey 3: Marco — The Developer / Open-Source Contributor

**Who he is:** Marco is a senior iOS/macOS developer. He uses meet-notes personally and loves it. He opens the GitHub repo out of curiosity.

**Opening scene:** Marco reads the README, clones the project, opens it in Xcode. He wants to add a feature: export transcript as Markdown to a file. He looks at the codebase — clean MVVM structure, Swift Actors, GRDB. He understands it immediately.

**Contribution path:** Marco opens a GitHub issue describing the feature, creates a branch, implements it in `TranscriptExportService`, submits a PR. The maintainer reviews it within a week, merges it. Marco's feature ships in the next release.

**Why this matters:** Marco is the community health indicator. If the codebase is clean and well-documented, contributors like Marco appear. His PRs reduce the maintenance burden and expand capability.

**Revealed requirements:** Clean, well-structured codebase; README with architecture overview; documented contribution guidelines; Swift Package Manager for all dependencies (no proprietary tooling); GitHub Actions CI that runs on PRs.

---

### Journey 4: The Failed Recording — Error Recovery (Edge Case)

**Scenario:** Sofia starts a recording, joins a meeting, and 30 minutes in, macOS prompts her to revoke screen recording permission (this can happen on macOS 15 system updates). The Core Audio Tap silently loses access. The recording continues but captures only microphone, not system audio.

**What the app does:**
- Detects audio tap disconnection within 2 seconds
- Shows a persistent warning in the menu bar: "System audio capture lost. Recording microphone only."
- Does NOT silently fail or crash
- When recording stops, processes whatever audio was captured — transcript will be microphone-only but is better than nothing
- Post-processing screen shows: "Partial recording — system audio unavailable. Transcript based on microphone only."

**Recovery:** Sofia sees the warning, re-grants screen recording in System Settings, restarts the recording session for her next meeting. She loses 30 minutes of the current meeting's system audio but has a microphone transcript.

**Revealed requirements:** Runtime detection of audio tap loss, non-blocking warning UI (doesn't interrupt the meeting), graceful degradation to microphone-only mode, clear post-recording status indicating capture quality, actionable recovery instructions.

---

### Journey Requirements Summary

| Capability Area | Required By Journey |
|---|---|
| Menu bar icon + status indicator (idle/recording/processing) | J1, J2, J4 |
| One-click start/stop recording | J1, J2 |
| System audio capture via Core Audio Taps | J1, J4 |
| Microphone capture (fallback and primary) | J2, J4 |
| WhisperKit transcription (on-device) | J1, J2 |
| AI summary via API key (cloud path) | J2 |
| AI summary via Ollama (local path) | J1 |
| Transcript-only mode (no LLM configured) | J2 |
| Meeting history list with search | J1 |
| Transcript + summary view per meeting | J1, J2 |
| First-launch permissions walkthrough with explainers | J2 |
| Settings: API key, Ollama endpoint, model selection | J1, J2 |
| Graceful error handling: permission loss, Ollama down, invalid key | J4, J2 |
| Partial recording status + recovery instructions | J4 |
| Clean, documented codebase + GitHub Actions CI | J3 |
| In-app help text and onboarding tooltips | J2 |

## Innovation & Novel Patterns

### Detected Innovation Areas

**1. Fully Local AI Meeting Pipeline**

meet-notes is among the first consumer-grade applications to assemble a complete AI processing pipeline — audio capture → transcription → summarization — with zero required cloud dependency at any stage. Each layer is independently local:
- Capture: Core Audio Taps (macOS 14.2+, on-device)
- Transcription: WhisperKit via CoreML/Apple Neural Engine (on-device)
- Summarization: Ollama with local models (on-device)

This was structurally impossible before Q4 2023 when Core Audio Taps, WhisperKit, and production-ready Ollama became simultaneously available. The "window" to be first with a polished native macOS implementation is now open.

**2. AsyncStream as Real-Time Concurrency Bridge**

The Core Audio tap callback runs on a real-time thread with strict latency constraints — it cannot block, cannot call async functions, and cannot touch Swift actors directly. The conventional solution (shared mutable state + locks) is error-prone and violates Swift 6 concurrency guarantees.

meet-notes solves this with `AsyncStream` as a zero-copy, non-blocking bridge:
```swift
audioEngine.inputNode.installTap(...) { buffer, _ in
    continuation.yield(buffer)  // only safe cross-boundary operation
}
// Swift Actor consumes from the other side with structured concurrency
```
This pattern is not yet widely documented or standardized in the macOS community — meet-notes can serve as a reference implementation.

**3. Privacy-as-Architecture (Not Privacy-as-Setting)**

Most privacy-focused tools implement privacy as a toggle ("don't send data to our servers"). meet-notes implements privacy structurally: there is no server to send data to. The architecture makes cloud exfiltration impossible by default, not just optional. This is a meaningful distinction that positions meet-notes as a reference for privacy-first macOS app design.

### Market Context & Competitive Landscape

| Tool | Privacy Model | Price | Native macOS | On-Device AI |
|---|---|---|---|---|
| Otter.ai | Cloud audio upload | $18/mo | No (web/Electron) | No |
| Fireflies | Cloud audio upload | $18/mo | No | No |
| Granola | Cloud audio upload | $18/mo | Yes (native) | No |
| Recap (open source) | Local | Free | Yes | Partial |
| **meet-notes** | **Local only** | **Free** | **Yes** | **Yes (full pipeline)** |

The gap: no tool is simultaneously free, fully native macOS, and fully on-device across the entire pipeline. Recap is the closest competitor but is less polished and less actively maintained. meet-notes can own this position.

### Validation Approach

- **Technical validation (pre-launch):** Run WhisperKit + Ollama pipeline on 10 real recorded meetings; measure WER and summary quality against known transcripts. Target: ≤5% WER, summaries pass a "would I act on this?" user test.
- **Market validation (launch):** GitHub stars and HN/Reddit mentions within 72 hours of a "Show HN" post. Signal: any organic repost or "I switched from Otter.ai" comment.
- **Usage validation (30 days post-launch):** Transcript search query rate — users who search past meetings are validated adopters.

### Risk Mitigation

| Innovation Risk | Likelihood | Mitigation |
|---|---|---|
| Core Audio Tap API changes in macOS 26/Tahoe | Medium | Design `RecordingService` behind a protocol — swap implementation without touching UI |
| WhisperKit accuracy regression on a future model version | Low | Pin WhisperKit version; test against fixed audio corpus before upgrading |
| Ollama ecosystem fragmentation (model availability) | Low | Support OpenAI-compatible API — any provider works, Ollama is just the default |
| AsyncStream bridge blocking discovered in production | Low | Instrument with os_signpost; strict linter rule: no async calls in tap callback |
| Apple restricts Core Audio Taps in future macOS | Low | Distribution outside App Store means no App Review gate; adapt when needed |

## Desktop App Specific Requirements

### Project-Type Overview

meet-notes is a macOS-native menu bar utility — no Dock icon, always running in background, surfaced via `MenuBarExtra`. It requires deep system integration (audio entitlements, Keychain, system permissions) and is distributed exclusively outside the Mac App Store as a notarized DMG. The entire application lifecycle — install, run, update, uninstall — is self-managed without App Store infrastructure.

### Platform Support

| Dimension | Decision | Rationale |
|---|---|---|
| **Target OS** | macOS 14.2+ (Sonoma) | Minimum required for Core Audio Taps API |
| **Architecture** | Apple Silicon only (arm64) | WhisperKit requires Apple Silicon for CoreML/ANE inference |
| **Intel Mac support** | Explicitly out of scope for v1.0 | WhisperKit has no Intel fallback; communicate clearly in README and onboarding |
| **Cross-platform** | macOS only | Native macOS is the product identity; no Electron, no Tauri, no Windows/Linux |
| **Universal binary** | Not applicable | arm64 only; no need for x86_64 slice |
| **Minimum Xcode** | Xcode 16.3+ | Required for Swift 6.1 and latest WhisperKit compatibility |

**System requirements communicated to users:**
- Mac with Apple Silicon (M1 or later)
- macOS Sonoma 14.2 or later
- ~2GB free disk space (WhisperKit model download)
- Microphone + screen recording permissions

### System Integration

meet-notes integrates with macOS at multiple system layers:

**Audio Subsystem:**
- `Core Audio Taps API` — per-process system audio capture; requires screen recording TCC entitlement even for audio-only capture
- `AVAudioEngine` — microphone capture; mixed with system audio stream
- `AVAudioConverter` — resampling from system rate (44.1/48kHz stereo) → 16kHz mono Float32 (Whisper input format)
- `AsyncStream<AVAudioPCMBuffer>` — non-blocking bridge from real-time audio callback to Swift concurrency

**Required Entitlements & Permissions:**

| Permission | Entitlement | Trigger |
|---|---|---|
| Microphone | `com.apple.security.device.audio-input` | First recording attempt |
| Screen Recording | `com.apple.security.screen-recording` | Required by Core Audio Tap (even audio-only) |
| Local Network | `com.apple.security.network.client` | Ollama API calls (localhost) |
| Hardened Runtime | Required | Notarization prerequisite |

**No App Sandbox** — Core Audio Tap + screen recording entitlements conflict with App Sandbox. Distributed outside Mac App Store.

**macOS App Lifecycle:**
- `MenuBarExtra` scene (SwiftUI, macOS 13+) — menu bar icon and popover
- `NSApplication.shared.setActivationPolicy(.accessory)` — no Dock icon; background process
- `@NSApplicationDelegateAdaptor` — bridges SwiftUI lifecycle to AppKit for startup/termination
- Main window (transcript history, settings) opened on demand from menu bar

**Security — API Key Storage:**
- User API keys (OpenAI, Anthropic) stored in macOS Keychain only — never in UserDefaults or plist files

### Update Strategy

**Framework:** Sparkle (non-App Store macOS standard, open source)

| Aspect | Decision |
|---|---|
| Auto-update check | On launch + every 24 hours |
| Update delivery | Sparkle appcast XML hosted on GitHub Releases |
| User control | Users can disable auto-update in settings |
| Delta updates | Supported via Sparkle; reduces download size for incremental releases |
| Signing | All updates signed with Developer ID; Sparkle verifies signature before installing |
| Model updates | WhisperKit models downloaded separately from app update (in-app, on-demand) |

**Release pipeline:** GitHub Actions → Xcode archive → sign with Developer ID → notarize with `xcrun notarytool` → staple → create DMG → upload to GitHub Releases → update Sparkle appcast.

### Offline Capabilities

meet-notes is designed to function fully offline for its core use case:

| Feature | Offline? | Notes |
|---|---|---|
| Audio recording | ✅ Always offline | Core Audio Taps, AVAudioEngine — no network |
| Transcription (WhisperKit) | ✅ Always offline | CoreML/ANE inference; model stored locally after first download |
| AI summary (Ollama) | ✅ Fully offline | Ollama runs on localhost; no internet required |
| AI summary (API key) | ❌ Requires internet | OpenAI/Anthropic API calls; clearly communicated to user |
| Model download (first launch) | ❌ Requires internet once | ~145MB (base) or ~800MB (large-v3-turbo); progress shown; cached forever |
| App updates (Sparkle) | ❌ Optional | User-initiated; auto-check can be disabled |

**Offline UX:** If user selects API key path and is offline, app shows: "Summary unavailable — no internet connection. Transcript is ready and searchable." App never blocks recording due to network state.

### Implementation Considerations

- **No sandbox:** Entitlement file must include `audio-input` + `screen-recording` explicitly; `com.apple.security.app-sandbox` must be `false`
- **Real-time thread discipline:** Absolute rule — no async calls, no database I/O, no actor calls inside Core Audio tap callback. Only `AsyncStream.continuation.yield()` is permitted.
- **Model storage:** WhisperKit models stored in `~/Library/Application Support/meet-notes/Models/` — not bundled in DMG
- **Database:** GRDB `DatabasePool` with WAL mode; `~/Library/Application Support/meet-notes/meetings.db`
- **Audio recordings (optional):** If raw audio retention is supported, store in `~/Library/Application Support/meet-notes/Recordings/` as M4A
- **Swift Package Manager only:** All dependencies (WhisperKit, GRDB, OllamaKit, Sparkle) via SPM — no CocoaPods, no Carthage

## Product Scope & Phased Development

### MVP Strategy & Philosophy

**MVP Approach:** Experience MVP — not the minimum that *works*, but the minimum that works *beautifully*. Beautiful UI is a stated core product value. An ugly or rough MVP would contradict the core positioning ("indistinguishable from a premium paid product") and undermine word-of-mouth growth. The bar is: a user who screenshots the app should not guess it's free and open-source.

**Why not a thinner MVP:** The core value proposition is the *complete loop* — record → transcribe → summarize → review. Shipping recording + transcription without summaries is like shipping half a product; users won't be able to evaluate whether it replaces their paid tool. All four stages ship together or not at all.

**Resource Profile:**
- Team: Solo developer (intermediate Swift/macOS level)
- Timeline target: 4–6 weeks to functional MVP; 2 additional weeks for polish + distribution
- Skills required: Swift 6, SwiftUI, Core Audio (borrowable from Recap/AudioCap), GRDB (basic), Xcode signing

### MVP Feature Set (Phase 1)

**Core User Journeys Supported:**
- Journey 1 (Sofia — happy path): Complete end-to-end from discovery through "aha!" moment
- Journey 2 (Alex — onboarding friction): Non-technical user can configure and use the app without developer knowledge
- Journey 4 (Failed recording — error recovery): App degrades gracefully rather than silently failing

**Must-Have Capabilities:**

| Capability | Must-Have Rationale |
|---|---|
| Menu bar icon + status (idle/recording/processing) | Without this, users can't control recording from any context |
| System audio capture (Core Audio Taps) | Without this, meeting audio is incomplete |
| Microphone capture (mixed) | Without this, speaker's own voice is missing |
| WhisperKit transcription (base model default) | Core value — no transcript = no product |
| AI summary via user API key | Accessible path for non-Ollama users |
| AI summary via Ollama | Privacy-first path; required for "100% local" positioning |
| Transcript-only mode (no LLM) | Fallback when neither path is configured |
| Meeting history list + full-text search | Without search, "aha!" moment never happens |
| Transcript + summary view | Post-meeting review is the deliverable |
| First-launch permissions walkthrough | Without this, non-technical users get stuck at screen recording prompt |
| Settings: API key, Ollama endpoint, model selector | Required to configure either AI path |
| Graceful error handling (all failure modes) | Without this, silent failures destroy user trust |
| Light + dark mode | Day-one; follows system appearance |

**MVP success gate:** 99%+ crash-free session rate in first 30 days, core loop reliable on any meeting platform, onboarding < 5 minutes, transcription within 60 seconds of meeting end.

**Explicit MVP Exclusions** (deferred, not forgotten):

| Feature | Deferral Rationale |
|---|---|
| Real-time word-by-word transcript | WhisperKit streaming API not yet stable for production use |
| Calendar integration / auto-start | Nice-to-have; users can click record manually |
| Export to Notion / Obsidian / Markdown | Manual copy acceptable for MVP; integration complexity not justified yet |
| Speaker diarization | Requires additional ML model; adds significant complexity |
| Action item extraction to task managers | Summary text covers this need initially |
| Custom vocabulary / domain hints | Power-user feature; defer until user base established |
| Intel Mac support | WhisperKit constraint; communicate clearly, not a surprise |

### Post-MVP Features

**Phase 2 — Power UX (v1.1):**
- Real-time transcript display (when WhisperKit streaming API stabilizes)
- Calendar integration — auto-title recordings by calendar event, auto-start
- Markdown / plain text export
- Transcript timestamp navigation (click a word, jump to that moment in audio)

**Phase 3 — Intelligence (v1.2):**
- Speaker diarization — "who said what" labels on transcript segments
- Action item extraction with structured output (task list format)
- Custom vocabulary hints — bias Whisper beam search toward domain-specific terms
- Multi-model support: user can switch between Whisper model sizes per meeting

**Phase 4 — Ecosystem (v2.0+):**
- Plugin system for export integrations
- Optional team sharing (privacy-preserving, local-network-only)
- Mobile companion app for reviewing transcripts on the go
- visionOS support (same Core Audio + WhisperKit stack runs on visionOS)

### Risk Mitigation Strategy

**Technical Risks:**

| Risk | Severity | Mitigation |
|---|---|---|
| Real-time thread blocking (audio glitches) | 🔴 High | Enforce with code review: only `AsyncStream.continuation.yield()` in tap callback; instrument with `os_signpost` |
| WhisperKit model download UX (800MB) | 🟡 Medium | Default to `base` model (~145MB); large-v3-turbo is an opt-in upgrade; show download progress |
| Ollama installation dependency | 🟡 Medium | Cloud API key is an equally prominent alternative; "skip for now" always available |
| macOS permission UX friction | 🟡 Medium | Step-by-step first-launch walkthrough with plain-English explanations for each permission |
| Core Audio Tap API instability on macOS 15+ | 🟡 Medium | `RecordingService` behind a protocol; monitor Apple developer forums; have ScreenCaptureKit as fallback |

**Market Risks:**

| Risk | Mitigation |
|---|---|
| Low adoption (product is discovered but not retained) | Target "Show HN" as launch channel — developer-heavy audience will appreciate the stack and spread the word |
| Users bounce due to Ollama setup friction | Cloud API key path removes this blocker entirely; Ollama is optional, not required |
| Recap ships major update before launch | Differentiate on UI polish and contributor-friendliness; Recap's codebase is less maintained |

**Resource Risks (Solo Developer):**

| Risk | Mitigation |
|---|---|
| Core Audio Tap implementation takes longer than expected | Study `insidegui/AudioCap` first — working sample code exists; don't build from scratch |
| WhisperKit integration complexity | Start with file-based (post-recording) transcription; streaming is a v1.1 feature |
| Scope creep during development | Hard freeze: if a feature isn't in Phase 1 list above, it goes to GitHub Issues, not the current sprint |
| Distribution/notarization friction | Set up GitHub Actions pipeline in Week 1, not Week 6 — don't leave it to the end |

## Functional Requirements

### Recording Control

- **FR1:** User can start an audio recording session from any context via the menu bar icon
- **FR2:** User can stop an active recording session from any context via the menu bar icon
- **FR3:** User can see the current application state (idle / recording / processing) via the menu bar icon at all times
- **FR4:** User can see elapsed recording time while a session is active

### Audio Capture

- **FR5:** The system can capture system audio from any active meeting application (Zoom, Google Meet, Microsoft Teams, and others) via per-process audio capture
- **FR6:** The system can simultaneously capture microphone input during a recording session
- **FR7:** The system can combine system audio and microphone input into a single stream for transcription
- **FR8:** The system can detect loss of system audio capture during an active recording and alert the user without interrupting the session
- **FR9:** The system can continue recording in microphone-only mode when system audio capture is unavailable

### Transcription

- **FR10:** The system can transcribe recorded audio to text on-device after a recording session ends
- **FR11:** User can select the Whisper transcription model size used for transcription
- **FR12:** The system can download WhisperKit transcription models on demand with visible progress
- **FR13:** User can see transcription status and progress after a recording session stops

### AI Summarization

- **FR14:** User can configure a cloud LLM API key (OpenAI or Anthropic-compatible) for meeting summarization
- **FR15:** User can configure a local Ollama endpoint for on-device meeting summarization
- **FR16:** The system can generate a structured meeting summary (key decisions, action items, overview) after transcription completes
- **FR17:** The system can operate in transcript-only mode when no LLM is configured, without blocking recording or transcription
- **FR18:** User can view the AI-generated summary for any recorded meeting

### Meeting Library & Search

- **FR19:** User can browse a chronological list of all past meetings with date, duration, and title
- **FR20:** User can open any past meeting to view its full transcript
- **FR21:** User can open any past meeting to view its AI-generated summary
- **FR22:** User can search across all transcripts and summaries by keyword
- **FR23:** User can see which transcript segments match a search query

### Onboarding & Permissions

- **FR24:** New users are guided through granting microphone permission during first launch
- **FR25:** New users are guided through granting screen recording permission during first launch with a plain-language explanation of why it is required
- **FR26:** User can be informed when a required permission is missing and directed to the correct System Settings location to grant it
- **FR27:** User can skip LLM configuration during onboarding and use transcript-only mode without being blocked

### Settings & Configuration

- **FR28:** User can choose their preferred LLM provider (Ollama or cloud API key) in settings
- **FR29:** User can enter, update, and remove their cloud LLM API key in settings
- **FR30:** User can configure the Ollama server endpoint URL in settings
- **FR31:** User can select the WhisperKit model size in settings
- **FR32:** User can configure whether the application launches at login

### Error Handling & Recovery

- **FR33:** The system can detect and surface actionable error messages for common failure modes: Ollama not running, invalid API key, missing permissions, model still downloading
- **FR34:** User can see the capture quality status of a completed recording (full system + mic capture vs microphone-only)
- **FR35:** The system can provide step-by-step recovery instructions specific to the failure detected
- **FR36:** User can view application update availability and install updates from within the app

### Application Lifecycle

- **FR37:** The application runs as a persistent menu bar utility without a Dock icon
- **FR38:** User can open the main meeting history window from the menu bar
- **FR39:** User can quit the application from the menu bar

## Non-Functional Requirements

### Performance

| NFR | Requirement | Rationale |
|---|---|---|
| App launch to record-ready | < 3 seconds from cold launch | Users need to start recording quickly when a meeting begins unexpectedly |
| Post-meeting processing time | ≤ 60 seconds end-to-end (transcription + summary) after recording stops | Users often have back-to-back meetings; notes must be ready between sessions |
| Transcription real-time factor | < 1x (completes faster than audio duration) on any Apple Silicon Mac | Ensures processing always finishes before the user needs the notes |
| Transcription accuracy | ≤ 5% WER on clear English meeting audio | Transcripts must be usable without significant manual correction |
| First transcript available | ≤ 10 seconds after recording stops | Perceived responsiveness; users should not feel the app has frozen |
| Audio capture continuity | Zero perceptible glitches or dropouts during a recording session | Audio dropouts produce gaps in transcripts that cannot be recovered |
| RAM during transcription | < 2 GB total application memory footprint | Compatible with 8GB base M-series MacBooks (most common Apple Silicon config) |
| CPU during active recording | < 15% additional CPU usage on Apple Silicon while recording (before transcription begins) | Battery-safe for all-day meeting use on laptops |

### Security & Privacy

- **NFR-S1:** API keys (OpenAI, Anthropic, etc.) are stored exclusively in the macOS Keychain; never persisted in UserDefaults, plist files, or the SQLite database
- **NFR-S2:** No audio, transcript, or summary data is transmitted to external servers unless the user has explicitly configured and enabled a cloud LLM API key
- **NFR-S3:** Hardened runtime is enabled for all distributed builds; no arbitrary code execution entitlements are granted
- **NFR-S4:** All user data (recordings, transcripts, summaries, database) is stored only in `~/Library/Application Support/meet-notes/`; no data is written outside this directory without user consent
- **NFR-S5:** No usage telemetry, crash analytics, or behavioral data is collected without explicit user opt-in
- **NFR-S6:** The application must clearly communicate to users at all times which LLM path is active (local Ollama vs cloud API) so they understand when data leaves their machine

### Reliability

- **NFR-R1:** ≥ 99% of recording sessions must complete without application crash or forced termination
- **NFR-R2:** Audio recording must not be interrupted by WhisperKit model loading, database write operations, or SwiftUI rendering cycles — these operations run on separate threads/actors
- **NFR-R3:** The real-time audio callback (Core Audio tap) must never perform blocking operations — no async I/O, no actor calls, no database access; only `AsyncStream.continuation.yield()` is permitted
- **NFR-R4:** The application must survive macOS sleep/wake cycles without corrupting recording state or losing captured audio buffers
- **NFR-R5:** WhisperKit model downloads must not block the UI; the app must remain fully interactive during download

### Accessibility

- **NFR-A1:** All interactive controls are fully operable via VoiceOver with meaningful accessibility labels
- **NFR-A2:** All text elements meet WCAG 2.1 AA minimum contrast ratio (4.5:1 for normal text, 3:1 for large text)
- **NFR-A3:** All interactive controls meet the minimum 44×44pt touch target size per macOS HIG
- **NFR-A4:** The application respects macOS system accessibility preferences: Reduce Motion (disable waveform animations), Reduce Transparency (replace blur materials with solid backgrounds), Increase Contrast (boost border and separator visibility), Dynamic Type (scale text with system font size)
- **NFR-A5:** The application is fully operable via keyboard alone; no interaction requires mouse or trackpad

### Integration

- **NFR-I1:** LLM summarization uses the OpenAI-compatible API format — any provider using this format (Ollama, OpenAI, Anthropic, LM Studio, etc.) works without code changes
- **NFR-I2:** Ollama connectivity failures (not running, wrong port, timeout) are detected within 5 seconds and surfaced to the user without blocking other app functions
- **NFR-I3:** All Sparkle update payloads are verified against a Developer ID signature before installation; unsigned updates are rejected
- **NFR-I4:** WhisperKit model downloads are resumable; an interrupted download can continue from the last byte received rather than restarting
