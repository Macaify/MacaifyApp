//
//  MacContentView.swift
//  XCAChatGPTMac
//
//  Created by lixindong on 2023/4/8.
//

import SwiftUI
import AppKit
import Defaults
import Combine

struct MacContentView: View {
    @EnvironmentObject var convVM: ConversationViewModel
    @StateObject var pathManager = PathManager.shared
    @State private var activeSheet: ActiveSheet?
    @State private var selection: UUID? = nil
    @AppStorage("selectedLanguage") var userDefaultsSelectedLanguage: String?

    var body: some View {
        Group {
            if #available(macOS 13.0, *) {
                NavigationSplitView(sidebar: { sidebar }, detail: { detail })
            } else {
                HStack(spacing: 0) { sidebar.frame(width: 240); Divider(); detail }
            }
        }
        .background(.background)
        .onAppear { syncSelection(); syncSheetState() }
        .onChange(of: convVM.currentChat) { _ in syncSelection() }
        .onChange(of: selection) { id in
            guard let id, let conv = convVM.conversations.first(where: { $0.id == id }) else { return }
            // 预热历史，减少切换卡顿
            let vm = convVM.commandViewModel(conv)
            Task { await vm.loadInitialMessagesAsync() }
            convVM.currentChat = conv
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .add:
                ConversationPreferenceView(conversation: GPTConversation(""), mode: .add)
                    .frame(minWidth: 640, minHeight: 520)
            case .edit(let conv):
                ConversationPreferenceView(conversation: conv, mode: .edit)
                    .frame(minWidth: 640, minHeight: 520)
            case .playground:
                PromptPlayground()
                    .frame(minWidth: 720, minHeight: 520)
            case .settingsBridge:
                SettingsBridgeView()
            }
        }
        .toolbar { toolbar }
        .environmentObject(pathManager)
    }

    // MARK: - Sidebar
    @ViewBuilder
    private var sidebar: some View {
        List(selection: Binding(get: { selection }, set: { selection = $0 })) {
            Section(String(localized: "bots")) {
                ForEach(convVM.conversations) { conv in
                    HStack(spacing: 8) {
                        ConversationIconView(conversation: conv, size: 16)
                        Text(conv.name).lineLimit(1)
                        if conv.typingInPlace {
                            Text("tip").font(.caption2).padding(2)
                                .background(Color.purple.opacity(0.9).cornerRadius(4))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(height: 28)
                    .tag(conv.id as UUID?)
                    .contextMenu {
                        Button(String(localized: "编辑")) { pathManager.to(target: .editCommand(command: conv)) }
                        Button(String(localized: "删除"), role: .destructive) { convVM.removeCommand(conv) }
                    }
                }
                .onDelete(perform: convVM.removeCommand)
                .onMove(perform: convVM.moveCommands)
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 220)
    }

    // MARK: - Detail
    @ViewBuilder
    private var detail: some View {
        if let conv = convVM.currentChat {
            SwiftUIChatDetail(conversation: conv)
                .id(conv.id)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background)
        } else {
            VStack(spacing: 12) {
                Text(String(localized: "welcome_to_macaify")).font(.title3)
                Text(String(localized: "hold_cmd_for_shortcuts")).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button(String(localized: "create_bot")) { pathManager.to(target: .addCommand) }
                    Button(String(localized: "bots_plaza")) { pathManager.to(target: .playground) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Toolbar
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Button { pathManager.to(target: .addCommand) } label: {
                Label(String(localized: "Create a Bot"), systemImage: "square.stack.3d.up.badge.a")
            }
        }
        ToolbarItem(placement: .automatic) {
            Button { pathManager.to(target: .playground) } label: {
                Label(String(localized: "Bots Plaza"), systemImage: "sparkles.rectangle.stack")
            }
        }
        ToolbarItem(placement: .automatic) {
            Button {
                if let c = convVM.currentChat { pathManager.to(target: .editCommand(command: c)) }
            } label: { Image(systemName: "gearshape") }
            .help(String(localized: "会话设置"))
            .disabled(convVM.currentChat == nil)
        }
        ToolbarItem(placement: .automatic) {
            Button {
                if #available(macOS 13.0, *) { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) }
                else { pathManager.to(target: .setting) }
            } label: {
                Label(String(localized: "Global Settings"), systemImage: "gear")
            }
        }
    }

    private func syncSelection() { selection = convVM.currentChat?.id }

}

enum Target: Hashable {
    case main(command: GPTConversation? = nil)
    case setting
    case addCommand
    case playground
    case editCommand(command: GPTConversation)
    case chat(command: GPTConversation, msg: String? = nil, mode: ChatMode = .normal)
}

//struct MacContentView_Previews: PreviewProvider {
//    static var previews: some View {
//        MacContentView()
//    }
//}

struct TView: View {
    
    init() {
        print("TView test")
    }
    var body: some View {
        Text("test 0")
    }
}

struct SettingsBridgeView: View {
    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .onAppear {
                if #available(macOS 13.0, *) {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    PathManager.shared.back()
                }
            }
    }
}

// MARK: - ActiveSheet: 路由到统一 Sheet
extension MacContentView {
    enum ActiveSheet: Identifiable, Equatable {
        case add
        case edit(GPTConversation)
        case playground
        case settingsBridge

        var id: String {
            switch self {
            case .add: return "add"
            case .edit(let conv): return "edit_\(conv.id.uuidString)"
            case .playground: return "playground"
            case .settingsBridge: return "settings"
            }
        }
    }

    private func syncSheetState() {
        switch pathManager.top {
        case .addCommand:
            activeSheet = .add
        case .editCommand(let conv):
            activeSheet = .edit(conv)
        case .playground:
            activeSheet = .playground
        case .setting:
            activeSheet = .settingsBridge
        default:
            activeSheet = nil
        }
    }
}
