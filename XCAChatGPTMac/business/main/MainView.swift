//
//  MainView.swift
//  A new SwiftUI home page: Sidebar (bots) + Chat detail + Toolbar
//

import SwiftUI
import Defaults

struct MainView: View {
    @EnvironmentObject var convVM: ConversationViewModel
    @EnvironmentObject var pathManager: PathManager

    @State private var selection: UUID? = nil

    var body: some View {
        Group {
            if #available(macOS 13.0, *) {
                NavigationSplitView(sidebar: { sidebar }, detail: { detail })
            } else {
                HStack(spacing: 0) { sidebar.frame(width: 240); Divider(); detail }
            }
        }
        .background(.background)
        .onAppear { syncSelection() }
        .onChange(of: convVM.currentChat) { _ in syncSelection() }
        .onChange(of: selection) { id in
            guard let id, let conv = convVM.conversations.first(where: { $0.id == id }) else { return }
            // Prewarm history for snappier switch
            let vm = convVM.commandViewModel(conv)
            Task { await vm.loadInitialMessagesAsync() }
            convVM.currentChat = conv
        }
        .toolbar { toolbar }
    }

    // MARK: - Sidebar
    @ViewBuilder private var sidebar: some View {
        List(selection: Binding(get: { selection }, set: { selection = $0 })) {
            Section(String(localized: "bots")) {
                ForEach(convVM.conversations) { conv in
                    HStack(spacing: 8) {
                        ConversationIconView(conversation: conv, size: 16)
                        Text(conv.name).lineLimit(1)
                        if conv.typingInPlace { Text("tip").font(.caption2).padding(2).background(Color.purple.opacity(0.9).cornerRadius(4)).foregroundColor(.white) }
                    }
                    .frame(height: 28)
                    .tag(conv.id as UUID?)
                    .contextMenu {
                        Button(String(localized: "编辑")) { pathManager.to(target: .editCommand(command: conv)) }
                        Button(String(localized: "删除"), role: .destructive) { convVM.removeCommand(conv) }
                    }
                }
                .onDelete(perform: convVM.removeCommand)
                .onMove(perform: convVM.moveCommands)
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 220)
    }

    // MARK: - Detail
    @ViewBuilder private var detail: some View {
        if let conv = convVM.currentChat {
            SwiftUIChatDetail(conversation: conv)
                .id(conv.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background)
        } else {
            VStack(spacing: 12) {
                Text(String(localized: "welcome_to_macaify")).font(.title3)
                Text(String(localized: "hold_cmd_for_shortcuts")).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button(String(localized: "create_bot")) { pathManager.to(target: .addCommand) }
                    Button(String(localized: "bots_plaza")) { pathManager.to(target: .playground) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Toolbar
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Button { pathManager.to(target: .addCommand) } label: {
                Label(String(localized: "Create a Bot"), systemImage: "square.stack.3d.up.badge.a")
            }
        }
        ToolbarItem(placement: .automatic) {
            Button { pathManager.to(target: .playground) } label: {
                Label(String(localized: "Bots Plaza"), systemImage: "sparkles.rectangle.stack")
            }
        }
        ToolbarItem(placement: .automatic) {
            Button {
                if let c = convVM.currentChat { pathManager.to(target: .editCommand(command: c)) }
            } label: { Image(systemName: "gearshape") }
                .help(String(localized: "会话设置"))
                .disabled(convVM.currentChat == nil)
        }
        ToolbarItem(placement: .automatic) {
            Button {
                if #available(macOS 13.0, *) { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) }
                else { pathManager.to(target: .setting) }
            } label: { Label(String(localized: "Global Settings"), systemImage: "gear") }
        }
    }

    private func syncSelection() {
        selection = convVM.currentChat?.id
    }
}

// MARK: - Pure SwiftUI Chat Detail
struct SwiftUIChatDetail: View {
    let conversation: GPTConversation
    @State private var vm: ViewModel
    @State private var draft: String = ""
    @State private var scroller: ScrollViewProxy? = nil
    @State private var bottomID = UUID()
    @Environment(\.colorScheme) private var colorScheme

    init(conversation: GPTConversation) {
        self.conversation = conversation
        _vm = State(initialValue: ConversationViewModel.shared.commandViewModel(conversation))
        _draft = State(initialValue: ConversationViewModel.shared.commandViewModel(conversation).inputMessage)
    }

    var body: some View {
        VStack(spacing: 0) {
            history
            Divider()
            composer.padding(8).background(.regularMaterial)
        }
        .background(.background)
        .task { await vm.loadInitialMessagesAsync() }
        .onChange(of: vm.messages.count) { _ in scrollToBottom() }
        .onChange(of: vm.isInteractingWithChatGPT) { _ in scrollToBottom() }
    }

    private var history: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(vm.messages) { msg in
                        VStack(alignment: .leading, spacing: 8) {
                            bubble(text: msg.sendText, isResponse: false)
                            if let t = msg.responseText { bubble(text: t, isResponse: true, loading: msg.isInteractingWithChatGPT, error: msg.responseError) }
                        }
                        .id(msg.id)
                    }
                    Color.clear.frame(height: 1).id(bottomID)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
            }
            .onAppear { scroller = proxy }
        }
    }

    private func bubble(text: String, isResponse: Bool, loading: Bool = false, error: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .font(.body)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(bubbleBackground(isResponse))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.12), lineWidth: 0.8))
            if let e = error { Text("Error: \(e)").foregroundColor(.red) }
            if loading { ProgressView().controlSize(.small) }
        }
    }

    private func bubbleBackground(_ isResponse: Bool) -> Color {
        if colorScheme == .light { return isResponse ? .black.opacity(0.04) : .black.opacity(0.025) }
        return isResponse ? .white.opacity(0.06) : .white.opacity(0.04)
    }

    private var composer: some View {
        HStack(alignment: .center, spacing: 8) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $draft)
                    .font(.body)
                    .frame(minHeight: 32, maxHeight: 120)
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(6)
                if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("输入消息…").foregroundColor(.secondary).padding(.top, 8).padding(.leading, 6)
                }
            }
            if vm.isInteractingWithChatGPT {
                Button { vm.interupt() } label: { Label("停止", systemImage: "stop.circle") }
                    .buttonStyle(.borderedProminent).tint(.red)
            } else {
                Button { Task { await send() } } label: { Label("发送", systemImage: "paperplane.fill") }
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    @MainActor private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        vm.inputMessage = text
        draft = ""
        scrollToBottom()
        await vm.sendTapped()
        scrollToBottom()
    }

    private func scrollToBottom(animated: Bool = true) {
        guard let proxy = scroller else { return }
        withAnimation(animated ? .easeOut(duration: 0.12) : nil) { proxy.scrollTo(bottomID, anchor: .bottom) }
    }
}

