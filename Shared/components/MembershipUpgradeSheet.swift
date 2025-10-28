import SwiftUI
import AppKit

struct MembershipUpgradeSheet: View {
    @Environment(\.dismiss) private var dismiss
    var requiredPlan: MembershipPlan
    // When presented outside of SwiftUI .sheet (e.g., inside NSPanel), provide a manual close handler.
    var onClose: (() -> Void)? = nil
    var includedModelsURL: URL? = URL(string: "https://macaify.com/#pricing")
    var upgradeURL: URL? = URL(string: "https://macaify.com/#pricing")

    var body: some View {
        VStack(spacing: 0) {
            // Hero card
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(LinearGradient(colors: [.pink.opacity(0.14), .red.opacity(0.10)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(height: 150)
                HStack(spacing: 18) {
                    Symbol("sparkles")
                    Symbol("brain.head.profile")
                    Symbol("bolt.horizontal.circle.fill")
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            VStack(alignment: .center, spacing: 10) {
                Text("Advanced AI Models").font(.title3).bold()
                Text("Access the most powerful models from OpenAI, Perplexity, Anthropic, and more from $4/month.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 6) {
                    Text("Which models are included?").font(.caption)
                        .foregroundStyle(.secondary)
                    if let url = includedModelsURL {
                        Button(action: { NSWorkspace.shared.open(url) }) {
                            Image(systemName: "info.circle").font(.caption)
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack(spacing: 12) {
                    if let url = upgradeURL {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            HStack(spacing: 6) {
                                Text("Upgrade to \(requiredPlan == .proPlus ? "Pro + Advanced AI" : requiredPlan.rawValue)")
                                Image(systemName: "arrow.up.right")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Button("Not now") {
                        if let onClose { onClose() } else { dismiss() }
                    }
                        .buttonStyle(.bordered)
                }
                .padding(.top, 6)
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 20)
        }
        .frame(width: 420)
        .padding(.bottom, 12)
    }

    private func Symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 42, weight: .semibold))
            .foregroundStyle(.pink)
            .shadow(color: .white.opacity(0.6), radius: 0.5, x: 0, y: 1)
    }
}
