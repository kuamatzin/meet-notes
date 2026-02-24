# meet-notes

A privacy-first macOS meeting recorder and transcriber.

Captures audio from any meeting app (Zoom, Google Meet, Teams), transcribes locally using WhisperKit, and produces AI meeting notes via Ollama — all on-device. No audio leaves your Mac.

## Requirements

- macOS 14.2+
- Apple Silicon (M1 or later)
- Xcode 16.3+
- [Ollama](https://ollama.ai) (for AI summaries — optional)

## Setup

### First-time Setup

1. Clone this repository
2. Open `MeetNotes/MeetNotes.xcodeproj` in Xcode 16.3+
3. Select your development team in **Signing & Capabilities**
4. Build and run (`⌘R`)

The app will appear as a menu bar icon — no Dock icon.

### Permissions

On first launch, grant:
- **Microphone** — for recording your own voice
- **Screen Recording** — required by macOS for system audio capture

### Architecture

See `_bmad-output/planning-artifacts/architecture.md` for the full Architecture Decision Record.

**Quick summary:**
- Swift 6 strict concurrency mode (`SWIFT_STRICT_CONCURRENCY = complete`)
- MVVM + `@Observable` — no Combine, no ObservableObject
- Swift Actors for all services (`RecordingService`, `TranscriptionService`, `SummaryService`)
- GRDB.swift + SQLite (`DatabasePool`, WAL mode) as single source of truth
- WhisperKit for on-device transcription (base model ~145MB by default)
- OllamaKit for local LLM summarization

### Project Structure

```
MeetNotes/MeetNotes/
├── App/                    # @main, AppDelegate, AppError, NavigationState
├── Features/
│   ├── Recording/          # RecordingService, RecordingViewModel, RecordingState
│   ├── Transcription/      # TranscriptionService, WhisperKit integration
│   ├── Summary/            # SummaryService, LLM providers
│   ├── MeetingList/        # Meeting history list UI
│   ├── MeetingDetail/      # Transcript + summary detail view
│   ├── Settings/           # App settings
│   └── Onboarding/         # First-launch onboarding wizard
├── Infrastructure/
│   ├── Database/           # AppDatabase (GRDB), Meeting, TranscriptSegment records
│   ├── Permissions/        # PermissionService
│   ├── Secrets/            # SecretsStore (Keychain)
│   └── Notifications/      # NotificationService
└── UI/
    ├── MenuBar/             # MenuBarPopoverView
    ├── MainWindow/          # MainWindowView
    └── Components/          # Color+DesignTokens, shared reusable views
```

## Contributing

See `_bmad-output/` for planning artifacts, epics, and implementation stories.
Sprint status: `_bmad-output/implementation-artifacts/sprint-status.yaml`
