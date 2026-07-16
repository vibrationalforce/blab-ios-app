# PLAN — Dissolution S3 (Genre/Variation/Mood pro MIDI-Spur) + S5 (Session/Comp nach oben)

Investigation date: 2026-07-16 @ dcf730b (read-only; canonical parent spec:
`scratchpads/PLAN_MENUBAR_DISSOLUTION.md`). One slice per Ralph-Wiggum cycle,
≤3 code files each, consumer BEFORE UI (consumer-proof law).

---

## PART A — S3: per-MIDI-track Genre · Variation · Mood

### A1. Consumer-truth table (the load-bearing audit)

| Lane field (Timeline.swift) | Written by | Consumed in a LIVE path? | Verdict |
|---|---|---|---|
| `genreOverride: MusicStyle?` (:60) | init param + `decodeIfPresent` (:142) only — **no setter, no UI** | Only `LaneComposerInput.apply` (`Sequencer/LaneComposerInput.swift:34`) → `input.style` — but `apply` has **ZERO production callers** (grep: only `Tests/EchoelmusicTests/LaneComposerInputTests.swift`) | **NONE** |
| `mood: MoodProfile?` (:61) | init + `decodeIfPresent` (:143) only | Only `LaneComposerInput.apply` (:35) → same zero-caller seam | **NONE** |
| `variationSeed: UInt64?` (:62) | init + `decodeIfPresent` (:144) only | Only `LaneComposerInput.apply` (:36) → same zero-caller seam | **NONE** |

**⇒ The consumer-proof law bites: all three fields are INERT (both writer-less
and consumer-less).** The pure seam `LaneComposerInput.apply/hasOverride` exists,
is tested (5 Linux tests), and is exactly the missing math — it just was never
called. S3 must land the consumer (A3/S3a+S3b) before any UI (S3d).

`decodeIfPresent` for the three fields: **verified done** in ce248bf
(`Timeline.swift:140-144`, comment "absent in older docs ⇒ nil = global");
encode omits nil (session log Forts. 66). Persistence law satisfied.

### A2. What changed since the 07-14 HOLD-FOR-FOUNDER (premise re-audit)

`PLAN_PER_LANE_COMPOSITION_2026-07-14.md` §"FINDING" held S3 because (a) generate()
never fed the timeline, (b) two separate transports, (c) secondary lanes folded
multi-bar clips `%16`. Status today:

- **(b) RESOLVED** — Cycle C (task #46, shipped): ONE transport; the transport ▶
  plays the ARRANGEMENT when regions exist (`WorkspaceView.swift:332-346`,
  `timelinePlayer.play(document:clips:pattern:pianoRoll:)`).
- **(c) RESOLVED** — M1c windowing: secondary lanes get the exact primary-roll
  bar-slicing (`TimelineRegionPlayer.swift:406-424` `windowedBars`, via
  `RegionNoteWindow`); multi-bar secondary clips play correctly.
- **multiRoll is default-ON** with per-lane voice/patch/transpose/detune/pan
  (Forts. 65; `fanOutSecondaryLanes` + `MultiRollFanout`), so a per-lane-composed
  clip is genuinely audible in its own timbre.
- **(a) remains, scoped honestly:** `generate()` still composes ONLY the primary
  `pianoRoll` (`EchoelStudioView.swift:3715-3912`); it creates no regions/clips.
  ⇒ S3's per-lane composition is defined **for MIDI lanes that HAVE regions on
  the timeline** (the arrangement path). That matches the founder's framing
  ("pro MIDI-Spur", the Spur = timeline lane) without the two-transport merge.
  A lane with an override but no MIDI region composes nothing (nothing to fill) —
  the lane editor copy says so.

### A3. Consumer design (before UI)

Write path exists and is safe-by-value: `ClipStore.updateMelody(id:notes:)`
(`Core/ClipStore.swift:59-66`, whole-value write, region player re-reads at
onsets — a mid-play write becomes audible at the next region onset, like H11).

Semantics: **setting an override turns that lane generative** — on every
`generate()` (user Generate, evolve tick, recompose triggers) each overridden
MIDI lane's region clips are re-composed via `LaneComposerInput.apply` on the
SAME base input (shared body-stable `structureSeed` ⇒ same-genre lanes stay
cohesive; per the seam's caller contract `base.structureSeed` is non-nil —
`makeComposerInput` provides it, `EchoelStudioView.swift:3620`). nil-override
lanes and all non-MIDI lanes are never touched ⇒ **bit-identical when no
override is set**.

Multi-bar clips: reuse generate()'s loop-conform pattern (:3818-3831) — for a
region of N bars, bar b composes with `seed = laneSeed &+ b`,
`progressionPhase = basePhase + b`, shared `structureSeed`; bar b's notes offset
by `b * TimelineTime.ticksPerBar` (Notes carry absolute `startTick`,
`Note.swift:39` — round-trips through `RegionNoteWindow.barSlices`).

**Known risk (Council/Skeptic, must be in the review):** `updateMelody`
overwrites clip content and `ClipStore` has NO undo (TimelineStore undo does not
cover it). Mitigations: (1) override is opt-in per lane, nil = untouched;
(2) the lane-editor copy states plainly "composes this track's clips on every
Generate — replaces their notes"; (3) fan-out writes only clips referenced by
THAT lane's MIDI regions (clip-ownership check: region.laneID == lane.id and
clip.kind == .midi), never drums/audio/video content; (4) clearing the override
back to Global stops all writes (the last composed take stays — user data is
never pruned on load or on clear).

