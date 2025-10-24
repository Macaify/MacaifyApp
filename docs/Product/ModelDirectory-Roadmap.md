Model Directory Integration Roadmap (macOS)

Goals
- Use backend unified model catalog for display and selection
- Keep UI simple: My custom instances on top; All models grouped by provider; login/upgrade locks
- Session-level override without touching global default; global default managed in Settings

Deliverables
- MacaifyServiceKit: typed client + ETag/TTL cache + tests
- BackendEnvironment/BackendClientFactory: base URL policy + client factory
- ModelSelectionManager: fetch, group, gate judgment, and selection dispatch
- Unified pickers: Settings popover + Session quick picker
- Basic UX: hover detail card, upgrade sheet

Scope (only active views)
- App entry: XCAChatGPTMacApp.swift → NewMainView.swift (MainSplitView/ChatDetailView)
- Settings: StandardSettingsView → ProvidersSettingsView

Tasks
1) Data + Networking
   - [x] Create MacaifyServiceKit (Moya, ETag, TTL, stale fallback)
   - [x] Add tests for decode/query/etag/ttl/error fallback
   - [x] BackendEnvironment (Debug localhost; Release dash; override by UserDefaults)
   - [x] BackendClientFactory (create ModelsAPI; localhost self-signed trust)

2) State + Mapping
   - [x] Extend ModelSelectionManager with providers grouping, RemoteModelItem, gate
   - [x] Inject membership from BetterAuth; login→refresh; upgrade→sheet
   - [x] Handle not logged in + Free plan available rule

3) Settings UI
   - [x] ProvidersSettingsView: add Default Model button; wire service catalog in “账号模型”
   - [x] Debug-only base URL label in header for verification
   - [x] Login/Upgrade actions

4) Session UI
   - [x] NewMainView ModelQuickPicker uses service catalog (with My Instances)
   - [x] Only update conversation.modelSource/modelId; do not touch global Defaults
   - [x] Hover secondary popover with model details

5) Polishing
   - [x] MembershipUpgradeSheet (placeholder visuals)
   - [x] ModelDetailCard (capabilities/context/pricing)
   - [x] Ensure project includes Shared/backend + components in build

Validation
- Package tests: `cd Packages/MacaifyServiceKit && swift test` (all passing)
- Debug build: Settings → Providers shows Base: http://localhost:3000 and lists providers/models
- Session picker: quick switch model works; login/upgrade triggers as expected

Next (optional)
- Restyle MembershipUpgradeSheet to match final design snippet
- Expand ModelDetailCard (scores, fuller descriptions)
- Add toolbar picker for other views if needed

