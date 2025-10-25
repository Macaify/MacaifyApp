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
import GPTEncoder
import MarkdownView

// MARK: - Store for sidebar bots
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
        conv.name = "New Bot"
        conv.prompt = ""
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

    @Published var messages: [ChatMessage] = []             // current session messages
    private var allMessages: [ChatMessage] = []             // full history (all sessions)
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
    struct SessionInfo: Identifiable, Hashable { let id = UUID(); var start: Int; var end: Int; var title: String }
    @Published var sessions: [SessionInfo] = []
    @Published var selectedSession: Int = 0
    @Published var tokenHint: String = ""
    private var sessionIDs: [NSManagedObjectID] = []
    @Published var pendingNewSession: Bool = false
    // Async token count calculation task (for throttling/off-main work)
    private var tokenCalcTask: Task<Void, Never>? = nil

    private var api: ChatGPTAPI
    private var conv: GPTConversation
    private let encoder = GPTEncoder()
    @Published var configHint: String? = nil
    private struct APISendConfig { let provider: String; let model: String; let baseURL: String; let keyMasked: String; let withContext: Bool; let systemPromptLen: Int; let convId: UUID; let isAccount: Bool }
    private var lastConfig: APISendConfig? = nil

    init(conversation: GPTConversation) {
        self.conv = conversation
        let resolved = Self.resolveAPI(for: conversation)
        self.api = resolved.api
        self.lastConfig = resolved.cfg
        self.configHint = resolved.hint
        self.modelLabel = Self.label(for: resolved.cfg)
        Task { await loadHistory() }
    }

    func updateConversation(_ next: GPTConversation) {
        let convChanged = next.id != self.conv.id
        self.conv = next
        let resolved = Self.resolveAPI(for: next)
        self.api = resolved.api
        self.lastConfig = resolved.cfg
        self.configHint = resolved.hint
        self.modelLabel = Self.label(for: resolved.cfg)
        // Only reload messages when switching to a different bot
        if convChanged {
            Task { await loadHistory() }
        }
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
        if let url = URL(string: "https://macaify.com/pricing") { NSWorkspace.shared.open(url) }
    }

    private static func computeHint(for conv: GPTConversation, cfg: APISendConfig) -> String? {
        var hints: [String] = []
        if conv.modelSource == "instance" {
            if cfg.keyMasked.isEmpty { hints.append("该模型实例未配置 Token") }
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
            provider = inst.provider
            baseURL = inst.baseURL
            key = ProviderStore.shared.token(for: inst.id) ?? ""
        } else {
            // account/default
            let selectedModel = conv.modelId.isEmpty ? Defaults[.selectedModelId] : conv.modelId
            model = selectedModel.isEmpty ? (LLMModelsManager.shared.modelCategories.first?.models.first?.id ?? "gpt-4o-mini") : selectedModel
            provider = Defaults[.selectedProvider].isEmpty ? "openai" : Defaults[.selectedProvider]
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

    private static func label(for cfg: APISendConfig) -> String {
        if cfg.baseURL.trimmingCharacters(in: .whitespaces).isEmpty && cfg.provider == "openai" {
            return cfg.model
        } else {
            return "\(cfg.provider):\(cfg.model)"
        }
    }

    @MainActor
    func loadHistory(limit: Int = 80) async {
        // 当准备开启临时会话时，不要回填旧会话历史，避免视觉上与上一会话混在一起
        if pendingNewSession {
            messages = []
            allMessages = []
            api.history = []
            tokenHint = ""
            return
        }
        messages = []
        error = nil
        // Ensure at least one session exists and messages are assigned
        PersistenceController.shared.ensureDefaultSession(conversation: conv)
        // Load sessions (viewContext)
        let allSess = PersistenceController.shared.loadSessions(conversation: conv)
        let sess = allSess.filter { !$0.archived }
        self.sessionIDs = sess.map { $0.objectID }
        self.sessions = []
        self.allMessages = []
        // Build sessions info and default select last
        if sess.isEmpty {
            self.sessions = [SessionInfo(start: 0, end: 0, title: "新会话")]
            self.selectedSession = 0
            self.messages = []
            api.history = []
            return
        }
        // Fetch messages for selected session
        if selectedSession >= sess.count { selectedSession = max(0, sess.count - 1) }
        let target = sess[selectedSession]
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
            self.messages = rows.flatMap { [ChatMessage(sender: .user, text: $0.0), ChatMessage(sender: .assistant, text: $0.1)] }
            self.allMessages = self.messages
            self.sessions = sess.map { SessionInfo(start: 0, end: self.messages.count, title: $0.title) }
            applySelectedSession()
        } catch {
            self.messages = []
            self.sessions = sess.map { SessionInfo(start: 0, end: 0, title: $0.title) }
        }
    }

    private func sessionTitle(in arr: [ChatMessage], start: Int, end: Int) -> String {
        let snippet = arr[start..<end].first(where: { $0.sender == .user })?.text ?? ""
        if snippet.isEmpty { return "新会话" }
        let trimmed = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count > 24 ? String(trimmed.prefix(24)) + "…" : trimmed
    }

    @MainActor
    func selectSession(_ index: Int) {
        guard index >= 0, index < sessions.count else { return }
        selectedSession = index
        Task { await loadHistory() }
    }

    // 临时会话状态下，允许用户切换到已保存的某个会话
    @MainActor
    func selectExistingSessionWhilePending(_ index: Int) {
        pendingNewSession = false
        selectSession(index)
    }

    private func applySelectedSession() {
        guard !sessions.isEmpty else {
            messages = []
            api.history = []
            tokenHint = ""
            return
        }
        api.history = messages.compactMap { m in
            switch m.sender { case .user: return Message(role: "user", content: m.text)
            case .assistant: return Message(role: "assistant", content: m.text) }
        }
        updateTokenHint(includingInput: input)
    }

    @MainActor
    func send() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        // 首次发送时，如果是临时会话则立即实体化，确保会话栏与消息区域状态同步
        ensureSessionReady()
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
        allMessages.append(.init(sender: .user, text: text))
        if !sessions.isEmpty { sessions[selectedSession].end = allMessages.count }
        updateTokenHint(includingInput: "")
        messages.append(.init(sender: .assistant, text: "", isStreaming: true))
        allMessages.append(.init(sender: .assistant, text: "", isStreaming: true))
        do {
            // Inject context into system prompt while sending (temporary override)
            let originalPrompt = api.systemPrompt
            if let suffix = makeSystemContextSuffix() {
                api.systemPrompt = originalPrompt + "\n\n" + "<context> is the context this chat session is based on." + "\n" + suffix
            }
            defer { api.systemPrompt = originalPrompt }
            let stream = try await api.chatsStream(text: text)
            var buffer = ""
            for try await chunk in stream {
                let delta = chunk.choices.first?.delta.content ?? ""
                guard !delta.isEmpty else { continue }
                buffer += delta
                if let idx = messages.lastIndex(where: { $0.isStreaming }) { messages[idx].text = buffer }
                if let idx = allMessages.lastIndex(where: { $0.isStreaming }) { allMessages[idx].text = buffer }
            }
            if let idx = messages.lastIndex(where: { $0.isStreaming }) { messages[idx].isStreaming = false }
            if let idx = allMessages.lastIndex(where: { $0.isStreaming }) { allMessages[idx].isStreaming = false }
            persist(user: text, assistant: buffer)
        } catch {
            // Print for debugging visibility
            print("[Chat] stream error:", error)
            if let idx = messages.lastIndex(where: { $0.isStreaming }) { messages.remove(at: idx) }
            if let idx = allMessages.lastIndex(where: { $0.isStreaming }) { allMessages.remove(at: idx) }
            let message: String
            if let apiErr = error as? ChatGPTAPI.ChatAPIError {
                message = apiErr.localizedDescription
                switch apiErr {
                case .planNotAllowed, .quotaExceeded, .trialExpired:
                    setError(message, primaryTitle: "升级", secondaryTitle: "切换默认模型", primary: { [weak self] in self?.openPricing() }, secondary: { [weak self] in self?.switchToAccountDefault() })
                case .unauthorized, .notLoggedIn:
                    setError(message, primaryTitle: "去登录", secondaryTitle: nil, primary: {
                        if #available(macOS 13.0, *) { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) }
                    })
                default:
                    setError(message)
                }
            } else {
                message = "Error: \(error.localizedDescription)"
                setError(message)
            }
            messages.append(.init(sender: .assistant, text: message))
            allMessages.append(.init(sender: .assistant, text: message))
        }
        if !sessions.isEmpty { sessions[selectedSession].end = allMessages.count }
        isSending = false
        if !contextPinned {
            contextSnippet = nil
            persistContextToCurrentSession()
        }
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
    func generateTitleForSession(idx: Int) async {
        guard idx >= 0, idx < sessions.count, idx < sessionIDs.count else { return }
        // Fetch messages from Core Data for the target session
        let container = PersistenceController.shared.container
        let targetID = sessionIDs[idx]
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
                renameSession(idx: idx, to: newTitle)
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
        allMessages.append(.init(sender: .assistant, text: "", isStreaming: true))
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
                if let idx = allMessages.lastIndex(where: { $0.isStreaming }) { allMessages[idx].text = buffer }
            }
            if let idx = messages.lastIndex(where: { $0.isStreaming }) { messages[idx].isStreaming = false }
            if let idx = allMessages.lastIndex(where: { $0.isStreaming }) { allMessages[idx].isStreaming = false }
            persist(user: lastUser, assistant: buffer)
        } catch {
            print("[Chat] regenerate error:", error)
            if let idx = messages.lastIndex(where: { $0.isStreaming }) { messages.remove(at: idx) }
            if let idx = allMessages.lastIndex(where: { $0.isStreaming }) { allMessages.remove(at: idx) }
            let message: String
            if let apiErr = error as? ChatGPTAPI.ChatAPIError {
                message = apiErr.localizedDescription
                switch apiErr {
                case .planNotAllowed, .quotaExceeded, .trialExpired:
                    setError(message, primaryTitle: "升级", secondaryTitle: "切换默认模型", primary: { [weak self] in self?.openPricing() }, secondary: { [weak self] in self?.switchToAccountDefault() })
                case .unauthorized, .notLoggedIn:
                    setError(message, primaryTitle: "去登录", secondaryTitle: nil, primary: {
                        if #available(macOS 13.0, *) { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) }
                    })
                default:
                    setError(message)
                }
            } else {
                message = "Error: \(error.localizedDescription)"
                setError(message)
            }
            messages.append(.init(sender: .assistant, text: message))
            allMessages.append(.init(sender: .assistant, text: message))
        }
        if !sessions.isEmpty { sessions[selectedSession].end = allMessages.count }
        isSending = false
    }

    // Start a new session lazily (不立即持久化，会在首次发送时创建)
    @MainActor
    func startNewSession() {
        pendingNewSession = true
        messages.removeAll()
        allMessages.removeAll()
        api.history = []
        tokenHint = ""
    }

    private func ensureSessionReady() {
        guard pendingNewSession || sessions.isEmpty || selectedSession >= sessionIDs.count else { return }
        if let created = PersistenceController.shared.createSession(conversation: conv, title: "新会话") {
            // Persist current context into the new session
            created.contextSnippet = (contextSnippet ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            created.contextSourceAppName = (contextSourceAppName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            created.contextSourceBundleId = (contextSourceBundleId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            created.updatedAt = Date()
            do { try created.managedObjectContext?.save() } catch { print("save session context error:", error) }
            let sess = PersistenceController.shared.loadSessions(conversation: conv).filter { !$0.archived }
            sessionIDs = sess.map { $0.objectID }
            sessions = sess.map { SessionInfo(start: 0, end: 0, title: $0.title) }
            selectedSession = 0
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

    // Persist current context fields into the selected session (if available and not pending)
    private func persistContextToCurrentSession() {
        guard !pendingNewSession, selectedSession < sessionIDs.count else { return }
        let ctx = PersistenceController.shared.container.viewContext
        let oid = sessionIDs[selectedSession]
        if let s = try? ctx.existingObject(with: oid) as? GPTSession {
            s.contextSnippet = (contextSnippet ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            s.contextSourceAppName = (contextSourceAppName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            s.contextSourceBundleId = (contextSourceBundleId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            s.updatedAt = Date()
            do { try ctx.save() } catch { print("persistContext error:", error) }
        }
    }

    @MainActor
    func renameSession(idx: Int, to title: String) {
        guard idx >= 0, idx < sessionIDs.count else { return }
        let oid = sessionIDs[idx]
        let ctx = PersistenceController.shared.container.viewContext
        if let s = try? ctx.existingObject(with: oid) as? GPTSession {
            PersistenceController.shared.rename(session: s, title: title)
            if idx < sessions.count { sessions[idx].title = title }
        }
    }

    @MainActor
    func archiveSession(idx: Int, archived: Bool) {
        guard idx >= 0, idx < sessionIDs.count else { return }
        let oid = sessionIDs[idx]
        let ctx = PersistenceController.shared.container.viewContext
        if let s = try? ctx.existingObject(with: oid) as? GPTSession {
            PersistenceController.shared.archive(session: s, archived: archived)
            Task { await loadHistory() }
        }
    }

    @MainActor
    func deleteSession(idx: Int) {
        guard idx >= 0, idx < sessionIDs.count else { return }
        let oid = sessionIDs[idx]
        let ctx = PersistenceController.shared.container.viewContext
        if let s = try? ctx.existingObject(with: oid) as? GPTSession {
            PersistenceController.shared.delete(session: s, moveToDefault: true)
            // adjust selection to previous index
            selectedSession = max(0, selectedSession - 1)
            Task { await loadHistory() }
        }
    }

    private func persist(user: String, assistant: String) {
        guard !assistant.isEmpty else { return }
        ensureSessionReady()
        let mc = conv.managedObjectContext ?? PersistenceController.shared.container.viewContext
        let answer = GPTAnswer(role: "user", prompt: user, response: assistant, parentId: conv.own.last?.uuid, context: mc)
        // Assign current session if available
        if selectedSession < sessionIDs.count {
            if let s = try? mc.existingObject(with: sessionIDs[selectedSession]) as? GPTSession {
                answer.session = s
                s.updatedAt = Date()
            }
        }
        conv.addAnswer(answer: answer)
        conv.timestamp = Date()
        conv.save()
    }

    @MainActor
    func clearHistory() {
        PersistenceController.shared.clearAnswers(conversation: conv)
        messages.removeAll()
        api.deleteHistoryList()
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

    var body: some View {
        NavigationSplitView {
            Sidebar(store: store)
        } detail: {
            if let current = store.selected {
                ChatDetailView(viewModel: chatVM, bot: current, openBotSettings: { showSettings = true }, store: store)
            } else {
                VStack { Spacer(); Text("No Bot Selected").foregroundStyle(.secondary); Spacer() }
            }
        }
        .navigationSplitViewStyle(.balanced)
        // Register the NSWindow that hosts the main chat UI
        .background(HostingWindowFinder { window in
            WindowBridge.shared.mainWindow = window
            WindowBridge.shared.openingMain = false
        })
        .onAppear { if let s = store.selected { chatVM.updateConversation(s) } }
        .onChange(of: store.selectedID) { _ in if let s = store.selected { chatVM.updateConversation(s) } }
        .onChange(of: store.bots) { _ in if let s = store.selected { chatVM.updateConversation(s) } }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            if let s = store.selected { chatVM.updateConversation(s) }
        }
        .onChange(of: chatVM.input) { newValue in
            chatVM.updateTokenHint(includingInput: newValue)
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("QuickChatSelectedText"))) { note in
            guard let info = note.userInfo as? [String: Any] else { return }
            let convIdStr = (info["convId"] as? String) ?? ""
            let textRaw = (info["text"] as? String) ?? ""
            let srcApp = (info["sourceAppName"] as? String) ?? ""
            let srcBundle = (info["sourceBundleId"] as? String) ?? ""
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
            let convIdStr = (info["convId"] as? String) ?? ""
            let textRaw = (info["text"] as? String) ?? ""
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
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button { store.addBot() } label: { Label("New Bot", systemImage: "plus") }
        }
        ToolbarItem(placement: .principal) { Text(store.selected?.name.isEmpty == false ? store.selected!.name : "Bots").font(.headline) }
        ToolbarItemGroup(placement: .automatic) {
            if let sel = store.selected {
                Toggle(isOn: Binding(get: { sel.withContext }, set: { v in sel.withContext = v; sel.save(); chatVM.updateConversation(sel) })) {
                    Image(systemName: sel.withContext ? "arrow.triangle.2.circlepath" : "arrow.triangle.2.circlepath.circle")
                }.toggleStyle(.button).help("Toggle Context")
            }
            Button { chatVM.clearHistory() } label: { Label("Clear", systemImage: "trash") }
                .disabled(store.selected == nil)
                .keyboardShortcut(.init("d"), modifiers: .command)
            Button { showSettings = true } label: { Label("Bot Settings", systemImage: "gear") }.disabled(store.selected == nil)
        }
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
    var body: some View {
        List(selection: Binding(get: { store.selectedID }, set: { store.selectedID = $0 })) {
            ForEach(store.bots, id: \.id) { bot in
                HStack(spacing: 8) {
                    Text(bot.icon.isEmpty ? "🤖" : bot.icon)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(bot.name.isEmpty ? "Untitled" : bot.name)
                        if !bot.prompt.isEmpty { Text(bot.prompt).lineLimit(1).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                .tag(bot.id as UUID?)
                .contextMenu { Button(role: .destructive) { store.deleteBot(bot) } label: { Label("Delete", systemImage: "trash") } }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Bots")
        .toolbar { ToolbarItem(placement: .automatic) { Button { store.addBot() } label: { Label("Add", systemImage: "plus") } } }
    }
}

struct ChatDetailView: View {
    @ObservedObject var viewModel: ChatSessionViewModel
    let bot: GPTConversation
    var openBotSettings: () -> Void = {}
    var store: BotStore? = nil
    // Model picker moved to the input bar; remove top-of-window variant
    // session picker state removed (unused)
    @State private var renamingSessionIndex: Int? = nil
    @State private var renameBuffer: String = ""
    @State private var pendingDeleteIndex: Int? = nil
    @State private var showDeleteConfirm: Bool = false
    @State private var contextCollapsed: Bool = true
    // Quick actions palette state
    @State private var showQuickActions: Bool = false
    @State private var actionsMode: QuickActions.Mode = .root
    // AnchoredPopover demo toggles (moved to InputBar)
    var body: some View {
        VStack(spacing: 0) {
            // Sessions bar
            if !viewModel.sessions.isEmpty {
                HStack(spacing: 8) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(viewModel.sessions.enumerated()), id: \.offset) { idx, info in
                                if renamingSessionIndex == idx {
                                    HStack(spacing: 6) {
                                        Image(systemName: "pencil")
                                        TextField("会话标题", text: $renameBuffer, onCommit: {
                                            let t = renameBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                                            viewModel.renameSession(idx: idx, to: t)
                                            renamingSessionIndex = nil
                                        })
                                        .textFieldStyle(.roundedBorder)
                                        Button("完成") {
                                            let t = renameBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                                            viewModel.renameSession(idx: idx, to: t)
                                            renamingSessionIndex = nil
                                        }
                                    }
                                    .font(.caption)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.accentColor.opacity(0.08))
                                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.25)))
                                    )
                                } else {
                                    Button {
                                        if viewModel.pendingNewSession {
                                            viewModel.selectExistingSessionWhilePending(idx)
                                        } else {
                                            viewModel.selectSession(idx)
                                        }
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: (!viewModel.pendingNewSession && idx == viewModel.selectedSession) ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
                                            Text(info.title).lineLimit(1)
                                        }
                                        .font(.caption)
                                        .padding(.horizontal, 10).padding(.vertical, 6)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill((!viewModel.pendingNewSession && idx == viewModel.selectedSession) ? Color.accentColor.opacity(0.12) : Color.clear)
                                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.25)))
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .onTapGesture(count: 2) {
                                        renamingSessionIndex = idx
                                        renameBuffer = info.title
                                    }
                                    .onLongPressGesture(minimumDuration: 0.35) {
                                        renamingSessionIndex = idx
                                        renameBuffer = info.title
                                    }
                                    .contextMenu {
                                        Button("重命名", systemImage: "pencil") {
                                            renamingSessionIndex = idx
                                            renameBuffer = info.title
                                        }
                                        Button("生成标题", systemImage: "textformat") {
                                            Task { await viewModel.generateTitleForSession(idx: idx) }
                                        }
                                        Divider()
                                        Button("归档", systemImage: "archivebox") {
                                            viewModel.archiveSession(idx: idx, archived: true)
                                        }
                                        Button("删除会话…", systemImage: "trash", role: .destructive) {
                                            pendingDeleteIndex = idx
                                            showDeleteConfirm = true
                                        }
                                    }
                                }
                            }
                            // 临时新会话标记（未持久化）
                            if viewModel.pendingNewSession {
                                HStack(spacing: 6) {
                                    Image(systemName: "sparkles")
                                    Text("新会话（未开始）")
                                }
                                .font(.caption)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.accentColor.opacity(0.12))
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor.opacity(0.25)))
                                )
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                    Button {
                        viewModel.startNewSession()
                    } label: {
                        Label("新会话", systemImage: "plus")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.init("n"), modifiers: .command)
                    .padding(.trailing, 12)
                }
                .padding(.top, 8)
                .padding(.bottom, 6)
            }
            if let raw = viewModel.contextSnippet, !raw.isEmpty {
                // 兼容旧格式：“【来源：xxx】\n正文”
                let parsed: (src: String?, body: String) = {
                    let s = raw
                    if s.hasPrefix("【来源："), let r = s.firstIndex(of: "】") {
                        let src = String(s[s.index(s.startIndex, offsetBy: 3)..<r])
                        let bodyStart = s.index(after: r)
                        let body = s[bodyStart...].trimmingCharacters(in: .whitespacesAndNewlines)
                        return (src.isEmpty ? nil : src, body)
                    }
                    return (nil, s)
                }()
                let sourceName = viewModel.contextSourceAppName ?? parsed.src
                let body = parsed.body

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        // 用样式区分来源，不出现“来源”二字；优先展示真实 App 图标
                        if let name = sourceName, !name.isEmpty {
                            HStack(spacing: 6) {
                                sourceAppIcon(bundleId: viewModel.contextSourceBundleId)
                                Text(name)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(body, forType: .string)
                        } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.plain)
                        Button { withAnimation { contextCollapsed.toggle() } } label: {
                            Image(systemName: contextCollapsed ? "chevron.down" : "chevron.up")
                        }
                        .buttonStyle(.plain)
                    }
                    if contextCollapsed {
                        Text(body)
                            .font(.caption)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView(.vertical) {
                            Text(body)
                                .font(.caption)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 120)
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.15), lineWidth: 1))
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }
            // Model picker moved next to the composer controls
            if !viewModel.tokenHint.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "gauge.medium")
                    Text(viewModel.tokenHint).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)
            }
            // Config guidance banner
            if let hint = viewModel.configHint {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle.fill").foregroundColor(.white)
                    Text(hint).foregroundColor(.white)
                    Spacer()
                    Button("Bot 设置") { openBotSettings() }
                        .buttonStyle(.borderedProminent)
                        .tint(.white)
                        .foregroundColor(.blue)
                        .keyboardShortcut(.init("e"), modifiers: .command)
                    Button("打开设置") {
                        // Choose tab: providers for instance, account for default
                        let tab = (bot.modelSource == "instance") ? SettingsTab.providers.rawValue : SettingsTab.account.rawValue
                        UserDefaults.standard.set(tab, forKey: "settings.selectedTab")
                        if #available(macOS 13.0, *) {
                            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                        }
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.white)
                }
                .padding(10)
                .background(Color.blue.opacity(0.85))
            }
            // Inline error banner
            if let error = viewModel.error, !error.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.white)
                    Text(error).foregroundColor(.white).lineLimit(2)
                    Spacer()
                    if let secondary = viewModel.errorSecondaryTitle {
                        Button(secondary) {
                            // fire and clear
                            viewModel.performSecondaryErrorAction()
                        }.buttonStyle(.bordered)
                            .tint(.white)
                            .foregroundColor(.red)
                    }
                    if let primary = viewModel.errorPrimaryTitle {
                        Button(primary) {
                            viewModel.performPrimaryErrorAction()
                        }.buttonStyle(.borderedProminent)
                            .tint(.white)
                            .foregroundColor(.red)
                    }
                    Button(action: { withAnimation { viewModel.error = nil } }) {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.white.opacity(0.9))
                    }.buttonStyle(.plain)
                }
                .padding(8)
                .background(Color.red.opacity(0.85))
            }
            ScrollViewReader { proxy in
                ScrollView {
                    messagesList
                }
                .onChange(of: viewModel.messages.count) { _ in
                    if let last = viewModel.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            Divider()
            InputBar(viewModel: viewModel, bot: bot, store: store, openQuickActions: {
                actionsMode = .root
                withAnimation(.spring(response: 0.2, dampingFraction: 0.9)) { showQuickActions = true }
            }, openBotSettings: {
                openBotSettings()
            })
                .padding(12)
        }
        .navigationTitle(bot.name.isEmpty ? "Chat" : bot.name)
        // 若是临时会话，给标题加个“(未开始)”提示，避免误解仍在上一会话
        .navigationSubtitle(viewModel.pendingNewSession ? "未开始的临时会话" : "")
        .onAppear { viewModel.updateConversation(bot) }
        .onChange(of: bot.id) { _ in
            // 切换到其他 Agent 时，关闭快捷面板
            if showQuickActions { showQuickActions = false }
        }
        .alert("确认删除会话？", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) { pendingDeleteIndex = nil }
            Button("删除", role: .destructive) {
                if let i = pendingDeleteIndex { viewModel.deleteSession(idx: i) }
                pendingDeleteIndex = nil
            }
        } message: {
            Text("删除后该会话的消息将移入默认会话。")
        }
        // Keyboard shortcuts
        .onKeyPressed { event in
            guard let action = event.action else { return false }
            let mods = event.modifierFlags
            // 当快捷动作面板显示时，不拦截按键，交给面板处理；仅处理 Esc 关闭面板
            if showQuickActions {
                if action == .escape { withAnimation { showQuickActions = false } ; return true }
                return false
            }
            switch action {
            case .enter, .keypadEnter:
                // ↩ 发送；⇧↩ 换行（保留本地处理）；⌘↩ 由 .keyboardShortcut 处理
                if mods.contains(.shift) && !mods.contains(.command) {
                    viewModel.input += "\n"
                    return true
                }
                Task { await viewModel.send() }
                return true
            case .escape:
                // 不再隐藏整个 App，由面板或默认处理
                return false
            case .c where mods.contains(.option) && mods.contains(.shift):
                viewModel.copyLastReply()
                return true
            case .v where mods.contains(.option) && mods.contains(.shift):
                viewModel.useLastReply()
                return true
            case .period where mods.contains(.command):
                viewModel.stopStreaming()
                return true
            default:
                return false
            }
        }
        // Hidden shortcut host for common actions, so shortcuts work reliably (even with the palette open)
        .overlay(alignment: .topLeading) {
            Group {
                // Regenerate: ⌘R
                Button("") {
                    if showQuickActions { withAnimation(.easeOut(duration: 0.15)) { showQuickActions = false } }
                    Task { await viewModel.regenerateLast() }
                }
                    .keyboardShortcut(.init("r"), modifiers: .command)
                    .opacity(0.001)
                    .frame(width: 0, height: 0)
                // Clear: ⌘D (in addition to toolbar binding)
                Button("") {
                    if showQuickActions { withAnimation(.easeOut(duration: 0.15)) { showQuickActions = false } }
                    viewModel.clearHistory()
                }
                    .keyboardShortcut(.init("d"), modifiers: .command)
                    .opacity(0.001)
                    .frame(width: 0, height: 0)
                // New session: ⌘N
                Button("") {
                    if showQuickActions { withAnimation(.easeOut(duration: 0.15)) { showQuickActions = false } }
                    viewModel.startNewSession()
                }
                    .keyboardShortcut(.init("n"), modifiers: .command)
                    .opacity(0.001)
                    .frame(width: 0, height: 0)
                // Copy last reply: ⌥⇧C
                Button("") {
                    if showQuickActions { withAnimation(.easeOut(duration: 0.15)) { showQuickActions = false } }
                    viewModel.copyLastReply()
                }
                    .keyboardShortcut(.init("c"), modifiers: [.option, .shift])
                    .opacity(0.001)
                    .frame(width: 0, height: 0)
                // Use last reply: ⌥⇧V
                Button("") {
                    if showQuickActions { withAnimation(.easeOut(duration: 0.15)) { showQuickActions = false } }
                    viewModel.useLastReply()
                }
                    .keyboardShortcut(.init("v"), modifiers: [.option, .shift])
                    .opacity(0.001)
                    .frame(width: 0, height: 0)
                // Toggle quick actions: ⌘K
                Button("") {
                    actionsMode = .root
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.9)) { showQuickActions.toggle() }
                }
                .keyboardShortcut(.init("k"), modifiers: .command)
                .opacity(0.001)
                .frame(width: 0, height: 0)
            }
        }
        // Quick Actions overlay attached at the view root, so遮罩覆盖全窗口
        .overlay {
            if showQuickActions {
                QuickActions(isPresented: $showQuickActions, mode: actionsMode, viewModel: viewModel, bot: bot, store: store)
            }
        }
    }

    // MARK: - Helpers
    @ViewBuilder
    private func sourceAppIcon(bundleId: String?) -> some View {
        if let bid = bundleId, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 14, height: 14)
                .cornerRadius(3)
        } else {
            Image(systemName: "app.fill")
                .font(.system(size: 12, weight: .semibold))
        }
}

