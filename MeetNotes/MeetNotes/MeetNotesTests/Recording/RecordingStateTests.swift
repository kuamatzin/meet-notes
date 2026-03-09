import Foundation
import Testing
@testable import MeetNotes

struct RecordingStateTests {
    // MARK: - Equatable conformance

    @Test func idleStatesAreEqual() {
        #expect(RecordingState.idle == RecordingState.idle)
    }

    @Test func recordingStatesWithSameValuesAreEqual() {
        let date = Date()
        let stateA = RecordingState.recording(startedAt: date, audioQuality: .full)
        let stateB = RecordingState.recording(startedAt: date, audioQuality: .full)
        #expect(stateA == stateB)
    }

    @Test func recordingStatesWithDifferentQualityAreNotEqual() {
        let date = Date()
        let stateA = RecordingState.recording(startedAt: date, audioQuality: .full)
        let stateB = RecordingState.recording(startedAt: date, audioQuality: .micOnly)
        #expect(stateA != stateB)
    }

    @Test func processingStatesWithSameValuesAreEqual() {
        let id = UUID()
        let stateA = RecordingState.processing(meetingID: id, phase: .summarizing)
        let stateB = RecordingState.processing(meetingID: id, phase: .summarizing)
        #expect(stateA == stateB)
    }

    @Test func processingStatesWithDifferentPhasesAreNotEqual() {
        let id = UUID()
        let stateA = RecordingState.processing(meetingID: id, phase: .summarizing)
        let stateB = RecordingState.processing(meetingID: id, phase: .transcribing(progress: 0.5))
        #expect(stateA != stateB)
    }

    @Test func errorStatesWithSameErrorAreEqual() {
        let stateA = RecordingState.error(.microphonePermissionDenied)
        let stateB = RecordingState.error(.microphonePermissionDenied)
        #expect(stateA == stateB)
    }

    @Test func differentCasesAreNotEqual() {
        let date = Date()
        #expect(RecordingState.idle != RecordingState.recording(startedAt: date, audioQuality: .full))
        #expect(RecordingState.idle != RecordingState.error(.recordingFailed))
    }

    // MARK: - Convenience properties

    @Test func isIdleReturnsCorrectly() {
        #expect(RecordingState.idle.isIdle == true)
        #expect(RecordingState.recording(startedAt: Date(), audioQuality: .full).isIdle == false)
        #expect(RecordingState.processing(meetingID: UUID(), phase: .summarizing).isIdle == false)
        #expect(RecordingState.error(.recordingFailed).isIdle == false)
    }

    @Test func isRecordingReturnsCorrectly() {
        #expect(RecordingState.idle.isRecording == false)
        #expect(RecordingState.recording(startedAt: Date(), audioQuality: .full).isRecording == true)
        #expect(RecordingState.processing(meetingID: UUID(), phase: .summarizing).isRecording == false)
        #expect(RecordingState.error(.recordingFailed).isRecording == false)
    }

    // MARK: - AudioQuality

    @Test func audioQualityEquatable() {
        #expect(AudioQuality.full == AudioQuality.full)
        #expect(AudioQuality.micOnly == AudioQuality.micOnly)
        #expect(AudioQuality.partial == AudioQuality.partial)
        #expect(AudioQuality.full != AudioQuality.micOnly)
        #expect(AudioQuality.full != AudioQuality.partial)
        #expect(AudioQuality.micOnly != AudioQuality.partial)
    }

    // MARK: - ProcessingPhase

    @Test func processingPhaseEquatable() {
        #expect(ProcessingPhase.summarizing == ProcessingPhase.summarizing)
        #expect(ProcessingPhase.transcribing(progress: 0.5) == ProcessingPhase.transcribing(progress: 0.5))
        #expect(ProcessingPhase.transcribing(progress: 0.5) != ProcessingPhase.transcribing(progress: 0.8))
        #expect(ProcessingPhase.summarizing != ProcessingPhase.transcribing(progress: 0.0))
    }
}
