import SwiftUI
import Defaults
import BetterAuth
import BetterAuthBrowserOTT

// Represents a concrete, callable model instance supplied by the user.
// Token is stored in Keychain keyed by `id`.
struct CustomModelInstance: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString
    var name: String                 // Display name
    var modelId: String              // e.g., gpt-4o-mini, claude-3-haiku
    var baseURL: String              // API host; empty for default provider
    var provider: String             // openai | anthropic | compatible
    var contextLength: Int? = nil    // Optional override
}

final class ProviderStore: ObservableObject {
    static let shared = ProviderStore()
    @Published var providers: [CustomModelInstance] = [] {
        didSet { persist() }
    }
    private let key = "custom.providers"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let list = try? JSONDecoder().decode([CustomModelInstance].self, from: data) {
            // 数据迁移：将旧的 provider 值（compatible/anthropic）统一为 openai
            var migrated = list
            var changed = false
            for i in 0..<migrated.count {
                let p = migrated[i]
                if p.provider.lowercased() == "compatible" || p.provider.lowercased() == "anthropic" {
                    migrated[i].provider = "openai"
                    changed = true
                }
            }
            providers = migrated
            if changed { persist() }
        }
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(providers) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    // MARK: - Tokens via Keychain
    func setToken(_ token: String, for id: String) {
        KeychainHelper.standard.set(token: token, account: id)
    }
    func token(for id: String) -> String? {
        KeychainHelper.standard.get(account: id)
    }
}

struct ProvidersSettingsView: View {
    @StateObject private var store = ProviderStore.shared
    @State private var editing: CustomModelInstance? = nil
    @EnvironmentObject private var authClient: BetterAuthClient
    @StateObject private var modelManager = ModelSelectionManager.shared
    @State private var showUpgrade: Bool = false
    @State private var pendingUpgradePlan: MembershipPlan = .pro
    private let authRedirectURI: String = "macaify://ott"
    @State private var showDefaultPicker: Bool = false
    @State private var hoveredCustomId: String? = nil
    @State private var hoveredRemoteId: String? = nil
    @State private var defaultPickerResetKey: Int = 0
    @State private var templatePickerResetKey: Int = 0
    @State private var showTemplatePicker: Bool = false

    // Observe global defaults for live label update
    @Default(.selectedModelId) private var selectedModelId
    @Default(.selectedProvider) private var selectedProvider
    @Default(.selectedProviderInstanceId) private var selectedProviderInstanceId
    @Default(.defaultSource) private var defaultSource

