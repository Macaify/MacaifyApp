//
//  NewMainView.swift
//  XCAChatGPTMac
//
//  Created by Codex on 2025/10/19.
//

import SwiftUI
#if canImport(MarkdownUI)
import MarkdownUI
#endif
import BetterAuth
import BetterAuthBrowserOTT
import CoreData
import Defaults
import AppKit
import Combine
import GPTEncoder
import MarkdownView
import MacaifyServiceKit

// MARK: - Store for sidebar bots
// Global quick-chat event deduper shared across all view hierarchies/windows
private final class QuickChatEventGate {
    static let shared = QuickChatEventGate()
    private var handled: Set<String> = []
    func checkAndMark(_ id: String) -> Bool {
        guard !id.isEmpty && id != "N/A" else { return true }
        if handled.contains(id) { return false }
        handled.insert(id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in self?.handled.remove(id) }
        return true
    }
}
final class BotStore: ObservableObject {
    @Published var bots: [GPTConversation] = []
    @Published var selectedID: UUID? = nil

    init() {
        reload()
        selectedID = bots.first?.id
        NotificationCenter.default.addObserver(forName: .NSManagedObjectContextDidSave, object: nil, queue: .main) { [weak self] _ in
            self?.reload()
        }
    }

    func reload() {
        bots = PersistenceController.shared.loadConversations()
        if let id = selectedID, bots.contains(where: { $0.id == id }) { /* keep */ }
        else { selectedID = bots.first?.id }
    }

    func addBot() {
        let conv = GPTConversation.new
        conv.name = String(localized: "new_bot")
        conv.prompt = ""
        conv.withContext = true
        conv.timestamp = Date()
        conv.copyToCoreData().save()
        reload()
        selectedID = bots.first?.id
    }

    func addBot(from template: PromptTemplate) {
        let conv = GPTConversation.new
        conv.name = template.title
        conv.prompt = template.prompt
        conv.withContext = true
        conv.timestamp = Date()
        conv.copyToCoreData().save()
        reload()
        selectedID = bots.first?.id
    }

    func deleteBot(_ bot: GPTConversation) {
        PersistenceController.shared.deleteConversation(conversation: bot)
        reload()
    }

    var selected: GPTConversation? { bots.first(where: { $0.id == selectedID }) }
}

// MARK: - Simplified chat VM for the new UI
final class ChatSessionViewModel: ObservableObject {
    struct ChatMessage: Identifiable, Hashable { enum Sender { case user, assistant }
        let id = UUID(); let sender: Sender; var text: String; var isStreaming: Bool = false; var viaAgent: String? = nil }

    @Published var messages: [ChatMessage] = []             // current session messages (ephemeral + streaming)
    @Published var input: String = ""
    @Published var isSending: Bool = false
    @Published var error: String? = nil
    @Published var errorPrimaryTitle: String? = nil
    @Published var errorSecondaryTitle: String? = nil
    private var errorPrimaryAction: (() -> Void)? = nil
    private var errorSecondaryAction: (() -> Void)? = nil
    @Published var modelLabel: String = ""
    @Published var contextSnippet: String? = nil
    @Published var contextSourceAppName: String? = nil
    @Published var contextSourceBundleId: String? = nil
    @Published var contextPinned: Bool = true
    // Selected session is tracked by Core Data objectID to avoid index/order drift
    @Published var selectedSessionID: NSManagedObjectID? = nil
    @Published var tokenHint: String = ""
    @Published var pendingNewSession: Bool = false
    // Correlate quick-chat triggers and dedupe analysis
    @Published var lastTriggerId: String? = nil
    // Async token count calculation task (for throttling/off-main work)
    private var tokenCalcTask: Task<Void, Never>? = nil

    private var api: ChatGPTAPI
    private var conv: GPTConversation
    private let encoder = GPTEncoder()
    @Published var configHint: String? = nil
    private struct APISendConfig { let provider: String; let model: String; let baseURL: String; let keyMasked: String; let withContext: Bool; let systemPromptLen: Int; let convId: UUID; let isAccount: Bool }
    private var lastConfig: APISendConfig? = nil
    private var cancellables: Set<AnyCancellable> = []
    private var selectLatestOnNextLoad: Bool = false

