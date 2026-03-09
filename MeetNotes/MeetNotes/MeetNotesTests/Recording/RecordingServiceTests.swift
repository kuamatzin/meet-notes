@preconcurrency import AVFAudio
import Foundation
import Testing
@testable import MeetNotes

// MARK: - Mock System Audio Capture

nonisolated final class MockSystemAudioCapture: SystemAudioCaptureProtocol, @unchecked Sendable {
    let audioStream: AsyncStream<AVAudioPCMBuffer>
    private let continuation: AsyncStream<AVAudioPCMBuffer>.Continuation

    var startCalled = false
    var stopCalled = false
    var pauseCalled = false
    var resumeCalled = false
    var receivedProcessObjectID: AudioObjectID??
    var shouldThrow = false
    var tapHealthy = true
    var shouldThrowOnResume = false

    init() {
        let (stream, cont) = AsyncStream<AVAudioPCMBuffer>.makeStream()
        self.audioStream = stream
        self.continuation = cont
    }

    func start(processObjectID: AudioObjectID?) throws(RecordingError) {
        startCalled = true
        receivedProcessObjectID = processObjectID
        if shouldThrow {
            throw .audioTapCreationFailed
        }
    }

    func stop() {
        stopCalled = true
        continuation.finish()
    }

    func isTapHealthy() -> Bool {
        tapHealthy
    }

    func pause() {
        pauseCalled = true
    }

    func resume() throws(RecordingError) {
        resumeCalled = true
        if shouldThrowOnResume {
            throw .audioTapCreationFailed
        }
    }

    func yieldBuffer(_ buffer: AVAudioPCMBuffer) {
        continuation.yield(buffer)
    }

    func finishStream() {
        continuation.finish()
    }
}

// MARK: - Mock Microphone Capture

nonisolated final class MockMicrophoneCapture: MicrophoneCaptureProtocol, @unchecked Sendable {
    let audioStream: AsyncStream<AVAudioPCMBuffer>
    private let continuation: AsyncStream<AVAudioPCMBuffer>.Continuation

    var startCalled = false
    var stopCalled = false
    var shouldThrow = false

    init() {
        let (stream, cont) = AsyncStream<AVAudioPCMBuffer>.makeStream()
        self.audioStream = stream
        self.continuation = cont
    }

    func start() throws(RecordingError) {
        startCalled = true
        if shouldThrow {
            throw .microphoneSetupFailed
        }
    }

    func stop() {
        stopCalled = true
        continuation.finish()
    }
}

// MARK: - Tests

@MainActor
struct RecordingServiceTests {

    private func makeSUT(healthCheckInterval: Duration = .seconds(1)) -> (service: RecordingService, sys: MockSystemAudioCapture, mic: MockMicrophoneCapture) {
        let sys = MockSystemAudioCapture()
        let mic = MockMicrophoneCapture()
        let service = RecordingService(
            systemCaptureFactory: { sys },
            micCaptureFactory: { mic },
            healthCheckInterval: healthCheckInterval
        )
        return (service, sys, mic)
    }

    // MARK: - Start

    @Test func startCallsSystemAndMicCapture() async throws {
        let (service, sys, mic) = makeSUT()

        try await service.start()

        #expect(sys.startCalled == true)
        #expect(mic.startCalled == true)
    }

    @Test func startUpdatesStateToRecording() async throws {
        let (service, _, _) = makeSUT()
        var receivedState: RecordingState?
        await service.setStateHandler { state in
            receivedState = state
        }

        try await service.start()

        #expect(receivedState?.isRecording == true)
    }

    @Test func startThrowsWhenSystemCaptureFails() async {
        let (service, sys, _) = makeSUT()
        sys.shouldThrow = true

        do {
            try await service.start()
            Issue.record("Expected audioTapCreationFailed error")
        } catch {
            #expect(error == .audioTapCreationFailed)
        }
    }

    @Test func startThrowsWhenMicCaptureFails() async {
        let (service, _, mic) = makeSUT()
        mic.shouldThrow = true

        do {
            try await service.start()
            Issue.record("Expected microphoneSetupFailed error")
        } catch {
            #expect(error == .microphoneSetupFailed)
        }
    }

    @Test func startCleansUpSystemCaptureWhenMicFails() async {
        let (service, sys, mic) = makeSUT()
        mic.shouldThrow = true

        do {
            try await service.start()
            Issue.record("Expected microphoneSetupFailed error")
        } catch {
            #expect(error == .microphoneSetupFailed)
        }

        #expect(sys.startCalled == true)
        #expect(sys.stopCalled == true)
    }

    // MARK: - Stop

    @Test func stopTearsDownBothCaptures() async throws {
        let (service, sys, mic) = makeSUT()

        try await service.start()
        await service.stop()

        #expect(sys.stopCalled == true)
        #expect(mic.stopCalled == true)
    }

    @Test func stopUpdatesStateToIdle() async throws {
        let (service, _, _) = makeSUT()
        var receivedStates: [RecordingState] = []
        await service.setStateHandler { state in
            receivedStates.append(state)
        }

        try await service.start()
        await service.stop()

        #expect(receivedStates.count == 2)
        #expect(receivedStates.last == .idle)
    }

