# Agents & Sessions – Incremental Plan

Goal
- Separate "definition" (Agent) from "usage" (Session) without breaking current flows, and ship value incrementally.

Concepts
- Agent = Bot definition (name, icon, system prompt, model source, shortcut, defaults).
- Session = A concrete conversation history under an Agent for one task.

Phases
1) Baseline (Done)
   - Keep current Bot = Conversation usage; add UX improvements (model picker, context banner, error banner).
2) Cross‑Agent Quick Actions (This PR)
   - From current chat, support:
     - "Run with other Agent" (single-shot) – execute current input via another Agent and show result inline tagged as `via AgentName`.
     - "Open with other Agent" – switch to selected Agent, prefill input with current text for a clean new chat.
   - No new data model required.
3) Introduce Session entity (Next)
   - Core Data: `GPTAgent`, `GPTSession`, re-map `GPTAnswer` -> `sessionId`.
   - UI: Session switcher (new, recent, archive) under an Agent.
4) Message metadata (Next)
   - Track `executedAgentId` per assistant message when using cross‑Agent run.
   - UI chip "via AgentName" on bubbles.
5) @Agent mention (Optional)
   - Inline override for a single message with agent auto‑complete.
6) Migration (Later)
   - One‑time migration from current Conversation → Agent + default Session.

Non‑Goals Now
- Full-blown multi‑provider blending, advanced routing.

Risk Mitigation
- Keep one main Agent per chat; cross‑Agent actions are one-off or open-in-new-chat to preserve history semantics.

