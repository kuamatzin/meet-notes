import Foundation
import Testing
@testable import MeetNotes

@MainActor
struct OllamaProviderStreamingTests {

    private static let chunkDecisions = """
        {"model":"llama3.2","message":{"role":"assistant","content":"## "},"done":false}
        """

    private static let chunkText = """
        {"model":"llama3.2","message":{"role":"assistant","content":"Decisions"},"done":false}
        """

    private static let chunkNewline = """
        {"model":"llama3.2","message":{"role":"assistant","content":"\\n"},"done":false}
        """

    private static let chunkDone = """
        {"model":"llama3.2","message":{"role":"assistant","content":""},"done":true}
        """

    private static let chunkHello = """
        {"model":"llama3.2","message":{"role":"assistant","content":"hello"},"done":false}
        """

    private static let chunkExtra = """
        {"model":"llama3.2","message":{"role":"assistant","content":"should not appear"},"done":false}
        """

    @Test func ndjsonParsingYieldsCorrectChunks() async throws {
        let ndjsonLines = [
            Self.chunkDecisions.trimmingCharacters(in: .whitespacesAndNewlines),
            Self.chunkText.trimmingCharacters(in: .whitespacesAndNewlines),
            Self.chunkNewline.trimmingCharacters(in: .whitespacesAndNewlines),
            Self.chunkDone.trimmingCharacters(in: .whitespacesAndNewlines)
        ]

        var chunks: [String] = []
        for line in ndjsonLines {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let message = json["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                continue
            }
            chunks.append(content)
        }

        #expect(chunks.count == 4)
        #expect(chunks[0] == "## ")
        #expect(chunks[1] == "Decisions")
        #expect(chunks[3] == "")
    }

    @Test func ndjsonDoneFieldTerminatesStream() async throws {
        let ndjsonLines = [
            Self.chunkHello.trimmingCharacters(in: .whitespacesAndNewlines),
            Self.chunkDone.trimmingCharacters(in: .whitespacesAndNewlines),
            Self.chunkExtra.trimmingCharacters(in: .whitespacesAndNewlines)
        ]

        var chunks: [String] = []
        for line in ndjsonLines {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let message = json["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                continue
            }
            chunks.append(content)
            if let done = json["done"] as? Bool, done {
                break
            }
        }

        #expect(chunks.count == 2)
        #expect(chunks[0] == "hello")
    }
}
