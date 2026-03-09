import GRDB
import Sparkle
import Testing
@testable import MeetNotes

@MainActor
struct CheckForUpdatesViewModelTests {

    // MARK: - canCheckForUpdates binding

    @Test func initialCanCheckForUpdatesMatchesUpdater() {
        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        let vm = CheckForUpdatesViewModel(updater: controller.updater)
        #expect(vm.canCheckForUpdates == controller.updater.canCheckForUpdates)
    }

    // MARK: - Settings auto-update toggle state reflection

    @Test func updaterAutomaticallyChecksForUpdatesIsConfigurable() {
        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        let updater = controller.updater

        updater.automaticallyChecksForUpdates = true
        #expect(updater.automaticallyChecksForUpdates == true)

        updater.automaticallyChecksForUpdates = false
        #expect(updater.automaticallyChecksForUpdates == false)
    }

    // MARK: - App version display correctness

    @Test func appVersionFromBundleIsNonEmpty() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        #expect(version != "Unknown")
    }

    @Test func settingsViewModelExposesAppVersion() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent(UUID().uuidString + ".db").path
        defer {
            try? FileManager.default.removeItem(atPath: dbPath)
            try? FileManager.default.removeItem(atPath: dbPath + "-wal")
            try? FileManager.default.removeItem(atPath: dbPath + "-shm")
        }

        let pool = try DatabasePool(path: dbPath)
        let database = try AppDatabase(pool)
        let vm = SettingsViewModel(
            database: database,
            modelDownloadManager: StubModelDownloadManager(),
            transcriptionService: StubTranscriptionService(),
            appErrorState: AppErrorState()
        )

        #expect(!vm.appVersion.isEmpty)
    }

    // MARK: - CheckForUpdatesViewModel binding behavior

    @Test func canCheckForUpdatesDefaultsToFalseWhenUpdaterNotStarted() {
        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        let vm = CheckForUpdatesViewModel(updater: controller.updater)
        #expect(vm.canCheckForUpdates == false)
    }
}
