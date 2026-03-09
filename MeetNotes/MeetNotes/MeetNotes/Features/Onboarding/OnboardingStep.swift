import Observation

enum OnboardingStep: Sendable {
    case welcome
    case permissions
    case ready
}

enum TestRecordingResult: Sendable {
    case success(transcriptSnippet: String)
    case failed(reason: String)
    case unavailable
}

enum TestRecordingState: Sendable {
    case idle
    case recording
    case completed(String)
    case unavailable(String)
}

@MainActor
protocol OnboardingTestRecorder {
    func runTestRecording() async -> TestRecordingResult
}

@Observable @MainActor final class SimulatedTestRecorder: OnboardingTestRecorder {
    func runTestRecording() async -> TestRecordingResult {
        .unavailable
    }
}
