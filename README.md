# Macaify — AI in any Mac app, no ⌘‑Tab
> 
> Select → Shortcut → Done. No app switching, no interruption.

Macaify is a native macOS AI app focused on preserving your flow: select text in any app, hit a shortcut, and get translation, rewrite, polishing, or summarization done in place. It also provides full chat mode and quick model switching. Use built‑in account models or your own API key (BYOK).

- macOS 12.0+ · Apple Silicon and Intel supported
- Free & Open Source · Attribution required (see `LICENSE`)
- Two modes: In‑Context (Any App) and Chat
- Model sources: Macaify account models or BYOK


## Focus, not switching
Switching to an AI tool, copy/paste, waiting, and switching back often costs more time and fragments your thoughts. Macaify integrates AI into your workflow instead of becoming another destination.

That’s why we built In‑Context: Select → Shortcut → Done. No switching, no extra thinking, no interruption. Chat mode remains familiar, with selected content pinned as context at the top.


## Highlights
- In‑Context (Any App)
  - Use shortcuts to translate, polish, or rewrite right where the text is.
  - Optional Typing In Place: replace the selection with the AI reply, no window pop‑up.
- Chat mode
  - Pin selected text as context; Markdown rendering and code highlighting.
  - Auto‑generated conversation titles; manage multiple sessions.
- Models and providers
  - Built‑in account models (login required; availability per plan).
  - BYOK: OpenAI / OpenAI‑compatible services with custom Base URL.
  - Quick picker and templates: set recommended models as default, or create custom instances from templates.
- Shortcuts
  - System‑wide: Option+V (CN‑EN translate), Option+S (Summarize), Option+Q (Quick ask).
  - ⌘K Command menu: send/retry, copy/paste last reply, switch agent, new chat.
- UX details
  - Native SwiftUI; menu bar entry; auto‑update; accessibility onboarding.
  - Useful prompt templates are pre‑seeded on first launch.


## Preview
- Accessibility permission walkthrough (video, playable on GitHub):
  - docs/Assets/accessibility_guide.mp4


## Install
- Download: visit `https://macaify.com` for signed builds.
- From source: see below.


## Build from source
> Tooling may move with dependencies. If you hit issues, please open an issue with details.

- OS: macOS 12.0+
- Tools: Xcode 16+ (Swift 6 toolchain)
- Clone with submodules:
  ```bash
  git clone --recursive git@github.com:YOUR_ORG/ChatGPTSwiftUI.git
  # If already cloned:
  git submodule update --init --recursive
  ```
- Open `XCAChatGPT.xcodeproj`, select the `XCAChatGPTMac` scheme, and run.
- First run:
  - Ships with default agents and shortcuts based on system language.
  - You will be asked to grant Accessibility permission (read selection, paste automation) locally.

Tip: If you just want BYOK, no account setup is needed. If you want Macaify account models, ensure `macaify.com` is reachable and sign in under Settings.


## Quick start
1) Pick a default model
- Settings → Accounts & Models. Pick from “Account models” or “My model instances”.
- BYOK: “Add from template” or “Add custom model” → fill `Model ID`, `Base URL`, and `API Key` → Save → “Set as default”.

2) Permissions & hotkeys
- In‑Context asks for Accessibility permission the first time.
- Default hotkeys:
  - Option+V: CN‑EN translate (Typing In Place)
  - Option+S: Summarize selection
  - Option+Q: Quick ask
  - ⌘K: Command menu
- Customize in Settings → Shortcuts.

3) Use it
- Select text in any app → hit a shortcut → stream in place.
- For chat: open the main window to create/switch sessions; selected content can be pinned as context.


## Configuration
- Account models (no key needed)
  - After sign‑in, you can use recommended providers (availability depends on plan).
  - Auth and membership are provided by `macaify.com` (see `XCAChatGPTMac/XCAChatGPTMacApp.swift:1`, `Shared/backend/BackendEnvironment.swift:1`).
- BYOK (your own API key)
  - Add custom instance in “My model instances”: `modelId`, `baseURL` (OpenAI‑compatible; usually ends with `/v1`), `provider` (typically `openai`).
  - Token is stored locally (UserDefaults) and used only to call your configured API host.
  - Use “Test connection” to verify settings.


## Privacy
- In‑Context selection reading and paste automation happen locally only.
- Account models talk to `macaify.com` for auth, quota checks, and routing.
- BYOK requests go directly to your configured API endpoint.
- No unrelated telemetry. See code for details.


## Project layout (short)
- `XCAChatGPTMac/`: macOS app entry and views (main window, menu bar, settings).
- `Shared/`: cross‑platform code (persistence, rendering, Chat API, components).
- `Packages/`: local deps (`BetterAuthSwift`, `AppUpdater`, `OpenAI`, `MacaifyServiceKit`, …).
- Pointers:
  - Chat API: `Shared/ChatGPTAPI.swift`
  - Providers & models: `XCAChatGPTMac/business/settings/ProvidersSettingsView.swift`
  - Backend env: `Shared/backend/BackendEnvironment.swift`
  - Settings & shortcuts: `XCAChatGPTMac/business/settings/*.swift`


## Roadmap & design docs
- Product requirements: `docs/Product/Requirements.md`
- Roadmap: `docs/Product/Roadmap.md`
- Design guidelines: `docs/Design/Settings-Design.md`, `docs/Design/Settings-Guidelines.md`
- Components/colors: `docs/Design/Components.md`, `docs/Design/Colors.md`


## FAQ
- Q: Toolchain mismatch when building?
  - A: Some deps require Swift 6+. Use Xcode 16+. If you must stay older, you may downgrade/replace deps.
- Q: Do I need `/v1` in `baseURL`?
  - A: Most OpenAI‑compatible hosts require `/v1`. The app can patch it when needed, but it’s safer to include it.
- Q: Where is the token stored?
  - A: Locally in `UserDefaults`. Avoid shared machines; consider temporary tokens when appropriate.
- Q: Can I use it without signing in?
  - A: Yes. Use BYOK to stay outside the account system (you pay the provider directly).


## Contributing
Issues and PRs welcome:
- Provide repro steps, macOS version, and exact UI path.
- Keep diffs focused and scoped; language/localization improvements are welcome.
- If changes affect licensing or permissions, mention that clearly in the PR.


## Acknowledgments
- Original inspirations from the open‑source community (see repo history and `LICENSE`).
- Deps include: OpenAI SDK, MarkdownView/MarkdownUI, Moya/Alamofire, BetterAuth, KeyboardShortcuts, and others.


## License
Follow the attribution rule in `LICENSE`: you may modify, distribute, and use commercially (including closed‑source), but you must show “Powered by Macaify — https://macaify.com” in a user‑visible place and keep copyright/third‑party attributions. The original MIT text is available in `LICENSE-BASE`.

—
If this project helps you, a star means a lot. You can also try the signed builds on the website and consider Pro to support model costs and development.
