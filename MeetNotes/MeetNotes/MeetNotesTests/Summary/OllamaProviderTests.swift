import Testing
@testable import MeetNotes

@MainActor
struct OllamaProviderTests {
    // MARK: - Unreachable Ollama

    @Test func unreachableOllamaThrowsOllamaNotReachable() async throws {
        // Use a non-routable endpoint that will fail fast
        let provider = OllamaProvider(endpoint: "http://127.0.0.1:19999", model: "llama3.2")

        do {
            _ = try await provider.summarize(transcript: "Test transcript")
            Issue.record("Expected SummaryError.ollamaNotReachable but no error was thrown")
        } catch let error as SummaryError {
            switch error {
            case .ollamaNotReachable(let endpoint):
                #expect(endpoint == "http://127.0.0.1:19999")
            default:
                Issue.record("Expected ollamaNotReachable but got \(error)")
            }
        }
    }

    // MARK: - Integration test (requires running Ollama)

    // This test requires Ollama to be running locally.
    // Uncomment and run manually when Ollama is available.
    //
    // @Test func summarizeReturnsResponseWhenOllamaRunning() async throws {
    //     let provider = OllamaProvider(endpoint: "http://localhost:11434", model: "llama3.2")
    //     let result = try await provider.summarize(transcript: "[00:00] Hello everyone, let's discuss the project timeline.")
    //     #expect(!result.isEmpty)
    // }
}
