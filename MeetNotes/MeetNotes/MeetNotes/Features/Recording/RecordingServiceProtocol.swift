enum RecordingError: Error, Equatable, Sendable {
    case startFailed
    case audioTapCreationFailed
    case microphoneSetupFailed
    case aggregateDeviceCreationFailed
    case audioFormatError
}

protocol RecordingServiceProtocol: Sendable {
    func start() async throws(RecordingError)
    func stop() async
    func setStateHandler(_ handler: @escaping @MainActor @Sendable (RecordingState) -> Void) async
    func setErrorHandler(_ handler: @escaping @MainActor @Sendable (AppError) -> Void) async
    func handleSleep() async
    func handleWake() async
    var currentAudioQuality: AudioQuality { get async }
}
