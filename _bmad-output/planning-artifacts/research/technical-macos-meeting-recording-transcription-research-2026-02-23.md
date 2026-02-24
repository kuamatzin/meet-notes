---
stepsCompleted: [1, 2, 3, 4, 5, 6]
inputDocuments: []
workflowType: 'research'
lastStep: 1
research_type: 'technical'
research_topic: 'macOS Native Meeting Recording and Transcription App'
research_goals: 'Determine the best approach to build a macOS native app that captures system audio + microphone from any meeting app (Zoom, Google Meet, Teams), transcribes locally using Whisper or other AI models, and produces meeting transcripts and notes — covering audio capture, transcription engine, and app framework options'
user_name: 'Cuamatzin'
date: '2026-02-23'
web_research_enabled: true
source_verification: true
---

# Research Report: technical

**Date:** 2026-02-23
**Author:** Cuamatzin
**Research Type:** technical

---

## Research Overview

This document presents comprehensive technical research into the design and implementation of a **privacy-first, macOS-native meeting recorder and transcriber** — a local-first desktop application capable of capturing audio from any meeting platform (Zoom, Google Meet, Microsoft Teams, and others) and transcribing it entirely on-device using modern Apple Silicon inference.

The research covers five technical domains: technology stack selection (languages, frameworks, transcription engines), integration patterns (audio pipeline design, permission model, LLM summarization), system architecture (MVVM + Swift Actors, menu bar app structure, data layer), implementation guidance (reference implementations, CI/CD, testing strategy), and strategic recommendations (final stack decision, phased roadmap, risk mitigation).

**Key finding**: The macOS ecosystem in 2025-2026 provides a mature, native-first path for this application. Apple's Core Audio Taps API (macOS 14.2+) eliminates the need for virtual audio drivers. WhisperKit delivers ~1% word error rate transcription faster than real-time on any Apple Silicon Mac. OllamaKit enables one-call local LLM summarization. The recommended stack — Swift 6 + SwiftUI + Core Audio Taps + WhisperKit + GRDB + OllamaKit — is production-proven by open-source projects including Recap and Meetily. See the Executive Summary below for the full strategic overview.

---

---

# Building a Privacy-First macOS Meeting Recorder: Comprehensive Technical Research

## Executive Summary

