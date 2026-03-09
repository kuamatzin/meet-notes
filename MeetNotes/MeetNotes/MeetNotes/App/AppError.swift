import Foundation

enum AppError: LocalizedError, Equatable, Sendable {
    case microphonePermissionDenied
    case screenRecordingPermissionDenied
    case recordingFailed
    case audioCaptureFailed
    case microphoneSetupFailed
    case audioFormatError
    case audioTapLost
    case transcriptionFailed
    case modelDownloadFailed(modelName: String)
    case databaseObservationFailed
    case meetingUpdateFailed
    case keychainSaveFailed
    case keychainDeleteFailed
    case ollamaNotRunning(endpoint: String)
    case summaryFailed
    case invalidAPIKey
    case networkUnavailable
    case modelNotDownloaded
    case searchFailed
    case launchAtLoginFailed

    var errorDescription: String? { bannerMessage }

    var bannerMessage: String {
        switch self {
        case .microphonePermissionDenied:
            "Microphone access required."
        case .screenRecordingPermissionDenied:
            "Screen Recording permission is required to capture audio from meeting apps."
        case .recordingFailed:
            "Recording failed to start. Please try again."
        case .audioCaptureFailed:
            "Failed to capture system audio. Try restarting your meeting app."
        case .microphoneSetupFailed:
            "Microphone setup failed. Check your audio input settings."
        case .audioFormatError:
            "Audio format error. Please try again."
        case .audioTapLost:
            "System audio capture lost. Recording continues with microphone only — no data lost."
        case .transcriptionFailed:
            "Transcription failed. Your recording has been saved."
        case .modelDownloadFailed(let modelName):
            "Failed to download \(modelName) model. Check your connection and try again."
        case .databaseObservationFailed:
            "Failed to load meeting data. Please restart the app."
        case .meetingUpdateFailed:
            "Failed to update meeting. Please try again."
        case .keychainSaveFailed:
            "Failed to save API key to Keychain. Check your system security settings."
        case .keychainDeleteFailed:
            "Failed to delete API key from Keychain. Check your system security settings."
        case .ollamaNotRunning(let endpoint):
            "Ollama isn't running at \(endpoint). Start Ollama to generate your meeting summary. Your transcript is saved — no data lost."
        case .summaryFailed:
            "Summary generation failed. Your transcript is saved — no data lost."
        case .invalidAPIKey:
            "API key invalid or expired."
        case .networkUnavailable:
            "Network unavailable. Check your connection and try again."
        case .modelNotDownloaded:
            "Whisper model not downloaded. Download the model to enable transcription."
        case .searchFailed:
            "Search failed. Try a different query."
        case .launchAtLoginFailed:
            "Failed to update launch at login setting."
        }
    }

    var recoveryLabel: String {
        switch self {
        case .microphonePermissionDenied, .screenRecordingPermissionDenied:
            "Open System Settings →"
        case .recordingFailed, .audioCaptureFailed, .audioFormatError:
            "Dismiss"
        case .microphoneSetupFailed:
            "Open System Settings →"
        case .audioTapLost, .transcriptionFailed, .databaseObservationFailed, .meetingUpdateFailed:
            "Dismiss"
        case .modelDownloadFailed:
            "Retry"
        case .keychainSaveFailed, .keychainDeleteFailed:
            "Dismiss"
        case .ollamaNotRunning:
            "Open Ollama"
        case .summaryFailed:
            "Dismiss"
        case .invalidAPIKey:
            "Update in Settings →"
        case .networkUnavailable:
            "Dismiss"
        case .modelNotDownloaded:
            "Download now →"
        case .searchFailed:
            "Dismiss"
        case .launchAtLoginFailed:
            "Dismiss"
        }
    }

    var sfSymbol: String {
        switch self {
        case .microphonePermissionDenied: "mic.slash.fill"
        case .screenRecordingPermissionDenied: "rectangle.inset.filled.and.person.filled"
        case .recordingFailed, .audioCaptureFailed, .audioFormatError, .transcriptionFailed: "exclamationmark.circle.fill"
        case .microphoneSetupFailed: "mic.slash.fill"
        case .audioTapLost: "waveform.slash"
        case .modelDownloadFailed: "arrow.down.circle.fill"
        case .databaseObservationFailed: "exclamationmark.triangle.fill"
        case .meetingUpdateFailed: "exclamationmark.circle.fill"
        case .keychainSaveFailed, .keychainDeleteFailed: "lock.slash.fill"
        case .ollamaNotRunning: "server.rack"
        case .summaryFailed: "exclamationmark.circle.fill"
        case .invalidAPIKey: "key.fill"
        case .networkUnavailable: "wifi.slash"
        case .modelNotDownloaded: "arrow.down.circle.fill"
        case .searchFailed: "magnifyingglass"
        case .launchAtLoginFailed: "power"
        }
    }

    var systemSettingsURL: URL? {
        switch self {
        case .microphonePermissionDenied:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .screenRecordingPermissionDenied:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        case .recordingFailed, .audioCaptureFailed, .audioFormatError, .audioTapLost,
             .transcriptionFailed, .modelDownloadFailed, .databaseObservationFailed,
             .meetingUpdateFailed:
            nil
        case .microphoneSetupFailed:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .keychainSaveFailed, .keychainDeleteFailed:
            nil
        case .invalidAPIKey, .networkUnavailable, .modelNotDownloaded,
             .ollamaNotRunning, .summaryFailed, .searchFailed, .launchAtLoginFailed:
            nil
        }
    }
}
