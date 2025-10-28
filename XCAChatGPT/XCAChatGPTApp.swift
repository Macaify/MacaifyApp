//
//  XCAChatGPTApp.swift
//  XCAChatGPT
//
//  Created by Alfian Losari on 01/02/23.
//

import SwiftUI
import CoreData
import Defaults
import OpenAI

@main
struct XCAChatGPTApp: App {
    var body: some Scene {
        WindowGroup {
            MainSplitView()
        }
    }
}

// MARK: - New Main Split View (Sidebar + Chat Detail + Toolbar)

fileprivate final class BotStore: ObservableObject {
    @Published var bots: [GPTConversation] = []
    @Published var selectedID: UUID? = nil

    private var context: NSManagedObjectContext { PersistenceController.shared.container.viewContext }

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

    func deleteBot(_ bot: GPTConversation) {
        PersistenceController.shared.deleteConversation(conversation: bot)
        reload()
    }
    var selected: GPTConversation? { bots.first(where: { $0.id == selectedID }) }
}

fileprivate struct ChatMessage: Identifiable, Hashable {
    enum Sender { case user, assistant }
    let id: UUID = UUID()
    let sender: Sender
    var text: String
    var isStreaming: Bool = false
}

fileprivate final class ChatSessionViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var input: String = ""
    @Published var isSending: Bool = false
    @Published var error: String? = nil

    private var api: ChatGPTAPI
    private var conv: GPTConversation

    init(conversation: GPTConversation) {
        self.conv = conversation
        let selectedModel = Defaults[.selectedModelId].isEmpty ? "macaify-1-mini" : Defaults[.selectedModelId]
        let maxToken = Defaults[.maxToken]
        let apiKey = Defaults[.apiKey]
        self.api = ChatGPTAPI(apiKey: apiKey, model: selectedModel, maxToken: maxToken, systemPrompt: conversation.prompt, temperature: 0.5, baseURL: "", withContext: conversation.withContext)
        Task { await loadHistory() }
    }

    func updateConversation(_ next: GPTConversation) {
        self.conv = next
        self.api.systemPrompt = next.prompt
        self.api.withContext = next.withContext
        Task { await loadHistory() }
    }

    @MainActor
    func loadHistory(limit: Int = 80) async {
        messages = []
        error = nil
        let convID = conv.objectID
        let container = PersistenceController.shared.container
        do {
            let rows: [(String, String)] = try await withCheckedThrowingContinuation { cont in
                let ctx = container.newBackgroundContext()
                ctx.perform {
                    do {
                        let convBG = try ctx.existingObject(with: convID) as! GPTConversation
                        let req: NSFetchRequest<GPTAnswer> = GPTAnswer.fetchRequest()
                        req.predicate = NSPredicate(format: "belongsTo == %@", convBG)
                        req.sortDescriptors = [NSSortDescriptor(key: "timestamp_", ascending: false)]
                        req.fetchLimit = limit
                        let fetched = try ctx.fetch(req).reversed()
                        let pairs = fetched.map { ($0.prompt, $0.response) }
                        cont.resume(returning: Array(pairs))
                    } catch { cont.resume(throwing: error) }
                }
            }
            self.messages = rows.flatMap { [ChatMessage(sender: .user, text: $0.0), ChatMessage(sender: .assistant, text: $0.1)] }
            self.api.history = self.messages.compactMap { msg -> Message? in
                switch msg.sender {
                case .user: return Message(role: "user", content: msg.text)
                case .assistant: return Message(role: "assistant", content: msg.text)
                }
            }
        } catch {
            self.messages = []
        }
    }

    @MainActor
    func send() async {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        input = ""
        isSending = true
        error = nil
        messages.append(ChatMessage(sender: .user, text: text))
        messages.append(ChatMessage(sender: .assistant, text: "", isStreaming: true))

        do {
            let stream = try await api.chatsStream(text: text)
            var buffer = ""
            for try await chunk in stream {
                let delta = chunk.choices.first?.delta.content ?? ""
                guard !delta.isEmpty else { continue }
                buffer += delta
                if let idx = messages.lastIndex(where: { $0.isStreaming }) {
                    messages[idx].text = buffer
                }
            }
            if let idx = messages.lastIndex(where: { $0.isStreaming }) {
                messages[idx].isStreaming = false
            }
            persistLastPair(user: text, assistant: buffer)
        } catch {
            if let idx = messages.lastIndex(where: { $0.isStreaming }) {
                messages.remove(at: idx)
            }
            self.error = error.localizedDescription
        }
        isSending = false
    }

    private func persistLastPair(user: String, assistant: String) {
        guard !assistant.isEmpty else { return }
        let answer = GPTAnswer(role: "user", prompt: user, response: assistant, parentId: conv.own.last?.uuid, context: conv.managedObjectContext ?? PersistenceController.shared.container.viewContext)
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

struct MainSplitView: View {
    @StateObject private var store = BotStore()
    @StateObject private var chatVM = ChatSessionViewModel(conversation: GPTConversation(context: PersistenceController.memoryContext))
    @State private var showSettings = false

    var body: some View {
        NavigationSplitView {
            Sidebar(store: store)
        } detail: {
            if let current = store.selected {
                ChatDetailView(viewModel: chatVM, bot: current)
            } else {
                VStack { Spacer(); Text("no_bot_selected").foregroundStyle(.secondary); Spacer() }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 460)
        .onAppear { if let s = store.selected { chatVM.updateConversation(s) } }
        .onChange(of: store.selectedID) { _ in if let s = store.selected { chatVM.updateConversation(s) } }
        .toolbar { toolbar }
        .sheet(isPresented: $showSettings) {
            if let selected = store.selection { BotSettingsView(bot: selected) { store.reload() } }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                store.addBot()
            } label: {
                Label(String(localized: "new_bot"), systemImage: "plus")
            }
        }
        ToolbarItem(placement: .principal) {
            Text(store.selected?.name.isEmpty == false ? store.selected!.name : "Bots")
                .font(.headline)
        }
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            if let sel = store.selected {
                Toggle(isOn: Binding(get: { sel.withContext }, set: { newVal in
                    sel.withContext = newVal; sel.save(); chatVM.updateConversation(sel)
                })) {
                    Image(systemName: sel.withContext ? "arrow.triangle.2.circlepath" : "arrow.triangle.2.circlepath.circle")
                }
                .toggleStyle(.button)
                .help("use_context")
            }
            Button {
                Task { await chatVM.clearHistory() }
            } label: { Label(String(localized: "clear"), systemImage: "trash") }
            .disabled(store.selected == nil)
            Button {
                showSettings = true
            } label: {
                Label(String(localized: "bot_settings"), systemImage: "gear")
            }
            .disabled(store.selected == nil)
        }
    }
}