    // MARK: - State Handler

    @Test func stateHandlerReceivesRecordingOnStart() async throws {
        let (service, _, _) = makeSUT()
        var receivedState: RecordingState?
        await service.setStateHandler { state in
            receivedState = state
        }

        try await service.start()

        guard case .recording(_, let quality) = receivedState else {
            Issue.record("Expected recording state, got \(String(describing: receivedState))")
            return
        }
        #expect(quality == .full)
    }

    @Test func stateHandlerReceivesIdleOnStop() async throws {
        let (service, _, _) = makeSUT()
        var lastState: RecordingState?
        await service.setStateHandler { state in
            lastState = state
        }

        try await service.start()
        await service.stop()

        #expect(lastState == .idle)
    }

    // MARK: - Concurrency Compliance

    @Test func recordingServiceConformsToProtocol() {
        let service: any RecordingServiceProtocol = RecordingService()
        #expect(service is RecordingService)
    }

    // MARK: - Tap Health Monitoring (Task 8)

    @Test func tapLossTriggersStateTransitionToMicOnly() async throws {
        let (service, sys, _) = makeSUT(healthCheckInterval: .milliseconds(50))
        var receivedStates: [RecordingState] = []
        await service.setStateHandler { state in
            receivedStates.append(state)
        }

        try await service.start()
        #expect(receivedStates.count == 1)

        // Simulate tap loss by marking tap unhealthy
        sys.tapHealthy = false

        // Wait for the health monitor to detect the loss
        try await Task.sleep(for: .milliseconds(200))

        // Should have transitioned to .recording(.micOnly)
        let micOnlyStates = receivedStates.filter {
            if case .recording(_, .micOnly) = $0 { return true }
            return false
        }
        #expect(micOnlyStates.count == 1)
    }

    @Test func tapLossPostsAudioTapLostError() async throws {
        let (service, sys, _) = makeSUT(healthCheckInterval: .milliseconds(50))
        var receivedError: AppError?
        await service.setStateHandler { _ in }
        await service.setErrorHandler { error in
            receivedError = error
        }

        try await service.start()
        sys.tapHealthy = false

        try await Task.sleep(for: .milliseconds(200))

        #expect(receivedError == .audioTapLost)
    }

    @Test func tapLossStopsSystemCaptureOnly() async throws {
        let (service, sys, mic) = makeSUT(healthCheckInterval: .milliseconds(50))
        await service.setStateHandler { _ in }

        try await service.start()
        sys.tapHealthy = false

        try await Task.sleep(for: .milliseconds(200))

        #expect(sys.stopCalled == true)
        #expect(mic.stopCalled == false)
    }

    @Test func audioQualityStartsAtFull() async throws {
        let (service, _, _) = makeSUT()
        try await service.start()
        let quality = await service.currentAudioQuality
        #expect(quality == .full)
    }

    @Test func audioQualityDegradesToMicOnlyOnTapLoss() async throws {
        let (service, sys, _) = makeSUT(healthCheckInterval: .milliseconds(50))
        await service.setStateHandler { _ in }
        try await service.start()

        sys.tapHealthy = false
        try await Task.sleep(for: .milliseconds(200))

        let quality = await service.currentAudioQuality
        #expect(quality == .micOnly)
    }

    // MARK: - Sleep/Wake (Task 9)

    @Test func handleSleepPausesSystemCapture() async throws {
        let (service, sys, _) = makeSUT()
        try await service.start()

        await service.handleSleep()

        #expect(sys.pauseCalled == true)
    }

    @Test func handleWakeResumesSystemCapture() async throws {
        let (service, sys, _) = makeSUT()
        try await service.start()

        await service.handleSleep()
        await service.handleWake()

        #expect(sys.resumeCalled == true)
    }

    @Test func handleWakeDegradesToMicOnlyWhenResumeFails() async throws {
        let (service, sys, _) = makeSUT()
        var receivedStates: [RecordingState] = []
        await service.setStateHandler { state in
            receivedStates.append(state)
        }
        await service.setErrorHandler { _ in }

        try await service.start()
        sys.shouldThrowOnResume = true

        await service.handleSleep()
        await service.handleWake()

        let quality = await service.currentAudioQuality
        #expect(quality == .micOnly)
        #expect(sys.stopCalled == true)
    }

    @Test func recordingStatePreservedAcrossSleepWake() async throws {
        let (service, _, _) = makeSUT()
        var lastState: RecordingState?
        await service.setStateHandler { state in
            lastState = state
        }

        try await service.start()
        let startState = lastState

        await service.handleSleep()
        await service.handleWake()

        // State should still be recording (quality may be same or partial)
        #expect(lastState?.isRecording == true)
        // Started-at time should be preserved
        if case .recording(let startedAt1, _) = startState,
           case .recording(let startedAt2, _) = lastState {
            #expect(startedAt1 == startedAt2)
        }
    }
}
