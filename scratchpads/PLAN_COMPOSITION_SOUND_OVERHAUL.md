# PLAN — Composition & Sound Overhaul (biofeedback-coherent, science-grounded)

Founder brief (2026-06-22): Rework compositions of ALL styles toward health/biofeedback-
**coherent** parameters (HeartMath / HRV resonance, newest scientific validation). Far MORE
composition techniques than just styles/character. Sound currently feels **rudimentary** (tones
+ sound quality) — must be avoided. All keys / tone systems complete, stable, high-quality,
brand-consistent instruments. "Set the best music scientists + developers of the world on it."

This plan synthesizes two expert passes: (A) a full code audit of the composition+sound stack,
and (B) a peer-reviewed science brief on HRV-coherence music. Cited sources live in the science
brief summary below. Execute in verified slices (compile-green per commit, TDD where logic).

---

## THE SCIENCE (validated levers — build on these, debunk the rest)

- **Resonance breathing ~0.1 Hz (≈6 br/min, RF range 4.5–6.5)** is the single strongest,
  best-replicated lever for coherence (Lehrer/Gevirtz; Nature 1.8M-session study: modal
  coherence freq = 0.10 Hz). Music's #1 job = entrain breath to RF. Slightly longer exhale.
- **Coherence = high-amplitude NARROW-BAND LF HRV peak (0.04–0.15 Hz, ~0.1 Hz).** HeartMath
  "coherence ratio" = power in ~0.03 Hz window around peak ÷ total. Score transparently.
- **Tempo→autonomic (dose-response):** slow 60–80 BPM = parasympathetic; >100–120 = sympathetic.
  Entrainment sweet spot ≈ resting HR 65–80. Two-clock design: **breath clock 0.1 Hz** +
  **pulse clock 60–80 BPM integer-locked to it**.
- **Syncopation = inverted-U** (medium = most pleasurable); for calm sit low-to-medium, reduce as
  coherence rises (Witek 2014).
- **Consonance/roughness→valence/tension** (robust). Slow harmonic rhythm + gentle tension cycles
  PHASE-LOCKED to breath (inhale→mild tension, exhale→resolve). As coherence rises → converge to
  consonance (↓roughness, ↓density, ↓brightness).
- **Melody:** phrase = one breath cycle (inhale rise / exhale fall). Moderate entropy: mostly
  stepwise + occasional well-prepared surprise as reward (ITPRA/Huron; Salimpoor dopamine).
- **Timbre (McAdams):** two dominant dims = **spectral centroid (brightness)** and **log attack
  time**. Calm = low centroid + slow attack + low roughness + evolving texture + clean reverb.
  "Professional vs thin" = detune/unison + slow filter/LFO motion + layered registers + width +
  per-note velocity/timbre variation + humanized timing. (audit: patches have noiseLevel:0, no
  unison/detune by default, static spectra → THAT is the "rudimentary" cause.)
- **PSEUDOSCIENCE — never surface:** Solfeggio (528 Hz "DNA repair" etc.), healing/chakra
  frequencies, Tesla 3-6-9, binaural "cellular" claims. (Brand rule already in CLAUDE.md.)
- **Honesty:** HRV-BF effect sizes are MEDIUM at best. Copy = "supports self-regulation /
  self-observation", never medical/therapeutic.

### Bio→Music mapping table (target directions; [V]=validated, [I]=grounded inference)
| Bio | → Musical param | Direction/target | Flag |
|---|---|---|---|
| Breath rate | breath clock / phrase length | pace swell at user RF ~0.1 Hz (10 s); lead slightly slower to coax down | V |
| Breath phase | contour, dynamics, filter, harmonic tension | inhale→rise+mild tension+cresc; exhale→fall+resolve+decresc | I |
| Breath depth | layer count / reverb / dynamic range | deeper → fuller arrangement (reward) | I |
| Heart rate | pulse-clock tempo (locked to breath clock) | ≈HR clamped 60–80; if HR high set pulse BELOW HR to pull down | V |
| Coherence | consonance, roughness, syncopation, density, brightness | ↑coh → ↑consonance ↓rough ↓sync ↓density ↓centroid (settle/reward); ↓coh → gentle re-engage | I |
| HRV/RMSSD | brightness, attack time, texture motion | ↑HRV → calmer palette (↓bright, slower attack, sparser) | V |
| LF/HF | spectral tilt / register | ↑LF/HF (sympathetic) → darker tilt, lower register | I |
| Coherence trend Δ | tension-curve dir, motif dev, layer add/remove | rising→resolve+thin+reward; stalling→small well-prepared novelty | I |

**Master loop = gentle SERVO, not 1:1 mirror.** Breath pacer leads at fixed RF; tempo/harmony/
timbre adjust SLOWLY (smoothing/hysteresis 5–15 s, never per-beat). Rising coherence → converge.
Stalling → inject minimal novelty, not complexity.

---

## IST-STAND (audit highlights, file:line in audit)

- **BioComposer** (`Sequencer/BioComposer.swift`): bio→{calm,vagal,energy,arousal,busy}; drives
  density+velocity+drums. Has: voice-leading (octave-shift), seeded progressions, phrase arc,
  ornamentation, mood blend (8 dims). MISSING: time-evolving tension curve, motif development,
  call-response, counterpoint, key modulation, song form, breath-clock, coherence servo.
- **MusicStyle** (22 genres): 2 beat-driven (hand-shaped), ~18 preset progression+patch+FX, 2
  ambient. Shallow depth; bio only modulates density/velocity. No sub-genre/orchestration.
