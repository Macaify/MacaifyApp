import SwiftUI

/// Opens the app Settings scene using SettingsLink when available.
/// Also preselects the Providers tab via `settings.selectedTab` AppStorage.
struct ProvidersSettingsLink<Label: View>: View {
    let label: () -> Label

    init(@ViewBuilder label: @escaping () -> Label) {
        self.label = label
    }

    var body: some View {
        Group {
            if #available(macOS 14.0, *) {
                SettingsLink { label() }
                    .simultaneousGesture(TapGesture().onEnded(setProvidersTab))
            } else {
                Button(action: openSettingsManually, label: label)
            }
        }
    }

    private func setProvidersTab() {
        UserDefaults.standard.set(SettingsTab.providers.rawValue, forKey: "settings.selectedTab")
    }

    private func openSettingsManually() {
        setProvidersTab()
        #if os(macOS)
        NSApp.activate(ignoringOtherApps: true)
        let ok1 = NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        if !ok1 { _ = NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil) }
        #endif
    }
}

