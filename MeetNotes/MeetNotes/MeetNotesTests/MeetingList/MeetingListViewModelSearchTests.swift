import Foundation
import GRDB
import Testing
@testable import MeetNotes

@MainActor
struct MeetingListViewModelSearchTests {
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
        id: String,
        title: String,
        startedAt: Date = Date(),
        segments: [(text: String, start: Double, end: Double)]
    ) throws {
        let meeting = Meeting(
            id: id,
            title: title,
            startedAt: startedAt,
            endedAt: nil,
            durationSeconds: nil,
            audioQuality: .full,
            summaryMd: nil,
            pipelineStatus: .complete,
            createdAt: startedAt
        )
        try db.pool.write { database in
            try meeting.insert(database)
            for seg in segments {
                var segment = TranscriptSegment(
                    id: nil,
                    meetingId: id,
                    startSeconds: seg.start,
                    endSeconds: seg.end,
                    text: seg.text,
                    confidence: 0.95
                )
                try segment.insert(database)
            }
        }
    }

    @Test func searchFiltersMeetingsToMatchingOnly() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let errorState = AppErrorState()
        let vm = MeetingListViewModel(database: database, appErrorState: errorState)
        vm.startObservation()

        try insertMeetingWithSegments(database, id: "m1", title: "Sprint Planning", segments: [
            (text: "We need to update the database schema", start: 0, end: 5)
        ])
        try insertMeetingWithSegments(database, id: "m2", title: "Design Review", segments: [
            (text: "The button color should be blue", start: 0, end: 5)
        ])

        try await Task.sleep(for: .milliseconds(200))
        #expect(vm.sections.flatMap(\.meetings).count == 2)

        vm.searchQuery = "database"
        try await Task.sleep(for: .milliseconds(1000))

        let matchedMeetings = vm.sections.flatMap(\.meetings)
        #expect(matchedMeetings.count == 1)
        #expect(matchedMeetings.first?.id == "m1")
    }

    @Test func clearSearchRestoresFullList() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let errorState = AppErrorState()
        let vm = MeetingListViewModel(database: database, appErrorState: errorState)
        vm.startObservation()

        try insertMeetingWithSegments(database, id: "m1", title: "Meeting 1", segments: [
            (text: "database discussion", start: 0, end: 5)
        ])
        try insertMeetingWithSegments(database, id: "m2", title: "Meeting 2", segments: [
            (text: "design review", start: 0, end: 5)
        ])

        try await Task.sleep(for: .milliseconds(200))

        vm.searchQuery = "database"
        try await Task.sleep(for: .milliseconds(1000))
        #expect(vm.sections.flatMap(\.meetings).count == 1)

        vm.searchQuery = ""
        try await Task.sleep(for: .milliseconds(200))
        #expect(vm.sections.flatMap(\.meetings).count == 2)
    }

    @Test func searchResultsContainMatchedSegmentIds() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let errorState = AppErrorState()
        let vm = MeetingListViewModel(database: database, appErrorState: errorState)
        vm.startObservation()

        try insertMeetingWithSegments(database, id: "m1", title: "Meeting", segments: [
            (text: "database schema update", start: 0, end: 5),
            (text: "unrelated topic", start: 5, end: 10)
        ])

        try await Task.sleep(for: .milliseconds(200))

        vm.searchQuery = "database"
        try await Task.sleep(for: .milliseconds(1000))

        #expect(!vm.searchResults.isEmpty)
        #expect(vm.searchResults["m1"] != nil)
        #expect(vm.searchResults["m1"]?.isEmpty == false)
    }

    @Test func noResultsShowsEmptySections() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let errorState = AppErrorState()
        let vm = MeetingListViewModel(database: database, appErrorState: errorState)
        vm.startObservation()

        try insertMeetingWithSegments(database, id: "m1", title: "Meeting", segments: [
            (text: "hello world", start: 0, end: 5)
        ])

        try await Task.sleep(for: .milliseconds(200))

        vm.searchQuery = "nonexistent"
        try await Task.sleep(for: .milliseconds(1000))

        #expect(vm.sections.isEmpty)
    }

    @Test func searchResultsClearedOnEmptyQuery() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let errorState = AppErrorState()
        let vm = MeetingListViewModel(database: database, appErrorState: errorState)
        vm.startObservation()

        try insertMeetingWithSegments(database, id: "m1", title: "Meeting", segments: [
            (text: "database topic", start: 0, end: 5)
        ])

        try await Task.sleep(for: .milliseconds(200))

        vm.searchQuery = "database"
        try await Task.sleep(for: .milliseconds(1000))
        #expect(!vm.searchResults.isEmpty)

        vm.searchQuery = ""
        try await Task.sleep(for: .milliseconds(200))
        #expect(vm.searchResults.isEmpty)
    }
}
