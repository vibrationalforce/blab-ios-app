# PLAN — Natural Sound · Loops that make sense · DAW-usable exports

Founder ask (2026-07-04): "Es ist enorm wichtig, dass die Musik natürlich klingt (echte
Instrumente + klassische Synths) und dass die Loops von Anfang an Sinn ergeben — wenn ich
einen 8- oder 16-Takt-Loop speichere, dass ich damit in der DAW vernünftig weiterarbeiten
kann. Deep Audit + Deep Research, dann vermeide Slop/Issues/Fehler/Ungenauigkeiten."

Method: 3 parallel code-audits (realism · loop-coherence · DAW-export) + web research on
synth realism + SMF/DAW loop standards. Findings below are CONFIRMED against the actual code.

---

## A · SOUND REALISM (EchoelDDSP + voices)

The additive engine is genuinely good (inharmonicity, analog drift, onset chiff, click-safe
attack, unison, soft-limit). What breaks "real instrument / classic synth":

- **A1 [CONFIRMED, FIXED 79.55]** `EchoelDDSP.applyCurve` `.exponential` was CONVEX → decay/
  release hung at peak then dropped abruptly ("hang-then-cut"). Corrected to concave
  `(1-exp(-6.9p))/(1-exp(-6.9))` (proper −60 dB decay). Attack unaffected (uses smoothstep).
- **A2 [CONFIRMED]** `EchoelSVFilter` cutoff hard-clamped to SR/6 = 8 kHz → no voice passes
  "air"; bright patches can't open. Fix: ZDF/TPT SVF stable to Nyquist, remove clamp.
- **A3 [CONFIRMED]** Every factory patch's `reverbMix/reverbDecay` is DEAD (convolution off);
  FXChain reverb off by default → instrument is bone-dry, "in a box". Fix: route patch
  reverbMix → algorithmic FXChain reverb on apply; default on for melodic voices.
- **A4 [GAP]** No filter envelope (ADSR→cutoff+amount) → the classic analog filter-sweep is
  impossible per patch. Add filter-EG fields to SynthPatch + voice.
- **A5 [CONFIRMED]** Synth drums (modal bank) have no pitch-envelope, no click transient, no
  noise excitation → kick = "membrane boop", snare/hat = tonal taps. Only samples convince.
- **A6 [CONFIRMED, perf]** `EchoelModalBank.excite()` recomputes mode freqs/weights on the
  AUDIO THREAD per strike (pow/sin ×64). Precompute on config-change only.
- **A7 [GAP]** No FM, no band-limited subtractive osc (saw/square/PWM/sync), no per-note sub.
- **A8 [slop]** bio-modulation OVERWRITES patch harmonicity/brightness/noise/reverb (collapses
  character). Should modulate RELATIVE to patch.

## B · LOOP MUSICAL SENSE (BioComposer + arrangement)

One bar is crafted well; the MULTI-bar loop + cadence degrade to "same vamp + new random tune
each bar", and the live path throws away genre tempo + drums:

- **B1 [CONFIRMED, biggest]** `EchoelStudioView.generate()` builds N bars sharing structureSeed
  but a NEW per-bar melody seed → 8 bars = same chords × 8 UNRELATED melodies. No theme/motif
  recurrence. Fix: draw motif cell from structureSeed (recurs), vary only answer/ornament;
  or A-A-A-B form / call-and-response (odd bar reuses prev bar).
- **B2 [CONFIRMED]** Whole progression crammed into EACH bar (≈4 chords/bar), repeated per bar
  → no multi-bar harmonic arc. Fix: one/two chords per bar across barCount, turnaround only
  on the final bar.
- **B3 [CONFIRMED]** "V→i turnaround" forces diatonic degree-4 = a MINOR v in minor modes (no
  leading tone) → never actually cadences. Fix: raise the third (borrow leading tone).
- **B4 [CONFIRMED]** Live path hard-codes `.flowFree` + octave-folds tempo to 50–130 → every
  genre plays at resting-heart tempo (Punk/Trap/Psy impossible). Fix: clamp body tempo INTO
  style.tempoRange.
