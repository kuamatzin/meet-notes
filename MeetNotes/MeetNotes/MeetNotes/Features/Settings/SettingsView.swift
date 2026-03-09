import Sparkle
import SwiftUI

struct SettingsView: View {
    let updater: SPUUpdater
    @ObservedObject private var checkForUpdatesViewModel: CheckForUpdatesViewModel
    @Environment(SettingsViewModel.self) private var viewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(updater: SPUUpdater) {
        self.updater = updater
        self.checkForUpdatesViewModel = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                transcriptionSection
                summarySection
                generalSection
            }
            .padding()
        }
        .frame(minWidth: 480, minHeight: 400)
        .task {
            await viewModel.loadSettings()
        }
    }

    private var transcriptionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Transcription Model")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Choose a model that balances accuracy and speed for your needs.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack {
                Text("Language")
                    .font(.headline)
                Spacer()
                Picker("", selection: Binding(
                    get: { viewModel.selectedLanguage },
                    set: { lang in Task { await viewModel.selectLanguage(lang) } }
                )) {
                    ForEach(TranscriptionLanguage.supported) { lang in
                        Text(lang.name).tag(lang)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 180)
            }
            .padding(.bottom, 4)

            ForEach(viewModel.availableModels, id: \.name) { model in
                ModelDownloadCard(
                    modelName: model.name,
                    displayName: model.displayName,
                    sizeLabel: model.sizeLabel,
                    accuracyLabel: model.accuracyLabel,
                    speedLabel: model.speedLabel,
                    languageNote: model.languageNote,
                    state: viewModel.modelStates[model.name] ?? .notDownloaded,
                    isSelected: viewModel.selectedModel == model.name,
                    onDownload: { Task { await viewModel.downloadModel(name: model.name) } },
                    onCancel: { Task { await viewModel.cancelDownload(name: model.name) } },
                    onSelect: { Task { await viewModel.selectModel(name: model.name) } },
                    onDelete: { Task { await viewModel.deleteModel(name: model.name) } }
                )
            }
        }
    }

    @MainActor private var summarySection: some View {
        @Bindable var viewModel = viewModel
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Summary")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                if viewModel.selectedLLMProvider == .ollama {
                    statusPill(text: "\u{1F512} On-device", color: .onDeviceGreen)
                } else {
                    statusPill(text: "\u{2601}\u{FE0F} Cloud", color: .accent)
                }
            }

            Text("Choose how meeting transcripts are summarized.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("AI Provider", selection: $viewModel.selectedLLMProvider) {
                Text("Ollama (local)").tag(LLMProvider.ollama)
                Text("Cloud API (OpenAI-compatible)").tag(LLMProvider.cloud)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("AI Provider")
            .onChange(of: viewModel.selectedLLMProvider) { _, newValue in
                Task { await viewModel.setLLMProvider(newValue) }
            }

            if viewModel.selectedLLMProvider == .ollama {
                ollamaSettings
            } else {
                cloudSettings
            }

            if !viewModel.isAPIKeyConfigured && viewModel.selectedLLMProvider == .cloud {
                noProviderNotice
            }
        }
    }

    private var ollamaSettings: some View {
        @Bindable var viewModel = viewModel
        return VStack(alignment: .leading, spacing: 8) {
            Text("Ollama Endpoint")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField("http://localhost:11434", text: $viewModel.ollamaEndpoint)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Ollama endpoint URL")
                .onSubmit {
                    Task { await viewModel.setOllamaEndpoint(viewModel.ollamaEndpoint) }
                }
        }
    }

    private var cloudSettings: some View {
        @Bindable var viewModel = viewModel
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("API Key")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if viewModel.isAPIKeyConfigured {
                    Label("Configured", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.onDeviceGreen)
                }
            }

            SecureField(viewModel.isAPIKeyConfigured ? "Enter new key to replace" : "sk-\u{2026}", text: $viewModel.apiKeyInput)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Cloud API key")

            HStack(spacing: 8) {
                Button(viewModel.isAPIKeyConfigured && viewModel.apiKeyInput.isEmpty ? "Test API Key" : "Save API Key") {
                    if viewModel.isAPIKeyConfigured && viewModel.apiKeyInput.isEmpty {
                        Task { await viewModel.testCloudAPIKey() }
                    } else {
                        Task { await viewModel.saveCloudAPIKey(viewModel.apiKeyInput) }
                    }
                }
                .disabled(!viewModel.isAPIKeyConfigured && viewModel.apiKeyInput.isEmpty)
                .accessibilityLabel(viewModel.isAPIKeyConfigured ? "Test API key" : "Save API key")

                if !viewModel.apiKeyInput.isEmpty && viewModel.isAPIKeyConfigured {
                    Button("Test") {
                        Task { await viewModel.testCloudAPIKey() }
                    }
                    .accessibilityLabel("Test API key")
                }

                if viewModel.isTestingAPIKey {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()

                if viewModel.isAPIKeyConfigured {
                    Button("Remove Key", role: .destructive) {
                        Task { await viewModel.deleteCloudAPIKey() }
                    }
                    .accessibilityLabel("Remove API key")
                }
            }

            if let result = viewModel.apiKeyTestResult {
                switch result {
                case .success:
                    Label("API key is valid", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.onDeviceGreen)
                case .failed(let message):
                    Label(message, systemImage: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.recordingRed)
                }
            }
        }
    }

    private var noProviderNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text("No AI provider configured \u{2014} transcripts will be saved without summaries.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(Color.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No AI provider configured. Transcripts will be saved without summaries.")
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("General")
                .font(.title2)
                .fontWeight(.semibold)

            Toggle(isOn: Binding(
                get: { viewModel.launchAtLogin },
                set: { viewModel.toggleLaunchAtLogin($0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Launch at login")
                    Text("Automatically start MeetNotes when you log in.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel("Launch at login")

            Toggle(isOn: Binding(
                get: { updater.automaticallyChecksForUpdates },
                set: { updater.automaticallyChecksForUpdates = $0 }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Automatic updates")
                    Text("Check for updates automatically every 24 hours.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel("Automatic updates")

            HStack {
                Button("Check for Updates\u{2026}", action: updater.checkForUpdates)
                    .disabled(!checkForUpdatesViewModel.canCheckForUpdates)
                    .accessibilityLabel("Check for updates")

                Spacer()

                Text("Version \(viewModel.appVersion)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("App version \(viewModel.appVersion)")
            }
        }
    }

    private func statusPill(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
