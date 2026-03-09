import Foundation
import GRDB
import Testing
@testable import MeetNotes

@MainActor
struct MeetingDetailViewModelTests {
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

    private func makeViewModel(database: AppDatabase) -> (MeetingDetailViewModel, AppErrorState) {
        let errorState = AppErrorState()
        let summaryService = SummaryService(database: database, appErrorState: errorState)
        return (MeetingDetailViewModel(database: database, appErrorState: errorState, summaryService: summaryService), errorState)
    }

    private func insertMeeting(
        _ db: AppDatabase,
        id: String = "test-meeting",
        title: String = "Test Meeting",
        startedAt: Date = Date(),
        pipelineStatus: Meeting.PipelineStatus = .complete,
        audioQuality: Meeting.AudioQuality = .full
    ) throws {
        let meeting = Meeting(
            id: id,
            title: title,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(3600),
            durationSeconds: 3600,
            audioQuality: audioQuality,
            summaryMd: nil,
            pipelineStatus: pipelineStatus,
            createdAt: startedAt
        )
        try db.pool.write { database in
            try meeting.insert(database)
        }
    }

    private func insertSegment(
        _ db: AppDatabase,
        meetingId: String = "test-meeting",
        startSeconds: Double,
        endSeconds: Double,
        text: String,
        confidence: Double? = nil
    ) throws {
        var segment = TranscriptSegment(
            id: nil,
            meetingId: meetingId,
            startSeconds: startSeconds,
            endSeconds: endSeconds,
            text: text,
            confidence: confidence
        )
        try db.pool.write { database in
            try segment.insert(database)
        }
    }

    // MARK: - Initial State

    @Test func initialStateIsEmpty() throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let (vm, _) = makeViewModel(database: database)
        #expect(vm.meeting == nil)
        #expect(vm.segments.isEmpty)
        #expect(vm.isTranscribing == false)
    }

    // MARK: - Load Segments

    @Test func loadSegmentsPopulatesSegments() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let (vm, _) = makeViewModel(database: database)

        try insertMeeting(database, id: "m1")
        try insertSegment(database, meetingId: "m1", startSeconds: 0, endSeconds: 5, text: "Hello")
        try insertSegment(database, meetingId: "m1", startSeconds: 5, endSeconds: 10, text: "World")

        vm.load(meetingID: "m1")
        try await Task.sleep(for: .milliseconds(200))

        #expect(vm.segments.count == 2)
        #expect(vm.segments.first?.text == "Hello")
        #expect(vm.segments.last?.text == "World")
    }

    @Test func segmentsOrderedByStartSeconds() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let (vm, _) = makeViewModel(database: database)

        try insertMeeting(database, id: "m1")
        try insertSegment(database, meetingId: "m1", startSeconds: 10, endSeconds: 15, text: "Second")
        try insertSegment(database, meetingId: "m1", startSeconds: 0, endSeconds: 5, text: "First")

        vm.load(meetingID: "m1")
        try await Task.sleep(for: .milliseconds(200))

        #expect(vm.segments.first?.text == "First")
        #expect(vm.segments.last?.text == "Second")
    }

    // MARK: - Live Observation

    @Test func newSegmentsAppearLive() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let (vm, _) = makeViewModel(database: database)

        try insertMeeting(database, id: "m1")
        vm.load(meetingID: "m1")
        try await Task.sleep(for: .milliseconds(200))
        #expect(vm.segments.isEmpty)

        try insertSegment(database, meetingId: "m1", startSeconds: 0, endSeconds: 5, text: "New segment")
        try await Task.sleep(for: .milliseconds(200))
        #expect(vm.segments.count == 1)
        #expect(vm.segments.first?.text == "New segment")
    }

    // MARK: - Transcribing State

    @Test func transcribingStateReflectsPipelineStatus() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let (vm, _) = makeViewModel(database: database)

        try insertMeeting(database, id: "m1", pipelineStatus: .transcribing)
        vm.load(meetingID: "m1")
        try await Task.sleep(for: .milliseconds(200))

        #expect(vm.isTranscribing == true)
    }

    @Test func completePipelineStatusNotTranscribing() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let (vm, _) = makeViewModel(database: database)

        try insertMeeting(database, id: "m1", pipelineStatus: .complete)
        vm.load(meetingID: "m1")
        try await Task.sleep(for: .milliseconds(200))

        #expect(vm.isTranscribing == false)
    }

    // MARK: - Meeting Loading

    @Test func loadMeetingPopulatesMeetingProperty() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let (vm, _) = makeViewModel(database: database)

        try insertMeeting(database, id: "m1", title: "My Meeting")
        vm.load(meetingID: "m1")
        try await Task.sleep(for: .milliseconds(200))

        #expect(vm.meeting?.title == "My Meeting")
        #expect(vm.meeting?.id == "m1")
    }

    // MARK: - Switching Meetings

    @Test func loadingNewMeetingClearsPreviousData() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let (vm, _) = makeViewModel(database: database)

        try insertMeeting(database, id: "m1", title: "Meeting 1")
        try insertMeeting(database, id: "m2", title: "Meeting 2")
        try insertSegment(database, meetingId: "m1", startSeconds: 0, endSeconds: 5, text: "M1 Segment")
        try insertSegment(database, meetingId: "m2", startSeconds: 0, endSeconds: 5, text: "M2 Segment")

        vm.load(meetingID: "m1")
        try await Task.sleep(for: .milliseconds(200))
        #expect(vm.meeting?.title == "Meeting 1")
        #expect(vm.segments.first?.text == "M1 Segment")

        vm.load(meetingID: "m2")
        try await Task.sleep(for: .milliseconds(200))
        #expect(vm.meeting?.title == "Meeting 2")
        #expect(vm.segments.first?.text == "M2 Segment")
        #expect(vm.segments.count == 1)
    }

    // MARK: - Error Handling

    @Test func noErrorOnNormalLoad() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let (vm, errorState) = makeViewModel(database: database)

        try insertMeeting(database, id: "m1")
        vm.load(meetingID: "m1")
        try await Task.sleep(for: .milliseconds(200))

        #expect(errorState.current == nil)
    }

    // MARK: - Audio Quality Badge

    @Test func micOnlyAudioQualityDetected() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let (vm, _) = makeViewModel(database: database)

        try insertMeeting(database, id: "m1", audioQuality: .micOnly)
        vm.load(meetingID: "m1")
        try await Task.sleep(for: .milliseconds(200))

        #expect(vm.meeting?.audioQuality == .micOnly)
    }

    @Test func fullAudioQualityNoBadge() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let (vm, _) = makeViewModel(database: database)

        try insertMeeting(database, id: "m1", audioQuality: .full)
        vm.load(meetingID: "m1")
        try await Task.sleep(for: .milliseconds(200))

        #expect(vm.meeting?.audioQuality == .full)
    }
}
