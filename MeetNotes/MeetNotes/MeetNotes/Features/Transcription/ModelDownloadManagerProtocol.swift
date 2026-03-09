import Foundation

enum ModelDownloadError: Error, Sendable, Equatable {
    case networkFailed
    case diskSpaceInsufficient
    case downloadInterrupted
    case invalidModelData
}

enum ModelDownloadState: Sendable, Equatable {
    case notDownloaded
    case downloading(progress: Double, speedDescription: String?)
    case downloaded
    case failed(String)

    static func downloading(progress: Double) -> ModelDownloadState {
        .downloading(progress: progress, speedDescription: nil)
    }
}

struct ModelInfo: Sendable, Equatable {
    let name: String
    let displayName: String
    let sizeBytes: Int64
    let accuracyLabel: String
    let speedLabel: String
    let isDefault: Bool
    var languageNote: String = ""

    var sizeLabel: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: sizeBytes)
    }
}

protocol ModelDownloadManagerProtocol: Sendable {
    func downloadModel(name: String) async throws(ModelDownloadError)
    func cancelDownload(name: String) async
    func isModelDownloaded(name: String) async -> Bool
    func deleteModel(name: String) async
    func setProgressHandler(_ handler: @escaping @MainActor @Sendable (String, ModelDownloadState) -> Void) async
    var availableModels: [ModelInfo] { get }
}
