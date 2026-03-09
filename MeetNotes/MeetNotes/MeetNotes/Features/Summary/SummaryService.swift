import Foundation
import GRDB
import os

actor SummaryService: SummaryServiceProtocol {
    private nonisolated static let logger = Logger(subsystem: "com.kuamatzin.meet-notes", category: "SummaryService")

    private let database: AppDatabase
    private let appErrorState: AppErrorState
    private var providerOverride: (any LLMSummaryProvider)?
    private var onStreamingChunk: (@MainActor @Sendable (String, String) -> Void)?

    init(database: AppDatabase, appErrorState: AppErrorState) {
        self.database = database
        self.appErrorState = appErrorState
    }

    func setProviderOverride(_ provider: any LLMSummaryProvider) {
        self.providerOverride = provider
    }

    func setStreamingHandler(_ handler: @escaping @MainActor @Sendable (String, String) -> Void) {
        self.onStreamingChunk = handler
    }

    func clearStreamingHandler() {
        self.onStreamingChunk = nil
    }

    func summarize(meetingID: String) async {
        do {
            try await database.pool.write { db in
                try db.execute(
                    sql: "UPDATE meetings SET pipeline_status = ? WHERE id = ?",
                    arguments: [Meeting.PipelineStatus.summarizing.rawValue, meetingID]
                )
            }
        } catch {
            Self.logger.error("Failed to set pipeline_status to summarizing: \(error)")
        }

        let segments: [TranscriptSegment]
        do {
            segments = try await database.pool.read { db in
                try TranscriptSegment
                    .filter(TranscriptSegment.Columns.meetingId == meetingID)
                    .order(TranscriptSegment.Columns.startSeconds)
                    .fetchAll(db)
            }
        } catch {
            Self.logger.error("Failed to read transcript segments: \(error)")
            await setComplete(meetingID: meetingID)
            return
        }

        guard !segments.isEmpty else {
            Self.logger.info("No transcript segments for meeting \(meetingID) — skipping summarization")
            await setComplete(meetingID: meetingID)
            return
        }

        let transcriptText = segments.map { segment in
            let totalSeconds = Int(segment.startSeconds)
            let minutes = totalSeconds / 60
            let secs = totalSeconds % 60
            return String(format: "[%02d:%02d] %@", minutes, secs, segment.text)
        }.joined(separator: "\n")

        Self.logger.debug("Transcript length: \(transcriptText.count) characters for meeting \(meetingID)")

        guard let provider = await resolveProvider() else {
            Self.logger.info("No LLM provider configured — skipping summarization for meeting \(meetingID)")
            await setComplete(meetingID: meetingID)
            await NotificationService.shared.postTranscriptReady(meetingID: meetingID)
            return
        }

        do {
            let summary: String
            if let handler = onStreamingChunk {
                var accumulated = ""
                for try await chunk in provider.summarizeStreaming(transcript: transcriptText) {
                    accumulated += chunk
                    await handler(meetingID, accumulated)
                }
                summary = accumulated
            } else {
                summary = try await provider.summarize(transcript: transcriptText)
            }

            try await database.pool.write { db in
                try db.execute(
                    sql: "UPDATE meetings SET summary_md = ?, pipeline_status = ? WHERE id = ?",
                    arguments: [summary, Meeting.PipelineStatus.complete.rawValue, meetingID]
                )
            }
            Self.logger.info("Summary saved for meeting \(meetingID)")

            let (firstDecision, firstAction) = NotificationService.extractNotificationBody(from: summary)
            await NotificationService.shared.postMeetingReady(
                meetingID: meetingID,
                firstDecision: firstDecision,
                firstAction: firstAction
            )
        } catch let error as SummaryError {
            Self.logger.error("Summary generation failed: \(error)")
            await setComplete(meetingID: meetingID)
            await NotificationService.shared.postTranscriptReady(meetingID: meetingID)
            await postError(error)
        } catch {
            Self.logger.error("Unexpected summary error: \(error)")
            await setComplete(meetingID: meetingID)
            await NotificationService.shared.postTranscriptReady(meetingID: meetingID)
            await MainActor.run { appErrorState.post(.summaryFailed) }
        }
    }

    private func resolveProvider() async -> (any LLMSummaryProvider)? {
        if let providerOverride {
            return providerOverride
        }

        let providerSetting = await database.readSetting(key: "llm_provider")

        switch providerSetting {
        case "ollama":
            let endpoint = await database.readSetting(key: "ollama_endpoint") ?? "http://localhost:11434"
            let model = await database.readSetting(key: "ollama_model") ?? "llama3.2"
            return await MainActor.run { OllamaProvider(endpoint: endpoint, model: model) }
        case "cloud":
            let apiKey = await MainActor.run { SecretsStore.load(for: .openAI) }
            guard let apiKey else {
                Self.logger.info("Cloud provider selected but no API key configured")
                return nil
            }
            return await MainActor.run { CloudAPIProvider(apiKey: apiKey) }
        default:
            return nil
        }
    }

    private func setComplete(meetingID: String) async {
        do {
            try await database.pool.write { db in
                try db.execute(
                    sql: "UPDATE meetings SET pipeline_status = ? WHERE id = ?",
                    arguments: [Meeting.PipelineStatus.complete.rawValue, meetingID]
                )
            }
        } catch {
            Self.logger.error("Failed to set pipeline_status to complete: \(error)")
        }
    }

    private func postError(_ error: SummaryError) async {
        await MainActor.run {
            switch error {
            case .ollamaNotReachable(let endpoint):
                appErrorState.post(.ollamaNotRunning(endpoint: endpoint))
            case .invalidAPIKey:
                appErrorState.post(.invalidAPIKey)
            case .networkUnavailable:
                appErrorState.post(.networkUnavailable)
            case .providerFailure:
                appErrorState.post(.summaryFailed)
            }
        }
    }
}
