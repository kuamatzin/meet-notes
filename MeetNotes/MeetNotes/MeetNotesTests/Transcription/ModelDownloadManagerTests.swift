import Foundation
import GRDB
import Testing
@testable import MeetNotes

struct ModelDownloadManagerTests {
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

    // MARK: - Available Models

    @Test func availableModelsContainsExpectedModels() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let manager = ModelDownloadManager(database: database)
        let models = await manager.availableModels
        #expect(models.count == 4)
        #expect(models[0].name == "base")
        #expect(models[0].isDefault == true)
        #expect(models[1].name == "small")
        #expect(models[2].name == "medium")
        #expect(models[3].name == "large-v3-turbo")
    }

    // MARK: - Model Downloaded Check

    @Test func baseModelAlwaysReportsDownloaded() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let manager = ModelDownloadManager(database: database)
        let isDownloaded = await manager.isModelDownloaded(name: "base")
        #expect(isDownloaded == true)
    }

    @Test func nonExistentModelReportsNotDownloaded() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let manager = ModelDownloadManager(database: database)
        let isDownloaded = await manager.isModelDownloaded(name: "nonexistent-model")
        #expect(isDownloaded == false)
    }

    // MARK: - Delete Model

    @Test func cannotDeleteBaseModel() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let manager = ModelDownloadManager(database: database)
        await manager.deleteModel(name: "base")
        let isDownloaded = await manager.isModelDownloaded(name: "base")
        #expect(isDownloaded == true)
    }

    // MARK: - Progress Handler

    @Test func progressHandlerCanBeSet() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let manager = ModelDownloadManager(database: database)

        var handlerCalled = false
        await manager.setProgressHandler { _, _ in
            handlerCalled = true
        }

        // The handler is set — verify no crash. Actual progress reporting
        // is tested via integration since it requires real downloads.
        #expect(!handlerCalled)
    }

    // MARK: - Cancellation

    @Test func cancelDownloadDoesNotCrash() async throws {
        let (database, dbPath) = try makeDatabase()
        defer { cleanupDatabase(atPath: dbPath) }

        let manager = ModelDownloadManager(database: database)
        // Cancelling a model that isn't downloading should be a no-op
        await manager.cancelDownload(name: "small")
        // Verify no crash
    }

    // MARK: - ModelDownloadState

    @Test func modelDownloadStateEquality() {
        #expect(ModelDownloadState.notDownloaded == ModelDownloadState.notDownloaded)
        #expect(ModelDownloadState.downloaded == ModelDownloadState.downloaded)
        #expect(ModelDownloadState.downloading(progress: 0.5) == ModelDownloadState.downloading(progress: 0.5))
        #expect(ModelDownloadState.downloading(progress: 0.5) != ModelDownloadState.downloading(progress: 0.7))
        #expect(ModelDownloadState.failed("a") == ModelDownloadState.failed("a"))
        #expect(ModelDownloadState.failed("a") != ModelDownloadState.failed("b"))
    }

    // MARK: - ModelDownloadError

    @Test func modelDownloadErrorEquality() {
        #expect(ModelDownloadError.networkFailed == ModelDownloadError.networkFailed)
        #expect(ModelDownloadError.diskSpaceInsufficient == ModelDownloadError.diskSpaceInsufficient)
        #expect(ModelDownloadError.downloadInterrupted == ModelDownloadError.downloadInterrupted)
        #expect(ModelDownloadError.invalidModelData == ModelDownloadError.invalidModelData)
        #expect(ModelDownloadError.networkFailed != ModelDownloadError.diskSpaceInsufficient)
    }

    // MARK: - ModelInfo

    @Test func modelInfoSizeLabelFormatsCorrectly() {
        let model = ModelInfo(name: "test", displayName: "Test", sizeBytes: 145_000_000, accuracyLabel: "Good", speedLabel: "Fast", isDefault: false)
        #expect(!model.sizeLabel.isEmpty)
    }
}
