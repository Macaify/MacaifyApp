import SwiftUI

#if os(macOS)
import AppKit

struct HoverPopover<Content: View>: NSViewRepresentable {
    @Binding var isPresented: Bool
    var preferredEdge: NSRectEdge = NSRectEdge.maxX
    @ViewBuilder var content: () -> Content

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }

    func updateNSView(_ nsView: NSView, context: Context) {
        if isPresented {
            if context.coordinator.popover == nil || context.coordinator.popover?.isShown == false {
                let pop = NSPopover()
                pop.behavior = .semitransient
                // Disable animations to improve perceived performance while hovering
                pop.animates = false
                let host = NSHostingController(rootView: content())
                pop.contentViewController = host
                host.view.layoutSubtreeIfNeeded()
                pop.contentSize = host.view.fittingSize
                pop.show(relativeTo: nsView.bounds, of: nsView, preferredEdge: preferredEdge)
                context.coordinator.popover = pop
            } else {
                if let pop = context.coordinator.popover,
                   let host = pop.contentViewController as? NSHostingController<AnyView> {
                    host.rootView = AnyView(content())
                    host.view.layoutSubtreeIfNeeded()
                    pop.contentSize = host.view.fittingSize
                } else if let pop = context.coordinator.popover {
                    // Replace controller if type mismatched
                    let host = NSHostingController(rootView: content())
                    pop.contentViewController = host
                    host.view.layoutSubtreeIfNeeded()
                    pop.contentSize = host.view.fittingSize
                }
            }
        } else {
            context.coordinator.popover?.close()
            context.coordinator.popover = nil
        }
    }

    final class Coordinator {
        var popover: NSPopover?
        deinit { popover?.close() }
    }
}

#else
// Non-macOS stub
struct HoverPopover<Content: View>: View {
    @Binding var isPresented: Bool
    var preferredEdge: Int = 0
    @ViewBuilder var content: () -> Content
    var body: some View { EmptyView() }
}
#endif
