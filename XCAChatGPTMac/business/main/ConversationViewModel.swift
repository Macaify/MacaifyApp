//
//  CommandStore.swift
//  XCAChatGPTMac
//
//  Created by lixindong on 2023/4/8.
//

import Foundation
import SwiftUI
import KeyboardShortcuts
import Defaults

class ConversationViewModel: ObservableObject {
    
    static let shared = ConversationViewModel()
    
    @Published var conversations: [GPTConversation] = []
    @Published var filteredConvs: [GPTConversation] = []
    
    // 当前进行的聊天
    @Published var currentChat: GPTConversation?
    
    // 选中的列表项下标
    @Published var hoveredCommand: GPTConversation?
    var selectedItemIndex: Int {
        get {
            if let hoveredCommand {
                return conversations.firstIndex(of: hoveredCommand) ?? -1
            } else {
                return -1
            }
        }
        set {
            hoveredCommand = conversations.indices.contains(newValue) ? conversations[newValue] : nil
        }
    }

    private let userDefaults = UserDefaults.standard
    private let commandsKey = "commands"
    private var viewModels: [UUID: ViewModel] = [:]

    var useVoice: Bool {
        UserDefaults.standard.object(forKey: "useVoice") as? Bool ?? false
    }

    //    let menuBarCommand = GPTConversation("showMenuBar", autoAddSelectedText: false)
    
    //    var menuViewModel: ViewModel {
    //        commandViewModel(menuBarCommand)
    //    }

    var selectedCommandOrDefault: GPTConversation {
        conversations.indices.contains(selectedItemIndex) ? conversations[selectedItemIndex] : GPTConversation.empty
    }

    var selectedCommand: GPTConversation? {
        conversations.indices.contains(selectedItemIndex) ? conversations[selectedItemIndex] : nil
    }
    
    init() {
        self.loadCommands()
    }
    
    func updateCommand(command: GPTConversation) {
        command.save()
        notifyConversationChanged()
    }
    
    func addCommand(command: GPTConversation) {
        command.copyToCoreData().save()
        notifyConversationChanged()
    }
    
    func removeCommand(at indexSet: IndexSet) {
        indexSet.forEach { index in
            conversations[index].delete()
        }
        notifyConversationChanged()
    }
    
    func removeCommand(_ command: GPTConversation) {
        command.delete()
        notifyConversationChanged()
    }
    
    func commandViewModel(_ conversation: GPTConversation) -> ViewModel {
        let id = conversation.id
        let useVoice = UserDefaults.standard.object(forKey: "useVoice") as? Bool ?? false
        let api = conversation.API
        if let viewModel = viewModels[id] {
            viewModel.updateAPI(api: api)
            viewModel.enableSpeech = useVoice
            return viewModel
        } else {
            let viewModel = ViewModel(conversation: conversation, api: api, enableSpeech: useVoice)
            viewModels[id] = viewModel
            return viewModel
        }
    }
    
    func loadCommands() {
        conversations = PersistenceController.shared.loadConversations()
        applySavedOrder()
        updateSelectedIndex()
        print("CommandStore loadCommands", conversations.count)
    }
    
    func indexOf(conv: GPTConversation) -> Int {
        for i in conversations.indices {
            if conv.id == conversations[i].id {
                return i
            }
        }
        return -1
    }
    
    private func notifyConversationChanged() {
        loadCommands()
        HotKeyManager.initHotKeys()
    }
    
    private func updateSelectedIndex() {
        let count = conversations.count
        if (selectedItemIndex >= count) {
            selectedItemIndex = count - 1
        }
        if (selectedItemIndex < 0) {
            selectedItemIndex = -1
        }
    }

    // MARK: - Reordering support
    func moveCommands(from source: IndexSet, to destination: Int) {
        conversations.move(fromOffsets: source, toOffset: destination)
        persistOrder()
    }

    private func persistOrder() {
        let ids = conversations.map { $0.id.uuidString }
        Defaults[.conversationOrder] = ids
    }

    private func applySavedOrder() {
        let saved = Defaults[.conversationOrder]
        guard !saved.isEmpty else { return }
        let indexMap = Dictionary(uniqueKeysWithValues: saved.enumerated().map { ($1, $0) })
        conversations.sort { a, b in
            let ia = indexMap[a.id.uuidString] ?? Int.max
            let ib = indexMap[b.id.uuidString] ?? Int.max
            if ia != ib { return ia < ib }
            return a.timestamp > b.timestamp
        }
    }
}

extension GPTConversation {
    
    var API: ChatGPTAPI {
        // Resolve source and model for this conversation
        var modelId = ModelSelectionManager.shared.getSelectedModelId()
        var provider = Defaults[.selectedProvider]
        var apiKey = Defaults[.apiKey]
        var baseURL = Defaults[.proxyAddress]
        var maxTok = Defaults[.maxToken]

        if modelSource == "instance", let inst = ProviderStore.shared.providers.first(where: { $0.id == modelInstanceId }), let token = ProviderStore.shared.token(for: inst.id) {
            // Per-bot custom instance
            modelId = inst.modelId
            provider = inst.provider
            apiKey = token
            baseURL = inst.baseURL
            if let ctx = inst.contextLength, ctx > 0 { maxTok = ctx }
        } else {
            // Use bot-specific account model if specified; otherwise fallback to global defaults
            if modelSource == "account" && !modelId.isEmpty {
                if let info = providerForAccountModel(modelId) {
                    provider = info.provider
                    if info.context > 0 { maxTok = info.context }
                }
            } else if Defaults[.defaultSource] == "provider" {
                let instanceId = Defaults[.selectedProviderInstanceId]
                if let inst = ProviderStore.shared.providers.first(where: { $0.id == instanceId }), let token = ProviderStore.shared.token(for: inst.id) {
                    modelId = inst.modelId
                    provider = inst.provider
                    apiKey = token
                    baseURL = inst.baseURL
                    if let ctx = inst.contextLength, ctx > 0 { maxTok = ctx }
                }
            }
        }
        return ChatGPTAPI(apiKey: apiKey, model: modelId, provider: provider, maxToken: maxTok, systemPrompt: prompt, temperature: 0.5, baseURL: baseURL)
    }

    private func providerForAccountModel(_ modelName: String) -> (provider: String, context: Int)? {
        for cat in LLMModelsManager.shared.modelCategories {
            if let m = cat.models.first(where: { $0.name == modelName }) {
                return (cat.provider, m.contextLength)
            }
        }
        return nil
    }
    
    var shortcutDescription: String {
//        "\(KeyboardShortcuts.getShortcut(for: KeyboardShortcuts.Name(uuid.uuidString)))"
        ""
    }

    static var empty: GPTConversation {
        get {
            GPTConversation(String(localized: "Ask a Question", locale: Locale(identifier: "en"), comment: ""), icon: "✨", withContext: true)
        }
    }
}
