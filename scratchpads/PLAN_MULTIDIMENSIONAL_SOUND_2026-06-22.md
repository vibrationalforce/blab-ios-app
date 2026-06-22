# PLAN — Multidimensional Sound (5D expression · spatial 3D/4D · room-in-room) + swinging visuals

Founder (2026-06-22): "multidimensional werden. 5D Sounds wie ROLI Seaboard + Airwave — also
Filter etc. moduliert durch rPPG, und der Raum/Delay. 4D Raum-in-Raum Faltungshall. Alle
Industriestandard-Formate für multidimensionalen Sound auf allen Bereichen. Dann die Farbringe
zum Schwingen bringen." Sound IS currently good (founder-approved v10.45) → do NOT regress the base
timbre; ADD dimensions.

Synthesis of two expert passes (full infra audit + industry-standard research, cited). Extends the
existing `scratchpads/PLAN_MULTIDIMENSIONAL_2026-06-17.md` Track D; reconcile, don't restart.

## IST-STAND (audit)
- ✅ **ADM-OSC live** (`Sync/ADMOSCSender.swift`): body→object azimuth/elev/dist/gain, single source of
  truth math. External rigs only — phone audio is stereo, no internal 3D.
- ✅ **MIDI 2.0 + MPE INPUT complete** (`Audio/MIDIInput.swift`) — but the **synth is DEAF**: pitch bend
  is parsed and NEVER applied; PolySynthVoice ignores controllerEvents (only the mono BioReactiveSynthVoice
  drains them, and even it doesn't apply bend/pressure/CC74).
- 🟡 **MPE OUTPUT** (`Audio/MIDIOutput.swift`): channel 2–16 allocation + MCM RPN done, but sends note
  on/off ONLY — no per-note bend/pressure/CC74/lift.
- 🟡 **Convolution reverb EXISTS but DISABLED** (`DSP/EchoelVDSPKit.swift` EchoelConvolution; DDSP race) —
  fixable via the proven SPSC-queue pattern. Freeverb (`DSP/EchoelReverb.swift`) is LIVE + bio (HRV→mix).
- ✅ **Bio→DSP modulation wired + safe** (`EchoelDDSP.applyBioReactive`, 10 Hz poll, one-pole smoothed,
  per-voice): coherence→filter cutoff/brightness/harmonicity, HR→vibrato, breath→LFO→filter, HRV→reverb mix.
  GLOBAL (all voices identical); no per-note; FX chain not bio-bound; no bio→pan/delay.
- ✅ **FFT spectral rings 2D** (`Studio/SpectralDonutView.swift`) — oscillating waveforms; no 3D swing.

## STANDARDS (research) — what Echoel can credibly support, Swift-only, no license
- **MPE (MIDI 1.0)** now; **MIDI 2.0/UMP per-note** later (CoreMIDI MIDIEventList). 5D = Strike(vel)/
  Glide(bend)/Slide(CC74)/Press(channel pressure)/Lift(release). Body→5D mapping table below.
- **On-device spatial:** Apple **PHASE** / **AVAudioEnvironmentNode** (HRTF binaural, head-tracking on
  AirPods) — reuse ADM-OSC position math so external rig + on-device agree. Stereo out, no format change.
- **Convolution room-in-room:** partitioned overlap-add FFT convolution (vDSP/EchoelRealFFT). "Room-in-room"
  = early-reflection short IR + long tail IR, **parallel blend** (one bio-mappable knob) — safer than series.
- **ADM-OSC** (live), **OSC** (live). **Ambisonics AmbiX 1st-order** later. **Binaural** via PHASE/env node.
- ⚠️ **BLOCKERS (state plainly):** Dolby **Atmos encode/render is licensed, NOT Swift-only** → Echoel is the
  SOURCE (ADM-OSC), never the renderer; never claim "Atmos export." HOA + multichannel discrete = large,
  later. IAMF/Eclipsa = royalty-free but needs a vendored **C** lib → Council-gated, later. No pseudoscience.

## BIO → MULTIDIMENSIONAL MAPPING (consistent with the coherence servo: coherence→settle/clarity/close)
| Bio | → param | dir |
|---|---|---|
| Coherence | CC74/Slide brightness; spatial distance (close); room-in-room blend (intimate ER) | high→bright/close/intimate |
| Breath phase | spatial azimuth (L↔R); amp/filter envelope | sweep with breath |
| Breath depth | Press (channel pressure); arrangement fullness | deep→swell |
| HRV | spatial elevation (lift); per-note glide micro-drift | calm→lift |
| Heart rate | vibrato rate; tempo | fast→faster |
| LF/HF | spectral tilt; delay feedback | sympathetic→darker/longer |
| Motion | object gain/forwardness; Strike trigger; delay throw | move→forward |

## ROADMAP (cheapest high-impact first; each compile+CI green; audio-thread-reviewed where render/graph)
1. **Room-in-room convolution CORE** (pure, tested): dual-IR (ER + tail) overlap-add FFT space, parallel
   blend, synthetic IRs, real-time-safe structure (preallocated). NOT yet in render. ← SLICE 1 (safe, CI)
2. **Wire the space into the live FX via SPSC queue** (fix the disabled-convolution race) + bio→blend
   (coherence) + bio→delay. Audio-thread-reviewed. Device-verified.
3. **Synth HEARS MPE expression** — PolySynthVoice drains controllerEvents, applies per-note pitch bend
   (Glide) at minimum, then pressure→filter/amp, CC74→brightness. Audio-thread-reviewed.
4. **On-device spatial** — AVAudioEnvironmentNode/PHASE binaural, positions from the ADM-OSC math; optional
   (spatialAudioEnabled, default preserves current graph). Device-verified.
5. **MPE OUTPUT 5D** — extend MIDIOutput with per-note bend/pressure/CC74/lift from bio (body plays any MPE rig).
6. **Visuals swing** — SpectralDonutView rings rotate to object azimuth, squash by elevation, scale by
   distance, slow ≤3 Hz sway by space depth — bound to the SAME spatial params (single source of truth).
7. Later/flagged: MIDI 2.0 UMP per-note; 1st-order Ambisonics; multichannel bed; IAMF export (C lib, Council).

## GUARDRAILS
Protected Rausch triad untouched. Audio-thread rules absolute → audio-thread-reviewer for slices 2–4.
EchoelValueField for any new param UI. No Atmos-export/ pseudoscience claims. Sound is founder-approved →
default-off / subtle for anything that could change the base timbre; founder device-verifies audible slices.

## STATUS
- [x] Audit + standards research (this plan); Council: ADOPT-PRODUCT (brand core "multidimensional")
- [ ] Slice 1 — room-in-room convolution core — NEXT