### A4. S3 slices (each ≤3 files, consumer-first)

**S3a — pure fan-out core (Linux-tested, invisible).**
New `Sources/Echoelmusic/Sequencer/LaneComposeFanout.swift` (pure, Foundation-only,
no Core import needed if it takes `[TimelineLane]`+`[Clip]` values — respect the
DSP/-import law: it lives in Sequencer/, fine):
`compose(base: BioComposer.Input, lanes: [TimelineLane], regions: [TimelineRegion], clips: (UUID)->Clip?, basePhase: Int) -> [UUID: [Note]]`
(clipID-keyed). Uses `LaneComposerInput.hasOverride/apply` + `BioComposer.compose`
+ per-bar seed/phase/tick-offset scheme above. Files: 1 source + 1 test.
TDD RED→GREEN: no-override ⇒ empty dict; deterministic (same input ⇒ same notes);
genre-only lane keeps global mood/seed; structureSeed untouched; bar-offset
round-trips `RegionNoteWindow.barSlices`; non-MIDI region/clip skipped.

**S3b — wire the consumer into generate().**
`EchoelStudioView.generate()` (after the primary take, ~:3835): call the S3a core
with the already-built `input`/`basePhase` and the timeline doc + clip store;
apply results via `clips.updateMelody(id:notes:)`. Guarded by
`lanes.contains(where: LaneComposerInput.hasOverride)` ⇒ zero work, bit-identical
today (no writer exists yet — wired but inert, the correct consumer-first state).
generate() is an ACTION (not body) — no sheet growth, no 10 Hz read, main-actor
compose, audio thread untouched. Files: `Studio/EchoelStudioView.swift` (+ reuse
S3a test file for any extracted decision helper). Reviewers: code + concurrency.

**S3c — lane setters (the writers).**
`Core/TimelineStore.swift`: `setLaneGenre(id:_ MusicStyle?)`,
`setLaneMood(id:_ MoodProfile?)`, `setLaneVariationSeed(id:_ UInt64?)` — exact
`setLanePan/setLaneTranspose` pattern (:475-498): guard index, assign, `persist()`.
nil = back to Global. Files: 1 source + `Tests/.../TimelineStoreTests` additions
(roundtrip, nil-reset, unknown-id no-op).

**S3d — UI in the EXISTING lane modal (slot-reuse, zero new sheets).**
`LaneFXEditor` (`Studio/ArrangeTimelineView.swift:1318`, presented via the ONE
`ArrangeModal .laneFX` item-sheet :176/:321 — the allowed pattern; root chain in
EchoelStudioView untouched). Add, **gated `lane.kind == .midi`**, below Detune:
- **Genre**: `.menu` Picker, `MusicStyle.Category` sections — the EXACT
  `genrePicker` pattern from `compositionPanel` (`EchoelStudioView.swift:1931-1954`)
  for visual/UX consistency — with a leading **"Global"** row (tag nil via
  `MusicStyle?`). onChange → `timeline.setLaneGenre` + recompose notification.
- **Mood**: Picker "Global / <saved moods>" from `MoodPresetStore`
  (factory + user presets; preset.profile → `setLaneMood`) — compact, reuses the
  one mood system instead of 8 more fields in the sheet. (If the founder wants
  free dial-in later: 8 `EchoelValueField`s in a DisclosureGroup — law-compliant,
  numeric params never get Slider/Stepper.)
- **Variation**: label "Variation: Global / eigene" + dice Button (rolls a new
  `UInt64.random` → `setLaneVariationSeed`; the seed is persisted so the take is
  deterministic thereafter — SeededRNG discipline downstream is untouched) +
  "Global" reset (nil). A seed is not a numeric parameter ⇒ button, not a field.
