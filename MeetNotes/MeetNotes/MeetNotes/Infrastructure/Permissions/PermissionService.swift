import AppKit
import AVFoundation
import CoreGraphics
import Observation
import os

private let logger = Logger(subsystem: "com.kuamatzin.meet-notes", category: "PermissionService")

@Observable @MainActor final class PermissionService: PermissionChecking {
    var microphoneStatus: PermissionStatus = .notDetermined
    var screenRecordingStatus: PermissionStatus = .notDetermined

    private var notificationObserver: (any NSObjectProtocol)?
    private var screenRecordingUserGranted = false

    init() {
        // If onboarding was completed, trust the user's grant
        if UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") {
            screenRecordingUserGranted = true
        }
        refreshStatus()
        startMonitoring()
    }

    func startMonitoring() {
        guard notificationObserver == nil else { return }
        notificationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshStatus()
            }
        }
        logger.info("Permission monitoring started")
    }

    func stopMonitoring() {
        if let notificationObserver {
            NotificationCenter.default.removeObserver(notificationObserver)
            self.notificationObserver = nil
            logger.info("Permission monitoring stopped")
        }
    }

    func requestMicrophone() async {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        microphoneStatus = granted ? .authorized : .denied
        logger.info("Microphone request result: \(granted ? "authorized" : "denied")")
    }

    func requestScreenRecording() {
        CGRequestScreenCaptureAccess()
        logger.info("Requested screen capture access")
    }

    func acknowledgeScreenRecordingGranted() {
        screenRecordingUserGranted = true
        screenRecordingStatus = .authorized
        logger.info("Screen recording marked as granted by user")
    }

    func openMicrophoneSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else {
            return
        }
        NSWorkspace.shared.open(url)
        logger.info("Opened System Settings for microphone permission")
    }

    func refreshStatus() {
        checkMicrophoneStatus()
        checkScreenRecordingStatus()
    }

    private func checkMicrophoneStatus() {
        let previous = microphoneStatus
        microphoneStatus = PermissionStatus(from: AVCaptureDevice.authorizationStatus(for: .audio))
        if previous == .authorized && microphoneStatus == .denied {
            logger.warning("Microphone permission was revoked")
        }
    }

    // CGPreflightScreenCaptureAccess is deprecated on macOS 15.1+ and unreliable —
    // it returns false even when permission is granted. Once the user has completed
    // onboarding or acknowledged the grant, trust that. If recording actually fails
    // due to missing permission, the error will surface at recording time.
    private func checkScreenRecordingStatus() {
        if screenRecordingUserGranted {
            screenRecordingStatus = .authorized
            return
        }
        let previous = screenRecordingStatus
        let granted = CGPreflightScreenCaptureAccess()
        screenRecordingStatus = granted ? .authorized : .denied
        if granted {
            screenRecordingUserGranted = true
        }
        if previous == .authorized && screenRecordingStatus == .denied {
            logger.warning("Screen recording permission was revoked")
        }
    }
}
