import AppKit
import SwiftUI

struct MainWindowView: View {
    @Environment(PermissionService.self) private var permissionService
    @Environment(AppErrorState.self) private var appErrorState
    @Environment(RecordingViewModel.self) private var recordingVM
    @Environment(MeetingListViewModel.self) private var meetingListVM
    @Environment(MeetingDetailViewModel.self) private var meetingDetailVM

    var body: some View {
        VStack(spacing: 0) {
            PermissionBannersView(
                permissionService: permissionService,
                appErrorState: appErrorState,
                onRetrySummary: { meetingDetailVM.retrySummary() }
            )
            .padding(.horizontal)
            .padding(.top, 8)

            switch recordingVM.state {
            case .idle, .error:
                MeetingListView()
            case .recording(let startedAt, let audioQuality):
                Spacer()
                RecordingInProgressView(
                    recordingVM: recordingVM,
                    startedAt: startedAt,
                    audioQuality: audioQuality
                )
                Spacer()
            case .processing:
                Spacer()
                ProcessingInProgressView()
                Spacer()
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .navigationTitle(windowTitle)
        .toolbar {
            if case .recording(let startedAt, _) = recordingVM.state {
                ToolbarItem(placement: .automatic) {
                    RecordingIndicatorToolbar(startedAt: startedAt)
                }
            }
        }
        .onAppear {
            meetingListVM.startObservation()
        }
    }

    private var windowTitle: String {
        switch recordingVM.state {
        case .recording:
            "Recording"
        case .processing:
            "Processing"
        default:
            "Meetings"
        }
    }
}

private struct RecordingIndicatorToolbar: View {
    let startedAt: Date

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.recordingRed)
                .frame(width: 8, height: 8)
            Text(timerInterval: startedAt...(.distantFuture), countsDown: false)
                .monospacedDigit()
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}


private struct RecordingInProgressView: View {
    let recordingVM: RecordingViewModel
    let startedAt: Date
    let audioQuality: AudioQuality

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 16) {
            Circle()
                .fill(Color.recordingRed)
                .frame(width: 16, height: 16)
            Text("Recording in Progress")
                .font(.title2).fontWeight(.semibold)
            Text(timerInterval: startedAt...(.distantFuture), countsDown: false)
                .monospacedDigit()
                .font(.system(.largeTitle, design: .monospaced))
                .foregroundStyle(.primary)
            Button("Stop Recording") {
                Task { await recordingVM.stopRecording() }
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.recordingRed)
            .font(.headline)
            .frame(minHeight: 44)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: recordingVM.state)
    }
}

private struct ProcessingInProgressView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Processing Meeting")
                .font(.title2).fontWeight(.semibold)
            Text("Transcribing and summarizing your meeting...")
                .font(.body).foregroundStyle(.secondary)
        }
    }
}

private struct PermissionBannersView: View {
    let permissionService: PermissionService
    let appErrorState: AppErrorState
    let onRetrySummary: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            if !permissionService.microphoneStatus.isGranted {
                ErrorBannerView(
                    icon: "mic.slash.fill",
                    message: "Microphone access required.",
                    recoveryLabel: "Open System Settings →",
                    recoveryAction: { permissionService.openMicrophoneSettings() }
                )
                .transition(reduceMotion ? .identity : .opacity)
            }

            if !permissionService.screenRecordingStatus.isGranted {
                ErrorBannerView(
                    icon: "rectangle.inset.filled.and.person.filled",
                    message: "Screen Recording permission is required to capture audio from meeting apps. If already granted, restart the app.",
                    recoveryLabel: "System Settings →",
                    recoveryAction: { permissionService.requestScreenRecording() }
                )
                .transition(reduceMotion ? .identity : .opacity)
            }

            if let error = appErrorState.current {
                ErrorBannerView(
                    icon: error.sfSymbol,
                    message: error.bannerMessage,
                    recoveryLabel: error.recoveryLabel,
                    recoveryAction: { performRecovery(for: error) },
                    secondaryLabel: secondaryLabel(for: error),
                    secondaryAction: secondaryAction(for: error),
                    dismissAction: { appErrorState.clear() }
                )
                .transition(reduceMotion ? .identity : .opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: permissionService.microphoneStatus.isGranted)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: permissionService.screenRecordingStatus.isGranted)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: appErrorState.current)
    }

    private func performRecovery(for error: AppError) {
        switch error {
        case .ollamaNotRunning:
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Ollama.app"))
        case .invalidAPIKey, .modelNotDownloaded:
            NSApp.activate()
            NSApp.sendAction(Selector("showSettingsWindow:"), to: nil, from: nil)
        case .microphonePermissionDenied, .screenRecordingPermissionDenied, .microphoneSetupFailed:
            if let url = error.systemSettingsURL {
                NSWorkspace.shared.open(url)
            }
        default:
            appErrorState.clear()
        }
    }

    private func secondaryLabel(for error: AppError) -> String? {
        if case .ollamaNotRunning = error { return "Retry" }
        return nil
    }

    private func secondaryAction(for error: AppError) -> (() -> Void)? {
        if case .ollamaNotRunning = error {
            return {
                appErrorState.clear()
                onRetrySummary?()
            }
        }
        return nil
    }
}
