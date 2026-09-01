# FEATURE MATRIX — Echoelmusic v10 (the "second brain")

> ⛔ **READ `docs/dev/PRODUCT_DEFINITION.md` FIRST (2026-08-28 banner).** This file claims
> canonical authority and then LEADS with a retired end-state: every UPDATE block dated
> before 2026-07-25 (including the 2026-07-13 "ONE tracks-centric, bio-reactive DAW …
> `ArrangeTimelineView` (home)" block below) describes the dismantled workstation half —
> `ArrangeTimelineView` is deleted (#121 Slice 4) and "DAW" is the retired framing
> (decisions.csv row 302). Trust rows that carry a ⛔/corrected date ≥ 2026-07-27; treat
> everything else as history until measured against `Sources/`.

**Canonical map: marketing tool ↔ real code ↔ status ↔ TestFlight acceptance.**

This is the single source of truth that ties the *website* (the 12 "Echoel\*"
tools, which are conceptual groupings — **not** Swift types) to the *code* (real
modules) and to *TestFlight readiness*. Read this first when building toward a
TestFlight release: locate the tool, jump to its files, check its status and
acceptance line.

- **Public mirror:** `docs/architecture.html` (LIVE vs ROADMAP) and `docs/tools.html`.
- **Truth-source for status:** this file + the code. If the website disagrees, the code wins.
- **Status legend:** `LIVE` = ships in build #1 · `PARTIAL` = some live, rest roadmap · `ROADMAP` = no code yet.

> **UPDATE (2026-07-13) — Deep Audit ground truth + tracks-as-DAW night run (code-truth, v191–v192 + pure cores):**
>
> Full audit + ranked 30-item backlog: `scratchpads/BACKLOG_2026-07-13.md` +
> `scratchpads/AUTONOMOUS_NIGHT_2026-07-13.md`. End-state (founder 2026-07-13): ONE
> tracks-centric, bio-reactive DAW — 480-PPQ Transport (one clock), `ArrangeTimelineView`
> (home), `EngineBus` (spine); every lane is an instrument OR a media carrier.
>
> **SHIPPED/WIRED this run:**
> - **Tracks = instruments (v191)** — Add-Track menu offers EchoelDrums/Break/Sampler/
>   Synth/Bass/Bio + a Video track; `TimelineLane.builtinInstrument`/`isArmed` persisted;
>   per-track record-arm button shows the lane's INPUT source (audio-in / MIDI-in / bio) and
>   turns red when armed. Model + UI complete; the per-source CAPTURE engine is device-gated.
> - ~~**AUv3 Generator visibility (v192)**~~ **SUPERSEDED 2026-07-24 (#121 Slice 2)** — the in-app AUv3 host was removed; this entry is history. Original text: host scan included `kAudioUnitType_Generator`
>   (many 3rd-party AUv3 instruments register as Generator, not MusicDevice) + a raw pre-filter
>   makers/types breadcrumb to diagnose "only Apple shows" on device.
> - **7 pure keystone cores (CI-green, Linux-tested):** `RPPGConditioning` (linearDetrend +
>   perfusion gate + ACF-prominence — the rPPG-lock fix), `LaneVoiceRackPlan` (multi-roll slot
>   reducer), `WarpedClipPlan`, `AudioClipFactory`, `RecordAnchor`, `VideoResyncPolicy`,
>   `VideoExportPlan` — each a pure value core unblocking a device-gated wiring step (+ B05
>   LaneVoicePool churn/overflow-promotion tests).
>
> **Corrected status (audit ground truth) — the vision's open gaps (MISSING or device-wiring pending):**
> - rPPG pulse lock on device (pk=0/bpm=0/conf=0) — pure fix built (`RPPGConditioning`), device wiring = B03.
> - Per-lane voice routing (tracks=instruments) — all MIDI lanes still share ONE voice; `LaneVoiceRack` = B07.
> - Multi-roll fan-out — pure plan built, `TimelineRegionPlayer` still reads one `rollLaneID`; B08.
> - Region add/move/trim gestures — `moveRegion`/`resizeRegion` pure & unused; B11.
> - Audio-loop import into lanes / audio-lane playback — factory built (B14); door + player = B13/B15/B16.
> - Per-track record capture — arm persisted, NO capture engine yet; B18/B19/B20 (dead `MultiTrackRecorder` = the audio half).
> - Video-in-tracks playback — 4 pure cores done; `VideoLanePlayer` = B23, trim + BioGrade = B24.
> - Master automation authoring — `AutomationCanvasMath` pure & unused; B25.
> - Dead/idle: OSC `/mod` (B26), multi-fixture lighting (B29), EchoelStore StoreKit (B30 flag-gate),
>   RTMP/HaishinKit (not linked), CloudSync (no adapter), Session/Entrainment (kept for flash/latency laws).

> **UPDATE (2026-07-12) — interface reorg + weather multi-param + adaptive (code-truth, v171–v173):**
> - **Hackbrett reorg (LIVE, v168/v171)** — the Mix panel is ONE board: the master voices
>   (Bass · Melodic[Pad+Lead] · Drums) render as strip-cards (`EchoelStudioView.mixStripCard`,
>   each = level + its bus filter/drive) directly above the per-drum-channel strips
>   (`ChannelRackView(embedded:)`). Pure layout over the existing MixerStore/TrackFXStore
>   bindings — no new audio, FX off = bit-identical.
>   ⛔ **Korrektur 2026-07-27 (#167):** die untere Hälfte davon existiert nicht mehr. Der
>   „Drums"-Strip fiel mit der Drum-Entfernung (2026-07-26), und `ChannelRackView.swift` ist
>   **gelöscht** — es mischte 8 Kanäle, die keinen Klang mehr erzeugen. Die Master-Strips
>   (Bass · Melodic) bleiben. Damit haben `BeatPlayer.setFX/setShape/setMute/setSolo/clearSolos`
>   und `sampleLabels` **keinen Aufrufer mehr** (nächster Schnitt).
> - **Weather multi-parameter panel (LIVE, v172)** — `Core/WeatherMood.swift`: `Contribution`
>   now carries continuous per-parameter targets split SOUND (darkness/liveliness/tension →
>   blended into `MoodProfile` before the composer Input) + IMAGE (hue/saturation/glow/motion →
>   crossfaded into the `FloatingVisualWindow` visual). A `Param` enum (domain·label·explanation·
>   mixKey·`currentIntensity`) + pure `blend()`; the mixers are `WeatherMixRow` leaves (each an
>   `EchoelValueField` 0..1), SPLIT BY DOMAIN since #359: the four sound influences sit in
>   `moodPanel` under the weather toggle, the four image influences in `visualPanel` (the Field
>   chip) as `weatherImageRow`. (Said "the Session weather row … grouped Klang/Bild mixer" until
>   2026-08-01 — wrong panel since step 1, wrong structure since step 2.) Weather
>   opt-in (default OFF); every mixer 0 = bit-identical. Fully unit-tested (pure), UI ui-state-reviewed.
> - **Adaptive H/V layout (LIVE, v170/v173 — Regel überlebt, Quelle nicht)** — die Regel kam aus
>   `ChannelRackView.rackColumns` (v170, gelöscht #167); sie lebt heute nur noch im
>   `AdaptiveCardGrid` leaf (v173) und reflowt heute NUR noch die master mix strips
>   (`mixerPanel`) plus die sieben Gitter in `soundPanel` (#292 Slice 2) zu 2 Spalten im
>   Querformat, 1 im Hochformat. Die weather Klang/Bild-Gruppen reflowen GAR NICHT mehr: #359
>   Schritt 2 hat die Bild-Karte nach `visualPanel` gezogen, und ein Gitter mit einer Karte
>   ordnet nichts an, also ist es mitgegangen. Size-class read
>   confined to the leaf (render-safe); layout-only, revertible.
> - **Timeline playback (PARTIAL, v169)** — `Sequencer/TimelineRegionPlayer.swift` rides the
>   transport and plays the roll lane's **MIDI/drum** regions (opt-in "Play timeline", additive —
>   the Generate+Play instrument is untouched). **Audio/video/visual lanes are scaffold — they do
>   NOT play** (`Clip.kind.isPlayable == .midi` only). Path to functioning audio tracks mapped in
>   `scratchpads/PLAN_TIMELINE_AUDIO_TRACKS.md` (blocked on durable audio-clip creation + device verify).
>
> **UPDATE (2026-07-11) — comprehensive-interface modules + sound (code-truth):**
> - **Module 1 Mixer — LIVE, but TWO faders, not four (corrected 2026-08-06, #438).** `Core/MixerStore.swift` still *stores* bass/pad/lead/drums (four persisted keys, deliberately — see the file's own `⚠️ drums IS INCLUDED AND THAT IS DELIBERATE` note: a key that vanishes cannot be reset to unity if drums ever return). What the user can actually MOVE is `mixerPanel`'s two `EchoelValueField` rows: **Level (bass) and Pad**. Lead's fader went with #255 (founder: "Lead kann raus aus dem Mix"); drums produce no sound at all since #166/#167.
>   ⛔ And the old wording ended `+ Drums live via BeatPlayer.masterLevel` — **that symbol does not exist and, on this repo's history, never did in the form quoted.** `git grep -n masterLevel -- Sources` returns only `AudioEngine`'s output meter. A doc line naming a non-existent API is worse than a stale one: it reads as a wiring instruction.
>   ⛔ **Korrektur 2026-07-27 (#167): `BeatPlayer.masterLevel` existiert nicht mehr** — der Drums-Kanal ist mit dem Kit gelöscht. Bass/Pad/Lead bleiben.
> - **Module 2 Per-Track FX (PARTIAL)** — `Core/TrackFXStore.swift` (persisted per-bus insert settings) + `DSP/ChannelInsertFX.swift` (audio-thread-safe resonant filter + drive). **Bass bus** (`SubBassVoice`) and **Melodic bus** (`PolySynthVoice` pad/harmony + the dedicated lead voice via the `\.leadSynth` env key) each have a per-bus insert fed by a lock-free `SPSCQueue<TrackFX>`; UI = "Bass/Melodic filter + drive" in the Mix panel (`EchoelValueField`). Off by default = bit-identical. **Drums bus = ROADMAP** (BeatPlayer is timer-driven, needs a different tap point). Both render-path changes audio-thread-reviewed; UI ui-state-reviewed.
> - **Bio-tempo model LIVE (model only)** — `Core/BioTempoDirector.swift`: `TempoMode.locked` vs `.bioFollow` (transport tempo glides toward the pulse, pulled to the 72-BPM resonance band by coherence). Pure/tested; **not yet wired to `Transport.tempo`** (that's a device-pass cycle).
> - **Modulation spine de-duplicated** — `ModulationMatrix.ModSource` is the one canonical bio-source enum; `BioModulation` keeps only its unique `ClockSource` + `BoundParameter` (now `Codable`), re-based onto `ModSource`. The "assign the pulse to any knob" UI is still ROADMAP.
> - **Sound:** analog-warmth soft-saturation (`EchoelDDSP.analogWarmth`, anti-"plastic") + tempo-adaptive note density (`BioComposer.tempoDensityScale`, less hectic at high BPM) shipped. `CloudSync` reclassified: not dead — a tested Phase-0 CloudKit foundation awaiting the founder's iCloud container (Phase 1).
>
> **UPDATE (2026-06-18) — reconciled to code (corrects stale notes below):**
> - **EchoelVis is LIVE** — `Views/MetalBioView.swift` is the live full-screen bio visual (HR→pulse ≤2.5 Hz WCAG, coherence→hue, breath→spread, honours Reduce Motion). NOT dormant/deprecated. **EchoelSeq = 16 offered genres** (corrected 2026-08-06; #254 added eight and every claim of "8" went stale — the "23"/"12" figures before that were both wrong too. Count with `MusicStyle.offered.count`, never from memory). **sACN unicast is LIVE** beside Art-Net.
> - **Real HRV coherence** (`Bio/HRVCoherence.swift`, Lomb-Scargle + Welch) replaced the placeholder; **resonance breath guide**, **tap-to-learn** bio metrics (`Studio/BioMetricInfo.swift` wired into BioStripView) + the "app as a school" layer (`Studio/MusicTheoryPrimer.swift`, `Studio/LearnLibrary.swift`).
> - **rPPG hardened** (`Bio/CameraRPPGBioPublisher.swift` + `Video/CameraCapture.swift`): session-device torch + exposure lock → reliable lock; peak scan throttled off the main actor (UI no longer stalls).
> - **New pure tested CORES, built but NOT yet wired** (do NOT claim as shipping): `Studio/BioVisualParams.swift`, `Studio/VocoderCore.swift` (the flagship audiovisual vocoder: voice→sound+visual+light, flash-safe), `Studio/FeedbackGuard.swift` (howlround duck+notch brain), `Studio/BioModulation.swift` (universal `BoundParameter` bio-binding spine + `ClockSource` heartbeat-vs-BPM-lock), `Core/CloudSync.swift` (zero references outside its own file as of the 2026-06-20 obstacle audit — wire or remove before it rots), `Bio/ResonanceFinder.swift` (personalized resonance-frequency core; host orchestration + UI pending).
> - **Clips/Arrangement:** domain (`Clip`/`Arrangement`/`ArrangementPlayer`/`LaunchQuantizer` + stores) + tests EXIST; the **UI is the open gap** (#1).
> - **Legal/privacy:** ONE worldwide policy (GDPR/UK + CCPA/CPRA) in American English; `privacy.html` / `impressum.html` / `health.html` corrected to match shipped features. **~214 Swift (Sources) + 1 Metal** (count drifts every cycle — verify with `find Sources -name '*.swift' | wc -l`; corrected 2026-07-04, was "~133 + 2 Metal").

> **UPDATE (2026-06-12) — USP focus + bio-generative composer:** the iPhone app
> is now **Simple-by-default**, reduced to the USP × broad-audience intersection
> — *"your heartbeat makes music: to calm down or for your track."* First-time
> users see only 3 core tabs (**Create · Meditate · Songs**); the pro/installation
> surfaces (Sessions recorder + Connect = OSC/ADM-OSC/Art-Net/sACN) are hidden
> behind an **Advanced tools** toggle (nothing removed). New: the **bio-generative
> composer** ("Generate from Body" — key selection, Studio/BPM-lock vs Flow/
> sync-free, on-device prompt sound-design, 25-preset library; see EchoelSeq #4 +
> EchoelAI #12). **TestFlight status: archive + signing verified; upload pending**
> (Apple daily upload limit hit during build verification — re-dispatch after ~24 h,
> no code change). **Still NOT shipping (do not claim):** video capture/edit, RTMP/
> live-streaming, multitrack, waveform editing.
>
> **CURRENT SHIPPING STATE (2026-06-09):** TestFlight **build 1535 VALID** — app +
> **EchoelmusicWidgets** (live bio glance) + **AUv3 plugin** embedded (the AUv3 half of
> this snapshot is HISTORY — the target was deleted 2026-07-24, see the Ecosystem table), driven by
> live bio via `BioFeedbackPublisher` → App Group (CX). New since 1469:
> **camera rPPG is LIVE** (finger-on-lens, locks on device); **BLE source is
> universal** (any standard Heart Rate Service device, not just Polar);
> **ADM-OSC** immersive object output (Sync tab); EchoelBeat gained
> **velocity/accent + swing + per-pad sample import (Files)**; **launch is
> guaranteed silent** (bio voice emits zero until first user trigger). Audited
> 2026-06-09 (`scratchpads/ARCHITECTURE_AUDIT_2026-06-09.md`). Watch companion
> compile-verified, not embedded (export blocked — needs local Xcode).
>
> **Architecture correction (audit):** the EngineBus bio path runs over the
> `@MainActor latestBio` **snapshot** (10 Hz), NOT the SPSC queue. The lock-free
> SPSCQueue is load-bearing only for `controllerEvents` (MIDI). `bioFrames`/
> `bioEvents` queues are present but **not drained** (reserved). RTMP/video/
> multitrack are **absent** (no wired code), not shipping — see each tool below.

> The "12 tools" are a taxonomy over the real modules. E.g. *EchoelSynth* is the
> group {EchoelDDSP, EchoelCellular, EchoelModalBank, EchoelPolyDDSP, SamplerVoice}.
> There is no `EchoelSynth` type.

---

## Spine & infrastructure (not a "tool", but everything routes through it)

| Module | File | Notes |
|---|---|---|
| EngineBus | `Sources/Echoelmusic/Core/EngineBus.swift` | `@MainActor @Observable` control plane (snapshots) + lock-free `SPSCQueue`. 3 topics: `bioFrames` / `controllerEvents` / `bioEvents`. **Audit truth:** bio flows over the `latestBio`/`latestBioEvent` snapshots (10 Hz poll); the SPSC queue is actually drained only for `controllerEvents` (MIDI). `bioFrames`/`bioEvents` queues are reserved/undrained. Modules produce/consume via the bus, never couple directly. |
| SPSCQueue | `Sources/Echoelmusic/Core/SPSCQueue.swift` | Lock-free single-producer/single-consumer ring; audio-thread safe. Live use: `controllerEvents`. |
| AudioEngine | `Sources/Echoelmusic/Audio/AudioEngine.swift` | `AVAudioEngine` master bus. Graph: source nodes → masterMixer → **AutoMixChain (EQ→gain)** → mainMixer → output. Attach source nodes **before** `start()`. |
| Store / Logger | `Core/EchoelStore.swift`, `Core/ProfessionalLogger.swift` (`EchoelLogger`) | Persistence; `os_log` wrapper (never `print`). |
| ModulationMatrix | `Core/ModulationMatrix.swift`, `Core/ModulationEngine.swift` | Freely-routable bio→parameter mapping. Per-route `live` or `hold(value,drift)`. **LIVE (wired) BUT NOT EDITABLE (corrected 2026-08-06, #438):** `ModulationEngine.start(subscribing:)` really does run (`EchoelmusicApp.swift:1031`), `tempo` is registered, and outputs are tapped to OSC `/echoelmusic/mod/*`. ⛔ The old line added "edited in the Sync tab (`ModulationView`)" — **there is no `ModulationView.swift` in the tree and no Sync tab**; the whole tab shell went long ago. So the matrix is shipped-and-running with **no user surface**, which is the thing to know before planning from this row (#136 is the task that would give it one). |

---

## The 12 tools

### 1. EchoelSynth — `LIVE`
- **Code:** `DSP/EchoelDDSP.swift`, `DSP/EchoelCellular.swift`, `DSP/EchoelModalBank.swift`, `EchoelPolyDDSP`, `Sequencer/SamplerVoice.swift`, `Tools/BioReactiveSynthVoice.swift`
- **Live:** DDSP synthesis; one-shot sampler; bio-reactive voice (HR→vibrato, HRV→brightness, coherence→harmonicity, breath→envelope), audible via `AVAudioSourceNode` → master mixer.
- **Live (voice timbre, #592a/#593):** a held tone captured in the Sound panel's "Voice timbre" row becomes the instrument's spectrum — `Studio/VoiceCaptureController` → `VoiceCaptureEngine` → `VoiceAnalyzer` → `SynthPatch.voiceProfileTaps` (~64 floats, max-normalized), blended over the patch by `EchoelDDSP`. **No audio is recorded and none is stored**: neither analyser nor engine touches `AVAudioFile`, `FileManager` or `write(to:)`, and `SynthPatch` says so at the field. A saved patch carries the envelope under a mandatory label. ⚠️ This entry was missing from every published surface except the store's release notes until #795/#797 — the reference document a session reads to decide what is live did not know the feature existed.
- ⛔ **"modal / cellular" stood in that Live line and neither makes a sound (#796).** Measured, not remembered: `git grep -n "EchoelModalBank(\|EchoelCellular(" -- Sources` returns **nothing** — zero production instantiators for either. `EchoelModalBank`'s only caller was the drum voice removed by #167; `EchoelCellular` never had one. Both stay in the tree deliberately (founder said "erstmal"), and both stay OUT of any Live line. ⚠️ The grep on the bare NAME is polluted by prose — fourteen files under `Sources/` mention them, all in comments; the grep that measures the thing is the one on `Name(`.
- **Roadmap:** EchoelBeat, breakbeat chopper, spectral morph.
- **TestFlight acceptance:** tapping play on `BioStripView` opens the envelope and produces sound; bio frames audibly modulate timbre.

### 2. EchoelFX — `PARTIAL` (deepened 2026-06-10; FX characters 2026-06-12)
- **Code:** `DSP/EchoelDelayLine.swift`, `DSP/EchoelDelay.swift`, `DSP/EchoelModFX.swift`, `DSP/EchoelDynamics.swift`, `DSP/EchoelFXChain.swift` (insert chain, **stereo tone filter first stage**), `DSP/EchoelSVFilter.swift`, `DSP/EchoelLFO.swift`, `DSP/TempoSyncOption.swift`, `Sequencer/GenreFX.swift` (`GenreFXPreset` + `FXCharacter`), `DSP/EchoelReverb.swift` (the algorithmic reverb that sounds); `EchoelConvolution` (in EchoelDDSP, disabled), `Audio/AutoMixChain.swift`, `DSP/EchoelVDSPKit.swift` · UI: `Studio/EchoelFXView.swift`
- **Live:** **insert FX chain** — every stage in signal order, filter first and limiter last (⛔ this read "filter → modulation → delay → dynamics → safety limiter" until the #480 follow-up. The ORDER was right, the completeness was not: `EchoelFXChain.processStereo` ran fourteen stages then and fifteen since #692 added Granular, and Saturation · Tape / VHS · Bitcrush · Harmonizer · Reverb · Stereo Width fell outside all four names. A list under a heading that reads as the whole chain is a completeness claim, and it has to be re-counted every time a stage is added — so name the two stable ENDS and let the sub-bullets below be the inventory. ⛔ #693: this bullet then opened with "14 stages" for two months — the sentence that says "it has to be re-counted every time a stage is added" sat inside the claim that had to be re-counted, and #692 added the fifteenth without walking it. Measure, do not quote — and measure the RIGHT function: `sed -n '/func processStereo/,/^    }$/p' Sources/Echoelmusic/DSP/EchoelFXChain.swift | grep -c 'if [a-z]*Enabled'` gives 15. ⚠️ The first #693 draft wrote that recipe WITHOUT the `sed` and it printed 29, because `reset()` and `noteRenderSleeping()` gate on the same flags — a quoted recipe that contradicts the prose beside it is read as a contradiction, not as a loose command. Same trap as the `EchoelModalBank` recipe in CLAUDE.md, hit twice in two commits.) — driven from the `FX` panel (BioStripView) and applied to the melody voice on generate:
  - **Filter** — stereo Chamberlin SVF, low/high/band/notch, cutoff + resonance (the basis of muffled/lo-fi colours). Off by default.
  - **Delay** — fractional delay line (linear + allpass interpolation), digital / **tape** (wow+flutter+saturation) / **ping-pong**, one-pole feedback tone, stability-clamped feedback. **Tempo-synced** (studio calculator: note division → time at the live BPM).
  - **Modulation** — chorus, flanger (feedback), phaser (cascaded allpass), tremolo / auto-pan; rates also tempo-syncable.
  - **Dynamics** — soft-knee compressor + brick-wall limiter (hard ceiling guarantee).
  - **Production FX characters** (`FXCharacter`): one-tap **Underwater** (deep low-pass + watery chorus + tape wobble), **Telephone**/**Megaphone** (band-pass), **Cassette**/**Vinyl** (warm low-pass), **Dream** (wide bright ping-pong), **Clean** (dry reset). Stampable in the FX tool *and* the Compose **Effects** picker. `Auto` defers to the genre's own space (see per-genre presets below).
  - **Per-genre FX presets** — each offered genre carries a signature space (long dub ping-pong delay, vapor chorus, psy roll), tempo-synced, auto-applied on "Generate from Body".
  - algorithmic reverb (`EchoelReverb`, enabled per genre preset), 4-band EQ + LUFS auto-gain (target from the Loudness picker — streaming −14, podcast −16, broadcast −23, cinema −24 or none; correction clamped to ±6 dB; 4 tonal presets), soft `tanh` saturation. `EchoelDDSP`'s convolution reverb is compiled but disabled (`useConvolutionReverb = false`) and makes no sound.
  - Audio-thread-safe (no alloc/locks in render; `audio-thread-reviewer`-audited each change); gated by `fxEnabled` (default off → bit-identical to prior builds until engaged).
- **Roadmap:** **master-FX bus** (so the whole beat/loop, not just the melody, can go Underwater — needs an AVAudioUnit insert on the master mixer), analog (VCA/Opto/FET/VariMu/Tube) emulations, spatial/Atmos 3D panning, stereo synth voice, ring-mod.
- **TestFlight acceptance:** FX panel toggles the insert chain audibly; filter/delay/chorus/flanger/phaser/tremolo/comp/limiter each change the sound; stamping **Underwater** muffles + adds watery movement, **Clean** resets to dry; export path applies AutoMix to the SELECTED loudness target without clipping.

### 3. EchoelMix — `PARTIAL`
- **Code:** `Audio/AudioEngine.swift`, `Audio/AutoMixChain.swift`, `Audio/SingleExport.swift`, `Audio/RetroCapture.swift`, `MicrophoneManager.swift`
- **Live:** master bus, mic FFT (1024-pt), 30 s stereo pre-roll ring (`.caf`), LUFS-normalized WAV/AAC export.
- **Roadmap:** `Audio/MultiTrackRecorder.swift` (skeleton), console UI, FLAC/ALAC, stem export.
- **TestFlight acceptance:** SingleExport writes a valid WAV/AAC normalised to the SELECTED loudness target (−14 only when the picker is on Streaming; "No target" writes at unity).

### 4. EchoelSeq — `PARTIAL`

> ⛔ **CORRECTION 2026-07-27 — most of this section describes features the founder
> REMOVED. Read the banner before any line below it.**
> - **Drums / step sequencer / sampler: GONE** (#166 "keine Drums" 2026-07-26, full
>   teardown #167). The `BeatPlayer` / `SamplerVoice` / sample-library / velocity /
>   swing / humanization bullets below are HISTORY, not status.
> - **Piano roll: GONE as a surface** (#178, 2026-07-26) **and gone as code** (#475,
>   2026-08-07). `PianoRollModel` survives as the note engine and `MusicalFrame`
>   publisher; the `PianoRollView` struct was doorless and unmounted, and has now been
>   deleted outright (987 lines). The FILE `Studio/PianoRollView.swift` remains — it is
>   where the model lives. There is no note editor in the app.
> - **Clips + Arrange timeline: GONE** (#121 Slice 4 — `ClipView` 807dc0d,
>   `ArrangeTimelineView` eb58e7a). The model retires in Slice 5 (#132).
> - **Genres: 16** — `MusicStyle.offered.count`. The enum holds 33 cases
>   (`MusicStyle.allCases`); the picker shows `offered`. ⛔ This block said "8, not 23 and
>   not 12", named the 8-genre roster, and put the taxonomy at 26 — all three went stale on
>   2026-07-30 when #254 added eight genres, and stayed stale until #428. It sat ELEVEN
>   lines above a corrected line in the same file, written in the emphatic "not 23 and not
>   12" voice that invites a reader to trust it. A correction block is not exempt from
>   going stale; recount it with the command, do not read it.
> - **Scales: 57** (`Scale.Family.allCases.flatMap(\.scales)`, which is what the picker
>   iterates) — was "50" here, correct until #232 J added the seven Indian scales.
> - **MIDI file export: LIVE** — ⛔ this said "built, DOORLESS — `exportMIDI()` has no
>   caller" and that has been FALSE since #188 put the door back in the existing export
>   slot: `EchoelStudioView.swift:6579` is `Button { exportMIDI() }`. The live App Store
>   description claims MIDI export (`fastlane/metadata/en-US/description.txt:28`), so a
>   session trusting the old line would have deleted a TRUE claim from live copy as an
>   overclaim. The dangerous direction of a stale doc is the one that reads as caution.
>
> What is still LIVE here: the bio-generative composer (BioComposer / MusicalKey /
> MusicStyle / GenrePatches), the studio precision + loop tools, and session naming.

- **Code:** `Sequencer/PatternEngine.swift`, `Sequencer/BeatPlayer.swift`, `Sequencer/SamplerVoice.swift`, `Sequencer/MIDIFileExporter.swift` (`scripts/generate_drums.py` gelöscht 2026-07-27 — es schrieb WAVs in ein Verzeichnis, das es nicht mehr gibt)
- ⛔ **Live-Zeile überholt (2026-07-27, #167).** Was davon **weg** ist: velocity/accent, swing, per-pad Sample-Import, das prozedurale Drum-Kit selbst — samt den 8 Pad-Stimmen, `Resources/Drums` und der Auslöse-Kette. Was **bleibt**: 8 Spuren × 16 Schritte, 30–300 BPM, randomize/shift — aber als **Takt-Clock**, nicht als Klangquelle: `pattern.onStep` wird nirgends mehr gesetzt. SMF Type-0 MIDI export unverändert (⛔ hier stand „Exporter intakt, aber TÜRLOS" — die Tür ist mit #188 zurück, `EchoelStudioView.swift:6579`).
- **Polyphonic piano roll — REMOVED** (#178, 2026-07-26; **struct DELETED** #475, 2026-08-07): the door went first, then the code. ⛔ This line said the file "still compiles (one static helper is under test) but has no door and is not mounted" — true until #470 hoisted that helper into `RollHitTest` and #475 deleted the 987-line `PianoRollView` struct outright. It is corrected here as well as in the banner above because THIS is the line a reader reaches by searching for the feature, and a published page that describes a deleted type as merely dormant invites someone to plan a re-door onto nothing. `PianoRollModel` stays — it is the note engine and the `MusicalFrame` publisher.
- **Session clips + Arrange timeline — MODEL ONLY, NO SURFACE (corrected 2026-08-06, #438; this row has now flipped three times, so check the tree before trusting any version of it).** What still exists and compiles: `Sequencer/Clip.swift`, `Core/ClipStore.swift`, `Sequencer/Timeline.swift` (480-PPQ lanes/regions/snap), `Core/TimelineStore.swift` (persist + lossless legacy migration), `Sequencer/ArrangementPlayer.swift`.
  ⛔ **What the old line named as LIVE and is DELETED:** `Studio/ClipView.swift` (#121 Slice 4, `807dc0d`) and `Studio/ArrangeTimelineView.swift` (#121 Slice 4, `eb58e7a`). It also said they "since v10.79.144 form THE one main view (timeline over instrument, track-head doors: Piano Roll / audio editor / rename / delete / add)" — **every clause of that is now false**: the home is `EchoelStudioView`, and the piano-roll door went with #178. Verify with `git ls-files 'Sources/**/ClipView.swift' 'Sources/**/ArrangeTimelineView.swift'` → zero.
  This is the pure-instrument epic (#121) doing what it was asked to do; the models survive on purpose and #132 Slice 5 is the open decision about them. **Restoring the views means rebuilding them, not re-hanging them** — do not read this row as a door that can be switched back on.
- **MIDI/MPE OUT — ⛔ THE "NOT REACHABLE" BELOW IS STALE SINCE #713 (banner 2026-08-28; the honest rows further down at "MPE OUT is real and switchable" were right all along — this row contradicted them in the same file):** since #713 both flags are persisted and have two switches in the reachable routing surface ("MPE note layout" / "Per-note expression"), written by `MIDIOutput.applyOutputPreferences()`. Historical text follows: `Audio/MIDIOutput.swift` builds a virtual "Echoelmusic" CoreMIDI source (`._1_0`) that mirrors played notes — but it is only created when a Patchbay MIDI route is enabled, and `mpeEnabled`/`expressionEnabled` had **no writer** from the Tools-grid removal (2026-07-02) until #713 restored their toggles. So MPE out is unreachable and the plain source is route-gated. Was listed LIVE (2026-06-17) when the Tools menu still existed.
- **Character params — LIVE (2026-06-17):** `MoodProfile` now 8 dims (… + **virtuosity, syncopation, humanize**), all consumed in the lead generator. **16 offered genres** (`MusicStyle.offered`; the enum holds 33 cases, so **17** are not offered — the curation is by ear and re-offering one is a listening decision. ⛔ This said "nine older ones": 33 − 16 = 17, and it was 17 at the 2026-07-24 curation too (25 declared, 8 offered). Nothing in the tree counts to nine).
- **Sampler playback shaping — ENGINE ONLY, and only the PITCH third of it (corrected 2026-08-06, #438).** `Sequencer/SamplerVoice.swift` still offers `configurePlayback(start:end:reverse:pitchSemitones:)`, interpolated and lock-free. Its **one** production caller is `Sequencer/LaneVoiceRack.swift:318`, and that caller passes **only `pitchSemitones`** (derived from the MIDI note, root 60, plus the lane transpose) — so `start`, `end` and `reverse` take their defaults and have **no writer anywhere in `Sources/`**. Check with `git grep -n 'configurePlayback(' -- Sources`.
  ⛔ The old line said "**per-pad** start/end trim, reverse, pitch" as a `LIVE engine`. There are no pads — the drum apparatus was deleted (#166/#167) — and two of the three named capabilities are unreachable. Engine capability is not a feature; this row now says which third ships.
- **Categorized sample library + browser — VOLLSTÄNDIG GELÖSCHT (2026-07-27, #167, zwei Commits):** erst `Studio/SampleBrowserView` (keine Tür), dann die **73 WAVs unter `Resources/Samples/` (5,42 MB)** samt ihrer `project.yml`-Ordnerreferenz und der `BeatPlayer`-API, die sie indizierte (`LibrarySample`, `samplesRoot()`, `static let library`, `auditionLibrary`, `assignLibrary`, der `"lib:"`-Zweig von `bundledAssignmentURL`). Damit ist auch die offene **Lizenzprüfung der pack-abgeleiteten Samples erledigt** — die Bytes werden nicht mehr ausgeliefert. ⚠ `.github/workflows/fetch-samples.yml` + `scratchpads/SAMPLES_MAP.tsv` (181 Zeilen, ~150 Ziele unter `Resources/Samples/…`) existieren weiter; ein Push auf `.deploy/fetch-samples` mit `phase: curate` würde das Verzeichnis wieder anlegen — ohne Build-Deklaration und ohne API, die es liest. Founder-Entscheidung offen (es ist SEINE Sample-Pipeline). Historie: `BeatPlayer.library` scannte `Resources/Samples/<Category>/*.wav` (Bass · Stab · Keys · Pad · Tone · Tom · Conga · FX · drum variations), surfaced in `Studio/SampleBrowserView` — audition ▶ before assign; bundled/library pad assignments persist across relaunch (`bundledKey`). Ships **~50 licence-clean ORIGINAL synthesized sounds** (`scratchpads/tools/echoel_tones.py` + `drum_synth.py`: subtractive/FM/additive + Karplus-Strong physical modeling, resonant-SVF character voices; mastered by `sample_processor.py`). Honest limit: pre-existing non-Echoel library samples are pack-derived → licence review pending before App Store submit.
- **Per-hit velocity humanization — GONE (corrected 2026-08-06, #438).** ⛔ The old line claimed this LIVE via `BeatPlayer.humanizeDepth`, ≤12 %, on "sequenced pad hits". **`git grep -n humanizeDepth -- Sources` returns nothing**, and there are no pad hits to humanize since #166/#167. The idea survives elsewhere and under a different name — `MoodProfile.humanize` feeds the melodic generator, and `hrvHumanize` puts the body's own jitter on note timing (see the #403 Slice 3b notes) — but nothing in this row is true as written.
- **Bio-generative composer ("your heartbeat composes"):** `Sequencer/MusicalKey.swift` (set your own key/scale, **57 scales** — `Scale.Family.allCases.flatMap(\.scales)`, which is what the picker iterates) + `Sequencer/MusicStyle.swift` (**16 offered genres** — Self-Observation, Deep Ambient, Drift, Contemplation, Vaporwave, Sci-Fi, Classical, Dub Techno, Acid Techno, Deep House, Uplifting Trance, Tech House, Minimal Techno, Detroit Techno, Still Drone, Ambient Pulse; all harmonic/melodic since the drums were removed) + `Sequencer/BioComposer.swift` (bio → in-key melody + heartbeat rhythm + tempo, SplitMix64-seeded → reproducible) + `Sequencer/GenrePatches.swift` (per-genre synth timbre), Two modes: **Studio** (BPM-locked, for Ableton/FL handoff) and **Flow** (sync-free, follows the heart — for meditation). Each take gets its genre timbre + genre/character FX space. Generated melody is written as MIDI (real durations + velocity) and the door is LIVE — #188 put `exportMIDI()` back into the existing export slot (`EchoelStudioView.swift:6579`); the live store description claims it. Surfaced as **"Generate from Body"** in `Studio/EchoelStudioView.swift`; the `Studio/ComposeView.swift` this line used to cite no longer exists.
- **Studio precision & loop tools:** two-decimal **BPM + Kammerton** (`DSP/TuningReference.swift`, A4 432–444, default 440, user-changeable), tempo-synced FX/LFO via the **studio calculator** (`DSP/StudioCalculator.swift`, `DSP/TempoSyncOption.swift`), **loop/stem cutting** at 2/4/8/16/32 bars (`Sequencer/LoopCutter.swift`), **tight-grid vs humanized** feel (`Sequencer/Humanizer.swift`).
- **Auto session name + export filename** (`Core/SessionNaming.swift`, `Core/SessionContext.swift`): every session and exported file is stamped `Artist_Date_Key_BPM_Kammerton[_Part]`, e.g. `Echoel_2026-06-12_Cm_124bpm_A440_Melody-4bar.mid` — persisted artist/key/Kammerton, previewed live in Compose, shown on saved bio sessions in Works.
- **Roadmap:** per-step probability, automation lanes, Euclidean / polyrhythm; multi-bar generated "pieces" via the arrangement; WAV stem bounce (needs offline-render harness).
- **TestFlight acceptance:** `BeatTab` plays a pattern at the set BPM; accent louder; swing audible; a loaded sample replaces a pad and survives relaunch; **"Generate from Body" writes an in-key melody in the chosen genre + key, applies the genre/character FX, and exports a stamped MIDI filename; Studio locks the BPM, Flow follows the heart.**

### 5. EchoelMIDI — `LIVE`
- **Code:** `Audio/MIDIInput.swift`, `Sync/MIDIBusPublisher.swift` → `EngineBus.controllerEvents`
- **Live:** MIDI 1.0/2.0 input — notes, channel pitch bend, Press (channel pressure, #939 → `expressionGain`) and Slide (CC 74, #942 → `renderCutoffScale`) → ONE monophonic bio-modulated performer voice (performer priority over breath). ⛔ **This said "MPE input (per-note bend, slide/CC74, air-CC)"** — #548/#770 — **and the RETRACTION's own reasoning has since expired twice while the retraction held.** It counted dimensions: three discarded, then two (#939), then none (#942). What was never about the count, and is why "MPE input" stays struck: `MIDIBusPublisher` tells no MPE zones apart (RPN 6,6 has no producer) and `apply(controller:)` never reads `event.channel`, so there is no member channel to tell apart. **A zone is what MPE adds.** `.airCC` (CC 21–31) is not an MPE dimension at all and is the one case still running into a bare `break`. "notes" in the plural was wrong too: `apply(controller:)` calls `playNote(` exactly once, onto one `synth`. (⛔ #943b: this read "`heldByController` is a single `Bool`" — true until #943 made it a computed `Bool` over a held-key STACK, at which point the evidence sentence named the one thing that had stopped being singular. The monophony lives in the single `synth`, not in the latch.) **MPE _out_ is real and switchable (#713).**
- **Roadmap:** Standard MIDI File I/O, MIDI output, touch instruments, audio-to-MIDI.
- **TestFlight acceptance:** an external MPE controller triggers synth notes.
- **Fixed:** `MIDIInput.swift:94` force-cast (`as! UInt32`) → crash-safe `compactMap { as? UInt32 }` (behavior-preserving; the word tuple is homogeneous UInt32).

### 6. EchoelBio — `LIVE`
- **Code:** `Core/EngineBus.swift` (`BioSampleFrame`), `Bio/HealthKitBioPublisher.swift`, `Bio/PolarH10BioPublisher.swift`, `Bio/BioSimulator.swift`, `Bio/EchoelBioEngine.swift`, `Bio/BioEventPublisher.swift`
- **Protected DSP triad (read-only, do not simplify):** `Bio/BioEventGraph.swift`, `Bio/HilbertSensorMapper.swift`, `Bio/BioSignalDeconvolver.swift`
- **Live:** **Universal BLE Heart Rate** (`PolarH10BioPublisher` connects to ANY standard 0x180D/0x2A37 device — Polar/Wahoo/Garmin/CooSpo straps, watches in broadcast; RR→RMSSD; shows device name) + HealthKit (Apple Watch + **Oura via Apple Health**) + **camera rPPG (`Bio/CameraRPPGBioPublisher.swift` → `Video/CameraAnalyzer.swift`, finger-on-lens + torch, locks on device, live waveform)** + Demo → bus snapshot; breath/motion onset events via BioEventGraph. **CX:** `Core/BioFeedbackPublisher.swift` mirrors vitals to App Group (~1 Hz) → Widget/Watch glance.
- **Honest limits:** Oura exposes no real-time third-party BLE (only via Apple Health, delayed). Camera rPPG is motion-sensitive (use a BLE strap for loud/active performance). PolarH10 per-RR `.heartbeat` events are published but currently have no working sink (snapshot loses sub-100 ms beats) — beat-sync cycle will drain `bioEvents`.
- **Roadmap:** face tracking (ARKit); raw PPG/ECG waveform; EEG band-power (LSL).
- **TestFlight acceptance:** `BioStripView` shows live HR/HRV/Br/Coh; camera pulse locks (PPG); BLE strap shows its name; Demo works on Simulator; Widget mirrors vitals.

### 7. EchoelVis — `LIVE` (corrected 2026-07-04; the old PARTIAL entry named deleted files)
- **Code (live):** `Views/MetalBioView.swift` (Metal bio visual, inline-compiled shader, AdaptiveQuality FPS/detail tiers, flash-safe ≤3 Hz, Reduce Motion) inside `Studio/FloatingVisualWindow.swift` — the floating/fullscreen window toggled from the WorkspaceView header, with in-fullscreen VJ controls + palette.
- **Code (live, capture):** `Video/VisualRecorder.swift` + `Video/VideoMuxer.swift` — records the visual to stamped **MP4 clips** (share-ready) from the floating window.
- **Gone:** `BioVisualView` / `BioVisualRenderer` / `MomentCaptureView` were deleted in cleanup — do not reference them.
- **Roadmap:** external-display output window; more looks; AR worlds.
- **TestFlight acceptance:** header monitor toggles the floating visual; it reacts to bio; fullscreen + record work.

### 8. EchoelVid — `ROADMAP`
- **Code:** `Video/CameraCapture.swift` (used ONLY by camera rPPG), `Video/CameraAnalyzer.swift` (rPPG). **Audit:** `CameraSession` / `VideoRecorder` / `ClipTrimmer` = 0 instantiations; `ShortContentRenderer` not wired. **No video recording/editing is shipping.**
- **Roadmap:** the CameraHub fan-out (`SPEC_CAMERA_PIPELINE.md`) so one capture serves rPPG + video + visuals; H.264/HEVC short-form record, NLE, ProRes.
- **TestFlight:** out of scope — video capture/edit is not wired today.

### 9. EchoelLux — `LIVE`
- **Code:** `Sync/ArtNetSender.swift`, `Sync/SACNSender.swift` (+ `ArtNetSenderTests`, `SACNSenderTests`)
- **Live:** native **Art-Net** (ArtDMX/UDP 6454, build 1543) **+ sACN / E1.31** (Data Packet/UDP 5568, **unicast** — iOS gates multicast behind the special entitlement; `multicastHost(universe:)` ready for when granted). Both zero-dependency, hand-built on Network.framework, sharing the bio→DMX mapping: dimmer←coherence, R←heart rate, G←HRV, B←breath. Smooth fades, no strobing (WCAG 3 Hz safe by construction). Opt-in from the Sync tab (host/universe per standard). Packet + mapping kernels unit-tested. Verification recipe: `scratchpads/SPEC_LIGHT_OSC_VERIFICATION.md`.
- **Roadmap:** sACN multicast (entitlement), fixture profiles, cue lists, HomeKit.
- **TestFlight acceptance:** an Art-Net node and/or an sACN receiver (sACNView/QLC+) shows the bio-reactive fixture move.

### 10. EchoelStage — `ROADMAP`
- **Code:** none. **Vision:** external displays, projection mapping (warp/edge-blend), multi-screen, NDI/Syphon, AirPlay.
- **TestFlight:** out of scope for build #1.

### 11. EchoelNet — `LIVE` (partial)
- **Code:** `Sync/OSCSender.swift`, `Sync/ADMOSCSender.swift`, `Sync/MIDIBusPublisher.swift`
- **Live:** OSC 1.0 over UDP — 5 continuous `/echoelmusic/bio/*` (`/bio/motion` is the 6th and is NOT sent in this build, #215: no motion sensor) + 6 discrete `/echoelmusic/bio/event/*` + `/echoelmusic/mod/*` (modulation), default `localhost:8000`. **Both bio paths carry provenance** via `/echoelmusic/bio/synthetic` (1 = the built-in demo generator, 0 = a real body): on the continuous batch it rides every tick that sends at least one value (#639); on the discrete events it is sent immediately before the event it describes and again only when the origin CHANGES, latched across polls (#785). Latch it as state — UDP does not preserve order. **ADM-OSC** immersive object output (`/adm/obj/{n}/position/{azimuth|elevation|distance}` + `/gain`, bio→object) into FletcherMachine/L-ISA/d&b — opt-in from the Sync tab. MIDI 1.0/2.0 input (⛔ **not MPE in** — #548/#770: the parser reads MPE traffic but tells no zones apart, and the consumer never reads `event.channel`, so no member channel exists to tell apart. The clause "`MIDIEventParse` has no Channel Pressure case at all … a single `break` for slide, air-CC and channel pressure" stood here until #939 parsed Press and #942 sounded Slide; only `.airCC` still breaks, and it is not an MPE dimension. The retraction is unchanged because it rests on ZONES, not on a count. **MPE OUT is real and switchable** since #713).
- **Beat-sync (audit fix 2026-06-09):** OSCSender now DRAINS the `bioEvents` SPSC queue (sole consumer) → every PolarH10 per-RR `.heartbeat` (+ breath/motion) event is sent at full resolution, no longer lost to the 100 ms snapshot. The synth's breath path still uses the independent `latestBioEvent` snapshot.
- **Roadmap:** Ableton Link tempo/phase, bidirectional OSC, RTP-MIDI, ADM-OSC native-protocol fallback lane.
- **TestFlight acceptance:** OSC frames reach a LAN receiver; ADM-OSC `/adm/obj/1/*` visible on an OSC monitor; heartbeat events arrive per-beat.

### 12. EchoelAI — `PARTIAL` (on-device generative, no cloud)
- **Code:** `Sequencer/BioComposer.swift` (deterministic bio→music generation), `DSP/SoundPrompt.swift` (semantic prompt→sound-design), `DSP/PatchLibrary.swift` (25-preset library).
- **Live:** **generative, not "AI" hype** — `BioComposer` turns biodata into an in-key melody + heartbeat rhythm + tempo (seeded → reproducible). **Prompt-based sound design** (`SoundPrompt`): a curated 24-descriptor vocabulary + intensity modifiers maps natural words ("warm lush pad", "bright glassy pluck") onto `SynthPatch` params — **fully on-device, deterministic, offline, private** (owner decision 2026-06-12: smartest *independent* variant + suggestions + a large preset DB; **no API, no LLM, no cloud**). `PatchLibrary` = 25 tagged factory presets across 8 categories as prompt starting points.
- **Roadmap:** on-device CoreML timbre transfer, stem separation; optional (opt-in) natural-language expansion — still local-first.
- **TestFlight acceptance:** a prompt ("warm lush pad") audibly shapes the synth; the preset library browses; generated melodies are in the chosen key.

---

## Ecosystem surfaces (the instrument extended across Apple platforms)

| Surface | Bundle | Status | Notes |
|---|---|---|---|
| **AUv3 plugin** | `…app.auv3` | `REMOVED` (2026-07-24) | Shipped in builds 1467/1469, then **deleted on purpose** by the pure-instrument epic #121 — Slice 1 dropped the target (`project.yml`, `Sources/EchoelmusicAUv3`, entitlements, CI scheme), Slice 2 dropped in-app AUv3 *hosting*. Echoel is a standalone instrument: neither plugin nor host, and not on the roadmap. Reaches a DAW via **WAV export** (`LoopExporter`) + live OSC/ADM-OSC/Art-Net. Also via **MIDI file export** — ⛔ this said "NOT via MIDI file export … no caller since the 2026-07-02 button removal", true until #188 restored the door (`EchoelStudioView.swift:6579`). `MIDIOutput`'s virtual source is `._1_0` and appears only when a Patchbay MIDI route is enabled; ⛔ "its `mpeEnabled`/`expressionEnabled` flags have no writer anywhere" stood here past #713 — both are persisted switches in the routing surface since then (banner 2026-08-28). |
| **Widgets** | `…app.widgets` | `LIVE` (shipped 1454→1469) | WidgetKit live bio glance, reads App Group via `BioFeedbackManager`. |
| **watchOS** | `…app.watchkitapp` | `COMPILE-VERIFIED, not embedded` | Bio glance; embed export-blocked (needs `WKCompanionAppBundleIdentifier` + Embed-Watch-Content phase verified in local Xcode). |
| **macOS (Catalyst)** | `com.echoelmusic.app` | `ROADMAP` (decided path) | Catalyst-first; native AppKit deferred. See `SPEC_ECOSYSTEM_TARGETS.md`. |
| **visionOS / tvOS** | `com.echoelmusic.app` | `ROADMAP` | Immersive / big-screen output. Separate-platform archive lanes (now cert-race-free). |
| **App Clip / Notification Service** | `…app.clip` / `…notification-service` | `ROADMAP` | Per `SPEC_ECOSYSTEM_TARGETS.md`. |

**Orientation (the Fahrplan):** THIS file is the spine — code-grounded status,
sequenced by value ÷ signing-risk. The **website mirrors** it (architecture.html /
tools.html), never the other way round ("if the website disagrees, the code wins").
Companion plans: `SPEC_ECOSYSTEM_TARGETS.md` (surfaces), `SPEC_CAMERA_PIPELINE.md`
(camera fan-out), `decisions.csv` (SDK doctrine, Oura-via-HealthKit, RTP-MIDI+Link).

---

## TestFlight build #1 — acceptance scope (the LIVE/PARTIAL set)

Ship only what is `LIVE` or the `LIVE` part of `PARTIAL`. Build #1 = a working
**bio-reactive performance instrument** on iPhone / iOS 18:

> ⛔ **THIS ACCEPTANCE LIST IS PRE-#121/#166 HISTORY (banner 2026-08-28)** — items 2
> (drums/sampler, deleted #166/#167), 4 (MPE-in, never built #548), 6 (no Sync tab; the
> matrix has no route, #541) and 7 (`BioVisualView` is gone) describe surfaces that no
> longer exist. Do not test a build against it; the live gate is CLAUDE.md's ship gate.

1. Synth is audible and bio-modulated (EchoelSynth) — silent until armed.
2. Beat sequencer plays with velocity/accent + swing; pads load custom samples (EchoelSeq).
3. Bio strip shows live HR/HRV/coherence; camera pulse locks; BLE strap shows name (EchoelBio).
4. MPE controller plays the synth (EchoelMIDI).
5. OSC + ADM-OSC stream bio/object out over UDP (EchoelNet).
6. Modulation matrix routes bio→tempo (Sync tab).
7. Well immersive visual reacts to bio (EchoelVis, BioVisualView).

**Not wired / not shipping** (re-corrected 2026-07-04): multitrack audio export, CAMERA video recording/editing (EchoelVid), RTMP streaming. **Now LIVE (the 2026-06-09 list was stale on these):** MP4 clips of the VISUAL (`VisualRecorder`), the Metal visual itself (MetalBioView, floating window), and lighting (`EchoelLux` Art-Net + sACN unicast). `EchoelStage`, `EchoelAI`, and all `Roadmap` rows remain out.

### Build/signing config of record (verify before each TestFlight run)
- **Target:** iOS 18, iPhone. `project.yml` + `Resources/iOS/Info.plist` + `Package.swift` all iOS 18. `MARKETING_VERSION 10.0.0`.
- **Info.plist source:** XcodeGen generates it from `project.yml` `info.properties` — keep it synced with `Resources/iOS/Info.plist`.
- **Entitlements:** HealthKit + App Group `group.com.echoelmusic` only. iCloud/CloudKit **disabled** (no code uses it; it blocks provisioning until the container is registered).
- **Signing (CI):** automatic, via App Store Connect API key secrets `APP_STORE_CONNECT_KEY_ID / ISSUER_ID / PRIVATE_KEY` + `APPLE_TEAM_ID`, `-allowProvisioningUpdates`. If archive succeeds but upload fails → check these secrets first (key created Dec may be expired).
- **AUv3 extension:** ❌ REMOVED 2026-07-24 (#121 Slice 1). It was enabled and shipped in 1467/1469; the target, its sources, its entitlements and the `EchoelmusicAUv3` compile-check scheme are all gone. Do not re-add without a founder ask. (Widget remains embedded + shipped. Watch dependency kept OFF — export-blocked.)

---

*Keep this file current: when a `ROADMAP` item gains code, move it to `PARTIAL`/`LIVE`,
add the file path, and mirror the change on `docs/architecture.html`.*
