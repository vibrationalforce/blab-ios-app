# CLAUDE.md — Echoel v10 (Bio · Audio · Video · Light · Space)

## IDENTITY

Repository: https://github.com/vibrationalforce/Echoelmusic
Developer: Echoel (Michael Terbuyken) @ Studio Hamburg
App Apple ID: 6757957358 · SKU: Simsalabimbam · Team ID: via `APPLE_TEAM_ID` secret
Bundle prefix: `com.echoelmusic` · App Group: `group.com.echoelmusic`
Bundles: `.app` (main, universal) · `.app.watchkitapp` · `.app.widgets` · `.app.clip` (deferred) · `.app.notification-service` (deferred)

**Canonical identity map:** `docs/dev/APP_STORE_CONNECT.md` · **Cross-platform plan:** `scratchpads/PLAN_MULTIPLATFORM_LINKING.md`

**Echoel — Physical Computing · Biofeedback · Multimedial & Multidimensional.**
An immersive, iPhone-first instrument and production platform where the body — heart, breath — drives sound, image, light and immersive space in real time.

⛔ **Drei Wörter sind am 2026-07-31 gestrichen worden, weil sie keinen Produzenten haben** — aus dieser Zeile, aus „Built for" darunter und aus den beiden BRAND-Zeilen: **„motion"** (`ModulationMatrix.hasProducer` gibt für `.motion` hart `false` zurück; ALLE SECHS `BioSampleFrame`-Konstruktionsstellen in `Sources/` schreiben `motionEnergy: 0`, der letzte CoreMotion-Provider ging im 2026-06-19-Cleanup — `import CoreMotion` kommt nirgends mehr vor) · **„brain rhythm"** (`.eegBurst` hat in `Sources/` VIER Vorkommen — Enum-Case, ein Doc-Kommentar, eine OSC-Adresszuordnung, ein Consumer-`switch` — und **NULL Produzenten**; nichts konstruiert je ein solches Ereignis) · **„broadcast"** (`Package.swift` hat ein leeres `dependencies`-Array, HaishinKit nicht verlinkt; RTMP kann als Codepfad nicht existieren).

⛔ **Und die ERSTE Fassung dieser Streichung ließ die Zeile stehen, die eine Session zuallererst liest: die H1.** Sie behauptete „Bio · Audio · Video · Light · **Broadcast**" als Produktsäule, während der Absatz direkt darunter erklärte, warum Broadcast nicht existiert — die einzige überlebende Falschstelle saß in der Überschrift, und der Absatz nannte sich dabei selbst „die erste Zeile, die eine Session liest". Die H1 sagt jetzt **Space** (ADM-OSC ist real und verdrahtet). Lehre für die nächste Wahrheits-Runde: **die Überschrift ist Teil der Behauptung**; ein `git grep` nach dem gestrichenen Wort über die GANZE Datei gehört zum Streichen dazu, nicht nur das Bearbeiten der Absätze, an die man gerade denkt.

