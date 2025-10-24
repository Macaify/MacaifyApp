import SwiftUI

#if os(macOS)
import AppKit
import BetterAuth

// 统一的模型选择面板 Presenter，供任意位置复用
enum ModelPicker {
    static func present(relativeTo view: NSView, authClient: BetterAuthClient?) {
        ModelPickerPanelBridge.shared.show(relativeTo: view, authClient: authClient)
    }
    static func toggle(relativeTo view: NSView, authClient: BetterAuthClient?) {
        ModelPickerPanelBridge.shared.toggle(relativeTo: view, authClient: authClient)
    }
    static func dismiss() { ModelPickerPanelBridge.shared.close() }
    static var window: NSWindow? { ModelPickerPanelBridge.shared.panelWindow() }
}

// SwiftUI 触发器：包一层锚点解析 + 点击展示
struct ModelPickerTrigger<Label: View>: View {
    @EnvironmentObject private var authClient: BetterAuthClient
    @State private var anchor: NSView? = nil
    let label: () -> Label
    var body: some View {
        Button(action: { if let v = anchor { ModelPicker.toggle(relativeTo: v, authClient: authClient) } }) {
            label()
        }
        .background(ModelPickerAnchorResolver(onResolve: { self.anchor = $0 }))
        .buttonStyle(.bordered)
    }
}

// 本文件内自带的锚点解析器（避免与 Popover 文件里的 PanelAnchorResolver 同名冲突）
struct ModelPickerAnchorResolver: NSViewRepresentable {
    var onResolve: (NSView) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: .zero)
        DispatchQueue.main.async { onResolve(v) }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) { }
}
#endif
