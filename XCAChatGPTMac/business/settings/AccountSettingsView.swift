import SwiftUI
import BetterAuth
import BetterAuthBrowserOTT
import BetterAuthMembership
import AppKit
import AppUpdater
import Defaults

enum PlanTier: String, Codable, CaseIterable, Identifiable {
    case free = "Free"
    case pro = "Pro"
    case proPlus = "Pro+"
    var id: String { rawValue }
}

struct AccountSettingsView: View {
    @EnvironmentObject private var authClient: BetterAuthClient
    @Default(.launchAtLogin) private var launchAtLogin

    @State private var plan: PlanTier = .free
    @State private var quotaUsed: Double = 0.12 // placeholder
    private let authRedirectURI: String = "macaify://ott"
    @State private var showUpdateSettings: Bool = false

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
        Form {
            Section { accountCard }
            Section(String(localized: "通用")) {
                Toggle(String(localized: "开机启动"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { LaunchAtLoginManager.set(enabled: $0) }
                AppShortcuts()
            }
            Form {
                HStack {
                    Spacer()
                    if #available(macOS 13.0, *) {
                        AppUpdaterLink(onOpenSettings: { showUpdateSettings = true })
                            .environmentObject(AppUpdaterHelper.shared.updater)
                    } else {
                        AppUpdaterLink()
                            .environmentObject(AppUpdaterHelper.shared.updater)
                    }
                }
            }.formStyle(.columns)
        }
        .formStyle(.grouped)
        .onAppear {
            if launchAtLogin != LaunchAtLoginManager.isEnabled { launchAtLogin = LaunchAtLoginManager.isEnabled }
            // Auto-check updates whenever opening this settings page
            AppUpdaterHelper.shared.updater.check()
        }
        .sheet(isPresented: $showUpdateSettings) {
            if #available(macOS 13.0, *) {
                AppUpdateSettings()
                    .environmentObject(AppUpdaterHelper.shared.updater)
                    .frame(minWidth: 560, minHeight: 480)
            } else {
                EmptyView()
            }
        }
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                            // 尝试通知后端登出，但无论成功与否，都清除本地令牌并刷新会话
                            do { _ = try await authClient.signOut() } catch {}
                            await TokenAuth.shared.clear()
                            await authClient.session.refreshSession()
                            // 触发全局通知，让其他窗口的 BetterAuthClient 也刷新
                            NotificationCenter.default.post(name: .init("BetterAuthSignedOut"), object: nil)
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
        // "会员：" / "Membership: " prefix + plan name
        let prefix = String(localized: "membership_prefix")
        parts.append(prefix + (type ?? "Free"))
        // Dates
        if trial, let trialEnds = user.membership?.trialEndsAt {
            let ds = trialEnds.formatted(date: .abbreviated, time: .omitted)
            parts.append(String(format: String(localized: "trial_until"), ds))
        } else if let next {
            let ds = next.formatted(date: .abbreviated, time: .omitted)
            parts.append(String(format: String(localized: "next_charge"), ds))
        } else if let end {
            let ds = end.formatted(date: .abbreviated, time: .omitted)
            parts.append(String(format: String(localized: "expires_on"), ds))
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
