import UserNotifications
@testable import MeetNotes

struct CapturedNotification: Sendable {
    let identifier: String
    let title: String
    let body: String
    let meetingID: String?
}

actor MockNotificationCenter: NotificationCenterProtocol {
    private var captured: [CapturedNotification] = []
    var status: UNAuthorizationStatus = .authorized
    var authorizationGrantResult: Bool = true
    var authorizationError: Error?

    nonisolated func add(_ request: UNNotificationRequest) async throws {
        let notification = CapturedNotification(
            identifier: request.identifier,
            title: request.content.title,
            body: request.content.body,
            meetingID: request.content.userInfo["meetingID"] as? String
        )
        await appendCaptured(notification)
    }

    private func appendCaptured(_ notification: CapturedNotification) {
        captured.append(notification)
    }

    nonisolated func authorizationStatus() async -> UNAuthorizationStatus {
        await self.status
    }

    nonisolated func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        let error = await self.authorizationError
        if let error { throw error }
        return await self.authorizationGrantResult
    }

    func setAuthorizationStatus(_ newStatus: UNAuthorizationStatus) {
        status = newStatus
    }

    func setAuthorizationGrantResult(_ result: Bool) {
        authorizationGrantResult = result
    }

    var capturedNotifications: [CapturedNotification] { captured }
}
