import SwiftUI
import Defaults

struct DefaultsSettingsView: View {
    @Default(.maxToken) private var maxToken
    @Default(.launchAtLogin) private var launchAtLogin

    var body: some View {
        Form {
            Section(String(localized: "通用")) {
                Toggle(String(localized: "开机启动"), isOn: $launchAtLogin)
            }
            Section(String(localized: "快捷键")) {
                AppShortcuts()
            }
            Section(String(localized: "语言与更新")) {
                LanguageOptions()
                AppUpdaterLink().environmentObject(AppUpdaterHelper.shared.updater)
            }
            Section(String(localized: "最大 Token")) {
                Stepper(value: $maxToken, in: 256...200000, step: 256) { Text("\(maxToken)") }
            }
        }
        .formStyle(.grouped)
    }
}