// MARK: - Message rendering (Markdown when available)
    @ViewBuilder
    private func messageBody(for msg: ChatSessionViewModel.ChatMessage) -> some View {
        #if canImport(MarkdownUI)
        // Avoid heavy Markdown layout while streaming; switch to Markdown after complete
        // if msg.isStreaming {
        //     Text(msg.text)
        //         .textSelection(.enabled)
        //         .font(.body)
        // } else {
            MarkdownView(msg.text)
                .textSelection(.enabled)
                .tint(.accentColor)
        // }
        #else
        Text(msg.text)
            .textSelection(.enabled)
            .font(.body)
        #endif
    }

    // MARK: - Messages list with SelectionArea when available
    @ViewBuilder
    private var messagesList: some View {
        listCore
    }

    @ViewBuilder
    private var listCore: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(viewModel.messages) { msg in
                HStack(alignment: .top) {
                    if msg.sender == .assistant { Spacer(minLength: 0) }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text(msg.sender == .user ? "You" : "Assistant").font(.caption).foregroundStyle(.secondary)
                            if let via = msg.viaAgent { Text("via \(via)").font(.caption2).foregroundStyle(.secondary) }
                        }
                        messageBody(for: msg)
                    }
                    .padding(10)
                    .background(msg.sender == .user ? Color.blue.opacity(0.08) : Color.gray.opacity(0.08))
                    .cornerRadius(10)
                    if msg.sender == .user { Spacer(minLength: 0) }
                }
                .id(msg.id)
                .contextMenu {
                    Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(msg.text, forType: .string) } label: { Label("复制", systemImage: "doc.on.doc") }
                    Button {
                        let md = "```\n\(msg.text)\n```"
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(md, forType: .string)
                    } label: { Label("复制为 Markdown", systemImage: "doc.on.doc.fill") }
                    Button { viewModel.injectContext(msg.text) } label: { Label("用作上下文", systemImage: "text.append") }
                    if msg.sender == .user {
                        Divider()
                        Button("设为 System Prompt 并重新生成", systemImage: "slider.horizontal.3") {
                            Task { await viewModel.regenerateWithSystemPromptOverride(msg.text) }
                        }
                    }
                    if let store {
                        Divider()
                        Menu("用其他 Agent 运行…", content: {
                            ForEach(store.bots, id: \.id) { other in
                                if other.id != bot.id {
                                    Button(other.name.isEmpty ? other.id.uuidString : other.name) {
                                        Task { await viewModel.runWithAgent(agent: other, using: msg.sender == .user ? msg.text : nil) }
                                    }
                                }
                            }
                        })
                        Menu("用其他 Agent 新开会话…", content: {
                            ForEach(store.bots, id: \.id) { other in
                                if other.id != bot.id {
                                    Button(other.name.isEmpty ? other.id.uuidString : other.name) {
                                        store.selectedID = other.id
                                        if let chosen = store.selected {
                                            viewModel.input = msg.sender == .user ? msg.text : (viewModel.input.isEmpty ? (viewModel.messages.last(where: { $0.sender == .user })?.text ?? "") : viewModel.input)
                                            viewModel.updateConversation(chosen)
                                        }
                                    }
                                }
                            }
                        })
                    }
                }
            }
        }
        .padding(12)
    }
}

