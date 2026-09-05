# Echoel — Ranked Work Order

**Ordering rule:** what most raises (a) how alive and distinctive the instrument sounds and looks, and (b) whether a person can find it, understand it, and trust that it worked. An engineering defect is ranked only by which of those two it costs.

**Format:** each item gives the ask, why it matters, the smallest shippable slice, files, and gating. **FOUNDER-GATED** means it needs his hand or his ear (how something sounds or looks, or `project.yml` / `Info.plist` / `.github/workflows`). Everything else the agent can land alone.

---

## Cycle 0 — do this first regardless of rank

### 0. Un-red the blocking test bundle: two guards assert opposite things about the still shutter

**Why:** costs no user anything directly, but until it is green every later cycle's "green" means nothing, and the next real visual regression lands unseen. It is one file and it gates the other 30 items.

Verified on HEAD: `AStillIsOneFrameNotASecondPathTests.swift:86` requires the substring `visualRecorder.requestStill()` in `EchoelStudioView.swift`; `TheStillSaysWhetherItWasSavedTests.swift:101` forbids the substring `requestStill(`. The first contains the second, so **no tree can satisfy both**. Measured: `visualRecorder.requestStill()` → False, `requestStill(` → False, `StillShutterButton(recorder:` → True, `.sheet(` count → 14. The shipped source obeys the *second* guard, which is the correct one (the menu-hosting body must not own the tap — 10.76.41/50 freeze law).

**Slice:** delete the stale door assertion at `AStillIsOneFrameNotASecondPathTests.swift:86-89`. Do **not** re-point it at `StillShutterButton(recorder:` — that needle already exists verbatim at `TheStillSaysWhetherItWasSavedTests.swift:97` and duplicating it is the #416 trap. Keep the `.sheet(` == 14 non-growth check at `:92`; it still measures correctly.
**Files:** `Tests/CISmoke/AStillIsOneFrameNotASecondPathTests.swift`.
**Gating:** none.

---

## Tier 1 — the user cannot get in, cannot trust what they see, or loses work

### 1. Onboarding: make the pages scroll, so the Start button is reachable

**Why:** it is the front door and the only exit. `grep -c ScrollView Sources/Echoelmusic/Views/OnboardingView.swift` → **0**. `readyPage` is a bare `VStack(spacing: 24)` (`:139`) holding a 48 pt glyph, a heading, a paragraph, a six-row safety box, a consent Toggle and — last — the Start button whose `isComplete = true` (`:229`) is the sole writer of `hasCompletedOnboarding`. Every string scales via `EchoelTheme.font(relativeTo: .body)`, and onboarding is the **one** surface with no Dynamic Type ceiling (`WorkspaceView.swift:232` caps the instrument branch; onboarding is a sibling branch). Landscape is unlocked (`Info.plist:53-55`, no orientation lock in `Sources/`). In landscape the user can rotate back. **In portrait at accessibility sizes there is no in-app escape** — the user must leave the app to shrink system text, and this is exactly the user the WCAG-tuned safety copy on that page was written for. Install → cannot enter → delete.

**Slice:** wrap each of the three page `VStack`s in `ScrollView { … }`, replace the per-page `Spacer()`s with top/bottom padding, add `.scrollBounceBehavior(.basedOnSize)` so short pages still feel fixed. Precedent already in tree: `SafeModeView.swift:10, :52, :103-106` applies exactly this and says why.
**Files:** `Sources/Echoelmusic/Views/OnboardingView.swift`, plus one CISmoke guard asserting each `Page: some View` opens with `ScrollView`.
**Gating:** none.

### 2. A video take can end in silence and produce nothing

