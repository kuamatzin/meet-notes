import AppKit
import SwiftUI

struct SummaryView: View {
    let summaryMarkdown: String?
    let isSummarizing: Bool
    let isStreamingSummary: Bool
    let llmProviderLabel: String?
    var summaryError: AppError?
    var onRetry: (() -> Void)?
    var onDismissError: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let markdown = summaryMarkdown {
            summaryContent(markdown: markdown)
        } else if isSummarizing {
            skeletonPlaceholder
        } else if let error = summaryError {
            summaryErrorCard(error)
        }
    }

    @ViewBuilder
    private func summaryContent(markdown: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            summaryHeader

            let sections = SummaryMarkdownParser.parse(markdown)

            ForEach(sections) { section in
                SummaryBlockView(
                    section: section,
                    isStreaming: isStreamingSummary
                )
            }
        }
        .padding()
        .transition(reduceMotion ? .identity : .opacity)
    }

    private var summaryHeader: some View {
        HStack {
            Text("Summary")
                .font(.system(size: 15, weight: .semibold))

            Spacer()

            if let label = llmProviderLabel {
                LLMPathBadge(label: label)
            }
        }
    }

    private var skeletonPlaceholder: some View {
        VStack(alignment: .leading, spacing: 16) {
            summaryHeader

            VStack(alignment: .leading, spacing: 8) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(.quaternary)
                        .frame(height: 14)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding()
    }

    @ViewBuilder
    private func summaryErrorCard(_ error: AppError) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            summaryHeader

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.warningAmber)
                    Text(error.bannerMessage)
                        .font(.system(size: 13))
                }

                HStack(spacing: 8) {
                    if case .ollamaNotRunning = error {
                        Button("Open Ollama") {
                            NSWorkspace.shared.open(URL(string: "ollama://")!)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityLabel("Open Ollama application")
                    }

                    if let onRetry {
                        Button("Retry") { onRetry() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .accessibilityLabel("Retry summary generation")
                    }

                    if let onDismissError {
                        Button("Dismiss") { onDismissError() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .accessibilityLabel("Dismiss error")
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
            )
        }
        .padding()
    }
}

private struct LLMPathBadge: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary)
            .clipShape(Capsule())
    }
}
