import Foundation
import GRDB
import Testing
@testable import MeetNotes

@MainActor
struct SettingsViewModelTests {
    private func makeDatabase() throws -> (AppDatabase, String) {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent(UUID().uuidString + ".db").path
        let pool = try DatabasePool(path: dbPath)
        let database = try AppDatabase(pool)
        return (database, dbPath)
    }

    private func cleanupDatabase(atPath path: String) {
        try? FileManager.default.removeItem(atPath: path)
        try? FileManager.default.removeItem(atPath: path + "-wal")
        try? FileManager.default.removeItem(atPath: path + "-shm")
    }

    private func makeViewModel(
        database: AppDatabase,
        launchAtLoginService: StubLaunchAtLoginService = StubLaunchAtLoginService()
    ) -> (SettingsViewModel, StubModelDownloadManager, StubTranscriptionService, StubLaunchAtLoginService, AppErrorState) {
        let stub = StubModelDownloadManager()
        let transcription = StubTranscriptionService()
        let errorState = AppErrorState()
        let vm = SettingsViewModel(
            database: database,
            modelDownloadManager: stub,
            transcriptionService: transcription,
            launchAtLoginService: launchAtLoginService,
            appErrorState: errorState
        )
        return (vm, stub, transcription, launchAtLoginService, errorState)
    }

    // MARK: - Initial State

