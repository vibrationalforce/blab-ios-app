# Plan: Unified Versioned Project Document + App-Wide Undo/Redo

> ⛔ **SCOPE NOTE (audit 2026-09-02): this plan predates the product definition of 2026-07-25**
> (`docs/dev/PRODUCT_DEFINITION.md`, Editor ≠ Workstation). Where it names timeline / clips /
> arrangement / multitrack / lanes-as-tracks / AUv3 / broadcast / drums / piano-roll surfaces, those
> are CUT and that part is history — do not execute it. Nothing below was edited; check the
> definition before building from any line here.

Date: 2026-06-20
Branch: claude/piano-roll-clip-view-wozlie (cut feature branches per cycle)

## Context
Persisted state is scattered across ~8 independent `@MainActor @Observable` stores, each
owning its own `AppGroupStore` subdirectory + filename, each calling a private `persist()`
on every mutation. There is no document concept (a "project" = one row in `ProjectStore`,
disjoint from the live clips/arrangement/patch/session state) and no undo anywhere. This
plan introduces (a) ONE versioned `EchoelDocument` that composes the live editable state
without removing the per-domain store ergonomics, and (b) a central reversible-command
layer added store-by-store. Both must stay CI-green and individually shippable (Ralph
Wiggum: one store per cycle, no big-bang).

---

## 1. Inventory — every piece of persisted state today

All JSON unless noted. App Group container `group.com.echoelmusic` (falls back to
Application Support on Linux/CI). Each path below is `<subdir>/<name>.json`.

| # | Owner (file) | Persistence | Container path | Schema (Codable type) |
|---|---|---|---|---|
| 1 | `Core/ClipStore.swift` | AppGroupStore | `Clips/clips.json` | `[Clip?]` fixed-8 grid |
| 2 | `Core/ArrangementStore.swift` | AppGroupStore | `Arrangement/song.json` | `Arrangement` (sections → `clipID`) |
| 3 | `Core/PatchStore.swift` | AppGroupStore ×2 | `Patches/userPatches.json` + `Patches/patchMeta.json` | `[SynthPatch]` (user only; factory excluded) + `Meta{favorites,recents}` |
| 4 | `Core/FXPresetStore.swift` | AppGroupStore ×2 | `FXPresets/userFXPresets.json` + `FXPresets/userFXPresetMeta.json` | `[FXPreset]` + `Meta` |
| 5 | `Core/MoodPresetStore.swift` | AppGroupStore ×2 | `MoodPresets/userMoodPresets.json` + `MoodPresets/moodPresetMeta.json` | `[MoodPreset]` (user only) + `Meta` |
| 6 | `Core/ProjectStore.swift` | AppGroupStore | `Echoel/projects.json` (default subdir) | `[Project]` newest-first |
| 7 | `Core/SessionContext.swift` | **UserDefaults** (not App Group!) | keys `echoel.artistName/keyRoot/keyScale/a4Hz` | scalars |
| 8 | `Core/CrashSafeStatePersistence.swift` | **raw FileManager** (App Support, NOT App Group), singleton, 10s Timer autosave + journal | `session_state.json` / `.tmp` / journal / recovery | `SessionState` (bio/audio/visual/light settings + metrics) |

Live, in-memory editable state with NO direct persistence (snapshotted only when a
`Project` is saved): `PianoRollModel` (the melody), `BeatPlayer.pattern` (drum grid +
tempo + swing/accents). `LoopExporter` = transient export, no state. `CloudSync.swift`
exists but is an unwired foundation. `ModulationEngine` routing is in-memory only.

Key observations driving the design:
- `Project` (`Core/Project.swift`) is already a flat snapshot bundle (style/key/bpm/
  patch/notes/drumSteps/drumAccents). It is the seed of the unified doc but does NOT yet
  compose clips, arrangement, presets, or session context, and has **no schema version**.
- Three storage backends are in use (App Group / UserDefaults / raw App Support). Only the
  App Group is shared with AUv3/Widget/Watch. SessionContext + CrashSafe escape it.
- Stores already enforce "one mutating method → one `persist()`" — the ideal seam for both
  command interception and autosave debouncing.

