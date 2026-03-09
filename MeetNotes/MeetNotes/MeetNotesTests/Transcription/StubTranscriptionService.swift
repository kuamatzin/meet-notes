@preconcurrency import AVFAudio
@testable import MeetNotes

final class StubTranscriptionService: TranscriptionServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _transcribeCalled = false
    private var _lastMeetingID: String?
    private var _lastBuffers: [AVAudioPCMBuffer]?
    private var _checkForStaleMeetingsCalled = false
    private var _setModelCalled = false
    private var _lastModelSet: String?
    var shouldThrow: TranscriptionError?
    var setModelShouldSucceed = true

    var transcribeCalled: Bool { lock.withLock { _transcribeCalled } }
    var lastMeetingID: String? { lock.withLock { _lastMeetingID } }
    var lastBuffers: [AVAudioPCMBuffer]? { lock.withLock { _lastBuffers } }
    var checkForStaleMeetingsCalled: Bool { lock.withLock { _checkForStaleMeetingsCalled } }
    var setModelCalled: Bool { lock.withLock { _setModelCalled } }
    var lastModelSet: String? { lock.withLock { _lastModelSet } }

    func transcribe(meetingID: String, audioBuffers: [AVAudioPCMBuffer]) async throws(TranscriptionError) {
        lock.withLock {
            _transcribeCalled = true
            _lastMeetingID = meetingID
            _lastBuffers = audioBuffers
        }
        if let error = shouldThrow {
            throw error
        }
    }

    func setStateHandler(_ handler: @escaping @MainActor @Sendable (RecordingState) -> Void) async {}

    func checkForStaleMeetings() async {
        lock.withLock { _checkForStaleMeetingsCalled = true }
    }

    @discardableResult
    func setModel(_ modelName: String) async -> Bool {
        lock.withLock {
            _setModelCalled = true
            _lastModelSet = modelName
        }
        return setModelShouldSucceed
    }
}
