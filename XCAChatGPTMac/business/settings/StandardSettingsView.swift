import SwiftUI

struct StandardSettingsView: View {
    @AppStorage("settings.selectedTab") private var storedTab: String = SettingsTab.account.rawValue
    @State private var selection: SettingsTab?

    init() {
        _selection = State(initialValue: SettingsTab(rawValue: UserDefaults.standard.string(forKey: "settings.selectedTab") ?? SettingsTab.account.rawValue) ?? .account)
    }

    var body: some View {
        if #available(macOS 13.0, *) {
            NavigationSplitView(sidebar: {
                sidebar
            }, detail: {
                detail
            })
            .frame(minWidth: 920, minHeight: 580)
        } else {
            HStack(spacing: 0) {
                sidebar.frame(width: 240)
                Divider()
                detail
            }
            .frame(minWidth: 920, minHeight: 580)
        }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                Label(tab.title, systemImage: tab.systemImage)
                    .tag(tab)
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var detail: some View {
        Group {
            switch selection ?? .account {
            case .account: AccountSettingsView().padding(24)
            case .providers: ProvidersSettingsView().padding(24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background)
        .onChange(of: selection) { newValue in
            storedTab = (newValue ?? .account).rawValue
        }
        .onAppear { selection = SettingsTab(rawValue: storedTab) ?? .account }
        .onChange(of: storedTab) { _ in selection = SettingsTab(rawValue: storedTab) ?? .account }
    }
}
