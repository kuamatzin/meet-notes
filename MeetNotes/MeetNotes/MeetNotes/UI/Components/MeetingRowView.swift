import SwiftUI

struct MeetingRowView: View {
    let title: String
    let date: Date
    let durationSeconds: Double?
    let pipelineStatus: Meeting.PipelineStatus

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var onExport: (() -> Void)?
    var onCopySummary: (() -> Void)?
    var onDelete: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(displayTitle)
                .font(.body)
                .fontWeight(.semibold)
                .lineLimit(1)

            HStack(spacing: 6) {
                PipelineStatusBadge(status: pipelineStatus)

                Text(formattedDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let duration = formattedDuration {
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(duration)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onHover { hovering in isHovering = hovering }
        .overlay(alignment: .trailing) {
            if isHovering {
                HStack(spacing: 4) {
                    if let onExport {
                        Button(action: onExport) {
                            Image(systemName: "square.and.arrow.up")
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Export meeting")
                    }
                    if let onCopySummary {
                        Button(action: onCopySummary) {
                            Image(systemName: "doc.on.doc")
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Copy summary")
                    }
                    if let onDelete {
                        Button(action: onDelete) {
                            Image(systemName: "trash")
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Delete meeting")
                    }
                }
                .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: isHovering)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(displayTitle), \(formattedDate)\(formattedDuration.map { ", \($0)" } ?? "")")
    }

    private var displayTitle: String {
        title.isEmpty ? formattedDateFallback : title
    }

    private var formattedDate: String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    private var formattedDateFallback: String {
        date.formatted(date: .long, time: .shortened)
    }

    private var formattedDuration: String? {
        guard let seconds = durationSeconds, seconds > 0 else { return nil }
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}

struct PipelineStatusBadge: View {
    let status: Meeting.PipelineStatus

    var body: some View {
        Image(systemName: iconName)
            .font(.caption2)
            .foregroundStyle(iconColor)
            .accessibilityLabel(accessibilityText)
    }

    private var iconName: String {
        switch status {
        case .recording: "circle.fill"
        case .transcribing: "waveform"
        case .transcribed: "checkmark.circle"
        case .summarizing: "sparkles"
        case .complete: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var iconColor: Color {
        switch status {
        case .recording: .recordingRed
        case .transcribing, .summarizing: .accent
        case .transcribed: .onDeviceGreen
        case .complete: .onDeviceGreen
        case .failed: .warningAmber
        }
    }

    private var accessibilityText: String {
        switch status {
        case .recording: "Recording"
        case .transcribing: "Transcribing"
        case .transcribed: "Transcribed"
        case .summarizing: "Summarizing"
        case .complete: "Complete"
        case .failed: "Failed"
        }
    }
}
