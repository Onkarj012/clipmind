# ClipMind on macOS + Android, with sync

**Status:** proposal · **Date:** 2026-10-07

Turn the macOS-only ClipMind into a two-platform product with end-to-end encrypted sync, plus the release tooling a real project needs.

## TL;DR

- **Keep the native macOS app** (Swift, SwiftUI, GRDB). **Build a native Android app** (Kotlin, Jetpack Compose, Room). The two apps share a **written protocol and golden test fixtures**, not code.
- **Sync goes through a small end-to-end encrypted relay**: Cloudflare Workers, one Durable Object per account, and R2 for images. The server stores ciphertext and can't read clips.
- **No accounts or passwords.** The first device creates a sync key. Other devices join by scanning a QR code. A recovery key covers losing every device.
- **Each clip is a state-based CRDT record**: per-field last-writer-wins with hybrid logical clocks. Merges don't depend on order, so offline edits on both devices converge without conflict logic on the server.
- **Android can't read the clipboard in the background** (Android 10+). Mac → phone is automatic. Phone → Mac takes one tap: the share sheet, the text-selection menu, a Quick Settings tile, or opening the app. A ClipMind keyboard could make it automatic later.
- **The Mac stays the "AI device".** It fills in titles, summaries, tags and OCR for clips from any device and syncs the results back. Android does no LLM or embedding work in v1.
- **Mac ↔ Mac sync ships and gets tested before Android sync starts**, so the protocol is proven on the platform that already works.

---

## 1. Where the project is today

These are the facts from the current code that the plan depends on.

| Area | Today | What it means for sync |
|---|---|---|
| App | macOS 15 menu-bar app, SwiftUI, ~5.9k lines in `ClipMind/`, not sandboxed, unsigned DMG | Keep it, move it to `apple/`, add Developer ID signing |
| Storage | GRDB/SQLite, migrations `v1`–`v6` in `Storage/DatabaseManager.swift`, FTS5 over items | Add migration `v7_sync`; search indexes stay local |
| Identity | `clipboard_items.id` is a random UUID; `content_hash` is SHA-256 and `UNIQUE` | Two devices copying the same text offline would create two IDs, so sync needs deterministic IDs |
| Mutations | In place: `copyCount += 1`, `lastUsedAt`, `isFavorite.toggle()`, `isDeleted` (trash) | Needs a clock per field to merge |
| Deletes | Hard deletes in `clearHistory`, `emptyTrash`, `hardDeleteItems` and the retention purge | Explicit deletes need tombstones; retention needs its own rule (§5.9) |
| Images | Absolute paths in `clipboard_assets.file_path`; PNG/TIFF originals plus a JPEG thumbnail | Paths are device-local; sync blob references, not paths |
| Files | `type = "file"` stores a Mac path | Meaningless on Android; sync as a reference only in v1 |
| Tags | `tags.id` is a random UUID, `name` is `UNIQUE` | Identify tags by normalized name across devices |
| Derived data | Embeddings (Apple `NLContextualEmbedding` or Ollama), AI metadata (Groq → Ollama), Vision OCR | Embeddings stay local to each device; metadata and OCR text sync |
| Privacy | `SensitiveDetector` (substring/regex checks), `CaptureDenylist` by bundle ID. The extractors don't check `org.nspasteboard.ConcealedType` / `TransientType` | Must be hardened before any byte leaves the device |
| Secrets | Groq key in the Keychain | The sync key goes in the Keychain too |
| CI | `macos-15` runner, `xcodebuild test`, manual release workflow producing an unsigned DMG | Split into per-platform workflows with path filters |

## 2. Goals and non-goals

**Goals for v1:**

1. A Mac copy is available on the phone within seconds, including on the phone's clipboard where Android allows it.
2. A capture on Android appears in the Mac history and command palette within seconds.
3. Favorites, trash, deletes, tags and AI metadata converge across devices, including after offline edits.
4. End-to-end encryption: the relay never sees clip content, titles, tags or images.
5. Each app is fully useful offline and without sync turned on.
6. A real release pipeline for both platforms.

**Non-goals for v1:** iOS, Windows/Linux, a web client, syncing file *contents*, syncing embeddings, shared or team histories, an Android keyboard (IME), and packaging the relay for self-hosting.

---

## 3. Decisions

Each decision has a recommendation and the main alternatives considered. The ones marked ⚑ are expensive to reverse, so confirm them before Phase 0 ends.

### D1 ⚑ A native app per platform; share contracts, not code

