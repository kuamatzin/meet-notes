import Foundation
import Observation
import Testing
@testable import MeetNotes

final class MockRecordingService: RecordingServiceProtocol, @unchecked Sendable {
    var startCallCount = 0
    var stopCalled = false
    var shouldThrowOnStart = false
    var errorToThrow: RecordingError?
    var stateHandler: (@MainActor @Sendable (RecordingState) -> Void)?
    var errorHandler: (@MainActor @Sendable (AppError) -> Void)?
    var handleSleepCalled = false
    var handleWakeCalled = false
    var currentAudioQuality: AudioQuality = .full

    func start() async throws(RecordingError) {
        startCallCount += 1
        if let error = errorToThrow {
            throw error
        }
        if shouldThrowOnStart {
            throw .startFailed
        }
        await MainActor.run { [stateHandler] in
            stateHandler?(.recording(startedAt: Date(), audioQuality: .full))
        }
    }

    func stop() async {
        stopCalled = true
        await MainActor.run { [stateHandler] in
            stateHandler?(.idle)
        }
    }

    func setStateHandler(_ handler: @escaping @MainActor @Sendable (RecordingState) -> Void) async {
        stateHandler = handler
    }

    func setErrorHandler(_ handler: @escaping @MainActor @Sendable (AppError) -> Void) async {
        errorHandler = handler
    }

    func handleSleep() async {
        handleSleepCalled = true
    }

    func handleWake() async {
        handleWakeCalled = true
    }
}

@MainActor
struct RecordingViewModelTests {
    private func makeSUT(
        permissionService: MockPermissionService = MockPermissionService(),
        recordingService: MockRecordingService = MockRecordingService(),
        appErrorState: AppErrorState = AppErrorState()
    ) async -> (vm: RecordingViewModel, permissions: MockPermissionService, recording: MockRecordingService, errors: AppErrorState) {
        let vm = RecordingViewModel(
            permissionService: permissionService,
            recordingService: recordingService,
            appErrorState: appErrorState
        )
        await recordingService.setStateHandler { [weak vm] state in
            vm?.state = state
        }
        return (vm, permissionService, recordingService, appErrorState)
    }

    // MARK: - Initial State

    @Test func initialStateIsIdle() async {
        let (vm, _, _, _) = await makeSUT()
        #expect(vm.state == .idle)
    }

    // MARK: - Start Recording

    @Test func startRecordingTransitionsToRecordingWhenPermissionsGranted() async {
        let (vm, permissions, recording, _) = await makeSUT()
        permissions.microphoneStatus = .authorized
        permissions.screenRecordingStatus = .authorized

        await vm.startRecording()

        #expect(recording.startCallCount == 1)
        #expect(vm.state.isRecording == true)
    }

    @Test func startRecordingPostsErrorWhenMicrophoneDenied() async {
        let (vm, permissions, recording, errors) = await makeSUT()
        permissions.microphoneStatus = .denied
        permissions.screenRecordingStatus = .authorized

        await vm.startRecording()

        #expect(recording.startCallCount == 0)
        #expect(vm.state == .idle)
        #expect(errors.current == .microphonePermissionDenied)
    }

    @Test func startRecordingPostsErrorWhenScreenRecordingDenied() async {
        let (vm, permissions, recording, errors) = await makeSUT()
        permissions.microphoneStatus = .authorized
        permissions.screenRecordingStatus = .denied

        await vm.startRecording()

        #expect(recording.startCallCount == 0)
        #expect(vm.state == .idle)
        #expect(errors.current == .screenRecordingPermissionDenied)
    }

    @Test func startRecordingTransitionsToErrorWhenServiceThrows() async {
        let recording = MockRecordingService()
        recording.shouldThrowOnStart = true
        let permissions = MockPermissionService()
        permissions.microphoneStatus = .authorized
        permissions.screenRecordingStatus = .authorized
        let errors = AppErrorState()

        let vm = RecordingViewModel(
            permissionService: permissions,
            recordingService: recording,
            appErrorState: errors
        )
        await recording.setStateHandler { [weak vm] state in
            vm?.state = state
        }

        await vm.startRecording()

        #expect(recording.startCallCount == 1)
        #expect(vm.state == .error(.recordingFailed))
        #expect(errors.current == .recordingFailed)
    }

