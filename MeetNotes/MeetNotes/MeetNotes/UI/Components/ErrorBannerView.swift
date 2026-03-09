import SwiftUI

struct ErrorBannerView: View {
    let icon: String
    let message: String
    let recoveryLabel: String
    let recoveryAction: () -> Void
    var secondaryLabel: String?
    var secondaryAction: (() -> Void)?
    var dismissAction: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Color.warningAmber)
                .font(.title3)
                .accessibilityHidden(true)

            Text(message)
                .font(.callout)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isStaticText)

            Button(action: recoveryAction) {
                HStack(spacing: 4) {
                    Text(recoveryLabel)
                    Image(systemName: "chevron.right")
                }
                .font(.callout)
                .foregroundStyle(Color.accent)
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)

            if let secondaryLabel, let secondaryAction {
                Button(action: secondaryAction) {
                    Text(secondaryLabel)
                        .font(.callout)
                        .foregroundStyle(Color.accent)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isButton)
            }

            if let dismissAction {
                Button(action: dismissAction) {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
                .accessibilityAddTraits(.isButton)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.cardBorder, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }
}
