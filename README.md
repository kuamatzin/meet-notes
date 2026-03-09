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

## CI/CD

Every PR runs CI (build + test + SwiftLint). Every merge to `main` triggers a full release: archive, sign, notarize, DMG, GitHub Release, and Sparkle appcast update.

**Branch Protection (Required):** Configure in GitHub **Settings > Branches > Branch protection rules** for `main`: require the "CI / build-and-test" status check to pass before merging.

### Required GitHub Secrets

Configure these in **Settings > Secrets and variables > Actions**:

| Secret | Description |
|---|---|
| `BUILD_CERTIFICATE_BASE64` | Developer ID Application certificate (.p12) exported as base64 |
| `P12_PASSWORD` | Password for the .p12 file |
| `KEYCHAIN_PASSWORD` | Any random password for the temporary CI keychain |
| `ASC_KEY_ID` | App Store Connect API key ID (for notarization) |
| `ASC_ISSUER_ID` | App Store Connect issuer UUID (for notarization) |
| `ASC_PRIVATE_KEY` | App Store Connect API private key (.p8 content) |
| `SPARKLE_PRIVATE_KEY` | Sparkle EdDSA private key (for signing auto-updates) |

### Sparkle Key Setup (One-Time)

1. Build the project once so Sparkle's SPM tools are available
2. Run `generate_keys` from Sparkle's build artifacts to create an EdDSA key pair
3. Copy the **public key** into `MeetNotes/MeetNotes/MeetNotes/Info.plist` as `SUPublicEDKey`
4. Export the **private key** and store it as the `SPARKLE_PRIVATE_KEY` GitHub secret

### Encoding the Certificate

```bash
base64 -i DeveloperIDApplication.p12 | pbcopy
```

Paste the clipboard contents as the `BUILD_CERTIFICATE_BASE64` secret.

## Contributing

See `_bmad-output/` for planning artifacts, epics, and implementation stories.
Sprint status: `_bmad-output/implementation-artifacts/sprint-status.yaml`