- Copy (no wellness words): "Composes this track's clips in its own genre on
  every Generate — replaces their notes. Global = follows the song."
Edits post the same recompose path S3b hears (reuse `recomposeIfRunning`'s
notification or a targeted `.echoelLaneCompositionChanged` handled where S3b
lives). Files: `Studio/ArrangeTimelineView.swift` (LaneFXEditor + a pure
gating/label helper) — setters from S3c. Reviewers: ui-state (freeze law — the
sheet reads only tap-frequency store state, no bio) + code review.

Order: **S3a → S3b → S3c → S3d**, one cycle each; deploy after S3d (working,
visible — the Transpose two-commit/one-deploy pattern).

---

## PART B — S5: Session (Name/Ort) + Key/Scale/Kammerton nach oben

### B1. Ground truth

- **Header (`WorkspaceView.topBar`, :143-204, height 50):** ZStack — centered
  brand button ("Echoelmusic" + version, ~100 pt); HStack: 12 pad + logo 22 +
  8 + `PulseMonitorMiniLive` (trace 50 + BPM minWidth 22 + padding ≈ **~90-100 pt**,
  `HeaderMonitors.swift:86/:108/:115`) + Spacer + Video tile 38 + 8 + Lux 38 + 8 +
  Immersive 54 + 12 pad = **~146 pt right block**.
- **TransportBar (:232-309, height 44):** 12 pad + Play 38 + 12 +
  `BodyTempoField(compact:)` (field 76 + lock 30 + spacing ≈ **112 pt**,
  `BodyTempoField.swift:67/:76/:110`) + 12 + "•••" 30 + 12 + Spacer +
  `TransportPositionView` (~70 pt monospaced) + 12 pad ≈ **~310 pt fixed**.
- **Panels today:** `compositionPanel` (:1575) = genrePicker · tonartRow
  (Key+Scale `.menu` Pickers, :1956) · kammertonRow (`EchoelValueField` A4,
  :1977) · tuningRow · tempoRow · variationsCard. `sessionPanel` (:1732) =
  `SessionNamePreviewLeaf` (:4229, readable "E~ · date · place · key · BPM · Hz"
  line) · placeRow (manual Ort ✅) · weatherRow. Both open as chips → the ONE
  `menuDropdownHost` overlay (:1201, NOT a sheet).
- **Data for chrome:** `SessionContext` carries `artistName/keyRoot/keyScale/
  a4Hz/placeToken` (`SessionContext.swift:32-88`) — all LOW-frequency. Key+Scale+
  Kammerton are chrome-readable with zero new plumbing. (`rootIndex`/`scale`
  @State in EchoelStudioView mirror into session via `adopt(key:)` at :3887.)
- **Chrome→studio door exists:** `.echoelChromeDoor` notification
  (`WorkspaceView:316`, handled `EchoelStudioView:505-520` — cases master/export/
  learn/live/video/routing/bio; **"composition"/"session" cases missing**).

### B2. Crowding math (iPhone 393 pt honest measurement)

- topBar: 295 pt fixed side content + ~100 pt centered brand = **~0 pt slack.
  Nothing more fits in row 1.** Cramming Key/Scale/A4 there is rejected.
- TransportBar: ~310 pt fixed ⇒ **~80 pt slack** — enough for ONE ~70 pt chip,
  not for Key+Scale+A4+Session (a "F♯ dorian · 432 Hz" readout alone is ~150 pt).
- **⇒ Design: a SECOND compact header row** (~26 pt) between topBar and
  TransportBar: the session identity line, tap = menu affordance (no cramming).
  Row budget: 393 − 24 padding = 369 pt; the line
  "E~ · 16 Jul · Hamburg · F♯ dorian · 72 BPM · 440 Hz" ≈ 46 chars @ font 11
  ≈ ~260 pt → fits; `lineLimit(1)` + `.truncationMode(.middle)`, place token
  display-capped (~12 chars) so a long manual Ort can't eat the key. Cost:
  chrome grows 94→120 pt (−26 pt timeline height) — honest price, flag for
  founder device-verify. (Alternative B, if the founder rejects the cost: swap
  the brand button's 9 pt version line for the session line — 0 pt cost but
  touches the brand header; hold unless asked.)

### B3. What moves vs. what stays