- **B5 [CONFIRMED]** `generate()` SILENCES all drums for every genre (even Trap/Dub) → genre's
  defining rhythm missing. Fix: load composition.drumSteps for beat-driven genres.
- **B6 [minor]** "voice-leading" = whole-octave block transposition (not real voice-leading).
- **B7 [gap]** Lead = pure chord-tone arpeggio, no passing tones, phrase never lands on tonic.
- **B9 [minor]** Progression random-rotated → loop may not start on the tonic.

## C · DAW-USABLE EXPORT (the explicit ask — most broken)

- **C1 [CONFIRMED, CRITICAL]** MIDI export is ALWAYS 1 BAR. `exportMIDI` sends `pianoRoll.notes`
  (only bar 0; the N bars live in private arrangementBars, cycled) + 16-step pattern. An 8/16-
  bar selection → a 1-bar `.mid`. Founder's core ask unmet. Asymmetric with WAV (N bars).
- **C2 [CONFIRMED]** `LoopCutter.tile(...)` (the bar-tiling engine, tested) is DEAD CODE — never
  called. It's exactly the transform C1 needs.
- **C3 [CONFIRMED]** MIDI file has NO time-signature (FF 58), NO key-signature (FF 59), NO track
  names (FF 03). Key ("Tonart soll mit drin") is lost; bar anchor relies on DAW 4/4 default.
- **C4 [CONFIRMED]** Drum accents flattened (single global velocity; accents grid not passed).
- **C5 [CONFIRMED]** No end-of-region anchor: EOT at last note-off → clip shorter than N bars →
  won't loop seamlessly. Need EOT at exactly N*4 quarters.
- **C6 [CONFIRMED]** WAV export = N bars + 0.4 s tail, not trimmed → overhangs the grid, won't
  loop. Fix: keep decay tail while capturing, trim written file to loopSamples(bars).
- **C7 [CONFIRMED]** Retroactive "keep last" WAV not bar-aligned → arbitrary-phase loop (seam
  click). Snap capture window to last downbeat.
- **C8 [gap]** No embedded tempo/loop metadata (ACID/bext) → no auto-warp. Low priority.
- **PPQ:** exporter downgrades 480→96 PPQ (truncates sub-step). Set 480, export Note.startTick.
- **Tempo-during-glide:** export can capture a transitional BPM; settle tempo before export.
- **Naming:** MIDI filename omits _<Genre> (WAV has it).

---

## SEQUENCED ROADMAP (one focused cycle each; CI/tests where deterministic)

1. **79.55 — A1 envelope curve** (DONE, shipping). Natural note tails. Ears A/B.
2. **79.56 — C DAW export: N-bar + anchors** (C1,C2,C3,C5,C4,PPQ,naming). Wire LoopCutter /
   flatten arrangement; add time-sig/key-sig/track-name meta + EOT anchor; PPQ 480; accents;
   genre in name. EXTEND MIDITests (N-bar length, meta present, EOT tick) → CI verifies. THE
   founder-explicit fix.
3. **79.57 — B4+B5 genre tempo + drums** in the live path (clamp into tempoRange, load drums
   for beat-driven genres). Loops finally sound like their genre.
4. **79.58 — B1+B2+B3 loop form + real cadence** (motif recurrence across bars, one chord/bar
   arc, real dominant). Biggest "makes sense from bar 1" win. Composer tests.
5. **79.59 — A3 real space** (patch reverbMix → FXChain reverb, default on for melodic).
6. **79.60 — A2+A4 Nyquist-stable filter + filter EG** (air + classic filter sweep).
7. **79.61 — A5+A6 synth-drum realism** (pitch-env + noise transient; move mode-recompute off
   audio thread).
8. Later: C6/C7 WAV bar-align + trim; A7 FM/subtractive; A8 bio-relative modulation.

Gate each audio-thread change through dsp-reviewer/audio-thread-reviewer; Council for the
filter replacement (A2) and any default-on reverb (A3, CPU). Verify CI green every build.
