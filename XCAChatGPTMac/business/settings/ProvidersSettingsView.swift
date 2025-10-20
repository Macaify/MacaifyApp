import SwiftUI
import Defaults

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
            providers = list
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
    @State private var presentEditor = false
    @State private var editing: CustomModelInstance? = nil

    var body: some View {
        Form {
            Section {
                ForEach(store.providers) { p in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name)
                            Text("\(p.provider) • \(p.modelId)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !p.baseURL.isEmpty {
                                Text(p.baseURL).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                        if isDefault(instance: p) {
                            Text(String(localized: "默认")).font(.caption2).foregroundStyle(.secondary)
                        }
                        let hasToken = (ProviderStore.shared.token(for: p.id) ?? "").isEmpty == false
                        Button(String(localized: "设为默认")) { setDefault(instance: p) }
                            .buttonStyle(.borderless)
                            .disabled(!hasToken)
                            .help(hasToken ? "" : String(localized: "请先配置 Token"))
                        Button(String(localized: "编辑")) { editing = p; presentEditor = true }
                            .buttonStyle(.borderless)
                        Button(String(localized: "删除")) { remove(p) }
                            .buttonStyle(.borderless)
                    }
                }
                Button(String(localized: "添加模型实例")) { editing = nil; presentEditor = true }
            } header: {
                Text(String(localized: "我的模型实例"))
            } footer: {
                Text(String(localized: "你可以创建多个自定义模型实例，它们会出现在‘我的模型’里供选择。Token 将安全存储在钥匙串。"))
                    .foregroundStyle(.secondary)
            }
            Section {
                ForEach(LLMModelsManager.shared.modelCategories, id: \.name) { cat in
                    Text(cat.name).font(.callout).foregroundStyle(.secondary)
                    ForEach(cat.models) { m in
                        HStack {
                            Text(m.name)
                            Spacer()
                            if isDefaultAccount(provider: cat.provider, modelId: m.id) {
                                Text(String(localized: "默认")).font(.caption2).foregroundStyle(.secondary)
                            }
                            Button(String(localized: "设为默认")) { setDefaultAccount(provider: cat.provider, modelId: m.id, context: m.contextLength) }
                                .buttonStyle(.borderless)
                        }
                    }
                }
            } header: {
                Text(String(localized: "账户模型"))
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $presentEditor) {
            ProviderEditorView(provider: editing) { updated in
                if let idx = store.providers.firstIndex(where: { $0.id == updated.id }) {
                    store.providers[idx] = updated
                } else {
                    store.providers.append(updated)
                }
            }
            .frame(width: 460, height: 360)
        }
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
}

struct ProviderEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State var provider: CustomModelInstance
    @State private var token: String = ""
    var onSave: (CustomModelInstance) -> Void
    let isNew: Bool

    init(provider: CustomModelInstance?, onSave: @escaping (CustomModelInstance) -> Void) {
        _provider = State(initialValue: provider ?? CustomModelInstance(name: "我的模型", modelId: "gpt-4o-mini", baseURL: "", provider: "openai"))
        self.onSave = onSave
        self.isNew = (provider == nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "基本信息")) {
                    TextField(String(localized: "显示名"), text: $provider.name)
                    LabeledContent(String(localized: "模型")) {
                        Menu {
                            ForEach(LLMModelsManager.shared.modelCategories, id: \.name) { cat in
                                Section(cat.name) {
                                    ForEach(cat.models) { m in
                                        Button(m.name) {
                                            provider.modelId = m.id
                                            provider.provider = cat.provider
                                            provider.contextLength = m.contextLength
                                        }
                                    }
                                }
                            }
                            Divider()
                            Button(String(localized: "手动输入")) {}
                        } label: {
                            HStack(spacing: 8) {
                                Text(provider.modelId)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.2)))
                        }
                        .buttonStyle(.plain)
                    }
                    Picker(String(localized: "Provider"), selection: $provider.provider) {
                        Text("OpenAI").tag("openai")
                        Text("Anthropic").tag("anthropic")
                        Text("Compatible").tag("compatible")
                    }
                }
                Section(String(localized: "连接")) {
                    TextField(String(localized: "Base URL（可选）"), text: $provider.baseURL)
                    SecureField(String(localized: "API Token"), text: $token)
                }
                Section(String(localized: "限制")) {
                    Stepper(value: Binding(get: { provider.contextLength ?? 4096 }, set: { provider.contextLength = $0 }), in: 256...200000, step: 256) {
                        HStack {
                            Text(String(localized: "最大 Token"))
                            Spacer()
                            Text("\(provider.contextLength ?? 4096)")
                                .foregroundStyle(.secondary)
                        }
                    }
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
}