The market for AI-powered meeting transcription is experiencing rapid growth — the broader U.S. transcription market is valued at $30.42 billion in 2024, projected to reach $41.93 billion by 2030. Within this market, a critical gap exists: **73% of businesses cite privacy concerns as a key factor in transcription adoption**, yet most commercial solutions (Otter.ai, Fireflies, Granola) upload audio to the cloud. This creates a clear opportunity for a privacy-first, fully local macOS meeting recorder — the same thesis that drives Meetily (#1 open-source AI meeting assistant) and Recap.

The macOS platform in 2025-2026 is uniquely well-suited for this application. Three converging technical developments make it possible to build a high-quality, fully local solution: (1) Apple's **Core Audio Taps API** (macOS 14.2+) enables driver-free per-application audio capture with no user setup beyond a permission grant; (2) **WhisperKit** delivers OpenAI Whisper-quality transcription (~1% WER) directly on Apple Silicon via CoreML, faster than real-time on any M1+ Mac; and (3) **Ollama** with **OllamaKit** makes local LLM summarization (Gemma3n, LLaMA3, Mistral) trivially integrable via a single Swift async call. Every piece of the puzzle is available, open-source, and actively maintained.

**Key Technical Findings:**

- **Audio capture**: Core Audio Taps (macOS 14.2+) is the definitive approach — per-process audio capture, no BlackHole, no virtual drivers. `insidegui/AudioCap` provides working sample code. Combine with `AVAudioEngine` for microphone.
- **Transcription**: WhisperKit (`large-v3-turbo`) achieves ~1% WER at faster-than-real-time speeds on M1+. Parakeet MLX is 20x faster but has 12% WER — too inaccurate for professional meetings.
- **Architecture**: Swift 6 + SwiftUI (MVVM + @Observable) + Swift Actors (one per service: recording, transcription, summarization) + GRDB.swift (SQLite/WAL). AsyncStream is the safe bridge between the real-time audio thread and Swift concurrency.
- **Summarization**: OllamaKit + local Ollama instance. Fully private, zero cloud dependency. OpenAI-compatible API format enables optional Claude/GPT fallback via the same interface.
- **Distribution**: Outside Mac App Store (no sandbox) + notarized DMG + GitHub Actions CI/CD + Sparkle for auto-updates.

**Technical Recommendations:**

1. **Start by cloning and running [Recap](https://github.com/RecapAI/Recap)** — it uses the identical stack and confirms the technical approach works end-to-end.
2. **Set macOS 14.2 as the deployment target** — this is required for Core Audio Taps and covers ~80%+ of active Macs.
3. **Default to WhisperKit `base` model** (~145MB) on first launch, offer `large-v3-turbo` upgrade in settings.
4. **Do not sandbox the app** — Core Audio Tap + screen recording entitlements conflict with App Sandbox.
5. **Treat Intel Mac support as out of scope for v1.0** — WhisperKit requires Apple Silicon. Communicate this clearly.

_Sources: [Sonix meeting transcription statistics 2026](https://sonix.ai/resources/meeting-transcription-adoption-statistics/), [DEV.to: why we built self-hosted meeting notes](https://dev.to/zackriya/we-built-a-self-hosted-ai-meeting-note-taker-because-every-cloud-solution-failed-our-privacy-1eml), [Meetily](https://meetily.zackriya.com/)_

---

## Table of Contents

1. Technical Research Introduction and Methodology
2. Technical Research Scope Confirmation
3. Technology Stack Analysis
4. Integration Patterns Analysis
5. Architectural Patterns and Design
6. Implementation Approaches and Technology Adoption
7. Technical Research Recommendations
8. Future Technical Outlook
9. Technical Conclusion

---

## 1. Technical Research Introduction and Methodology

### Research Significance

Privacy-first AI meeting transcription is a fast-growing segment driven by enterprise compliance requirements (GDPR, HIPAA), increasing data sensitivity awareness, and the maturation of on-device inference on Apple Silicon. The macOS platform hosts a disproportionate share of enterprise knowledge workers — developers, managers, designers — who conduct dozens of meetings per week. A native macOS tool that requires zero cloud connectivity is both technically feasible in 2026 and commercially underserved.

From a technical standpoint, this research is timely because three foundational APIs reached production maturity in 2023-2024: Core Audio Taps (macOS 14.2, Dec 2023), WhisperKit (v1.0, Argmax, 2024), and Ollama's OpenAI-compatible API (2024). Before these, building a fully local meeting recorder required virtual audio drivers (BlackHole), Python runtimes, or proprietary Rust binaries. Today, the entire stack is native Swift with SPM dependencies.

### Methodology

- **Scope**: All major technical components — audio capture, transcription engine, app framework, data layer, summarization, CI/CD — researched comprehensively.
- **Sources**: Apple Developer Documentation, GitHub repositories (WhisperKit, Recap, AudioCap, GRDB, OllamaKit), academic papers (WhisperKit on-device ASR paper), benchmark sites, developer blogs (Argmax, sotto.to, voicci.com), and community forums (Hacker News, Swift Forums).
- **Web verification**: All factual claims (performance benchmarks, API availability, version requirements) verified against current (2025-2026) sources.
- **Reference implementations studied**: Recap, Meetily, Azayaka, AudioCap, BetterCapture.

### Research Goals Achieved

**Original goals**: Determine the best approach for system audio + microphone capture, transcription engine selection, and overall app architecture for a macOS native meeting recorder.

**Achieved**:
- Audio capture: Core Audio Taps definitively selected (per-app, no drivers, macOS 14.2+) ✅
- Transcription: WhisperKit `large-v3-turbo` selected (1% WER, faster than real-time on M1+) ✅
- Framework: Swift 6 + SwiftUI selected (macOS-native, direct API access, best performance) ✅
- Architecture: MVVM + @Observable + Swift Actors + AsyncStream bridge pattern documented ✅
- Summarization: OllamaKit + local Ollama, with optional cloud fallback ✅
- CI/CD, testing, distribution: GitHub Actions + notarytool + Sparkle ✅

---

## Technical Research Scope Confirmation

**Research Topic:** macOS Native Meeting Recording and Transcription App
**Research Goals:** Determine the best approach to build a macOS native app that captures system audio + microphone from any meeting app (Zoom, Google Meet, Teams), transcribes locally using Whisper or other AI models, and produces meeting transcripts and notes — covering audio capture, transcription engine, and app framework options

**Technical Research Scope:**

- Architecture Analysis - design patterns, frameworks, system architecture
- Implementation Approaches - development methodologies, coding patterns
- Technology Stack - languages, frameworks, tools, platforms
- Integration Patterns - APIs, protocols, interoperability
- Performance Considerations - scalability, optimization, patterns

**Research Methodology:**

- Current web data with rigorous source verification
- Multi-source validation for critical technical claims
- Confidence level framework for uncertain information
- Comprehensive technical coverage with architecture-specific insights

**Scope Confirmed:** 2026-02-23

<!-- Content will be appended sequentially through research workflow steps -->

## Technology Stack Analysis

### Programming Languages

For a macOS-native meeting recorder, the language choice directly determines which Apple APIs are accessible.

**Primary Languages:**
- **Swift** — The recommended primary language. First-class access to all Apple frameworks (Core Audio, ScreenCaptureKit, AVFoundation, CoreML). Swift 5.9+ with structured concurrency (async/await) handles real-time audio pipelines elegantly. Used by Recap, Azayaka, BetterCapture.
- **Objective-C** — Still required for some low-level Core Audio bridging; interoperates seamlessly with Swift.
- **C/C++** — Needed if embedding whisper.cpp directly (via Swift Package Manager or bridging headers).
- **Rust** — Alternative backend if using Tauri framework; can call native macOS APIs via Swift interop plugins.
- **Python** — Viable for prototyping transcription pipelines (faster-whisper, mlx-whisper), but not suitable for a shipped native app due to runtime overhead.

_Recommendation: Swift as primary language. macOS-only scope removes any need for cross-platform compromise._
_Source: [Recap GitHub](https://github.com/RecapAI/Recap), [BetterCapture GitHub](https://github.com/jsattler/BetterCapture)_

### Development Frameworks and Libraries

**UI Framework:**
- **SwiftUI** — Native declarative UI, first-class on macOS 13+. Best performance, smallest footprint, native look and feel.
- **AppKit** — Lower-level, still needed for some menu bar/system-level UI not yet in SwiftUI.
- **Electron** — NOT recommended: bundles full Chromium (100MB+), heavy memory use, limited audio API access. Audio capture via `desktopCapturer` lacks Core Audio Taps support. _(Source: [Electron vs Tauri — DoltHub](https://www.dolthub.com/blog/2025-11-13-electron-vs-tauri/))_
- **Tauri** — Valid if cross-platform is a future goal. Rust backend with Swift plugin interop. ~10MB app size, low idle memory (~30-40MB). The reference project Meetily uses Tauri. _(Source: [Tauri 2.0 vs Electron — Medium](https://medium.com/@sevenall/tauri-2-0-released-can-it-beat-electron-this-time-c748663d90ea))_

**Audio Frameworks:**
- **Core Audio Taps API** (macOS 14.2+) — **Best approach for audio-only capture.** Captures per-process audio (e.g. only Zoom, only Teams) without virtual audio drivers. No BlackHole needed. Used by Recap. _(Source: [Apple Developer Docs](https://developer.apple.com/documentation/CoreAudio/capturing-system-audio-with-core-audio-taps), [AudioCap sample](https://github.com/insidegui/AudioCap))_
- **ScreenCaptureKit** (macOS 13+) — Captures system-wide audio + screen. Better for screen recording use cases. Has known issues on macOS 15 (SCStreamErrorDomain -3805). _(Source: [Apple WWDC24](https://developer.apple.com/videos/play/wwdc2024/10088/))_
- **AVFoundation** — For microphone capture and audio file I/O.

**Transcription Libraries:**
- **WhisperKit** — Swift-native Whisper implementation using CoreML. Designed for Apple Silicon. First-class Swift API. Used directly by Recap. Best integration story for a Swift app.
- **whisper.cpp** — C/C++ port of Whisper. Fastest inference, CoreML + Apple Neural Engine support, 2-3x speedup on Apple Silicon. Callable from Swift via bridging. _(Source: [Whisper.cpp on Apple Silicon — sotto.to](https://sotto.to/blog/whisper-cpp-apple-silicon))_
- **Parakeet MLX** — NVIDIA Parakeet model via Apple's MLX framework. Extremely fast (2s for 7:31 min audio on M2 Pro) but lower accuracy (WER 12%). Best for speed-critical scenarios where accuracy can be traded. _(Source: [9to5Mac Parakeet vs Whisper](https://9to5mac.com/2025/07/03/how-accurate-is-apples-new-transcription-ai-we-tested-it-against-whisper-and-parakeet/))_
- **Apple Native Transcription** (new macOS Speech framework) — Fast (9s for 7:31 min), 8% WER. No external model download needed. Limited control over model version.

_Source: [mac-whisper-speedtest benchmarks](https://github.com/anvanvan/mac-whisper-speedtest), [MLX vs faster-whisper comparison — Medium](https://medium.com/@GenerationAI/streaming-with-whisper-in-mlx-vs-faster-whisper-vs-insanely-fast-whisper-37cebcfc4d27)_

### Database and Storage Technologies

- **SQLite** (via GRDB Swift library) — Ideal for storing transcripts, meeting metadata, speaker segments. Lightweight, zero-config, embedded.
- **Core Data** — Apple's ORM over SQLite. More boilerplate but tighter SwiftUI integration.
- **Local file system** — Audio recordings stored as WAV/M4A files. Transcripts as JSON or plain text alongside.
- **UserDefaults / plist** — App preferences and settings.

No cloud database required for a privacy-first local app.

### Development Tools and Platforms

- **Xcode** — Required for Swift/SwiftUI development, code signing, and App Store distribution.
- **Swift Package Manager (SPM)** — Dependency management. WhisperKit, GRDB, and most Swift libraries support SPM.
- **Instruments** — Profiling audio capture latency, CoreML inference time, battery impact.
- **TestFlight** — Beta distribution if targeting Mac App Store.
- **Notarization** — Required for distribution outside App Store; Apple Silicon entitlements needed for microphone + screen recording permissions.

### Transcription Engine Performance Benchmarks

Tested on M2 Pro MacBook Pro, 7:31 minute audio file:

| Engine | Time | Word Error Rate | Notes |
|---|---|---|---|
| Parakeet MLX | 2s | 12% | Fastest, least accurate |
| Apple Native STT | 9s | 8% | No model download, limited control |
| Whisper Large V3 Turbo | 40s | 1% | Most accurate, still faster than real-time |
| whisper.cpp + CoreML | ~1.2s/10s chunk | ~1-2% | Best real-time option |

**For real-time meeting transcription**: whisper.cpp or WhisperKit with `large-v3-turbo` + CoreML acceleration is the recommended balance — faster than real-time on any Apple Silicon Mac, with ~1% WER.

_Source: [Voicci Apple Silicon Whisper Benchmarks](https://www.voicci.com/blog/apple-silicon-whisper-performance.html), [DEV.to M4 Whisper Analysis](https://dev.to/theinsyeds/whisper-speech-recognition-on-mac-m4-performance-analysis-and-benchmarks-2dlp)_

### Technology Adoption Trends

- **Core Audio Taps replacing BlackHole**: Since macOS 14.2 (Dec 2023), developers no longer need virtual audio drivers. This is a significant shift — new projects should use Core Audio Taps exclusively.
- **WhisperKit gaining momentum**: Swift-native Whisper is emerging as the standard for macOS/iOS apps, replacing Python-based pipelines.
- **MLX framework growing**: Apple's MLX enables running models like Parakeet directly on Apple Silicon via unified memory — no CUDA required.
- **Local-first AI**: The market is moving strongly toward on-device processing. Privacy regulations and user preference drive this. Meetily, Recap, and others all run 100% locally.
- **Tauri 2.0 adoption**: Released Oct 2024, adds iOS/Android support. Viable cross-platform alternative to Electron for teams with Rust expertise.

_Source: [Apple Core Audio Taps docs](https://developer.apple.com/documentation/CoreAudio/capturing-system-audio-with-core-audio-taps), [Recap AI GitHub](https://github.com/RecapAI/Recap)_

## Integration Patterns Analysis

### Audio Capture Pipeline

The core integration challenge is stitching together three audio sources (system audio from the meeting app, microphone) into a single PCM stream that Whisper can consume.

**Recommended Pipeline:**

```
[Meeting App Process]
        ↓ Core Audio Tap (per-process capture)
[AVAudioEngine Graph]
        ↓ installTap(onBus:bufferSize:format:block:)
[PCM Buffer Queue] — Float32, 16kHz mono (Whisper format)
        ↓ AsyncStream<AVAudioPCMBuffer>
[Chunk Accumulator] — 30s window (Whisper's native context)
        ↓
[WhisperKit / whisper.cpp]
        ↓ Streaming transcription segments
[Transcript Store] — SQLite via GRDB
        ↓
[Ollama / Claude API]
        ↓ Meeting summary + action items
[UI — SwiftUI]
```

**Buffer Size**: Install tap with ~4096 frames at 16kHz = ~256ms per callback. Accumulate into 5-30 second chunks before sending to WhisperKit.

**Audio format conversion**: Core Audio Tap delivers audio at the system sample rate (typically 44.1kHz or 48kHz stereo). Must downsample to 16kHz mono Float32 before passing to Whisper. Use `AVAudioConverter` for this.

_Source: [AVAudioEngine Streaming — Haris Ali](https://www.syedharisali.com/articles/streaming-audio-with-avaudioengine/), [WhisperKit GitHub](https://github.com/argmaxinc/WhisperKit)_

### WhisperKit Streaming Integration

WhisperKit (by Argmax) is architected specifically for streaming inference:
- The **Audio Encoder** natively supports incremental audio input.
- The **Text Decoder** yields transcript segments on partial audio — no need to wait for silence.
- Integration via Swift Package Manager: `https://github.com/argmaxinc/WhisperKit`
- CLI streaming test: `swift run whisperkit-cli transcribe --model large-v3 --stream`
- Supports async/await + AsyncStream output for Swift concurrency.

_Source: [WhisperKit on-device ASR paper](https://arxiv.org/html/2507.10860v1), [Transloadit WhisperKit guide](https://transloadit.com/devtips/transcribe-audio-on-ios-macos-whisperkit/)_

### macOS Permissions and Entitlements

Four permissions are required. Each must be declared in entitlements + Info.plist:

| Permission | Entitlement Key | Info.plist Key | When Triggered |
|---|---|---|---|
| Microphone | `com.apple.security.device.audio-input` | `NSMicrophoneUsageDescription` | First mic access |
| Screen Recording | `com.apple.security.screen-recording` | `NSScreenCaptureUsageDescription` | If using ScreenCaptureKit |
| Core Audio Tap | Requires Screen Recording permission | — | Per-process audio capture |
| Local network (Ollama) | `com.apple.security.network.client` | — | Ollama API calls |

**macOS 15 note**: Apple tweaked screen recording permission frequency in macOS 15.1 — popups are less frequent but the initial grant is still required. Core Audio Tap for audio-only (no screen) still triggers the screen recording TCC prompt.

_Source: [Apple Audio Input Entitlement](https://developer.apple.com/documentation/BundleResources/Entitlements/com.apple.security.device.audio-input), [Apple Media Capture Authorization](https://developer.apple.com/documentation/avfoundation/requesting-authorization-to-capture-and-save-media)_

### Ollama / LLM Summarization Integration

After transcription, the plain text transcript is sent to a local LLM for summarization.

**OllamaKit** — Swift-native Ollama client (SPM: `https://github.com/kevinhermawan/OllamaKit`):
- Simple async/await API: `OllamaKit().chat(data: chatData)`
- Ollama now supports OpenAI-compatible API format: POST `http://localhost:11434/v1/chat/completions`
- Compatible models for meeting summarization: **Gemma 3n**, **LLaMA 3.1**, **Mistral 7B**

**Optional multi-provider support**: `swift_llm_bridge` supports Ollama, LM Studio, Claude, and OpenAI from a single interface — good if you want to offer both local and cloud AI options.

**Summarization prompt pattern** (from Meetily reference):
```
Summarize the following meeting transcript. Extract:
1. Key decisions made
2. Action items with owners
3. Topics discussed
Transcript: {transcript_text}
```

_Source: [OllamaKit Swift](https://github.com/kevinhermawan/OllamaKit), [Meetily Ollama integration — DEV.to](https://dev.to/zackriya/local-meeting-notes-with-whisper-transcription-ollama-summaries-gemma3n-llama-mistral--2i3n), [swift_llm_bridge](https://github.com/bipark/swift_llm_bridge)_

### Data Formats

| Stage | Format | Notes |
|---|---|---|
| Raw audio capture | PCM Float32, 16kHz mono | Whisper requirement |
| Audio storage (optional) | M4A / WAV | Compressed for storage |
| Transcript segments | JSON `{start, end, text, confidence}` | Per segment |
| Full transcript | Plain text / Markdown | For LLM input |
| Meeting summary | Markdown | Rendered in SwiftUI |
| App database | SQLite (GRDB) | Meetings, segments, summaries |

### Integration Security Patterns

Since the app is fully local, traditional API security (OAuth, JWT) is not required. Security focus areas:

- **Entitlements hardened runtime**: Required for notarization. Prevents running arbitrary code.
- **Sandbox mode**: Consider whether to sandbox (limits file access but required for App Store). Menu bar apps often distributed outside App Store to avoid sandbox restrictions.
- **No data exfiltration**: If Ollama is local, no data leaves the machine. If cloud LLM is optional, make it explicit to the user with an opt-in toggle.
- **Keychain**: Store any API keys (optional Claude/OpenAI) in macOS Keychain, never in UserDefaults.

## Architectural Patterns and Design

### System Architecture Pattern

**Recommended: MVVM + Swift Actors + @Observable (2025 standard)**

In 2025, the Apple community has converged on a pragmatic architecture: `@Observable` view models (MVVM) for UI state, Swift Actors for concurrent services, and AsyncStream as the glue between callback-based Apple APIs and structured concurrency. TCA (The Composable Architecture) is powerful but introduces significant complexity — appropriate only if the team is already familiar with it or the app grows to enterprise scale.

**High-level component diagram:**

```
┌──────────────────────────────────────────────────────────────┐
│                        SwiftUI Layer                         │
│   MenuBarExtra | TranscriptView | SummaryView | Settings     │
│   (@Observable ViewModels — live updates from DB/actors)     │
└────────────────────────┬─────────────────────────────────────┘
                         │ @Observable ViewModels
┌────────────────────────▼─────────────────────────────────────┐
│                   Domain Services (Swift Actors)              │
│   RecordingService | TranscriptionService | SummaryService   │
│   (thread-safe, async/await, isolated state)                 │
└───────┬──────────────────┬─────────────────────┬────────────┘
        │                  │                     │
┌───────▼──────┐   ┌───────▼────────┐   ┌───────▼──────────┐
│ Core Audio   │   │  WhisperKit    │   │  OllamaKit /     │
│ Tap Layer    │   │  (CoreML/ANE)  │   │  Claude API      │
│ AVAudioEngine│   │                │   │  (local-first)   │
└──────────────┘   └────────────────┘   └──────────────────┘
                           │
                    ┌──────▼────────────┐
                    │  GRDB SQLite      │
                    │  (DatabasePool,   │
                    │   WAL mode)       │
                    └───────────────────┘
```

_Source: [Architecture Playbook iOS 2025 — Medium](https://medium.com/@mrhotfix/the-architecture-playbook-for-ios-2025-swiftui-concurrency-modular-design-a35b98cbf688), [TCA vs MVVM — Medium](https://medium.com/@chathurikabandara0701/tca-vs-mvvm-in-swiftui-which-architecture-should-you-choose-f4cd21315329)_

### Menu Bar App Architecture

This app is best structured as a **menu bar utility** (no Dock icon, always-on background):

- **`MenuBarExtra` scene** (SwiftUI, macOS 13+): Native API for menu bar icon + popover/window. Simple, declarative.
- **`NSApplication.shared.setActivationPolicy(.accessory)`**: Keeps the process running in background without a Dock icon.
- **`@NSApplicationDelegateAdaptor`**: Bridges SwiftUI App lifecycle to AppKit's `NSApplicationDelegate` for app startup, termination, and background task management.
- **Two UI surfaces**:
  1. Menu bar popover — quick status, start/stop recording, current session time.
  2. Main window (optional) — full transcript view, history, settings. Opened on demand.

_Source: [Build macOS menu bar utility in SwiftUI — nilcoalescing.com](https://nilcoalescing.com/blog/BuildAMacOSMenuBarUtilityInSwiftUI/), [Menu bar app architecture — Kyan](https://kyan.com/insights/using-swift-swiftui-to-build-a-modern-macos-menu-bar-app)_

### Real-Time Audio Pipeline Architecture

The core challenge is safely moving data from a **real-time audio thread** (which cannot block) through **structured concurrency** (Swift actors) to the transcription engine.

**Pattern: AsyncStream as Real-Time Bridge**

```swift
// Core Audio Tap callback → AsyncStream (non-blocking bridge)
let (audioStream, continuation) = AsyncStream<AVAudioPCMBuffer>.makeStream()

audioEngine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
    continuation.yield(buffer)  // non-blocking, never call async from here
}

// TranscriptionActor consumes from AsyncStream
actor TranscriptionService {
    func process(stream: AsyncStream<AVAudioPCMBuffer>) async {
        for await buffer in stream {
            let converted = resample(buffer, to: 16000)  // AVAudioConverter
            let segments = await whisperKit.transcribe(converted)
            await database.saveSegments(segments)
        }
    }
}
```

**Critical rule**: Never call async functions, database I/O, or network requests inside the Core Audio tap callback. The callback runs on a real-time thread — blocking it causes audio glitches. `AsyncStream.continuation.yield()` is the only safe cross-boundary call.

_Source: [AsyncStream + Actor patterns — Medium](https://medium.com/@mrhotfix/advanced-swift-concurrency-combining-asyncstream-actor-async-let-in-real-time-swiftui-apps-b2bd5d123d6e), [Swift Forums: Actors and Audio Units](https://forums.swift.org/t/concurrency-actors-and-audio-units/42664), [Real-time voice AI pipeline design — Gladia](https://www.gladia.io/blog/concurrent-pipelines-for-voice-ai)_

### Data Architecture Patterns

**GRDB.swift** (v7.10.0, Feb 2026) is the recommended data layer:

- `DatabasePool` with WAL mode: concurrent reads while writes happen (non-blocking UI reads).
- Short-lived value types (`struct Meeting`, `struct TranscriptSegment`) — no living objects that mutate behind your back.
- `ValueObservation`: observes database changes and publishes to SwiftUI via `@Query` or Combine.
- Single source of truth: the database. ViewModels read from GRDB, not in-memory caches.

**Schema sketch:**

```sql
CREATE TABLE meetings (id, title, started_at, ended_at, duration_seconds, summary_md);
CREATE TABLE segments (id, meeting_id, start_time, end_time, text, confidence);
CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT);
```

_Source: [GRDB.swift GitHub](https://github.com/groue/GRDB.swift), [Local-first architecture with SwiftData — Medium](https://medium.com/@gauravharkhani01/designing-efficient-local-first-architectures-with-swiftdata-cc74048526f2)_

### Scalability and Performance Patterns

- **CoreML / Apple Neural Engine**: WhisperKit automatically dispatches model inference to the ANE. No explicit thread management needed — the framework handles it.
- **Chunk size tuning**: Start with 5-second chunks for real-time feel. Longer chunks (15-30s) produce more accurate transcription. Expose as a user setting.
- **Background Task API**: Use `BGProcessingTask` or `ProcessInfo.performExpiringActivity` if the app needs to finish transcription after screen lock.
- **Memory management**: Audio buffers are large. Process and release immediately — do not accumulate unbounded. Use a bounded `AsyncChannel` or backpressure on the stream if WhisperKit falls behind.

### Deployment and Distribution Architecture

- **Outside Mac App Store** (recommended): Avoids sandbox restrictions that conflict with Core Audio Tap + screen recording entitlements. Distribute as a signed + notarized `.dmg`.
- **Hardened Runtime**: Required for notarization. Must explicitly enable `audio-input` and `screen-recording` entitlements.
- **Auto-updates**: [Sparkle framework](https://sparkle-project.org/) is the standard for non-App Store macOS auto-updates.
- **App bundle size**: Model files (Whisper large-v3-turbo) are ~800MB. Use on-demand download at first launch, not bundled in the `.dmg`.

### Design Principles

- **Local-first**: All data on device. Network is optional (Ollama is local; cloud LLM is opt-in).
- **Privacy by default**: No telemetry, no analytics without explicit opt-in. Align with GDPR/CCPA for future expansion.
- **Fail gracefully**: If WhisperKit is loading a model or Ollama is not running, the app degrades gracefully — records audio and queues transcription for when the model is ready.
- **Single responsibility per Actor**: `RecordingService` knows nothing about transcription. `TranscriptionService` knows nothing about the UI. Clean separation enables independent testing.

## Implementation Approaches and Technology Adoption

### Technology Adoption Strategy

**Recommended: Study-first, then build incrementally.**

Two open-source projects serve as the primary reference implementations:

| Project | Stack | Audio Capture | Transcription | Summarization | Study Priority |
|---|---|---|---|---|---|
| **[Recap](https://github.com/RecapAI/Recap)** | Swift/SwiftUI | Core Audio Taps | WhisperKit | Ollama | ⭐ Highest — identical stack |
| **[Meetily](https://meetily.zackriya.com/)** | Tauri/Rust | ScreenCaptureKit | whisper.cpp | Ollama | Good for architecture reference |
| **[AudioCap](https://github.com/insidegui/AudioCap)** | Swift | Core Audio Tap | — | — | Audio capture code reference |
| **[Azayaka](https://github.com/Mnpn/Azayaka)** | Swift | ScreenCaptureKit | — | — | ScreenCaptureKit patterns |

Start by cloning Recap and running it locally before writing a single line of code.

_Source: [Recap GitHub](https://github.com/RecapAI/Recap), [Meetily](https://meetily.zackriya.com/)_

### WhisperKit Integration — Concrete Steps

**Requirements**: macOS 14.0+, Xcode 15.0+, Apple Silicon (Intel Macs are NOT supported for WhisperKit inference).

**Step 1 — Add SPM dependency:**
```swift
// Package.swift or via Xcode: File > Add Package Dependencies
.package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0")
```

**Step 2 — Initialize and download model:**
```swift
let config = WhisperKitConfig(model: "openai_whisper-large-v3-turbo")
let whisperKit = try await WhisperKit(config)
// Model downloads (~800MB) on first run to ~/Library/Application Support/
```

**Step 3 — Transcribe (file-based or streaming):**
```swift
// File-based (post-recording)
let results = try await whisperKit.transcribe(audioPath: recordingURL.path)

// Streaming (real-time) — via CLI flag --stream, API in active development
```

**Model size vs accuracy tradeoff:**

| Model | Size | WER | Speed (M2) | Recommended for |
|---|---|---|---|---|
| `tiny` | ~75MB | ~8% | Very fast | Testing / low-end |
| `base` | ~145MB | ~5% | Fast | Quick demos |
| `large-v3-turbo` | ~800MB | ~1% | Faster than real-time | Production |

_Source: [WhisperKit GitHub](https://github.com/argmaxinc/WhisperKit), [WhisperKit Transloadit guide](https://transloadit.com/devtips/transcribe-audio-on-ios-macos-whisperkit/)_

### Development Workflow and Tooling

- **Xcode 16.3+** — Required for Swift 6.1+ and latest WhisperKit.
- **Swift Package Manager** — All dependencies (WhisperKit, GRDB, OllamaKit, Sparkle) available via SPM. No CocoaPods or Carthage needed.
- **SwiftLint** — Enforce code style. Add as an SPM plugin.
- **Swift Testing** (Apple's new framework, 2024) — Run alongside XCTest. More expressive API. Use for new tests; migrate XCTest gradually.

_Source: [Swift Testing — Apple Developer](https://developer.apple.com/xcode/swift-testing)_

### Testing and Quality Assurance

**AVAudioEngine testing challenge**: AVAudioEngine requires real hardware and cannot be easily mocked. Strategy:

1. **Protocol-based dependency injection** for `AudioCaptureService`:
   ```swift
   protocol AudioCaptureServiceProtocol {
       var audioStream: AsyncStream<AVAudioPCMBuffer> { get }
       func start() async throws
       func stop()
   }
   // Real implementation: Core Audio Tap
   // Mock: yields synthetic PCM buffers from test audio files
   ```

2. **Integration tests** for WhisperKit: test with short (5-10s) known audio fixtures. Assert word error rate on known content.

3. **Unit tests** for: transcript segment parsing, GRDB queries, Ollama response parsing, audio format conversion math.

4. **UI tests** (XCUITest): test recording start/stop flow, transcript display, history navigation.

### Deployment and CI/CD

**GitHub Actions pipeline** (notarization flow):

```yaml
# .github/workflows/release.yml
jobs:
  build-and-notarize:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Build
        run: xcodebuild -scheme MeetNotes -configuration Release archive
      - name: Sign
        run: # Import cert from GitHub Secret (base64-encoded p12)
      - name: Notarize
        run: xcrun notarytool submit app.dmg --apple-id ${{ secrets.APPLE_ID }}
            --team-id ${{ secrets.TEAM_ID }} --password ${{ secrets.APP_PASSWORD }} --wait
      - name: Upload DMG
        uses: actions/upload-artifact@v4
```

_Source: [Automatic notarization GitHub Actions — Federico Terzi](https://federicoterzi.com/blog/automatic-code-signing-and-notarization-for-macos-apps-using-github-actions/), [macOS signing GitHub Actions — Localazy](https://localazy.com/blog/how-to-automatically-sign-macos-apps-using-github-actions)_

### Team Organization and Skills Required

For a solo developer or small team:

| Skill | Required Level | Learning Resources |
|---|---|---|
| Swift + Swift Concurrency | Intermediate-Advanced | Swift by Sundell, Hacking with Swift |
| SwiftUI (macOS) | Intermediate | Kodeco macOS by Tutorials |
| Core Audio (basics) | Basic — copy AudioCap | insidegui/AudioCap sample |
| GRDB.swift | Basic | GRDB documentation + guides |
| Xcode + signing | Basic | GitHub Actions workflows above |
| OllamaKit | Trivial | README — it's 5 lines of code |

### Risk Assessment and Mitigation

| Risk | Severity | Mitigation |
|---|---|---|
| Intel Mac exclusion (WhisperKit) | Medium | Offer Apple Speech framework as fallback for Intel; be clear in marketing |
| macOS 14.2+ floor (Core Audio Tap) | Low | ~80%+ of active Macs already on 14+; acceptable |
| Whisper model download UX (800MB) | Medium | Offer tiny/base models first, upgrade in-app; show progress bar |
| Ollama installation dependency | Medium | Bundle a lightweight llama.cpp binary as an alternative; or cloud fallback |
| macOS 15 ScreenCaptureKit bug (-3805) | None | Using Core Audio Tap only avoids this entirely |
| Real-time thread blocking (audio glitches) | High | Strict code review: no async/IO in tap callback; enforce with linter rule |

## Technical Research Recommendations

### Implementation Roadmap

**Phase 1 — Foundation (Weeks 1-2)**
1. Xcode project setup, configure entitlements (microphone + screen recording)
2. Implement Core Audio Tap audio capture (study `insidegui/AudioCap`)
3. Audio format conversion: system rate → 16kHz mono Float32 via `AVAudioConverter`
4. Microphone capture via AVAudioEngine, mix with system audio
5. WhisperKit integration (SPM), test with pre-recorded audio files

**Phase 2 — Real-Time Pipeline (Weeks 2-3)**
6. AsyncStream bridge: Core Audio tap callback → Swift concurrency
7. Streaming transcription with WhisperKit
8. GRDB data layer: `Meeting`, `TranscriptSegment` models + `DatabasePool`
9. SwiftUI: `MenuBarExtra` menu, live transcript window

**Phase 3 — Summarization + Polish (Weeks 3-5)**
10. OllamaKit integration: post-meeting summary generation
11. Model selection settings (tiny/base/large-v3-turbo)
12. Meeting history view, transcript export (Markdown, plain text)
13. Audio device selector (handle multiple input devices)

**Phase 4 — Distribution (Week 5-6)**
14. Code signing + notarization (GitHub Actions)
15. Sparkle auto-update framework
16. Beta testing (direct DMG distribution)

### Technology Stack Recommendations

**Final recommended stack:**

| Layer | Technology | Rationale |
|---|---|---|
| Language | Swift 6 | Native macOS, best API access |
| UI | SwiftUI + MenuBarExtra | Modern, native, macOS 13+ |
| System Audio | Core Audio Tap (macOS 14.2+) | No virtual drivers, per-app capture |
| Microphone | AVAudioEngine | Standard, well-documented |
| Transcription | WhisperKit (large-v3-turbo) | Swift-native, 1% WER, CoreML/ANE |
| Data | GRDB.swift + SQLite | Reliable, fast, actively maintained |
| Summarization | OllamaKit (local) | Privacy-first, Gemma3n/LLaMA3/Mistral |
| Cloud LLM (opt-in) | swift_llm_bridge | Unified interface for Claude/OpenAI |
| Updates | Sparkle | Non-App Store standard |
| CI/CD | GitHub Actions + notarytool | Standard macOS distribution pipeline |

### Success Metrics

- **Transcription accuracy**: Target < 5% WER on typical meeting audio (English)
- **Real-time factor**: Transcription must complete faster than audio is recorded (< 1x real-time)
- **Latency**: First transcript segment visible within 10 seconds of speaking
- **Memory**: < 2GB RAM during active transcription (model + buffers)
- **Battery**: < 15% additional CPU impact on Apple Silicon during meeting
- **First-run setup**: User goes from DMG install to first transcription in < 5 minutes (including Ollama setup or model download)

---

## Future Technical Outlook

### Near-Term (2026)

- **Apple's native Speech framework improving**: Apple's new transcription API (tested at 8% WER, 9s for 7:31 min audio in 2025) will improve rapidly. In 1-2 years, it may match Whisper accuracy while being zero-download and system-managed. Design the `TranscriptionService` actor behind a protocol to make swapping engines trivial.
- **WhisperKit streaming API stabilizing**: The streaming transcription API is in active development (currently best accessed via CLI `--stream`). The Swift API will stabilize in 2026, enabling true word-by-word real-time display.
- **MLX framework growing**: Apple's MLX will enable running more models (speaker diarization, language identification) directly on Apple Silicon. Speaker labeling ("Speaker A:", "Speaker B:") is the most requested missing feature — expect MLX-based diarization libraries to emerge.

### Medium-Term (2027-2028)

- **On-device speaker diarization**: Currently the hardest unsolved problem in local meeting transcription. Who said what? Models like pyannote-audio are too large for real-time local use today, but will become feasible on M3/M4 class hardware.
- **visionOS expansion**: Meeting transcription on Apple Vision Pro (spatial computing) is a natural extension — the same Core Audio Tap + WhisperKit stack runs on visionOS.
- **macOS 15+ system-level integration**: Apple may expose meeting context APIs (knowing Zoom is in a call) via ScreenCaptureKit or new APIs, enabling smarter per-session recording without user interaction.

### Innovation Opportunities for This Project

- **Speaker diarization** — differentiate from competitors by labeling who said what.
- **Real-time vocabulary hints** — let users add custom vocabulary (product names, acronyms) that bias Whisper's beam search.
- **Action item detection** — fine-tune a small local model to extract tasks from transcript text in real-time.
- **Calendar integration** — auto-title recordings by calendar event name, attach transcripts to calendar events.

---

## Technical Conclusion

### Summary of Key Findings

Building a privacy-first macOS meeting recorder in 2026 is technically straightforward with the right stack. The three historically hard problems — system audio capture, accurate local transcription, and local LLM summarization — are all solved by production-ready, open-source Swift libraries:

| Problem | Solution | Status |
|---|---|---|
| System audio capture (no drivers) | Core Audio Taps + AVAudioEngine | Production-ready (macOS 14.2+) |
| Accurate local transcription | WhisperKit large-v3-turbo | Production-ready (~1% WER) |
| Real-time pipeline (no blocking) | AsyncStream + Swift Actors | Best practice (Swift 6) |
| Local LLM summarization | OllamaKit + Ollama | Production-ready |
| Data persistence | GRDB.swift + SQLite | Production-ready (v7.10, Feb 2026) |
| Distribution | Notarized DMG + GitHub Actions | Standard practice |

### Strategic Impact Assessment

The recommended stack closely mirrors **Recap** ([github.com/RecapAI/Recap](https://github.com/RecapAI/Recap)), which proves the technical approach works. The primary differentiators for a new project would be: polished UI, speaker diarization, broader model support, and a better first-run experience (model download UX).

The privacy angle is a genuine market differentiator. With 73% of enterprises citing privacy as a barrier to cloud transcription adoption, a high-quality local-first tool addresses a real pain point.

### Next Steps

1. **Clone and run Recap** to validate the full stack end-to-end on your machine.
2. **Study `insidegui/AudioCap`** for Core Audio Tap implementation patterns.
3. **Proceed to Create Product Brief** (`/bmad-bmm-create-product-brief`) to define your unique angle vs. existing tools.
4. **Then Create PRD** (`/bmad-bmm-create-prd`) — this research feeds directly into the technical constraints and architecture sections.

---

**Technical Research Completion Date:** 2026-02-23
**Research Period:** Comprehensive current technical analysis (2024-2026 sources)
**Source Verification:** All technical facts verified against current public sources
**Technical Confidence Level:** High — based on multiple authoritative sources and production reference implementations

_This document serves as the authoritative technical reference for the meet-notes project and provides the foundation for PRD, architecture, and implementation planning._
