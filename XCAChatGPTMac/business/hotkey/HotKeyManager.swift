//
//  HotkeyHandler.swift
//  XCAChatGPTMac
//
//  Created by lixindong on 2023/4/8.
//

import Foundation
import KeyboardShortcuts
import AppKit
import SwiftUI

class HotKeyManager {
    
    static let shared = HotKeyManager()

    static func initHotKeys() {
        KeyboardShortcuts.removeAllHandlers()
        migrateLegacyShortcuts()
        
//        KeyboardShortcuts.onKeyDown(for: .search) {
////            if !CMDKWindowController.shared.isVisible {
////                CMDKWindowController.shared.showWindow()
////            } else {
////                CMDKWindowController.shared.closeWindow()
////            }
//            StartupPasteboardManager.shared.startup { text in
//                print("got text", text, isCodeSnippet(text ?? ""))
//                CMDKWindowController.shared.viewModel.context = text ?? ""
//                
//                if !CMDKWindowController.shared.isVisible {
//                    CMDKWindowController.shared.showWindow()
//                } else {
////                    CMDKWindowController.shared.closeWindow()
//                }
//            }
//        }
//        
        KeyboardShortcuts.onKeyDown(for: .quickAsk) { [self] in
            NSLog("key pressed \(Bundle.main.bundleIdentifier)")
            
            if appShortcutOption() == "custom" {
                toggleMainWindow()
            }
        }

        ConversationViewModel.shared.conversations.forEach { conversation in
            HotKeyManager.register(conversation)
        }

        KeyboardShortcuts.onKeyDown(for: .menuBar) { [self] in
            NSLog("key pressed")
            let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.antiless.XCAChatGPTMac").first
            print("app is nil ? \(app)")
            NSApplication.shared.activate(ignoringOtherApps: true)
//            self.window.makeKeyAndOrderFront(nil)
            app?.activate(options: [.activateAllWindows])
        }
    }
    
    // 将旧的单一快捷键迁移到新模式化快捷键
    static func migrateLegacyShortcuts() {
        ConversationViewModel.shared.conversations.forEach { conv in
            let old = KeyboardShortcuts.getShortcut(for: conv.Name)
            let edit = KeyboardShortcuts.getShortcut(for: conv.NameEdit)
            let chat = KeyboardShortcuts.getShortcut(for: conv.NameChat)
            guard let old = old else { return }
            // 仅在新键位均未设置时迁移，避免覆盖用户已设置的键位
            if edit == nil && chat == nil {
                if conv.typingInPlace {
                    KeyboardShortcuts.setShortcut(old, for: conv.NameEdit)
                } else {
                    KeyboardShortcuts.setShortcut(old, for: conv.NameChat)
                }
            }
            // 无论是否迁移，清理旧键位，避免重复触发
            KeyboardShortcuts.reset(conv.Name)
        }
    }

