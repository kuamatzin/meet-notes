import Foundation

protocol SummaryServiceProtocol: Sendable {
    func summarize(meetingID: String) async
}
