# Story 2.3: Missing Permission Recovery & Guidance

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a user whose permissions were denied or revoked,
I want the app to detect missing permissions, show me a clear explanation of what is missing, and give me a single-tap path to the correct System Settings location to fix it,
So that I never get silently stuck and can recover without needing to search for solutions.

## Acceptance Criteria

1. **Given** microphone permission is denied when the user attempts to start a recording, **when** `PermissionService` detects the denied state, **then** an inline banner is shown: "Microphone access required. [Open System Settings →]" — no modal dialog (FR26), **and** tapping the link opens System Settings → Privacy & Security → Microphone directly.

2. **Given** screen recording permission is denied when the user attempts to start a recording, **when** `PermissionService` detects the denied state, **then** an inline banner is shown: "Screen Recording permission is required to capture audio from meeting apps. [Open System Settings →]" (FR26), **and** tapping the link opens System Settings → Privacy & Security → Screen Recording directly.

3. **Given** a permission is revoked while the app is running, **when** `PermissionService` detects the revocation, **then** the relevant inline banner appears immediately without crashing or silently continuing.

4. **Given** the main window empty state is shown when permissions are missing, **when** the user sees it, **then** the CTA reads "Set Up meet-notes" instead of "Start Recording".

5. **Given** both permissions are granted after following recovery instructions, **when** the app regains focus, **then** the warning banners disappear and the app returns to normal state without requiring a restart.

## Tasks / Subtasks