// MARK: - Input Bar with shortcuts and Quick Actions
private struct InputBar: View {
    @ObservedObject var viewModel: ChatSessionViewModel
    let bot: GPTConversation
    var store: BotStore?
    var openQuickActions: () -> Void
    var openBotSettings: () -> Void
    @State private var inputHeight: CGFloat = ChatTokens.controlHeight
    // AnchoredPopover test state (scoped to input bar)
    // Removed test toggles for AnchoredPopover demo
    @State private var showSessionPicker: Bool = false
    @State private var sessionPickerResetKey: Int = 0

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                GrowingTextView(
                    placeholder: "发送消息…",
                    text: $viewModel.input,
                    measuredHeight: $inputHeight,
                    minHeight: ChatTokens.controlHeight,
                    maxHeight: 140
                )
                .frame(height: inputHeight)
                .animation(.easeInOut(duration: 0.16), value: inputHeight)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2)))
                if viewModel.isSending {
                    Button(action: { viewModel.stopStreaming() }) {
                        Image(systemName: "stop.circle.fill")
                            .foregroundColor(.red)
                    }
                    .help("停止生成 ⌘.")
                    .keyboardShortcut(.init("."), modifiers: .command)
                } else {
                    Button(action: { Task { await viewModel.send() } }) {
                        Image(systemName: "paperplane")
                    }
                    .help("发送 ↩ / ⌘↩，换行 ⇧↩")
                    .disabled(viewModel.isSending)
                    .keyboardShortcut(.return, modifiers: .command)
                }
                Button(action: { openQuickActions() }) {
                    Text("操作 ⌘K")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 4)
                }
                .help("打开动作 ⌘K")
                .keyboardShortcut(.init("k"), modifiers: .command)
            }

            // Session-scoped model selector (AnchoredPopover), default opens above
            HStack(alignment: .center) {
                Button(action: { showSessionPicker.toggle() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.horizontal.circle")
                        Text(viewModel.modelLabel.isEmpty ? String(localized: "选择模型") : viewModel.modelLabel)
                            .lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .background(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.25)))
                .background(
                    AnchoredPopover(isPresented: $showSessionPicker, preferredDirection: .above) {
                        QuickModelPickerView(
                            onDismiss: { showSessionPicker = false },
                            resetKey: sessionPickerResetKey,
                            isInstanceSelected: { inst in bot.modelSource == "instance" && bot.modelInstanceId == inst.id },
                            isAccountSelected: { _, modelId in bot.modelSource == "account" && bot.modelId == modelId },
                            onPickInstance: { inst in
                                var updated = bot
                                updated.modelSource = "instance"
                                updated.modelInstanceId = inst.id
                                updated.modelId = ""
                                updated.save()
                                viewModel.updateConversation(updated)
                            },
                            onPickRemote: { item in
                                var updated = bot
                                updated.modelSource = "account"
                                updated.modelId = item.slug
                                updated.modelInstanceId = ""
                                updated.save()
                                viewModel.updateConversation(updated)
                            }
                        )
                    }
                )
                .onChange(of: showSessionPicker) { open in
                    if open { sessionPickerResetKey &+= 1 }
                }

                Text("发送 ↩ / ⌘↩ · 换行 ⇧↩ · 动作 ⌘K")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            // Removed AnchoredPopover test buttons
        }
    }

    private func applySelectedModelToConversation() {
        var updated = bot
        let source = Defaults[.defaultSource]
        if source == "provider" {
            updated.modelSource = "instance"
            updated.modelInstanceId = Defaults[.selectedProviderInstanceId]
            updated.modelId = ""
        } else {
            updated.modelSource = "account"
            updated.modelId = Defaults[.selectedModelId]
            updated.modelInstanceId = ""
        }
        updated.save()
        viewModel.updateConversation(updated)
    }
    
}

