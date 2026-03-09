import Testing
@testable import MeetNotes

struct SecretsStoreTests {
    private func cleanup() throws {
        try SecretsStore.delete(for: .openAI)
        try SecretsStore.delete(for: .anthropic)
    }

    @Test func saveAndLoadRoundTripOpenAI() throws {
        defer { try? cleanup() }
        try cleanup()
        try SecretsStore.save(apiKey: "sk-test-123", for: .openAI)
        #expect(SecretsStore.load(for: .openAI) == "sk-test-123")
    }

    @Test func saveAndLoadRoundTripAnthropic() throws {
        defer { try? cleanup() }
        try cleanup()
        try SecretsStore.save(apiKey: "sk-ant-test-456", for: .anthropic)
        #expect(SecretsStore.load(for: .anthropic) == "sk-ant-test-456")
    }

    @Test func loadReturnsNilWhenEmpty() throws {
        try cleanup()
        #expect(SecretsStore.load(for: .openAI) == nil)
    }

    @Test func deleteRemovesKey() throws {
        defer { try? cleanup() }
        try cleanup()
        try SecretsStore.save(apiKey: "sk-delete-me", for: .anthropic)
        try SecretsStore.delete(for: .anthropic)
        #expect(SecretsStore.load(for: .anthropic) == nil)
    }

    @Test func saveOverwritesExistingKey() throws {
        defer { try? cleanup() }
        try cleanup()
        try SecretsStore.save(apiKey: "old-key", for: .openAI)
        try SecretsStore.save(apiKey: "new-key", for: .openAI)
        #expect(SecretsStore.load(for: .openAI) == "new-key")
    }
}
