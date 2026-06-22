# PRD: Phase A — AI Intelligence (v1)

**Triage:** `ready-for-agent`  
**Milestone:** v1  
**Status:** A1 shipped in codebase · A2 ~95% · A3/A4 not started  
**Source:** [ROADMAP-post-v0.md](../plans/ROADMAP-post-v0.md) · grilling session 20 Jun 2026

---

## Problem Statement

ClipMind v0 captures clipboard history and finds clips with keyword (FTS5) search. Developers and power users still lose time hunting for clips they remember vaguely (“that React hydration error from yesterday”), reading long unlabeled entries, manually reformatting pasted content, and searching screenshots by memory alone.

They need a clipboard that **understands** what was copied: natural-language recall, readable titles and tags, on-demand transformations, and text inside images — without requiring a local Ollama daemon or sending secrets to the cloud.

## Solution

Complete **Phase A** in four tracks:

1. **Semantic search (A1)** — hybrid FTS + vector similarity, Apple embeddings by default. *Already implemented.*
2. **AI metadata (A2)** — auto title, summary, tags; similar clips; `tag:` search. Finish by routing long-clip generation through **Groq → Ollama → rules-only**, with API key in Keychain.
3. **AI actions (A3)** — six user-initiated transforms from clip detail, preview-before-paste, same LLM stack.
4. **Vision OCR (A4)** — Apple Vision text extraction on image capture, indexed in FTS and embeddings, toggle in Settings.

Sensitive clips never leave the device for LLM calls. The app works without Ollama running.

## User Stories

### Search & recall (A1 — done)

1. As a developer, I want to search with natural language (4+ words), so that I find clips by meaning not exact keywords.
2. As a developer, I want semantic search to combine with FTS ranking, so that results balance relevance and keyword hits.
3. As a privacy-conscious user, I want embeddings generated on-device via Apple NL by default, so that I don't need external services for search.
4. As a power user, I want to optionally use Ollama for embeddings, so that I can experiment with custom embedding models.
5. As a user, I want tiny clips skipped for embedding, so that indexing stays fast and storage stays small.
6. As a user, I want `type:`, `from:`, and `tag:` prefixes to disable semantic search, so that structured filters stay precise.
7. As a user, I want to disable semantic search in Settings, so that I can fall back to keyword-only search.
8. As a developer, I want stack traces found by queries like “react hydration bug missing props”, so that semantic recall beats FTS alone.

### Metadata & organization (A2)

9. As a user, I want long text clips to get an auto-generated title, so that rows are scannable in the library and palette.
10. As a user, I want long text clips to get a one-line summary, so that I can triage without opening detail.
11. As a user, I want clips tagged automatically (e.g. `error`, `code`), so that I can filter with `tag:error`.
12. As a user, I want short clips (&lt;200 chars) metadata from fast rules without an LLM, so that indexing is instant offline.
13. As a user, I want a Groq API key stored in Keychain, so that my key isn't in plaintext preferences.
14. As a user, I want Groq as the primary LLM for metadata, so that I don't need Ollama running in the background.
15. As a user, I want Ollama as fallback when Groq is unavailable, so that I can still get LLM metadata locally if I choose.
16. As a user with no API key and no Ollama, I want rules-only metadata, so that the app remains usable offline.
17. As a user, I want sensitive clips to never be sent to Groq or Ollama, so that passwords and tokens stay local.
18. As a user, I want an “Indexing…” indicator on fresh clips, so that I know metadata is still processing.
19. As a user, I want to see similar clips in detail view, so that I can find related copies quickly.
20. As a user, I want similar clips ranked by embedding similarity with a minimum score threshold, so that unrelated clips don't appear.
21. As a user, I want to disable AI metadata in Settings, so that I control background processing.
22. As a user, I want tag chips visible on rows and detail, so that tags are glanceable.
23. As a developer, I want a 500-word clip to receive title and summary within ~10 seconds when Groq is configured, so that the A2 exit criterion is met.

### Actions & smart paste (A3)

24. As a user, I want to summarize a clip from detail view, so that I can paste a shorter version elsewhere.
25. As a user, I want to make a clip shorter or more professional in tone, so that I can reuse content quickly.
26. As a user, I want to explain a clip (especially code/errors), so that I understand what I copied.
27. As a user, I want to format JSON clips into valid pretty JSON, so that I can paste into editors cleanly.
28. As a user, I want bullet points extracted from prose, so that I can paste structured notes.
29. As a user, I want links extracted from a clip, so that I can paste a URL list.
30. As a user, I want a preview sheet before pasting an action result, so that I don't accidentally paste wrong output.
31. As a user, I want smart paste variants (summary, bullets, plain, Markdown/JSON), so that I choose the output shape.
32. As a user, I want AI actions only in detail view (not palette), so that transforms are deliberate not accidental.
33. As a user, I want AI actions disabled on sensitive clips, so that secrets are never sent to cloud LLM.
34. As a user, I want clear UI when no LLM is available, so that I'm not stuck on a spinning action.
35. As a user, I want actions to use the same Groq → Ollama fallback as metadata, so that configuration is consistent.

