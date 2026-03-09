import Foundation

nonisolated enum RecordingState: Equatable, Sendable {
    case idle
    case recording(startedAt: Date, audioQuality: AudioQuality)
    case processing(meetingID: UUID, phase: ProcessingPhase)
    case error(AppError)
}

nonisolated enum AudioQuality: Equatable, Sendable {
    case full
    case micOnly
    case partial
}

nonisolated enum ProcessingPhase: Equatable, Sendable {
    case transcribing(progress: Double)
    case summarizing
}

extension RecordingState {
    var isIdle: Bool {
        if case .idle = self { return true }
        return false
    }

    var isRecording: Bool {
        if case .recording = self { return true }
        return false
    }
}
