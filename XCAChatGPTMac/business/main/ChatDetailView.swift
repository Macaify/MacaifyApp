//
//  ChatDetailView.swift
//  XCAChatGPT
//
//  Created by lixindong on 2025/10/27.
//

import SwiftUI
import CoreData
import BetterAuth
import Defaults
import MarkdownView

struct ChatDetailView: View {
    #if os(macOS)
    @EnvironmentObject private var authClient: BetterAuthClient
    #endif
    @ObservedObject var viewModel: ChatSessionViewModel
    let bot: GPTConversation
    @FetchRequest private var fetchedSessions: FetchedResults<GPTSession>
    var openBotSettings: () -> Void = {}
    var store: BotStore? = nil
    // Model picker moved to the input bar; remove top-of-window variant
    // session picker state removed (unused)
    @State private var renamingSessionIndex: Int? = nil
    @State private var renameBuffer: String = ""
    @State private var pendingDeleteSession: GPTSession? = nil
    @State private var showDeleteConfirm: Bool = false
    @State private var showClearConfirm: Bool = false
    @State private var contextCollapsed: Bool = true
    // Quick actions palette state
    @State private var showQuickActions: Bool = false
    @State private var actionsMode: QuickActions.Mode = .root
    // AnchoredPopover demo toggles (moved to InputBar)
    init(viewModel: ChatSessionViewModel, bot: GPTConversation, openBotSettings: @escaping () -> Void = {}, store: BotStore? = nil) {
        self._viewModel = ObservedObject(initialValue: viewModel)
        self.bot = bot
        self.openBotSettings = openBotSettings
        self.store = store
        // Keep ordering consistent with Persistence.loadSessions (latest first)
        self._fetchedSessions = FetchRequest(
            sortDescriptors: [
                NSSortDescriptor(key: "updatedAt_", ascending: false),
                NSSortDescriptor(key: "createdAt_", ascending: false)
            ],
            predicate: NSPredicate(format: "agent == %@ AND archived_ == NO", bot)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Sessions bar
            if !fetchedSessions.isEmpty || viewModel.pendingNewSession {
                HStack(spacing: 8) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            // 临时新会话标记（未持久化）放在最左侧
                            if viewModel.pendingNewSession {
                                HStack(spacing: 6) {
                                    Image(systemName: "sparkles")
                                    Text("new_session_not_started")
                                }
                                .font(.caption)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.accentColor.opacity(0.12))
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor.opacity(0.25)))
                                )
                            }
                            // Use objectID for stable identity; derive index for rename state on demand
                            ForEach(fetchedSessions, id: \.objectID) { sess in
                                let idx = fetchedSessions.firstIndex(where: { $0.objectID == sess.objectID }) ?? 0
                                if renamingSessionIndex == idx {
                                    HStack(spacing: 6) {
                                        Image(systemName: "pencil")
                                        TextField("session_title", text: $renameBuffer, onCommit: {
                                            let t = renameBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                                            viewModel.rename(session: sess, to: t)
                                            renamingSessionIndex = nil
                                        })
                                        .textFieldStyle(.roundedBorder)
                                        Button("done") {
                                            let t = renameBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                                            viewModel.rename(session: sess, to: t)
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
                                            viewModel.selectExistingSessionWhilePending(session: sess)
                                        } else {
                                            viewModel.select(session: sess)
                                        }
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: (viewModel.isSelected(session: sess)) ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
                                            Text(sess.title).lineLimit(1)
                                        }
                                        .font(.caption)
                                        .padding(.horizontal, 10).padding(.vertical, 6)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(viewModel.isSelected(session: sess) ? Color.accentColor.opacity(0.12) : Color.clear)
                                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.25)))
                                        )
                                        .contentShape(.rect)
                                        .containerShape(.rect)
                                    }
                                    .buttonStyle(.plain)
                                    .onTapGesture(count: 2) {
                                        renamingSessionIndex = idx
                                        renameBuffer = sess.title
                                    }
                                    .onLongPressGesture(minimumDuration: 0.35) {
                                        renamingSessionIndex = idx
                                        renameBuffer = sess.title
                                    }
                                    .contextMenu {
                                        Button("rename", systemImage: "pencil") {
                                            renamingSessionIndex = idx
                                            renameBuffer = sess.title
                                        }
                                        Button("generate_title", systemImage: "textformat") {
                                            Task { await viewModel.generateTitle(for: sess) }
                                        }
                                        Divider()
                                        Button("archive", systemImage: "archivebox") {
                                            viewModel.archive(session: sess, archived: true)
                                        }
                                        Button("delete_session", systemImage: "trash", role: .destructive) {
                                            pendingDeleteSession = sess
                                            showDeleteConfirm = true
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                    // Removed visible New Session button (toolbar/shortcut remains available)
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
            Button("bot_settings") { openBotSettings() }
                        .buttonStyle(.borderedProminent)
                        .tint(.white)
                        .foregroundColor(.blue)
                        .keyboardShortcut(.init("e"), modifiers: .command)
            Button("open_settings") {
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.85))
                .clipped()
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.85))
                .clipped()
            }
            ScrollViewReader { proxy in
                ScrollView {
                    if let current = fetchedSessions.first(where: { viewModel.isSelected(session: $0) }), !viewModel.pendingNewSession {
                        SessionMessagesView(session: current, viewModel: viewModel, bot: bot, store: store)
                            .id(current.objectID)
                    } else {
                        messagesList
                    }
                }
                .onChange(of: viewModel.messages.count) { _ in
                    if let last = viewModel.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
                .onChange(of: viewModel.messages.last?.text) { _ in
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
        .navigationTitle(bot.name.isEmpty ? String(localized: "chat") : bot.name)
        // 若是临时会话，给标题加个“(未开始)”提示，避免误解仍在上一会话
        .navigationSubtitle(viewModel.pendingNewSession ? String(localized: "temporary_session_not_started") : "")
        .onAppear {
            // Single source of truth: updateConversation triggers loading when bot changed
            viewModel.updateConversation(bot)
            ensureSelectionIfNeeded()
        }
        // Use Core Data object identity instead of an auto-generated UUID
        .onChange(of: bot.objectID.uriRepresentation()) { _ in
            // 切换到其他 Agent：刷新会话列表与消息，并关闭快捷面板
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                viewModel.updateConversation(bot)
                if showQuickActions { showQuickActions = false }
            }
        }
        // 当会话列表发生变化（可能有轻微延迟）时，若无有效选中则按规则选中
        .onChange(of: fetchedSessions.map { $0.objectID }) { newIds in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                ensureSelectionIfNeeded(newIds.first)
            }
        }
        .alert(String(localized: "confirm_delete_session"), isPresented: $showDeleteConfirm) {
            Button(String(localized: "cancel"), role: .cancel) { pendingDeleteSession = nil }
            Button(String(localized: "delete"), role: .destructive) {
                if let s = pendingDeleteSession { viewModel.delete(session: s) }
                pendingDeleteSession = nil
            }
        } message: {
            Text("delete_session_message")
        }
        .alert(String(localized: "confirm_clear_chat"), isPresented: $showClearConfirm) {
            Button(String(localized: "cancel"), role: .cancel) {}
            Button(String(localized: "clear"), role: .destructive) { viewModel.clearHistory() }
        } message: {
            Text("clear_chat_message")
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
                    showClearConfirm = true
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
                QuickActions(
                    isPresented: $showQuickActions,
                    mode: actionsMode,
                    viewModel: viewModel,
                    bot: bot,
                    store: store,
                    requestClear: { withAnimation(.easeOut(duration: 0.15)) { showQuickActions = false }; showClearConfirm = true }
                )
            }
        }
        // 登录状态变化后，自动隐藏错误并刷新模型目录
        .onReceive(NotificationCenter.default.publisher(for: .init("BetterAuthSessionChanged"))) { _ in
            viewModel.error = nil
            Task { await ModelSelectionManager.shared.refreshRemote() }
        }
        // Handle login requested from ViewModel error action
        .onReceive(NotificationCenter.default.publisher(for: .init("BetterAuthLoginRequestedFromChat"))) { _ in
            #if os(macOS)
            Task {
                do { _ = try await authClient.browserOTT.signIn(with: .init(redirect_uri: "macaify://ott")) } catch {}
                await authClient.session.refreshSession()
                NotificationCenter.default.post(name: .init("BetterAuthSessionChanged"), object: nil)
            }
            #endif
        }
    }

    // 根据优先级进行选中：
    // 1) 若存在临时会话（pendingNewSession），保持临时态，不选持久化会话；
    // 2) 若无选中或选中已无效，且列表非空，则选中最新（FetchRequest 已按 updatedAt 降序）；
    private func ensureSelectionIfNeeded(_ id: NSManagedObjectID? = nil) {
        if viewModel.pendingNewSession { return }
        guard !fetchedSessions.isEmpty else { return }
        if let sel = viewModel.selectedSessionID,
           fetchedSessions.contains(where: { $0.objectID == sel }) {
            return
        }
        // 选中最新一条
        if let id {
            viewModel.select(id: id)
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

// MARK: - Messages via Core Data (FetchRequest)
private struct SessionMessagesView: View {
    @ObservedObject var session: GPTSession
    @ObservedObject var viewModel: ChatSessionViewModel
    let bot: GPTConversation
    var store: BotStore?

    @FetchRequest private var rows: FetchedResults<GPTAnswer>

    init(session: GPTSession, viewModel: ChatSessionViewModel, bot: GPTConversation, store: BotStore?) {
        self._session = ObservedObject(initialValue: session)
        self._viewModel = ObservedObject(initialValue: viewModel)
        self.bot = bot
        self.store = store
        self._rows = FetchRequest(
            sortDescriptors: [NSSortDescriptor(key: "timestamp_", ascending: true)],
            predicate: NSPredicate(format: "session == %@", session)
        )
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            ForEach(rows) { row in
                // user prompt
                if !row.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    bubble(text: row.prompt, sender: .user)
                }
                // assistant response
                if !row.response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    bubble(text: row.response, sender: .assistant)
                }
            }
            // Ephemeral user + streaming assistant bubbles (not persisted yet)
            if let sIdx = viewModel.messages.lastIndex(where: { $0.isStreaming && $0.sender == .assistant }) {
                if sIdx > 0 {
                    let u = viewModel.messages[sIdx - 1]
                    if u.sender == .user { bubble(text: u.text, sender: .user, id: u.id) }
                }
                let streaming = viewModel.messages[sIdx]
                bubble(text: streaming.text, sender: .assistant, id: streaming.id, streaming: true)
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private func bubble(text: String, sender: ChatSessionViewModel.ChatMessage.Sender, id: UUID? = nil, streaming: Bool = false) -> some View {
        let label = sender == .user ? String(localized: "you") : String(localized: "assistant")
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(label).font(.caption).foregroundStyle(.secondary)
                }
                if streaming && sender == .assistant {
                    HStack(alignment: .firstTextBaseline, spacing: text.isEmpty ? 0 : 2) {
                        Text(text).textSelection(.enabled).font(.body)
                        BlinkingCaret()
                    }
                } else {
                    #if canImport(MarkdownUI)
                    MarkdownView(text).textSelection(.enabled).tint(.accentColor)
                    #else
                    Text(text).textSelection(.enabled).font(.body)
                    #endif
                }
            }
            .padding(10)
            .frame(maxWidth: 560, alignment: .leading)
            .background(sender == .user ? Color.blue.opacity(0.08) : Color.gray.opacity(0.08))
            .cornerRadius(12)
        }
        .frame(maxWidth: .infinity, alignment: sender == .user ? .trailing : .leading)
        .id(id ?? UUID())
        .contextMenu {
            Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) } label: { Label("copy", systemImage: "doc.on.doc") }
            Button {
                let md = "```\n\(text)\n```"
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(md, forType: .string)
            } label: { Label("copy_as_markdown", systemImage: "doc.on.doc.fill") }
            Button { viewModel.injectContext(text) } label: { Label("use_as_context", systemImage: "text.append") }
            if sender == .user {
                Divider()
                Button("set_as_system_prompt_and_regenerate", systemImage: "slider.horizontal.3") {
                    Task { await viewModel.regenerateWithSystemPromptOverride(text) }
                }
            }
            if let store {
                Divider()
                Menu("用其他 Agent 运行…", content: {
                    ForEach(store.bots, id: \.id) { other in
                        if other.id != bot.id {
                            Button(other.name.isEmpty ? other.id.uuidString : other.name) {
                                Task { await viewModel.runWithAgent(agent: other, using: (sender == .user ? text : nil)) }
                            }
                        }
                    }
                })
            }
        }
    }
}

