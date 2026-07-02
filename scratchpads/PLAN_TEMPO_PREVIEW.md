# PLAN — Vorhören im Mastertempo (tempo-matched audition), for ALL tools

**Founder (2026-07-02):** "Vorhören im Mastertempo, wenn ich Samples oder Loops
aussuche im Browser — für ALLE Tools. Egal ob Sampler-Instrument, Breakbeat-Slicer
oder Drum-Machine. … Vermeide unzureichende Tools. Alles auf top Level."

## North star
When auditioning a sample/loop anywhere (Browser, sampler-instrument pad picker,
breakbeat slicer, drum machine), it plays IN TIME at the current master (transport)
tempo — pitch-preserving, top quality — so you hear how it fits the track before
committing. One preview path, shared by every tool.

## Quality bar (why not varispeed)
Varispeed (rate change) alters pitch — fine for a DJ, wrong for a melodic loop and
below "top Level". Use **Apple's `AVAudioUnitTimePitch`** (system AU, high-quality,
pitch-preserving time-stretch, `rate` 1/32…32) — zero custom DSP, professional result.

## Build (in order; each device-verified)
1. ✅ **Pure core `TempoMatch`** (`Sequencer/TempoMatch.swift`) + tests — native-BPM from
   (duration, bars, beatsPerBar) and the clamped stretch `rate = masterBPM/nativeBPM`.
   No audio graph; unit-tested. ← landed now (foundation).
2. **Shared tempo-preview voice** — one `AVAudioPlayerNode → AVAudioUnitTimePitch → mix`
   preview path (owned by BeatPlayer, reused by every tool, NOT the kit). Loop the
   buffer; set `timePitch.rate = TempoMatch.stretchRate(...)`; follow `Transport.tempo`
   live. Hot-attach before `engine.start()` (build-1363 rule). DEVICE-VERIFY: audio
   starts, no glitch, loop seam clean, rate tracks tempo.
3. **Bar-length affordance** — a compact control (EchoelValueField/segmented 1·2·4·8
   bars) next to the audition ▶ so the loop's length is known → correct native BPM. A
   one-shot (drum hit) skips stretch (bars = 0 → rate 1.0).
4. **Wire every tool's audition to the shared voice**:
   - Browser Samples (currently `player.auditionBundled`/`audition(url:)`).
   - Sampler-instrument pad picker (SampleBrowserView "preview before assign").
   - Breakbeat slicer (LoopCutter) — preview slices at master tempo.
   - Drum machine (BeatPlayer pads) — one-shots unaffected; loop pads matched.
5. **Auto bar-length guess** (nice-to-have) — snap duration to the nearest power-of-two
   bars at the current tempo so the default "just works" for well-cut loops.

## Guardrails
- Audio-thread rules on the preview render path (no malloc/lock in the tap/callback).
- `AVAudioUnitTimePitch` is a main-graph node → attach/detach on the main actor, never
  mid-render; reuse ONE preview voice (don't spawn nodes per audition).
- Clamp rate to 0.25…4.0 (musical) so a mis-set bar count can't produce absurd speed.
- Device verification REQUIRED (audio quality / seams can't be proven by compile+review).
