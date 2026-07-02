# PLAN — Professionalize Music + Visuals (founder: "wirkt unprofessionell… alles aufräumen und stabil wieder zusammensetzen")

Date: 2026-07-02 · Branch: claude/piano-roll-clip-view-wozlie
Direction (decided, reconciles the logged Cousto/physical-light decision with the
"no slop" goal): **keep the science, make the RENDER professional.** No big-bang rewrite
(Council: black-screen `.sheet` limit + 10 Hz freeze + "5 oscillations/0 breadth" history).
One compile-gated cycle at a time.

## Evidence (measured, not vibes)
- **Music:** clip LRA = **1.7 LU** (pros 5–12+), −11.5 LUFS. → dynamically FLAT: the app renders
  a single **16-step / 1-bar loop** (`BioComposer.stepCount = 16`) that repeats with tiny
  variation. Per-note arcs exist; there is **no section-level arc** (intro/build/break). That
  monotony is the "unprofessional" tell, more than the sounds.
- **Visuals (frames):** every look throws the **full spectrum at ~full saturation**
  (`toneColour`/`wavelengthToRGB` maps each harmonic to its own spectral hue → rainbow rings /
  rainbow mesh / RGB bars) with **thin aliased lines** and plain gaussian-blur "depth". Neon
  rainbow + crude line craft = the #1 amateur signifier.

## Hard constraint (drives sequencing)
- The visual looks are an **inline Metal shader** in `MetalBioView` (`makeLibrary(source:)`),
  compiled at **runtime** → a shader error is **NOT caught by `xcode-compile-check`**; it
  crashes on device. And this sandbox has **no audio playback / no device / no Metal output**.
- ∴ **Pure-Swift + CI + unit-tested** changes are safe to ship blind. **Audio-feel and Metal
  changes require a device/ear check** → those cycles ship, then wait for founder verification.

## Music track (M) — dynamics + arrangement
- **M1 (pure, testable) — bar-internal dynamic contour.** Deepen + shape the per-bar velocity
  envelope so even a looping bar breathes (musical crescendo/relax), widen the velocity range.
  Tests assert increased dynamic spread. Ships blind (reversible).
- **M2 (architectural) — multi-bar arrangement.** The real LRA fix: generate an N-bar phrase
  (e.g. 4–8 bars) with section dynamics (intro → build → main → break) via an arrangement
  envelope in `BioComposer` (+ playback support). Pure kernel = unit-testable; wire to
  PatternEngine/PianoRoll carefully (one cycle). Founder ear-check.
- **M3 — mix polish.** Per-genre bus levels / gentle bus glue so parts sit (needs ear-check).

## Visual track (V) — grade + render craft (device-verified cycles)
- **V1 — palette DISCIPLINE (grade).** Keep tone→wavelength science, but tame default
  saturation + add a value/contrast curve + slight hue cohesion so it reads GRADED, not neon.
  NOTE: changes the logged "physical-colour default" → founder confirms on device.
- **V2 — render craft.** Anti-alias the line looks (smoothstep SDFs), add a real bloom pass +
  fine film grain + vignette so it reads premium, not flat. Runtime-Metal → device-verify.
- **V3 — legible bio-reactivity.** Make the body visibly DRIVE the visual (pulse→bloom beat,
  coherence→palette focus) so it's "your body", not a generic visualizer.

## Sequencing
1. **M1** now (pure/tested, safe). 2. **V1** (device-verified) after founder confirms the grade
   direction. 3. **M2** (multi-bar arrangement). 4. **V2/V3**, **M3**. Each its own commit +
   compile gate; audio/visual cycles gated on a founder device/ear check before the next.

## Not doing
- No root rewrite. No blind inline-Metal edits (uncaught by CI). No abandoning the scientific
  colour model (founder's logged decision) — we GRADE it, we don't replace it.
