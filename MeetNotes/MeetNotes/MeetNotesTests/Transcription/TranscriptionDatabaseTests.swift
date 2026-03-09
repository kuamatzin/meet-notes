import Foundation
import GRDB
import Testing
@testable import MeetNotes

struct TranscriptionDatabaseTests {
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

    // MARK: - Pipeline Status Transitions

    @Test func pipelineStatusTransitionsRecordingToTranscribing() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let meetingID = UUID().uuidString
        let meeting = Meeting(
            id: meetingID,
            title: "Pipeline Test",
            startedAt: Date(),
            endedAt: nil,
            durationSeconds: nil,
            audioQuality: .full,
            summaryMd: nil,
            pipelineStatus: .recording,
            createdAt: Date()
        )

        try await database.pool.write { db in
            try meeting.insert(db)
            try db.execute(
                sql: "UPDATE meetings SET pipeline_status = ? WHERE id = ?",
                arguments: [Meeting.PipelineStatus.transcribing.rawValue, meetingID]
            )
        }

        let fetched = try await database.pool.read { db in
            try Meeting.fetchOne(db, key: meetingID)
        }
        #expect(fetched?.pipelineStatus == .transcribing)
    }

    @Test func pipelineStatusTransitionsTranscribingToTranscribed() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let meetingID = UUID().uuidString
        let meeting = Meeting(
            id: meetingID,
            title: "Pipeline Test",
            startedAt: Date(),
            endedAt: nil,
            durationSeconds: nil,
            audioQuality: .full,
            summaryMd: nil,
            pipelineStatus: .transcribing,
            createdAt: Date()
        )

        try await database.pool.write { db in
            try meeting.insert(db)
            try db.execute(
                sql: "UPDATE meetings SET pipeline_status = ? WHERE id = ?",
                arguments: [Meeting.PipelineStatus.transcribed.rawValue, meetingID]
            )
        }

        let fetched = try await database.pool.read { db in
            try Meeting.fetchOne(db, key: meetingID)
        }
        #expect(fetched?.pipelineStatus == .transcribed)
    }

    @Test func pipelineStatusTransitionsToComplete() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let meetingID = UUID().uuidString
        let meeting = Meeting(
            id: meetingID,
            title: "Pipeline Test",
            startedAt: Date(),
            endedAt: nil,
            durationSeconds: nil,
            audioQuality: .full,
            summaryMd: nil,
            pipelineStatus: .transcribed,
            createdAt: Date()
        )

        try await database.pool.write { db in
            try meeting.insert(db)
            try db.execute(
                sql: "UPDATE meetings SET pipeline_status = ? WHERE id = ?",
                arguments: [Meeting.PipelineStatus.complete.rawValue, meetingID]
            )
        }

        let fetched = try await database.pool.read { db in
            try Meeting.fetchOne(db, key: meetingID)
        }
        #expect(fetched?.pipelineStatus == .complete)
    }

    // MARK: - Segment Incremental Saves + FTS5

    @Test func incrementalSegmentSavesTriggerFTS5Indexing() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let meetingID = UUID().uuidString
        let meeting = Meeting(
            id: meetingID,
            title: "Segment Test",
            startedAt: Date(),
            endedAt: nil,
            durationSeconds: nil,
            audioQuality: .full,
            summaryMd: nil,
            pipelineStatus: .transcribing,
            createdAt: Date()
        )

        try await database.pool.write { db in
            try meeting.insert(db)
        }

        // Simulate incremental segment saves
        let segments = [
            ("Hello everyone, welcome to the meeting", 0.0, 5.0),
            ("Today we'll discuss the quarterly results", 5.0, 10.0),
            ("Revenue increased by twenty percent", 10.0, 15.0),
        ]

        for (text, start, end) in segments {
            try await database.pool.write { db in
                var segment = TranscriptSegment(
                    id: nil,
                    meetingId: meetingID,
                    startSeconds: start,
                    endSeconds: end,
                    text: text,
                    confidence: 0.9
                )
                try segment.insert(db)
            }
        }

        // Verify segment count
        let segmentCount = try await database.pool.read { db in
            try TranscriptSegment
                .filter(TranscriptSegment.Columns.meetingId == meetingID)
                .fetchCount(db)
        }
        #expect(segmentCount == 3)

        // Verify FTS5 indexing
        let ftsQuarterlyCount = try await database.pool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM segments_fts WHERE segments_fts MATCH 'quarterly'")
        }
        #expect(ftsQuarterlyCount == 1)

        let ftsRevenueCount = try await database.pool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM segments_fts WHERE segments_fts MATCH 'revenue'")
        }
        #expect(ftsRevenueCount == 1)
    }

    // MARK: - Audio Quality Persistence

    @Test func meetingRecordStoresAudioQuality() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        for quality in [Meeting.AudioQuality.full, .micOnly, .partial] {
            let meetingID = UUID().uuidString
            let meeting = Meeting(
                id: meetingID,
                title: "Quality Test",
                startedAt: Date(),
                endedAt: Date(),
                durationSeconds: 300,
                audioQuality: quality,
                summaryMd: nil,
                pipelineStatus: .recording,
                createdAt: Date()
            )

            try await database.pool.write { db in
                try meeting.insert(db)
            }

            let fetched = try await database.pool.read { db in
                try Meeting.fetchOne(db, key: meetingID)
            }
            #expect(fetched?.audioQuality == quality)
        }
    }

    // MARK: - Crash Recovery Query

    @Test func queryForTranscribingMeetingsFindsStaleOnes() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        // Insert meetings with various statuses
        let statuses: [(String, Meeting.PipelineStatus)] = [
            (UUID().uuidString, .recording),
            (UUID().uuidString, .transcribing),
            (UUID().uuidString, .transcribing),
            (UUID().uuidString, .complete),
            (UUID().uuidString, .failed),
        ]

        for (id, status) in statuses {
            let meeting = Meeting(
                id: id,
                title: "Status \(status.rawValue)",
                startedAt: Date(),
                endedAt: nil,
                durationSeconds: nil,
                audioQuality: .full,
                summaryMd: nil,
                pipelineStatus: status,
                createdAt: Date()
            )
            try await database.pool.write { db in
                try meeting.insert(db)
            }
        }

        let staleMeetings = try await database.pool.read { db in
            try Meeting
                .filter(Meeting.Columns.pipelineStatus == Meeting.PipelineStatus.transcribing.rawValue)
                .fetchAll(db)
        }

        #expect(staleMeetings.count == 2)
        for meeting in staleMeetings {
            #expect(meeting.pipelineStatus == .transcribing)
        }
    }
}
