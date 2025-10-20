//
//  MessageRowView.swift
//  XCAChatGPT
//
//  Created by Alfian Losari on 02/02/23.
//

import SwiftUI
// Markdown rendering is disabled to improve scrolling performance

// Cross‑platform design tokens for Chat UI
enum ChatTokens {
    static let bubbleRadius: CGFloat = 10
    static let gap: CGFloat = 12
    static let rowPaddingH: CGFloat = 16
    static let rowPaddingV: CGFloat = 12
    static let iconSize: CGFloat = 24
    static let controlHeight: CGFloat = 32

    static var controlBackground: Color {
        #if canImport(AppKit)
        return Color(nsColor: .controlBackgroundColor)
        #elseif canImport(UIKit)
        return Color(uiColor: .systemGray6)
        #else
        return Color.gray.opacity(0.1)
        #endif
    }

    static var strokeColor: Color { Color.gray.opacity(0.12) }
}

struct MessageRowView: View {
    
    @Environment(\.colorScheme) private var colorScheme
    let message: MessageRow
    var tag: String = ""
    let retryCallback: (MessageRow) -> Void

    var imageSize: CGSize {
        #if os(iOS) || os(macOS)
        CGSize(width: 25, height: 25)
        #elseif os(watchOS)
        CGSize(width: 20, height: 20)
        #else
        CGSize(width: 80, height: 80)
        #endif
    }
    
    var body: some View {
        VStack(spacing: 0) {
            messageRow(text: message.sendText, image: message.sendImage, isResponse: false)
            if let text = message.responseText {
                messageRow(text: text, image: message.responseImage, responseError: message.responseError, showDotLoading: message.isInteractingWithChatGPT, isResponse: true, clearContextAfterThis: message.clearContextAfterThis)
            }
            if message.clearContextAfterThis { divider }
        }
    }
    
    func messageRow(text: String, image: String, responseError: String? = nil, showDotLoading: Bool = false, isResponse: Bool = true, clearContextAfterThis: Bool = false) -> some View {
        #if os(watchOS)
        VStack(alignment: .leading, spacing: 8) {
            messageRowContent(text: text, image: image, responseError: responseError, showDotLoading: showDotLoading, isResponse: isResponse, clearContextAfterThis: false)
        }
        
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bubbleBackground(isResponse: isResponse))
        #else
        HStack(alignment: .top, spacing: ChatTokens.gap) {
            messageRowContent(text: text, image: image, responseError: responseError, showDotLoading: showDotLoading, isResponse: isResponse)
        }
        .padding(.horizontal, ChatTokens.rowPaddingH)
        .padding(.vertical, ChatTokens.rowPaddingV)
        .frame(maxWidth: .infinity, alignment: .leading)
        #endif
    }
    
    @ViewBuilder
    func messageRowContent(text: String, image: String, responseError: String? = nil, showDotLoading: Bool = false, isResponse: Bool = true, clearContextAfterThis: Bool = false) -> some View {
        if image.hasPrefix("http"), let url = URL(string: image) {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .frame(width: imageSize.width, height: imageSize.height)
            } placeholder: {
                ProgressView()
            }

        } else {
            Image(image)
                .resizable()
                .frame(width: imageSize.width, height: imageSize.height)
        }
        
        VStack(alignment: .leading, spacing: 8) {
            // Markdown disabled for performance: render all as plain text
            Text(text)
                .font(.body)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(bubbleBackground(isResponse: isResponse))
                .clipShape(RoundedRectangle(cornerRadius: ChatTokens.bubbleRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: ChatTokens.bubbleRadius)
                        .stroke(ChatTokens.strokeColor, lineWidth: 0.8)
                )
            
            if let error = responseError {
                Text("Error: \(error)")
                    .foregroundColor(.red)
                    .multilineTextAlignment(.leading)
                
                Button("Regenerate response") {
                    retryCallback(message)
                }
                .foregroundColor(.accentColor)
                .padding(.top)
            }
            
            if showDotLoading {
                #if os(tvOS)
                ProgressView()
                    .progressViewStyle(.circular)
                    .padding()
                #else
                DotLoadingView()
                    .frame(width: 60, height: 30)
                #endif
            }

            if responseError == nil && !showDotLoading && isResponse && !text.isEmpty {
                HStack {
//                    PlainButton(icon: "doc.on.doc", label: "复制") {
                    PlainButton(icon: "doc.on.doc", label: "复制", shortcut: .init(tag.first!), modifiers: .command) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    }
//                    PlainButton(icon: "doc.on.doc", label: "复制并隐藏") {
                    PlainButton(icon: "doc.on.doc", label: "使用回答", shortcut: .init(tag.first!), modifiers: [.command, .shift]) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
//                        NSApplication.shared.windows.first?.miniaturize(nil)
                        NSApplication.shared.hide(nil)
                        paste(delay: 0.1, sentence: text)
                    }
                }
            }
            
//            if isResponse && message.clearContextAfterThis {
//                divider
//            }
        }
    }

    private func bubbleBackground(isResponse: Bool) -> Color {
        if colorScheme == .light {
            return isResponse ? Color.black.opacity(0.04) : Color.black.opacity(0.025)
        } else {
            return isResponse ? Color.white.opacity(0.06) : Color.white.opacity(0.04)
        }
    }
    
    #if os(tvOS)
    private func rowsFor(text: String) -> [String] {
        var rows = [String]()
        let maxLinesPerRow = 8
        var currentRowText = ""
        var currentLineSum = 0
        
        for char in text {
            currentRowText += String(char)
            if char == "\n" {
                currentLineSum += 1
            }

            if currentLineSum >= maxLinesPerRow {
                rows.append(currentRowText)
                currentLineSum = 0
                currentRowText = ""
            }
        }

        rows.append(currentRowText)
        return rows
    }
    
    func responseTextView(text: String) -> some View {
        ForEach(rowsFor(text: text), id: \.self) { text in
            Text(text)
                .focusable()
                .multilineTextAlignment(.leading)
        }
    }
    #endif
    
    var divider: some View {
        HStack(alignment: .center, spacing: 10) {
            Rectangle()
                .frame(height: 1)
                .foregroundColor(.divider)
            Text("new_chat")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(height: 1)
            Rectangle()
                .frame(height: 1)
                .foregroundColor(.divider)
        }
        .padding()
        .padding(.bottom, 24)
    }
}

struct MessageRowView_Previews: PreviewProvider {
    
    static let message = MessageRow(
        isInteractingWithChatGPT: true, sendImage: "profile",
        sendText: "What is SwiftUI?",
        responseImage: "openai",
        responseText: "SwiftUI is a user interface framework that allows developers to design and develop user interfaces for iOS, macOS, watchOS, and tvOS applications using Swift, a programming language developed by Apple Inc.")
    
    static let message2 = MessageRow(
        isInteractingWithChatGPT: false, sendImage: "profile",
        sendText: "What is SwiftUI?",
        responseImage: "openai",
        responseText: "",
        responseError: "ChatGPT is currently not available")
        
    static var previews: some View {
        NavigationView {
            ScrollView {
                MessageRowView(message: message, retryCallback: { messageRow in
                    
                })
                    
                MessageRowView(message: message2, retryCallback: { messageRow in
                    
                })
                  
            }
            .frame(width: 400)
            .previewLayout(.sizeThatFits)
        }
    }
}
