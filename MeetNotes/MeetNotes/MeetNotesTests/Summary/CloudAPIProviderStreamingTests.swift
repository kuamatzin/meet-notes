import Foundation
import Testing
@testable import MeetNotes

@MainActor
struct CloudAPIProviderStreamingTests {

    @Test func sseParsingYieldsCorrectChunks() async throws {
        let sseLines = [
            "data: {\"choices\":[{\"delta\":{\"content\":\"## \"}}]}",
            "data: {\"choices\":[{\"delta\":{\"content\":\"Decisions\"}}]}",
            "data: {\"choices\":[{\"delta\":{\"content\":\"\\n\"}}]}",
            "data: [DONE]"
        ]

        var chunks: [String] = []
        for line in sseLines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let delta = first["delta"] as? [String: Any],
                  let content = delta["content"] as? String else {
                continue
            }
            chunks.append(content)
        }

        #expect(chunks.count == 3)
        #expect(chunks[0] == "## ")
        #expect(chunks[1] == "Decisions")
        #expect(chunks[2] == "\n")
    }

    @Test func sseDoneTerminatesStream() async throws {
        let sseLines = [
            "data: {\"choices\":[{\"delta\":{\"content\":\"hello\"}}]}",
            "data: [DONE]",
            "data: {\"choices\":[{\"delta\":{\"content\":\"should not appear\"}}]}"
        ]

        var chunks: [String] = []
        for line in sseLines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let delta = first["delta"] as? [String: Any],
                  let content = delta["content"] as? String else {
                continue
            }
            chunks.append(content)
        }

        #expect(chunks.count == 1)
        #expect(chunks[0] == "hello")
    }

    @Test func sseIgnoresNonDataLines() async throws {
        let sseLines = [
            ": comment line",
            "",
            "event: ping",
            "data: {\"choices\":[{\"delta\":{\"content\":\"content\"}}]}",
            "data: [DONE]"
        ]

        var chunks: [String] = []
        for line in sseLines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            if payload == "[DONE]" { break }
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let first = choices.first,
                  let delta = first["delta"] as? [String: Any],
                  let content = delta["content"] as? String else {
                continue
            }
            chunks.append(content)
        }

        #expect(chunks.count == 1)
        #expect(chunks[0] == "content")
    }
}