- [x] **Task 1: Expand `AppError` enum with permission cases and banner metadata** (AC: #1, #2)
  - [x] Open `App/AppError.swift` (currently empty enum)
  - [x] Add cases: `.microphonePermissionDenied`, `.screenRecordingPermissionDenied`
  - [x] Add computed property `bannerMessage: String` returning the user-facing banner text per AC
  - [x] Add computed property `recoveryLabel: String` returning "Open System Settings →"
  - [x] Add computed property `sfSymbol: String` returning the appropriate icon name
  - [x] Add computed property `systemSettingsURL: URL?` returning the deep-link URL for the relevant System Settings pane
  - [x] Conform to `Equatable` and `Sendable`

- [x] **Task 2: Enhance `AppErrorState` with `post()` and `clear()` methods** (AC: #1, #2, #3)
  - [x] Open `App/AppErrorState.swift` (currently has only `var current: AppError?`)
  - [x] Add `func post(_ error: AppError)` that sets `current = error`
  - [x] Add `func clear()` that sets `current = nil`

- [x] **Task 3: Add `openMicrophoneSettings()` to `PermissionService` and protocol** (AC: #1)
  - [x] Add `func openMicrophoneSettings()` to `PermissionService` — opens `x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone` via `NSWorkspace.shared.open()`
  - [x] Add `func openMicrophoneSettings()` to `PermissionChecking` protocol
  - [x] Update `MockPermissionService` in `PermissionServiceTests.swift` — add `openMicrophoneSettingsCalled: Bool` tracking property and protocol conformance

- [x] **Task 4: Create `ErrorBannerView` reusable component** (AC: #1, #2, #3)
  - [x] Create `ErrorBannerView.swift` in `UI/Components/`
  - [x] Pure display component — takes `icon: String`, `message: String`, `recoveryLabel: String`, `recoveryAction: () -> Void`, optional `dismissAction: (() -> Void)?`
  - [x] Render as horizontal card: SF Symbol icon + message text + recovery CTA button
  - [x] Use `Color.warningAmber` for icon tint, `Color.cardBg` background, `Color.cardBorder` border
  - [x] 12pt corner radius, 12pt horizontal padding, 10pt vertical padding
  - [x] Recovery CTA styled as `.accent` text button with `chevron.right` trailing icon
  - [x] Accessible: `.accessibilityElement(children: .combine)`, `.accessibilityLabel` combining message + recovery label
  - [x] Guard all animations with `@Environment(\.accessibilityReduceMotion)`
  - [x] **CRITICAL: Zero ViewModel dependencies.** This component takes all data via parameters. It does NOT read `AppErrorState` or any other type from `@Environment`. This keeps `UI/Components/` dependency-free per architecture rules.

- [x] **Task 5: Update `MainWindowView` with permission banners and state-dependent CTA** (AC: #1, #2, #3, #4, #5)
  - [x] Add `@Environment(PermissionService.self) private var permissionService`
  - [x] Add `@Environment(AppErrorState.self) private var appErrorState`
  - [x] Add `@Environment(\.accessibilityReduceMotion) private var reduceMotion`
  - [x] Compute `var allPermissionsGranted: Bool` from `permissionService.microphoneStatus.isGranted && permissionService.screenRecordingStatus.isGranted`
  - [x] Add `VStack` at top of content for stacking multiple banners
  - [x] Show microphone `ErrorBannerView` when `!permissionService.microphoneStatus.isGranted` — message: "Microphone access required.", recovery calls `permissionService.openMicrophoneSettings()`
  - [x] Show screen recording `ErrorBannerView` when `!permissionService.screenRecordingStatus.isGranted` — message: "Screen Recording permission is required to capture audio from meeting apps.", recovery calls `permissionService.requestScreenRecording()`
  - [x] Show one-shot `ErrorBannerView` when `appErrorState.current != nil` with dismiss action calling `appErrorState.clear()`
  - [x] Replace static "Welcome to meet-notes" with empty state that shows "Set Up meet-notes" CTA when `!allPermissionsGranted`, "Start Recording" when `allPermissionsGranted`
  - [x] CTA is a `Button` with `.accent` fill, `.headline` weight, 44pt min height, 10pt corner radius (same pattern as onboarding)
  - [x] "Set Up meet-notes" CTA opens System Settings for the first missing permission
  - [x] "Start Recording" CTA is a no-op placeholder (RecordingService doesn't exist yet — Epic 3)
  - [x] Banners auto-disappear reactively: `PermissionService` is `@Observable`, so when permissions are granted and `refreshStatus()` fires on `didBecomeActiveNotification`, the views re-render and banners vanish (AC #5)
  - [x] Extract `PermissionBannersView` and `EmptyStateView` as named subviews to keep body nesting ≤ 3 levels

- [x] **Task 6: Add permission status indicator to `MenuBarPopoverView`** (AC: #1, #2, #3)
  - [x] Add `@Environment(PermissionService.self) private var permissionService`
  - [x] When any permission is denied, show a brief warning row above "Open meet-notes": SF Symbol `exclamationmark.triangle.fill` in `.warningAmber` + "Permissions needed" text
  - [x] Tapping the warning row opens the main window (`openWindow(id: "Meetings")`) where full banners are visible

- [x] **Task 7: Write unit tests** (AC: all)
  - [x] Create `MeetNotesTests/App/AppErrorTests.swift`
  - [x] Test: `microphonePermissionDenied` has correct `bannerMessage`
  - [x] Test: `screenRecordingPermissionDenied` has correct `bannerMessage`
  - [x] Test: `microphonePermissionDenied` has correct `recoveryLabel` ("Open System Settings →")
  - [x] Test: `screenRecordingPermissionDenied` has correct `recoveryLabel`
  - [x] Test: `microphonePermissionDenied` has correct `sfSymbol`
  - [x] Test: `screenRecordingPermissionDenied` has correct `sfSymbol`
  - [x] Test: `systemSettingsURL` returns valid URL for each case
  - [x] Create `MeetNotesTests/App/AppErrorStateTests.swift`
  - [x] Test: initial `current` is `nil`
  - [x] Test: `post()` sets `current` to the given error
  - [x] Test: `clear()` sets `current` to `nil`
  - [x] Test: `post()` replaces previous error
  - [x] All tests use Swift Testing (`@Test`, `#expect`) — no XCTest

- [x] **Task 8: Verify build and all tests pass** (AC: all)
  - [x] Build with zero warnings under `SWIFT_STRICT_CONCURRENCY = complete`
  - [x] Run full test suite — no regressions in existing tests (AppDatabase, SecretsStore, PermissionService, OnboardingViewModel)
  - [x] Verify zero actor isolation warnings

## Dev Notes

### Technical Requirements

**Permission Banner Reactivity Pattern:**

Permission banners are driven **reactively** by `PermissionService` (which is `@Observable`), NOT by one-shot `AppErrorState` posts. This is critical because:
1. Permission errors are **persistent** — they last until the user grants access
2. **Multiple** permission errors can be active simultaneously (both mic + screen denied)
3. They **auto-clear** when `PermissionService.refreshStatus()` fires on `didBecomeActiveNotification`

`AppErrorState` is for **one-shot transient errors** from services (e.g., recording failed, model download failed). It holds a single `current: AppError?`. Permission banners bypass `AppErrorState` and read `PermissionService` state directly in the view.

```swift
// MainWindowView observes PermissionService reactively — NOT through AppErrorState
@Environment(PermissionService.self) private var permissionService

// Permission banners appear/disappear automatically via @Observable reactivity:
if !permissionService.microphoneStatus.isGranted {
    ErrorBannerView(
        icon: "mic.slash.fill",
        message: "Microphone access required.",
        recoveryLabel: "Open System Settings →",
        recoveryAction: { permissionService.openMicrophoneSettings() }
    )
}
```

**ErrorBannerView is a PURE display component:**

```swift
// CORRECT — pure component, zero dependencies, lives in UI/Components/
struct ErrorBannerView: View {
    let icon: String
    let message: String
    let recoveryLabel: String
    let recoveryAction: () -> Void
    var dismissAction: (() -> Void)? = nil
}

// WRONG — reading AppErrorState makes it non-reusable and breaks Components/ dependency-free rule
struct ErrorBannerView: View {
    @Environment(AppErrorState.self) private var appErrorState  // ← DO NOT DO THIS
}
```

The architecture file tree comment says `ErrorBannerView` "reads AppErrorState" — this was high-level guidance. In practice, making it a pure component is architecturally superior because:
- It stays dependency-free in `UI/Components/` per the project rule
- It can render both permission banners (from `PermissionService`) and transient errors (from `AppErrorState`)
- The parent view orchestrates which banners to show

**System Settings Deep-Link URLs:**

```swift
// Microphone:
"x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"

// Screen Recording (already in PermissionService.requestScreenRecording()):
"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
```

These URLs open the correct System Settings pane directly on macOS 14+.

**`AppError` Design:**

```swift
enum AppError: LocalizedError, Equatable, Sendable {
    case microphonePermissionDenied
    case screenRecordingPermissionDenied

    var bannerMessage: String {
        switch self {
        case .microphonePermissionDenied:
            "Microphone access required."
        case .screenRecordingPermissionDenied:
            "Screen Recording permission is required to capture audio from meeting apps."
        }
    }

    var recoveryLabel: String { "Open System Settings →" }

    var sfSymbol: String {
        switch self {
        case .microphonePermissionDenied: "mic.slash.fill"
        case .screenRecordingPermissionDenied: "rectangle.inset.filled.and.person.filled"
        }
    }

    var systemSettingsURL: URL? {
        switch self {
        case .microphonePermissionDenied:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .screenRecordingPermissionDenied:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        }
    }
}
```

Future stories will add more cases (`audioTapLost`, `modelNotDownloaded`, `ollamaNotRunning`, `invalidAPIKey`). Do NOT add them now — only add what this story needs.

**`AppErrorState` Enhancement:**

```swift
@Observable @MainActor final class AppErrorState {
    var current: AppError? = nil

    func post(_ error: AppError) { current = error }
    func clear() { current = nil }
}
```

This matches the architecture document exactly. The `post()` / `clear()` methods are the canonical API for one-shot errors from services.

**Main Window Empty State:**

```swift
// When permissions are missing:
VStack(spacing: 16) {
    Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 48))
        .foregroundStyle(Color.warningAmber)
    Text("Permissions Required")
        .font(.title2).fontWeight(.semibold)
    Text("meet-notes needs microphone and screen recording access to capture your meetings.")
        .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
    Button("Set Up meet-notes") { openFirstMissingPermissionSettings() }
        // .accent fill, .headline weight, 44pt min height, 10pt corner radius
}

// When all permissions are granted:
VStack(spacing: 16) {
    Image(systemName: "mic.fill")
        .font(.system(size: 48))
        .foregroundStyle(Color.accent)
    Text("Ready to Record")
        .font(.title2).fontWeight(.semibold)
    Text("Click the menu bar icon or press ⌘⇧R to start recording.")
        .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
    Button("Start Recording") { /* no-op placeholder — RecordingService ships in Epic 3 */ }
        // .accent fill, .headline weight, 44pt min height, 10pt corner radius
}
```

**Auto-Dismiss Mechanism (AC #5):**

`PermissionService` already monitors `NSApplication.didBecomeActiveNotification` and calls `refreshStatus()` when the app regains focus. Since `PermissionService` is `@Observable`, when `microphoneStatus` or `screenRecordingStatus` changes from `.denied` to `.authorized`, SwiftUI automatically re-evaluates the `if !...isGranted` conditions and removes the banners. **No additional code needed for auto-dismiss.**

**Permission Revocation Detection (AC #3):**

`PermissionService` already logs warnings on revocation in `checkMicrophoneStatus()` and `checkScreenRecordingStatus()`. The revocation updates the `@Observable` properties, which triggers SwiftUI re-renders. The banners will appear immediately. **No additional code needed for revocation detection.**

### Architecture Compliance

**Mandatory patterns from architecture document:**

- **`AppError` type:** `enum AppError: LocalizedError` in `App/AppError.swift` — per architecture file tree. Exhaustive enum, all user-facing error cases. [Source: architecture.md#AppError — Single Exhaustive Enum]
- **`AppErrorState` type:** `@Observable @MainActor final class AppErrorState` — per architecture decision. [Source: architecture.md#Decision: Error Propagation]
- **`ErrorBannerView` location:** `UI/Components/ErrorBannerView.swift` — per architecture file tree. [Source: architecture.md#Complete File Tree]
- **Three-layer error rule:** Service → ViewModel → View. For this story, permission errors are reactive (not thrown), so the View reads `PermissionService` state directly. `AppErrorState` + `ErrorBannerView` infrastructure is laid down for future stories where the three-layer rule fully applies.
- **No Combine:** Zero `import Combine` anywhere.
- **No `@StateObject` / `@ObservedObject`:** Views use `@Environment(SomeType.self)`.
- **Design tokens only:** `Color.warningAmber`, `Color.cardBg`, `Color.cardBorder`, `Color.accent`, `Color.windowBg` — no hardcoded color literals.
- **Accessibility:** Every animation guarded by `@Environment(\.accessibilityReduceMotion)`. Banner accessible labels combining message + recovery action.
- **View nesting depth ≤ 3:** Extract `PermissionBannersView`, `EmptyStateView` as named subviews.
- **`UI/Components/` is dependency-free:** `ErrorBannerView` takes all data via parameters — zero `@Environment` usage of app-specific types.
- **Logger at file scope:** `Logger(subsystem: "com.kuamatzin.meet-notes", category: "ExactTypeName")` for any new types that need logging (none expected — views don't log).
- **No `print()`:** Use `Logger` exclusively.

### Library & Framework Requirements

| Library | Import | Purpose | Notes |
|---|---|---|---|
| SwiftUI | `import SwiftUI` | All views, `@Environment`, button styling | System framework |
| Observation | `import Observation` | `@Observable` on `AppErrorState` | System framework (already imported) |
| AppKit | `import AppKit` | `NSWorkspace.shared.open()` for System Settings deep links | Only in `PermissionService.swift` (already imported there) |

**No external SPM dependencies needed for this story.** All APIs are system frameworks.

**Do NOT import:**
- `Combine` — prohibited
- `AVFoundation` — not needed (permission APIs accessed through `PermissionService`)
- `CoreGraphics` — not needed directly
- `Foundation` — only if needed for `URL` construction in `AppError.swift`

### File Structure Requirements

**New files to create:**

| File | Location | Type | Description |
|---|---|---|---|
| `ErrorBannerView.swift` | `MeetNotes/MeetNotes/MeetNotes/UI/Components/` | SwiftUI View | Pure inline banner component: icon + message + recovery CTA |
| `AppErrorTests.swift` | `MeetNotes/MeetNotes/MeetNotesTests/App/` | Swift Testing tests | Tests for `AppError` enum computed properties |
| `AppErrorStateTests.swift` | `MeetNotes/MeetNotes/MeetNotesTests/App/` | Swift Testing tests | Tests for `AppErrorState` post/clear |

**Files to modify:**

| File | Change |
|---|---|
| `MeetNotes/MeetNotes/MeetNotes/App/AppError.swift` | Add permission cases + computed properties (currently empty enum) |
| `MeetNotes/MeetNotes/MeetNotes/App/AppErrorState.swift` | Add `post()` and `clear()` methods |
| `MeetNotes/MeetNotes/MeetNotes/Infrastructure/Permissions/PermissionService.swift` | Add `openMicrophoneSettings()` method |
| `MeetNotes/MeetNotes/MeetNotes/Infrastructure/Permissions/PermissionStatus.swift` | Add `openMicrophoneSettings()` to `PermissionChecking` protocol |
| `MeetNotes/MeetNotes/MeetNotes/UI/MainWindow/MainWindowView.swift` | Add permission banners, error banners, and state-dependent empty state CTA |
| `MeetNotes/MeetNotes/MeetNotes/UI/MenuBar/MenuBarPopoverView.swift` | Add permission warning indicator row |
| `MeetNotes/MeetNotes/MeetNotesTests/Infrastructure/PermissionServiceTests.swift` | Update `MockPermissionService` with `openMicrophoneSettings()` |

**Directory creation:**

- `MeetNotes/MeetNotes/MeetNotesTests/App/` — **new directory**, must be created. Xcode `PBXFileSystemSynchronizedRootGroup` auto-discovers new files.

**Xcode auto-discovery:** `PBXFileSystemSynchronizedRootGroup` in Xcode 16+ auto-discovers new Swift files in existing directories. No manual `project.pbxproj` editing required (confirmed in Stories 1.2, 1.3, 2.1, and 2.2).

### Testing Requirements

**Framework:** Swift Testing (`@Test`, `#expect`) — per project-context.md. Do NOT use XCTest.

**Test File 1:** `MeetNotesTests/App/AppErrorTests.swift`

| # | Test | Validates |
|---|---|---|
| 1 | `microphonePermissionDenied.bannerMessage` contains "Microphone access required" | AC #1 banner text |
| 2 | `screenRecordingPermissionDenied.bannerMessage` contains "Screen Recording permission" | AC #2 banner text |
| 3 | Both cases return `recoveryLabel` "Open System Settings →" | AC #1, #2 recovery CTA |
| 4 | `microphonePermissionDenied.sfSymbol` is `"mic.slash.fill"` | Icon correctness |
| 5 | `screenRecordingPermissionDenied.sfSymbol` is `"rectangle.inset.filled.and.person.filled"` | Icon correctness |
| 6 | `systemSettingsURL` returns non-nil URL for each case | Deep link validity |
| 7 | `AppError` conforms to `Equatable` | Required for comparisons |

**Test File 2:** `MeetNotesTests/App/AppErrorStateTests.swift`

| # | Test | Validates |
|---|---|---|
| 1 | Initial `current` is `nil` | Default state |
| 2 | `post(.microphonePermissionDenied)` sets `current` correctly | Post mechanism |
| 3 | `clear()` sets `current` to `nil` | Clear mechanism |
| 4 | Second `post()` replaces previous error | Single-error behavior |

**Mock updates:**

- `MockPermissionService` in `PermissionServiceTests.swift` — add `openMicrophoneSettingsCalled: Bool` and `func openMicrophoneSettings()` to conform to updated protocol.

**No UI tests in this story.** `ErrorBannerView` is a pure component tested through its parent's integration. Isolated view snapshot tests are deferred.

**Existing test patterns to follow:**
- `PermissionServiceTests.swift` — Swift Testing with `@Test`, `#expect`, `@MainActor` functions, `MockPermissionService`
- `OnboardingViewModelTests.swift` — async tests, mock injection, UserDefaults cleanup
- Test file naming: `{TypeName}Tests.swift`

### Previous Story Intelligence

**From Story 2.2 (First-Launch Onboarding Wizard) — DIRECT PREDECESSOR:**

1. **`PermissionService` is `@Observable @MainActor final class`** — already injected into all scenes via `.environment(permissionService)` in `MeetNotesApp.swift`. The main window and menu bar can consume it via `@Environment(PermissionService.self)`.

2. **`PermissionChecking` protocol** exists at `Infrastructure/Permissions/PermissionStatus.swift` — defines `microphoneStatus`, `screenRecordingStatus`, `requestMicrophone() async`, `requestScreenRecording()`, `refreshStatus()`. Story 2.3 adds `openMicrophoneSettings()` to this protocol.

3. **`MockPermissionService`** exists in `MeetNotesTests/Infrastructure/PermissionServiceTests.swift` — conforms to `PermissionChecking`, tracks method calls. Must be updated with `openMicrophoneSettings()` when the protocol changes.

4. **`CGPreflightScreenCaptureAccess()` `.notDetermined` limitation** — returns Bool only. First-time users see `screenRecordingStatus == .denied` until they grant. The recovery banners must treat `.denied` as "not yet granted" — show the grant prompt, NOT an error-severity banner. Use `warningAmber` color, NOT `recordingRed`.

5. **`PermissionService.startMonitoring()`** is called in `init()` — monitoring is active from app launch. When the user grants permissions in System Settings and returns to the app, `refreshStatus()` fires automatically via `didBecomeActiveNotification`. The banners disappear reactively. **No manual refresh needed.**

6. **`PermissionService.requestScreenRecording()`** already opens System Settings with the deep link URL. The new `openMicrophoneSettings()` follows the same pattern.

7. **Logger subsystem:** `"com.kuamatzin.meet-notes"` — established pattern.

8. **Test count baseline:** 36 tests currently passing (24 existing + 12 from Story 2.2). This story should add ~11 tests for a new total of ~47.

9. **`@AppStorage("hasCompletedOnboarding")`** controls the onboarding sheet. After onboarding, if the user denied permissions, they arrive at `MainWindowView` — this is exactly when Story 2.3 recovery banners should appear.

10. **`MeetNotesApp.swift` environment injection pattern:** Five `@State` properties injected via `.environment()`. No new state properties needed for Story 2.3 — `PermissionService` and `AppErrorState` are already injected.

### Git Intelligence

**Recent commits (2 total):**
- `a1e7def` — Add Xcode project structure with code review fixes
- `5d57653` — Initial commit: project scaffold, planning artifacts, and Story 1.1 Swift source files

**Established patterns from codebase:**

1. **Environment injection in `MeetNotesApp.swift`:** `permissionService`, `recordingVM`, `appErrorState`, `navigationState` are all `@State` properties injected via `.environment()`. Story 2.3 does NOT add new state properties — it uses existing injected instances.

2. **View pattern:** `MainWindowView` uses `Color.windowBg`, `.frame(minWidth: 800, minHeight: 600)`. `MenuBarPopoverView` uses `Color.cardBg`, 200pt width. Follow these token patterns.

3. **`PermissionService` deep link pattern:** `requestScreenRecording()` uses `NSWorkspace.shared.open(URL)` with `x-apple.systempreferences:...`. The new `openMicrophoneSettings()` follows the identical pattern.

4. **Design tokens:** `Color.warningAmber` (#FF9F0A) is specifically defined for warning states. Use it for error banner icon tint.

5. **No uncommitted Story 2.2 code in git** — Story 2.2 files appear in `git status` as untracked. The dev agent must ensure these files exist on disk before building.

### Latest Tech Information

**macOS System Settings Deep Links (March 2026):**

1. **`x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone`** — opens System Settings → Privacy & Security → Microphone. Works on macOS 13+.

2. **`x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture`** — opens System Settings → Privacy & Security → Screen Recording. Already used in `PermissionService.requestScreenRecording()`.

3. **System Settings app renamed from System Preferences** in macOS 13 Ventura. The `x-apple.systempreferences:` URL scheme still works. The UI calls it "System Settings" (not "System Preferences") — use "System Settings" in all user-facing copy.

4. **`NSWorkspace.shared.open(URL)`** — the standard way to open System Settings from a non-sandboxed macOS app. No special entitlements required. Works with hardened runtime.

5. **`@Observable` + SwiftUI reactive rendering** — when an `@Observable` property changes, all views observing it re-render. This is the mechanism that makes permission banners auto-appear/disappear without manual state management.

### Project Structure Notes

- Aligns with architecture file tree: `UI/Components/ErrorBannerView.swift` listed explicitly
- `ErrorBannerView` is dependency-free (takes parameters, no `@Environment` of app types) — stays in `UI/Components/`
- New test directory: `MeetNotesTests/App/` — follows test mirror structure rule
- Does NOT create or modify any database schemas
- Does NOT add any SPM dependencies
- Does NOT modify Info.plist or entitlements
- Does NOT modify `MeetNotesApp.swift` (all injections already exist)
- Modifies `PermissionService.swift` — adds one new method, does not change existing behavior
- Modifies `PermissionStatus.swift` — adds one method to protocol
- Modifies `MainWindowView.swift` — complete rewrite of body with permission-aware content
- Modifies `MenuBarPopoverView.swift` — adds permission warning row

### References

- Story 2.3 acceptance criteria: [Source: _bmad-output/planning-artifacts/epics.md#Story 2.3]
- FR26 Permission recovery: [Source: _bmad-output/planning-artifacts/prd.md#Onboarding & Permissions]
- FR33 Actionable error messages: [Source: _bmad-output/planning-artifacts/prd.md#Error Handling & Recovery]
- FR35 Step-by-step recovery: [Source: _bmad-output/planning-artifacts/prd.md#Error Handling & Recovery]
- AppError enum architecture: [Source: _bmad-output/planning-artifacts/architecture.md#AppError — Single Exhaustive Enum]
- AppErrorState decision: [Source: _bmad-output/planning-artifacts/architecture.md#Decision: Error Propagation]
- ErrorBannerView file tree: [Source: _bmad-output/planning-artifacts/architecture.md#Complete File Tree — "ErrorBannerView.swift — inline non-blocking banner; single recovery CTA; reads AppErrorState"]
- Three-layer error rule: [Source: _bmad-output/planning-artifacts/architecture.md#Error Handling — The Three-Layer Rule]
- UX error recovery patterns: [Source: _bmad-output/planning-artifacts/ux-design-specification.md#Error Recovery Patterns]
- UX emotional design "Safety in errors": [Source: _bmad-output/planning-artifacts/ux-design-specification.md#Emotional Mapping]
- PermissionService implementation: [Source: _bmad-output/implementation-artifacts/2-2-first-launch-onboarding-wizard.md#Previous Story Intelligence]
- Swift 6 concurrency rules: [Source: _bmad-output/project-context.md#Swift 6 Concurrency Rules]
- SwiftUI rules: [Source: _bmad-output/project-context.md#SwiftUI Rules]
- Design tokens: [Source: MeetNotes/MeetNotes/MeetNotes/UI/Components/Color+DesignTokens.swift]
- PermissionChecking protocol: [Source: MeetNotes/MeetNotes/MeetNotes/Infrastructure/Permissions/PermissionStatus.swift]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6

### Debug Log References

No issues encountered. Build and tests passed on first attempt.

### Completion Notes List

- Implemented `AppError` enum with `.microphonePermissionDenied` and `.screenRecordingPermissionDenied` cases, including computed properties for `bannerMessage`, `recoveryLabel`, `sfSymbol`, and `systemSettingsURL`. Conforms to `Equatable`, `Sendable`, and `LocalizedError`.
- Enhanced `AppErrorState` with `post()` and `clear()` methods for one-shot transient error management.
- Added `openMicrophoneSettings()` to `PermissionService` and `PermissionChecking` protocol, following the existing `requestScreenRecording()` deep-link pattern.
- Created `ErrorBannerView` as a pure display component in `UI/Components/` — zero ViewModel dependencies, takes all data via parameters. Renders horizontal card with SF Symbol, message, and recovery CTA.
- Rewrote `MainWindowView` with permission-reactive banners (driven by `@Observable` `PermissionService`, not `AppErrorState`), transient error banner (driven by `AppErrorState`), and state-dependent empty state CTA ("Set Up meet-notes" vs "Start Recording"). Extracted `PermissionBannersView` and `EmptyStateView` subviews to keep nesting ≤ 3 levels.
- Updated `MenuBarPopoverView` with permission warning indicator row that opens the main window when tapped.
- Added 12 new tests (8 AppError + 4 AppErrorState) using Swift Testing framework. Updated `MockPermissionService` with `openMicrophoneSettings()` conformance.
- All 48 tests passing (36 existing + 12 new), zero regressions, zero warnings.

### File List

**New files:**
- `MeetNotes/MeetNotes/MeetNotes/UI/Components/ErrorBannerView.swift`
- `MeetNotes/MeetNotes/MeetNotesTests/App/AppErrorTests.swift`
- `MeetNotes/MeetNotes/MeetNotesTests/App/AppErrorStateTests.swift`

**Modified files:**
- `MeetNotes/MeetNotes/MeetNotes/App/AppError.swift`
- `MeetNotes/MeetNotes/MeetNotes/App/AppErrorState.swift`
- `MeetNotes/MeetNotes/MeetNotes/Infrastructure/Permissions/PermissionService.swift`
- `MeetNotes/MeetNotes/MeetNotes/Infrastructure/Permissions/PermissionStatus.swift`
- `MeetNotes/MeetNotes/MeetNotes/UI/MainWindow/MainWindowView.swift`
- `MeetNotes/MeetNotes/MeetNotes/UI/MenuBar/MenuBarPopoverView.swift`
- `MeetNotes/MeetNotes/MeetNotesTests/Infrastructure/PermissionServiceTests.swift`

## Senior Developer Review (AI)

**Reviewer:** Cuamatzin | **Date:** 2026-03-04 | **Outcome:** Approved with fixes applied

### Findings Summary
- **0 CRITICAL** | **5 MEDIUM (all fixed)** | **4 LOW (noted)**

### MEDIUM Issues (Fixed)
1. **M1:** Removed unused `reduceMotion` from `ErrorBannerView` — dead `@Environment` property with no animations to guard
2. **M2+M3:** Moved `reduceMotion` into `PermissionBannersView`, added `.transition(.opacity)` on each banner and `.animation(.easeInOut)` guarded by `reduceMotion` — banners now animate smoothly on appear/disappear
3. **M4:** Added missing `openMicrophoneSettingsTracksCall` test to `MockPermissionServiceTests` — every mock method now has corresponding test coverage
4. **M5:** Added `errorDescription` computed property to `AppError` returning `bannerMessage` — `LocalizedError` conformance now meaningful

### LOW Issues (Noted, not fixed)
- L1: `import AppKit` + direct `NSWorkspace.shared.open()` in view layer for transient error recovery — consider routing through service
- L2: `.clipShape(RoundedRectangle(cornerRadius: 10))` on `.borderedProminent` buttons — double corner radius
- L3: Asymmetric API: `openMicrophoneSettings()` exists but no `openScreenRecordingSettings()`
- L4: Transient error banner recovery assumes `systemSettingsURL` exists — future error cases may silently fail CTA

### Files Modified by Review
- `MeetNotes/UI/Components/ErrorBannerView.swift` — removed unused `reduceMotion`
- `MeetNotes/UI/MainWindow/MainWindowView.swift` — moved `reduceMotion` to `PermissionBannersView`, added transitions + animations
- `MeetNotes/App/AppError.swift` — added `errorDescription` computed property
- `MeetNotesTests/Infrastructure/PermissionServiceTests.swift` — added `openMicrophoneSettingsTracksCall` test

## Change Log

- 2026-03-04: Code review passed — 5 MEDIUM issues fixed (dead code, missing transitions, missing test, misleading protocol conformance). 4 LOW noted for future. Status → done.
- 2026-03-04: Implemented Story 2.3 — Missing Permission Recovery & Guidance. Added `AppError` permission cases with banner metadata, `AppErrorState` post/clear API, `openMicrophoneSettings()` deep link, `ErrorBannerView` pure component, permission-reactive banners in `MainWindowView`, permission warning in `MenuBarPopoverView`, and 12 unit tests. Total: 48 tests passing.
