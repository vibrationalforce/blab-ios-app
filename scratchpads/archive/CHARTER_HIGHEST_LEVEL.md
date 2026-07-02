# Highest-Level Charter — Bedienung · Technik · Kompatibilität · Qualität · Future-Safety

Founder (2026-06-17): everything at the highest level; long-term outclass Ableton,
Pro Tools, Acid, Final Cut, Logic, Reaper, DaVinci Resolve, Arena/Resolume, OBS,
Canva, Adobe. + "avoid slop".

## How we actually win (NOT by cloning each app)
Echoel's defensible position = the **bio-driven, accessibility-first, open-standard
SOURCE & HUB** that unifies sound + light + space + visual + broadcast on one
mobile-first instrument AND plugs into every incumbent via open standards. We beat
them on (1) the body as controller, (2) accessibility (WCAG/VoiceOver/numbers-first),
(3) ONE multidimensional pipeline, (4) zero lock-in. Where we compete head-on
(sampler, arrangement, video edit) the feature must be genuinely pro-grade.

## Interop matrix — incumbent → the open standard we meet/surpass it with
| Incumbent | Domain | Echoel interop (own, open) |
|---|---|---|
| Ableton Live | DAW/clips/Link | MIDI 1.0/2.0/MPE IN+OUT (✅), **Ableton Link** (roadmap), clip/arrangement (salvage), AUv3 |
| Logic / Pro Tools / Reaper / Acid | DAW | MIDI/MPE OUT (✅), MIDI file export (✅), AUv3, stem/WAV −14 LUFS (✅), warp (roadmap) |
| Final Cut / DaVinci Resolve | NLE/grade | video capture+edit (roadmap), ProRes/H.265 export, timecode; bio→grade params |
| Resolume / Arena | VJ/projection | NDI/Syphon out (roadmap), Art-Net (✅)/sACN, OSC (✅) — Echoel as the bio visual+light source |
| OBS | streaming | RTMP/RTMPS (roadmap, HaishinKit), NDI; bio-reactive overlays |
| Canva / Adobe | design/content | short-form A/V export, templates; bio-generative motion (roadmap) |

## Non-negotiable quality bars (every cycle)
- Realtime: audio thread no alloc/lock/ObjC/GCD; <10ms latency; per-sample smoothing; denormal-flushed.
- One shared PatternEngine clock (no 2nd timer — SIGTRAP history). Control-plane only off the audio thread.
- Swift 6 strict concurrency; -warnings-as-errors green; reviewer agents (audio/concurrency) before merge.
- Accessibility-first: VoiceOver, Dynamic Type, numbers-first, WCAG ≤3 Hz flash.
- Open standards only, no SDK lock-in (HaishinKit = sole external dep).
- Future-safety: value types + Codable persistence (App Group), forward-compatible decoding (optional new fields).
- No slop: no stale refs to deleted files, no dead half-wired code, tests with every logic cycle.
- Honesty: code wins over website; never claim unbuilt features (no overclaim/esoteric/AGI language).

## Reality tiering (so ambition stays honest)
- LIVE now: bio instrument, 23-genre composer, 8 character params, FX, sampler-pro engine,
  MIDI/MPE IN+OUT, OSC/ADM-OSC/Art-Net, export, AUv3, piano roll.
- NEAR (bounded, in salvage/loop): clips+arrangement (one view), sampler UI+folder/waveform,
  EchoelBreak, instrument selector, sessions recorder.
- ROADMAP (greenfield, never built): video capture/edit, RTMP, NDI/Syphon, Ableton Link, sACN multicast, multitrack.
- NORTH-STAR (concept, not product copy): full multidimensional installation world.
