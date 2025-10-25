import SwiftUI

struct ModelDetailCard: View {
    let item: RemoteModelItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    Circle().fill(Color.gray.opacity(0.12))
                    Text(String(item.provider.prefix(1)).uppercased())
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.primary)
                }
                .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(.headline).foregroundStyle(.primary)
                    if let desc = item.description, !desc.isEmpty {
                        Text(desc)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    } else {
                        Text(item.provider.capitalized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            Divider().overlay(Color.gray.opacity(0.2)).padding(.horizontal, -12)

            // Spec rows
            VStack(alignment: .leading, spacing: 10) {
                if let s = item.scoreSpeed { SpecRowLeft("Speed") { ScoreBars(score: s) } }
                if let iq = item.scoreIntelligence { SpecRowLeft("Intelligence") { ScoreBars(score: iq) } }
                SpecRowLeft("模型接口") { Text(item.provider.capitalized) }
                if let ctx = item.contextTokens {
                    SpecRowLeft("Context") { Text(tokenString(ctx)).fontWeight(.semibold) }
                    Text(wordAndPageHint(ctx))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 84)
                }
                SpecRowLeft("Recommended") { Text("AI Chat"); Spacer(); Image(systemName: "checkmark") }
                // Supports list
                VStack(alignment: .leading, spacing: 6) {
                    Text("Supports").foregroundStyle(.secondary)
                    if item.supportsWeb { supportRow("Web Search") }
                    if item.supportsImage { supportRow("Image Generation") }
                    if item.supportsTools { supportRow("AI Extensions") }
                    if item.thinking { supportRow("MCP") }
                    if item.supportsReasoning { supportRow("Vision") }
                }
                .padding(.leading, 2)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
        )
        .frame(width: 300)
    }
}

private struct ScoreBars: View {
    let score: Int // 0...5
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<5, id: \.self) { i in
                Capsule()
                    .fill(i < max(0, min(5, score)) ? Color.red : Color.gray.opacity(0.25))
                    .frame(width: 24, height: 4)
            }
        }
    }
}

private struct SpecRowLeft<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }
    var body: some View {
        HStack(spacing: 10) {
            Text(title).foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            content()
            Spacer()
        }
        .font(.caption)
    }
}

private func tokenString(_ tokens: Int) -> String {
    if tokens >= 1_000_000 { return "\(tokens/1_000_000)M tokens" }
    if tokens >= 1_000 { return "\(tokens/1_000)k tokens" }
    return "\(tokens) tokens"
}

private func wordAndPageHint(_ tokens: Int) -> String {
    // rough approximations: 1 token ≈ 0.75 words; 1 page ≈ 375 words
    let words = Int(Double(tokens) * 0.75)
    let pages = max(1, words / 375)
    let wordsStr = words >= 1_000_000 ? "\(words/1_000_000)M words" : (words >= 1_000 ? "\(words/1_000)k words" : "\(words) words")
    let pagesStr = pages >= 1000 ? "\(pages/1000)k pages" : "\(pages) pages"
    return "\(wordsStr) | \(pagesStr)"
}

@ViewBuilder private func supportRow(_ text: String) -> some View {
    HStack { Text(text); Spacer(); Image(systemName: "checkmark") }
}
