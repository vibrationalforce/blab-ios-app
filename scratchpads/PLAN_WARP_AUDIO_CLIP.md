# PLAN — Warp im Audio-Clip-Editor (Task #54)

**Founder (2026-07-16):** "Warp in den Audio Clip edits hatten wir doch auch schon geplant
mit neuster Technologie." — Audio clips conform to the project tempo (pitch-preserving
time-stretch), Ableton-style, inside the EXISTING audio clip editor.

**Status: investigation done (read-only). No code changed yet.**

---

## 1. What already exists (the founder is right — it WAS planned, half the machine is built)

| Piece | File | State |
|---|---|---|
| Pure tempo math (`nativeBPM`, `stretchRate` clamped 0.25…4.0, `guessBars` power-of-2 snap) | `Sources/Echoelmusic/Sequencer/TempoMatch.swift` | ✅ built + tested |
| Editor model with `warpEnabled` + `nativeBPM` (Codable, decode-safe) + `effectiveStretchRate(projectBPM:)` | `Sources/Echoelmusic/Sequencer/AudioClipRegion.swift` | ✅ built — but this model is the EDITOR's ephemeral `@State`; warp fields are **never persisted** to the timeline document |
| Sample-accurate warp placement plan (source frames → output frames → onset) | `Sources/Echoelmusic/Sequencer/WarpedClipPlan.swift` + `Tests/EchoelmusicTests/WarpedClipPlanTests.swift` | ✅ built + tested — **consumed by NOTHING** (tests only) |
| Import heuristic: bar-guess → implied native BPM | `Sources/Echoelmusic/Sequencer/AudioClipFactory.swift` (`guessBars`/`nativeBPM`) | ✅ built — native BPM is computed at import (`AudioClipView.addToTimeline` line ~223) then **discarded** (only used to size the region's bar span) |
| Timeline audio playback (per-lane `AVAudioPlayerNode` per format, `scheduleSegment` streaming) | `Sequencer/TimelineAudioSink.swift` + `AudioLanePlayer.swift` + `AudioRegionPlayback.swift` | ✅ live (A1) — header says it honestly: *"per-clip fades/warp from the audio editor are not consumed on the timeline yet (audit A5)"* |
| Audio clip editor UI (waveform + trim handles + EchoelValueFields + fades + gain) | `Studio/AudioClipView.swift` — opened via `ArrangeTimelineView.ArrangeModal.region(...)` (edit door) and `.lane(...)` (import door) | ✅ live — the modal slot for warp UI **already exists**, no new sheet needed |

**Gap in one sentence:** warp metadata is never persisted (`TimelineRegion` has no `warpEnabled`,
`Clip` has no `nativeBPM`), the timeline sink has no rate-capable node, and the editor shows no
warp controls. Everything below closes exactly that gap.

---

## 2. Technology decision ("neuste Technologie", honestly evaluated for iOS 18+)

### Correction of a common conflation
`AVAudioTimePitchAlgorithm` (`.spectral` / `.timeDomain` / `.varispeed`) is the algorithm selector
for **AVPlayerItem / AVAssetReaderAudioMixOutput / AVMutableAudioMix** — it does NOT exist on
`AVAudioUnitTimePitch`. The real-time engine node is `AVAudioUnitTimePitch`
(kAudioUnitSubType_NewTimePitch): `rate` 1/32…32, `pitch` in cents, `overlap`. It is Apple's
current, supported, pitch-preserving real-time stretcher — there is no newer public API as of
iOS 18/26 SDKs. Plans/claims must name the APIs correctly.

### Options

**A. Real-time `AVAudioUnitTimePitch` insert per audio lane (player → timePitch → masterMixer)** ← CHOSEN
- ✅ Live rate updates: tempo edits (`BodyTempoField`) and bio→tempo modulation change the rate as
  a control-plane property set — no re-render, no cache, no file I/O.
- ✅ Fits the existing streaming sink unchanged in spirit: still `scheduleSegment`, still no PCM
  buffer on the main actor, still attach-at-prime.
- ✅ Audio-thread safe: the AU does its own rendering inside the engine graph; we only set
  properties from `@MainActor` (same class of operation as `node.volume`/`node.pan` today).
- ⚠️ CPU: ~1–3% per stereo instance on modern A-chips; one instance per (lane × format-node).
  Bounded by lane count (~8). Mitigation below (bypass at rate 1.0).
- ⚠️ Latency: NewTimePitch adds processing latency (order of a few ms — device-verify). Constant
  per instance; first slice ACCEPTS it and measures; compensation via `auAudioUnit.latency`
  in scheduling is a documented follow-up if audible.
- ⚠️ Quality at extreme ratios below offline `.spectral` — irrelevant here: `TempoMatch.rateRange`
  already clamps to 0.25…4.0 and musical use is ~0.8…1.25.

**B. Offline pre-render** (AVAudioEngine `manualRenderingMode` + AVAudioUnitTimePitch, or
AVAssetReader + audioMix `.spectral`, cached per (mediaRef, nativeBPM, projectBPM))
- ✅ Best quality, zero runtime CPU.
- ❌ Cache invalidation is poison here: project tempo is LIVE-mutable (tempo field + bio→tempo
  ModulationEngine routing). Every tempo move = re-render + file I/O + a silent gap or stale
  audio. Disk growth per tempo value. Wrong first fit; keep as a future "freeze/bounce clip"
  feature, where it is the right tool.

**C. `AVAudioSequencer`** — time-scales MIDI, not audio media. Not applicable. Rejected.

**Decision:** A. Real-time `AVAudioUnitTimePitch` per lane-format node, rate from the already-tested
`TempoMatch.stretchRate`, with `auAudioUnit.shouldBypassEffect = true` whenever the effective rate
is exactly 1.0 (unwarped lanes stay CPU-free and as bit-clean as possible; bypass toggling is a
property set, NOT a graph mutation — attach-before-start law holds). Device-verify that bypass
toggling is glitch-free; fallback is rate=1.0 without bypass.

### Tempo detection reality (no fabrication)
There is **no beat-detection DSP in this repo** and no public Apple BPM-analysis API. First slice
uses what already ships: `TempoMatch.guessBars` length-snap (assume the clip spans 1/2/4/8 bars,
pick the least-stretch fit) to seed a **user-editable** Clip BPM, plus a Bars field
(`nativeBPM = bars × 4 × 60 / fileDuration`). Real onset-based tempo analysis (Accelerate
autocorrelation) is a separate research task — NOT claimed, NOT in this plan's slices.

---

## 3. Data model (Codable, decodeIfPresent, document-safe)

Two fields, split by what they describe:

1. **`Clip.nativeBPM: Double`** (`Sequencer/Clip.swift`) — a property of the MEDIA. Default `0`
   = unknown (never warps). Set at import from the existing `AudioClipFactory.nativeBPM(...)`
   guess; user-correctable in the editor. Decode: `(try? c.decode(...)) ?? 0`, re-clamped
   (0, or 20…400 like `AudioClipRegion.nativeBPMRange`). Older documents load with 0 →
   bit-identical behavior. Nothing pruned.
2. **`TimelineRegion.warpEnabled: Bool`** (`Sequencer/Timeline.swift`) — a property of the
   PLACEMENT. Default `false`. Decode: `?? false`. `split(atTick:)` / `merged(with:)` /
   front-trim copy it like `gain` (both halves of a split keep warp; merge requires equal
   warp state — check `canMerge`).

Effective rate (ONE pure function, the testable core):

```swift
// AudioRegionPlayback (pure, Foundation-only, Linux CI)
static func effectiveStretchRate(warpEnabled: Bool, clipNativeBPM: Double,
                                 projectBPM: Double) -> Double
// = TempoMatch.stretchRate(nativeBPM:masterBPM:) when warpEnabled && clipNativeBPM > 0
//   && projectBPM > 0, else exactly 1.0
```

Rate-aware mapping (extends the existing tested functions; `stretchRate: Double = 1.0` default
keeps every existing call site + test green):

```swift
filePositionSeconds(for:atTick:bpm:stretchRate:)  // media pos = offset + elapsedSong × rate
frameCount(for:fromTick:bpm:sampleRate:stretchRate:)  // source frames = songSeconds × rate × sr
```

`WarpedClipPlan` stays as-is (tested reference for the frame identities); the sink path uses the
`AudioRegionPlayback` extensions because `AudioLanePlayer` already calls them. Do not duplicate
maths beyond that — the new functions must agree with `WarpedClipPlan` (a cross-check test asserts
it).

---

## 4. Playback wiring (engine slice — audio-thread-reviewer flagged)

`TimelineAudioSink` (per lane):
- Per `FormatKey` node entry becomes `(player: AVAudioPlayerNode, timePitch: AVAudioUnitTimePitch)`.
- `ensureLoaded` attaches the CHAIN `player → timePitch → masterMixer` inside ONE
  `engine.withGraphPaused { }` (the existing safe re-wire primitive; needs a small
  `AudioEngine.attachPlayerChain(_:through:format:)` sibling of `attachPlayerNode`). By
  construction this happens at PRIME time (transport parked) — same law as today (PERF-01).
- New `AudioRegionSink` requirement with a default no-op extension (existing fakes in tests keep
  compiling): `func setRate(_ rate: Double)` → sets `timePitch.rate = Float(clamped 0.25…4)`,
  and `shouldBypassEffect = (rate == 1.0)`. Property sets only — never a graph mutation, never
  called from a render block. NOTHING in this feature touches the render thread.
- `play(url:fromSeconds:lengthSeconds:gain:)` gains a `sourceLengthSeconds` honesty: the
  coordinator now passes SOURCE-domain length (already × rate), sink behavior unchanged.

`AudioLanePlayer` (coordinator, Foundation-only, fully unit-tested via fake sink):
- `start(...)`: compute `rate = AudioRegionPlayback.effectiveStretchRate(...)` (needs the clip's
  `nativeBPM` — resolve via an injected `resolveNativeBPM: (UUID) -> Double`, sibling of
  `resolveURL`), call `sink.setRate(rate)` before `play`, and use the rate-aware
  `filePositionSeconds` / source-length maths so mid-region entry and the region-boundary stop
  stay sample-honest.
- `reconcileMix(...)` (the `.unchanged` path, ~transport-step cadence — NOT 10 Hz UI): if the
  active region's effective rate drifted from the applied rate (tempo edit / bio→tempo) by
  more than 2% (log-ratio), RE-START the region at the honest position (exact — reuses the
  unmute machinery); below that threshold `setRate` live and accept sub-2% boundary drift until
  the next onset (no stutter under continuous bio modulation). `appliedRate: [UUID: Double]`
  bookkeeping mirrors `appliedGain`/`appliedPan`.
- `prime(...)`: unchanged shape; preload attaches the chain per distinct format as today.

Hard laws honored: attach-before-start (chain attaches at prime, inside withGraphPaused);
no locks/malloc/file-I/O added to any render path (all control-plane `@MainActor`);
no SPSC change needed (this is the same control plane that already drives volume/pan).

## 5. UI (inside the EXISTING editor — zero new modal slots)

Surface: `AudioClipView`, reached today via `ArrangeTimelineView`'s ONE `.sheet(item:)` —
`ArrangeModal.region(...)` ("Edit" on a placed audio region) and `ArrangeModal.lane(...)`
(audio-lane import door). **The root EchoelStudioView sheet chain is untouched.**

New "Warp" group under `regionControls` (shown when a file is loaded):
- `Toggle("Warp")` — same style as the existing Loop toggle (Toggle is a switch, not a numeric
  parameter — allowed; parameter rule applies to numerics).
- `EchoelValueField(label: "Clip BPM", range: 20…400, decimals: 1)` — seeded from
  `clip.nativeBPM`, or the `AudioClipFactory.nativeBPM` guess when 0/unknown.
- `EchoelValueField(label: "Bars", range: 1…64, decimals: 0)` — editing Bars recomputes
  Clip BPM from the trimmed duration (`bars × 4 × 60 / duration`); the two fields are two views
  of one truth (BPM is stored).
- One static read-out line (no live churn): "×0.94 → 120 BPM" derived from current values at
  body-build time; the editor reads `beatPlayer.pattern.tempo` once per interaction, NOT a
  10 Hz live value — no high-frequency `@Observable` read enters this body (swiftui-render-safety).
- Commit on Done (edit door, follows the CLIP-4 "only a real edit writes" pattern):
  `timeline.setRegionWarp(id:enabled:)` (undo-history participating, like `setRegionGain`) +
  `clips.setNativeBPM(id:bpm:)`. Landing door: `addToTimeline` persists the (already computed,
  currently discarded) `native` into the new clip and `warpEnabled` into the placed region.
- Audition preview inside the editor plays UNWARPED in slice order below (honest label
  "Vorschau in Originaltempo" until S4 adds a preview timePitch to `AudioClipPlayer`).

Copy stays capability-honest ("Warp: passt den Clip ans Projekttempo an, Tonhöhe bleibt") —
no wellness/esoteric language. Optional later (same node, zero extra engine work): clip
pitch-shift in cents via `timePitch.pitch` — NOT in these slices, listed as follow-up only.

---

## 6. Atomic slices (Ralph Wiggum — one shippable point each, ≤3 source files)

**S1 — Pure core + persistence (Linux CI, test-first).**
Files: `Sequencer/Clip.swift` (+`nativeBPM`), `Sequencer/Timeline.swift`
(`TimelineRegion.warpEnabled` + split/merge/front-trim carry), `Sequencer/AudioRegionPlayback.swift`
(`effectiveStretchRate`, rate-aware `filePositionSeconds`/`frameCount`, defaults = 1.0).
Tests FIRST: `Tests/EchoelmusicTests/AudioWarpMathTests.swift` — sourceBPM×bars→rate table,
rate-1 identity (bit-length-identical to today), mid-region entry at rate ≠ 1, split/merge
warp carry, decode of a pre-warp document (fields absent → 0/false, nothing pruned),
cross-check agreement with `WarpedClipPlan`. Ships green with zero behavior change.

**S2 — Engine: rate-capable sink + coordinator (AUDIO-THREAD-REVIEWER FLAGGED).**
Files: `Sequencer/TimelineAudioSink.swift` (timePitch chain + `setRate` + bypass-at-1.0),
`Sequencer/AudioLanePlayer.swift` (resolveNativeBPM, rate in start/reconcile, 2% restart
threshold), `Audio/AudioEngine.swift` (`attachPlayerChain`). Tests: fake-sink coordinator tests
(rate passed at onset; tempo-drift restart above threshold, live setRate below; unwarped lane
never calls setRate ≠ 1). All regions still unwarped in real documents → device behavior
unchanged; device-verify prime/attach latency + bypass glitch before S3 exposes the toggle.

**S3 — UI door + write-back.**
Files: `Studio/AudioClipView.swift` (Warp group: toggle + Clip BPM + Bars EchoelValueFields +
derived read-out + seed/commit), `Core/TimelineStore.swift` (`setRegionWarp`, undoable),
`Core/ClipStore.swift` (`setNativeBPM`). `addToTimeline` stops discarding the computed native BPM.
Tests: store setters + undo; commit-only-on-real-edit (CLIP-4 guarantee extended to warp fields).
THIS is the founder-visible cycle → TestFlight/device evaluation of the whole feature.

**S4 — Polish (optional, after device verdict).**
Files: `Sequencer/AudioClipPlayer.swift` (audition timePitch so the editor preview warps too),
`Studio/ArrangeTimelineView.swift` ("W" badge on warped regions). Plus follow-up candidates,
each its own cycle: latency compensation via `auAudioUnit.latency`; clip pitch-shift field;
offline "freeze clip" bounce (option B, where it IS right).

## 7. Risks / open device questions
1. `shouldBypassEffect` toggle glitch-free mid-song? (fallback: always-processing rate 1.0).
2. NewTimePitch added latency audible against MIDI lanes? (measure; compensate in a follow-up).
3. CPU with 8 warped lanes on the oldest supported device (Adaptive Quality tier interplay).
4. Bio→tempo modulation cadence vs. the 2% restart threshold — tune on device, not blind.

## 8. REVIEW FINDINGS from S1 (3717d3b APPROVE) — MUST resolve in S2, BEFORE S3 exposes the toggle

**MEDIUM — split/trim media-offset identity breaks at rate ≠ 1 (latent, unreachable in S1).**
`TimelineRegion.split(at:bpm:)` and `trimmedStart(toTick:bpm:)` advance
`contentOffsetSeconds` by SONG-domain elapsed seconds — correct only at rate 1.0.
Once S2 wires playback, splitting a warped (rate 1.25) region makes the second
half repeat ~20% of already-played media (offset should advance by
`songSeconds × rate`). `abuts()` uses the same song-domain expectation, so
split/join stay internally consistent — but the persisted offset is wrong for
playback. DECIDE in S2 (explicitly, not by accident):
  (a) scale the offset delta by the effective rate at EDIT time — requires
      passing rate (clip nativeBPM + project BPM) into split/trim; or
  (b) define `contentOffsetSeconds` as SONG-domain for warped regions and
      convert (`× rate`) at schedule time in the player — no edit-math change,
      one conversion point, but a domain that depends on a flag.
Leaning (a): keeps the field's media-domain meaning unconditional; the split/trim
call sites (TimelineStore) already receive `bpm` and can resolve the clip.
Add the S2 test: split a warped region mid-play window → second piece's media
continuity (no repeat/gap) at rate 1.25.

**LOW — rounding identity `frameCount` vs `WarpedClipPlan` can differ ±1 frame at
non-exact tempi** (one-step vs two-step rounding). Schedule-boundary only; add a
tolerance property test or comment in S2 when the sink consumes both.
