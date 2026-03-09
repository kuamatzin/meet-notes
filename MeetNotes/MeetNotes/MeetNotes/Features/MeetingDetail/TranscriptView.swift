import AppKit
import SwiftUI

struct TranscriptView: View {
    let segments: [TranscriptSegment]
    let isTranscribing: Bool
    var matchedSegmentIDs: Set<Int64> = []
    var searchQuery: String = ""

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAtBottom = true

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(segments) { segment in
                            TranscriptSegmentRow(
                                segment: segment,
                                searchQuery: matchedSegmentIDs.contains(segment.id ?? -1) ? searchQuery : ""
                            )
                            .id(segment.id)
                            .transition(reduceMotion ? .identity : .opacity)
                        }

                        if isTranscribing {
                            ProcessingIndicator()
                                .id("transcript-bottom")
                        }

                        GeometryReader { geo in
                            Color.clear
                                .preference(
                                    key: ScrollOffsetPreferenceKey.self,
                                    value: geo.frame(in: .named("transcript-scroll")).maxY
                                )
                        }
                        .frame(height: 1)
                        .id("transcript-end")
                    }
                    .padding()
                    .animation(reduceMotion ? nil : .easeIn(duration: 0.15), value: segments.count)
                }
                .coordinateSpace(name: "transcript-scroll")
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { maxY in
                    isAtBottom = maxY < 800
                }
                .onChange(of: segments.count) { _, _ in
                    if isAtBottom {
                        let scrollTarget: String = isTranscribing ? "transcript-bottom" : "transcript-end"
                        if reduceMotion {
                            proxy.scrollTo(scrollTarget, anchor: .bottom)
                        } else {
                            withAnimation(.easeIn(duration: 0.15)) {
                                proxy.scrollTo(scrollTarget, anchor: .bottom)
                            }
                        }
                    }
                }
                .onChange(of: matchedSegmentIDs) { _, newIDs in
                    guard !newIDs.isEmpty else { return }
                    if let firstMatchId = segments.first(where: { newIDs.contains($0.id ?? -1) })?.id {
                        if reduceMotion {
                            proxy.scrollTo(firstMatchId, anchor: .top)
                        } else {
                            withAnimation(.easeIn(duration: 0.2)) {
                                proxy.scrollTo(firstMatchId, anchor: .top)
                            }
                        }
                    }
                }
            }

            if !isAtBottom && isTranscribing {
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
                .accessibilityLabel("Jump to live transcript")
            }
        }
    }
}

private struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct TranscriptSegmentRow: View {
    let segment: TranscriptSegment
    var searchQuery: String = ""
    @State private var showPopover = false
    @State private var selectedText = ""

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(formatTimestamp(segment.startSeconds))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .leading)
                .monospacedDigit()

            SelectableTextView(
                text: Self.cleanTranscriptText(segment.text),
                isLowConfidence: isLowConfidence,
                highlightTerms: searchQuery.isEmpty ? [] : searchQuery
                    .split(separator: " ")
                    .map(String.init),
                onSelection: { text in
                    selectedText = text
                    showPopover = !text.isEmpty
                }
            )
            .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                TranscriptSelectionPopover(
                    selectedText: selectedText,
                    onDismiss: { showPopover = false }
                )
            }
        }
    }

    private var isLowConfidence: Bool {
        guard let confidence = segment.confidence else { return false }
        return confidence < 0.7
    }

    private static func cleanTranscriptText(_ text: String) -> String {
        text.replacingOccurrences(
            of: "<\\|[^|]*\\|>",
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct SelectableTextView: NSViewRepresentable {
    let text: String
    let isLowConfidence: Bool
    var highlightTerms: [String] = []
    let onSelection: (String) -> Void

    private static let highlightColor = NSColor(Color.accent)

    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isRichText = true
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.delegate = context.coordinator
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        updateTextView(textView)
        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        context.coordinator.onSelection = onSelection
        updateTextView(textView)
    }

    private func updateTextView(_ textView: NSTextView) {
        let color: NSColor = isLowConfidence ? NSColor.secondaryLabelColor : .labelColor
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13),
                .foregroundColor: color
            ]
        )

        for term in highlightTerms where !term.isEmpty {
            let nsText = text as NSString
            var searchRange = NSRange(location: 0, length: nsText.length)
            while searchRange.location < nsText.length {
                let range = nsText.range(of: term, options: .caseInsensitive, range: searchRange)
                guard range.location != NSNotFound else { break }
                attributed.addAttribute(.foregroundColor, value: Self.highlightColor, range: range)
                attributed.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 13), range: range)
                searchRange.location = range.location + range.length
                searchRange.length = nsText.length - searchRange.location
            }
        }

        textView.textStorage?.setAttributedString(attributed)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelection: onSelection)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onSelection: (String) -> Void

        init(onSelection: @escaping (String) -> Void) {
            self.onSelection = onSelection
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let range = textView.selectedRange()
            if range.length > 0, let text = textView.string as NSString? {
                let selected = text.substring(with: range)
                onSelection(selected)
            } else {
                onSelection("")
            }
        }
    }
}

private struct TranscriptSelectionPopover: View {
    let selectedText: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(selectedText, forType: .string)
                onDismiss()
            }
            Divider()
            Button("Create Action Item") {
                // Stub: future story scope
                onDismiss()
            }
            Button("Highlight") {
                // Stub: future story scope
                onDismiss()
            }
        }
        .padding(8)
    }
}

private struct ProcessingIndicator: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let dotCount = Int(context.date.timeIntervalSinceReferenceDate * 2) % 3 + 1
            HStack(spacing: 12) {
                Spacer()
                    .frame(width: 50)
                Text(String(repeating: "\u{00B7}", count: dotCount))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("Transcription in progress")
    }
}

private func formatTimestamp(_ totalSeconds: Double) -> String {
    let hours = Int(totalSeconds) / 3600
    let minutes = (Int(totalSeconds) % 3600) / 60
    let seconds = Int(totalSeconds) % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
    return String(format: "%d:%02d", minutes, seconds)
}
