//
//  MessageRowView.swift
//  XCAChatGPT
//
//  Created by Alfian Losari on 02/02/23.
//

import SwiftUI
import MarkdownUI

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
            messageRow(text: message.sendText, image: message.sendImage, bgColor: colorScheme == .light ? .white : Color(red: 52/255, green: 53/255, blue: 65/255, opacity: 0.5), isResponse: false)
            
            if let text = message.responseText {
//                Divider().padding(.horizontal)
                messageRow(text: text, image: message.responseImage, bgColor: colorScheme == .light ? .white : Color(red: 52/255, green: 53/255, blue: 65/255, opacity: 1), responseError: message.responseError, showDotLoading: message.isInteractingWithChatGPT, isResponse: true, clearContextAfterThis: message.clearContextAfterThis)
//                Divider().padding(.horizontal)
            }
            
            if message.clearContextAfterThis {
                divider
            }
        }
    }
    
    func messageRow(text: String, image: String, bgColor: Color, responseError: String? = nil, showDotLoading: Bool = false, isResponse: Bool = true, clearContextAfterThis: Bool = false) -> some View {
        #if os(watchOS)
        VStack(alignment: .leading, spacing: 8) {
            messageRowContent(text: text, image: image, responseError: responseError, showDotLoading: showDotLoading, isResponse: isResponse, clearContextAfterThis: false)
        }
        
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bgColor)
        #else
        HStack(alignment: .top, spacing: 24) {
            messageRowContent(text: text, image: image, responseError: responseError, showDotLoading: showDotLoading, isResponse: isResponse)
        }
        #if os(tvOS)
        .padding(32)
        #else
        .padding(16)
        #endif
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(bgColor)
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
        
        VStack(alignment: .leading) {
            if !text.isEmpty, let attr = try? AttributedString(markdown: text) {
//                #if os(tvOS)
//                responseTextView(text: text)
//                #else
//                Text(text)
//                    .multilineTextAlignment(.leading)
//                    #if os(iOS) || os(macOS)
//                    .textSelection(.enabled)
//                    #endif
//                #endif
                Text(attr)
//                Markdown {
//                    text
//                }
//                .markdownTheme(.gitHub)
                .textSelection(.enabled)
            }
            
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
            Text("新聊天")
                .font(.body)
                .foregroundColor(.text)
                .opacity(0.5)
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