    init(conversation: GPTConversation) {
        self.conv = conversation
        let resolved = Self.resolveAPI(for: conversation)
        self.api = resolved.api
        self.lastConfig = resolved.cfg
        self.configHint = resolved.hint
        self.modelLabel = self.modelLabelText(for: resolved.cfg)
        // React to model catalog updates to keep provider/name fresh for account models
        ModelSelectionManager.shared.$modelsByProvider
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                let resolved = Self.resolveAPI(for: self.conv)
                self.api = resolved.api
                self.lastConfig = resolved.cfg
                self.configHint = resolved.hint
                self.modelLabel = self.modelLabelText(for: resolved.cfg)
            }
            .store(in: &cancellables)
        Task { await loadHistory() }
    }

    func updateConversation(_ next: GPTConversation) {
        // Compare via Core Data identity to avoid unstable UUIDs
        let convChanged = next.objectID != self.conv.objectID
        self.conv = next
        let resolved = Self.resolveAPI(for: next)
        self.api = resolved.api
        self.lastConfig = resolved.cfg
        self.configHint = resolved.hint
        self.modelLabel = self.modelLabelText(for: resolved.cfg)
        // Only reload messages when switching to a different bot
        if convChanged {
            // Reset transient state so the new bot can deterministically select default session
            pendingNewSession = false
            selectedSessionID = nil // force default selection in loadHistory
            selectLatestOnNextLoad = false
            Task { await loadHistory() }
        }
    }

    // Lightweight conversation switch used by TypingInPlace mirroring.
    // Does not reset pending state or trigger loadHistory to avoid racing away ephemeral bubbles.
    func updateConversationForMirroring(_ next: GPTConversation) {
        self.conv = next
        let resolved = Self.resolveAPI(for: next)
        self.api = resolved.api
        self.lastConfig = resolved.cfg
        self.configHint = resolved.hint
        self.modelLabel = self.modelLabelText(for: resolved.cfg)
    }

    private func setError(_ message: String, primaryTitle: String? = nil, secondaryTitle: String? = nil, primary: (() -> Void)? = nil, secondary: (() -> Void)? = nil) {
        self.error = message
        self.errorPrimaryTitle = primaryTitle
        self.errorSecondaryTitle = secondaryTitle
        self.errorPrimaryAction = primary
        self.errorSecondaryAction = secondary
    }

    private func clearError() {
        setError("")
        self.error = nil
    }

    private func switchToAccountDefault() {
        let defModel = Defaults[.selectedModelId]
        var updated = conv
        updated.modelSource = "account"
        updated.modelId = defModel
        updated.save()
        updateConversation(updated)
    }
    private func openPricing() {
        if let url = URL(string: "https://macaify.com/#pricing") { NSWorkspace.shared.open(url) }
    }

    private static func computeHint(for conv: GPTConversation, cfg: APISendConfig) -> String? {
        var hints: [String] = []
        if conv.modelSource == "instance" {
            if cfg.keyMasked.isEmpty { hints.append(String(localized: "instance_token_not_configured")) }
            if cfg.provider != "openai" && cfg.baseURL.trimmingCharacters(in: .whitespaces).isEmpty { hints.append("该实例需要设置 Base URL") }
        } else {
            // 账户模型走网关，不再需要本地 API Key 提示
            if !cfg.isAccount && cfg.keyMasked.isEmpty { hints.append("未设置账户 API Key") }
        }
        return hints.isEmpty ? nil : hints.joined(separator: "；") + "。"
    }

    private static func resolveAPI(for conv: GPTConversation) -> (api: ChatGPTAPI, cfg: APISendConfig, hint: String?) {
        let maxToken = Defaults[.maxToken]
        var model = conv.modelId
        var provider = "openai"
        var baseURL = ""
        var key: String = ""
        var isAccount = false
        let source = conv.modelSource

        if source == "instance", let inst = ProviderStore.shared.providers.first(where: { $0.id == conv.modelInstanceId }) {
            model = inst.modelId
            // 将 "compatible" 归一化为 openai（使用 OpenAI 兼容接口 + 自定义 Base URL）
            provider = (inst.provider == "compatible" ? "openai" : inst.provider)
            baseURL = inst.baseURL
            key = ProviderStore.shared.token(for: inst.id) ?? ""
        } else {
            // account/default
            let selectedModel = conv.modelId.isEmpty ? Defaults[.selectedModelId] : conv.modelId
            model = selectedModel.isEmpty ? "macaify-1-mini" : selectedModel
            // Derive provider from catalog by slug; fall back to Defaults
            if let prov = ModelSelectionManager.shared.modelsByProvider.first(where: { (_, arr) in arr.contains(where: { $0.slug == model }) })?.key {
                provider = prov
            } else {
                provider = Defaults[.selectedProvider].isEmpty ? "openai" : Defaults[.selectedProvider]
            }
            // 账户模型：使用账户网关 + Bearer，不再读取本地 API Key
            isAccount = true
            baseURL = ""
            key = ""
        }

        let api = ChatGPTAPI(apiKey: key, model: model, provider: provider, maxToken: maxToken, systemPrompt: conv.prompt, temperature: 0.5, baseURL: baseURL, withContext: conv.withContext, useAccountGateway: isAccount)
        let masked = key.isEmpty ? "" : String(repeating: "*", count: max(0, key.count - 6)) + key.suffix(6)
        let cfg = APISendConfig(provider: provider, model: model, baseURL: baseURL, keyMasked: masked, withContext: conv.withContext, systemPromptLen: conv.prompt.count, convId: conv.id, isAccount: isAccount)

        let hintText = computeHint(for: conv, cfg: cfg)
        return (api, cfg, hintText)
    }

    private func modelLabelText(for cfg: APISendConfig) -> String {
        // For custom instances, prefer the instance's display name
        if conv.modelSource == "instance", let inst = ProviderStore.shared.providers.first(where: { $0.id == conv.modelInstanceId }) {
            return inst.name.isEmpty ? inst.modelId : inst.name
        }
        // For account/default models, resolve friendly name via service catalog (name only)
        let provider = cfg.provider
        let slug = cfg.model
        let name = ModelSelectionManager.shared.modelsByProvider[provider]?.first(where: { $0.slug == slug })?.name ?? slug
        return name
    }

    @MainActor
    func loadHistory(limit: Int = 80) async {
        // 当准备开启临时会话或当前正在流式时，跳过历史加载，避免清空临时气泡
        if pendingNewSession || messages.last?.isStreaming == true {
            return
        }
        messages = []
        error = nil
        // Ensure at least one session exists
        PersistenceController.shared.ensureDefaultSession(conversation: conv)
        // Load sessions (viewContext)
        let sess = PersistenceController.shared.loadSessions(conversation: conv).filter { !$0.archived }
        if sess.isEmpty {
            // No sessions (should be rare due to ensureDefaultSession); show empty state gracefully
            self.selectedSessionID = nil
            self.messages = []
            api.history = []
            tokenHint = ""
            return
        }
        // Preserve user's explicit selection.
        // Only auto-select latest when: (a) no selection yet, or (b) previous selection no longer exists.
        if selectedSessionID == nil {
            selectedSessionID = sess.first?.objectID
        } else if let sel = selectedSessionID, !(sess.contains { $0.objectID == sel }) {
            selectedSessionID = sess.first?.objectID
        }
        // Do not override a valid manual selection just because a bot switch happened
        if selectLatestOnNextLoad && selectedSessionID == nil {
            selectedSessionID = sess.first?.objectID
        }
        selectLatestOnNextLoad = false
        guard let selID = selectedSessionID, let target = sess.first(where: { $0.objectID == selID }) else {
            self.messages = []
            api.history = []
            tokenHint = ""
            return
        }
        // Load persisted context for this session
        let snip = target.contextSnippet.trimmingCharacters(in: .whitespacesAndNewlines)
        contextSnippet = snip.isEmpty ? nil : snip
        let srcName = target.contextSourceAppName.trimmingCharacters(in: .whitespacesAndNewlines)
        contextSourceAppName = srcName.isEmpty ? nil : srcName
        let srcBid = target.contextSourceBundleId.trimmingCharacters(in: .whitespacesAndNewlines)
        contextSourceBundleId = srcBid.isEmpty ? nil : srcBid
        let container = PersistenceController.shared.container
        let targetID = target.objectID
        let convID = conv.objectID
        do {
            let rows: [(String, String)] = try await withCheckedThrowingContinuation { cont in
                let ctx = container.newBackgroundContext()
                ctx.perform {
                    do {
                        let convBG = try ctx.existingObject(with: convID) as! GPTConversation
                        let sessionBG = try ctx.existingObject(with: targetID) as! GPTSession
                        let req: NSFetchRequest<GPTAnswer> = GPTAnswer.fetchRequest()
                        req.predicate = NSPredicate(format: "belongsTo == %@ AND session == %@", convBG, sessionBG)
                        req.sortDescriptors = [NSSortDescriptor(key: "timestamp_", ascending: true)]
                        let fetched = try ctx.fetch(req)
                        let pairs = fetched.map { ($0.prompt, $0.response) }
                        cont.resume(returning: pairs)
                    } catch { cont.resume(throwing: error) }
                }
            }
            // 不将历史消息回填到 UI，本地只维护流式的临时气泡
            self.api.history = rows.flatMap { [Message(role: "user", content: $0.0), Message(role: "assistant", content: $0.1)] }
            updateTokenHint(includingInput: input)
        } catch {
            self.messages = []
        }
    }

    // removed: sessionTitle helper; session naming handled by explicit actions

    // 临时会话状态下，允许用户切换到已保存的某个会话
    @MainActor
    func selectExistingSessionWhilePending(session: GPTSession) {
        pendingNewSession = false
        select(session: session)
    }

    // MARK: - Session helpers for SwiftUI FetchRequest bridge
    @MainActor
    func select(session: GPTSession) {
        // Manual selection cancels any pending "select latest" override
        selectLatestOnNextLoad = false
        selectedSessionID = session.objectID
        // Update per-session context immediately for header
        let snip = session.contextSnippet.trimmingCharacters(in: .whitespacesAndNewlines)
        contextSnippet = snip.isEmpty ? nil : snip
        let srcName = session.contextSourceAppName.trimmingCharacters(in: .whitespacesAndNewlines)
        contextSourceAppName = srcName.isEmpty ? nil : srcName
        let srcBid = session.contextSourceBundleId.trimmingCharacters(in: .whitespacesAndNewlines)
        contextSourceBundleId = srcBid.isEmpty ? nil : srcBid
        // Refresh API history to this session on a background task
        Task { await refreshHistoryForSelectedSession(session) }
    }
    @MainActor
    func select(id: NSManagedObjectID) {
        // Manual selection cancels any pending "select latest" override
        selectLatestOnNextLoad = false
        selectedSessionID = id
        // Try to populate context and history for the selected id quickly
        let ctx = PersistenceController.shared.container.viewContext
        if let s = try? ctx.existingObject(with: id) as? GPTSession {
            let snip = s.contextSnippet.trimmingCharacters(in: .whitespacesAndNewlines)
            contextSnippet = snip.isEmpty ? nil : snip
            let srcName = s.contextSourceAppName.trimmingCharacters(in: .whitespacesAndNewlines)
            contextSourceAppName = srcName.isEmpty ? nil : srcName
            let srcBid = s.contextSourceBundleId.trimmingCharacters(in: .whitespacesAndNewlines)
            contextSourceBundleId = srcBid.isEmpty ? nil : srcBid
            Task { await refreshHistoryForSelectedSession(s) }
        }
    }

    @MainActor
    func rename(session: GPTSession, to title: String) {
        PersistenceController.shared.rename(session: session, title: title)
    }

    @MainActor
    func generateTitle(for session: GPTSession) async {
        await generateTitleInternal(for: session)
    }

    @MainActor
    func archive(session: GPTSession, archived: Bool) {
        PersistenceController.shared.archive(session: session, archived: archived)
        Task { await loadHistory() }
    }

    @MainActor
    func delete(session: GPTSession) {
        PersistenceController.shared.delete(session: session, moveToDefault: true)
        // If we deleted the selected one, reset to latest next load
        if selectedSessionID == session.objectID { selectedSessionID = nil }
        Task { await loadHistory() }
    }

    func isSelected(session: GPTSession) -> Bool {
        return session.objectID == selectedSessionID
    }

    @MainActor
    func send() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        let eid = lastTriggerId ?? "N/A"
        print("[SEND_BEGIN] id=\(eid) text.len=\(text.count) pendingNew=\(pendingNewSession) selected=\(String(describing: selectedSessionID))")
        // 首次发送时，如果是临时会话则立即实体化，确保会话栏与消息区域状态同步。
        // 发送前记录是否为“新建的首条消息”，用于触发自动生成标题。
        let wasNewSession = pendingNewSession || selectedSessionID == nil
        // 此处立即创建并捕获目标 session，避免后续异步步骤与 loadHistory 竞争导致写入到错误会话。
        ensureSessionReady()
        let targetSessionID = selectedSessionID
        print("[SEND_SESSION] id=\(eid) target=\(String(describing: targetSessionID))")
        input = ""
        isSending = true
        error = nil
        if let cfg = lastConfig {
            print("[Chat] Sending…",
                  "provider=\(cfg.provider)",
                  "model=\(cfg.model)",
                  "baseURL=\(cfg.baseURL.isEmpty ? "<default>" : cfg.baseURL)",
                  "apiKey=\(cfg.keyMasked.isEmpty ? "<empty>" : cfg.keyMasked)",
                  "withContext=\(cfg.withContext)",
                  "systemPromptLen=\(cfg.systemPromptLen)",
                  "convId=\(cfg.convId)")
            let defSource = Defaults[.defaultSource]
            let defModel = Defaults[.selectedModelId]
            let defProv = Defaults[.selectedProvider]
            let useProxy = UserDefaults.standard.object(forKey: "useProxy") as? Bool ?? false
            let proxyAddr = UserDefaults.standard.object(forKey: "proxyAddress") as? String ?? ""
            print("[Chat] Selection:",
                  "conv.source=\(conv.modelSource)",
                  "conv.modelId=\(conv.modelId)",
                  "conv.instanceId=\(conv.modelInstanceId)",
                  "Defaults.source=\(defSource)",
                  "Defaults.model=\(defModel)",
                  "Defaults.provider=\(defProv)",
                  "useProxy=\(useProxy)",
                  "proxy=\(proxyAddr)")
        }
        // For UI and persistence, keep the user's message clean (no inline context)
        messages.append(.init(sender: .user, text: text))
        updateTokenHint(includingInput: "")
        messages.append(.init(sender: .assistant, text: "", isStreaming: true))
        do {
            // Inject context into system prompt while sending (temporary override)
            let originalPrompt = api.systemPrompt
            if let suffix = makeSystemContextSuffix() {
                api.systemPrompt = originalPrompt + "\n\n" + "<context> is the context this chat session is based on." + "\n" + suffix
            }
            // If this is the first user message in this session, kick off title generation via backend service kit
            if wasNewSession {
                let systemForTitle: String = {
                    if let suffix = makeSystemContextSuffix() {
                        return originalPrompt + "\n\n" + "<context> is the context this chat session is based on." + "\n" + suffix
                    }
                    return originalPrompt
                }()
                let userForTitle = text
                let sessionForTitle = targetSessionID
                Task.detached { [weak self] in
                    guard let self else { return }
                    await self.generateTitleWithServiceKit(system: systemForTitle, user: userForTitle, sessionID: sessionForTitle)
                }
            }
            defer { api.systemPrompt = originalPrompt }
            let stream = try await api.chatsStream(text: text)
            var buffer = ""
            for try await chunk in stream {
                let delta = chunk.choices.first?.delta.content ?? ""
                guard !delta.isEmpty else { continue }
                buffer += delta
                if let idx = messages.lastIndex(where: { $0.isStreaming }) { messages[idx].text = buffer }
            }
            if let idx = messages.lastIndex(where: { $0.isStreaming }) { messages[idx].isStreaming = false }
            print("[SEND_PERSIST] id=\(eid) to=\(String(describing: targetSessionID)) len=\(buffer.count)")
            persist(user: text, assistant: buffer, to: targetSessionID)
        } catch {
            // Print for debugging visibility
            print("[Chat] stream error:", error)
            if let idx = messages.lastIndex(where: { $0.isStreaming }) { messages.remove(at: idx) }
            let message: String
            if let apiErr = error as? ChatGPTAPI.ChatAPIError {
                message = apiErr.localizedDescription
                switch apiErr {
                case .planNotAllowed, .quotaExceeded, .trialExpired:
                    setError(message, primaryTitle: String(localized: "升级"), secondaryTitle: String(localized: "切换默认模型"), primary: { [weak self] in self?.openPricing() }, secondary: { [weak self] in self?.switchToAccountDefault() })
                case .unauthorized, .notLoggedIn:
                    setError(message, primaryTitle: String(localized: "去登录"), secondaryTitle: nil, primary: {
                        NotificationCenter.default.post(name: .init("BetterAuthLoginRequestedFromChat"), object: nil)
                    })
                default:
                    setError(message)
                }
            } else {
                message = "Error: \(error.localizedDescription)"
                setError(message)
            }
            messages.append(.init(sender: .assistant, text: message))
            
        }
        isSending = false
        print("[SEND_END] id=\(eid)")
        if !contextPinned {
            contextSnippet = nil
            persistContextToCurrentSession()
        }
    }

    // MARK: - Title generation via MacaifyServiceKit
    @MainActor private func truncate(_ s: String, to max: Int) -> String { s.count > max ? String(s.prefix(max)) : s }
    private func generateTitleWithServiceKit(system: String, user: String, sessionID: NSManagedObjectID?) async {
        // Prepare request payload with light truncation
        let sys = await MainActor.run { truncate(system.trimmingCharacters(in: .whitespacesAndNewlines), to: 2000) }
        let usr = await MainActor.run { truncate(user.trimmingCharacters(in: .whitespacesAndNewlines), to: 800) }
        let msgs = [TitleMessage(role: "system", content: sys), TitleMessage(role: "user", content: usr)]
        // Fetch bearer if available
        var auth: String? = nil
        #if canImport(BetterAuth)
        auth = await TokenAuth.shared.getAuthorizationHeader()
        #endif
        let api = BackendClientFactory.makeTitlesAPI()
        do {
            let title = try await api.generateChatTitle(messages: msgs, text: nil, maxLen: 30, authHeader: auth)
            // Apply to the captured session
            await MainActor.run {
                let oid = sessionID ?? selectedSessionID
                if let oid, let s = try? PersistenceController.shared.container.viewContext.existingObject(with: oid) as? GPTSession {
                    PersistenceController.shared.rename(session: s, title: title)
                }
            }
        } catch {
            print("[TITLE_ERROR] failed to generate: \(error.localizedDescription)")
        }
    }

    // MARK: - Mirroring for TypingInPlace (In-Context)
    // Show the same ephemeral bubbles in the main UI while typing into other apps.
    @MainActor
    func mirrorStart(user text: String) {
        let eid = lastTriggerId ?? "N/A"
        print("[MIRROR_START] id=\(eid) len=\(text.count)")
        // Keep in pending-new-session so ChatDetailView renders ephemeral list instead of persisted rows.
        pendingNewSession = true
        messages.removeAll()
        input = ""
        error = nil
        messages.append(.init(sender: .user, text: text))
        messages.append(.init(sender: .assistant, text: "", isStreaming: true))
        updateTokenHint(includingInput: "")
    }

    @MainActor
    func mirrorDelta(_ delta: String) {
        let eid = lastTriggerId ?? "N/A"
        print("[MIRROR_DELTA] id=\(eid) len=\(delta.count)")
        guard !delta.isEmpty else { return }
        if let idx = messages.lastIndex(where: { $0.isStreaming && $0.sender == .assistant }) {
            messages[idx].text += delta
        }
    }

    @MainActor
    func mirrorFinish(persistResult: Bool = true) {
        let eid = lastTriggerId ?? "N/A"
        if let idx = messages.lastIndex(where: { $0.isStreaming && $0.sender == .assistant }) {
            messages[idx].isStreaming = false
            if persistResult {
                let user = messages.prefix(idx).last(where: { $0.sender == .user })?.text ?? ""
                let assistant = messages[idx].text
                if !assistant.isEmpty {
                    // Materialize and capture target session to avoid race with selection/history reload
                    ensureSessionReady()
                    let target = selectedSessionID
                    print("[MIRROR_PERSIST] id=\(eid) to=\(String(describing: target)) len=\(assistant.count)")
                    persist(user: user, assistant: assistant, to: target)
                }
                // After persistence, switch to normal session mode next render
                pendingNewSession = false
            }
        }
        print("[MIRROR_END] id=\(eid)")
    }

    @MainActor
    func stopStreaming() {
        api.interupt()
        isSending = false
        if let idx = messages.lastIndex(where: { $0.isStreaming }) {
            messages[idx].isStreaming = false
        }
    }

    // MARK: - Quick actions
    func copyLastReply() {
        if let last = messages.last(where: { $0.sender == .assistant && !$0.text.isEmpty }) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(last.text, forType: .string)
        }
    }
    func useLastReply() {
        if let last = messages.last(where: { $0.sender == .assistant && !$0.text.isEmpty }) {
            paste(delay: 0.1, sentence: last.text)
            NSApp.hide(nil)
        }
    }
    func injectContext(_ text: String) {
        contextSnippet = text
        // Persist immediately if current session exists
        persistContextToCurrentSession()
    }

    @MainActor
    func runWithAgent(agent: GPTConversation, using text: String?) async {
        let base = (text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        let fallback = messages.last(where: { $0.sender == .user })?.text ?? ""
        var composed = base.isEmpty ? fallback : base
        guard !composed.isEmpty else {
            self.error = "没有可运行的输入（请输入内容或选择一条消息）"
            return
        }

        // Build a temporary API for the selected agent
        let resolved = Self.resolveAPI(for: agent)
        let tempAPI = resolved.api
        // Show a streaming assistant bubble tagged with agent name
        messages.append(.init(sender: .assistant, text: "", isStreaming: true, viaAgent: agent.name))
        do {
            // Inject context into system prompt for agent run (temporary override)
            let original = tempAPI.systemPrompt
            if let suffix = makeSystemContextSuffix() {
                tempAPI.systemPrompt = original + "\n\n" + "<context> is the context this chat session is based on." + "\n" + suffix
            }
            defer { tempAPI.systemPrompt = original }
            let stream = try await tempAPI.chatsStream(text: composed)
            var buffer = ""
            for try await chunk in stream {
                let delta = chunk.choices.first?.delta.content ?? ""
                guard !delta.isEmpty else { continue }
                buffer += delta
                if let idx = messages.lastIndex(where: { $0.isStreaming }) { messages[idx].text = buffer }
            }
            if let idx = messages.lastIndex(where: { $0.isStreaming }) { messages[idx].isStreaming = false }
        } catch {
            if let idx = messages.lastIndex(where: { $0.isStreaming }) { messages.remove(at: idx) }
            let message = "Error(via \(agent.name)): \(error.localizedDescription)"
            messages.append(.init(sender: .assistant, text: message, isStreaming: false, viaAgent: agent.name))
        }
    }

    @MainActor
    func regenerateWithSystemPromptOverride(_ promptText: String) async {
        guard !isSending else { return }
        let original = api.systemPrompt
        api.systemPrompt = promptText
        defer { api.systemPrompt = original }
        await regenerateLast()
    }

    @MainActor
    func generateTitleInternal(for session: GPTSession) async {
        // Fetch messages from Core Data for the target session
        let container = PersistenceController.shared.container
        let targetID = session.objectID
        let convID = conv.objectID
        var joined = ""
        do {
            let text: String = try await withCheckedThrowingContinuation { cont in
                let ctx = container.newBackgroundContext()
                ctx.perform {
                    do {
                        let convBG = try ctx.existingObject(with: convID) as! GPTConversation
                        let sessionBG = try ctx.existingObject(with: targetID) as! GPTSession
                        let req: NSFetchRequest<GPTAnswer> = GPTAnswer.fetchRequest()
                        req.predicate = NSPredicate(format: "belongsTo == %@ AND session == %@", convBG, sessionBG)
                        req.sortDescriptors = [NSSortDescriptor(key: "timestamp_", ascending: true)]
                        let fetched = try ctx.fetch(req)
                        let j = fetched.map { (ans: GPTAnswer) in
                            let isUser = (ans.role == "user")
                            return (isUser ? "User: " : "Assistant: ") + (isUser ? ans.prompt : ans.response)
                        }.joined(separator: "\n")
                        cont.resume(returning: j)
                    } catch { cont.resume(throwing: error) }
                }
            }
            joined = text
        } catch {
            self.error = "生成标题失败：\(error.localizedDescription)"
            return
        }
        let resolved = Self.resolveAPI(for: conv)
        let tmpAPI = resolved.api
        let directive = "请为以下对话生成一个不超过24字的简短标题：\n\n" + joined + "\n\n仅输出标题，不要引号。"
        do {
            let title = try await tmpAPI.sendMessage(directive)
            let compact = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !compact.isEmpty {
                let newTitle = compact.count > 24 ? String(compact.prefix(24)) + "…" : compact
                PersistenceController.shared.rename(session: session, title: newTitle)
            }
        } catch {
            self.error = "生成标题失败：\(error.localizedDescription)"
        }
    }
    @MainActor
    func regenerateLast() async {
        guard !isSending else { return }
        guard let lastUser = messages.last(where: { $0.sender == .user })?.text, !lastUser.isEmpty else { return }
        isSending = true
        messages.append(.init(sender: .assistant, text: "", isStreaming: true))
        do {
            // Inject context into system prompt while regenerating (temporary override)
            let originalPrompt = api.systemPrompt
            if let suffix = makeSystemContextSuffix() {
                api.systemPrompt = originalPrompt + "\n\n" + "<context> is the context this chat session is based on." + "\n" + suffix
            }
            defer { api.systemPrompt = originalPrompt }
            let stream = try await api.chatsStream(text: lastUser)
            var buffer = ""
            for try await chunk in stream {
                let delta = chunk.choices.first?.delta.content ?? ""
                guard !delta.isEmpty else { continue }
                buffer += delta
                if let idx = messages.lastIndex(where: { $0.isStreaming }) { messages[idx].text = buffer }
            }
            if let idx = messages.lastIndex(where: { $0.isStreaming }) { messages[idx].isStreaming = false }
            persist(user: lastUser, assistant: buffer)
        } catch {
            print("[Chat] regenerate error:", error)
            if let idx = messages.lastIndex(where: { $0.isStreaming }) { messages.remove(at: idx) }
            let message: String
            if let apiErr = error as? ChatGPTAPI.ChatAPIError {
                message = apiErr.localizedDescription
                switch apiErr {
                case .planNotAllowed, .quotaExceeded, .trialExpired:
                    setError(message, primaryTitle: String(localized: "升级"), secondaryTitle: String(localized: "切换默认模型"), primary: { [weak self] in self?.openPricing() }, secondary: { [weak self] in self?.switchToAccountDefault() })
                case .unauthorized, .notLoggedIn:
                    setError(message, primaryTitle: String(localized: "去登录"), secondaryTitle: nil, primary: {
                        NotificationCenter.default.post(name: .init("BetterAuthLoginRequestedFromChat"), object: nil)
                    })
                default:
                    setError(message)
                }
            } else {
                message = "Error: \(error.localizedDescription)"
                setError(message)
            }
            messages.append(.init(sender: .assistant, text: message))
            
        }
        isSending = false
    }

    // Start a new session lazily (不立即持久化，会在首次发送时创建)
    @MainActor
    func startNewSession() {
        pendingNewSession = true
        messages.removeAll()
        // New session starts with empty per-session context
        contextSnippet = nil
        contextSourceAppName = nil
        contextSourceBundleId = nil
        api.history = []
        tokenHint = ""
    }

    private func ensureSessionReady() {
        guard pendingNewSession || selectedSessionID == nil else { return }
        if let created = PersistenceController.shared.createSession(conversation: conv, title: String(localized: "new_session")) {
            // Persist current context into the new session
            created.contextSnippet = (contextSnippet ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            created.contextSourceAppName = (contextSourceAppName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            created.contextSourceBundleId = (contextSourceBundleId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            created.updatedAt = Date()
            do { try created.managedObjectContext?.save() } catch { print("save session context error:", error) }
            print("[SESSION_CREATE] reason=ensureSessionReady id=\(created.objectID)")
            selectedSessionID = created.objectID
            pendingNewSession = false
        }
    }

    func updateTokenHint(includingInput input: String) {
        let historyText = api.history.map { $0.content }.joined(separator: "\n")
        let maxTk = Defaults[.maxToken]
        tokenCalcTask?.cancel()
        tokenCalcTask = Task.detached(priority: .utility) { [historyText, input, weak self] in
            guard let self else { return }
            let text = historyText + (input.isEmpty ? "" : ("\n" + input))
            let total = self.encoder.encode(text: text).count
            await MainActor.run { [weak self] in self?.tokenHint = "~ \(total) / \(maxTk) tokens" }
        }
    }

    // Build a structured context block to append to system prompt
    private func makeSystemContextSuffix() -> String? {
        let raw = (contextSnippet ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        let app = (contextSourceAppName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var block = "<context>\n"
        if !app.isEmpty {
            block += "<source app>\n\(app)\n</source app>\n"
        }
        block += "<selectedText>\n\(raw)\n</selectedText>\n" + "</context>"
        return block
    }

    // Rebuild API history for a specific session selection
    private func refreshHistoryForSelectedSession(_ session: GPTSession) async {
        let container = PersistenceController.shared.container
        let convID = conv.objectID
        let targetID = session.objectID
        do {
            let rows: [(String, String)] = try await withCheckedThrowingContinuation { cont in
                let bg = container.newBackgroundContext()
                bg.perform {
                    do {
                        let convBG = try bg.existingObject(with: convID) as! GPTConversation
                        let sessionBG = try bg.existingObject(with: targetID) as! GPTSession
                        let req: NSFetchRequest<GPTAnswer> = GPTAnswer.fetchRequest()
                        req.predicate = NSPredicate(format: "belongsTo == %@ AND session == %@", convBG, sessionBG)
                        req.sortDescriptors = [NSSortDescriptor(key: "timestamp_", ascending: true)]
                        let fetched = try bg.fetch(req)
                        let pairs = fetched.map { ($0.prompt, $0.response) }
                        cont.resume(returning: pairs)
                    } catch { cont.resume(throwing: error) }
                }
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.api.history = rows.flatMap { [Message(role: "user", content: $0.0), Message(role: "assistant", content: $0.1)] }
                self.updateTokenHint(includingInput: self.input)
            }
        } catch {
            await MainActor.run { [weak self] in self?.api.history = [] }
        }
    }

    // Persist current context fields into the selected session (if available and not pending)
    private func persistContextToCurrentSession() {
        guard !pendingNewSession, let oid = selectedSessionID else { return }
        let ctx = PersistenceController.shared.container.viewContext
        if let s = try? ctx.existingObject(with: oid) as? GPTSession {
            s.contextSnippet = (contextSnippet ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            s.contextSourceAppName = (contextSourceAppName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            s.contextSourceBundleId = (contextSourceBundleId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            s.updatedAt = Date()
            do { try ctx.save() } catch { print("persistContext error:", error) }
        }
    }

    @MainActor
    // removed index-based session management in favor of objectID-based selection

    private func persist(user: String, assistant: String) {
        guard !assistant.isEmpty else { return }
        ensureSessionReady()
        let mc = conv.managedObjectContext ?? PersistenceController.shared.container.viewContext
        let answer = GPTAnswer(role: "user", prompt: user, response: assistant, parentId: conv.own.last?.uuid, context: mc)
        // Assign current session if available
        if let oid = selectedSessionID, let s = try? mc.existingObject(with: oid) as? GPTSession {
            answer.session = s
            s.updatedAt = Date()
        }
        conv.addAnswer(answer: answer)
        conv.timestamp = Date()
        conv.save()
    }

    // 显式持久化到指定的 session（避免异步改选导致写错会话）
    private func persist(user: String, assistant: String, to sessionID: NSManagedObjectID?) {
        guard !assistant.isEmpty else { return }
        let mc = conv.managedObjectContext ?? PersistenceController.shared.container.viewContext
        let answer = GPTAnswer(role: "user", prompt: user, response: assistant, parentId: conv.own.last?.uuid, context: mc)
        if let sid = sessionID, let s = try? mc.existingObject(with: sid) as? GPTSession {
            answer.session = s
            s.updatedAt = Date()
        } else if let oid = selectedSessionID, let s = try? mc.existingObject(with: oid) as? GPTSession {
            // fallback: 当前选中
            answer.session = s
            s.updatedAt = Date()
        }
        print("[PERSIST] target=\(String(describing: sessionID)) fallback=\(String(describing: selectedSessionID)) len=\(assistant.count)")
        conv.addAnswer(answer: answer)
        conv.timestamp = Date()
        conv.save()
    }

    @MainActor
    func clearHistory() {
        // Prefer clearing only the currently selected session; never wipe the whole conversation
        if !pendingNewSession, let sel = selectedSessionID {
            let ctx = PersistenceController.shared.container.viewContext
            if let s = try? ctx.existingObject(with: sel) as? GPTSession {
                PersistenceController.shared.clearAnswers(session: s)
                messages.removeAll()
                api.deleteHistoryList()
                updateTokenHint(includingInput: input)
                return
            }
        }
        // No concrete session selected; clear only in-memory state
        messages.removeAll()
        api.deleteHistoryList()
        updateTokenHint(includingInput: input)
    }
}

extension ChatSessionViewModel {
    func performPrimaryErrorAction() { errorPrimaryAction?(); errorPrimaryAction = nil }
    func performSecondaryErrorAction() { errorSecondaryAction?(); errorSecondaryAction = nil }
}

// MARK: - UI
struct MainSplitView: View {
    @StateObject private var store = BotStore()
    @StateObject private var chatVM = ChatSessionViewModel(conversation: GPTConversation(context: PersistenceController.memoryContext))
    @State private var showSettings = false
    @State private var showBotTemplatePicker = false
    @State private var botTemplateResetKey = 0
    @State private var myWindow: NSWindow? = nil

    var body: some View {
        NavigationSplitView {
            Sidebar(store: store, openTemplatePicker: {
                botTemplateResetKey &+= 1
                showBotTemplatePicker = true
            })
        } detail: {
            if let current = store.selected {
                ChatDetailView(viewModel: chatVM, bot: current, openBotSettings: { showSettings = true }, store: store)
                    .id(current.id)
            } else {
                VStack { Spacer(); Text("no_bot_selected").foregroundStyle(.secondary); Spacer() }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 460)
        // Register the NSWindow that hosts the main chat UI
        .background(HostingWindowFinder { window in
            myWindow = window
            WindowBridge.shared.mainWindow = window
            WindowBridge.shared.openingMain = false
        })
        // No cookie bridge needed; title auth uses Bearer
        // Let ChatDetailView drive conversation updates on appear/change.
        .onChange(of: chatVM.input) { newValue in
            chatVM.updateTokenHint(includingInput: newValue)
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("QuickChatSelectedText"))) { note in
            guard let info = note.userInfo as? [String: Any] else { return }
            let eid = (info["eventId"] as? String) ?? "N/A"
            guard let mine = myWindow, WindowBridge.shared.mainWindow === mine else { print("[QC_SKIP_NOT_MAIN] id=\(eid)"); return }
            if !QuickChatEventGate.shared.checkAndMark(eid) { print("[QC_DROP_DUP] id=\(eid)"); return }
            let convIdStr = (info["convId"] as? String) ?? ""
            let textRaw = (info["text"] as? String) ?? ""
            let srcApp = (info["sourceAppName"] as? String) ?? ""
            let srcBundle = (info["sourceBundleId"] as? String) ?? ""
            chatVM.lastTriggerId = eid
            let vmId = ObjectIdentifier(chatVM).debugDescription
            print("[QC_RECV] id=\(eid) type=Selected vm=\(vmId) pending=\(chatVM.pendingNewSession) selected=\(String(describing: chatVM.selectedSessionID)) len=\(textRaw.count)")
            if let uuid = UUID(uuidString: convIdStr), let bot = store.bots.first(where: { $0.id == uuid }) {
                store.selectedID = uuid
                chatVM.updateConversation(bot)
                // Hotkey 打开：只开启“待创建”的新会话，不立即持久化
                chatVM.startNewSession()
                let text = textRaw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    // 分离来源与正文：来源走独立字段，正文保持纯文本
                    chatVM.contextSourceAppName = srcApp.isEmpty ? nil : srcApp
                    chatVM.contextSourceBundleId = srcBundle.isEmpty ? nil : srcBundle
                    chatVM.injectContext(text)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("QuickChatSendSelectedText"))) { note in
            guard let info = note.userInfo as? [String: Any] else { return }
            let eid = (info["eventId"] as? String) ?? "N/A"
            guard let mine = myWindow, WindowBridge.shared.mainWindow === mine else { print("[QC_SKIP_NOT_MAIN] id=\(eid)"); return }
            if !QuickChatEventGate.shared.checkAndMark(eid) { print("[QC_DROP_DUP] id=\(eid)"); return }
            let convIdStr = (info["convId"] as? String) ?? ""
            let textRaw = (info["text"] as? String) ?? ""
            chatVM.lastTriggerId = eid
            let vmId = ObjectIdentifier(chatVM).debugDescription
            print("[QC_RECV] id=\(eid) type=SendSelected vm=\(vmId) pending=\(chatVM.pendingNewSession) selected=\(String(describing: chatVM.selectedSessionID)) len=\(textRaw.count)")
            if let uuid = UUID(uuidString: convIdStr), let bot = store.bots.first(where: { $0.id == uuid }) {
                store.selectedID = uuid
                chatVM.updateConversation(bot)
                chatVM.startNewSession()
                let text = textRaw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    chatVM.input = text
                    Task { await chatVM.send() }
                }
            }
        }
        // Mirror TypingInPlace streaming into the main UI
        .onReceive(NotificationCenter.default.publisher(for: .init("TypingInPlaceMirrorStart"))) { note in
            guard let info = note.userInfo as? [String: Any] else { return }
            let convIdStr = (info["convId"] as? String) ?? ""
            let text = (info["text"] as? String) ?? ""
            if let uuid = UUID(uuidString: convIdStr), let bot = store.bots.first(where: { $0.id == uuid }) {
                store.selectedID = uuid
                // Rebuild API without triggering history load/reset
                chatVM.updateConversationForMirroring(bot)
                // Enter pending-new-session mode and seed ephemeral bubbles
                chatVM.mirrorStart(user: text)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("TypingInPlaceMirrorDelta"))) { note in
            guard let info = note.userInfo as? [String: Any] else { return }
            let convIdStr = (info["convId"] as? String) ?? ""
            let delta = (info["delta"] as? String) ?? ""
            if let uuid = UUID(uuidString: convIdStr), let _ = store.bots.first(where: { $0.id == uuid }) {
                chatVM.mirrorDelta(delta)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("TypingInPlaceMirrorEnd"))) { note in
            guard let info = note.userInfo as? [String: Any] else { return }
            let convIdStr = (info["convId"] as? String) ?? ""
            if let uuid = UUID(uuidString: convIdStr), let _ = store.bots.first(where: { $0.id == uuid }) {
                chatVM.mirrorFinish(persistResult: true)
            }
        }
        .toolbar { toolbar }
        .sheet(isPresented: $showSettings) {
            if let selected = store.selected {
                LegacyBotSettingsSheet(bot: selected) {
                    store.reload()
                    if let s = store.selected { chatVM.updateConversation(s) }
                }
                    .frame(minWidth: 640, minHeight: 520)
                    .environmentObject(ConversationViewModel.shared)
                    .environmentObject(PathManager.shared)
            }
        }
        .sheet(isPresented: $showBotTemplatePicker) {
            BotTemplatePicker(resetKey: botTemplateResetKey) { tpl in
                store.addBot(from: tpl)
                if let s = store.selected { chatVM.updateConversation(s) }
                showBotTemplatePicker = false
            }
            .frame(minWidth: 560, minHeight: 520)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            // New session
            Button { chatVM.startNewSession() } label: { Label(String(localized: "new_session"), systemImage: "plus") }
                .keyboardShortcut(.init("n"), modifiers: .command)
            // Settings
            Button { showSettings = true } label: { Label(String(localized: "bot_settings"), systemImage: "gear") }
                .disabled(store.selected == nil)
        }
    }

    // MARK: - Sidebar toggle (macOS)
    private func toggleSidebar() {
        #if os(macOS)
        NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
        #endif
    }
}

// Utility to access the hosting NSWindow for a SwiftUI view hierarchy
private struct HostingWindowFinder: NSViewRepresentable {
    var onFound: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            onFound(window)
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
                if WindowBridge.shared.mainWindow === window {
                    WindowBridge.shared.mainWindow = nil
                }
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in
            if let window = nsView?.window { onFound(window) }
        }
    }
}

struct Sidebar: View {
    @ObservedObject var store: BotStore
    var openTemplatePicker: () -> Void
    var body: some View {
        List(selection: Binding(get: { store.selectedID }, set: { store.selectedID = $0 })) {
            ForEach(store.bots, id: \.id) { bot in
                HStack(spacing: 8) {
                    Text(bot.icon.isEmpty ? "🤖" : bot.icon)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bot.name.isEmpty ? String(localized: "untitled") : bot.name)
                        if !bot.prompt.isEmpty { Text(bot.prompt).lineLimit(1).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                .tag(bot.id as UUID?)
                .contextMenu { Button(role: .destructive) { store.deleteBot(bot) } label: { Label(String(localized: "delete"), systemImage: "trash") } }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(String(localized: "agents"))
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Menu {
                    Button { store.addBot() } label: { Label(String(localized: "新建空白Bot"), systemImage: "plus") }
                    Button { openTemplatePicker() } label: { Label(String(localized: "从模板添加…"), systemImage: "rectangle.stack.badge.plus") }
                } label: {
                    Label(String(localized: "add"), systemImage: "plus")
                }
            }
        }
    }
}

// Wrapper to present the legacy ConversationPreferenceView and auto-dismiss
struct LegacyBotSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    var bot: GPTConversation
    var onSaved: () -> Void

    var body: some View {
        ConversationPreferenceView(conversation: bot, mode: .edit)
            .onAppear {
                // Seed a non-main path so PathManager.back() will transition to .main and post notification
                PathManager.shared.to(target: .editCommand(command: bot))
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("toMain"))) { _ in
                onSaved()
                dismiss()
            }
    }
}

// MARK: - Inline, minimal model picker
// ModelQuickPicker has been inlined as SessionModelPicker (shared), remove legacy inline version