    @Test func startRecordingWhileRecordingIsIgnored() async {
        let (vm, permissions, recording, _) = await makeSUT()
        permissions.microphoneStatus = .authorized
        permissions.screenRecordingStatus = .authorized

        await vm.startRecording()
        #expect(vm.state.isRecording == true)
        #expect(recording.startCallCount == 1)

        await vm.startRecording()
        #expect(vm.state.isRecording == true)
        #expect(recording.startCallCount == 1)
    }

    @Test func startRecordingMapsAudioTapErrorToAppError() async {
        let recording = MockRecordingService()
        recording.errorToThrow = .audioTapCreationFailed
        let permissions = MockPermissionService()
        permissions.microphoneStatus = .authorized
        permissions.screenRecordingStatus = .authorized
        let errors = AppErrorState()

        let vm = RecordingViewModel(
            permissionService: permissions,
            recordingService: recording,
            appErrorState: errors
        )

        await vm.startRecording()

        #expect(vm.state == .error(.audioCaptureFailed))
        #expect(errors.current == .audioCaptureFailed)
    }

    @Test func startRecordingMapsMicErrorToAppError() async {
        let recording = MockRecordingService()
        recording.errorToThrow = .microphoneSetupFailed
        let permissions = MockPermissionService()
        permissions.microphoneStatus = .authorized
        permissions.screenRecordingStatus = .authorized
        let errors = AppErrorState()

        let vm = RecordingViewModel(
            permissionService: permissions,
            recordingService: recording,
            appErrorState: errors
        )

        await vm.startRecording()

        #expect(vm.state == .error(.microphoneSetupFailed))
        #expect(errors.current == .microphoneSetupFailed)
    }

    @Test func canRetryAfterError() async {
        let recording = MockRecordingService()
        recording.shouldThrowOnStart = true
        let permissions = MockPermissionService()
        permissions.microphoneStatus = .authorized
        permissions.screenRecordingStatus = .authorized

        let vm = RecordingViewModel(
            permissionService: permissions,
            recordingService: recording,
            appErrorState: AppErrorState()
        )
        await recording.setStateHandler { [weak vm] state in
            vm?.state = state
        }

        await vm.startRecording()
        #expect(vm.state == .error(.recordingFailed))

        recording.shouldThrowOnStart = false
        await vm.startRecording()
        #expect(vm.state.isRecording == true)
        #expect(recording.startCallCount == 2)
    }

    // MARK: - Stop Recording

    @Test func stopRecordingTransitionsToIdle() async {
        let (vm, permissions, recording, _) = await makeSUT()
        permissions.microphoneStatus = .authorized
        permissions.screenRecordingStatus = .authorized

        await vm.startRecording()
        #expect(vm.state.isRecording == true)

        await vm.stopRecording()

        #expect(recording.stopCalled == true)
        #expect(vm.state == .idle)
    }

    @Test func stopRecordingWhileIdleIsIgnored() async {
        let (vm, _, recording, _) = await makeSUT()
        #expect(vm.state == .idle)

        await vm.stopRecording()

        #expect(vm.state == .idle)
        #expect(recording.stopCalled == false)
    }

    // MARK: - Elapsed Time

    @Test func elapsedTimeReturnsZeroWhenIdle() async {
        let (vm, _, _, _) = await makeSUT()
        #expect(vm.elapsedTime == 0)
    }

    @Test func formattedElapsedTimeReturnsZeroFormatWhenIdle() async {
        let (vm, _, _, _) = await makeSUT()
        #expect(vm.formattedElapsedTime == "00:00")
    }

    @Test func elapsedTimeIsPositiveWhenRecording() async {
        let (vm, permissions, _, _) = await makeSUT()
        permissions.microphoneStatus = .authorized
        permissions.screenRecordingStatus = .authorized

        await vm.startRecording()

        #expect(vm.elapsedTime >= 0)
    }

    // MARK: - State Propagation

    @Test func stateChangesAreObservable() async {
        let (vm, permissions, _, _) = await makeSUT()
        permissions.microphoneStatus = .authorized
        permissions.screenRecordingStatus = .authorized

        #expect(vm.state == .idle)

        await vm.startRecording()
        #expect(vm.state.isRecording == true)

        await vm.stopRecording()
        #expect(vm.state == .idle)
    }
}