- **Mac:** keep Swift/SwiftUI. The app depends on polling `NSPasteboard`, pasting via `CGEvent` with accessibility trust, global shortcuts, a floating panel, Vision OCR and NaturalLanguage embeddings. None of that ports, and it already works.
- **Android:** Kotlin, Jetpack Compose and Room. Clipboard capture on Android lives in platform corners: share targets, `ACTION_PROCESS_TEXT`, Quick Settings tiles, FCM and WorkManager. Cross-platform toolkits wrap these poorly.
- **Shared:**
  - `spec/` holds the protocol, crypto, record schema and LLM prompt templates.
  - `fixtures/` holds JSON golden cases that the Swift and Kotlin test suites both run.
  - Together they keep the two implementations in agreement.
- **Rejected:**
  - *Flutter or React Native.* It would mean rewriting the working Mac app or maintaining two Mac UIs.
  - *A Kotlin Multiplatform shared core.* Worth it once a third client exists, such as iOS. For one Mac app with a mature GRDB layer, the Swift ↔ KMP interop and build cost outweighs the roughly 1.5k lines of sync logic it would share.
  - *A Rust core via UniFFI.* Same reasoning, with more toolchain.

### D2 ⚑ Sync backend: an E2EE relay on Cloudflare

- **Stack:** Cloudflare Workers (TypeScript), **one Durable Object per account** (SQLite-backed storage, WebSocket hibernation), and **R2** for encrypted image blobs.
- **Why it fits:** a Durable Object is a single-threaded actor per account, which is exactly the shape this needs:
  - an ordered change log;
  - compare-and-swap per record;
  - fan-out of "something changed" pokes to connected devices.

  There's no database cluster to run, and cost is near zero at personal scale.
- **FCM** (Firebase Cloud Messaging) is needed either way to wake Android. Its messages carry no content, only a "poke".
- **Rejected:**
  - *Firebase Firestore.* Good Android story, but with E2EE we'd store opaque blobs anyway and get none of its query or conflict features. Plus lock-in.
  - *Supabase.* A good fallback if you prefer Postgres. Same protocol, with compare-and-swap in a Postgres function.
  - *CloudKit.* No Android.
  - *LAN-only peer-to-peer, like KDE Connect or LocalSend.* No sync away from home. Worth adding later as a second transport.

### D3 ⚑ Identity: device pairing, no accounts

- **First device:** generates a 256-bit **account key `K`** and registers an account. The server returns an `account_id` and a device token.
- **More devices:** join by **scanning a QR code** shown on an already-paired device (flow in §5.8). The server relays the encrypted key exchange and never holds `K`.
- **Recovery key:** `K` encoded as 24 words or a printable QR code. It restores the account if every device is lost. Without it, data on the relay is unrecoverable. That trade-off is inherent to E2EE, and onboarding has to say so plainly.
- **Rejected:** email/password or Sign in with Google/Apple. It adds an auth system and still needs a separate encryption secret for E2EE. It can be layered on later if billing ever needs it.

### D4 Data model: deterministic IDs and a per-field LWW CRDT

- **Sync ID:**

  ```
  sync_id = base32(HMAC-SHA256(K_id, kind ‖ ":" ‖ content_hash))[0..26]
  kind ∈ {text, image, file}
  ```

  - **Same content, same ID.** The same content copied on two devices gets the **same ID**, so cross-device dedupe works the same way local dedupe already does.
  - **Coarse `kind` on purpose.** The ID uses `kind`, not the classifier's `type` (`text`/`url`/`code`). The Swift and Kotlin classifiers will drift, and a drift must never create duplicates.
  - **Keyed hash.** Keying with `K_id` stops the server from checking guesses against a plain SHA-256 ("is this user's clipboard `hunter2`?").
- **Field clocks.** Every mutable field carries a **hybrid logical clock (HLC)**. Merge is per field: the highest `(precedence, hlc, device_id)` wins. The merge is commutative, associative and idempotent, so delivery order and duplicate deliveries don't matter.
- **Local IDs don't change.** The local `id` stays a UUID, so existing rows keep their primary keys and asset file names. `sync_id` is a new unique column, filled in when sync is turned on.

### D5 The Android capture model

Since Android 10, only the focused app or the default keyboard can read the clipboard. Android 12+ shows a toast on each read, and Android 13+ clears the clipboard automatically after a while. So:

- **Phone → Mac (one tap):**
  - the share sheet target;
  - `ACTION_PROCESS_TEXT`, which puts "ClipMind" in the text-selection menu and needs no clipboard access at all;
  - a Quick Settings tile and an optional notification action, each opening a transparent activity that reads the clipboard once it has focus (the pattern KDE Connect uses);
  - a clipboard check when the app resumes.
- **Mac → phone (automatic):**
  - an opt-in background *write* of the newest Mac clip to the phone's clipboard;
  - a "Copied from MacBook" notification with a Copy action as the fallback.

  Background writes are expected to work, but Phase 0 verifies this on Pixel and Samsung hardware before anything is built on it.
