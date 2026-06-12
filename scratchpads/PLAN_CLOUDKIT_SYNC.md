# Plan: CloudKit Sync for User Projects / Patches / Sessions
Date: 2026-06-12
Branch: claude/piano-roll-clip-view-wozlie (create a fresh feature branch for this work)

## Context
Owner wants user-authored data (projects, patches, sessions) stored securely,
space-efficiently, Apple-ecosystem-native, and FREE to operate. CloudKit's
private database uses the END USER's iCloud quota (not the developer's), so
owner operating cost stays ~$0. This plan mirrors the EXISTING local Codable
stores into CloudKit, keeping local storage as the source of truth (offline-first).

## Current persistence inventory (what would sync)

| Data | Model type (Codable) | Today's store | Location |
|------|----------------------|---------------|----------|
| Session-grid clips | `[Clip?]` (8 slots) | `ClipStore` | App-Group JSON `Clips/clips.json` |
| Song timeline | `Arrangement` (sections) | `ArrangementStore` | App-Group JSON `Arrangement/song.json` |
| User synth patches | `[SynthPatch]` | `PatchStore` | App-Group JSON `Patches/userPatches.json` |
| Bio session summaries | `[BioSessionSummary]` | `SessionRecorder` | UserDefaults key `bioSessions.v1` |
| Crash/session state | `SessionState` | `CrashSafeStatePersistence` | App-Support JSON (local only, do NOT sync) |

All five are **value-type `Codable` structs** persisted as JSON through one tiny
helper: `Sources/Echoelmusic/Core/AppGroupStore.swift` (load/save/delete by name).

### Critical finding — SwiftData is dormant, not live
- `Sources/Echoelmusic/Core/SessionStore.swift` defines `@Model SoundscapeSession`
  and `Sources/Echoelmusic/Views/SessionHistoryView.swift` uses `@Query`, BUT
  **no `.modelContainer(...)` modifier exists anywhere** in the app (grep across
  `Sources/` returns zero hits). SessionHistoryView would crash if ever
  presented. The LIVE session path is `SessionRecorder` (UserDefaults JSON),
  surfaced in `Studio/WorksView.swift`.
- Therefore "SwiftData is already used" is FALSE in practice. Adopting
  `NSPersistentCloudKitContainer`/`ModelContainer(cloudKit:)` would mean wiring
  up a brand-new container, migrating JSON->SwiftData, and re-pointing
  SessionRecorder/Works — a large, higher-risk change touching the live path.

## 1. Recommended architecture: CKContainer private DB mirror (NOT SwiftData)

**Decision: a thin CloudKit private-database sync layer that mirrors the existing
Codable stores. Do NOT migrate to SwiftData + ModelContainer(cloudKit:).**

Justification (lower risk given current code):
- The local stores are already small, self-contained Codable value types behind
  one helper. A CloudKit mirror leaves them as the source of truth and adds sync
  as an isolated, optional layer — the app works identically with iCloud off.
- SwiftData is currently UNWIRED. Switching to `ModelContainer(cloudKit:)` would
  require: standing up a container, converting `@Model` classes to be
  CloudKit-compatible (all-optional or defaulted properties, no unique
  constraints, no `.unique`), migrating three JSON files + one UserDefaults blob
  into the store, and rewriting ClipStore/ArrangementStore/PatchStore/
  SessionRecorder to read/write through ModelContext. That is a multi-week
  refactor of the live persistence path — exactly the kind of restructure
  CLAUDE.md says to avoid.
- A CKContainer mirror is additive: if any sync step fails, fall back to local.
  Zero behavior change when iCloud is unavailable.

### Design: `CloudSyncEngine` (one new file, MainActor @Observable)
- `CKContainer(identifier: "iCloud.com.echoelmusic.app").privateCloudDatabase`.
- One record type per store, each storing the JSON blob as a `CKRecord` field
  plus a `modifiedAt` timestamp and a schema `version` Int:
  - `ClipGrid` (single record, fixed recordName `clips`)
  - `Arrangement` (single record, recordName `song`)
  - `PatchLibrary` (single record, recordName `userPatches`) — or one record per
    patch keyed by `SynthPatch.id` (preferred for finer conflict granularity)
  - `BioSession` (one record per `BioSessionSummary.id`)
- Blob field is the SAME JSON the local store already produces (reuse the exact
  `Codable` encoding) -> "space-saving" (compact) and trivially round-trips.
- Sync uses `CKModifyRecordsOperation` (push) + `CKQueryOperation` /
  `CKFetchRecordZoneChangesOperation` (pull) in a custom record zone
  (`EchoelZone`) so we get change tokens for delta sync (only changed records
  transfer — space- and bandwidth-saving). Persist the `CKServerChangeToken`
  locally (UserDefaults) for incremental pulls.
- Push triggered on local save (debounced); pull triggered on launch,
  foreground, and via `CKDatabaseSubscription` + silent push (optional, Phase 2).

### Offline-first / source of truth
- LOCAL store is always written first and read first. The app never blocks on
  CloudKit. `CloudSyncEngine` observes store changes and pushes asynchronously;
  pulls merge into the local store, which then re-persists locally.