**Why:** an unrepeatable performance capture disappears with no signal. `VideoRecorder.stopRecording()` returns nil on three exits (`:90` not recording, `:103-107` armed-but-no-frame-ever-arrived, `:118-123` writer failed → `recordState = .error`), a fourth `.error` is set at `:167`, and **nothing in the UI reads `recordState`** (`git grep -n recordState -- Sources/Echoelmusic/Studio` → one doc comment). All three stop doors discard the nil (`FloatingVisualWindow.swift:1258`, `EchoelStudioView.swift:1575`, `VideoLibraryPanel.swift:246`). Worst case is the empty take: `RecordingBadge` counts wall-clock seconds off a `Date` while `elapsed` stays 0, so the performer watches a REC timer for a take that wrote nothing, then gets no share sheet, no library row, no sentence. The repo closed this exact defect class one commit ago for the *still* button (#986, `StillOutcome`/`lastStillOutcome`/`stillOutcomeToken`) and left the artefact that costs far more to lose silent.

**Slice:** add `TakeOutcome { saved, empty, failed(String) }` + `lastTakeOutcome` + `takeOutcomeToken` to `VisualRecorder`, published from **all four** exits; render it at each stop site. Note `StillShutterButton` has exactly one mount (`EchoelStudioView.swift:1607`), so the floating window and the library stop row need the answer leaf too — split into two cycles if three files is tight.
**Files:** `Sources/Echoelmusic/Video/VisualRecorder.swift`, `Sources/Echoelmusic/Video/VideoRecorder.swift`, one door + a CISmoke guard.
**Gating:** none.

### 3. The header pulse pill lies during a camera stall or an iOS interruption

**Why:** the pill is the only pulse surface visible while performing. With zero frames the analyzer is never called (`CameraRPPGBioPublisher.swift:1058-1061`), `ageConfidence`'s four callers all sit inside frame processing so nothing decays, and the publish loop copies the frozen `isFingerDetected / bpmConfidence / estimatedBPM / recentWaveform` on every tick (`:1201-1215`, `:1268`) — **above** the inbound guard at `:1378` that correctly stops feeding the bus. Result: green "locked" accent, confident BPM, a still-plausible trace, while the music has eased to idle because the instrument stopped following the body. Indefinite while iOS holds the camera interrupted, indefinite in a sub-6 Hz trickle. The honest sentence exists (`RPPGRecoveryState.userHint`, "Camera paused by iOS — waiting to resume") and `grep -n recoveryState Sources/Echoelmusic/Studio/HeaderMonitors.swift` → **zero hits**.

**Slice:** at `HeaderMonitors.swift:293`, gate `locked` on frames-actually-flowing — expose the same predicate the bus uses (`inboundRateEMA >= minMeasurableInboundHz`), or accept only `.interrupted`/`.recovering`. Do **not** gate on `recoveryState == .healthy`: `:1176-1180` drops to `.cooling` on thermal state alone while frames and the bus feed are fine, which would blank a genuinely measured BPM. Add a short form of the hint (`"Camera paused"`) for the `status:` slot — the existing 40-char sentence is built for `BioStripView`'s wrapping banner, not a `minWidth: 28` group at 11 pt.
**Files:** `Sources/Echoelmusic/Studio/HeaderMonitors.swift`, `Sources/Echoelmusic/Bio/CameraRPPGBioPublisher.swift` (expose the predicate + short string).
**Gating:** none.

### 4. Both save paths answer nothing on failure

**Why:** success is loud (share sheet, a row); failure is indistinguishable from a dead button. **WAV:** the Record tile lives on the always-visible front plate (`EchoelStudioView.swift:2152`) while its only failure sentence renders inside the Save & Export dropdown (`:8280`, in `utilityRow`) — placed there under a #216 comment saying "sits where the user is already looking", which was true until #482 moved the button out of that panel. The tile itself has no `.failed` branch in `exportIcon`/`exportLabel`. **Project:** `ProjectStore.persist()` (`:170-172`) is `_ = store.save(...)`, discarding a `Bool` that `AppGroupStore.swift:171-198` returns `false` from three branches, while `ProjectStore.swift:33-36` inserts into the in-memory array *before* persisting. The row appears, the take looks saved, and it is gone at next launch.

**Slice:** ship the **WAV half alone** — move the `exportFailure` line onto the front plate beside the existing `if !hasComposed { … }` line in `startControlRow`. Inline row, never an `.alert` (the modifier chain is pinned at 14). The project-save half is registered as founder-gated question #515 (`AppGroupStore.swift:152-155`, pinned by `AFailedSaveLeavesATraceTests:212`) — raise it, do not implement it unilaterally.
**Files:** `Sources/Echoelmusic/Studio/EchoelStudioView.swift`, one CISmoke guard.
**Gating:** the WAV half no; the project half FOUNDER-GATED (#515 is an open surface question).

### 5. Turn the first-run guide ON — it is the only place the app says the picture is playable

**Why:** the highest artistic payoff per byte in this whole list. `StudioDefaultKeys.swift:51` ships `guideVisible` = `false` (verified on HEAD), and the only writer that sets it true is the user's own Toggle in the Save & Export panel, next to Reset and Diagnostics. The card it gates, `guide.see` (`LearnLibrary.swift:88`), is the **only** in-app sentence that says *"Touch it to play notes — every touch lands in key, so there is no wrong place."* Onboarding never mentions it; its final line is "Press Play to start… Export to your DAW." Meanwhile `TouchInstrumentView` is mounted at `FloatingVisualWindow.swift:791` and the window opens on launch. So a new user spends their first two minutes looking at a full-screen living picture that is silently a six-voice, scale-locked, pressure-sensitive instrument, framed by every word the app has said as *output*. They read it as a screensaver. That is the difference between "an ambient loop generator" and "an instrument worth practising."

**Slice:** flip `:51` to `value: true`. The overlay already self-dismisses (`GuideOverlay.swift:104` sets it false on the last card, `:71` on the X), so it shows once. Reorder `LearnLibrary.guideEntries` so `guide.see` is not last.
**Files:** `Sources/Echoelmusic/Core/StudioDefaultKeys.swift`, `Sources/Echoelmusic/Studio/LearnLibrary.swift`, + `Tests/CISmoke/TheGuideOpensOnFirstLaunchTests.swift`.
**Gating:** **FOUNDER-GATED** — it changes what he sees on first launch. Recommend strongly; it is one boolean.

---

## Tier 2 — the image and the sound

### 6. Stop the picture pinning breath at its dimmest for every camera session

**Why:** one line, immediately visible. `MetalBioView.swift:987` reads **raw** `breathPhase` — `breath: bio.map { sin(Float.pi * min(max($0.breathPhase, 0), 1)) } ?? (idle ? idleBreath : 0.5)` (verified on HEAD) — while its own neighbour nine lines up reads the guarded `coherenceForSound`. Every non-HealthKit publisher writes a literal `breathPhase: 0` when it measures no respiration (`PolarH10BioPublisher.swift:223` always; `FaceExpressionBioPublisher.swift:155`; `CameraRPPGBioPublisher.swift:1584` until breath locks — and that gate's own device note at `:1538-1547` says it "never opened while signal quality was nominally high"). A present frame switches `idle` off, killing the drifting idle sine, and `sin(0) = 0` pins `restGlow` at its 0.07 floor of a 0.07…0.21 span — **half** the neutral resting glow — and multiplies the heartbeat bloom by that floor. The one element that says "your heart drives this" reads at half brightness for the whole take. HealthKit is worse in the other direction: its 0.5 placeholder gives `sin(π·0.5) = 1.0`, pinned at the ceiling, for a source that measures no respiration at all.

**Slice:** gate the read on `hasMeasuredBreath` and fall back to the **constant 0.5 magnitude** the existing `?? … 0.5` arm already uses — not to `idleBreath`, which fabricates a drifting breath while a real sensor is attached, and not to `breathPhaseForSound`, which is a phase and would map neutral to the *brightest* value through the `sin(π·x)` fold.
**Files:** `Sources/Echoelmusic/Views/MetalBioView.swift` (+ one CISmoke guard pinning that no visual consumer reads raw `breathPhase`).
**Gating:** **FOUNDER-GATED** (it changes the picture) — but it restores a documented neutral, so it is a low-risk look.

### 7. Publish a real breath **phase** from the camera

**Why:** `RespirationEstimator.amplitude` is a 0.5-centred sinusoid ("1 = inhale peak"), and `CameraRPPGBioPublisher.swift:1584` publishes it into `breathPhase`, a field whose contract (`EngineBus.swift:238-245`) is a wrapping sawtooth. Three classes of consumer fold it as a phase. Consequences, honestly sized: the audio swell doubles its rate with minima at *both* breath extremes but is bounded by `swellDepth` to 0.9 dB (`EchoelDDSP.swift:2237-2245`) — small; the armed "Body voice" fires `playNote` once per breath at `BioEventGraph.swift:154` while the exhale wrap at `:150` cannot be satisfied by a smooth sinusoid at the ~1 Hz publish rate, giving **a sustained drone re-attacked each inhale, never released**, at exactly the slow resonance rates the breath guide paces toward; and `/echoelmusic/bio/breath/phase` leaves the device carrying an amplitude labelled a phase, to external light and space rigs. It also unblocks item 20 (Aurora).

**Slice:** `RespirationEstimator` already holds `periodEMA` and the crossing timestamps — publish `phase = fract((t − lastAcceptT) / periodEMA)`, held at the unmeasured sentinel when no period is accepted. Anchor on `lastAcceptT`, **not** `lastCrossT` (`:502`, `:747-750` show the latter advances on rejected noise crossings). Then publish `resp.phase` at `:1584`. Keep `amplitude` — the breath-guide ball wants fullness. Retract the now-partial note at `EngineBus.swift:238-245`.
**Files:** `Sources/Echoelmusic/Bio/RespirationEstimator.swift`, `Sources/Echoelmusic/Bio/CameraRPPGBioPublisher.swift`, `Sources/Echoelmusic/Core/EngineBus.swift`.
**Gating:** **FOUNDER-GATED** (changes how the breath swell and the picture move).

### 8. Give the second bio→timbre character a door: "Harmonic mapping"

**Why:** the instrument ships one bio voice while the engine holds two. `bioMappingHarmonic`'s only writer is `BioSourceView.swift:122-123`, and `git grep -c "BioSourceView(" -- Sources` → **0**. Everything downstream is live: `bioModulationEnabled` is armed automatically at take start (`EchoelStudioView.swift:9012`), the profile line runs every take (`PolySynthVoice.swift:962`), and `.harmonicSeries` *replaces* rather than tints — `EchoelDDSP.swift:2354` gives HRV absolute control of harmonicity (`0.40 + hrv·0.50`, span 0.40–0.90) against `.natural`'s ±0.06 nudge around the patch base, and deepens the breath swell 0.10 → 0.18. HRV is the channel a performer can most consciously move by slowing the breath. This is range already paid for in build size that nobody can play.

**Slice:** one Toggle in the reachable `bioPanel` (door: the pulse pill), in the `BreathVoiceRow`/`AutoModeRow` zero-modifier shape, beside "Body voice". Note "Body voice" writes `arm()/disarm()` on `BioReactiveSynthVoice`, **not** `bioModulationEnabled` — the new toggle is independent, and only bites while a take runs. Label it as mapping character, never with a wellness word. Do not re-door `BioSourceView` (it drags in a second camera arm, a second pulse readout, and `BreathGuideView`).
**Files:** `Sources/Echoelmusic/Studio/EchoelStudioView.swift`, one CISmoke guard, + the doorless-register line in `CLAUDE.md`.
**Gating:** **FOUNDER-GATED** (a new bio→sound character on screen).

### 9. Re-seed `_smoothedBrightness` on patch apply — stop genres bleeding into each other

**Why:** this leaks straight through the `bioBase*` anchor law that exists to give each patch its own centre, and it does so exactly while a performer is A/B-testing whether the genres are distinct — the repo's longest-running artistic complaint. `EchoelDDSP.swift:1746` seeds `_smoothedBrightness = 0.25` and `SynthPatch.apply(to:)` cannot reach it: it writes `synth.brightness` (`:777`) and `synth.bioBaseBrightness` (`:784`), and the next bio frame overwrites the live property with the accumulator (`:1994`). At `smoothCoeff = 0.6065` on the ~1 Hz bio clock (τ ≈ 2 s), a 0.8 → 0.1 switch reads 0.524 on the first frame and takes ~5 s to converge. The in-file proof it is an oversight, not a design: `filterCutoff` (`:2169`) smooths *in the live property* `apply(to:)` writes, so it self-re-seeds — brightness is the one control-rate pole a patch cannot reach. On the poly path each voice owns its accumulator and only voices holding a note are updated (`:3376`), so an idle voice's brightness can be stale from a patch two switches ago and chord voices can hold different brightnesses for seconds.

**Slice:** brightness only. Seed `_smoothedBrightness = -1`, add `if _smoothedBrightness < 0 { _smoothedBrightness = targetBrightness }` before `:1993`, and re-arm that sentinel from `SynthPatch.apply(to:)`. **Drop `_smoothedAmplitude`** — its target carries no patch term, so a re-seed there is a no-op.
**Files:** `Sources/Echoelmusic/DSP/EchoelDDSP.swift`, `Sources/Echoelmusic/DSP/SynthPatch.swift`.
**Gating:** **FOUNDER-GATED** (timbre), but with an ear-test that is trivially designed: switch two genres back and forth.

### 10. Flow mode: compute note density at the tempo the clock actually plays

**Why:** Flow is the **shipped default** (`StudioDefaultKeys.lockBPM` = false). `BioComposer.swift:862-863` feeds `tempoDensityScale` the un-folded servo tempo from `tempo(for:)` (`:450-455`, clamped 40…160), while both unlocked clock branches (`EchoelStudioView.swift:9781-9784`, `:9805-9808`) play that same value **octave-folded into the genre window**. A resting body at 60 BPM gives `tempoDensityScale(60) = 1.0` — full density — over a groove the transport runs at ~127. The anti-hectic coarsening that exists for the founder's own "auf 132 zu hektisch" never fires for a calm body on any 118–150 BPM genre, so the arp step and inner pulse never thin and the lead count is never cut. **The calmer the performer gets, the further the two halves diverge** — the reward is inverted. The locked twin of this defect is explicitly parked at `:9755-9764`; the Flow half is parked nowhere, and `MusicStyle.swift` plus a blocking guard (`GenreFamilyDistinctnessTests.swift:191-206`) both reason at the genre-window tempo the composer never receives — a guard pinning a distinction the default runtime does not produce.

**Slice:** at the density decision only — leave `tempo(for:)` and `suggestedTempo` alone (T2 and `TempoInvariantTests` bind them). `let clockTempo = StudioCalculator.genreTempo(playTempo, into: input.style.tempoRange)` for `.flowFree`, feed density from that. The fold is idempotent in-range, so calm contemplative genres are byte-identical. Note the residual: the clock also applies `tilted(...)` after the fold — within-window, note it in the guard rather than chasing it.
**Files:** `Sources/Echoelmusic/Sequencer/BioComposer.swift`, one CISmoke guard.
**Gating:** **FOUNDER-GATED** — device listen, ship alone.

### 11. The "inner PULSE" layer fills the gap that IS the groove on the stab genres

**Why:** directly on the founder's live ask (Deep Tech · Dark Minimal · Deep House · Psy Prog House). On two-section stab genres the block at `BioComposer.swift:2603-2629` emits **one held note per chord section**, an octave above the pad, starting on `secStart` — precisely the stab's own downbeat — and because `pt` resets each section it is always the same chord-tone slot: no rhythmic and no melodic movement. techHouse's own patch comment says the short release exists "so the stab stops before the next one lands (that gap IS the groove)". It is also the one layer the Pad-rhythm picker cannot reach (the block is a sibling of the `padBeats` chain and reads no character variable).

**Slice:** the rate cap does **not** fix it — `plen = pulseGap` (`:2623`) makes the layer 100 % duty-cycle at any rate, so capping the gap just doubles the attacks on the same continuous fill. Ship exactly one of: (a) decouple length from gap — a short fixed `plen` of 1–2 steps plus `ps = secStart + pulseGap/2` to move off the downbeat; or (b) gate the block off when `articulation == .stab`. Ship alone, with a device listen.
**Files:** `Sources/Echoelmusic/Sequencer/BioComposer.swift`, one CISmoke guard.
**Gating:** **FOUNDER-GATED** — this is an ear call between two options.

### 12. Stop HealthKit overwriting the source the performer chose

**Why:** `EngineBus.latestBio` is a single slot. `EchoelmusicApp.swift:1334/:1363` start the HealthKit publisher at app level, and `stopBioSource()` (`EchoelStudioView.swift:9235-9243`) stops camera, Polar and demo — **not** HealthKit — under a doc comment reading "Stop EVERY bio publisher… so no source keeps feeding the bus", with `selectBioSource`'s doc adding "Only ONE source feeds the bus at a time". Both are false. So for any Health-authorised user, every new wrist sample overwrites the camera/strap frame: the four always-on timbre channels are handed the neutral 0.5 instead of a measured 0.85, and **every surface that reads `usableBio()` flips its source label mid-take** — `BioStripView`, `AutomationStatusStrip`, `BodyShapesThisSoundLine`, `AlwaysOnBioRow` — showing a 4–5 s latent HR from a different origin for no reason the player can see. The τ ≈ 2 s smoother attenuates each excursion to ~39 %, so it reads as a periodic tone wobble on a ~4–5 s cycle: the engine sounding unstable, not the body being followed.

**Slice:** the repo's own recorded playbook is *"geteilter Zustand hinter einem 'gemessen?'-Tor — HALTEN, nicht nullen"* (`HARNESS_LEDGER.md:1428`). Apply it at the two consumers: hold the last measured level per channel rather than substituting neutral. Do **not** stand the publisher down — the interleave is deliberate and documented (`BioEventPublisher.swift:45-56`, the 90 s wrist window, and a DEAD-END entry against source arbitration).
**Cheap half, land first:** correct the two false doc comments at `:9233-9234` and `:9249` to name HealthKit as an app-level publisher the picker does not own. Three slices have now each had to rediscover this interleave from scratch.
**Files:** `Sources/Echoelmusic/Studio/EchoelStudioView.swift` (comments); then `Tools/BioReactiveSynthVoice.swift` + `Tools/PolySynthVoice.swift` (hold).
**Gating:** comments no; the hold change **FOUNDER-GATED** (timbre).

### 13. Brightness 0.60–0.72: the app can never lock and sends the user to warm their hand

**Why:** this is the binding constraint of the entire product — getting a pulse at all — failing silently *in the direction of wrong advice*. `canLockNow` refuses at ≥ 0.6 (`CameraRPPGBioPublisher.swift:743, :749-751`) while the coaching classifier's flood test is `isWashedOut` at > 0.72 (`:620`, `:885-887`). In the band the machine has decided the scene is flooded and the screen never says "light": the cue falls to `.finding` and after 45 s latches `.stalled`, whose strings are "lift your finger and place it again" and "**try another finger, or warm your hand first**" — while the correct remedy, `PulseCue.tooBright` "Press a little lighter", is unreachable there. During the first ~6 s of finger presence the uncued unlockable band is wider still (0.28–0.72, via `strictLockBrightness`). The file indicts itself at `:593-598` and cites the device value 0.62 twice. For a first-run user this is the difference between the instrument working and the instrument appearing broken.

**Slice, and it must be a measurement first:** add the band and `lastFilteredAmplitude` to the diagnostic breadcrumb so a device session shows whether brightness actually rests in [0.60, 0.72) and for how long. The wording change itself is a parked founder/device call (#304/#410, pinned in `OneDefinitionOfTooBrightTests.swift:18-24`) and could swap one wrong sentence for another — this file attributes 0.6–0.8 to "finger lightening / re-grip", not flooding. The per-frame-churn objection to putting `.tooBright` in the banner is already answered by the `BioTrustLatch` at `:554-560`.
**Files:** `Sources/Echoelmusic/Bio/CameraRPPGBioPublisher.swift` (breadcrumb only).
**Gating:** breadcrumb no; **the wording is FOUNDER-GATED** and needs the log first.

---

## Tier 3 — the instrument's reach: what the performer plays, and where it goes

### 14. Mirror the touch surface's notes to MIDI out

**Why:** the app's one genuinely human, expressive gesture — six voices, scale-locked, velocity from contact area, slide-glide — is the one thing that cannot leave the device as data. `grep -n "midiOut\|MIDIOutput\|Recorder" Sources/Echoelmusic/Studio/TouchInstrumentView.swift` returns **one line in 1429**, and it is a doc comment. The surface's only sinks are `synth?.noteOn/noteOff` and `TouchToneChannel` (visual-only; sole external reader is `MetalBioView.swift:775`). Meanwhile the `.mid` export takes its notes from `pianoRoll.arrangementForExport()` and the only two producers of MIDI-out notes are the generated arrangement and MIDI-in thru. So a performer can export what the machine wrote and not what they played, and their playing is invisible to a hardware rig while the loop drives it fine. For the audience of the "MIDI I/O" identity line, that is exactly backwards.

**Slice:** `FloatingVisualWindow` already sits in an environment carrying `MIDIOutput` — pass it into `TouchInstrumentView(...)` at `:791` as it already passes `synth:`, and call `midiOut?.noteOn/noteOff` beside each existing `synth?.noteOn/noteOff` (7 + 2 sites). `midiOut` is already in `panicAllNotesOff`'s fan-out, so stuck notes are covered. **Do not bundle the roll/export half** — note capture sits near the Editor/Workstation boundary and is a founder call.
**Files:** `Sources/Echoelmusic/Studio/FloatingVisualWindow.swift`, `Sources/Echoelmusic/Studio/TouchInstrumentView.swift`, `Tests/CISmoke/ThePlayedNotesReachTheWireTests.swift`.
**Gating:** none.

### 15. Persist the audio buffer choice

**Why:** the only latency control in the app is `@State` (`AudioInputPickerView.swift:648`) — no `@AppStorage` in the file, no key in `StudioDefaultKeys`, no re-apply at launch. A performer who feels the water surface lagging, digs into MASTER → "Audio input" (a *microphone* sheet — nobody tuning touch response looks there), sets Ultra (128 / 2.7 ms) and finally gets a responsive instrument, gets 512 back on the next launch with the segmented control cheerfully reading "Normal". And the shipped default `normalBufferSize = 512` is 10.67 ms — already outside this repo's own stated <10 ms target before hardware I/O is added, so out of the box the play surface is at its least responsive *and* the fix does not stick.

**Slice:** add `latencyMode` to `StudioDefaultKeys`, switch `:648` to `@AppStorage`, write it after a successful `setLatencyMode`, re-apply once at launch in the existing audio-configuration `do/catch` (a refusal falls back to 512 and logs). Moving the door out of the mic sheet is a separate UI slice.
**Files:** `Core/StudioDefaultKeys.swift`, `Studio/AudioInputPickerView.swift`, `EchoelmusicApp.swift`, + `Tests/CISmoke/TheBufferChoiceSurvivesRelaunchTests.swift`.
**Gating:** none (persisting a user choice); the **default** value is FOUNDER-GATED.

### 16. Make the network "sending" dot mean a datagram left the device

**Why:** it fires exactly where recovery is impossible — on stage, pre-doors. All four senders set `isActive = true` one line after `connect()` (`OSCSender.swift:120`, `ADMOSCSender.swift:133`, `SACNSender.swift:117`, `ArtNetSender.swift:138`), every datagram discards its completion error (`.contentProcessed { _ in }`), `git grep -n stateUpdateHandler -- Sources` → **zero**, and `PatchbayView.swift:289-293/:339` renders and announces that flag as "sending". Concretely: the dot reads "sending" with the engine stopped and no publisher running; and the OSC row — whose only live path is bio-gated — reads "sending" for a whole session when the bus's latest frame is `.healthKit`, because `BioEgressPolicy` refuses that source and no user-facing string anywhere explains the rule. `ImmersiveStageView.swift:249-257` is worse: it asserts *"Streaming N object(s) to host:port"* from the same flag, under a comment promising "one honest line for every state".

**Slice:** **not** `stateUpdateHandler` — UDP `.ready` is reached for any routable literal IPv4, and both light senders default to exactly those (255.255.255.255, 192.168.1.100), so that change would leave the wrong-IP rig still filled. Wire the already-computed, zero-reader `lastSentTimestamp` (declared in all four senders for precisely this purpose). It is stamped at 20–30 Hz, so the read must live in a **per-row leaf view** with its own staleness tick (the `PulseMonitorMiniLive` pattern), never in the Patchbay body — that body hosts the host/port fields and Pickers. Copy says "sending" vs "idle", never "connected". Watch the honest non-stamping cases: the light senders' hold arms and ADM's static-scene guard legitimately stop stamping while the output is correct.
**Files:** `Sources/Echoelmusic/Studio/PatchbayView.swift` (+ new leaf), `Sources/Echoelmusic/Studio/ImmersiveStageView.swift`.
**Gating:** none.

### 17. Address more than one lamp

**Why:** Echoel's positioning names Installation · Event · Cinema · Theater and the light output writes a single 4-channel block starting at DMX slot 1. `ArtNetSender.dmxChannels(for:)` returns 4 bytes (8 in 16-bit); `startChannel` exists **only** inside `LightFixtureGroup`, whose `composeUniverse()` has zero callers; the Light UI offers Master, Blackout and bit-depth and nothing else. The two protocols fail differently: Art-Net's short packet leaves other fixtures holding stale values; **sACN pads to a full 512 slots, so it actively drives every other fixture to zero — they go dark and stay dark.** The artist's only workaround today is re-patching every lamp in the venue onto address 1.

**Slice:** two `EchoelValueField`s in `PatchbayView.lichtSection` — "Fixtures" (1…32) and "Spacing" — writing `fixtureCount`/`fixtureSpacing` on `ArtNetSender`; then in `sendIfFresh`, **after** the existing slew lines, replicate the already-slewed `channels` block N times into a ≤512-byte buffer. Do **not** route through `composeUniverse()` — it re-applies its own master/blackout and would bypass `FlashGuard.slewedDimmer`. Sell it honestly as *addressing the rig*, not spatial differentiation: N fixtures get N identical colours, because both DMX arms produce one global colour. Per-fixture variation needs a producer that exists nowhere and is a later slice.
**Files:** `Sync/ArtNetSender.swift`, `Sync/SACNSender.swift`, `Studio/PatchbayView.swift`.
**Gating:** none for the addressing; **FOUNDER-GATED** for anything that changes what the lamps *do*.

### 18. The launch screen sheds the only labelled door back to the instrument

**Why:** first screen after onboarding, whose last words were "Press Play to start". `WorkspaceView.swift:323-325` seeds the visual visible and fullscreen on every cold launch; the fullscreen bar needs 529 pt and sheds `lookSlider` (→431 pt) then `studioChip` — so on 375/390/393/402/430 pt phones in portrait the word "Studio" is gone and what remains are two glyphs whose meaning lives only in VoiceOver. The user is handed a picture, told to start the music, and given no word and no Play button. The guard that reads as if it covered this — `ChromeBudgetFitsTests.testFullscreenFitsWithTheSliderAndTheStudioChip` (renamed `testFullscreenFitsAtEveryShippedWidth` by #1017) — makes one assertion (`barWidth <= bounds.width`) and never inspects `fit.studioChip`.

**Slice:** add `XCTAssertTrue(fit.studioChip)` inside the existing loop at `ChromeBudgetFitsTests.swift:194`. **It goes red on today's tree, and that red IS the report.** Do not ship the shed reorder as a "fix": it inverts a ranking documented as a product decision at `FloatingVisualLayout.swift:285-289` and would permanently remove the live loop-position readout from fullscreen on every phone under 440 pt. The cheap alternative that costs nothing is shrinking the chip to icon + shorter reserve, or labelling the two existing exits visibly.
**Files:** `Tests/CISmoke/ChromeBudgetFitsTests.swift`; then `Studio/FloatingVisualLayout.swift`.
**Gating:** the guard no; **the shed order and the chip design are FOUNDER-GATED.**

**⛔ THE SLICE AS WRITTEN ABOVE WAS NOT SHIPPED, AND THE REASON IS THIS FILE'S OWN GATING LINE (#1017).** `ChromeBudgetFitsTests` lives in `Tests/CISmoke` — the **blocking** bundle. `XCTAssertTrue(fit.studioChip)` there is red on a correct tree, so it does not "report", it **stops every push** until a repair the same paragraph marks FOUNDER-GATED lands. An audit item may not hold the gate hostage to a decision it has already said is not ours.

**What shipped instead, all measured:** (a) the test is renamed `testFullscreenFitsAtEveryShippedWidth`, because the old name promised coverage of two items it never inspected — the reason the shed went unseen (#374); (b) the thresholds are recorded on it: the chip needs **431 pt** and the slider **529 pt** idle, **507 / 605 pt** while a WAV take runs, against a widest shipped phone of 440 pt; (c) a new `testTheShedOrderIsAPrefixOfTheDocumentedRanking` pins the ranking `chromeFit`'s prose asks to be protected from a quiet reorder — chosen because prefix-ness survives every repair on the table (a cheaper chip moves the threshold, not the order), whereas pinning "the chip survives at 393 pt" would pin the defect and go red on a tree that just got better (#364).

**⛔ And one premise of this item is now stale in the app's favour:** "given no word" — a first-run overlay does show two labelled lines (`FloatingVisualWindow.swift:1449`, "Start the music, then a finger on the back camera" / "Touch the image to play notes"). What is genuinely missing is narrower and still real: that overlay tells the user to start the music, and the only way to reach Play is one of the two unlabelled glyphs. **The founder question is the chip's 83 pt text reserve, not the word count.**

---

## Tier 4 — what the outside world is told

### 19. The website denies the app's most distinctive interaction

**Why:** worst claim defect in the set, because it is not silence — it is an active denial. `docs/faq.html:133-134`, the item literally titled *"What touch instruments are available?"*, answers that in-app you only shape the patch in the patch editor, and closes *"Dedicated touch instruments … are on the roadmap, not in the app today"* — while a scale-quantized multi-touch surface ships and opens on launch. `docs/faq.html:114` repeats it with a Planned tag. And it is in **no** acquisition copy at all: zero hits for touch/finger/berühr/tippen across all 16 files in `fastlane/metadata/`, and zero across every page under `docs/`. A musician evaluating the listing or the site has no way to learn the instrument has hands.

**Slice:** rewrite the FAQ answer to lead with the shipped surface (keeping the four named pads — chord pad, XY pad, multi-octave keyboard, strum pad — as genuine roadmap); add one bullet to both `description.txt` files; add a ✅ capability row to `ContentPipeline/CLAIMS.md` citing `FloatingVisualWindow.swift:791` so scripts can use it. Note in the copy that the surface follows the take's patch **by default** but can hold its own selection.
**Files:** `docs/faq.html`, `fastlane/metadata/{en-US,de-DE}/description.txt`, `ContentPipeline/CLAIMS.md` (split across two cycles).
**Gating:** none — but user-facing copy, so run it past The Council per the brand rule.

### 20. "Ten generative looks" → four

**Why:** claimed in six places including **two Schema.org blocks** that answer engines ingest verbatim (`docs/index.html:104, :803`; `docs/faq.html:44, :114, :186`; `docs/version.json:34`), while `LookBlendMap.swift:35-37` defines Rings/Water/Aurora/Depth and the only chip source is `EchoelStudioView.swift:5915`. Two of the sentences self-contradict — "ten generative looks — Rings, Water, Aurora and Depth". A reader counts four names, concludes the site does not check itself, and discounts the hard-won claims that *are* true (Art-Net/sACN, ADM-OSC, MPE out). Not in `fastlane/metadata`, so it is an SEO/truth defect, not live 2.3 exposure.

**Slice:** replace the phrase in all six places.
**Files:** `docs/index.html`, `docs/faq.html`, `docs/version.json`.
**Gating:** none.

### 21. Correct the "space" mapping in the store description

**Why:** both locales (`en-US/description.txt:11`, `de-DE:11`) list "space"/"Raum" inside a list of **automatic** body→sound mappings whose other three entries are genuinely automatic. There is no automatic synth path to space: the one write (`EchoelDDSP.swift:2311`, `reverbMix` from HRV) is read only inside `if Self.useConvolutionReverb`, declared `false` at `:853` with **no assignment anywhere in `Sources/`**. Two real bio→space paths do ship — an opt-in FX route to `EchoelReverb`, and ADM-OSC object position — so the fix is re-attribution, not deletion. The repo already struck this same claim from three other surfaces; this is the fourth and the only one where being wrong is a review conversation.

**Slice:** keep the automatic list to "brightness, harmonicity and texture"; name space where it is true (the ADM-OSC / FX section already in the same file). Add a proximity needle to `TheStoreTextClaimsOnlyWhatShipsTests` for the always-on bullet only — do not ban the word.
**Files:** `fastlane/metadata/{en-US,de-DE}/description.txt`, `Tests/CISmoke/TheStoreTextClaimsOnlyWhatShipsTests.swift`.
**Gating:** none.

### 22. The safety copy is wrong about safety

**Why:** the one screen a photosensitive user is asked to tick "I understand" against. `LearnLibrary.swift:194-196` says visuals "freeze entirely with Reduce Motion on; if you are photosensitive, turn Reduce Motion on before you start", and `OnboardingView.swift:191` prints an unqualified 3 Hz guarantee above the consent toggle. Nothing freezes entirely: `HeaderMonitors.swift:501` holds the pulse at 0.5 but leaves the unslewed `0.35 * masterLevel` live on an unpaused 20 Hz `TimelineView`; `:601`'s `0.3 + 0.7 * masterLevel` has no slew anchor and its own Reduce-Motion branch concedes the colour still moves; `git grep -n reduceMotion -- Sources/Echoelmusic/Sync` → **zero**, so no lamp honours it; and even `MetalBioView` keeps a music swell (eased, well under 3 Hz, but not frozen). The lamps *are* rate-limited by `applySlewedColour` to ~1.2 Hz, so the 3 Hz half holds there — only "freeze entirely" is false everywhere.

**Slice:** copy only, two files. Say that the immersive visual freezes its motion while the small header monitors and connected fixtures follow the music rate-limited rather than frozen, and name **Blackout** as the instruction that works on a rig; narrow the onboarding row to the immersive visual or drop the numeric guarantee. The behavioural half (slewing the two `masterLevel` terms through `FlashGuard.limitedLuminance`) is already registered as a follow-up at `HeaderMonitors.swift:557-565` and belongs in its own slice with a device look.
**Files:** `Sources/Echoelmusic/Studio/LearnLibrary.swift`, `Sources/Echoelmusic/Views/OnboardingView.swift`.
**Gating:** none for copy; the slew is **FOUNDER-GATED** (chrome appearance).

### 23. The site has no image, video or audio of an audiovisual instrument

**Why:** the single largest artistic failure on any outward surface. All 24 pages under `docs/` contain zero `<img>`, `<video>`, `<audio>`, `<iframe>`, `<canvas>`; the only content raster is `og-cover.png`, a typographic brand card referenced solely from `og:image`. A musician judges an instrument by ear and eye in ten seconds and gets a sentence about a Metal GPU renderer. `docs/press.html:157` tells journalists screenshots and preview video are "available on request (device captures in progress)". Every competitor leads with 8 seconds of motion.

**Slice, split honestly:** the agent **cannot** produce the asset — that is a founder device capture, already logged as one in `scratchpads/FOUNDER_DEVICE_SESSION.md:74-79 §4`, and `ContentPipeline/Assets/README.md:3-5` gates committing raw video. What the agent *can* land: prepare the slot — a `<video muted autoplay loop playsinline poster>` block inside the existing `@media (prefers-reduced-motion: reduce)` guard at `docs/index.html:567`, with the poster as fallback — and write the ask. `index.html` inlines its own `<style>` and does not load `shared.css`. Do **not** touch `artist.html` (standing "do not build a player" gate at `docs/CLAUDE.md:23-27`), and never use `docs/screenshots/*.html` — those are CSS mockups, a worse claim than none.
**Files:** `docs/index.html`, `docs/press.html`.
**Gating:** **FOUNDER-GATED** — the asset needs his device and his eye.

### 24. Give press and testers a door

**Why:** `docs/press.html:114` tells journalists "Coming soon to the App Store (**TestFlight now**)" and `docs/brainstorming.html:121/131` is an entire page addressed to testers ("What you actually get in TestFlight today", "In TestFlight now — Live") — while `grep -rni testflight docs/*.html` returns prose only, zero `href`s, and no form on any page. A reader convinced by those pages has no route to the build they say exists. (The hero span is *not* the defect: a live tester/collaborator mailto already sits 65 lines below it at `docs/index.html:722`.)

**Slice:** one label edit on press.html's Availability row and one at the top of brainstorming.html — a real join link if the build is open, otherwise "Request TestFlight access" pointing at the existing mailto.
**Files:** `docs/press.html`, `docs/brainstorming.html`.
**Gating:** **FOUNDER-GATED** if a public TestFlight link is to be enabled; the label edit alone is not.

---

## Tier 5 — instruments that measure the product, and registers that misdirect the next cycle

### 25. Read the full test suite's answer: it compiles clean and 8 tests fail

**Why:** the workflow's own header makes adopting the full suite conditional on this reveal; **half that condition is already met and nobody knows**, because `continue-on-error: true` on both xcodebuild steps rewrites `conclusion`, so the run card, the run list and every step read `success`. Measured on HEAD (run 33909501464): `build-for-testing: success`, `test-without-building: failure`, empty build-errors block, eight named failures — `StudioDefaultKeysTests.testCanonicalDefaults_matchFounderDecisions`, `ModulationEngineTests.testApply_smoothing_rampsTowardTarget`, two `PolySynthAutomationBindTests`, `ProjectCodableTests.testExplicitEncoder_writesEveryField`, `SynthPatchTests.testEchoelSynth_isTheResponsivePlaySurfaceDefault`, `FeatureFlagsTests.testEveryFlagDefaultsOff`, `BioComposerTests.testGenresSharingAnArchetypeRenderDistinctDrums`. Seven appear in no session log or decision record. At least one is one word from green: `SynthPatchTests.swift:63` asserts `"Echoel Synth"` against `SynthPatch.swift:547`'s renamed `"Echoel Field"`. The rest sit on the founder's canonical defaults, project encode/decode (a data-loss class), automation parameter binding and genre distinctness.

**Slice, and this is the non-gated half:** **triage**, one or two tests per cycle. Fix the stale assertions, log which are real defects. The CI edit (a step gated on `steps.*.outcome` so the reveal reaches the jobs payload — an annotation would not, since `list_workflow_jobs` has no annotations field) is founder-gated and secondary.
**Files:** the failing test files, one per cycle.
**Gating:** triage no; `.github/workflows/full-tests.yml` **FOUNDER-GATED**.

### 26. Erase path for persisted HealthKit vitals

**Why:** trust, and a 5.1.3 conversation. `BioFeedbackPublisher.publishTick()` takes `bus?.usableBio()` — any source, including `.healthKit` — into `BioFeedbackManager`'s `UserDefaults(suiteName: "group.com.echoelmusic")` under `bioVitals.v1`. No `removeObject`, no `clearSharedVitals()`, no backup exclusion; a UserDefaults suite lives in `Library/Preferences`, which iCloud and encrypted backups include — the repo reasons through exactly this channel for the *derived* performer fingerprint at `PerformerSignature.swift:19-26` and applied the erase remedy there only. A user who revokes Health access, or hands the phone to another performer, cannot make Echoel forget the last reading — and since the same key holds the last reading from **any** source, and camera rPPG is the default, that applies to everyone.

**Slice:** add `clearSharedVitals()` and call it directly from `resetSoundToDefaults()` against the **group** suite. Do not add it to `SoundReset.entries`: the production caller passes `.standard`, so it would clear nothing, and `ResetSoundClearsWhatTheLaunchLineReportsTests:65-72` would go red. If moving to a backup-excluded file, the new writer must `removeObject(forKey: "bioVitals.v1")` once, or every installed device keeps exactly the payload the change exists to remove.
**Files:** `Core/BioFeedbackManager.swift`, `Studio/EchoelStudioView.swift`.
**Gating:** none.

### 27. Three permission strings promise less than the code does

**Why:** `Info.plist:93` says Photos gets "Finished visual recordings" while a live still-shutter door writes a JPEG; `:87` names only heart rate and HRV while `.respiratoryRate` is in `readTypes`, so iOS renders a Respiratory Rate row under a sentence that never mentions breathing (and under-sells a genuinely live channel); `:85` says "Audio is not recorded or sent anywhere unless you export it yourself" while stopping a visual take bakes the monitored mic into the .mp4 and auto-adds it to Photos. All three are 5.1.1(i) findings a reviewer hits by *using* the app.

**Slice:** report the three strings for the founder to edit. The agent's own half: add `NSPhotoLibraryAddUsageDescription` to `required_keys` in `scripts/check-infoplist.sh:27-34`, where it is currently absent — so neither its inaccuracy nor its removal is detected. Note the mic case is not fully closed by wording: the prompt fires when monitoring is enabled, not when the take is stopped, so it also wants a record-time disclosure (item 2's outcome sentence is the natural home).
**Files:** `scripts/check-infoplist.sh`; `Resources/iOS/Info.plist` **report only**.
**Gating:** **FOUNDER-GATED** (`Info.plist`).

### 28. Fix the register lies that misdirect the next cycle

Three small entries, one cycle each, all in the always-loaded or near-always-loaded set:

- **The genre roster.** `MusicStyle.swift:173` still says *"Every genre is now offered"* while the enum has 36 cases (measured) and `MusicStyle.offered` lists 19 — the `.rock` family vanishes from the picker entirely and `.acoustic` surfaces only `.classical`. The curation is a founder ear-call and stands; the comment is the trap, because a session that trusts it adds a genre to `Category.genres` only and ships a doorless one. Strike the clause, state that `offered` is the roster, add the re-derivation command. *(Separately worth putting to the founder: seventeen finished, patched, distinct sound-worlds are dark one curated array away — a large latent answer to "does a performer have enough range".)*
- **`FaceExpressionBioPublisher`.** A complete, finished ARKit front-camera bio publisher with **zero construction sites** (`git grep -n "FaceExpressionBioPublisher(" -- Sources` → 0; `BioSourceOption` is `camera, ble, sim`), absent from `CLAUDE.md`'s doorless register — which is the list a session uses to decide what may still be opened. A whole input *modality*, not a view, so the omission is expensive in both directions: someone rebuilds face tracking that exists, or someone wires a TrueDepth path without the privacy flag the register should carry. Add the entry + `Tests/CISmoke/TheFaceSourceHasNoDoorTests.swift` in the `ThePulseReadoutHasNoDoorTests` shape (it must not *forbid* wiring — #364 — it goes red the day someone does and names the prose to move).
- **The donut-mode caption.** In the fullscreen cover with donut mode on, the VJ overlay shows *"Detail shapes the Rings look only"* — naming the **one** control that does reach `SpectralDonutView(bandCount:)` as inert, while nine genuinely inert fields carry no caption. Its gate (`LookBlendMap.detailReach`) knows nothing about donut mode, and `LookBlendMap.swift:69-73` predicted the trap verbatim ("wrong the day it is re-doored") — #747 re-doored the cover and never updated it. Pass `spectralDonuts` into `visualAdjustFields(spacing:)` (the parameter convention exists) and replace the caption. Do **not** hide the other eight fields: `ExternalDisplayScene.swift:140-190` renders `MetalBioView` from the same keys, so with a projector attached they are live.

**Gating:** none.

---

## Below the line — do not spend a cycle on these

| Item | Why it drops |
|---|---|
| Auto-gain steers on a peak-held, clamped, mono display cell | Real defect, but the ±6 dB clamp means fixing it changes the applied gain by **zero** on three of four loudness targets and ≤1.64 dB on the default. It does not close the LUFS-vs-Target gap either (the servo is deliberately feed-forward, pre-chain). Worth ~1–3 dB of misdirected gain, all in the quiet direction. |
| Aurora ignores its `breath` parameter | The one-line swap makes Aurora **worse today** — `breathPhase` is a constant 0 or 0.5 on every shipped source, so the term would freeze at 0.8 and Aurora would lose its shimmer entirely. Do it *after* item 7, gated on `hasMeasuredBreath` with the pulse term as fallback. Raising the 2.5 Hz ceiling afterwards just relocates zero margin to Rings. |
| TestFlight's phantom `skip_tests` toggle | The two-line deletion is a runtime no-op — that is precisely why the knob is dead. It removes a checkbox from a dropdown no documented ship route renders. The substantive risk (an untested ship path) is real; the honest minimum is `needs: [preflight, compile_check]` on the `ios` job, described as gating on **compile**, not tests. Founder-gated, low. |
| The version guard can't run on the deploy commit | The stated mechanism is wrong (`grep -m1` stops at the first matching *line*, so a stray `v` in the notes cannot beat line 1), and there are 0 violations across all 60 revisions of `.deploy/release`. If touched at all, add `- '.deploy/release'` to `ci.yml`'s paths — one line, no transcription of a mis-stated law. |
| `Xcode Compile Check` doesn't compile `Tests/**` | Already documented in three places; `ci.yml` already runs `build-for-testing` on the same pushes and `gh-test-verdict.py` separates `TEST BUILD FAILED` from the standing #396 red. The proposed edit would duplicate that step and delete the repo's only Release/iphoneos compile. Fix the *path filter* (drop `Tests/**`) if anything. |
| Website publishes with no gate | Known, documented, human-mitigated by a checklist. The one-line `docs/**` addition to `ci.yml` buys a post-publication log line on a macOS runner, after the cherry-pick and Pages deploy have already finished. The change that would matter (making the merge wait) is a larger founder call. |

---

## The three findings that most surprised me

1. **The app's most distinctive interaction is one the app itself denies.** `TouchInstrumentView` is 1429 lines of six-voice, scale-locked, pressure-sensitive instrument, mounted on the launch screen — and the one in-app sentence that reveals it ships behind a default-off switch two panels deep next to Reset and Diagnostics (item 5), it appears in **no** store or website copy, and `docs/faq.html`, under the heading *"What touch instruments are available?"*, answers **no** (item 19). Three independent teams found three different faces of the same hole. The most expressive thing Echoel does is the thing it hides hardest — and it is the one gesture that cannot leave the device as data either (item 14).

2. **The most sophisticated failures are the ones where every layer is individually correct.** The Flow-mode density defect (item 10) has a correct composer, a correct clock and a wrong product, because each half uses a different tempo and no guard can see across them — and a *blocking* guard in the same repo pins a genre distinction the default runtime never produces. Same shape in the brightness accumulator (item 9): three sibling one-poles, two reachable by `apply(to:)` and one not, so the odd one out has silently blended patches for months.

3. **The blocking test bundle has been red by construction, and the non-blocking one has been printing the answer nobody read.** Two guards in `Tests/CISmoke` assert a substring and its own superstring (verified on HEAD), so no tree can satisfy both — while the full suite has been reporting `success` at every layer above the step summary with a clean compile and eight named failures inside it. The repo's law is executable; for a stretch it has been unrunnable in one direction and unread in the other.

## What the audit could not determine

- **Whether any of this sounds good.** Ship-gate check 1 is the founder's ear and nothing in the repo can substitute. The structural half is pinned (`GenreFamilyDistinctnessTests`: no offered pair shares a fingerprint); that one of them is *musical* is unprovable here.
- **How often the camera's respiration gate actually opens.** `CameraRPPGBioPublisher.swift:1538-1547` cites a device log where it never opened at nominally high signal quality. That single fact decides whether item 7's audible half is a live defect or a latent one, and whether item 13's dead band is a rare edge or the ordinary first-run experience. Both need the diagnostic breadcrumb and one device session — which is why item 13's slice is a measurement, not a fix.
- **Which of the eight full-suite failures are stale renames and which are real.** One is provably stale (one word). The other seven were not triaged because triage requires reading each test's intent, and they touch the founder's canonical defaults and project encode/decode.
- **Whether any bio egress is genuinely reaching a rig.** No sender inspects its socket and no reader exists for `lastSentTimestamp`, so "does anything arrive at Resolume / a lighting desk" is unanswerable from this repo, by anyone, including the performer (item 16).
- **iCloud/backup behaviour for App Group preferences** (item 26). The repo asserts it at `PerformerSignature.swift:20-22`; it is Apple platform behaviour, not verifiable from this tree.
- **Anything requiring a build.** No Swift toolchain here. Every finding is source reading, `git grep` counts, and CI logs.

## What I would deliberately not do

- **Not rebuild the note editor, timeline, clips, multi-track or the mixer.** Item 14 stops at MIDI *out* on purpose: capturing played notes into a roll is note editing, which is the Editor/Workstation line, and it is the founder's call, not a slice. "You cannot correct the take" is a stated consequence of a founder decision, not a defect to route around.
- **Not re-offer the seventeen dark genres, or re-open `BioSourceView`.** Curation is an ear-call that stands. Item 28 fixes the comment that *lies about* the curation; it does not undo it. And item 8 doors one switch into an already-reachable panel rather than re-doring a view that would drag back a second camera arm, a second pulse readout and `BreathGuideView`.
- **Not "fix" entrainment by shipping it.** It is genuinely audible (0.30–0.60 AM) and genuinely unreachable, but `decisions.csv:168` records a Council ruling that its efficacy is unproven and un-claimable, and its mandated vehicle/alcohol safety copy exists only inside the doorless view. That is a founder + claims decision, not an engineering unblock.
- **Not chase the CI-hygiene tier.** The phantom `skip_tests` toggle, the version-guard path filter and the compile-check scope are all real and all cost the artist and the user exactly nothing; three of the four proposed fixes are runtime no-ops and one would delete a compile the repo relies on. They belong in a single status report to the founder, not in the ship queue.
- **Not append a `.sheet`.** The chain is at 14 (verified). Every UI item above reuses an existing slot or adds an inline row. Two slots (`showMeditation`, `midiImportPresented`) have no setter and are the first place to look for room.
- **Not raise the flash ceiling.** Aurora's zero margin is real, but moving the ceiling to 3.0 Hz simply relocates zero margin to Rings. Fix the cause (item 7), then re-derive.