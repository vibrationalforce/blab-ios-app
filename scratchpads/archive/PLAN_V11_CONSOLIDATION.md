# PLAN — v11 Consolidation ("alle gebauten Kerne, optimiert, zusammen")

Founder request (2026-06-18): one version where every desired, already-built
feature comes together in optimized form. Scope LOCKED to **wire the built cores +
optimize** (not the RTMP/video/live-vocal-monitoring roadmap — that's a separate,
bigger effort). Audio quality is a first-class pillar.

Versioning: ship interim builds as **10.22.x** (so each step is visible in
TestFlight), stamp **11.0.0** only when the whole consolidation is integrated +
device-verified = "it all came together".

## Inventory (verified 2026-06-18 against code)

WIRED & live: bio instrument, synth/FX/export, Art-Net/sACN, ADM-OSC, sub-bass/
haptics, Metal visual, OSC/MIDI/MPE/AUv3, Clips, Audio-input picker, MultiTrack
recorder, SkillLevel (ComposeView).

BUILT, NOT wired (this plan wires them):
- VocoderCore + FeedbackGuard  (flagship: voice+body → sound+visual+light)
- BioModulation (BoundParameter spine + ClockSource heartbeat-vs-BPM)
- MicrotonalTuning (TuningSystem: quarter tones, just intonation, world systems)
- LatencyCompensation (captured in recorder; not applied in mix)
- BioVisualParams (rings/cymatics/mandala, flash-safe)
- EchoelLanguageModel / EchoelAIRouter (on-device AI tutor; needs FM adapter)

## Execution order (one verified cycle each; render-path last + device-verified)

0. **Audio bombenfest (in flight)** — voice pool 12 + steal-slot clear (build 1912),
   per-sample frequency glide (build 1913). NEXT: consistent loudness independent
   of note density (tanh still swings 6↔14 notes) → proper output limiter/AGC.
   GATE: founder ear-confirms 1913 before more render changes.

1. **MicrotonalTuning → instrument (opt-in, default 12-TET)** — selectable tone
   system in the Sound editor; route note→frequency through TuningSystem; default
   unchanged so zero detune risk. Unit-test the mapping. CI-verifiable.

2. **BioModulation spine** — extend the existing ModulationEngine (bio→tempo) into
   the BoundParameter model: bind a few headline params (coherence→brightness,
   HRV→filter, breath→amplitude) + ClockSource heartbeat-as-clock toggle. Control-
   plane (10 Hz), deterministic, unit-tested. The "everything docks on the body" id.

3. **LatencyCompensation in the mix** — apply the captured offset to recorded takes
   on playback/export (align vocal to beat). Offline (files), not render-thread.

4. **BioVisualParams → Metal visual** — feed the rebuilt flash-safe params into the
   live visual so HR/coherence/breath drive rings/cymatics/mandala properly.

5. **On-device AI tutor** — Apple Foundation Models adapter conforming
   EchoelLanguageModel (iOS 26 guarded) + deterministic fallback, behind the
   BioExplanation / Learn layer (Direct Injection from LearnLibrary/MusicTheory).
   Non-render, CI-verifiable.

6. **Vocoder (flagship) — LAST, most careful** — VocoderCore + FeedbackGuard on the
   live mic→FX path (voice → sound+visual+light). Render-path + needs mic monitoring
   → audio-thread-reviewer + device verification mandatory. Wired-first; honest BT
   latency. May split into sub-cycles.

7. **Stamp v11.0.0** — once 1–6 integrate cleanly and are device-verified.

## Discipline
- One core per cycle; `swift build`/tests green via CI each push; build-guard local.
- Render-path changes (0, 6) go through audio-thread-reviewer + device ear-check.
- Each deploy: tell founder the exact TestFlight build number to test.
- Non-render wiring (1–5) can proceed CI-verified without a device.
