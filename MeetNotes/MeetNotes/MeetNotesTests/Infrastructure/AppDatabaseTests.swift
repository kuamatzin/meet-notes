import Foundation
import Testing
import GRDB
@testable import MeetNotes

struct AppDatabaseTests {
    private func makeDatabase() throws -> (AppDatabase, String) {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent(UUID().uuidString + ".db").path
        let pool = try DatabasePool(path: dbPath)
        let database = try AppDatabase(pool)
        return (database, dbPath)
    }

    private func cleanupDatabase(atPath path: String) {
        try? FileManager.default.removeItem(atPath: path)
        try? FileManager.default.removeItem(atPath: path + "-wal")
        try? FileManager.default.removeItem(atPath: path + "-shm")
    }

    @Test func migrationCreatesAllTables() throws {
        let (appDB, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }
        try appDB.pool.read { database in
            let meetingsExists = try database.tableExists("meetings")
            let segmentsExists = try database.tableExists("segments")
            let settingsExists = try database.tableExists("settings")
            let ftsExists = try database.tableExists("segments_fts")
            #expect(meetingsExists)
            #expect(segmentsExists)
            #expect(settingsExists)
            #expect(ftsExists)
        }
    }

    @Test func idempotentMigration() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent(UUID().uuidString + ".db").path
        defer {
            try? FileManager.default.removeItem(atPath: dbPath)
            try? FileManager.default.removeItem(atPath: dbPath + "-wal")
            try? FileManager.default.removeItem(atPath: dbPath + "-shm")
        }
        let pool = try DatabasePool(path: dbPath)
        _ = try AppDatabase(pool)
        _ = try AppDatabase(pool)
    }

    @Test func insertAndFetchMeeting() throws {
        let (appDB, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }
        let now = Date()
        let endTime = now.addingTimeInterval(3600)
        let meeting = Meeting(
            id: "test-meeting-1",
            title: "Test Meeting",
            startedAt: now,
            endedAt: endTime,
            durationSeconds: 3600.0,
            audioQuality: .full,
            summaryMd: "Test summary",
            pipelineStatus: .recording,
            createdAt: now
        )

        try appDB.pool.write { database in
            try meeting.insert(database)
        }

        let fetched = try appDB.pool.read { database in
            try Meeting.fetchOne(database, key: "test-meeting-1")
        }

        #expect(fetched != nil)
        #expect(fetched?.id == "test-meeting-1")
        #expect(fetched?.title == "Test Meeting")
        #expect(fetched?.audioQuality == .full)
        #expect(fetched?.pipelineStatus == .recording)
        #expect(fetched?.durationSeconds == 3600.0)
        #expect(fetched?.summaryMd == "Test summary")
        #expect(fetched?.endedAt != nil)
        #expect(fetched?.startedAt != nil)
        #expect(fetched?.createdAt != nil)
    }

    @Test func fts5TriggerOnInsert() throws {
        let (appDB, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }
        let now = Date()
        let meeting = Meeting(
            id: "meeting-fts",
            title: "FTS Test",
            startedAt: now,
            endedAt: nil,
            durationSeconds: nil,
            audioQuality: .full,
            summaryMd: nil,
            pipelineStatus: .recording,
            createdAt: now
        )

        try appDB.pool.write { database in
            try meeting.insert(database)
            var segment = TranscriptSegment(
                id: nil,
                meetingId: "meeting-fts",
                startSeconds: 0.0,
                endSeconds: 5.0,
                text: "hello world testing",
                confidence: 0.95
            )
            try segment.insert(database)
        }

        let ftsCount = try appDB.pool.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM segments_fts WHERE segments_fts MATCH 'hello'")
        }
        #expect(ftsCount == 1)
    }

    @Test func fts5TriggerOnDelete() throws {
        let (appDB, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }
        let now = Date()
        let meeting = Meeting(
            id: "meeting-del",
            title: "Delete Test",
            startedAt: now,
            endedAt: nil,
            durationSeconds: nil,
            audioQuality: .full,
            summaryMd: nil,
            pipelineStatus: .recording,
            createdAt: now
        )

        try appDB.pool.write { database in
            try meeting.insert(database)
            var segment = TranscriptSegment(
                id: nil,
                meetingId: "meeting-del",
                startSeconds: 0.0,
                endSeconds: 3.0,
                text: "removable content",
                confidence: 0.9
            )
            try segment.insert(database)
        }

        var ftsCount = try appDB.pool.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM segments_fts WHERE segments_fts MATCH 'removable'")
        }
        #expect(ftsCount == 1)

        try appDB.pool.write { database in
            try database.execute(sql: "DELETE FROM segments WHERE meeting_id = 'meeting-del'")
        }

        ftsCount = try appDB.pool.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM segments_fts WHERE segments_fts MATCH 'removable'")
        }
        #expect(ftsCount == 0)
    }

    @Test func cascadeDeleteSegments() throws {
        let (appDB, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }
        let now = Date()
        let meeting = Meeting(
            id: "meeting-cascade",
            title: "Cascade Test",
            startedAt: now,
            endedAt: nil,
            durationSeconds: nil,
            audioQuality: .full,
            summaryMd: nil,
            pipelineStatus: .recording,
            createdAt: now
        )

        try appDB.pool.write { database in
            try meeting.insert(database)
            var seg1 = TranscriptSegment(
                id: nil,
                meetingId: "meeting-cascade",
                startSeconds: 0.0,
                endSeconds: 2.0,
                text: "segment one",
                confidence: 0.8
            )
            try seg1.insert(database)
            var seg2 = TranscriptSegment(
                id: nil,
                meetingId: "meeting-cascade",
                startSeconds: 2.0,
                endSeconds: 4.0,
                text: "segment two",
                confidence: 0.85
            )
            try seg2.insert(database)
        }

        var segmentCount = try appDB.pool.read { database in
            try TranscriptSegment
                .filter(TranscriptSegment.Columns.meetingId == "meeting-cascade")
                .fetchCount(database)
        }
        #expect(segmentCount == 2)

        try appDB.pool.write { database in
            try database.execute(sql: "DELETE FROM meetings WHERE id = 'meeting-cascade'")
        }

        segmentCount = try appDB.pool.read { database in
            try TranscriptSegment
                .filter(TranscriptSegment.Columns.meetingId == "meeting-cascade")
                .fetchCount(database)
        }
        #expect(segmentCount == 0)
    }

    @Test func fts5TriggerOnUpdate() throws {
        let (appDB, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }
        let now = Date()
        let meeting = Meeting(
            id: "meeting-upd",
            title: "Update Test",
            startedAt: now,
            endedAt: nil,
            durationSeconds: nil,
            audioQuality: .full,
            summaryMd: nil,
            pipelineStatus: .recording,
            createdAt: now
        )

        try appDB.pool.write { database in
            try meeting.insert(database)
            var segment = TranscriptSegment(
                id: nil,
                meetingId: "meeting-upd",
                startSeconds: 0.0,
                endSeconds: 5.0,
                text: "original phrase",
                confidence: 0.9
            )
            try segment.insert(database)
        }

        var ftsCount = try appDB.pool.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM segments_fts WHERE segments_fts MATCH 'original'")
        }
        #expect(ftsCount == 1)

        try appDB.pool.write { database in
            try database.execute(sql: "UPDATE segments SET text = 'updated phrase' WHERE meeting_id = 'meeting-upd'")
        }

        ftsCount = try appDB.pool.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM segments_fts WHERE segments_fts MATCH 'original'")
        }
        #expect(ftsCount == 0)

        ftsCount = try appDB.pool.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM segments_fts WHERE segments_fts MATCH 'updated'")
        }
        #expect(ftsCount == 1)
    }

    @Test func insertAndFetchAppSetting() throws {
        let (appDB, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }
        let setting = AppSetting(key: "whisper_model", value: "base")

        try appDB.pool.write { database in
            try setting.insert(database)
        }

        let fetched = try appDB.pool.read { database in
            try AppSetting.fetchOne(database, key: "whisper_model")
        }
        #expect(fetched?.value == "base")
    }
}
