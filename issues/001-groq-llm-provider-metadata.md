# Groq LLM provider + finish metadata pipeline

**Triage:** `ready-for-agent`  
**Milestone:** v1 · Phase A2

## Parent

[PRD: Phase A — AI Intelligence](../docs/prd/PRD-phase-a-ai.md)

## What to build

Finish Phase A2 by replacing the hard-coded Ollama-only metadata path with a shared generative LLM stack:

```
protocol LLMProvider: Sendable {
  func complete(prompt: String) async throws -> String
}

LLMProviderChain: Groq (Keychain key present) → Ollama localhost → unavailable
```

**Groq** is primary (`llama-3.3-70b-versatile` default, user-configurable). API key lives in **macOS Keychain only** — never UserDefaults. **Ollama** remains optional fallback. **Sensitive clips** (`isSensitive`) never call Groq or Ollama; they keep rules-only metadata.

Wire the chain into `AIMetadataService` / `MetadataIndexer` for clips ≥200 chars. Short clips stay rules-only (&lt;200 chars). Settings gains Groq API key field + model field + status (configured / missing key). Remove any UX that implies Ollama must be running for metadata.

Most A2 surface already exists (schema, tags, similar clips, `tag:` search, indexing UI). This slice completes the LLM path and Settings.

## Acceptance criteria

- [ ] `LLMProvider` protocol + `GroqChatProvider` + `LLMProviderChain` implemented
- [ ] Groq API key saved/read via Keychain; injectable store for tests
- [ ] Settings: Groq key field, model field (default `llama-3.3-70b-versatile`), shared Ollama URL retained for fallback
- [ ] Long text clip with Groq configured receives title + summary + tags without Ollama running
- [ ] Groq unavailable → Ollama fallback works when localhost is up
- [ ] No key and no Ollama → rules-only metadata; app does not crash
- [ ] Sensitive clips never invoke Groq or Ollama; rules-only metadata only
- [ ] Unit tests: fake `LLMProvider` drives metadata parse; chain order tested (Groq → Ollama → throw)
- [ ] Existing A2 tests still pass (`AIMetadataTests`, `TagSearchTests`, `SimilarClipsTests`)

## Blocked by

None — can start immediately

## User stories

13, 14, 15, 16, 17, 21, 23, 43, 45
