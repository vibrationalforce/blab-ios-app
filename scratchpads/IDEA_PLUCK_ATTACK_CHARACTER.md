# Idea — "SomaChord pluck" as a deliberate attack character

**Source:** Founder, 2026-06-18 (after device testing 10.28/10.29).
**Quote (paraphrased):** The clicking feels a bit like lying on a SomaChord with the
strings being plucked — that could become a NEW characteristic in the overall sound.
When keys/tonalities change, the attack / Einschwingphase (onset) plays a big role.

## The reframe
Distinguish two things that both sound "clicky":

1. **Defect transients** (REMOVED, correctly): voice-stealing discontinuities, phase
   jumps, retrigger steps. Random, non-musical, not pitch-locked. Fixed this session
   (12-voice pool + stolen-slot clear, per-sample frequency glide, attackStartLevel ramp).
2. **Musical attack transient** (TO CULTIVATE): a deliberate plucked/struck onset — the
   SomaChord "string plucked" feel. Intentional, pitch-locked, repeatable, expressive.
   This is shaped by the amplitude envelope's ATTACK (+ optional short excitation burst),
   NOT a glitch.

The goal is not "no transient" — it's "the RIGHT transient": a defined pluck/strike that
gives the body-played note a physical, string-like articulation.

## Where it lives (grounded)
- `SynthPatch`: attack/decay/sustain/release + envelopeCurve already exist.
  - Factory presets already span the range — e.g. one is attack 0.005 / decay 0.25 /
    sustain 0.0 (that IS a plucked/percussive shape) vs pad-like attack 0.5.
- `EchoelDDSP`: ADSR with `attackStartLevel` ramp (continuous onset, no retrigger click),
  `envelopeCurve` (exponential), per-partial spectral envelope.
- A true "pluck" = short attack + short decay + low sustain + a brief broadband
  excitation at onset (EchoelModalBank already does struck/plucked excitation for drums —
  `excite(velocity:position:)`; could lend a string/modal pluck layer to the lead).

## Why the attack matters MOST on key changes
A key/tonart change re-articulates notes at new pitches (and with the microtonal retune,
new frequencies). The onset/Einschwingphase is exactly WHEN the listener hears the new
note assert itself. A defined pluck attack makes a key change read as an intentional,
expressive articulation instead of a smeared/legato blur. So: tie attack character to the
moment of note onset, and make it audible across retuning.

## Possible feature shape (design, not committed)
- A "Pluck ↔ Pad" macro on the one instrument (single slider): morphs attack/decay/sustain
  together from struck-string to slow-swell. (One control, on-vision: "add dimensions as
  sliders, never new tabs.")
- Optionally a subtle modal/string excitation burst at onset for the SomaChord body feel
  (reuse EchoelModalBank pluck excitation as a per-note transient layer).
- Bio link (later, via the BioModulation spine): arousal/HR could push toward pluck
  (sharper, more present) and calm/coherence toward pad (softer swell) — body shapes the
  articulation, not just the notes.

## Status
NOT a fire. A creative direction to design deliberately AFTER:
1. (tomorrow) Apple Watch live-HR producer.
2. Verify 10.27.0 coherence wedge + 10.28/10.29 rPPG/Watch on device.
Then prototype the Pluck↔Pad macro and (optional) onset excitation. Keep the defect-click
fixes — this builds a chosen transient on top of a clean baseline.
