import os

private let logger = Logger(subsystem: "com.kuamatzin.meet-notes", category: "StubRecordingService")

final class StubRecordingService: RecordingServiceProtocol, Sendable {
    let currentAudioQuality: AudioQuality = .full

    func start() async throws(RecordingError) {
        logger.info("Stub: recording started")
    }

    func stop() async {
        logger.info("Stub: recording stopped")
    }

    func setStateHandler(_ handler: @escaping @MainActor @Sendable (RecordingState) -> Void) async {}
    func setErrorHandler(_ handler: @escaping @MainActor @Sendable (AppError) -> Void) async {}
    func handleSleep() async {}
    func handleWake() async {}
}
