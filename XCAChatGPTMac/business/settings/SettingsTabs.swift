import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable, Hashable {
    case account
    case providers
    case preferences

    var id: String { rawValue }

    var title: String {
        switch self {
        case .account: return String(localized: "Account")
        case .providers: return String(localized: "模型与来源")
        case .preferences: return String(localized: "偏好设置")
        }
    }

    var systemImage: String {
        switch self {
        case .account: return "person.crop.circle"
        case .providers: return "server.rack"
        case .preferences: return "slider.horizontal.3"
        }
    }
}

struct SettingsTopTabs: View {
    @Binding var selection: SettingsTab

    var body: some View {
        HStack(spacing: 12) {
            ForEach(SettingsTab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { selection = tab }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: tab.systemImage)
                            .symbolRenderingMode(selection == tab ? .multicolor : .hierarchical)
                            .font(.system(size: 18, weight: .semibold))
                        Text(tab.title)
                            .font(.footnote)
                    }
                    .frame(width: 120, height: 66)
                    .background(
                        ZStack {
                            if selection == tab {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.accentColor.opacity(0.10))
                                    .shadow(color: Color.accentColor.opacity(0.18), radius: 6, y: 4)
                            }
                        }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(selection == tab ? Color.accentColor.opacity(0.3) : Color.gray.opacity(0.2), lineWidth: 1)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