- **Later:** a ClipMind keyboard (IME) is the only sanctioned way to get automatic phone-side capture. It's a large effort, so it's in Phase 7.
- **Rejected:** clipboard snooping through an Accessibility service, and `READ_LOGS` workarounds. Both are fragile and risk removal from the Play Store.

---

## 4. Architecture

```
 macOS app (Swift)                               Android app (Kotlin)
 ─────────────────                               ────────────────────
 ClipboardWatcher                                share · process-text · QS tile · in-app
   → ClipboardRepository (GRDB, FTS5)              → ClipRepository (Room, FTS4)
   → indexers: OCR, embeddings, AI metadata        → rules-only metadata
 SyncStore: clocks · outbox · tombstones         SyncStore: clocks · outbox · tombstones
 SyncEngine → RecordCodec → SyncCrypto           SyncEngine → RecordCodec → SyncCrypto
                            (CryptoKit)                                     (Tink)
        │ HTTPS + WebSocket                              │ HTTPS + WebSocket (foreground)
        │                                                │   ▲ FCM poke (background)
        ▼                                                ▼   │
 Relay (Cloudflare) ───────────────────────────────────────────────────────────
   Worker: device-token auth → one Durable Object per account
     SQLite: records(record_id, seq, header, envelope) · devices · pairings
     WebSocket hub (hibernating) · FCM sender · retention GC (alarm)
   R2: acct/<account_id>/blobs/<blob_id>      (ciphertext only)
```

---

## 5. Sync design

### 5.1 What syncs

| Data | Syncs? | Notes |
|---|---|---|
| Text, URL and code clips | Yes | Full content, encrypted |
| Image clips | Yes | Encrypted thumbnail inside the record. The original goes to R2 as an encrypted blob, up to 10 MB, with TIFF converted to PNG before upload. Android downloads originals on demand |
| File clips | Reference only | Name, size and origin device; a Mac path is useless on Android. Shown as "on MacBook". File transfer is Phase 7 |
| Sensitive clips (`isSensitive`, nspasteboard concealed types, Android `EXTRA_IS_SENSITIVE`) | **Never** | They stay on the device that captured them. There's no setting for this in v1 |
| Favorite, trash, permanent delete | Yes | Per-field LWW; a permanent delete is a tombstone |
| Title, summary, tags, OCR text | Yes | Derived fields filled in by whichever device can (§5.3) |
| `last_used_at` | Yes | The maximum wins |
| `copy_count` | No | A per-device statistic |
| Embeddings | No | Each platform uses a different model, so each device embeds its own copy |
| Settings | A few | Account-wide: retention, "sync images", "auto-copy to phone". Everything else stays per device. Syncing the Groq key is an optional Phase 7 item |

### 5.2 Record format

The **header** is plaintext the server can see, and is deliberately minimal:

```json
{ "record_id": "<sync_id>", "schema": 1, "key_epoch": 1,
  "favorite": false, "purged": false, "last_activity_ms": 1791400000000,
  "blob_ids": ["b_…"] }
```

`favorite`, `purged` and `last_activity_ms` are exposed so the server can enforce retention and garbage-collect blobs without decrypting anything (§5.9). This is a documented metadata leak: the server learns how many clips you have, when they were active and which are favorites. It never learns what they contain.

The **payload** is encrypted JSON (schema 1):

```jsonc
{
  "kind": "text",                       // text | image | file; immutable
  "content": "…",                       // text clips; immutable
  "created_at_ms": 1791399000000,
  "origin": { "device_id": "d_…", "platform": "macos", "app": "Xcode", "bundle_id": "com.apple.dt.Xcode" },
  "type":     { "v": "code",                 "t": "<hlc>", "src": "rules" },
  "favorite": { "v": true,                   "t": "<hlc>" },
  "trashed":  { "v": false,                  "t": "<hlc>" },
  "purged":   { "v": false,                  "t": "<hlc>" },
  "title":    { "v": "TypeError in …",       "t": "<hlc>", "src": "llm" },
  "summary":  { "v": "…",                    "t": "<hlc>", "src": "llm" },
  "tags":     { "v": ["javascript", "error"], "t": "<hlc>", "src": "llm" },
  "ocr_text": { "v": null,                   "t": "<hlc>", "src": "vision" },
  "last_used_at_ms": 1791400000000,
  "image": { "blob_id": "b_…", "blob_key": "<b64>", "mime": "image/png",
             "w": 1920, "h": 1080, "bytes": 482113, "thumb_jpeg": "<b64, ≤ 32 KB>" },
  "file":  { "name": "report.pdf", "bytes": 182733 }
}
```

