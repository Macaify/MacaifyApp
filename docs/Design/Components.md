# Components Library

Tabs Toolbar
- Horizontal toolbar with icon + label items.
- Enum-driven `SettingsTab` with `title`, `symbol`.

Cards
- Reusable `SettingsCard` with title, subtitle, content slot.
- Optional footer area for CTA buttons.

List Rows
- ProviderRow: name, baseURL, status badge (Verified/Rate-limited/Invalid), context actions.
- ModelRow: name, caps chips (context, vision), lock badge.

Badges
- PlanBadge: Free/Pro/Pro+.
- StatusBadge: Verified/Failed/Syncing.
- LockBadge: “Pro”/“Pro+”.

Dialogs/Sheets
- UpgradeSheet: reason bullets + CTA open website + fallback to providers.
- ProviderEditor: create/edit provider (name, baseURL, key, organization).

Pickers
- SourcePicker: Account Credits | My Providers.
- ModelPicker: shows lock state and provider availability.

