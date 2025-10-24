//
//  ModelSelectionManager.swift
//  XCAChatGPTMac
//
//  Created by lixindong on 2023/4/8.
//

import Foundation
import Defaults

/// 会员计划
enum MembershipPlan: String, CaseIterable, Hashable {
    case free = "Free"
    case pro = "Pro"
    case proPlus = "Pro+"

    var rank: Int { switch self { case .free: return 0; case .pro: return 1; case .proPlus: return 2 } }
}

/// 登录/计划状态提供者（与 betterauthswift 解耦）。
protocol MembershipProvider {
    var isLoggedIn: Bool { get }
    var currentPlan: MembershipPlan? { get }
}

struct DefaultMembershipProvider: MembershipProvider {
    var isLoggedIn: Bool { false }
    var currentPlan: MembershipPlan? { nil }
}

/// 远端模型条目（最小视图模型，用于 UI 展示与选择）。
struct RemoteModelItem: Identifiable, Equatable, Hashable {
    enum Gate: Hashable { case available, loginRequired, upgradeRequired(MembershipPlan) }
    let id: String        // backend id e.g. "anthropic/claude-3.5-sonnet"
    let slug: String      // e.g. "claude-3.5-sonnet" or "gpt-4o-mini"
    let name: String
    let provider: String
    let description: String?
    let contextTokens: Int?
    let gate: Gate
    // Lightweight capability/price for悬浮详情
    let supportsImage: Bool
    let supportsTools: Bool
    let supportsReasoning: Bool
    let supportsWeb: Bool
    let thinking: Bool
    let pricePromptPerM: Int?
    let priceCompletionPerM: Int?
    let scoreSpeed: Int?
    let scoreIntelligence: Int?
}

/// 管理“可用模型目录 + 选择状态”。
final class ModelSelectionManager: ObservableObject {
    static let shared = ModelSelectionManager()

    // 自定义（本地）模型：沿用现有 XML/用户输入
    let localModels = LLMModelsManager.shared.modelCategories.flatMap { $0.models }

    // 远端 provider 顺序与分组
    @Published private(set) var providers: [String] = []
    @Published private(set) var modelsByProvider: [String: [RemoteModelItem]] = [:]
    @Published private(set) var isFetching = false
    @Published private(set) var lastUpdatedAt: Date? = nil
    @Published private(set) var errorMessage: String? = nil

    // 会员状态来源（可注入）
    var membership: MembershipProvider = DefaultMembershipProvider()

    private init() {}

    func model(name: String) -> Model? {
        localModels.first(where: { $0.name == name }) ?? Model(name: name, contextLength: 4096)
    }

    func getSelectedModelId() -> String {
        let modelId = Defaults[.selectedModelId]
        if modelId.isEmpty {
            return localModels.first?.id ?? "gpt-4o-mini"
        } else {
            return modelId
        }
    }
}

// MARK: - Remote loading

import MacaifyServiceKit

extension ModelSelectionManager {
    @MainActor
    func refreshRemote() async {
        #if DEBUG
        print("[ModelSelectionManager] base=\(BackendEnvironment.baseURL.absoluteString)")
        #endif
        isFetching = true
        defer { isFetching = false }
        let api = BackendClientFactory.makeModelsAPI()
        do {
            let data = try await api.fetchAvailableModels(mode: MacaifyServiceKit.Mode.effective)
            // Build sections
            var grouped: [String: [RemoteModelItem]] = [:]
            for model in data.models {
                let provider = model.provider
                let slug = model.slug
                let gate = gateForRemoteModel(plans: model.plans)
                let item = RemoteModelItem(
                    id: model.id,
                    slug: slug,
                    name: model.name,
                    provider: provider,
                    description: model.description,
                    contextTokens: model.context?.tokens,
                    gate: gate,
                    supportsImage: model.modalities?.input?.contains("image") == true,
                    supportsTools: model.features?.tools ?? false,
                    supportsReasoning: model.features?.reasoning ?? false,
                    supportsWeb: model.features?.webSearch ?? false,
                    thinking: model.thinking ?? false,
                    pricePromptPerM: model.pricingPerMillion?.prompt,
                    priceCompletionPerM: model.pricingPerMillion?.completion,
                    scoreSpeed: model.scores?.speed,
                    scoreIntelligence: model.scores?.intelligence
                )
                grouped[provider, default: []].append(item)
            }
            // Preserve provider order from backend
            self.providers = data.providers
            self.modelsByProvider = grouped
            self.lastUpdatedAt = Date()
            self.errorMessage = nil
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    private func gateForRemoteModel(plans: [MacaifyServiceKit.Plan]?) -> RemoteModelItem.Gate {
        // 未登录：若标注包含 Free，则视为可用；否则需要登录
        if !membership.isLoggedIn {
            if plans == nil { return .available }
            if let p = plans, p.contains(.free) { return .available }
            return .loginRequired
        }
        guard let requiredPlans = plans, !requiredPlans.isEmpty else { return .available }
        // Find minimal required plan
        let required: MembershipPlan? = requiredPlans
            .compactMap { p in
                switch p { case .free: return .free; case .pro: return .pro; case .proPlus: return .proPlus }
            }
            .sorted(by: { $0.rank < $1.rank })
            .first
        if let cur = membership.currentPlan, let req = required, cur.rank >= req.rank { return .available }
        return .upgradeRequired(required ?? .pro)
    }
}

// MARK: - Side effects

extension ModelSelectionManager {
    /// 选择远端模型（根据 gate 做跳转或设置 Defaults）。
    func select(remote item: RemoteModelItem, onLogin: () -> Void, onUpgrade: (MembershipPlan) -> Void) {
        switch item.gate {
        case .available:
            Defaults[.selectedModelId] = item.slug
            Defaults[.selectedProvider] = item.provider
            if let ctx = item.contextTokens { Defaults[.maxToken] = ctx }
            Defaults[.defaultSource] = "account"
            Defaults[.selectedProviderInstanceId] = ""
        case .loginRequired:
            onLogin()
        case .upgradeRequired(let plan):
            onUpgrade(plan)
        }
    }
}
