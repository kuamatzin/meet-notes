@preconcurrency import AVFAudio
import GRDB
import os
@preconcurrency import WhisperKit

actor TranscriptionService: TranscriptionServiceProtocol {
    private nonisolated static let logger = Logger(subsystem: "com.kuamatzin.meet-notes", category: "TranscriptionService")

    private let database: AppDatabase
    private let summaryService: any SummaryServiceProtocol
    private var onStateChange: (@MainActor @Sendable (RecordingState) -> Void)?
    private var whisperKitProvider: (any WhisperKitProviding)?
    private let whisperKitFactory: @Sendable (String) async throws -> any WhisperKitProviding
    private var savedSegmentCount = 0
    private var currentModelName: String = "base"
    private var currentLanguage: String?
    private var isTranscribing = false

    init(
        database: AppDatabase,
        summaryService: any SummaryServiceProtocol,
        whisperKitFactory: @escaping @Sendable (String) async throws -> any WhisperKitProviding = { modelName in
            let fullModelName = "openai_whisper-\(modelName)"
            let pipe = try await WhisperKit(WhisperKitConfig(model: fullModelName))
            return WhisperKitProvider(pipe: pipe)
        }
    ) {
        self.database = database
        self.summaryService = summaryService
        self.whisperKitFactory = whisperKitFactory
    }

    func setStateHandler(_ handler: @escaping @MainActor @Sendable (RecordingState) -> Void) {
        self.onStateChange = handler
    }

    @discardableResult
    func setModel(_ modelName: String) async -> Bool {
        guard !isTranscribing else {
            Self.logger.warning("Cannot switch model during active transcription")
            return false
        }
        guard modelName != currentModelName else { return true }
        currentModelName = modelName
        whisperKitProvider = nil
        await database.writeSetting(key: "whisperkit_model", value: modelName)
        Self.logger.info("Model set to \(modelName) — will initialize on next transcription")
        return true
    }

    func loadInitialModel() async {
        if let saved = await database.readSetting(key: "whisperkit_model") {
            currentModelName = saved
            Self.logger.info("Loaded saved model preference: \(saved)")
        }
        if let lang = await database.readSetting(key: "transcription_language") {
            currentLanguage = lang == "auto" ? nil : lang
            Self.logger.info("Loaded language preference: \(lang)")
        }
    }

    func setLanguage(_ language: String?) async {
        currentLanguage = language
        let value = language ?? "auto"
        await database.writeSetting(key: "transcription_language", value: value)
        Self.logger.info("Language set to \(value)")
    }

    func transcribe(meetingID: String, audioBuffers: [AVAudioPCMBuffer]) async throws(TranscriptionError) {
        Self.logger.info("Starting transcription for meeting \(meetingID)")
        isTranscribing = true
        defer { isTranscribing = false }

        guard let meetingUUID = UUID(uuidString: meetingID) else {
            Self.logger.error("Invalid meeting ID: \(meetingID)")
            throw .transcriptionFailed("Invalid meeting ID")
        }

        do {
            try await database.pool.write { db in
                try db.execute(
                    sql: "UPDATE meetings SET pipeline_status = ? WHERE id = ?",
                    arguments: [Meeting.PipelineStatus.transcribing.rawValue, meetingID]
                )
            }
        } catch {
            Self.logger.error("Failed to update pipeline_status to transcribing: \(error)")
            throw .databaseWriteFailed
        }

        await updateState(.processing(meetingID: meetingUUID, phase: .transcribing(progress: 0)))

        if whisperKitProvider == nil {
            do {
                whisperKitProvider = try await whisperKitFactory(currentModelName)
                Self.logger.info("WhisperKit initialized with \(self.currentModelName) model")
            } catch {
                Self.logger.error("Failed to initialize WhisperKit: \(error)")
                await markMeetingFailed(meetingID)
                throw .modelNotLoaded
            }
        }

        guard let provider = whisperKitProvider else {
            throw .modelNotLoaded
        }

        let audioArray = convertBuffersToFloatArray(audioBuffers)
        Self.logger.info("Converted \(audioBuffers.count) buffers to \(audioArray.count) float samples")

        guard !audioArray.isEmpty else {
            Self.logger.warning("Empty audio array — skipping transcription")
            await finalizeMeeting(meetingID, meetingUUID: meetingUUID)
            return
        }

        let totalDuration = Float(audioArray.count) / 16000.0
        savedSegmentCount = 0

        do {
            let results = try await provider.transcribe(
                audioArray: audioArray,
                language: currentLanguage,
                segmentCallback: nil
            )

            if let finalSegments = results.first {
                for segment in finalSegments {
                    await saveSegment(segment, meetingID: meetingID)
                }
                savedSegmentCount = finalSegments.count
            }

            Self.logger.info("Transcription complete: \(self.savedSegmentCount) segments saved")
        } catch {
            Self.logger.error("WhisperKit transcription failed: \(error)")
            await markMeetingFailed(meetingID)
            throw .transcriptionFailed(error.localizedDescription)
        }

        await finalizeMeeting(meetingID, meetingUUID: meetingUUID)
    }

    func checkForStaleMeetings() async {
        Self.logger.info("Checking for stale transcribing meetings...")
        do {
            let staleMeetings = try await database.pool.read { db in
                try Meeting
                    .filter(Meeting.Columns.pipelineStatus == Meeting.PipelineStatus.transcribing.rawValue)
                    .fetchAll(db)
            }
            for meeting in staleMeetings {
                Self.logger.warning("Found stale transcribing meeting: \(meeting.id) — marking as failed")
                try? await database.pool.write { db in
                    try db.execute(
                        sql: "UPDATE meetings SET pipeline_status = ? WHERE id = ?",
                        arguments: [Meeting.PipelineStatus.failed.rawValue, meeting.id]
                    )
                }
            }
            if !staleMeetings.isEmpty {
                Self.logger.info("Marked \(staleMeetings.count) stale meetings as failed")
            }
        } catch {
            Self.logger.error("Failed to check for stale meetings: \(error)")
        }
    }

    // MARK: - Private

    private func processNewSegments(
        _ segments: [TranscriptionSegmentResult],
        meetingID: String,
        meetingUUID: UUID,
        totalDuration: Float
    ) async {
        let newSegments = Array(segments.dropFirst(savedSegmentCount))
        guard !newSegments.isEmpty else { return }
        for segment in newSegments {
            await saveSegment(segment, meetingID: meetingID)
        }
        savedSegmentCount = segments.count
        let progressVal = Double(min((segments.last?.end ?? 0) / totalDuration, 1.0))
        await updateState(.processing(meetingID: meetingUUID, phase: .transcribing(progress: progressVal)))
    }

    private nonisolated func convertBuffersToFloatArray(_ buffers: [AVAudioPCMBuffer]) -> [Float] {
        var result: [Float] = []
        for buffer in buffers {
            guard let channelData = buffer.floatChannelData else { continue }
            let frames = Int(buffer.frameLength)
            result.append(contentsOf: UnsafeBufferPointer(start: channelData[0], count: frames))
        }
        return result
    }

    private func saveSegment(_ segment: TranscriptionSegmentResult, meetingID: String) async {
        let confidence = min(1.0, max(0.0, exp(Double(segment.avgLogprob))))
        do {
            try await database.pool.write { db in
                var dbSegment = TranscriptSegment(
                    id: nil,
                    meetingId: meetingID,
                    startSeconds: Double(segment.start),
                    endSeconds: Double(segment.end),
                    text: segment.text,
                    confidence: confidence
                )
                try dbSegment.insert(db)
            }
        } catch {
            Self.logger.error("Failed to save segment: \(error)")
        }
    }

    private func finalizeMeeting(_ meetingID: String, meetingUUID: UUID) async {
        do {
            try await database.pool.write { db in
                try db.execute(
                    sql: "UPDATE meetings SET pipeline_status = ? WHERE id = ?",
                    arguments: [Meeting.PipelineStatus.transcribed.rawValue, meetingID]
                )
            }
        } catch {
            Self.logger.error("Failed to update pipeline_status to transcribed: \(error)")
        }

        await summaryService.summarize(meetingID: meetingID)
        await updateState(.idle)
        Self.logger.info("Meeting \(meetingID) pipeline complete")
    }

    private func markMeetingFailed(_ meetingID: String) async {
        try? await database.pool.write { db in
            try db.execute(
                sql: "UPDATE meetings SET pipeline_status = ? WHERE id = ?",
                arguments: [Meeting.PipelineStatus.failed.rawValue, meetingID]
            )
        }
    }

    private func updateState(_ state: RecordingState) async {
        await MainActor.run { [onStateChange] in
            onStateChange?(state)
        }
    }
}
