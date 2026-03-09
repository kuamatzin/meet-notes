import GRDB
import Foundation

struct Meeting: Codable, Identifiable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "meetings"

    var id: String
    var title: String
    var startedAt: Date
    var endedAt: Date?
    var durationSeconds: Double?
    var audioQuality: AudioQuality
    var summaryMd: String?
    var pipelineStatus: PipelineStatus
    var createdAt: Date

    enum AudioQuality: String, Codable, Sendable {
        case full
        case micOnly = "mic_only"
        case partial
    }

    enum PipelineStatus: String, Codable, Sendable {
        case recording
        case transcribing
        case transcribed
        case summarizing
        case complete
        case failed
    }

    enum CodingKeys: String, CodingKey {
        case id, title
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case durationSeconds = "duration_seconds"
        case audioQuality = "audio_quality"
        case summaryMd = "summary_md"
        case pipelineStatus = "pipeline_status"
        case createdAt = "created_at"
    }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let title = Column(CodingKeys.title)
        static let startedAt = Column(CodingKeys.startedAt)
        static let endedAt = Column(CodingKeys.endedAt)
        static let durationSeconds = Column(CodingKeys.durationSeconds)
        static let audioQuality = Column(CodingKeys.audioQuality)
        static let summaryMd = Column(CodingKeys.summaryMd)
        static let pipelineStatus = Column(CodingKeys.pipelineStatus)
        static let createdAt = Column(CodingKeys.createdAt)
    }
}
