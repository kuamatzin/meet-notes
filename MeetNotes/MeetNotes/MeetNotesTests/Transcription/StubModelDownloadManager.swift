import Foundation
@testable import MeetNotes

final class StubModelDownloadManager: ModelDownloadManagerProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _downloadCalled = false
    private var _lastDownloadedModel: String?
    private var _cancelCalled = false
    private var _deleteCalled = false
    private var _lastDeletedModel: String?
    private var _downloadedModels: Set<String> = ["base"]
    var shouldThrowOnDownload: ModelDownloadError?
    private var progressHandler: (@MainActor @Sendable (String, ModelDownloadState) -> Void)?

    var downloadCalled: Bool { lock.withLock { _downloadCalled } }
    var lastDownloadedModel: String? { lock.withLock { _lastDownloadedModel } }
    var cancelCalled: Bool { lock.withLock { _cancelCalled } }
    var deleteCalled: Bool { lock.withLock { _deleteCalled } }
    var lastDeletedModel: String? { lock.withLock { _lastDeletedModel } }

    let availableModels: [ModelInfo] = [
        ModelInfo(name: "base", displayName: "Base", sizeBytes: 145_000_000, accuracyLabel: "Baseline", speedLabel: "Fastest", isDefault: true),
        ModelInfo(name: "small", displayName: "Small", sizeBytes: 465_000_000, accuracyLabel: "+15%", speedLabel: "~2x slower", isDefault: false),
    ]

    func downloadModel(name: String) async throws(ModelDownloadError) {
        lock.withLock {
            _downloadCalled = true
            _lastDownloadedModel = name
        }
        if let error = shouldThrowOnDownload {
            throw error
        }
        lock.withLock { _downloadedModels.insert(name) }
    }

    func cancelDownload(name: String) async {
        lock.withLock { _cancelCalled = true }
    }

    func isModelDownloaded(name: String) async -> Bool {
        lock.withLock { _downloadedModels.contains(name) }
    }

    func deleteModel(name: String) async {
        lock.withLock {
            _deleteCalled = true
            _lastDeletedModel = name
            _downloadedModels.remove(name)
        }
    }

    func setProgressHandler(_ handler: @escaping @MainActor @Sendable (String, ModelDownloadState) -> Void) async {
        progressHandler = handler
    }

    func simulateProgress(_ modelName: String, _ state: ModelDownloadState) async {
        await MainActor.run { [progressHandler] in
            progressHandler?(modelName, state)
        }
    }
}
