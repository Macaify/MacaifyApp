import SwiftUI
import Defaults
import AppKit

struct ModelsSettingsView: View {
    @State private var showUpgrade = false
    @State private var pendingModel: Model? = nil
    @StateObject private var providerStore = ProviderStore.shared

    var body: some View {
        Form {
            Section(String(localized: "全部模型")) {
                ForEach(LLMModelsManager.shared.modelCategories, id: \.name) { cat in
                    Text(cat.name).font(.callout).foregroundStyle(.secondary)
                    ForEach(cat.models) { m in
                        modelRow(model: m, provider: cat.provider)
                    }
                }
            }
            Section(String(localized: "我的模型")) {
                ForEach(providerStore.providers) { inst in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(inst.name)
                            Text("\(inst.provider) • \(inst.modelId)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(String(localized: "选择")) {
                            Defaults[.selectedModelId] = inst.modelId
                            Defaults[.selectedProvider] = inst.provider
                            Defaults[.proxyAddress] = inst.baseURL
                            Defaults[.defaultSource] = "provider"
                            Defaults[.selectedProviderInstanceId] = inst.id
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showUpgrade) {
            UpgradeSheet(model: pendingModel)
                .frame(width: 420)
        }
    }

    @ViewBuilder
    private func modelRow(model: Model, provider: String) -> some View {
        HStack {
            Text(model.name).font(.body)
            Spacer()
            if requiresUpgrade(model) {
                LockBadge(text: "Pro+")
            }
            Button(String(localized: "Select")) {
                if requiresUpgrade(model) {
                    pendingModel = model
                    showUpgrade = true
                } else {
                    Defaults[.selectedModelId] = model.id
                    Defaults[.selectedProvider] = provider
                    Defaults[.maxToken] = model.contextLength
                }
            }
        }
        .padding(.vertical, 4)
        .overlay(Divider(), alignment: .bottom)
    }

    private func requiresUpgrade(_ model: Model) -> Bool {
        // Temporary heuristic: any model with context > 128k requires Pro+
        return model.contextLength > 128000
    }
}

struct LockBadge: View {
    let text: String
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "lock.fill")
            Text(text)
        }
        .font(.caption2)
        .padding(.horizontal, 6).padding(.vertical, 4)
        .background(Capsule().fill(Color.gray.opacity(0.15)))
    }
}

struct UpgradeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let model: Model?
    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "模型")) {
                    Text(model?.name ?? "")
                }
                Section(String(localized: "说明")) {
                    Text(String(localized: "该模型需要 Pro+ 计划。你可以前往升级，或改用你自己的模型实例。"))
                        .foregroundStyle(.secondary)
                }
                Section(String(localized: "操作")) {
                    HStack {
                        Button(String(localized: "升级")) {
                            if let url = URL(string: "https://macaify.com/pricing") { NSWorkspace.shared.open(url) }
                        }
                        .buttonStyle(.borderedProminent)
                        Button(String(localized: "使用我的模型实例")) {
                            if let url = URL(string: "https://macaify.com/help/providers") { NSWorkspace.shared.open(url) }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(String(localized: "需要升级"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "关闭")) { dismiss() }
                }
            }
        }
        .frame(minWidth: 420, minHeight: 280)
    }
}
