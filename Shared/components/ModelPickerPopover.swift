import SwiftUI
import Defaults
#if canImport(MacaifyServiceKit)
import MacaifyServiceKit
#endif
#if os(macOS)
import AppKit
import BetterAuth
import BetterAuthBrowserOTT
#endif

// 统一的模型选择 Popover：顶部为“我的自定义”，其后为“全部模型（按 provider 分组）”。
struct ModelPickerPopover: View {
    @ObservedObject private var manager = ModelSelectionManager.shared
    @ObservedObject private var store = ProviderStore.shared
    #if os(macOS)
    @EnvironmentObject private var authClient: BetterAuthClient
    #endif

    @State private var showUpgrade: Bool = false
    @State private var pendingPlan: MembershipPlan = .pro
    // Hover behavior: debounce show/hide to avoid flicker while scrolling
    @State private var hoverCandidate: RemoteModelItem? = nil
    @State private var showHoverItem: RemoteModelItem? = nil
    @State private var hoverShowTask: Task<Void, Never>? = nil
    @State private var hoverHideTask: Task<Void, Never>? = nil
    private let authRedirectURI: String = "macaify://ott"
    // Use an NSPopover via NSViewRepresentable; avoids covering list and improves perf

    // Whether to show floating hover detail panel (macOS only). Default true for top toolbar usage.
    var showHoverDetail: Bool = true
    // Selection customization for reuse across contexts
    var isInstanceSelected: (CustomModelInstance) -> Bool = { p in
        Defaults[.defaultSource] == "provider" && Defaults[.selectedProviderInstanceId] == p.id
    }
    var isAccountSelected: (String, String) -> Bool = { provider, modelId in
        Defaults[.defaultSource] == "account" && Defaults[.selectedProvider] == provider && Defaults[.selectedModelId] == modelId
    }
    var onPickInstance: ((CustomModelInstance) -> Void)? = nil
    var onPickRemote: ((RemoteModelItem) -> Void)? = nil
    // Provide a parent window for detail panel pinning; defaults to picker panel window
    var parentWindowProvider: () -> NSWindow? = { ModelPickerPanelBridge.shared.panelWindow() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                combinedList
            }
            .padding(8)
        }
        .frame(width: 320, height: 440)
        .background(
            // Subtle material and shadow for better readability/perceived performance
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 6)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task {
            updateMembershipFromAuth()
            if manager.providers.isEmpty && !manager.isFetching {
                await manager.refreshRemote()
            }
        }
        .onDisappear { hoverShowTask?.cancel(); hoverHideTask?.cancel(); hoverCandidate = nil; showHoverItem = nil }
        #if os(macOS)
        // On macOS, present upgrade via a dedicated NSPanel to avoid the popover overlay issue.
        #else
        .sheet(isPresented: $showUpgrade) { MembershipUpgradeSheet(requiredPlan: pendingPlan) }
        #endif
    }

    // MARK: Subviews
    @ViewBuilder
    private var customSection: some View { EmptyView() }

    @ViewBuilder
    private var allModelsSection: some View { EmptyView() }

    @ViewBuilder
    private func providerSection(_ provider: String) -> some View { EmptyView() }

    @ViewBuilder
    private var combinedList: some View {
        // 1) 我的实例（样式与远端一致，仅保留 图标 + 名称 + 状态）
        ForEach(store.providers) { inst in
            CustomInstanceRow(
                inst: inst,
                isSelected: isInstanceSelected(inst),
                onTap: { select(instance: inst) }
            )
        }

        // 2) 远端模型：扁平化展示（不再按 provider 分段/标题）
        if manager.isFetching && manager.providers.isEmpty {
            HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }
                .padding(.vertical, 12)
        }
        if let msg = manager.errorMessage, manager.providers.isEmpty {
            Text(msg).foregroundStyle(.secondary).padding(.vertical, 8)
        }
        let allItems: [RemoteModelItem] = manager.providers.flatMap { manager.modelsByProvider[$0] ?? [] }
        ForEach(allItems) { item in
            row(for: item)
        }
    }

    @ViewBuilder
    private func row(for item: RemoteModelItem) -> some View {
        let isHovered = (hoverCandidate == item || showHoverItem == item)
        #if os(macOS)
        if showHoverDetail {
            RowWithAnchor(
                item: item,
                isSelected: isAccountSelected(item.provider, item.slug),
                isHovered: isHovered,
                onHoverChange: { inside in handleHover(inside: inside, item: item) },
                onTap: { select(remote: item) },
                isPresented: Binding(
                    get: { showHoverItem == item },
                    set: { newVal in if !newVal && showHoverItem == item { showHoverItem = nil } }
                ),
                parentWindowProvider: parentWindowProvider
            )
        } else {
            ModelRow(
                item: item,
                isSelected: isAccountSelected(item.provider, item.slug),
                isHovered: isHovered,
                onHoverChange: { inside in handleHover(inside: inside, item: item) },
                onTap: { select(remote: item) }
            )
            .background(
                HoverPopover(isPresented: Binding(
                    get: { showHoverItem == item },
                    set: { newVal in if !newVal && showHoverItem == item { showHoverItem = nil } }
                ), preferredEdge: .maxX) {
                    ModelDetailCard(item: item)
                }
            )
        }
        #else
        ModelRow(
            item: item,
            isSelected: isAccountSelected(item.provider, item.slug),
            isHovered: isHovered,
            onHoverChange: { inside in handleHover(inside: inside, item: item) },
            onTap: { select(remote: item) }
        )
        #endif
    }

    private func handleHover(inside: Bool, item: RemoteModelItem) {
        #if os(macOS)
        if !showHoverDetail {
            // Maintain hover highlight and local hover popover state; don't use floating NSPanel
            if inside {
                hoverHideTask?.cancel()
                hoverCandidate = item
                hoverShowTask?.cancel()
                hoverShowTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 80_000_000)
                    if hoverCandidate == item { showHoverItem = item }
                }
            } else {
                hoverShowTask?.cancel()
                hoverCandidate = nil
                hoverHideTask?.cancel()
                hoverHideTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 120_000_000)
                    if hoverCandidate == nil && showHoverItem == item { showHoverItem = nil }
                }
            }
            return
        }
        #endif
        if inside {
            // 进入：立刻更新 hover 指向，取消隐藏计时器，并短延迟更新内容
            hoverHideTask?.cancel()
            hoverCandidate = item
            hoverShowTask?.cancel()
            hoverShowTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 80_000_000)
                if hoverCandidate == item { showHoverItem = item }
            }
        } else {
            // 离开：立即清除高亮，但给弹窗一个短容错时间，避免在模型之间切换时闪烁
            hoverShowTask?.cancel()
            hoverCandidate = nil
            hoverHideTask?.cancel()
            hoverHideTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 120_000_000)
                if hoverCandidate == nil && showHoverItem == item {
                    showHoverItem = nil
                    #if os(macOS)
                    if showHoverDetail { ModelDetailPanelBridge.shared.close() }
                    #endif
                }
            }
        }
    }

    // MARK: - Selection helpers
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
        #if os(macOS)
        if showHoverDetail {
            // 选择完成后自动关闭弹窗与介绍浮层（仅在面板形态下）
            ModelDetailPanelBridge.shared.close()
            ModelPickerPanelBridge.shared.close()
        }
        #endif
    }
    private func select(remote item: RemoteModelItem) {
        // Respect gating first; then perform custom pick or fallback to global default selection
        switch item.gate {
        case .available:
            if let onPickRemote {
                onPickRemote(item)
            } else {
                manager.select(remote: item, onLogin: {}, onUpgrade: { _ in })
            }
            #if os(macOS)
            if showHoverDetail {
                ModelDetailPanelBridge.shared.close()
                ModelPickerPanelBridge.shared.close()
            }
            #endif
        case .loginRequired:
            #if os(macOS)
            Task {
                do { _ = try await authClient.browserOTT.signIn(with: .init(redirect_uri: authRedirectURI)) } catch {}
                await authClient.session.refreshSession()
                await manager.refreshRemote()
            }
            #else
            // For iOS/tvOS, let the outer sheet drive auth if needed
            #endif
        case .upgradeRequired(let plan):
            pendingPlan = plan
            showUpgrade = true
            #if os(macOS)
            let hostWindow = ModelPickerPanelBridge.shared.panelWindow()?.parent
            ModelDetailPanelBridge.shared.close()
            ModelPickerPanelBridge.shared.close()
            UpgradePanelBridge.shared.present(requiredPlan: plan, parentWindow: hostWindow)
            #endif
        }
        /*
        // Previous behavior (global default selection with membership & login handling)
        manager.select(remote: item, onLogin: {
            #if os(macOS)
            Task {
                do { _ = try await authClient.browserOTT.signIn(with: .init(redirect_uri: authRedirectURI)) } catch {}
                await authClient.session.refreshSession()
                await manager.refreshRemote()
            }
            #endif
        }, onUpgrade: { plan in
            pendingPlan = plan
            showUpgrade = true
            #if os(macOS)
            // Present the upgrade panel attached to the same host window where the picker originated.
            // Capture parent before closing the panel.
            let hostWindow = ModelPickerPanelBridge.shared.panelWindow()?.parent
            ModelDetailPanelBridge.shared.close()
            ModelPickerPanelBridge.shared.close()
            UpgradePanelBridge.shared.present(requiredPlan: plan, parentWindow: hostWindow)
            #endif
        })
        // 若该条目可直接选择，选择后自动关闭弹窗
        if case .available = item.gate {
            #if os(macOS)
            ModelDetailPanelBridge.shared.close()
            ModelPickerPanelBridge.shared.close()
            #endif
        }
        */
    }

    private func updateMembershipFromAuth() {
        #if os(macOS)
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
    }
}

