import GRDB
import Foundation

struct TranscriptSegment: Codable, Identifiable, FetchableRecord, PersistableRecord, Sendable {
    var id: Int64?
    var meetingId: String
    var startSeconds: Double
    var endSeconds: Double
    var text: String
    var confidence: Double?

    enum CodingKeys: String, CodingKey {
        case id, text, confidence
        case meetingId = "meeting_id"
        case startSeconds = "start_seconds"
        case endSeconds = "end_seconds"
    }

    static let databaseTableName = "segments"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let meetingId = Column(CodingKeys.meetingId)
        static let startSeconds = Column(CodingKeys.startSeconds)
        static let endSeconds = Column(CodingKeys.endSeconds)
        static let text = Column(CodingKeys.text)
        static let confidence = Column(CodingKeys.confidence)
    }
}
