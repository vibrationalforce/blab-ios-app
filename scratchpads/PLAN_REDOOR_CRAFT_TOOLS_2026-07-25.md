# PLAN — Task #131: re-door the craft tools (PatchEditor · PianoRoll · Spatial Stage)

**Why now:** this is ship-gate item 2 **"Kontrolle"** of *Instrument-Complete v1*
(`docs/dev/PRODUCT_DEFINITION.md`). The TestFlight freeze cannot lift without it.
Sequenced BEFORE Slice 5 (DAW-Model-Removal) because Slice 5 is pure hygiene with
no user-visible value, while this unblocks shipping.

**Decision already made** (Grand Council 2026-07-25, founder delegation, `d29a14a`):
the patch editor and piano roll are **instrument controls, not DAW surfaces** —
Editor ≠ Workstation. The piano roll is additionally load-bearing: `PianoRollView`
**publishes `MusicalFrame`**, the signal the visuals and light rig read. So this is
"re-door", never "cut".

---

## ⚠ CORRECTION 2026-07-25 (before building 131a): the patch half of #131 was WRONG

I told the founder the instrument "can neither edit a generated melody nor shape
or save a sound patch". **Only the melody half was true.** Ground truth:

- `EchoelStudioView.soundPanel` (`:2748`, "Sound & texture — Shape the timbre —
  exact to 0.0001") is **mounted** (`dropdownContent` `:1308`) and **reachable**
  through the LIVE `StudioMenu.sound` chip. It carries `presetRow`, a randomize
  button, and tone / filter / envelope / space+vibrato / sub rows bound to
  `$currentPatch` — the single source of truth for the live timbre (`:152`, `:274`).
- Patch **library load** (`:2920`) and **save-as** (`patchStore.saveAs`, `:840`)
  are both live from that panel.
- v10.79.207 removed the `PatchEditorView` sheet as a **"Dead-*duplicate*"** —
  duplicate of exactly this panel. Re-dooring it would rebuild something that was
  deliberately deleted, and would spend sheet-chain headroom on a second UI for a
  capability the instrument already has.

**Consequences:**
1. **131a is re-scoped to the piano roll** (the genuinely doorless capability).
2. `PatchEditorView.swift` is reclassified: not a doorless keeper but a
   **near-redundant duplicate** → hand it to Slice 6. Ship-gate item 2 "Kontrolle"
   is satisfied for the patch half **today**, by `soundPanel`.
   ⚠ **But not a strict superset** (found by code-reviewer on 131a, verified): three
   `SynthPatch` fields have NO editor anywhere outside `PatchEditorView` —
   `outputLevel` (`PatchEditorView.swift:218`), `unisonVoices`, `unisonDetuneCents` —
   plus its `previewKeys` audition keyboard. So Slice 6 must **port those rows into
   `soundPanel` BEFORE deleting the file**, otherwise "cleanup" silently removes
   three real parameters. Deleting first and porting later is not acceptable: the
   parameters stay in the persisted `SynthPatch`, so they would become invisible
   state the user cannot reach.
3. 131b folds into 131a — there is only one editor left to door, so doing it in
   two commits would be ceremony. The `CraftEditor` enum still exists so the NEXT
   editor costs a case, not a modifier.
4. `CLAUDE.md`'s DOORLESS KEEPERS block must drop `PatchEditorView` (131d).
5. This also settles the Slice 5 open question: the door presents the **LIVE**
   roll (`onDone: nil` ⇒ not clip-scoped), so nothing here needs
   `syncPrimaryRollClip`'s ClipStore/TimelineStore mirror — it stays dead weight
   and Slice 5 may remove it.

---

## Audit — the sheet chain as it stands (2026-07-25, after Slice 4)

`EchoelStudioView.swift` body carries **11** presentation modifiers:

| Line | Modifier | Binding |
|---|---|---|
| 704 | `.sheet(isPresented:)` | `showOpen` |
| 705 | `.sheet(item:)` | `share` |
| 706 | `.sheet(item:)` | `diagnostics` |
| 707 | `.sheet(isPresented:)` | `showAllFX` |
| 713 | `.sheet(isPresented:)` | `showInput` |
| 714 | `.sheet(isPresented:)` | `showRouting` |
| 715 | `.sheet(isPresented:)` | `showLearn` |
| 723 | `.sheet(item:)` | `sampleBrowserTrack` |
| 725 | `.fullScreenCover(isPresented:)` | `showVisual` |
| 807 | `.fullScreenCover(isPresented:)` | `showMeditation` |
| 809 | `.sheet(isPresented:)` | `showLiveColabo` |

(`:804 .sheet(item: $visualShare)` is nested INSIDE the `showVisual` cover, not on
the body — it does not count toward the body's aggregate generic type.)

**Headroom exists but must not be spent carelessly.** The 10.76.34 black-screen
crash happened at ~19 body modifiers (≈16 sheets + 3 covers); the last known-good
baseline was "just under". Slices 1–4 plus the v10.79.207 sheet retirement have
brought the chain down to 11 — roughly 8 modifiers of margin. That margin is
insurance, **not budget**: the law in `CLAUDE.md` is "do NOT keep GROWING this
chain", and an `AnyView` split does not save it (10.76.35 proved that).

### Live door mechanisms (verified)

1. **`.echoelChromeDoor` notification — LIVE.** Posted by `WorkspaceView:404` and
   `HeaderMonitors:223/356/431`; handled in `EchoelStudioView:520` (`case "master"`,
   `"export"`, `"learn"`, `"live"`, `"video"`, `"routing"`, `"bio"`, `"tempo"`,
   `"session"`). This is the extensible, already-working router.
2. **`StudioMenu` / `activeMenu` — LIVE.** The in-panel menu system.

### ⚠ Trap for a future session: `toolItems` / `openTool` / `toolsSection` are a DEAD, LYING mechanism

- `toolsSection` (`:926`) still exists as a view builder with
  `gridChip(t.title, t.icon) { openTool(t.id) }`, but is **not composed into the
  body** (removed as "pure dead weight on the 21-modal metadata chain", see the
  comment at `:365`).
- `toolItems` (`:866`) still advertises **`pianoroll`**, **`sound`** (= the patch
  editor), `automation`, `audioclip`, `plugins`, `broadcast`.
- But `openTool` (`:898`) has **no case for any of them** — only `audioin`,
  `meditation`, `routing`, `learn`, `importmidi`, `livecolabo`, `visual`, then
  `default: break`.
- So the file's own documented invariant at `:865` — *"guards their action in
  `openTool`, so a tool never appears without a live action"* — **is violated
  today**. Re-mounting `toolsSection` would render six chips that silently do
  nothing.

**Consequence for this task:** do NOT restore the tools grid to fix #131. Use the
live chrome-door router. And add `toolItems`/`openTool`/`toolsSection` to the
Slice 6 cleanup list (either delete, or restore the invariant).

---

## Design — ONE new slot, three destinations

Add **exactly one** `.sheet(item:)` driven by a 3-case enum. Chain goes 11 → 12,
one modifier for three doors, and the enum makes the *next* editor free.

```swift
/// The craft editors — instrument controls (Editor ≠ Workstation). ONE sheet slot
/// for all of them so the body's modifier chain does not grow per editor
/// (black-screen metadata law).
private enum CraftEditor: String, Identifiable {
    case patch, roll, stage
    var id: String { rawValue }
}
@State private var craftEditor: CraftEditor?
```

- ONE modifier: `.sheet(item: $craftEditor) { AnyView(craftEditorSheet($0)) }`
- The content switch lives in a **separate small builder func**, not inline in
  `body`, so the body's aggregate type stays flat.
- Doors: extend the LIVE `.echoelChromeDoor` handler at `:520` with
  `case "patch"`, `case "roll"`, `case "stage"` → `craftEditor = .patch` etc.
  Never drive two modals true at once (invisible tap-blocking layer).

**Why not slot-reuse instead?** No existing slot is dead — every one of the 11
bindings has real write sites (checked). `showMeditation` looked dead but is driven
at `:901`. So reuse would mean removing a working feature; one consolidated new
slot is cheaper and honest.

---

## Sub-slices (one Ralph commit each, gates green + reviewer each)

- **131a — the slot + the piano roll (ONE commit, per the correction above).**
  `private enum CraftEditor: String, Identifiable { case roll }` + `@State
  craftEditor` + ONE `.sheet(item: $craftEditor) { AnyView(craftEditorSheet($0)) }`
  (chain 11→12, verified by grep) + a `craftEditorSheet(_:) -> AnyView` builder
  returning `PianoRollView(pattern: beatPlayer.pattern, model: pianoRoll)` — the
  exact init from the deleted timeline (`git show eb58e7a^:…ArrangeTimelineView.swift:531`),
  whose DEFAULT `onDone: nil` gives the LIVE clocked+voiced roll, i.e. the normal
  `MusicalFrame` publish path. Door: a `directChip("Notes", "pianokeys")` in the
  live `menuBar` — reviving an existing-but-unused helper, inside an `AnyView`-erased
  inner row, so the root body's generic type is untouched. It sets `activeMenu = nil`
  first (never two modals at once).
  **Deliberately NOT done:** no `.echoelChromeDoor` `case "roll"` — nothing in the
  chrome posts it, and a receiver for an unposted notification is exactly the dead,
  lying mechanism this plan warns about. No `.patch`/`.stage` case for the same
  reason: a case is added only together with its door.
  **Reviewers: ui-state-reviewer + code-reviewer.**
  **SHIPPED `f2cbf34`** (Xcode Compile Check green). ui-state-reviewer: 0 defects —
  chain 11→12 confirmed by independent count, one `craftEditor` write site with
  `activeMenu = nil` first, and the freeze law holds *structurally* because
  `BeatPlayer.pattern` is a `let` (`Sequencer/BeatPlayer.swift:44`) and the
  `@Observable` macro instruments only `var`s, so the read registers no observation in
  any scope. It also verified `PianoRollView` already keeps `pattern.currentStep` in
  the `RollPlayheadView` leaf (`:1864`), so the new door brings no fresh freeze source.
  Follow-up `<this commit>` fixed three code-review findings: my own `craftEditorSheet`
  doc wrongly claimed presenting the roll is the `MusicalFrame` publish path (it is
  `PianoRollModel` on the shared tick, presentation-independent); the comment cited
  PRODUCT_DEFINITION for "automation", a word that doc never uses; and
  `AnyView(craftEditorSheet($0))` double-boxed an already-`AnyView` return.
  **Known + accepted:** the roll's Stop cascades the ONE-Stop law
  (`PianoRollView.swift:1206` → `stopEverything`), so Stop inside the roll ends the
  bio session, not just playback — intentional but newly reachable from a surface where
  a local transport is plausible → NEEDS-FOUNDER-VERIFY. The chip is 26 pt tall
  (matches `menuChip`), i.e. consistent with the bar but below the 44 pt HIG minimum
  that #113 enforced for header tiles → a candidate for the chrome-pro pass (#114),
  not a regression of this slice.
  **Trap grew a second head:** `toolItems` still advertises a dead `pianoroll` id
  (`:893`) while `openTool` has no case for it, so the roll now has one real door and
  one lying one. A future session "fixing" the list would create a duplicate door.
  Slice 6 must delete the trio, not repair it.
- **131c — spatial stage (decide, then wire).** `.stage` → `ImmersiveStageView()`.
  This is the output stage (ADM-OSC scene placement), so it belongs to the product
  per PRODUCT_DEFINITION — but it is the least urgent of the three for the ship
  gate (gate item 4 says light/space are "demonstrable, not required for v1"). May
  be deferred; if deferred, remove `.stage` from the enum rather than leaving a
  dead case (the enum ships with `case roll` only for exactly this reason).
- **131d — docs + invariant.** ⚠ The "delete the trio" half is NOT a doc tweak —
  audited 2026-07-25 and it has three real dependencies. `openTool` (`:930`) is
  called ONLY from `toolsSection` (`:985/995/1000/1025`), which is not composed into
  the body, so the whole trio is already unreachable — deleting it therefore cannot
  reduce reachability. BUT three bindings have their **only** `= true` write site
  inside it:
  · `showMeditation` (`:933`) — consistent with the founder's "MeditationView bleibt
    bewusst türlos". Deleting is correct; the `.fullScreenCover` at `:833` and the
    binding go with it (or the whole MeditationView door is a founder ask).
  · `midiImportPresented` (`:937`) — so **MIDI file IMPORT is currently doorless**
    (the `.fileImporter` at `:745` can never open). Export works. This is a real
    capability gap, not cleanup: decide re-door vs. retire.
  · `showVisual` (`:943`) — so the `.fullScreenCover` immersive visual at `:757` is
    **doorless too**. It is however a DUPLICATE: `FloatingVisualWindow` carries its
    own `.fullscreen` size case (`FloatingVisualWindow.swift:210/219/230`) and IS
    reachable (header toggle `WorkspaceView.swift:258`, Synth panel `:2250`). So
    ship-gate item 4 is not blocked — the wow visual is reachable edge-to-edge via
    the floating window.
    **Prize for Slice 6:** removing the doorless cover takes the body chain from
    **12 → 11** AND deletes the two-MetalBioView coordination dance
    (`floatingWasVisible`, `:718-725`) that exists only to stop the cover and the
    floating window rendering at once. That is a modifier slot bought back plus a
    GPU hazard removed — the best-value item on the Slice 6 list.
  Each of the three needs its own decision, so the trio deletion is a Slice 6 slice
  with reviewers, NOT part of 131d.
  131d itself: update `CLAUDE.md`: the DOORLESS KEEPERS block drops
  `PatchEditorView` (never was doorless in substance — `soundPanel` is the live
  editor) and marks `PianoRollView` re-doored via the `craftEditor` slot. Then
  either restore or delete the `toolItems`/`openTool` invariant so no future
  session trusts a lying list.

## Protection gates (must not break)

- Body modifier count **must be ≤ 12** after 131a; assert by grep in the commit
  message. If a later editor is added, extend the enum — never add a modifier.
- No `@Observable` high-frequency read (bio/playhead) introduced into
  `EchoelStudioView.body` or any computed var it evaluates.
- Never two modals true simultaneously.
- `EchoelValueField` for any numeric parameter row added.
- Device-verify honestly: this is a render/presentation change, so it is
  **compile-verified only** until a founder device run. Say so.