private struct ModelRow: View {
    let item: RemoteModelItem
    let isSelected: Bool
    let isHovered: Bool
    var onHoverChange: (Bool) -> Void
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
        .background(
            // No border/background between items; only subtle hover
            (isHovered ? Color.gray.opacity(0.08) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover(perform: onHoverChange)
    }
}

// 小徽章
struct GateBadge: View {
    let text: String
    var tint: Color = .pink
    var body: some View {
        HStack(spacing: 4) {
            Text(text)
        }
        .font(.caption2)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(tint.opacity(0.12)))
        .overlay(Capsule().stroke(tint.opacity(0.35), lineWidth: 0.8))
        .foregroundStyle(tint)
    }
}

#if os(macOS)
// Wrap row with anchor resolution and floating tooltip show/hide
private struct RowWithAnchor: View {
    let item: RemoteModelItem
    let isSelected: Bool
    let isHovered: Bool
    var onHoverChange: (Bool) -> Void
    var onTap: () -> Void
    @Binding var isPresented: Bool
    var parentWindowProvider: () -> NSWindow?

    @State private var anchorView: NSView? = nil

    var body: some View {
        ModelRow(
            item: item,
            isSelected: isSelected,
            isHovered: isHovered,
            onHoverChange: { inside in
                onHoverChange(inside)
                if inside {
                    ModelDetailPanelBridge.shared.scheduleShow(item: item, parent: parentWindowProvider())
                }
            },
            onTap: onTap
        )
        .background(RowAnchorResolver(onResolve: { _ in }))
        .onChange(of: isPresented) { present in
            if present { ModelDetailPanelBridge.shared.showNow(parent: parentWindowProvider(), item: item) }
        }
    }
}
#endif

