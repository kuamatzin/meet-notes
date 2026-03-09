import Foundation
import GRDB
import Testing
@testable import MeetNotes

@MainActor
struct SummaryErrorMappingTests {
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

    private func insertMeetingWithSegments(in database: AppDatabase, id: String = "test-meeting-1") async throws {
        try await database.pool.write { db in
            var meeting = Meeting(
                id: id,
                title: "Test Meeting",
                startedAt: Date(),
                endedAt: nil,
                durationSeconds: nil,
                audioQuality: .full,
                summaryMd: nil,
                pipelineStatus: .transcribed,
                createdAt: Date()
            )
            try meeting.insert(db)

            var segment = TranscriptSegment(
                id: nil,
                meetingId: id,
                startSeconds: 0,
                endSeconds: 30,
                text: "Test segment content.",
                confidence: 0.95
            )
            try segment.insert(db)
        }
    }

    // MARK: - SummaryError.invalidAPIKey maps to AppError.invalidAPIKey

    @Test func invalidAPIKeyMapsToAppErrorInvalidAPIKey() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let errorState = AppErrorState()
        let service = SummaryService(database: database, appErrorState: errorState)

        let stub = StubLLMProvider()
        await stub.setError(.invalidAPIKey)
        await service.setProviderOverride(stub)

        try await insertMeetingWithSegments(in: database)
        await service.summarize(meetingID: "test-meeting-1")

        #expect(errorState.current == .invalidAPIKey)
    }

    // MARK: - SummaryError.networkUnavailable maps to AppError.networkUnavailable

    @Test func networkUnavailableMapsToAppErrorNetworkUnavailable() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let errorState = AppErrorState()
        let service = SummaryService(database: database, appErrorState: errorState)

        let stub = StubLLMProvider()
        await stub.setError(.networkUnavailable)
        await service.setProviderOverride(stub)

        try await insertMeetingWithSegments(in: database)
        await service.summarize(meetingID: "test-meeting-1")

        #expect(errorState.current == .networkUnavailable)
    }

    // MARK: - SummaryError.providerFailure maps to AppError.summaryFailed

    @Test func providerFailureMapsToAppErrorSummaryFailed() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let errorState = AppErrorState()
        let service = SummaryService(database: database, appErrorState: errorState)

        let stub = StubLLMProvider()
        await stub.setError(.providerFailure(NSError(domain: "test", code: 1)))
        await service.setProviderOverride(stub)

        try await insertMeetingWithSegments(in: database)
        await service.summarize(meetingID: "test-meeting-1")

        #expect(errorState.current == .summaryFailed)
    }

    // MARK: - SummaryError.ollamaNotReachable maps to AppError.ollamaNotRunning

    @Test func ollamaNotReachableMapsToAppErrorOllamaNotRunning() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let errorState = AppErrorState()
        let service = SummaryService(database: database, appErrorState: errorState)

        let stub = StubLLMProvider()
        await stub.setError(.ollamaNotReachable(endpoint: "http://localhost:11434"))
        await service.setProviderOverride(stub)

        try await insertMeetingWithSegments(in: database)
        await service.summarize(meetingID: "test-meeting-1")

        #expect(errorState.current == .ollamaNotRunning(endpoint: "http://localhost:11434"))
    }
}
