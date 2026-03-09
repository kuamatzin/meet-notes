import SwiftUI

struct MenuBarPopoverView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(PermissionService.self) private var permissionService
    @Environment(RecordingViewModel.self) private var recordingVM
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var anyPermissionDenied: Bool {
        !permissionService.microphoneStatus.isGranted || !permissionService.screenRecordingStatus.isGranted
    }

    var body: some View {
        VStack(spacing: 0) {
            if anyPermissionDenied {
                PermissionWarningRow(openWindow: openWindow)
                Divider()
            }

            RecordingControlSection(recordingVM: recordingVM, reduceMotion: reduceMotion)
            Divider()

            Button("Open meet-notes") {
                NSApp.activate()
                openWindow(id: "Meetings")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .accessibilityLabel("Open meet-notes window")

            Divider()

            Button("Quit") {
                NSApp.terminate(nil)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .accessibilityLabel("Quit meet-notes")
        }
        .frame(width: 240)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct RecordingControlSection: View {
    let recordingVM: RecordingViewModel
    let reduceMotion: Bool

    var body: some View {
        switch recordingVM.state {
        case .idle:
            IdleRecordingRow(recordingVM: recordingVM)
        case .recording(let startedAt, let audioQuality):
            ActiveRecordingRow(
                recordingVM: recordingVM,
                startedAt: startedAt,
                audioQuality: audioQuality,
                reduceMotion: reduceMotion
            )
        case .processing:
            ProcessingRow()
        case .error:
            IdleRecordingRow(recordingVM: recordingVM)
        }
    }
}

private struct IdleRecordingRow: View {
    let recordingVM: RecordingViewModel

    var body: some View {
        Button {
            Task { await recordingVM.startRecording() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "record.circle")
                    .foregroundStyle(Color.recordingRed)
                Text("Start Recording")
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityLabel("Start recording")
        .accessibilityHint("Begins capturing meeting audio")
    }
}

private struct ActiveRecordingRow: View {
    let recordingVM: RecordingViewModel
    let startedAt: Date
    let audioQuality: AudioQuality
    let reduceMotion: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.recordingRed)
                    .frame(width: 8, height: 8)
                Text("Recording")
                    .font(.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                Spacer()
                AudioQualityBadge(quality: audioQuality)
            }

            HStack(spacing: 8) {
                Text(timerInterval: startedAt...(.distantFuture), countsDown: false)
                    .monospacedDigit()
                    .font(.system(.title3, design: .monospaced))
                    .foregroundStyle(.primary)
                Spacer()
            }

            Button {
                Task { await recordingVM.stopRecording() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "stop.fill")
                    Text("Stop Recording")
                }
                .font(.callout)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color.recordingRed)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop recording")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: recordingVM.state)
    }
}

private struct AudioQualityBadge: View {
    let quality: AudioQuality

    var body: some View {
        Text(quality.label)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(quality.badgeColor.opacity(0.2))
            .foregroundStyle(quality.badgeColor)
            .clipShape(Capsule())
            .accessibilityLabel("Audio quality: \(quality.label)")
    }
}

extension AudioQuality {
    var label: String {
        switch self {
        case .full: "Full"
        case .micOnly: "Mic Only"
        case .partial: "Partial"
        }
    }

    var badgeColor: Color {
        switch self {
        case .full: .onDeviceGreen
        case .micOnly: .warningAmber
        case .partial: .warningAmber
        }
    }
}

private struct ProcessingRow: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.7)
            Text("Processing...")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Processing meeting audio")
    }
}

private struct PermissionWarningRow: View {
    let openWindow: OpenWindowAction

    var body: some View {
        Button {
            NSApp.activate()
            openWindow(id: "Meetings")
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.warningAmber)
                Text("Permissions needed")
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityLabel("Permissions needed, tap to open settings")
    }
}
