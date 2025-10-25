import SwiftUI

// Direction is top-level to avoid tying it to the generic Content type
public enum AnchoredPopoverDirection { case above, below, leading, trailing }

#if os(macOS)
import AppKit

/// A lightweight, reusable popover-like presenter for macOS that does not use NSPopover or SwiftUI's .popover.
/// - Presents SwiftUI content inside an `NSPanel` anchored to any SwiftUI view.
/// - Supports preferred display direction (above/below/leading/trailing) with screen-edge adaptation.
/// - Dismisses on ESC and outside-click (configurable), and on parent window deactivation.
/// - Size is driven by the SwiftUI content's layout (use .frame modifiers as usual).
///
/// Usage:
///
/// ```swift
/// struct Example: View {
///   @State private var isOpen = false
///   var body: some View {
///     Button("Show") { isOpen.toggle() }
///       .background(
///         AnchoredPopover(isPresented: $isOpen, preferredDirection: .below) {
///           VStack(alignment: .leading, spacing: 8) {
///             Text("Hello, Popover!").font(.headline)
///             Button("Close") { isOpen = false }
///           }
///           .padding(12)
///           .frame(width: 260) // control size as usual
///           .background(.regularMaterial)
///           .clipShape(RoundedRectangle(cornerRadius: 12))
///         }
///       )
///   }
/// }
/// ```
public struct AnchoredPopover<Content: View>: NSViewRepresentable {
    // Retain nested name for ergonomics
    public typealias Direction = AnchoredPopoverDirection

    @Binding var isPresented: Bool
    var preferredDirection: AnchoredPopoverDirection
    var edgeInset: CGFloat
    var dismissOnOutsideClick: Bool
    var dismissOnESC: Bool
    var cornerRadius: CGFloat
    var level: NSWindow.Level
    var canBecomeKey: Bool
    var onDismiss: (() -> Void)?
    @ViewBuilder var content: () -> Content

    public init(
        isPresented: Binding<Bool>,
        preferredDirection: AnchoredPopoverDirection = .below,
        edgeInset: CGFloat = 8,
        dismissOnOutsideClick: Bool = true,
        dismissOnESC: Bool = true,
        cornerRadius: CGFloat = 12,
        level: NSWindow.Level = .popUpMenu,
        canBecomeKey: Bool = true,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        _isPresented = isPresented
        self.preferredDirection = preferredDirection
        self.edgeInset = edgeInset
        self.dismissOnOutsideClick = dismissOnOutsideClick
        self.dismissOnESC = dismissOnESC
        self.cornerRadius = cornerRadius
        self.level = level
        self.canBecomeKey = canBecomeKey
        self.onDismiss = onDismiss
        self.content = content
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(
            isPresented: $isPresented,
            preferredDirection: preferredDirection,
            edgeInset: edgeInset,
            dismissOnOutsideClick: dismissOnOutsideClick,
            dismissOnESC: dismissOnESC,
            cornerRadius: cornerRadius,
            level: level,
            canBecomeKey: canBecomeKey,
            onDismiss: onDismiss,
            content: { AnyView(content()) }
        )
    }

    public func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { context.coordinator.anchorView = view }
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.anchorView = nsView
        context.coordinator.preferredDirection = preferredDirection
        context.coordinator.edgeInset = edgeInset
        context.coordinator.cornerRadius = cornerRadius
        context.coordinator.level = level
        context.coordinator.canBecomeKey = canBecomeKey
        context.coordinator.dismissOnOutsideClick = dismissOnOutsideClick
        context.coordinator.dismissOnESC = dismissOnESC
        context.coordinator.onDismiss = onDismiss
        context.coordinator.content = {
            // 包装内容，添加 ESC 处理
            let wrapped = AnyView(
                self.content()
                    .background(
                        self.dismissOnESC ?
                            AnyView(ESCHandlerView(onESC: { context.coordinator.dismiss() })) :
                            AnyView(EmptyView())
                    )
            )
            return wrapped
        }

