import Foundation
import Testing
import GRDB
@testable import MeetNotes

struct AppDatabaseSearchTests {
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

    private func insertMeetingWithSegments(
        _ db: AppDatabase,
        meetingId: String,
        title: String,
        segments: [(text: String, start: Double, end: Double)]
    ) throws {
        let now = Date()
        let meeting = Meeting(
            id: meetingId,
            title: title,
            startedAt: now,
            endedAt: nil,
            durationSeconds: nil,
            audioQuality: .full,
            summaryMd: nil,
            pipelineStatus: .complete,
            createdAt: now
        )

        try db.pool.write { database in
            try meeting.insert(database)
            for seg in segments {
                var segment = TranscriptSegment(
                    id: nil,
                    meetingId: meetingId,
                    startSeconds: seg.start,
                    endSeconds: seg.end,
                    text: seg.text,
                    confidence: 0.95
                )
                try segment.insert(database)
            }
        }
    }

    // MARK: - FTS5 Search Round-Trip

    @Test func searchReturnsMatchingSegments() async throws {
        let (appDB, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        try insertMeetingWithSegments(appDB, meetingId: "m1", title: "Sprint Planning", segments: [
            (text: "We need to decide on the database schema", start: 0, end: 5),
            (text: "The API endpoint should return JSON", start: 5, end: 10)
        ])

        let results = try await appDB.searchSegments(query: "database")
        #expect(!results.isEmpty)
        #expect(results[0].meetingId == "m1")
    }

    @Test func searchReturnsEmptyForNoMatch() async throws {
        let (appDB, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        try insertMeetingWithSegments(appDB, meetingId: "m1", title: "Meeting", segments: [
            (text: "Hello world", start: 0, end: 5)
        ])

        let results = try await appDB.searchSegments(query: "nonexistent")
        #expect(results.isEmpty)
    }

    @Test func searchPorterStemmingMatchesVariants() async throws {
        let (appDB, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        try insertMeetingWithSegments(appDB, meetingId: "m1", title: "Decision Meeting", segments: [
            (text: "We decided to go with option A", start: 0, end: 5),
            (text: "Let us decide tomorrow", start: 5, end: 10),
            (text: "They are deciding right now", start: 10, end: 15)
        ])

        let results = try await appDB.searchSegments(query: "decided")
        #expect(results.count == 3)
    }

    @Test func searchGroupsResultsByMeetingId() async throws {
        let (appDB, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        try insertMeetingWithSegments(appDB, meetingId: "m1", title: "Meeting 1", segments: [
            (text: "We need a new database", start: 0, end: 5)
        ])
        try insertMeetingWithSegments(appDB, meetingId: "m2", title: "Meeting 2", segments: [
            (text: "Database migration is complete", start: 0, end: 5)
        ])

        let results = try await appDB.searchSegments(query: "database")
        let meetingIds = Set(results.map(\.meetingId))
        #expect(meetingIds.count == 2)
        #expect(meetingIds.contains("m1"))
        #expect(meetingIds.contains("m2"))
    }

    @Test func searchReturnsSnippetWithMarkTags() async throws {
        let (appDB, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        try insertMeetingWithSegments(appDB, meetingId: "m1", title: "Meeting", segments: [
            (text: "The database schema needs updating", start: 0, end: 5)
        ])

        let results = try await appDB.searchSegments(query: "database")
        #expect(!results.isEmpty)
        #expect(results[0].snippet.contains("<mark>"))
        #expect(results[0].snippet.contains("</mark>"))
    }

    @Test func searchReturnsSegmentId() async throws {
        let (appDB, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        try insertMeetingWithSegments(appDB, meetingId: "m1", title: "Meeting", segments: [
            (text: "Testing segment ID return", start: 0, end: 5)
        ])

        let results = try await appDB.searchSegments(query: "testing")
        #expect(!results.isEmpty)
        #expect(results[0].segmentId > 0)
    }

    @Test func searchWithEmptyQueryReturnsEmpty() async throws {
        let (appDB, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        try insertMeetingWithSegments(appDB, meetingId: "m1", title: "Meeting", segments: [
            (text: "Some content here", start: 0, end: 5)
        ])

        let results = try await appDB.searchSegments(query: "")
        #expect(results.isEmpty)
    }
}
