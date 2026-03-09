import Foundation
import Observation
import os

private let logger = Logger(subsystem: "com.kuamatzin.meet-notes", category: "SettingsViewModel")

enum LLMProvider: String, CaseIterable, Sendable {
    case ollama
    case cloud
}

struct TranscriptionLanguage: Identifiable, Hashable {
    let code: String?
    let name: String
    var id: String { code ?? "auto" }

    static let supported: [TranscriptionLanguage] = [
        .init(code: nil, name: "Auto-detect"),
        .init(code: "en", name: "English"),
        .init(code: "es", name: "Español"),
        .init(code: "fr", name: "Français"),
        .init(code: "de", name: "Deutsch"),
        .init(code: "it", name: "Italiano"),
        .init(code: "pt", name: "Português"),
        .init(code: "ja", name: "日本語"),
        .init(code: "ko", name: "한국어"),
        .init(code: "zh", name: "中文"),
        .init(code: "ru", name: "Русский"),
        .init(code: "ar", name: "العربية"),
        .init(code: "hi", name: "हिन्दी"),
        .init(code: "nl", name: "Nederlands"),
        .init(code: "pl", name: "Polski"),
        .init(code: "tr", name: "Türkçe"),
        .init(code: "sv", name: "Svenska"),
        .init(code: "da", name: "Dansk"),
        .init(code: "no", name: "Norsk"),
        .init(code: "fi", name: "Suomi"),
    ]
}

@Observable @MainActor final class SettingsViewModel {
    var selectedModel: String = "base"
    var modelStates: [String: ModelDownloadState] = [:]
    private(set) var availableModels: [ModelInfo] = []
    var selectedLanguage: TranscriptionLanguage = TranscriptionLanguage.supported[0]

    // LLM Settings
    var selectedLLMProvider: LLMProvider = .ollama
    var ollamaEndpoint: String = "http://localhost:11434"
    private(set) var isAPIKeyConfigured: Bool = false
    var apiKeyInput: String = ""
    var apiKeyTestResult: APIKeyTestResult?
    var isTestingAPIKey: Bool = false

    enum APIKeyTestResult: Equatable {
        case success
        case failed(String)
    }

    // General Settings
    var launchAtLogin: Bool = false
    let appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"

    private let database: AppDatabase
    private let modelDownloadManager: any ModelDownloadManagerProtocol
    private let transcriptionService: any TranscriptionServiceProtocol
    private let launchAtLoginService: any LaunchAtLoginService
    private let appErrorState: AppErrorState
    private var progressHandlerWired = false

    init(
        database: AppDatabase,
        modelDownloadManager: any ModelDownloadManagerProtocol,
        transcriptionService: any TranscriptionServiceProtocol,
        launchAtLoginService: any LaunchAtLoginService = SMAppLaunchAtLoginService(),
        appErrorState: AppErrorState
    ) {
        self.database = database
        self.modelDownloadManager = modelDownloadManager
        self.transcriptionService = transcriptionService
        self.launchAtLoginService = launchAtLoginService
        self.appErrorState = appErrorState
        self.availableModels = modelDownloadManager.availableModels
        self.launchAtLogin = launchAtLoginService.isEnabled()
    }

    func loadSettings() async {
        if let saved = await database.readSetting(key: "whisperkit_model") {
            selectedModel = saved
        }

        if let langCode = await database.readSetting(key: "transcription_language") {
            selectedLanguage = TranscriptionLanguage.supported.first(where: { ($0.code ?? "auto") == langCode })
                ?? TranscriptionLanguage.supported[0]
        }

        for model in availableModels {
            let downloaded = await modelDownloadManager.isModelDownloaded(name: model.name)
            modelStates[model.name] = downloaded ? .downloaded : .notDownloaded
        }

        await loadLLMSettings()
        await wireDownloadManager()
    }

    func selectLanguage(_ language: TranscriptionLanguage) async {
        selectedLanguage = language
        await transcriptionService.setLanguage(language.code)
        logger.info("Selected language: \(language.name)")
    }

    func selectModel(name: String) async {
        guard modelStates[name] == .downloaded || name == "base" else { return }
        let success = await transcriptionService.setModel(name)
        guard success else {
            logger.warning("Model switch to \(name) rejected — transcription in progress")
            return
        }
        selectedModel = name
        logger.info("Selected model: \(name)")
    }

