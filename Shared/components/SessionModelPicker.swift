import SwiftUI
import Defaults

#if os(macOS)
import BetterAuth
#endif

// A simple session-scoped trigger that reuses the unified ModelPickerPopover via injected handlers.
public struct SessionModelPickerButton: View {
    public var bot: GPTConversation
    public var onPicked: (GPTConversation) -> Void
    public var openBotSettings: () -> Void
    @State private var showPicker = false
    #if os(macOS)
    @EnvironmentObject private var authClient: BetterAuthClient
    @State private var anchorView: NSView? = nil
    #endif

    public init(bot: GPTConversation, onPicked: @escaping (GPTConversation) -> Void, openBotSettings: @escaping () -> Void) {
        self.bot = bot
        self.onPicked = onPicked
        self.openBotSettings = openBotSettings
    }

    private var labelText: String {
        // Instance: prefer custom instance display name
        if bot.modelSource == "instance", let inst = ProviderStore.shared.providers.first(where: { $0.id == bot.modelInstanceId }) {
            return inst.name.isEmpty ? inst.modelId : inst.name
        }
        // Account (per-bot) model: resolve friendly name from remote catalog
        if bot.modelSource == "account", !bot.modelId.isEmpty {
            // Derive provider from catalog by slug; fall back to Defaults for formatting only
            let prov = ModelSelectionManager.shared.modelsByProvider.first(where: { (_, arr) in arr.contains(where: { $0.slug == bot.modelId }) })?.key
            let provider = prov ?? (Defaults[.selectedProvider].isEmpty ? "openai" : Defaults[.selectedProvider])
            let all = ModelSelectionManager.shared.modelsByProvider
            let name = all[provider]?.first(where: { $0.slug == bot.modelId })?.name ?? bot.modelId
            return provider == "openai" ? name : "\(provider):\(name)"
        }
        // Fallback to global default selection
        let model = Defaults[.selectedModelId].isEmpty ? (LLMModelsManager.shared.modelCategories.first?.models.first?.id ?? "gpt-4o-mini") : Defaults[.selectedModelId]
        let provider = Defaults[.selectedProvider].isEmpty ? "openai" : Defaults[.selectedProvider]
        let name = ModelSelectionManager.shared.modelsByProvider[provider]?.first(where: { $0.slug == model })?.name ?? model
        return provider == "openai" ? name : "\(provider):\(name)"
    }

    public var body: some View {
        Button {
            #if os(macOS)
            if let v = anchorView {
                let cfg = ModelPickerPanelBridge.ModelPickerConfig(
                    showHoverDetail: true,
                    isInstanceSelected: { inst in bot.modelSource == "instance" && bot.modelInstanceId == inst.id },
                    isAccountSelected: { _, modelId in bot.modelSource == "account" && bot.modelId == modelId },
                    onPickInstance: { inst in var updated = bot; updated.modelSource = "instance"; updated.modelInstanceId = inst.id; updated.modelId = ""; onPicked(updated) },
                    onPickRemote: { item in var updated = bot; updated.modelSource = "account"; updated.modelId = item.slug; onPicked(updated) }
                )
                ModelPickerPanelBridge.shared.toggle(relativeTo: v, authClient: authClient, config: cfg)
                return
            }
            #endif
            showPicker.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "bolt.horizontal.circle")
                Text(labelText.isEmpty ? String(localized: "选择模型") : labelText)
                    .lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).stroke(Color.gray.opacity(0.25)))
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .background(ModelPickerAnchorResolver(onResolve: { self.anchorView = $0 }))
        #endif
        .popover(isPresented: $showPicker, arrowEdge: .bottom) {
            ModelPickerPopover(
                showHoverDetail: false,
                isInstanceSelected: { inst in bot.modelSource == "instance" && bot.modelInstanceId == inst.id },
                isAccountSelected: { _, modelId in bot.modelSource == "account" && bot.modelId == modelId },
                onPickInstance: { inst in
                    var updated = bot
                    updated.modelSource = "instance"
                    updated.modelInstanceId = inst.id
                    updated.modelId = ""
                    onPicked(updated)
                    showPicker = false
                },
                onPickRemote: { item in
                    var updated = bot
                    updated.modelSource = "account"
                    updated.modelId = item.slug
                    onPicked(updated)
                    showPicker = false
                }
            )
            .frame(width: 320, height: 440)
        }
    }
}