// 自定义实例行：与远端模型统一样式（图标 + 名称 + 状态），带 hover 高亮
private struct CustomInstanceRow: View {
    let inst: CustomModelInstance
    let isSelected: Bool
    var onTap: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                ProviderIconView(provider: inst.provider)
                Text(inst.name)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").foregroundStyle(.secondary)
                } else {
                    let hasToken = (ProviderStore.shared.token(for: inst.id) ?? "").isEmpty == false
                    if !hasToken {
                        GateBadge(text: String(localized: "未配置"), tint: .orange)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(hovered ? Color.gray.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
        .onHover { inside in
            hovered = inside
            #if os(macOS)
            if inside { ModelDetailPanelBridge.shared.close() }
            #endif
        }
    }
}

// 启动器按钮：显示当前选择，点击打开 Popover
struct ModelPickerButton: View {
    @State private var showPopover = false
    var label: String = String(localized: "选择模型")
    #if os(macOS)
    @EnvironmentObject private var authClient: BetterAuthClient
    @State private var anchorView: NSView? = nil
    #endif

    var currentText: String {
        let src = Defaults[.defaultSource]
        if src == "provider" {
            return "\(Defaults[.selectedProvider]) • \(Defaults[.selectedModelId])"
        }
        return "\(Defaults[.selectedProvider]) • \(Defaults[.selectedModelId])"
    }

    var body: some View {
        Button {
            #if os(macOS)
            if let view = anchorView {
                ModelPickerPanelBridge.shared.toggle(relativeTo: view, authClient: authClient)
            } else {
                showPopover.toggle()
            }
            #else
            showPopover.toggle()
            #endif
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.grid.2x2")
                Text(currentText.isEmpty ? label : currentText)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.bordered)
        // Ensure the entire visual rect is clickable/hoverable
        .contentShape(Rectangle())
        #if os(macOS)
        .background(PanelAnchorResolver(onResolve: { view in
            self.anchorView = view
            // 提前预热面板与内容，减少首次点击等待
            if self.anchorView != nil {
                ModelPickerPanelBridge.shared.prewarm(authClient: authClient)
            }
        }))
        #endif
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            ModelPickerPopover()
                .frame(width: 320, height: 440)
        }
    }
}

