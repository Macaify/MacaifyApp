//
//  ContentView.swift
//  XCAChatGPT
//
//  Created by Alfian Losari on 01/02/23.
//

import SwiftUI
import AVKit
import Combine

struct ContentView: View {
    
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject var vm: ViewModel
    @FocusState var isTextFieldFocused: Bool
    @State var scrolledByUser = false
    // Simplify input sizing to reduce layout cost
    @State var resetHovered: Bool = false
    @State var newHovered: Bool = false
    // Keep input local to avoid publishing each keystroke to vm
    @State private var localInput: String = ""

    var body: some View {
        ZStack {
            Color.clear
            chatListView
        }
    }

    var emptyView: some View {
        ZStack(alignment: .center) {
            Color.clear
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("cmd_d").font(.body).foregroundColor(.text)
                    Text("cmd_n").font(.body).foregroundColor(.text)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("delete_chat_history").font(.body).foregroundColor(.text)
                    Text("clear_context_start_new_chat").font(.body).foregroundColor(.text)
                }
            }
        }
    }
    
    var chatListView: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                if vm.messages.isEmpty {
                    emptyView
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(vm.messages) { message in
                                MessageRowView(message: message, tag: "\(message.id.uuidString.prefix(1))") { message in
                                    Task { @MainActor in
                                        await vm.retry(message: message)
                                    }
                                }.id(message.id)
                            }
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom, content: {
                VStack(spacing: 0) {
                    Divider()
                    bottomView(image: "profile", proxy: proxy)
                        .padding(4)
                }
                .background(.background)
                .background(.regularMaterial)
                .shadow(color: .gray.opacity(0.03), radius: 8, x: 0, y: 1)
            })
            .onChange(of: vm.messages.last?.responseText) { _ in
                throttleScrollToBottom(proxy: proxy)
            }
            .onChange(of: vm.messages.last?.clearContextAfterThis) { _ in
                scrollToBottom(proxy: proxy)
            }
            .onAppear {
                DispatchQueue.main.async {
                    scrollToBottom(proxy: proxy)
                    isTextFieldFocused = true
                }
                trackScrollWheel()
            }
        }
        .background(.background)
//        .background(.regularMaterial)
    }
    
    
    func trackScrollWheel() {
        NSApplication.shared.publisher(for: \.currentEvent)
            .filter { event in event?.type == .scrollWheel }
            .throttle(for: .milliseconds(200),
                      scheduler: DispatchQueue.main,
                      latest: true)
            .sink { [weak vm] event in
                if let deltaY = event?.deltaY, deltaY > 0 {
                    scrolledByUser = true
                }
            }
            .store(in: &subs)
    }

    @State var subs = Set<AnyCancellable>() // Cancel onDisappear

    func bottomView(image: String, proxy: ScrollViewProxy) -> some View {
        HStack(alignment: .center, spacing: 8) {
            PlainButton(icon: "clear", label: "delete_record_cmd_d", shortcut: .init("d"), modifiers: .command, autoShowShortcutHelp: false, showLabel: resetHovered) {
                vm.clearMessages()
            }
            .help("delete_chat_history_cmd_d")
            .onHover { hover in
                resetHovered = hover
            }
            PlainButton(icon: "lasso.sparkles", label: "new_chat_cmd_n", shortcut: .init("n"), modifiers: .command, autoShowShortcutHelp: false, showLabel: newHovered) {
                vm.clearContext()
            }
            .help("new_chat_cmd_n")
            .onHover { hover in
                newHovered = hover
            }
            InputEditor(placeholder: String(localized: "tap_to_chat"), text: $localInput, onShiftEnter: {
                Task { @MainActor in
                    if !localInput.isEmpty {
                        scrolledByUser = false
                        scrollToBottom(proxy: proxy)
                        vm.inputMessage = localInput
                        await vm.sendTapped()
                        localInput = ""
                    }
                }
            })
            .frame(minHeight: 32, maxHeight: 120)
#if os(iOS) || os(macOS)
                .textFieldStyle(.roundedBorder)
#endif
                .focused($isTextFieldFocused)
                .disabled(vm.isInteractingWithChatGPT)
                .task {
                    isTextFieldFocused = true
                    localInput = vm.inputMessage
                }

            if vm.isInteractingWithChatGPT {
                HStack {
                    DotLoadingView().frame(width: 40, height: 30)
                    PlainButton(icon: "stop.circle", label: "stop_generating", backgroundColor: Color.hex(0xFF0000).opacity(0.5), foregroundColor: .white, shortcut: .init("s"), modifiers: .command) {
                        scrolledByUser = false
                        vm.interupt()
                    }
                }
            } else {
                HStack {
                    // Only send on Command+Enter to avoid conflicting with IME Enter
                    PlainButton(label: "send_enter", backgroundColor: .purple, foregroundColor: .white, shortcut: .return, modifiers: .command, autoShowShortcutHelp: false, action: {
                        Task { @MainActor in
                            if !localInput.isEmpty {
                                scrolledByUser = false
                                scrollToBottom(proxy: proxy)
                                vm.inputMessage = localInput
                                await vm.sendTapped()
                                localInput = ""
                            }
                        }
                    })
                    .disabled(localInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(localInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)

                    PlainButton(label: "use_response_cmd_enter", shortcut: .return, modifiers: .command, autoShowShortcutHelp: false) {
                        print("mini")
                        Task { @MainActor in
                            print("mini")
//                            copy(text: vm.messages.last?.responseText ?? "")
                            NSApplication.shared.hide(nil)
//                            NSApplication.shared.windows.first?.miniaturize(nil)
                            paste(delay: 0.1, sentence: vm.messages.last?.responseText ?? "")
                        }
                    }
                    .disabled(vm.messages.last?.responseText?.isEmpty ?? true)
                    .opacity(vm.messages.last?.responseText?.isEmpty ?? true ? 0.5 : 1)
                }
            }
        }
        .padding(.horizontal, 8)
//        .animation(.easeInOut)
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard let id = vm.messages.last?.id else { return }
        proxy.scrollTo(id, anchor: .bottom)
    }

    // Reduce excessive scroll invocations during streaming
    @State private var lastScrollTime: TimeInterval = 0
    private func throttleScrollToBottom(proxy: ScrollViewProxy) {
        guard !scrolledByUser else { return }
        let now = Date.timeIntervalSinceReferenceDate
        if now - lastScrollTime > 0.06 {
            lastScrollTime = now
            scrollToBottom(proxy: proxy)
        }
    }
}
struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// Removed dynamic text width tracking to reduce layout work
