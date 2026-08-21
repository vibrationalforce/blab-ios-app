# Echoel — Project Knowledge (the always-present reference)

Durable, comprehensive knowledge of the project from the start. Read at session
start with `memory/vision.md` (tiered vision/north-star), `decisions.md`/`decisions.csv`
(decisions), `inspiration_intake.md` (the vision-gate funnel) and `scratchpads/SESSION_LOG.md`
(recent cycles). This file = the consolidated "what is Echoel, how is it built, what
have we learned" so the knowledge is never lost between sessions.

## Identity

- **Echoel** (Michael Terbuyken, Studio Hamburg). Repo: github.com/vibrationalforce/Echoelmusic.
- App Store: Apple ID 6757957358 · SKU Simsalabimbam · bundle `com.echoelmusic` · App Group `group.com.echoelmusic`.
- **Echoel — Physical Computing · Biofeedback · Multimedial & Multidimensional.** iPhone-first,
  on-device, private, free. *Create From Within.*
- **The one sentence:** the instrument where ONE body plays multiple real dimensions at once —
  sound, space, light, vibration — over open standards, no SDK lock-in. The bio-reactive
  object *source*, not a renderer.

## The five dimensions (one instrument, never new tabs)

Body (differentiator) → Sound → Space → Light → Vibration, with Data (OSC/MIDI 2.0/MPE/AUv3)
as the connective layer. See `memory/vision.md` for the LIVE / ROADMAP / NORTH-STAR tiers.

## Architecture (audited)

- **EngineBus** = `@MainActor @Observable` control plane: snapshot `latestBio`/`latestBioEvent`
  (10 Hz poll) + lock-free `SPSCQueue`. Bio flows over the snapshot (correct for slow bio);
  the SPSC queue is drained only for `controllerEvents` (MIDI). `bioFrames`/`bioEvents` queues
  are reserved/undrained. New `freshBio(maxAge:5)` returns the latest frame only if recent.