    static func register(_ conversation: GPTConversation) {
        KeyboardShortcuts.onKeyDown(for: conversation.Name) { [self] in
            NSLog("key pressed \(conversation.autoAddSelectedText) conversation \(conversation.id) autoAdd \(conversation.autoAddSelectedText)")

            print("top is found \(NSApplication.shared.isActive)")
//            print("top is Main \(case .main = PathManager.shared.top)")

            let isActive = NSApplication.shared.isActive

            if conversation.typingInPlace {
                TypingInPlace.shared.typeInPlace(conv: conversation)
            } else if isActive {
                PathManager.shared.toChat(conversation, msg: "")
                // Notify SwiftUI main split view to focus this bot and inject context
                let eid = UUID().uuidString
                print("[QC_POST] id=\(eid) name=QuickChatSelectedText conv=\(conversation.id) len=0")
                NotificationCenter.default.post(name: .init("QuickChatSelectedText"), object: nil, userInfo: [
                    "eventId": eid,
                    "convId": conversation.id.uuidString,
                    "text": ""
                ])
            } else if (conversation.autoAddSelectedText) {
                StartupPasteboardManager.shared.startup { text in
                    switch PathManager.shared.top {
                    case .chat(let command, _,_):
                        print("tapped text \(text)")
                        PathManager.shared.toChat(conversation, msg: text)
                        if command.id == conversation.id {
                            if let text = text, !text.isEmpty {
                                let vm = ConversationViewModel.shared.commandViewModel(conversation)
                                print("copy text \(text) to viewmodel \(vm)")
                                vm.inputMessage = text
                                Task { @MainActor in
                                    if (!vm.isInteractingWithChatGPT && !vm.inputMessage.isEmpty) {
                                        await vm.sendTapped()
                                    }
                                }
                            }
                        }
                    default:
                        PathManager.shared.toChat(conversation, msg: text)
                    }

                    // Broadcast selection to SwiftUI main split view as well
                    let eid = UUID().uuidString
                    print("[QC_POST] id=\(eid) name=QuickChatSelectedText conv=\(conversation.id) len=\(text?.count ?? 0)")
                    NotificationCenter.default.post(name: .init("QuickChatSelectedText"), object: nil, userInfo: [
                        "eventId": eid,
                        "convId": conversation.id.uuidString,
                        "text": text ?? ""
                    ])
                    resume()
                }
            } else {
                // No auto text; still open and focus the bot
                let eid = UUID().uuidString
                print("[QC_POST] id=\(eid) name=QuickChatSelectedText conv=\(conversation.id) len=0")
                NotificationCenter.default.post(name: .init("QuickChatSelectedText"), object: nil, userInfo: [
                    "eventId": eid,
                    "convId": conversation.id.uuidString,
                    "text": ""
                ])
                resume()
                PathManager.shared.toChat(conversation)
            }
        }

        // Additional explicit bindings for two-mode shortcuts
        if KeyboardShortcuts.getShortcut(for: conversation.NameEdit) != nil {
            KeyboardShortcuts.onKeyDown(for: conversation.NameEdit) { [self] in
                NSLog("edit-mode hotkey pressed for \(conversation.id)")
                TypingInPlace.shared.typeInPlace(conv: conversation)
            }
        }
        if KeyboardShortcuts.getShortcut(for: conversation.NameChat) != nil {
            KeyboardShortcuts.onKeyDown(for: conversation.NameChat) { [self] in
                NSLog("chat-mode hotkey pressed for \(conversation.id)")
                // 根据设置分两种模式：true=直接发送；false=作为上下文
                let sendDirectly = conversation.autoAddSelectedText
                StartupPasteboardManager.shared.startup { text in
                    let bundleId = StartupPasteboardManager.shared.currentSourceBundleId ?? ""
                    let appName = StartupPasteboardManager.shared.currentSourceAppName ?? ""
                    resume()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        if sendDirectly {
                            let eid = UUID().uuidString
                            print("[QC_POST] id=\(eid) name=QuickChatSendSelectedText conv=\(conversation.id) len=\(text?.count ?? 0)")
                            NotificationCenter.default.post(name: .init("QuickChatSendSelectedText"), object: nil, userInfo: [
                                "eventId": eid,
                                "convId": conversation.id.uuidString,
                                "text": text ?? ""
                            ])
                        } else {
                            let eid = UUID().uuidString
                            print("[QC_POST] id=\(eid) name=QuickChatSelectedText conv=\(conversation.id) len=\(text?.count ?? 0)")
                            NotificationCenter.default.post(name: .init("QuickChatSelectedText"), object: nil, userInfo: [
                                "eventId": eid,
                                "convId": conversation.id.uuidString,
                                "text": text ?? "",
                                "sourceBundleId": bundleId,
                                "sourceAppName": appName
                            ])
                        }
                    }
                }
            }
        }
    }
}

func resume() {
    // 只通过 WindowGroup(id: "main") 打开主窗口，不遍历 NSApp.windows
    if let open = WindowBridge.shared.openMainWindow {
        open()
    }
    NSApp.activate(ignoringOtherApps: true)
}

func toggleMainWindow() {
    // 简化：直接打开 WindowGroup(id: "main") 的窗口
    if let open = WindowBridge.shared.openMainWindow { open() }
    NSApp.activate(ignoringOtherApps: true)
}
