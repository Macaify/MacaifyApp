import SwiftUI

enum SettingsTokens {
    static let cornerRadius: CGFloat = 12
    static let cardPadding: CGFloat = 12
    static let spacing: CGFloat = 16
    static var cardBackground: Color { Color(nsColor: .controlBackgroundColor) }
    static var stroke: Color { Color.gray.opacity(0.12) }
}

struct CardGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            configuration.label
                .font(.subheadline)
                .foregroundStyle(.secondary)
            configuration.content
        }
        .padding(SettingsTokens.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: SettingsTokens.cornerRadius)
                .fill(SettingsTokens.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SettingsTokens.cornerRadius)
                .stroke(SettingsTokens.stroke, lineWidth: 1)
        )
    }
}

