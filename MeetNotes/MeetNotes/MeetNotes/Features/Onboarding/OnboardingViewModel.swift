import Foundation
import Observation
import os

private let logger = Logger(subsystem: "com.kuamatzin.meet-notes", category: "OnboardingViewModel")

@Observable @MainActor final class OnboardingViewModel {
    var currentStep: OnboardingStep = .welcome
    var testRecordingState: TestRecordingState = .idle

    private let permissionService: any PermissionChecking
    private let testRecorder: any OnboardingTestRecorder
    private let userDefaults: UserDefaults

    init(
        permissionService: any PermissionChecking,
        testRecorder: any OnboardingTestRecorder = SimulatedTestRecorder(),
        userDefaults: UserDefaults = .standard
    ) {
        self.permissionService = permissionService
        self.testRecorder = testRecorder
        self.userDefaults = userDefaults
    }

    var micPermissionGranted: Bool { permissionService.microphoneStatus.isGranted }
    var screenPermissionGranted: Bool { permissionService.screenRecordingStatus.isGranted }
    var allPermissionsGranted: Bool { micPermissionGranted && screenPermissionGranted }

    func advanceStep() {
        switch currentStep {
        case .welcome:
            currentStep = .permissions
            logger.info("Advanced to permissions step")
        case .permissions:
            currentStep = .ready
            logger.info("Advanced to ready step")
        case .ready:
            break
        }
    }

    func requestMicrophonePermission() async {
        await permissionService.requestMicrophone()
        logger.info("Microphone permission requested")
    }

    func requestScreenRecordingPermission() {
        permissionService.requestScreenRecording()
        logger.info("Screen recording permission requested")
    }

    func confirmScreenRecordingGranted() {
        permissionService.acknowledgeScreenRecordingGranted()
        logger.info("User confirmed screen recording permission granted")
    }

    func runTestRecording() async {
        testRecordingState = .recording
        let result = await testRecorder.runTestRecording()
        switch result {
        case .success(let snippet):
            testRecordingState = .completed(snippet)
            logger.info("Test recording completed successfully")
        case .failed(let reason):
            testRecordingState = .unavailable(reason)
            logger.warning("Test recording failed: \(reason)")
        case .unavailable:
            testRecordingState = .unavailable("Test recording will be available after audio services are configured")
            logger.info("Test recording unavailable — stub active")
        }
    }

    func completeOnboarding() {
        userDefaults.set(true, forKey: "hasCompletedOnboarding")
        logger.info("Onboarding completed")
    }
}