// Pure SwiftUI chat view (no custom components). Only shows history and sends messages.
struct SwiftUIChatView: View {
    let conversation: GPTConversation

    @State private var vm: ViewModel
    @State private var draft: String = ""
    @State private var scroller: ScrollViewProxy? = nil
    @State private var bottomID = UUID()

    init(conversation: GPTConversation) {
        self.conversation = conversation
        _vm = State(initialValue: ConversationViewModel.shared.commandViewModel(conversation))
        _draft = State(initialValue: ConversationViewModel.shared.commandViewModel(conversation).inputMessage)
    }

    var body: some View {
        VStack(spacing: 0) {
            history
            Divider()
            composer
                .padding(8)
                .background(.regularMaterial)
        }
        .background(.background)
        .task { await vm.loadInitialMessagesAsync() }
        .onChange(of: vm.messages.count) { _ in scrollToBottom() }
        .onChange(of: vm.isInteractingWithChatGPT) { _ in scrollToBottom() }
    }

    // MARK: - History
    private var history: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(vm.messages) { msg in
                        messageGroup(msg)
                            .id(msg.id)
                    }
                    Color.clear.frame(height: 1).id(bottomID)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
            }
            .onAppear { scroller = proxy }
        }
    }

    private func scrollToBottom(animated: Bool = true) {
        guard let proxy = scroller else { return }
        withAnimation(animated ? .easeOut(duration: 0.12) : nil) {
            proxy.scrollTo(bottomID, anchor: .bottom)
        }
    }

    // MARK: - Message Cell
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder private func messageGroup(_ m: MessageRow) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            bubble(text: m.sendText, isResponse: false)
            if let t = m.responseText { bubble(text: t, isResponse: true, loading: m.isInteractingWithChatGPT, error: m.responseError) }
        }
    }

    @ViewBuilder private func bubble(text: String, isResponse: Bool, loading: Bool = false, error: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .font(.body)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(bubbleBackground(isResponse))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.12), lineWidth: 0.8))
            if let e = error { Text("Error: \(e)").foregroundColor(.red) }
            if loading { ProgressView().controlSize(.small) }
        }
    }

    private func bubbleBackground(_ isResponse: Bool) -> Color {
        if colorScheme == .light { return isResponse ? .black.opacity(0.04) : .black.opacity(0.025) }
        return isResponse ? .white.opacity(0.06) : .white.opacity(0.04)
    }

    // MARK: - Composer
    private var composer: some View {
        HStack(alignment: .center, spacing: 8) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $draft)
                    .font(.body)
                    .frame(minHeight: 32, maxHeight: 120)
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(6)
                if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("输入消息…")
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                        .padding(.leading, 6)
                }
            }

            if vm.isInteractingWithChatGPT {
                Button { vm.interupt() } label: { Label("停止", systemImage: "stop.circle") }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
            } else {
                Button { Task { await send() } } label: { Label("发送", systemImage: "paperplane.fill") }
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    @MainActor private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        vm.inputMessage = text
        draft = ""
        scrollToBottom()
        await vm.sendTapped()
        scrollToBottom()
    }
}
