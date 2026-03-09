import Testing
@testable import MeetNotes

@MainActor
struct AppErrorStateTests {
    @Test func initialCurrentIsNil() {
        let state = AppErrorState()
        #expect(state.current == nil)
    }

    @Test func postSetsCurrentToGivenError() {
        let state = AppErrorState()
        state.post(.microphonePermissionDenied)
        #expect(state.current == .microphonePermissionDenied)
    }

    @Test func clearSetsCurrentToNil() {
        let state = AppErrorState()
        state.post(.microphonePermissionDenied)
        state.clear()
        #expect(state.current == nil)
    }

    @Test func postReplacesPreviousError() {
        let state = AppErrorState()
        state.post(.microphonePermissionDenied)
        state.post(.screenRecordingPermissionDenied)
        #expect(state.current == .screenRecordingPermissionDenied)
    }
}
