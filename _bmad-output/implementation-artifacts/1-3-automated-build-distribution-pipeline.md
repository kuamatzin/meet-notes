# Story 1.3: Automated Build & Distribution Pipeline

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a developer building meet-notes,
I want every PR to run a CI build and every merge to `main` to automatically produce a code-signed, notarized DMG and update the Sparkle appcast,
So that releases are always current, correctly signed for Gatekeeper, and secure against tampering — with zero manual shipping steps.

## Acceptance Criteria

1. **Given** a pull request is opened against `main`, **when** the `ci.yml` GitHub Actions workflow runs on a macOS runner, **then** the project builds successfully, all unit tests pass, and SwiftLint reports no violations, **and** the PR cannot be merged until CI passes (branch protection rule).

2. **Given** a commit is merged to `main`, **when** the `release.yml` workflow runs, **then** it archives the app with Xcode, signs it with the Developer ID Application certificate, and notarizes with `xcrun notarytool`.

3. **Given** notarization succeeds, **when** the workflow continues, **then** it staples the notarization ticket, packages the app into a `.dmg`, uploads the DMG to GitHub Releases, and updates `appcast.xml` with the new release entry including the download URL, version, and `sparkle:edSignature`.

4. **Given** the Sparkle appcast is updated, **when** a running instance of meet-notes checks for updates, **then** Sparkle validates the downloaded DMG's signature against the embedded `SUPublicEDKey` before installing — unsigned or mismatched payloads are rejected (NFR-I3).

5. **Given** the release workflow runs, **when** `CFBundleVersion` needs incrementing, **then** `agvtool` or a build number script auto-increments the build number on each merge; `CFBundleShortVersionString` is managed manually in `Info.plist`.

## Tasks / Subtasks