#if os(macOS)
// MARK: - NSPanel bridge (no animations for appearance/disappearance)
final class ModelPickerPanelBridge: NSObject, NSWindowDelegate {
    static let shared = ModelPickerPanelBridge()
    private var panel: ModelPickerPanel?
    private var host: NSHostingController<AnyView>?
    private weak var parentWindow: NSWindow?
    private weak var anchorViewRef: NSView?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    struct ModelPickerConfig {
        var showHoverDetail: Bool = true
        var isInstanceSelected: (CustomModelInstance) -> Bool
        var isAccountSelected: (String, String) -> Bool
        var onPickInstance: (CustomModelInstance) -> Void
        var onPickRemote: (RemoteModelItem) -> Void
        var parentWindowProvider: () -> NSWindow? = { ModelPickerPanelBridge.shared.panelWindow() }
    }

    func toggle(relativeTo view: NSView, authClient: BetterAuthClient?) {
        if let panel = panel, panel.isVisible {
            close()
        } else {
            show(relativeTo: view, authClient: authClient)
        }
    }
    func toggle(relativeTo view: NSView, authClient: BetterAuthClient?, config: ModelPickerConfig) {
        if let panel = panel, panel.isVisible {
            close()
        } else {
            show(relativeTo: view, authClient: authClient, config: config)
        }
    }

    // 预热：提前创建 NSPanel 和 SwiftUI 内容，减少首次点击卡顿
    func prewarm(authClient: BetterAuthClient?) {
        if panel == nil { createPanel(authClient: authClient) }
    }

