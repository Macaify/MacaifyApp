//
//  CmdKWindowController.swift
//  XCAChatGPT
//
//  Created by lixindong on 2024/8/11.
//

import Foundation
import AppKit
import SwiftUI

class CMDKWindowController: NSWindowController, NSWindowDelegate {
    static let shared = CMDKWindowController()
    
    var contentView: CMDKView!
    var isVisible: Bool {
        window?.isVisible ?? false
    }
    let viewModel = CMDKViewModel()
    
    convenience init() {
        self.init(windowNibName: "CMDKWindow")
        contentView = CMDKView()
    }
    
    override func loadWindow() {
        window = CMDKWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 300), styleMask: [.hudWindow, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: true)
        window?.level = .mainMenu
        window?.center()
        window?.contentView = NSHostingView(rootView: contentView.environmentObject(viewModel))
        window?.delegate = self
        window?.backgroundColor = .clear
        window?.titlebarAppearsTransparent = true
        window?.isMovableByWindowBackground = true
    }
    
    func showWindow() {
        guard let window = window else { return }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        showWindow(nil)
    }
    
    func closeWindow() {
        viewModel.clear()
        close()
        window?.close()
    }
    
    func windowDidResignKey(_ notification: Notification) {
        closeWindow()
    }
}


class CMDKWindow: NSPanel {
    override var canBecomeKey: Bool { true }
}

class CMDKViewModel: ObservableObject {
    @Published var command: String = ""
    @Published var nextCommand: String = ""
    @Published var context: String = "" {
        didSet {
            updateDiff()
        }
    }
    @Published var result: String = "" {
        didSet {
            updateDiff()
        }
    }
    
    @Published var diffLines: [DiffString] = []
    @Published var generating = false
    
    private var task: Task<Void, Error>?
    
    func clear() {
        command = ""
        nextCommand = ""
        context = ""
        result = ""
        diffLines.removeAll()
        generating = false
        task?.cancel()
        task = nil
    }
    
    func updateDiff() {
        let contextLines = context.components(separatedBy: .newlines)

        guard let startIndex = result.range(of: "// Start of Selection")?.upperBound else {
            // Handle out of bounds error
            return
        }
        let endIndex = result.range(of: "// End of Selection")?.lowerBound ?? result.endIndex
        print("startIndex: \(startIndex), endIndex: \(endIndex)")
        let extractedContent = extractSelection()
        
        let resultLines = extractedContent.components(separatedBy: .newlines)
        
        let diffs = contextLines.diff(resultLines)
//        self.diffs = diff(text1: context, text2: result)
        print(diffs)
        
        // diffs 转化为用于渲染的富文本模式
        var displayLines: [String] = []
        displayLines.append(contentsOf: contextLines)

        diffLines = mergeDiffs(contextLines: contextLines, resultLines: resultLines, diffs: diffs.elements)
    }
    
    func extractSelection() -> String {
        guard let startIndex = result.range(of: "// Start of Selection")?.upperBound else {
            // Handle out of bounds error
            return ""
        }
        let endIndex = result.range(of: "// End of Selection")?.lowerBound ?? result.endIndex
        print("startIndex: \(startIndex), endIndex: \(endIndex)")
        return String(result[startIndex..<endIndex]).trimmingCharacters(in: .newlines)
    }
    
    func testMergeDiffs() {
        let contextLines = ["111", "222", "333", "444", "555", "666"]
        let resultLines = ["111", "555", "222", "444", "333"]
        let diffs = contextLines.diff(resultLines)
        // 我希望能转成下图表示：
        /// 111
        ///+ 555
        /// 222
        ///- 333
        /// 444
        /// - 555
        /// - 666
        ///+ 333
        
        let mergedResult = mergeDiffs(contextLines: contextLines, resultLines: resultLines, diffs: diffs.elements)

        // 打印结果
        print(diffs)

        for line in mergedResult {
            print(line)
        }
    }
    func mergeDiffs(contextLines: [String], resultLines: [String], diffs: [Diff.Element]) -> [DiffString] {
        var mergedLines: [DiffString] = []
        var contextIndex = 0
        var mergedIndex = 0
        var diffIndex = 0

        while contextIndex < contextLines.count && diffIndex < diffs.count {
            let diff = diffs[diffIndex]
            // 如果 diff 是 delete
            //  看看 context 到没到下一个 at
            //      如果没到，添加 context 到 merged，merged+1, context+1
            //      如果到了，添加 context 到 merged，diff+1, context+1
            //  否则（insert），看看 result 有没有到下一个 at
            //      如果没到，添加 context 到 merged，merged+1, context+1
            //      如果到了，添加 context 到 merged，merged+1，diff+1
            switch diff {
            case .delete(let at):
                if contextIndex < at {
                    mergedLines.append(DiffString(string: contextLines[contextIndex], type: .equal))
                    contextIndex += 1
                    mergedIndex += 1
                } else {
                    mergedLines.append(DiffString(string: contextLines[at], type: .delete))
                    contextIndex += 1
                    diffIndex += 1
                }
                break
            case .insert(at: let at):
                if mergedIndex < at {
                    mergedLines.append(DiffString(string: contextLines[contextIndex], type: .equal))
                    contextIndex += 1
                    mergedIndex += 1
                } else {
                    mergedLines.append(DiffString(string: resultLines[at], type: .insert))
                    mergedIndex += 1
                    diffIndex += 1
                }
                break
            }
        }
        // 看看 context 到最后没，如果没到，全部直接加到最后面
        if contextIndex < contextLines.count {
            mergedLines.append(contentsOf: contextLines[contextIndex...].map { DiffString(string: $0, type: .equal) })
        }
        // 看看 diff 到最后没，如果没到，肯定全是加，resultLines 剩下的也全加到最后面
        if mergedIndex < resultLines.count {
            mergedLines.append(contentsOf: resultLines[mergedIndex...].map { DiffString(string: $0, type: .insert) })
        }

        return mergedLines
    }
    