Built for: **Installation · Event · Content · Cinema · Theater · Performance.** (⛔ „Live Broadcast" gestrichen, gleicher Grund.)

Capabilities (all routed through one typed bus): **bio-reactive synthesis** · **generative composition** (key/scale/genre, in-key melody + harmony from the body) · **OSC / MIDI I/O** · **generative visuals + lighting** (Art-Net · sACN · ADM-OSC).

⛔ **Was hier stand und 2026-07-27 gestrichen wurde, weil es nichts davon (mehr) gibt:** „Beat Maker (16-step × 8-track sequencer + sampler)" — Drums, Pad-Stimmen, Sample-Import und die Sample-Bibliothek sind mit #166/#167 gelöscht, der Step-Grid überlebt nur als Takt-Clock · „Multi-track Recorder (mic over beats)" — **KORRIGIERT 2026-07-31: „nie gebaut" war falsch.** `MultiTrackRecorder` existiert und wird unbedingt konstruiert (`AudioEngine.swift:265`); durchgereicht wird es nur hinter `FeatureFlags.audioLaneRecording` (`EchoelmusicApp.swift:997`), und dieser Key wird NIE an `UserDefaults.register(defaults:)` übergeben (registriert sind nur `multiRoll`, `voiceKindRouting`, `instrumentHome`) — löst also zu `false` auf. Ehrlich ist: **gebaut, flag-gated AUS, türlos (#204)**. Der Unterschied ist nicht kosmetisch: „nie gebaut" lässt eine Session neu bauen, was schon da ist · „Video Capture & Trim" — **halb**: der SCHNITT ging mit #121 Slice 3, die AUFNAHME nicht. `VisualRecorder` wird in `EchoelmusicApp.swift:181` konstruiert, die Aufnahmetaste sitzt im erreichbaren `FloatingVisualWindow`, und `videoPanel` → `VideoLibraryPanelContent` ist die erreichbare Bibliothek mit mp4-Export. (Die REC-Taste im `showVisual`-Vollbild ist die TOTE Zweitkopie — nicht mit ihr verwechseln.) · „RTMP Live Stream" — nie verlinkt (`BroadcastPublisher` ist ein Compile-Guard-Gerüst). **MPE** ist aus dem I/O-Satz gestrichen, weil `mpeEnabled`/`expressionEnabled` seit dem Tools-Grid-Removal keinen Schreiber haben. Diese Zeile ist die Identitäts-Zeile der Datei — sie muss der Wahrheit folgen, sonst plant die nächste Session aus ihr heraus Features, deren Fundament abgerissen ist.

---

## CURRENT STATE

- **⭐ PRODUCT DEFINITION (canonical, 2026-07-25 — read `docs/dev/PRODUCT_DEFINITION.md` before any scope decision).** Founder delegated the call in full ("Du entscheidest… einfach zu begreifen, zu vermarkten und zu pflegen"); decided via Grand Council.
  **One sentence: Echoel is a bio-reactive instrument — your body plays it, and its output is multidimensional (sound, image, light, space).** There is no second product and no acronym.
  **"DMMW" is RETIRED** (unrepeatable, put a solo dev on DAW turf, infinite maintenance surface; the 2026-07-19 Council already logged "Fokusverlust seit DMMW"). `docs/dev/DMMW_ARCHITECTURE.md` is superseded — history only, do not plan from it. The multidimensional half survives as the instrument's **output stage** (one bus: `BioFrame` + `MusicalFrame` → visual · light/Art-Net+sACN · space/ADM-OSC · haptics), never as its own product. Adding a medium = adding a subscriber, never a new surface.
  **THE BOUNDARY that decides every keep/cut — Editor ≠ Workstation:** is it about the sound being made *now* (KEEP: generative engine, Flow/Loop, **patch editor**, **piano roll**, genres, output stage, export) or about arranging material *over time* (CUT: timeline/arrangement/clips, multi-track & mixer, audio-file regions, video edit, AUv3 host+target, RTMP, subscriptions)? **Craft tools are instrument controls, not DAW surfaces** — a synth you cannot tune is not an instrument. (⚠ The parenthetical that stood here — *"Hard technical reason the piano roll stays: `PianoRollView` PUBLISHES `MusicalFrame`"* — was FALSE, and line 49 below already said so: the publish lives in `PianoRollModel`'s tick handler, installed once at app start, view or no view. It is corrected here too because THIS is the line a session reads when deciding whether a removal is safe, and as written it would have made one refuse the founder's 2026-07-26 removal on a technical ground that does not exist. **`PianoRollView` = the editor, removed. `PianoRollModel` = the note engine + `MusicalFrame` publisher, KEPT** — that one is genuinely load-bearing.)
  **SHIP GATE "Instrument-Complete v1"** — replaces the dead *"bis die gesamte DMMW auf Profi-Level ist"* (unreachable once the workstation half was dismantled). Five binary checks, all true → lift the freeze: **1. Klang** (curated genres professional, identity survives, no convergence bug) · **2. Kontrolle** (patch editor reachable — `soundPanel` behind the Sound chip; **the piano-roll half of this check is RETIRED by founder decision 2026-07-26, "Pianoroll soll raus"** — the note editor is gone on purpose, so do not read this gate as blocked by its absence) · **3. Modi** (Flow + Loop) · **4. Ausgabe** (visual live + contemplative on device; light/space demonstrable, not required) · **5. Stabilität** (clean launch, no black screen, no menu freeze).
- **Branch:** run `git branch --show-current` — the literal used to be pinned here and was wrong for weeks. Prior cycles auto-merged to `main`.
- **Mode:** RALPH WIGGUM LAMBDA — one feature/fix per cycle, build → test → ship → loop
- **Positioning:** "The first bio-reactive performance instrument" — and, per the 2026-06-06 deep-research roadmap, the **bio-reactive object source for accessible immersive multidimensional media art** (open standards: ADM-OSC, MIDI 2.0, OSC, BLE HRS; no SDK lock-in). See `scratchpads/STRATEGY_STATE_OF_THE_ART_2026-06-06.md`.
- **Architecture (audited 2026-06-09 — `scratchpads/ARCHITECTURE_AUDIT_2026-06-09.md`):** `EngineBus` = `@MainActor @Observable` control plane (snapshots) + lock-free `SPSCQueue`. 3 topics — `bioFrames` / `controllerEvents` / `bioEvents`. **Bio flows over the `latestBio`/`latestBioEvent` snapshot; the SPSC queue is drained only for `controllerEvents` (MIDI).** `bioFrames`/`bioEvents` queues are reserved/undrained (snapshot is the correct path for slow bio). Modules couple only via the bus. ⛔ **Diese Zeile sagte „(10 Hz poll)" und genau diese Zahl hat #315, #332 und #336 erzeugt — drei Zeitkonstanten, die aus ihr abgeleitet und dadurch um das 10- bis 60-Fache daneben lagen. Der POLL ist 10 Hz, die ANWENDUNGSRATE ist ~1 Hz**, weil jeder Verbraucher auf `frame.timestamp` dedupliziert und jeder verdrahtete Publisher mit ~1 Hz sendet (`CameraRPPGBioPublisher` `tick % 10` in einer 100-ms-Schleife, Polar 1 s, Simulator 1 s, HealthKit 500-ms-Poll hinter einem 4–5-s-Sensor). **Für jede Zeitkonstante gilt die 1 Hz, nicht die 10** — der Poll ist nur die Obergrenze, die ein schnellerer Publisher erreichen könnte. Ein Wächter im blockierenden Bundle (`Tests/CISmoke/BioApplyRateIsTheDedupedRateTests.swift`) hält die Publisher-Kadenz und die Deduplizierung fest, damit diese Zeile nicht wieder still altert.
- **Live pipeline:** HealthKit + **camera rPPG (live, locks on device)** + Demo → bio snapshot. (**Universal BLE HR (0x180D) = GEBAUT + VERDRAHTET**, aber **KORRIGIERT 2026-07-26 — die Tür ist NICHT die Patchbay.** Die alte Fassung hier behauptete, der Source-Port `blehrs.in` starte/stoppe `PolarH10BioPublisher` via `applyRouting` [`hasEnabledRoute(fromSource:"blehrs.in")`]. Das galt nur von B4 [2026-07-12] bis **BLE-3 [2026-07-15]**, das die Kopplung wieder entfernte: `applyRouting` war damit ein ZWEITER Lifecycle-Besitzer, der einen über die Pulse-Pille gestarteten Gurt bei JEDEM unbeteiligten Patchbay-Edit mitten in der Performance killte. **Heute hat der Gurt genau EINEN Besitzer: das Source-Dropdown der Pulse-Pille [`startBioSource`].** `blehrs.in` ist ein reiner Datenfluss-Port; `hasEnabledRoute(fromSource:)` hat **keinen Produktions-Aufrufer** — nicht daraus einen Start-Hook zurück-ableiten. Gerät-Verify wartet auf Gurt-Eintreffen [NEEDS-FOUNDER-VERIFY]. Deep Audit `scratchpads/DEEP_AUDIT_2026-07-12.md` ist an dieser Stelle ebenfalls überholt.) Pipeline weiter: bio snapshot → BioReactiveSynthVoice (EchoelDDSP; **silent until user-armed**) + OSCSender (`/echoelmusic/bio/*`) + **ADMOSCSender** (`/adm/obj/{n}/*` immersive object out). CoreMIDI MPE → controllerEvents → synth notes (performer priority). BioEventGraph → breath/motion onsets. ModulationEngine wired (bio→tempo). **EchoelBeat ist TOT** (korrigiert 2026-07-27): velocity/accent, swing und Per-Pad-Sample-Import standen hier weiter als live, obwohl der Founder die Drums am 2026-07-26 entfernt hat (#166). `BeatPlayer.attach(to:)` hängt nur noch `previewVoice` ein — kein Pad-Voice, kein `pattern.onStep`. Es kann heute KEIN Drum-Klang entstehen. **Der vollständige Abriss (#167) ist am 2026-07-31 FERTIG**: `DrumSynthVoice`, `LaneDrumKitVoice` und `DrumNoteMap` sind als Dateien gelöscht, ebenso `PhysicalVoiceRef.drums` und `LaneVoiceRack.kits`/`setDrumsInsert`. Die Enum-Cases `LaneVoiceKind.drums` / `TrackInstrument.drums` BLEIBEN. ⛔ **Die erste Fassung dieser Zeile begründete das mit „persistierte rawValues, ein unbekannter verwirft beim Decode die ganze Spur" — BEIDE Hälften sind falsch, und die Begründung stand gleichzeitig in vier Quelldateien.** `LaneVoiceKind` ist gar nicht `Codable` und erreicht nie die Platte (`Timeline.swift` sagt das selbst). `TrackInstrument` ist es, aber `TimelineLane`s Decoder wickelt ihn in `try? … ?? nil` — genau damit #167 überlebbar ist: ein unbekannter Case wird zu „kein eingebautes Instrument", die Spur mit Regionen, Clips, Mixer und Patch bleibt vollständig. Die WAHREN Gründe sind schwächer und stehen jetzt an den Cases selbst: `TrackInstrument.drums` löschen kostet einer Altspur ihre Instrument-WAHL (Founder sagte „erstmal"), `LaneVoiceKind.drums` ist ein toter Case ohne Produzenten, der eine eigene Entscheidung braucht. **Lehre: ein „NICHT löschen"-Kommentar mit falscher Begründung ist schlimmer als keiner — die nächste Session kann ihn nicht widerlegen.**
- **Protected DSP triad (READ-ONLY, now implemented):** BioSignalDeconvolver (detrend·notch·validity), HilbertSensorMapper (1D→2D Hilbert curve), BioEventGraph (heartbeat/breath/motion detectors). Pure value types, SKILL.md contracts under `.claude/skills/`.
- **SDK:** iOS 18 deployment floor (Package.swift + project.yml + Resources/iOS/Info.plist synced). Xcode 26.2 in `testflight.yml`. App Group `group.com.echoelmusic`.
- **Root view (RE-FOCUS 2026-07-06B — founder: "die Leute brauchen gar keine Atemübung. Es geht um Performance und Entspannungssteigerung dadurch, dass sich die Musik mit dem Biofeedback generativ verändert"): the bio-generative INSTRUMENT is the app HOME.** This supersedes the same-day 2026-07-06A "Session is home" flip (the founder tested it and rejected the breathing-exercise framing within hours). `WorkspaceView` body = brand header (`topBar`) + persistent `TransportBar` + `EchoelStudioView()` + `FloatingVisualWindow`. **The Session experiment (`SessionView`/`SessionEngine`/`SessionGuide`/`SessionClock`/`EntrainmentEngine`) stays in code, compiling, but NOTHING presents it** — do not re-add a Session door/card without a founder ask; equally, do not delete those files without one (they hold the tested flash-safety/latency/pacing laws, reusable for future bio-visual work). The product bar now: the generative MUSIC must sound organic/professional and the VISUAL must be part of the experience ("wow", contemplative) — quality work goes there, not into new surfaces.
- **Studio shell internals:** brand header (`topBar`) + persistent `TransportBar` (Play/Stop + tempo-lock button + `TransportPositionView` loop/position leaf; NO tempo number in the chrome since v10.79.64 — the one musical-tempo control is the compact `BodyTempoField` in the TransportBar chrome itself (`WorkspaceView.swift:345`) — the full-width Composition-panel tempo row is gone, the one live pulse number is in the bio strip) + `EchoelStudioView` (the instrument) + the floating immersive visual (`FloatingVisualWindow`, toggled from the header monitor). **The former 6-surface bottom bar (Arrange · Clips · Compose · Mix · Bio · Browse) is REMOVED from navigation** — **von den sechs ist nur noch EINE als Datei da: `BioSourceView`** (unerreichbar, aber restaurierbar). Die Liste, die hier stand („ClipView/ArrangementView/ChannelRackView/BioSourceView … reversible by restoring the bottom bar"), war am 2026-07-27 zu drei Vierteln falsch und hätte eine Session glauben lassen, die Mix- und Clip-Flächen ließen sich durch Wiedereinhängen der Leiste zurückholen: **`ClipView` (807dc0d) und `ArrangeTimelineView` (eb58e7a) sind mit #121 Slice 4 gelöscht, `BrowserView` und `ChannelRackView` mit #167 (2026-07-27)** — letzteres mischte 8 Kanäle, die keinen Klang mehr erzeugen. Wiederherstellen hieße hier neu bauen, nicht wieder anhängen. Do not "restore" them without a founder ask. **Video page = designed + DEFERRED** (`scratchpads/PLAN_VIDEO_PAGE.md`). The old `StudioRoot` Tools/Works/Sync/Well TabView is long gone.
- **Presentation (stability, as-shipped — corrected 10.76.38):** the device-confirmed-launching `EchoelStudioView` uses **MANY `AnyView`-wrapped `.sheet`/`.fullScreenCover` modifiers** chained on the body. Counted by grep 2026-07-27 on `EchoelStudioView.body`: **8 `.sheet` + 2 `.fullScreenCover` + 3 `.alert` + 1 `.fileImporter` = 14 presentation modifiers** on the chain (a 15th `.sheet(item: $visualShare)` sits INSIDE the fullScreenCover's content, not on the body). The old "= 16" here was stale by two — and it was the number a session reads BEFORE adding a modal, so believing in headroom that does not exist is how the black-screen SIGSEGV comes back. The CRAFT-TOOL DOORS bullet below carries the same count; keep the two in sync or delete one. Each has its own `isPresented:`/`item:` binding and an `AnyView(...)`-erased content closure. This is the baseline that launches — the earlier "ONE `.sheet(item:)` + ONE `.fullScreenCover(item:)` via computed bindings" note was **aspirational, never the shipping code**, and is removed to stop a future session "fixing" the launching code into a regression. **THE REAL RULE (learned the hard way, 10.76.34/build 2068 black screen): do NOT keep GROWING this modifier chain.** Adding sheets pushed the body's aggregate generic type past the SwiftUI metadata-decoder stack limit → SIGSEGV at first render, before any view appears (presents as a black screen, or "Safe Mode oder Black Screen" alternating once the self-healing net catches every other launch). The chain was "just under" the limit at 10.76.9/21; three sheets added 10.76.25/27/29 tipped it over (an `AnyView`-split of the chain did NOT save it — 10.76.35 still crashed; only reverting to the 10.76.21 body did). To add a NEW modal: **reuse/replace an existing slot, or consolidate the whole chain into a single `.sheet(item:)` enum FIRST** — never just append another `.sheet`. (Separately: never drive two modals true at once — that installs an invisible tap-blocking layer, the "can't click anything" hang.) **Also (10.76.41, "Tonart-Menü friert ein / kann plötzlich nicht mehr auswählen"): never read a HIGH-FREQUENCY `@Observable` (the ~10 Hz `CameraRPPGBioPublisher` finger/confidence/waveform, any bio snapshot, a playhead) directly in `EchoelStudioView.body` or in a computed `var` that `body` evaluates — `AnyView(...)` is NOT an observation boundary, so those reads register the WHOLE root body as a 10 Hz observer and every rebuild tears down any open `.menu` Picker popover (the freeze; worse while playing). Confine such reads to their own small leaf `View` struct (e.g. `BioStripView`, `PulseMeasurementView`) so only that view churns; the Picker-hosting body stays still.** **AND (10.76.48, "Sobald Biofeedback läuft kann ich nicht mehr auswählen"): the camera-freeze had a SECOND, non-SwiftUI cause — a high-frequency producer on a background queue must NOT hop to `@MainActor` per item. `CameraRPPGBioPublisher.onFrame` did a `Task { @MainActor }` PER captured frame (~30/s before the analyzer's frame-skip); that flood of tiny main-actor task submissions starved the SwiftUI executor → the open `.menu` Picker stopped responding while bio ran. Fix pattern: the background closure pushes into a lock-protected `RGBSampleQueue` (`@unchecked Sendable`, `NSLock`, capped) with ZERO actor hop; the EXISTING 10 Hz `publishTask` drains+feeds the `@MainActor` analyzer in one batch (carry a `timestamp` so rate maths is unchanged). Rule: never `Task { @MainActor }` per frame from a 30 fps source — batch into an existing low-rate main-actor poll via a Sendable queue.** **AND (10.76.50, the ACTUAL recurring menu-freeze cause — found after 41/43/47/48 each fixed a real-but-insufficient cause): the churn was in `WorkspaceView` (the ROOT, ABOVE every surface), NOT in `EchoelStudioView`. `WorkspaceView.topBar` read `cameraRPPG.waveform`/`detectedBPM`/`isLocked` directly to feed the header `PulseMonitorMini` — `waveform` updates ~10 Hz during biofeedback, so `WorkspaceView.body` rebuilt 10×/s and tore down any open `.menu` Picker in the surface BELOW it. Every prior audit scoped to `EchoelStudioView` and correctly found it clean — the 10 Hz read was one level up. FIX: confine the live reads to a leaf (`PulseMonitorMiniLive` reads the publisher in its OWN body); `WorkspaceView` only reads `isRunning` (start/stop). **RULE: when a freeze/churn persists after the obvious view is proven clean, AUDIT THE PARENT/ROOT (`WorkspaceView`, any always-on header/HUD that reads live bio) — a 10 Hz read in ANY ancestor of the menu host rebuilds the whole subtree. Header/monitor tiles that show live bio MUST read it in their own leaf, never via values passed down from a parent body.**
- **✅ TESTFLIGHT PIPELINE: GREEN (verified 2026-05-30).** Prior "deploy blocker" note is resolved — `testflight.yml` runs #1404–#1407 on `main` all succeeded across every platform (iOS upload + Summary), preflight confirms App Store Connect secrets are present and valid. Dispatch + poll from the sandbox via `bash scripts/check-testflight.sh dispatch` (token in gitignored `.claude/settings.local.json`). Push the feature branch's newer work (bio synth / OSC / Polar) to TestFlight with a full `build_only=false` run once a branch verification run is green.
- **Latest batch (2026-07-12, 24h-Mandat, on branch, gates green, TestFlight-FREEZE bis Profi-Milestone):** **A3 drawable automation canvas** (tap-add / drag-move / segment-bend / double-tap-delete; `AutomationCanvasMath` pure) · **A4 bio-operators** (coherence shifts the chance threshold, roll stays seeded) · **L1 Grand Master + Blackout** (Art-Net + sACN; blackout wins, return slews) · **P1 idle-voice skip** (frames not blocks, 2.5 s window > dub-echo tail; audio-thread-reviewed) · **B2 per-track pan** (`TimelineLane.pan`, honest `sourceNode.pan`/AVAudioMixing engine path, sends deliberately absent) · **B3 Bio into the menu host** (always-on strip removed, "Bio" chip + header long-press) · **B4 BLE strap door — ZURÜCKGENOMMEN am 2026-07-15 durch BLE-3**, die Patchbay ist NICHT die Tür des Gurts (siehe Pipeline-Zeile) · **B5 sample door on every drum channel strip** (slot-reuse) · **W1 LyricsModel** (deterministic singing syllabification + melisma, pure; W-track per founder 2026-07-12C) · **EchoelAI foundation N0–N4** (`scratchpads/ECHOELAI_ADR_2026-07-12.md`: `EchoelParameterRegistry` [keyPath-stable, DDSP inventory] + `BrainBackend`/`FoundationModelsBrain` [Tier-1, `#if canImport(FoundationModels)`+iOS 26, else unavailable] + `ParameterToolCore` [model-free tool logic] + vocabulary data — ALL behind `FeatureFlags.echoelAI` default OFF, Release bit-identical; the LLM never touches the audio thread) · **Body Science learn section** (`BioScienceInfo`: cited HRV-resonance research — Lehrer/Vaschillo, Goessl 2017 — facts + self-observation, NO health claim, test-guarded; report `scratchpads/REPORT_SOUND_PAIN_EVIDENCE_2026-07-12.md`). **Healing/organ/tissue/wound theme = pre-Echoel (BLAB/Syng) legacy, never code here, stays a hard REJECT red line.**
- **Latest work (2026-06-23, on branch, gates green):** **Adaptive Quality** (AdaptiveQuality core + ResourceGovernor: thermal/battery/measured-FPS → tier → MetalBioView detail/reduce-motion **+ OSCSender's bio-egress rate via `PollingRateCeiling`, a CEILING and not a target** — corrected 2026-07-28 twice over: the governor never drove MetalBioView's frame RATE (`MetalBioView.swift:373` pins `preferredFramesPerSecond = 60` statically, and `AdaptiveQuality.swift` says so itself), and the one consumer wired since — `bioHz` → `OSCSender` (34e2355) — was missing. `targetFPS` / `oscHz` / `allowSpectralDonuts` have NO consumer, by design. This is the line a session reads before touching a quality knob, so both halves being wrong was the dangerous kind of stale) · **camera-session resilience** (runtime-error/interruption observers + frame-stall watchdog — fixes the silent ~68–200 s rPPG freeze) · **rPPG saturation-hold** · **composition cohesion** (BioComposer structure/detail RNG split — "homogener klingen") · **master −1 dBFS true-peak trim** · **EchoelFX bio-reactive modulation** (FXModulation core in `Core/` + FXBioModulator ~30 Hz; body→FX-param routing, UI section) · **EchoelFX Bitcrush + Stereo Widener** stages (wired chain/VM/UI/FXPreset/bio-mod) · **VJ visuals** (live in-fullscreen control overlay + shader hue/saturation palette, physical-colour default preserved). EchoelFX deepening = 4 workstreams (1 bio-mod + 2 algorithms shipped; 3 macro-morph + 4 CI-polish pending).
- **Prior TestFlight ship (2026-06-18):** rPPG fix (torch + exposure lock), real frequency-domain HRV coherence (Lomb-Scargle + Welch), resonance breath guide, tap-to-learn bio metrics, Art-Net flash-safety. Base build 1543 (app + Widget + AUv3, camera rPPG, universal BLE, ADM-OSC, EchoelLux Art-Net, launch silence).
- **Absent (not wired — do not claim as shipping):** RTMP/streaming (BroadcastPublisher is a compile-safe scaffold behind `#if canImport(HaishinKit)`; HaishinKit not integrated), Video-SCHNITT (⛔ korrigiert 2026-07-31: hier stand „video capture/edit" — die CAPTURE ist erreichbar und darf sehr wohl als shipping gelten, nur der EDIT ging mit #121 Slice 3), multitrack audio (gebaut, flag-gated AUS, türlos — siehe den ⛔-Absatz „Was hier stand und 2026-07-27 gestrichen wurde" ganz oben und #204; „absent" stimmt für den Nutzer, „nicht gebaut" nicht für den Entwickler). **EchoelStore** (`Core/EchoelStore.swift`) = compiling but UNREACHABLE: `ProUnlockView` exists and is never presented (`WorkspaceView.swift:117`), so nothing is purchasable today. Corrected 2026-07-25 — the old "ZERO consumers" + "legacy subscription product IDs" wording was false on both halves: the one compiled product is the NON-CONSUMABLE `com.echoelmusic.app.pro` (`ProGate.swift`). **Aber das ist ÜBRIGGEBLIEBEN, nicht der Plan** (korrigiert 2026-07-28): die zweite Founder-Entscheidung vom 2026-07-10, wörtlich festgehalten in `WorkspaceView.swift` über `body`, hebt das Einmal-Pro auf — v1.0 komplett kostenlos, v1.1 = „Echoel Live" Jahres-Abo, v1.2 = Per-Event-Host-Gebühr. `ProUnlockView`/`EchoelStore`/`ProGate` bleiben im Code, um dafür UMGEWIDMET zu werden: nicht löschen, vor v1.1 nicht wieder präsentieren. **Push/CloudKit:** `aps-environment=production` + iCloud/CloudKit entitlements ARE declared and `AnnouncementCenter` (registerForRemoteNotifications + CKQuerySubscription) EXISTS — but hard-gated OFF for v1.0 via `AnnouncementCenter.cloudKitConfigured = false` (zero CloudKit/push calls execute; launch-crash fix v10.79.148). Its Learn-view toggle is HIDDEN while the gate is false (2.1 audit 2026-07-16). Before flipping the gate in v1.1: deploy the CloudKit "Announcement" schema to Production FIRST. (The old "zero push code" claim here was stale — corrected 2026-07-16.) **Art-Net + sACN (unicast) are live.** **VocoderCore / BioModulation** = pure tested cores, **not yet wired** (foundations). **FeedbackGuard** (audio-input live monitoring): ENGINE wired (AudioEngine ~15 Hz Duck-Loop, Tests grün) — aber die UI-Tür (`AudioInputPickerView`, `showInput`) ist seit dem Tools-Grid-Removal (2026-07-02) UNERREICHBAR; gleiches Schicksal für PatchbayView (Routing!), MeditationView, PatchEditorView, SampleBrowserView, AutomationView, BroadcastView, SpectralDonutView — alle Slots existieren, einziger Trigger war das tote `toolsSection`/`openTool` (Deep Audit 2026-07-12; tote Slots = SLOT-REUSE-Reservoir an der Modal-Decke). **BEHOBEN (2026-07-12 batch + seither):** PatchbayView (Routing/Master-Panel), ~~SampleBrowserView (B5, Drum-Channel-Strip-Tür)~~ — **GELÖSCHT 2026-07-27 (#167)**; die B5-Tür starb schon mit den Drums (#166), die Datei ist jetzt auch weg. Genau die „verifiziert erreichbar"-Falle, vor der derselbe Absatz warnt: Slot + Setzer beweist keine Erreichbarkeit, und ein Eintrag hier veraltet still, **FeedbackGuard/AudioInputPicker** (Master-Panel „Audio input"-Tür, EchoelStudioView.swift `masterDoorButton`) ist wieder erreichbar. **NICHT erreichbar** (Stand 2026-07-31, per Zählung der Instanziierungsstellen): ~~`PatchEditorView`~~ — **GELÖSCHT 2026-07-31 (#132 Slice 6)**, kein Eintrag mehr in dieser Liste, weil es die Datei nicht mehr gibt; der lebende Timbre-Editor ist und war `soundPanel` hinter dem Sound-Chip. `AutomationView` (Datei existiert nicht), `SpectralDonutView`, `SampleBrowserView` (mit #167 gelöscht), ~~`FileWaveformView`~~ — **GELÖSCHT 2026-07-28 (#132 Slice 5, `2245671`)** zusammen mit `WaveformView` und `WaveformCache`; kein Eintrag mehr in dieser Liste, weil es die Datei nicht mehr gibt. Der reine Kern `WaveformReducer` BLEIBT, jetzt test-only und mit Nachruf im eigenen Datei-Kopf. **Genau die Falle, vor der dieser Absatz zweimal warnt:** der Eintrag stand hier als Gegenwarts-Tatsache, geschrieben am selben Tag als PLAN für genau diesen Commit — wer ihn danach las, hätte eine türlose Waveform-Ansicht wieder aufmachen wollen, die es nicht mehr gibt. **KORREKTUR 2026-07-26 (die „verifiziert 2026-07-21"-Zeile war FALSCH für zwei ihrer Einträge):** `AutomationView.swift` existiert im Repo nicht mehr — es kann keine Tür haben. Und **`SpectralDonutView` ist UNERREICHBAR:** ihr einziger Instanziierungsort liegt im `.fullScreenCover(isPresented: $showVisual)`, und `showVisual`s einziger Setzer war `openTool`, aufrufbar nur aus `toolsSection`, **das nichts rendert**. Dieselbe tote Kette nimmt den MIDI-**Import** (`midiImportPresented` / `importMIDI()`) und die REC-Taste im Visual-Vollbild mit; die „Donuts"-Pille im Synth-Reiter ist live antippbar und wirkungslos, weil `FloatingVisualWindow` — das einzige erreichbare Visual — den `spectralDonuts`-Key nie liest. **3 der 14 Präsentations-Slots hängen an Flags, die niemand setzen kann** = freier Kopfraum an der Metadata-Decke, statt einen 17. anzuhängen. Der tote Tools-Katalog selbst ist mit `f371d27` gelöscht (`ToolCat`/`ToolItem`/`toolItems`/`openTool`/`toolsSection`/`toolGroup`/`gridChip`/`gridChipLabel`, 157 Zeilen) — die drei Modifier stehen absichtlich weiter da, als wiederverwendbare Slots. **Er nahm dabei die einzige Oberfläche für drei Opt-ins mit:** „Save to Apple Health" (persistiert! mit `083cec8` als `HealthWriteOptInRow` im Bio-Panel zurückgeholt — ein persistiertes Gesundheits-Einverständnis MUSS einen erreichbaren Aus-Schalter haben) sowie `midiOut.mpeEnabled` / `expressionEnabled` (nicht persistiert, Default aus → Fähigkeitslücke, kein Einverständnis-Problem; gehören in die Routing-Fläche, offen). ZWEI LEHREN: (1) „per direktem Code-Read verifiziert" heißt nur etwas, wenn die Kette bis zum RENDERNDEN Elternteil verfolgt wurde — Slot + Setzer beweist keine Erreichbarkeit. (2) **Vor dem Löschen eines UI-Blocks prüfen, welche Modelle er als EINZIGER schreibt** — ein Toggle mit persistiertem Flag hinterlässt beim Löschen einen unwiderruflichen Zustand, keine Lücke. **Keine Zeilennummern in diesem Absatz:** die erste Fassung zitierte Nummern, die derselbe Commit um 157 verschob. MeditationView bleibt bewusst türlos (Founder: Teil des Produktionsflusses, keine eigene Tür gewollt). **BroadcastView bleibt türlos — korrekt so**, solange HaishinKit/RTMP nicht verlinkt ist (eine Tür zu einem nicht funktionierenden Backend wäre ein Halbfertig-Feature). **BioVisualParams** (immersive flash-safe pulse) is **wired**. See `docs/dev/FEATURE_MATRIX.md` + `scratchpads/DEEP_AUDIT_2026-07-12.md`.
- **P1 "Sound complete" — ALREADY BUILT (audited 2026-07-01; corrects the old "Clips/Arrangement UI not wired" note):** the melodic/DAW core is done and wired — **polyphonic synth** (`PolySynthVoice`) + **bass** (`SubBassVoice`) + ~~hybrid sample/synth drums~~ (`BeatPlayer` + `DrumSynthVoice` — **entfernt 2026-07-26, #166/#167; klingt nicht mehr**); **full patch editor + presets** (`SynthPatch`/`PatchStore` + `soundPanel`, favorites/community/save-as, live-apply, tested. ⛔ Hier stand `PatchEditorView` als der Editor „DOORLESS since 2026-07-25" — die Datei ist mit #132 Slice 6 gelöscht; der Editor war die ganze Zeit `soundPanel` hinter dem Sound-Chip); **breakbeat loop-cut** (`LoopCutter`/`LoopBarLength` in the Studio UI); **MIDI export** — **AUSGELIEFERT** (korrigiert 2026-07-28): `exportMIDI()` wird wieder aufgerufen, aus dem Export-Schacht heraus (#188 hat die Tür in den VORHANDENEN Slot zurückgeholt, kein neuer Sheet). `MIDIFileExporter` intakt und getestet. Der App-Store-Text behauptet den MIDI-Export — nicht entfernen, ohne `fastlane/metadata` mitzuziehen; Clips + Arrangement UI **DELETED** by the pure-instrument epic (#121 Slice 4 — `ClipView` 807dc0d, `ArrangeTimelineView` eb58e7a; `ClipStore`/`ArrangementStore`/`AutomationLane` model retires in Slice 5).
  **CRAFT-TOOL DOORS — the #131a craft-editor slot is GONE again (2026-07-26).** It was shipped 2026-07-25 (`f2cbf34`/`bda8f41`) to door the piano roll, and it held exactly ONE case; when the founder said *"Pianoroll soll raus"* the honest move was to take the slot with it rather than leave an undoored enum (the lying-`toolItems` trap). **Body presentation-modifier count = 14** (8 sheet + 2 cover + 3 alert + 1 fileImporter), verified by grep 2026-07-27 — the sample-browser `.sheet(item:)` went with `SampleBrowserView` (#167). It was 15 the day before — it was 16 the day before, and the "= 12" before that counted only `.sheet`+`.fullScreenCover` and read as headroom that does not exist. Alerts and the file importer sit on the same chain and carry the same metadata cost. **The NEXT editor re-introduces the slot as `enum` + `@State` + ONE `.sheet(item:)` + an out-of-body content builder — NEVER a bare appended modifier**, and a case is added ONLY together with its door. Three of the 14 slots (`showVisual`, `showMeditation`, `midiImportPresented`) have no setter at all and are the first place to look for room. `sampleBrowserTrack` was the fourth and is DELETED (2026-07-27): once `SampleBrowserView` itself went, the slot pointed at a type that no longer compiles — a slot is only reusable while its content still builds.
  · **`PianoRollView` = DOORLESS AND UNMOUNTED** (founder 2026-07-26). The struct still compiles and still exists because `Tests/EchoelmusicTests/NoteOperatorsTests.swift` calls its static `occurrencePeriod(forUnit:)`; hoisting that one pure function into a core file is what unblocks deleting the struct. `RollSelection` is file-scope and would survive that deletion. **Consequence to state plainly: there is NO note editor in the app any more** — the generated take can be heard, mixed and exported, not corrected.
  · **`PatchEditorView.swift` IST GELÖSCHT (#132 Slice 6, 2026-07-31).** Die Vorgeschichte gehört hierher, weil sie zweimal in die falsche Richtung gelesen wurde: die Datei war seit dem Tools-Grid-Removal türlos, und meine frühere Behauptung, das Instrument könne „keinen Klang formen oder speichern", war FALSCH — `soundPanel` (an `dropdownContent` `.sound`, erreichbar über den Sound-Chip) IST der lebende Timbre-Editor und war es die ganze Zeit. Blockiert war die Löschung von fünf persistierten Parametern, deren einzige Zeile in der türlosen Datei stand; sie sind portiert (**`unisonVoices`/`unisonDetuneCents` mit #281, `spectralShape`/`noiseColor` und `outputLevel` mit #286**), jeder mit gerenderter Zeile UND Wächter im blockierenden Bundle (`Tests/CISmoke/UnisonRowDefaultsTests.swift`). Die **Preview-Tastatur** war kein Parameter, sondern eine Urteilsfrage — entschieden: die Spielfläche deckt sie ab, nicht portiert. Die **Preset-Leiste** (laden · favorisieren · speichern · Save-as · löschen · einreichen) ist da (⛔ hier stand „fehlte nie“ — in diesem SHALLOW-Klon, gepfropft auf `24e9420`, liefert `git log -S` auf die Aufrufstellen nur den Graft; die Gegenwart ist belegbar, die Vorgeschichte nicht, und genau solche unbelegten „schon immer“-Sätze streicht diese Datei an anderer Stelle selbst): `presetRow` hält alle sechs, seit `Tests/CISmoke/SoundPanelPresetBarTests.swift` auch nachweislich — und DAS ist der Grund, warum die Löschung nichts gekostet hat. ⚠️ Die `outputLevel`-Hälfte hing einen Monat an einer Begründung, die faktisch falsch war (ein Quellkommentar erklärte einen manuellen Trim für unvereinbar mit `loudnessNormalized()`; das läuft **einmal** beim Bau der `static let factory`-Liste und kann eine Nutzer-Eingabe nie überschreiben, was das Feld-Doc seit dem ersten Tag sagt). **Lehre: ein „gehört dem Founder"-Vermerk mit prüfbarer Begründung gehört geprüft, bevor er eine Aufräumarbeit blockiert.**
  · **`ImmersiveStageView` (spatial stage) stays doorless — deliberately.** Ship-gate item 4 makes light/space "demonstrable, not required for v1" (#131c).
  · **Correction to a claim I made about the roll:** presenting it is NOT what publishes `MusicalFrame`. That publish is in `PianoRollModel`'s tick handler (`PianoRollView.swift`) on the shared sequencer tick, installed once at app start (`pianoRoll.start(...)` in `EchoelmusicApp`) — so the visual/light output stage is lit whether or not the roll is open. The door is load-bearing for EDITING, not for the spine.
  · **NEEDS-FOUNDER-VERIFY:** launch (the +1 modifier vs the black-screen law) and the roll's Stop, which cascades the ONE-Stop law (the ONE-Stop cascade in `PianoRollView`) and ends the whole bio session rather than only playback.
  Music theory is fully in-house. The real remaining frontier is **P3 Video** (⛔ korrigiert 2026-07-31: „no recorder/trim/export yet" war falsch für zwei Drittel — RECORDER und EXPORT existieren und sind erreichbar, `VisualRecorder` + `FloatingVisualWindow`s Aufnahmetaste + `videoPanel` → `VideoLibraryPanelContent` mit mp4-Share. Was fehlt, ist der TRIM/SCHNITT, mit #121 Slice 3 absichtlich entfernt) and **P4 Broadcast**. See `scratchpads/PLAN_REDOOR_CRAFT_TOOLS_2026-07-25.md`.
- **Files:** **346** Swift under `Sources/` (`git ls-files 'Sources/**/*.swift' | wc -l`, 2026-08-05 nach `Bio/PerformerSignature.swift` (#403 Slice 1 — WIEDER EINE Datei, reiner Kern ohne eigene Ansicht, und damit die VIERTE hintereinander. Der Absatz sagt eine Zeile weiter, dass drei keine Regel sind; vier sind es auch nicht — sie folgen daraus, dass diese Scheiben Arithmetik und Persistenz waren, nicht Fläche. Die Tür ist hier nicht einmal eine Zeile in einem Panel, sondern eine Faltung INNERHALB einer schon vorhandenen Methode (`makeComposerInput`), also die kleinste mögliche), davor „345" nach `Sequencer/TakeDistance.swift` (#403 Slice 0 — EINE Datei, reiner Kern ohne eigene Ansicht, wie #398 und #400. Drei Ein-Datei-Scheiben hintereinander sind jetzt eine Serie und trotzdem KEINE Regel: sie folgen daraus, dass die letzten drei Scheiben Arithmetik waren, nicht Fläche. Die nächste Scheibe, die etwas ZEIGT, ist wieder +2), davor „344" nach `Core/SoundReset.swift` (#400 - wieder EINE Datei, reiner Kern ohne eigene Ansicht, wie #398: die Tür ist eine Zeile in einem SCHON vorhandenen Panel („Save & Export“), keine neue Fläche. Zwei Ein-Datei-Scheiben hintereinander machen daraus trotzdem keine Regel — die #385-Scheibe zwei Einträge weiter war +2), davor „343" nach `Core/RegenSchedule.swift` (#398 — EINE Datei, reiner Kern ohne eigene Ansicht: die Arithmetik zog aus einer View-Methode aus, es entstand keine zweite Fläche. Der Gegenfall zu den #347/#385-Scheiben direkt daneben, und der Grund, warum „+1 oder +2" nichts ist, das man aus dem Muster ableiten kann — man zählt), davor „342" nach `Studio/WavefrontField.swift` + `Studio/AnalysisWavefrontView.swift` (#385 — ZWEI Dateien, Kern plus Ansicht, wie jede #347-Scheibe; genau der Fall, den Slice 2 dort mit nur +1 verbucht hat), davor „340" nach `Studio/HeaderSpectrumStrip.swift` (#384) — ⚠️ und dieser Stand wurde NACH dem `git add` gemessen: der Befehl listet nur getrackte Dateien, eine frisch angelegte zählt er erst nach dem Stagen. Wer vor dem Stagen misst, trägt die Zahl von gestern ein und merkt es nicht. Davor „339" nach `Studio/AnalysisPoincareView.swift` (#347 Slice 3b), davor „338" nach `Bio/PoincareMetrics.swift` (#347 Slice 3a), davor **„337"** nach `Studio/SpectrumReadout.swift` + `Studio/AnalysisSpectrumView.swift` (#347 Slice 2). ⛔ **Und an dieser Stelle stand „336", gemessen falsch:** `git ls-tree -r --name-only 23ee416 Sources | grep -c '\.swift$'` sagt 337. Beide #347-Slices haben je ZWEI Dateien angelegt (Kern + Ansicht); Slice 1 wurde korrekt mit +2 verbucht (333→335), Slice 2 mit nur +1. Der Fehler ist NICHT das übliche Vergessen des Nachführens — die Zeile wurde im selben Commit angefasst, nur um eins zu niedrig. **Lehre für diesen Absatz, der schon zwei andere Zähl-Lehren trägt: beim Nachführen zählt der Befehl, nicht die Erinnerung an „ich habe eine Datei angelegt".** Davor „335" nach `Studio/ScopeTrigger.swift` + `Studio/AnalysisScopeView.swift` (#347 Slice 1), „333" nach der #132-Slice-6-Löschung von `Studio/PatchEditorView.swift`, am 2026-07-31 früher „334" (nach `Studio/VisualEnergy.swift`, #228), „333" (nach der #167-Löschung der drei Drum-Dateien), „336" (nach `DSP/ExpressionLevelTrim.swift`) und „335", davor „333" (30.), „331" (29.), „330" am selben Tag, „326" (28.), „323" am selben Tag; ZWANZIG Stände in neun Tagen — 346·345·344·343·342·340·339·338·337·335·333·334·333·336·335·333·331·330·326·323, und ACHTUNG beim Nachzählen: „336" steht in dieser Zeile jetzt ZWEIMAL für zwei verschiedene Dinge — einmal als echter Stand vom 2026-07-31 (nach `DSP/ExpressionLevelTrim.swift`) und einmal in der ⛔-Notiz oben als die FALSCH eingetragene Zahl, die nie ein Stand war. Nur der erste zählt (⛔ und beim Nachführen auf diesen Stand stand hier ZEHN, während elf Zahlen dastanden — schon wieder das Zahlwort, schon wieder in dem Absatz, dessen einziger Zweck das Mitzählen ist. Der Fehler ist nicht Nachlässigkeit, sondern ein Muster: wer eine Zahl vorne einfügt, liest das Zahlwort als Prosa und nicht als eine zweite Zahl, die er gerade ungültig gemacht hat) (der AKTUELLE Wert ist hier mitgezählt — der CISmoke-Absatz weiter unten zählt umgekehrt nur die HISTORIE, also einen weniger als es Stände gibt; zwei Absätze, zwei Konventionen, beide für sich korrekt, aber wer sie vergleicht, muss das wissen), alle einmal als Beleg zitiert (⛔ die erste Fassung dieser Zeile schrieb „NEUN" und listete acht — in genau dem Absatz, dessen einziger Zweck das Mitzählen ist. Zähl die Zahlen, nicht das vorige Zahlwort +1). Dass „333" hier zum DRITTEN Mal steht — einmal als aktueller Wert, zweimal in der Historie — ohne dass es je dieselben Dateien sind, ist der Beweis, dass die Zahl allein nichts belegt. Das Zahlwort MITZÄHLEN ist Teil des Nachführens — der CISmoke-Absatz weiter unten hat genau daran schon einmal veraltet. **Schreib hier nie eine Zahl hin, ohne den Befehl danebenzustellen**, und lies sie nie ohne ihn nachzuführen), **ZERO Metal files** — corrected 2026-07-25; the old "~212 Swift + 1 Metal (`Video/Shaders/ChromaKey.metal`)" was stale twice over: the count was long out of date and `ChromaKey.metal` was DELETED by Slice 3 (video-cut removal) together with its directory. `MetalBioView` compiles its shader inline at runtime, so the app ships no `.metal` source at all. | **Swift 100%** | top-level dirs under `Sources/Echoelmusic/`: `Audio Bio Core DSP EchoelAI Resources Sequencer Stream Studio Sync Tools Video Views`, plus the two loose top-level files `EchoelmusicApp.swift` and `MicrophoneManager.swift`. NOTE: the "four pillars" (EchoelTools/Works/Sync/Well) referenced by older vision docs were **never built as modules** — `EngineBus` is the one real coupling spine; `Views/` now holds only `MetalBioView` + `OnboardingView` (its long deprecated list is gone).

---

## BRAND

**Echoel — Physical Computing · Biofeedback · Multimedial & Multidimensional.**

An immersive multimedia instrument and production platform for **Installation · Event · Content · Cinema · Theater · Performance.** The body is the controller: heart and breath drive sound, image, light and immersive space in real time.

⛔ **Der Absatz, der hier stand, war die dichteste Falschstelle der ganzen Datei** — und er stand unter der Überschrift BRAND, also genau dort, wo eine Session Formulierungen für Store-Text, Website und Presse HOLT. Er lautete: *„Concrete capabilities span beat-making, multi-track recording, video capture/edit, RTMP live streaming, bio-reactive synthesis, generative visuals, and OSC/MIDI/MPE integration"*. Davon existieren heute: bio-reaktive Synthese, generative Visuals, OSC/MIDI. **Beat-making ist mit #166/#167 gelöscht · Video-EDIT mit #121 Slice 3 · RTMP war nie verlinkt · MPE hat keinen Schreiber · Multi-Track-Recording ist gebaut, aber flag-gated aus und türlos.** Fünf falsche Behauptungen in einem Satz, aus dem Marketing-Text entsteht — #184 hat genau solche zwölf aus dem App-Store-Text entfernt, wo eine falsche Behauptung eine 2.3-Ablehnung ist. **Die wahre Fassung ist die Zeile, die mit „Capabilities (all routed through one typed bus)" beginnt**; von dort zitieren, nicht von hier. (⛔ Hier stand „Zeile 18" — falsch, weil derselbe Commit zwei Zeilen darüber eingefügt und den Verweis mitverschoben hat. In dieser Datei ist eine zitierte Phrase belastbar und eine Zeilennummer nicht; der Absatz zu den Modal-Slots sagt dasselbe über sich.) Die Identität ist **das Instrument**, nicht ein Konkurrent, den es ersetzt.

**Biofeedback is core, not wellness.** Echoel treats physiology as a first-class, science-based modulation source (HRV resonance, peer-reviewed bio-signal processing). It is NOT a wellness, soundscape, or therapy product.

NEVER use "BLAB", "Vibrational Force", legacy bio-wellness/soundscape branding, or esoteric terminology ("healing frequencies", chakras, Solfeggio) in user-facing copy.

---

## ARCHITECTURE (original v10 target — SUPERSEDED; see CURRENT STATE for as-built)

> ⚠️ **This tree is the ORIGINAL v10 plan, NOT what shipped.** The as-built app is a
> single `EchoelStudioView` (see "CURRENT STATE" above and "Studio sections" below) —
> there is **no `StudioRoot` TabView**, and Record/Video/Share were never built
> (RTMP / video capture / multitrack = roadmap). Kept here only as the audio-foundation
> reuse map.

```
EchoelmusicApp (@main)
└── StudioRoot                     ← TabView with 4 tabs (NEW)
    ├── BeatTab                    ← drum pads + 16-step sequencer (NEW)
    │   └── PatternEngine          ← 8-track × 16-step + tempo clock (NEW)
    │       └── SamplerVoice       ← one-shot WAV player (NEW)
    ├── RecordTab                  ← mic + master mixer + REC (NEW)
    │   ├── MultiTrackRecorder     ← mic over beats, sample-accurate sync (NEW)
    │   ├── RetroCapture           ← 30s pre-roll ring buffer (KEEP)
    │   └── AutoMixChain           ← EQ → Comp → Limiter → LUFS (KEEP)
    ├── VideoTab                   ← camera capture + trim (NEW)
    │   ├── CameraSession          ← AVCaptureSession 1080p30 (NEW)
    │   ├── VideoRecorder          ← AVAssetWriter H.264+AAC (NEW)
    │   └── ClipTrimmer            ← in/out points (NEW)
    └── ShareTab                   ← RTMP stream + export (NEW)
        ├── RTMPPublisher          ← HaishinKit wrapper (NEW)
        └── SingleExport           ← LUFS mastering → WAV/AAC/MP4 (KEEP)

Audio Foundation (KEEP):
  AudioEngine (AVAudioEngine master bus) · MicrophoneManager · SPSCQueue ·
  EchoelDDSP (reused as synth voice) · EchoelCellular (reused as FX texture)
```

Deprecated from main flow: the old SoundscapeEngine, ClipEngine, MomentCaptureView,
  BioSourceManager, Oura/EEG bridges, WeatherProvider, CircadianClock files have all
  been REMOVED in cleanup (2026-06-19 audit) — they no longer exist. (HealthKit + rPPG
  are now LIVE, not deprecated.) The genuinely app-unwired pure cores remaining are
  BioModulation and CloudSync. NOW WIRED — do NOT list these as unwired: BioVisualParams
  (read by EchoelBioEngine + MetalBioView), FeedbackGuard (AudioEngine duck loop + the
  masterDoorButton „Audio input" door), LearnLibrary (LearnView), EchoelFXView (doored via
  `showAllFX`), VocoderCore (consumed by VoiceAnalyzer + BrainwaveModulation — whether THAT
  chain reaches a door is unverified, so do not claim either way).

Protected (do not modify without explicit user approval):
  BioEventGraph, HilbertSensorMapper, BioSignalDeconvolver.

### EchoelStudioView (actual, as shipped — corrected 2026-07-04)

**The single Compose instrument, NOT a section shell.** Since the 2026-07-02 founder
pivot ("Alles weg außer visuals"), the section Picker and the Tools grid are REMOVED
from the UI — `EchoelStudioView` is the one-button bio-generative flow: a menu bar of
chips, each opening one dropdown panel, plus generate + play and FX character.

**Re-verified against code 2026-07-25 — all three concrete claims that stood here were
wrong, so check before trusting this paragraph again:**
- `BioStripView` is NOT always-on. It lives in `bioPanel` (`EchoelStudioView`),
  reached by the "Bio" chip — that is deliberate (B3, 2026-07-12): the always-on strip was
  removed so its 10 Hz camera read stays in a leaf and cannot tear down an open Picker.
- `PianoRollView` is DOORLESS again — the chip, the `craftEditor` slot and its content
  builder were all removed 2026-07-26 on the founder's "Pianoroll soll raus". This
  paragraph has now flipped twice; check `menuBar` before trusting either version.
- The patch editor's live equivalent is `soundPanel` (presets, tone/filter/envelope, save-as)
  behind the Sound chip. `PatchEditorView.swift` was the near-duplicate file and is DELETED
  (#132 Slice 6, 2026-07-31) — it never was the live door.

There are no audio-clip doors — that surface went with the DAW removal. AUv3 hosting is
gone (#121 Slice 2). The old Section/Tools table stood here until 2026-07-04; do not
resurrect it as fact.

---

## TECH STACK — Zero Dependencies Today

| Layer | Framework |
|---|---|
| Apple (iPhone) | SwiftUI + AVFoundation + Accelerate + Metal + CoreMIDI + **Network** (OSC · ADM-OSC · Art-Net · sACN) + die Sensor-/Kollab-Quellen HealthKit · CoreBluetooth · CoreLocation · WeatherKit · MultipeerConnectivity, je hinter `canImport` |
| RTMP/RTMPS | HaishinKit = **PLANNED** dep for P4 Broadcast — NOT linked (`Package.swift` `dependencies: []`; `BroadcastPublisher` is a `#if canImport(HaishinKit)` scaffold) |
| Build | XcodeGen (`project.yml`) + Fastlane (TestFlight upload) + GitHub Actions |
| DSP | Swift (audio-thread-safe, lock-free SPSC queues) |

⛔ **`VideoToolbox` und `SwiftData` standen hier und werden NIRGENDS importiert** (`git grep -l VideoToolbox -- Sources` → 0, `git grep -ln 'import SwiftData' -- Sources` → 0; Stand 2026-07-31). Das ist die Tabelle, die eine Session liest, BEVOR sie eine Persistenz- oder Encode-API wählt — ein Phantom hier führt direkt zu Code gegen ein Framework, das das Projekt nicht benutzt. Persistenz läuft über `Codable` + JSON in `*Store`-Typen, Video-Encode über `AVAssetWriter` in `VideoRecorder`.

⛔ **Und die erste Reparatur dieser Zeile machte denselben Fehler eine Stufe kleiner.** Sie ergänzte fünf Sensor-/Kollab-Frameworks und ließ **`Network` weg** — dabei trägt genau das die Sync-Fähigkeit, die die Identitätszeile nennt (`Sync/OSCSender`, `ADMOSCSender`, `ArtNetSender`, `SACNSender`, **4 Dateien**, mehr als HealthKit mit 3). Eine Tabelle, die vor der Wahl einer Netzwerk-API gelesen wird und das Netzwerk-Framework verschweigt, ist derselbe Defekt wie ein Phantom, nur andersherum. Ebenfalls nachgetragen: `SwiftUI` (47 Dateien, das mit Abstand meistimportierte). Bewusst NICHT gelistet: `UIKit` (13) — es steht schon als Plattform-Guard-Regel weiter unten; und die Ein-Datei-Fälle CloudKit · Photos · ARKit · AVKit · CoreHaptics · UserNotifications, damit die Zeile eine Orientierung bleibt und kein Inventar wird. **Auswahlregel, damit die nächste Ergänzung nicht wieder willkürlich ist: alles, was eine in der Identitätszeile genannte Fähigkeit trägt, plus alles ab ~3 importierenden Dateien.**

Zählweise: `git grep -ln "import <X>" -- Sources` — **und das zählt Kommentare mit**. Die erste Fassung schrieb „CoreBluetooth 2 Dateien"; einer der beiden Treffer ist Prosa in `MultipeerSession.swift`, echt importiert wird es in **einer**. **Jeder neue Eintrag in dieser Zeile braucht den Befehl daneben — und einen Blick auf die Treffer, nicht nur auf ihre Anzahl.**

**⭐ PLATTFORM-ZIEL (Founder 2026-07-31, wörtlich): „Das gesamte Apple Ökosystem soll langfristig unterstützt werden auch VR/XR und Waerables."** Das ist die Richtung, nicht eine Option — iPhone-first ist **Reihenfolge, kein Umfang**. Konsequenz für jede UI-Entscheidung ab hier: **jeder feste `frame(width:/height:)` und jedes Panel, das nicht reflowt, ist Ökosystem-Schuld**, kein Schönheitsfehler. Der Adaptivitäts-Durchgang (#292) ist damit Fundament, nicht Politur.

**Heute ausgeliefert: iPhone (`"1"`) + Watch als Anzeige (`"4"`).** Die Reifeleiter — was jede Plattform BRAUCHT, bevor sie angeschaltet werden kann, damit die nächste Session nicht rät:

| Plattform | Stand | Was fehlt, bevor es angeht |
|---|---|---|
| **iPhone** | live | — (Instrument · Sensor · Ausgabe) |
| **Watch** | Target existiert, `EchoelmusicWatch/EchoelWatchApp.swift` (95 Zeilen) liest App-Group-Werte | die **Produzenten-Hälfte** (Handgelenk-HealthKit-HR → App Group → Telefon). Im Dateikopf selbst als „C7" markiert und **nie gelandet** — das ist die konkreteste Wearable-Lücke. **Harte Grenze bleibt:** ~4–5 s Latenz → Anzeige, Trend, langsame Modulation (HRV/Kohärenz), **niemals Beat-Sync** |
| **iPad** | **vier Einstellungen + ein Wächter, in EINEM Commit** (`TARGETED_DEVICE_FAMILY` an App · Widget · beiden Test-Bundles, dazu `Tests/CISmoke/DeviceFamilyIsPhoneOnlyTests.swift` — harte Gleichheit im BLOCKIERENDEN Bundle — **plus zwei Prosa-Blöcke**, die beim Ändern falsch werden: der `#`-Block über der Einstellung und die ⛔-Notiz unter dieser Tabelle) | eine dort funktionierende Bio-Quelle — kein iPad hat eine rückseitige LED, und `CameraCapture` koppelt die rPPG-Beleuchtung an `device.hasTorch`; der BLE-Gurt ist gebaut+verdrahtet, die Watch käme als zweite Quelle infrage — **plus** #292 (heute reflowen **3 von 10** Panels; Befehl siehe die Zeile „Kein ‚nie'" unter dieser Tabelle. ⛔ Diese Zelle stand auf „2 von 11", während die Zeile „Kein ‚nie'" schon „2 von 10" sagte — DIESELBE Tatsache, zwei Zahlen, 12 Zeilen auseinander, weil #359 Schritt 3 nur die untere nachführte. Der Absatz unter dieser Tabelle trägt fünf Lehren über seine eigenen Zählfehler und keine davon lautete „such nach der ZWEITEN Stelle"; sie lautet jetzt so) |
| **Vision / XR** | kein Target; `visionOS` kommt in `Sources/` nur in Plattform-Guards vor (`MicrophoneManager`, `AudioInputManager`, `SPSCQueue`, `MemoryPressureHandler`) | der natürliche Sitz ist die **Ausgabe-Stufe, die schon existiert**: `ImmersiveStageView` (türlos, absichtlich — Ship-Gate 4 sagt „demonstrierbar, nicht erforderlich"), ADM-OSC-Raum, das Visual. Bio-Quelle bliebe Telefon oder Gurt |
| **Mac** | kein Target, kein Catalyst-Flag | offen |

⛔ **Was hier bis 2026-07-31 stand, war doppelt irreführend, und die zweite Fassung desselben Tages auch.** Erst: „iPhone-only for v10 MVP. iPad / Mac / Watch / Vision deferred to v1.1+" — während `project.yml` an ALLEN VIER iOS-Targets `TARGETED_DEVICE_FAMILY: "1,2"` setzte, die App also an iPad ausgeliefert wurde. Niemand hatte das entschieden; es war ein Default, den niemand nachgelesen hat. Dann, nach der Korrektur auf `"1"` (#292), las sich der Absatz wie ein **Ausschluss** von iPad/Vision — genau falsch herum, wie der Founder Stunden später klarstellte. Die Entscheidung (v1.0 = iPhone) steht; ihre BEGRÜNDUNG ist Sequenzierung und der fehlende Sensor auf iPad, nicht ein Verzicht auf das Ökosystem.

⛔ **Und die iPad-Zeile trug bis zur Reviewer-Nachlese am selben Tag einen Slogan, der in VIER Dateien gleichzeitig stand und in jeder falsch war:** „Wiederanschalten ist EINE Zeile" (hier, in `project.yml`, im Commit-Text und in `decisions.csv`) — während der Wächter, den **derselbe Commit** installierte, wörtlich sagt „change the settings AND this test in the same commit". Zwei Sätze aus einem Changeset, die einander widersprechen; der eingängigere war der falsche. Es sind vier Einstellungen plus der Wächter plus zwei Prosa-Blöcke, die beim Ändern falsch werden. **Lehre, weil sie sich von der üblichen unterscheidet:** hier war nicht eine Zahl veraltet, sondern eine Behauptung wurde nie geprüft, weil sie gut klang und niemandem wehtat — und sie ist genau der Satz, aus dem eine künftige iPad-Rückkehr ihren Aufwand schätzt. Ein Slogan, der Arbeit KLEINER macht als sie ist, ist gefährlicher als eine falsche Zahl.

⛔ **Dieser Satz war bis 2026-07-31 eine BEHAUPTUNG, kein Zustand** — und er stand hier, während `project.yml` an ALLEN VIER iOS-Targets `TARGETED_DEVICE_FAMILY: "1,2"` setzte, die App also an iPad ausgeliefert wurde. Niemand hatte das entschieden; es war ein Default, den niemand nachgelesen hat. Founder-Frage („Sind alle Fenster adaptiv für alle Geräte?") plus Delegation („Du entscheidest zukunftsweisend") → jetzt wirklich `"1"` (#292), abgesichert durch `Tests/CISmoke/DeviceFamilyIsPhoneOnlyTests.swift`.

**Der entscheidende Grund ist der SENSOR, nicht das Layout, und er gehört hierher, weil aus dieser Zeile heraus über Plattformen geplant wird:** `CameraCapture` koppelt die rPPG-Beleuchtung an `device.hasTorch`, und kein iPad hat eine rückseitige LED. Auf iPad läuft der Finger-auf-Linse-Puls also ohne Licht — genau die Bedingung, die der 2026-06-18-Fix als Ursache fürs Nicht-Locken identifiziert hat. Ein iPad-Build stellt die eigene Prämisse („Dein Körper spielt es") auf ein Gerät, auf dem die Hauptquelle degradiert ist.

**Kein „nie".** Die großen Flächen sind die Zukunft als **AUSGABE** — externer Bildschirm/Beamer (#206), ADM-OSC-Raum —, nicht als zweite App-Oberfläche. Kommt iPad als Instrumenten-Fläche zurück, braucht es eine dort funktionierende Bio-Quelle (der BLE-Gurt ist gebaut und verdrahtet) plus den Adaptivitäts-Durchgang #292. **Der Durchgang passiert ohnehin:** iPhone allein spannt 375–440 pt, erlaubt Querformat und läuft mit ungedeckeltem Dynamic Type — heute reflowen **3 von 10** Panels: `mixerPanel`, `soundPanel` (mit sieben Gittern) und seit #292 Slice 3 `moodPanel` (mit zwei). Die anderen sieben — `menuPanelHost`, `bioPanel`, `videoPanel`, `tempoToolsPanel`, `masterPanel`, `visualPanel`, `effectsPanel` — stapeln weiter starr. (Der Nenner war bis #359 Schritt 3 elf; `sessionPanel` ist mit diesem Schritt gelöscht, sein einziger Inhalt `placeRow` sitzt jetzt in „Save & Export". Zähl mit `grep -c "private var \w*Panel\w*: some View"`, nicht aus dem Kopf — genau diese Zeile trägt vier Absätze über ihre eigenen Zählfehler. ⚠️ Und der Befehl misst die NAMENSFORM, nicht die Sache: er zählt `menuPanelHost` mit, das der Wirt ist und kein Panel, und übersieht `utilityRow`, das eines der Dropdown-Panels IST und nicht reflowt. Die zehn stimmen als Zahl, die MENGE ist um je einen daneben — wer die Panels einzeln durchgeht, muss beide Abweichungen kennen.)

⛔ **Diese Zeile hat DREIMAL hintereinander dasselbe Panel falsch genannt, und jede Korrektur hat den Fehler geerbt.** Sie stand als „2 von 11" (gezählt: `mixerPanel` + `soundPanel`), wurde auf „3 von 11" mit `sessionPanel` korrigiert — und **dieses Panel hatte nie ein Gitter**. Der Träger sitzt in `weatherRow`; `sessionPanel` hat es bloß GERENDERT. Zwei bereits im Repo stehende Korrekturen sagen das ausdrücklich (`EchoelStudioView.swift`: „NOT `sessionPanel`, which merely renders `weatherRow` and contains no grid at all"; `Tests/CISmoke/SoundPanelReflowsTests.swift`: „⛔ The first version wrote `sessionPanel` here and in three other places — wrong"), und #359 Schritt 1 ist trotzdem ein drittes Mal hineingelaufen.

**Und deshalb ist der Befehl unten seit #359 Schritt 1 aktiv irreführend, nicht bloß ungenau:** seine Regel „jede Gitter-Zeile gehört zur letzten Panel-Deklaration darüber" ordnete das `weatherRow`-Gitter weiterhin `sessionPanel` zu, weil `weatherRow` im File zwischen `sessionPanel` und `masterPanel` stand — während es seit #359 Schritt 1 in `moodPanel` rendert, 1600 Zeilen weiter unten. (Beides ist inzwischen doppelt überholt: `weatherRow`s Gitter ist mit Schritt 2 entfallen, `sessionPanel` mit Schritt 3 gelöscht. Der Absatz bleibt, weil die LEHRE unabhängig von beidem gilt — und weil er zeigt, dass eine falsche Zuordnung zwei Codeänderungen überlebt hat, ohne dass ein Test rot wurde.) **Ein Gitter kann in einem `private var` liegen, das kein Panel ist**; wer nachführt, muss dem AUFRUFER folgen, nicht der Dateireihenfolge. Die dritte Zeile unten macht genau das —
```
grep -n "AdaptiveCardGrid {\|AdaptiveCardGrid(spacing" Sources/Echoelmusic/Studio/EchoelStudioView.swift
grep -n "private var \w*Panel\w*: some View\|private var weatherRow: some View" Sources/Echoelmusic/Studio/EchoelStudioView.swift
grep -n "^ *weatherRow$" Sources/Echoelmusic/Studio/EchoelStudioView.swift   # WER baut die Zeile ein
```
(die `private struct AdaptiveCardGrid`-Zeile selbst ist kein Treffer). **Die Lehre ist nicht „Zahl nachführen" — die steht in dieser Datei schon dreimal. Sie ist: eine Zuordnung, die aus der DATEIREIHENFOLGE abgeleitet wird, überlebt keine Verschiebung.**

⚠️ **Und die vierte Fassung derselben Zeile war „2 von 11 bedingungslos + `moodPanel` bedingt" — genauer als ihre Vorgänger und trotzdem nur Stunden haltbar.** #359 Schritt 2 hat die Bild-Regler aus `weatherRow` in `visualPanel` gezogen; ein Gitter, das nur noch EINE Karte anordnet, ordnet nichts an, also ist es mitgegangen. Damit ist `mixerPanel` der einzige nackte `AdaptiveCardGrid`-Aufrufer und die „bedingt"-Hälfte ersatzlos weg. **Das ist keine fünfte Falschmeldung, sondern ihr Gegenteil:** die Zeile war zum Zeitpunkt des Schreibens korrekt und ist durch eine echte Codeänderung ungültig geworden. Der Unterschied gehört hierher, weil dieser Absatz sonst wie eine Serie desselben Fehlers gelesen wird — und weil er zeigt, dass die Zahl auch dann nachzuführen ist, wenn niemand sie falsch aufgeschrieben hat.

---

## REPO STRUCTURE (v10)

```
Sources/Echoelmusic/
  Audio/               ← AudioEngine, AudioConfiguration, MIDIInput,
                          RetroCapture, AutoMixChain, SingleExport (KEEP)
                       ← MultiTrackRecorder (NEW W2)
  Sequencer/           ← PatternEngine (the TRANSPORT — tempo/play/stop/step clock),
                          BeatPlayer (its holder + audition; the kit inside it no longer
                          SOUNDS — attach(to:) hangs only previewVoice. ⛔ #167 ist am
                          2026-07-31 FERTIG: `DrumSynthVoice.swift`, `LaneDrumKitVoice.swift`
                          und `DrumNoteMap.swift` sind gelöscht, `PhysicalVoiceRef.drums`
                          und `LaneVoiceRack.kits`/`setDrumsInsert` ebenfalls. Was BLEIBT und
                          bleiben MUSS: die Enum-Cases `LaneVoiceKind.drums` und
                          `TrackInstrument.drums` — persistierte rawValues; ein unbekannter
                          wirft und verwirft die ganze Spur beim Decode),
                          SamplerVoice (audition + lane sampler)
  Video/               ← CameraCapture, CameraAnalyzer, RPPGConditioning, PulsePeriodEstimator
                          (the rPPG path), VideoRecorder, VisualRecorder, VideoMuxer +
                          VideoMuxAlignment — visual capture ONLY; video edit went with #121
                          Slice 3. `CameraSession`/`ClipTrimmer` do NOT exist (verified 2026-07-28)
  Stream/              ← BroadcastPublisher ONLY — a `#if canImport(HaishinKit)` compile-guard
                          scaffold. HaishinKit is NOT a dependency; there is no RTMPPublisher
  Studio/              ← EchoelStudioView (root), EchoelFXView,
                          EchoelTheme (as-built; the old StudioRoot/Beat/Record/Video/
                          ShareTab plan was never built. SampleBrowserView + BrowserView
                          gelöscht 2026-07-27 #167; ClipView mit #121 Slice 4)
  Core/                ← EchoelStore, SPSCQueue, ProfessionalLogger, MemoryPressureHandler,
                          NumericExtensions, ClipStore, ModulationEngine (KEEP). No `SessionStore`
                          — the real files are SessionContext/SessionNaming/SessionRecorder
                       ← (SoundscapeEngine/ClipEngine/WeatherProvider/CircadianClock/PlatformAvailability REMOVED 2026-06-19)
  Bio/                 ← BioEventGraph, HilbertSensorMapper, BioSignalDeconvolver (PROTECTED)
                       ← EchoelBioEngine + HealthKitBioPublisher + CameraRPPGBioPublisher (LIVE)
                       ← (BioSourceManager/OuraRingClient/EEGSensorBridge/MotionActivityProvider REMOVED)
  DSP/                 ← EchoelDDSP, EchoelCellular, EchoelVDSPKit (KEEP, reused as synth voices)
                       ← EchoelModalBank — ⛔ TEST-ONLY seit #167 (2026-07-31): sein einziger
                          Instanziierer war `DrumSynthVoice`; `git grep -l EchoelModalBank --
                          Sources` liefert heute NUR die eigene Datei. ~800 Zeilen DSP ohne
                          Produktionspfad. Nicht gelöscht (Founder sagte „erstmal"), aber auch
                          nicht als lebende Stimme zitieren.
  Sync/                ← OSCSender, ADMOSCSender, Art-Net/sACN (EchoelLux), CloudSync
  Tools/               ← PolySynthVoice, SubBassVoice, breath/vocal tools
  Views/               ← MetalBioView + OnboardingView ONLY (the old deprecated-view list is deleted)
Tests/EchoelmusicTests/ ← 313 test files (`git ls-files 'Tests/EchoelmusicTests/*.swift' | wc -l`,
                          2026-07-31 nach `DrumNoteMapTests.swift` (#167)). ⛔ Drei Zahlen
                          kursierten für DIESE eine Suite: 305 hier, 294 in den Schrittnamen von
                          `full-tests.yml`, 311 auf der Platte am 2026-07-28 — dann 314, heute 313.
                          Die Workflow-Beschriftung ist founder-gated und bleibt vorerst falsch (#208).
                          Und die Suite ist NICHT das blockierende Bundle — das baut aus
                          `Tests/CISmoke` (**155** Dateien, `git ls-files 'Tests/CISmoke/*.swift' | wc -l`,
                          2026-08-05 nach `TheGenerateLineExplainsItsNoteCountTests.swift` (#413 — der
                          erste Wächter in dieser Kette über einer BREADCRUMB statt über einem Verhalten
                          oder einer Anzeige, und deshalb der erste, dessen beide Hälften Quelltext-Scans
                          sind und der das im eigenen Kopf als Grenze aufschreibt statt es zu verschweigen.
                          Er prüft, dass die `generate[…]`-Zeile alle VIER Dichte-Treiber nennt (Genre ·
                          lebender Frame · `busy` · Stimmung+Tempo-Ausdünnung) und dass `busy` aus
                          `BioComposer.musicalState` mit demselben `input` neu gerechnet wird, das der
                          Komponist bekam — eine zweite Herleitung wäre eine Zahl, die vom Klang abweichen
                          und im Log trotzdem maßgeblich aussehen kann. Was er NICHT kann und was deshalb
                          im Dateikopf steht: dass die Zeile das Gerät erreicht (Geräte-Lesung) und dass
                          das gedruckte `busy` GLEICH dem ist, das `compose` benutzt hat — das gilt durch
                          Konstruktion, und Konstruktion ist genau das, was eine spätere Änderung bricht),
                          davor „154" nach `OneDefinitionOfTooBrightTests.swift` (#416 — der erste
                          Wächter in dieser Kette über einer DOPPELTEN Definition statt über einer
                          fehlenden: „die Fingerkuppe ist überstrahlt" stand zweimal in EINER Datei,
                          einmal als Zustandsmaschine (`isWashedOut`, 0,72) und einmal als Satz auf
                          dem Schirm (`acquisitionCue`, eigenes Paar, 0,85). Die Rot-Hälften blieben
                          gleich, die Helligkeits-Hälften nicht: über 0,72…0,85 belichtete die
                          Maschine neu, WEIL sie das Bild für geflutet hielt, während der Schirm
                          über Licht gar nichts sagte. **Lehre, und sie unterscheidet sich von der
                          üblichen Zahlen-Lehre dieses Absatzes: nicht eine Zahl war veraltet,
                          sondern eine zweite Kopie derselben Entscheidung ist bearbeitet worden und
                          die erste nicht.** ⛔ **UND DIE ERSTE FASSUNG DIESES EINTRAGS TRUG DREI
                          FALSCHE BEHAUPTUNGEN, die alle vier zugleich in Quelle, Test, Commit-Text
                          und hier standen — der Bio-Reviewer hat sie gefunden, ich habe jede selbst
                          nachgeprüft.** (1) „also drücken statt lockern": FALSCH für alle drei
                          ausgelieferten Sätze — „Hold still — keep your finger steady", „Press
                          gently and hold still", „Hold still — finding your pulse…"; der mittlere
                          verlangt ausdrücklich WENIGER Druck. Die Aufzählung ließ dabei `.holdStill`
                          weg, und genau der trug das Gewicht: die Datei selbst schreibt das Band dem
                          „finger lightening / re-grip" zu, der Analyzer dem „hard-press / re-grip"
                          — `.holdStill` war dort also vermutlich die RICHTIGE Meldung und wird
                          seit #416 verdrängt. (2) „EINE Definition": es sind DREI Helligkeitslinien
                          in dieser Datei (`strictLockBrightness` 0,28 · `maxLockBrightness` 0,6 ·
                          `isWashedOut` 0,72), und der Hinweis übernimmt die LOCKERSTE. Bei 0,65
                          verweigert die Maschine den Lock und der Schirm sagt weiter nichts — und in
                          diesem Restband liegt 0,62, der Wert, den dieselbe Datei ZWEIMAL als ihren
                          kanonischen Fehlschlag zitiert. (3) „unter BEIDEN Schwellen": 0,30 liegt
                          ÜBER `strictLockBrightness` (0,28) — die eine Linie, von der die Datei
                          sagt, sie entscheide, ob der Take überhaupt trägt. **Die eigentliche Lehre
                          ist damit eine andere als die oben: eine Formulierung, die sich gut liest
                          („drücken statt lockern"), wird nicht geprüft — sie wird kopiert.** Der
                          Wächter hat zwei Hälften, und auch da war ich zu großzügig: die
                          Verhaltens-Hälfte prüft `isWashedOut`, das #416 gar nicht angefasst hat,
                          ist also auf BEIDEN Seiten der Änderung grün; nur der Quelltext-Scan
                          unterscheidet vorher/nachher. Sie bleibt, weil sie die Linie ins
                          BLOCKIERENDE Bundle holt — aber sie heißt nicht mehr „die Regression".
                          Was NICHT repariert ist: die Akquise. Die gescheiterte Founder-Sitzung lag
                          bei bright ≈ 0,30, das bleibt #304/#410 und braucht eine
                          Geräte-Entscheidung, keine dritte blinde Schwelle),
                          davor „153" nach `TheDynamicsAreThePersonsTests.swift` (#403 Slice 3 — der
                          erste Wächter in dieser Kette, dessen eigene erste Fassung an DREI Stellen
                          gegen die API gelaufen wäre, die er prüft, und die dritte ist die lehrreiche:
                          die Argument-REIHENFOLGE von `BioSampleFrame.init` war vertauscht
                          (`coherence` vor `breathRate`) und der Quellen-Case hieß `.cameraRPPG` statt
                          `.cameraPPG` — beides fängt der Compiler. Die dritte nicht: jeder Frame trug
                          `timestamp: 0`, und `observing` verlangt `now > 0` PLUS 30 s Abstand, also
                          hätten die beiden Lern-Tests acht Beobachtungen gefüttert, null davon
                          angenommen und trotzdem grün auf `unknown` behauptet, die Rampe sei geprüft.
                          **Lehre: ein Test, der einen Lernpfad treibt, muss ZUERST behaupten, dass
                          gelernt wurde** — beide Fälle prüfen jetzt `hrvCount`, bevor sie den Tilt
                          ansehen. Dazu: die eine Hälfte, die ein Wächter hier nicht kann, steht im
                          Dateikopf — dass zwei Handschriften VERSCHIEDEN klingen ist prüfbar, dass ein
                          Take „nach dir klingt" ist eine Hörprobe. ⛔ **Und die Datei wurde Stunden
                          später für Slice 3b komplett neu geschrieben, weil der DSP-Reviewer den
                          Mechanismus widerlegt hat, den sie schützte:** Slice 3 kippte die
                          Sektions-VELOCITY, Velocity erreicht im Synth ausschließlich `velocityGain`
                          (reine Amplitude, kein Timbre-Pfad), und `AutoMixChain` ist per Default auf
                          −14 LUFS an und liest einen Meter VOR der eigenen `gainNode` — also
                          vorwärtsgekoppelt mit Fixpunkt `Ziel − Lᵢₙ`, entfernt einen Pegel-Offset
                          vollständig. Auf dem ausgelieferten Default-Genre leitet sich JEDE klingende
                          Note aus `padVelocity` ab, der Kipp war also zu 100 % Gleichtakt — genau das
                          Signal, das diese Stufe auslöschen soll. **Die Lehre ist allgemein und gehört
                          nicht zu diesem Parameter: bevor man aus einer Größe eine Handschrift macht,
                          verfolgt man sie bis zum Lautsprecher.** Pegel gehört dem Master (mit eigenem
                          Nutzer-Regler), BALANCE gehört dem Composer und wird nirgends normalisiert;
                          3b kippt deshalb den Bass-Lift über dem Pad. ⛔ **Und die Begründung DIESER
                          Umkehrung war selbst zur Hälfte falsch — zwei Reviewer fanden unabhängig
                          dieselben zwei Stellen, und sie standen in vier Dateien plus hier.** (1)
                          „Velocity erreicht genau EINE Sache" stimmt nicht: `spawnVoice` schreibt auch
                          `noteVelocity`, und das speist `brightBoost`, also die Filter-Cutoff, bei
                          `filterEnvAmount` = 1 ohne Setter in `Sources/` — auf JEDER Note jedes
                          Patches. (2) „entfernt einen Pegel-Offset VOLLSTÄNDIG" stimmt auch nicht:
                          `steadyGainDB` hat `deadZoneDB = 0.4` und HÄLT darin — und die Rechnung, die
                          ich nie gemacht habe, ergibt für Slice 3 einen Versatz von +0,32/−0,42 dB bei
                          Kohärenz 0,5, also eine ganze Seite INNERHALB der Totzone. Das Urteil ist
                          weder „gelöscht" noch „überlebt", sondern **unbestimmt** — was für eine
                          Handschrift schlechter ist als beides. Die Entscheidung für Balance bleibt
                          (ein VERHÄLTNIS rührt kein Gain-Servo an), die Begründung ist ersetzt.
                          **Lehre, zusätzlich zur obigen: „eine Regelstufe löscht das" ist erst ein
                          Argument, wenn die GRÖSSE des Effekts neben der Totzone dieser Stufe steht.**
                          Dazu drei kleinere Korrekturen: der Fühl-Sub (`SubBassVoice`) verwirft
                          Velocity, es bewegt sich also die Bass-LINIE und nicht „das Tieftonband"; die
                          `v^0.5`-Kurve gilt nur mit armierter Bio-Modulation auf einem Ambient-Patch;
                          und auf dem ausgelieferten Genre trägt ein Take EINE Bassnote, deren
                          Humanisierung (±0,086 mit `hrvHumanize`) größer ist als der systematische
                          Kipp (±0,07) — die Handschrift ist ein Bias ÜBER Takes, keine Garantie pro
                          Take),
                          davor „152" nach `TimingVerdictReachesTheScreenTests.swift` (#408 — der erste
                          Wächter in dieser Kette über einer ANZEIGE statt über einem Verhalten, und
                          deshalb der erste, dessen Fehlermodi allesamt EHRLICHKEIT betreffen: ein Fenster
                          ohne gemessene Intervalle darf nicht wie ein sauberes lesen (`isClean` ist
                          `glitchCount == 0` und damit auch für den toten Tap wahr), und ein sauberes
                          Fenster darf nicht wie eine Entwarnung lesen — dieses Messgerät sieht die ganze
                          zweite Klasse von Klick nicht. ⛔ Und seine eigene erste Fassung war rot auf
                          korrektem Code: die Reihenfolge-Prüfung ankerte auf
                          `shouldReportTimingWindow(firstWindow:`, was zuerst die DEKLARATION trifft und
                          nicht den Aufruf, also 1228 < 1169. Ein Quelltext-Scan muss auf ein Token
                          ankern, das NUR an der gemeinten Stelle steht — die Eindeutigkeit zu prüfen
                          gehört zum Schreiben des Scans, nicht zur Nachlese. ⛔ Und die Nachlese fand
                          BEIDE Reviewer an derselben Stelle: die Zeile behauptete das Wanduhr-Fenster
                          als Beweis-Spanne. `measuredIntervals` diente nur als `> 0`-Tor,
                          `discontinuityCount` erreichte die Zeile gar nicht — ein flatternder
                          Bluetooth-Ausgang mit 50 Intervallen, davon 48 Abrisse, las sich als
                          „Nothing late in the last 60 s", also ein sauberes Urteil auf einer
                          Viertelsekunde Beleg. Das Feld-Doc formuliert genau diese Regel und
                          `diagnosticLine` hält sie ein; nur die neue Zeile nicht. **Lehre: wer eine
                          zweite Ausgabe für dieselbe Messung schreibt, muss die Vorbehalte der ersten
                          mitnehmen — die stehen nicht zur Kürzung frei, sie sind die Messung.**
                          Dazu: die Begründung für das Leaf-View nannte den ROOT-Body als Beobachter,
                          während `EchoelPanel` mit seinem `@escaping @ViewBuilder` die echte Grenze
                          ist — dieselbe Datei sagt das 1400 Zeilen weiter oben, und ein Wächter, der
                          nur den Mount-String suchte, wäre über einem auskommentierten Mount grün
                          geblieben),
                          davor „151" nach `TheMasterGainMovesInSmallStepsTests.swift` (#404 Slice 2 — der
                          erste Wächter in dieser Kette, dessen Schwelle beim Schreiben zuerst FALSCH gewählt
                          war und deren Korrektur die eigentliche Lehre ist: die erste Fassung setzte ein
                          lineares 2-%-Budget, der schlimmste legale Schnitt-Schritt liegt bei 2,68 %, und der
                          naheliegende Griff wäre gewesen, das Budget auf 3 % zu schieben — also die Schwelle
                          so zu wählen, dass der eigene Code sie besteht. Die Schwelle steht jetzt in dB (der
                          Einheit der Sache), wurde VOR der Messung gewählt und wird zweifach geprüft: Decke
                          für den schlimmsten legalen Fall, strengere Marke für den gewöhnlichen. Dazu ein
                          Test, der die VOR-Zahl festnagelt — ohne ihn könnte eine spätere Sitzung `subSteps`
                          auf 1 zurückdrehen und am bestandenen Deckel-Test ablesen, es sei nichts verloren.
                          ⛔ Die Nachlese fand die Datei trotzdem an vier Stellen falsch, und die lehrreichste
                          ist die Prozentzahl selbst: `abs(1 − 10^(dB/20))` ist IMMER der Anhebungs-Betrag,
                          egal welches Vorzeichen gemeint war — an einen SCHNITT geheftet überzeichnete sie
                          den Defekt um 13 bzw. 28 % relativ. Dazu: der größte Einzelschritt der Datei kommt
                          gar nicht aus dem Koeffizienten, sondern aus dem „No target"-Sprung (0,4 dB), den der
                          erste Wächter mit „alles andere ist kleiner" ausdrücklich ausschloss; „bit-for-bit"
                          galt nicht in einem 0,078 dB breiten Band um die Totzone; und der erste Commit
                          verurteilte `min(max(…))` fünfzehn Zeilen über einem überlebenden `min(max(…))` auf
                          genau der Zeile, die den Mixer schreibt),
                          davor „150" nach `ThePaceIsTiltedInsideTheGenreTests.swift` (#403 Slice 2 — der
                          erste Wächter in dieser Kette, dessen wichtigste Hälfte eine NICHT-Wirkung sichert:
                          dass eine Zahl das Fenster ihres Genres unter KEINEM Wert verlässt. Deshalb gewischt
                          und nicht stichprobenartig — der Fehler, gegen den er steht, ist ein Refactor auf
                          „Offset dann Clamp", der jeden einzelnen aufgeschriebenen Fall besteht und danach
                          eine ganze Population von Performern auf eine Genre-Grenze sättigt. Die zweite
                          Auflage steht im Wortlaut seines Namens: `testTheLockedTempoIsNotTilted` ist ein
                          POSITIVER Scan auf die unveränderte Zuweisung, weil ein negativer Scan Code nicht
                          von Prosa unterscheiden kann — dieselbe #367-Falle, die #404 einen Tag zuvor auf
                          der Quellseite lösen musste),
                          davor „149" nach `SignatureIsThePersonNotTheMomentTests.swift` (#403 Slice 1 — der
                          erste Wächter in dieser Kette, der einen SIMULATOR ausschließt statt einen Wert zu
                          prüfen: `BioSimulator` stempelt `.fallback` und liefert vollkommen plausible Zahlen,
                          also hätte ein Demo-Lauf die Handschrift der PERSON geschrieben. Zwei Fälle dafür,
                          und der zweite ist der, den man vergisst — die Ablehnung darf das 30-s-Fenster nicht
                          verbrauchen, sonst überspringt eine Demo-dann-Spiel-Sitzung die erste echte Messung),
                          davor „148" nach `ReusedTailIsTheQuietestOneTests.swift` (#404 — der erste Wächter in
                          dieser Kette, dessen NEGATIVE Hälfte beim Schreiben fast am eigenen Doc-Kommentar
                          gescheitert wäre: ein Quelltext-Scan auf die ABWESENHEIT einer Zeile kann Code nicht
                          von Prosa unterscheiden, also hätte die Erwähnung der alten Regel in der Begründung
                          der neuen das blockierende Gate rot gefärbt. Das ist die #367-Falle andersherum —
                          nicht ein Wächter, der nicht scheitern KANN, sondern einer, der an einem Satz
                          scheitert. Gelöst auf der Quellseite: die Doc nennt die alte Regel in Worten und
                          zitiert ihren Aufruf nirgends; die Auflage steht in beiden Dateien),
                          davor „147" nach `TakeDistanceTests.swift` (#403 Slice 0 — der erste Wächter in dieser
                          Kette, der ein MESSGERÄT prüft statt eines Verhaltens, und deshalb zwei Hälften in
                          einer Datei hat: exakt nachrechenbare Eigenschaften des reinen Maßes, DANN dasselbe
                          Maß an echten `BioComposer`-Takes. Die zweite Hälfte ist der Punkt — ein reiner Kern
                          ohne Aufrufer ist derselbe Defekt mit mehr Schritten. Seine Schwellen sind BÖDEN
                          gegen Konvergenz und ausdrücklich keine Qualitätsurteile: „klingt für ein Ohr
                          verschieden genug" kann diese Datei nicht beweisen und behauptet es auch nicht),
                          davor „146" nach `ResetSoundClearsWhatTheLaunchLineReportsTests.swift` (#400 — der erste Wächter
                          in dieser Kette, der ein PAAR zusammenhält statt einer Sache: er liest die
                          `launch/musical:`-Zeile aus #401 und verlangt, dass jeder Wert, den der Reset
                          löscht, dort auch GEMELDET wird. Bewusst auf DIESE eine Zeile eingegrenzt und
                          nicht auf die Datei — die `generate[…]`-Breadcrumb trägt `key=`, `tuning=`
                          und `a4=` ebenfalls, ein dateiweiter Scan wäre für genau die drei stumm
                          geblieben),
                          davor „145" nach `FieldSoundSurvivesRelaunchTests.swift` (#402 — die erste Datei
                          in dieser Kette, deren Verhaltens-Hälfte einen reinen Kern prüft, den DERSELBE
                          Commit erst geschaffen hat, um ihn prüfbar zu machen: der Defekt war eine
                          Reihenfolge zwischen zwei Anwendern desselben Patches, und Reihenfolge ist ohne
                          Simulator nicht testbar — die ENTSCHEIDUNG „welcher Patch wacht auf" schon, sobald
                          sie in einer puren Funktion sitzt. Sechs Verhaltensfälle plus EIN Quelltext-Scan
                          darauf, dass der Start-Task überhaupt fragt; ohne den wäre der Kern korrekt und
                          unbenutzt, was genau derselbe Defekt mit mehr Schritten ist),
                          davor „144" nach `LaunchLogsWhatItWokeUpWithTests.swift` (#401 — der Wächter über einer
                          DIAGNOSE statt über einem Fix, und deshalb ein anderer Typ als jeder Eintrag davor:
                          er verlangt, dass die Start-Breadcrumb alle acht persistierten musikalischen Werte
                          NENNT, und verbietet als einziger Test in dieser Kette ausdrücklich etwas — die UUID
                          des Nutzer-Patches im Log. Drei Quelltext-Scans plus EIN echter Verhaltenstest auf den
                          Frisch-Installations-Defaults, weil „Neuinstallation heilt" nur dann ein Beleg für
                          persistierten Zustand ist, wenn eine frische Installation für die betroffenen Schlüssel
                          wirklich neutral ist),
                          davor „143" nach `AReclaimedFloorIsNotAddedToTheWaitTests.swift` (#398 — die erste Datei
                          in dieser Kette, deren behaviouraler Teil einen PUREN Kern treibt statt DSP-Puffer:
                          sechs Fälle Zeitarithmetik, davon drei nachweislich rot auf dem alten Code, plus EIN
                          Quelltext-Scan für die Verdrahtung. Beides bewusst in einer Datei — ein korrekter Kern
                          ohne Aufrufer ist genau der Fehler, den dieses Repo schon bezahlt hat),
                          davor „142" nach `BypassingTheChainEmptiesItOnTheWayBackTests.swift` (#397 — der Zwilling
                          von #389 eine Ebene höher: derselbe Drain, ausgelöst vom sichtbaren
                          FX-Schalter statt vom Einschlafen; halb Verhaltenstest, halb
                          Reihenfolge-Scan, weil die Sicherheit an der REIHENFOLGE hängt),
                          davor „141" nach `SleepingChainDoesNotHoardAudioTests.swift` (#389 — die
                          erste Datei in dieser Kette, die KEIN Quelltext-Scan ist, sondern echte
                          Float-Puffer durch die echten Stufen treibt; sie kann deshalb am
                          SYMPTOM scheitern statt an einer fehlenden Codezeile),
                          davor „140" nach `DetunedInstrumentSaysSoTests.swift` (#325),
                          davor „139" nach `ScrollSweepCannotAnchorAScrubTests.swift` (#392),
                          davor „138" nach `ConcertPitchDoesNotRideTheScrollTests.swift` (#391),
                          davor „137" nach `RecordingCanBeStoppedWithoutThePictureTests.swift` (#387),
                          davor „136" nach `ReSeedIntervalIsMeasuredBeforeItIsResetTests.swift` (#390),
                          davor „135" nach `ActiveTargetsIsAPerEditFactTests.swift` (#388),
                          davor „134" nach `BioFXReachesEveryChainTests.swift` (#386),
                          davor „133" nach `RecordingKeepsItsPictureTests.swift` (#319),
                          davor „132" nach `FXPanelReachesEveryChainTests.swift` (#318),
                          davor „131" nach `InfoSheetTextScalesTests.swift` (#353f),
                          davor „130" nach `ParameterRowStacksAtAccessibilitySizesTests.swift` (#353e),
                          davor „129" nach `BioNumbersGrowWithTheTextTests.swift` (#353c),
                          davor „128" nach `WavefrontSpreadingTests.swift` (#385),
                          davor „127" nach `HeaderSpectrumIsALeafTests.swift` (#384),
                          davor „126" nach `DiagnosticsTextScalesTests.swift` (#353d, zweite Scheibe),
                          davor „125" nach `ConfidenceCannotOutliveTheMeasurementTests.swift` (#383),
                          davor „124" nach `DeletingAClipIsUndoableTests.swift` (#357 d),
                          davor „123" nach `DeletingAPresetIsUndoableTests.swift` (#357 a — der
                          Eintrag hieß zuerst „(Loesch-Undo)"; er stand EINE Zeile über dem
                          gleichen Fehler und wurde bei dessen Korrektur übersehen, was der
                          Absatz unter der Plattform-Tabelle bereits als eigene Lehre trägt:
                          such nach der ZWEITEN Stelle),
                          davor „122" nach `RandomizeIsUndoableTests.swift` (#357 c — der Eintrag
                          hieß zuerst „(Randomize-Undo)", als einziger in dieser Kette ohne
                          Slice-Nummer; eine Kette, deren Einträge verschieden benannt sind, lässt
                          sich nicht mehr gegen die Commit-Historie prüfen),
                          davor „121" nach `OpeningAProjectRescuesTheLiveTakeTests.swift` (#357 b),
                          davor „120" nach `LockCueDoesNotShoveTheControlsTests.swift` (#382),
                          davor „119" nach `CoachingTextScalesTests.swift` (#353d),
                          davor „118" nach `ChipLabelGrowsWithTheTextTests.swift` (#353b),
                          davor „117" nach `LockedTempoIsTheNumberYouSetTests.swift` (#380),
                          davor „116" nach `TempoLockAlwaysAsksForARecomposeTests.swift` (#356 b),
                          davor „115" nach `CopyNamesTheLiveControlTests.swift` (#355 b/c),
                          davor „114" nach `MoodPanelReflowsTests.swift` (#292 Slice 3). ⛔ **Und
                          dieser Stand „114" wurde NACHGETRAGEN, nicht nachgeführt** — der
                          #292-Slice-3-Commit legte die Datei an und ließ diese Zeile auf „113"
                          stehen, genau der Fehler, vor dem der Absatz zwei Sätze weiter unten
                          warnt („diese Zahl ist die am schnellsten veraltende in dieser Datei").
                          Er ist hier nicht ausgelassen, weil ein stiller Sprung 113→115 die
                          nächste Session glauben ließe, ein Zyklus habe zwei Dateien angelegt.
                          Davor „113" nach `ControlBoundaryIsInteractiveTests.swift` (#367),
                          davor „112" nach `WeatherIsAMoodRubricTests.swift` (#359 Schritt 1),
                          davor „111" nach `PresetSurvivesACancelledDragTests.swift` (#379),
                          davor „110" nach `SlowScrubStillMovesTests.swift` (#376),
                          davor „109" nach `ScrubNotifiesOnlyOnRealChangeTests.swift` (#375),
                          davor „108" nach `RefractoryIsAskedInTimeTests.swift` (#374). ⛔ Der
                          Kopf dieser Kette hieß Stunden zuvor `RefractoryFollowsTheMeasuredRateTests.swift`
                          (#373) — #374 hat diese Datei GELÖSCHT und die neue angelegt, also EINE
                          Löschung plus EINE Anlage bei gleichbleibender Zahl. Die Zahl allein hätte
                          den Tausch nicht gezeigt: **eine unveränderte Zahl ist kein Beleg dafür,
                          dass sich nichts geändert hat**, und der Name im Kopf ist hier der einzige
                          Träger dieser Information. Umbenannt, weil der alte NAME eine Vorgehensweise
                          beschrieb (Umrechnung in eine gemessene Sample-Rate), die der Code nicht
                          mehr nimmt — genau die Stale-Name-Falle, die dieser Absatz an Zahlen schon
                          zweimal bezahlt hat, davor „107" nach `WebsitePagesAreFindableAndHonestTests.swift` (#371 — der
                          erste Wächter in diesem Bundle, der nicht `Sources/` prüft, sondern die
                          veröffentlichte Seite unter `docs/`; die Begründung steht im Dateikopf),
                          davor „106" nach `FlashSlewIsPerSecondTests.swift` (#370),
                          „105" nach `TempoReadsAsAMeasurementTests.swift` (#368),
                          „104" nach `TypeWeightsThatExistTests.swift` (#361),
                          „103" nach `PrimaryFillIsMonochromeTests.swift` (#364),
                          „102" nach `AnalysisViewsSpeakTheirNumbersTests.swift` (#352),
                          „101" nach `FirstInstructionIsTrueTests.swift` (#351),
                          „100" nach `OneRedForRecordingTests.swift` (#363),
                          „99" nach `SectionHeadingIsOneTreatmentTests.swift` (#362),
                          „98" nach `ChromeBudgetFitsTests.swift` (#365),
                          „97" nach `TapTargetFloorTests.swift` (#350),
                          „96" nach `WeatherToneIsAudibleTests.swift` (#349),
                          „95" nach `PoincareViewDoorTests.swift` (#347 Slice 3b),
                          „94" nach `PoincareMetricsTests.swift` (#347 Slice 3a),
                          „93" nach `SpectrumReadoutTests.swift` (#347 Slice 2),
                          „92" nach `BioApplyRateIsTheDedupedRateTests.swift` (#341-Nachlese —
                          die Datei, die der #341-Commit als existierend ZITIERTE, bevor es sie gab),
                          „91" nach `ScopeTriggerStandsStillTests.swift` (#347),
                          „90" nach `MixFaderRespondsBeforeThePersistTests.swift` (#342),
                          „89" nach `SubBassFollowsTheToneSystemTests.swift` (#312),
                          „88" nach `BioSmoothingSharesOnePoleTests.swift` (#332),
                          „87" nach `DisabledReverbIsNotClaimedLiveTests.swift` (#335),
                          „86" nach `AutoGainClampMatchesTheWebsiteTests.swift` (#333),
                          „85" nach `ControllerEventDrainIsPushedTests.swift` (#317),
                          „84" nach `LoudnessReadoutMeasurementPointTests.swift` (#316),
                          „83" nach `LeadMixDoorAndNormalisationTests.swift` (#255),
                          „82" nach `BioFollowsTheBodyTests.swift` (#331),
                          „81" nach `MixBoardOwnsEveryLevelTests.swift` (#330),
                          „80" nach `GenreSwingReachesTheClockTests.swift` (#327),
                          „79" nach `NoDoorlessStudioViewsTests.swift` (#322),
                          „78" nach `SoundPromptHasADoorTests.swift` (#320),
                          „77" nach `FieldSurvivesAHiddenPictureTests.swift` (#311),
                          „76" nach `SoundPanelPresetBarTests.swift` (#132 Slice 6),
                          „75" nach `RecordRouteOwnershipTests.swift` (#299),
                          „74" nach `GainLatchRecoveryTests.swift` (#295/#296/#297),
                          „73" nach `MIDIClockTests.swift` (#300),
                          „72" nach `AudioInputDoorTests.swift` (#298),
                          „71" nach `FilterCutoffClampTests.swift` (#294),
                          „70" nach `PatchVibratoAnchorTests.swift` (#279),
                          „69" nach `SoundPanelReflowsTests.swift` (#292 Slice 2),
                          „68" nach `DeviceFamilyIsPhoneOnlyTests.swift` (#292 Slice 1),
                          „67" nach `ChipStripScrollsToSelectionTests.swift` (#291),
                          „66" nach `LibraryAutosaveSectionTests.swift` (#285), „65" nach
                          `ContentPipelineClaimsTests.swift` (#287) — das ist der Stand, dessen
                          Datei das blockierende Gate ROT gemacht hat, weil ihre Fehlermeldungen
                          als `+`-Ketten zu teuer zu type-checken waren (`3379bb3`); die Zahl
                          stimmte, die Datei kompilierte nicht. **Diese Zeile zählt Dateien, nicht
                          grüne Gates** — beides nachführen. Davor „64" nach
                          `SynthPatchValuesResolveTests.swift` (#286), „63" nach
                          `UnisonRowDefaultsTests.swift` (#281), „62" nach
                          `AutosaveSlotTests.swift` (#273), „61" nach
                          `SaveDoorNamingTests.swift` (#272) und „60" nach
                          `ResourceGovernorWarmupTests.swift` (#271) — der Commit,
                          der sie anlegte (`fca5ae4`), führte DIESE Zeile nicht nach und der
                          #271-Reviewer fand sie im selben Durchgang falsch, drei Absätze unter
                          der Regel, die das verlangt; am selben Tag früher „59" (`VisualEnergyTests.swift`, #228), „58" (Dateinamen-ASCII-Wächter) und „57", am 2026-07-30 „56", „55", „54", „53", „52", „51", „50", „49", „48", „47", „46", „45", „41", „39", am
                          2026-07-29 nachmittags „30", vormittags „21", und davor monatelang
                          „1 Datei" — das ließ das EINZIGE
                          Bundle, das einen Merge rot färben kann, kleiner aussehen als es ist. Das
                          Bundle WÄCHST gerade schnell, weil jeder Ralph-Slice seinen Wächter hierher
                          legt statt in die non-blocking Suite: **diese Zahl ist die am schnellsten
                          veraltende in dieser Datei — führ sie mit dem Befehl nach, zitier sie nie
                          ungeprüft**. HUNDERTVIERZEHN FRÜHERE Stände in acht Tagen (⛔ hier stand „sechs“, und die Zahl war nur mitgeschoben: der frühere Text sagte „fünf Tagen“ für 07-29…08-01, also VIER — der Off-by-one wurde beim Erhöhen geerbt statt geprüft. 07-29 bis 08-02 sind fünf; mit dem 08-05-Stand sind es acht, und dieser Absatz hat die Spanne diesmal MIT der Zahl nachgeführt statt sie stehen zu lassen) — der aktuelle Wert 155 ist hier NICHT mitgezählt, anders als im Sources-Absatz oben (154·153·152·151·150·149·148·147·146·145·144·143·142·141·140·139·138·137·136·135·134·133·132·131·130·129·128·127·126·125·124·123·122·121·120·119·118·117·116·115·114·113·112·111·110·109·108·107·106·105·104·103·102·101·100·99·98·97·96·95·94·93·92·91·90·89·88·87·86·85·84·83·82·81·80·79·78·77·76·75·74·73·72·71·70·69·68·67·66·65·64·63·62·61·60·59·58·57·56·55·54·53·52·51·50·49·48·47·46·45·41·39·30·21 — bei der
                          Korrektur auf „47" schob „46" in die Liste und das Zahlwort blieb auf
                          SECHS stehen, in genau dem Absatz, dessen einziger Zweck es ist, dass
                          eine Zahl neben ihrem Befehl wahr bleibt; das Zahlwort MITZÄHLEN ist
                          Teil des Nachführens) — „45" stand am 2026-07-30 auf der
                          Platte, war aber nie in DIESER Zeile, und die erste Fassung dieser
                          Korrektur zählte es mit: wer sie liest, ohne den Befehl
                          daneben laufen zu lassen, liest eine Zahl von gestern. ZWEI aufeinander
                          folgende #254-Reviewer fanden sie je einen Commit nach ihrer letzten
                          Korrektur wieder falsch — genau deshalb steht hier der Befehl und nicht
                          nur die Zahl, und deshalb ist das Nachführen dieser Zeile Teil jedes
                          Commits, der eine Datei in dieses Verzeichnis legt).
                          Siehe KEY TESTS.
docs/                  ← Website (GitHub Pages)
.github/workflows/     ← CI/CD (testflight.yml is primary)
```

Existing top-level directories under `Sources/Echoelmusic/`: `Audio/ Bio/ Core/ DSP/ EchoelAI/ Resources/ Sequencer/ Stream/ Studio/ Sync/ Tools/ Video/ Views/`. No NEW top-level directories without approval.

---

## BIO-SIGNAL DSP — DO NOT SIMPLIFY

| Algorithm | Basis | Function |
|---|---|---|
| BioEventGraph | DELLY (Rausch 2012) | Graph-based event detection, k-means clustering |
| HilbertSensorMapper | Hilbert curves | 1D→2D locality-preserving sensor mapping |
| BioSignalDeconvolver | Tracy (Rausch 2017) | Separates cardiac/respiratory/artifact via adaptive biquad IIR |

### DDSP Bio-Mappings

Coherence → Harmonicity | HRV → Brightness | Heart rate → Vibrato | Breath phase → Envelope | Breath depth → Noise | LF/HF → Spectral tilt | Coherence trend → Shape morphing

---

## PERFORMANCE — Hard Limits

| Metric | Target | FAIL |
|---|---|---|
| Audio Latency | <10ms | >15ms |
| CPU | <30% | >50% |
| Memory | <200MB | >300MB |
| Visual FPS | 120fps | <60fps |
| Bio Loop | 120Hz | <60Hz |

**Audio thread: NO locks, NO malloc, NO ObjC messaging, NO file I/O, NO GCD.**

---

## PLATFORM CONSTRAINTS

- Apple Watch HR: ~4-5 sec latency — NO beat-sync!
- RMSSD: Self-calculate (Apple only gives SDNN)
- Bluetooth Audio: 150-250ms latency
- Flash animations: Max 3 Hz (epilepsy W3C WCAG)

---

## SAFETY WARNINGS (must be in app)

- Brainwave Entrainment: NOT while operating vehicles
- NOT under influence of alcohol/drugs
- Therapeutic use: coordinate medications with provider
- Max 3 Hz visual flash rate
- Data for self-observation, NOT medical diagnosis

---

## RALPH WIGGUM LAMBDA PROTOCOL

```
1. git status && git log --oneline -10
2. swift build 2>&1 | tail -20
3. Identify ONE broken/unclear thing
4. Fix it (minimal change, max 3 files)
5. swift test --filter [relevant]
6. Commit: fix: [description]
7. Deploy to TestFlight
8. Evaluate on device
9. GOTO 1
```

ONE issue per cycle. No batching. Build fails = ONLY priority.
No features during fix cycles. Convergence only.

---

## "CLEAR SOFTWARE" CHECKLIST

1. Every screen does something (no placeholders)
2. Navigation works (tabs respond, back goes back)
3. Bio-feedback visible (HR, HRV, coherence front and center)
4. Audio works (tap synth = hear sound)
5. Buttons respond, states change, loading indicators work
6. No crashes (force unwraps banned, optionals handled)
7. Permission denials handled gracefully
8. Background/foreground transitions stable

---

## SESSION START

```bash
git status
git log --oneline -20
swift build 2>&1 | tail -30
cat .ai/*.md 2>/dev/null
swift test 2>&1 | tail -20
```

Priority: Build errors → Test failures → Crash code → Task → Cleanup

---

## CODE STYLE

- **SwiftUI + MVVM** | `@Observable` (iOS 17+) | async/await + `@MainActor`
- **Swift 6** strict concurrency | SwiftLint enforced
- `os_log` ONLY (never `print`) | Guard-let over if-let
- Conventional commits | One change per commit
- Swift-first; **no PAID frameworks (no JUCE), no CMake**. The original "no C++"
  rule was really "no JUCE licence fees" — C++ is permitted ONLY for a **free,
  well-contained, Council-approved** library kept out of the Swift audio core
  (e.g. Ableton Link / LinkKit, which is free). Default stays Swift; deps stay
  minimal (ZERO external deps shipped today; HaishinKit = the planned RTMP dep, not linked).
- `///` for public API docs

---

## CRITICAL BUILD ERROR PATTERNS

### Swift Compiler Errors

| Pattern | Fix |
|---------|-----|
| UIKit refs on non-iOS | `#if canImport(UIKit)` |
| @MainActor in Sendable closure | `Task { @MainActor in }` |
| deinit calls @MainActor method | Nonisolated cleanup directly |
| `public let foo: InternalType` | Hard error — match access levels |
| `Color.magenta` | Doesn't exist. Use `Color(red:1,green:0,blue:1)` |
| WeatherKit | `@available(iOS 16.0, *)` AND `#if canImport(WeatherKit)` |
| vDSP overlapping accesses | Copy inputs to temp vars before `vDSP_DFT_Execute` |
| `self` before `super.init()` | Move setup AFTER `super.init()` |
| `inout` + escaping closure | Copy to local var first |
| `@MainActor` property read from a `nonisolated` audio-render block ("main actor-isolated property X can not be referenced from a nonisolated context") | Keep the public `@MainActor` prop for the UI, add an `@ObservationIgnored nonisolated(unsafe)` mirror written in its `didSet`; the render reads the mirror (see SubBassVoice.audioSubGain / PolySynthVoice params) |
| `@Observable` class: a manual stored prop named `_foo` ("invalid redeclaration of '_foo'" / "ambiguous use of '_foo'") | The macro generates `_foo` as `foo`'s backing — never name your own field `_<name>`; use a non-underscore name (e.g. `audioFoo`) |
| `static let` on a `@MainActor` class read from `Task.detached` — "main actor-isolated static property X cannot be accessed from outside of the actor" | Xcode's toolchain isolates it even when immutable (SwiftPM CI may accept the same code — toolchains disagree on SE-0434 inference). Mark it `nonisolated static let` explicitly |

### Logger Usage (Global `log` is EchoelLogger instance)

```swift
// CORRECT:
log.log(.info, category: .audio, "message")

// WRONG - tries to call logger as function:
log(.info, ...)

// WRONG - instance method, not static:
ProfessionalLogger.log()

// Math log() is shadowed — use:
Foundation.log(value)
```

### API Gotchas

> **DELETED 2026-07-25 — every type this section named is GONE.** It listed
> `SpatialAudioEngine`, `UnifiedHealthKitEngine` and `NormalizedCoherence` with
> their "correct API". A grep of `Sources/` and `Tests/` returns **zero** matches
> for all three (`NormalizedCoherence` survives only as the name of a test METHOD,
> `CoreSystemTests.swift:61` — not a type). A session reading this would write code
> against APIs that do not exist and only find out at the CI gate.
> The same applied to the old **Type Conflict Resolution** section: `ProSessionEngine`,
> `ProStreamEngine`, `ProCueSystem`, `ProColorGrading`, `ChannelStrip`,
> `ArticulationType`, `SubsystemID` — all zero files. And to
> `CXProviderConfiguration` (CallKit is not used here).
> Do not restore any of it from an older revision; it documents a codebase that no
> longer exists.

Language-level notes that ARE still true and worth keeping:

- `Swift.max`/`Swift.min` must be qualified when a struct in scope has a static
  `.max` property.
- **Argument order in `max`/`min` decides NaN behaviour.** `max(x, y)` is
  `y >= x ? y : x`, so `max(0, NaN)` returns `0` (NaN-safe) while `max(NaN, 0)`
  returns `NaN`. `min(max(v, lo), hi)` therefore passes NaN straight through — use
  the NaN-safe `clamped(to:)` (`Core/FloatingPointClamp.swift`) for anything that
  reaches the audio thread. This has caused shipped permanent-silence bugs.
- `@escaping` required for `TaskGroup.addTask` closures.
- Result builder: `buildBlock(_ components: [T]...)` when using `buildExpression`.

---

## KEY TESTS (313 files under `Tests/EchoelmusicTests/` — `git ls-files` re-run 2026-07-31 nach #167)

Run `swift test` (or rely on the CI gates) before ANY commit. Highest-value areas:
DSP (`EchoelDDSPTests` · `DSPTests` · `VDSPTests`) · protected triad
(`BioEventGraphTests` · `BioSignalDeconvolverTests`) · sequencer/tempo
(`PatternEngineTransportRelayTests` · `TempoStabilityTests` · `SequencerTests`) ·
MIDI export (`MIDIFileImporterTests`) · rPPG trust (`CameraRPPGTrustTests`) ·
FX (`EchoelFXChainTests` · `GenreFXTests`). (The old "15 files, 1,060+ methods"
list named 11 files that never existed — do not reintroduce it.)

---

## CI/CD

### Active Workflows (.github/workflows/)

| Workflow | Purpose |
|----------|---------|
| `testflight.yml` | **PRIMARY** — TestFlight builds (ID: 225043686) |
| `ci.yml` | Main CI (SwiftPM build, test, lint) |
| `xcode-compile-check.yml` | XcodeGen + `xcodebuild` compile gate (catches Xcode/AUv3-only errors) |
| `quick-test.yml` | Fast test suite |
| `pr-check.yml` | PR validation |

**⚠️ WELCHES GATE WAS BEWEIST — die Unterscheidung, die jede Session sonst neu falsch rät** (per Workflow-Lesung 2026-07-31; sie hat in dieser Woche zweimal einen Commit rot gemacht, den ein grüner Compile-Check schon abgesegnet hatte):

- **`Xcode Compile Check`** ist `xcodebuild build` auf Scheme `Echoelmusic` (`xcode-compile-check.yml:57`) — **NICHT** `build-for-testing`. Das kompiliert **nur `Sources/`**, und der Beleg steht im Schema selbst: `project.yml:379-382` gibt Scheme `Echoelmusic` unter `build.targets` **ausschließlich** `Echoelmusic`; `EchoelmusicTests` (Sources = `Tests/CISmoke`, `project.yml:304-310`) steht dort nur unter `test.targets`, und `xcodebuild build` baut die `build`-Targets. Ein grünes Compile-Check-Häkchen beweist über eine neue oder geänderte TESTDATEI also **nichts** — nicht einmal, dass sie kompiliert. (Der Schritt selbst ist ehrlich: er fängt `${PIPESTATUS[0]}` ab und gibt es weiter, trotz des `set +eo pipefail` davor. Sein Blindfleck ist die Reichweite, nicht die Maskierung.)
- **`Echoelmusic CI/CD Pipeline`** macht `build-for-testing` (`ci.yml:175`) **und** `test-without-building` (`ci.yml:190`), beide mit `set -o pipefail` und ohne `continue-on-error` (ein Kommentar bei `ci.yml:198-202` verbietet die frühere `|| cat`-Maske ausdrücklich). **Auf `push` ist es das EINZIGE Gate, das `Tests/CISmoke` kompiliert UND ausführt.** (⛔ Ohne das „auf `push`" war der Satz falsch: `pr-check.yml:106` baut dasselbe Scheme mit `build-for-testing` und `:129` würde es ausführen — auf PRs nach `main`/`develop`. Es kommt dort nie an, weil der Schritt dazwischen, `:118`, das nicht existierende Scheme `Echoelmusic-macOS` baut und den Job vorher tötet. Die Exklusivität ist also eine **Nebenwirkung von #210**, nicht der Entwurf; wer #210 repariert, muss diesen Satz mitziehen.)
- Konsequenz für die Sprache in jedem Status-Delta: „beide echten Gates grün" ist als Kurzform für „das blockierende Bundle lief" nur deshalb richtig, **weil CI/CD dabei ist**. Für eine reine Testdatei ist CI/CD allein maßgeblich; Compile-Check-grün allein heißt nur `Sources/`-grün.
- **`Echoel Full Test Suite (non-blocking)` beweist gar nichts** — es meldete am 2026-07-31 `success` auf `bc35248`, während beide echten Gates an 12 Compile-Fehlern scheiterten. Ursache und Reparatur: #208 (founder-gated, `.github/workflows/**` ist berichten-nicht-editieren).

> **No JUCE / no CMake / no C++.** Swift 100%, ZERO external dependencies today (`Package.swift` `dependencies: []`; HaishinKit = planned, compile-guarded only).
> The old CMake/JUCE/iPlug2 desktop scaffolding (`CMakeLists.txt`, `setup*.sh`,
> `build.yml`, `desktop_build.yml`, desktop build scripts) was removed 2026-06-19.
> Legacy/contradictory workflows also removed 2026-06-19: `android-build.yml`,
> `phase8000-ci.yml`, `swift.yml`, `release-all-platforms.yml` (Android is disabled;
> these were redundant with `ci.yml`/`testflight.yml`).

Android build is disabled. TestFlight needs 60min timeout (30min+ compile).

### GitHub API Access

Token stored in `.claude/settings.local.json` (gitignored, NEVER committed).

**Read token:**
```bash
GITHUB_TOKEN=$(python3 -c "import json; print(json.load(open('.claude/settings.local.json'))['github']['token'])" 2>/dev/null)
```

**Available commands:**
- `/testflight-deploy` — Full pre-flight + deploy to TestFlight
- `/github` — GitHub API operations (PRs, issues, workflow status)

**If token missing:** Ask user to create `.claude/settings.local.json`:
```json
{
  "github": {
    "token_name": "claude-code",
    "token": "ghp_...",
    "owner": "vibrationalforce",
    "repo": "Echoelmusic"
  }
}
```

---

## OSC (EchoelSync)

Actual address set (source of truth: `Sync/OSCSender.swift` — corrected 2026-07-04;
the old list named eeg/{band}, audio/rms, audio/pitch which are NEVER sent):

```
/echoelmusic/bio/heart/bpm       float
/echoelmusic/bio/heart/hrv       float [0-1] (normalized)
/echoelmusic/bio/heart/rmssd     float ms   (only when source provides >0)
/echoelmusic/bio/heart/sdnn      float ms   (   "   )
/echoelmusic/bio/heart/pnn50     float      (   "   )
/echoelmusic/bio/breath/rate     float
/echoelmusic/bio/breath/phase    float [0-1]
/echoelmusic/bio/coherence       float [0-1]
/echoelmusic/bio/motion          float      — NOT SENT in this build (#215): nothing
                                              measures motion, so a constant 0 would be
                                              indistinguishable from a still performer.
                                              Gated on `ModSource.motion.hasProducer`
/echoelmusic/mod/<key>           float      (modulation-matrix outs, e.g. seq.tempo)
/echoelmusic/bio/event/heartbeat | breath/inhale | breath/exhale | coherence
                                                     (discrete events, ADRESSEN MIT PRODUZENT)
/echoelmusic/bio/event/motion    — Adresse existiert, wird nie gesendet (dieselbe #215-Begründung
                                   wie vier Zeilen höher; nichts misst Bewegung)
/echoelmusic/bio/event/eeg       — Adresse existiert, wird nie gesendet. `.eegBurst` hat NULL
                                   Produzenten in `Sources/`; die Zuordnung in OSCSender ist
                                   Vorbereitung, kein Ausgang. Kein Integrator darf darauf warten.
```

Plus ADM-OSC immersive object out via `ADMOSCSender`: `/adm/obj/{n}/*`.
UDP. Target: <5ms LAN.

---

## PLATFORM NOTES

- **Simulator:** No HealthKit, Push 3, head tracking
- **Push 3:** Requires USB
- **DMX:** Requires network 192.168.1.100
- **Linux:** `apt install libasound2-dev`

---

## DEVELOPMENT WORKFLOW

### Persistent Memory (memory/)

The `memory/` directory is **durable knowledge** that persists across all sessions:

| File | Purpose |
|------|---------|
| `decisions.md` | Architectural and strategic decisions with rationale and review dates |
| `people.md` | Key contributors, collaborators, contacts |
| `preferences.md` | User preferences for workflow, communication, tooling |
| `user.md` | User profile, project vision, working style |

**SESSION START (mandatory):**
1. Read ALL files in `memory/` to restore context
2. Read `scratchpads/SESSION_LOG.md` for recent session history
3. Read `memory/decisions.md` for any decisions due for review

**SESSION END (mandatory):**
1. Update `memory/` files with any new discoveries, decisions, or preferences learned during the session
2. Log new decisions to `memory/decisions.md` AND `decisions.csv` (see Decision Logging below)
3. Update `scratchpads/SESSION_LOG.md` with session summary

### Decision Logging (decisions.csv)

Machine-readable decision log at repo root. Format:
```
date,decision,reasoning,expected_outcome,review_date,status
```

- Log every architectural/strategic decision the user describes
- Review dates default to 30 days from decision date
- Run `./review.sh` to surface decisions due for review
- Daily cron job auto-flags overdue decisions with `REVIEW_DUE`

### Long-Term Memory (scratchpads/)

The `scratchpads/` directory is session-specific logs and plans:

| File | Purpose |
|------|---------|
| `SESSION_LOG.md` | **Read first** — session history, key discoveries, commits |
| `HARNESS_LEDGER.md` | **The idea-maze** — proven DEAD-ENDS (don't retry), reliable PLAYBOOKS, shipped leaderboard |
| `ARCHITECTURE_AUDIT_*.md` | Data flow diagrams, env object chains, init sequence |
| `PLAN_*.md` | Feature/fix plans before implementation |

**Start every session** by reading `memory/` first, then `scratchpads/SESSION_LOG.md`,
then `scratchpads/HARNESS_LEDGER.md`.

**Harness discipline (long-running-agent effectiveness).** Before trying any
non-trivial approach, scan `HARNESS_LEDGER.md` DEAD-ENDS — a past (context-compacted)
cycle may already have proven it wrong; take the "do this instead". After a cycle,
append ONE row for any real dead-end hit or reliable playbook found, so the loop
climbs instead of circling. Check CI gate status compactly with
`python3 scripts/gh-run-status.py <saved-tool-result.json>` (parses the overflowing
`mcp__github__actions_*` dump into `sha status conclusion run_id title`).

### 4-Phase Workflow

**Phase 1 — Plan:**
- Read `scratchpads/SESSION_LOG.md` for context
- Break task into atomic steps (max 5 min each)
- Write plan to `scratchpads/PLAN_<feature>.md`
- Include exact file paths, expected changes, test strategy

**Phase 2 — Implement (TDD):**
- Write failing test FIRST when adding new functionality
- Run `swift test` — confirm RED
- Implement minimal code to pass
- Run `swift test` — confirm GREEN
- Refactor while GREEN

**Phase 3 — Verify:**
- `swift build` must pass (remember: `-warnings-as-errors`)
- `swift test` must pass
- No force unwraps, no divide-by-zero, no missing environmentObjects
- Guard all divisions, guard all array access, guard all optionals

**Phase 4 — Ship:**
- Commit with conventional prefix: `feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`, `perf:`
- Update `scratchpads/SESSION_LOG.md` with session summary
- Push to feature branch

### Parallel Agent Strategy

For large tasks, use 3-agent parallel audits:
```
Agent 1: Core systems (App entry, init sequence, data flow)
Agent 2: UI layer (Views, environment objects, navigation)
Agent 3: Domain logic (Audio, bio, visual, lighting pipelines)
```

### Code Review Checklist

- [ ] No `@EnvironmentObject` without matching `.environmentObject()` injection
- [ ] No division without guard (`.count`, heartRate, etc.)
- [ ] No `#if os()` missing for platform-specific APIs
- [ ] No hardcoded values where real data should flow
- [ ] All Combine subscriptions stored in cancellables
- [ ] `@MainActor` on all `ObservableObject` classes

---

## UI DESIGN CONSTRAINTS (Uncodixfy)

When generating SwiftUI views, follow clean design principles. Avoid AI-default patterns.

**Reference aesthetic:** Linear, Raycast, Stripe, GitHub — functional, minimal, precise.

**BANNED patterns:**
- Border radii > 16px (no pill shapes, no 20-32px radii)
- Glassmorphism, frosted panels, blur hazes, soft gradients
- Decorative KPI card grids, fake charts, hero sections inside dashboards
- "Eyebrow" labels (tiny uppercase with letter-spacing above headings)
- Glow effects, neon accents, shadow layers > 8px blur
- Transform/scale animations on hover/tap (use opacity/color only)
- Nested panel types (card-in-card, panel-in-panel)
- Decorative copy ("Live Pulse", "Neural Sync", "Quantum Flow")
- Floating cards with large shadows

**REQUIRED patterns:**
- Solid fills or borders on buttons, 8-12px radius max
- Subtle borders (1px, muted color), max 8px shadow blur
- Sidebars: 240-260px fixed, solid background, 1px border
- Forms: labels above inputs, no floating labels, simple focus ring
- Tables: left-aligned text, subtle row hover, clean grid
- Color: use existing palette, dark muted backgrounds, avoid neon
- Transitions: 100-200ms, opacity/color only
- Bio-signal displays: legible numbers first, visualization second
- Flash rate: max 3 Hz (W3C WCAG epilepsy compliance)
- **Parameter rows — ONE control everywhere:** every adjustable numeric parameter (FX, synth
  patch, mix, bio, future modules) uses `EchoelValueField` (label + value + unit, adjusted by a
  vertical-fader drag / tap-to-type). **No raw SwiftUI `Slider`/`Stepper` for parameters.** Tap-to-type
  opens `EchoelNumberPad` — our OWN keypad (the iOS decimal pad can't carry a sign key), with − / +
  at the bottom-left where **− makes the value negative, + positive** (logical for Transpose); − is
  disabled where the range can't go below zero (10.76.44). One keypad app-wide — don't reintroduce the
  system `.decimalPad`/keyboard-toolbar sign buttons. This
  keeps reading + interaction identical app-wide and is science-first (number, not a knob). Dimensionless
  values show as raw decimals (e.g. `0.50`), not `%`. New parameter UI MUST use it; if it can't, raise it
  in The Council before diverging. **Scope:** the whole app. (The old exemption for the standalone `EchoelmusicAUv3`
  plugin target is void — that target was removed 2026-07-24.)
  **⚠️ READ THE WORD "NUMERIC" — the law is not "every parameter is a number field".** A parameter whose
  values have NAMES is a `Picker`, and always was: the filter mode and the delay mode rows are
  `.pickerStyle(.segmented)`, the bio-mod carrier/target/curve rows are `.pickerStyle(.menu)`. Since
  2026-07-29 the two **harmonizer intervals** are too (`HarmonyInterval`, `EchoelFXView.intervalRow`) —
  the founder asked for *"keine semitone Schritte sondern sinnvolle harmonische"*, and the point of that
  change is precisely that a harmony interval STOPS being a number to decode. **Do not "restore" any of
  those to an `EchoelValueField` in the name of this rule.** The rule exists so numbers read and behave
  identically app-wide; turning a named choice back into a raw semitone count would be obeying its letter
  against its purpose — and against an explicit founder ask. The Council step above still applies to a
  genuinely NUMERIC parameter that wants to diverge.

**SCIENCE-FIRST display:**
- Real biometric data only — no decorative visualizations
- HR, HRV, coherence: large legible numbers, small trend sparklines
- No "control room cosplay" or "premium dashboard" aesthetic
- Every visual element must reflect actual data or serve a control function

---

## DO NOT

- Restructure project without approval
- Add dependencies without asking
- Create new targets or top-level dirs
- Modify Info.plist / CI config without asking
- Use force unwrap, `print()`, `ObservableObject`, `UIScreen.main`
- Simplify Rausch DSP algorithms
- Allocate memory on audio thread
- Batch unrelated fixes
- Add features during fix cycles
- Use esoteric terminology

---

## THE COUNCIL (always-on, optimized)

Before any **significant or hard-to-reverse** decision — architecture, scope
changes, >1 file, audio-thread / protected Rausch triad, user-facing copy,
ambiguous founder asks, or deploy/delete/publish — **convene The Council**
(`.claude/skills/the-council/SKILL.md`). Fixed seats (Architect · DSP Purist ·
Vision-Keeper · Shipper · Skeptic · User-Advocate) each give a one-line position
+ sharpest concern; dissent is surfaced, not smoothed; synthesize ONE cheapest
next step + a gate (proceed / mitigate / hold-for-founder). **Skip trivial
reversible actions** — convening on trivia is the failure mode. Composes with
`vision-gate` and the Ralph Wiggum loop; never overrides explicit founder
instructions or the hard rules above.

**Marketing:** to market Echoel (App Store/ASO, website `docs/`, launch, pricing,
social, PR, SEO), use the `echoel-marketing` skill — the Echoel-tuned front door
over the vendored MIT pack at `.claude/skills/marketing/` (Corey Haines, 45
skills). It enforces brand guardrails (no wellness/esoteric/overclaim, claim only
what ships) and is **PIPELINE only — never shipped in-app, never touches `Sources/`**.

**Short-form video content** (TikTok/Reels/Shorts, founder 2026-07-30) lives in
`ContentPipeline/` — same PIPELINE-only rule. **Read `ContentPipeline/CLAIMS.md`
BEFORE writing any script, caption or hashtag set**; it is the one list of what is
true today and what is struck, with the reason. It exists because #158/#192 spent two
whole cycles removing ONE false claim (AUv3) from the website and #184 removed twelve
from the App Store text, where a false claim is a 2.3 rejection. A model asked for
"bio-music app content" will reliably invent an AUv3 plugin and a meditation audience
— Echoel is neither. Note two structural facts recorded in `ContentPipeline/README.md`:
XcodeGen needs no exclusion (targets list explicit source paths, so a new top-level
directory is never scanned), and `ContentPipeline/**` is in NO auto-merge path filter,
so commits touching only it never reach `main` by automation (#252).

## ACTIVATION

```
ECHOEL MODE ACTIVE
Branch: [branch]  Build: [number]
Priority: [errors | failures | task]
Mode: Ralph Wiggum Lambda — Fix → Build → Test → Ship → Loop
```

No intro. Audit → Fix → Build → Loop.