    func show(relativeTo view: NSView, authClient: BetterAuthClient?) {
        // If the view is not yet in a window, defer showing until next runloop.
        guard let window = view.window else {
            self.anchorViewRef = view
            DispatchQueue.main.async { [weak self] in
                self?.show(relativeTo: view, authClient: authClient)
            }
            return
        }

        if panel == nil { createPanel(authClient: authClient) }
        guard let panel = panel else { return }

        // Default content (global)
        if let host {
            let root = AnyView(ModelPickerPopover().environmentObjectIfAvailable(authClient))
            host.rootView = root
        }

        // Cache anchors for pinning
        self.anchorViewRef = view
        self.parentWindow = window

        // Determine final frame before making it visible
        let size = NSSize(width: 320, height: 440)
        let rectInWindow = view.convert(view.bounds, to: nil)
        let screenRect = window.convertToScreen(rectInWindow)
        let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let margin: CGFloat = 8
        // Compute available spaces
        let spaceBelow = max(0, screenRect.minY - visible.minY - margin)
        let spaceAbove = max(0, visible.maxY - screenRect.maxY - margin)
        // Choose side with more space (prefer above when near bottom)
        let placeAbove = spaceAbove >= spaceBelow
        var originY: CGFloat
        if placeAbove {
            originY = screenRect.maxY + margin
        } else {
            originY = screenRect.minY - size.height - margin
        }
        // Clamp to visible area
        originY = max(visible.minY + margin, min(visible.maxY - size.height - margin, originY))
        var originX = screenRect.minX
        originX = max(visible.minX + margin, min(visible.maxX - size.width - margin, originX))
        let targetFrame = NSRect(origin: NSPoint(x: originX, y: originY), size: size)
        panel.setContentSize(size)
        panel.setFrame(targetFrame, display: false)

        // Attach and show without any intermediate wrong position
        window.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        installMouseMonitors()
    }

    // Show with a custom-configured content (session-scoped selection etc.)
    func show(relativeTo view: NSView, authClient: BetterAuthClient?, config: ModelPickerConfig) {
        // If the view is not yet in a window, defer showing until next runloop.
        guard let window = view.window else {
            self.anchorViewRef = view
            DispatchQueue.main.async { [weak self] in
                self?.show(relativeTo: view, authClient: authClient, config: config)
            }
            return
        }
        if panel == nil { createPanel(authClient: authClient) }
        guard let panel = panel else { return }
        // Inject configured content
        if let host {
            let root = AnyView(
                ModelPickerPopover(
                    showHoverDetail: config.showHoverDetail,
                    isInstanceSelected: config.isInstanceSelected,
                    isAccountSelected: config.isAccountSelected,
                    onPickInstance: config.onPickInstance,
                    onPickRemote: config.onPickRemote,
                    parentWindowProvider: config.parentWindowProvider
                ).environmentObjectIfAvailable(authClient)
            )
            host.rootView = root
        }

        // Cache anchors for pinning
        self.anchorViewRef = view
        self.parentWindow = window

        // Determine final frame before making it visible
        let size = NSSize(width: 320, height: 440)
        let rectInWindow = view.convert(view.bounds, to: nil)
        let screenRect = window.convertToScreen(rectInWindow)
        let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let margin: CGFloat = 8
        let spaceBelow = max(0, screenRect.minY - visible.minY - margin)
        let spaceAbove = max(0, visible.maxY - screenRect.maxY - margin)
        let placeAbove = spaceAbove >= spaceBelow
        var originY: CGFloat = placeAbove ? (screenRect.maxY + margin) : (screenRect.minY - size.height - margin)
        originY = max(visible.minY + margin, min(visible.maxY - size.height - margin, originY))
        var originX = screenRect.minX
        originX = max(visible.minX + margin, min(visible.maxX - size.width - margin, originX))
        let targetFrame = NSRect(origin: NSPoint(x: originX, y: originY), size: size)
        panel.setContentSize(size)
        panel.setFrame(targetFrame, display: false)

        // Attach and show without any intermediate wrong position
        window.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        installMouseMonitors()
    }

    func close() {
        if let parent = parentWindow, let panel = panel { parent.removeChildWindow(panel) }
        panel?.orderOut(nil)
        // 关闭细节浮层
        ModelDetailPanelBridge.shared.close()
        removeMouseMonitors()
    }

