# PLAN S2-W2 — voiceKind-aware routing (bottom-bar dissolution, Spur = Instrument)

> ⛔ **SCOPE NOTE (audit 2026-09-02): this plan predates the product definition of 2026-07-25**
> (`docs/dev/PRODUCT_DEFINITION.md`, Editor ≠ Workstation). Where it names timeline / clips /
> arrangement / multitrack / lanes-as-tracks / AUv3 / broadcast / drums / piano-roll surfaces, those
> are CUT and that part is history — do not execute it. Nothing below was edited; check the
> definition before building from any line here.


**Date:** 2026-07-16 · **Branch (investigation):** claude/piano-roll-clip-view-wozlie-5kxnrl
**Founder order / review finding:** 75e4899 REQUEST_CHANGES — `TimelineLane.builtinInstrument`
does NOT steer the sound path. Every SECONDARY MIDI lane plays a generic rack
`PolySynthVoice` (LaneVoiceRack, capacity 4); the PRIMARY roll lane plays `synth+leadSynth`
regardless of instrument. An "EchoelDrums" lane sounds like a poly synth.
**Goal:** a lane's instrument selects its voice KIND (drums → drum voice, subBass → real
mono sub, polySynth → PolySynthVoice; sampler → deferred, see §6). Afterwards the
`TrackInstrument.fxBus` pins for drums/subBass flip nil → `.drums`/`.bass`
(`TrackInstrumentTests.testFxBus_isHonestToTodaysEngineWiring` enforces flipping TOGETHER
with the routing — never alone).

---

## 1. Ground truth (investigated 2026-07-16)

