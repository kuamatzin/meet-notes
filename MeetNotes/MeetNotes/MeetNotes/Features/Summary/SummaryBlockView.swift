import AppKit
import SwiftUI

struct SummarySection: Identifiable, Sendable {
    let id: String
    let title: String
    let emoji: String
    let items: [String]
    let isActionItems: Bool
}

enum SummaryMarkdownParser: Sendable {
    static func parse(_ markdown: String) -> [SummarySection] {
        var sections: [SummarySection] = []
        var currentTitle: String?
        var currentItems: [String] = []

        let lines = markdown.components(separatedBy: "\n")
        for line in lines {
            if line.hasPrefix("## ") {
                if let title = currentTitle {
                    sections.append(makeSection(title: title, items: currentItems))
                }
                currentTitle = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                currentItems = []
            } else if line.hasPrefix("- "), currentTitle != nil {
                let item = String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if !item.isEmpty {
                    currentItems.append(item)
                }
            }
        }

        if let title = currentTitle {
            sections.append(makeSection(title: title, items: currentItems))
        }

        return sections
    }

    private static func makeSection(title: String, items: [String]) -> SummarySection {
        let emoji: String
        let isActionItems: Bool

        switch title.lowercased() {
        case "decisions":
            emoji = "\u{1F3AF}"
            isActionItems = false
        case "action items":
            emoji = "\u{2705}"
            isActionItems = true
        case "key topics":
            emoji = "\u{1F4AC}"
            isActionItems = false
        default:
            emoji = "\u{1F4CB}"
            isActionItems = false
        }

        return SummarySection(
            id: title.lowercased().replacingOccurrences(of: " ", with: "-"),
            title: title,
            emoji: emoji,
            items: items,
            isActionItems: isActionItems
        )
    }
}

struct SummaryBlockView: View {
    let section: SummarySection
    let isStreaming: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(section.emoji) \(section.title)")
                .font(.system(size: 15, weight: .semibold))
                .accessibilityLabel("\(section.title) section, \(section.items.count) items")

            if section.isActionItems {
                ForEach(Array(section.items.enumerated()), id: \.offset) { index, item in
                    ActionItemCard(text: item)
                        .transition(reduceMotion ? .identity : .opacity)
                        .animation(
                            reduceMotion ? nil : .easeIn(duration: 0.15).delay(Double(index) * 0.08),
                            value: section.items.count
                        )
                }
            } else {
                ForEach(Array(section.items.enumerated()), id: \.offset) { index, item in
                    bulletItem(item, index: index)
                }
            }

            if isStreaming && !reduceMotion {
                Text("|")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func bulletItem(_ text: String, index: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\u{2022}")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(size: 13))
                .textSelection(.enabled)
        }
        .transition(reduceMotion ? .identity : .opacity)
        .animation(
            reduceMotion ? nil : .easeIn(duration: 0.15).delay(Double(index) * 0.08),
            value: section.items.count
        )
    }
}
