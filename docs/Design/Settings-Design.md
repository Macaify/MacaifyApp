# Settings UX Design (macOS)

Goals
- Elevate perceived value of paid plans (Free/Pro/Pro+).
- Make “Account credits first, custom providers optional” crystal clear.
- Reduce setup friction while giving power users deep control.
- Use native macOS patterns: toolbar tabs, grouped forms, sheets.

Information Architecture (Tabs)
- Account: Login, plan, credits, upgrade CTA.
- AI Providers: Manage multiple custom providers (OpenAI/Anthropic/Compatible).
- Models: All models vs My Providers; lock states and Upgrade prompts.
- Defaults: Default source and model; new chat behavior.
- Advanced: Privacy, network (proxy), language, updates.

Visual System
- Surface: Translucent backgrounds where appropriate; grouped cards.
- Elevation: Light shadows, 8–12pt corner radius on cards.
- Icons: SF Symbols only; consistent color accents per capability.
- Density: Primary actions visible; secondary in-line; avoid clutter.

Micro‑copy
- Account: “Use your account credits for the best experience.”
- Models (locked): “Pro+ required. Upgrade to unlock.”
- Fallback: “Prefer your own keys? Switch to ‘My Providers’.”

Motion
- Tab transitions: subtle slide/fade.
- Lock → Upgrade sheet: spring modal with dimmed backdrop.

Entry Points
- Toolbar button opens Settings.
- In-chat model picker mirrors same lock/upgrade patterns.

Accessibility
- Large hit targets; keyboard navigable controls; VoiceOver labels.

