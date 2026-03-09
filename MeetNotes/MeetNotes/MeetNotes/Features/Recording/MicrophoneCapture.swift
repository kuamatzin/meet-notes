@preconcurrency import AVFAudio
import os

nonisolated(unsafe) private let logger = Logger(subsystem: "com.kuamatzin.meet-notes", category: "MicrophoneCapture")

nonisolated protocol MicrophoneCaptureProtocol: Sendable {
    var audioStream: AsyncStream<AVAudioPCMBuffer> { get }
    func start() throws(RecordingError)
    func stop()
}

nonisolated final class MicrophoneCapture: MicrophoneCaptureProtocol, @unchecked Sendable {
    let audioStream: AsyncStream<AVAudioPCMBuffer>
    private let continuation: AsyncStream<AVAudioPCMBuffer>.Continuation
    private let engine = AVAudioEngine()

    init() {
        let (stream, continuation) = AsyncStream<AVAudioPCMBuffer>.makeStream()
        self.audioStream = stream
        self.continuation = continuation
    }

    func start() throws(RecordingError) {
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard inputFormat.sampleRate > 0 else {
            logger.error("Invalid microphone format: sample rate is 0")
            throw .microphoneSetupFailed
        }

        let cont = self.continuation
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            // REAL-TIME THREAD — only yield
            cont.yield(buffer)
        }

        do {
            try engine.start()
        } catch {
            logger.error("AVAudioEngine failed to start: \(error)")
            inputNode.removeTap(onBus: 0)
            throw .microphoneSetupFailed
        }

        logger.info("Microphone capture started (format: \(inputFormat))")
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        continuation.finish()
        logger.info("Microphone capture stopped")
    }
}
