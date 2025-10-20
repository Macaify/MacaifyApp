import SwiftUI
import BetterAuth
import BetterAuthMagicLink
import AppKit
import Defaults

enum PlanTier: String, Codable, CaseIterable, Identifiable {
    case free = "Free"
    case pro = "Pro"
    case proPlus = "Pro+"
    var id: String { rawValue }
}

struct AccountSettingsView: View {
    @EnvironmentObject private var authClient: BetterAuthClient

    @State private var plan: PlanTier = .free
    @State private var quotaUsed: Double = 0.12 // placeholder

    private var defaultSourceText: String {
        switch Defaults[.defaultSource] {
        case "provider": return String(localized: "默认来源：我的模型实例")
        case "account": return String(localized: "默认来源：账户模型")
        default: return String(localized: "默认来源：账户模型")
        }
    }

    var body: some View {
        Form {
            Section(String(localized: "账户")) {
                HStack(spacing: 10) {
                    PlanBadge(plan: plan)
                    Text(defaultSourceText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let user = authClient.user {
                    LabeledContent(String(localized: "用户名")) { Text(user.name) }
                    LabeledContent(String(localized: "邮箱")) { Text(user.email) }
                } else {
                    Text(String(localized: "未登录，登录以解锁更多模型"))
                        .foregroundStyle(.secondary)
                }
            }

            Section(String(localized: "用量")) {
                LabeledContent(String(localized: "本周期消息")) {
                    VStack(alignment: .leading) {
                        ProgressView(value: quotaUsed)
                        Text("\(Int(quotaUsed * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: 240)
                }
            }

            Section(String(localized: "操作")) {
                HStack {
                    if authClient.session != nil {
                        Button(String(localized: "退出登录")) {
                            Task { try await authClient.signOut() }
                        }
                    } else {
                        Button(String(localized: "登录")) {
                            Task { try? await authClient.signIn.magicLink(with: .init(email: "user@example.com")) }
                        }
                    }
                    Button(String(localized: "管理订阅")) {
                        if let url = URL(string: "https://macaify.com/pricing") { NSWorkspace.shared.open(url) }
                    }
                }
            }

            Section(String(localized: "你的计划")) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(String(localized: "更快响应"), systemImage: "bolt.fill")
                    Label(String(localized: "更大上下文"), systemImage: "text.append")
                    Label(String(localized: "视觉与推理"), systemImage: "eye")
                }
                .foregroundStyle(.secondary)
                Button(String(localized: "升级")) {
                    if let url = URL(string: "https://macaify.com/pricing") { NSWorkspace.shared.open(url) }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .formStyle(.grouped)
    }
}

struct PlanBadge: View {
    let plan: PlanTier
    var body: some View {
        Text(plan.rawValue)
            .font(.caption).bold()
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(
                Capsule().fill(color)
            )
            .foregroundColor(.white)
    }
    private var color: Color {
        switch plan { case .free: return .gray; case .pro: return .blue; case .proPlus: return .purple }
    }
}
