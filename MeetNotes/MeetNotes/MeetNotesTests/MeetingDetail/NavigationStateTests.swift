import Testing
@testable import MeetNotes

@MainActor
struct NavigationStateTests {
    // MARK: - Initial State

    @Test func initialSelectedMeetingIDIsNil() {
        let state = NavigationState()
        #expect(state.selectedMeetingID == nil)
    }

    // MARK: - openMeeting

    @Test func openMeetingSetsSelectedMeetingID() {
        let state = NavigationState()
        state.openMeeting(id: "meeting-123")
        #expect(state.selectedMeetingID == "meeting-123")
    }

    @Test func openMeetingIdempotentForSameID() {
        let state = NavigationState()
        state.openMeeting(id: "meeting-123")
        #expect(state.selectedMeetingID == "meeting-123")
        state.openMeeting(id: "meeting-123")
        #expect(state.selectedMeetingID == "meeting-123")
    }

    @Test func openMeetingChangesForDifferentID() {
        let state = NavigationState()
        state.openMeeting(id: "meeting-1")
        #expect(state.selectedMeetingID == "meeting-1")
        state.openMeeting(id: "meeting-2")
        #expect(state.selectedMeetingID == "meeting-2")
    }

    @Test func selectedMeetingIDCanBeSetDirectly() {
        let state = NavigationState()
        state.selectedMeetingID = "direct-set"
        #expect(state.selectedMeetingID == "direct-set")
    }

    @Test func selectedMeetingIDCanBeClearedToNil() {
        let state = NavigationState()
        state.openMeeting(id: "meeting-1")
        state.selectedMeetingID = nil
        #expect(state.selectedMeetingID == nil)
    }
}