// MARK: - Message rendering (Markdown when available)
    @ViewBuilder
    private func messageBody(for msg: ChatSessionViewModel.ChatMessage) -> some View {
        #if canImport(MarkdownUI)
        // 流式加载时使用纯文本 + 光标闪烁，完成后再用 Markdown 渲染
        if msg.isStreaming && msg.sender == .assistant {
            HStack(alignment: .firstTextBaseline, spacing: msg.text.isEmpty ? 0 : 2) {
                Text(msg.text)
                    .textSelection(.enabled)
                    .font(.body)
                BlinkingCaret()
            }
        } else {
            MarkdownView(msg.text)
                .textSelection(.enabled)
                .tint(.accentColor)
        }
        #else
        Text(msg.text)
            .textSelection(.enabled)
            .font(.body)
        #endif
    }

    private struct BlinkingCaret: View {
        var period: TimeInterval = 0.6
        var body: some View {
            TimelineView(.periodic(from: .now, by: period)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let phase = Int((t / period).rounded(.down))
                let on = (phase % 2) == 0
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 2, height: 16)
                    .opacity(on ? 1 : 0) // 离散闪烁，不做透明度动画
            }
        }
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
                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text(msg.sender == .user ? String(localized: "you") : String(localized: "assistant"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let via = msg.viaAgent { Text("via \(via)").font(.caption2).foregroundStyle(.secondary) }
                        }
                        messageBody(for: msg)
                    }
                    .padding(10)
                    .frame(maxWidth: 560, alignment: .leading)
                    .background(msg.sender == .user ? Color.blue.opacity(0.08) : Color.gray.opacity(0.08))
                    .cornerRadius(12)
                }
                .frame(maxWidth: .infinity, alignment: msg.sender == .user ? .trailing : .leading)
                .id(msg.id)
                .contextMenu {
                    Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(msg.text, forType: .string) } label: { Label("copy", systemImage: "doc.on.doc") }
                    Button {
                        let md = "```\n\(msg.text)\n```"
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(md, forType: .string)
                    } label: { Label("copy_as_markdown", systemImage: "doc.on.doc.fill") }
                    Button { viewModel.injectContext(msg.text) } label: { Label("use_as_context", systemImage: "text.append") }
                    if msg.sender == .user {
                        Divider()
                        Button("set_as_system_prompt_and_regenerate", systemImage: "slider.horizontal.3") {
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
                    placeholder: String(localized: "send_message_ellipsis"),
                    text: $viewModel.input,
                    measuredHeight: $inputHeight,
                    minHeight: ChatTokens.controlHeight,
                    maxHeight: 140,
                    onEnter: { Task { await viewModel.send() } },
                    onShiftEnter: { /* newline inserted by NSTextView */ },
                    onCommandEnter: { Task { await viewModel.send() } },
                    onCommandK: { withAnimation(.spring(response: 0.2, dampingFraction: 0.9)) { openQuickActions() } }
                )
                .frame(height: inputHeight)
                .animation(.easeInOut(duration: 0.16), value: inputHeight)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2)))
                if viewModel.isSending {
                    Button(action: { viewModel.stopStreaming() }) {
                        Image(systemName: "stop.circle.fill")
                            .foregroundColor(.red)
                    }
                    .help("stop_generating_shortcut")
                    .keyboardShortcut(.init("."), modifiers: .command)
                } else {
                    Button(action: { Task { await viewModel.send() } }) {
                        Image(systemName: "paperplane")
                    }
                    .help("send_and_newline_help")
                    .disabled(viewModel.isSending)
                    .keyboardShortcut(.return, modifiers: .command)
                }
                Button(action: { openQuickActions() }) {
                    Text("actions_cmdk")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 4)
                }
                .help("open_actions_cmdk")
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

                Text("keyboard_hint_full")
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
    var requestClear: () -> Void = {}

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
            arr.append(Item(title: String(localized: "send"), systemImage: "paperplane", keyHint: "↩", group: .message, action: { Task { await viewModel.send() }; dismiss() }))
        }
        arr.append(Item(title: String(localized: "regenerate_response"), systemImage: "arrow.clockwise", keyHint: "⌘R", group: .message, action: { Task { await viewModel.regenerateLast() }; dismiss() }))
        arr.append(Item(title: String(localized: "copy_last_reply"), systemImage: "doc.on.doc", keyHint: "⌥⇧C", group: .clipboard, action: { viewModel.copyLastReply(); dismiss() }))
        arr.append(Item(title: String(localized: "paste_to_front_app"), systemImage: "rectangle.and.text.magnifyingglass", keyHint: "⌥⇧V", group: .clipboard, action: { viewModel.useLastReply(); dismiss() }))
        arr.append(Item(title: String(localized: "run_with_other_agent"), systemImage: "bolt.horizontal.circle", keyHint: "→", group: .agent, opensSubmenu: .runWithAgent, action: { switchMode(.runWithAgent) }))
        arr.append(Item(title: String(localized: "new_chat_with_other_agent"), systemImage: "arrow.uturn.forward", keyHint: "→", group: .agent, opensSubmenu: .newChatWithAgent, action: { switchMode(.newChatWithAgent) }))
        arr.append(Item(title: String(localized: "clear_chat"), systemImage: "eraser", keyHint: "⌘D", group: .danger, action: { requestClear() }))
        return arr
    }

    private var agentItems: [Item] {
        let list = (store?.bots ?? []).filter { $0.id != bot.id }
        switch currentMode {
        case .runWithAgent:
            return list.map { other in
                Item(title: other.name.isEmpty ? other.id.uuidString : other.name, subtitle: String(localized: "run_current_input_or_last_question"), systemImage: "bolt.fill", keyHint: nil, group: .agent, action: {
                    Task { await viewModel.runWithAgent(agent: other, using: viewModel.input.isEmpty ? nil : viewModel.input) }
                    dismiss()
                })
            }
        case .newChatWithAgent:
            return list.map { other in
                Item(title: other.name.isEmpty ? other.id.uuidString : other.name, subtitle: String(localized: "switch_to_agent_and_start_new_session"), systemImage: "arrow.uturn.right.circle.fill", keyHint: nil, group: .agent, action: {
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
        case .message: return String(localized: "message")
        case .clipboard: return String(localized: "clipboard")
        case .agent: return "Agent"
        case .session: return String(localized: "session")
        case .danger: return String(localized: "danger")
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
                    TextField("search_actions_ellipsis", text: $query)
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
                            Text("no_actions")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 24)
                        }
                        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && currentMode != .root {
                            Text(currentMode == .runWithAgent ? String(localized: "choose_agent_to_run") : String(localized: "choose_agent_to_new_chat"))
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
                        requestClear(); return true
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
