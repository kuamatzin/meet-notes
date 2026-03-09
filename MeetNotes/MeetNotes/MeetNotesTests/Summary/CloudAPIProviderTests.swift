import Foundation
import Testing
@testable import MeetNotes

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Data, HTTPURLResponse))?

    nonisolated override init(request: URLRequest, cachedResponse: CachedURLResponse?, client: (any URLProtocolClient)?) {
        super.init(request: request, cachedResponse: cachedResponse, client: client)
    }

    nonisolated override class func canInit(with request: URLRequest) -> Bool { true }
    nonisolated override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    nonisolated override func startLoading() {
        guard let handler = MockURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (data, response) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    nonisolated override func stopLoading() {}
}

private func makeMockSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    config.timeoutIntervalForRequest = 5
    return URLSession(configuration: config)
}

private func makeOpenAIResponse(content: String) -> Data {
    let json: [String: Any] = [
        "choices": [
            [
                "message": ["role": "assistant", "content": content],
                "finish_reason": "stop"
            ]
        ]
    ]
    // swiftlint:disable:next force_try
    return try! JSONSerialization.data(withJSONObject: json)
}

@Suite(.serialized)
@MainActor
struct CloudAPIProviderTests {
    // MARK: - Successful response

    @Test func successfulResponseReturnsParsedContent() async throws {
        let expectedContent = "## Decisions\n- Approved budget.\n\n## Action Items\n- None.\n\n## Key Topics\n- Planning"

        MockURLProtocol.handler = { request in
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test-key")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (makeOpenAIResponse(content: expectedContent), response)
        }
        defer { MockURLProtocol.handler = nil }

        let provider = CloudAPIProvider(apiKey: "sk-test-key", session: makeMockSession())
        let result = try await provider.summarize(transcript: "[00:00] Hello everyone")
        #expect(result == expectedContent)
    }

    // MARK: - 401 response

    @Test func unauthorizedResponseThrowsInvalidAPIKey() async throws {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(), response)
        }
        defer { MockURLProtocol.handler = nil }

        let provider = CloudAPIProvider(apiKey: "bad-key", session: makeMockSession())
        do {
            _ = try await provider.summarize(transcript: "test")
            Issue.record("Expected SummaryError.invalidAPIKey")
        } catch {
            switch error {
            case .invalidAPIKey:
                break
            default:
                Issue.record("Expected invalidAPIKey but got \(error)")
            }
        }
    }

    // MARK: - Network error

    @Test func networkErrorThrowsNetworkUnavailable() async throws {
        MockURLProtocol.handler = { _ in
            throw URLError(.notConnectedToInternet)
        }
        defer { MockURLProtocol.handler = nil }

        let provider = CloudAPIProvider(apiKey: "sk-test-key", session: makeMockSession())
        do {
            _ = try await provider.summarize(transcript: "test")
            Issue.record("Expected SummaryError.networkUnavailable")
        } catch {
            switch error {
            case .networkUnavailable:
                break
            default:
                Issue.record("Expected networkUnavailable but got \(error)")
            }
        }
    }
}