- **Tombstones carry no user data.** When `purged` is true, the payload drops `content`, `image`, `file`, `title`, `summary`, `tags` and `ocr_text`.
- **Unknown fields survive.** Clients keep fields they don't recognize and write them back unchanged, so an older client can't erase a newer client's data.

### 5.3 Merge rules

| Field | Rule |
|---|---|
| `kind`, `content`, `created_at_ms`, `origin`, `image` | Immutable. The first write wins and later values are ignored |
| `favorite`, `trashed` | LWW by `(hlc, device_id)` |
| `purged` | LWW. Copying purged content again on any device writes `purged = false` with a newer HLC and re-supplies the content, so the clip comes back |
| `title`, `summary`, `tags`, `type`, `ocr_text` | Precedence first (`user` > `llm`/`vision` > `rules`), then LWW. A rules-based value never overwrites an LLM value, and a user edit always wins |
| `last_used_at_ms` | `max()` |

**HLC:**

- **Format:** 48 bits of wall-clock milliseconds plus a 16-bit counter, with `device_id` as the tie-break.
- **Encoding:** a fixed-width string, so values sort lexicographically.
- **On receive:** the local clock advances past the remote one. This keeps ordering correct even when a device's wall clock is off by a few minutes.

**Derived fields are filled by whichever device can:**

- The capturing device writes rules-based values immediately.
- Any device with an LLM or Vision available upgrades them later; in practice that's the Mac.
- When the Mac pulls an Android clip whose `title.src` is `rules`, the existing `MetadataIndexer` runs and pushes the LLM result. So Android gets AI titles and tags without needing an LLM key.

### 5.4 Protocol v1

