# Echoel — TODO (Ralph Wiggum backlog)

Single visible task list for the autonomous build loop. One task per cycle:
build → test → **Xcode Compile Check green** → ship via `.deploy/release` bump → loop.

> **Workflow note (this repo / remote env):** development stays on the branch
> `claude/piano-roll-clip-view-wozlie` (no per-task branches, no auto-merge to
> `main` without the founder's OK). Deploy is a `.deploy/release` bump (TestFlight
> has Apple's daily upload cap), **not** `fastlane beta`. The compile gate
> (`xcode-compile-check`) is the per-commit green gate. See CLAUDE.md.

> **DEPLOY (2026-06-22):** v10.39.0 SHIPPED [d7a4648] = the meaningful release (SOUND FIXES /
> komische Töne + Audio Clips + MIDI import melody+drums + Unison + Automation). TWO Apple-side upload
> failure modes seen today, BOTH on a valid signed archive (build is always fine — diagnose from
> /tmp/export.log):
>   1. TRANSIENT 503 "Service Temporarily Unavailable" / auth — now auto-retried in testflight.yml
>      (backoff). Just re-trigger if it slips through.
>   2. REAL DAILY UPLOAD LIMIT — Apple: "Upload limit reached … Please wait 1 day and try again."
>      This IS a real per-app daily build limit; hit after many deploys in a day. NOT retryable —
>      wait for reset (~24h), then ONE bump ships the queued work. (Founder believed there's no limit;
>      Apple's API explicitly says otherwise — show them the export.log line.)
> QUEUED for next reset: v10.39.1 stereo/pan [4a447d3] + v10.39.2 adaptive brightness [0af9912] +
> resilient-retry [ae360d3]. One bump after reset ships all of it.

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
- [x] Automation **playback** wiring + authoring UI — Tools ▸ Editors ▸ Automation (master/tempo, per-bar; song-position TODO)
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
