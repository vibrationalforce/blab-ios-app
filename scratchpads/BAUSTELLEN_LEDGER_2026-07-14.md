# BAUSTELLEN-LEDGER — exhaustive verified audit (2026-07-14)

Workflow wf_bdbd3441-1f2: 28 findings, 28 confirmed (36 agents, 0 errors). 
Ranked by founderValue down, risk up, cheapest-first. Verified = each status adversarially confirmed.

## Summary

Echoel's audio/FX/bio-visual core genuinely works (EchoelFX chain, FX bio-mod live view, FeedbackGuard, HRV/rPPG pipeline, visual→MP4 share all verified end-to-end), but a large band of conceptually-complete work is stranded one wire short of the user: network outputs only reach localhost, three parallel bio-modulation spines exist yet only the FX one is live, per-lane instrument/AUv3/composition assignments update the UI but not the sound, and several built capabilities (MIDI import, Donuts visual) have no reachable door because their only trigger was the never-mounted toolsSection. The dominant failure mode is 'built but not verdrahtet' plus documentation drift (CLAUDE.md overclaims MIDI export and FeedbackGuard-türlosigkeit). Recommended first three Ralph cycles — all high-value, low-risk, no founder decision: (1) Network output host/port config UI so OSC/ADM-OSC/sACN actually reach Resolume/TouchDesigner/light nodes; (2) the VINTAGE Tape/VHS FX first slice (wow&flutter on the dry path, reusing the proven EchoelDelay LFO/delay-line pattern); (3) per-lane composition (genreOverride/mood/seed) behind a hasOverride gate so it stays bit-identical until set — then the cheap founder-ask pair (Detune cents + Octaver) and the one-line MIDI-import door. The four biggest strategic questions (which modulation spine, whether to build the vocoder flagship and per-lane voices, and Broadcast/HaishinKit vs App Store 2.1) are batched at the end as founder product calls, not fix cycles.

## Ledger (ranked)

### #1 — Network output target (OSC / ADM-OSC / sACN) — no host/port config UI
- status: **half-wired** | value: high | risk: low
- symptom: Enabling OSC Out / ADM-OSC / sACN in Routing blinks the activity dot, but data only goes to localhost/127.0.0.1 or a wrong hardcoded 192.168.1.100 — Resolume / TouchDesigner / MadMapper / LAN light nodes receive nothing, with no way to point at the right machine (only Art-Net works, via 255.255.255.255 broadcast default).
- fix: Add a compact target row per active output to the already-reachable PatchbayView sheet (no new modal): TextField for host + EchoelValueField for port/universe, bound to each sender's existing @Observable host/port/universe. Persist via didSet→UserDefaults (mirror BroadcastPublisher.swift:37-39). Switch sACN default from unicast 192.168.1.100 to E1.31 multicast via the existing multicastHost(universe:) helper (not a raw 239.255.0.<universe> literal — breaks for universe>255). Note: connect() runs only in start(), so a live host edit needs a route toggle to reconnect.
- files: Sources/Echoelmusic/Studio/PatchbayView.swift, Sources/Echoelmusic/Sync/OSCSender.swift, Sources/Echoelmusic/Sync/ADMOSCSender.swift, Sources/Echoelmusic/Sync/SACNSender.swift, Sources/Echoelmusic/Sync/ArtNetSender.swift