**Auth:** every request uses `Authorization: Bearer <device_token>`. The token has the form `<account_id>.<random 256 bits>`, so the Worker routes it to the account's Durable Object without a global lookup table. The Durable Object stores only `sha256(token)`.

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/v1/accounts` | Create an account. Returns `account_id` and the first device token. Rate-limited per IP |
| `GET` | `/v1/changes?since=<seq>&limit=500` | Records with `seq > since`, in order: `{ changes: [{ header, envelope, seq }], cursor, more }` |
| `POST` | `/v1/changes` | Batch upsert of `[{ header, envelope, if_seq }]`. Compare-and-swap: returns `409` with the current record when the stored seq ≠ `if_seq`. The client merges and retries |
| `GET` | `/v1/ws` | WebSocket. The server sends `{"type":"poke","seq":N}` after each accepted write |
| `PUT` / `GET` | `/v1/blobs/:blob_id` | Upload or download an encrypted blob, streamed through the Worker to R2 (10 MB cap) |
| `POST` | `/v1/pairings`, `/v1/pairings/:id/join`, `/v1/pairings/:id/complete` | Pairing (§5.8) |
| `GET` / `DELETE` | `/v1/devices`, `/v1/devices/:id` | List devices, or revoke one (also used for "sign out this device") |
| `PUT` | `/v1/devices/me/push` | Register an FCM token (Android) |
| `PUT` | `/v1/settings/retention` | Set the account retention policy, in plaintext, so the server can enforce it |
| `DELETE` | `/v1/account` | Delete every record, blob and device. Irreversible |

**Client loop** (identical on both platforms):

1. **Push.** For each dirty record in the outbox:
   - serialize the current local state, encrypt it, and `POST` it with `if_seq` set to the last known seq;
   - on `409`, decrypt the server's copy, merge, write the result locally, and retry.
2. **Pull.** `GET /changes?since=cursor`, then decrypt and merge each page into the local DB in one transaction, and advance the cursor. If the merged result differs from what the server sent (the local copy had newer fields), mark the record dirty.
3. **Triggers:** a local change (debounced 300 ms), a WebSocket poke, an FCM poke, app launch, network regained, Mac wake from sleep, and a 15-minute fallback timer.

### 5.5 Realtime and wake-ups

- **Mac.** The menu-bar app is always running, so it keeps one `URLSessionWebSocketTask` open. It uses exponential backoff, watches the network with `NWPathMonitor`, and reconnects on `NSWorkspace.didWakeNotification`.
- **Android in the foreground.** An OkHttp WebSocket stays open while any activity is visible.
- **Android in the background:**
  - The Durable Object sends a **high-priority FCM data message** with `{poke, seq}` to devices that have no live socket.
  - The handler runs an expedited WorkManager job that pulls the new data, then auto-copies the clip, posts "Copied from MacBook", or both.
  - High-priority FCM messages are meant to lead to something the user sees, and this one does.
- **Latency target** for a Mac copy reaching the phone: p50 under 2 s, p95 under 5 s. The Phase 5 exit test measures it.

### 5.6 Blobs

- **Encryption:** each image gets a random 256-bit key. The client encrypts the image, uploads it, and stores `blob_id` and `blob_key` inside the encrypted record.
- **Upload order:** the blob first, then the record, so a record never points at a missing blob.
- **Garbage collection:** when a record is purged or removed by retention, the Durable Object deletes its blobs from R2. A nightly alarm sweeps orphaned blobs older than 24 hours.
- **Settings:** "Sync images" (default on, up to 10 MB each) and "Download originals on cellular" (default off).

### 5.7 Cryptography

Write a spec and test vectors (`fixtures/crypto.json`) before writing any code. Both clients must pass the vectors in CI.

- **Keys:**
  - `K` is 32 random bytes.
  - Subkeys come from HKDF-SHA256 with distinct info strings:
    - `K_rec = HKDF(K, "clipmind/v1/record")`
    - `K_id = HKDF(K, "clipmind/v1/sync-id")`
- **Record envelope:** `ChaCha20-Poly1305(K_rec, nonce = 12 random bytes, AAD = account_id ‖ record_id ‖ schema ‖ key_epoch)`.
  - The AAD stops the server from swapping or replaying an envelope under a different record.
  - Random 96-bit nonces allow about 2³² messages per key, orders of magnitude above clipboard volume.
- **Blobs:** ChaCha20-Poly1305 with a per-blob key, in 64 KB frames so large images can stream.
- **Pairing:** an ephemeral X25519 key agreement, then HKDF, then ChaCha20-Poly1305.
- **Libraries:**
  - **Mac:** CryptoKit (`ChaChaPoly`, `Curve25519`, `HKDF`, `HMAC`), so no new dependency.
  - **Android:** Google Tink. X25519 support in the platform JCA varies by Android version; Tink gives one code path for API 29+.
- **Storing `K`:**
  - **Mac:** in the Keychain with `kSecAttrAccessibleAfterFirstUnlock`, the same pattern as the existing Groq key.
  - **Android:** wrapped by a non-exportable Android Keystore AES key, with the ciphertext in DataStore. Don't use `EncryptedSharedPreferences`; Jetpack Security Crypto is deprecated.
- **Key rotation:** the `key_epoch` field exists in v1, but only epoch 1 is used. Real rotation (a new epoch when a device is revoked, re-wrapped for the remaining devices) is Phase 7.

### 5.8 Pairing and devices

1. **Start.** An already-paired device (say, the Mac) calls `POST /v1/pairings` and gets a `pairing_id` that's valid for 5 minutes. It generates an ephemeral X25519 key `E_a` and a random secret `s`, then shows a QR code:

   ```
   clipmind://pair?acct=…&p=<pairing_id>&k=<E_a.pub>&s=<s>
   ```

2. **Join.** The new device scans the code, generates `E_b`, and calls `join` with:
   - `E_b.pub`;
   - its name and platform;
   - `proof = HMAC(s, E_b.pub)`.
3. **Approve.** The Mac receives the join over its WebSocket and checks `proof`.
   - It shows **"Add 'Pixel 9'?"** with a 6-digit code derived from both public keys; the phone shows the same code.
   - On approval it calls `complete` with `ChaChaPoly(HKDF(X25519(E_a, E_b.pub)), K ‖ account_id)`.
   - The server then mints the new device's token.
4. **Finish.** The new device decrypts `K`, stores it, and starts a full pull.

Pairing Mac ↔ Mac (no camera) uses the same flow, with the QR contents copied and pasted as a code.

Settings on both platforms lists devices with name, platform, last seen, and a revoke button. Revoking cuts off server access immediately. A revoked device that kept `K` can still decrypt ciphertext it already downloaded; key rotation in Phase 7 closes that gap for new data.

### 5.9 Deletes, trash and retention

- **Trash and restore.** The `trashed` field syncs, so the Trash view is the same everywhere.
- **Permanent delete** (Empty Trash, Clear History, deleting from Trash):
  - writes `purged = true` tombstones and deletes the content locally;
  - the server deletes the matching blobs;
  - tombstones are kept for 90 days, then compacted. A device that was offline longer than that does a full re-sync (§5.10).
- **Retention** (500 items / 30 days today) becomes an **account setting**:
  - Each device applies it locally *without* writing tombstones.
  - The server applies the same rule using the plaintext header (`favorite`, `last_activity_ms`).
  - Retention therefore never creates sync traffic, and the server doesn't hold history the user asked to forget.
  - If another device later changes a clip that retention removed locally, the clip comes back. That's intended.
  - "Keep forever" turns off server-side expiry, within a quota (default: 20k records and 2 GB of blobs per account).

### 5.10 Edge cases

- **Echo loops.** When ClipMind writes the system clipboard itself (paste on the Mac, auto-copy on Android), it adds a private marker (an `io.clipmind.origin` pasteboard type on the Mac, a `ClipDescription` extra on Android), and the watcher skips it. The deterministic `sync_id` would merge the clip anyway; the marker just avoids a spurious `last_used_at` bump.
- **Turning on sync with existing history.** Compute `sync_id` for every local item, push everything (oldest first, images last), then pull. Two devices that already hold the same clips end up with one record per clip.
- **Cursor too old.** If `since` is older than tombstone compaction, the server returns `410`. The client then does a full re-sync: pull everything, then reconcile local items missing from the server using the rules above.
- **Schema changes.** The header carries `schema`:
  - Clients skip records with a higher major version than they understand.
  - For the same major version, clients keep unknown fields.
  - The server can refuse writes from clients below a minimum version with `426 Upgrade Required`, which doubles as a kill switch for a buggy release.
- **Hash normalization.** Text must be trimmed identically on both platforms before hashing:
  - Swift's `.whitespacesAndNewlines` and the JVM's whitespace rules don't define the same set; for example, U+001C–U+001F count as whitespace on the JVM but not in Swift.
  - The spec defines the exact set, and `fixtures/normalize_hash.json` pins it, so a mismatch fails CI instead of creating duplicates.

---

## 6. macOS work

1. **Move the repo.** `git mv` the app into `apple/` in a commit with no other changes, so history follows the files. Update `project.yml` paths, CI, `release.yml`, `bump_version.py` and `scripts/`.
2. **Harden capture first.** This is useful even without sync.
   - Skip pasteboard contents marked `org.nspasteboard.ConcealedType`, `TransientType` or `AutoGeneratedType`. Password managers set these, and the current extractors don't check for them.
   - Move the `SensitiveDetector` cases into `fixtures/sensitive.json` and tighten the rules. Today `text.contains("sk-")` also flags ordinary text like "risk-free". False positives matter more once "sensitive" means "never syncs".
3. **Add migration `v7_sync`:**
   - On `clipboard_items`, add `sync_id TEXT UNIQUE`, `origin_device_id` and `origin_platform`.
   - Add these tables:
     - `field_clocks(item_id, field, hlc, src)`
     - `sync_outbox(item_id PRIMARY KEY, dirty_at)`
     - `sync_records(item_id, server_seq)`
     - `tombstones(sync_id PRIMARY KEY, hlc)`
     - `sync_state(key, value)`, which holds the cursor, device ID and account ID
4. **Track changes.** Every mutating repository method bumps its field clocks and marks the outbox **in the same transaction**:
   - `insertText`, `insertImage`, `insertFile`
   - `toggleFavorite`, `softDelete`, `restore`, `touchLastUsed`
   - `applyAIMetadata`, `applyOCRText`
   - `clearHistory`, `emptyTrash`, `hardDeleteItems`

   Add a test that lists the repository's public mutators and fails if any of them doesn't record a change. Put this logic in a new `SyncStore`; `ClipboardRepository.swift` is already 1,000 lines.
5. **Build a pure core, unit-tested against the fixtures:** `HLC`, `RecordCodec` (DB row ⇄ payload), `RecordMerger` and `SyncCrypto`.
6. **Add a `SyncEngine` actor** that owns:
   - the push/pull loop;
   - a `SyncTransport` protocol, with a fake for tests;
   - the WebSocket;
   - blob upload and download;
   - backoff;
   - a status publisher for the UI.
7. **Handle remote clips.** Merging a remote clip enqueues the local indexers:
   - embeddings always;
   - OCR when `ocr_text` is empty;
   - AI metadata when `src` is `rules`.

   A new option, "Copy clips from my phone to the Mac clipboard", defaults to off.
8. **UI:**
   - A **Devices** tab in Settings: turn on sync, show the pairing QR code (`CIQRCodeGenerator`), list and revoke devices, export the recovery key.
   - A sync status indicator in the menu bar.
   - An origin-device badge on clip rows.
   - A `device:` search qualifier alongside `from:`.
9. **Distribution:** Developer ID signing, notarization and stapling in `release.yml`; Sparkle for updates; `os.Logger` in place of `NSLog`.

---

## 7. Android app

**Stack:**

- **UI:** Kotlin 2.x, Jetpack Compose, Material 3.
- **SDK levels:** minSdk 29, targeting the current SDK.
- **Libraries:**
  - Hilt for dependency injection;
  - Room with FTS4 (the FTS version Room supports) and DataStore for storage;
  - WorkManager for background work;
  - OkHttp for HTTP and WebSocket;
  - kotlinx.serialization;
  - Tink for crypto;
  - CameraX with ML Kit barcode scanning for the pairing QR code;
  - Firebase Messaging.

**Modules:**

```
android/
  app/           Compose UI, navigation, Hilt wiring
  core/model/    ClipRecord, Kind, Tag … (pure Kotlin)
  core/rules/    classifier, sensitive detector, search-query parser, rules-based metadata
                 (pure Kotlin; JVM tests run fixtures/)
  core/data/     Room DB, DAOs, FTS, ClipRepository, SyncStore (clocks, outbox, tombstones)
  sync/          HLC, RecordCodec, RecordMerger, SyncCrypto, SyncEngine, API client
                 (pure Kotlin + OkHttp; runs on the JVM, so CI can test it against a local relay)
  capture/       share target, ProcessTextActivity, transparent ClipboardReadActivity,
                 Quick Settings TileService, notifications