    @Test func initialSelectedModelIsBase() throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let (vm, _, _, _, _) = makeViewModel(database: database)
        #expect(vm.selectedModel == "base")
    }

    @Test func availableModelsLoadedFromManager() throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let (vm, _, _, _, _) = makeViewModel(database: database)
        #expect(vm.availableModels.count == 2) // StubModelDownloadManager has base + small
    }

    // MARK: - Load Settings

    @Test func loadSettingsReadsModelFromDatabase() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        await database.writeSetting(key: "whisperkit_model", value: "small")

        let (vm, _, _, _, _) = makeViewModel(database: database)
        await vm.loadSettings()

        #expect(vm.selectedModel == "small")
    }

    @Test func loadSettingsDefaultsToBaseWhenNoSavedSetting() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let (vm, _, _, _, _) = makeViewModel(database: database)
        await vm.loadSettings()

        #expect(vm.selectedModel == "base")
    }

    @Test func loadSettingsPopulatesModelStates() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let (vm, _, _, _, _) = makeViewModel(database: database)
        await vm.loadSettings()

        #expect(vm.modelStates["base"] == .downloaded)
        #expect(vm.modelStates["small"] == .notDownloaded)
    }

    // MARK: - Model Selection

    @Test func selectModelUpdatesSelectedModel() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let (vm, stub, _, _, _) = makeViewModel(database: database)
        await vm.loadSettings()

        // Mark small as downloaded in the stub so it can be selected
        try await stub.downloadModel(name: "small")
        vm.modelStates["small"] = .downloaded

        await vm.selectModel(name: "small")

        // DB persistence is now handled by TranscriptionService.setModel
        #expect(vm.selectedModel == "small")
    }

    @Test func selectModelCallsTranscriptionServiceSetModel() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let (vm, stub, transcription, _, _) = makeViewModel(database: database)
        await vm.loadSettings()

        try await stub.downloadModel(name: "small")
        vm.modelStates["small"] = .downloaded

        await vm.selectModel(name: "small")

        #expect(transcription.setModelCalled)
        #expect(transcription.lastModelSet == "small")
    }

    @Test func selectModelDoesNotPersistWhenSetModelFails() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let (vm, stub, transcription, _, _) = makeViewModel(database: database)
        await vm.loadSettings()

        try await stub.downloadModel(name: "small")
        vm.modelStates["small"] = .downloaded

        transcription.setModelShouldSucceed = false
        await vm.selectModel(name: "small")

        #expect(vm.selectedModel == "base") // Should remain base
        let saved = await database.readSetting(key: "whisperkit_model")
        #expect(saved == nil) // Should NOT have been persisted
    }

    @Test func selectModelIgnoresNotDownloadedModel() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let (vm, _, _, _, _) = makeViewModel(database: database)
        await vm.loadSettings()

        await vm.selectModel(name: "small") // small is not downloaded
        #expect(vm.selectedModel == "base") // Should remain base
    }

    // MARK: - Download

    @Test func downloadModelDelegatesToManager() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let (vm, stub, _, _, _) = makeViewModel(database: database)
        await vm.downloadModel(name: "small")

        #expect(stub.downloadCalled)
        #expect(stub.lastDownloadedModel == "small")
    }

    @Test func downloadModelPostsErrorOnFailure() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let errorState = AppErrorState()
        let stub = StubModelDownloadManager()
        stub.shouldThrowOnDownload = .networkFailed
        let vm = SettingsViewModel(
            database: database,
            modelDownloadManager: stub,
            transcriptionService: StubTranscriptionService(),
            appErrorState: errorState
        )

        await vm.downloadModel(name: "small")
        #expect(errorState.current == .modelDownloadFailed(modelName: "small"))
    }

    // MARK: - Cancel

    @Test func cancelDownloadDelegatesToManager() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let (vm, stub, _, _, _) = makeViewModel(database: database)
        await vm.cancelDownload(name: "small")

        #expect(stub.cancelCalled)
        #expect(vm.modelStates["small"] == .notDownloaded)
    }

    // MARK: - Delete

    @Test func deleteModelDelegatesToManager() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let (vm, stub, _, _, _) = makeViewModel(database: database)
        await vm.deleteModel(name: "small")

        #expect(stub.deleteCalled)
        #expect(stub.lastDeletedModel == "small")
    }

    @Test func deleteActiveModelRevertsToBase() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let (vm, stub, _, _, _) = makeViewModel(database: database)
        await vm.loadSettings()

        // Download and select small
        try await stub.downloadModel(name: "small")
        vm.modelStates["small"] = .downloaded
        await vm.selectModel(name: "small")
        #expect(vm.selectedModel == "small")

        // Delete small — should revert to base
        await vm.deleteModel(name: "small")
        #expect(vm.selectedModel == "base")
    }

    // MARK: - Progress Handler

    @Test func progressHandlerUpdatesModelStates() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let (vm, stub, _, _, _) = makeViewModel(database: database)
        await vm.loadSettings()

        await stub.simulateProgress("small", .downloading(progress: 0.5))

        #expect(vm.modelStates["small"] == .downloading(progress: 0.5))
    }

    // MARK: - LLM Settings: Initial State

    @Test func llmDefaultProviderIsOllama() throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let (vm, _, _, _, _) = makeViewModel(database: database)
        #expect(vm.selectedLLMProvider == .ollama)
    }

    @Test func llmDefaultEndpointIsLocalhost() throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let (vm, _, _, _, _) = makeViewModel(database: database)
        #expect(vm.ollamaEndpoint == "http://localhost:11434")
    }

    @Test func llmDefaultAPIKeyNotConfigured() throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let (vm, _, _, _, _) = makeViewModel(database: database)
        #expect(vm.isAPIKeyConfigured == false)
    }

    // MARK: - LLM Settings: Load

    @Test func loadLLMSettingsReadsProviderFromDatabase() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        await database.writeSetting(key: "llm_provider", value: "cloud")

        let (vm, _, _, _, _) = makeViewModel(database: database)
        await vm.loadLLMSettings()

        #expect(vm.selectedLLMProvider == .cloud)
    }

    @Test func loadLLMSettingsReadsEndpointFromDatabase() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        await database.writeSetting(key: "ollama_endpoint", value: "http://192.168.1.100:11434")

        let (vm, _, _, _, _) = makeViewModel(database: database)
        await vm.loadLLMSettings()

        #expect(vm.ollamaEndpoint == "http://192.168.1.100:11434")
    }

    @Test func loadLLMSettingsReadsAPIKeyConfiguredFlag() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        await database.writeSetting(key: "openai_api_key_configured", value: "true")

        let (vm, _, _, _, _) = makeViewModel(database: database)
        await vm.loadLLMSettings()

        #expect(vm.isAPIKeyConfigured == true)
    }

    @Test func loadLLMSettingsDefaultsWhenNoSavedSettings() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let (vm, _, _, _, _) = makeViewModel(database: database)
        await vm.loadLLMSettings()

        #expect(vm.selectedLLMProvider == .ollama)
        #expect(vm.ollamaEndpoint == "http://localhost:11434")
        #expect(vm.isAPIKeyConfigured == false)
    }

    // MARK: - LLM Settings: Set Provider

    @Test func setLLMProviderPersistsToDatabase() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let (vm, _, _, _, _) = makeViewModel(database: database)
        await vm.setLLMProvider(.cloud)

        #expect(vm.selectedLLMProvider == .cloud)
        let saved = await database.readSetting(key: "llm_provider")
        #expect(saved == "cloud")
    }

    // MARK: - LLM Settings: Set Ollama Endpoint

    @Test func setOllamaEndpointPersistsToDatabase() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let (vm, _, _, _, _) = makeViewModel(database: database)
        await vm.setOllamaEndpoint("http://192.168.1.100:11434")

        #expect(vm.ollamaEndpoint == "http://192.168.1.100:11434")
        let saved = await database.readSetting(key: "ollama_endpoint")
        #expect(saved == "http://192.168.1.100:11434")
    }

    @Test func setOllamaEndpointRejectsInvalidURL() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let (vm, _, _, _, _) = makeViewModel(database: database)
        await vm.setOllamaEndpoint("")

        #expect(vm.ollamaEndpoint == "http://localhost:11434") // unchanged
    }

    // MARK: - LLM Settings: API Key
    // Note: These tests call real SecretsStore/Keychain. May fail on CI runners without Keychain access.

    @Test func saveCloudAPIKeyUpdatesConfiguredFlag() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let (vm, _, _, _, _) = makeViewModel(database: database)
        await vm.saveCloudAPIKey("sk-test-key-12345")

        #expect(vm.isAPIKeyConfigured == true)
        let saved = await database.readSetting(key: "openai_api_key_configured")
        #expect(saved == "true")
    }

    @Test func deleteCloudAPIKeyResetsConfiguredFlag() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let (vm, _, _, _, _) = makeViewModel(database: database)
        await vm.saveCloudAPIKey("sk-test-key-12345")
        #expect(vm.isAPIKeyConfigured == true)

        await vm.deleteCloudAPIKey()

        #expect(vm.isAPIKeyConfigured == false)
        #expect(vm.apiKeyInput == "")
        let saved = await database.readSetting(key: "openai_api_key_configured")
        #expect(saved == "false")
    }

    // MARK: - LLM Settings: Transcript-only mode

    @Test func noLLMProviderDoesNotBlockRecording() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let (vm, _, _, _, _) = makeViewModel(database: database)
        await vm.loadSettings()

        // With no LLM configured, recording-related state should be unaffected
        #expect(vm.selectedModel == "base")
        #expect(vm.isAPIKeyConfigured == false)
        #expect(vm.selectedLLMProvider == .ollama)
    }

    // MARK: - LLM Settings loaded via loadSettings

    @Test func loadSettingsAlsoLoadsLLMSettings() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        await database.writeSetting(key: "llm_provider", value: "cloud")
        await database.writeSetting(key: "openai_api_key_configured", value: "true")

        let (vm, _, _, _, _) = makeViewModel(database: database)
        await vm.loadSettings()

        #expect(vm.selectedLLMProvider == .cloud)
        #expect(vm.isAPIKeyConfigured == true)
    }

    // MARK: - Launch at Login: Initial State

    @Test func launchAtLoginReflectsServiceState() throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let loginService = StubLaunchAtLoginService()
        try loginService.register()

        let (vm, _, _, _, _) = makeViewModel(database: database, launchAtLoginService: loginService)
        #expect(vm.launchAtLogin == true)
    }

    @Test func launchAtLoginDefaultsToFalse() throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let (vm, _, _, _, _) = makeViewModel(database: database)
        #expect(vm.launchAtLogin == false)
    }

    // MARK: - Launch at Login: Toggle ON

    @Test func toggleLaunchAtLoginOnCallsRegister() throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let (vm, _, _, loginService, _) = makeViewModel(database: database)
        vm.toggleLaunchAtLogin(true)

        #expect(loginService.registerCalled)
        #expect(vm.launchAtLogin == true)
    }

    // MARK: - Launch at Login: Toggle OFF

    @Test func toggleLaunchAtLoginOffCallsUnregister() throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let loginService = StubLaunchAtLoginService()
        try loginService.register()
        let (vm, _, _, _, _) = makeViewModel(database: database, launchAtLoginService: loginService)
        #expect(vm.launchAtLogin == true)

        vm.toggleLaunchAtLogin(false)

        #expect(loginService.unregisterCalled)
        #expect(vm.launchAtLogin == false)
    }

    // MARK: - Launch at Login: Error Handling

    @Test func toggleLaunchAtLoginPostsErrorOnRegisterFailure() throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let loginService = StubLaunchAtLoginService()
        loginService.shouldThrowOnRegister = true
        let (vm, _, _, _, errorState) = makeViewModel(database: database, launchAtLoginService: loginService)

        vm.toggleLaunchAtLogin(true)

        #expect(vm.launchAtLogin == false)
        #expect(errorState.current == .launchAtLoginFailed)
    }

    @Test func toggleLaunchAtLoginPostsErrorOnUnregisterFailure() throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let loginService = StubLaunchAtLoginService()
        try loginService.register()
        let (vm, _, _, _, errorState) = makeViewModel(database: database, launchAtLoginService: loginService)
        loginService.shouldThrowOnUnregister = true

        vm.toggleLaunchAtLogin(false)

        #expect(vm.launchAtLogin == true)
        #expect(errorState.current == .launchAtLoginFailed)
    }
}
