# Echoel — TODO (Ralph Wiggum backlog)

Single visible task list for the autonomous build loop. One task per cycle:
build → test → **Xcode Compile Check green** → ship via `.deploy/release` bump → loop.

> **Workflow note (this repo / remote env):** development stays on the branch
> `claude/piano-roll-clip-view-wozlie` (no per-task branches, no auto-merge to
> `main` without the founder's OK). **DEPLOY IS FULLY AUTONOMOUS AND TOKENLESS:**
> bump `.deploy/release` and `git push` → `testflight.yml`'s `push:` trigger
> (path-filtered to `.deploy/release`) runs the iOS TestFlight upload using the
> repo's App Store Connect secrets. **No local token, no `workflow_dispatch`, no
> founder action needed.** Do NOT claim a "daily upload cap" or that the founder
> must dispatch — that was a false belief; the push-trigger just works (verified
> v10.40.0 + v10.41.0). `workflow_dispatch` needs `actions:write` (absent here) —
> never use it; use the `.deploy/release` bump. Compile gate (`xcode-compile-check`)
> is the per-commit green gate. See CLAUDE.md.
>
> ⚠️ **GATE TRAP — verify `xcode-compile-check`, NOT `ci.yml`, for Accelerate/DSP code:** `ci.yml`
> runs on **Linux** where `canImport(Accelerate)` is FALSE, so every `#if canImport(Accelerate)`
> file (DSP/EchoelVDSPKit, EchoelDDSP, SpaceReverb, …) is EXCLUDED — ci.yml can be falsely GREEN
> while the iOS build FAILS (e.g. SpaceReverb's bad hex literal passed ci.yml, failed iOS). The
> macOS/iOS `xcode-compile-check.yml` is authoritative for any DSP/Accelerate/Metal/AUv3 change.

> **DEPLOY (2026-06-22):** v10.40.0 SHIPPED (upload SUCCESS) — filter-cutoff automation + key-follow
> stereo + adaptive brightness + resilient retry, on top of the live v10.39.0 sound fixes. App version
> now reports 10.40.0 (was stuck at 10.33.0). Apple's daily upload limit IS real (hit it mid-day after
> many deploys; cleared ~2.5h later). On an upload-step failure: 503/auth → auto-retried now; "Upload
> limit reached" → wait for reset, don't hammer. Build NUMBER is the true per-build identifier.

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
- [x] Audio clips **playable** (AVAudioPlayerNode, trim/loop) — Tools ▸ Audio Clip (import → trim/loop → play)
- [x] Automation **playback** wiring + authoring UI — Tools ▸ Editors ▸ Automation (master · tempo · filter cutoff)
- [ ] Multi-track arrangement timeline (parallel lanes, 2-D grid)
- [ ] Video: **recording** (AVAssetWriter) + **clip playback** (AVPlayer), transport-synced
- [x] MIDI **import** (SMF → piano roll) — Tools ▸ Editors ▸ Import MIDI (melody folds onto the bar + GM ch10 → drum grid)
- [x] Unison / detune richness — stacked detuned voices per note (opt-in patch param + gentle default on leads)

## Open — reach / polish
- [ ] Light fixture library + multi-universe (club rigs)
- [ ] Claims-guardrail lint (negation-aware, so it doesn't flag the brand's own anti-esoteric copy)
- [ ] Laser OSC namespace + doc (tethered Pangolin/LD2000)

## Gated (need founder verify / dep)
- [ ] HaishinKit RTMP/SRT A/V streaming (per docs/dev/BROADCAST_HAISHINKIT_FINISH.md)
- [ ] Ableton Link (timecode/clock sync)
- [ ] NDI (proprietary SDK)