```

**v1 features:**

- **History:** list, search (FTS plus `type:`, `tag:`, `is:favorite`, `device:`), detail view, favorites, trash, tags.
- **Capture:** share sheet, text-selection menu, Quick Settings tile, notification action, and a clipboard check on resume (auto-save or a "Save clipboard?" chip, configurable).
- **Output:** tap to copy, and share out.
- **Images:** thumbnails from the record, originals downloaded on demand, and capture of images shared into the app.
- **Sync:** pairing by QR scan, opt-in auto-copy from the Mac, and the "Copied from MacBook" notification.
- **Privacy:**
  - Honor `ClipDescription.EXTRA_IS_SENSITIVE` on incoming clips, and set it on clips the app writes when the source clip was sensitive.
  - Optionally set `FLAG_SECURE` on screens that show clip content.
- **AI:** shows the Mac-generated title, summary, tags and OCR text. Android itself computes only rules-based metadata in v1.

**Later:**

- On-device semantic search with a small embedding model via MediaPipe or ONNX, kept local.
- ML Kit OCR for when no Mac is online.
- Groq-backed AI actions on Android, using the shared prompt templates in `spec/prompts/`.
- The keyboard.

---

## 8. Relay server

- **Layout:** `server/` contains TypeScript built with Wrangler, a Hono router (or bare `fetch`), and one `AccountDO` class.
- **Durable Object tables:**
  - `records(record_id PRIMARY KEY, seq, header_json, envelope BLOB, updated_at)`, with an index on `seq`
  - `devices(device_id, name, platform, token_hash, push_token, last_seen, revoked_at)`
  - `pairings(id, expires_at, state, payloads)`
  - `meta(next_seq, retention_json)`
- **Background work:** the WebSocket hibernation API keeps idle sockets free. A Durable Object alarm drives retention GC, pairing expiry and the orphaned-blob sweep.
- **Limits:**
  - 256 KB per envelope;
  - 10 MB per blob;
  - 500 records per batch;
  - per-device rate limits and per-account quotas.
- **Tests:** Vitest with `@cloudflare/vitest-pool-workers`, covering:
  - compare-and-swap conflicts and cursor paging;
  - `410` re-sync;
  - the pairing state machine and revoke;
  - GC and quotas.
- **Environments:** `staging` and `production`. The Firebase service-account key for FCM is a Worker secret. Deploys run from GitHub Actions on tags.
- **Observability:** Workers analytics plus structured logs that contain no device tokens (and no clip content, which the server never has).

---

## 9. Repo layout, tooling and CI

```
clipmind/
  apple/      ClipMind/, ClipMindTests/, project.yml, ClipMind.xcodeproj   (moved)
  android/    Gradle multi-module project (§7)
  server/     Cloudflare Worker (§8)
  spec/       sync-protocol.md, crypto.md, record.schema.json, prompts/
  fixtures/   normalize_hash.json, classifier.json, sensitive.json, search_query.json,
              merge.json, hlc.json, crypto.json      ← run by the Swift and Kotlin suites
  plans/      this document
  issues/     vertical slices, existing format
  .github/workflows/
              ci-apple.yml · ci-android.yml · ci-server.yml
              release-mac.yml · release-android.yml · deploy-server.yml
