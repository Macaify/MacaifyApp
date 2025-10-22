//
//  KeyEvents.swift
//  XCAChatGPTMac
//
//  Created by lixindong on 2023/4/15.
//

import Foundation
import AppKit
import SwiftUI

struct OnKeyPressed: ViewModifier {
    var keyAction: KeyAction?
    var callback: (NSEvent) -> Bool
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        var listener = KeyboardListener(target: PathManager.shared.top, keyAction: keyAction, callback: callback)
        content.background(listener)
            .onAppear {
                listener.window = NSApplication.shared.keyWindow
            }
    }

    private struct KeyboardListener: NSViewRepresentable {
        var target: Target?
        var keyAction: KeyAction?
        var callback: (NSEvent) -> Bool
        var window: NSWindow?
        var nsView: NSView?

        func makeCoordinator() -> Coordinator {
            Coordinator(self)
        }
        
        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            view.addTrackingArea(NSTrackingArea(rect: view.bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: context.coordinator))
            context.coordinator.nsView = view
            return view
        }

        func updateNSView(_ nsView: NSView, context: Context) {
        }

        class Coordinator: NSObject {
            var parent: KeyboardListener
            var nsView: NSView?
            var monitor: Any?

            init(_ parent: KeyboardListener) {
                self.parent = parent
                super.init()
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    // 仅在视图所在 case 与当前栈顶 case 相同时处理（忽略关联值差异）
                    let tA = parent.target
                    let tB = PathManager.shared.top
                    let sameCase: Bool = {
                        switch (tA, tB) {
                        case (.some(.main), .some(.main)), (.some(.setting), .some(.setting)), (.some(.addCommand), .some(.addCommand)), (.some(.playground), .some(.playground)), (.some(.editCommand), .some(.editCommand)), (.some(.chat), .some(.chat)):
                            return true
                        default:
                            return false
                        }
                    }()
                    if sameCase {
                        if parent.keyAction == nil || event.action == parent.keyAction {
                            return parent.callback(event) ? nil : event
                        }
                    }
                    return event
                }
            }

            deinit {
                if let m = monitor { NSEvent.removeMonitor(m) }
            }
        }
    }
}

extension View {
    func onKeyPressed(callback: @escaping (NSEvent) -> Bool) -> some View {
        modifier(OnKeyPressed(callback: callback))

    }
    func onKeyPressed(_ keyAction: KeyAction, callback: @escaping (NSEvent) -> Bool) -> some View {
        modifier(OnKeyPressed(keyAction: keyAction, callback: callback))
    }
}


struct KeyEventsContentView: View {
    var body: some View {
        VStack {
            Text("Hello, World!")
        }
        .onKeyPressed { event in
            print("key \(event.characters)")
            return true
        }
    }
}