        if isPresented {
            context.coordinator.presentIfNeeded()
            context.coordinator.updateContentAndReposition()
        } else {
            context.coordinator.close()
        }
    }

    public final class Coordinator: NSObject, NSWindowDelegate {
        // Inputs
        var isPresented: Binding<Bool>
        var preferredDirection: AnchoredPopoverDirection
        var edgeInset: CGFloat
        var dismissOnOutsideClick: Bool
        var dismissOnESC: Bool
        var cornerRadius: CGFloat
        var level: NSWindow.Level
        var canBecomeKey: Bool
        var onDismiss: (() -> Void)?
        var content: () -> AnyView

        // Runtime
        weak var anchorView: NSView?
        private var panel: AnchoredPopoverPanel?
        private var host: NSHostingController<AnyView>?
        private var localMouseMonitor: Any?
        private var globalMouseMonitor: Any?

        init(
            isPresented: Binding<Bool>,
            preferredDirection: AnchoredPopoverDirection,
            edgeInset: CGFloat,
            dismissOnOutsideClick: Bool,
            dismissOnESC: Bool,
            cornerRadius: CGFloat,
            level: NSWindow.Level,
            canBecomeKey: Bool,
            onDismiss: (() -> Void)?,
            content: @escaping () -> AnyView
        ) {
            self.isPresented = isPresented
            self.preferredDirection = preferredDirection
            self.edgeInset = edgeInset
            self.dismissOnOutsideClick = dismissOnOutsideClick
            self.dismissOnESC = dismissOnESC
            self.cornerRadius = cornerRadius
            self.level = level
            self.canBecomeKey = canBecomeKey
            self.onDismiss = onDismiss
            self.content = content
        }

        deinit { removeMonitors() }

        func presentIfNeeded() {
            guard panel?.isVisible != true else { return }
            ensurePanel()
            guard let anchor = anchorView, let anchorWindow = anchor.window, let panel else { return }
            anchorWindow.addChildWindow(panel, ordered: .above)
            panel.makeKeyAndOrderFront(nil)
            panel.orderFrontRegardless()
            installMonitorsIfNeeded()
        }

        func updateContentAndReposition() {
            ensurePanel()
            guard let panel, let host else { return }
            host.rootView = content()
            host.view.wantsLayer = true
            host.view.layer?.cornerRadius = cornerRadius
            host.view.layoutSubtreeIfNeeded()
            var size = host.view.fittingSize
            size.width = max(1, size.width)
            size.height = max(1, size.height)
            if panel.contentView?.frame.size != size { panel.setContentSize(size) }

            if let frame = computeTargetFrame(for: size) {
                if panel.frame != frame { panel.setFrame(frame, display: false) }
            }
        }

        func close() {
            removeMonitors()
            guard let p = panel else { return }
            if let parent = p.parent { parent.removeChildWindow(p) }
            p.orderOut(nil)
        }

        private func ensurePanel() {
            guard panel == nil else { return }
            let p = AnchoredPopoverPanel(
                contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                styleMask: [.nonactivatingPanel, .hudWindow, .fullSizeContentView],
                backing: .buffered,
                defer: true
            )
            p.level = level
            p.hasShadow = true
            p.isOpaque = false
            p.backgroundColor = .clear
            p.isMovable = false
            p.isMovableByWindowBackground = false
            p.titleVisibility = .hidden
            p.titlebarAppearsTransparent = true
            p.animationBehavior = .none
            p.delegate = self
            p.allowsKeyFocus = canBecomeKey  // 控制是否能成为 key window

            let host = NSHostingController(rootView: AnyView(EmptyView()))
            host.view.wantsLayer = true
            host.view.layer?.cornerRadius = cornerRadius
            p.contentView = host.view
            self.host = host
            self.panel = p
        }

        // MARK: Positioning
        private func computeTargetFrame(for size: NSSize) -> NSRect? {
            guard let anchor = anchorView, let window = anchor.window else { return nil }
            let rectInWindow = anchor.convert(anchor.bounds, to: nil)
            let anchorScreenRect = window.convertToScreen(rectInWindow)
            let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

            let candidates = candidateOrder(startingWith: preferredDirection)
            for dir in candidates {
                let f = frame(for: dir, anchor: anchorScreenRect, size: size, visible: visible)
                if visible.contains(f) { return f }
            }
            // Fallback: clamp the preferred direction within visible bounds
            var fallback = frame(for: preferredDirection, anchor: anchorScreenRect, size: size, visible: visible)
            if fallback.minX < visible.minX + edgeInset { fallback.origin.x = visible.minX + edgeInset }
            if fallback.maxX > visible.maxX - edgeInset { fallback.origin.x = visible.maxX - size.width - edgeInset }
            if fallback.minY < visible.minY + edgeInset { fallback.origin.y = visible.minY + edgeInset }
            if fallback.maxY > visible.maxY - edgeInset { fallback.origin.y = visible.maxY - size.height - edgeInset }
            return fallback
        }

        private func candidateOrder(startingWith dir: AnchoredPopoverDirection) -> [AnchoredPopoverDirection] {
            switch dir {
            case .below: return [.below, .above, .trailing, .leading]
            case .above: return [.above, .below, .trailing, .leading]
            case .trailing: return [.trailing, .leading, .below, .above]
            case .leading: return [.leading, .trailing, .below, .above]
            }
        }

        private func frame(for dir: AnchoredPopoverDirection, anchor: NSRect, size: NSSize, visible: NSRect) -> NSRect {
            let inset = edgeInset
            var x = anchor.minX
            var y = anchor.minY
            switch dir {
            case .above:
                y = anchor.maxY + inset
                // left align; clamp horizontally
                x = min(max(visible.minX + inset, anchor.minX), visible.maxX - size.width - inset)
            case .below:
                y = anchor.minY - size.height - inset
                x = min(max(visible.minX + inset, anchor.minX), visible.maxX - size.width - inset)
            case .trailing:
                x = anchor.maxX + inset
                // top align with anchor's top; clamp vertically
                y = min(max(visible.minY + inset, anchor.maxY - size.height), visible.maxY - size.height - inset)
            case .leading:
                x = anchor.minX - size.width - inset
                y = min(max(visible.minY + inset, anchor.maxY - size.height), visible.maxY - size.height - inset)
            }
            return NSRect(origin: NSPoint(x: x, y: y), size: size)
        }

        // MARK: Dismissal & monitors
        private func installMonitorsIfNeeded() {
            guard localMouseMonitor == nil && globalMouseMonitor == nil else { return }
            
            if dismissOnOutsideClick {
                localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] e in
                    guard let self, let panel = self.panel else { return e }
                    let pt = NSEvent.mouseLocation
                    if !panel.frame.contains(pt) { self.dismiss() }
                    return e
                }
                globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
                    guard let self, let panel = self.panel else { return }
                    let pt = NSEvent.mouseLocation
                    if !panel.frame.contains(pt) { self.dismiss() }
                }
            }
        }

        private func removeMonitors() {
            if let m = localMouseMonitor { NSEvent.removeMonitor(m); localMouseMonitor = nil }
            if let m = globalMouseMonitor { NSEvent.removeMonitor(m); globalMouseMonitor = nil }
        }

        func dismiss() {
            isPresented.wrappedValue = false
            close()
            onDismiss?()
        }

        // MARK: NSWindowDelegate
        public func windowDidResignKey(_ notification: Notification) {
            // Auto-close when focus is lost
            dismiss()
        }

        public func windowDidMove(_ notification: Notification) {
            updateContentAndReposition()
        }

        public func windowDidChangeScreen(_ notification: Notification) {
            updateContentAndReposition()
        }

        public func windowDidResize(_ notification: Notification) {
            updateContentAndReposition()
        }
    }
}

