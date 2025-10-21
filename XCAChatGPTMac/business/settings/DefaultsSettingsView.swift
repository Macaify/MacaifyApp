import SwiftUI
import Defaults

struct DefaultsSettingsView: View {
    @Default(.maxToken) private var maxToken
    @Default(.launchAtLogin) private var launchAtLogin

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsTokens.spacing) {
            GroupBox {
                Toggle(String(localized: "开机启动"), isOn: $launchAtLogin)
            } label: {
                Label(String(localized: "通用"), systemImage: "gearshape")
            }

            GroupBox {
                AppShortcuts()
            } label: {
                Label(String(localized: "快捷键"), systemImage: "command")
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    LanguageOptions()
                    AppUpdaterLink().environmentObject(AppUpdaterHelper.shared.updater)
                }
            } label: {
                Label(String(localized: "语言与更新"), systemImage: "globe")
            }

            GroupBox {
                Stepper(value: $maxToken, in: 256...200000, step: 256) {
                    HStack {
                        Text(String(localized: "最大 Token"))
                        Spacer()
                        Text("\(maxToken)").foregroundStyle(.secondary)
                    }
                }
            } label: {
                Label(String(localized: "高级"), systemImage: "slider.horizontal.3")
            }
        }
        .groupBoxStyle(CardGroupBoxStyle())
    }
}