### Vision & images (A4)

36. As a user, I want text in screenshots extracted automatically on copy, so that I don't manually transcribe errors.
37. As a user, I want OCR text searchable via FTS, so that keyword search finds words in images.
38. As a user, I want OCR text embedded for semantic search, so that natural-language queries find screenshot content.
39. As a user, I want extracted text shown under the thumbnail in detail view, so that I can read it without re-opening the image.
40. As a user, I want to disable OCR in Settings, so that I control CPU use and privacy on image-heavy workflows.
41. As a user, I want existing images backfilled with OCR when the feature ships, so that my history becomes searchable.
42. As a developer, I want a screenshot containing “TypeError: undefined is not a function” to appear when I search that phrase, so that the A4 exit criterion is met.

### Settings & configuration

43. As a user, I want one Ollama URL field shared where relevant, so that Settings isn't duplicated confusingly.
44. As a user, I want separate toggles for semantic search, AI metadata, and OCR, so that I enable only what I need.
45. As a user, I want the Groq model configurable (default `llama-3.3-70b-versatile`), so that I can change models later.

### Cross-cutting

46. As a user, I want all AI indexing on background utility queues, so that capture and UI stay responsive.
47. As a user, I want failures in embedding or LLM indexing logged without crashing, so that one bad clip doesn't break the app.
48. As a release owner, I want Phase A complete only when A1–A4 exit criteria pass, so that v1 is a coherent AI MVP.

## Implementation Decisions

### AI provider stack (locked)

| Concern | Primary | Fallback | Offline |
|---------|---------|----------|---------|
| Embeddings | Apple `NLContextualEmbedding` | Ollama `api/embeddings` | FTS5 always |
| Generative LLM | Groq chat completions | Ollama `api/generate` | Rules-only (metadata); actions unavailable |
| OCR | Apple `VNRecognizeTextRequest` | — | — |

- Groq default model: `llama-3.3-70b-versatile`
- Groq API key: **Keychain only** (never UserDefaults)
- Sensitive clips (`isSensitive`): never call cloud or Ollama LLM; rules-only metadata; A3 actions hidden/disabled

### LLMProvider abstraction (new — unblocks A2 finish + A3)

Introduce a single protocol consumed by `AIMetadataService` and `AIActionService`:

```
protocol LLMProvider: Sendable {
  func complete(prompt: String) async throws -> String
}

struct LLMProviderChain: LLMProvider
  // order: Groq (if key present) → Ollama (if reachable / enabled) → throw unavailable
```

- `GroqChatProvider`: POST to Groq OpenAI-compatible chat/completions endpoint; API key from Keychain
- `OllamaChatProvider`: existing generate endpoint; retained as fallback
- `AIMetadataService.generateWithLLM` delegates to `LLMProvider` instead of hard-coded Ollama
- JSON response parsing for metadata stays in `AIMetadataService` (prompt asks for `{title, summary, tags}`)

### A2 — remaining work

- Wire `LLMProviderChain` into `MetadataIndexer` / `AIMetadataService`
- Settings: Groq API key field (save/read Keychain), provider status indicator (configured / missing key)
- Remove assumption that Ollama must run for long-clip metadata
- Extend `AIMetadataSettings` with `groqModel`, `llmBackend` preference if needed (default Groq-first chain)

### A3 — AIActionService (new)

- Enum `AIAction`: summarize, shorter, explain, formatJSON, bulletPoints, extractLinks
- `AIActionService.run(action:content:provider:)` → `String` result
- Each action has a dedicated prompt template; Format JSON validates parseable JSON in tests
- UI: `ClipDetailView` action section + modal/sheet `ActionPreviewView` with Copy / Paste / Cancel
- `AppModel` orchestrates: check sensitive → check provider available → run → show preview
- Post-v1 (out of this PRD): professional, extractTasks, translate, email/tweet presets

### A4 — VisionOCRService (new)

- `VisionOCRService.recognize(imageAt:)` or `recognize(cgImage:)` → `String?`
- Migration `v6_ocr`: add `ocr_text TEXT` to `clipboard_assets`
- FTS: extend virtual table + triggers to include `ocr_text` (or join path for image search — prefer indexing OCR into searchable surface used by `ClipboardRepository.search`)
- On image insert: run OCR if enabled → persist `ocr_text` → enqueue embedding on OCR text (reuse `EmbeddingIndexer` with synthetic text source)
- Settings: `ocrEnabled` toggle (default on)
- Optional one-time backfill job for existing image assets (utility queue, cancellable)

### Schema (remaining)

```sql
-- clipboard_assets (migration v6)
ocr_text TEXT
```