---

## 2. Target: ONE versioned `EchoelDocument`

New file `Sources/Echoelmusic/Core/EchoelDocument.swift` — pure `Codable, Sendable,
Equatable` value type. It COMPOSES (does not replace) the per-domain value types so the
stores keep their methods and ergonomics; the document is just the aggregate snapshot
they all read from / write into.

```
public struct EchoelDocument: Codable, Sendable, Equatable, Identifiable {
    public static let currentSchemaVersion = 1
    public var schemaVersion: Int        // forward-compat gate
    public var id: UUID
    public var name: String
    public var savedAt: Date

    // Composed domains (each already Codable today):
    public var session:     DocSession         // artist/keyRoot/keyScale/a4Hz  (from SessionContext)
    public var transport:   DocTransport        // bpm, loopBars, swing          (from BeatPlayer)
    public var melody:      [Note]              // (from PianoRollModel)
    public var drums:       DocDrums            // steps[][], accents[][]        (from BeatPlayer.pattern)
    public var activePatch: SynthPatch          // the sound on the poly voice
    public var clips:       [Clip?]             // fixed-8 grid                   (from ClipStore)
    public var arrangement: Arrangement         // section chain                 (from ArrangementStore)

    // Forward-compat capsules — present but empty until those domains land.
    // Decoded leniently; unknown keys ignored. Reserve the names now.
    public var video:       DocVideo?    = nil  // capture/trim (ROADMAP)
    public var stream:      DocStream?   = nil  // RTMP scene   (ROADMAP)
    public var automation:  DocAutomation? = nil// param lanes  (ROADMAP)
    public var modulation:  DocModulation? = nil// mod matrix
}
```

Forward-compat rules (documented in-file + a SKILL contract): all enums stored raw-string
with safe fallbacks (as `Project` already does); decoder uses
`decodeIfPresent` for every field so an older binary can open a newer doc minus unknown
domains; `schemaVersion` lets a newer binary run a migrator. Library-style data (preset
collections + favorites/recents in PatchStore/FXPreset/MoodPreset) stays OUTSIDE the
document — those are device libraries, not per-song state, and keep their own files. The
document references a patch by value (the active sound), not the whole library.

`ProjectStore` becomes the document library: rename conceptually to "documents", keep
`projects.json` filename for compat, change element type `Project` → `EchoelDocument` via
the migration in §3. Each store gains two pure methods (no I/O): `snapshot(into:)` writes
its slice into a `var EchoelDocument`, and `load(from:)` adopts a slice. The document is
assembled/applied by a thin new coordinator `Sources/Echoelmusic/Core/DocumentCoordinator.swift`
(`@MainActor @Observable`) that holds references to the stores + live models, owns the
"current open document" identity, and is the ONLY thing that calls `ProjectStore.save`.

---

## 3. Non-destructive migration + rollback

New file `Sources/Echoelmusic/Core/DocumentMigration.swift` (pure, fully unit-testable —
no I/O; takes raw `Data`/decoded values in, returns `EchoelDocument`).

Forward path (lazy, copy-not-move — originals stay untouched):
1. On `DocumentCoordinator` init, if `Echoel/projects.json` decodes as `[EchoelDocument]`
   with `schemaVersion >= 1`, use it directly.
2. Else attempt decode as legacy `[Project]`. For each, build `EchoelDocument` (schemaVersion
   1) by lifting the flat fields into the composed sub-structs; `clips`/`arrangement` default
   empty (legacy projects never had them). This is a pure function `migrate(legacy:) ->
   EchoelDocument`.
3. Write the migrated array to a NEW file `Echoel/documents.json` (`projects.json` is left
   in place, read-only, as the rollback source). A one-shot `UserDefaults` flag
   `echoel.docMigration.v1.done` guards against re-running.
4. SessionContext (UserDefaults) and CrashSafe (`session_state.json`) are NOT folded into
   the document on migration; they remain the "live working state" sources and are read
   into the document only when the user explicitly Saves. (CrashSafe stays as the
   crash-recovery layer; it can later autosave the open `EchoelDocument` instead of the
   ad-hoc `SessionState` — separate cycle.)