### Conflict resolution
- Last-writer-wins by `modifiedAt`, at record granularity. Because patches/
  sessions are per-record, conflicts are rare and isolated.
- For the single-record stores (clips, arrangement) use CloudKit's
  `savePolicy = .ifServerRecordUnchanged`; on `serverRecordChanged` error,
  compare `modifiedAt` and keep the newer, then re-push the merged record.
- No CRDT/3-way merge in v1 (over-engineering for single-user iCloud). Document
  as a known limitation; revisit if multi-device editing collides often.

### Graceful degradation (MUST NOT crash or block)
- On init, check `CKContainer.accountStatus`. If not `.available`
  (`.noAccount`, `.restricted`, `.couldNotDetermine`, `.temporarilyUnavailable`),
  set `syncState = .unavailable(reason)` and DO NOTHING further. App runs fully
  on local stores.
- Wrap every CloudKit call; on error, log via `os_log` and degrade to local-only.
  Never `try!`, never force-unwrap a `CKRecord` field.
- Observe `.CKAccountChanged` to re-enable sync when the user signs in later.
- Feature-flag the whole engine (`Settings` toggle "iCloud Sync", default ON but
  silently no-op when account unavailable).

## 2. OWNER-APPROVAL-REQUIRED changes (entitlements / Info.plist / project.yml / CI)

CLAUDE.md forbids changing entitlements/Info.plist/CI without explicit approval.
The following are REQUIRED and must be approved by the owner before implementing:

1. **`Echoelmusic.entitlements`** — uncomment the already-present (commented)
   block (lines 9-24):
   ```xml
   <key>com.apple.developer.icloud-services</key>
   <array><string>CloudKit</string></array>
   <key>com.apple.developer.icloud-container-identifiers</key>
   <array><string>iCloud.com.echoelmusic.app</string></array>
   ```
   NOTE the file's own warning: enabling this makes automatic provisioning
   REQUIRE a registered `iCloud.com.echoelmusic.app` container, or the
   TestFlight archive/upload FAILS. So step 2 must happen first.

2. **Apple Developer Portal (owner action, outside repo):** register the CloudKit
   container `iCloud.com.echoelmusic.app` under Team ID, and create the schema
   (record types/fields) in the CloudKit Console (Development env first, then
   "Deploy to Production" before App Store release).

3. **`project.yml`** — add `com.apple.developer.ubiquity-kvstore` is NOT needed;
   but add the iCloud background mode for silent-push pull (Phase 2 only):
   under iOS target `UIBackgroundModes` (currently `audio`,
   `bluetooth-central`, `bluetooth-peripheral`) add `remote-notification`.
   Phase 1 (no silent push) needs NO background-mode change.

