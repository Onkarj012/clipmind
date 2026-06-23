# Detail-view AI actions with preview sheet

**Triage:** `ready-for-agent`  
**Milestone:** v1 · Phase A3

## Parent

[PRD: Phase A — AI Intelligence](../docs/prd/PRD-phase-a-ai.md)

## What to build

Add user-initiated AI transforms on **clip detail view only** (not command palette). Reuse `LLMProviderChain` from issue 001.

**Core six actions:**

| Action | Purpose |
|--------|---------|
| Summarize | Shorter prose summary |
| Shorter | Condense while keeping meaning |
| Explain | Plain-language explanation (code/errors) |
| Format JSON | Pretty-print / fix malformed JSON |
| Bullet points | Extract bullets from prose |
| Extract links | List URLs found in clip |

Flow: user picks action → `AIActionService` calls LLM with action-specific prompt → **preview sheet** shows result → user Copy, Paste, or Cancel. Sensitive clips: actions hidden or disabled; content never sent to cloud. No LLM available: clear error state, no infinite spinner.

Smart paste output shapes supported in preview where applicable (plain, bullets, Markdown/JSON).

## Acceptance criteria

- [ ] `AIActionService` with six actions; each has dedicated prompt template
- [ ] Uses shared `LLMProviderChain` (Groq → Ollama)
- [ ] Detail view action menu for text/code clips
- [ ] Preview sheet before paste with Copy / Paste / Cancel
- [ ] Sensitive clips: actions not available
- [ ] No provider: graceful unavailable message
- [ ] Format JSON action produces parseable JSON (unit tested with fake provider)
- [ ] Unit tests per action shape via fake `LLMProvider`; no live HTTP in tests
- [ ] Manual: malformed JSON clip → Format JSON → valid output in preview → paste works

## Blocked by

- [001 — Groq LLM provider + finish metadata pipeline](001-groq-llm-provider-metadata.md)

## User stories

24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35
