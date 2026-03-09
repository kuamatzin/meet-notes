@preconcurrency import AVFAudio
import GRDB
import os

actor RecordingService: RecordingServiceProtocol {
    private nonisolated static let logger = Logger(subsystem: "com.kuamatzin.meet-notes", category: "RecordingService")

    private var onStateChange: (@MainActor @Sendable (RecordingState) -> Void)?
    private var onError: (@MainActor @Sendable (AppError) -> Void)?
    private var systemCapture: (any SystemAudioCaptureProtocol)?
    private var micCapture: (any MicrophoneCaptureProtocol)?
    private var mixerHandle: MixerHandle?
    private var tapMonitorTask: Task<Void, Never>?
    private var recordingStartedAt: Date?
    private let makeSystemCapture: @Sendable () -> any SystemAudioCaptureProtocol
    private let makeMicCapture: @Sendable () -> any MicrophoneCaptureProtocol
    nonisolated let healthCheckInterval: Duration

    private let database: AppDatabase?
    private let transcriptionService: (any TranscriptionServiceProtocol)?

    private(set) var currentAudioQuality: AudioQuality = .full

    var combinedAudioStream: AsyncStream<AVAudioPCMBuffer>? {
        mixerHandle?.combinedStream
    }

    init(
        systemCaptureFactory: @escaping @Sendable () -> any SystemAudioCaptureProtocol = { SystemAudioCapture() },
        micCaptureFactory: @escaping @Sendable () -> any MicrophoneCaptureProtocol = { MicrophoneCapture() },
        healthCheckInterval: Duration = .seconds(1),
        database: AppDatabase? = nil,
        transcriptionService: (any TranscriptionServiceProtocol)? = nil
    ) {
        self.makeSystemCapture = systemCaptureFactory
        self.makeMicCapture = micCaptureFactory
        self.healthCheckInterval = healthCheckInterval
        self.database = database
        self.transcriptionService = transcriptionService
    }

    func setStateHandler(_ handler: @escaping @MainActor @Sendable (RecordingState) -> Void) {
        self.onStateChange = handler
    }

    func setErrorHandler(_ handler: @escaping @MainActor @Sendable (AppError) -> Void) {
        self.onError = handler
    }

    func start() async throws(RecordingError) {
        let processObjectID = AudioProcessDiscovery.findMeetingAppProcess()
        Self.logger.info("Starting recording (target process: \(processObjectID.map { String($0) } ?? "global"))")

        let sysCapture = makeSystemCapture()
        try sysCapture.start(processObjectID: processObjectID)
        self.systemCapture = sysCapture

        let micCap = makeMicCapture()
        do {
            try micCap.start()
        } catch {
            Self.logger.error("Mic capture failed, cleaning up system capture")
            sysCapture.stop()
            self.systemCapture = nil
            throw error
        }
        self.micCapture = micCap

        let handle = MixerHandle(
            systemStream: sysCapture.audioStream,
            micStream: micCap.audioStream
        )
        self.mixerHandle = handle

        currentAudioQuality = .full
        let now = Date()
        recordingStartedAt = now

        startTapHealthMonitor()

        Self.logger.info("Recording started successfully")
        await updateState(.recording(startedAt: now, audioQuality: .full))
    }

    func stop() async {
        tapMonitorTask?.cancel()
        tapMonitorTask = nil

        let audioQuality = currentAudioQuality
        let startedAt = recordingStartedAt
        let buffers = mixerHandle?.finalizeBuffers() ?? []

        systemCapture?.stop()
        systemCapture = nil
        micCapture?.stop()
        micCapture = nil
        mixerHandle?.stop()
        mixerHandle = nil
        recordingStartedAt = nil

        Self.logger.info("Recording stopped, \(buffers.count) buffers accumulated")

        // Create meeting record and start transcription pipeline
        if let database, let transcriptionService {
            let meetingID = UUID().uuidString
            let now = Date()
            let duration = startedAt.map { now.timeIntervalSince($0) }

            let meetingAudioQuality: Meeting.AudioQuality = switch audioQuality {
            case .full: .full
            case .micOnly: .micOnly
            case .partial: .partial
            }

            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            let defaultTitle = "Meeting on \(formatter.string(from: startedAt ?? now))"

            let meeting = Meeting(
                id: meetingID,
                title: defaultTitle,
                startedAt: startedAt ?? now,
                endedAt: now,
                durationSeconds: duration,
                audioQuality: meetingAudioQuality,
                summaryMd: nil,
                pipelineStatus: .recording,
                createdAt: now
            )

            do {
                try await database.pool.write { db in
                    try meeting.insert(db)
                }
                Self.logger.info("Meeting record created: \(meetingID)")
            } catch {
                Self.logger.error("Failed to create meeting record: \(error)")
                await updateState(.idle)
                await postError(.transcriptionFailed)
                return
            }

            // Transition to processing state
            if let uuid = UUID(uuidString: meetingID) {
                await updateState(.processing(meetingID: uuid, phase: .transcribing(progress: 0)))
            }

            // Start transcription in background
            Task {
                do {
                    try await transcriptionService.transcribe(meetingID: meetingID, audioBuffers: buffers)
                } catch {
                    Self.logger.error("Transcription failed: \(error)")
                    await self.postError(.transcriptionFailed)
                    await self.updateState(.idle)
                }
            }
        } else {
            Self.logger.warning("No database or transcription service configured — recording discarded")
            await updateState(.idle)
        }
    }

    func handleSleep() {
        Self.logger.info("System going to sleep — pausing system capture")
        systemCapture?.pause()
    }

    func handleWake() async {
        Self.logger.info("System woke — resuming system capture")
        guard let sysCapture = systemCapture else { return }
        do {
            try sysCapture.resume()
            if currentAudioQuality == .micOnly {
                currentAudioQuality = .partial
                if let startedAt = recordingStartedAt {
                    await updateState(.recording(startedAt: startedAt, audioQuality: .partial))
                }
            }
            Self.logger.info("System capture resumed successfully")
        } catch {
            Self.logger.warning("System capture resume failed — degrading to mic-only")
            await handleTapLoss()
        }
    }

    // MARK: - Private

    private func startTapHealthMonitor() {
        tapMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: self?.healthCheckInterval ?? .seconds(1))
                guard !Task.isCancelled else { break }
                guard let self else { break }
                let healthy = await self.checkTapHealth()
                if !healthy {
                    await self.handleTapLoss()
                    break
                }
            }
        }
    }

    private func checkTapHealth() -> Bool {
        guard let sysCapture = systemCapture else { return false }
        return sysCapture.isTapHealthy()
    }

    private func handleTapLoss() async {
        Self.logger.warning("Tap loss detected — stopping system capture, continuing mic-only")
        systemCapture?.stop()
        systemCapture = nil
        tapMonitorTask?.cancel()
        tapMonitorTask = nil

        currentAudioQuality = .micOnly

        if let startedAt = recordingStartedAt {
            await updateState(.recording(startedAt: startedAt, audioQuality: .micOnly))
        }
        await postError(.audioTapLost)
    }

    private func updateState(_ state: RecordingState) async {
        await MainActor.run { [onStateChange] in
            onStateChange?(state)
        }
    }

    private func postError(_ error: AppError) async {
        await MainActor.run { [onError] in
            onError?(error)
        }
    }
}
