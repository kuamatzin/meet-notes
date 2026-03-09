import Foundation
import os
@preconcurrency import WhisperKit

actor ModelDownloadManager: ModelDownloadManagerProtocol {
    private nonisolated static let logger = Logger(subsystem: "com.kuamatzin.meet-notes", category: "ModelDownloadManager")

    private let database: AppDatabase
    private var progressHandler: (@MainActor @Sendable (String, ModelDownloadState) -> Void)?
    private var activeDownloads: [String: Task<Void, any Error>] = [:]
    private var cancelledModels: Set<String> = []
    private var downloadStartTime: [String: Date] = [:]

    let availableModels: [ModelInfo] = [
        ModelInfo(name: "base", displayName: "Base", sizeBytes: 145_000_000, accuracyLabel: "Baseline", speedLabel: "Fastest", isDefault: true, languageNote: "English only"),
        ModelInfo(name: "small", displayName: "Small", sizeBytes: 465_000_000, accuracyLabel: "+15%", speedLabel: "~2x slower", isDefault: false, languageNote: "Multilingual"),
        ModelInfo(name: "medium", displayName: "Medium", sizeBytes: 1_500_000_000, accuracyLabel: "+25%", speedLabel: "~4x slower", isDefault: false, languageNote: "Multilingual"),
        ModelInfo(name: "large-v3_turbo", displayName: "Large v3 Turbo", sizeBytes: 3_100_000_000, accuracyLabel: "Best", speedLabel: "~3x slower", isDefault: false, languageNote: "Multilingual"),
    ]

    init(database: AppDatabase) {
        self.database = database
    }

    func setProgressHandler(_ handler: @escaping @MainActor @Sendable (String, ModelDownloadState) -> Void) {
        self.progressHandler = handler
    }

    func downloadModel(name: String) async throws(ModelDownloadError) {
        guard !isModelDownloadedSync(name: name) else { return }

        cancelledModels.remove(name)
        downloadStartTime[name] = Date()
        await reportProgress(name, .downloading(progress: 0, speedDescription: nil))

        var lastError: ModelDownloadError?
        let maxRetries = 3
        let backoffSeconds: [UInt64] = [1, 2, 4]

        for attempt in 0..<maxRetries {
            if cancelledModels.contains(name) {
                downloadStartTime[name] = nil
                await reportProgress(name, .notDownloaded)
                throw .downloadInterrupted
            }

            do {
                try await performDownload(name: name)
                downloadStartTime[name] = nil
                await database.writeSetting(key: "download_progress_\(name)", value: "")
                await reportProgress(name, .downloaded)
                Self.logger.info("Model \(name) downloaded successfully")
                return
            } catch let error as ModelDownloadError {
                lastError = error
                Self.logger.warning("Download attempt \(attempt + 1)/\(maxRetries) failed for \(name): \(String(describing: error))")

                if attempt < maxRetries - 1 {
                    try? await Task.sleep(for: .seconds(backoffSeconds[attempt]))
                }
            } catch {
                lastError = .networkFailed
                Self.logger.warning("Download attempt \(attempt + 1)/\(maxRetries) failed for \(name): \(error)")

                if attempt < maxRetries - 1 {
                    try? await Task.sleep(for: .seconds(backoffSeconds[attempt]))
                }
            }
        }

        downloadStartTime[name] = nil
        let errorMessage = String(describing: lastError ?? .networkFailed)
        await reportProgress(name, .failed(errorMessage))
        Self.logger.error("Model download exhausted retries for \(name)")
        throw lastError ?? .networkFailed
    }

    func cancelDownload(name: String) {
        cancelledModels.insert(name)
        activeDownloads[name]?.cancel()
        activeDownloads[name] = nil
        downloadStartTime[name] = nil
    }

    func isModelDownloaded(name: String) async -> Bool {
        if name == "base" { return true }
        if let storedPath = await database.readSetting(key: "model_path_\(name)"),
           !storedPath.isEmpty,
           FileManager.default.fileExists(atPath: storedPath) {
            return true
        }
        return isModelDownloadedSync(name: name)
    }

    func deleteModel(name: String) async {
        guard name != "base" else {
            Self.logger.warning("Cannot delete base model")
            return
        }
        let modelDir = modelDirectory(for: name)
        try? FileManager.default.removeItem(at: modelDir)
        if let storedPath = await database.readSetting(key: "model_path_\(name)"),
           !storedPath.isEmpty {
            try? FileManager.default.removeItem(atPath: storedPath)
        }
        await database.writeSetting(key: "download_progress_\(name)", value: "")
        await database.writeSetting(key: "model_path_\(name)", value: "")
        await reportProgress(name, .notDownloaded)
        Self.logger.info("Deleted model: \(name)")
    }

    /// Check for interrupted downloads on startup and restore their state
    func checkForInterruptedDownloads() async -> [String: Double] {
        var interrupted: [String: Double] = [:]
        for model in availableModels where model.name != "base" {
            if let progressStr = await database.readSetting(key: "download_progress_\(model.name)"),
               !progressStr.isEmpty,
               let progress = Double(progressStr),
               progress > 0, progress < 1.0,
               !isModelDownloadedSync(name: model.name) {
                interrupted[model.name] = progress
            }
        }
        return interrupted
    }

    // MARK: - Private

    private func performDownload(name: String) async throws(ModelDownloadError) {
        let downloadedPath: URL
        do {
            try Task.checkCancellation()

            downloadedPath = try await WhisperKit.download(
                variant: name,
                from: "argmaxinc/whisperkit-coreml",
                progressCallback: { [weak self] progress in
                    guard let self else { return }
                    Task {
                        await self.handleDownloadProgress(name: name, progress: progress)
                    }
                }
            )

            try Task.checkCancellation()
        } catch is CancellationError {
            throw .downloadInterrupted
        } catch let error as ModelDownloadError {
            throw error
        } catch let error as NSError where error.domain == NSCocoaErrorDomain
            && (error.code == NSFileWriteOutOfSpaceError || error.code == NSFileWriteVolumeReadOnlyError) {
            throw .diskSpaceInsufficient
        } catch {
            throw .networkFailed
        }

        guard FileManager.default.fileExists(atPath: downloadedPath.path) else {
            throw .invalidModelData
        }

        // Store the actual download path so isModelDownloaded can find it
        await database.writeSetting(key: "model_path_\(name)", value: downloadedPath.path)
    }

    private func handleDownloadProgress(name: String, progress: Progress) async {
        let fraction = progress.fractionCompleted

        var speedDescription: String?
        if let startTime = downloadStartTime[name],
           let modelInfo = availableModels.first(where: { $0.name == name }) {
            let elapsed = Date().timeIntervalSince(startTime)
            if elapsed > 1.0 {
                let totalBytes = Double(modelInfo.sizeBytes)
                let downloadedBytes = fraction * totalBytes
                let bytesPerSecond = downloadedBytes / elapsed

                if bytesPerSecond > 0 {
                    let remainingBytes = totalBytes - downloadedBytes
                    let remainingSeconds = remainingBytes / bytesPerSecond
                    let speedStr = ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .file)
                    let etaStr = formatTimeRemaining(remainingSeconds)
                    speedDescription = "\(speedStr)/s \u{2022} ~\(etaStr) remaining"
                }
            }
        }

        await database.writeSetting(
            key: "download_progress_\(name)",
            value: String(format: "%.4f", fraction)
        )
        await reportProgress(name, .downloading(progress: fraction, speedDescription: speedDescription))
    }

    private func formatTimeRemaining(_ seconds: Double) -> String {
        if seconds < 60 { return "\(Int(seconds))s" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        let hours = Int(seconds / 3600)
        let mins = Int(seconds.truncatingRemainder(dividingBy: 3600) / 60)
        return "\(hours)h \(mins)m"
    }

    private func isModelDownloadedSync(name: String) -> Bool {
        if name == "base" { return true }
        let modelDir = modelDirectory(for: name)
        return FileManager.default.fileExists(atPath: modelDir.path)
    }

    private func modelDirectory(for name: String) -> URL {
        (try? whisperKitModelDirectory(for: name)) ?? fallbackModelDirectory(for: name)
    }

    private func whisperKitModelDirectory(for name: String) throws -> URL {
        let base = try modelsBaseDirectory()
        let directPath = base.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: directPath.path) {
            return directPath
        }
        return base
            .appendingPathComponent("argmaxinc")
            .appendingPathComponent("whisperkit-coreml")
            .appendingPathComponent("openai_whisper-\(name)")
    }

    private func fallbackModelDirectory(for name: String) -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("meet-notes")
            .appendingPathComponent("Models")
            .appendingPathComponent(name)
    }

    private func modelsBaseDirectory() throws -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let modelsDir = appSupport
            .appendingPathComponent("meet-notes")
            .appendingPathComponent("Models")
        try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        return modelsDir
    }

    private func reportProgress(_ modelName: String, _ state: ModelDownloadState) async {
        guard let handler = progressHandler else { return }
        await MainActor.run { handler(modelName, state) }
    }
}
