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

    // 选中的列表项下标
    @Published var selectedItemIndex = 0

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

    init() {
        self.loadCommands()
        updateSelectedIndex()
    }

    func updateCommand(command: GPTConversation) {
        command.save()
        notifyConversationChanged()
    }
    
    func addCommand(command: GPTConversation) {
        command.copyToCoreData().save()
        notifyConversationChanged()
    }

    func removeCommand(_ command: GPTConversation) {
        PersistenceController.shared.deleteConversation(conversation: command)
        notifyConversationChanged()
    }

    func commandViewModel(for id: UUID) -> ViewModel {
        let command = conversations.first(where: { $0.id == id }) ?? GPTConversation.empty
        return commandViewModel(command)
    }

    func commandViewModel(_ command: GPTConversation) -> ViewModel {
        let id = command.id
        let useVoice = UserDefaults.standard.object(forKey: "useVoice") as? Bool ?? false
        let api = command.API
        if let viewModel = viewModels[id] {
            viewModel.updateAPI(api: api)
            viewModel.enableSpeech = useVoice
            return viewModel
        } else {
            let viewModel = ViewModel(api: api, enableSpeech: useVoice)
            viewModels[id] = viewModel
            return viewModel
        }
    }
    private func loadCommands() {
        conversations = PersistenceController.shared.loadConversations()
        updateSelectedIndex()
        print("CommandStore loadCommands", conversations)
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
            selectedItemIndex = 0
        }
    }
}

extension GPTConversation {
    // Updated to use per-conversation model selection (account or custom instance)
    var API: ChatGPTAPI {
        var model = self.modelId
        var provider = "openai"
        var baseURL = ""
        var key: String = ""
        var maxTok = Defaults[.maxToken]
        var useAccountGateway = false

        let source = self.modelSource
        if source == "instance", let inst = ProviderStore.shared.providers.first(where: { $0.id == self.modelInstanceId }) {
            model = inst.modelId
            provider = (inst.provider == "compatible" ? "openai" : inst.provider)
            baseURL = inst.baseURL
            key = ProviderStore.shared.token(for: inst.id) ?? ""
            if let ctx = inst.contextLength, ctx > 0 { maxTok = ctx }
        } else {
            let selected = model.isEmpty ? Defaults[.selectedModelId] : model
            model = selected.isEmpty ? "macaify-1-mini" : selected
            if let prov = ModelSelectionManager.shared.modelsByProvider.first(where: { (_, arr) in arr.contains(where: { $0.slug == model }) })?.key {
                provider = prov
                if let ctx = ModelSelectionManager.shared.modelsByProvider[prov]?.first(where: { $0.slug == model })?.contextTokens, let ctx = ctx, ctx > 0 {
                    maxTok = ctx
                }
            } else {
                provider = Defaults[.selectedProvider].isEmpty ? "openai" : Defaults[.selectedProvider]
            }
            useAccountGateway = true
            baseURL = ""
            key = ""
        }
        return ChatGPTAPI(apiKey: key, model: model, provider: provider, maxToken: maxTok, systemPrompt: prompt, temperature: 0.5, baseURL: baseURL, withContext: withContext, useAccountGateway: useAccountGateway)
    }
    
    var shortcutDescription: String {
        KeyboardShortcuts.getShortcut(for: KeyboardShortcuts.Name(uuid.uuidString))?.description ?? ""
    }
    
    static var empty: GPTConversation {
        get {
            GPTConversation("")
        }
    }
}