| Item | Header row 2 (NEW) | Stays in panel |
|---|---|---|
| Session name (E~ · date · place · key · bpm · Hz) | READOUT (the SessionNamePreviewLeaf fields, one line) | Filename detail line, artist edit |
| Ort (manual + toggle) | shown as token only | placeRow controls (TextField, toggle, status) |
| Key/Scale | shown ("F♯ dorian") — tap opens Composition dropdown | tonartRow Pickers (the CONTROLS) |
| Kammerton | shown ("440 Hz") — tap opens Composition dropdown | kammertonRow EchoelValueField |
| Tempo (+lock) | already up (TransportBar `BodyTempoField`, 8ae8522) ✓ | tempoRow extras (tap-tempo, metronome, haptics) |

Controls stay in the dropdown panels (a 26 pt row can't host Pickers on 393 pt);
the row is the always-visible identity + the DOOR. Two tap zones: left half
(name/place) posts `.echoelChromeDoor "session"`, right half (key/Hz) posts
`"composition"` — the existing decoupling, NO new root sheet, the dropdown host
is an overlay (:1196-1200), modal chain untouched.

### B4. Law checks (S5)

- **10-Hz/leaf law:** the row reads `SessionContext` (tap-frequency) and
  `transport.tempo` — tempo CHURNS ~10 Hz during a ~2 s `glideTempo` ease
  (`generate` :3872) ⇒ the row MUST be its own leaf struct
  (`SessionIdentityRowLeaf`, private in WorkspaceView.swift — exact
  `TransportPositionView` precedent :374-379). WorkspaceView.body itself reads
  none of it. No bio values in the row (pulse stays in `PulseMonitorMiniLive`).
- **Sheets:** zero new; doors reuse the dropdown. **EchoelValueField:** no new
  numeric UI in chrome (readout text only). **Flash:** static text. **Copy:**
  factual (key/Hz/BPM) — no wellness terms.

### B5. S5 slices

**S5a — pure identity-line core (Linux TDD).**
`Core/SessionNaming.swift` (exists — `effectivePlace` precedent): add pure
`SessionIdentityFormat.line(artist:date:place:keyName:bpm:a4Hz:) -> String`
+ place-token display cap. Files: 1 source + 1 test (fields order = founder's
E·date·place·key·BPM·Hz; empty-place omitted; cap; determinism via injected Date).

**S5b — the row + doors.**
`Studio/WorkspaceView.swift`: `SessionIdentityRowLeaf` (private leaf; reads
session + transport.tempo in its OWN body; two tap zones posting
`.echoelChromeDoor` "session"/"composition"; height 26, `EchoelTheme` border
bottom, a11y labels) + insert between topBar and TransportBar.
`Studio/EchoelStudioView.swift`: add `case "composition": activeMenu = .composition`
and `case "session": activeMenu = .session` to the :507 switch. Files: 2.
Reviewers: ui-state (freeze law: verify WorkspaceView.body gained no live read —
the 10.76.50 rule; the leaf owns the churn) + code review.

**S5c — chip retirement (AFTER founder device-verify, the Bio-B3 order).**
Remove `.composition`/`.session` from `studioChips` (`EchoelStudioView.swift:1136`)
— panels stay reachable from the header row doors; chips-filter is one line,
reversible. Files: 1. Only after the founder confirms the row on device
(gesetz: "Chip fällt erst nach Geräte-Verify").

### B6. Test strategy summary

| Slice | RED→GREEN (Linux) | Device/CI-only |
|---|---|---|
| S3a | fan-out determinism, no-override empty, structureSeed shared, bar offsets, non-MIDI skip | — |
| S3b | decision helper (which lane→clip pairs get written) if extracted; else covered by S3a | Xcode gate; bit-identical smoke (no override ⇒ no updateMelody call, assert via test seam if cheap) |
| S3c | setter roundtrip/nil-reset/unknown-id | — |
| S3d | MIDI-gating + label helper pure tests | ui-state review; founder device-verify: 2 lanes, one Genre=Trap ⇒ two genres sound simultaneously; clear→Global follows the song again |
| S5a | line format/order/omission/cap | — |
| S5b | — (view glue) | ui-state review (no ancestor churn), device: open menus WHILE bio runs (menu-freeze regression check) |
| S5c | — | founder verify first |

### Open founder questions (surface, don't guess)
1. S5 row costs 26 pt timeline height — ok, or prefer Alternative B (replace the
   version line under "Echoelmusic")?
2. S3 mood UI: preset picker enough, or the 8 dials per lane?
3. S3 semantics: overridden lane re-composes on EVERY Generate/evolve (clip notes
   replaced) — confirm that's the wanted "generative Spur" behavior.
