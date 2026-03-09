import Foundation
import GRDB
import os

private let logger = Logger(subsystem: "com.kuamatzin.meet-notes", category: "AppDatabase")

final class AppDatabase: Sendable {
    let pool: DatabasePool

    init(_ pool: DatabasePool) throws {
        self.pool = pool
        var migrator = DatabaseMigrator()
        migrator.eraseDatabaseOnSchemaChange = false
        registerMigrations(&migrator)
        try migrator.migrate(pool)
    }

    // swiftlint:disable:next function_body_length
    private func registerMigrations(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v1") { database in
            // meetings table
            try database.create(table: "meetings") { table in
                table.primaryKey("id", .text)
                table.column("title", .text).notNull().defaults(to: "")
                table.column("started_at", .datetime).notNull()
                table.column("ended_at", .datetime)
                table.column("duration_seconds", .double)
                table.column("audio_quality", .text).notNull().defaults(to: "full")
                table.column("summary_md", .text)
                table.column("pipeline_status", .text).notNull().defaults(to: "recording")
                table.column("created_at", .datetime).notNull().defaults(sql: "(datetime('now'))")
            }

            // segments table
            try database.create(table: "segments") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("meeting_id", .text).notNull()
                    .references("meetings", onDelete: .cascade)
                table.column("start_seconds", .double).notNull()
                table.column("end_seconds", .double).notNull()
                table.column("text", .text).notNull()
                table.column("confidence", .double)
            }

            // settings table
            try database.create(table: "settings") { table in
                table.primaryKey("key", .text)
                table.column("value", .text).notNull()
            }

            // FTS5 virtual table
            try database.execute(sql: """
                CREATE VIRTUAL TABLE segments_fts USING fts5(
                    text,
                    content='segments',
                    content_rowid='id',
                    tokenize='porter unicode61'
                )
                """)

            // FTS5 sync triggers
            try database.execute(sql: """
                CREATE TRIGGER segments_ai AFTER INSERT ON segments BEGIN
                    INSERT INTO segments_fts(rowid, text) VALUES (new.id, new.text);
                END
                """)
            try database.execute(sql: """
                CREATE TRIGGER segments_ad AFTER DELETE ON segments BEGIN
                    INSERT INTO segments_fts(segments_fts, rowid, text) VALUES ('delete', old.id, old.text);
                END
                """)
            try database.execute(sql: """
                CREATE TRIGGER segments_au AFTER UPDATE ON segments BEGIN
                    INSERT INTO segments_fts(segments_fts, rowid, text) VALUES ('delete', old.id, old.text);
                    INSERT INTO segments_fts(rowid, text) VALUES (new.id, new.text);
                END
                """)
        }
    }

    static func makeShared() throws -> AppDatabase {
        let url = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("meet-notes", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let dbURL = url.appendingPathComponent("meetings.db")
        logger.info("Opening database at \(dbURL.path)")
        let pool = try DatabasePool(path: dbURL.path)
        return try AppDatabase(pool)
    }

    func readSetting(key: String) async -> String? {
        try? await pool.read { db in
            try AppSetting
                .filter(AppSetting.Columns.key == key)
                .fetchOne(db)?
                .value
        }
    }

    func writeSetting(key: String, value: String) async {
        try? await pool.write { db in
            var setting = AppSetting(key: key, value: value)
            try setting.save(db, onConflict: .replace)
        }
    }

    func deleteMeeting(id: String) async throws {
        try await pool.write { db in
            try db.execute(sql: "DELETE FROM meetings WHERE id = ?", arguments: [id])
        }
    }

    func renameMeeting(id: String, newTitle: String) async throws {
        try await pool.write { db in
            try db.execute(sql: "UPDATE meetings SET title = ? WHERE id = ?", arguments: [newTitle, id])
        }
    }

    struct SearchResult: Sendable {
        let meetingId: String
        let segmentId: Int64
        let snippet: String
    }

    func searchSegments(query: String) async throws -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        return try await pool.read { db in
            let sanitized = trimmed
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            guard !sanitized.isEmpty else { return [] }

            let ftsQuery = sanitized

            let sql = """
                SELECT segments.meeting_id, segments.id,
                       snippet(segments_fts, 0, '<mark>', '</mark>', '...', 32) AS snippet
                FROM segments_fts
                JOIN segments ON segments.id = segments_fts.rowid
                WHERE segments_fts MATCH ?
                ORDER BY rank
                """

            let rows = try Row.fetchAll(db, sql: sql, arguments: [ftsQuery])
            return rows.map { row in
                SearchResult(
                    meetingId: row["meeting_id"],
                    segmentId: row["id"],
                    snippet: row["snippet"]
                )
            }
        }
    }

    static let shared: AppDatabase = {
        do {
            return try makeShared()
        } catch {
            fatalError("Database initialization failed: \(error)")
        }
    }()
}
