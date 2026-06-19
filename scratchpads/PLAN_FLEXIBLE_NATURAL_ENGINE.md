# Plan — Flexible, Natural Voice: Excitation × Resonator

Founder directive (2026-06-19): "Überarbeite die gesamte Engine und das Interface.
Möglichst flexibel, alle Sounds erzeugbar, möglichst natürlich klingend."

## Architecture decision
Adopt **EXCITATION → RESONATOR** as the synthesis-flexibility model (how real
instruments work: struck/plucked/bowed/blown excitation drives a resonant body).
**Reuse, don't rewrite** — the repo already has the resonator (EchoelModalBank, used
only for drums) + additive (EchoelDDSP) + noise/formant + filter. No sample libraries
(keeps the zero-heavy-dependency identity). Protected Rausch triad untouched.

## Honest scope
- ACHIEVABLE incrementally: convincingly natural, infinitely tweakable physically-
  modeled instruments (pluck/bow/blow/strike × modal/additive/formant).
- NOT promised: sample-accurate emulations (need sample libs); convolution bodies
  (path gated off for a thread race — separate hardening); waveguide PM (large).
- "Any sound" = plausible/expressive/physical, NOT "any recorded instrument".

## Staged roadmap (biggest naturalness win / least risk first)
- **Stage 1 (SHIPPED v10.32.0):** expose existing timbre-transfer instrument spectra
  (violin/flute/trumpet/cello/clarinet/oboe) as Characters. Pure additive, no new DSP,
  no new thread crossing. Files: SynthPatch (timbreProfile/timbreBlend + apply + 6
  factory chars). instrumentProfile()/loadTimbreProfile() already existed, were just
  unreachable from UI.
- **Stage 2:** pitched MODAL resonator as a selectable Character — per-voice
  EchoelModalBank in EchoelPolyDDSP, resonatorKind atomic mirror, render the selected
  engine in renderStereo. Bell/bar/plate/string/glass/gong, polyphonic + pitch-tracked.
- **Stage 3:** excitation→resonator coupling — add external audio-rate excitation input
  to EchoelModalBank (exciteSample / buffer sum before decay loop); implement the
  already-declared ExcitationType (impulse/pluck/bow/blow/noise). The one real new DSP.
  dsp-reviewer pass required.
- **Stage 4:** additive↔modal crossfade per voice (resonatorBlend). Watch <30% CPU
  (two engines/voice) — cap blended polyphony.
- **Stage 5:** UI — collapsed "Sound engine" group in Sound&texture (Resonator picker
  Additive/Modal/Hybrid + Material/Damping/Stiffness/Strike-pos/Size + Excitation +
  Hardness), all scrubbable EchoelValueFields, no new tab. Character picker stays the
  front door; Swell↔Strike macro stays global (composes: macro over modal = mallet vs bowed).
- **Stage 6 (optional):** bio mappings for new dims (coherence→excitation hardness,
  HRV→modal damping via applyBioReactive, breath→continuous excitation).

## Audio-thread rules for every stage
New params reach audio via the existing patchCommands SPSC queue OR atomic-width
nonisolated(unsafe) mirrors (a4Hz idiom). NEVER mutate a control-thread Swift array the
render reads (= the convolution-reverb crash / first-note crash). Pre-allocate modal
banks + scratch in init. Keep build green (build-guard + macOS CI) and app playable each stage.

## Key file map
- EchoelDDSP.swift: additive engine; instrumentProfile L998, loadTimbreProfile L982,
  InstrumentTimbre L1060; EchoelPolyDDSP L1138 (renderStereo L1385 = the mixer seam).
- EchoelModalBank.swift: resonator; excite L428, setContinuousExcitation L479 (bow/breath
  exists), materials L89, ExcitationType L101 (declared, unused).
- SynthPatch.swift: patch model + factory characters + case-insensitive match().
- EchoelStudioView.swift: Sound&texture panel, presetRow, Swell↔Strike macro L476.