A2 schema (`summary`, `tags`, `clipboard_tags`, `clipboard_embeddings`) already migrated.

### Modules touched

| Module | A1 | A2 finish | A3 | A4 |
|--------|----|-----------|----|-----|
| Intelligence/ | ✅ | LLMProvider, GroqChatProvider, AIMetadataService | AIActionService, VisionOCRService | VisionOCRService |
| Storage/ | ✅ | Keychain helper, AIMetadataSettings | — | ClipboardAsset, DatabaseManager, ClipboardRepository |
| UI/ | ✅ | SettingsView | ClipDetailView, ActionPreviewView | ClipDetailView, SettingsView |
| AppModel | ✅ | settings wiring | action orchestration | OCR on capture, backfill |

### Indexer pattern (existing — reuse)

- `EmbeddingIndexer`: utility queue, `enqueue(item:)`, skip tiny text — **do not duplicate queue logic** for OCR; call `enqueue` with item whose searchable text includes OCR
- `MetadataIndexer`: same pattern; call after insert for text/code; for images optionally after OCR if text length qualifies

### Search behavior (unchanged contracts)

- Natural-language hybrid: 4+ words, no `type:`/`from:`/`tag:` prefix
- `tag:` filter via `clipboard_tags` join (implemented)
- Similar clips: cosine &gt; 0.1, exclude self, preserve rank order

## Testing Decisions

### Philosophy

Test **observable behavior at repository and service boundaries**, not indexer queue timing or URLSession internals. Use fakes for network and Keychain.

### Primary test seam (one)

**`ClipboardRepository`** — already the integration point for search, tags, metadata persistence, embeddings, and (after A4) OCR-backed search. Extend existing test suites rather than adding parallel seams.

**Secondary seam for generative behavior:** `LLMProvider` fake returning fixed JSON strings — wired into `AIMetadataService` and `AIActionService` tests without HTTP.

Do **not** unit-test `MetadataIndexer`/`EmbeddingIndexer` loop mechanics; test that given a persisted item + fake provider, `applyAIMetadata` / search results are correct.

### What to test

| Area | Behavior | Prior art |
|------|----------|-----------|
| A1 | Hybrid merge, semantic qualification, embedding round-trip | `SemanticSearchTests`, `EmbeddingRepositoryTests` |
| A2 | Rules metadata, tag search, similar clips threshold, sensitive skips LLM | `AIMetadataTests`, `TagSearchTests`, `SimilarClipsTests` |
| A2 new | `LLMProviderChain` order: Groq when key present, else Ollama, else throw; metadata parse | New tests with fake providers |
| A2 new | Keychain store/retrieve round-trip (or injectable `SecretsStore` protocol) | New small test target or mock |
| A3 | Each action returns expected shape; Format JSON produces valid JSON; sensitive blocks action | New `AIActionServiceTests` |
| A4 | OCR text persisted → FTS search finds term; embedding enqueued for OCR text | New `VisionOCRTests` using fixture image or injected OCR result |
| A4 | OCR disabled → no `ocr_text` written | Repository test |

### Manual exit tests (not automated)

- A2: 500-word clip → title + summary via Groq in ~10s
- A3: malformed JSON clip → Format JSON → valid paste from preview sheet
- A4: screenshot with visible error → searchable by error string

## Out of Scope

- Phase B (discovery, privacy UI, polish, distribution, growth)
- Cloud embeddings
- Auto-running AI actions on every capture
- Palette action menu (detail only for v1)
- A3 actions: Professional, Extract tasks, Translate, email/tweet presets
- `sqlite-vec` extension
- Core ML custom embedding bundles (Apple NL sufficient)
- iCloud sync, Mac App Store sandbox
- AI topic memory / auto-cleanup

## Further Notes

### Current codebase state

- **A1 complete** — 56 unit tests passing; Apple default embeddings; hybrid search live
- **A2 ~95%** — schema, UI, rules path, similar clips, tag search done; **Ollama-only LLM path** must be replaced with `LLMProvider` + Groq + Keychain
- **A3/A4** — not started

### Suggested implementation order

See **[issues/](../issues/)** for grabbable vertical slices:

1. [001 — Groq LLM provider + metadata](../issues/001-groq-llm-provider-metadata.md)
2. [002 — Detail-view AI actions](../issues/002-detail-view-ai-actions.md) (blocked by 001)
3. [003 — Screenshot OCR](../issues/003-screenshot-ocr-searchable.md) (parallel OK)

### Seams check

The agent should test at **`ClipboardRepository` + fake `LLMProvider`** — not at individual network providers or indexer queues. Confirm this matches intent before large refactors; if A4 OCR is injected as a protocol (`OCRProvider`) for testability, keep it behind `VisionOCRService` only.

### Roadmap alignment

This PRD supersedes the “local Ollama only” wording in the original plan. Cloud LLM (Groq) is in scope for generation; cloud embeddings remain out of scope.