### #2 — VINTAGE / Tape-Bandmaschine / VHS character FX (wow&flutter on dry, hiss, dropouts) [NEW ASK b]
- status: **half-wired** | value: high | risk: medium
- symptom: Founder gets a warm tape ECHO from Cassette/Vinyl but not authentic tape/VHS character — the whole DRY signal never drifts in pitch (wow&flutter), and there is no tape hiss or momentary dropout.
- fix: First slice: a dedicated EchoelTape chain stage that puts wow&flutter on the DRY path by reading an EchoelDelayLine at a slowly-modulated fractional offset (reuse EchoelDelayLine + two EchoelLFO exactly like EchoelDelay.swift:80-116 but on the through-signal, ~5-8 ms base) — audio-thread safe (no alloc/locks). Insert after saturation in EchoelFXChain with a tapeEnabled rising-edge reset (same willSet pattern as :57); let .cassette/.vinyl presets enable it. Defer hiss (gated-low xorshift RNG already in EchoelLFO.swift:101) and dropouts (LFO/random gate ≤3 Hz, flash-safety analogue) to slice 2. Surface via the EXISTING Effects character picker + All-parameters sheet — no new .sheet.
- files: Sources/Echoelmusic/DSP/EchoelLoFiFX.swift, Sources/Echoelmusic/DSP/EchoelFXChain.swift, Sources/Echoelmusic/Sequencer/GenreFX.swift, Sources/Echoelmusic/DSP/FXPreset.swift

### #3 — Per-lane composition (genreOverride / mood / variationSeed — several genres at once)
- status: **inert-data** | value: high | risk: medium
- symptom: Founder's explicit '2026-07-14: alles pro Instrument' does nothing — TimelineLane.genreOverride/mood/variationSeed persist across saves but change no sound (written only in init/decode, no reader; generate() composes ONE global input, loops only over loop-bars, never per-lane), and there is no UI to set them.
- fix: Cycle A (invisible, bit-identical while unset): extract a pure Sequencer func composeLaneOverrides(base:lanes:)->[laneID:[Note]] (test-first RED→GREEN) that, for each secondary MIDI lane where LaneComposerInput.hasOverride(lane), builds LaneComposerInput.apply(lane,to:base) reusing base.structureSeed for song cohesion (proven pattern BioVariationMaze.swift:124-134), runs BioComposer.compose().notes. Call after the primary take in generate(); write each result into that lane's active-region clip melody via a ClipStore setter AFTER verifying clip ownership (Council skeptic: clobbering a user-placed clip is the cheapest-wrong). @MainActor at generate time only, never audio thread, no Rausch touch. Cycle B (UI): add a Genre Picker + 8 Mood EchoelValueFields + variation dice to the existing per-lane LaneFXEditor SHEET (ArrangeTimelineView.swift:875) — not the root body (no sheet-chain growth, no 10 Hz freeze).
- files: Sources/Echoelmusic/Sequencer/LaneComposerInput.swift, Sources/Echoelmusic/Studio/EchoelStudioView.swift, Sources/Echoelmusic/Studio/ArrangeTimelineView.swift, Sources/Echoelmusic/Core/ClipStore.swift, Tests/EchoelmusicTests/LaneComposerInputTests.swift

