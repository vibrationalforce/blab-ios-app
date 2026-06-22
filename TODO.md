# Echoel — TODO (Ralph Wiggum backlog)

Single visible task list for the autonomous build loop. One task per cycle:
build → test → **Xcode Compile Check green** → ship via `.deploy/release` bump → loop.

> **Workflow note (this repo / remote env):** development stays on the branch
> `claude/piano-roll-clip-view-wozlie` (no per-task branches, no auto-merge to
> `main` without the founder's OK). Deploy is a `.deploy/release` bump (TestFlight
> has Apple's daily upload cap), **not** `fastlane beta`. The compile gate
> (`xcode-compile-check`) is the per-commit green gate. See CLAUDE.md.

## Done — 2026-06-22 session
- [x] Persistent bottom navigation bar (Arrange · Clips · Compose)
- [x] Structured, collapsible Tools menu (grouped)
- [x] Persistent brand top bar — centred "Echoelmusic" + E-waves logo + version
- [x] Piano-roll PPQ tick precision (Note model, tested)
- [x] AutomationLane data model (tested)
- [x] Felt sub by default + missing-fundamental harmonics
- [x] Spectral-donut visual tracks the live envelope
- [x] Calmer bio re-generation (settle into a phrase)
- [x] rPPG re-grip false-lock fix (fresh-lock corroboration)
- [x] Brighter / livelier default tone (genre patches)
- [x] Channel Rack — per-track Level · Mute · Solo (tested)
- [x] Per-channel insert FX (filter + drive) — drum **sample** path
- [x] Per-channel insert FX — **synth-drum** path (DrumSynthVoice)
- [x] AudioClipRegion — pure trim/loop/frame model (foundation for audio clips)

## Open — DAW / media depth
- [ ] Audio clips **playable** (AVAudioPlayerNode, trim/loop) — makes the audio lane real ← NEXT
- [ ] Automation **playback** wiring (read AutomationLane during transport) + authoring UI
- [ ] Multi-track arrangement timeline (parallel lanes, 2-D grid)
- [ ] Video: **recording** (AVAssetWriter) + **clip playback** (AVPlayer), transport-synced
- [ ] MIDI **import** (SMF → piano roll)
- [ ] Unison / detune richness (ensemble voicing, CPU-bounded)

## Open — reach / polish
- [ ] Light fixture library + multi-universe (club rigs)
- [ ] Claims-guardrail lint (negation-aware, so it doesn't flag the brand's own anti-esoteric copy)
- [ ] Laser OSC namespace + doc (tethered Pangolin/LD2000)

## Gated (need founder verify / dep)
- [ ] HaishinKit RTMP/SRT A/V streaming (per docs/dev/BROADCAST_HAISHINKIT_FINISH.md)
- [ ] Ableton Link (timecode/clock sync)
- [ ] NDI (proprietary SDK)
