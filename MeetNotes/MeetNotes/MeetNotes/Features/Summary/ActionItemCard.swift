import AppKit
import SwiftUI

struct ActionItemCard: View {
    let text: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @State private var showCopyFlash = false

    private var parsed: ParsedActionItem {
        ParsedActionItem.parse(text)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let assignee = parsed.assignee {
                Text(assignee)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            Text(parsed.task)
                .font(.system(size: 13))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let due = parsed.dueDate {
                Text(due)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(showCopyFlash
                    ? Color.green.opacity(0.15)
                    : Color.cardBg.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    Color.cardBorder.opacity(isHovered ? 0.4 : 0.2),
                    lineWidth: 1
                )
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            copyToClipboard()
        }
        .focusable()
        .onKeyPress(.return) {
            copyToClipboard()
            return .handled
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Double tap to copy to clipboard")
    }

    private var accessibilityText: String {
        var parts: [String] = []
        if let assignee = parsed.assignee {
            parts.append(assignee)
        }
        parts.append(parsed.task)
        if let due = parsed.dueDate {
            parts.append("due \(due)")
        }
        return parts.joined(separator: ", ")
    }

    private func copyToClipboard() {
        var clipboard = ""
        if let assignee = parsed.assignee {
            clipboard += "\(assignee): "
        }
        clipboard += parsed.task
        if let due = parsed.dueDate {
            clipboard += " (due \(due))"
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(clipboard, forType: .string)

        showCopyFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            if reduceMotion {
                showCopyFlash = false
            } else {
                withAnimation(.easeOut(duration: 0.3)) {
                    showCopyFlash = false
                }
            }
        }
    }
}

struct ParsedActionItem: Sendable {
    let assignee: String?
    let task: String
    let dueDate: String?

    static func parse(_ text: String) -> ParsedActionItem {
        var assignee: String?
        var task = text
        var dueDate: String?

        // Extract due date pattern: (due YYYY-MM-DD) or (by YYYY-MM-DD) at end
        if let dueRange = task.range(of: #"\((?:due|by)\s+[^)]+\)\s*$"#, options: .regularExpression) {
            let dueString = String(task[dueRange])
                .trimmingCharacters(in: CharacterSet(charactersIn: "()"))
                .replacingOccurrences(of: "due ", with: "")
                .replacingOccurrences(of: "by ", with: "")
                .trimmingCharacters(in: .whitespaces)
            dueDate = dueString
            task = String(task[task.startIndex..<dueRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        }

        // Extract assignee: "Name to verb..." or "Name: task..."
        if let colonRange = task.range(of: ": ", options: []) {
            let potentialAssignee = String(task[task.startIndex..<colonRange.lowerBound])
            if potentialAssignee.count <= 30 && !potentialAssignee.contains(" to ") {
                assignee = potentialAssignee
                task = String(task[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
        } else if let toRange = task.range(of: " to ", options: []) {
            let potentialAssignee = String(task[task.startIndex..<toRange.lowerBound])
            let words = potentialAssignee.split(separator: " ")
            if words.count <= 3 && words.allSatisfy({ $0.first?.isUppercase == true }) {
                assignee = potentialAssignee
                task = String(task[toRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
        }

        return ParsedActionItem(assignee: assignee, task: task, dueDate: dueDate)
    }
}
