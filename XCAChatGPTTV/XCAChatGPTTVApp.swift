//
//  XCAChatGPTTVApp.swift
//  XCAChatGPTTV
//
//  Created by Alfian Losari on 05/02/23.
//

import SwiftUI

@main
struct XCAChatGPTTVApp: App {
    
    @StateObject var vm = ViewModel(api: ChatGPTAPI(apiKey: "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"), enableSpeech: true)
    
    @FocusState var isTextFieldFocused: Bool
    
    var body: some Scene {
        WindowGroup {
            VStack {
                Text("XCA ChatGPT").font(.largeTitle)
                HStack(alignment: .top) {
                    ContentView(vm: vm)
                        .cornerRadius(32)
                        .overlay {
                            if vm.messages.isEmpty {
                                Text("click_to_start")
                                    .multilineTextAlignment(.center)
                                    .font(.headline)
                                    .foregroundColor(Color(UIColor.placeholderText))
                            } else {
                                EmptyView()
                            }
                        }
                    
                    VStack {
                        TextField("send", text: $vm.inputMessage)
                        .multilineTextAlignment(.center)
                        .frame(width: 176)
                        .focused($isTextFieldFocused)
                        .disabled(vm.isInteractingWithChatGPT)
                        .onSubmit {
                            Task { @MainActor in
                                await vm.sendTapped()
                                isTextFieldFocused = true
                            }
                        }
                        .onChange(of: isTextFieldFocused) { _  in
                            vm.inputMessage = ""
                        }
                        
                        Button("clear", role: .destructive) {
                            vm.clearMessages()
                        }
                        .frame(width: 176)
                        .disabled(vm.isInteractingWithChatGPT || vm.messages.isEmpty)
                        
                        
                        ProgressView()
                            .progressViewStyle(.circular)
                            .padding()
                            .opacity(vm.isInteractingWithChatGPT ? 1 : 0)
                    }
                }
            }
        }
    }
}
