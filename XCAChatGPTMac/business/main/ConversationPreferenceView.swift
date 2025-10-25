//
//  AddCommandView.swift
//  XCAChatGPTMac
//
//  Created by lixindong on 2023/4/8.
//

import SwiftUI
import AppKit
import KeyboardShortcuts
import Defaults

struct ConversationPreferenceView: View {

    @EnvironmentObject var commandStore: ConversationViewModel
    @EnvironmentObject var pathManager: PathManager
    @State var conversation: GPTConversation
    @State var autoAddSelectedText: Bool
    @State var typingInPlace: Bool
    @State var oneTimeChat: Bool
    @State var prompt: String
    let mode: ConversationPreferenceMode

    @State private var isShowingPopover = false
    @State private var icon: Emoji? = nil
    

    init(conversation: GPTConversation, mode: ConversationPreferenceMode) {
        self.conversation = conversation
        self.autoAddSelectedText = conversation.autoAddSelectedText
        self.typingInPlace = conversation.typingInPlace
        self.oneTimeChat = conversation.withContext
        self.mode = mode
        self.prompt = conversation.prompt
    }
    
    var isNew: Bool {
        get { mode == .add }
    }

    var body: some View {
        NavigationStack {
            Form {
                iconView
                Section {
                    name
                    systemProtmp
                }
                modelUnifiedSelection
                useContext
                hotkey
                typingInPlaceItem
            }
            .formStyle(.grouped)
            .navigationTitle(isNew ? "新建机器人" : "编辑机器人")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { pathManager.back() }
                }
                if !isNew {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("删除") {
                            commandStore.removeCommand(conversation)
                            pathManager.toMain()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { saveAndClose() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private func saveAndClose() {
        if conversation.name.isEmpty { conversation.name = "Untitled" }
        switch (mode) {
        case .add:
            commandStore.addCommand(command: conversation)
            commandStore.selectedItemIndex = 0
        case .edit:
            commandStore.updateCommand(command: conversation)
        default:
            break
        }
        pathManager.back()
    }
    
    var iconView: some View {
        LabeledContent("icon") {
            Button {
                if !conversation.icon.isEmpty {
                    isShowingPopover.toggle()
                } else {
                    icon = EmojiManager.shared.randomOnce()
                    isShowingPopover.toggle()
                }
            } label: {
                if (!conversation.icon.isEmpty) {
                    ConversationIconView(conversation: conversation, size: 40).id(conversation.icon)
                } else {
                    Text("add_icon")
                        .font(.body)
                        .opacity(0.5)
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isShowingPopover) {
                EmojiPickerView(selectedEmoji: $icon)
            }
            .onChange(of: icon?.emoji) { newValue in
                print("emoji selected \(newValue)")
                conversation.icon = newValue ?? ""
                ConversationViewModel.shared.updateCommand(command: conversation)
            }
        }
    }
    
    var name: some View {
        TextField("bot_name", text: $conversation.name)
    }
    
    var systemProtmp: some View {
        Group {
            Text("system_prompt")
            TextEditor(text: $prompt)
                .onChange(of: prompt) { newValue in
                    print("prompt changed")
                    conversation.prompt = prompt
                }
        }
    }
    
    var hotkey: some View {
        Section("hotkey") {
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent(String(localized: "edit_mode_shortcut")) {
                    KeyboardShortcuts.Recorder(for: conversation.NameEdit) { shortcut in
                        if shortcut != nil { HotKeyManager.register(conversation) }
                        else { KeyboardShortcuts.reset(conversation.NameEdit) }
                    }
                    .controlSize(.large)
                }
                Text(String(localized: "edit_mode_help")).font(.caption).foregroundStyle(.secondary)

                LabeledContent(String(localized: "chat_mode_shortcut")) {
                    KeyboardShortcuts.Recorder(for: conversation.NameChat) { shortcut in
                        if shortcut != nil { HotKeyManager.register(conversation) }
                        else { KeyboardShortcuts.reset(conversation.NameChat) }
                    }
                    .controlSize(.large)
                }
                Text(String(localized: "chat_mode_help")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    
    var useContext: some View {
        Toggle(isOn: $oneTimeChat) {
            Text("use_context")
        }
        .onChange(of: oneTimeChat) { newValue in
            conversation.withContext = newValue
        }
    }
    
    var autoAddText: some View {
        Toggle(isOn: $autoAddSelectedText) {
            Text("auto_add_selected_text")
        }.onChange(of: autoAddSelectedText) { newValue in
            conversation.autoAddSelectedText = newValue
        }
    }
    
    var typingInPlaceItem: some View {
        Section("行为") {
            HStack {
                Spacer()
                Picker("", selection: $typingInPlace) {
                    Text("编辑模式").tag(true)
                    Text("聊天模式").tag(false)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .onChange(of: typingInPlace) { conversation.typingInPlace = $0 }
            }
            if !typingInPlace {
                autoAddText
            }
        }
    }

    // MARK: - Unified model chooser (account + custom)
    @State private var showModelPopover = false
    @State private var hoverModel: ModelItem? = nil
    @State private var selectedModel: ModelItem? = nil

    struct ModelItem: Identifiable, Hashable { let id: String; let title: String; let provider: String; let context: Int; let source: Source; let instanceId: String?; enum Source { case account, custom } }

    var modelUnifiedSelection: some View {
        Section("模型") {
            LabeledContent("模型") {
                Button {
                    showModelPopover.toggle()
                } label: {
                    HStack(spacing: 8) {
                        Text(currentModelTitle)
                        Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.2)))
                }
                .buttonStyle(.plain)
                .background(
                    AnchoredPopover(isPresented: $showModelPopover, preferredDirection: .above) {
                        QuickModelPickerView(
                            onDismiss: { showModelPopover = false },
                            isInstanceSelected: { inst in conversation.modelSource == "instance" && conversation.modelInstanceId == inst.id },
                            isAccountSelected: { _, modelId in conversation.modelSource == "account" && conversation.modelId == modelId },
                            onPickInstance: { inst in
                                conversation.modelSource = "instance"
                                conversation.modelInstanceId = inst.id
                                conversation.modelId = ""
                            },
                            onPickRemote: { item in
                                conversation.modelSource = "account"
                                conversation.modelId = item.slug
                                conversation.modelInstanceId = ""
                            }
                        )
                    }
                )
            }
        }
    }

    private var currentModelTitle: String {
        if conversation.modelSource == "instance" {
            return ProviderStore.shared.providers.first(where: { $0.id == conversation.modelInstanceId })?.name ?? "模型"
        } else if !conversation.modelId.isEmpty {
            return conversation.modelId
        } else {
            return Defaults[.selectedModelId]
        }
    }

    private var modelPickerPopover: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                TextField("Search...", text: Binding(
                    get: { _search }, set: { _search = $0 }
                )).textFieldStyle(.roundedBorder)
                List(selection: $selectedModel) {
                    if !accountItemsFiltered.isEmpty {
                        Section(String(localized: "账户模型")) { ForEach(accountItemsFiltered) { itemRow($0) } }
                    }
                    if !customItemsFiltered.isEmpty {
                        Section(String(localized: "我的模型实例")) { ForEach(customItemsFiltered) { itemRow($0) } }
                    }
                }
            }
            .frame(width: 280)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                if let h = (selectedModel ?? hoverModel) {
                    Text(h.title).font(.headline)
                    Divider()
                    LabeledContent("Provider") { Text(h.provider) }
                    LabeledContent("上下文") { Text("\(h.context) tokens") }
                } else {
                    Text("悬停以查看详情").foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
        }
        .padding(8)
        .onAppear { preselectCurrentModel() }
    }

    @State private var _search = ""
    private var accountItems: [ModelItem] {
        LLMModelsManager.shared.modelCategories.flatMap { cat in
            cat.models.map { m in ModelItem(id: "\(cat.provider)_\(m.name)", title: m.name, provider: cat.provider, context: m.contextLength, source: .account, instanceId: nil) }
        }
    }
    private var customItems: [ModelItem] {
        ProviderStore.shared.providers.map { p in ModelItem(id: p.id, title: p.name, provider: p.provider, context: p.contextLength ?? 4096, source: .custom, instanceId: p.id) }
    }
    private var accountItemsFiltered: [ModelItem] { _search.isEmpty ? accountItems : accountItems.filter { $0.title.localizedCaseInsensitiveContains(_search) } }
    private var customItemsFiltered: [ModelItem] { _search.isEmpty ? customItems : customItems.filter { $0.title.localizedCaseInsensitiveContains(_search) } }

    @ViewBuilder
    private func itemRow(_ item: ModelItem) -> some View {
        HStack { Text(item.title); Spacer() }
            .tag(item)
            .contentShape(Rectangle())
            .onHover { hovering in hoverModel = hovering ? item : nil }
            .onTapGesture { selectModel(item) }
    }

    private func preselectCurrentModel() {
        if conversation.modelSource == "instance", let inst = ProviderStore.shared.providers.first(where: { $0.id == conversation.modelInstanceId }) {
            selectedModel = ModelItem(id: inst.id, title: inst.name, provider: inst.provider, context: inst.contextLength ?? 4096, source: .custom, instanceId: inst.id)
        } else if !conversation.modelId.isEmpty {
            if let m = accountItems.first(where: { $0.title == conversation.modelId }) { selectedModel = m }
        }
    }

    private func selectModel(_ item: ModelItem) {
        switch item.source {
        case .account:
            conversation.modelSource = "account"
            conversation.modelInstanceId = ""
            conversation.modelId = item.title
        case .custom:
            conversation.modelSource = "instance"
            conversation.modelInstanceId = item.instanceId ?? ""
            conversation.modelId = ""
        }
        showModelPopover = false
    }
}
struct CustomTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.vertical, 12)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(.systemGray).opacity(0.3), lineWidth: 1)
                    )
            )
            .foregroundColor(.text)
            .font(.body)
    }
}

enum ConversationPreferenceMode {
    case add
    case edit
    case trial
}
