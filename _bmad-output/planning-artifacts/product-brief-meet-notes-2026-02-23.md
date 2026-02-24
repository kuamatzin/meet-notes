---
stepsCompleted: [1, 2, 3, 4, 5, 6]
inputDocuments:
  - _bmad-output/planning-artifacts/research/technical-macos-meeting-recording-transcription-research-2026-02-23.md
date: 2026-02-23
author: Cuamatzin
---

# Product Brief: meet-notes

<!-- Content will be appended sequentially through collaborative workflow steps -->

## Executive Summary

meet-notes is a free, privacy-first macOS application for individual professionals
who attend frequent online meetings. It captures, transcribes, and summarizes
meetings entirely on-device — no subscriptions, no cloud audio uploads, no
recurring costs. Users can leverage their own LLM API keys for AI summaries, or
run Ollama locally for a completely free and fully local experience from recording
to final notes.

---

## Core Vision

### Problem Statement

Individual professionals attending multiple online meetings daily struggle to
retain decisions, action items, and context. Existing transcription tools
(Otter.ai, Fireflies, Granola) solve the technical problem but introduce new
ones: recurring subscription fees of $10–30/month and cloud servers that receive
sensitive meeting audio.

### Problem Impact

Without accessible meeting notes, professionals:
- Forget decisions and must re-ask colleagues, creating friction
- Scrub through full recordings to find a single moment
- Either pay ongoing fees or accept privacy trade-offs with sensitive conversations

### Why Existing Solutions Fall Short

Every major competitor in this space is subscription-based and cloud-dependent.
There is no serious, free, native macOS option that keeps audio and transcripts
entirely on the user's machine. Open-source projects exist but are too technical
for everyday professionals to adopt.

### Proposed Solution

A native macOS application that:
- Captures system audio + microphone from any meeting platform (Zoom, Meet, Teams)
- Transcribes entirely on-device using WhisperKit on Apple Silicon
- Generates AI meeting summaries via user-supplied API key (OpenAI, Anthropic, etc.)
  OR via local Ollama — making the full pipeline free and offline-capable
- Stores all recordings, transcripts, and notes locally in SQLite

### Key Differentiators

1. **Always free** — no subscription, no tiers, no paywalls, ever
2. **Full privacy by default** — audio never leaves the machine
3. **Native macOS performance** — Swift 6, Core Audio Taps, WhisperKit for
   best-in-class speed and battery efficiency
4. **User sovereignty** — bring your own API key or run Ollama for 100% local AI

---

## Target Users

### Primary Users

**The Meeting-Heavy Professional**

A broad but well-defined archetype: software engineers, product managers,
consultants, designers, and freelancers who spend 1–10 hours per day in online
meetings. They work across any platform — Zoom, Google Meet, Microsoft Teams —
and their meeting load makes manual note-taking unsustainable.

**Profile:**
- Role: Knowledge worker — any function, any industry
- Environment: Remote or hybrid, macOS as primary work machine
- Meeting load: 1–10 meetings/day across multiple platforms
- Goal: Be able to recall decisions, action items, and context from past meetings
  without relying on memory or expensive subscriptions

**Problem Experience:**
Currently managing with one of three frustrating approaches:
- Manual notes during meetings (splits attention, often incomplete)
- Pure memory (reliable for hours, fails after days)
- Paid tools like Otter.ai or Fireflies ($10–30/month) — a recurring cost they
  resent for something that should be a utility

**What Success Looks Like:**
"I can look back at any meeting from the past month and immediately know what
was decided, what I committed to, and what was said — without paying for it
or worrying that my meeting audio is stored on someone else's server."

### Secondary Users

N/A — meet-notes v1.0 targets individual professionals only.

### User Journey

**Discovery:**
Finds meet-notes via GitHub, Product Hunt, or word of mouth in developer and
professional communities. The "always free" and "runs locally" messaging resonates
immediately — no sign-up required, just download and run.

**Onboarding:**
Downloads the notarized DMG, installs, and grants screen recording + microphone
permissions. meet-notes appears in the menu bar — minimal footprint, no dock
icon. Takes under 2 minutes to be ready to record.

**Core Usage:**
Joins a meeting on any platform → taps the menu bar icon to start recording →
meeting ends → taps stop → transcript processes locally in under a minute →
AI summary generated via their own API key or Ollama. Returns to find structured
notes ready.

**The "Aha!" Moment:**
Two weeks after first use, they need to recall a specific decision from a past
call. They search their transcript, find the exact moment in seconds, and realize
they'll never need to worry about this again.

**Long-term:**
Recording becomes a passive, automatic habit. meet-notes is always running,
every meeting is captured, and the growing library of searchable transcripts
becomes an invaluable personal knowledge base.

---

## Success Metrics

### User Success Metrics

Users are succeeding when:
- **Reliability**: The app records every meeting without crashes or audio dropouts
- **Useful summaries**: AI-generated summaries capture decisions, action items,
  and key points accurately enough that users don't need to re-read full transcripts
