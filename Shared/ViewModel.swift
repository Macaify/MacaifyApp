//
//  ViewModel.swift
//  XCAChatGPT
//
//  Created by Alfian Losari on 02/02/23.
//

import Foundation
import SwiftUI
import AVKit

class ViewModel: ObservableObject {
    
    @Published var isInteractingWithChatGPT = false
    @Published var messages: [MessageRow] = []
    @Published var inputMessage: String = ""
    
    private let synthesizer: AVSpeechSynthesizer
    var enableSpeech: Bool = false
    
    private var api: ChatGPTAPI
    private var conversation: GPTConversation
    
    init(conversation: GPTConversation, api: ChatGPTAPI, enableSpeech: Bool = false) {
        self.conversation = conversation
        self.api = api
        self.enableSpeech = enableSpeech
        synthesizer = .init()
        messages = conversation.own!.array.map({ answer in
            let answer = answer as! GPTAnswer
            return MessageRow(isInteractingWithChatGPT: false, sendImage: "profile", sendText: answer.prompt, responseImage: "openai", responseText: answer.response, clearContextAfterThis: answer.contextClearedAfterThis)
        })
        api.withContext = conversation.withContext
        updateAPIHistory()
        startObserve()
    }
    
    func startObserve() {
        
    }
    
    func updateAPIHistory() {
        // 携带上下文
        let lastCleared = messages.lastIndex { msg in msg.clearContextAfterThis }
        let startIndex = lastCleared == nil ? 0 : lastCleared! + 1
        api.history = messages[startIndex..<messages.count].map { msg in
            [Message(role: "user", content: msg.sendText), Message(role: "assistant", content: msg.responseText ?? "")]
        }
        .flatMap { msgs in msgs }
        print("new history \(api.history)")
    }
    
    @MainActor
    func sendTapped() async {
        let text = inputMessage
        inputMessage = ""
        print("withContext ? ", conversation.withContext)
        api.withContext = conversation.withContext
        await send(text: text)
    }
    
    @MainActor
    func clearMessages() {
        stopSpeaking()
        api.deleteHistoryList()
        PersistenceController.shared.clearAnswers(conversation: conversation)
        withAnimation { [weak self] in
            self?.messages = []
        }
    }
    
    @MainActor
    func clearContext() {
        stopSpeaking()
        api.deleteHistoryList()
        PersistenceController.shared.clearContext(conversation: conversation)
        if var last = self.messages.last {
            print("clearContext on \(last)")
            last.clearContextAfterThis = true
            self.messages[messages.count - 1] = last
            print("clearContext after \(self.messages)")
        }
    }
    
    @MainActor
    func retry(message: MessageRow) async {
        guard let index = messages.firstIndex(where: { $0.id == message.id }) else {
            return
        }
        self.messages.remove(at: index)
        await send(text: message.sendText)
    }
    
    @MainActor
    private func send(text: String) async {
        isInteractingWithChatGPT = true
        var streamText = ""
        var messageRow = MessageRow(
            isInteractingWithChatGPT: true,
            sendImage: "profile",
            sendText: text,
            responseImage: "openai",
            responseText: streamText,
            responseError: nil)
        
        self.messages.append(messageRow)
        
        do {
            let stream = try await api.sendMessageStream(text: text)
            for try await text in stream {
                streamText += text
                messageRow.responseText = streamText.trimmingCharacters(in: .whitespacesAndNewlines)
                self.messages[self.messages.count - 1] = messageRow
            }
        } catch {
            messageRow.responseError = error.localizedDescription
        }
        
        messageRow.isInteractingWithChatGPT = false
        self.messages[self.messages.count - 1] = messageRow
        PersistenceController.shared.addAnswer(conversation: conversation, role: "user", response: messageRow.responseText ?? "", prompt: messageRow.sendText, parentId: (conversation.own?.array.last as? GPTAnswer)?.uuid)
        isInteractingWithChatGPT = false
        speakLastResponse()
    }
    
    func speakLastResponse() {
        if (!enableSpeech) {
            return
        }
        guard let responseText = self.messages.last?.responseText, !responseText.isEmpty else {
            return
        }
        stopSpeaking()
        let utterance = AVSpeechUtterance(string: responseText)
        utterance.voice = .init()
        utterance.rate = 0.5
        utterance.pitchMultiplier = 0.8
        utterance.postUtteranceDelay = 0.2
        synthesizer.speak(utterance )
    }
    
    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
    }
    
    func disableProxy() {
        api.disableProxy()
    }
    
    func useProxy(proxy: String) {
        api.useProxy(proxy: proxy)
    }
    
    func updateAPI(api: ChatGPTAPI) {
        api.history = self.api.history
        self.api = api
    }
}
