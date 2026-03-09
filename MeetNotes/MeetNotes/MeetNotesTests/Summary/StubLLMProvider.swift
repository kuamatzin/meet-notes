@testable import MeetNotes

actor StubLLMProvider: LLMSummaryProvider {
    var responseToReturn: String = "## Decisions\n- No decisions recorded.\n\n## Action Items\n- No action items identified.\n\n## Key Topics\n- Discussed project timeline"
    var errorToThrow: SummaryError?
    var streamChunks: [String]?

    nonisolated func summarize(transcript: String) async throws(SummaryError) -> String {
        let error = await errorToThrow
        if let error {
            throw error
        }
        return await responseToReturn
    }

    nonisolated func summarizeStreaming(transcript: String) -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            Task {
                let errorToThrow = await self.errorToThrow
                if let error = errorToThrow {
                    continuation.finish(throwing: error)
                    return
                }
                let response = await self.responseToReturn
                let chunks = await self.streamChunks
                let resolvedChunks = chunks ?? [response]
                for chunk in resolvedChunks {
                    continuation.yield(chunk)
                }
                continuation.finish()
            }
        }
    }

    func setResponse(_ response: String) {
        responseToReturn = response
    }

    func setError(_ error: SummaryError) {
        errorToThrow = error
    }

    func setStreamChunks(_ chunks: [String]) {
        streamChunks = chunks
    }
}
