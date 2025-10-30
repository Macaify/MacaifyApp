//
//  InputEditor.swift
//  XCAChatGPTMac
//
//  Created by lixindong on 2023/4/10.
//

import SwiftUI
import AppKit

struct InputEditor: View {
    let placeholder: String
    @Binding var text: String
    let onShiftEnter: () -> Void

    var body: some View {
        CustomTextEditor(
            placeholder: placeholder,
            text: $text,
            onShiftEnter: onShiftEnter
        )
    }
}

private struct CustomTextEditor: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let onShiftEnter: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let textView = CustomTextView()
        let font = NSFont.preferredFont(forTextStyle: .body)
        textView.font = font

        textView.placeholderAttributedString = .init(
            string: placeholder,
            attributes: [
                .font: font,
                .foregroundColor: NSColor.tertiaryLabelColor,
            ]
        )

        textView.isRichText = false
        textView.autoresizingMask = [.width, .height]
        textView.translatesAutoresizingMaskIntoConstraints = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.allowsUndo = true

        textView.onShiftEnter = onShiftEnter
        textView.delegate = context.coordinator

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.documentView = textView
        scrollView.drawsBackground = false

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? CustomTextView else { return }

        textView.string = text

        guard !context.coordinator.selectedRanges.isEmpty else { return }

        textView.selectedRanges = context.coordinator.selectedRanges
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        var selectedRanges = [NSValue]()

        init(text: Binding<String>) {
            _text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }

            Task { @MainActor in
                text = textView.string
            }
            selectedRanges = textView.selectedRanges
        }
    }
}

private class CustomTextView: NSTextView {
    var onShiftEnter: (() -> Void)?
    @objc var placeholderAttributedString: NSAttributedString?

    // Respect IME composition and keep Enter as newline; do not send on Enter here.
    override func insertNewline(_ sender: Any?) {
        super.insertNewline(sender)
    }
}
