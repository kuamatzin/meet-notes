# Story 1.2: App Database Foundation & Secrets Store

Status: done

<!-- Note: Validation is optional. Run validate-create-story for quality check before dev-story. -->

## Story

As a developer building meet-notes,
I want the SQLite database initialized with the full schema (meetings, segments, settings, FTS5) via GRDB DatabasePool + WAL mode, and API keys stored exclusively in the macOS Keychain,
So that all subsequent features have a reliable, secure data layer that never blocks the audio pipeline and never exposes credentials.

## Acceptance Criteria

1. **Given** the app launches for the first time, **when** `AppDatabase` initializes, **then** a GRDB `DatabasePool` opens in WAL mode at `~/Library/Application Support/meet-notes/meetings.db`, creating the directory if needed, **and** the `v1` migration runs creating: `meetings` table, `segments` table, `settings` table, `segments_fts` FTS5 virtual table with Porter stemming and `content='segments'`, `content_rowid='id'`.

2. **Given** the v1 migration creates the sync triggers, **when** a segment is inserted into `segments`, **then** the `segments_ai` trigger automatically inserts the segment's `text` into `segments_fts`.

3. **Given** a segment is deleted from `segments`, **when** the `segments_ad` trigger fires, **then** the deleted row is removed from `segments_fts`.

4. **Given** the app launches when the database already exists, **when** the `DatabaseMigrator` runs, **then** it is idempotent — already-applied migrations are skipped without error or data loss.

5. **Given** `SecretsStore.save(apiKey:for:)` is called with a credential, **when** the operation completes, **then** the key is stored in the macOS Keychain via `SecItem` APIs **and** the key is NOT present in UserDefaults, any SQLite table, any plist file, or any log output (NFR-S1).

6. **Given** `SecretsStore.load(for:)` is called when no key has been saved, **then** it returns `nil` without throwing.

7. **Given** `SecretsStore.delete(for:)` is called, **then** the key is removed from the Keychain and subsequent `load(for:)` calls return `nil`.

8. **Given** the Swift 6 concurrency checker runs, **when** the entire `AppDatabase` and `SecretsStore` codebase is analyzed, **then** there are zero actor isolation warnings or errors.

## Tasks / Subtasks