    var body: some View {
        Form {
            Section {
                HStack {
                    Text(String(localized: "默认模型"))
                    Spacer()
                    Button {
                        showDefaultPicker.toggle()
                    } label: {
                        HStack(spacing: 8) {
                            Text(defaultPickerLabel)
                            Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.2)))
                    }
                    .buttonStyle(.plain)
                    .background(
                        AnchoredPopover(isPresented: $showDefaultPicker, preferredDirection: .above) {
                            // 使用 QuickModelPickerView，未注入回调时默认写入全局 Defaults
                            QuickModelPickerView(onDismiss: { showDefaultPicker = false }, resetKey: defaultPickerResetKey)
                                .frame(width: 350, height: 600)
                        }
                    )
                    .onChange(of: showDefaultPicker) { open in if open { defaultPickerResetKey &+= 1 } }
                }
            }
            Section {
                ForEach(store.providers) { p in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name)
                            if !p.baseURL.isEmpty {
                                Text(p.baseURL).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                        if isDefault(instance: p) {
                            Text(String(localized: "默认")).font(.caption2).foregroundStyle(.secondary)
                        }
                        let hasToken = (ProviderStore.shared.token(for: p.id) ?? "").isEmpty == false
                        if hoveredCustomId == p.id {
                            Button(String(localized: "设为默认")) { setDefault(instance: p) }
                                .buttonStyle(.borderless)
                                .disabled(!hasToken)
                                .help(hasToken ? "" : String(localized: "请先配置 Token"))
                        }
                        Button(String(localized: "编辑")) { editing = p }
                            .buttonStyle(.borderless)
                        Button(String(localized: "删除")) { remove(p) }
                            .buttonStyle(.borderless)
                    }
                    .onHover { inside in
                        hoveredCustomId = inside ? p.id : (hoveredCustomId == p.id ? nil : hoveredCustomId)
                    }
                }
                    HStack(spacing: 12) {
                        Button(String(localized: "从模型模板添加")) { templatePickerResetKey &+= 1; showTemplatePicker = true }
                        Button(String(localized: "添加自定义模型")) {
                            editing = CustomModelInstance(name: String(localized: "我的模型"), modelId: "", baseURL: "", provider: "openai")
                        }
                    }
            } header: {
                Text(String(localized: "我的模型实例"))
            } footer: {
                Text(String(localized: "你可以创建多个自定义模型实例，它们会出现在‘我的模型’里供选择。Token 将安全存储在钥匙串。"))
                    .foregroundStyle(.secondary)
            }
            Section {
                if modelManager.isFetching && modelManager.providers.isEmpty {
                    ProgressView().controlSize(.small)
                }
                if let msg = modelManager.errorMessage, modelManager.providers.isEmpty {
                    Text(msg).foregroundStyle(.secondary)
                }
                ForEach(modelManager.providers, id: \.self) { provider in
                    Text(provider.capitalized).font(.callout).foregroundStyle(.secondary)
                    ForEach(modelManager.modelsByProvider[provider] ?? []) { item in
                        HStack {
                            Text(item.name)
                            Spacer()
                            // Hover-only default button (placed LEFT to badges to avoid shifting existing content)
                            if hoveredRemoteId == item.id {
                                Button(String(localized: "设为默认")) {
                                    modelManager.select(remote: item, onLogin: {
                                        Task {
                                            do { _ = try await authClient.browserOTT.signIn(with: .init(redirect_uri: authRedirectURI)) } catch {}
                                            await authClient.session.refreshSession()
                                            await modelManager.refreshRemote()
                                        }
                                    }, onUpgrade: { plan in
                                        pendingUpgradePlan = plan
                                        showUpgrade = true
                                    })
                                }
                                .buttonStyle(.borderless)
                                // Add as custom instance (template from remote)
                                Button(String(localized: "添加为实例")) {
                                    let template = CustomModelInstance(
                                        name: item.name,
                                        modelId: item.slug,
                                        baseURL: "",
                                        provider: "openai",
                                        contextLength: item.contextTokens
                                    )
                                    editing = template
                                }
                                .buttonStyle(.borderless)
                            }
                            // Selected marker
                            if isDefaultAccount(provider: item.provider, modelId: item.slug) {
                                Text(String(localized: "默认")).font(.caption2).foregroundStyle(.secondary)
                            }
                            // Gate badge (no extra action button)
                            switch item.gate {
                            case .loginRequired:
                                GateBadge(text: String(localized: "登录"), tint: .gray)
                            case .upgradeRequired:
                                GateBadge(text: String(localized: "升级"), tint: .pink)
                            default: EmptyView()
                            }
                        }
                        .onHover { inside in
                            hoveredRemoteId = inside ? item.id : (hoveredRemoteId == item.id ? nil : hoveredRemoteId)
                        }
                    }
                }
            } header: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "账户模型"))
                    #if DEBUG
                    Text("Base: \(BackendEnvironment.baseURL.absoluteString)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    #endif
                }
            }
        }
        .formStyle(.grouped)
        .task {
            // 将 BetterAuth 状态注入 manager（登录与计划）
            updateMembershipFromAuth()
            await modelManager.refreshRemote()
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("BetterAuthSignedOut"))) { _ in
            updateMembershipFromAuth()
            Task { await modelManager.refreshRemote() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("BetterAuthSessionChanged"))) { _ in
            updateMembershipFromAuth()
            Task { await modelManager.refreshRemote() }
        }
        .sheet(item: $editing) { item in
            ProviderEditorView(provider: item) { updated in
                if let idx = store.providers.firstIndex(where: { $0.id == updated.id }) {
                    store.providers[idx] = updated
                } else {
                    store.providers.append(updated)
                }
                editing = nil
            }
            .frame(width: 460, height: 420)
        }
        .sheet(isPresented: $showTemplatePicker) {
            RemoteModelTemplatePicker(resetKey: templatePickerResetKey) { item in
                let template = CustomModelInstance(
                    name: item.name,
                    modelId: item.slug,
                    baseURL: "",
                    provider: "openai",
                    contextLength: item.contextTokens
                )
                editing = template
                showTemplatePicker = false
            }
            .frame(width: 460, height: 560)
        }
        .sheet(isPresented: $showUpgrade) { MembershipUpgradeSheet(requiredPlan: pendingUpgradePlan) }
    }

    private func select(instance p: CustomModelInstance) {
        Defaults[.selectedModelId] = p.modelId
        Defaults[.selectedProvider] = p.provider
        Defaults[.proxyAddress] = p.baseURL
        Defaults[.selectedProviderInstanceId] = p.id
        Defaults[.defaultSource] = "provider"
    }

    private func setDefault(instance p: CustomModelInstance) { select(instance: p) }
    private func isDefault(instance p: CustomModelInstance) -> Bool {
        Defaults[.defaultSource] == "provider" && Defaults[.selectedProviderInstanceId] == p.id
    }
    private func setDefaultAccount(provider: String, modelId: String, context: Int) {
        Defaults[.selectedModelId] = modelId
        Defaults[.selectedProvider] = provider
        Defaults[.defaultSource] = "account"
        Defaults[.selectedProviderInstanceId] = ""
    }
    private func isDefaultAccount(provider: String, modelId: String) -> Bool {
        Defaults[.defaultSource] == "account" && Defaults[.selectedProvider] == provider && Defaults[.selectedModelId] == modelId
    }

    private func remove(_ p: CustomModelInstance) {
        store.providers.removeAll { $0.id == p.id }
    }

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
        modelManager.membership = Injected(isLoggedIn: loggedIn, currentPlan: plan)
    }

    // Label for default picker button
    private var defaultPickerLabel: String {
        if defaultSource == "provider", let inst = store.providers.first(where: { $0.id == selectedProviderInstanceId }) {
            return inst.name.isEmpty ? inst.modelId : inst.name
        }
        let provider = selectedProvider.isEmpty ? "openai" : selectedProvider
        let model = selectedModelId.isEmpty ? (LLMModelsManager.shared.modelCategories.first?.models.first?.id ?? "gpt-4o-mini") : selectedModelId
        let name = ModelSelectionManager.shared.modelsByProvider[provider]?.first(where: { $0.slug == model })?.name ?? model
        return name
    }
}

