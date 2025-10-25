import SwiftUI
import Defaults

#if os(macOS)
import BetterAuth
import BetterAuthBrowserOTT
#endif

/// Minimal unified model picker content showing both custom instances and remote models.
/// - Supports multi-context selection via injected handlers; defaults to global selection.
/// - Uses gating badges: 登录 / 升级
/// - Hover on remote items shows AnchoredPopover with ModelDetailCard (prefer right side)
struct QuickModelPickerView: View {
    @ObservedObject private var store = ProviderStore.shared
    @ObservedObject private var manager = ModelSelectionManager.shared
    #if os(macOS)
    @EnvironmentObject private var authClient: BetterAuthClient
    #endif
    
    /// 选择完成后的回调，用于关闭弹窗
    var onDismiss: (() -> Void)? = nil
    /// 外部触发的重置键：当值变化时，清空本地状态并将列表滚动到顶部
    var resetKey: Int = 0
    /// 注入：判断是否为“当前已选中”（用于高亮）。未注入时走全局 Defaults。
    var isInstanceSelected: (CustomModelInstance) -> Bool = { p in
        Defaults[.defaultSource] == "provider" && Defaults[.selectedProviderInstanceId] == p.id
    }
    var isAccountSelected: (String, String) -> Bool = { provider, modelId in
        Defaults[.defaultSource] == "account" && Defaults[.selectedProvider] == provider && Defaults[.selectedModelId] == modelId
    }
    /// 注入：执行选择行为（用于会话级选择等）。未注入时写入全局 Defaults。
    var onPickInstance: ((CustomModelInstance) -> Void)? = nil
    var onPickRemote: ((RemoteModelItem) -> Void)? = nil

    @State private var hoverItemId: String? = nil
    @State private var anchorView: NSView? = nil  // 用于固定二级弹窗位置
    @State private var showUpgrade: Bool = false
    @State private var pendingPlan: MembershipPlan = .pro

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // 主内容
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // 顶部锚点：用于重置时滚动到顶部
                        Color.clear.frame(height: 0).id("top")
                    // Custom instances
                    ForEach(store.providers) { inst in
                        ProviderInstanceRow(
                            inst: inst,
                            isSelected: isInstanceSelected(inst),
                            onTap: {
                                // 立即清除 hover 状态，避免干扰弹窗关闭
                                hoverItemId = nil
                                // 使用 Task 异步执行，避免 "Modifying state during view update"
                                Task { @MainActor in
                                    select(instance: inst)
                                }
                            },
                            onHoverChange: { inside in
                                // hover custom 模型时关闭二级弹窗
                                if inside { hoverItemId = nil }
                            }
                        )
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
                            onTap: {
                                // 立即清除 hover 状态，避免干扰弹窗关闭
                                hoverItemId = nil
                                // 使用 Task 异步执行，避免 "Modifying state during view update"
                                Task { @MainActor in
                                    select(remote: item)
                                }
                            }
                        )
                    }
                    }
                    .padding(8)
                }
                // 使用 .id(resetKey) 强制重建 ScrollView，避免出现“回到顶部”的滚动过程
                .id(resetKey)
                .onChange(of: resetKey) { _ in
                    // 重置 hover 状态；滚动位置通过重建视图直接在顶部，无需滚动动画
                    hoverItemId = nil
                }
            }
            .frame(width: 350, height: 600)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.regularMaterial)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .task { await onAppearFetch() }
            .onReceive(NotificationCenter.default.publisher(for: .init("BetterAuthSignedOut"))) { _ in
                #if os(macOS)
                updateMembershipFromAuth()
                Task { await manager.refreshRemote() }
                #endif
            }
            
            // 固定位置的二级弹窗锚点（位于主弹窗右上角）
            #if os(macOS)
            Color.clear
                .frame(width: 1, height: 600)  // 与主弹窗同高，确保顶部对齐
                .background(
                    VStack {
                        Color.clear
                            .frame(width: 1, height: 1)
                            .background(AnchorResolver(onResolve: { view in anchorView = view }))
                        Spacer()
                    }
                )
                // 二级弹窗（hover 显示模型详情）暂时禁用，等待 ESC 关闭问题修复
                // TODO: 重新启用 AnchoredPopover 以恢复二级弹窗
                #if false
                .background(
                    Group {
                        if anchorView != nil {
                            AnchoredPopover(
                                isPresented: Binding(
                                    get: { hoverItemId != nil },
                                    set: { newVal in if !newVal { hoverItemId = nil } }
                                ),
                                preferredDirection: .trailing,
                                dismissOnOutsideClick: false,
                                dismissOnESC: false,  // 不响应 ESC，让主弹窗处理
                                level: .statusBar,
                                canBecomeKey: false
                            ) {
                                if let itemId = hoverItemId,
                                   let item = findItem(byId: itemId) {
                                    ModelDetailCard(item: item)
                                }
                            }
                        }
                    }
                )
                #endif
            #endif
        }
    }
    
    // 根据 ID 查找模型项
    private func findItem(byId id: String) -> RemoteModelItem? {
        let allItems: [RemoteModelItem] = manager.providers.flatMap { manager.modelsByProvider[$0] ?? [] }
        return allItems.first(where: { $0.id == id })
    }

    private func select(instance p: CustomModelInstance) {
        if let onPickInstance {
            onPickInstance(p)
        } else {
            Defaults[.selectedModelId] = p.modelId
            Defaults[.selectedProvider] = p.provider
            Defaults[.proxyAddress] = p.baseURL
            Defaults[.selectedProviderInstanceId] = p.id
            Defaults[.defaultSource] = "provider"
        }
        onDismiss?()
    }

    private func select(remote item: RemoteModelItem) {
        switch item.gate {
        case .available:
            if let onPickRemote {
                onPickRemote(item)
            } else {
                manager.select(remote: item, onLogin: {}, onUpgrade: { _ in })
            }
            onDismiss?()
        case .loginRequired:
            #if os(macOS)
            Task {
                do { _ = try await authClient.browserOTT.signIn(with: .init(redirect_uri: "macaify://ott")) } catch {}
                await authClient.session.refreshSession()
                // 登录完成后，先更新会员注入，再刷新远端模型，确保权益状态即时更新
                await MainActor.run { updateMembershipFromAuth() }
                await manager.refreshRemote()
            }
            #endif
        case .upgradeRequired(let plan):
            #if os(macOS)
            // 在面板/弹窗场景，使用全局 UpgradePanelBridge，并优先附着到“触发按钮所在的父窗口”（而非 Popover 本身）
            // anchorView?.window 指向的是当前 Popover 的 NSPanel；其 parent 才是触发按钮所在的窗口
            let hostWindow = anchorView?.window?.parent ?? anchorView?.window
            UpgradePanelBridge.shared.present(requiredPlan: plan, parentWindow: hostWindow)
            #else
            pendingPlan = plan
            showUpgrade = true
            #endif
        }
    }

    private func onAppearFetch() async {
        #if os(macOS)
        updateMembershipFromAuth()
        #endif
        if manager.providers.isEmpty && !manager.isFetching {
            await manager.refreshRemote()
        }
    }

    #if os(macOS)
    private func updateMembershipFromAuth() {
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
    }
    #endif
}

#if os(macOS)
import AppKit

// 用于获取 NSView 引用的辅助组件
private struct AnchorResolver: NSViewRepresentable {
    var onResolve: (NSView) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { onResolve(v) }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) { }
}
#endif

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
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .background(isHovering ? Color.gray.opacity(0.08) : Color.clear)
        .contentShape(.rect)
        .containerShape(.rect)
        .onHover { inside in onHover(inside) }
    }
}