- [x] **Task 1: Create `AppDatabase` class with GRDB DatabasePool + WAL** (AC: #1, #4)
  - [x]Create `Infrastructure/Database/AppDatabase.swift`
  - [x]Initialize `DatabasePool` at `~/Library/Application Support/meet-notes/meetings.db`
  - [x]Create the `Application Support/meet-notes/` directory if it doesn't exist using `FileManager`
  - [x]Configure WAL mode (GRDB `DatabasePool` uses WAL by default — verify, do not set manually)
  - [x]Add a `DatabaseMigrator` property with `eraseDatabaseOnSchemaChange = false` (production safety)
  - [x]Expose a `static let shared` singleton for app-wide access (or use dependency injection via init parameter)
  - [x]Ensure `AppDatabase` is a plain `class` (not actor, not @MainActor) — GRDB `DatabasePool` handles its own thread safety

- [x] **Task 2: Implement v1 migration — meetings table** (AC: #1)
  - [x]Register migration `"v1"` in the `DatabaseMigrator`
  - [x]Create `meetings` table with columns: `id TEXT PRIMARY KEY`, `title TEXT NOT NULL DEFAULT ''`, `started_at DATETIME NOT NULL`, `ended_at DATETIME`, `duration_seconds REAL`, `audio_quality TEXT NOT NULL DEFAULT 'full'`, `summary_md TEXT`, `pipeline_status TEXT NOT NULL DEFAULT 'recording'`, `created_at DATETIME NOT NULL DEFAULT (datetime('now'))`
  - [x]Valid `audio_quality` values: `'full'`, `'mic_only'`, `'partial'`
  - [x]Valid `pipeline_status` values: `'recording'`, `'transcribing'`, `'summarizing'`, `'complete'`, `'failed'`

- [x] **Task 3: Implement v1 migration — segments table** (AC: #1, #2, #3)
  - [x]Create `segments` table: `id INTEGER PRIMARY KEY AUTOINCREMENT`, `meeting_id TEXT NOT NULL REFERENCES meetings(id) ON DELETE CASCADE`, `start_seconds REAL NOT NULL`, `end_seconds REAL NOT NULL`, `text TEXT NOT NULL`, `confidence REAL`
  - [x]Create `segments_fts` FTS5 virtual table: `CREATE VIRTUAL TABLE segments_fts USING fts5(text, content='segments', content_rowid='id', tokenize='porter unicode61')`
  - [x]Create trigger `segments_ai`: after INSERT on segments, insert into segments_fts
  - [x]Create trigger `segments_ad`: after DELETE on segments, insert delete command into segments_fts
  - [x]Create trigger `segments_au`: after UPDATE on segments, delete old entry then insert new entry into segments_fts

- [x] **Task 4: Implement v1 migration — settings table** (AC: #1)
  - [x]Create `settings` table: `key TEXT PRIMARY KEY`, `value TEXT NOT NULL`
  - [x]This table stores non-sensitive app preferences (Whisper model choice, Ollama endpoint, launch-at-login, etc.)
  - [x]API keys are NOT stored here — they go in Keychain via SecretsStore (NFR-S1)

- [x] **Task 5: Create GRDB record structs** (AC: #1, #8)
  - [x]Create `Infrastructure/Database/Meeting.swift` — `struct Meeting: Codable, Identifiable, FetchableRecord, PersistableRecord`
  - [x]Define nested `Columns` enum with explicit column mappings (camelCase → snake_case)
  - [x]Define nested `AudioQuality` enum: `full`, `micOnly`, `partial` (raw values match SQL)
  - [x]Define nested `PipelineStatus` enum: `recording`, `transcribing`, `summarizing`, `complete`, `failed` (raw values match SQL)
  - [x]Create `Infrastructure/Database/TranscriptSegment.swift` — `struct TranscriptSegment: Codable, Identifiable, FetchableRecord, PersistableRecord`
  - [x]Define nested `Columns` enum with explicit column mappings
  - [x]Create `Infrastructure/Database/AppSetting.swift` — `struct AppSetting: Codable, FetchableRecord, PersistableRecord`
  - [x]All record types: NO suffix (not `MeetingRecord`, not `MeetingModel`)
  - [x]All types must pass Swift 6 strict concurrency (add `Sendable` conformance)

- [x] **Task 6: Create `SecretsStore` struct** (AC: #5, #6, #7, #8)
  - [x]Create `Infrastructure/Secrets/SecretsStore.swift`
  - [x]Define as `struct SecretsStore` with static methods only — no instantiation, no state
  - [x]Define `LLMProviderKey` enum: `openAI`, `anthropic` (String raw values used as Keychain account names)
  - [x]Implement `static func save(apiKey: String, for provider: LLMProviderKey) throws`
  - [x]Implement `static func load(for provider: LLMProviderKey) -> String?`
  - [x]Implement `static func delete(for provider: LLMProviderKey) throws`
  - [x]Use `SecItemAdd`, `SecItemCopyMatching`, `SecItemUpdate`, `SecItemDelete` APIs
  - [x]Keychain query attributes: `kSecClass: kSecClassGenericPassword`, `kSecAttrService: "com.kuamatzin.meet-notes"`, `kSecAttrAccount: provider.rawValue`
  - [x]Do NOT set `kSecAttrSynchronizable` (local-only, no iCloud sync — privacy requirement)
  - [x]`save` must handle "already exists" by calling `SecItemUpdate` instead of duplicating
  - [x]`load` returns `nil` on `errSecItemNotFound` — does not throw
  - [x]`delete` succeeds silently if item doesn't exist (`errSecItemNotFound` is not an error)

- [x] **Task 7: Write unit tests for AppDatabase** (AC: #1, #2, #3, #4)
  - [x]Create `MeetNotesTests/Infrastructure/AppDatabaseTests.swift`
  - [x]Use Swift Testing framework (`@Test`, `#expect`) — NOT XCTest
  - [x]Use in-memory database (`:memory:`) — never a file path
  - [x]Test: v1 migration creates all 3 tables + FTS5 virtual table
  - [x]Test: insert a Meeting record, fetch it back, verify all fields
  - [x]Test: insert a TranscriptSegment, verify FTS5 trigger populates segments_fts
  - [x]Test: delete a TranscriptSegment, verify it's removed from segments_fts
  - [x]Test: idempotent migration — running migrator twice doesn't error
  - [x]Test: ON DELETE CASCADE — deleting a meeting removes its segments

- [x] **Task 8: Write unit tests for SecretsStore** (AC: #5, #6, #7)
  - [x]Create `MeetNotesTests/Infrastructure/SecretsStoreTests.swift`
  - [x]Use Swift Testing framework (`@Test`, `#expect`)
  - [x]Test: save + load round-trip for `.openAI` key
  - [x]Test: save + load round-trip for `.anthropic` key
  - [x]Test: load returns nil when no key saved
  - [x]Test: delete removes key, subsequent load returns nil
  - [x]Test: save overwrites existing key (update, not duplicate)
  - [x]Note: Keychain tests require running on macOS (not CI-safe on Linux runners)

- [x] **Task 9: Verify and validate** (AC: all)
  - [x]Build with `SWIFT_STRICT_CONCURRENCY = complete` → zero warnings
  - [x]Run all tests → all pass
  - [x]SwiftLint → zero violations
  - [x]Verify no API keys, passwords, or secrets in any committed file
  - [x]Verify `AppDatabase` directory creation works on clean install (delete `~/Library/Application Support/meet-notes/` and re-run)

## Dev Notes

### Technical Requirements

**GRDB DatabasePool + WAL Mode:**

`AppDatabase` is a plain `class` (not `actor`, not `@MainActor`). GRDB's `DatabasePool` is inherently thread-safe — it manages its own reader/writer dispatch. Wrapping it in an actor would cause unnecessary serialization and potential deadlocks.

```swift
// Infrastructure/Database/AppDatabase.swift
import GRDB
import os

private let logger = Logger(subsystem: "com.kuamatzin.meet-notes", category: "AppDatabase")

final class AppDatabase: Sendable {
    let pool: DatabasePool

    init(_ pool: DatabasePool) throws {
        self.pool = pool
        var migrator = DatabaseMigrator()
        migrator.eraseDatabaseOnSchemaChange = false
        migrator.registerMigration("v1") { db in
            // meetings table
            try db.create(table: "meetings") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull().defaults(to: "")
                t.column("started_at", .datetime).notNull()
                t.column("ended_at", .datetime)
                t.column("duration_seconds", .double)
                t.column("audio_quality", .text).notNull().defaults(to: "full")
                t.column("summary_md", .text)
                t.column("pipeline_status", .text).notNull().defaults(to: "recording")
                t.column("created_at", .datetime).notNull().defaults(sql: "datetime('now')")
            }

            // segments table
            try db.create(table: "segments") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("meeting_id", .text).notNull()
                    .references("meetings", onDelete: .cascade)
                t.column("start_seconds", .double).notNull()
                t.column("end_seconds", .double).notNull()
                t.column("text", .text).notNull()
                t.column("confidence", .double)
            }

            // settings table
            try db.create(table: "settings") { t in
                t.primaryKey("key", .text)
                t.column("value", .text).notNull()
            }

            // FTS5 virtual table
            try db.execute(sql: """
                CREATE VIRTUAL TABLE segments_fts USING fts5(
                    text,
                    content='segments',
                    content_rowid='id',
                    tokenize='porter unicode61'
                )
                """)

            // FTS5 sync triggers
            try db.execute(sql: """
                CREATE TRIGGER segments_ai AFTER INSERT ON segments BEGIN
                    INSERT INTO segments_fts(rowid, text) VALUES (new.id, new.text);
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER segments_ad AFTER DELETE ON segments BEGIN
                    INSERT INTO segments_fts(segments_fts, rowid, text) VALUES ('delete', old.id, old.text);
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER segments_au AFTER UPDATE ON segments BEGIN
                    INSERT INTO segments_fts(segments_fts, rowid, text) VALUES ('delete', old.id, old.text);
                    INSERT INTO segments_fts(rowid, text) VALUES (new.id, new.text);
                END
                """)
        }
        try migrator.migrate(pool)
    }
}
```

**Database file location:**
```swift
static func makeShared() throws -> AppDatabase {
    let url = try FileManager.default
        .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        .appendingPathComponent("meet-notes", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    let dbURL = url.appendingPathComponent("meetings.db")
    let pool = try DatabasePool(path: dbURL.path)
    return try AppDatabase(pool)
}
```

**SecretsStore Pattern:**
```swift
// Infrastructure/Secrets/SecretsStore.swift
import Foundation
import Security
import os

private let logger = Logger(subsystem: "com.kuamatzin.meet-notes", category: "SecretsStore")

struct SecretsStore {
    enum LLMProviderKey: String, CaseIterable, Sendable {
        case openAI = "openai-api-key"
        case anthropic = "anthropic-api-key"
    }

    private static let service = "com.kuamatzin.meet-notes"

    static func save(apiKey: String, for provider: LLMProviderKey) throws {
        let data = Data(apiKey.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue
        ]
        // Try update first; if item doesn't exist, add it
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess {
            let update: [String: Any] = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw SecretsStoreError.keychainFailure(updateStatus)
            }
        } else {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw SecretsStoreError.keychainFailure(addStatus)
            }
        }
    }

    static func load(for provider: LLMProviderKey) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(for provider: LLMProviderKey) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue
        ]
        SecItemDelete(query as CFDictionary)  // errSecItemNotFound is fine — no-op
    }
}

enum SecretsStoreError: Error, LocalizedError {
    case keychainFailure(OSStatus)
    var errorDescription: String? {
        "Keychain operation failed with status \(String(describing: self))"
    }
}
```

**GRDB Record Struct Pattern (explicit Columns):**
```swift
// Infrastructure/Database/Meeting.swift
struct Meeting: Codable, Identifiable, FetchableRecord, PersistableRecord, Sendable {
    var id: String  // UUID string
    var title: String
    var startedAt: Date
    var endedAt: Date?
    var durationSeconds: Double?
    var audioQuality: AudioQuality
    var summaryMd: String?
    var pipelineStatus: PipelineStatus
    var createdAt: Date

    enum AudioQuality: String, Codable, Sendable {
        case full, micOnly = "mic_only", partial
    }

    enum PipelineStatus: String, Codable, Sendable {
        case recording, transcribing, summarizing, complete, failed
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let title = Column(CodingKeys.title)
        static let startedAt = Column(CodingKeys.startedAt)
        static let endedAt = Column(CodingKeys.endedAt)
        static let durationSeconds = Column(CodingKeys.durationSeconds)
        static let audioQuality = Column(CodingKeys.audioQuality)
        static let summaryMd = Column(CodingKeys.summaryMd)
        static let pipelineStatus = Column(CodingKeys.pipelineStatus)
        static let createdAt = Column(CodingKeys.createdAt)
    }
}
```

**CRITICAL: GRDB column name mapping.** GRDB uses `CodingKeys` for column name derivation. You MUST add a custom `CodingKeys` enum to map Swift `camelCase` to SQL `snake_case`:
```swift
enum CodingKeys: String, CodingKey {
    case id, title
    case startedAt = "started_at"
    case endedAt = "ended_at"
    case durationSeconds = "duration_seconds"
    case audioQuality = "audio_quality"
    case summaryMd = "summary_md"
    case pipelineStatus = "pipeline_status"
    case createdAt = "created_at"
}
```

**Same pattern for TranscriptSegment:**
```swift
struct TranscriptSegment: Codable, Identifiable, FetchableRecord, PersistableRecord, Sendable {
    var id: Int64?  // AUTOINCREMENT — nil before insert
    var meetingId: String
    var startSeconds: Double
    var endSeconds: Double
    var text: String
    var confidence: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case meetingId = "meeting_id"
        case startSeconds = "start_seconds"
        case endSeconds = "end_seconds"
        case text, confidence
    }

    static let databaseTableName = "segments"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let meetingId = Column(CodingKeys.meetingId)
        static let startSeconds = Column(CodingKeys.startSeconds)
        static let endSeconds = Column(CodingKeys.endSeconds)
        static let text = Column(CodingKeys.text)
        static let confidence = Column(CodingKeys.confidence)
    }
}
```

### Architecture Compliance

**Mandatory patterns from architecture document:**

- `AppDatabase` is a plain `class` (or `final class: Sendable`) — NOT an actor. GRDB `DatabasePool` is internally thread-safe. Wrapping in an actor adds unnecessary serialization.
- `SecretsStore` is a `struct` with static methods only. No instantiation, no shared state, no actor. Keychain is inherently thread-safe.
- Record types (`Meeting`, `TranscriptSegment`, `AppSetting`) have NO suffix — they are named after the domain entity directly.
- Migrations are append-only. Once `"v1"` is registered, it is NEVER modified in future stories. New schema changes get `"v2"`, `"v3"`, etc.
- `DatabasePool` WAL mode is the default for `DatabasePool` in GRDB — do NOT manually set journal mode. Just use `DatabasePool(path:)`.
- FTS5 triggers keep `segments_fts` in sync automatically. Never manually insert into `segments_fts` — always insert/update/delete via the `segments` table.
- `ValueObservation` (used by ViewModels in later stories) depends on the schema being correct here. The FTS5 and trigger setup MUST be verified via tests.
- Error propagation: `AppDatabase` initialization errors should be fatal at app launch (the app cannot function without a database). Use `try!` or `fatalError` in the `shared` initializer if the database cannot be opened.
- Logger category: `"AppDatabase"` for database operations, `"SecretsStore"` for keychain operations. Subsystem: `"com.kuamatzin.meet-notes"`.
- NEVER use `print()` — use `Logger` only.

### Library & Framework Requirements

**GRDB.swift:**
- Version: ≥ 7.0.0 (latest stable: 7.10.0, Feb 2026). Already added as SPM dependency in Story 1.1 with `upToNextMajorVersion: 7.0.0`.
- Import: `import GRDB`
- Key APIs: `DatabasePool`, `DatabaseMigrator`, `FetchableRecord`, `PersistableRecord`, `Column`, `ValueObservation`
- `DatabasePool` automatically uses WAL mode. Do NOT manually execute `PRAGMA journal_mode=wal`.
- GRDB 7.x requires Swift 6.1+ / Xcode 16.3+ — matches our project requirements.
- Use GRDB's type-safe table creation API (`db.create(table:)`) for readability, but raw SQL is acceptable for FTS5 virtual tables and triggers (GRDB doesn't have a type-safe API for these).

**Security framework (Keychain):**
- Import: `import Security`
- No external dependency — `Security.framework` is part of macOS SDK.
- Key APIs: `SecItemAdd`, `SecItemCopyMatching`, `SecItemUpdate`, `SecItemDelete`
- Use `kSecClassGenericPassword` for API keys.
- Do NOT use `kSecAttrSynchronizable` — keys must stay local (privacy requirement NFR-S1).
- Handle `errSecItemNotFound` (-25300) gracefully — it means "no key stored", not an error.
- Handle `errSecDuplicateItem` (-25299) by using update flow instead of add.

### File Structure Requirements

**New files to create (all paths relative to `MeetNotes/MeetNotes/MeetNotes/`):**

| File | Location | Type |
|---|---|---|
| `AppDatabase.swift` | `Infrastructure/Database/` | `final class AppDatabase: Sendable` |
| `Meeting.swift` | `Infrastructure/Database/` | `struct Meeting: Codable, Identifiable, FetchableRecord, PersistableRecord, Sendable` |
| `TranscriptSegment.swift` | `Infrastructure/Database/` | `struct TranscriptSegment: Codable, Identifiable, FetchableRecord, PersistableRecord, Sendable` |
| `AppSetting.swift` | `Infrastructure/Database/` | `struct AppSetting: Codable, FetchableRecord, PersistableRecord, Sendable` |
| `SecretsStore.swift` | `Infrastructure/Secrets/` | `struct SecretsStore` (static methods only) |

**New test files (relative to `MeetNotes/MeetNotes/MeetNotesTests/`):**

| File | Location |
|---|---|
| `AppDatabaseTests.swift` | `Infrastructure/` |
| `SecretsStoreTests.swift` | `Infrastructure/` |

**Existing directories that already have `.gitkeep` files:**
- `Infrastructure/Database/` — remove `.gitkeep` after adding Swift files
- `Infrastructure/Secrets/` — remove `.gitkeep` after adding Swift files
- `MeetNotesTests/Infrastructure/` — remove `.gitkeep` after adding test files

**Xcode project note:** Files placed in `PBXFileSystemSynchronizedRootGroup` directories (Xcode 16+) are automatically discovered by Xcode. No manual pbxproj editing needed for new files — just create them in the correct filesystem location.

**Do NOT create files outside these directories.** Do not create any files in `Features/`, `UI/`, or `App/` for this story.

### Testing Requirements

**Framework:** Swift Testing (`@Test`, `#expect`, `#require`) — NOT XCTest. Do not mix both in the same file.

**AppDatabase tests — in-memory database:**
```swift
import Testing
import GRDB
@testable import MeetNotes

struct AppDatabaseTests {
    private func makeDatabase() throws -> AppDatabase {
        let pool = try DatabasePool(path: ":memory:")
        return try AppDatabase(pool)
    }

    @Test func migrationCreatesAllTables() throws {
        let db = try makeDatabase()
        try db.pool.read { db in
            #expect(try db.tableExists("meetings"))
            #expect(try db.tableExists("segments"))
            #expect(try db.tableExists("settings"))
            // FTS5 virtual table
            #expect(try db.tableExists("segments_fts"))
        }
    }

    @Test func idempotentMigration() throws {
        // Running init twice should not error
        let pool = try DatabasePool(path: ":memory:")
        _ = try AppDatabase(pool)
        _ = try AppDatabase(pool)  // second run — idempotent
    }

    @Test func insertAndFetchMeeting() throws { /* ... */ }
    @Test func fts5TriggerOnInsert() throws { /* ... */ }
    @Test func fts5TriggerOnDelete() throws { /* ... */ }
    @Test func cascadeDeleteSegments() throws { /* ... */ }
}
```

**SecretsStore tests — real Keychain (macOS only):**
```swift
import Testing
@testable import MeetNotes

struct SecretsStoreTests {
    // Clean up after each test
    private func cleanup() {
        SecretsStore.delete(for: .openAI)
        SecretsStore.delete(for: .anthropic)
    }

    @Test func saveAndLoadRoundTrip() throws {
        defer { cleanup() }
        try SecretsStore.save(apiKey: "sk-test-123", for: .openAI)
        #expect(SecretsStore.load(for: .openAI) == "sk-test-123")
    }

    @Test func loadReturnsNilWhenEmpty() {
        cleanup()
        #expect(SecretsStore.load(for: .openAI) == nil)
    }

    @Test func deleteRemovesKey() throws {
        defer { cleanup() }
        try SecretsStore.save(apiKey: "sk-test", for: .anthropic)
        SecretsStore.delete(for: .anthropic)
        #expect(SecretsStore.load(for: .anthropic) == nil)
    }

    @Test func saveOverwritesExistingKey() throws {
        defer { cleanup() }
        try SecretsStore.save(apiKey: "old-key", for: .openAI)
        try SecretsStore.save(apiKey: "new-key", for: .openAI)
        #expect(SecretsStore.load(for: .openAI) == "new-key")
    }
}
```

**CI note:** SecretsStore tests use the real macOS Keychain and may not pass on CI runners without Keychain access. Consider marking with a custom trait if needed, but they MUST pass on local macOS builds.

### Previous Story Intelligence

**From Story 1.1 (Xcode Project Initialization):**

**Critical learnings:**
1. **OllamaKit NOT linked** — Added as SPM package reference but NOT linked to MeetNotes target due to Swift 6 strict concurrency error in `OKHTTPClient.swift:52`. Will be linked in Story 5.2. Do NOT attempt to import or use OllamaKit in this story.
2. **Xcode 26 defaults** — Project uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and `SWIFT_APPROACHABLE_CONCURRENCY = YES`. This means types without explicit annotation default to `@MainActor`. Be explicit about isolation annotations on new types.
3. **NavigationState.shared singleton** — Code review found that `MeetNotesApp` was creating a new `NavigationState()` instead of using `NavigationState.shared`. Fixed. Same pattern vigilance needed for `AppDatabase` — decide on shared vs injected and be consistent.
4. **GRDB version pinning** — Changed from `branch: master` to `upToNextMajorVersion: 7.0.0` during code review. No further version changes needed.
5. **PBXFileSystemSynchronizedRootGroup** — Xcode 26 uses synchronized root groups. New files in the filesystem are automatically discovered. No manual pbxproj editing required for new source files.
6. **SwiftLint `identifier_name` rule** — Short variable names (`a`, `r`, `g`, `b`) were flagged. Avoid single-character variable names.
7. **Test target exists** — `MeetNotesTests` target was manually added with Swift Testing `@Test` function. Tests use `import Testing`, not XCTest.
8. **File path pattern** — All source files are at `MeetNotes/MeetNotes/MeetNotes/<Group>/<File>.swift`. Test files at `MeetNotes/MeetNotes/MeetNotesTests/<Group>/<File>.swift`.
9. **Existing stubs that this story might interact with** — `AppError.swift` (empty enum), `AppErrorState.swift` (@Observable @MainActor class). Database errors should eventually map to `AppError` cases, but that wiring is for a later story.

**Code patterns established in Story 1.1:**
- `@Observable @MainActor final class` for ViewModels
- `actor` for services (NotificationService)
- `Logger(subsystem: "com.kuamatzin.meet-notes", category: "<TypeName>")`
- Design tokens in `Color+DesignTokens.swift`
- `.environment()` injection from `MeetNotesApp`

### Git Intelligence

**Recent commits (2 total):**
- `a1e7def` — Add Xcode project structure with code review fixes
- `5d57653` — Initial commit: project scaffold, planning artifacts, and Story 1.1 Swift source files

**Patterns observed:**
- Commit messages use imperative mood, concise style
- Story 1.1 was implemented across two sessions (Linux for source files, macOS for Xcode/build verification)
- Code review fixes were committed separately
- All BMAD planning artifacts are committed in `_bmad-output/`

### Latest Tech Information

**GRDB.swift v7.10.0** (released Feb 15, 2026):
- Requires Swift 6.1+ / Xcode 16.3+
- Full Swift 6 strict concurrency support
- `DatabasePool` is `Sendable`
- Use GRDB's native `create(table:)` API for type-safe schema creation
- Raw SQL required for FTS5 `CREATE VIRTUAL TABLE` and triggers (no type-safe API)
- `DatabaseMigrator` supports `eraseDatabaseOnSchemaChange` flag for development

**macOS Keychain (Security.framework):**
- `SecItemAdd`, `SecItemCopyMatching`, `SecItemUpdate`, `SecItemDelete` — four core operations
- All functions are C-bridged and synchronous — safe to call from any thread
- `errSecItemNotFound` (-25300) — item doesn't exist (not an error for load/delete)
- `errSecDuplicateItem` (-25299) — item already exists (handle in save by falling back to update)
- `kSecAttrSynchronizable: kCFBooleanFalse` — explicitly disable iCloud Keychain sync if needed, but simply omitting the attribute also keeps it local-only (default is no sync)

### Project Structure Notes

**Alignment with project structure:**
- All new files go in `Infrastructure/Database/` and `Infrastructure/Secrets/` — these directories already exist with `.gitkeep` files from Story 1.1
- Test files go in `MeetNotesTests/Infrastructure/` — directory exists with `.gitkeep`
- Remove `.gitkeep` files from directories after adding real Swift files
- No files created outside the established project structure

**project-context.md rules relevant to this story:**
- Services throw typed domain errors using `throws(DomainError)` syntax — `SecretsStore` uses `SecretsStoreError`
- GRDB writes in service actors only — `AppDatabase` is the write entry point, consumed by actor services
- Explicit `Columns` enum required for every GRDB record struct
- Migrations are append-only; `v1` once registered is immutable
- `Logger` at file scope with category = exact type name
- Never use `print()` — `Logger` only
- One primary type per file
- `context7` MCP should be used for GRDB API verification before implementation

### References

- SQL schema: [Source: _bmad-output/planning-artifacts/architecture.md#Data Architecture]
- Migration strategy: [Source: _bmad-output/planning-artifacts/architecture.md#Migration Strategy]
- SecretsStore pattern: [Source: _bmad-output/planning-artifacts/architecture.md#Authentication & Security]
- LLMProviderKey enum: [Source: _bmad-output/planning-artifacts/architecture.md#Keychain-Only API Key Storage]
- Implementation sequence (AppDatabase → SecretsStore): [Source: _bmad-output/planning-artifacts/architecture.md#Decision Impact Analysis]
- Cross-component dependencies: [Source: _bmad-output/planning-artifacts/architecture.md#Cross-Component Dependencies]
- Record naming conventions: [Source: _bmad-output/planning-artifacts/architecture.md#Naming Patterns]
- GRDB rules (ValueObservation, write-ownership): [Source: _bmad-output/project-context.md#GRDB Rules]
- Testing rules (in-memory DB, Swift Testing): [Source: _bmad-output/project-context.md#Testing Rules]
- Story 1.2 acceptance criteria: [Source: _bmad-output/planning-artifacts/epics.md#Story 1.2]
- NFR-S1 (Keychain-only API keys): [Source: _bmad-output/planning-artifacts/prd.md#Security & Privacy]
- NFR-R2 (DatabasePool WAL for recording isolation): [Source: _bmad-output/planning-artifacts/prd.md#Reliability]
- FTS5 triggers: [Source: _bmad-output/project-context.md#GRDB Rules]
- Previous story learnings: [Source: _bmad-output/implementation-artifacts/1-1-xcode-project-initialization-runnable-shell.md#Dev Agent Record]

## Dev Agent Record

### Agent Model Used

Claude Opus 4.6

### Debug Log References

- SQLite `DEFAULT datetime('now')` requires parentheses: `DEFAULT (datetime('now'))` — GRDB's `.defaults(sql:)` does not auto-wrap function expressions
- `DatabasePool` cannot use `:memory:` path — WAL mode requires a real file; tests use `FileManager.default.temporaryDirectory` with UUID-named files
- GRDB derives table name from struct name (`Meeting` → `meeting`); must add `static let databaseTableName = "meetings"` for plural table names
- SwiftLint `identifier_name` rule requires 3+ char variables; renamed migration closure params from `db`/`t` to `database`/`table`
- SwiftLintBuildToolPlugin was incorrectly referenced as a Framework dependency in pbxproj (Story 1.1 bug); removed from Frameworks build phase and packageProductDependencies to unblock build
- Removed all `.gitkeep` placeholder files from source/test directories to fix "duplicate output file" build errors with PBXFileSystemSynchronizedRootGroup

### Completion Notes List

- All 9 tasks and subtasks completed
- All 13 tests pass (7 AppDatabase, 5 SecretsStore, 1 existing appLaunches)
- Zero SwiftLint violations on all new files
- Build succeeds with `SWIFT_STRICT_CONCURRENCY = complete` and zero warnings
- No API keys, passwords, or secrets in any committed file
- AppDatabase: GRDB DatabasePool + WAL mode with v1 migration (meetings, segments, settings, FTS5 with sync triggers)
- SecretsStore: Keychain-based API key storage with save/load/delete operations
- GRDB record structs: Meeting, TranscriptSegment, AppSetting with explicit CodingKeys and Columns enums

### Change Log

- 2026-03-03: Implemented Story 1.2 — AppDatabase with GRDB DatabasePool + WAL, v1 migration (meetings, segments, settings, FTS5), GRDB record structs (Meeting, TranscriptSegment, AppSetting), SecretsStore with Keychain API, comprehensive unit tests
- 2026-03-03: Fixed Story 1.1 bug — removed SwiftLintBuildToolPlugin from Frameworks phase and packageProductDependencies in pbxproj
- 2026-03-03: Removed all .gitkeep placeholder files from source tree to fix PBXFileSystemSynchronizedRootGroup duplicate resource errors
- 2026-03-03: **Code Review (Claude Opus 4.6)** — Fixed 7 issues (3H, 4M):
  - H1: Added missing `fts5TriggerOnUpdate` test for `segments_au` trigger
  - H2: Added `Columns` enum to `AppSetting` per architecture rules
  - H3: Fixed `SecretsStore.save` to explicitly check `errSecItemNotFound` vs other Keychain errors
  - M1: Added temp file cleanup (`defer`) to all database tests
  - M2: Updated project-context.md to document temp-file DB tests (not `:memory:`)
  - M3: Expanded `insertAndFetchMeeting` test to verify all 9 columns including date/optional fields
  - M4: Noted `@MainActor` default isolation concern for future stories (not a current bug)
  - 3 LOW issues accepted: SwiftLint disable comment, unnecessary Sendable on SecretsStore, makeShared visibility

### File List

**New files:**
- `MeetNotes/MeetNotes/MeetNotes/Infrastructure/Database/AppDatabase.swift`
- `MeetNotes/MeetNotes/MeetNotes/Infrastructure/Database/Meeting.swift`
- `MeetNotes/MeetNotes/MeetNotes/Infrastructure/Database/TranscriptSegment.swift`
- `MeetNotes/MeetNotes/MeetNotes/Infrastructure/Database/AppSetting.swift`
- `MeetNotes/MeetNotes/MeetNotes/Infrastructure/Secrets/SecretsStore.swift`
- `MeetNotes/MeetNotes/MeetNotesTests/Infrastructure/AppDatabaseTests.swift`
- `MeetNotes/MeetNotes/MeetNotesTests/Infrastructure/SecretsStoreTests.swift`

**Modified files:**
- `MeetNotes/MeetNotes/MeetNotes.xcodeproj/project.pbxproj` (removed SwiftLintBuildToolPlugin from Frameworks and packageProductDependencies)

**Deleted files:**
- `MeetNotes/MeetNotes/MeetNotes/Infrastructure/Database/.gitkeep`
- `MeetNotes/MeetNotes/MeetNotes/Infrastructure/Secrets/.gitkeep`
- `MeetNotes/MeetNotes/MeetNotes/Infrastructure/Permissions/.gitkeep`
- `MeetNotes/MeetNotes/MeetNotes/Features/MeetingDetail/.gitkeep`
- `MeetNotes/MeetNotes/MeetNotes/Features/MeetingList/.gitkeep`
- `MeetNotes/MeetNotes/MeetNotes/Features/Onboarding/.gitkeep`
- `MeetNotes/MeetNotes/MeetNotes/Features/Settings/.gitkeep`
- `MeetNotes/MeetNotes/MeetNotes/Features/Summary/.gitkeep`
- `MeetNotes/MeetNotes/MeetNotes/Features/Transcription/.gitkeep`
