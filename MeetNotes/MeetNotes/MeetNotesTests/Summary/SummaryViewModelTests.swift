import Foundation
import GRDB
import Testing
@testable import MeetNotes

@MainActor
struct SummaryViewModelTests {
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

    private func insertSegments(in database: AppDatabase, meetingId: String = "test-meeting-1",
                                 count: Int = 3) async throws {
        try await database.pool.write { db in
            for i in 0..<count {
                var segment = TranscriptSegment(
                    id: nil,
                    meetingId: meetingId,
                    startSeconds: Double(i * 30),
                    endSeconds: Double(i * 30 + 29),
                    text: "Segment \(i) content about the meeting discussion.",
                    confidence: 0.95
                )
                try segment.insert(db)
            }
        }
    }

    private func insertMeeting(in database: AppDatabase, id: String = "test-meeting-1",
                                pipelineStatus: Meeting.PipelineStatus = .complete,
                                summaryMd: String? = nil) async throws {
        try await database.pool.write { db in
            var meeting = Meeting(
                id: id,
                title: "Test Meeting",
                startedAt: Date(),
                endedAt: nil,
                durationSeconds: nil,
                audioQuality: .full,
                summaryMd: summaryMd,
                pipelineStatus: pipelineStatus,
                createdAt: Date()
            )
            try meeting.insert(db)
        }
    }

    // MARK: - Completed summary loads from database

    @Test func completedSummaryLoadsFromDatabase() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let expectedSummary = "## Decisions\n- Approved budget\n\n## Action Items\n- Alice: send report\n\n## Key Topics\n- Q3 planning"
        try await insertMeeting(in: database, pipelineStatus: .complete, summaryMd: expectedSummary)

        let errorState = AppErrorState()
        let summaryService = SummaryService(database: database, appErrorState: errorState)
        let vm = MeetingDetailViewModel(database: database, appErrorState: errorState, summaryService: summaryService)

        vm.load(meetingID: "test-meeting-1")

        // Allow ValueObservation to fire
        try await Task.sleep(for: .milliseconds(100))

        #expect(vm.summaryMarkdown == expectedSummary)
        #expect(vm.isStreamingSummary == false)
    }

    // MARK: - Nil summary produces absent summary

    @Test func nilSummaryProducesNilMarkdown() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        try await insertMeeting(in: database, pipelineStatus: .complete, summaryMd: nil)

        let errorState = AppErrorState()
        let summaryService = SummaryService(database: database, appErrorState: errorState)
        let vm = MeetingDetailViewModel(database: database, appErrorState: errorState, summaryService: summaryService)

        vm.load(meetingID: "test-meeting-1")

        try await Task.sleep(for: .milliseconds(100))

        #expect(vm.summaryMarkdown == nil)
        #expect(vm.isSummarizing == false)
    }

    // MARK: - Streaming updates summaryMarkdown

    @Test func streamingChunksUpdateSummaryMarkdown() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        try await insertMeeting(in: database, pipelineStatus: .summarizing)
        try await insertSegments(in: database)

        let errorState = AppErrorState()
        let summaryService = SummaryService(database: database, appErrorState: errorState)
        let stub = StubLLMProvider()
        await stub.setStreamChunks(["## Decisions\n", "- First decision\n", "\n## Action Items\n- None"])
        await summaryService.setProviderOverride(stub)

        let vm = MeetingDetailViewModel(database: database, appErrorState: errorState, summaryService: summaryService)
        vm.load(meetingID: "test-meeting-1")

        // Wait for load() to register the streaming handler via its internal Task
        try await Task.sleep(for: .milliseconds(300))

        // Trigger summarization which will use the streaming handler
        await summaryService.summarize(meetingID: "test-meeting-1")

        try await Task.sleep(for: .milliseconds(200))

        // After summarization completes, the summary is saved to the database
        let meeting = try await database.pool.read { db in
            try Meeting.fetchOne(db, key: "test-meeting-1")
        }
        #expect(meeting?.summaryMd != nil)
        #expect(meeting?.summaryMd?.contains("Decisions") == true)
    }

    // MARK: - LLM provider label

    @Test func llmProviderLabelLoadsOllama() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        try await insertMeeting(in: database, pipelineStatus: .complete)
        await database.writeSetting(key: "llm_provider", value: "ollama")

        let errorState = AppErrorState()
        let summaryService = SummaryService(database: database, appErrorState: errorState)
        let vm = MeetingDetailViewModel(database: database, appErrorState: errorState, summaryService: summaryService)

        vm.load(meetingID: "test-meeting-1")

        try await Task.sleep(for: .milliseconds(200))

        #expect(vm.llmProviderLabel == "On-device")
    }

    @Test func llmProviderLabelLoadsCloud() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        try await insertMeeting(in: database, pipelineStatus: .complete)
        await database.writeSetting(key: "llm_provider", value: "cloud")

        let errorState = AppErrorState()
        let summaryService = SummaryService(database: database, appErrorState: errorState)
        let vm = MeetingDetailViewModel(database: database, appErrorState: errorState, summaryService: summaryService)

        vm.load(meetingID: "test-meeting-1")

        try await Task.sleep(for: .milliseconds(200))

        #expect(vm.llmProviderLabel == "Cloud")
    }
}
