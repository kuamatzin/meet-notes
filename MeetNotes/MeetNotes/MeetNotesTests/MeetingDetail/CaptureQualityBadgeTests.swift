import Foundation
import GRDB
import Testing
@testable import MeetNotes

@MainActor
struct CaptureQualityBadgeTests {
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
        audioQuality: Meeting.AudioQuality = .full,
        pipelineStatus: Meeting.PipelineStatus = .complete
    ) throws {
        let meeting = Meeting(
            id: id,
            title: "Test Meeting",
            startedAt: Date(),
            endedAt: Date().addingTimeInterval(3600),
            durationSeconds: 3600,
            audioQuality: audioQuality,
            summaryMd: nil,
            pipelineStatus: pipelineStatus,
            createdAt: Date()
        )
        try db.pool.write { database in
            try meeting.insert(database)
        }
    }

    private func shouldShowBadge(for quality: Meeting.AudioQuality) -> Bool {
        quality == .micOnly || quality == .partial
    }

    private func awaitMeeting(_ vm: MeetingDetailViewModel) async throws -> Meeting {
        for _ in 0..<20 {
            if let meeting = vm.meeting { return meeting }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw CaptureQualityBadgeTestError.timeout
    }

    enum CaptureQualityBadgeTestError: Error {
        case timeout
    }

    // MARK: - Badge shown for micOnly

    @Test func micOnlyQualityShowsBadge() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let (vm, _) = makeViewModel(database: database)
        try insertMeeting(database, id: "m1", audioQuality: .micOnly)
        vm.load(meetingID: "m1")

        let meeting = try await awaitMeeting(vm)
        #expect(meeting.audioQuality == .micOnly)
        #expect(shouldShowBadge(for: meeting.audioQuality))
    }

    // MARK: - Badge shown for partial

    @Test func partialQualityShowsBadge() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let (vm, _) = makeViewModel(database: database)
        try insertMeeting(database, id: "m1", audioQuality: .partial)
        vm.load(meetingID: "m1")

        let meeting = try await awaitMeeting(vm)
        #expect(meeting.audioQuality == .partial)
        #expect(shouldShowBadge(for: meeting.audioQuality))
    }

    // MARK: - Badge hidden for full

    @Test func fullQualityHidesBadge() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let (vm, _) = makeViewModel(database: database)
        try insertMeeting(database, id: "m1", audioQuality: .full)
        vm.load(meetingID: "m1")

        let meeting = try await awaitMeeting(vm)
        #expect(meeting.audioQuality == .full)
        #expect(!shouldShowBadge(for: meeting.audioQuality))
    }
}
