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
        if !hasAccessibilityPermission() { _ = hasAccessibilityPermission(prompt: true) }
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
                // Mirror to main UI: show ephemeral bubbles while typing-in-place
                NotificationCenter.default.post(name: .init("TypingInPlaceMirrorStart"), object: nil, userInfo: [
                    "convId": conv.id.uuidString,
                    "text": newValue,
                    "sourceBundleId": bid ?? "",
                    "sourceAppName": name ?? ""
                ])
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
                            let delta = answer.choices.first?.delta.content ?? ""
                            guard !delta.isEmpty else { continue }
                            sentence += delta
                            // Mirror streaming delta to main UI
                            NotificationCenter.default.post(name: .init("TypingInPlaceMirrorDelta"), object: nil, userInfo: [
                                "convId": conv.id.uuidString,
                                "delta": delta
                            ])
                            print("sentence \(sentence)", delta)
                        }
                        
                        self.interupt()
                        if !sentence.isEmpty {
                            paste(delay: 0, sentence: sentence)
                            sentence = ""
                        }
                        // Signal finish (UI can persist if desired)
                        NotificationCenter.default.post(name: .init("TypingInPlaceMirrorEnd"), object: nil, userInfo: [
                            "convId": conv.id.uuidString
                        ])
                    }
                    catch {
                        self?.interupt()
                        print("[TIP] stream error: \(error)")
                        NotificationCenter.default.post(name: .init("TypingInPlaceMirrorEnd"), object: nil, userInfo: [
                            "convId": conv.id.uuidString
                        ])
                    }
                }
            }
        }
    } 
    
    func typeInPlace(conv: GPTConversation, context: String, command: String) {
        if !hasAccessibilityPermission() { _ = hasAccessibilityPermission(prompt: true) }
        self.interupt()
        self.api = conv.API
        self.api?.systemPrompt = context
        print("asking api \(command), system prompt \(conv.API.systemPrompt)")
        NotificationCenter.default.post(name: .init("TypingInPlaceMirrorStart"), object: nil, userInfo: [
            "convId": conv.id.uuidString,
            "text": command
        ])
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
                    let delta = answer.choices.first?.delta.content ?? ""
                    guard !delta.isEmpty else { continue }
                    sentence += delta
                    NotificationCenter.default.post(name: .init("TypingInPlaceMirrorDelta"), object: nil, userInfo: [
                        "convId": conv.id.uuidString,
                        "delta": delta
                    ])
                }
                
                self.interupt()
                if !sentence.isEmpty {
                    paste(delay: 0, sentence: sentence)
                    sentence = ""
                }
                NotificationCenter.default.post(name: .init("TypingInPlaceMirrorEnd"), object: nil, userInfo: [
                    "convId": conv.id.uuidString
                ])
            }
            catch {
                self?.interupt()
                print("[TIP] stream error: \(error)")
                NotificationCenter.default.post(name: .init("TypingInPlaceMirrorEnd"), object: nil, userInfo: [
                    "convId": conv.id.uuidString
                ])
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
