//
//  TypingInPlace.swift
//  Found
//
//  Created by lixindong on 2023/5/14.
//

import Foundation
import KeyboardShortcuts
import AppKit

class TypingInPlace: ObservableObject {
    static let shared = TypingInPlace()
    
    @Published var typing: Bool = false
    private var sendTask: Task<Void, Error>? = nil
    private var api: ChatGPTAPI? = nil
    private var pasteTimer: Timer? = nil
    
    func typeInPlace(conv: GPTConversation) {
        let (bid, name) = frontmostAppInfo()
        print("[TIP] frontmost before copy: \(bid ?? "?") / \(name ?? "?")")
        // Try AX first for better reliability
        var captured = getSelectedTextAX()
        if captured == nil || captured?.isEmpty == true {
            performGlobalCopyShortcut()
        }
        // Give the target app a bit more time to update clipboard when using Cmd+C
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            if captured == nil || captured?.isEmpty == true {
                let cp = getLatestTextFromPasteboard()
                print("newClip", cp.text as Any, cp.time as Any)
                captured = cp.text
            }
            var newValue = captured ?? ""

            if (!newValue.isEmpty) {
                self.interupt()
                self.api = conv.API
                print("asking api \(newValue)")
                self.sendTask = Task { [weak self] in
                    do {
                        guard let self = self else { return }
                        guard let api = self.api else { return }
                        TypingInPlace.shared.typing = true
                        api.systemPrompt += "用户输入："
                        let stream = try await api.chatsStream(text: newValue)
                        var sentence = ""
                        var puncted = false
                        let isNotion = isInNotion()
                        print("isNotion \(isNotion)")
                        
                        self.pasteTimer = Timer.scheduledTimer(withTimeInterval: 1.0/3.0, repeats: true) { timer in
                            if !sentence.isEmpty {
                                paste(delay: 0, sentence: sentence)
                                sentence = ""
                            }
                        }
                        for try await answer in stream {
                            sentence += answer.choices.first?.delta.content ?? ""
                            print("sentence \(sentence)", answer.choices.first?.delta.content)
                        }
                        
                        self.interupt()
                        if !sentence.isEmpty {
                            paste(delay: 0, sentence: sentence)
                            sentence = ""
                        }
                    }
                    catch {
                        self?.interupt()
                        print("[TIP] stream error: \(error)")
                    }
                }
            }
        }
    } 
    
    func typeInPlace(conv: GPTConversation, context: String, command: String) {
        self.interupt()
        self.api = conv.API
        self.api?.systemPrompt = context
        print("asking api \(command), system prompt \(conv.API.systemPrompt)")
        self.sendTask = Task { [weak self] in
            do {
                guard let self = self else { return }
                guard let api = self.api else { return }
                Task { @MainActor in
                    TypingInPlace.shared.typing = true
                }
                let stream = try await api.chatsStream(text: command)
                var sentence = ""
                var puncted = false
                let isNotion = isInNotion()
                print("isNotion \(isNotion)")
                
                self.pasteTimer = Timer.scheduledTimer(withTimeInterval: 1.0/3.0, repeats: true) { timer in
                    if !sentence.isEmpty {
                        paste(delay: 0, sentence: sentence)
                        sentence = ""
                    }
                }
                for try await answer in stream {
                    sentence += answer.choices.first?.delta.content ?? ""
                }
                
                self.interupt()
                if !sentence.isEmpty {
                    paste(delay: 0, sentence: sentence)
                    sentence = ""
                }
            }
            catch {
                self?.interupt()
                print("[TIP] stream error: \(error)")
            }
        }
    }
    
    func interupt() {
        sendTask?.cancel()
        sendTask = nil
        
        api?.interupt()
        api = nil
        
        Task { @MainActor in
            typing = false
        }
        
        pasteTimer?.invalidate()
        pasteTimer = nil
    }
}

private var queue = DispatchQueue(label: "trans")

func paste(delay: CGFloat, sentence: String) {
    queue.asyncAfter(deadline: .now() + delay) {
        copy(text: sentence)
//        print("copy into clipboard")
        // Let pasteboard propagate before issuing Cmd+V
        usleep(65_000)
        performGlobalPasteShortcut()
        let (bid, name) = frontmostAppInfo()
        print("paste -> frontmost: \(bid ?? "?") / \(name ?? "?") len=\(sentence.count)")
    }
}

func isInNotion() -> Bool {
    let notionBundleID = "notion.id"

    return NSWorkspace.shared.frontmostApplication?.bundleIdentifier == notionBundleID
}
