import Foundation
import os

actor CloudAPIProvider: LLMSummaryProvider {
    private nonisolated static let logger = Logger(
        subsystem: "com.kuamatzin.meet-notes",
        category: "CloudAPIProvider"
    )

    private let apiKey: String
    private let session: URLSession

    init(apiKey: String, session: URLSession? = nil) {
        self.apiKey = apiKey
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 30
            self.session = URLSession(configuration: config)
        }
    }

    nonisolated func summarizeStreaming(transcript: String) -> AsyncThrowingStream<String, Error> {
        let apiKey = self.apiKey
        let session = self.session
        return AsyncThrowingStream { continuation in
            let task = Task {
                let url = URL(string: "https://api.openai.com/v1/chat/completions")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                let body: [String: Any] = [
                    "model": "gpt-4o-mini",
                    "messages": [
                        ["role": "system", "content": SummaryPrompt.system],
                        ["role": "user", "content": transcript]
                    ],
                    "temperature": 0.3,
                    "stream": true
                ]

                do {
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)
                } catch {
                    continuation.finish(throwing: SummaryError.providerFailure(error))
                    return
                }

                do {
                    let (bytes, response) = try await session.bytes(for: request)

                    if let httpResponse = response as? HTTPURLResponse {
                        switch httpResponse.statusCode {
                        case 200:
                            break
                        case 401, 403:
                            continuation.finish(throwing: SummaryError.invalidAPIKey)
                            return
                        default:
                            Self.logger.error("Cloud API HTTP \(httpResponse.statusCode)")
                            continuation.finish(throwing: SummaryError.providerFailure(
                                CloudAPIError.httpError(statusCode: httpResponse.statusCode)))
                            return
                        }
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        if payload == "[DONE]" { break }
                        guard let lineData = payload.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                              let choices = json["choices"] as? [[String: Any]],
                              let first = choices.first,
                              let delta = first["delta"] as? [String: Any],
                              let content = delta["content"] as? String else {
                            continue
                        }
                        continuation.yield(content)
                    }
                    continuation.finish()
                } catch {
                    Self.logger.error("Cloud API streaming error: \(error)")
                    continuation.finish(throwing: SummaryError.networkUnavailable)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}

private enum CloudAPIError: Error, Sendable {
    case httpError(statusCode: Int)
    case emptyResponse
}