### #4 — General bio→parameter modulation matrix (ModulationEngine + ModulationMatrix) — 'frei wählbar welche Parameter moduliert werden' **[FOUNDER-DECISION]**
- status: **half-wired** | value: high | risk: medium
- symptom: The 'freely route any body signal to any parameter' spine is unreachable — no route editor, so the body never drives tempo through this engine and the documented /echoelmusic/mod/<key> OSC address never emits a single message (TouchDesigner/Resolume/Max get nothing). A fully-built, tested, persisted-capable engine that produces zero effect (matrix empty by default; apply()'s guard !result.isEmpty returns before any handler fires).
- fix: Cheapest CODE step to make the running loop live: seed one default route in ModulationEngine.init (e.g. ModRoute(source:.coherence, destination: ModDestinationKey.tempo, depth:0.3, smoothingTau:1.0)) so the already-registered tempo handler + /mod OSC tap begin firing — additive, off-audio-thread, honors the existing BPM-lock guard. To expose the freely-routable concept, add a route-list editor as a LEAF view (own struct reading modulationEngine.matrix/lastAppliedTimestamp, never in an ancestor body — 10 Hz freeze rule) by REUSING an existing sheet slot (not a new .sheet). Rows are Codable; persist via existing save().
- files: Sources/Echoelmusic/Core/ModulationEngine.swift, Sources/Echoelmusic/EchoelmusicApp.swift, Sources/Echoelmusic/Studio/EchoelStudioView.swift

### #5 — VocoderCore + VoiceAnalyzer — the 'audiovisual vocoder' flagship (voice+body → sound+visual+light) **[FOUNDER-DECISION]**
- status: **absent-scaffold** | value: high | risk: medium
- symptom: The stated flagship vision is entirely inert — sing into the mic and nothing maps to sound/colour/light. No button leads to it, not even a dead one; VoiceFrame/VoiceAnalyzer/VocoderMapping have zero producers outside their defs+tests.
- fix: First slice = wire the INPUT half only: add a mic tap (reuse the AudioEngine input path FeedbackGuard already uses) that fills a lock-protected RGBSample-style Sendable queue, drained by an EXISTING ~10-30 Hz main-actor poll into VoiceAnalyzer.analyze() → VoiceFrame → VocoderMapping (NEVER Task{@MainActor} per audio buffer — batch, per the 10 Hz freeze rule). Route VocoderMapping.carrierMidi into the already-live synth noteOn and its formant/level into the FloatingVisualWindow shader (flash-safety already baked into VocoderCore). Surface behind a SLOT-REUSE sheet (do NOT append a new .sheet). Ship input→sound first; visual+light second.
- files: Sources/Echoelmusic/Studio/VoiceAnalyzer.swift, Sources/Echoelmusic/Audio/AudioEngine.swift, Sources/Echoelmusic/EchoelmusicApp.swift, Sources/Echoelmusic/Studio/EchoelStudioView.swift

### #6 — BoundParameter / ClockSource — the 'universal bio-binding spine' (any param follows-body OR manual; heartbeat becomes the clock) **[FOUNDER-DECISION]**
- status: **absent-scaffold** | value: high | risk: medium
- symptom: The headline principle — 'assign the pulse to THIS knob' identical on every parameter, and the heartbeat literally becoming the tempo clock — exists only as a tested skeleton (BoundParameter(/.resolved(from: = 0 Sources hits; ClockSource has no consumers). Combined with the inert ModulationMatrix and the live-but-separate FXBioModulator, the app now has THREE parallel bio-mod abstractions, only one live.
- fix: Pick ONE modulation spine (Council/founder call) before wiring more code — do not deepen three parallel systems. If BoundParameter is chosen: wire it into a single real parameter as a vertical slice (e.g. a synth cutoff EchoelValueField gains a source picker + amount; a control tick calls resolved(from: bus.freshBio())), keeping the live readout in the param's own leaf view (freeze rule). Otherwise mark it explicitly dormant in CLAUDE.md alongside VocoderCore so it stops reading as shippable.
- files: Sources/Echoelmusic/Studio/BioModulation.swift, CLAUDE.md

### #7 — Per-lane built-in instrument selection (EchoelDrums/Break/Sampler/Bass/Bio) actually changing the lane's VOICE **[FOUNDER-DECISION]**
- status: **half-wired** | value: high | risk: high
- symptom: Assigning 'EchoelBass'/'EchoelDrums'/'EchoelSampler' to a track updates name+icon+checkmark, but the track keeps sounding like the same poly synth — the chosen instrument is silent-as-selected. The literal 'die ganzen EchoelTools funktionieren noch nicht' complaint.
- fix: Make LaneVoiceRack heterogeneous: instead of always PolySynthVoice (hard-coded LaneVoiceRack.swift:52), instantiate one voice per slot keyed off the lane's TrackInstrument.voiceKind (the shipped-but-unread pure map LaneVoiceKind.swift:34) — poly→PolySynthVoice, drums→DrumSynthVoice/BeatPlayer, sampler→SamplerVoice, subBass→SubBassVoice, bioVoice→BioReactiveSynthVoice — attached in the existing attach-before-start block, each keeping its own lock-free SPSC queue (no new audio-thread code). Fan-out sink dispatches note events by slot voice kind; swap the primary lane's voice by its builtinInstrument too. Gate under FeatureFlags.multiRoll. Honest interim if the device module is deferred: keep only .polySynth selectable and hide the not-yet-voiced rows so the menu doesn't promise a sound it can't make.
- files: Sources/Echoelmusic/Sequencer/LaneVoiceRack.swift, Sources/Echoelmusic/EchoelmusicApp.swift, Sources/Echoelmusic/Sequencer/TimelineRegionPlayer.swift

### #8 — Per-lane fine DETUNE (cents) [NEW ASK a1]
- status: **absent-scaffold** | value: medium | risk: low
- symptom: Founder can shift a lane by whole semitones but cannot nudge it a few cents to fatten/beat against another lane — the fine-tune control is missing (and the existing 'Detune' label misleadingly means unison spread).
- fix: Add a plain var fineTuneCents: Float to EchoelDDSP (like transposeSemitones — NOT @ObservationIgnored nonisolated(unsafe); EchoelDDSP is @unchecked Sendable, not @Observable), fold + fineTuneCents/100 into the noteOn exponent at EchoelDDSP.swift:1686 (0 ⇒ bit-identical); add setFineTune(cents:) on PolySynthVoice mirroring setTranspose; add detuneCents: Int to TimelineLane + setLaneDetune in TimelineStore; drive via a new rollDetuneSink/slotDetuneSink beside the transpose sinks (EchoelmusicApp.swift:516-525); expose one EchoelValueField (±50 cents) next to Transpose in ArrangeTimelineView.swift:919. Same proven path as Transpose.
- files: Sources/Echoelmusic/DSP/EchoelDDSP.swift, Sources/Echoelmusic/Tools/PolySynthVoice.swift, Sources/Echoelmusic/Sequencer/Timeline.swift, Sources/Echoelmusic/Core/TimelineStore.swift, Sources/Echoelmusic/EchoelmusicApp.swift, Sources/Echoelmusic/Studio/ArrangeTimelineView.swift

### #9 — Per-lane OCTAVER (±octave switch) [NEW ASK a2]
- status: **absent-scaffold** | value: medium | risk: low
- symptom: Founder must type ±12 in the Transpose field to shift an octave; there is no one-tap '±octave' performance switch.
- fix: Pure UI convenience on the SAME setLaneTranspose already wired — add two small −8ve/+8ve buttons near ArrangeTimelineView.swift:919 that call timeline.setLaneTranspose(id:, current ± 12) (clamp to ±48 handled by TimelineStore.swift:167). No DSP, no new state, no new sheet. Ship together with a1.
- files: Sources/Echoelmusic/Studio/ArrangeTimelineView.swift

### #10 — MIDI import (bring-your-DAW-MIDI onto piano roll + drum grid)
- status: **dead-door** | value: medium | risk: low
- symptom: No way to import a .mid file anywhere in the app — a built, working DAW capability with no reachable button (midiImportPresented is set only in openTool, called only from the never-mounted toolsSection).
- fix: Wire ONE reachable trigger to the EXISTING $midiImportPresented @State — e.g. an ArrangeTimelineView MIDI-lane/region context action, a track-menu case, or a row in the chrome Export dropdown (utilityRow, reachable via case .export→1220) that sets midiImportPresented = true. The .fileImporter already lives on the EchoelStudioView body (already in the modal chain), so this adds NO new sheet/cover — a pure Button→@State edit, no 10 Hz read, no audio-thread touch.
- files: Sources/Echoelmusic/Studio/ArrangeTimelineView.swift, Sources/Echoelmusic/Studio/EchoelStudioView.swift

### #11 — Per-track record-arm capture for AUDIO-input and VIDEO-capture lanes
- status: **half-wired** | value: medium | risk: medium
- symptom: Arm a mic/Audio track (red arm dot lights, Record button enables), hit Record, sing over the take, Stop — and NO clip appears. The arm+record affordance is fully live but yields nothing for audio/video sources (TakeRecorder no-ops .audioInput/.videoCapture yet canRecord=true puts them in RecordPlan.targets).
- fix: Full fix: on take start with an armed audio lane, drive the EXISTING MicrophoneManager/MultiTrackRecorder to write mic audio to an App-Group file OFF the audio thread, then in commit() build an audio Clip (kind .audio, mediaRef to the file) + region on that lane, reusing RecordAnchor for tick alignment. Interim honesty variant: exclude .audioInput/.videoCapture from RecordPlan.targets so an audio-only arm no longer enables a Record button that produces nothing — but prefer the targets-exclusion form over setting canRecord=false, since canRecord=false would also strip the per-track arm button the founder asked for (ArrangeTimelineView.swift:603-608).
- files: Sources/Echoelmusic/Sequencer/TakeRecorder.swift, Sources/Echoelmusic/Core/RecordController.swift, Sources/Echoelmusic/Sequencer/RecordAnchor.swift

### #12 — 'Donuts' visual look (SpectralDonutView) — selectable but never renders **[FOUNDER-DECISION]**
- status: **half-wired** | value: medium | risk: medium
- symptom: Tapping 'Donuts' in the Synth panel highlights the chip (flag defaults true) but the floating visual keeps showing the ring/metal visual — the donut spectrum mode is unreachable (SpectralDonutView renders only in the dead $showVisual cover whose sole true-setter is inside the never-mounted toolsSection; FloatingVisualWindow always renders MetalBioView and never reads the flag).
- fix: Clean path = flip the default to false and DROP the Donuts chip. Do NOT mirror the 660-673 branch into FloatingVisualWindow.card: MetalBioView there is welded to the TouchInstrumentView play surface (FVW.swift:392-401) and the MP4/WAV recorder (capturesVideo:true) which a Canvas can't provide — a default-true donut window would ship a non-playable/non-recordable visual. Separately, delete the dead $showVisual fullScreenCover (654-734) to reclaim body-metadata headroom.
- files: Sources/Echoelmusic/Studio/FloatingVisualWindow.swift, Sources/Echoelmusic/Studio/EchoelStudioView.swift

### #13 — News & live events push toggle (AnnouncementCenter / E4 broadcast push) **[FOUNDER-DECISION]**
- status: **half-wired** | value: medium | risk: medium
- symptom: Flipping 'News & live events' ON shows 'Saved — live news arrives with Echoel Live' but no push ever arrives — the CloudKit 'Announcement' schema is not deployed to production, so cloudKitConfigured=false makes didSet return without ever calling activate(). Honestly labeled, but the control does not do its named thing.
- fix: Deploy the 'Announcement' record type to the CloudKit PRODUCTION environment (CloudKit Dashboard), THEN flip one line: cloudKitConfigured = true (AnnouncementCenter.swift:48). All activation logic (permission request, CKQuerySubscription save, ckInflight circuit-breaker, completion-handler bridge) is already built. Do NOT flip the flag before the schema is live — v145/v147 launch-crash history is an EXC_BREAKPOINT inside CloudKit when the schema is absent.
- files: Sources/Echoelmusic/Sync/AnnouncementCenter.swift

### #14 — Per-lane AUv3 instrument / effects assignment ('Assign to this track') routing to the lane's sound **[FOUNDER-DECISION]**
- status: **inert-data** | value: medium | risk: high
- symptom: User browses third-party AUv3 plugins, assigns a synth/FX to a track, sees the puzzle-piece badge and 'Instrument: X' header — but the track's sound is completely unchanged. A live door onto data that does nothing (lane.instrument/effects read ONLY by UI badge + persistence; no Audio/DSP path consumes the AUPluginRef).
- fix: Real fix is heavy (per-lane AU instantiation + insert into that lane's rack voice FX chain on the multiRoll rack) and shares the device milestone as the built-in-voice finding. Cheapest HONEST interim: relabel the assignment as display/persist-only (header 'Assigned (routing pending)') OR gate the Assign action behind FeatureFlags.multiRoll so it isn't offered as a working affordance until per-lane routing exists — avoids the inert-badge false promise without building the full AU-per-lane host.
- files: Sources/Echoelmusic/Studio/ArrangeTimelineView.swift, Sources/Echoelmusic/Core/TimelineStore.swift

### #15 — Broadcast / RTMP / SRT live stream (BroadcastView + BroadcastPublisher) **[FOUNDER-DECISION]**
- status: **absent-scaffold** | value: medium | risk: high
- symptom: No streaming capability is reachable: BroadcastView has zero presenters, start() is an honest no-op (HaishinKit unlinked), and the 'Broadcast (RTMP/SRT)' points in Routing show a 'soon' tag but are permanently unroutable (rtmp.out/srt.out are kind .audio with no .audio source or converter, so wantsBroadcast is always false). Nothing streams from the phone.
- fix: Product decision required BEFORE any code: (a) does an RTMP/SRT stream of the live instrument pass App Store Guideline 2.1 (open task #28), and (b) commit to integrating HaishinKit — a NEW dependency currently forbidden by the zero-deps rule. Until both are founder-approved, leave BroadcastView door-less and the 'soon' ports unroutable (correct today — no dead affordance). When approved: link HaishinKit, then add a chrome/patchbay door to present BroadcastView(embedded:).
- files: Sources/Echoelmusic/Stream/BroadcastPublisher.swift, Sources/Echoelmusic/Studio/BroadcastView.swift, Sources/Echoelmusic/Core/SignalRouter.swift, Package.swift

### #16 — toolsSection / openTool — orphaned tool catalog (dead-door root cause)
- status: **dead-door** | value: low | risk: low
- symptom: Invisible to the user (never mounted) but it is the mechanism behind the founder's 'so viel was konzeptionell stand' — a full tool catalog wired to nothing. A future session may wrongly assume these tools are reachable.
- fix: After each of the two still-stranded destinations (MIDI import, Donuts/showVisual) gets an explicit door via the other findings, delete toolsSection + openTool + the now-orphaned toolItems/ToolItem/ToolCat (audit each openTool case for an alternate live trigger FIRST — audioin/routing/learn/live were already re-doored; importmidi+visual are the last two). Pure removal of dead SwiftUI builders also shrinks the root body's generic depth (metadata law).
- files: Sources/Echoelmusic/Studio/EchoelStudioView.swift

### #17 — MIDI export (exportMIDI + ShareSheet — claimed shipping in CLAUDE.md P1) **[FOUNDER-DECISION]**
- status: **inert-data** | value: low | risk: low
- symptom: No user symptom (button intentionally removed 2026-07-02). This is dead code + a documentation-drift trap: a future session reading CLAUDE.md's P1 line will believe MIDI export ships and may 'restore' it, contradicting the founder's removal.
- fix: Do NOT re-wire (re-adding the door contradicts the explicit 2026-07-02 founder call). Cheapest correct change is hygiene: delete the orphaned exportMIDI() function (zero callers, EchoelStudioView.swift:3946) OR annotate it, and correct the CLAUDE.md P1 line to state MIDI export is intentionally un-doored. No Sources behavior change.
- files: Sources/Echoelmusic/Studio/EchoelStudioView.swift, CLAUDE.md

### #18 — CloudSync (CloudKit project/patch/session sync foundation)
- status: **absent-scaffold** | value: low | risk: low
- symptom: None — no sync toggle, no cloud door. Foundation-only (Phase 0, Foundation-only, no CKContainer binding); zero app consumers outside tests. Safely dormant, not a broken affordance.
- fix: No action required today. When wanted: implement a CKContainer backend conforming to the existing protocol and inject it; the last-writer-wins engine + record model are done and tested. Product/infra decision, not a wiring gap.
- files: Sources/Echoelmusic/Core/CloudSync.swift

### #19 — EchoelStore Pro one-time unlock (StoreKit-2) + ProUnlockView **[FOUNDER-DECISION]**
- status: **absent-scaffold** | value: low | risk: low
- symptom: None — no purchase/restore button or Pro door anywhere; the scaffold is fully dark (StoreKit gated OFF by FeatureFlags.storeKit default-false; ProUnlockView has no call site). Reported so a future cycle does not chase the phantom 'contradictory subscription IDs' the docs describe.
- fix: No fix today (leave dormant). When monetizing: present ProUnlockView from a settings/paywall door and set FeatureFlags.storeKit=true. Also correct the stale CLAUDE.md 'Absent' line — the product is a SINGLE non-consumable com.echoelmusic.app.pro, not subscriptions.
- files: Sources/Echoelmusic/Core/EchoelStore.swift, Sources/Echoelmusic/Core/ProGate.swift, Sources/Echoelmusic/Studio/ProUnlockView.swift, CLAUDE.md

### #20 — EchoelAI on-device Brain / LLM planner (FoundationModelsBrain, BrainBackend, ParameterToolCore) **[FOUNDER-DECISION]**
- status: **absent-scaffold** | value: low | risk: low
- symptom: None — no AI button, prompt field, or assistant surface. The LLM half is fully gated (FeatureFlags.echoelAI default-OFF, never read at runtime) and door-less; the parameter-registry half already powers automation/AUv3.
- fix: No action required. When shipping EchoelAI: add a UI door guarded by FeatureFlags.echoelAI and keep the LLM off the audio thread (already the ADR contract). Product call.
- files: Sources/Echoelmusic/EchoelAI/FoundationModelsBrain.swift, Sources/Echoelmusic/EchoelAI/BrainBackend.swift

### #21 — EchoelFX chain (filter · saturation · bitcrush · harmonizer · chorus/flanger/phaser/tremolo · delay · reverb · widener · comp · limiter) + bio-mod
- status: **works** | value: high | risk: low
- symptom: None — every FX stage is audible, bio-reactive, and reachable via Effects panel → All parameters. NOT a Baustelle.
- fix: No change needed. Verified end-to-end: render (PolySynthVoice.swift:596, BioReactiveSynthVoice.swift:375) + UI door (EchoelStudioView.swift:2914→:636 EchoelFXView) + bio-mod (FXBioModulator ~30 Hz); all 14 stages in EchoelFXChain.swift.

### #22 — FX bio-modulation LIVE visibility — 'which parameters is the body moving right now' (task #3)
- status: **works** | value: medium | risk: low
- symptom: None — with an FX bio route added and a session running, carrier→target rows show live signal bars + signed offsets. Confirms task #3 is real. Only caveat: scoped to FX-chain parameters, not the general matrix or BoundParameter targets.
- fix: No change required. If broader visibility is wanted later, reuse this exact leaf pattern (own View struct, ~10 Hz throttled Equatable snapshot) for whichever modulation spine the founder makes live.

### #23 — FeedbackGuard live-input monitoring (engine + UI door)
- status: **works** | value: medium | risk: low
- symptom: None — the CLAUDE.md note that AudioInputPicker/FeedbackGuard 'bleiben türlos' is STALE; the door exists in the Master menu (WorkspaceView 'master' → masterDoorButton → AudioInputPickerView sheet, ~15 Hz updateFeedbackGuard live).
- fix: No behavior change — update the CLAUDE.md note only (remove the 'FeedbackGuard/AudioInputPicker bleiben türlos' claim). Do not re-add a door.
- files: CLAUDE.md

### #24 — Video capture / trim / export (P3)
- status: **works** | value: low | risk: low
- symptom: None broken — the film/record control on the visual window produces a shareable MP4. A dedicated camera-video recorder and a trim UI simply do not exist yet (no dead button).
- fix: No fix — the visual→MP4→share path works. Camera-video + trim are net-new founder-scoped features, not a wiring repair.
- files: Sources/Echoelmusic/Video/VisualRecorder.swift, Sources/Echoelmusic/Studio/FloatingVisualWindow.swift

## Execution order (Ralph, one reviewed cycle per item)

1. Network output target (OSC / ADM-OSC / sACN) — no host/port config UI
2. VINTAGE / Tape-Bandmaschine / VHS character FX (wow&flutter on dry, hiss, dropouts) [NEW ASK b]
3. Per-lane composition (genreOverride / mood / variationSeed — several genres at once)
4. Per-lane fine DETUNE (cents) [NEW ASK a1]
5. Per-lane OCTAVER (±octave switch) [NEW ASK a2]
6. MIDI import (bring-your-DAW-MIDI onto piano roll + drum grid)
7. Per-track record-arm capture for AUDIO-input and VIDEO-capture lanes
8. FeedbackGuard live-input monitoring (engine + UI door)
9. toolsSection / openTool — orphaned tool catalog (dead-door root cause)
10. General bio→parameter modulation matrix (ModulationEngine + ModulationMatrix)
11. VocoderCore + VoiceAnalyzer — the 'audiovisual vocoder' flagship
12. BoundParameter / ClockSource — the 'universal bio-binding spine'
13. Per-lane built-in instrument selection (EchoelDrums/Break/Sampler/Bass/Bio) actually changing the lane's VOICE
14. 'Donuts' visual look (SpectralDonutView) — selectable but never renders
15. News & live events push toggle (AnnouncementCenter / E4 broadcast push)
16. Per-lane AUv3 instrument / effects assignment routing to the lane's sound
17. MIDI export (exportMIDI + ShareSheet) — hygiene + CLAUDE.md drift
18. Broadcast / RTMP / SRT live stream (BroadcastView + BroadcastPublisher)
19. EchoelStore Pro one-time unlock (StoreKit-2) — CLAUDE.md correction
20. EchoelAI on-device Brain / LLM planner

## Founder decisions (batched — product/architecture calls, not fix cycles)

- Modulation spine: the app now has THREE parallel bio-modulation abstractions — the live FXBioModulator, the built-but-empty ModulationEngine/ModulationMatrix, and the tested-but-unwired BoundParameter/ClockSource. Choose ONE canonical spine before wiring more code; the other two get explicitly marked dormant. This decides ranks 4 and 6.
- General bio→param modulation matrix (rank 4): approve seeding one default route (coherence→tempo) to make the /echoelmusic/mod OSC tap + tempo handler start firing, and approve a route-editor leaf reachable by reusing an existing sheet slot.
- VocoderCore audiovisual vocoder (rank 5): approve building the flagship's INPUT slice (mic→VoiceAnalyzer→VocoderMapping→synth noteOn) now, visual+light second — or keep it dormant.
- Per-lane built-in instrument VOICE routing (rank 7) and per-lane AUv3 assignment (rank 14): approve building the heterogeneous LaneVoiceRack + device multiRoll milestone, OR approve the honest interim (hide/relabel not-yet-voiced instrument rows so the menus don't promise a sound they can't make).
- Donuts visual (rank 12): retire it — flip the default to false and drop the chip (recommended clean path), since a default-true donut window would ship a non-playable, non-recordable visual.
- News & live events push (rank 13): approve deploying the 'Announcement' record type to the CloudKit PRODUCTION environment before flipping cloudKitConfigured=true (flag must not flip before schema is live — prior launch-crash risk).
- Broadcast RTMP/SRT (rank 15): a product/policy call — App Store Guideline 2.1 review risk for a streaming door, plus committing to HaishinKit as the one sanctioned new dependency. Keep door-less until both are greenlit.
- MIDI export (rank 17): confirm it stays un-doored per the 2026-07-02 removal — approve deleting the orphaned exportMIDI() and correcting the CLAUDE.md P1 overclaim.
- Monetization (rank 19) and EchoelAI (rank 20): confirm both stay dormant for now; approve only the CLAUDE.md corrections (single non-consumable, not subscriptions).