4. **`Resources/iOS/Info.plist`** — only if Phase 2 silent push is adopted
   (`remote-notification` background mode mirrored here if not driven by
   project.yml's GENERATE_INFOPLIST_FILE=NO). No Phase 1 change.

5. **CI (`.github/workflows/testflight.yml`)** — likely NO file change, but the
   archive will now require the provisioning profile to include the CloudKit
   container. Confirm the App Store Connect provisioning regenerates with the
   container before the first `build_only=false` run. Flag for owner.

NONE of these will be edited by the agent until the owner approves. Phase 1 needs
only items 1 + 2.

## 3. Privacy / Security
- **Private database only.** No public DB, no shared DB. Data is per-iCloud-user,
  end-to-end under the user's account; the owner/developer cannot read it.
- **No PII.** Patches/clips/arrangements are creative data. Bio session summaries
  (`BioSessionSummary`) contain avg/peak HR, HRV, coherence — health-adjacent.
  Keep these in the PRIVATE DB only; they never touch a public/shared zone.
- **Bio data considerations:** treat `BioSession` records as sensitive. Make bio
  session sync a SEPARATE, independently-toggleable opt-in ("Sync wellness
  sessions to iCloud", default OFF) so users can sync music projects without
  syncing physiology. Reinforces CLAUDE.md "self-observation, not medical
  diagnosis" — no health claims in record metadata.
- **No secrets in records** (no tokens, no device IDs beyond CloudKit's own).
- **App Store review notes:** declare iCloud/CloudKit usage; in the privacy
  nutrition label, "Health & Fitness" data is stored in the user's private
  iCloud (not collected by developer, not linked to identity, not for tracking).
  Music project data = "User Content" stored in private iCloud.

## 4. Atomic steps (<5 min each), test strategy, riskiest steps

### Phase 0 — Local refactor to enable testable sync (no entitlement needed)
1. [ ] Add `protocol SyncableStore` exposing `func snapshotJSON() -> Data?` and
   `func mergeJSON(_ data: Data, modifiedAt: Date)` — File: new
   `Sources/Echoelmusic/Core/SyncableStore.swift`. Test: pure unit test of
   round-trip on a fake store.
2. [ ] Conform `ClipStore`, `ArrangementStore`, `PatchStore`, `SessionRecorder`
   to `SyncableStore` (reuse existing encode/decode; add `modifiedAt` write).
   Files: the four store files. Test: extend each store's existing tests to
   assert snapshot/merge round-trips and that merge with OLDER `modifiedAt`
   is rejected (LWW).
3. [ ] Add `enum SyncState { case unavailable(String), idle, syncing, error(String) }`
   and a `CloudSyncEngine` skeleton (`@MainActor @Observable`) behind
   `#if canImport(CloudKit)`. File: new
   `Sources/Echoelmusic/Core/CloudSyncEngine.swift`. Test: init with a mock
   `accountStatus` returning `.noAccount` sets `.unavailable` and performs no
   network call (inject a `CloudKitFacade` protocol so CK is mockable).
4. [ ] Define `CloudKitFacade` protocol (accountStatus / save / fetchChanges /
   delete) + a real `CKDatabaseFacade` impl. File: same file or
   `CloudKitFacade.swift`. Test: conflict-resolution and token-advance logic
   unit-tested against an in-memory fake facade (NO real iCloud).

### Phase 1 — Real CloudKit wiring (needs approved entitlement + container)
5. [ ] OWNER: uncomment entitlement block + register container/schema (items
   1-2 above). [BLOCKER — owner approval]
6. [ ] Implement `CKDatabaseFacade` save/fetch using a custom zone `EchoelZone`,
   blob field `payload` + `modifiedAt` + `version`. File: `CloudKitFacade.swift`.
   Test: device/iCloud-account integration only (cannot unit-test real CK).
7. [ ] Wire `CloudSyncEngine` into `EchoelmusicApp.swift` as an `.environment`
   object; trigger pull on `.active` scene phase, push on store-change
   (debounced 2s). File: `EchoelmusicApp.swift`. Test: device.
8. [ ] Add Settings toggles: "iCloud Sync" (default ON, no-op if unavailable),
   "Sync wellness sessions" (default OFF). File: `Views/SettingsView.swift`.
   Test: UI + device round-trip across two devices.

### Phase 2 (optional, later) — silent-push delta pull
9. [ ] `CKDatabaseSubscription` + `remote-notification` background mode (needs
   item 3 approval). Device-only.

### Test strategy
- **Unit-testable (CI, no iCloud):** SyncableStore snapshot/merge round-trips;
  LWW conflict resolution; account-unavailable -> no-op + no crash; change-token
  advance; JSON schema-version handling. All against the `CloudKitFacade` fake.
- **Device/iCloud-account required (manual):** real save/fetch, two-device
  convergence, sign-out mid-sync, airplane-mode degradation, fresh-install pull.
- **Riskiest steps:**
  - Step 5 (entitlement): a wrong/missing container BREAKS TestFlight archive
    (the entitlements file explicitly warns about this). Verify a `build_only`
    archive succeeds BEFORE a real upload.
  - Step 6 (conflict on single-record stores): clip/arrangement LWW could lose a
    concurrent edit; mitigate with `.ifServerRecordUnchanged` + merge-newer retry.
  - Bio session privacy default: must ship OFF by default (step 8) or it is a
    privacy regression.

## Risks
- Enabling iCloud entitlement without a registered container -> TestFlight upload
  fails. -> Mitigation: owner registers container first; gate on a green
  `build_only=false` verification run.
- LWW data loss on simultaneous multi-device edits. -> per-record granularity for
  patches/sessions; `.ifServerRecordUnchanged` + merge for single-record stores.
- Scope creep into a SwiftData migration. -> explicitly OUT of scope; keep local
  Codable stores as source of truth.
- Bio data leaving device unexpectedly. -> separate opt-in, default OFF.

## Dependencies
- OWNER: approve entitlement/Info.plist/project.yml edits (section 2).
- OWNER: register `iCloud.com.echoelmusic.app` CloudKit container + deploy schema.
- A real device + iCloud account for integration testing (Simulator CloudKit is
  unreliable; CI cannot test real CK).

## Rollback
- Phase 0 is local-only and inert (no behavior change) — revert the new files.
- Phase 1: flip the Settings "iCloud Sync" flag off (runtime kill switch), or
  re-comment the entitlement block and `git revert` the wiring commit. Local
  stores are untouched, so no data is lost on rollback.

## 5. Free-tier reality (confirmed)
- CloudKit **private database** storage and transfer count against the END
  USER's personal iCloud quota (the 5 GB free tier + whatever iCloud+ they buy),
  NOT the developer. Owner pays nothing for private-DB user data.
- CloudKit **public database** has a developer-side quota, but it SCALES FREE
  with active users (base 10 GB storage / 100 MB DB asset + per-user increments,
  up to very large ceilings at no charge). This plan uses NO public DB, so this
  doesn't even apply — owner cost is effectively $0 regardless of user count.
- Practical limits to respect: CKRecord max 1 MB per record field for non-asset
  data (use a `CKAsset` if any single blob could exceed ~1 MB — unlikely for
  patches/clips/sessions, but guard SynthPatch/Arrangement blob size and switch
  to per-record patches to stay small). Request-rate limits exist but are far
  above this app's sync cadence.
- Net: storing user projects/patches/sessions in the CloudKit PRIVATE DB is the
  intended, free-to-operate, Apple-native design the owner asked for.
