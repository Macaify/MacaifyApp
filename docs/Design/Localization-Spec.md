Localization Spec (XCAChatGPT)

Scope
- Localize all user‑facing UI strings across macOS, iOS/tvOS/watchOS targets.
- Exclude data content like long built‑in prompt templates and developer logs.
- Keep third‑party example code under Packages/* unchanged.

Files
- Use `Packages/Localizables/en.lproj/Localizable.strings` for English.
- Use `Packages/Localizables/zh-Hans.lproj/Localizable.strings` for Simplified Chinese.

Conventions
- Prefer semantic snake_case keys: example `new_session`, `bot_settings`.
- Reuse existing keys where present (do not invent duplicates).
- For legacy usages that already pass a literal into `String(localized:)`, keep as‑is and ensure translations exist.
- For SwiftUI, use LocalizedStringKey-capable initializers: `Text("key")`, `Button("key")`, `Label("key", ...)`, `.navigationTitle("key")`, `.help("key")`.
- For dynamic values, keep the static part localized and keep the value separate: e.g. `Text("base") + Text(": ") + Text(url)`.
- Do not localize technical identifiers, URLs, code, or tokens shown as data.

Review Checklist
- No hardcoded Chinese or English in UI components (Text, Button, Label, Toggle, Section, help/alert, navigationTitle, placeholders).
- Tooltips and confirmation dialogs localized.
- Default/fallback titles (e.g., Untitled, Chat, No Bot Selected) localized.
- Add missing keys to both `en.lproj` and `zh-Hans.lproj`.

Testing
- Switch app language between English and Chinese to verify the updated UI.
- Verify that String(localized:) legacy keys resolve to expected translations.
