//
//  XCAChatGPTMacApp.swift
//  XCAChatGPTMac
//
//  Created by Alfian Losari on 04/02/23.
//

import SwiftUI
import CoreData
import Foundation
import AppKit
import AppUpdater
import BetterAuth
import BetterAuthBrowserOTT
//import FirebaseCore
import ApplicationServices

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
    
//    @AppStorage("selectedLanguage") var userDefaultsSelectedLanguage: String?
    
    @StateObject private var authClient = BetterAuthClient(
        // baseURL: URL(string: "http://localhost:3000")!,
       baseURL: URL(string: "https://dash.macaify.com")!,
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
        Window("", id: "main") {
            MainSplitView()
                .environmentObject(authClient)
                .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
                .frame(minWidth: 920, minHeight: 600)
                .onOpenURL { url in
                    // Forward deep links to the OTT plugin
                    BrowserOTTDeepLinkCenter.resume(with: url)
                }
                .task {
                    // Load initial session on app start
                    await authClient.session.refreshSession()
                    // Inject membership into model manager and refresh models once per app launch
                    await MainActor.run {
                        let loggedIn = authClient.session.data?.user != nil
                        let planStr = authClient.session.data?.user.membership?.type ?? authClient.session.data?.user.membershipType
                        let plan: MembershipPlan? = {
                            guard let t = planStr?.lowercased() else { return nil }
                            if t == "pro+" || t == "proplus" { return .proPlus }
                            if t == "pro" { return .pro }
                            return .free
                        }()
                        struct Injected: MembershipProvider { let isLoggedIn: Bool; let currentPlan: MembershipPlan? }
                        ModelSelectionManager.shared.membership = Injected(isLoggedIn: loggedIn, currentPlan: plan)
                    }
                    await ModelSelectionManager.shared.refreshRemote()
                }
                .onAppear {
                    // Register a global opener that ensures exactly one main window.
                    WindowBridge.shared.openMainWindow = {
                        if let win = WindowBridge.shared.mainWindow {
                            if win.isMiniaturized { win.deminiaturize(nil) }
                            win.makeKeyAndOrderFront(nil)
                        } else if !WindowBridge.shared.openingMain {
                            WindowBridge.shared.openingMain = true
                            openWindow(id: "main")
                        }
                        NSApp.activate(ignoringOtherApps: true)
                    }
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
                    HStack(spacing: 4) { Text("stop"); Text("") }
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
                if let url = URL(string: "https://twitter.com/sintoneli") {
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
                Text("quit")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.init("q"))
        } label: {
            if TypingInPlace.shared.typing {
                (Text("typing") + Text(dots) + Text("🖌️"))
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
    }

    private var settingsView: some Scene {
        Settings {
            StandardSettingsView()
                .environmentObject(authClient)
                .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
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
        // Run one-time data migrations on startup
        DataMigrationManager.shared.runMigrations()
        AppUpdaterHelper.shared.initialize()
        globalMonitor.start()
        globalMonitor.updateModifier(appShortcutKey())
        // Using SwiftUI WindowGroup as main window (MainSplitView)
        // Accessibility onboarding is now handled by a first‑run sheet in MainSplitView.
        // Seed default agents on first launch when database is empty
        Task {
            await MainActor.run {
                let seededKey = "defaultConversationsSeeded.v1"
                let already = UserDefaults.standard.bool(forKey: seededKey)
                let hasData = !PersistenceController.shared.loadConversations().isEmpty
                if !already && !hasData {
                    let preferred = (Bundle.main.preferredLocalizations.first?.lowercased()
                                     ?? Locale.preferredLanguages.first?.lowercased()
                                     ?? "en")
                    let lang = preferred.hasPrefix("zh") ? "zh" : "en"
                    initializeIfNeeded(lang)
                    UserDefaults.standard.set(true, forKey: seededKey)
                }
            }
        }
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

// MARK: - Centralized data migration manager
final class DataMigrationManager {
    static let shared = DataMigrationManager()
    private init() {}

    private let providersKey = "custom.providers"
    private let providerFieldMigrationKey = "custom.providers.migratedProviderField.2025-10-25"
    private let baseURLV1MigrationKey = "custom.providers.migratedBaseURLv1.2025-10-25"

    func runMigrations() {
        migrateProvidersFieldIfNeeded()
        migrateBaseURLV1IfNeeded()
    }

    private func migrateProvidersFieldIfNeeded() {
        let ud = UserDefaults.standard
//        guard !ud.bool(forKey: providerFieldMigrationKey) else { return }
        guard let data = ud.data(forKey: providersKey) else { ud.set(true, forKey: providerFieldMigrationKey); return }
        do {
            var list = try JSONDecoder().decode([CustomModelInstance].self, from: data)
            var changed = false
            for i in 0..<list.count {
                let v = list[i].provider.lowercased()
                if v == "compatible" || v == "anthropic" {
                    list[i].provider = "openai"
                    changed = true
                }
            }
            if changed {
                let out = try JSONEncoder().encode(list)
                ud.set(out, forKey: providersKey)
            }
            ud.set(true, forKey: providerFieldMigrationKey)
        } catch {
            ud.set(true, forKey: providerFieldMigrationKey)
        }
    }

    private func migrateBaseURLV1IfNeeded() {
        let ud = UserDefaults.standard
        guard !ud.bool(forKey: baseURLV1MigrationKey) else { return }
        guard let data = ud.data(forKey: providersKey) else { ud.set(true, forKey: baseURLV1MigrationKey); return }
        do {
            var list = try JSONDecoder().decode([CustomModelInstance].self, from: data)
            var changed = false
            for i in 0..<list.count {
                let raw = list[i].baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !raw.isEmpty else { continue }
                if let comp = URLComponents(string: raw) {
                    let path = comp.path
                    if !path.hasPrefix("/v1") {
                        let trimmed = raw.hasSuffix("/") ? String(raw.dropLast()) : raw
                        list[i].baseURL = trimmed + "/v1"
                        changed = true
                    }
                }
            }
            if changed {
                let out = try JSONEncoder().encode(list)
                ud.set(out, forKey: providersKey)
            }
            ud.set(true, forKey: baseURLV1MigrationKey)
        } catch {
            ud.set(true, forKey: baseURLV1MigrationKey)
        }
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
