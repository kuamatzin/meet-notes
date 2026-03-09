import AppKit
import Observation

@Observable @MainActor final class NavigationState {
    @MainActor static let shared = NavigationState()

    var selectedMeetingID: String?

    func openMeeting(id: String) {
        guard selectedMeetingID != id else { return }
        selectedMeetingID = id
        NSApp.activate()
    }
}
