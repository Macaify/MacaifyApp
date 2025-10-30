//
//  GrowingTextView.swift
//  XCAChatGPTMac
//
//  Auto-growing NSTextView for macOS, sized by content with min/max caps.
//

import SwiftUI
import AppKit

struct GrowingTextView: NSViewRepresentable {
    var placeholder: String? = nil
    @Binding var text: String
    @Binding var measuredHeight: CGFloat
    var minHeight: CGFloat
    var maxHeight: CGFloat
    var font: NSFont = .preferredFont(forTextStyle: .body)
    var onEnter: (() -> Void)? = nil
    var onShiftEnter: (() -> Void)? = nil
    var onCommandEnter: (() -> Void)? = nil
    var onCommandK: (() -> Void)? = nil

    func makeNSView(context: Context) -> NSScrollView {
        let textView = CustomGrowingTextView()
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.font = font
        // Behavior
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDataDetectionEnabled = true
        // Insets for nicer caret/placeholder alignment
        textView.textContainerInset = NSSize(width: 8, height: verticalInset(for: font))
        textView.textContainer?.lineFragmentPadding = 6
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.delegate = context.coordinator
        // Wire key handlers
        textView.onEnter = onEnter
        textView.onShiftEnter = onShiftEnter
        textView.onCommandEnter = onCommandEnter
        textView.onCommandK = onCommandK
        if let placeholder {
            textView.placeholderAttributedString = NSAttributedString(
                string: placeholder,
                attributes: [
                    .font: font,
                    .foregroundColor: NSColor.tertiaryLabelColor
                ]
            )
        }

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.documentView = textView

        textView.string = text
        DispatchQueue.main.async {
            self.updateHeight(from: textView, scroll: scroll)
        }
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        // Keep key handlers in sync when SwiftUI updates the representable
        if let tv = textView as? CustomGrowingTextView {
            tv.onEnter = onEnter
            tv.onShiftEnter = onShiftEnter
            tv.onCommandEnter = onCommandEnter
            tv.onCommandK = onCommandK
        }
        if textView.string != text {
            textView.string = text
        }
        // Ensure wrapping reflects current width before measuring
        let targetWidth = nsView.contentSize.width
        if textView.frame.size.width != targetWidth {
            textView.setFrameSize(NSSize(width: targetWidth, height: textView.frame.size.height))
        }
        // Keep vertical inset consistent with control height and font
        if textView.textContainerInset.height != verticalInset(for: textView.font ?? font) {
            textView.textContainerInset = NSSize(width: textView.textContainerInset.width,
                                                height: verticalInset(for: textView.font ?? font))
        }
        updateHeight(from: textView, scroll: nsView)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: GrowingTextView
        init(_ parent: GrowingTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView,
                  let scroll = textView.enclosingScrollView else { return }
            parent.text = textView.string
            parent.updateHeight(from: textView, scroll: scroll)
        }
    }

    private func updateHeight(from textView: NSTextView, scroll: NSScrollView) {
        guard let container = textView.textContainer, let layout = textView.layoutManager else { return }
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container)
        let insets = textView.textContainerInset
        let rawHeight = ceil(used.size.height + insets.height * 2)
        let oneLine = ceil(lineHeight(for: textView.font ?? font) + insets.height * 2)
        let clamped = max(minHeight, min(maxHeight, max(oneLine, rawHeight)))
        if measuredHeight != clamped {
            // Avoid per-keystroke animations which can cause input lag
            DispatchQueue.main.async {
                self.measuredHeight = clamped
            }
        }
        scroll.hasVerticalScroller = clamped >= maxHeight - 0.5
    }

    private func lineHeight(for font: NSFont) -> CGFloat {
        // Approximate line height from font metrics
        return font.ascender - font.descender + font.leading
    }

    private func verticalInset(for font: NSFont) -> CGFloat {
        let lh = lineHeight(for: font)
        // Center one text line inside the minimum control height
        let raw = max(4, (minHeight - lh) / 2)
        // Round to keep crisp layout
        return CGFloat(floor(raw))
    }
}

// Draws placeholder text for macOS versions where NSTextView may not expose placeholder API.
private final class CustomGrowingTextView: NSTextView {
    @objc var placeholderAttributedString: NSAttributedString?
    var onEnter: (() -> Void)?
    var onShiftEnter: (() -> Void)?
    var onCommandEnter: (() -> Void)?
    var onCommandK: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let isEnter = event.keyCode == 36 // return
        let isK = event.keyCode == 40
        let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if isEnter {
            // Respect IME composition: if has marked text, never treat Enter as send
            if self.hasMarkedText() {
                super.keyDown(with: event)
                return
            }
            if mods.contains(.command) {
                onCommandEnter?()
                return
            } else if mods.contains(.shift) {
                // Insert newline and let parent optionally react
                super.keyDown(with: event)
                onShiftEnter?()
                return
            } else {
                // Plain Enter: if no explicit handler, default to insert newline
                if let onEnter {
                    onEnter()
                } else {
                    super.keyDown(with: event)
                }
                return
            }
        } else if isK && mods.contains(.command) {
            onCommandK?()
            return
        }
        super.keyDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty, let placeholderAttributedString, let container = textContainer {
            let inset = textContainerInset
            let padding = container.lineFragmentPadding
            let lh = (font?.ascender ?? 0) - (font?.descender ?? 0) + (font?.leading ?? 0)
            // Align baseline with the actual text's first line area
            let y = inset.height + max(0, (bounds.height - (lh + inset.height*2)) / 2 - 1)
            let rect = NSRect(x: inset.width + padding,
                              y: y,
                              width: bounds.width - (inset.width + padding) * 2,
                              height: lh)
            placeholderAttributedString.draw(in: rect)
        }
    }
}
