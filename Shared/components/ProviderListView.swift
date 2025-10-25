import SwiftUI

/// A simple provider instances list using the same visual style as ModelPickerPopover's custom instance rows.
struct ProviderListView: View {
    @ObservedObject private var store = ProviderStore.shared
    var isSelected: (CustomModelInstance) -> Bool = { _ in false }
    var onTap: (CustomModelInstance) -> Void = { _ in }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(store.providers) { inst in
                    ProviderInstanceRow(inst: inst, isSelected: isSelected(inst)) {
                        onTap(inst)
                    }
                }
            }
            .padding(8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Public reusable component for custom instance rows

/// 通用的自定义实例行组件，显示图标、名称、选中状态和配置状态
/// 可在多个模型选择器场景中复用
struct ProviderInstanceRow: View {
    let inst: CustomModelInstance
    let isSelected: Bool
    var onTap: () -> Void
    /// 是否在 hover 时执行额外操作（如关闭详情面板），默认不执行
    var onHoverChange: ((Bool) -> Void)? = nil
    
    @State private var hovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                ProviderIconView(provider: inst.provider)
                Text(inst.name)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").foregroundStyle(.secondary)
                } else {
                    let hasToken = (ProviderStore.shared.token(for: inst.id) ?? "").isEmpty == false
                    if !hasToken {
                        GateBadge(text: String(localized: "未配置"), tint: .orange)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(hovered ? Color.gray.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
        .containerShape(.rect)
        .onHover { inside in
            hovered = inside
            onHoverChange?(inside)
        }
    }
}

