@preconcurrency import AVFAudio
import Foundation
@preconcurrency import WhisperKit

enum TranscriptionError: Error, Equatable, Sendable {
    case modelNotLoaded
    case transcriptionFailed(String)
    case databaseWriteFailed

    static func == (lhs: TranscriptionError, rhs: TranscriptionError) -> Bool {
        switch (lhs, rhs) {
        case (.modelNotLoaded, .modelNotLoaded): true
        case (.databaseWriteFailed, .databaseWriteFailed): true
        case (.transcriptionFailed(let a), .transcriptionFailed(let b)): a == b
        default: false
        }
    }
}

protocol TranscriptionServiceProtocol: Sendable {
    func transcribe(meetingID: String, audioBuffers: [AVAudioPCMBuffer]) async throws(TranscriptionError)
    func setStateHandler(_ handler: @escaping @MainActor @Sendable (RecordingState) -> Void) async
    func checkForStaleMeetings() async
    @discardableResult
    func setModel(_ modelName: String) async -> Bool
    func setLanguage(_ language: String?) async
}

struct TranscriptionSegmentResult: Sendable {
    let start: Float
    let end: Float
    let text: String
    let avgLogprob: Float
}

protocol WhisperKitProviding: Sendable {
    func transcribe(audioArray: [Float], language: String?, segmentCallback: (@Sendable ([TranscriptionSegmentResult]) -> Void)?) async throws -> [[TranscriptionSegmentResult]]
}

extension WhisperKit: @retroactive @unchecked Sendable {}

struct WhisperKitProvider: WhisperKitProviding, Sendable {
    private let pipe: WhisperKit

    init(pipe: WhisperKit) {
        self.pipe = pipe
    }

    func transcribe(audioArray: [Float], language: String?, segmentCallback: (@Sendable ([TranscriptionSegmentResult]) -> Void)?) async throws -> [[TranscriptionSegmentResult]] {
        let options = DecodingOptions(
            task: .transcribe,
            language: language,
            usePrefillPrompt: language != nil,
            usePrefillCache: false,
            detectLanguage: language == nil,
            skipSpecialTokens: true
        )

        let results = try await pipe.transcribe(
            audioArray: audioArray,
            decodeOptions: options
        )

        let mapped = results.map { result in
            result.segments.map { seg in
                TranscriptionSegmentResult(start: seg.start, end: seg.end, text: seg.text, avgLogprob: seg.avgLogprob)
            }
        }

        if let allSegments = mapped.first {
            segmentCallback?(allSegments)
        }

        return mapped
    }
}
