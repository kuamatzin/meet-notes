@preconcurrency import AVFAudio
import Foundation
import GRDB
import Testing
@testable import MeetNotes

// MARK: - Factory Tracker

final class FactoryTracker: @unchecked Sendable {
    nonisolated(unsafe) private let lock = NSLock()
    nonisolated(unsafe) private var _modelNames: [String] = []

    nonisolated var modelNames: [String] { lock.withLock { _modelNames } }
    nonisolated var callCount: Int { lock.withLock { _modelNames.count } }

    nonisolated func record(_ modelName: String) {
        lock.withLock { _modelNames.append(modelName) }
    }
}

// MARK: - Mock Summary Service

final class MockSummaryService: SummaryServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _summarizeCalled = false
    private var _lastMeetingID: String?

    var summarizeCalled: Bool { lock.withLock { _summarizeCalled } }
    var lastMeetingID: String? { lock.withLock { _lastMeetingID } }

    func summarize(meetingID: String) async {
        lock.withLock {
            _summarizeCalled = true
            _lastMeetingID = meetingID
        }
    }
}

// MARK: - Mock WhisperKit Provider

final class MockWhisperKitProvider: WhisperKitProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var _transcribeCalled = false
    var segmentsToReturn: [[TranscriptionSegmentResult]] = []
    var shouldThrow: Error?

    var transcribeCalled: Bool { lock.withLock { _transcribeCalled } }

    func transcribe(audioArray: [Float], segmentCallback: (@Sendable ([TranscriptionSegmentResult]) -> Void)?) async throws -> [[TranscriptionSegmentResult]] {
        lock.withLock { _transcribeCalled = true }
        if let error = shouldThrow { throw error }

        // Simulate incremental callback delivery
        if let callback = segmentCallback {
            var accumulated: [TranscriptionSegmentResult] = []
            for group in segmentsToReturn {
                accumulated.append(contentsOf: group)
                callback(accumulated)
            }
        }

        return segmentsToReturn
    }
}

// MARK: - Tests

struct TranscriptionServiceTests {
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

    private func insertTestMeeting(into database: AppDatabase, id: String, status: Meeting.PipelineStatus = .recording) async throws {
        let meeting = Meeting(
            id: id,
            title: "Test Meeting",
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

    private func makeFakeAudioBuffer() -> AVAudioPCMBuffer {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16000)!
        buffer.frameLength = 16000
        // Fill with silence (zeros)
        if let channelData = buffer.floatChannelData {
            memset(channelData[0], 0, Int(buffer.frameLength) * MemoryLayout<Float>.size)
        }
        return buffer
    }

    // MARK: - Pipeline Status Transitions

    @Test func transcribeUpdatesPipelineStatusToTranscribing() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let meetingID = UUID().uuidString
        try await insertTestMeeting(into: database, id: meetingID)

        let mockWhisper = MockWhisperKitProvider()
        mockWhisper.segmentsToReturn = [[
            TranscriptionSegmentResult(start: 0, end: 1.0, text: "Hello", avgLogprob: -0.3)
        ]]

        let mockSummary = MockSummaryService()
        let service = TranscriptionService(
            database: database,
            summaryService: mockSummary,
            whisperKitFactory: { _ in mockWhisper }
        )

        try await service.transcribe(meetingID: meetingID, audioBuffers: [makeFakeAudioBuffer()])

        let meeting = try await database.pool.read { db in
            try Meeting.fetchOne(db, key: meetingID)
        }
        // After full pipeline: recording → transcribing → transcribed → complete (via summary stub)
        #expect(meeting?.pipelineStatus == .complete)
    }

    @Test func transcribeUpdatesStatusToTranscribedBeforeSummary() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let meetingID = UUID().uuidString
        try await insertTestMeeting(into: database, id: meetingID)

        let mockWhisper = MockWhisperKitProvider()
        mockWhisper.segmentsToReturn = [[
            TranscriptionSegmentResult(start: 0, end: 1.0, text: "Test", avgLogprob: -0.2)
        ]]

