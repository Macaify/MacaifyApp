//
//  MinimalChatView.swift
//  XCAChatGPTMac
//
//  A simplified chat view that only displays history and sends messages.
//

import SwiftUI

struct MinimalChatView: View {
    let conversation: GPTConversation
    var onBack: (() -> Void)? = nil

    @State private var vm: ViewModel
    @State private var scrollSignal: Int = 0

    init(conversation: GPTConversation, onBack: (() -> Void)? = nil) {
        self.conversation = conversation
        self.onBack = onBack
        _vm = State(initialValue: ConversationViewModel.shared.commandViewModel(conversation))
    }

    var body: some View {
        VStack(spacing: 0) {
            ChatTableView(vm: vm, onRetry: { _ in }, scrollSignal: $scrollSignal)

            Divider()

            HStack(alignment: .center, spacing: 8) {
                InputEditor(placeholder: String("Tab to chat"), text: $vm.inputMessage, onShiftEnter: {
                    Task { @MainActor in await sendIfNeeded() }
                })
                .frame(minHeight: ChatTokens.controlHeight, maxHeight: 120)
                .textFieldStyle(.roundedBorder)
                .disabled(vm.isInteractingWithChatGPT)

                if vm.isInteractingWithChatGPT {
                    DotLoadingView().frame(width: 40, height: 30)
                    PlainButton(icon: "stop.circle", label: "停止", backgroundColor: .red.opacity(0.6), pressedBackgroundColor: .red.opacity(0.7), foregroundColor: .white) {
                        vm.interupt()
                    }
                } else {
                    PlainButton(label: "发送 ↩", backgroundColor: .accentColor, pressedBackgroundColor: .accentColor.opacity(0.9), foregroundColor: .white, shortcut: .return, autoShowShortcutHelp: false) {
                        Task { @MainActor in await sendIfNeeded() }
                    }
                    .disabled(vm.inputMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(vm.inputMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
                }
            }
            .padding(6)
            .background(.regularMaterial)
        }
        .background(.background)
        .task {
            await vm.loadInitialMessagesAsync()
            await MainActor.run {
                if (!vm.isInteractingWithChatGPT && !vm.inputMessage.isEmpty) {
                    scrollSignal &+= 1
                }
            }
        }
        .onKeyPressed(.escape) { _ in NSApp.hide(nil); return true }
    }

    @MainActor
    private func sendIfNeeded() async {
        let text = vm.inputMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        scrollSignal &+= 1
        await vm.sendTapped()
    }
}

