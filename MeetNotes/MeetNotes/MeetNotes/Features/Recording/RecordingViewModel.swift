import Foundation
import Observation
import os

private let logger = Logger(subsystem: "com.kuamatzin.meet-notes", category: "RecordingViewModel")

@Observable @MainActor final class RecordingViewModel {
    internal(set) var state: RecordingState = .idle

    private let permissionService: any PermissionChecking
    private let recordingService: any RecordingServiceProtocol
    private let appErrorState: AppErrorState
    private var stateHandlerConfigured = false

    init(
        permissionService: any PermissionChecking = PermissionService(),
        recordingService: any RecordingServiceProtocol = StubRecordingService(),
        appErrorState: AppErrorState = AppErrorState()
    ) {
        self.permissionService = permissionService
        self.recordingService = recordingService
        self.appErrorState = appErrorState
    }

    var elapsedTime: TimeInterval {
        guard case .recording(let startedAt, _) = state else { return 0 }
        return Date().timeIntervalSince(startedAt)
    }

    var formattedElapsedTime: String {
        let total = Int(elapsedTime)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    func startRecording() async {
        await ensureStateHandler()
        if case .error = state {
            state = .idle
        }
        guard state.isIdle else { return }
        guard permissionService.microphoneStatus == .authorized else {
            appErrorState.post(.microphonePermissionDenied)
            logger.warning("Recording blocked: microphone permission denied")
            return
        }
        guard permissionService.screenRecordingStatus == .authorized else {
            appErrorState.post(.screenRecordingPermissionDenied)
            logger.warning("Recording blocked: screen recording permission denied")
            return
        }
        do {
            try await recordingService.start()
            logger.info("Recording started")
        } catch {
            let appError: AppError = switch error {
            case .audioTapCreationFailed, .aggregateDeviceCreationFailed: .audioCaptureFailed
            case .microphoneSetupFailed: .microphoneSetupFailed
            case .audioFormatError: .audioFormatError
            case .startFailed: .recordingFailed
            }
            state = .error(appError)
            appErrorState.post(appError)
            logger.error("Recording failed to start: \(error)")
        }
    }

    func stopRecording() async {
        guard state.isRecording else { return }
        await recordingService.stop()
        logger.info("Recording stopped")
    }

    private func ensureStateHandler() async {
        guard !stateHandlerConfigured else { return }
        await recordingService.setStateHandler { [weak self] state in
            self?.state = state
        }
        await recordingService.setErrorHandler { [weak self] error in
            self?.appErrorState.post(error)
        }
        stateHandlerConfigured = true
    }
}