```

- **Path-filtered CI:**

  | Changed path | Job |
  |---|---|
  | `apple/` | macOS job (`xcodebuild test`) |
  | `android/` | Ubuntu Gradle job (`lint test assembleDebug`) |
  | `server/` | Node job |
  | `spec/` or `fixtures/` | All three |

- **Conformance tests across clients:**
  - The Kotlin `sync` module is plain JVM code. CI starts the relay locally (`wrangler dev`) and runs two simulated Kotlin devices against it.
  - A randomized "chaos" test makes random edits, takes devices offline and restarts them, then asserts the devices converge.
  - The Swift engine runs the same scenarios against a fake transport, plus the shared `merge.json` cases.
- **Versioning:** each app keeps its own semver. `spec/` has its own protocol version, and the server accepts versions N and N−1.

---

## 10. Phases

Sizes are relative effort (S < M < L), not calendar time.

| # | Phase | Main outputs | Exit criteria | Size |
|---|---|---|---|---|
| 0 | Foundations and spikes | The monorepo move and CI split; drafts in `spec/`; the first fixtures, generated from current Swift behavior and read by the Swift tests; Mac capture hardening (§6 step 2). **Spike A:** on a Pixel and a Samsung, verify background clipboard writes, Quick Settings tile reads, `PROCESS_TEXT`, and FCM latency under Doze. **Spike B:** a Durable Object + WebSocket + R2 prototype driven by curl | The spikes answer the open Android questions; spec reviewed; all CI green | S–M |
| 1 | Mac data layer ready for sync | `v7_sync` migration, HLC, change tracking in every mutator, `RecordCodec`, `RecordMerger`, `SyncCrypto` with vectors | Merge, HLC and crypto fixtures pass; no user-visible change; existing tests pass | M |
| 2 | Relay v1 | Everything in §8, deployed to staging | Server test suite green; two JVM test devices converge through a local `wrangler dev`, including the chaos test | M |
| 3 | Mac ↔ Mac sync | `SyncEngine`, the Devices UI, pairing by code, status UI, origin badges; a debug flag to run a second instance with its own data directory | Two Mac instances converge after offline edits on both; trash, deletes, favorites, tags and AI metadata propagate; revoke works | M–L |
| 4 | Android MVP, local only | All of §7 except sync: list, search, detail, capture surfaces, the rules port passing the shared fixtures | Usable as a standalone app; every `core/rules` fixture passes | M–L |
| 5 | Android sync | Crypto (Tink) passing the vectors, the engine, QR pairing, FCM, WorkManager, images, auto-copy, notifications | **End-to-end checklist:** Mac copy → phone p95 < 5 s with the app in the background; phone share → Mac p95 < 5 s; offline edits on both sides converge; a revoked phone loses access; sensitive clips never leave the device | L |
| 6 | Ship | **Mac:** Developer ID, notarization, Sparkle, sync onboarding with a recovery-key step. **Android:** Play internal → closed testing, privacy policy, Data safety form, opt-in crash reporting. Account deletion on both | Public beta on both platforms | M |
| 7 | Later | Keyboard (IME), on-device semantic search on Android, ML Kit OCR, file transfer, key rotation on revoke, Groq key sync, LAN transport, iOS (reusing `apple/`) | — | — |

Phases 1 and 2 can run in parallel. Phase 4 can run alongside Phase 3 once the `spec/` and fixtures from Phase 1 are stable.

---

## 11. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Android tightens clipboard rules further, or some OEMs block background writes | The phone side feels manual | Several one-tap capture paths; tapping the notification as the fallback for Mac → phone; Spike A before any build-out; the keyboard as the long-term answer |
| OEM battery managers delay FCM (Samsung, Xiaomi) | Slow Mac → phone delivery | High-priority FCM that leads to a visible notification; in-app battery-optimization guidance; WebSocket while in the foreground |
| Swift and Kotlin logic drift (hashing, classifier, query parser) | Duplicate clips or inconsistent search | `sync_id` built only from the coarse `kind`; shared fixtures gate CI on both sides |
| Lost key means lost synced data | User trust | The recovery key is part of onboarding. Each device's local database is unaffected by key loss, and turning sync back on re-uploads everything |
| A sync bug corrupts or deletes history | Severe | An idempotent CRDT merge; chaos tests; an automatic local DB backup before the first sync and before every migration; the `426` kill switch for bad client releases |
| Clipboard secrets leak to the cloud | Severe | E2EE; sensitive clips never sync; nspasteboard concealed types honored; the plaintext header is limited to timestamps and flags, and that's documented |
| Scope: two native apps and a server for one developer | Delays | A deliberately thin Android v1; AI stays on the Mac; Mac ↔ Mac proves the protocol before Android sync begins |
| Relay abuse or cost | Bills, downtime | Per-IP limits on account creation, quotas, size caps |

---

## 12. Decisions to confirm

1. **Native Kotlin for Android** (D1), rather than Flutter or a KMP shared core.
2. **A Cloudflare relay with E2EE** (D2). It needs a Cloudflare account, plus a Firebase project used only for FCM.
3. **QR pairing with no accounts** (D3), accepting the recovery-key trade-off.
4. **Distribution:**
   - the Apple Developer Program ($99/year) for Developer ID and notarization;
   - a Google Play developer account ($25 once);
   - whether a build without FCM, for F-Droid, matters to you.
5. **Defaults:** images sync (up to 10 MB), files sync as references only, sensitive clips never sync, and auto-copy to the phone is opt-in.