struct ProviderEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State var provider: CustomModelInstance
    @State private var token: String = ""
    @State private var testing = false
    @State private var testResult: String? = nil
    var onSave: (CustomModelInstance) -> Void
    let isNew: Bool
    @State private var showTemplateMenu: Bool = false

    init(provider: CustomModelInstance?, onSave: @escaping (CustomModelInstance) -> Void) {
        let seed = provider ?? CustomModelInstance(name: "我的模型", modelId: "", baseURL: "", provider: "openai")
        var fixed = seed
        if fixed.provider != "openai" { fixed.provider = "openai" }
        _provider = State(initialValue: fixed)
        self.onSave = onSave
        self.isNew = (provider == nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "基本信息")) {
                    TextField(String(localized: "显示名"), text: $provider.name)
                    TextField(String(localized: "模型调用名"), text: $provider.modelId)
                    Picker(String(localized: "模型接口格式"), selection: $provider.provider) {
                        Text(String(localized: "OpenAI / 兼容")).tag("openai")
                    }
                }
                Section(String(localized: "连接")) {
                    TextField(String(localized: "Base URL（可选）"), text: $provider.baseURL, prompt: Text(String(localized: "https://your-host.com/v1")))
                    SecureField(String(localized: "API Token"), text: $token)
                    HStack(spacing: 10) {
                        Button(action: { Task { await testConnection() } }) {
                            if testing { ProgressView().controlSize(.small) } else { Text(String(localized: "测试连接")) }
                        }
                        .disabled(testing || provider.modelId.trimmingCharacters(in: .whitespaces).isEmpty)
                        if let res = testResult {
                            Text(res)
                                .font(.caption)
                                .foregroundStyle(res.hasPrefix("✅") ? .green : .red)
                        }
                        Spacer()
                    }
                }
                Section(String(localized: "限制")) {
                    LabeledContent(String(localized: "最大 Token")) {
                        TextField("", value: Binding(get: { provider.contextLength ?? 4096 }, set: { provider.contextLength = $0 }), format: .number)
                            .textFieldStyle(.plain)
                            .frame(width: 120)
                    }
                    .help(String(localized: "支持手动输入"))
                }
            }
            .formStyle(.grouped)
            .navigationTitle(String(localized: isNew ? "新建模型实例" : "编辑模型实例"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "保存")) {
                        onSave(provider)
                        ProviderStore.shared.setToken(token, for: provider.id)
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .onAppear { token = ProviderStore.shared.token(for: provider.id) ?? "" }
    }

    @MainActor
    private func testConnection() async {
        testing = true
        testResult = nil
        defer { testing = false }
        do {
            let maxTk = provider.contextLength ?? 4096
            let api = ChatGPTAPI(apiKey: token, model: provider.modelId, provider: provider.provider, maxToken: maxTk, systemPrompt: "", temperature: 0.2, baseURL: provider.baseURL, withContext: false, useAccountGateway: false)
            let reply = try await api.sendMessage("hi")
            let sample = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            let brief = sample.count > 36 ? String(sample.prefix(36)) + "…" : sample
            testResult = "✅ 连接成功"
        } catch {
            testResult = "❌ 失败：\(error.localizedDescription)"
        }
    }
}

