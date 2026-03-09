import Testing
import UserNotifications
@testable import MeetNotes

@MainActor
struct NotificationServiceTests {
    // MARK: - postMeetingReady

    @Test func postMeetingReadyCreatesCorrectRequest() async throws {
        let mockCenter = MockNotificationCenter()
        let service = NotificationService(notificationCenter: mockCenter)

        await service.postMeetingReady(
            meetingID: "meeting-1",
            firstDecision: "Approved the budget",
            firstAction: "Alice to send report"
        )

        let notifications = await mockCenter.capturedNotifications
        #expect(notifications.count == 1)
        let n = notifications[0]
        #expect(n.identifier == "meeting-1")
        #expect(n.title == "Meeting summary ready")
        #expect(n.body == "Decision: Approved the budget\nAction: Alice to send report")
        #expect(n.meetingID == "meeting-1")
    }

    @Test func postMeetingReadyWithNilFieldsFallsBackToGenericBody() async throws {
        let mockCenter = MockNotificationCenter()
        let service = NotificationService(notificationCenter: mockCenter)

        await service.postMeetingReady(meetingID: "meeting-2", firstDecision: nil, firstAction: nil)

        let notifications = await mockCenter.capturedNotifications
        #expect(notifications.count == 1)
        #expect(notifications[0].body == "Your meeting summary is ready.")
    }

    @Test func postMeetingReadyFiltersPlaceholderDecisions() async throws {
        let mockCenter = MockNotificationCenter()
        let service = NotificationService(notificationCenter: mockCenter)

        await service.postMeetingReady(
            meetingID: "meeting-3",
            firstDecision: "No decisions recorded.",
            firstAction: "No action items identified."
        )

        let notifications = await mockCenter.capturedNotifications
        #expect(notifications.count == 1)
        #expect(notifications[0].body == "Your meeting summary is ready.")
    }

    // MARK: - postTranscriptReady

    @Test func postTranscriptReadyCreatesCorrectRequest() async throws {
        let mockCenter = MockNotificationCenter()
        let service = NotificationService(notificationCenter: mockCenter)

        await service.postTranscriptReady(meetingID: "meeting-4")

        let notifications = await mockCenter.capturedNotifications
        #expect(notifications.count == 1)
        let n = notifications[0]
        #expect(n.identifier == "meeting-4")
        #expect(n.title == "Transcript ready")
        #expect(n.body == "Your meeting transcript is saved and searchable.")
        #expect(n.meetingID == "meeting-4")
    }

    // MARK: - requestPermissionIfNeeded

    @Test func postDoesNotSendWhenPermissionDenied() async throws {
        let mockCenter = MockNotificationCenter()
        await mockCenter.setAuthorizationStatus(.denied)
        let service = NotificationService(notificationCenter: mockCenter)

        await service.postMeetingReady(meetingID: "meeting-5", firstDecision: "Test", firstAction: nil)

        let notifications = await mockCenter.capturedNotifications
        #expect(notifications.isEmpty)
    }

    @Test func postRequestsPermissionWhenNotDetermined() async throws {
        let mockCenter = MockNotificationCenter()
        await mockCenter.setAuthorizationStatus(.notDetermined)
        await mockCenter.setAuthorizationGrantResult(true)
        let service = NotificationService(notificationCenter: mockCenter)

        await service.postMeetingReady(meetingID: "meeting-6", firstDecision: "Test", firstAction: nil)

        let notifications = await mockCenter.capturedNotifications
        #expect(notifications.count == 1)
    }

    @Test func postDoesNotSendWhenPermissionRequestDenied() async throws {
        let mockCenter = MockNotificationCenter()
        await mockCenter.setAuthorizationStatus(.notDetermined)
        await mockCenter.setAuthorizationGrantResult(false)
        let service = NotificationService(notificationCenter: mockCenter)

        await service.postMeetingReady(meetingID: "meeting-7", firstDecision: "Test", firstAction: nil)

        let notifications = await mockCenter.capturedNotifications
        #expect(notifications.isEmpty)
    }

    // MARK: - Notification tap deep-link (via NavigationState)

    @Test func navigationStateOpenMeetingSetsSelectedID() async throws {
        let navState = NavigationState()
        navState.openMeeting(id: "meeting-from-tap")
        #expect(navState.selectedMeetingID == "meeting-from-tap")
    }

    @Test func navigationStateDoesNotDuplicateForSameID() async throws {
        let navState = NavigationState()
        navState.openMeeting(id: "meeting-dup")
        #expect(navState.selectedMeetingID == "meeting-dup")
        navState.openMeeting(id: "meeting-dup")
        #expect(navState.selectedMeetingID == "meeting-dup")
    }
}