// Helper已移除：改为在 ChatDetailView 顶层承载面板，使遮罩覆盖全窗口

// MARK: - Raycast‑style quick actions palette
private struct QuickActions: View {
    enum Mode { case root, runWithAgent, newChatWithAgent }
    @Binding var isPresented: Bool
    var mode: Mode
    @ObservedObject var viewModel: ChatSessionViewModel
    let bot: GPTConversation
    var store: BotStore?

    @State private var query: String = ""
    @State private var selection: Int = 0
    @FocusState private var focusSearch: Bool
    @State private var currentMode: Mode = .root

    struct Item: Identifiable {
        let id = UUID()
        var title: String
        var subtitle: String? = nil
        var systemImage: String
        var keyHint: String? = nil
        enum Group { case message, clipboard, agent, session, danger }
        var group: Group
        // For items that should open a sublist via →
        var opensSubmenu: Mode? = nil
        var action: () -> Void
    }

    private var baseItems: [Item] {
        var arr: [Item] = []
        if !viewModel.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            arr.append(Item(title: "发送", systemImage: "paperplane", keyHint: "↩", group: .message, action: { Task { await viewModel.send() }; dismiss() }))
        }
        arr.append(Item(title: "重新生成", systemImage: "arrow.clockwise", keyHint: "⌘R", group: .message, action: { Task { await viewModel.regenerateLast() }; dismiss() }))
        arr.append(Item(title: "复制最后回答", systemImage: "doc.on.doc", keyHint: "⌥⇧C", group: .clipboard, action: { viewModel.copyLastReply(); dismiss() }))
        arr.append(Item(title: "粘贴到前台应用", systemImage: "rectangle.and.text.magnifyingglass", keyHint: "⌥⇧V", group: .clipboard, action: { viewModel.useLastReply(); dismiss() }))
        arr.append(Item(title: "用其他 Agent 运行…", systemImage: "bolt.horizontal.circle", keyHint: "→", group: .agent, opensSubmenu: .runWithAgent, action: { switchMode(.runWithAgent) }))
        arr.append(Item(title: "用其他 Agent 新开会话…", systemImage: "arrow.uturn.forward", keyHint: "→", group: .agent, opensSubmenu: .newChatWithAgent, action: { switchMode(.newChatWithAgent) }))
        arr.append(Item(title: "清空聊天", systemImage: "trash", keyHint: "⌘D", group: .danger, action: { viewModel.clearHistory(); dismiss() }))
        return arr
    }

    private var agentItems: [Item] {
        let list = (store?.bots ?? []).filter { $0.id != bot.id }
        switch currentMode {
        case .runWithAgent:
            return list.map { other in
                Item(title: other.name.isEmpty ? other.id.uuidString : other.name, subtitle: "运行当前输入/最近一次提问", systemImage: "bolt.fill", keyHint: nil, group: .agent, action: {
                    Task { await viewModel.runWithAgent(agent: other, using: viewModel.input.isEmpty ? nil : viewModel.input) }
                    dismiss()
                })
            }
        case .newChatWithAgent:
            return list.map { other in
                Item(title: other.name.isEmpty ? other.id.uuidString : other.name, subtitle: "切换到该 Agent 并开始新会话", systemImage: "arrow.uturn.right.circle.fill", keyHint: nil, group: .agent, action: {
                    if let store {
                        store.selectedID = other.id
                        if let chosen = store.selected {
                            viewModel.input = viewModel.input.isEmpty ? (viewModel.messages.last(where: { $0.sender == .user })?.text ?? "") : viewModel.input
                            viewModel.updateConversation(chosen)
                        }
                    }
                    dismiss()
                })
            }
        default:
            return []
        }
    }

    private var items: [Item] {
        let source = (currentMode == .root) ? baseItems : agentItems
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return source }
        let q = query.lowercased()
        return source.filter { $0.title.lowercased().contains(q) || ($0.subtitle?.lowercased().contains(q) ?? false) }
    }

    private func groupTitle(_ g: Item.Group) -> String {
        switch g {
        case .message: return "消息"
        case .clipboard: return "剪贴板"
        case .agent: return "Agent"
        case .session: return "会话"
        case .danger: return "危险"
        }
    }

    var body: some View {
        ZStack {
            // 透明点击区域：不再做半透明遮罩
            Color.clear
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                    TextField("搜索动作…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .focused($focusSearch)
                        .onAppear { DispatchQueue.main.async { focusSearch = true } }
                        .onSubmit { if items.indices.contains(selection) { items[selection].action() } }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.15)))

                Divider().padding(.horizontal, 2).opacity(0.25)

                ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        if items.isEmpty {
                            Text("No actions")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 24)
                        }
                        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && currentMode != .root {
                            Text(currentMode == .runWithAgent ? "选择 Agent 运行" : "选择 Agent 新开会话")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.bottom, 2)
                        }
                        ForEach(Array(items.enumerated()), id: \.element.id) { idx, it in
                            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && currentMode == .root && (idx == 0 || items[idx-1].group != it.group) {
                                Text(groupTitle(it.group))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, idx == 0 ? 0 : 4)
                                    .padding(.bottom, 2)
                                    .padding(.horizontal, 10)
                            }
                            Button(action: { it.action() }) {
                                HStack(spacing: 10) {
                                    Image(systemName: it.systemImage)
                                        .frame(width: 16)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(it.title)
                                            .foregroundStyle(it.group == .danger ? Color.red : Color.primary)
                                        if let s = it.subtitle { Text(s).font(.caption).foregroundStyle(.secondary) }
                                    }
                                    Spacer()
                                    if let hint = it.keyHint { KeyHint(hint) }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .contentShape(RoundedRectangle(cornerRadius: 8))
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(selection == idx ? Color.accentColor.opacity(0.15) : Color.clear)
                                )
                            }
                            .buttonStyle(.plain)
                            .id(it.id)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                // 自动滚动到选中项
                .onChange(of: selection) { newValue in
                    if items.indices.contains(newValue) {
                        let target = items[newValue].id
                        withAnimation(.easeInOut(duration: 0.15)) { proxy.scrollTo(target, anchor: .center) }
                    }
                }
                }
                .frame(maxHeight: 320)
            }
            .padding(12)
            .frame(width: 420)
            .background(.regularMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.15), radius: 24, x: 0, y: 8)
            .onAppear { selection = 0; query = ""; currentMode = mode }
            .onChange(of: items.count) { _ in selection = min(selection, max(0, items.count - 1)) }
            .background(QuickActionsKeyCatcher(handle: { event in
                guard let a = event.action else { return false }
                let mods = event.modifierFlags
                // Support system shortcuts while palette is open; perform action and dismiss.
                if mods.contains(.command) {
                    switch a {
                    case .r:
                        Task { await viewModel.regenerateLast() }
                        dismiss(); return true
                    case .d:
                        viewModel.clearHistory()
                        dismiss(); return true
                    case .n:
                        viewModel.startNewSession()
                        dismiss(); return true
                    case .k:
                        dismiss(); return true
                    case .enter, .keypadEnter:
                        Task { await viewModel.send() }
                        dismiss(); return true
                    case .c:
                        if mods.contains(.option) && mods.contains(.shift) { viewModel.copyLastReply(); dismiss(); return true }
                    case .v:
                        if mods.contains(.option) && mods.contains(.shift) { viewModel.useLastReply(); dismiss(); return true }
                    default: break
                    }
                }
                switch a {
                case .upArrow:
                    selection = max(0, selection - 1); return true
                case .downArrow:
                    selection = min(max(0, items.count - 1), selection + 1); return true
                case .rightArrow:
                    if currentMode == .root, items.indices.contains(selection), let submenu = items[selection].opensSubmenu {
                        switchMode(submenu); return true
                    }
                    return false
                case .leftArrow:
                    if currentMode != .root { switchMode(.root); return true }
                    return false
                case .enter, .keypadEnter:
                    if items.indices.contains(selection) { items[selection].action() }
                    return true
                case .escape:
                    dismiss(); return true
                default:
                    return false
                }
            }))
        }
        // Remove scale from transition to avoid intermittent layout jitter of the search row
        .transition(.opacity)
    }

    private func dismiss() { withAnimation(.easeOut(duration: 0.15)) { isPresented = false } }
    private func switchMode(_ next: Mode) {
        withAnimation(.easeInOut(duration: 0.15)) {
            currentMode = next
            query = ""
            selection = 0
        }
    }
}

// A local key catcher that doesn't depend on PathManager case matching.
private struct QuickActionsKeyCatcher: NSViewRepresentable {
    var handle: (NSEvent) -> Bool
    func makeCoordinator() -> Coordinator { Coordinator(handle) }
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
    class Coordinator: NSObject {
        var monitor: Any?
        var handle: (NSEvent) -> Bool
        init(_ handle: @escaping (NSEvent)->Bool) {
            self.handle = handle
            super.init()
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
                guard let self else { return e }
                return self.handle(e) ? nil : e
            }
        }
        deinit { if let m = monitor { NSEvent.removeMonitor(m) } }
    }
}

private struct KeyHint: View { var text: String; init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.gray.opacity(0.16))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.black.opacity(0.05)))
            )
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
