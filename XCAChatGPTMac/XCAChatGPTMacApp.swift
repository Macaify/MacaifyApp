//
//  XCAChatGPTMacApp.swift
//  XCAChatGPTMac
//
//  Created by Alfian Losari on 04/02/23.
//

import SwiftUI
import AppKit
import AppUpdater
import BetterAuth
import BetterAuthBrowserOTT
//import FirebaseCore

@main
struct XCAChatGPTMacApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) private var openWindow
//    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

//    @StateObject var vm = CommandStore.shared.menuViewModel
    @StateObject private var appState = AppState()
    @StateObject private var typingInPlace = TypingInPlace.shared
    @State var commandKeyDown: Bool = false
    @State var commandKeyDownTimestamp: TimeInterval = 0
    
    @StateObject var updater = AppUpdaterHelper.shared.updater
    
    @AppStorage("selectedLanguage") var userDefaultsSelectedLanguage: String?
    
    @StateObject private var authClient = BetterAuthClient(
        baseURL: URL(string: "http://localhost:3000")!,
//        baseURL: URL(string: "https://dash.macaify.com")!,
        plugins: [
            // Open auth URL in the default browser and wait for deep link callback
            BrowserOTTPlugin(decideOpen: { url, _ in
                #if os(macOS)
                NSWorkspace.shared.open(url)
                #endif
                return true
            })
        ]
    )

    var body: some Scene {
        windowView
        menuView
        settingsView
    }

    private var windowView: some Scene {
        WindowGroup {
            MainSplitView()
                .frame(minWidth: 920, minHeight: 600)
                .onOpenURL { url in
                    // Forward deep links to the OTT plugin
                    BrowserOTTDeepLinkCenter.resume(with: url)
                }
                .task {
                    // Load initial session on app start
                    await authClient.session.refreshSession()
                }
        }
    }
    @State private var dots = ""
    @State var menuAnimateTimer: Timer? = nil

    @available(macOS 13.0, *)
    private var menuView: some Scene {
        MenuBarExtra {
            if TypingInPlace.shared.typing {
                Button {
                    TypingInPlace.shared.interupt()
                } label: {
                    Text("Stop ")
                    Image(systemName: "stop.circle")
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 24))
                }
                .buttonStyle(.borderless)
            }
            Button {
                resume()
            } label: {
                Text("open_macaify")
            }
            Divider()
            Button {
                if let url = URL(string: "https://macaify.com") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Text("website")
            }
            .buttonStyle(.borderless)
            Button {
                if let url = URL(string: "https://twitter.com/macaify") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Text("twitter")
            }
            .buttonStyle(.borderless)
            Button {
                if let url = URL(string: "mailto:macaify@gokoding.com") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Text("feedback")
            }
            .buttonStyle(.borderless)
            
            Divider()
            
            AppUpdaterLink()
                .environmentObject(updater)
            
            Divider()
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("Quit")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.init("q"))
        } label: {
            if TypingInPlace.shared.typing {
                Text("Typing\(dots)🖌️")
                    .onAppear {
                        // Start the timer when the view appears
                        self.menuAnimateTimer = Timer.scheduledTimer(withTimeInterval: 1.0/3.0, repeats: true) { timer in
                            withAnimation {
                                // Update the dots every time the timer fires
                                switch dots.count {
                                case 0:
                                    dots = "."
                                case 1:
                                    dots = ".."
                                case 2:
                                    dots = "..."
                                case 3:
                                    dots = ""
                                default:
                                    break
                                }
                            }
                        }
                    }
                    .onDisappear {
                        self.menuAnimateTimer?.invalidate()
                        self.menuAnimateTimer = nil
                    }
            }
            else {
                Image("menubar")
                    .resizable()
                    .frame(width: 8)
            }
        }
        .menuBarExtraStyle(.menu)
        .environment(\.locale, .init(identifier: userDefaultsSelectedLanguage ?? "en"))
    }

    private var settingsView: some Scene {
        Settings {
            StandardSettingsView()
                .environmentObject(authClient)
                .onOpenURL { url in
                    BrowserOTTDeepLinkCenter.resume(with: url)
                }
                .task {
                    await authClient.session.refreshSession()
                }
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    init() {
        HotKeyManager.initHotKeys()
        DispatchQueue(label: "EmojiManager").async {
            let _ = EmojiManager.shared.emojis
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var globalMonitor = KeyMonitorManager.shared

    func application(_ application: NSApplication, open urls: [URL]) {
        print("application")
    }
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        print("application will finish launching")
        NSApp.appearance = NSAppearance(named: .aqua)
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("application did finish launching")
//        FirebaseApp.configure()
//        MenuBarManager.shared.setupMenus()
        AULog.printLog = true
        AppUpdaterHelper.shared.initialize()
        globalMonitor.start()
        globalMonitor.updateModifier(appShortcutKey())
        // Using SwiftUI WindowGroup as main window (MainSplitView)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        print("applicationShouldTerminateAfterLastWindowClosed")
        return false
    }
    func applicationDidReceiveMemoryWarning(_ application: NSApplication) {
        print("log-DidReceiveMemoryWarning")
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if let w = NSApp.windows.first { w.makeKeyAndOrderFront(nil) }
        NSApp.activate(ignoringOtherApps: true)
        return true
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        print("windowShouldClose")
//        sender.orderOut(self)
//        sender.miniaturize(nil)
        NSApp.hide(nil)
        return false
    }
}