    func downloadModel(name: String) async {
        do {
            try await modelDownloadManager.downloadModel(name: name)
        } catch {
            let appError = AppError.modelDownloadFailed(modelName: name)
            appErrorState.post(appError)
            logger.error("Model download failed for \(name): \(String(describing: error))")
        }
    }

    func cancelDownload(name: String) async {
        await modelDownloadManager.cancelDownload(name: name)
        modelStates[name] = .notDownloaded
    }

    func deleteModel(name: String) async {
        await modelDownloadManager.deleteModel(name: name)
        modelStates[name] = .notDownloaded
        if selectedModel == name {
            await selectModel(name: "base")
        }
    }

    // MARK: - Launch at Login

    func toggleLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try launchAtLoginService.register()
            } else {
                try launchAtLoginService.unregister()
            }
            launchAtLogin = enabled
        } catch {
            appErrorState.post(.launchAtLoginFailed)
            logger.error("Failed to \(enabled ? "enable" : "disable") launch at login: \(String(describing: error))")
        }
    }

    // MARK: - LLM Settings

    func loadLLMSettings() async {
        if let provider = await database.readSetting(key: "llm_provider"),
           let parsed = LLMProvider(rawValue: provider) {
            selectedLLMProvider = parsed
        }
        if let endpoint = await database.readSetting(key: "ollama_endpoint") {
            ollamaEndpoint = endpoint
        }
        let keyConfigured = await database.readSetting(key: "openai_api_key_configured")
        isAPIKeyConfigured = keyConfigured == "true"
    }

    func setLLMProvider(_ provider: LLMProvider) async {
        selectedLLMProvider = provider
        await database.writeSetting(key: "llm_provider", value: provider.rawValue)
        logger.info("LLM provider set to \(provider.rawValue)")
    }

    func setOllamaEndpoint(_ url: String) async {
        guard URL(string: url) != nil else {
            logger.warning("Invalid Ollama endpoint URL: \(url)")
            return
        }
        ollamaEndpoint = url
        await database.writeSetting(key: "ollama_endpoint", value: url)
        logger.info("Ollama endpoint updated")
    }

    func saveCloudAPIKey(_ key: String) async {
        do {
            try SecretsStore.save(apiKey: key, for: .openAI)
            isAPIKeyConfigured = true
            apiKeyInput = ""
            await database.writeSetting(key: "openai_api_key_configured", value: "true")
            logger.info("API key saved")
        } catch {
            appErrorState.post(.keychainSaveFailed)
            logger.error("Failed to save API key: \(String(describing: error))")
        }
    }

    func deleteCloudAPIKey() async {
        do {
            try SecretsStore.delete(for: .openAI)
            isAPIKeyConfigured = false
            await database.writeSetting(key: "openai_api_key_configured", value: "false")
            apiKeyInput = ""
            apiKeyTestResult = nil
            logger.info("API key deleted")
        } catch {
            appErrorState.post(.keychainDeleteFailed)
            logger.error("Failed to delete API key: \(String(describing: error))")
        }
    }

    func testCloudAPIKey() async {
        let keyToTest: String
        if !apiKeyInput.isEmpty {
            keyToTest = apiKeyInput
        } else if let stored = SecretsStore.load(for: .openAI) {
            keyToTest = stored
        } else {
            apiKeyTestResult = .failed("No API key to test")
            return
        }

        isTestingAPIKey = true
        apiKeyTestResult = nil

        let url = URL(string: "https://api.openai.com/v1/models")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(keyToTest)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                switch http.statusCode {
                case 200:
                    apiKeyTestResult = .success
                    logger.info("API key test passed")
                case 401, 403:
                    apiKeyTestResult = .failed("Invalid API key")
                    logger.warning("API key test failed: unauthorized")
                default:
                    apiKeyTestResult = .failed("HTTP \(http.statusCode)")
                    logger.warning("API key test failed: HTTP \(http.statusCode)")
                }
            }
        } catch {
            apiKeyTestResult = .failed("Network error")
            logger.error("API key test error: \(String(describing: error))")
        }

        isTestingAPIKey = false
    }

    private func wireDownloadManager() async {
        guard !progressHandlerWired else { return }
        progressHandlerWired = true
        await modelDownloadManager.setProgressHandler { [weak self] modelName, state in
            self?.modelStates[modelName] = state
        }
    }
}
