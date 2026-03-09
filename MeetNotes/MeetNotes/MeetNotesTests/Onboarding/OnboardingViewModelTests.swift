import Foundation
import Observation
import Testing
@testable import MeetNotes

@Observable @MainActor final class MockTestRecorder: OnboardingTestRecorder {
    var runTestRecordingCalled = false
    var resultToReturn: TestRecordingResult = .unavailable

    func runTestRecording() async -> TestRecordingResult {
        runTestRecordingCalled = true
        return resultToReturn
    }
}

@MainActor
struct OnboardingViewModelTests {
    private func makeSUT(
        permissionService: MockPermissionService = MockPermissionService(),
        testRecorder: MockTestRecorder = MockTestRecorder(),
        userDefaults: UserDefaults? = nil
    ) -> (vm: OnboardingViewModel, mock: MockPermissionService, recorder: MockTestRecorder, defaults: UserDefaults, cleanup: @Sendable () -> Void) {
        let suiteName = "test-onboarding-\(UUID().uuidString)"
        let defaults = userDefaults ?? UserDefaults(suiteName: suiteName)!
        let vm = OnboardingViewModel(
            permissionService: permissionService,
            testRecorder: testRecorder,
            userDefaults: defaults
        )
        nonisolated(unsafe) let unsafeDefaults = defaults
        let cleanup: @Sendable () -> Void = { unsafeDefaults.removePersistentDomain(forName: suiteName) }
        return (vm, permissionService, testRecorder, defaults, cleanup)
    }

    @Test func currentStepStartsAtWelcome() {
        let (vm, _, _, _, cleanup) = makeSUT()
        defer { cleanup() }
        #expect(vm.currentStep == .welcome)
    }

    @Test func advanceStepFromWelcomeToPermissions() {
        let (vm, _, _, _, cleanup) = makeSUT()
        defer { cleanup() }
        vm.advanceStep()
        #expect(vm.currentStep == .permissions)
    }

    @Test func advanceStepFromPermissionsToReady() {
        let (vm, _, _, _, cleanup) = makeSUT()
        defer { cleanup() }
        vm.advanceStep()
        vm.advanceStep()
        #expect(vm.currentStep == .ready)
    }

    @Test func advanceStepFromReadyDoesNotAdvance() {
        let (vm, _, _, _, cleanup) = makeSUT()
        defer { cleanup() }
        vm.advanceStep()
        vm.advanceStep()
        vm.advanceStep()
        #expect(vm.currentStep == .ready)
    }

    @Test func requestMicrophonePermissionDelegatesToService() async {
        let (vm, mock, _, _, cleanup) = makeSUT()
        defer { cleanup() }
        await vm.requestMicrophonePermission()
        #expect(mock.requestMicrophoneCalled == true)
        #expect(mock.microphoneStatus == .authorized)
    }

    @Test func requestScreenRecordingPermissionDelegatesToService() {
        let (vm, mock, _, _, cleanup) = makeSUT()
        defer { cleanup() }
        vm.requestScreenRecordingPermission()
        #expect(mock.requestScreenRecordingCalled == true)
    }

    @Test func micPermissionGrantedReflectsServiceStatus() {
        let mock = MockPermissionService()
        let (vm, _, _, _, cleanup) = makeSUT(permissionService: mock)
        defer { cleanup() }
        #expect(vm.micPermissionGranted == false)
        mock.microphoneStatus = .authorized
        #expect(vm.micPermissionGranted == true)
    }

    @Test func screenPermissionGrantedReflectsServiceStatus() {
        let mock = MockPermissionService()
        let (vm, _, _, _, cleanup) = makeSUT(permissionService: mock)
        defer { cleanup() }
        #expect(vm.screenPermissionGranted == false)
        mock.screenRecordingStatus = .authorized
        #expect(vm.screenPermissionGranted == true)
    }

    @Test func allPermissionsGrantedRequiresBoth() {
        let mock = MockPermissionService()
        let (vm, _, _, _, cleanup) = makeSUT(permissionService: mock)
        defer { cleanup() }
        #expect(vm.allPermissionsGranted == false)
        mock.microphoneStatus = .authorized
        #expect(vm.allPermissionsGranted == false)
        mock.screenRecordingStatus = .authorized
        #expect(vm.allPermissionsGranted == true)
    }

    @Test func completeOnboardingSetsUserDefaultsFlag() {
        let (vm, _, _, defaults, cleanup) = makeSUT()
        defer { cleanup() }
        #expect(defaults.bool(forKey: "hasCompletedOnboarding") == false)
        vm.completeOnboarding()
        #expect(defaults.bool(forKey: "hasCompletedOnboarding") == true)
    }

    @Test func runTestRecordingWithUnavailableResult() async {
        let recorder = MockTestRecorder()
        recorder.resultToReturn = .unavailable
        let (vm, _, _, _, cleanup) = makeSUT(testRecorder: recorder)
        defer { cleanup() }

        await vm.runTestRecording()
        #expect(recorder.runTestRecordingCalled == true)
        if case .unavailable = vm.testRecordingState {
            // expected
        } else {
            Issue.record("Expected .unavailable state but got \(vm.testRecordingState)")
        }
    }

    @Test func runTestRecordingWithSuccessResult() async {
        let recorder = MockTestRecorder()
        recorder.resultToReturn = .success(transcriptSnippet: "Hello world")
        let (vm, _, _, _, cleanup) = makeSUT(testRecorder: recorder)
        defer { cleanup() }

        await vm.runTestRecording()
        #expect(recorder.runTestRecordingCalled == true)
        if case .completed(let snippet) = vm.testRecordingState {
            #expect(snippet == "Hello world")
        } else {
            Issue.record("Expected .completed state but got \(vm.testRecordingState)")
        }
    }

    @Test func runTestRecordingWithFailedResult() async {
        let recorder = MockTestRecorder()
        recorder.resultToReturn = .failed(reason: "No audio input detected")
        let (vm, _, _, _, cleanup) = makeSUT(testRecorder: recorder)
        defer { cleanup() }

        await vm.runTestRecording()
        #expect(recorder.runTestRecordingCalled == true)
        if case .unavailable(let message) = vm.testRecordingState {
            #expect(message == "No audio input detected")
        } else {
            Issue.record("Expected .unavailable state with reason but got \(vm.testRecordingState)")
        }
    }
}