    private func createPanel(authClient: BetterAuthClient?) {
        let panel = ModelPickerPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 440),
            styleMask: [.nonactivatingPanel, .hudWindow, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        panel.level = .popUpMenu
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.animationBehavior = .none
        panel.delegate = self
        let root = AnyView(ModelPickerPopover().environmentObjectIfAvailable(authClient))
        let host = NSHostingController(rootView: root)
        host.view.wantsLayer = true
        host.view.layer?.cornerRadius = 12

        panel.contentView = host.view
        self.host = host
        self.panel = panel
    }

    func windowDidResignKey(_ notification: Notification) { close() }
    func windowDidMove(_ notification: Notification) { applyPinnedFrame(size: panel?.frame.size ?? NSSize(width: 320, height: 440)) }

    private func applyPinnedFrame(size: NSSize) {
        guard let panel = panel, let anchor = anchorViewRef, let window = anchor.window else { return }
        let rectInWindow = anchor.convert(anchor.bounds, to: nil)
        var screenRect = window.convertToScreen(rectInWindow)
        screenRect.origin.y -= (size.height + 8)
        let frame = NSRect(origin: NSPoint(x: screenRect.minX, y: screenRect.minY), size: size)
        if panel.frame != frame { panel.setFrame(frame, display: false) }
    }

    // 暴露主面板 window，供详情浮层定位
    func panelWindow() -> NSWindow? { panel }

    // MARK: - Fast outside-click dismissal (let background receive the click)
    private func installMouseMonitors() {
        removeMouseMonitors()
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] e in
            guard let self, let panel = self.panel else { return e }
            let pt = NSEvent.mouseLocation
            if !panel.frame.contains(pt) { self.close() }
            return e
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            guard let self, let panel = self.panel else { return }
            let pt = NSEvent.mouseLocation
            if !panel.frame.contains(pt) { self.close() }
        }
    }
    private func removeMouseMonitors() {
        if let m = localMouseMonitor { NSEvent.removeMonitor(m); localMouseMonitor = nil }
        if let m = globalMouseMonitor { NSEvent.removeMonitor(m); globalMouseMonitor = nil }
    }
}

final class ModelPickerPanel: NSPanel { override var canBecomeKey: Bool { true } }

private struct PanelAnchorResolver: NSViewRepresentable {
    var onResolve: (NSView) -> Void
    func makeNSView(context: Context) -> NSView { let v = NSView(); DispatchQueue.main.async { onResolve(v) }; return v }
    func updateNSView(_ nsView: NSView, context: Context) { }
}

// Resolve an NSView for each row (hover anchor)
private struct RowAnchorResolver: NSViewRepresentable {
    var onResolve: (NSView) -> Void
    func makeNSView(context: Context) -> NSView { let v = NSView(); DispatchQueue.main.async { onResolve(v) }; return v }
    func updateNSView(_ nsView: NSView, context: Context) { }
}

// Floating model detail panel (non-activating, pinned to row)
final class ModelDetailPanelBridge: NSObject {
    static let shared = ModelDetailPanelBridge()
    private var panel: ModelTooltipPanel?
    private var host: NSHostingController<AnyView>?
    private var currentItemId: String?
    private var scheduledWork: DispatchWorkItem?

    // 新：基于主面板固定定位（不再随行移动）
    func scheduleShow(item: RemoteModelItem, parent: NSWindow?) {
        scheduledWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.showNow(parent: parent, item: item) }
        scheduledWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    func showNow(parent: NSWindow?, item: RemoteModelItem) {
        guard let parent = parent ?? ModelPickerPanelBridge.shared.panelWindow() else { return }
        if panel == nil { createPanel() }
        guard let panel, let host else { return }

        currentItemId = item.id
        host.rootView = AnyView(ModelDetailCard(item: item))
        host.view.layoutSubtreeIfNeeded()
        var size = host.view.fittingSize
        size.width = max(280, min(320, size.width))
        panel.setContentSize(size)

        // 固定与主面板顶部对齐；优先右侧，不够再到左侧
        let parentFrame = parent.frame
        let visible = parent.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        var originX = parentFrame.maxX + 8
        if originX + size.width > visible.maxX - 8 {
            originX = max(visible.minX + 8, parentFrame.minX - size.width - 8)
        }
        var originY = parentFrame.maxY - size.height // 顶部齐平
        if originY < visible.minY + 8 { originY = visible.minY + 8 }
        if originY + size.height > visible.maxY - 8 { originY = visible.maxY - size.height - 8 }
        let frame = NSRect(origin: NSPoint(x: originX, y: originY), size: size)
        panel.setFrame(frame, display: false)

        if panel.parent != parent { parent.addChildWindow(panel, ordered: .above) }
        panel.orderFront(nil)
    }

