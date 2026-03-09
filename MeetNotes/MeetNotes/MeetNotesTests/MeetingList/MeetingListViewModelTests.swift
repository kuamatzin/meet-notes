import Foundation
import GRDB
import Testing
@testable import MeetNotes

@MainActor
struct MeetingListViewModelTests {
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

    private func insertMeeting(
        _ db: AppDatabase,
        id: String = UUID().uuidString,
        title: String = "Test Meeting",
        startedAt: Date = Date(),
        durationSeconds: Double? = 3600,
        pipelineStatus: Meeting.PipelineStatus = .complete
    ) throws {
        let meeting = Meeting(
            id: id,
            title: title,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(durationSeconds ?? 0),
            durationSeconds: durationSeconds,
            audioQuality: .full,
            summaryMd: nil,
            pipelineStatus: pipelineStatus,
            createdAt: startedAt
        )
        try db.pool.write { database in
            try meeting.insert(database)
        }
    }

    // MARK: - Initial State

    @Test func initialStateHasEmptySections() throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let errorState = AppErrorState()
        let vm = MeetingListViewModel(database: database, appErrorState: errorState)
        #expect(vm.sections.isEmpty)
        #expect(vm.selectedMeetingID == nil)
        #expect(vm.searchQuery == "")
    }

    // MARK: - Temporal Grouping

    @Test func todayMeetingGroupedUnderToday() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let errorState = AppErrorState()
        let vm = MeetingListViewModel(database: database, appErrorState: errorState)
        vm.startObservation()

        try insertMeeting(database, title: "Today Meeting", startedAt: Date())

        try await Task.sleep(for: .milliseconds(200))

        let todaySection = vm.sections.first { $0.title == "Today" }
        #expect(todaySection != nil)
        #expect(todaySection?.meetings.count == 1)
        #expect(todaySection?.meetings.first?.title == "Today Meeting")
    }

    @Test func thisWeekMeetingGroupedUnderThisWeek() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let errorState = AppErrorState()
        let vm = MeetingListViewModel(database: database, appErrorState: errorState)
        vm.startObservation()

        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: Date())!
        // Only group as "This Week" if not today
        let isToday = Calendar.current.isDateInToday(twoDaysAgo)
        try insertMeeting(database, title: "Week Meeting", startedAt: twoDaysAgo)

        try await Task.sleep(for: .milliseconds(200))

        if !isToday {
            let weekSection = vm.sections.first { $0.title == "This Week" }
            #expect(weekSection != nil)
            #expect(weekSection?.meetings.count == 1)
        }
    }

    @Test func olderMeetingGroupedByMonthYear() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let errorState = AppErrorState()
        let vm = MeetingListViewModel(database: database, appErrorState: errorState)
        vm.startObservation()

        let twoMonthsAgo = Calendar.current.date(byAdding: .month, value: -2, to: Date())!
        try insertMeeting(database, title: "Old Meeting", startedAt: twoMonthsAgo)

        try await Task.sleep(for: .milliseconds(200))

        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        let expectedTitle = formatter.string(from: twoMonthsAgo)

        let olderSection = vm.sections.first { $0.title == expectedTitle }
        #expect(olderSection != nil)
        #expect(olderSection?.meetings.count == 1)
    }

    @Test func meetingsSortedByStartedAtDescending() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let errorState = AppErrorState()
        let vm = MeetingListViewModel(database: database, appErrorState: errorState)
        vm.startObservation()

        let now = Date()
        try insertMeeting(database, id: "older", title: "Older", startedAt: now.addingTimeInterval(-3600))
        try insertMeeting(database, id: "newer", title: "Newer", startedAt: now)

        try await Task.sleep(for: .milliseconds(200))

        let todaySection = vm.sections.first { $0.title == "Today" }
        #expect(todaySection != nil)
        #expect(todaySection?.meetings.first?.title == "Newer")
        #expect(todaySection?.meetings.last?.title == "Older")
    }

    // MARK: - Selection

    @Test func selectionUpdatesSelectedMeetingID() throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let errorState = AppErrorState()
        let vm = MeetingListViewModel(database: database, appErrorState: errorState)
        vm.selectedMeetingID = "test-id"
        #expect(vm.selectedMeetingID == "test-id")
    }

    // MARK: - Empty State

    @Test func emptyStateDetectedWhenNoMeetings() throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let errorState = AppErrorState()
        let vm = MeetingListViewModel(database: database, appErrorState: errorState)
        #expect(vm.sections.isEmpty)
    }

    // MARK: - Error Handling

    @Test func vmInitializesWithNoErrors() throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let errorState = AppErrorState()
        let vm = MeetingListViewModel(database: database, appErrorState: errorState)
        #expect(errorState.current == nil)
        _ = vm
    }

    @Test func deleteNonexistentMeetingDoesNotCrash() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let errorState = AppErrorState()
        let vm = MeetingListViewModel(database: database, appErrorState: errorState)
        await vm.deleteMeeting(id: "nonexistent-id")
        #expect(errorState.current == nil)
    }

    // MARK: - Rename Meeting

    @Test func renameMeetingUpdatesTitle() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let errorState = AppErrorState()
        let vm = MeetingListViewModel(database: database, appErrorState: errorState)
        vm.startObservation()

        try insertMeeting(database, id: "rename-me", title: "Old Title")

        try await Task.sleep(for: .milliseconds(200))
        let before = vm.sections.flatMap(\.meetings).first { $0.id == "rename-me" }
        #expect(before?.title == "Old Title")

        await vm.renameMeeting(id: "rename-me", newTitle: "New Title")

        try await Task.sleep(for: .milliseconds(200))
        let after = vm.sections.flatMap(\.meetings).first { $0.id == "rename-me" }
        #expect(after?.title == "New Title")
    }

    // MARK: - Pipeline Status

    @Test func meetingsPreservePipelineStatus() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let errorState = AppErrorState()
        let vm = MeetingListViewModel(database: database, appErrorState: errorState)
        vm.startObservation()

        try insertMeeting(database, id: "rec", title: "Recording", pipelineStatus: .recording)
        try insertMeeting(database, id: "trans", title: "Transcribing", pipelineStatus: .transcribing)
        try insertMeeting(database, id: "done", title: "Complete", pipelineStatus: .complete)

        try await Task.sleep(for: .milliseconds(200))

        let allMeetings = vm.sections.flatMap(\.meetings)
        let recording = allMeetings.first { $0.id == "rec" }
        let transcribing = allMeetings.first { $0.id == "trans" }
        let complete = allMeetings.first { $0.id == "done" }

        #expect(recording?.pipelineStatus == .recording)
        #expect(transcribing?.pipelineStatus == .transcribing)
        #expect(complete?.pipelineStatus == .complete)
    }

    // MARK: - Delete Meeting

    @Test func deleteMeetingRemovesFromDatabase() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let errorState = AppErrorState()
        let vm = MeetingListViewModel(database: database, appErrorState: errorState)
        vm.startObservation()

        try insertMeeting(database, id: "to-delete", title: "Delete Me")

        try await Task.sleep(for: .milliseconds(200))
        #expect(vm.sections.flatMap(\.meetings).count == 1)

        await vm.deleteMeeting(id: "to-delete")

        try await Task.sleep(for: .milliseconds(200))
        #expect(vm.sections.flatMap(\.meetings).isEmpty)
    }
}
