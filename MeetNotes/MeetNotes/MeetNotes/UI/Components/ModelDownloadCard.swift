import SwiftUI

struct ModelDownloadCard: View {
    let modelName: String
    let displayName: String
    let sizeLabel: String
    let accuracyLabel: String
    let speedLabel: String
    var languageNote: String = ""
    let state: ModelDownloadState
    let isSelected: Bool
    var onDownload: () -> Void = {}
    var onCancel: () -> Void = {}
    var onSelect: () -> Void = {}
    var onDelete: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showDownloadPrompt = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow
            badgeRow
            actionArea
        }
        .padding(12)
        .background(Color.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accent : Color.cardBorder, lineWidth: isSelected ? 2 : 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Subviews

    private var headerRow: some View {
        HStack {
            Text(modelEmoji)
            Text(displayName)
                .font(.headline)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accent)
            }
        }
    }

    private var badgeRow: some View {
        HStack(spacing: 8) {
            badge(sizeLabel, icon: "internaldrive")
            badge(accuracyLabel, icon: "target")
            badge(speedLabel, icon: "gauge.with.dots.needle.33percent")
            if !languageNote.isEmpty {
                badge(languageNote, icon: "globe")
            }
        }
        .font(.caption)
    }

    @ViewBuilder
    private var actionArea: some View {
        switch state {
        case .notDownloaded:
            if modelName == "base" {
                readyIndicator
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Button("Download") { onDownload() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .scaleEffect(showDownloadPrompt ? 1.05 : 1.0)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: showDownloadPrompt)
                            .accessibilityLabel("Download \(displayName) model")
                        Button("Select") {
                            showDownloadPrompt = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityLabel("Select model")
                    }
                    if showDownloadPrompt {
                        Text("Download this model first before setting it as active.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

        case .downloading(let progress, let speedDescription):
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: progress)
                    .tint(Color.warningAmber)
                HStack {
                    if let speedDescription {
                        Text("\(Int(progress * 100))% \u{2022} \(speedDescription)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(Int(progress * 100))%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Cancel") { onCancel() }
                        .buttonStyle(.plain)
                        .font(.caption2)
                        .foregroundStyle(Color.recordingRed)
                        .accessibilityLabel("Cancel \(displayName) download")
                }
            }

        case .downloaded:
            if isSelected {
                selectedIndicator
            } else {
                HStack {
                    readyIndicator
                    Spacer()
                    Button("Select") { onSelect() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityLabel("Select \(displayName) model")
                    Button(role: .destructive) { onDelete() } label: {
                        Image(systemName: "trash")
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete \(displayName) model")
                }
            }

        case .failed(let message):
            VStack(alignment: .leading, spacing: 4) {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(Color.recordingRed)
                Button("Retry") { onDownload() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .accessibilityLabel("Retry \(displayName) download")
            }
        }
    }

    private var readyIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.onDeviceGreen)
                .frame(width: 8, height: 8)
            Text("Ready")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var selectedIndicator: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.accent)
            Text("Selected")
                .font(.caption)
                .foregroundStyle(Color.accent)
        }
    }

    private func badge(_ text: String, icon: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
            Text(text)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.cardBorder.opacity(0.5))
        .clipShape(Capsule())
        .foregroundStyle(.secondary)
    }

    private var modelEmoji: String {
        switch modelName {
        case "base": return "🟢"
        case "small": return "🔵"
        case "medium": return "🟠"
        case "large-v3_turbo": return "🟣"
        default: return "⚪"
        }
    }

    private var accessibilityDescription: String {
        let stateDesc: String
        switch state {
        case .notDownloaded: stateDesc = modelName == "base" ? "ready" : "available for download"
        case .downloading(let progress, _): stateDesc = "downloading, \(Int(progress * 100))% complete"
        case .downloaded: stateDesc = isSelected ? "ready, selected" : "ready"
        case .failed: stateDesc = "download failed"
        }
        return "\(displayName) model, \(sizeLabel), accuracy \(accuracyLabel), speed \(speedLabel), \(stateDesc)"
    }
}