    func hideIfFor(itemId: String) {
        if currentItemId == itemId { close() }
    }

    func close() {
        scheduledWork?.cancel(); scheduledWork = nil
        guard let p = panel else { return }
        p.orderOut(nil)
        if let parent = p.parent { parent.removeChildWindow(p) }
        currentItemId = nil
    }

    private func createPanel() {
        let p = ModelTooltipPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 240),
            styleMask: [.nonactivatingPanel, .hudWindow, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        p.level = .statusBar
        p.hasShadow = true
        p.isOpaque = false
        p.backgroundColor = .clear
        p.ignoresMouseEvents = true
        p.animationBehavior = .none
        let host = NSHostingController(rootView: AnyView(EmptyView()))
        p.contentView = host.view
        self.host = host
        self.panel = p
    }
}

final class ModelTooltipPanel: NSPanel {
    override var canBecomeKey: Bool { false }
}

// MARK: - Upgrade panel bridge (present MembershipUpgradeSheet above all windows)
final class UpgradePanelBridge: NSObject {
    static let shared = UpgradePanelBridge()
    private var panel: NSPanel?
    private var host: NSHostingController<AnyView>?

    func present(requiredPlan: MembershipPlan, parentWindow: NSWindow? = nil) {
        if panel == nil { createPanel() }
        guard let panel, let host = host else { return }
        // Inject a manual close handler since we're not using SwiftUI .sheet here.
        host.rootView = AnyView(MembershipUpgradeSheet(requiredPlan: requiredPlan, onClose: { [weak self] in self?.close() }))
        host.view.layoutSubtreeIfNeeded()
        var size = host.view.fittingSize
        size.width = max(420, size.width)
        panel.setContentSize(size)

        // Prefer the provided host; otherwise use current key window; finally fallback to main window/screen.
        if let win = parentWindow ?? NSApp.keyWindow ?? NSApp.mainWindow ?? WindowBridge.shared.mainWindow {
            if panel.parent != win { win.addChildWindow(panel, ordered: .above) }
            let frame = win.frame
            let origin = NSPoint(x: frame.midX - size.width/2, y: frame.midY - size.height/2)
            panel.setFrame(NSRect(origin: origin, size: size), display: false)
        } else if let screen = NSScreen.main?.visibleFrame {
            let origin = NSPoint(x: screen.midX - size.width/2, y: screen.midY - size.height/2)
            panel.setFrame(NSRect(origin: origin, size: size), display: false)
        }
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    func close() {
        guard let p = panel else { return }
        p.orderOut(nil)
        if let parent = p.parent { parent.removeChildWindow(p) }
    }

    private func createPanel() {
        let p = UpgradeDialogPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 320),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        p.level = .modalPanel
        p.hasShadow = true
        p.isOpaque = false
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.moveToActiveSpace]
        p.animationBehavior = .none
        let host = NSHostingController(rootView: AnyView(EmptyView()))
        p.contentView = host.view
        self.host = host
        self.panel = p
    }
}

final class UpgradeDialogPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

// Conditionally inject BetterAuthClient when available
private extension View {
    func environmentObjectIfAvailable(_ client: BetterAuthClient?) -> AnyView {
        if let client {
            return AnyView(self.environmentObject(client))
        } else {
            return AnyView(self)
        }
    }
}
#endif
