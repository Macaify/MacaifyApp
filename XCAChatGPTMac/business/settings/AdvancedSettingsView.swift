import SwiftUI
import Defaults

struct AdvancedSettingsView: View {
    @State private var apiKey: String = APIKeyManager.shared.getAPIKey()
    @AppStorage("proxyAddress") private var proxyAddress = "https://openai.gokoding.com"
    @AppStorage("useVoice") private var useVoice = false

    var body: some View {
        Form {
            Section(String(localized: "API 与网络")) {
                TextField(String(localized: "API Key"), text: $apiKey)
                TextField(String(localized: "Base URL"), text: $proxyAddress)
                HStack { Spacer(); Button(String(localized: "保存")) { APIKeyManager.shared.setAPIKey(apiKey) } }
            }
            Section(String(localized: "语言与语音")) {
                Toggle(String(localized: "语音聊天"), isOn: $useVoice)
            }
            Section(String(localized: "应用更新")) {
                AppUpdaterLink().environmentObject(AppUpdaterHelper.shared.updater)
            }
        }
        .formStyle(.grouped)
    }
}
