//
//  MainWindowController.swift
//  Macaify
//
//  Created by lixindong on 2024/10/2.
//

import Foundation
import AppKit
import SwiftUI
import BetterAuth

class MainWindowController: NSWindowController, NSWindowDelegate {
    static let shared = MainWindowController()
    
    var contentView: ContentViewWrapper!
    var isVisible: Bool {
        window?.isVisible ?? false
    }
    
    // MARK: events
    
    var commandLocalMonitor = KeyMonitor(.command)
    var pathManager = PathManager.shared
    let globalConfig = GlobalConfig()
    
    convenience init() {
        self.init(windowNibName: "MainWindow")
        contentView = ContentViewWrapper()
    }
    
    override func loadWindow() {
        let rect = NSRect(x: 0, y: 0, width: 960, height: 640)
        window = MainWindow(contentRect: rect,
                            styleMask: [.titled, .resizable, .closable, .miniaturizable],
                            backing: .buffered, defer: true)
        guard let window else { return }
        window.level = .normal
        window.title = "Macaify"
        window.isMovableByWindowBackground = false
        window.titlebarAppearsTransparent = false
        window.backgroundColor = .windowBackgroundColor

        window.contentView = NSHostingView(rootView: contentView.environmentObject(globalConfig))
        window.center()
        window.delegate = self

        // SwiftUI Toolbar is provided in MainView. Remove AppKit toolbar to avoid duplication/layout shifts.
        window.toolbar = nil
    }
    
    func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        guard let window = window else { return }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        showWindow(nil)
    }
    
    func closeWindow() {
        close()
        window?.close()
    }
    
    func toggle() {
        if isVisible {
            closeWindow()
        } else {
            showWindow()
        }
    }
    
    func windowDidResignKey(_ notification: Notification) {
        unobserveEvents()
    }
    
    func windowDidBecomeKey(_ notification: Notification) {
        observeEvents()
    }
    
    func observeEvents() {
        commandLocalMonitor.handler = {
            print("Command key was held down for 1 second")
            withAnimation {
                self.globalConfig.showShortcutHelp = true
            }
        }
        commandLocalMonitor.onKeyUp = {
            withAnimation {
                self.globalConfig.showShortcutHelp = false
            }
        }
        commandLocalMonitor.start()
    }
    
    func unobserveEvents() {
        commandLocalMonitor.stop()
    }
}

class MainWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

struct ContentViewWrapper: View {
    @Environment(\.scenePhase) private var scenePhase

    @StateObject var vm = ConversationViewModel.shared
    @StateObject private var emojiViewModel = EmojiPickerViewModel()
    @AppStorage("selectedLanguage") var userDefaultsSelectedLanguage: String?
    @StateObject private var authClient = BetterAuthClient(
        baseURL: URL(string: "http://localhost:3000")!
//        baseURL: URL(string: "https://dash.macaify.com")!
      )

    var body: some View {
        MacContentView()
            .environmentObject(vm)
            .environmentObject(emojiViewModel)
            .environment(\.locale, .init(identifier: userDefaultsSelectedLanguage ?? "en"))
            .environmentObject(authClient)
            .onReceive(NotificationCenter.default.publisher(for: .init("BetterAuthSignedOut"))) { _ in
                Task { await authClient.session.refreshSession() }
            }
            .cornerRadius(12)
            .background {
                Button {
                    MainWindowController.shared.closeWindow()
                } label: {
                    Image(systemName: "xmark")
                }.keyboardShortcut("w", modifiers: .command)
                    .keyboardShortcut(.escape, modifiers: [])
                    .hidden()
            }
    }
}

// (Toolbar logic moved to SwiftUI .toolbar in MainView)