| Piece | State |
|---|---|
| `Sequencer/LaneVoiceKind.swift` | EXISTS: `LaneVoiceKind` (poly/drums/sampler/subBass/bioVoice) + `TrackInstrument.voiceKind` (breakLoop → .drums). **Zero consumers** (confirmed). Tested (`LaneVoiceKindTests`). |
| `Sequencer/LaneVoiceRack.swift` | Fixed pool of 4 `PolySynthVoice`, created+attached ONLY in `attachAll()` (called flag-ON in the app's "attaching voices" block BEFORE `audioEngine.start()` — attach-before-start law, `EchoelmusicApp.swift:455`). `voice(slot:)`, `setInsert(fx)` (S2-W1 melodic fan). |
| Slotting (pure, Linux-tested) | `LaneVoiceSlotMap` → `LaneVoicePool.reconcile` (advisory) → `LaneVoiceRackPlan.commands` (**authoritative: slot == priority RANK** among secondary MIDI lanes) → `MultiRollFanout` per-slot lookups (patch/transpose/detune/pan/gain/instrument/laneID). Slots are RANK everywhere: pumps, all sinks, and the H5b AU host keying ride on it. |
| Player sinks (`TimelineRegionPlayer`) | `slotNoteSink`, `slotPatchSink`, `slotTransposeSink`, `slotDetuneSink`, `slotPanSink`, `slotGainSink`, `slotLaneSink` — fired at prime/load (`:452-462`, `:518-523`), live mixer merge (`:558-561`), clear/stop (`:481`, `:611`). `enableMultiRoll(capacity:sink:patchSink:)` (`:137`). |
| App wiring (`EchoelmusicApp.swift:515-574`) | Note sink: AU instrument wins (H5b), else `laneVoiceRack.voice(slot:)?.noteOn`; **note-OFFs go to BOTH** (mid-take flip law). All other sinks address rack slots + AU voices. |
| Candidate voices | `PolySynthVoice` (SPSC note/patch/fx queues; `setTranspose/setDetune/setPan/setGain/apply/setInsert`) · `DrumSynthVoice` (modal bank, `configure(DrumSynthParams)` + `fire(gain:)` + `configureInsertFX`, lock-free counters, mono per instance) · `SamplerVoice` (one-shot, `fire(gain:)`, `setRegion(... pitchSemitones:)` rate-pitch, `configureInsertFX`) · `SubBassVoice` (mono SPSC `noteOn(pitch:)`, octave-fold felt band, `setInsert`, NO setPan/setGain of its own) · `BeatPlayer` (8 Sampler + 8 DrumSynth + preview = its OWN kit; the step sequencer fires it). |
| FX buses | `FXBus` = bass/melodic/drums (`TrackFXStore`). Push sites today: `EchoelStudioView.setBassFX` (`:1490` → `subBass.setInsert`), `setDrumsFX` (`:1550` → fan over `beatPlayer.setFX` all 8 channels), `setMelodicFX` (`:1517` → synth+leadSynth+`laneVoiceRack.setInsert`, S2-W1); `ArrangeTimelineView.apply` (`:1387`, LaneFXEditor, melodic only). |
| Primary roll path | `PianoRollView.swift` (`PianoRollModel.applyStep ~:540-611`): notes → `outputVoice(for: role)` (synth/leadSynth split), `suppressBuiltIn` when a hosted AU owns the lane, plus the mono sub-DOUBLING reconcile (`subVoice`) and MIDI/AU mirrors. |
| Flags | `FeatureFlags.multiRoll`, `.laneAUInstruments` — registration-domain defaults, `set()` override; precedent for a new gate. |
| Pin test | `TrackInstrumentTests.swift:94-110` — compile-time-exhaustive switch; comment mandates together-flip. |

Budgets (CLAUDE.md): CPU <30%, mem <200MB, audio thread lock/malloc/ObjC/GCD-free.
P1 idle-voice skip (frames) already cuts idle render cost.

---

## 2. Chosen approach — heterogeneous kind pool AT THE RACK BOUNDARY

**Keep rank-based slotting untouched everywhere.** Slots stay priority ranks in
`LaneVoicePool` / `LaneVoiceRackPlan` / `MultiRollFanout` / pumps / every sink / the AU host.
The ONLY change of meaning happens inside `LaneVoiceRack`: it becomes a **facade** that
binds a rank-slot to a **physical voice** chosen by kind, from a small fixed heterogeneous
pool that is fully pre-attached before `audioEngine.start()`:

```
Physical pool (flag ON):  4 × PolySynthVoice   (existing — unchanged)
                        + 1 × LaneDrumKitVoice (NEW container: 4 × DrumSynthVoice, pitch-mapped)
                        + 1 × SubBassVoice     (NEW dedicated lane sub — NOT the primary doubling sub)
Physical pool (flag OFF): exactly today's 4 × PolySynthVoice — bit-identical.
```

A new PURE `KindVoiceAllocator` decides `rank-slot + kind → physical voice ref`
(`.poly(rank)` / `.drums(0)` / `.subBass(0)`), with per-kind capacity {drums: 1, subBass: 1},
stable bindings, deterministic first-rank-wins on contention, and **poly fallback**
(a 2nd drums lane sounds exactly as today — a poly voice — never silence). `sampler` and
`bioVoice` kinds resolve to poly fallback in v1 (§6). Runtime instrument switches are pure
re-routing on the control plane (everything is pre-attached → **no graph mutation while
running**); a kind flip mid-take sends allNotesOff/note-offs to the previously bound voice
(the H5b stranded-note law).

**Why this wins:**
- **Attach-before-start law holds trivially** — the pool is fixed, attached once in
  `attachAll()`, flag-gated, zero runtime attach.
- **Zero churn in the proven pure slotting machinery** — LaneVoicePool/RackPlan/Fanout keep
  their tested contracts; only a new pure layer + the device facade are added.
- **Budget-honest:** +5 source nodes flag-ON only (4 modal drums, idle-skipped + 1 sub sine,
  `hasEverSounded`-gated). Memory ≈ +100 KB. Flag OFF = today's byte path.
- **fxBus honesty becomes real:** the `.drums`/`.bass` inserts can be fanned to the SAME
  physical voices the lanes play (mirroring S2-W1's melodic fan), so the pins stop lying.

### Rejected alternatives
- **(b) Per-slot multi-voice** (every slot pre-attaches one voice of EVERY kind, one active):
  4 slots × (4 drum + 1 sub + 1 sampler) = **~24 idle source nodes** for a document that
  realistically has one drums + one bass lane. Scales O(slots × kinds); worst CPU/mem per
  benefit. Its one advantage (any slot any kind, no contention) is kept anyway via poly
  fallback in the allocator.
- **(a-strict) Kind-aware slot ASSIGNMENT inside LaneVoicePool/LaneVoiceRackPlan:** rewrites
  the authoritative rank contract that pumps, seven sinks and the H5b AU host all key on —
  maximal blast radius through reviewed, device-verified code for zero user-visible gain
  over the rack-boundary bind.
- **(c) Render-time timbre switching inside PolySynthVoice:** a DDSP poly pretending to be a
  modal drum kit / a felt mono sub is dishonest ("claim only what ships"), puts NEW code in
  the hottest render path, and still wouldn't justify the fxBus pins (the .drums bus params
  target `ChannelInsertFX`-style per-hit inserts, not a poly macro).
- **Route drum lanes into the existing BeatPlayer kit / bass lanes into the global doubling
  `subBass`:** two writers per voice — the step sequencer (kit) and the primary roll's sub
  reconcile (mono retune!) would fight the lane; per-lane gain/pan/mute (`slotGainSink`)
  would duck the sequencer's kit. Dedicated lane voices are the only honest mixer story.

---

## 3. Atomic slices (Ralph Wiggum: each ≤3 files, each alone shippable + green)

### S2-W2-1 — PURE: `KindVoiceAllocator` + `MultiRollFanout.voiceKind(forSlot:)`
*Files (3):*
- `Sources/Echoelmusic/Sequencer/KindVoiceAllocator.swift` (NEW, Foundation-only)
- `Sources/Echoelmusic/Sequencer/MultiRollFanout.swift` (add `voiceKind(forSlot:in:rollLane:)
  -> LaneVoiceKind` — reads `lane.builtinInstrument?.voiceKind ?? .poly`; mirrors
  `patch(forSlot:)`)
- `Tests/EchoelmusicTests/KindVoiceAllocatorTests.swift` (NEW)

Contract: `PhysicalVoiceRef { case poly(Int), drums(Int), subBass(Int) }`;
`allocate(ordered: [(slot: Int, kind: LaneVoiceKind)], drumUnits: Int, subUnits: Int)
-> [Int: PhysicalVoiceRef]`. Laws under test: determinism (no Date/UUID/random), stability
(an active lane keeps its physical voice across reconciles), first-rank-wins contention,
poly fallback on kind exhaustion, sampler/bioVoice → poly (documented v1),
`drumUnits/subUnits == 0` → all-poly (the flag-OFF shape). Zero consumers → behavior-frozen,
Linux CI green. **TDD: tests first.**

### S2-W2-2 — PURE map + device container: `DrumNoteMap` + `LaneDrumKitVoice`
*Files (3):*
- `Sources/Echoelmusic/Sequencer/DrumNoteMap.swift` (NEW, pure): MIDI pitch → pad
  (kick 35/36 · snare/clap 37–40 · hats 42/44/46 [44 = tighter damping] · else perc/tom)
  + per-pad `DrumSynthParams` preset + velocity→gain. Deterministic, total (every pitch maps).
- `Sources/Echoelmusic/Sequencer/LaneDrumKitVoice.swift` (NEW, `#if canImport(AVFoundation)`):
  4 `DrumSynthVoice` pads; `attach(to:)` (all 4, before start); `noteOn(pitch:velocity:)` →
  `configure` (only when the pad's cached params differ — avoids per-hit reconfigure) +
  `fire(gain:)`; `noteOff` = no-op (one-shots); `allNotesOff` = no-op documented;
  `setInsert(TrackFX)` → fan `configureInsertFX` over pads; lane gain/pan via the pads'
  `sourceNode` AVAudioMixing `volume`/`pan` (the B2-precedent engine path — control-plane only).
- `Tests/EchoelmusicTests/DrumNoteMapTests.swift` (NEW)

No new render code — reuses DrumSynthVoice's lock-free strike/config counters.
**audio-thread-reviewer: flag (voice-adjacent), expected pass.**

> **S2-W2-1 SHIPPED (4b962d1, APPROVE).** Review-Hinweise für die nächsten Scheiben:
> (a) `allocate` liefert ein Dictionary — ein Konsument, dessen ANWENDUNGS-Reihenfolge
> Nebenwirkungen hat (allNotesOff, Engine-Calls, Logging), MUSS über `keys.sorted()`
> iterieren (Dict-Iteration ist nondeterministisch). (b) Der Allocator garantiert NUR
> "gleiche Ranks rein ⇒ gleiche Bindings raus" + Append-Monotonie — KEINE
> Lane-Identitäts-Stabilität über Rank-Shifts; S2-W2-3 darf das allNotesOff-on-rebind
> deshalb nicht einsparen (refreshStructure flusht ohnehin alle Pumps bei Rank-Shift).
> (c) Wenn per-Kind-Kapazität > 1 kommt (§6): zuerst den `.drums(1)`-Index-Test ergänzen.

### S2-W2-3 — DEVICE: heterogeneous rack + `FeatureFlags.voiceKindRouting`
*Files (2):* `Sources/Echoelmusic/Sequencer/LaneVoiceRack.swift`,
`Sources/Echoelmusic/Core/FeatureFlags.swift`

- New flag `voiceKindRouting` (registration-domain default **OFF** — Release bit-identical;
  same pattern as `laneAUInstruments`).
- `attachAll()` additionally creates+attaches 1 `LaneDrumKitVoice` + 1 `SubBassVoice`
  **IFF the flag is ON** (still strictly before `audioEngine.start()`).
- Facade: `setKind(slot:kind:)` (drives `KindVoiceAllocator`; on a binding change,
  allNotesOff the previously bound physical voice), `noteOn(slot:pitch:velocity:)` /
  `noteOff(slot:pitch:)` routing. **Note-OFFs fan to ALL physical voices ever bindable to
  that slot** (poly slot + kit + sub — offs for never-started pitches are harmless; the
  H5b mid-take-flip law). Param routing: `setTranspose` → poly as today, sub = shift pitch
  control-side before enqueue, drums = ignored (documented: a kit is unpitched);
  `setDetune` → poly only; `apply(patch)` → poly only (documented no-op elsewhere);
  `setGain/setPan` → poly API / kit AVAudioMixing / sub `sourceNode.volume` (pan on the
  mono sub = documented no-op — subs are un-panned, pro-audio convention).
- Flag OFF ⇒ allocator gets `drumUnits: 0, subUnits: 0` ⇒ every call resolves to the
  existing poly path — bit-identical.
**audio-thread-reviewer: YES (attach-before-start + control→SPSC handoff).**

> **S2-W2-3 GEBAUT (89814a2, Reviews laufen).** Flag `voiceKindRouting` default OFF
> (absent-key-false, KEINE Registrierung — erst S2-W2-7). Fassade wie geplant; die
> Carries (a) keys.sorted()-Iteration und (b) allNotesOff-on-rebind sind implementiert,
> Gain-Kontrakt 0…2 + non-finite→0 erfüllt (Kit klemmt intern seit 0b3f6fa). Zusatz-
> Entscheid: Sub-Transpose wird control-seitig beim Enqueue gepitcht; ein Shift-WECHSEL
> bei sub-gebundenem Slot released die gehaltene Mono-Note (Off-Matching-Gesetz).
> Datei-Guard von LaneVoiceRack auf AVFoundation+Accelerate verbreitert (Kit-Typ).
> Offen fuer S2-W2-4/5: Lane-Sub bekommt noch KEIN setTuning(a4Hz:)-Mitlaufen —
> beim App-Wiring den Kammerton an rack.subs fannen (wie der Primary-Sub ihn erhaelt).

### S2-W2-4 — DEVICE: player `slotKindSink` + app wiring
*Files (2):* `Sources/Echoelmusic/Sequencer/TimelineRegionPlayer.swift`,
`Sources/Echoelmusic/EchoelmusicApp.swift`

- `slotKindSink: ((_ slot: Int, _ kind: LaneVoiceKind) -> Void)?` — fired at exactly the
  sites the sibling sinks fire: prime (`~:452-462`), window load (`~:518-523`), live merge
  (`~:558-561`), and reset to `.poly` on clear/silence/stop (`~:481`, `~:611`), sourced from
  `MultiRollFanout.voiceKind(forSlot:)`.
- App: wire `slotKindSink → laneVoiceRack.setKind`; note sink becomes
  AU-wins (unchanged H5b) else `laneVoiceRack.noteOn(slot:...)` facade; offs → AU + rack-all
  (replaces `voice(slot:)?.noteOn/Off`). Patch/transpose/detune/pan/gain sinks call the
  facade (which routes per bound kind).
**audio-thread-reviewer: YES. On-device smoke: drums lane hits, bass lane felt sub,
poly lanes unchanged, mid-take instrument switch leaves no stuck notes.**

> **S2-W2-4 FERTIG (9267e49 + Test b5010b8, 2×APPROVE).** slotKindSink an allen
> vier Sink-Sites (load/prime/clear-silence/stop); App routet ALLE Per-Slot-Sinks
> (Note/Patch/Transpose/Detune/Pan/Gain + setKind) über die Fassade. Ordering-Gesetz
> (Kind bindet VOR Patch/Noten) test-gepinnt. Flag-OFF bit-identisch bestätigt.
> Kammerton-Fan HIERHIN aufgeschoben (siehe unten). refreshMixer bewusst OHNE
> slotKindSink: Kind ist strukturell (refreshStructure→reload), kein Mixer-Merge-Feld.
>
> **S2-W2-5 ZUSATZ (aufgeschoben aus S2-W2-4):** LaneVoiceRack.setTuning(a4Hz:) an ALLE
> subs fannen, gerufen an den 3 subBass.setTuning-Sites in EchoelStudioView
> (~1984 session-restore, ~3732, ~4110) — sonst läuft der Lane-Sub bei A≠440 verstimmt.

### S2-W2-5 — DEVICE: fan the `.drums`/`.bass` bus inserts to the lane kind voices
*Files (2):* `Sources/Echoelmusic/Studio/EchoelStudioView.swift`,
`Sources/Echoelmusic/Sequencer/LaneVoiceRack.swift`

- `LaneVoiceRack.setDrumsInsert(_:)` → kit `setInsert`; `setBassInsert(_:)` → lane sub
  `setInsert`. No-op while unattached / flag OFF (S2-W1's `setInsert` stance).
- `setDrumsFX` (`:1550`) additionally calls `laneVoiceRack.setDrumsInsert(fx)`;
  `setBassFX` (`:1490`) additionally calls `laneVoiceRack.setBassInsert(fx)`; include the
  launch-restore site (same file `.task` restore, S2-W1 precedent — verify during impl).
Exact mirror of the S2-W1 melodic fan. **audio-thread-reviewer: light (control path).**

> **S2-W2-5 FERTIG (17e690e, 2×APPROVE, 4/4 grün).** setDrumsInsert/setBassInsert +
> setTuning(a4Hz:) an Kit/Sub; EchoelStudioView an setBassFX/setDrumsFX/Launch-Restore +
> allen 3 subBass.setTuning-Sites verdrahtet; Debug-Seams pinnen Delivery. Flag-OFF
> bit-identisch. Kammerton-Fan (aufgeschoben aus S2-W2-4) = ERLEDIGT. Projektweiter Audit
> 2026-07-16 bestätigt: Slices 5-6 = autonom flag-OFF; Slices 7-8 founder-gated (Geräte-
> Session-Checkliste scratchpads/FOUNDER_DEVICE_SESSION.md). Slice-7-Checkliste MERKE:
> Becken-freien Groove testen (4-Pad-Kit voiced GM-Becken als Toms); .drums-Bus ist GETEILT
> (BeatPlayer + alle Lane-Kits, ein Charakter) — Founder-Design-Bestätigung vor Slice 8.

### S2-W2-6 — DEVICE (riskiest): PRIMARY roll lane kind routing
*Files (2):* `Sources/Echoelmusic/Studio/PianoRollView.swift`,
`Sources/Echoelmusic/EchoelmusicApp.swift`

The pin flip is dishonest while the PRIMARY lane set to "EchoelDrums" still sounds poly.
- `PianoRollModel` gains `kindVoiceSink: ((NoteEvent) -> Void)?` (name TBD): when non-nil,
  `applyStep`'s starting/ending notes route to it INSTEAD of `outputVoice(for:)`, and the
  mono sub-DOUBLING reconcile is skipped (the kind voice IS the instrument — no doubling of
  a drum kit). Reuses the existing `suppressBuiltIn` discipline; MIDI/AU mirrors unchanged.
- App: at roll-region load (the `rollTransposeSink` precedent site), read the roll lane's
  `builtinInstrument?.voiceKind`; if `.drums`/`.subBass` (and flag ON) set the sink to the
  rack's kit/sub facade; else nil (today's path — bit-identical for poly).
**audio-thread-reviewer: YES. Fallback if device verify misbehaves: hold S2-W2-8
(gate: hold-for-founder) and document the primary exception in `fxBus` docs instead.**

### S2-W2-7 — Device verify + flag default ON
*Files (1):* `Sources/Echoelmusic/Core/FeatureFlags.swift` (+ a
`scratchpads/DEVICE_VERIFY_VOICEKIND_*.md` note, non-source).
Founder verify on device: drums lane = drums, bass lane = felt sub (octave-fold band),
poly untouched, launch silence preserved, Xcode CPU gauge < 30% while playing a
4-lane doc, no menu freeze (no new @Observable reads in any ancestor body — the facade is
control-plane only; **swiftui-render-safety check before merging any UI touch**).
Then flip `voiceKindRouting` registration default → ON.

### S2-W2-8 — PURE, LAST: the fxBus pin flip (the founder-ordered payoff)
*Files (2):* `Sources/Echoelmusic/Sequencer/TrackInstrument.swift`,
`Tests/EchoelmusicTests/TrackInstrumentTests.swift` — **same commit** (the test enforces
together-flip; the default-less switch forces explicit verdicts).
- `.drums` → `.drums` · `.breakLoop` → `.drums` (kind .drums) · `.subBass` → `.bass` ·
  `.sampler` → stays nil (poly fallback until §6 ships) · `.bioVoice` → stays nil.
- Rewrite the `fxBus` doc comment to the NEW engine truth (the current comment is the
  75e4899 correction — replace, don't append).
- Consequence (free): `LaneFXEditor`'s bus section (S2b) now appears for drum/bass lanes
  wherever it keys on `fxBus != nil` — inside the existing `ArrangeModal` item-sheet.
  **Root sheet chain untouched (zero new sheets anywhere in this plan).**

---

## 4. Test strategy (pure Linux core first)

1. **Linux CI (`swift test`, every slice):** `KindVoiceAllocatorTests` (determinism,
   stability, contention, fallback, zero-units), `DrumNoteMapTests` (total mapping,
   pad presets, velocity), `MultiRollFanout.voiceKind` cases (in the allocator test file or
   the existing fanout tests: nil instrument → .poly, breakLoop → .drums, out-of-range slot
   → .poly), `TrackInstrumentTests` pin flip (last slice). Existing suites stay green:
   `LaneVoiceKindTests`, LaneVoicePool/RackPlan/Fanout, `TempoStabilityTests`,
   `SequencerTests`.
2. **Xcode compile gate** (`xcode-compile-check.yml`) for every AVFoundation-guarded file
   (LaneDrumKitVoice, LaneVoiceRack, app wiring).
3. **On-device (founder):** S2-W2-4/6/7 smoke list above; mid-take instrument-switch
   stuck-note hunt; CPU/memory gauges vs. hard limits; flag OFF regression pass
   (must be indistinguishable from today).
4. **audio-thread-reviewer** flagged on slices 2 (light), 3, 4, 6 — but note: NO new render
   block is written anywhere in this plan; all handoff rides existing SPSC queues /
   atomic-width counters / AVAudioMixing.

## 5. Law compliance checklist
- Root sheet chain: **zero new modals**; the only UI consequence lands inside the existing
  `ArrangeModal` item-sheet enum (allowed pattern). ✓
- 10 Hz reads: none added; facade is control-plane, no view reads any new @Observable. ✓
- Audio thread: no locks/malloc/ObjC/GCD/IO added; attach-before-start preserved (fixed
  pre-attached pool, flag-gated); runtime switch = routing only. ✓
- EchoelValueField / flash 3 Hz: no new parameter UI in this plan. ✓
- Rausch triad: untouched. ✓ · DSP/ imports: no DSP/ file touched. ✓
- Persistence: NO new Codable fields (sampler's `sampleRef` deferred → will use
  `decodeIfPresent` when it ships); no document pruning. ✓
- Copy: brand instrument names only, no wellness/esoteric terms. ✓
- Claim only what ships: sampler/bioVoice pins stay nil; pin flip strictly after routing +
  device verify + flag default ON. ✓

## 6. Deferred (explicitly OUT of S2-W2 — logged, not lost)
- **Sampler kind (S2-W3):** a sampler LANE has no sample source field yet — routing it to an
  empty `SamplerVoice` would be honest silence but a worse experience than today's poly
  fallback. Needs `TimelineLane.sampleRef` (Codable, `decodeIfPresent`) + a pick-sample door
  as a new `ArrangeModal` case reusing `SampleBrowserView` (B5 precedent) + `.drums`-bus
  verdict for `.sampler`'s pin. Until then: allocator maps sampler → poly (documented).
- **bioVoice kind:** poly fallback; optionally flip that slot voice's
  `bioModulationEnabled = true` (honest "body modulates this lane") — **hold-for-founder**.
- **Per-kind capacities > 1** (2 drum lanes with 2 real kits): raise `drumUnits` only after
  on-device CPU numbers, same stance as the rack's capacity-4 comment.
- **Drum-pad editing per lane** (per-lane kit presets): rides `DrumSynthParams` later.

## 7. Council synthesis (fast gate)
Architect: rack-boundary bind keeps the rank contract sacred — proceed. DSP Purist: no new
render code, reuse tested lock-free voices — proceed. Vision-Keeper: "Spur = Instrument" is
the tracks-centric pivot's core promise — this IS the product bar. Shipper: 8 slices, each
green alone; pin flip last = no lying intermediate state. Skeptic (sharpest): slice 6
(primary roll) touches the most intertwined note path in the app — keep its fallback
(hold pin flip, document exception) explicitly cheap. User-Advocate: a drums lane finally
sounding like drums is the single most audible honesty fix available.
**Verdict: proceed, slice order as above; gate S2-W2-8 on S2-W2-7's founder device verify.**
