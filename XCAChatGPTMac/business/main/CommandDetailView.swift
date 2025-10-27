//
//  CommandDetailView.swift
//  XCAChatGPTMac
//
//  Created by lixindong on 2023/4/9.
//

import SwiftUI
import MarkdownUI

struct CommandDetailView: View {
    @Environment(\.scenePhase) private var scenePhase

    @EnvironmentObject var pathManager: PathManager
    var command: GPTConversation
    @State var icon: Emoji? = nil
    @State var isShowingPopover = false

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Group {
                        ConversationIconView(conversation: command, size: 40).id(command.icon)
                    }
                    .onTapGesture {
                        isShowingPopover.toggle()
                    }
                    .popover(isPresented: $isShowingPopover) {
                        EmojiPickerView(selectedEmoji: $icon)
                    }
                    .onChange(of: icon?.emoji) { newValue in
                        print("emoji selected")
//                        if let icon = newValue {
                            print("emoji selected \(newValue)")
                            command.icon = newValue ?? ""
                            ConversationViewModel.shared.updateCommand(command: command)
//                        }
                    }
                    
                    Spacer()
                    PlainButton(icon: "slider.horizontal.3", label: "edit", shortcut: .init("e"), modifiers: .command) {
                        print("edit command \(command.id) \(command.name)")
                        pathManager.to(target: .editCommand(command: command))
                    }
                }
                HStack(alignment: .bottom) {
                    Text(command.name)
                        .font(.title)
                }
                .padding(.top, 8)
                
                if !command.shortcutDescription.isEmpty {
                    Text(command.shortcutDescription)
                        .font(.title2)
                        .opacity(0.5)
                }
                Markdown(command.prompt)
                    .font(.title3)
                    .opacity(0.7)
                    .padding(.top, 12)
                Spacer()
            }
            .padding(24)
            .padding(.top, 4)
        }
        .onAppear {
            print("detailView onAppear")
        }
        .onDisappear {
            print("detailView onDisappear")
        }
    }
}