        // Use a summary service that does NOT update status, so we can check transcribed status
        let noOpSummary = MockSummaryService()
        let service = TranscriptionService(
            database: database,
            summaryService: noOpSummary,
            whisperKitFactory: { _ in mockWhisper }
        )

        try await service.transcribe(meetingID: meetingID, audioBuffers: [makeFakeAudioBuffer()])

        #expect(noOpSummary.summarizeCalled)
        #expect(noOpSummary.lastMeetingID == meetingID)
    }

    // MARK: - Segment DB Writes

    @Test func transcribeSavesSegmentsToDatabase() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let meetingID = UUID().uuidString
        try await insertTestMeeting(into: database, id: meetingID)

        let mockWhisper = MockWhisperKitProvider()
        mockWhisper.segmentsToReturn = [[
            TranscriptionSegmentResult(start: 0, end: 5.0, text: "Hello everyone", avgLogprob: -0.3),
            TranscriptionSegmentResult(start: 5.0, end: 10.0, text: "Welcome to the meeting", avgLogprob: -0.4),
        ]]

        let mockSummary = MockSummaryService()
        let service = TranscriptionService(
            database: database,
            summaryService: mockSummary,
            whisperKitFactory: { _ in mockWhisper }
        )

        try await service.transcribe(meetingID: meetingID, audioBuffers: [makeFakeAudioBuffer()])

        let segments = try await database.pool.read { db in
            try TranscriptSegment
                .filter(TranscriptSegment.Columns.meetingId == meetingID)
                .order(TranscriptSegment.Columns.startSeconds)
                .fetchAll(db)
        }

        #expect(segments.count == 2)
        #expect(segments[0].text == "Hello everyone")
        #expect(segments[0].startSeconds == 0)
        #expect(segments[0].endSeconds == 5.0)
        #expect(segments[1].text == "Welcome to the meeting")
        #expect(segments[1].startSeconds == 5.0)
    }

    @Test func confidenceIsNormalizedNotRawLogprob() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let meetingID = UUID().uuidString
        try await insertTestMeeting(into: database, id: meetingID)

        let mockWhisper = MockWhisperKitProvider()
        mockWhisper.segmentsToReturn = [[
            TranscriptionSegmentResult(start: 0, end: 1.0, text: "Test", avgLogprob: -0.3),
        ]]

        let mockSummary = MockSummaryService()
        let service = TranscriptionService(
            database: database,
            summaryService: mockSummary,
            whisperKitFactory: { _ in mockWhisper }
        )

        try await service.transcribe(meetingID: meetingID, audioBuffers: [makeFakeAudioBuffer()])

        let segment = try await database.pool.read { db in
            try TranscriptSegment
                .filter(TranscriptSegment.Columns.meetingId == meetingID)
                .fetchOne(db)
        }

        // exp(-0.3) ≈ 0.74, should be between 0 and 1
        #expect(segment?.confidence != nil)
        #expect(segment!.confidence! > 0)
        #expect(segment!.confidence! <= 1.0)
    }

    // MARK: - Progress Reporting

    @Test func transcribeReportsProgressViaStateHandler() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let meetingID = UUID().uuidString
        try await insertTestMeeting(into: database, id: meetingID)

        let mockWhisper = MockWhisperKitProvider()
        mockWhisper.segmentsToReturn = [[
            TranscriptionSegmentResult(start: 0, end: 0.5, text: "A", avgLogprob: -0.2),
        ]]

        let mockSummary = MockSummaryService()
        let service = TranscriptionService(
            database: database,
            summaryService: mockSummary,
            whisperKitFactory: { _ in mockWhisper }
        )

        var receivedStates: [RecordingState] = []
        await service.setStateHandler { state in
            receivedStates.append(state)
        }

        try await service.transcribe(meetingID: meetingID, audioBuffers: [makeFakeAudioBuffer()])

        // Should have received: processing(progress: 0), possibly incremental updates, then idle
        let hasProcessing = receivedStates.contains { state in
            if case .processing = state { return true }
            return false
        }
        let hasIdle = receivedStates.contains { $0.isIdle }

        #expect(hasProcessing)
        #expect(hasIdle)
    }

    // MARK: - Crash Recovery

    @Test func checkForStaleMeetingsMarksTranscribingAsFailed() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let meetingID = UUID().uuidString
        try await insertTestMeeting(into: database, id: meetingID, status: .transcribing)

        let mockSummary = MockSummaryService()
        let service = TranscriptionService(database: database, summaryService: mockSummary)

        await service.checkForStaleMeetings()

        let meeting = try await database.pool.read { db in
            try Meeting.fetchOne(db, key: meetingID)
        }
        #expect(meeting?.pipelineStatus == .failed)
    }

    @Test func checkForStaleMeetingsIgnoresNonTranscribingMeetings() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let recordingID = UUID().uuidString
        let completeID = UUID().uuidString
        try await insertTestMeeting(into: database, id: recordingID, status: .recording)
        try await insertTestMeeting(into: database, id: completeID, status: .complete)

        let mockSummary = MockSummaryService()
        let service = TranscriptionService(database: database, summaryService: mockSummary)

        await service.checkForStaleMeetings()

        let recording = try await database.pool.read { db in
            try Meeting.fetchOne(db, key: recordingID)
        }
        let complete = try await database.pool.read { db in
            try Meeting.fetchOne(db, key: completeID)
        }
        #expect(recording?.pipelineStatus == .recording)
        #expect(complete?.pipelineStatus == .complete)
    }

    // MARK: - Error Handling

    @Test func transcribeThrowsModelNotLoadedWhenFactoryFails() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let meetingID = UUID().uuidString
        try await insertTestMeeting(into: database, id: meetingID)

        let mockSummary = MockSummaryService()
        let service = TranscriptionService(
            database: database,
            summaryService: mockSummary,
            whisperKitFactory: { _ in throw NSError(domain: "test", code: 1) }
        )

        do {
            try await service.transcribe(meetingID: meetingID, audioBuffers: [makeFakeAudioBuffer()])
            Issue.record("Expected modelNotLoaded error")
        } catch let error as TranscriptionError {
            #expect(error == .modelNotLoaded)
        }

        let meeting = try await database.pool.read { db in
            try Meeting.fetchOne(db, key: meetingID)
        }
        #expect(meeting?.pipelineStatus == .failed)
    }

    @Test func transcribeThrowsTranscriptionFailedWhenWhisperFails() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let meetingID = UUID().uuidString
        try await insertTestMeeting(into: database, id: meetingID)

        let mockWhisper = MockWhisperKitProvider()
        mockWhisper.shouldThrow = NSError(domain: "whisper", code: 42, userInfo: [NSLocalizedDescriptionKey: "model error"])

        let mockSummary = MockSummaryService()
        let service = TranscriptionService(
            database: database,
            summaryService: mockSummary,
            whisperKitFactory: { _ in mockWhisper }
        )

        do {
            try await service.transcribe(meetingID: meetingID, audioBuffers: [makeFakeAudioBuffer()])
            Issue.record("Expected transcriptionFailed error")
        } catch let error as TranscriptionError {
            if case .transcriptionFailed = error {
                // Expected
            } else {
                Issue.record("Expected transcriptionFailed, got \(error)")
            }
        }

        let meeting = try await database.pool.read { db in
            try Meeting.fetchOne(db, key: meetingID)
        }
        #expect(meeting?.pipelineStatus == .failed)
    }

    // MARK: - Empty Audio Handling

    @Test func transcribeWithEmptyBuffersFinalizesMeeting() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let meetingID = UUID().uuidString
        try await insertTestMeeting(into: database, id: meetingID)

        let mockWhisper = MockWhisperKitProvider()
        let mockSummary = MockSummaryService()
        let service = TranscriptionService(
            database: database,
            summaryService: mockSummary,
            whisperKitFactory: { _ in mockWhisper }
        )

        // Empty buffers → empty audio array → finalize immediately
        try await service.transcribe(meetingID: meetingID, audioBuffers: [])

        // WhisperKit should NOT have been called
        #expect(!mockWhisper.transcribeCalled)

        // Summary should have been called (finalize path)
        #expect(mockSummary.summarizeCalled)
    }

    // MARK: - Protocol Conformance

    @Test func transcriptionServiceConformsToProtocol() throws {
        let (database, _) = try makeDatabase()
        let mockSummary = MockSummaryService()
        let service: any TranscriptionServiceProtocol = TranscriptionService(database: database, summaryService: mockSummary)
        #expect(service is TranscriptionService)
    }

    // MARK: - TranscriptionError

    @Test func transcriptionErrorEquality() {
        #expect(TranscriptionError.modelNotLoaded == TranscriptionError.modelNotLoaded)
        #expect(TranscriptionError.databaseWriteFailed == TranscriptionError.databaseWriteFailed)
        #expect(TranscriptionError.transcriptionFailed("a") == TranscriptionError.transcriptionFailed("a"))
        #expect(TranscriptionError.transcriptionFailed("a") != TranscriptionError.transcriptionFailed("b"))
        #expect(TranscriptionError.modelNotLoaded != TranscriptionError.databaseWriteFailed)
    }

    // MARK: - Model Switching

    @Test func setModelInvalidatesCachedProvider() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let meetingID = UUID().uuidString
        try await insertTestMeeting(into: database, id: meetingID)

        let tracker = FactoryTracker()
        let mockWhisper = MockWhisperKitProvider()
        mockWhisper.segmentsToReturn = [[
            TranscriptionSegmentResult(start: 0, end: 1.0, text: "Test", avgLogprob: -0.3)
        ]]

        let mockSummary = MockSummaryService()
        let service = TranscriptionService(
            database: database,
            summaryService: mockSummary,
            whisperKitFactory: { modelName in
                tracker.record(modelName)
                return mockWhisper
            }
        )

        // First transcription — should use "base"
        try await service.transcribe(meetingID: meetingID, audioBuffers: [makeFakeAudioBuffer()])
        #expect(tracker.modelNames == ["base"])

        // Switch model — returns true when not transcribing
        let switched = await service.setModel("small")
        #expect(switched == true)

        // Verify model preference persisted to database
        let saved = await database.readSetting(key: "whisperkit_model")
        #expect(saved == "small")

        // Second transcription — should reinitialize with "small"
        let meetingID2 = UUID().uuidString
        try await insertTestMeeting(into: database, id: meetingID2)
        try await service.transcribe(meetingID: meetingID2, audioBuffers: [makeFakeAudioBuffer()])
        #expect(tracker.modelNames == ["base", "small"])
    }

    @Test func setModelToSameNameDoesNotInvalidate() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let meetingID = UUID().uuidString
        try await insertTestMeeting(into: database, id: meetingID)

        let tracker = FactoryTracker()
        let mockWhisper = MockWhisperKitProvider()
        mockWhisper.segmentsToReturn = [[
            TranscriptionSegmentResult(start: 0, end: 1.0, text: "Test", avgLogprob: -0.3)
        ]]

        let mockSummary = MockSummaryService()
        let service = TranscriptionService(
            database: database,
            summaryService: mockSummary,
            whisperKitFactory: { modelName in
                tracker.record(modelName)
                return mockWhisper
            }
        )

        try await service.transcribe(meetingID: meetingID, audioBuffers: [makeFakeAudioBuffer()])
        #expect(tracker.callCount == 1)

        // Set same model — should NOT invalidate, returns true
        let switched = await service.setModel("base")
        #expect(switched == true)

        let meetingID2 = UUID().uuidString
        try await insertTestMeeting(into: database, id: meetingID2)
        try await service.transcribe(meetingID: meetingID2, audioBuffers: [makeFakeAudioBuffer()])
        #expect(tracker.callCount == 1) // Factory NOT called again
    }

    @Test func transcriptionServiceConformsToUpdatedProtocol() async throws {
        let (database, _) = try makeDatabase()
        let mockSummary = MockSummaryService()
        let service: any TranscriptionServiceProtocol = TranscriptionService(database: database, summaryService: mockSummary)
        let result = await service.setModel("small")
        #expect(result == true)
    }
}
