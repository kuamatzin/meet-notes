import Foundation
import GRDB
import Observation
import os

private let logger = Logger(subsystem: "com.kuamatzin.meet-notes", category: "MeetingDetailViewModel")

@Observable @MainActor final class MeetingDetailViewModel {
    var meeting: Meeting?
    var segments: [TranscriptSegment] = []
    var isTranscribing = false
    var summaryMarkdown: String?
    var isSummarizing = false
    var isStreamingSummary = false
    var llmProviderLabel: String?
    var summaryError: AppError?
    var matchedSegmentIDs: Set<Int64> = []
    var activeSearchQuery: String = ""

    private let database: AppDatabase
    private let appErrorState: AppErrorState
    private let summaryService: SummaryService
    private var segmentsCancellable: AnyDatabaseCancellable?
    private var meetingCancellable: AnyDatabaseCancellable?

    init(database: AppDatabase, appErrorState: AppErrorState, summaryService: SummaryService) {
        self.database = database
        self.appErrorState = appErrorState
        self.summaryService = summaryService
    }

    func load(meetingID: String) {
        Task { await summaryService.clearStreamingHandler() }
        segmentsCancellable = nil
        meetingCancellable = nil
        summaryMarkdown = nil
        isStreamingSummary = false
        isSummarizing = false
        summaryError = nil

        let segmentsObservation = ValueObservation.tracking { db in
            try TranscriptSegment
                .filter(TranscriptSegment.Columns.meetingId == meetingID)
                .order(TranscriptSegment.Columns.startSeconds.asc)
                .fetchAll(db)
        }

        segmentsCancellable = segmentsObservation.start(
            in: database.pool,
            scheduling: .immediate,
            onError: { [weak self] error in
                Task { @MainActor in
                    logger.error("Segments observation error: \(error)")
                    self?.appErrorState.post(.databaseObservationFailed)
                }
            },
            onChange: { [weak self] segments in
                Task { @MainActor in
                    self?.segments = segments
                }
            }
        )

        let meetingObservation = ValueObservation.tracking { db in
            try Meeting.fetchOne(db, id: meetingID)
        }

        meetingCancellable = meetingObservation.start(
            in: database.pool,
            scheduling: .immediate,
            onError: { [weak self] error in
                Task { @MainActor in
                    logger.error("Meeting observation error: \(error)")
                    self?.appErrorState.post(.databaseObservationFailed)
                }
            },
            onChange: { [weak self] meeting in
                Task { @MainActor in
                    guard let self else { return }
                    self.meeting = meeting
                    self.isTranscribing = meeting?.pipelineStatus == .transcribing
                    self.isSummarizing = meeting?.pipelineStatus == .summarizing

                    if meeting?.pipelineStatus == .complete || meeting?.pipelineStatus == .transcribed {
                        if let md = meeting?.summaryMd, !md.isEmpty {
                            self.summaryMarkdown = md
                        }
                        if self.isStreamingSummary {
                            Task { await self.summaryService.clearStreamingHandler() }
                        }
                        self.isStreamingSummary = false

                        if self.isSummarizing == false,
                           self.summaryMarkdown == nil,
                           let error = self.appErrorState.current {
                            switch error {
                            case .ollamaNotRunning, .summaryFailed, .invalidAPIKey, .networkUnavailable:
                                self.summaryError = error
                            default:
                                break
                            }
                        }
                    }
                }
            }
        )

        Task {
            await registerStreamingHandler(meetingID: meetingID)
            await loadLLMProviderLabel()
        }
    }

    func dismissSummaryError() {
        summaryError = nil
    }

    func retrySummary() {
        guard let meetingID = meeting?.id else { return }
        summaryError = nil
        Task {
            await summaryService.summarize(meetingID: meetingID)
        }
    }

    private func registerStreamingHandler(meetingID: String) async {
        await summaryService.setStreamingHandler { [weak self] streamMeetingID, text in
            guard let self, self.meeting?.id == streamMeetingID else { return }
            self.summaryMarkdown = text
            self.isStreamingSummary = true
        }
    }

    private func loadLLMProviderLabel() async {
        let provider = await database.readSetting(key: "llm_provider")
        switch provider {
        case "ollama":
            llmProviderLabel = "On-device"
        case "cloud":
            llmProviderLabel = "Cloud"
        default:
            llmProviderLabel = nil
        }
    }
}