    struct DiffString {
        let string: String
        var type: DiffType = .equal
    }
    
    enum DiffType {
        case insert
        case delete
        case equal
    }
    
    func handleCommand() {
//        CMDKWindowController.shared.closeWindow()

        print("handleCommand")
        command = command + " " + nextCommand
        nextCommand = ""
        let (systemPrompt, userPrompt) = getPrompt(text: context, cmd: command)
        let conv = GPTConversation.empty
//        let systemPrompt = "这是用户需要修改的内容<content>, 它会给出指令<cmd>让你帮忙修改。注意，不要说多余的话，直接给出修改后的结果。\n<content>: \(context)\n\n<cmd>:"
//        TypingInPlace.shared.typeInPlace(conv: conv, context: systemPrompt, command: command)
        
        task = Task { @MainActor in
            let api = conv.API
            api.systemPrompt = systemPrompt
            let stream = try await api.sendMessageStream(text: userPrompt)
            
            generating = true
            result.removeAll()
            for try await answer in stream {
                guard !Task.isCancelled else {
                    return
                }
                result += answer
            }
            generating = false
        }
    }
    
    struct Context {
        let selectedText: String
        let autoAddSelectedText: Bool
    }
}

struct CMDKView: View {
    @EnvironmentObject var viewModel: CMDKViewModel
    @FocusState var focus: FocusField?
    
    @State var scrollViewHeight: CGFloat = 0

    var body: some View {
        VStack {
            TextField("enter_generate_command", text: $viewModel.command)
                .textFieldStyle(.plain)
                .onSubmit {
                    print("Submit: \(viewModel.command)")
                    viewModel.handleCommand()
                }
                .focused($focus, equals: .command)
                .onAppear(perform: {
                    focus = .command
                })
                .disabled(!viewModel.result.isEmpty)
            if !viewModel.result.isEmpty {
                ScrollView {
                    VStack {
                        ForEach(viewModel.diffLines.indices, id: \.self) { index in
                            if index < viewModel.diffLines.count {
                                let diff = viewModel.diffLines[index]
                                let type = diff.type
                                switch type {
                                case .insert:
                                    Text(diff.string)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .lineLimit(nil)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .background(.green.opacity(0.5))
                                case .delete:
                                    Text(diff.string)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .lineLimit(nil)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .background(.red.opacity(0.5))
                                case .equal:
                                    Text(diff.string)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .lineLimit(nil)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        GeometryReader {
                            let size = $0.size
                            Color.clear
                                .onChange(of: size) { newValue in
                                    scrollViewHeight = min(size.height, 400)
                                }
                        }
                    }
//                    
//                    Text(viewModel.diffsRichText)
//                        .frame(maxWidth: .infinity, alignment: .leading)
//                        .lineLimit(nil)
//                        .fixedSize(horizontal: false, vertical: true)
//                        .background {
//                            GeometryReader {
//                                let size = $0.size
//                                Color.clear
//                                    .onChange(of: size) { newValue in
//                                        scrollViewHeight = min(size.height, 400)
//                                    }
//                            }
//                        }
                }
                .frame(height: scrollViewHeight)
            }
            if !viewModel.result.isEmpty, !viewModel.generating {
                HStack {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(viewModel.extractSelection(), forType: .string)
                        print("copy to clipboard: \(viewModel.result)")
                        
                        CMDKWindowController.shared.closeWindow()

                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            print("perform global paste shortcut")
                            performGlobalPasteShortcut()
                        }
                    } label: {
                        Text("apply")
                    }.keyboardShortcut(.return, modifiers: .command)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(viewModel.extractSelection(), forType: .string)
                        print("copy to clipboard: \(viewModel.result)")
                    } label: {
                        Text("copy")
                    }.keyboardShortcut("c", modifiers: .command)
                    TextField("continue_editing", text: $viewModel.nextCommand)
                        .textFieldStyle(.plain)
                        .onSubmit {
                            print("Submit: \(viewModel.nextCommand)")
                            viewModel.handleCommand()
                        }
                        .focused($focus, equals: .nextCommand)
                        .onAppear(perform: {
                            focus = .nextCommand
                        })
                }
            }
        }
        .frame(width: 300)
        .padding()
        .background(.white.opacity(0.5))
        .background(.regularMaterial)
        .cornerRadius(16)
    }
}

enum FocusField: Hashable {
    case command
    case nextCommand
}
