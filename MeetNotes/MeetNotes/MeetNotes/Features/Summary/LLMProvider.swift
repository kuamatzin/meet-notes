import Foundation

nonisolated protocol LLMSummaryProvider: Sendable {
    func summarize(transcript: String) async throws(SummaryError) -> String
    func summarizeStreaming(transcript: String) -> AsyncThrowingStream<String, Error>
}

extension LLMSummaryProvider {
    func summarize(transcript: String) async throws(SummaryError) -> String {
        var result = ""
        do {
            for try await chunk in summarizeStreaming(transcript: transcript) {
                result += chunk
            }
        } catch let error as SummaryError {
            throw error
        } catch {
            throw SummaryError.providerFailure(error)
        }
        return result
    }
}
