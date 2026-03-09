import AVFoundation

enum PermissionStatus: Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted

    var isGranted: Bool {
        self == .authorized
    }
}

extension PermissionStatus {
    init(from avStatus: AVAuthorizationStatus) {
        switch avStatus {
        case .notDetermined: self = .notDetermined
        case .authorized: self = .authorized
        case .denied: self = .denied
        case .restricted: self = .restricted
        @unknown default: self = .denied
        }
    }
}

@MainActor
protocol PermissionChecking {
    var microphoneStatus: PermissionStatus { get }
    var screenRecordingStatus: PermissionStatus { get }
    func requestMicrophone() async
    func requestScreenRecording()
    func acknowledgeScreenRecordingGranted()
    func openMicrophoneSettings()
    func refreshStatus()
}
