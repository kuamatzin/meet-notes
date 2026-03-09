import AppKit
import Sparkle

class AppDelegate: NSObject, NSApplicationDelegate {
    let updaterController: SPUStandardUpdaterController
    weak var recordingService: RecordingService?

    override init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Task { await NotificationService.shared.configure() }

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(systemWillSleep),
            name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification, object: nil)
    }

    @objc private func systemWillSleep(_ notification: Notification) {
        Task { await recordingService?.handleSleep() }
    }

    @objc private func systemDidWake(_ notification: Notification) {
        Task { await recordingService?.handleWake() }
    }
}
