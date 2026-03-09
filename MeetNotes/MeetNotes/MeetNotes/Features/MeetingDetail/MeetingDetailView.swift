import SwiftUI

struct MeetingDetailView: View {
    @Environment(MeetingDetailViewModel.self) private var viewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isAtBottom = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let meeting = viewModel.meeting {
                MeetingDetailHeader(meeting: meeting)
                    .padding()

                Divider()

                ZStack(alignment: .bottom) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                SummaryView(
                                    summaryMarkdown: viewModel.summaryMarkdown,
                                    isSummarizing: viewModel.isSummarizing,
                                    isStreamingSummary: viewModel.isStreamingSummary,
                                    llmProviderLabel: viewModel.llmProviderLabel,
                                    summaryError: viewModel.summaryError,
                                    onRetry: { viewModel.retrySummary() },
                                    onDismissError: { viewModel.dismissSummaryError() }
                                )

                                if viewModel.summaryMarkdown != nil || viewModel.isSummarizing {
                                    Divider()
                                        .padding(.horizontal)
                                }

                                TranscriptView(
                                    segments: viewModel.segments,
                                    isTranscribing: viewModel.isTranscribing,
                                    matchedSegmentIDs: viewModel.matchedSegmentIDs,
                                    searchQuery: viewModel.activeSearchQuery
                                )

                                Color.clear.frame(height: 1).id("detail-bottom")
                                    .onAppear { isAtBottom = true }
                                    .onDisappear { isAtBottom = false }
                            }
                        }
                        .onChange(of: viewModel.summaryMarkdown) { _, _ in
                            if isAtBottom && viewModel.isStreamingSummary {
                                if reduceMotion {
                                    proxy.scrollTo("detail-bottom", anchor: .bottom)
                                } else {
                                    withAnimation(.easeIn(duration: 0.15)) {
                                        proxy.scrollTo("detail-bottom", anchor: .bottom)
                                    }
                                }
                            }
                        }
                    }

                    if !isAtBottom && viewModel.isStreamingSummary {
                        Button {
                            isAtBottom = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.system(size: 11))
                                Text("Jump to live")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.regularMaterial)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, 12)
                        .transition(reduceMotion ? .identity : .opacity)
                        .accessibilityLabel("Jump to live content")
                    }
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct MeetingDetailHeader: View {
    let meeting: Meeting

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private var formattedDate: String {
        Self.dateFormatter.string(from: meeting.startedAt)
    }

    private var formattedDuration: String? {
        guard let duration = meeting.durationSeconds else { return nil }
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        if hours > 0 {
            return String(format: "%dh %dm %ds", hours, minutes, seconds)
        }
        return String(format: "%dm %ds", minutes, seconds)
    }

    private var showAudioQualityBadge: Bool {
        meeting.audioQuality == .micOnly || meeting.audioQuality == .partial
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(meeting.title.isEmpty ? "Untitled Meeting" : meeting.title)
                .font(.system(size: 13, weight: .medium))

            HStack(spacing: 8) {
                Text(formattedDate)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                if let duration = formattedDuration {
                    Text("·")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(duration)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            if showAudioQualityBadge {
                AudioQualityBadgeView(audioQuality: meeting.audioQuality)
                    .padding(.top, 4)
            }
        }
    }
}

private struct AudioQualityBadgeView: View {
    let audioQuality: Meeting.AudioQuality

    private var badgeText: String {
        switch audioQuality {
        case .micOnly:
            "Microphone only — system audio was unavailable during this meeting."
        case .partial:
            "Partial recording — system audio was unavailable during part of this meeting."
        case .full:
            ""
        }
    }

    @ViewBuilder
    var body: some View {
        if !badgeText.isEmpty {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9))
                Text(badgeText)
                    .font(.system(size: 11))
            }
            .foregroundStyle(Color.warningAmber)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(badgeText)
        }
    }
}