- **Active recall**: Users regularly return to search past meetings and transcripts
  to find specific information
- **Subscription cancellation**: Users cancel or downgrade paid tools (Otter.ai,
  Fireflies) because meet-notes covers their needs for free

**Leading indicators:**
- Daily/weekly active usage (recording at least one meeting per week)
- Transcript search usage (users mining past meetings)
- Positive word-of-mouth ("I told a colleague to switch")

### Business Objectives

As a free, open-source project, success is measured by community health and
adoption rather than revenue:

1. **User adoption**: Growing install base of active users on macOS
2. **Community engagement**: GitHub stars, forks, and contributor participation
3. **Stability reputation**: Known as the most reliable free option in the space
4. **Open-source credibility**: Cited as a reference project for native macOS
   audio/transcription development

### Key Performance Indicators

| KPI | Target (3 months post-launch) |
|-----|-------------------------------|
| GitHub Stars | 500+ |
| Active installs | 200+ |
| Crash-free session rate | ≥ 99% |
| Transcription accuracy (WER) | ≤ 5% on clear audio |
| Onboarding to first recording | < 5 minutes |
| App launch to recording ready | < 3 seconds |
| Community contributors | 5+ |

### Design Quality Standard

Beautiful UI is a core product value — not an afterthought.
meet-notes should be indistinguishable from a premium paid product in terms of
polish, consistency, and attention to detail. The standard is: if someone saw
a screenshot, they would not guess it was free and open-source.

- Follows macOS Human Interface Guidelines strictly
- Consistent typography, spacing, and iconography
- Smooth animations and transitions native to macOS
- Light and dark mode support from day one

---

## MVP Scope

### Core Features

The MVP delivers the complete core loop: record → transcribe → summarize → review.
All four stages are required for the product to deliver its core value promise.

**1. Menu Bar Application**
- Persistent menu bar icon — minimal footprint, no dock entry
- One-click start/stop recording from any context
- Status indicator (idle / recording / processing)
- Light and dark mode support

**2. Audio Capture**
- System audio capture from any meeting platform (Zoom, Google Meet, Teams, etc.)
  via Core Audio Taps API
- Simultaneous microphone input via AVAudioEngine
- Mixed audio stream for complete meeting capture

**3. Local Transcription**
- On-device transcription via WhisperKit (Apple Silicon only)
- Default model: base (~145MB) with upgrade option to large-v3-turbo in settings
- No audio ever sent to external servers

**4. AI Meeting Summary**
- Post-meeting summary generation with:
  - **Option A**: User's own API key (OpenAI, Anthropic, or compatible)
  - **Option B**: Local Ollama instance — 100% free and offline
- Summary includes: key decisions, action items, and meeting overview
- Both options available from day one — user chooses in settings

**5. Meeting History**
- Browsable list of all past meetings (date, duration, title)
- Full transcript view per meeting
- AI summary view per meeting
- Basic search across transcripts and summaries

**6. Settings & Onboarding**
- First-launch permissions walkthrough (microphone + screen recording)
- Settings panel: API key configuration, Ollama endpoint, Whisper model selection
- Graceful error states (Ollama not running, invalid API key, etc.)

### Out of Scope for MVP

The following are explicitly deferred to post-v1:

| Feature | Rationale |
|---------|-----------|
| Speaker diarization (who said what) | Requires additional ML models; adds complexity without blocking core value |
| Calendar integration / auto-start | Convenient but not essential for v1 adoption |
| Export integrations (Notion, Obsidian) | Valuable, but manual copy is acceptable for MVP |
| Real-time word-by-word transcript display | WhisperKit streaming API not yet stable |
| Custom vocabulary / domain hints | Enhancement for power users post-launch |
| Action item extraction to task managers | Integration complexity; summary covers this need initially |
| Sharing / collaboration features | v1 is individual-only by design |
| Windows / Linux support | Out of scope — macOS native is the product identity |

### MVP Success Criteria

The MVP is considered successful and ready to scale when:
- Zero critical bugs: 99%+ crash-free session rate in the first 30 days
- Core loop works end-to-end reliably on any meeting platform
- Onboarding to first completed recording: < 5 minutes
- Transcription available within 60 seconds of meeting end
- 200+ active users within 3 months of public launch
- GitHub community engagement: 500+ stars, first external contributions received

### Future Vision

If meet-notes succeeds, it evolves into the definitive macOS meeting intelligence
tool:

- **v1.1 – Power UX**: Real-time transcript display, calendar auto-start,
  export to Markdown / Notion / Obsidian
- **v1.2 – Intelligence**: Speaker diarization, action item extraction,
  custom vocabulary hints for specialized domains
- **v2.0 – Ecosystem**: Plugin system for export integrations, team sharing
  (optional, privacy-preserving), mobile companion for review on the go
- **Long term**: Becomes the go-to open-source reference for on-device macOS
  audio intelligence — the privacy-first alternative the market is missing
