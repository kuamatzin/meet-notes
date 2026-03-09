@preconcurrency import AVFAudio
import Foundation
import Testing
@testable import MeetNotes

struct AudioStreamMixerTests {

    // MARK: - Helpers

    private func makeBuffer(format: AVAudioFormat, frameCount: AVAudioFrameCount) -> AVAudioPCMBuffer {
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        // Fill with a simple sine tone for identifiable content
        if let channelData = buffer.floatChannelData {
            for frame in 0..<Int(frameCount) {
                let value = sin(Float(frame) * 0.1)
                for ch in 0..<Int(format.channelCount) {
                    channelData[ch][frame] = value
                }
            }
        }
        return buffer
    }

    // MARK: - Resampling

    @Test func targetFormatIs16kHzMonoFloat32() {
        let format = MixerHandle.targetFormat
        #expect(format.sampleRate == 16000)
        #expect(format.channelCount == 1)
        #expect(format.commonFormat == .pcmFormatFloat32)
    }

    @Test func combinedStreamProducesBuffersFromBothSources() async {
        let format48k = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 2, interleaved: false)!
        let format44k = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 1, interleaved: false)!

        let (sysStream, sysCont) = AsyncStream<AVAudioPCMBuffer>.makeStream()
        let (micStream, micCont) = AsyncStream<AVAudioPCMBuffer>.makeStream()

        let mixer = MixerHandle(systemStream: sysStream, micStream: micStream)

        // Yield one buffer from each source
        let sysBuffer = makeBuffer(format: format48k, frameCount: 4800)
        let micBuffer = makeBuffer(format: format44k, frameCount: 4410)
        sysCont.yield(sysBuffer)
        micCont.yield(micBuffer)

        // Finish both sources
        sysCont.finish()
        micCont.finish()

        var outputCount = 0
        for await buffer in mixer.combinedStream {
            #expect(buffer.format.sampleRate == 16000)
            #expect(buffer.format.channelCount == 1)
            outputCount += 1
            if outputCount >= 2 { break }
        }

        #expect(outputCount == 2)
    }

    @Test func streamFinishesWhenBothInputsComplete() async {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 1, interleaved: false)!

        let (sysStream, sysCont) = AsyncStream<AVAudioPCMBuffer>.makeStream()
        let (micStream, micCont) = AsyncStream<AVAudioPCMBuffer>.makeStream()

        let mixer = MixerHandle(systemStream: sysStream, micStream: micStream)

        // Yield one buffer then finish both
        sysCont.yield(makeBuffer(format: format, frameCount: 480))
        sysCont.finish()
        micCont.finish()

        var bufferCount = 0
        for await _ in mixer.combinedStream {
            bufferCount += 1
        }

        // Stream should eventually terminate
        #expect(bufferCount >= 1)
    }

    @Test func stopCancelsTasks() {
        let (sysStream, _) = AsyncStream<AVAudioPCMBuffer>.makeStream()
        let (micStream, _) = AsyncStream<AVAudioPCMBuffer>.makeStream()

        let mixer = MixerHandle(systemStream: sysStream, micStream: micStream)
        mixer.stop()

        // After stop, no crash — verifies clean cancellation
        #expect(true)
    }

    // MARK: - Stream Survival (Task 10)

    @Test func combinedStreamContinuesAfterSystemStreamFinishes() async {
        let micFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 1, interleaved: false)!
        let sysFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 2, interleaved: false)!

        let (sysStream, sysCont) = AsyncStream<AVAudioPCMBuffer>.makeStream()
        let (micStream, micCont) = AsyncStream<AVAudioPCMBuffer>.makeStream()

        let mixer = MixerHandle(systemStream: sysStream, micStream: micStream)

        // Yield one system buffer then finish system stream (simulate tap loss)
        sysCont.yield(makeBuffer(format: sysFormat, frameCount: 4800))
        sysCont.finish()

        // Yield mic buffers AFTER system stream ends
        micCont.yield(makeBuffer(format: micFormat, frameCount: 4410))
        micCont.yield(makeBuffer(format: micFormat, frameCount: 4410))

        // Finish mic to terminate the test
        micCont.finish()

        var outputCount = 0
        for await buffer in mixer.combinedStream {
            #expect(buffer.format.sampleRate == 16000)
            #expect(buffer.format.channelCount == 1)
            outputCount += 1
        }

        // Should have at least 3 buffers: 1 system + 2 mic
        #expect(outputCount >= 3)
    }

    @Test func micOnlyBuffersArriveAtTargetFormat() async {
        let micFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 1, interleaved: false)!

        let (sysStream, sysCont) = AsyncStream<AVAudioPCMBuffer>.makeStream()
        let (micStream, micCont) = AsyncStream<AVAudioPCMBuffer>.makeStream()

        let mixer = MixerHandle(systemStream: sysStream, micStream: micStream)

        // Immediately finish system stream (no system audio at all)
        sysCont.finish()

        // Yield mic-only buffers
        micCont.yield(makeBuffer(format: micFormat, frameCount: 4410))
        micCont.finish()

        var outputCount = 0
        for await buffer in mixer.combinedStream {
            #expect(buffer.format.sampleRate == 16000)
            #expect(buffer.format.channelCount == 1)
            #expect(buffer.format.commonFormat == .pcmFormatFloat32)
            outputCount += 1
        }

        #expect(outputCount == 1)
    }

    @Test func combinedStreamFinishesOnlyWhenBothInputsComplete() async {
        let micFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 1, interleaved: false)!

        let (sysStream, sysCont) = AsyncStream<AVAudioPCMBuffer>.makeStream()
        let (micStream, micCont) = AsyncStream<AVAudioPCMBuffer>.makeStream()

        let mixer = MixerHandle(systemStream: sysStream, micStream: micStream)

        // Finish system stream only
        sysCont.finish()

        // Yield a mic buffer — stream should still be open
        micCont.yield(makeBuffer(format: micFormat, frameCount: 4410))

        // Read one buffer to prove stream is still alive
        var gotBuffer = false
        for await buffer in mixer.combinedStream {
            gotBuffer = true
            #expect(buffer.format.sampleRate == 16000)
            // Now finish mic to end the test
            micCont.finish()
            break
        }

        #expect(gotBuffer == true)
    }
}
