import SwiftUI
import BetterAuth
import BetterAuthBrowserOTT
import BetterAuthMembership
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
    private let authRedirectURI: String = "macaify://ott"

    private var currentPlan: PlanTier {
        if let t = authClient.session.data?.user.membership?.type ?? authClient.session.data?.user.membershipType {
            switch t.lowercased() {
            case "pro+", "proplus": return .proPlus
            case "pro": return .pro
            default: return .free
            }
        }
        return .free
    }

    private var defaultSourceText: String {
        switch Defaults[.defaultSource] {
        case "provider": return String(localized: "默认来源：我的模型实例")
        case "account": return String(localized: "默认来源：账户模型")
        default: return String(localized: "默认来源：账户模型")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsTokens.spacing) {
            accountCard

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "本周期消息"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack {
                        ProgressView(value: quotaUsed)
                            .frame(maxWidth: 260)
                        Spacer()
                        Text("\(Int(quotaUsed * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } label: {
                Label(String(localized: "用量"), systemImage: "chart.bar.fill")
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Label(String(localized: "更快响应"), systemImage: "bolt.fill")
                    Label(String(localized: "更大上下文"), systemImage: "text.append")
                    Label(String(localized: "视觉与推理"), systemImage: "eye")

                    HStack(spacing: 12) {
                        Button(String(localized: "升级")) {
                            if let url = URL(string: "https://macaify.com/pricing") { NSWorkspace.shared.open(url) }
                        }
                        .buttonStyle(.borderedProminent)
                        Button(String(localized: "管理订阅")) {
                            if let url = URL(string: "https://macaify.com/pricing") { NSWorkspace.shared.open(url) }
                        }
                    }
                    .padding(.top, 6)
                }
                .foregroundStyle(.secondary)
            } label: {
                Label(String(localized: "你的计划"), systemImage: "rectangle.grid.2x2")
            }
        }
        .groupBoxStyle(CardGroupBoxStyle())
    }

    private var accountCard: some View {
        GroupBox {
            HStack(alignment: .center, spacing: 16) {
                avatar
                VStack(alignment: .leading, spacing: 6) {
                    if let user = authClient.session.data?.user {
                        HStack(spacing: 8) {
                            Text(user.name.isEmpty ? user.email : user.name)
                                .font(.headline)
                            PlanBadge(plan: currentPlan)
                        }
                        if !user.email.isEmpty {
                            Text(user.email)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let summary = membershipSummary(user: user) {
                            Text(summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(defaultSourceText)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    } else {
                        Text(String(localized: "未登录"))
                            .font(.headline)
                        Text(String(localized: "登录以解锁更多模型与权益"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if authClient.session.data?.user != nil {
                    Button(String(localized: "退出登录")) {
                        Task {
                            do { _ = try await authClient.signOut() } catch {}
                            await authClient.session.refreshSession()
                        }
                    }
                } else {
                    Button(String(localized: "登录")) {
                        Task {
                            do {
                                _ = try await authClient.browserOTT.signIn(with: .init(
                                    redirect_uri: authRedirectURI,
                                    state: nil
                                ))
                            } catch {}
                            await authClient.session.refreshSession()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        } label: {
            Label(String(localized: "账户"), systemImage: "person.fill")
        }
    }

    private var avatar: some View {
        Group {
            if let urlString = authClient.session.data?.user.image,
               let url = URL(string: urlString) {
                if #available(macOS 12.0, *) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image): image.resizable().scaledToFill()
                        default: Image(systemName: "person.crop.circle.fill").resizable().scaledToFill()
                        }
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                } else {
                    Image(systemName: "person.crop.circle.fill").resizable().frame(width: 44, height: 44)
                }
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .frame(width: 44, height: 44)
            }
        }
    }

    private func membershipSummary(user: SessionUser) -> String? {
        let type = user.membership?.type ?? user.membershipType
        let trial = user.membership?.trialActive == true
        let next = user.membership?.nextBillingAt
        let end = user.membership?.endAt
        var parts: [String] = []
        if let type { parts.append(String(localized: "会员：\(type)")) } else { parts.append(String(localized: "会员：Free")) }
        if trial, let trialEnds = user.membership?.trialEndsAt {
            parts.append(String(localized: "试用至 \(trialEnds.formatted(date: .abbreviated, time: .omitted))"))
        } else if let next {
            parts.append(String(localized: "下次扣款 \(next.formatted(date: .abbreviated, time: .omitted))"))
        } else if let end {
            parts.append(String(localized: "到期 \(end.formatted(date: .abbreviated, time: .omitted))"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
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