// 仅用于从账户模型中挑选一个模板（不会建立任何关联）
private struct RemoteModelTemplatePicker: View {
    @ObservedObject private var manager = ModelSelectionManager.shared
    #if os(macOS)
    @EnvironmentObject private var authClient: BetterAuthClient
    #endif
    var resetKey: Int = 0
    var onPick: (RemoteModelItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(String(localized: "选择模型模板"))
                    .font(.headline)
                Spacer()
                #if os(macOS)
                if manager.membership.isLoggedIn == false {
                    Button(String(localized: "登录")) {
                        Task {
                            do { _ = try await authClient.browserOTT.signIn(with: .init(redirect_uri: "macaify://ott")) } catch {}
                            await authClient.session.refreshSession()
                            NotificationCenter.default.post(name: .init("BetterAuthSessionChanged"), object: nil)
                            await manager.refreshRemote()
                        }
                    }
                }
                #endif
            }
            .padding(12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    let all = manager.providers.flatMap { manager.modelsByProvider[$0] ?? [] }
                    let recommended = all.filter { $0.recommended == true }
                    let others = all.filter { ($0.recommended ?? false) == false }
                    if !recommended.isEmpty {
                        Text(String(localized: "推荐"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.top, 6)
                            .padding(.bottom, 4)
                        ForEach(recommended) { item in row(item) }
                    }
                    if !others.isEmpty {
                        Text(String(localized: "全部模型"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.top, 10)
                            .padding(.bottom, 4)
                        ForEach(others) { item in row(item) }
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .id(resetKey)
        .task {
            if manager.providers.isEmpty && !manager.isFetching {
                await manager.refreshRemote()
            }
        }
    }

    @ViewBuilder
    private func row(_ item: RemoteModelItem) -> some View {
        Button {
            onPick(item)
        } label: {
            HStack(spacing: 10) {
                ProviderIconView(provider: item.provider)
                Text(item.name)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                if manager.membership.isLoggedIn == false {
                    GateBadge(text: String(localized: "登录"), tint: .gray)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .disabled(manager.membership.isLoggedIn == false)
    }
}
