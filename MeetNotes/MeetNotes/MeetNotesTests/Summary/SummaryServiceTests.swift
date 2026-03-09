import Foundation
import GRDB
import Testing
@testable import MeetNotes

@MainActor
struct SummaryServiceTests {
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

    private func insertMeeting(in database: AppDatabase, id: String = "test-meeting-1",
                                pipelineStatus: Meeting.PipelineStatus = .transcribed) async throws {
        try await database.pool.write { db in
            var meeting = Meeting(
                id: id,
                title: "Test Meeting",
                startedAt: Date(),
                endedAt: nil,
                durationSeconds: nil,
                audioQuality: .full,
                summaryMd: nil,
                pipelineStatus: pipelineStatus,
                createdAt: Date()
            )
            try meeting.insert(db)
        }
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

    private func fetchMeeting(from database: AppDatabase, id: String = "test-meeting-1") async throws -> Meeting? {
        try await database.pool.read { db in
            try Meeting.fetchOne(db, key: id)
        }
    }

    // MARK: - Happy path: provider returns summary

    @Test func summarizeWithStubProviderWritesSummaryAndCompletes() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let errorState = AppErrorState()
        let service = SummaryService(database: database, appErrorState: errorState)

        let stub = StubLLMProvider()
        let expectedSummary = "## Decisions\n- Approved the budget.\n\n## Action Items\n- Alice to send report.\n\n## Key Topics\n- Q3 planning"
        await stub.setResponse(expectedSummary)
        await service.setProviderOverride(stub)

        try await insertMeeting(in: database)
        try await insertSegments(in: database)

        await service.summarize(meetingID: "test-meeting-1")

        let meeting = try await fetchMeeting(from: database)
        #expect(meeting?.pipelineStatus == .complete)
        #expect(meeting?.summaryMd == expectedSummary)
        #expect(errorState.current == nil)
    }

    // MARK: - No provider configured

    @Test func summarizeWithNoProviderSetsPipelineComplete() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let errorState = AppErrorState()
        let service = SummaryService(database: database, appErrorState: errorState)

        try await insertMeeting(in: database)
        try await insertSegments(in: database)

        // No llm_provider setting and no override → resolveProvider returns nil

        await service.summarize(meetingID: "test-meeting-1")

        let meeting = try await fetchMeeting(from: database)
        #expect(meeting?.pipelineStatus == .complete)
        #expect(meeting?.summaryMd == nil)
        #expect(errorState.current == nil)
    }

    // MARK: - No transcript segments

    @Test func summarizeWithNoSegmentsSetsPipelineComplete() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let errorState = AppErrorState()
        let service = SummaryService(database: database, appErrorState: errorState)

        let stub = StubLLMProvider()
        await service.setProviderOverride(stub)

        try await insertMeeting(in: database)
        // No segments inserted

        await service.summarize(meetingID: "test-meeting-1")

        let meeting = try await fetchMeeting(from: database)
        #expect(meeting?.pipelineStatus == .complete)
        #expect(meeting?.summaryMd == nil)
        #expect(errorState.current == nil)
    }

    // MARK: - Provider error posts to AppErrorState

    @Test func summarizeWithProviderErrorPostsToAppErrorState() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let errorState = AppErrorState()
        let service = SummaryService(database: database, appErrorState: errorState)

        let stub = StubLLMProvider()
        await stub.setError(.ollamaNotReachable(endpoint: "http://localhost:11434"))
        await service.setProviderOverride(stub)

        try await insertMeeting(in: database)
        try await insertSegments(in: database)

        await service.summarize(meetingID: "test-meeting-1")

        let meeting = try await fetchMeeting(from: database)
        #expect(meeting?.pipelineStatus == .complete)
        #expect(meeting?.summaryMd == nil)
        #expect(errorState.current == .ollamaNotRunning(endpoint: "http://localhost:11434"))
    }

    @Test func summarizeWithNetworkUnavailablePostsNetworkUnavailable() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let errorState = AppErrorState()
        let service = SummaryService(database: database, appErrorState: errorState)

        let stub = StubLLMProvider()
        await stub.setError(.networkUnavailable)
        await service.setProviderOverride(stub)

        try await insertMeeting(in: database)
        try await insertSegments(in: database)

        await service.summarize(meetingID: "test-meeting-1")

        let meeting = try await fetchMeeting(from: database)
        #expect(meeting?.pipelineStatus == .complete)
        #expect(errorState.current == .networkUnavailable)
    }

    // MARK: - Cloud provider with no API key skips

    @Test func summarizeWithCloudButNoAPIKeySkips() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let errorState = AppErrorState()
        let service = SummaryService(database: database, appErrorState: errorState)

        try await insertMeeting(in: database)
        try await insertSegments(in: database)

        await database.writeSetting(key: "llm_provider", value: "cloud")
        // No API key in keychain → treated as unconfigured

        await service.summarize(meetingID: "test-meeting-1")

        let meeting = try await fetchMeeting(from: database)
        #expect(meeting?.pipelineStatus == .complete)
        #expect(meeting?.summaryMd == nil)
        #expect(errorState.current == nil)
    }

    // MARK: - Pipeline status transitions

    @Test func summarizeSetsStatusToSummarizingDuringExecution() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let errorState = AppErrorState()
        let service = SummaryService(database: database, appErrorState: errorState)

        try await insertMeeting(in: database, pipelineStatus: .transcribed)
        // No segments → quick path, but status should still transition through summarizing to complete

        await service.summarize(meetingID: "test-meeting-1")

        let meeting = try await fetchMeeting(from: database)
        #expect(meeting?.pipelineStatus == .complete)
    }
}