- **MusicalKey**: 10 scales × 12 roots complete, no gaps. No microtonal-within-diatonic, no
  modulation/secondary dominants.
- **MicrotonalTuning**: 16 systems (4 ET, 3 JI, 6 world, 1 xen). No user-defined, no adaptive JI.
- **EchoelDDSP/Poly**: rich engine (64 partials, 65-band noise, 8 spectral shapes, SVF+LFO,
  morphing, timbre transfer, vibrato) but UNDERUSED: **all genre patches noiseLevel:0**, static
  spectral envelope (no time-evolving), no per-note voice variation, vibrato often 0, convolution
  reverb disabled (thread race) → FX-chain Freeverb only. THIS is why it sounds thin.
- **Bio→sound**: coherence→harmonicity, HRV→brightness, HR→vibrato exist in mapping comments but
  the COMPOSER side is shallow; no breath-clock, no LF/HF, no closed loop.

---

## ROADMAP (phased slices — each compile-green; TDD on logic)

### PHASE 1 — Coherence core (brand spine; founder's lead)
1. **Breath clock at resonance.** Default pacer 6/min (5.5 in / 4.5 out); optional RF-finder
   sweep (4–7/min) storing per-user RF. Expose `breathClockHz` on the bio frame. (BreathPacer*)
2. **Coherence servo in BioComposer.** Smoothed (5–15 s hysteresis) coherence/HRV → consonance↑,
   roughness↓, density↓, syncopation↓, brightness↓ as coherence rises; gentle re-engage when it
   stalls. Replace the shallow busy/arousal density with the validated table above. TDD.
3. **Two-clock tempo.** Pulse 60–80 BPM integer-locked to the breath clock; if HR high, pulse set
   BELOW HR (entrainment pull). Phrase/bar boundaries phase-locked to breath.
4. **Breath-phase phrasing.** Inhale→rising contour + mild harmonic tension + cresc + filter open;
   exhale→fall + resolve to tonic + decresc. Across ALL styles, not just ambient.

### PHASE 2 — Sound quality (kill "rudimentär")
5. **Richness defaults** for every genre patch: subtle unison/detune (few cents), slow filter/LFO
   motion, low roughness, layered registers (sub+body+air), tasteful reverb, stereo width.
6. **Per-note humanization in the composer** (micro-timing, velocity + timbre variation,
   round-robin-ish) so repeats aren't machine-gun identical.
7. **Time-evolving timbre** (attack-bright→sustain-darker; envelope-tracked filter) + use the
   noise bank for body/air per patch.
8. **Brand-consistent instrument palette**: a curated, named set of high-quality voices reused
   across genres (sub, pad, lead, pluck, bell, keys) so identity is consistent.

### PHASE 3 — Composition techniques (more than styles/character)
9. Motif development (transpose/invert/retrograde/augment/sequence/fragment).
10. Tension curve = time-evolving arc mapped to coherence trajectory.
11. Call & response (antiphony) split across inhale/exhale.
12. Harmonic rhythm as a first-class bio-mapped lever; ostinato/pedal anchors for calm.
13. Counterpoint / secondary voices; arrangement layering (additive/subtractive by layer count).
14. Optional key modulation / borrowed chords / secondary dominants.

### PHASE 4 — Completeness & systems
15. Tone-system completeness: adaptive JI on held notes, user-defined tunings, more rāga/world.
16. Microtonal-within-diatonic; ensure all 12 roots × all scales × all tunings exercised + tested.
17. (Stretch) closed-loop: measure post-generation bio shift; reward rising coherence.

---

## GUARDRAILS
- Protected Rausch triad untouched (BioEventGraph/HilbertSensorMapper/BioSignalDeconvolver).
- Audio-thread rules absolute; any tap/render change → audio-thread-reviewer before ship.
- `EchoelValueField` for any new parameter UI. No wellness/esoteric/overclaim copy.
- Each slice: compile-green gate + tests; one coherent change per commit; deploy via `.deploy/release`.

## STATUS (2026-06-22)
- [x] Audit + science brief (this plan)
- [x] **Phase 1 — coherence core COMPLETE:**
  - [x] Breath clock @ resonance (already shipped: BreathPattern.resonance 4in/6out = 6/min)
  - [x] Coherence-convergence density servo (BioComposer.musicalState; v10.42.0)
  - [x] Two-clock tempo entrainment (Flow pulse → 72 BPM as coherence rises; v10.43.0)
  - [x] Consonance convergence (effectiveTension → 40% at full coherence; v10.44.0)
- [x] **Phase 2 — sound, started:**
  - [x] Gentle default unison 2-voice/~7¢ (v10.43.0)
  - [x] Live per-note velocity humanization (v10.44.0)
  - [ ] NEXT: time-evolving timbre (bright attack→darker sustain; envelope-tracked filter)
  - [ ] Use the noise bank for body/air per patch (patches are all noiseLevel:0)
  - [ ] Brand-consistent named instrument palette
- [~] **Phase 3 — composition techniques (begun):**
  - [x] Coherence-aware groove sparsity (beat settles with the body; v10.45.0)
  - [x] (found already present) breath-phase contour bias in harmonic lead
  - [ ] motif development, tension arc, call&response, harmonic-rhythm lever,
        counterpoint, arrangement layering
- [ ] **Phase 4 — completeness** (adaptive JI, user tunings, all roots×scales×tunings tested)

All Phase-1/2 slices: pure helpers + unit tests in BioComposerTests; compile+CI green;
shipped v10.42.0→v10.44.0 via `.deploy/release` push-trigger (tokenless, autonomous).
