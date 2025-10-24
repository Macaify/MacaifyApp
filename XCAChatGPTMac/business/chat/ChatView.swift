//
//  ChatView.swift
//  XCAChatGPTMac
//
//  Created by lixindong on 2023/4/9.
//

import SwiftUI
import BetterAuth
//import AlertToast

struct ChatView: View {
    let conversation: GPTConversation
    let mode: ChatMode
    let onBack: () -> Void
    var id: UUID {
        get {
            conversation.id
        }
    }
    var bottomBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                PlainButton(icon: "clear", label: "删除记录 ⌘D", backgroundColor: ChatTokens.controlBackground, pressedBackgroundColor: ChatTokens.controlBackground.opacity(0.9), shortcut: .init("d"), modifiers: .command, autoShowShortcutHelp: false, showLabel: false) {
                vm.clearMessages()
            }
            .help("删除聊天记录 ⌘D")

            PlainButton(icon: "lasso.sparkles", label: "新聊天 ⌘N", backgroundColor: ChatTokens.controlBackground, pressedBackgroundColor: ChatTokens.controlBackground.opacity(0.9), shortcut: .init("n"), modifiers: .command, autoShowShortcutHelp: false, showLabel: false) {
                vm.clearContext()
            }
            .help("新聊天 ⌘N")

            InputEditor(placeholder: String("Tab to chat"), text: $vm.inputMessage, onShiftEnter: {
                Task { @MainActor in
                    if !vm.inputMessage.isEmpty {
                        scrollSignal &+= 1
                        await vm.sendTapped()
                    }
                }
            })
            .frame(minHeight: ChatTokens.controlHeight, maxHeight: 120)
            .textFieldStyle(.roundedBorder)
            .disabled(vm.isInteractingWithChatGPT)

            if vm.isInteractingWithChatGPT {
                HStack(spacing: 8) {
                    DotLoadingView().frame(width: 40, height: 30)
                    PlainButton(icon: "stop.circle", label: "停止生成", backgroundColor: .red.opacity(0.6), pressedBackgroundColor: .red.opacity(0.7), foregroundColor: .white, shortcut: .init("s"), modifiers: .command) {
                        vm.interupt()
                    }
                }
            } else {
                HStack(spacing: 8) {
                    PlainButton(label: "发送 ↩", backgroundColor: .accentColor, pressedBackgroundColor: .accentColor.opacity(0.9), foregroundColor: .white, shortcut: .return, autoShowShortcutHelp: false, action: {
                        Task { @MainActor in
                            if !vm.inputMessage.isEmpty {
                                scrollSignal &+= 1
                                await vm.sendTapped()
                            }
                        }
                    })
                    .disabled(vm.inputMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(vm.inputMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)

                    PlainButton(label: "使用回答 ⌘↩", backgroundColor: ChatTokens.controlBackground, pressedBackgroundColor: ChatTokens.controlBackground.opacity(0.9), shortcut: .return, modifiers: .command, autoShowShortcutHelp: false) {
                        Task { @MainActor in
                            NSApplication.shared.hide(nil)
                            paste(delay: 0.1, sentence: vm.messages.last?.responseText ?? "")
                        }
                    }
                    .disabled(vm.messages.last?.responseText?.isEmpty ?? true)
                    .opacity(vm.messages.last?.responseText?.isEmpty ?? true ? 0.5 : 1)
                }
            }
            }
            // Session-scoped model selector below the input row, smaller font
            SessionModelPickerButton(bot: conversation, onPicked: { updated in
                updated.save()
                vm.updateAPI(api: updated.API)
            }, openBotSettings: {
                pathManager.to(target: .editCommand(command: conversation))
            })
            .font(.caption)
            .help(String(localized: "选择模型"))
        }
        .padding(.horizontal, 8)
    }
    @ObservedObject var pathManager: PathManager = PathManager.shared
    @ObservedObject var commandStore: ConversationViewModel = ConversationViewModel.shared
    @State var vm: ViewModel
    @AppStorage("proxyAddress") private var proxyAddress = ""
    @AppStorage("useProxy") private var useProxy = false

    @State private var showToast = false

    init(command: GPTConversation, msg: String? = nil, mode: ChatMode = .normal, onBack: @escaping () -> Void) {
        self.conversation = command
        self.mode = mode
        self.onBack = onBack
//        let useVoice = UserDefaults.standard.object(forKey: "useVoice") as? Bool ?? false
//        let api = command.API
//        self.vm = ViewModel(conversation: command, api: api, enableSpeech: useVoice)
        self.vm = ConversationViewModel.shared.commandViewModel(command)
//        print("proxy \(useProxy) \(proxyAddress) \(msg)")
        self.vm.inputMessage = msg ?? ""
    }

    @State private var scrollSignal: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            ChatTableView(vm: vm, onRetry: { message in
                Task { @MainActor in await vm.retry(message: message) }
            }, scrollSignal: $scrollSignal)

            Divider()

            bottomBar
                .padding(6)
                .background(.regularMaterial)
        }
        .background(.background)
        .task {
            // Load history immediately for a snappy feel
            await vm.loadInitialMessagesAsync()
            await MainActor.run {
                if (!vm.isInteractingWithChatGPT && !vm.inputMessage.isEmpty) {
                    scrollSignal &+= 1
                }
            }
            if (!vm.isInteractingWithChatGPT && !vm.inputMessage.isEmpty) {
                await vm.sendTapped()
            }
        }
        .onKeyPressed(.escape) { _ in NSApp.hide(nil); return true }
    }

    
    
    @MainActor
    func setMessage(msg: String?) async {
        print("ChatView setMessage \(msg ?? "nil")")
        self.vm.inputMessage = msg ?? ""
        scrollSignal &+= 1
        await self.vm.sendTapped()
    }
}
//
//struct ChatView_Previews: PreviewProvider {
//    static var previews: some View {
//        ChatView()
//    }
//}

enum ChatMode {
    case normal
    case trial
}