- **Audio graph:** `AudioEngine` (`@MainActor @Observable`) master `AVAudioEngine`; source nodes
  attach BEFORE start (build-1363 hot-attach rule — hot-attach to a running engine crashed).
  PolySynthVoice (stereo, 8 voices, SPSC note/patch queues, WeakBox render), SubBassVoice (mono
  LFE, own node), PatternEngine (the transport/step clock) + BeatPlayer (audition preview voice
  ONLY — the drum kit inside it was removed 2026-07-26 (#166); #167 completes the file
  deletion. No drum sound is produced today). **Single main-queue beat clock is LOAD-BEARING** —
  moving it caused real SIGTRAPs (1769/1777); do not move it.
- **Self-healing:** AudioEngine watchdog auto-recovers from `.AVAudioEngineConfigurationChange`
  + route loss (de-bounced, capped); `degraded`/`lastAudioError` surface a manual retry.
- **Protected Rausch triad (READ-ONLY, do not simplify):** BioEventGraph (DELLY-style event
  detection), HilbertSensorMapper (1D→2D Hilbert locality), BioSignalDeconvolver (cardiac/
  respiratory/artifact separation via adaptive biquads). SKILL.md contracts in `.claude/skills/`.
- **Bio sources:** HealthKit + universal BLE 0x180D (Polar/Wahoo/Garmin/generic, auto-reconnect)
  + camera rPPG (locks on device) + Demo. Silent until user-armed; guaranteed launch silence.
- **Composition:** BioComposer (seed-rotated progressions, borrowed chords, turnarounds,
  phrase-arc velocity, grace-note ornamentation, octave climax), MusicalKey, MusicStyle (16 genres OFFERED in the picker out of 33
  declared — see `MusicStyle.offered`; #254 took the roster 8→16 on 2026-07-30 and this line
  stayed on 8 until #428), GenrePatches; mood model (liveliness/darkness/tension/romance/weird). Seamless
  bar-boundary morph (pendingNotes/loadAtBoundary). Sound→light: tonic transposed ~40 octaves
  to visible wavelength→sRGB in MetalBioView.
- **DSP:** EchoelDDSP (per-sample smoothed cutoff/harmonicity/noise/gain, denormal flush),
  EchoelCellular, EchoelModalBank, EchoelVDSPKit, FX chain (reverb/delay/EQ/dynamics/LUFS).
- **Outputs (open standards, native, ~zero deps):** OSC (`/echoelmusic/bio/*`), ADM-OSC
  (`/adm/obj/{n}/*`), Art-Net + sACN (light), MIDI 2.0/MPE in, RTP-MIDI, WAV/MIDI export.
- **Root view:** `Studio/EchoelStudioView.swift` — ONE instrument, collapsible panels + always-on
  BioStripView. UI: numbers-only scrubbable `EchoelValueField` (no sliders/knobs), pinch-to-zoom
  (Dynamic Type), website CI tokens via `EchoelTheme`.

## UI / brand rules (non-negotiable)

- **Website CI is the source of truth** (`docs/shared.css`): black ground, #e0e0e0 muted text,
  1px subtle borders, ≤12px radius, bio-green accent ONLY for live signal/active state (never
  page chrome), Atkinson Hyperlegible font. EchoelTheme mirrors it.
- Accessibility-first: VoiceOver on the instrument surfaces (play surface, chips, panels — the
  DAW surface this line used to name was deleted with #121 Slice 4), WCAG ≤3 Hz flash by
  construction, scalable.
- **No overclaim (auto-reject in product copy):** quantum AI, super-AI/AGI, wellness/healing/
  Solfeggio/chakra, "16K", BLAB/Vibrational Force/legacy soundscape. Biofeedback = science, show
  the number, never promise the benefit (FDA general-wellness line). **Code is the truth; if the
  website disagrees, the code wins.** ("Quantum/God mode" framing the founder uses = playful
  energy for the dev loop, NOT product language.)

## History arc (from the deep laser audit, 2026-06-17)

The visible git tree is a shallow ~2-week window (278 commits, 2026-06-03→06-17); deeper history
lives in scratchpads + SESSION_LOG. Phases:
1. **Foundation / pre-history** — EngineBus + HealthKit + protected-DSP contracts laid; an earlier
   deprecated v8 "soundscape/wellness" identity was dropped. Strategy docs deflated an inflated
   "1,552-commit / 12-tool" claim — discipline of honesty began here.
2. **Brand re-anchor (05-30→06-03)** — canonical brand set; verdict: bio-reactive instrument FIRST,
   fan out pillar-by-pillar (breadth-first caused 5 oscillations, 0 shipped breadth).
3. **Open-standard outputs (June)** — ADM-OSC, native Art-Net + sACN (zero-dep), RTP-MIDI, camera rPPG live.
4. **Crash crucible (~1683–1777)** — SIGTRAP on beat clock, reverb use-after-free, NaN→Int traps,
   note races. Lesson: the single main beat clock must not move.
5. **"Ich höre gar nichts" silence saga (06-13)** — StoreKit/HealthKit blocked audio start; fixed →
   core instrument starts before StoreKit/HealthKit; guaranteed launch silence.
6. **Sound-quality / USP (06-12→13)** — "too thin/digital" → consonant-by-design composition,
   analog saturation; strategic cut of video/RTMP/multitrack to sharpen the wedge.
7. **Deep composition + bio-acceptance (06-16)** — crackle-free per-sample gain, phrasing/
   ornamentation (1855); freshness window + BLE auto-reconnect (1857).
8. **Multidimensional pivot (06-17)** — "the multidimensional production instrument"; shipped
   sub-bass/LFE + Metal bio-visual + first-launch instant-sound (1867); self-healing engine
   (1869); numbers-only UI + pinch-zoom (1871); units + 4-decimals + physically-correct
   sound→light + bigger CI value boxes (1875).

## Founder principles (the constitution)

1. Stable-first / build-green is the only gate (Ralph Wiggum: one change/cycle, no batching, CI-verified).
2. Open standards, near-zero deps, no SDK lock-in (sole sanctioned dep: HaishinKit, behind a logged decision).
3. Biofeedback is science, not wellness.
4. Brand purity / no overclaim — code is truth.
5. Accessibility-first.
6. One paradigm: fan out from the bio core; anti-pattern = breadth-first oscillation.
7. Audio-thread sanctity (no malloc/locks/GCD/file-IO in render).
8. Honesty over cheerleading — green CI ≠ works on device.

## Deploy pipeline (token-free, verified)

- `git push -u origin claude/<branch>` → auto-merges to main **only if the push touches a watched
  path** (`Sources/** · Tests/** · Package.swift · project.yml · .github/workflows/**`); `docs/`
  auto-merges + Pages publishes. ⛔ #699: this line was unconditional, and it is `cat`-ed whole at
  every session start while the correction sits in CLAUDE.md's CI section — the more-read file
  said the looser thing. A commit touching only `CLAUDE.md`, `memory/**` or `scratchpads/**`
  triggers no merge of its own; it rides to `main` as a passenger on the next code commit, and
  **stays behind for good if the branch ENDS on it** — the ordinary end of a 24h mandate. It also
  blocks `auto-merge-docs.yml`, which skips its cherry-pick when the branch delta is not docs-only
  and still exits green.
- `git push -f origin HEAD:deploy-dryrun` → **Compile Check** job (xcodebuild iOS device SDK, no
  signing, no upload) = the real compile gate.
- `git push -f origin HEAD:deploy` → full build: iOS **Archive** (the compile gate on this path) →
  Export & Upload to TestFlight → "Verify build landed in ASC".
- **THE REAL GATE IS `testflight.yml`** (run_number = build number), NOT the deploy-on-tag wrapper
  (it only confirms dispatch). Parse runs via GitHub MCP `actions_list`/`actions_get`; responses are
  huge → save to file, parse with python.
- No local Swift compiler in the sandbox; verify ONLY via CI. No GitHub token in `.claude/
  settings.local.json` currently (it's cleared); use the GitHub MCP tools.
- Model id `claude-opus-4-8` must NEVER appear in commits/PRs/code/artifacts (chat only).

## Swift 6 / build gotchas learned (also in CLAUDE.md)

- `@MainActor` prop read from a nonisolated audio-render block → keep the @MainActor prop for UI,
  add an `@ObservationIgnored nonisolated(unsafe)` mirror written in didSet; render reads the mirror.
- `@Observable` generates `_foo` as `foo`'s backing → never name your own field `_<name>` (use
  `audioFoo`). (Both sub-bass compile fails came from these.)
- Removing a control? Grep ALL references first — a leftover `knobCols` grid usage broke build 1872.
- Custom font scaling: `.custom(name, size:, relativeTo:.body)` makes it honour Dynamic Type/zoom.
- GitHub MCP list responses overflow context → always persist + python-parse.

## Standing vision↔code gaps (keep honest, review each cycle)

1. "Live Broadcast" is a brand pillar with 0 code (HaishinKit authorized, unused; oscillated cut/re-list).
2. CLAUDE.md "v10 Target" diagram describes Beat/Record/Video/Share tabs never built (as-built = one
   EchoelStudioView); the file contradicts itself.
3. FEATURE_MATRIX stale on the visual dimension (cites old deleted MetalBioView; a new live one exists).
4. Bus `bioFrames`/`bioEvents` reserved but undrained; per-RR heartbeat events have no synth sink.
5. North-star concepts (installation worlds, auto-driving, dive-flying/Tauchfliegen, "revolutionise
   humanity via self-observation") are parked in `memory/vision.md` Tier-3 — never in product copy.

## Roadmap — SHIP GATE "Instrument-Complete v1"

The old track order here (Live Clip session grid · RTMP broadcast · AUv3 instrument · video
editing) named four things that were deleted or decided out by the pure-instrument epic
(#121/#122/#123) — it would have sent a session building against a product that no longer
exists. The canonical gate now lives in `docs/dev/PRODUCT_DEFINITION.md`; five binary checks:

1. **Klang** — curated genres professional, identity survives, no convergence bug.
2. **Kontrolle** — patch editor reachable (`soundPanel` behind the Sound chip). The piano-roll
   half of this check was RETIRED by founder decision 2026-07-26 (#178).
3. **Modi** — Flow + Loop.
4. **Ausgabe** — visual live + contemplative on device; light/space demonstrable, not required.
5. **Stabilität** — clean launch, no black screen, no menu freeze.

Mapping (Art-Net/sACN/ADM-OSC) is live; the Metal GPU visual foundation is laid.

_Last consolidated: 2026-07-28. Update when the arc advances materially._