Rollback story:
- Originals (`projects.json`, each `<subdir>/*.json`, the UserDefaults keys) are never
  deleted or rewritten by the migration — only read. Deleting `documents.json` + clearing
  `echoel.docMigration.v1.done` returns the app to pre-unification behavior on next launch.
- A debug-only `DocumentCoordinator.resetMigration()` does exactly that for QA.
- Because the new document library lives in a new filename, an older app build that ships
  rolled back still finds its `projects.json` intact.

---

## 4. Central command model for app-wide Undo/Redo

New file `Sources/Echoelmusic/Core/CommandStack.swift` — `@MainActor @Observable`.

```
public protocol ReversibleCommand: Sendable {
    var label: String { get }                 // "Move Section", "Set Clip"
    @MainActor func apply()
    @MainActor func revert()
}
@MainActor @Observable public final class CommandStack {
    public private(set) var canUndo: Bool
    public private(set) var canRedo: Bool
    public func run(_ c: ReversibleCommand)   // apply + push to undo, clear redo
    public func undo(); public func redo()
    public func beginGroup(_ label:); public func endGroup()  // transactional grouping
}
```

Design for INCREMENTAL adoption (no big-bang):
- A store is undo-enabled by routing its mutations through `CommandStack.run` with a
  closure-pair command. The simplest, lowest-risk pattern: a generic
  `ClosureCommand(label:, do:, undo:)` so a store edit like
  `ArrangementStore.move(at:by:)` becomes capture-old-value → run a command whose `revert`
  restores it. No per-edit bespoke command classes required up front.
- Stores currently call private `persist()` after each edit. Adoption per store = inject an
  optional `commandStack` + an optional "edit closure" indirection; when present, route
  through it; when absent (default), behave exactly as today. This keeps every un-migrated
  store and all existing tests green.
- Transactional grouping: a compound user gesture (e.g. "duplicate section + assign clip")
  wraps `beginGroup`/`endGroup` so it undoes atomically. The document save is the natural
  commit boundary (autosave fires after the group closes).
- Snapshot-fallback option for coarse domains (PianoRoll/BeatPattern, which mutate in many
  tiny ways): a single `SnapshotCommand` that captures the whole domain value before/after
  a gesture — cheap given these are small value types — avoids instrumenting every setter.
- Undo/redo are pure in-memory operations on `@MainActor`; they trigger the same
  debounced autosave path. The stack is session-scoped (not persisted) in v1.

Adoption order (most edits / highest value first, each its own cycle): Arrangement →
Clips → PianoRoll (snapshot) → BeatPattern (snapshot) → PatchEditor → SessionContext.

---

## 5. Concurrency notes (Swift 6 strict)
- All new types: `DocumentCoordinator`, `CommandStack` are `@MainActor @Observable`;
  `EchoelDocument` + all `Doc*` sub-structs are `Codable, Sendable, Equatable` value types.
- Autosave debouncing: `DocumentCoordinator` replaces the current "persist on every
  mutation" with a debounced commit — a `Task`-based 400–800 ms trailing debounce on the
  MainActor (cancel-and-reschedule), so a burst of undoable edits writes once. Each store's
  private `persist()` is redirected to `coordinator.markDirty()` rather than writing
  directly (per store, during its adoption cycle). Library files keep their own immediate
  saves (low churn).
- NO audio-thread I/O: stores/coordinator are MainActor-only; the audio render path never
  touches them. Live models that the render path reads (BeatPlayer.pattern, voices) are
  snapshotted to/from the document on the MainActor, never serialized from the render block.
- `AppGroupStore.save` already does `.atomic` + `.completeFileProtection` — keep. The
  debounced write stays off the render thread by construction (MainActor `Task`).
- `CommandStack.undo/redo` run synchronously on MainActor; `ReversibleCommand` is `Sendable`
  but its `apply/revert` are `@MainActor`-isolated (no cross-actor capture of stores).

---

## 6. Cycle plan (bounded, CI-green, individually shippable)

Each cycle = ≤3 files, builds + tests green, shippable alone. TDD: pure migration/command
logic gets failing tests first.