fileprivate struct Sidebar: View {
    @ObservedObject var store: BotStore

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
                .contextMenu {
                    Button(role: .destructive) { store.deleteBot(bot) } label: { Label(String(localized: "delete"), systemImage: "trash") }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("bots")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button { store.addBot() } label: { Label(String(localized: "add"), systemImage: "plus") }
            }
        }
    }
}

fileprivate struct ChatDetailView: View {
    @ObservedObject var viewModel: ChatSessionViewModel
    let bot: GPTConversation

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.messages) { msg in
                            HStack(alignment: .top) {
                                if msg.sender == .assistant { Spacer(minLength: 0) }
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(msg.sender == .user ? String(localized: "you") : String(localized: "assistant")).font(.caption).foregroundStyle(.secondary)
                                    Text(msg.text).textSelection(.enabled)
                                }
                                .padding(10)
                                .background(msg.sender == .user ? Color.blue.opacity(0.08) : Color.gray.opacity(0.08))
                                .cornerRadius(10)
                                if msg.sender == .user { Spacer(minLength: 0) }
                            }
                            .id(msg.id)
                        }
                    }.padding(12)
                }
                .onChange(of: viewModel.messages.count) { _ in
                    if let last = viewModel.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            Divider()
            HStack(alignment: .bottom, spacing: 8) {
                TextEditor(text: $viewModel.input)
                    .frame(minHeight: 38, maxHeight: 120)
                    .textEditorStyle(.plain)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.2)))
                Button(action: { Task { await viewModel.send() } }) {
                    Image(systemName: viewModel.isSending ? "paperplane.fill" : "paperplane")
                }
                .disabled(viewModel.isSending)
            }
            .padding(12)
        }
        .navigationTitle(bot.name.isEmpty ? String(localized: "chat") : bot.name)
        .onAppear { viewModel.updateConversation(bot) }
    }
}

fileprivate struct BotSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State var bot: GPTConversation
    var onSaved: () -> Void

    @State private var name: String = ""
    @State private var prompt: String = ""
    @State private var withContext: Bool = true

    init(bot: GPTConversation, onSaved: @escaping () -> Void) {
        self._bot = State(initialValue: bot)
        self.onSaved = onSaved
        self._name = State(initialValue: bot.name)
        self._prompt = State(initialValue: bot.prompt)
        self._withContext = State(initialValue: bot.withContext)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "basics")) {
                    TextField(String(localized: "name"), text: $name)
                    Toggle(String(localized: "use_context"), isOn: $withContext)
                }
                Section(String(localized: "system_prompt")) {
                    TextEditor(text: $prompt).frame(minHeight: 160)
                }
            }
            .navigationTitle("bot_settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(String(localized: "cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "save")) { save() }.keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private func save() {
        bot.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        bot.prompt = prompt
        bot.withContext = withContext
        bot.timestamp = Date()
        bot.save()
        onSaved()
        dismiss()
    }
}
