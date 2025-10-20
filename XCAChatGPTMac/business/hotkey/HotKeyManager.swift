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
    
    static func register(_ conversation: GPTConversation) {
        KeyboardShortcuts.onKeyDown(for: conversation.Name) { [self] in
            NSLog("key pressed \(conversation.autoAddSelectedText) conversation \(conversation.id) autoAdd \(conversation.autoAddSelectedText)")

            print("top is found \(NSApplication.shared.isActive)")
//            print("top is Main \(case .main = PathManager.shared.top)")

            let isActive = NSApplication.shared.isActive

            if conversation.typingInPlace {
                TypingInPlace.shared.typeInPlace(conv: conversation)
            } else if isActive {
                PathManager.shared.toChat(conversation, msg: MainViewModel.shared.searchText)
                // Notify SwiftUI main split view to focus this bot and inject context
                NotificationCenter.default.post(name: .init("QuickChatSelectedText"), object: nil, userInfo: [
                    "convId": conversation.id.uuidString,
                    "text": MainViewModel.shared.searchText ?? ""
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
                    NotificationCenter.default.post(name: .init("QuickChatSelectedText"), object: nil, userInfo: [
                        "convId": conversation.id.uuidString,
                        "text": text ?? ""
                    ])
                    resume()
                }
            } else {
                // No auto text; still open and focus the bot
                NotificationCenter.default.post(name: .init("QuickChatSelectedText"), object: nil, userInfo: [
                    "convId": conversation.id.uuidString,
                    "text": ""
                ])
                resume()
                PathManager.shared.toChat(conversation)
            }
        }
    }
}

func resume() {
    if let w = NSApp.windows.first {
        w.makeKeyAndOrderFront(nil)
    }
    NSApp.activate(ignoringOtherApps: true)
}

func toggleMainWindow() {
    if let w = NSApp.windows.first {
        if NSApp.isActive && w.isKeyWindow {
            NSApp.hide(nil)
        } else {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    } else {
        NSApp.activate(ignoringOtherApps: true)
    }
}
