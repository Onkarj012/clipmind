# Screenshot OCR — searchable images

**Triage:** `ready-for-agent`  
**Milestone:** v1 · Phase A4

## Parent

[PRD: Phase A — AI Intelligence](../docs/prd/PRD-phase-a-ai.md)

## What to build

Extract text from screenshots on capture using Apple `VNRecognizeTextRequest`. Make that text findable via FTS and semantic search.

End-to-end path:

1. **Schema** — add `ocr_text` to `clipboard_assets` (new migration)
2. **VisionOCRService** — recognize text from image file on disk
3. **On image insert** — if OCR enabled in Settings (default on), run OCR → persist `ocr_text`
4. **Search** — OCR text indexed in FTS5; enqueue semantic embedding on OCR text (reuse `EmbeddingIndexer` — extend so image items with OCR text get embedded without duplicating queue infrastructure)
5. **Detail view** — show extracted text under thumbnail
6. **Settings** — `ocrEnabled` toggle (separate from semantic search / AI metadata toggles)
7. **Backfill** — one-time utility-queue pass over existing image assets when feature first runs

OCR disabled → no `ocr_text` written, no OCR CPU on new captures.

## Acceptance criteria

- [ ] Migration adds `ocr_text` to `clipboard_assets`
- [ ] `VisionOCRService` extracts text from captured images
- [ ] New screenshot: OCR runs automatically when enabled; text visible in detail view
- [ ] Keyword search finds clip by words visible in screenshot (FTS)
- [ ] Natural-language semantic search can surface screenshot via OCR embedding (4+ word query)
- [ ] Settings toggle disables OCR on new captures
- [ ] Backfill processes existing images without blocking UI
- [ ] Unit tests: persisted `ocr_text` → repository search returns image; OCR disabled → no write (inject OCR result or fixture image)
- [ ] Manual: screenshot containing “TypeError: undefined is not a function” appears in search

## Blocked by

None — can start immediately (parallel with 002 after 001 is underway)

## User stories

36, 37, 38, 39, 40, 41, 42, 44
