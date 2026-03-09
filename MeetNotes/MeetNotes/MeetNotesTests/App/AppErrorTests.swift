import Testing
@testable import MeetNotes

struct AppErrorTests {
    @Test func microphonePermissionDeniedHasCorrectBannerMessage() {
        let error = AppError.microphonePermissionDenied
        #expect(error.bannerMessage.contains("Microphone access required"))
    }

    @Test func screenRecordingPermissionDeniedHasCorrectBannerMessage() {
        let error = AppError.screenRecordingPermissionDenied
        #expect(error.bannerMessage.contains("Screen Recording permission"))
    }

    @Test func microphonePermissionDeniedHasCorrectRecoveryLabel() {
        #expect(AppError.microphonePermissionDenied.recoveryLabel == "Open System Settings →")
    }

    @Test func screenRecordingPermissionDeniedHasCorrectRecoveryLabel() {
        #expect(AppError.screenRecordingPermissionDenied.recoveryLabel == "Open System Settings →")
    }

    @Test func microphonePermissionDeniedHasCorrectSfSymbol() {
        #expect(AppError.microphonePermissionDenied.sfSymbol == "mic.slash.fill")
    }

    @Test func screenRecordingPermissionDeniedHasCorrectSfSymbol() {
        #expect(AppError.screenRecordingPermissionDenied.sfSymbol == "rectangle.inset.filled.and.person.filled")
    }

    @Test func systemSettingsURLReturnsValidURLForEachCase() {
        #expect(AppError.microphonePermissionDenied.systemSettingsURL != nil)
        #expect(AppError.screenRecordingPermissionDenied.systemSettingsURL != nil)
    }

    @Test func appErrorConformsToEquatable() {
        #expect(AppError.microphonePermissionDenied == AppError.microphonePermissionDenied)
        #expect(AppError.microphonePermissionDenied != AppError.screenRecordingPermissionDenied)
    }

    @Test func ollamaNotRunningHasCorrectBannerMessage() {
        let error = AppError.ollamaNotRunning(endpoint: "http://localhost:11434")
        #expect(error.bannerMessage.contains("Ollama isn't running"))
        #expect(error.bannerMessage.contains("http://localhost:11434"))
    }

    @Test func ollamaNotRunningHasCorrectRecoveryLabel() {
        #expect(AppError.ollamaNotRunning(endpoint: "http://localhost:11434").recoveryLabel == "Open Ollama")
    }

    @Test func ollamaNotRunningHasNoSystemSettingsURL() {
        #expect(AppError.ollamaNotRunning(endpoint: "http://localhost:11434").systemSettingsURL == nil)
    }

    @Test func summaryFailedHasCorrectBannerMessage() {
        let error = AppError.summaryFailed
        #expect(error.bannerMessage.contains("Summary generation failed"))
    }

    @Test func summaryFailedHasCorrectRecoveryLabel() {
        #expect(AppError.summaryFailed.recoveryLabel == "Dismiss")
    }

    @Test func summaryFailedHasCorrectSfSymbol() {
        #expect(AppError.summaryFailed.sfSymbol == "exclamationmark.circle.fill")
    }

    // MARK: - invalidAPIKey

    @Test func invalidAPIKeyHasCorrectBannerMessage() {
        let error = AppError.invalidAPIKey
        #expect(error.bannerMessage.contains("API key invalid or expired"))
    }

    @Test func invalidAPIKeyHasCorrectRecoveryLabel() {
        #expect(AppError.invalidAPIKey.recoveryLabel == "Update in Settings →")
    }

    @Test func invalidAPIKeyHasCorrectSfSymbol() {
        #expect(AppError.invalidAPIKey.sfSymbol == "key.fill")
    }

    @Test func invalidAPIKeyHasNoSystemSettingsURL() {
        #expect(AppError.invalidAPIKey.systemSettingsURL == nil)
    }

    // MARK: - networkUnavailable

    @Test func networkUnavailableHasCorrectBannerMessage() {
        let error = AppError.networkUnavailable
        #expect(error.bannerMessage.contains("Network unavailable"))
    }

    @Test func networkUnavailableHasCorrectRecoveryLabel() {
        #expect(AppError.networkUnavailable.recoveryLabel == "Dismiss")
    }

    // MARK: - modelNotDownloaded

    @Test func modelNotDownloadedHasCorrectBannerMessage() {
        let error = AppError.modelNotDownloaded
        #expect(error.bannerMessage.contains("model not downloaded"))
    }

    @Test func modelNotDownloadedHasCorrectRecoveryLabel() {
        #expect(AppError.modelNotDownloaded.recoveryLabel == "Download now →")
    }

    @Test func modelNotDownloadedHasCorrectSfSymbol() {
        #expect(AppError.modelNotDownloaded.sfSymbol == "arrow.down.circle.fill")
    }

    // MARK: - "No data lost" messaging

    @Test func audioTapLostContainsNoDataLostCopy() {
        #expect(AppError.audioTapLost.bannerMessage.contains("no data lost"))
    }

    @Test func ollamaNotRunningContainsNoDataLostCopy() {
        let error = AppError.ollamaNotRunning(endpoint: "http://localhost:11434")
        #expect(error.bannerMessage.contains("no data lost"))
    }

    @Test func summaryFailedContainsNoDataLostCopy() {
        #expect(AppError.summaryFailed.bannerMessage.contains("no data lost"))
    }

    // MARK: - Permission errors have system settings URL

    @Test func permissionErrorsHaveSystemSettingsURL() {
        #expect(AppError.microphonePermissionDenied.systemSettingsURL != nil)
        #expect(AppError.screenRecordingPermissionDenied.systemSettingsURL != nil)
        #expect(AppError.microphoneSetupFailed.systemSettingsURL != nil)
    }
}