final class AnchoredPopoverPanel: NSPanel {
    var allowsKeyFocus: Bool = true
    override var canBecomeKey: Bool { allowsKeyFocus }
}

// ESC 处理 View - 不使用 event monitor，直接响应键盘事件
private struct ESCHandlerView: NSViewRepresentable {
    let onESC: () -> Void
    
    func makeNSView(context: Context) -> ESCResponderView {
        let view = ESCResponderView()
        view.onESC = onESC
        return view
    }
    
    func updateNSView(_ nsView: ESCResponderView, context: Context) {
        nsView.onESC = onESC
    }
}

private class ESCResponderView: NSView {
    var onESC: (() -> Void)?
    
    override var acceptsFirstResponder: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            onESC?()
        } else {
            super.keyDown(with: event)
        }
    }
    
    // 确保视图能接收键盘事件
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }
}

#else

// Non-macOS stub for API compatibility
public struct AnchoredPopover<Content: View>: View {
    @Binding var isPresented: Bool
    var preferredDirection: AnchoredPopoverDirection = .below
    var edgeInset: CGFloat = 8
    var dismissOnOutsideClick: Bool = true
    var cornerRadius: CGFloat = 12
    var level: Int = 0
    @ViewBuilder var content: () -> Content
    public init(
        isPresented: Binding<Bool>,
        preferredDirection: AnchoredPopoverDirection = .below,
        edgeInset: CGFloat = 8,
        dismissOnOutsideClick: Bool = true,
        cornerRadius: CGFloat = 12,
        level: Int = 0,
        @ViewBuilder content: @escaping () -> Content
    ) {
        _isPresented = isPresented
        self.preferredDirection = preferredDirection
        self.edgeInset = edgeInset
        self.dismissOnOutsideClick = dismissOnOutsideClick
        self.cornerRadius = cornerRadius
        self.level = level
        self.content = content
    }
    public var body: some View { EmptyView() }
}

#endif
