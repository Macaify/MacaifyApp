//
//  ViewModel.swift
//  XCAChatGPT
//
//  Created by Alfian Losari on 02/02/23.
//

import Foundation
import CoreData
import SwiftUI
import AVKit

class ViewModel: ObservableObject, Equatable {
    static func == (lhs: ViewModel, rhs: ViewModel) -> Bool {
        lhs.conversation.id == rhs.conversation.id
    }

    @Published var isInteractingWithChatGPT = false
    @Published var messages: [MessageRow] = []
    @Published var inputMessage: String = ""
    
    private let synthesizer: AVSpeechSynthesizer
    var enableSpeech: Bool = false
    
    private var api: ChatGPTAPI
    var conversation: GPTConversation
    private var interupted = false
    private var sendTask: Task<Void, Error>? = nil
    
    init(conversation: GPTConversation, api: ChatGPTAPI, enableSpeech: Bool = false) {
        self.conversation = conversation
        self.api = api
        self.enableSpeech = enableSpeech
        synthesizer = .init()
        // Lazy initial load with limit to avoid UI hitch when switching bots
        messages = []
        api.withContext = conversation.withContext
        updateAPIHistory()
        startObserve()
    }

    private let initialLoadLimit: Int = 80

    private var didLoadHistory: Bool = false

    func loadInitialMessagesAsync(limit: Int? = nil) async {
        if didLoadHistory { return }
        let reqLimit = limit ?? initialLoadLimit
        let convID = conversation.objectID
        let container = PersistenceController.shared.container
        do {
            let rows: [MessageRow] = try await withCheckedThrowingContinuation { cont in
                let ctx = container.newBackgroundContext()
                ctx.perform {
                    do {
                        let convBG = try ctx.existingObject(with: convID) as! GPTConversation
                        let req: NSFetchRequest<GPTAnswer> = GPTAnswer.fetchRequest()
                        req.predicate = NSPredicate(format: "belongsTo == %@", convBG)
                        req.sortDescriptors = [NSSortDescriptor(key: "timestamp_", ascending: false)]
                        if reqLimit > 0 { req.fetchLimit = reqLimit }
                        let fetched = try ctx.fetch(req)
                        let answers = fetched.reversed()
                        let mapped = answers.map { ans in
                            MessageRow(isInteractingWithChatGPT: false,
                                       sendImage: "profile",
                                       sendText: ans.prompt,
                                       responseImage: "openai",
                                       responseText: ans.response,
                                       responseError: nil,
                                       clearContextAfterThis: ans.contextClearedAfterThis)
                        }
                        cont.resume(returning: mapped)
                    } catch {
                        cont.resume(throwing: error)
                    }
                }
            }
            await MainActor.run {
                self.messages = rows
                self.didLoadHistory = true
            }
        } catch {
            await MainActor.run {
                self.messages = []
                self.didLoadHistory = true
            }
        }
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
//        print("new history \(api.history)")
    }
    
    @MainActor
    func sendTapped() async {
        let text = inputMessage
        inputMessage = ""
//        print("withContext ? ", conversation.withContext)
        api.withContext = conversation.withContext
        api.systemPrompt = conversation.prompt
        sendTask = Task { @MainActor in
            await send(text: text)
        }
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
        interupted = false
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
            let stream = try await api.chatsStream(text: text)
            let throttle: Double = 0.12
            var lastUpdate: Double = 0
            for try await chunk in stream {
                if interupted { interupted = false; break }
                let delta = chunk.choices.first?.delta.content ?? ""
                guard !delta.isEmpty else { continue }
                streamText += delta
                let now = Date.timeIntervalSinceReferenceDate
                if now - lastUpdate > throttle {
                    lastUpdate = now
                    messageRow.responseText = streamText
                    self.messages[self.messages.count - 1] = messageRow
                }
            }
            // Final update
            messageRow.responseText = streamText
            self.messages[self.messages.count - 1] = messageRow
        } catch {
//        print(error)
        messageRow.responseError = error.localizedDescription
        }
        
        messageRow.isInteractingWithChatGPT = false
        self.messages[self.messages.count - 1] = messageRow
        
        // 保存数据
        if let response = messageRow.responseText, !response.isEmpty {
            let answer = GPTAnswer(role: "user", prompt: messageRow.sendText, response: messageRow.responseText ?? "", parentId: conversation.own.last?.uuid, context: conversation.managedObjectContext!)
            conversation.addAnswer(answer: answer)
        }
        
        isInteractingWithChatGPT = false
        speakLastResponse()
    }
    
    @MainActor
    func interupt() {
        sendTask?.cancel()
        sendTask = nil
        api.interupt()
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