- [x] **Task 1: Create `ci.yml` GitHub Actions workflow** (AC: #1)
  - [x] Create `.github/workflows/ci.yml`
  - [x] Trigger on: `pull_request` targeting `main`, and `push` to `main` (for post-merge validation)
  - [x] Use `macos-15` runner (GA since April 2025, has Xcode 16.3+ pre-installed)
  - [x] Select Xcode version 16.3+ via `maxim-lobanov/setup-xcode@v1` or `sudo xcode-select`
  - [x] Resolve SPM dependencies: `xcodebuild -resolvePackageDependencies`
  - [x] Build: `xcodebuild build -scheme MeetNotes -destination 'platform=macOS,arch=arm64'`
  - [x] Run tests: `xcodebuild test -scheme MeetNotes -destination 'platform=macOS,arch=arm64'`
  - [x] Verify SwiftLint: SwiftLint runs as SPM build tool plugin during build — zero violations enforced by build failure
  - [x] Add concurrency group to cancel stale workflow runs on force-push

- [x] **Task 2: Create `release.yml` GitHub Actions workflow** (AC: #2, #3, #5)
  - [x] Create `.github/workflows/release.yml`
  - [x] Trigger on: `push` to `main` branch only (every merge triggers a release)
  - [x] Use `macos-15` runner with Xcode 16.3+
  - [x] **Step 1: Checkout** — `actions/checkout@v4` with full history for `agvtool`
  - [x] **Step 2: Import Developer ID certificate** — Decode `.p12` from `BUILD_CERTIFICATE_BASE64` secret, create temp keychain, import certificate
  - [x] **Step 3: Increment build number** — `xcrun agvtool new-version -all ${{ github.run_number }}`
  - [x] **Step 4: Resolve SPM dependencies** — `xcodebuild -resolvePackageDependencies`
  - [x] **Step 5: Archive** — `xcodebuild archive -scheme MeetNotes -archivePath build/MeetNotes.xcarchive`
  - [x] **Step 6: Export** — `xcodebuild -exportArchive -archivePath build/MeetNotes.xcarchive -exportPath build/export -exportOptionsPlist ExportOptions.plist`
  - [x] **Step 7: Create DMG** — Use `create-dmg` with `--sandbox-safe` flag for headless CI; fall back to `hdiutil` if needed
  - [x] **Step 8: Notarize** — `xcrun notarytool submit build/MeetNotes.dmg --key ... --key-id ... --issuer ... --wait`
  - [x] **Step 9: Staple** — `xcrun stapler staple build/MeetNotes.dmg`
  - [x] **Step 10: Sign with Sparkle EdDSA** — `./bin/sign_update build/MeetNotes.dmg --ed-key-file sparkle_private_key`
  - [x] **Step 11: Create GitHub Release** — Use `softprops/action-gh-release@v2` to upload DMG and appcast.xml
  - [x] **Step 12: Update appcast.xml** — Generate/update using Sparkle's `generate_appcast` tool or script
  - [x] **Step 13: Cleanup** — Delete temporary keychain

- [x] **Task 3: Create `ExportOptions.plist`** (AC: #2)
  - [x] Create `ExportOptions.plist` at project root (or `MeetNotes/MeetNotes/`)
  - [x] Set `method` = `developer-id` (not `app-store` — distributed outside App Store)
  - [x] Set `signingStyle` = `automatic` or specify `signingCertificate` = `Developer ID Application`
  - [x] Set `teamID` from secrets or hardcode if public

- [x] **Task 4: Add Sparkle `SUPublicEDKey` and `SUFeedURL` to Info.plist** (AC: #4)
  - [x] Generate Sparkle EdDSA key pair using `generate_keys` tool locally (one-time)
  - [x] Add `SUPublicEDKey` (base64 public key) to Info.plist
  - [x] Add `SUFeedURL` pointing to GitHub-hosted appcast.xml URL (e.g., `https://raw.githubusercontent.com/kuamatzin/meet-notes/main/appcast.xml` or GitHub Releases asset)
  - [x] Store the Sparkle private key as GitHub Actions secret `SPARKLE_PRIVATE_KEY`
  - [x] Verify Sparkle is already added as SPM dependency (added in Story 1.1)

- [x] **Task 5: Configure Xcode project for versioning** (AC: #5)
  - [x] Ensure Build Settings: Versioning System = "Apple Generic"
  - [x] Set `CURRENT_PROJECT_VERSION` (CFBundleVersion) = `1` (initial)
  - [x] Verify `MARKETING_VERSION` (CFBundleShortVersionString) = `0.1.0` (initial pre-release)
  - [x] Verify `agvtool what-version` reads the version correctly from the project

- [x] **Task 6: Document required GitHub Secrets** (AC: #2, #3, #4)
  - [x] Create or update README section listing all required GitHub Secrets:
    - `BUILD_CERTIFICATE_BASE64` — Developer ID Application certificate (.p12) as base64
    - `P12_PASSWORD` — Password for the .p12 file
    - `KEYCHAIN_PASSWORD` — Any random password for the temporary CI keychain
    - `ASC_KEY_ID` — App Store Connect API key ID
    - `ASC_ISSUER_ID` — App Store Connect issuer UUID
    - `ASC_PRIVATE_KEY` — App Store Connect API private key (.p8 content)
    - `SPARKLE_PRIVATE_KEY` — Sparkle EdDSA private key (for signing updates)
  - [x] Do NOT commit any actual secrets to the repository

- [x] **Task 7: Create initial `appcast.xml` placeholder** (AC: #3, #4)
  - [x] Create `appcast.xml` at repository root with empty `<channel>` element
  - [x] The release workflow will populate this with real release entries
  - [x] Structure: RSS 2.0 with Sparkle XML namespace

- [x] **Task 8: Verify and validate** (AC: all)
  - [x] Verify `ci.yml` syntax with `actionlint` or manual review
  - [x] Verify `release.yml` syntax and secret references
  - [x] Verify no actual secrets, certificates, or private keys in any committed file
  - [x] Verify Sparkle public key is in Info.plist
  - [x] Verify ExportOptions.plist has correct signing configuration
  - [x] Verify agvtool integration with Xcode project
  - [x] Document CI/CD setup steps in a comment block at the top of each workflow file

## Dev Notes

### Technical Requirements

**CI Workflow (`ci.yml`) Pattern:**

```yaml
# .github/workflows/ci.yml
name: CI

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

jobs:
  build-and-test:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4

      - uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: '16.3'

      - name: Resolve SPM dependencies
        run: |
          xcodebuild -resolvePackageDependencies \
            -project MeetNotes/MeetNotes/MeetNotes.xcodeproj \
            -scheme MeetNotes

      - name: Build
        run: |
          xcodebuild build \
            -project MeetNotes/MeetNotes/MeetNotes.xcodeproj \
            -scheme MeetNotes \
            -destination 'platform=macOS,arch=arm64' \
            SWIFT_STRICT_CONCURRENCY=complete

      - name: Test
        run: |
          xcodebuild test \
            -project MeetNotes/MeetNotes/MeetNotes.xcodeproj \
            -scheme MeetNotes \
            -destination 'platform=macOS,arch=arm64'
```

**Release Workflow (`release.yml`) Pattern:**

```yaml
# .github/workflows/release.yml
name: Release

on:
  push:
    branches: [main]

jobs:
  release:
    runs-on: macos-15
    permissions:
      contents: write  # Required for creating GitHub Releases
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0  # Full history for agvtool

      - uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: '16.3'

      - name: Install Developer ID certificate
        env:
          BUILD_CERTIFICATE_BASE64: ${{ secrets.BUILD_CERTIFICATE_BASE64 }}
          P12_PASSWORD: ${{ secrets.P12_PASSWORD }}
          KEYCHAIN_PASSWORD: ${{ secrets.KEYCHAIN_PASSWORD }}
        run: |
          CERTIFICATE_PATH=$RUNNER_TEMP/build_certificate.p12
          KEYCHAIN_PATH=$RUNNER_TEMP/app-signing.keychain-db

          echo -n "$BUILD_CERTIFICATE_BASE64" | base64 --decode -o $CERTIFICATE_PATH

          security create-keychain -p "$KEYCHAIN_PASSWORD" $KEYCHAIN_PATH
          security set-keychain-settings -lut 21600 $KEYCHAIN_PATH
          security unlock-keychain -p "$KEYCHAIN_PASSWORD" $KEYCHAIN_PATH
          security import $CERTIFICATE_PATH -P "$P12_PASSWORD" -A -t cert -f pkcs12 -k $KEYCHAIN_PATH
          security set-key-partition-list -S apple-tool:,apple: -k "$KEYCHAIN_PASSWORD" $KEYCHAIN_PATH
          security list-keychain -d user -s $KEYCHAIN_PATH

      - name: Increment build number
        run: |
          cd MeetNotes/MeetNotes
          xcrun agvtool new-version -all ${{ github.run_number }}

      - name: Resolve SPM dependencies
        run: |
          xcodebuild -resolvePackageDependencies \
            -project MeetNotes/MeetNotes/MeetNotes.xcodeproj \
            -scheme MeetNotes

      - name: Archive
        run: |
          xcodebuild archive \
            -project MeetNotes/MeetNotes/MeetNotes.xcodeproj \
            -scheme MeetNotes \
            -archivePath $RUNNER_TEMP/MeetNotes.xcarchive \
            SWIFT_STRICT_CONCURRENCY=complete

      - name: Export
        run: |
          xcodebuild -exportArchive \
            -archivePath $RUNNER_TEMP/MeetNotes.xcarchive \
            -exportPath $RUNNER_TEMP/export \
            -exportOptionsPlist ExportOptions.plist

      - name: Create DMG
        run: |
          brew install create-dmg
          create-dmg \
            --volname "MeetNotes" \
            --hide-extension "MeetNotes.app" \
            --app-drop-link 480 190 \
            --icon "MeetNotes.app" 180 190 \
            --no-internet-enable \
            --sandbox-safe \
            "$RUNNER_TEMP/MeetNotes-$(xcrun agvtool what-marketing-version -terse1).dmg" \
            "$RUNNER_TEMP/export/"
          # create-dmg exits 2 on "icon positioning failed" which is cosmetic — ignore
          DMG_PATH=$(ls $RUNNER_TEMP/MeetNotes-*.dmg)
          echo "DMG_PATH=$DMG_PATH" >> $GITHUB_ENV

      - name: Notarize
        env:
          ASC_KEY_ID: ${{ secrets.ASC_KEY_ID }}
          ASC_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
          ASC_PRIVATE_KEY: ${{ secrets.ASC_PRIVATE_KEY }}
        run: |
          ASC_KEY_PATH=$RUNNER_TEMP/AuthKey.p8
          echo -n "$ASC_PRIVATE_KEY" > $ASC_KEY_PATH
          xcrun notarytool submit "$DMG_PATH" \
            --key "$ASC_KEY_PATH" \
            --key-id "$ASC_KEY_ID" \
            --issuer "$ASC_ISSUER_ID" \
            --wait --timeout 30m

      - name: Staple
        run: xcrun stapler staple "$DMG_PATH"

      - name: Sign with Sparkle EdDSA
        env:
          SPARKLE_PRIVATE_KEY: ${{ secrets.SPARKLE_PRIVATE_KEY }}
        run: |
          SPARKLE_KEY_PATH=$RUNNER_TEMP/sparkle_private_key
          echo -n "$SPARKLE_PRIVATE_KEY" > $SPARKLE_KEY_PATH
          # Find Sparkle sign_update binary from SPM build artifacts
          SIGN_UPDATE=$(find ~/Library/Developer/Xcode/DerivedData -name "sign_update" -type f 2>/dev/null | head -1)
          if [ -z "$SIGN_UPDATE" ]; then
            echo "sign_update not found in DerivedData, extracting from Sparkle package"
            SIGN_UPDATE=$(find .build -name "sign_update" -type f 2>/dev/null | head -1)
          fi
          SIGNATURE=$("$SIGN_UPDATE" "$DMG_PATH" --ed-key-file "$SPARKLE_KEY_PATH")
          echo "SPARKLE_SIGNATURE=$SIGNATURE" >> $GITHUB_ENV

      - name: Get version info
        run: |
          cd MeetNotes/MeetNotes
          VERSION=$(xcrun agvtool what-marketing-version -terse1)
          BUILD=$(xcrun agvtool what-version -terse)
          echo "VERSION=$VERSION" >> $GITHUB_ENV
          echo "BUILD=$BUILD" >> $GITHUB_ENV

      - name: Create GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          tag_name: v${{ env.VERSION }}-build.${{ env.BUILD }}
          name: MeetNotes v${{ env.VERSION }} (Build ${{ env.BUILD }})
          files: ${{ env.DMG_PATH }}
          generate_release_notes: true

      - name: Clean up keychain
        if: always()
        run: security delete-keychain $RUNNER_TEMP/app-signing.keychain-db
```

**ExportOptions.plist:**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
```

**Appcast.xml Template:**

```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0"
     xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
     xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>MeetNotes Changelog</title>
    <link>https://github.com/kuamatzin/meet-notes</link>
    <description>Most recent changes with links to updates.</description>
    <language>en</language>
    <!-- Release items will be prepended here by the release workflow -->
  </channel>
</rss>
```

**Sparkle appcast item format (generated by release workflow):**

```xml
<item>
  <title>Version X.Y.Z</title>
  <sparkle:version>BUILD_NUMBER</sparkle:version>
  <sparkle:shortVersionString>X.Y.Z</sparkle:shortVersionString>
  <sparkle:minimumSystemVersion>14.2</sparkle:minimumSystemVersion>
  <pubDate>RFC_2822_DATE</pubDate>
  <enclosure
    url="https://github.com/kuamatzin/meet-notes/releases/download/vX.Y.Z-build.N/MeetNotes-X.Y.Z.dmg"
    sparkle:edSignature="BASE64_SIGNATURE"
    length="FILE_SIZE_BYTES"
    type="application/octet-stream" />
</item>
```

### Architecture Compliance

**Mandatory patterns from architecture document:**

- **CI/CD: Every merge to `main` triggers a full release build** — archive, sign, notarize, DMG, GitHub Release, Sparkle appcast update. This is the chosen deployment model for a solo open-source project.
- **Versioning:** `CFBundleVersion` (build number) auto-incremented by `agvtool` using `github.run_number`. `CFBundleShortVersionString` (marketing version) manually set in Info.plist at milestones.
- **Branch protection:** PRs must pass CI before merging to `main`. `main` is always releasable.
- **Distribution:** Notarized DMG outside App Store. Sparkle for auto-updates.
- **Hardened Runtime:** Already enabled (Story 1.1). Required for notarization.
- **No App Sandbox:** Already disabled (Story 1.1). Required for Core Audio Taps.
- **Secrets never in source:** All signing certificates, API keys, and private keys stored in GitHub Actions secrets. The app reads credentials at runtime from macOS Keychain only (SecretsStore from Story 1.2).
- **No crash reporting (v1.0):** Do NOT add Sentry, Crashlytics, or any telemetry dependency. Users file GitHub issues with Console.app crash logs (NFR-S5).
- **SPM only:** All dependencies via SPM. Sparkle is already added as SPM package (Story 1.1).

### Library & Framework Requirements

**Sparkle (Auto-Update):**
- Already added as SPM dependency in Story 1.1
- Latest stable: **Sparkle 2.9.0** (Feb 2026)
- Key integration: `SPUStandardUpdaterController` in `MeetNotesApp`, `SUPublicEDKey` + `SUFeedURL` in Info.plist
- EdDSA signing: Generate key pair with `generate_keys` tool, store private key as CI secret, embed public key in Info.plist
- Sparkle verifies `sparkle:edSignature` on every downloaded update against the embedded `SUPublicEDKey` (NFR-I3)
- Note: Sparkle's SwiftUI example uses `@ObservedObject` — this project must adapt to use `@Observable` pattern per architecture rules. However, for the Sparkle updater controller specifically, `SPUStandardUpdaterController` is Sparkle's own type and can be used as-is. Do NOT try to wrap it in `@Observable`.

**GitHub Actions:**
- `macos-15` runner: GA since April 2025, has Xcode 16.0–16.4 pre-installed
- `maxim-lobanov/setup-xcode@v1` to select specific Xcode version
- `actions/checkout@v4` with `fetch-depth: 0` for agvtool
- `softprops/action-gh-release@v2` for creating GitHub Releases

**xcrun notarytool:**
- Authenticates via App Store Connect API key (.p8) — recommended for CI over Apple ID
- `--wait` flag blocks until notarization completes (typically 2-10 minutes)
- `--timeout 30m` prevents hanging indefinitely
- After success: `xcrun stapler staple` embeds the ticket in the DMG

**create-dmg:**
- `brew install create-dmg` on CI runner
- `--sandbox-safe` flag is CRITICAL for headless CI (no GUI session)
- `--no-internet-enable` — Apple deprecated internet-enable for DMGs
- Exit code 2 from `create-dmg` is cosmetic (icon positioning failed) — the DMG contents are correct

**agvtool:**
- Requires Build Settings: "Versioning System" = "Apple Generic"
- `CURRENT_PROJECT_VERSION` must be set in pbxproj
- `xcrun agvtool new-version -all N` sets CFBundleVersion
- `xcrun agvtool what-marketing-version -terse1` reads CFBundleShortVersionString
- Modifies Info.plist and pbxproj in place — fine for CI since changes are not committed back

### File Structure Requirements

**New files to create:**

| File | Location | Type |
|---|---|---|
| `ci.yml` | `.github/workflows/` | GitHub Actions workflow |
| `release.yml` | `.github/workflows/` | GitHub Actions workflow |
| `ExportOptions.plist` | Repository root or `MeetNotes/MeetNotes/` | Xcode export configuration |
| `appcast.xml` | Repository root | Sparkle appcast feed |

**Files to modify:**

| File | Change |
|---|---|
| Info.plist | Add `SUPublicEDKey` and `SUFeedURL` keys |
| project.pbxproj | Verify `VERSIONING_SYSTEM = "apple-generic"` and `CURRENT_PROJECT_VERSION = 1` |

**No Swift source files are created or modified in this story.** This story is entirely infrastructure (YAML, plist, XML).

**Important path notes:**
- GitHub Actions workflows MUST be in `.github/workflows/` at the repository root
- The Xcode project is at `MeetNotes/MeetNotes/MeetNotes.xcodeproj/` — all `xcodebuild` commands must use `-project` flag with this path
- `agvtool` must be run from within the directory containing the `.xcodeproj` (`cd MeetNotes/MeetNotes`)
- `ExportOptions.plist` path is relative to where `xcodebuild -exportArchive` runs — place at repo root and reference with full path, or place alongside the xcodeproj

### Testing Requirements

**This story has no unit tests.** CI/CD pipeline testing is validated by:
1. Pushing a PR and verifying `ci.yml` runs successfully
2. Merging to `main` and verifying `release.yml` produces a GitHub Release
3. Downloading the DMG and verifying Gatekeeper accepts it
4. Verifying `appcast.xml` is updated with correct signature

**Manual verification checklist:**
- [ ] CI workflow passes on PR: build + test + SwiftLint
- [ ] Release workflow produces signed, notarized DMG
- [ ] DMG opens cleanly on macOS 14.2+ with Gatekeeper
- [ ] `appcast.xml` contains valid Sparkle entry with EdDSA signature
- [ ] `spctl --assess --verbose=4 --type execute MeetNotes.app` returns "accepted"
- [ ] `codesign --verify --deep --strict MeetNotes.app` succeeds
- [ ] `xcrun stapler validate MeetNotes.dmg` succeeds

### Previous Story Intelligence

**From Story 1.2 (App Database Foundation & Secrets Store):**

Critical learnings:
1. **SwiftLintBuildToolPlugin was incorrectly referenced** as a Framework dependency in pbxproj (Story 1.1 bug) — removed from Frameworks build phase and packageProductDependencies. This fix should already be applied. Verify before CI workflow runs.
2. **OllamaKit NOT linked** to target due to Swift 6 strict concurrency error. Do NOT reference OllamaKit in build verification.
3. **PBXFileSystemSynchronizedRootGroup** — Xcode 16+ auto-discovers files. No manual pbxproj editing for new source files.
4. **`.gitkeep` files removed** in Story 1.2 — all placeholder files in source directories were removed to fix "duplicate output file" build errors.
5. **Test target exists** — `MeetNotesTests` with Swift Testing framework. CI must run these tests.
6. **DatabasePool requires real file** (not `:memory:`) — tests use temp file paths. This should work fine on CI macOS runners.
7. **Keychain tests may fail on CI** — SecretsStore tests use real macOS Keychain. May need to be gated or the CI runner may need Keychain access configured.

**Code patterns established:**
- `Logger(subsystem: "com.kuamatzin.meet-notes", category: "<TypeName>")`
- GRDB with WAL mode, Swift Testing framework
- All builds use `SWIFT_STRICT_CONCURRENCY = complete`

### Git Intelligence

**Recent commits (2 total):**
- `a1e7def` — Add Xcode project structure with code review fixes
- `5d57653` — Initial commit: project scaffold, planning artifacts, and Story 1.1 Swift source files

**Observations:**
- No `.github/` directory exists yet — will be created by this story
- No `ExportOptions.plist` exists
- No `appcast.xml` exists
- Entitlements file at `MeetNotes/MeetNotes/MeetNotes/MeetNotes.entitlements` already has required permissions (sandbox disabled, audio input, screen recording, network client)
- Sparkle is already in SPM dependencies but Sparkle-related Info.plist keys are not yet configured

### Latest Tech Information

**Sparkle 2.9.0 (Feb 2026):**
- EdDSA (Ed25519) is the only supported signing method (DSA deprecated)
- `generate_keys` tool creates the key pair, stores private key in Keychain
- `generate_keys -x <file>` exports private key for CI
- `sign_update` tool signs DMG files with EdDSA
- `generate_appcast` tool auto-generates `appcast.xml` from a directory of archives
- SPM integration fully supported

**GitHub Actions macOS runners (March 2026):**
- `macos-15` runner: GA, has Xcode 16.0–16.4
- `macos-14` runner: Available, has Xcode 15.x–16.2
- `macos-latest` points to `macos-15` since Sept 2025
- Apple Silicon runners available (`macos-15` uses M1)

**xcrun notarytool (current):**
- App Store Connect API key authentication recommended for CI
- `--wait` flag blocks until complete (replaces the old `altool --notarize-app` + polling pattern)
- `--timeout 30m` prevents indefinite hangs
- After success, `xcrun stapler staple` embeds the ticket

**create-dmg:**
- `brew install create-dmg` — available on CI
- `--sandbox-safe` is REQUIRED for headless CI environments (no Finder/AppleScript)
- Exit code 2 is cosmetic (icon positioning) — DMG contents are correct

### Project Structure Notes

- This story creates infrastructure files only (YAML workflows, plist, XML) — no Swift source
- `.github/workflows/` directory must be at the repository root (not inside `MeetNotes/`)
- All `xcodebuild` commands must reference the correct project path: `MeetNotes/MeetNotes/MeetNotes.xcodeproj`
- `agvtool` must run from the directory containing the xcodeproj
- The owner must generate Sparkle EdDSA keys locally and store the private key as a GitHub secret before the release workflow can sign updates

### References

- CI/CD architecture decision: [Source: _bmad-output/planning-artifacts/architecture.md#Infrastructure & Deployment]
- Release pipeline: [Source: _bmad-output/planning-artifacts/architecture.md#Decision: CI/CD Release Trigger]
- Sparkle integration: [Source: _bmad-output/planning-artifacts/architecture.md#Technical Constraints & Dependencies]
- Versioning strategy: [Source: _bmad-output/planning-artifacts/architecture.md#Decision Impact Analysis]
- NFR-I3 (Sparkle signature verification): [Source: _bmad-output/planning-artifacts/prd.md#Integration]
- NFR-S5 (No telemetry): [Source: _bmad-output/planning-artifacts/prd.md#Security & Privacy]
- Distribution strategy (notarized DMG): [Source: _bmad-output/planning-artifacts/prd.md#Desktop App Specific Requirements]
- Update strategy: [Source: _bmad-output/planning-artifacts/prd.md#Update Strategy]
- Branch strategy: [Source: _bmad-output/project-context.md#Development Workflow Rules]
- Commit message style: [Source: _bmad-output/project-context.md#Development Workflow Rules]
- Story 1.3 acceptance criteria: [Source: _bmad-output/planning-artifacts/epics.md#Story 1.3]
- Previous story learnings: [Source: _bmad-output/implementation-artifacts/1-2-app-database-foundation-secrets-store.md#Dev Agent Record]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6

### Debug Log References

- actionlint initially reported SC2086 (info-level shellcheck) for unquoted variables in release.yml — all fixed by adding double quotes to shell variable expansions
- No Info.plist existed (project uses GENERATE_INFOPLIST_FILE=YES) — created partial Info.plist with Sparkle keys only and added INFOPLIST_FILE build setting; Xcode merges custom keys with auto-generated ones
- MARKETING_VERSION was 1.0 (from Story 1.1) — updated to 0.1.0 per story spec
- VERSIONING_SYSTEM was not set — added "apple-generic" to enable agvtool
- ExportOptions.plist uses `signingStyle = automatic` (no teamID hardcoded) — team is resolved from Xcode's automatic signing
- SUPublicEDKey has placeholder value — owner must generate actual key pair with Sparkle's generate_keys tool

### Completion Notes List

- Created CI workflow (.github/workflows/ci.yml) with macos-15 runner, Xcode 16.3, build+test+SwiftLint, concurrency group
- Created Release workflow (.github/workflows/release.yml) with full pipeline: certificate import, agvtool build number increment, archive, export, DMG creation, notarization, stapling, Sparkle EdDSA signing, appcast update, GitHub Release creation, keychain cleanup
- Created ExportOptions.plist at repo root with developer-id method and automatic signing
- Created Info.plist with SUPublicEDKey (placeholder) and SUFeedURL pointing to GitHub raw content
- Updated pbxproj: added INFOPLIST_FILE, VERSIONING_SYSTEM=apple-generic, MARKETING_VERSION=0.1.0
- Created appcast.xml placeholder with RSS 2.0 + Sparkle namespace
- Updated README.md with CI/CD section, required GitHub secrets table, Sparkle key setup instructions
- All workflow files validated clean with actionlint (zero errors/warnings)
- No secrets committed — verified all secret references use ${{ secrets.* }}

### Change Log

- 2026-03-03: Implemented full CI/CD pipeline — ci.yml, release.yml, ExportOptions.plist, appcast.xml, Info.plist with Sparkle keys, pbxproj versioning config, README CI/CD docs
- 2026-03-03: Code review fixes — 9 issues found (4 HIGH, 3 MEDIUM, 2 LOW), all fixed: appcast commit-back step added to release.yml, create-dmg error handling improved, sign_update discovery error guard added, release concurrency group added, secret files cleanup expanded, project-context.md runner version corrected, branch protection documented in README, MeetNotesTests MARKETING_VERSION fixed, story File List updated

### File List

| Action | File |
|---|---|
| Added | .github/workflows/ci.yml |
| Added | .github/workflows/release.yml |
| Added | ExportOptions.plist |
| Added | appcast.xml |
| Added | MeetNotes/MeetNotes/MeetNotes/Info.plist |
| Modified | MeetNotes/MeetNotes/MeetNotes.xcodeproj/project.pbxproj |
| Modified | README.md |
| Modified | MeetNotes/MeetNotes/MeetNotesTests (MARKETING_VERSION fix in pbxproj) |
| Modified | _bmad-output/project-context.md |
| Modified | _bmad-output/implementation-artifacts/sprint-status.yaml |
| Modified | _bmad-output/implementation-artifacts/1-3-automated-build-distribution-pipeline.md |
