import UserNotifications
import os

actor NotificationService: NSObject {
    static let shared = NotificationService()
    private nonisolated static let logger = Logger(subsystem: "com.kuamatzin.meet-notes", category: "NotificationService")

    private var notificationCenter: any NotificationCenterProtocol

    override init() {
        self.notificationCenter = UNUserNotificationCenter.current()
        super.init()
    }

    init(notificationCenter: any NotificationCenterProtocol) {
        self.notificationCenter = notificationCenter
        super.init()
    }

    func configure() async {
        if notificationCenter is UNUserNotificationCenter {
            UNUserNotificationCenter.current().delegate = self
        }
    }

    func postMeetingReady(meetingID: String, firstDecision: String?, firstAction: String?) async {
        guard await requestPermissionIfNeeded() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Meeting summary ready"
        content.body = Self.formatBody(firstDecision: firstDecision, firstAction: firstAction)
        content.sound = .default
        content.userInfo = ["meetingID": meetingID]
        let request = UNNotificationRequest(identifier: meetingID, content: content, trigger: nil)
        try? await notificationCenter.add(request)
    }

    func postTranscriptReady(meetingID: String) async {
        guard await requestPermissionIfNeeded() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Transcript ready"
        content.body = "Your meeting transcript is saved and searchable."
        content.sound = .default
        content.userInfo = ["meetingID": meetingID]
        let request = UNNotificationRequest(identifier: meetingID, content: content, trigger: nil)
        try? await notificationCenter.add(request)
    }

    private func requestPermissionIfNeeded() async -> Bool {
        let status = await notificationCenter.authorizationStatus()
        if status == .authorized { return true }
        guard status == .notDetermined else { return false }
        return (try? await notificationCenter.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    nonisolated static func formatBody(firstDecision: String?, firstAction: String?) -> String {
        var parts: [String] = []
        if let d = firstDecision, d != "No decisions recorded." { parts.append("Decision: \(truncate(d, maxLength: 100))") }
        if let a = firstAction, a != "No action items identified." { parts.append("Action: \(truncate(a, maxLength: 100))") }
        return parts.isEmpty ? "Your meeting summary is ready." : parts.joined(separator: "\n")
    }

    private nonisolated static func truncate(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else { return text }
        return String(text.prefix(maxLength - 1)) + "…"
    }

    nonisolated static func extractNotificationBody(from summaryMd: String) -> (firstDecision: String?, firstAction: String?) {
        let sections = summaryMd.components(separatedBy: "## ")
        var firstDecision: String?
        var firstAction: String?
        for section in sections {
            if section.hasPrefix("Decisions") {
                firstDecision = extractFirstBullet(from: section)
            } else if section.hasPrefix("Action Items") {
                firstAction = extractFirstBullet(from: section)
            }
        }
        return (firstDecision, firstAction)
    }

    private nonisolated static func extractFirstBullet(from section: String) -> String? {
        let lines = section.split(separator: "\n", omittingEmptySubsequences: true)
        for line in lines.dropFirst() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- ") {
                return String(trimmed.dropFirst(2))
            } else if trimmed.hasPrefix("* ") {
                return String(trimmed.dropFirst(2))
            }
        }
        return nil
    }
}

extension NotificationService: @preconcurrency UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let meetingID = response.notification.request.content
                .userInfo["meetingID"] as? String else { return }
        await NavigationState.shared.openMeeting(id: meetingID)
    }
}
