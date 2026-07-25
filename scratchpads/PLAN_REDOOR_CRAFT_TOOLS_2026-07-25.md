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

- **131a — the slot.** Add `CraftEditor` enum + `@State` + ONE `.sheet(item:)` +
  the `craftEditorSheet(_:)` builder returning `PatchEditorView` for `.patch` and
  `EmptyView()` for the other two (wired next). Chain 11→12, verified by count.
  Extend the chrome-door handler with `case "patch"`. Add the visible entry point
  (Sound/patch row in the existing Composition or Master panel — no new surface).
  **Reviewer: ui-state-reviewer** (chain count + no double-modal + no 10 Hz read
  in the host body).
- **131b — piano roll.** `.roll` → `PianoRollView(...)`. Must pass the same
  environment the deleted timeline supplied (`pattern:`, `model:`) — ground-truth
  the exact init args from git history (`git show eb58e7a^:...ArrangeTimelineView.swift`
  lines 456/531) rather than guessing. Door: chrome-door `case "roll"` + an entry
  point next to the generated-melody controls. **Reviewer: ui-state-reviewer.**
  ⚠ `PianoRollView` publishes `MusicalFrame` — verify the publish path still fires
  when it is presented from here, otherwise the visual/light spine stays dark.
- **131c — spatial stage (decide, then wire).** `.stage` → `ImmersiveStageView()`.
  This is the output stage (ADM-OSC scene placement), so it belongs to the product
  per PRODUCT_DEFINITION — but it is the least urgent of the three for the ship
  gate (gate item 4 says light/space are "demonstrable, not required for v1"). May
  be deferred; if deferred, remove `.stage` from the enum rather than leaving a
  dead case.
- **131d — docs + invariant.** Update `CLAUDE.md` (the doorless-keeper warning
  becomes "re-doored"), and either restore or delete the
  `toolItems`/`openTool` invariant so no future session trusts a lying list.

## Protection gates (must not break)

- Body modifier count **must be ≤ 12** after 131a; assert by grep in the commit
  message. If a later editor is added, extend the enum — never add a modifier.
- No `@Observable` high-frequency read (bio/playhead) introduced into
  `EchoelStudioView.body` or any computed var it evaluates.
- Never two modals true simultaneously.
- `EchoelValueField` for any numeric parameter row added.
- Device-verify honestly: this is a render/presentation change, so it is
  **compile-verified only** until a founder device run. Say so.
