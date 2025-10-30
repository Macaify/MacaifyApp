//
//  UnboundComposer.swift
//  XCAChatGPTMac
//
//  Auto-growing NSTextView without binding its text into SwiftUI state.
//  - Avoids per-keystroke SwiftUI updates
//  - IME-safe key handling
//  - Height updates are coalesced to reduce layout churn
//

import SwiftUI
import AppKit

final class UnboundComposerController: ObservableObject {
    fileprivate weak var textView: NSTextView?
    func getText() -> String { textView?.string ?? "" }
    func setText(_ text: String) { textView?.string = text }
    func clear() { textView?.string = "" }
    func focus() { textView?.window?.makeFirstResponder(textView) }
}

struct UnboundComposer: NSViewRepresentable {
    var placeholder: String
    @Binding var measuredHeight: CGFloat
    var minHeight: CGFloat
    var maxHeight: CGFloat
    var onCommandEnter: (() -> Void)? = nil
    var onCommandK: (() -> Void)? = nil
    @ObservedObject var controller: UnboundComposerController

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let tv = ComposerTextView()
        tv.isRichText = false
        tv.drawsBackground = false
        tv.font = .preferredFont(forTextStyle: .body)
        tv.textContainerInset = NSSize(width: 8, height: 6)
        tv.textContainer?.lineFragmentPadding = 6
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.heightTracksTextView = false
        tv.delegate = context.coordinator
        tv.onCommandEnter = onCommandEnter
        tv.onCommandK = onCommandK
        tv.placeholder = placeholder

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.documentView = tv

        controller.textView = tv
        // Initial height
        DispatchQueue.main.async { context.coordinator.updateHeight(from: tv, scroll: scroll) }
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = nsView.documentView as? ComposerTextView else { return }
        controller.textView = tv
        tv.onCommandEnter = onCommandEnter
        tv.onCommandK = onCommandK
        // Ensure wrapping width is current
        let targetWidth = nsView.contentSize.width
        if tv.frame.size.width != targetWidth {
            tv.setFrameSize(.init(width: targetWidth, height: tv.frame.size.height))
        }
        // Coalesced height update
        context.coordinator.scheduleHeightUpdate(for: tv, in: nsView)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: UnboundComposer
        private var pending: DispatchWorkItem?
        init(_ parent: UnboundComposer) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView, let scroll = tv.enclosingScrollView else { return }
            scheduleHeightUpdate(for: tv, in: scroll)
        }

        func scheduleHeightUpdate(for tv: NSTextView, in scroll: NSScrollView) {
            pending?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.updateHeight(from: tv, scroll: scroll) }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
        }

        func updateHeight(from tv: NSTextView, scroll: NSScrollView) {
            guard let container = tv.textContainer, let layout = tv.layoutManager else { return }
            layout.ensureLayout(for: container)
            let used = layout.usedRect(for: container)
            let insets = tv.textContainerInset
            let lineH = (tv.font?.ascender ?? 0) - (tv.font?.descender ?? 0) + (tv.font?.leading ?? 0)
            let raw = ceil(used.height + insets.height * 2)
            // Snap to full-line boundaries to reduce micro-changes
            let snapped = ceil(raw / max(lineH, 1)) * max(lineH, 1) + max(0, insets.height * 0)
            let oneLine = ceil(lineH + insets.height * 2)
            let clamped = max(parent.minHeight, min(parent.maxHeight, max(oneLine, snapped)))
            if parent.measuredHeight != clamped {
                DispatchQueue.main.async { self.parent.measuredHeight = clamped }
            }
            scroll.hasVerticalScroller = clamped >= parent.maxHeight - 0.5
        }
    }
}

private final class ComposerTextView: NSTextView {
    var onCommandEnter: (() -> Void)?
    var onCommandK: (() -> Void)?
    var placeholder: String = ""
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font ?? .preferredFont(forTextStyle: .body),
                .foregroundColor: NSColor.tertiaryLabelColor
            ]
            let lh = (font?.ascender ?? 0) - (font?.descender ?? 0) + (font?.leading ?? 0)
            let inset = textContainerInset
            let pad = textContainer?.lineFragmentPadding ?? 6
            let y = inset.height + max(0, (bounds.height - (lh + inset.height * 2)) / 2 - 1)
            let rect = NSRect(x: inset.width + pad, y: y, width: bounds.width - (inset.width + pad) * 2, height: lh)
            (placeholder as NSString).draw(in: rect, withAttributes: attrs)
        }
    }

    override func keyDown(with event: NSEvent) {
        let isEnter = event.keyCode == 36 || event.keyCode == 76 // return or keypad enter
        let isK = event.keyCode == 40
        let mods = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if isEnter {
            if self.hasMarkedText() {
                super.keyDown(with: event); return
            }
            if mods.contains(.command) {
                onCommandEnter?(); return
            }
            // Default: newline
            super.keyDown(with: event); return
        }
        if isK && mods.contains(.command) { onCommandK?(); return }
        super.keyDown(with: event)
    }
}
