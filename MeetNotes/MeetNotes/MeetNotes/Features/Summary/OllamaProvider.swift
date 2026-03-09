import Foundation
import os

actor OllamaProvider: LLMSummaryProvider {
    private nonisolated static let logger = Logger(
        subsystem: "com.kuamatzin.meet-notes",
        category: "OllamaProvider"
    )

    private let endpoint: String
    private let model: String
    private let session: URLSession

    init(endpoint: String = "http://localhost:11434", model: String = "llama3.2") {
        self.endpoint = endpoint
        self.model = model
        let config = URLSessionConfiguration.default
        // Session-level timeout governs the reachability HEAD check only.
        // Chat requests override with a 300s timeout for long LLM generations.
        config.timeoutIntervalForRequest = 5
        self.session = URLSession(configuration: config)
    }

    nonisolated func summarizeStreaming(transcript: String) -> AsyncThrowingStream<String, Error> {
        let endpoint = self.endpoint
        let model = self.model
        let session = self.session
        return AsyncThrowingStream { continuation in
            let task = Task {
                guard let baseURL = URL(string: endpoint) else {
                    continuation.finish(throwing: SummaryError.ollamaNotReachable(endpoint: endpoint))
                    return
                }

                let reachable = await Self.checkReachable(baseURL: baseURL, session: session)
                guard reachable else {
                    continuation.finish(throwing: SummaryError.ollamaNotReachable(endpoint: endpoint))
                    return
                }

                let chatURL = baseURL.appendingPathComponent("api/chat")
                var request = URLRequest(url: chatURL)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 300

                let body: [String: Any] = [
                    "model": model,
                    "messages": [
                        ["role": "system", "content": SummaryPrompt.system],
                        ["role": "user", "content": transcript]
                    ],
                    "stream": true
                ]

                do {
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)
                } catch {
                    continuation.finish(throwing: SummaryError.providerFailure(error))
                    return
                }

                do {
                    let (bytes, _) = try await session.bytes(for: request)
                    for try await line in bytes.lines {
                        guard !line.isEmpty else { continue }
                        guard let lineData = line.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                              let message = json["message"] as? [String: Any],
                              let content = message["content"] as? String else {
                            continue
                        }
                        continuation.yield(content)
                        if let done = json["done"] as? Bool, done {
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    Self.logger.error("Ollama streaming request failed: \(error)")
                    continuation.finish(throwing: SummaryError.providerFailure(error))
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    private nonisolated static func checkReachable(baseURL: URL, session: URLSession) async -> Bool {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5
        do {
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse {
                return http.statusCode == 200
            }
            return false
        } catch {
            return false
        }
    }
}
