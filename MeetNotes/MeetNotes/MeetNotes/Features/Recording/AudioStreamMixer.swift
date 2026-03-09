@preconcurrency import AVFAudio
import os

extension AVAudioPCMBuffer: @unchecked @retroactive Sendable {}

nonisolated final class MixerHandle: @unchecked Sendable {
    static let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )!

    let combinedStream: AsyncStream<AVAudioPCMBuffer>
    private var sysTask: Task<Void, Never>?
    private var micTask: Task<Void, Never>?
    private let continuation: AsyncStream<AVAudioPCMBuffer>.Continuation
    private var accumulatedBuffers: [AVAudioPCMBuffer] = []
    private let bufferLock = NSLock()

    init(systemStream: AsyncStream<AVAudioPCMBuffer>, micStream: AsyncStream<AVAudioPCMBuffer>) {
        let (stream, cont) = AsyncStream<AVAudioPCMBuffer>.makeStream()
        self.combinedStream = stream
        self.continuation = cont

        let finishCount = FinishCounter()

        self.sysTask = Task.detached { [weak self] in
            var converter: AVAudioConverter?
            for await buffer in systemStream {
                guard !Task.isCancelled else { break }
                if converter == nil {
                    converter = AVAudioConverter(from: buffer.format, to: MixerHandle.targetFormat)
                }
                guard let converter else { continue }
                if let resampled = MixerHandle.resample(buffer: buffer, using: converter) {
                    self?.appendBuffer(resampled)
                    cont.yield(resampled)
                }
            }
            if finishCount.increment() == 2 {
                cont.finish()
            }
        }

        self.micTask = Task.detached { [weak self] in
            var converter: AVAudioConverter?
            for await buffer in micStream {
                guard !Task.isCancelled else { break }
                if converter == nil {
                    converter = AVAudioConverter(from: buffer.format, to: MixerHandle.targetFormat)
                }
                guard let converter else { continue }
                if let resampled = MixerHandle.resample(buffer: buffer, using: converter) {
                    self?.appendBuffer(resampled)
                    cont.yield(resampled)
                }
            }
            if finishCount.increment() == 2 {
                cont.finish()
            }
        }
    }

    func stop() {
        sysTask?.cancel()
        micTask?.cancel()
        sysTask = nil
        micTask = nil
        continuation.finish()
    }

    /// Returns all accumulated 16kHz mono Float32 buffers and clears the internal store.
    func finalizeBuffers() -> [AVAudioPCMBuffer] {
        bufferLock.withLock {
            let buffers = accumulatedBuffers
            accumulatedBuffers = []
            return buffers
        }
    }

    private func appendBuffer(_ buffer: AVAudioPCMBuffer) {
        bufferLock.withLock {
            accumulatedBuffers.append(buffer)
        }
    }

    private static func resample(buffer: AVAudioPCMBuffer, using converter: AVAudioConverter) -> AVAudioPCMBuffer? {
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        guard outputFrameCount > 0 else { return nil }

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount) else {
            return nil
        }

        var error: NSError?
        let inputBuffer = buffer
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return inputBuffer
        }

        if error != nil {
            return nil
        }

        return outputBuffer
    }

    deinit {
        sysTask?.cancel()
        micTask?.cancel()
    }
}

private nonisolated final class FinishCounter: @unchecked Sendable {
    private var value = 0
    private let lock = NSLock()

    func increment() -> Int {
        lock.withLock {
            value += 1
            return value
        }
    }
}
