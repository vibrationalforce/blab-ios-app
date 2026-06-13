# PLAN — Synthesis Expansion (Echoel)

> Status: PLANNED. Do NOT build until the user confirms the launch-fix build
> (233ff4a) is audible. User directive 2026-06-13: "erst hören, dann entscheiden."

User wants the generated sound to go from "thin/digital" to genuinely
beautiful, professional, musical — via richer synthesis:

1. **Acoustic instruments** (physical modeling)
2. **Multiple synthesis models** (selectable per sound)
3. **Unison / detune per voice** in EchoelDDSP (analog movement)
4. **Fuller chord voicings** (BioComposer)

---

## What already exists (reuse, don't rebuild)

- `EchoelDDSP` — 64-partial additive harmonic+noise synth (the current voice).
- `EchoelPolyDDSP` — 6-voice pool, stealing, stereo pan, tanh soft-limit.
- `EchoelModalBank` — **physical modeling already present**: materials
  (drum/bell/string/…), params stiffness/damping/size/strikePosition/brightness,
  `excite(velocity:position:)`. → the basis for "acoustic instruments".
- `EchoelCellular` — cellular-automata texture (FX/experimental timbre).
- `EchoelFXChain` — filter → saturation (new) → chorus → … → limiter.

So three synthesis engines already exist: **additive (DDSP), modal (physical),
cellular**. The expansion is mostly *wiring + voicing*, not new DSP from scratch.

---

## Workstream A — Unison / detune in EchoelDDSP (cheapest, biggest "analog" win)

Add per-voice unison: render N (2–3) slightly detuned copies of the partial
stack, hard-panned a little for width. Detune ±(5–12) cents + tiny phase
offset → the partials beat against each other = thick, moving, analog.

- In `EchoelDDSP.render`: add `unisonCount` + `unisonDetuneCents`; inner loop
  sums `unisonCount` detuned copies (scale amplitude by 1/sqrt(unisonCount)).
- Audio-thread safe (pre-allocated, no alloc). Profile CPU: 6 voices × 64
  partials × 2–3 unison — may need to cap harmonics or voices adaptively.
- Expose in `SynthPatch` (Codable) + PatchEditorView "Unison" section.

## Workstream B — Selectable synthesis model per sound

`enum SynthEngine { case additive, modal, cellular }` on `SynthPatch`.
`PolySynthVoice` routes notes to the chosen engine (DDSP pool / modal bank /
cellular). Genre patches pick a default engine (e.g. esoteric→additive pad,
"acoustic"→modal string/bell). UI: engine picker at top of Sound Design.

## Workstream C — Acoustic instrument presets (modal)

Curate modal presets: Plucked String, Struck Bell, Marimba, Glass, Tine EP.
Wrap `EchoelModalBank` in a `ModalSynthVoice` (mirror PolySynthVoice pattern:
@MainActor @Observable, AVAudioSourceNode, hasEverSounded gate, attach/start).

## Workstream D — Fuller chord voicings (BioComposer)

In `BioComposer.compose` melodic/harmonic path: extend triads to 7th/9th, add
octave doubling + a bass root an octave below, spread voicing across the
register (drop-2). Keep it in-scale + seeded/deterministic (tests stay green).

---

## Sequencing (one workstream per commit, build/test green each step)

1. D — fuller voicings (pure value logic, fully unit-testable, no DSP risk).
2. A — unison/detune (audio-thread review, CPU profile).
3. C — ModalSynthVoice (acoustic presets) — audio-thread review.
4. B — engine picker wiring (UI + routing).

## Verification
- Audio-thread-reviewer over any new render block (A, C).
- Concurrency-reviewer over new @Observable voices.
- swift build / test green; iOS compile-check via build_only=true before deploy.
- On-device: play a chord (hear unison thickness), switch engine (additive →
  modal acoustic), generate a loop (fuller voicing). Ship per workstream.
