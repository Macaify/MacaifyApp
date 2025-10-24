import SwiftUI
import Defaults

#if os(macOS)
import BetterAuth
import BetterAuthBrowserOTT
#endif

/// Minimal unified model picker content showing both custom instances and remote models.
/// - Uses gating badges: 登录 / 升级
/// - Hover on remote items shows AnchoredPopover with ModelDetailCard (prefer right side)
struct QuickModelPickerView: View {
    @ObservedObject private var store = ProviderStore.shared
    @ObservedObject private var manager = ModelSelectionManager.shared
    #if os(macOS)
    @EnvironmentObject private var authClient: BetterAuthClient
    #endif

    @State private var hoverItemId: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Custom instances
                ForEach(store.providers) { inst in
                    ProviderInstanceRow(inst: inst, isSelected: isInstanceSelected(inst)) {
                        select(instance: inst)
                    }
                }

                // Remote models (flattened)
                if manager.isFetching && manager.providers.isEmpty {
                    HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }
                        .padding(.vertical, 12)
                }
                if let msg = manager.errorMessage, manager.providers.isEmpty {
                    Text(msg).foregroundStyle(.secondary).padding(.vertical, 8)
                }
                let allItems: [RemoteModelItem] = manager.providers.flatMap { manager.modelsByProvider[$0] ?? [] }
                ForEach(allItems) { item in
                    QuickRemoteRow(
                        item: item,
                        isSelected: isAccountSelected(item.provider, item.slug),
                        isHovering: hoverItemId == item.id,
                        onHover: { inside in hoverItemId = inside ? item.id : (hoverItemId == item.id ? nil : hoverItemId) },
                        onTap: { select(remote: item) }
                    )
                    .background(
                        AnchoredPopover(
                            isPresented: Binding(
                                get: { hoverItemId == item.id },
                                set: { newVal in if !newVal && hoverItemId == item.id { hoverItemId = nil } }
                            ),
                            preferredDirection: .trailing
                        ) {
                            ModelDetailCard(item: item)
                        }
                    )
                }
            }
            .padding(8)
        }
        .frame(width: 350, height: 600)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task { await onAppearFetch() }
    }

    private func isInstanceSelected(_ inst: CustomModelInstance) -> Bool {
        Defaults[.defaultSource] == "provider" && Defaults[.selectedProviderInstanceId] == inst.id
    }
    private func isAccountSelected(_ provider: String, _ modelId: String) -> Bool {
        Defaults[.defaultSource] == "account" && Defaults[.selectedProvider] == provider && Defaults[.selectedModelId] == modelId
    }

    private func select(instance p: CustomModelInstance) {
        Defaults[.selectedModelId] = p.modelId
        Defaults[.selectedProvider] = p.provider
        Defaults[.proxyAddress] = p.baseURL
        Defaults[.selectedProviderInstanceId] = p.id
        Defaults[.defaultSource] = "provider"
    }

    private func select(remote item: RemoteModelItem) {
        switch item.gate {
        case .available:
            manager.select(remote: item, onLogin: {}, onUpgrade: { _ in })
        case .loginRequired:
            #if os(macOS)
            Task {
                do { _ = try await authClient.browserOTT.signIn(with: .init(redirect_uri: "macaify://ott")) } catch {}
                await authClient.session.refreshSession()
                await manager.refreshRemote()
            }
            #endif
        case .upgradeRequired:
            // Minimal: just surface the badge; a full upgrade panel is out-of-scope for minimal picker
            break
        }
    }

    private func onAppearFetch() async {
        #if os(macOS)
        // Inject membership state from auth
        let loggedIn = authClient.session.data?.user != nil
        let planStr = authClient.session.data?.user.membership?.type ?? authClient.session.data?.user.membershipType
        let plan: MembershipPlan? = {
            guard let t = planStr?.lowercased() else { return nil }
            if t == "pro+" || t == "proplus" { return .proPlus }
            if t == "pro" { return .pro }
            return .free
        }()
        struct Injected: MembershipProvider { let isLoggedIn: Bool; let currentPlan: MembershipPlan? }
        manager.membership = Injected(isLoggedIn: loggedIn, currentPlan: plan)
        #endif
        if manager.providers.isEmpty && !manager.isFetching {
            await manager.refreshRemote()
        }
    }
}

// MARK: - Remote row (minimal style matching ModelPickerPopover)
private struct QuickRemoteRow: View {
    let item: RemoteModelItem
    let isSelected: Bool
    let isHovering: Bool
    var onHover: (Bool) -> Void
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                ProviderIconView(provider: item.provider)
                Text(item.name)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                switch item.gate {
                case .available:
                    if isSelected { Image(systemName: "checkmark").foregroundStyle(.secondary) }
                case .loginRequired:
                    GateBadge(text: String(localized: "登录"), tint: .gray)
                case .upgradeRequired:
                    GateBadge(text: String(localized: "升级"), tint: .pink)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isHovering ? Color.gray.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
        .onHover { inside in onHover(inside) }
    }
}

