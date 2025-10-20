# Settings Redesign Roadmap

Phase 1 — Scaffold (this PR)
- Add tabbed Settings container and stub pages.
- Migrate existing fields into Advanced/Defaults.
- Persist selected tab; keep back navigation.

Phase 2 — Account & Defaults
- Account page with login panel, plan badge, credits placeholder, upgrade CTA.
- Defaults: default source (Account/Provider), default model (Best/Specific).
- Wire Defaults to existing Defaults keys.

Phase 3 — AI Providers
- ProviderStore (UserDefaults + Keychain for secrets).
- Providers list, add/edit/delete, connection test placeholder.

Phase 4 — Models Catalog
- All vs My Providers views; lock state by plan.
- Upgrade sheet flow; open external upgrade URL.
- “Best Available” recommendation toggle.

Phase 5 — Advanced
- Privacy, proxy/base URL, language, voice toggle, updater link.

Acceptance
- App builds; Settings accessible; each tab functional per phase.
- No regressions in chat creation and API usage.