1. **Doc model + schema version.** Add `EchoelDocument.swift` + `Doc*` sub-structs; add
   `schemaVersion` to `Project` is NOT needed (keep `Project` as legacy). Tests:
   round-trip encode/decode, forward-compat decode of a doc with unknown future keys.
   Files: `Core/EchoelDocument.swift`, `Tests/.../DocumentTests.swift`. Ship.
2. **Migration (pure).** `DocumentMigration.swift` + `migrate(legacy:)`. Tests: legacy
   `[Project]` → `[EchoelDocument]` lossless on shared fields, empty clips/arrangement.
   Files: `Core/DocumentMigration.swift`, tests. Ship (not yet wired → no behavior change).
3. **Coordinator + lazy migration on launch.** `DocumentCoordinator.swift`: reads
   `documents.json` else migrates `projects.json` (copy), guarded by the UserDefaults flag;
   `resetMigration()` for QA. Wire into `EchoelmusicApp` as one `@State` + `.environment`.
   `ProjectStore` reads through it. Tests: migration runs once; originals untouched. Ship.
4. **Snapshot/apply slices.** Add `snapshot(into:)`/`load(from:)` to ClipStore +
   ArrangementStore + PianoRollModel + BeatPlayer + SessionContext (pure, no I/O).
   Coordinator assembles/applies the full document (Save/Open a project = full state).
   Tests: assemble→apply round-trip equals original. Ship.
5. **Debounced autosave.** Redirect each store's `persist()` to `coordinator.markDirty()`;
   coordinator owns the trailing-debounce write. Tests: N rapid edits → 1 write (inject a
   fake clock/sink). Ship.
6. **CommandStack.** `CommandStack.swift` + `ClosureCommand` + `SnapshotCommand` +
   grouping. Tests: run/undo/redo/group invariants, canUndo/canRedo. Add to app env. No
   store wired yet. Ship.
7..N. **Adopt undo per store** (one per cycle): Arrangement, Clips, PianoRoll(snapshot),
   BeatPattern(snapshot), PatchEditor, SessionContext. Each cycle: route that store's edits
   through `CommandStack`, add undo/redo affordance, keep default-off path intact, add tests.
   Ship each.
8. **(Later) CrashSafe → document.** Point `CrashSafeStatePersistence` autosave at the open
   `EchoelDocument` instead of ad-hoc `SessionState`; fold SessionContext into App Group.
   Gated cycle (touches recovery + storage backend — Council review).

## Risks
- Three storage backends (App Group / UserDefaults / raw App Support) → fold gradually;
  do NOT move SessionContext/CrashSafe in the same cycle as the doc model (risk to recovery).
- Snapshot-based undo on PianoRoll/BeatPattern could miss in-place mutation if a setter
  bypasses the gesture boundary → enforce "every undoable gesture wraps begin/endGroup".
- Forward-compat decode must never throw on unknown keys → enforce `decodeIfPresent` +
  test with a synthetic future doc.
- Doubling files (`projects.json` + `documents.json`) during rollback window → acceptable;
  cleaned up in a later `chore:` once v1 is proven on device.

## Dependencies
- None external (Foundation only). No new top-level dirs (all under `Core/`). No audio
  thread, no DSP triad touched.
- Founder gate: §8 (CrashSafe/SessionContext storage move) and renaming user-facing
  "Project" concept → Council per CLAUDE.md.

## Test Strategy
- New `DocumentTests` (round-trip, forward-compat), `DocumentMigrationTests` (lossless
  legacy lift, idempotent guard), `CommandStackTests` (undo/redo/group), per-store
  snapshot round-trip tests. Run with existing CoreSystemTests/CoreServicesTests suites.
- All pure logic (migration, commands, snapshot/apply) is I/O-free → runs on Linux CI.

## Rollback
- Delete `Echoel/documents.json` + clear `echoel.docMigration.v1.done`; originals intact.
- `DocumentCoordinator.resetMigration()` (debug) does this. Each cycle is revertable by
  its own commit since stores keep their default no-command / direct-persist path until
  explicitly migrated.
