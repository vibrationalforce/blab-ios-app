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
  **THE BOUNDARY that decides every keep/cut — Editor ≠ Workstation:** is it about the sound being made *now* (KEEP: generative engine, Flow/Loop, **patch editor**, ~~**piano roll**~~ [der Grundsatz gilt, die Instanz nicht: der Founder hat den Noten-Editor am 2026-07-26 gestrichen, #178 nahm die Tür, #475 die 988-Zeilen-`struct` — als Beispiel für „Craft tool, kein DAW" bleibt er lesbar, als Bestandsangabe ist er falsch], genres, output stage, export) or about arranging material *over time* (CUT: timeline/arrangement/clips, multi-track & mixer, audio-file regions, video edit, AUv3 host+target, RTMP, subscriptions)? **Craft tools are instrument controls, not DAW surfaces** — a synth you cannot tune is not an instrument. (⚠ The parenthetical that stood here — *"Hard technical reason the piano roll stays: `PianoRollView` PUBLISHES `MusicalFrame`"* — was FALSE, and line 49 below already said so: the publish lives in `PianoRollModel`'s tick handler, installed once at app start, view or no view. It is corrected here too because THIS is the line a session reads when deciding whether a removal is safe, and as written it would have made one refuse the founder's 2026-07-26 removal on a technical ground that does not exist. **`PianoRollView` = the editor, removed. `PianoRollModel` = the note engine + `MusicalFrame` publisher, KEPT** — that one is genuinely load-bearing.)
  **SHIP GATE "Instrument-Complete v1"** — replaces the dead *"bis die gesamte DMMW auf Profi-Level ist"* (unreachable once the workstation half was dismantled). Five binary checks, all true → lift the freeze: **1. Klang** (curated genres professional, identity survives, no convergence bug) · **2. Kontrolle** (patch editor reachable — `soundPanel` behind the Sound chip; **the piano-roll half of this check is RETIRED by founder decision 2026-07-26, "Pianoroll soll raus"** — the note editor is gone on purpose, so do not read this gate as blocked by its absence) · **3. Modi** (Flow + Loop) · **4. Ausgabe** (visual live + contemplative on device; light/space demonstrable, not required) · **5. Stabilität** (clean launch, no black screen, no menu freeze).
- **Branch:** run `git branch --show-current` — the literal used to be pinned here and was wrong for weeks. Prior cycles auto-merged to `main`.
- **Mode:** RALPH WIGGUM LAMBDA — one feature/fix per cycle, build → test → ship → loop
- **Positioning:** "The first bio-reactive performance instrument" — and, per the 2026-06-06 deep-research roadmap, the **bio-reactive object source for accessible immersive multidimensional media art** (open standards: ADM-OSC, MIDI 2.0, OSC, BLE HRS; no SDK lock-in). See `scratchpads/STRATEGY_STATE_OF_THE_ART_2026-06-06.md`.
- **Architecture (audited 2026-06-09 — `scratchpads/ARCHITECTURE_AUDIT_2026-06-09.md`):** `EngineBus` = `@MainActor @Observable` control plane (snapshots) + lock-free `SPSCQueue`. 3 topics — `bioFrames` / `controllerEvents` / `bioEvents`. **Bio flows over the `latestBio`/`latestBioEvent` snapshot; the SPSC queue is drained only for `controllerEvents` (MIDI).** `bioFrames`/`bioEvents` queues are reserved/undrained (snapshot is the correct path for slow bio). Modules couple only via the bus. ⛔ **Diese Zeile sagte „(10 Hz poll)" und genau diese Zahl hat #315, #332 und #336 erzeugt — drei Zeitkonstanten, die aus ihr abgeleitet und dadurch um das 10- bis 60-Fache daneben lagen. Der POLL ist 10 Hz, die ANWENDUNGSRATE ist ~1 Hz**, weil jeder Verbraucher auf `frame.timestamp` dedupliziert und jeder verdrahtete Publisher mit ~1 Hz sendet (`CameraRPPGBioPublisher` `tick % 10` in einer 100-ms-Schleife, Polar 1 s, Simulator 1 s, HealthKit 500-ms-Poll hinter einem 4–5-s-Sensor). **Für jede Zeitkonstante gilt die 1 Hz, nicht die 10** — der Poll ist nur die Obergrenze, die ein schnellerer Publisher erreichen könnte. Ein Wächter im blockierenden Bundle (`Tests/CISmoke/BioApplyRateIsTheDedupedRateTests.swift`) hält die Publisher-Kadenz und die Deduplizierung fest, damit diese Zeile nicht wieder still altert. ⛔ **UND ES GIBT EINE VIERTE UND FÜNFTE AUFLAGE, in einer Richtung, die dieser Absatz bisher nicht abdeckte** (gefunden in der #459-Nachlese, 2026-08-07, beide in `CameraAnalyzer.swift`): der `beatTimes`-Doc-Kommentar und danach der `rrSegments`-Doc-Kommentar schrieben „wird etwa einmal pro Sekunde neu geschrieben". Die ~1 Hz ist die **LESE**-Rate des Publishers; **geschrieben** werden beide Arrays in `detectPeaks`, das hinter `peakTick % 4` auf einem 15-fps-Feed sitzt — **~3,75 Hz**. Der Fehler ist also nicht Poll-gegen-Anwendung derselben Größe, sondern **SCHREIB-Rate gegen LESE-Rate zweier verschiedener Größen**, und er ist in der SICHEREN Richtung passiert (die reale Rate ist höher, die `@ObservationIgnored`-Begründung wird damit stärker) — weshalb nichts ihn je rot gemacht hätte. **Regel: eine Rate gehört zu genau EINER Operation; wer „~1 Hz" aus einem Nachbar-Kommentar übernimmt, übernimmt zuerst, WELCHE Operation dort gemeint war.**
- **Live pipeline:** HealthKit + **camera rPPG (live, locks on device)** + Demo → bio snapshot. (**Universal BLE HR (0x180D) = GEBAUT + VERDRAHTET**, aber **KORRIGIERT 2026-07-26 — die Tür ist NICHT die Patchbay.** Die alte Fassung hier behauptete, der Source-Port `blehrs.in` starte/stoppe `PolarH10BioPublisher` via `applyRouting` [`hasEnabledRoute(fromSource:"blehrs.in")`]. Das galt nur von B4 [2026-07-12] bis **BLE-3 [2026-07-15]**, das die Kopplung wieder entfernte: `applyRouting` war damit ein ZWEITER Lifecycle-Besitzer, der einen über die Pulse-Pille gestarteten Gurt bei JEDEM unbeteiligten Patchbay-Edit mitten in der Performance killte. **Heute hat der Gurt genau EINEN Besitzer: das Source-Dropdown der Pulse-Pille [`startBioSource`].** `blehrs.in` ist ein reiner Datenfluss-Port; `hasEnabledRoute(fromSource:)` hat **keinen Produktions-Aufrufer** — nicht daraus einen Start-Hook zurück-ableiten. Gerät-Verify wartet auf Gurt-Eintreffen [NEEDS-FOUNDER-VERIFY]. Deep Audit `scratchpads/DEEP_AUDIT_2026-07-12.md` ist an dieser Stelle ebenfalls überholt.) Pipeline weiter: bio snapshot → BioReactiveSynthVoice (EchoelDDSP; **silent until user-armed**) + OSCSender (`/echoelmusic/bio/*`) + **ADMOSCSender** (`/adm/obj/{n}/*` immersive object out). CoreMIDI MPE → controllerEvents → synth notes (performer priority). BioEventGraph → breath/motion onsets. ModulationEngine wired (bio→tempo). **EchoelBeat ist TOT** (korrigiert 2026-07-27): velocity/accent, swing und Per-Pad-Sample-Import standen hier weiter als live, obwohl der Founder die Drums am 2026-07-26 entfernt hat (#166). `BeatPlayer.attach(to:)` hängt nur noch `previewVoice` ein — kein Pad-Voice, kein `pattern.onStep`. Es kann heute KEIN Drum-Klang entstehen. **Der vollständige Abriss (#167) ist am 2026-07-31 FERTIG**: `DrumSynthVoice`, `LaneDrumKitVoice` und `DrumNoteMap` sind als Dateien gelöscht, ebenso `PhysicalVoiceRef.drums` und `LaneVoiceRack.kits`/`setDrumsInsert`. Die Enum-Cases `LaneVoiceKind.drums` / `TrackInstrument.drums` BLEIBEN. ⛔ **Die erste Fassung dieser Zeile begründete das mit „persistierte rawValues, ein unbekannter verwirft beim Decode die ganze Spur" — BEIDE Hälften sind falsch, und die Begründung stand gleichzeitig in vier Quelldateien.** `LaneVoiceKind` ist gar nicht `Codable` und erreicht nie die Platte (`Timeline.swift` sagt das selbst). `TrackInstrument` ist es, aber `TimelineLane`s Decoder wickelt ihn in `try? … ?? nil` — genau damit #167 überlebbar ist: ein unbekannter Case wird zu „kein eingebautes Instrument", die Spur mit Regionen, Clips, Mixer und Patch bleibt vollständig. Die WAHREN Gründe sind schwächer und stehen jetzt an den Cases selbst: `TrackInstrument.drums` löschen kostet einer Altspur ihre Instrument-WAHL (Founder sagte „erstmal"), `LaneVoiceKind.drums` ist ein toter Case ohne Produzenten, der eine eigene Entscheidung braucht. **Lehre: ein „NICHT löschen"-Kommentar mit falscher Begründung ist schlimmer als keiner — die nächste Session kann ihn nicht widerlegen.**
- **Protected DSP triad (READ-ONLY, now implemented):** BioSignalDeconvolver (detrend·notch·validity), HilbertSensorMapper (1D→2D Hilbert curve), BioEventGraph (heartbeat/breath/motion detectors). Pure value types, SKILL.md contracts under `.claude/skills/`.
- **SDK:** iOS 18 deployment floor (Package.swift + project.yml + Resources/iOS/Info.plist synced). Xcode 26.2 in `testflight.yml`. App Group `group.com.echoelmusic`.
- **Root view (RE-FOCUS 2026-07-06B — founder: "die Leute brauchen gar keine Atemübung. Es geht um Performance und Entspannungssteigerung dadurch, dass sich die Musik mit dem Biofeedback generativ verändert"): the bio-generative INSTRUMENT is the app HOME.** This supersedes the same-day 2026-07-06A "Session is home" flip (the founder tested it and rejected the breathing-exercise framing within hours). `WorkspaceView` body = brand header (`topBar`) + `CompositionHeaderStrip` + `EchoelStudioView()` + `FloatingVisualWindow`. (⛔ Hier stand „persistent `TransportBar`“ — mit #456 am 2026-08-07 aufgelöst: die Leiste hielt seit #411 nur noch zwei Kinder, und der Founder hat beide per Screenshot-Pfeil in die Transport-Zeile des Instruments geschickt. Die Chrome ist zwei Leisten, nicht drei.) **The Session experiment (`SessionView`/`SessionEngine`/`SessionGuide`/`SessionClock`/`EntrainmentEngine`) stays in code, compiling, but NOTHING presents it** — do not re-add a Session door/card without a founder ask; equally, do not delete those files without one (they hold the tested flash-safety/latency/pacing laws, reusable for future bio-visual work). The product bar now: the generative MUSIC must sound organic/professional and the VISUAL must be part of the experience ("wow", contemplative) — quality work goes there, not into new surfaces.
- **Studio shell internals:** brand header (`topBar`) + `CompositionHeaderStrip` + `EchoelStudioView` (the instrument) + the floating immersive visual (`FloatingVisualWindow`, toggled from the header monitor). ⛔ **Was hier stand, war ab #411 halb und ab #456 ganz falsch — und es ist die Zeile, aus der eine Session die Chrome-Struktur liest:** „persistent `TransportBar` (Play/Stop + tempo-lock button + `TransportPositionView` loop/position leaf … der eine Tempo-Regler ist das kompakte `BodyTempoField` in der TransportBar-Chrome selbst (`WorkspaceView.swift:345`))“. Davon stimmt heute NICHTS mehr: Play/Stop ging mit #289 als `PlaybackToggleButton` ins Instrument, das Tempo-Feld mit #411 in `EchoelStudioView.startControlRow`, und mit #456 sind auch die letzten zwei Kinder — das „•••“-Überlaufmenü und `TransportPositionView` — dorthin gewandert; die Leiste ist gelöscht. Der EINE Tempo-Regler ist weiterhin genau einer, er sitzt nur im Instrument. **Und die Zeilennummer war der übliche Zusatzfehler** — dieselbe Lehre wie im Absatz über die Modal-Slots: eine zitierte Phrase überlebt eine Einfügung, eine Zeilennummer nicht. **The former 6-surface bottom bar (Arrange · Clips · Compose · Mix · Bio · Browse) is REMOVED from navigation** — **von den sechs ist nur noch EINE als Datei da: `BioSourceView`** (unerreichbar, aber restaurierbar). Die Liste, die hier stand („ClipView/ArrangementView/ChannelRackView/BioSourceView … reversible by restoring the bottom bar"), war am 2026-07-27 zu drei Vierteln falsch und hätte eine Session glauben lassen, die Mix- und Clip-Flächen ließen sich durch Wiedereinhängen der Leiste zurückholen: **`ClipView` (807dc0d) und `ArrangeTimelineView` (eb58e7a) sind mit #121 Slice 4 gelöscht, `BrowserView` und `ChannelRackView` mit #167 (2026-07-27)** — letzteres mischte 8 Kanäle, die keinen Klang mehr erzeugen. Wiederherstellen hieße hier neu bauen, nicht wieder anhängen. Do not "restore" them without a founder ask. **Video page = designed + DEFERRED** (`scratchpads/PLAN_VIDEO_PAGE.md`). The old `StudioRoot` Tools/Works/Sync/Well TabView is long gone.
- **Presentation (stability, as-shipped — corrected 10.76.38):** the device-confirmed-launching `EchoelStudioView` uses **MANY `AnyView`-wrapped `.sheet`/`.fullScreenCover` modifiers** chained on the body. Counted by grep 2026-07-27 on `EchoelStudioView.body`: **8 `.sheet` + 2 `.fullScreenCover` + 3 `.alert` + 1 `.fileImporter` = 14 presentation modifiers** on the chain (⛔ „ein 15ter“ war eine Zahl zu wenig: es sind **ZWEI** verschachtelte, gemessen 2026-08-07 — `.sheet(item: $visualShare)` im `showVisual`-Vollbild und `.fileImporter(isPresented: $projectImportPresented)` in `openSheet`. **Dateiweit also 16, auf der Kette 14**, und nur die 14 sind das Metadata-Budget. Seit #479 behauptet `ResetSoundClearsWhatTheLaunchLineReportsTests` BEIDE Zahlen: dateiweit `== 16` fängt das HINZUFÜGEN, kettenweise `<= 14` fängt das VERSCHIEBEN eines verschachtelten Modifiers auf die Kette — der dateiweite Zähler bleibt dabei grün, während der generische Typ wächst. `<=` und nicht `==`, weil die vorgeschriebene Reparatur — alles in EIN `.sheet(item:)`-Enum falten — die Kette VERKÜRZT und ein Gleichheitstest die Reparatur selbst rot färben würde.) The old "= 16" here was stale by two — and it was the number a session reads BEFORE adding a modal, so believing in headroom that does not exist is how the black-screen SIGSEGV comes back. The CRAFT-TOOL DOORS bullet below carries the same count; keep the two in sync or delete one. Each has its own `isPresented:`/`item:` binding and an `AnyView(...)`-erased content closure. This is the baseline that launches — the earlier "ONE `.sheet(item:)` + ONE `.fullScreenCover(item:)` via computed bindings" note was **aspirational, never the shipping code**, and is removed to stop a future session "fixing" the launching code into a regression. **THE REAL RULE (learned the hard way, 10.76.34/build 2068 black screen): do NOT keep GROWING this modifier chain.** Adding sheets pushed the body's aggregate generic type past the SwiftUI metadata-decoder stack limit → SIGSEGV at first render, before any view appears (presents as a black screen, or "Safe Mode oder Black Screen" alternating once the self-healing net catches every other launch). The chain was "just under" the limit at 10.76.9/21; three sheets added 10.76.25/27/29 tipped it over (an `AnyView`-split of the chain did NOT save it — 10.76.35 still crashed; only reverting to the 10.76.21 body did). To add a NEW modal: **reuse/replace an existing slot, or consolidate the whole chain into a single `.sheet(item:)` enum FIRST** — never just append another `.sheet`. (Separately: never drive two modals true at once — that installs an invisible tap-blocking layer, the "can't click anything" hang.) **Also (10.76.41, "Tonart-Menü friert ein / kann plötzlich nicht mehr auswählen"): never read a HIGH-FREQUENCY `@Observable` (the ~10 Hz `CameraRPPGBioPublisher` finger/confidence/waveform, any bio snapshot, a playhead) directly in `EchoelStudioView.body` or in a computed `var` that `body` evaluates — `AnyView(...)` is NOT an observation boundary, so those reads register the WHOLE root body as a 10 Hz observer and every rebuild tears down any open `.menu` Picker popover (the freeze; worse while playing). Confine such reads to their own small leaf `View` struct (e.g. `BioStripView`, `PulseMeasurementView`) so only that view churns; the Picker-hosting body stays still.** **AND (10.76.48, "Sobald Biofeedback läuft kann ich nicht mehr auswählen"): the camera-freeze had a SECOND, non-SwiftUI cause — a high-frequency producer on a background queue must NOT hop to `@MainActor` per item. `CameraRPPGBioPublisher.onFrame` did a `Task { @MainActor }` PER captured frame (~30/s before the analyzer's frame-skip); that flood of tiny main-actor task submissions starved the SwiftUI executor → the open `.menu` Picker stopped responding while bio ran. Fix pattern: the background closure pushes into a lock-protected `RGBSampleQueue` (`@unchecked Sendable`, `NSLock`, capped) with ZERO actor hop; the EXISTING 10 Hz `publishTask` drains+feeds the `@MainActor` analyzer in one batch (carry a `timestamp` so rate maths is unchanged). Rule: never `Task { @MainActor }` per frame from a 30 fps source — batch into an existing low-rate main-actor poll via a Sendable queue.** **AND (10.76.50, the ACTUAL recurring menu-freeze cause — found after 41/43/47/48 each fixed a real-but-insufficient cause): the churn was in `WorkspaceView` (the ROOT, ABOVE every surface), NOT in `EchoelStudioView`. `WorkspaceView.topBar` read `cameraRPPG.waveform`/`detectedBPM`/`isLocked` directly to feed the header `PulseMonitorMini` — `waveform` updates ~10 Hz during biofeedback, so `WorkspaceView.body` rebuilt 10×/s and tore down any open `.menu` Picker in the surface BELOW it. Every prior audit scoped to `EchoelStudioView` and correctly found it clean — the 10 Hz read was one level up. FIX: confine the live reads to a leaf (`PulseMonitorMiniLive` reads the publisher in its OWN body); `WorkspaceView` only reads `isRunning` (start/stop). **RULE: when a freeze/churn persists after the obvious view is proven clean, AUDIT THE PARENT/ROOT (`WorkspaceView`, any always-on header/HUD that reads live bio) — a 10 Hz read in ANY ancestor of the menu host rebuilds the whole subtree. Header/monitor tiles that show live bio MUST read it in their own leaf, never via values passed down from a parent body.**
- **✅ TESTFLIGHT PIPELINE: GREEN (verified 2026-05-30).** Prior "deploy blocker" note is resolved — `testflight.yml` runs #1404–#1407 on `main` all succeeded across every platform (iOS upload + Summary), preflight confirms App Store Connect secrets are present and valid. Dispatch + poll from the sandbox via `bash scripts/check-testflight.sh dispatch` (token in gitignored `.claude/settings.local.json`). Push the feature branch's newer work (bio synth / OSC / Polar) to TestFlight with a full `build_only=false` run once a branch verification run is green.
- **Latest batch (2026-07-12, 24h-Mandat, on branch, gates green, TestFlight-FREEZE bis Profi-Milestone):** **A3 drawable automation canvas** (tap-add / drag-move / segment-bend / double-tap-delete; `AutomationCanvasMath` pure) · **A4 bio-operators** (coherence shifts the chance threshold, roll stays seeded) · **L1 Grand Master + Blackout** (Art-Net + sACN; blackout wins, return slews) · **P1 idle-voice skip** (frames not blocks, 2.5 s window > dub-echo tail; audio-thread-reviewed) · **B2 per-track pan** (`TimelineLane.pan`, honest `sourceNode.pan`/AVAudioMixing engine path, sends deliberately absent) · **B3 Bio into the menu host** (always-on strip removed, "Bio" chip + header long-press) · **B4 BLE strap door — ZURÜCKGENOMMEN am 2026-07-15 durch BLE-3**, die Patchbay ist NICHT die Tür des Gurts (siehe Pipeline-Zeile) · **B5 sample door on every drum channel strip** (slot-reuse) · **W1 LyricsModel** (deterministic singing syllabification + melisma, pure; W-track per founder 2026-07-12C) · **EchoelAI foundation N0–N4** (`scratchpads/ECHOELAI_ADR_2026-07-12.md`: `EchoelParameterRegistry` [keyPath-stable, DDSP inventory] + `BrainBackend`/`FoundationModelsBrain` [Tier-1, `#if canImport(FoundationModels)`+iOS 26, else unavailable] + `ParameterToolCore` [model-free tool logic] + vocabulary data — ⛔ **„ALL behind `FeatureFlags.echoelAI` default OFF" IST FALSCH, und zwar in beide Richtungen. Gemessen 2026-08-07: `git grep -n "FeatureFlags.echoelAI" -- Sources` liefert GENAU EINEN Treffer, und der ist ein KOMMENTAR** (`EchoelAI/BrainBackend.swift:10`). Der Schalter hat null Leser; nichts ist hinter ihm. **(a)** `BrainBackend` und `FoundationModelsBrain` haben außerhalb von `EchoelAI/` überhaupt keinen Verbraucher — sie sind AUS, weil sie niemand ruft, nicht weil eine Flagge sie ausschaltet. **(b)** Und die gefährlichere Hälfte: `EchoelParameterRegistry` steht in dieser Aufzählung, liegt aber in `Core/` und ist in FÜNF Dateien live (`AutomationPlayer`, `ParameterApplyRouter`, `EchoelDDSP`, `EchoelmusicApp`) — der Satz erklärt einen LEBENDEN Typ für flag-gated aus. `ParameterToolCore` ebenso, gelesen von `ParameterApplyRouter`. **Die Sicherheits-Eigenschaft „Release bit-identical" stimmt weiterhin, aber sie kommt vom fehlenden AUFRUFER, nicht von einer Flagge** — wer später eine Aufrufstelle hinzufügt und sich auf `FeatureFlags.echoelAI` als Absicherung verlässt, hat gar keine. Entweder wird die Flagge wirklich verdrahtet oder sie wird gelöscht; heute ist sie Dekoration. (Der EchoelAI-Safety-Owner aus `ultracode-teams` ist genau dafür da.) Unverändert wahr: der LLM berührt den Audio-Thread nicht.) · **Body Science learn section** (`BioScienceInfo`: cited HRV-resonance research — Lehrer/Vaschillo, Goessl 2017 — facts + self-observation, NO health claim, test-guarded; report `scratchpads/REPORT_SOUND_PAIN_EVIDENCE_2026-07-12.md`). **Healing/organ/tissue/wound theme = pre-Echoel (BLAB/Syng) legacy, never code here, stays a hard REJECT red line.**
- **Latest work (2026-06-23, on branch, gates green):** **Adaptive Quality** (AdaptiveQuality core + ResourceGovernor: thermal/battery/measured-FPS → tier → MetalBioView detail/reduce-motion **+ OSCSender's bio-egress rate via `PollingRateCeiling`, a CEILING and not a target** — corrected 2026-07-28 twice over: the governor never drove MetalBioView's frame RATE (`MetalBioView.swift:373` pins `preferredFramesPerSecond = 60` statically, and `AdaptiveQuality.swift` says so itself), and the one consumer wired since — `bioHz` → `OSCSender` (34e2355) — was missing. `targetFPS` / `oscHz` / `allowSpectralDonuts` have NO consumer, by design. This is the line a session reads before touching a quality knob, so both halves being wrong was the dangerous kind of stale) · **camera-session resilience** (runtime-error/interruption observers + frame-stall watchdog — fixes the silent ~68–200 s rPPG freeze) · **rPPG saturation-hold** · **composition cohesion** (BioComposer structure/detail RNG split — "homogener klingen") · **master −1 dBFS true-peak trim** · **EchoelFX bio-reactive modulation** (FXModulation core in `Core/` + FXBioModulator ~30 Hz; body→FX-param routing, UI section) · **EchoelFX Bitcrush + Stereo Widener** stages (wired chain/VM/UI/FXPreset/bio-mod) · **VJ visuals** (live in-fullscreen control overlay + shader hue/saturation palette, physical-colour default preserved). EchoelFX deepening = 4 workstreams (1 bio-mod + 2 algorithms shipped; 3 macro-morph + 4 CI-polish pending).
- **Prior TestFlight ship (2026-06-18):** rPPG fix (torch + exposure lock), real frequency-domain HRV coherence (Lomb-Scargle + Welch), resonance breath guide, tap-to-learn bio metrics, Art-Net flash-safety. Base build 1543 (app + Widget + AUv3, camera rPPG, universal BLE, ADM-OSC, EchoelLux Art-Net, launch silence).
- **Absent (not wired — do not claim as shipping):** RTMP/streaming (BroadcastPublisher is a compile-safe scaffold behind `#if canImport(HaishinKit)`; HaishinKit not integrated), Video-SCHNITT (⛔ korrigiert 2026-07-31: hier stand „video capture/edit" — die CAPTURE ist erreichbar und darf sehr wohl als shipping gelten, nur der EDIT ging mit #121 Slice 3), multitrack audio (gebaut, flag-gated AUS, türlos — siehe den ⛔-Absatz „Was hier stand und 2026-07-27 gestrichen wurde" ganz oben und #204; „absent" stimmt für den Nutzer, „nicht gebaut" nicht für den Entwickler). **EchoelStore** (`Core/EchoelStore.swift`) = compiling but UNREACHABLE: `ProUnlockView` exists and is never presented (`WorkspaceView.swift:117`), so nothing is purchasable today. Corrected 2026-07-25 — the old "ZERO consumers" + "legacy subscription product IDs" wording was false on both halves: the one compiled product is the NON-CONSUMABLE `com.echoelmusic.app.pro` (`ProGate.swift`). **Aber das ist ÜBRIGGEBLIEBEN, nicht der Plan** (korrigiert 2026-07-28): die zweite Founder-Entscheidung vom 2026-07-10, wörtlich festgehalten in `WorkspaceView.swift` über `body`, hebt das Einmal-Pro auf — v1.0 komplett kostenlos, v1.1 = „Echoel Live" Jahres-Abo, v1.2 = Per-Event-Host-Gebühr. `ProUnlockView`/`EchoelStore`/`ProGate` bleiben im Code, um dafür UMGEWIDMET zu werden: nicht löschen, vor v1.1 nicht wieder präsentieren. **Push/CloudKit:** `aps-environment=production` + iCloud/CloudKit entitlements ARE declared and `AnnouncementCenter` (registerForRemoteNotifications + CKQuerySubscription) EXISTS — but hard-gated OFF for v1.0 via `AnnouncementCenter.cloudKitConfigured = false` (zero CloudKit/push calls execute; launch-crash fix v10.79.148). Its Learn-view toggle is HIDDEN while the gate is false (2.1 audit 2026-07-16). Before flipping the gate in v1.1: deploy the CloudKit "Announcement" schema to Production FIRST. (The old "zero push code" claim here was stale — corrected 2026-07-16.) **Art-Net + sACN (unicast) are live.** **VocoderCore / BioModulation** = pure tested cores, **not yet wired** (foundations). **FeedbackGuard** (audio-input live monitoring): ENGINE wired (AudioEngine ~15 Hz Duck-Loop, Tests grün) — aber die UI-Tür (`AudioInputPickerView`, `showInput`) ist seit dem Tools-Grid-Removal (2026-07-02) UNERREICHBAR; gleiches Schicksal für PatchbayView (Routing!), MeditationView, PatchEditorView, SampleBrowserView, AutomationView, BroadcastView, SpectralDonutView — alle Slots existieren, einziger Trigger war das tote `toolsSection`/`openTool` (Deep Audit 2026-07-12; tote Slots = SLOT-REUSE-Reservoir an der Modal-Decke). **BEHOBEN (2026-07-12 batch + seither):** PatchbayView (Routing/Master-Panel), ~~SampleBrowserView (B5, Drum-Channel-Strip-Tür)~~ — **GELÖSCHT 2026-07-27 (#167)**; die B5-Tür starb schon mit den Drums (#166), die Datei ist jetzt auch weg. Genau die „verifiziert erreichbar"-Falle, vor der derselbe Absatz warnt: Slot + Setzer beweist keine Erreichbarkeit, und ein Eintrag hier veraltet still, **FeedbackGuard/AudioInputPicker** (Master-Panel „Audio input"-Tür, EchoelStudioView.swift `masterDoorButton`) ist wieder erreichbar. **NICHT erreichbar** (Stand 2026-07-31, per Zählung der Instanziierungsstellen): ~~`PatchEditorView`~~ — **GELÖSCHT 2026-07-31 (#132 Slice 6)**, kein Eintrag mehr in dieser Liste, weil es die Datei nicht mehr gibt; der lebende Timbre-Editor ist und war `soundPanel` hinter dem Sound-Chip. `AutomationView` (Datei existiert nicht), `SpectralDonutView`, `SampleBrowserView` (mit #167 gelöscht), ~~`FileWaveformView`~~ — **GELÖSCHT 2026-07-28 (#132 Slice 5, `2245671`)** zusammen mit `WaveformView` und `WaveformCache`; kein Eintrag mehr in dieser Liste, weil es die Datei nicht mehr gibt. Der reine Kern `WaveformReducer` BLEIBT, jetzt test-only und mit Nachruf im eigenen Datei-Kopf. **Genau die Falle, vor der dieser Absatz zweimal warnt:** der Eintrag stand hier als Gegenwarts-Tatsache, geschrieben am selben Tag als PLAN für genau diesen Commit — wer ihn danach las, hätte eine türlose Waveform-Ansicht wieder aufmachen wollen, die es nicht mehr gibt. **KORREKTUR 2026-07-26 (die „verifiziert 2026-07-21"-Zeile war FALSCH für zwei ihrer Einträge):** `AutomationView.swift` existiert im Repo nicht mehr — es kann keine Tür haben. Und **`SpectralDonutView` ist UNERREICHBAR:** ihr einziger Instanziierungsort liegt im `.fullScreenCover(isPresented: $showVisual)`, und `showVisual`s einziger Setzer war `openTool`, aufrufbar nur aus `toolsSection`, **das nichts rendert**. Dieselbe tote Kette nimmt den MIDI-**Import** (`midiImportPresented` / `importMIDI()`) und die REC-Taste im Visual-Vollbild mit; die „Donuts"-Pille im Synth-Reiter ist live antippbar und wirkungslos, weil `FloatingVisualWindow` — das einzige erreichbare Visual — den `spectralDonuts`-Key nie liest. **3 der 14 Präsentations-Slots hängen an Flags, die niemand setzen kann** = freier Kopfraum an der Metadata-Decke, statt einen 17. anzuhängen. Der tote Tools-Katalog selbst ist mit `f371d27` gelöscht (`ToolCat`/`ToolItem`/`toolItems`/`openTool`/`toolsSection`/`toolGroup`/`gridChip`/`gridChipLabel`, 157 Zeilen) — die drei Modifier stehen absichtlich weiter da, als wiederverwendbare Slots. **Er nahm dabei die einzige Oberfläche für drei Opt-ins mit:** „Save to Apple Health" (persistiert! mit `083cec8` als `HealthWriteOptInRow` im Bio-Panel zurückgeholt — ein persistiertes Gesundheits-Einverständnis MUSS einen erreichbaren Aus-Schalter haben) sowie `midiOut.mpeEnabled` / `expressionEnabled` (nicht persistiert, Default aus → Fähigkeitslücke, kein Einverständnis-Problem; gehören in die Routing-Fläche, offen). ZWEI LEHREN: (1) „per direktem Code-Read verifiziert" heißt nur etwas, wenn die Kette bis zum RENDERNDEN Elternteil verfolgt wurde — Slot + Setzer beweist keine Erreichbarkeit. (2) **Vor dem Löschen eines UI-Blocks prüfen, welche Modelle er als EINZIGER schreibt** — ein Toggle mit persistiertem Flag hinterlässt beim Löschen einen unwiderruflichen Zustand, keine Lücke. **Keine Zeilennummern in diesem Absatz:** die erste Fassung zitierte Nummern, die derselbe Commit um 157 verschob. MeditationView bleibt bewusst türlos (Founder: Teil des Produktionsflusses, keine eigene Tür gewollt). **BroadcastView bleibt türlos — korrekt so**, solange HaishinKit/RTMP nicht verlinkt ist (eine Tür zu einem nicht funktionierenden Backend wäre ein Halbfertig-Feature). **BioVisualParams** (immersive flash-safe pulse) is **wired**. See `docs/dev/FEATURE_MATRIX.md` + `scratchpads/DEEP_AUDIT_2026-07-12.md`.
  ⛔ **DREI TÜRLOSE FLÄCHEN FEHLTEN IN DIESEM REGISTER (nachgetragen 2026-08-07, jede per Zählung der Instanziierungsstellen).** Das Register ist die Liste, aus der eine Sitzung ableitet, was sie noch aufmachen oder löschen darf — eine Lücke darin ist teurer als eine falsche Zahl, weil sie gar nicht erst als Frage auftaucht.
  · **`AnalysisScopeView`** (#347 Slice 1) und **`AnalysisPoincareView`** (#347 Slice 3b): `git grep -n "AnalysisScopeView(\|AnalysisPoincareView(" -- Sources` außerhalb der eigenen Dateien = **0**. Ihre zwei Geschwister derselben Epic sind sehr wohl montiert (`AnalysisSpectrumView` und `AnalysisWavefrontView`, beide in `EchoelStudioView`). **Das ist KEIN Defekt und muss so dastehen:** die Entscheidung ist am 2026-08-02 per Founder-Screenshot mit rotem X gefallen und im Quelltext an der Montagestelle festgehalten. Also türlos ABSICHTLICH, wie `ImmersiveStageView` und `BroadcastView` — nur stand es nirgends im Register, und genau das ist der Zustand, den der Doctor-Sektion-C-Text „unerreichbar UND nirgends aufgeschrieben" nennt.
  · **`TimelineAutomationRow` = GELÖSCHT (#473, 2026-08-07).** Der Eintrag stand hier als türlos-aber-nicht-löschbar, weil `TimelineAutomationRowMath` in DERSELBEN Datei lebte und `Core/TimelineStore.swift` es ruft — ein „lösch die türlose Datei"-Aufräumen hätte den Store gebrochen. **#472 hat den Kern herausgehoben, #473 hat die Ansicht gelöscht**: `struct TimelineAutomationRow: View` plus `TimelineAutomationTargetOption` und `TimelineAutomationHeadCell`, alle drei mit null externen Verweisen. Die Datei ist weg; `Sequencer/TimelineAutomationRowMath.swift` bleibt und ist unverändert.
    ⛔ **UND DIE ERSTE FASSUNG DIESER ZEILE HAT DIE #475-LEHRE WÖRTLICH WIEDERHOLT, EINEN ZYKLUS SPÄTER: sie schrieb „415 Zeilen `struct TimelineAutomationRow`".** 415 ist die **DATEI** (`git show --stat`, 415 Löschungen). Der `struct` läuft von 217 bis 414, ist also **198** Zeilen; die ganze `#if canImport(SwiftUI)`-Hälfte mit allen DREI Typen sind **344** (72–415). Und der Widerspruch stand schon im Baum: `TimelineAutomationRowMath.swift` und dieselbe CLAUDE.md sagen seit #472 „344 Zeilen" über die Ansicht. **Dieselbe Zahl an das falsche OBJEKT geheftet — nicht veraltet, sondern von Anfang an dem falschen Ding zugeordnet**, und das ist der Grund, warum das Repo jetzt zwei Zahlen für eine Sache trug. Belastbar ist die GRÖSSE des Eingriffs (415 Löschungen), weil die sich nie wieder ändert; für die Ansicht nennt man die Ansicht.
    ⭐ **DIE PROSA-ZITATE IN FÜNF DATEIEN SIND UMGESIEDELT, NICHT VERWORFEN — es sind SECHS Zitate, weil `EchoelValueField` zwei trägt — und das war der eigentliche Blocker, den keine Register-Zeile vorhergesagt hatte** (die #472-Lehre: eine registrierte Entblockung ist erst dann eine, wenn man NACH dem Ausführen noch einmal grept). `Core/PerTrackParameterKeyPath.swift` hatte einen ZEIGER auf den `DATA MODEL (honest):`-Block der Ansicht — der Block ist jetzt dort EINGERÜCKT statt ein drittes Mal zitiert, denn dieselbe Zeile hatte schon eine `:11-16`-Zeilenspanne an #472 verloren. **Zwei Zitat-Ausfälle, zwei Mechanismen, eine Datei: ein Zeiger ist nur so haltbar wie das, worauf er zeigt.** Die zwei `EchoelValueField`-Prämissen stehen jetzt als HISTORISCHER Beleg — die SwiftUI-Behauptungen sind unverändert, der Zeuge im Repo ist weg, und die zweite (`⚠️ HONEST LIMIT`) wird dadurch SCHÄRFER: diese Datei ist der einzige verbliebene Abhängige. `DSP/EchoelDDSP.swift` benutzte die Türlosigkeit als Prämisse — „null Instanziierungsstellen" hätte ein Wieder-Einhängen still falsifiziert, „gelöscht" kann das nicht, das Argument ist also STÄRKER geworden. `Core/AutomationPlayer.swift`s ⛔-Rücknahme bleibt, gerade WEIL der Code, den sie korrigiert, nicht mehr nachlesbar ist. Und `Sequencer/ClipAutomationEdit.swift` zitierte „TimelineAutomationRow's static helpers" — seit #472 falsch, nach #473 gegenstandslos.
    ⛔ **UND DAS NACH-DEM-SCHNEIDEN-GREPEN HAT EINEN VERWAISTEN NACHBARN GEFUNDEN, den niemand aufgeschrieben hatte:** `AutomationPlayer.extraAutomatableDescriptors` hat seither **null** Aufrufer in `Sources/` — sein einziger Leser war `TimelineAutomationTargetOption`. NICHT mitgelöscht: es ist das Placebo-Gesetz in ausführbarer Form („biete nur einen Parameter an, der wirklich Audio bewegt") und genau das, was eine künftige Automations-Fläche zuerst braucht. Der Vermerk steht an der Deklaration statt hier zu verjähren.
    ⚠️ Der Wächter ist im SELBEN Commit mitgezogen (#456): `TheAutomationRowLawHasItsOwnFileTests` LAS die gelöschte Datei über ein `try` hinter einem verzeichnis-weiten Skip — die Löschung wäre sonst ein hartes Rot auf korrektem Baum geworden. Ersetzt durch etwas STRENGERES: die Datei muss ABWESEND sein, und ein Lauf über `Sources/` verlangt **genau EINE** Deklaration von `enum TimelineAutomationRowMath` (die alte Form fragte nur, ob EINE benannte Datei sie nicht wiederholt — eine Zweitkopie irgendwo anders wäre durchgegangen). Der Test ist dabei umbenannt, weil sein alter Name ein Verfahren beschrieb, das der Code nicht mehr nimmt (#374).
    ⚠️ **Was sich NICHT geändert hat: Timeline-Automation ist weiter unerreichbar.** `AutomationPlayer` hat keinen Produktions-Schreiber; eine von einem älteren Build persistierte Kurve SPIELT (über `applyStep` auf jedem Transport-Schritt), aber keine Fläche kann heute eine zeichnen. #473 hat eine Ansicht entfernt, die nichts montiert hat — keine Fähigkeit.
- **P1 "Sound complete" — ALREADY BUILT (audited 2026-07-01; corrects the old "Clips/Arrangement UI not wired" note):** the melodic/DAW core is done and wired — **polyphonic synth** (`PolySynthVoice`) + **bass** (`SubBassVoice`) + ~~hybrid sample/synth drums~~ (`BeatPlayer` + `DrumSynthVoice` — **entfernt 2026-07-26, #166/#167; klingt nicht mehr**); **full patch editor + presets** (`SynthPatch`/`PatchStore` + `soundPanel`, favorites/community/save-as, live-apply, tested. ⛔ Hier stand `PatchEditorView` als der Editor „DOORLESS since 2026-07-25" — die Datei ist mit #132 Slice 6 gelöscht; der Editor war die ganze Zeit `soundPanel` hinter dem Sound-Chip); **breakbeat loop-cut** (`LoopCutter`/`LoopBarLength` in the Studio UI); **MIDI export** — **AUSGELIEFERT** (korrigiert 2026-07-28): `exportMIDI()` wird wieder aufgerufen, aus dem Export-Schacht heraus (#188 hat die Tür in den VORHANDENEN Slot zurückgeholt, kein neuer Sheet). `MIDIFileExporter` intakt und getestet. Der App-Store-Text behauptet den MIDI-Export — nicht entfernen, ohne `fastlane/metadata` mitzuziehen; Clips + Arrangement UI **DELETED** by the pure-instrument epic (#121 Slice 4 — `ClipView` 807dc0d, `ArrangeTimelineView` eb58e7a; `ClipStore`/`ArrangementStore`/`AutomationLane` model retires in Slice 5).
  **CRAFT-TOOL DOORS — the #131a craft-editor slot is GONE again (2026-07-26).** It was shipped 2026-07-25 (`f2cbf34`/`bda8f41`) to door the piano roll, and it held exactly ONE case; when the founder said *"Pianoroll soll raus"* the honest move was to take the slot with it rather than leave an undoored enum (the lying-`toolItems` trap). **Body presentation-modifier count = 14** (8 sheet + 2 cover + 3 alert + 1 fileImporter; dateiweit 16 — die zwei verschachtelten stehen im Absatz oben, und seit #479 sind BEIDE Zahlen im blockierenden Bundle festgenagelt), nachgemessen 2026-08-07 und erstmals gegen die `struct EchoelStudioView: View`-DEKLARATION verankert statt gegen die Einrückung allein. ⛔ Hier stand „alle 14 lösen auf `var body: some View` auf, kein anderes `var …: some View` trägt heute einen“ — **falsch, und widerlegt vom Absatz darüber**: `private var openSheet: some View` trägt sehr wohl einen (`.fileImporter`), und genau den nennt derselbe Absatz als verschachtelten Wirt. Wahr ist das ENGERE: kein anderes `var …: some View` trägt einen auf EINRÜCKUNG 8, also auf seiner eigenen obersten Kette. Dazu zwei fail-open-Pfade der ersten Fassung, beide im Review gefunden: der Anker nahm das erste 4-Einrückungs-`var body` DATEIWEIT (es gibt **sieben**; `EchoelStudioView` gewann nur, weil die `struct` bei :47 beginnt), und der Terminator verglich exakt auf `"    }"`, was ein `    } // …` verfehlt, weil der Kommentar-Stripper eine nachlaufende Leerstelle hinterlässt. **Beide machen die Kette KLEINER, und `<=` sieht das nicht** — deshalb steht jetzt ein Sentinel daneben, der verlangt, dass die Scheibe ihr LETZTES Kettenglied noch enthält. **Die Historie der Zahl:** the sample-browser `.sheet(item:)` went with `SampleBrowserView` (#167). It was 15 the day before — it was 16 the day before, and the "= 12" before that counted only `.sheet`+`.fullScreenCover` and read as headroom that does not exist. Alerts and the file importer sit on the same chain and carry the same metadata cost. **The NEXT editor re-introduces the slot as `enum` + `@State` + ONE `.sheet(item:)` + an out-of-body content builder — NEVER a bare appended modifier**, and a case is added ONLY together with its door. Three of the 14 slots (`showVisual`, `showMeditation`, `midiImportPresented`) have no setter at all and are the first place to look for room. `sampleBrowserTrack` was the fourth and is DELETED (2026-07-27): once `SampleBrowserView` itself went, the slot pointed at a type that no longer compiles — a slot is only reusable while its content still builds.
  · **`PianoRollView` = GELÖSCHT (#475, 2026-08-07).** Der Eintrag stand hier als „DOORLESS AND UNMOUNTED" samt der Entblockungs-Bedingung („hoisting that one pure function into a core file is what unblocks deleting the struct") — **#470 hat gehoben, #475 hat gelöscht**: **987** Zeilen `struct PianoRollView: View` plus die zwei privaten Gesten-Typen `RollDragAnchor`/`RollDrag`. Die Datei `Studio/PianoRollView.swift` BLEIBT, weil sie `PianoRollModel` enthält — die Notenmaschine UND den `MusicalFrame`-Publisher, also die Wirbelsäule der Ausgabestufe (Visual · Licht · Raum). `RollSelection` ist ebenfalls geblieben, jetzt test-only (**acht** Behauptungen in `Tests/EchoelmusicTests/NoteTests.swift`), die `WaveformReducer`-Form. ⛔ **DREI ZAHLEN DIESES EINTRAGS WAREN FALSCH, und die Reviewer-Nachlese fand INSGESAMT NEUN Falschbehauptungen in der #475-Prosa — die höchste Zahl, die eine Scheibe in dieser Kette je produziert hat.** (1) „988 Zeilen“: die `struct` läuft von 1305 bis Dateiende 2291, also **987**. (2) „neun Behauptungen“: neun ist `grep -c RollSelection`, das den Testnamen `func testRollSelection_…` mitzählt; die Behauptungen sind **acht**. (3) „2291 → 1278 Zeilen“ ist **ersatzlos GESTRICHEN statt korrigiert** — der Stand beim Löschcommit war 1325, und die Nachlese hat ihn im selben Zug wieder bewegt. **Eine Zeilenzahl einer LEBENDEN Datei ist keine Tatsache, sondern ein Datum**, und dieser Absatz trägt bereits zwei Lehren darüber; belastbar ist die GRÖSSE des Eingriffs (`git show --stat` auf den Commit: 54 Einfügungen / 1020 Löschungen, netto **−966**), weil die sich nie wieder ändert. Ebenfalls aus derselben Nachlese und schwerer als jede Zahl: die #475-Prosa erklärte `pitchCount` für aufruferlos (es hat einen Leser, `highPitch`), zitierte ZWEI grep-Rezepte, die derselbe Commit falsifizierte, und ließ einen ⚠-DORMANT-Kommentar stehen, der eine GELÖSCHTE `PianoRollView.transport` als „den einzigen Produzenten“ benannte und behauptete, die Flagge „kann nicht mehr gesetzt werden“ — während `WorkspaceView` sie auf dem ⏸-Pfad live setzt. **Das ist die teuerste Sorte: ein Vermerk, der einen lebenden Mechanismus für tot erklärt, lädt die nächste Sitzung ein, seine Invariante als Ballast zu behandeln.** **Consequence to state plainly: there is NO note editor in the app any more** — the generated take can be heard, mixed and exported, not corrected.
    ⭐ **UND DIE LÖSCHUNG HAT DREI NACHBARN VERWAIST, was keine Register-Zeile vorhergesagt hatte** (gemessen NACH dem Schneiden, die #472-Lehre): `Studio/RollHitTest.swift` und `Studio/RollFitMath.swift` haben seither **null** Produktions-Aufrufer, `Studio/RollNoteOps.swift` überlebt mit genau einem (`stableSeed`, gerufen von `PianoRollModel`). Keiner ist mitgelöscht — `RollHitTest` trägt das #470-Gesetz, das die Löschung überleben SOLLTE, und im blockierenden Bundle pinnt es `TheUnitToPeriodLawSurvivesTheViewTests`. Dessen dritte Behauptung („die Lane ruft das Gesetz noch") ist im selben Commit zurückgezogen, weil die Lane weg ist — der Wächter hatte diese Anweisung in der eigenen Fehlermeldung stehen. **Sieben `PianoRollModel`-Mitglieder sind ebenfalls aufruferlos** und im Dateikopf namentlich aufgeschrieben statt still gelöscht.
  · **`PatchEditorView.swift` IST GELÖSCHT (#132 Slice 6, 2026-07-31).** Die Vorgeschichte gehört hierher, weil sie zweimal in die falsche Richtung gelesen wurde: die Datei war seit dem Tools-Grid-Removal türlos, und meine frühere Behauptung, das Instrument könne „keinen Klang formen oder speichern", war FALSCH — `soundPanel` (an `dropdownContent` `.sound`, erreichbar über den Sound-Chip) IST der lebende Timbre-Editor und war es die ganze Zeit. Blockiert war die Löschung von fünf persistierten Parametern, deren einzige Zeile in der türlosen Datei stand; sie sind portiert (**`unisonVoices`/`unisonDetuneCents` mit #281, `spectralShape`/`noiseColor` und `outputLevel` mit #286**), jeder mit gerenderter Zeile UND Wächter im blockierenden Bundle (`Tests/CISmoke/UnisonRowDefaultsTests.swift`). Die **Preview-Tastatur** war kein Parameter, sondern eine Urteilsfrage — entschieden: die Spielfläche deckt sie ab, nicht portiert. Die **Preset-Leiste** (laden · favorisieren · speichern · Save-as · löschen · einreichen) ist da (⛔ hier stand „fehlte nie“ — in diesem SHALLOW-Klon, gepfropft auf `24e9420`, liefert `git log -S` auf die Aufrufstellen nur den Graft; die Gegenwart ist belegbar, die Vorgeschichte nicht, und genau solche unbelegten „schon immer“-Sätze streicht diese Datei an anderer Stelle selbst): `presetRow` hält alle sechs, seit `Tests/CISmoke/SoundPanelPresetBarTests.swift` auch nachweislich — und DAS ist der Grund, warum die Löschung nichts gekostet hat. ⚠️ Die `outputLevel`-Hälfte hing einen Monat an einer Begründung, die faktisch falsch war (ein Quellkommentar erklärte einen manuellen Trim für unvereinbar mit `loudnessNormalized()`; das läuft **einmal** beim Bau der `static let factory`-Liste und kann eine Nutzer-Eingabe nie überschreiben, was das Feld-Doc seit dem ersten Tag sagt). **Lehre: ein „gehört dem Founder"-Vermerk mit prüfbarer Begründung gehört geprüft, bevor er eine Aufräumarbeit blockiert.**
  · **`ImmersiveStageView` (spatial stage) stays doorless — deliberately.** Ship-gate item 4 makes light/space "demonstrable, not required for v1" (#131c).
  · **Correction to a claim I made about the roll:** presenting it is NOT what publishes `MusicalFrame`. That publish is in `PianoRollModel`'s tick handler (`PianoRollView.swift`) on the shared sequencer tick, installed once at app start (`pianoRoll.start(...)` in `EchoelmusicApp`) — so the visual/light output stage is lit whether or not the roll is open. The door is load-bearing for EDITING, not for the spine.
  · **NEEDS-FOUNDER-VERIFY:** launch (the +1 modifier vs the black-screen law). ⛔ Die zweite Hälfte — „and the roll's Stop, which cascades the ONE-Stop law … and ends the whole bio session" — ist **HINFÄLLIG**: dieser Knopf saß in der `PianoRollView`-`struct`, die #475 gelöscht hat. Ein Verify-Posten, der auf ein entferntes Bedienelement zeigt, kostet den Founder eine Geräteprobe, die nichts entscheiden kann. Der ÜBERLEBENDE Produzent des Playback-only-Stopps ist das Transport-■ in `WorkspaceView` (`pianoRoll.requestPlaybackOnlyStop()`, #179), und den pinnt `OneStartControlTests.testThePlaybackOnlyStopHasAReachableProducer` im blockierenden Bundle.
  Music theory is fully in-house. The real remaining frontier is **P3 Video** (⛔ korrigiert 2026-07-31: „no recorder/trim/export yet" war falsch für zwei Drittel — RECORDER und EXPORT existieren und sind erreichbar, `VisualRecorder` + `FloatingVisualWindow`s Aufnahmetaste + `videoPanel` → `VideoLibraryPanelContent` mit mp4-Share. Was fehlt, ist der TRIM/SCHNITT, mit #121 Slice 3 absichtlich entfernt) and **P4 Broadcast**. See `scratchpads/PLAN_REDOOR_CRAFT_TOOLS_2026-07-25.md`.
- **Files:** **348** Swift under `Sources/` (`git ls-files 'Sources/**/*.swift' | wc -l`, 2026-08-07 nach der #490-LÖSCHUNG von `Studio/HeaderSpectrumStrip.swift` (die 180-Zeilen-Farbbalken aus dem Marken-Header, die der Founder mit #384 selbst bestellt und mit dem 2026-08-07-Screenshot wieder gestrichen hat: *„die bunten Balken weg stattdessen die einzeigen für die Loop Länge und der Balken"*. **Löschbar war sie, weil sie eine ZWEITKOPIE war und keine Fähigkeit** — `AnalysisSpectrumView` trägt dieselbe Messung im Instrument, und vor dem Schneiden ist jeder Kollaborateur einzeln nachgezählt worden (`EchoelRealFFT`, `SpectrumAnalysis.bands`, `SpectralColor.visibleColor`, `AudioEngine.copyLatestOutputSamples`, `SpectrumAnalysis.centerFrequency`): **null Verwaiste**. ⭐ Und das ist die ZWEITE ersatzlose Löschung dieser Kette und die erste, die einen Wächter MITNIMMT — `Tests/CISmoke/HeaderSpectrumIsALeafTests.swift` ist im selben Commit gelöscht, weil sein ganzes Subjekt weg ist. **Damit steht die CISmoke-Zahl unverändert auf 203, obwohl der Commit eine Datei löscht und eine anlegt** — die #374-Lehre wörtlich: *eine unveränderte Zahl ist kein Beleg dafür, dass sich nichts geändert hat.* Wer die zwei Zahlen dieses Eintrags nebeneinanderlegt, sieht −1 bei `Sources/` und ±0 bei `Tests/CISmoke`, und nur die erste ist eine Bewegung, die man sehen KANN.), davor **349** nach `Studio/EchoelIconTile.swift` (#482 — EINE Datei, deren neuer Typ KEIN reiner Rechen-Kern ist, sondern eine ANSICHT. ⛔ Hier stand „die erste dieser Kette seit Wochen" — falsch, und ungezählt hingeschrieben, weil es sich rund anhörte: `Studio/AnalysisWavefrontView.swift` (#385, Stand 342) und `Studio/HeaderSpectrumStrip.swift` (#384, Stand 340) sind beide Ansichten und beide vom **2026-08-02**, also FÜNF TAGE davor und beide in dieser Kette. Dieselbe Klasse wie „seit SIEBEN Ständen" und „ZEHN/elf" zwei Absätze weiter unten, im Absatz, dessen einziger Zweck das Mitzählen ist: das eine geteilte Knopf-Format, das der Founder wörtlich verlangt hat („die Größe der Buttons anpassen, die sollen immer gleichgroß sein"). Sie zählt trotzdem +1 und nicht +2, weil sie KEINE Fläche aufmacht — sie ersetzt an sechs Aufrufstellen handgezeichnete Chrome durch einen Aufruf. ⭐ Und die LEHRE ist der Gegenfall zur Zeile direkt daneben: der Stand davor war eine ersatzlose LÖSCHUNG, dieser eine EXTRAKTION aus vorhandenen Rümpfen — zwei Vorgänge, die die Zahl in verschiedene Richtungen um eins bewegen. Wer aus zwei aufeinanderfolgenden Ständen eine Richtung ableitet, leitet aus zwei verschiedenen Vorgängen dieselbe Zahl ab. ⛔ **UND DIE #482-BENOTUNG WAR DIE #433-KLASSE, schon wieder:** der Commit-Text nannte „zwei neue Behauptungen — die Reihenfolge im Tile und ein GEGENGEWICHT" und ließ damit die erste als Regression lesen. Sie treibt einen Typ, den DERSELBE Commit anlegt — sie konnte nie rot sein. Von den sieben angefassten Behauptungen ist **KEINE** eine Regression: vier sind Pins auf neuen Code, zwei Gegengewichte, eine ein Anker-Umzug. Die #482-Nachlese (dieser Commit) fügt die EINE echte Lücke hinzu, die der Reviewer fand — `.contentShape(Rectangle())` im Tile, ohne die fünf `.plain`-Buttons auf ~38×32 zurückfallen, während alles grün bleibt.), davor **348** nach der #473-LÖSCHUNG von `Studio/TimelineAutomationRow.swift` — **die erste MINUS-Bewegung dieser Kette seit 334→333**, und sie ist der Gegenfall zu allem darunter: die sieben Stände davor sind neue oder umgezogene KERNE, das hier ist eine ersatzlose Entfernung. Wer aus der Serie „+1 pro Zyklus“ ableitet, hätte hier 350 erwartet und liegt um zwei daneben — **man zählt weiter, statt zu extrapolieren**, was dieser Absatz schon dreimal sagt und was hier zum ersten Mal in die andere Richtung zutrifft. ⛔ Und diese Zeile stand einen Entwurf lang auf „seit SIEBEN Ständen“, ungezählt hingeschrieben, weil es sich rund anhörte — in dem Absatz, dessen einziger Zweck das Mitzählen ist. Nachgezählt: zwischen 333 und 349 liegen dreizehn Stände. Ersetzt durch die NENNUNG des letzten Rückgangs statt einer Ordnungszahl, denn eine Ordnungszahl altert bei jedem weiteren Eintrag und ein benannter Übergang nie. ⚠️ **ACHTUNG beim Nachzählen: seit #490 steht „348“ DREIMAL und „349“ ZWEIMAL** — „348“ als aktueller Stand (#490), als Historien-Eintrag nach der #473-Löschung UND nach `Bio/RRAdjacency.swift` (#425); „349“ nach `Studio/EchoelIconTile.swift` (#482) UND nach `Sequencer/TimelineAutomationRowMath.swift` (#472). ⛔ Diese Warnung stand einen Stand lang auf „seit #482 … je ZWEIMAL“ und war beim Voranstellen der #490-Zahl still falsch geworden — **eine Warnung über Doppelungen ist selbst eine Zahl und altert genauso**. Dieselbe Doppelung wie bei „333“ und „336“, und aus demselben Grund: die Zahl allein belegt nichts, es sind nie dieselben Dateien. Vorher **349** nach `Sequencer/TimelineAutomationRowMath.swift` (#472 — EINE Datei, reiner Kern ohne eigene Ansicht, die SIEBTE hintereinander, und die erste, die aus der Reihe fällt, ohne die Zahl zu ändern: die sechs davor waren NEUE Kerne, das hier ist eine EXTRAKTION. Der Zeilenbestand des Repos wächst also kaum — es zieht Vorhandenes um. Wer aus dieser Serie „+1 pro Zyklus“ ableitet, leitet aus zwei verschiedenen Vorgängen dieselbe Zahl ab; man zählt weiter, statt zu extrapolieren. ⭐ Und die LEHRE dieser Scheibe steht nicht in der Zahl: der Hoist war als Entblockung der Ansichts-Löschung registriert, und beim Grepen NACH dem Ausführen kam ein zweiter Blocker zum Vorschein, den die Register-Zeile nicht kannte — FÜNF Quelldateien zitieren die türlose Ansicht in Prosa, zwei davon tragend für `EchoelValueField`. **Eine registrierte Entblockung ist erst dann eine, wenn man nach dem Ausführen noch einmal grept.**), davor „348“ nach `Bio/RRAdjacency.swift` (#425 — WIEDER EINE Datei, reiner Kern ohne eigene Ansicht, die SECHSTE hintereinander. Der Absatz sagt an drei Stellen, dass die Serie nichts vorhersagt; sie folgt weiter daraus, dass diese Scheiben Arithmetik sind. Was DIESE von den fünf davor unterscheidet, gehört hierher, weil es eine LEHRE ist: der Kern durfte den vorhandenen Nachbarn (`RRIntervalHygiene`) NICHT wiederverwenden, obwohl der genau diese Runs schon liefert. Er liefert sie als NEBENPRODUKT einer AKZEPTANZ-Entscheidung (Band + Malik-20-%-Schritt, gurt-getunt) — und `CameraAnalyzer` hat diese Entscheidung längst getroffen, zweimal, mit eigenen Regeln, und dabei beide Male VERDICHTET. Ihn darüberlaufen zu lassen hätte eine DRITTE Akzeptanzpolitik auf eine Reihe angewandt, deren Nachbarschaft schon zerstört war. Die Nachbarschaft ist stattdessen aus `beatTimes` ABGELEITET, das der Analyzer seit #343 ohnehin 1:1 mitführt — es ändert damit KEINE Akzeptanzentscheidung. **Wiederverwenden ist die Regel, aber ein Typ, der die richtige DATENFORM zurückgibt, ist noch nicht der richtige Typ** — was er nebenbei entscheidet, reist mit. ⛔ **Und der Halbsatz „und die Verfügbarkeit kann nicht sinken", der hier stand, war FALSCH — in drei Dateien gleichzeitig (hier, im Testkopf, im Commit-Text).** Er gilt für AKZEPTANZ-Entscheidungen und nicht für die veröffentlichten ZAHLEN, und das ist die Hälfte, die einen Leser interessiert: `pnn50(segments:)` liefert 0, wo der flache Lauf einen Prozentsatz lieferte, und `rmssd` fällt auf einem Fenster mit lauter isolierten Intervallen auf 0, wo der flache Lauf immer etwas ausgab. Dieser Rückgang IST die Korrektur — die alte Zahl war ein Artefakt der Verdichtung —, aber „kann nicht sinken" behauptete ein Gratis-Mittagessen, während der `calculateRMSSD`-Doc-Kommentar DESSELBEN Commits den Rückgang ausführlich beschrieb. **Eine Scheibe darf nicht zugleich eine Behauptung und ihre Widerlegung enthalten.** ⭐ Und die Nachlese fand die eigentliche Lehre eine Ebene höher: das Halten, das die erste Fassung als `guard value > 0` einbaute, lebte NOCH ZWEIMAL als Mindest-Stichproben-Tor (`if rrIntervals.count >= 3 { calculateRMSSD() }` an beiden Veröffentlichungsstellen, plus `guard rrIntervals.count >= 2` im Rumpf). **Ein Mindest-Stichproben-Tor, dessen Fehlschlag-Zweig `return` ist, IST ein Halt** — die Arrays werden erneuert, `rmssd` nicht, und der nächste Frame trägt ein abgestandenes `hrvRMSSDms > 0` neben einem frisch gerechneten `hrvPNN50 == 0`, womit das OSC-Tor (`OSCSender` koppelt pNN50 an RMSSD, nicht an den eigenen Wert) ein erfundenes „echte 0 %" an eine fremde Lichtkonsole schickt. Alle drei sind weg; die Mindest-Entscheidung gehört `HRVMetrics` und lautet dort `pairs > 0`, was `pnn50(segments:)` ohnehin benutzt — damit werden beide Metriken im selben Augenblick unverfügbar, per Konstruktion statt per zwei zufällig gleicher Literale), davor „347" nach `Sequencer/BreathHold.swift` (#434 — WIEDER EINE Datei, reiner Kern ohne eigene Ansicht, die FÜNFTE hintereinander; die Serie sagt weiterhin nichts vorher, sie folgt daraus, dass diese Scheiben Arithmetik sind. Was diese Scheibe von den vier davor unterscheidet, gehört hierher, weil es eine LEHRE ist und keine Zahl: der Kern war fertig, gemessen und mit acht Tests belegt — und tat auf seinem Hauptfall NICHTS, weil er auf `frame.timestamp` gelesen wurde statt auf der Uhr. Ein Frame-Stempel steht genau dann still, wenn eine Ausblendung gebraucht wird (`CameraRPPGBioPublisher` wiederholt beim Puls-Halten mit `held.timestamp`, `usableBio()` hält den eingefrorenen Frame gegen die WANDUHR am Leben). **Keiner der acht Verhaltenstests konnte das sehen, weil alle die Zeit synthetisch vorwärts trugen** — gefunden hat es ein Reviewer, bestätigt an einem Quellkommentar, der die Falle selbst benennt. Zwei Uhren in einem Signalpfad sind kein Detail, und ein Test, der beide aus derselben Variable speist, prüft keine davon), davor „346" nach `Bio/PerformerSignature.swift` (#403 Slice 1 — WIEDER EINE Datei, reiner Kern ohne eigene Ansicht, und damit die VIERTE hintereinander. Der Absatz sagt eine Zeile weiter, dass drei keine Regel sind; vier sind es auch nicht — sie folgen daraus, dass diese Scheiben Arithmetik und Persistenz waren, nicht Fläche. Die Tür ist hier nicht einmal eine Zeile in einem Panel, sondern eine Faltung INNERHALB einer schon vorhandenen Methode (`makeComposerInput`), also die kleinste mögliche), davor „345" nach `Sequencer/TakeDistance.swift` (#403 Slice 0 — EINE Datei, reiner Kern ohne eigene Ansicht, wie #398 und #400. Drei Ein-Datei-Scheiben hintereinander sind jetzt eine Serie und trotzdem KEINE Regel: sie folgen daraus, dass die letzten drei Scheiben Arithmetik waren, nicht Fläche. Die nächste Scheibe, die etwas ZEIGT, ist wieder +2), davor „344" nach `Core/SoundReset.swift` (#400 - wieder EINE Datei, reiner Kern ohne eigene Ansicht, wie #398: die Tür ist eine Zeile in einem SCHON vorhandenen Panel („Save & Export“), keine neue Fläche. Zwei Ein-Datei-Scheiben hintereinander machen daraus trotzdem keine Regel — die #385-Scheibe zwei Einträge weiter war +2), davor „343" nach `Core/RegenSchedule.swift` (#398 — EINE Datei, reiner Kern ohne eigene Ansicht: die Arithmetik zog aus einer View-Methode aus, es entstand keine zweite Fläche. Der Gegenfall zu den #347/#385-Scheiben direkt daneben, und der Grund, warum „+1 oder +2" nichts ist, das man aus dem Muster ableiten kann — man zählt), davor „342" nach `Studio/WavefrontField.swift` + `Studio/AnalysisWavefrontView.swift` (#385 — ZWEI Dateien, Kern plus Ansicht, wie jede #347-Scheibe; genau der Fall, den Slice 2 dort mit nur +1 verbucht hat), davor „340" nach `Studio/HeaderSpectrumStrip.swift` (#384) — ⚠️ und dieser Stand wurde NACH dem `git add` gemessen: der Befehl listet nur getrackte Dateien, eine frisch angelegte zählt er erst nach dem Stagen. Wer vor dem Stagen misst, trägt die Zahl von gestern ein und merkt es nicht. Davor „339" nach `Studio/AnalysisPoincareView.swift` (#347 Slice 3b), davor „338" nach `Bio/PoincareMetrics.swift` (#347 Slice 3a), davor **„337"** nach `Studio/SpectrumReadout.swift` + `Studio/AnalysisSpectrumView.swift` (#347 Slice 2). ⛔ **Und an dieser Stelle stand „336", gemessen falsch:** `git ls-tree -r --name-only 23ee416 Sources | grep -c '\.swift$'` sagt 337. Beide #347-Slices haben je ZWEI Dateien angelegt (Kern + Ansicht); Slice 1 wurde korrekt mit +2 verbucht (333→335), Slice 2 mit nur +1. Der Fehler ist NICHT das übliche Vergessen des Nachführens — die Zeile wurde im selben Commit angefasst, nur um eins zu niedrig. **Lehre für diesen Absatz, der schon zwei andere Zähl-Lehren trägt: beim Nachführen zählt der Befehl, nicht die Erinnerung an „ich habe eine Datei angelegt".** Davor „335" nach `Studio/ScopeTrigger.swift` + `Studio/AnalysisScopeView.swift` (#347 Slice 1), „333" nach der #132-Slice-6-Löschung von `Studio/PatchEditorView.swift`, am 2026-07-31 früher „334" (nach `Studio/VisualEnergy.swift`, #228), „333" (nach der #167-Löschung der drei Drum-Dateien), „336" (nach `DSP/ExpressionLevelTrim.swift`) und „335", davor „333" (30.), „331" (29.), „330" am selben Tag, „326" (28.), „323" am selben Tag; SECHSUNDZWANZIG Stände in elf Tagen — 348·349·348·349·348·347·346·345·344·343·342·340·339·338·337·335·333·334·333·336·335·333·331·330·326·323 (⛔ die Spanne stand auf „neun Tagen" und war schon vor dieser Zeile falsch: der älteste genannte Stand ist der 2026-07-28, der jüngste war der 08-06 — das sind zehn Tage, nicht neun. Mit dem 08-07-Stand elf. **Die Spanne ist eine ZWEITE Zahl in diesem Satz und altert genauso wie die erste**; der CISmoke-Absatz weiter unten hat seine mitgeführt, dieser nicht), und ACHTUNG beim Nachzählen: „336" steht in dieser Zeile jetzt ZWEIMAL für zwei verschiedene Dinge — einmal als echter Stand vom 2026-07-31 (nach `DSP/ExpressionLevelTrim.swift`) und einmal in der ⛔-Notiz oben als die FALSCH eingetragene Zahl, die nie ein Stand war. Nur der erste zählt (⛔ und beim Nachführen auf diesen Stand stand hier ZEHN, während elf Zahlen dastanden — schon wieder das Zahlwort, schon wieder in dem Absatz, dessen einziger Zweck das Mitzählen ist. Der Fehler ist nicht Nachlässigkeit, sondern ein Muster: wer eine Zahl vorne einfügt, liest das Zahlwort als Prosa und nicht als eine zweite Zahl, die er gerade ungültig gemacht hat) (der AKTUELLE Wert ist hier mitgezählt — der CISmoke-Absatz weiter unten zählt umgekehrt nur die HISTORIE, also einen weniger als es Stände gibt; zwei Absätze, zwei Konventionen, beide für sich korrekt, aber wer sie vergleicht, muss das wissen), alle einmal als Beleg zitiert (⛔ die erste Fassung dieser Zeile schrieb „NEUN" und listete acht — in genau dem Absatz, dessen einziger Zweck das Mitzählen ist. Zähl die Zahlen, nicht das vorige Zahlwort +1). Dass „333" hier zum DRITTEN Mal steht — einmal als aktueller Wert, zweimal in der Historie — ohne dass es je dieselben Dateien sind, ist der Beweis, dass die Zahl allein nichts belegt. Das Zahlwort MITZÄHLEN ist Teil des Nachführens — der CISmoke-Absatz weiter unten hat genau daran schon einmal veraltet. **Schreib hier nie eine Zahl hin, ohne den Befehl danebenzustellen**, und lies sie nie ohne ihn nachzuführen), **ZERO Metal files** — corrected 2026-07-25; the old "~212 Swift + 1 Metal (`Video/Shaders/ChromaKey.metal`)" was stale twice over: the count was long out of date and `ChromaKey.metal` was DELETED by Slice 3 (video-cut removal) together with its directory. `MetalBioView` compiles its shader inline at runtime, so the app ships no `.metal` source at all. | **Swift 100%** | top-level dirs under `Sources/Echoelmusic/`: `Audio Bio Core DSP EchoelAI Resources Sequencer Stream Studio Sync Tools Video Views`, plus the two loose top-level files `EchoelmusicApp.swift` and `MicrophoneManager.swift`. NOTE: the "four pillars" (EchoelTools/Works/Sync/Well) referenced by older vision docs were **never built as modules** — `EngineBus` is the one real coupling spine; `Views/` now holds only `MetalBioView` + `OnboardingView` (its long deprecated list is gone).

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
  EchoelDDSP (reused as synth voice) · EchoelCellular (⛔ NICHT „reused as FX texture" —
    gemessen 2026-08-07: `git grep -ln EchoelCellular -- Sources Tests` liefert die eigene
    Datei plus ZWEI Testdateien und sonst nichts. Es ist test-only, dieselbe Lage wie
    `EchoelModalBank` weiter unten. Behalten, aber nicht als klingende Stufe zitieren.)
```

Deprecated from main flow: the old SoundscapeEngine, ClipEngine, MomentCaptureView,
  BioSourceManager, Oura/EEG bridges, WeatherProvider, CircadianClock files have all
  been REMOVED in cleanup (2026-06-19 audit) — they no longer exist. (HealthKit + rPPG
  are now LIVE, not deprecated.) The genuinely app-unwired pure cores remaining are
  BioModulation and CloudSync. NOW WIRED — do NOT list these as unwired: BioVisualParams
  (read by EchoelBioEngine + MetalBioView), FeedbackGuard (AudioEngine duck loop + the
  masterDoorButton „Audio input" door), LearnLibrary (LearnView), EchoelFXView (doored via
  `showAllFX`). ⛔ **VocoderCore stand hier als „NOW WIRED" mit dem Zusatz „whether THAT chain
  reaches a door is unverified, so do not claim either way" — die offene Frage ist am
  2026-08-07 BEANTWORTET, und die Antwort ist NEIN.** Die Kette terminiert nach einem Schritt:
  `git grep -ln VocoderCore -- Sources` findet `Core/BrainwaveModulation.swift` und
  `Studio/VoiceAnalyzer.swift`; beide Verbraucher haben SELBST null Verbraucher
  (`git grep -n VoiceAnalyzer -- Sources` außerhalb der eigenen Datei = **0 Treffer**, ebenso
  `BrainwaveModulation`). Drei Dateien, die sich gegenseitig lesen und die kein vierter liest.
  Also gehört VocoderCore in die Zeile darüber zu BioModulation/CloudSync — reiner,
  getesteter Kern OHNE App-Pfad —, nicht in die „NOW WIRED"-Liste. **Lehre, und sie ist die
  Umkehrung der üblichen in dieser Datei: ein „unverifiziert, behaupte nichts"-Vermerk ist
  ehrlich, aber er bleibt für immer stehen, wenn niemand die zwei `grep`s macht, die ihn
  auflösen.**

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
- `PianoRollView` is DELETED (#475, 2026-08-07) — the chip, the `craftEditor` slot and its
  content builder went 2026-07-26 on the founder's "Pianoroll soll raus"; the 987-line struct
  itself followed. This paragraph flipped twice while the view existed, so the flip-checking
  advice stood here for good reason — it no longer applies, there is nothing left to re-door
  without writing it. `PianoRollModel` in the same file is untouched and load-bearing.
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
| **iPad** | **vier Einstellungen + ein Wächter, in EINEM Commit** (`TARGETED_DEVICE_FAMILY` an App · Widget · beiden Test-Bundles, dazu `Tests/CISmoke/DeviceFamilyIsPhoneOnlyTests.swift` — harte Gleichheit im BLOCKIERENDEN Bundle — **plus zwei Prosa-Blöcke**, die beim Ändern falsch werden: der `#`-Block über der Einstellung und die ⛔-Notiz unter dieser Tabelle) | eine dort funktionierende Bio-Quelle — kein iPad hat eine rückseitige LED, und `CameraCapture` koppelt die rPPG-Beleuchtung an `device.hasTorch`; der BLE-Gurt ist gebaut+verdrahtet, die Watch käme als zweite Quelle infrage — **plus** #292 (heute reflowen **4 von 10** Panels; Befehl siehe die Zeile „Kein ‚nie'" unter dieser Tabelle. ⛔ Diese Zelle stand auf „2 von 11", während die Zeile „Kein ‚nie'" schon „2 von 10" sagte — DIESELBE Tatsache, zwei Zahlen, 12 Zeilen auseinander, weil #359 Schritt 3 nur die untere nachführte. Der Absatz unter dieser Tabelle trägt fünf Lehren über seine eigenen Zählfehler und keine davon lautete „such nach der ZWEITEN Stelle"; sie lautet jetzt so) |
| **Vision / XR** | kein Target; `visionOS` kommt in `Sources/` nur in Plattform-Guards vor (`MicrophoneManager`, `AudioInputManager`, `SPSCQueue`, `MemoryPressureHandler`) | der natürliche Sitz ist die **Ausgabe-Stufe, die schon existiert**: `ImmersiveStageView` (türlos, absichtlich — Ship-Gate 4 sagt „demonstrierbar, nicht erforderlich"), ADM-OSC-Raum, das Visual. Bio-Quelle bliebe Telefon oder Gurt |
| **Mac** | kein Target, kein Catalyst-Flag | offen |

⛔ **Was hier bis 2026-07-31 stand, war doppelt irreführend, und die zweite Fassung desselben Tages auch.** Erst: „iPhone-only for v10 MVP. iPad / Mac / Watch / Vision deferred to v1.1+" — während `project.yml` an ALLEN VIER iOS-Targets `TARGETED_DEVICE_FAMILY: "1,2"` setzte, die App also an iPad ausgeliefert wurde. Niemand hatte das entschieden; es war ein Default, den niemand nachgelesen hat. Dann, nach der Korrektur auf `"1"` (#292), las sich der Absatz wie ein **Ausschluss** von iPad/Vision — genau falsch herum, wie der Founder Stunden später klarstellte. Die Entscheidung (v1.0 = iPhone) steht; ihre BEGRÜNDUNG ist Sequenzierung und der fehlende Sensor auf iPad, nicht ein Verzicht auf das Ökosystem.

⛔ **Und die iPad-Zeile trug bis zur Reviewer-Nachlese am selben Tag einen Slogan, der in VIER Dateien gleichzeitig stand und in jeder falsch war:** „Wiederanschalten ist EINE Zeile" (hier, in `project.yml`, im Commit-Text und in `decisions.csv`) — während der Wächter, den **derselbe Commit** installierte, wörtlich sagt „change the settings AND this test in the same commit". Zwei Sätze aus einem Changeset, die einander widersprechen; der eingängigere war der falsche. Es sind vier Einstellungen plus der Wächter plus zwei Prosa-Blöcke, die beim Ändern falsch werden. **Lehre, weil sie sich von der üblichen unterscheidet:** hier war nicht eine Zahl veraltet, sondern eine Behauptung wurde nie geprüft, weil sie gut klang und niemandem wehtat — und sie ist genau der Satz, aus dem eine künftige iPad-Rückkehr ihren Aufwand schätzt. Ein Slogan, der Arbeit KLEINER macht als sie ist, ist gefährlicher als eine falsche Zahl.

⛔ **Dieser Satz war bis 2026-07-31 eine BEHAUPTUNG, kein Zustand** — und er stand hier, während `project.yml` an ALLEN VIER iOS-Targets `TARGETED_DEVICE_FAMILY: "1,2"` setzte, die App also an iPad ausgeliefert wurde. Niemand hatte das entschieden; es war ein Default, den niemand nachgelesen hat. Founder-Frage („Sind alle Fenster adaptiv für alle Geräte?") plus Delegation („Du entscheidest zukunftsweisend") → jetzt wirklich `"1"` (#292), abgesichert durch `Tests/CISmoke/DeviceFamilyIsPhoneOnlyTests.swift`.

**Der entscheidende Grund ist der SENSOR, nicht das Layout, und er gehört hierher, weil aus dieser Zeile heraus über Plattformen geplant wird:** `CameraCapture` koppelt die rPPG-Beleuchtung an `device.hasTorch`, und kein iPad hat eine rückseitige LED. Auf iPad läuft der Finger-auf-Linse-Puls also ohne Licht — genau die Bedingung, die der 2026-06-18-Fix als Ursache fürs Nicht-Locken identifiziert hat. Ein iPad-Build stellt die eigene Prämisse („Dein Körper spielt es") auf ein Gerät, auf dem die Hauptquelle degradiert ist.

**Kein „nie".** Die großen Flächen sind die Zukunft als **AUSGABE** — externer Bildschirm/Beamer (#206), ADM-OSC-Raum —, nicht als zweite App-Oberfläche. Kommt iPad als Instrumenten-Fläche zurück, braucht es eine dort funktionierende Bio-Quelle (der BLE-Gurt ist gebaut und verdrahtet) plus den Adaptivitäts-Durchgang #292. **Der Durchgang passiert ohnehin:** iPhone allein spannt 375–440 pt, erlaubt Querformat und läuft mit ungedeckeltem Dynamic Type — heute reflowen **4 von 10** Panels: `mixerPanel`, `soundPanel` (mit sieben Gittern), seit #292 Slice 3 `moodPanel` (mit zwei) und seit #292 Slice 4 `visualPanel` (mit zwei). Die anderen sechs — `menuPanelHost`, `bioPanel`, `videoPanel`, `tempoToolsPanel`, `masterPanel`, `effectsPanel` — stapeln weiter starr. ⚠️ **`visualPanel` ist der erste Eintrag dieser Liste, der seine Gitter NICHT im eigenen Rumpf hat**, und das ist genau die Falle, vor der der ⛔-Absatz unter diesem warnt: sie sitzen in `visualAdjustFields(spacing:)`, das der Rumpf aufruft. Wer die Liste per `grep` über Panel-Rümpfe nachführt, findet `visualPanel` nicht — man folgt dem AUFRUFER, sonst zählt man es beim nächsten Mal wieder als starr. ⭐ Und Slice 4 hat als erste eine Fläche mitgenommen, die gar kein Panel ist: `visualVJOverlay` rendert dieselbe Definition und reflowt seither ebenfalls — es steht bewusst nicht im Zähler, weil der Nenner Panels zählt, aber es ist der Grund, warum `spacing` dort ein ARGUMENT ist (14 im Panel, 8 im Overlay; in einer Spalte ERSETZT das Gitter den Abstand des Wirts, ein Literal hätte also eine der beiden Flächen im Hochformat still umgesetzt). Wächter: `Tests/CISmoke/VisualFineTuneReflowsTests.swift`. (Der Nenner war bis #359 Schritt 3 elf; `sessionPanel` ist mit diesem Schritt gelöscht, sein einziger Inhalt `placeRow` sitzt jetzt in „Save & Export". Zähl mit `grep -c "private var \w*Panel\w*: some View"`, nicht aus dem Kopf — genau diese Zeile trägt vier Absätze über ihre eigenen Zählfehler. ⚠️ Und der Befehl misst die NAMENSFORM, nicht die Sache: er zählt `menuPanelHost` mit, das der Wirt ist und kein Panel, und übersieht `utilityRow`, das eines der Dropdown-Panels IST und nicht reflowt. Die zehn stimmen als Zahl, die MENGE ist um je einen daneben — wer die Panels einzeln durchgeht, muss beide Abweichungen kennen.)

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
  DSP/                 ← EchoelDDSP, EchoelVDSPKit (KEEP, reused as synth voices).
                          ⛔ `EchoelCellular` stand hier mit im „reused"-Satz und ist es NICHT
                          (gemessen 2026-08-07: eigene Datei + 2 Testdateien, null Produktion) —
                          siehe die korrigierte Zeile in der Audio-Foundation-Liste oben.
                       ← EchoelModalBank — ⛔ TEST-ONLY seit #167 (2026-07-31): sein einziger
                          Instanziierer war `DrumSynthVoice`. ~800 Zeilen DSP ohne
                          Produktionspfad. Nicht gelöscht (Founder sagte „erstmal"), aber auch
                          nicht als lebende Stimme zitieren.
                          ⛔ **DAS REZEPT, DAS HIER STAND, IST ABGELAUFEN, und es ist die Sorte
                          Ablauf, die diese Datei sonst nur bei Zahlen kennt.** Es lautete
                          „`git grep -l EchoelModalBank -- Sources` liefert heute NUR die eigene
                          Datei" — am 2026-08-07 liefert derselbe Befehl **DREI**
                          (`LaneVoiceRack.swift`, `TakeDistance.swift`). Beide Zusatztreffer sind
                          KOMMENTARE: der eine erklärt, warum ein Wächter seine Begründung
                          verloren hat, der andere zitiert genau diesen CLAUDE.md-Absatz als
                          Warnung. **Die SCHLUSSFOLGERUNG überlebt** (null Instanziierer, null
                          Produktionspfad), das REZEPT nicht — und ein Rezept, das man ausführt
                          und das „3" sagt, wo die Prosa „1" verspricht, wird als Widerspruch
                          gelesen, nicht als veraltete Formulierung. Der Befehl, der die Sache
                          wirklich misst, ist der auf die BENUTZUNG:
                          `git grep -n "EchoelModalBank(" -- Sources` → 0.
                          **Lehre: ein Vermerk, der ein `grep` ZITIERT, altert schneller als
                          einer, der eine Tatsache behauptet — weil jeder Kommentar, den man
                          über die Sache schreibt, den eigenen Beleg verfälscht.**
  Sync/                ← OSCSender, ADMOSCSender, Art-Net/sACN (EchoelLux), CloudSync
  Tools/               ← PolySynthVoice, SubBassVoice, breath/vocal tools
  Views/               ← MetalBioView + OnboardingView ONLY (the old deprecated-view list is deleted)
Tests/EchoelmusicTests/ ← **314** test files (`git ls-files 'Tests/EchoelmusicTests/*.swift' | wc -l`,
                          2026-08-07 nach `MIDIFileExporterTests.swift` (#469 — die **22**
                          MIDI-Export-Tests, die in keinem Target standen und nie gelaufen sind.
                          ⛔ Hier stand „24", und diese Zahl stammt aus #469s eigener
                          Commit-Betreffzeile — sie war NIE eine Zählung: `grep -c "func test"`
                          liefert 22, und auf `6a8deb8` selbst auch 22, denn #469 war ein reiner
                          `git mv` mit null Einfügungen. Beim Reparieren des erfundenen
                          Dateinamens ist die falsche ZAHL unangetastet mitgereist, in genau dem
                          Satz, der „ein Name ist genauso ein `git ls-files` wert wie eine Zahl"
                          festhält.).
                          ⛔ **Hier stand `MIDIFileExporterDrumTests.swift`, eine Datei, die es
                          NIE gegeben hat** — #469 hat `Tests/EchoelmusicCoreTests/MIDIFileExporterTests.swift`
                          VERSCHOBEN, nicht eine neue angelegt. Gefunden bei #474, als der
                          Befehl `ls Tests/EchoelmusicTests | grep -i midi` den Namen nicht
                          lieferte. **Die ZAHL war richtig und der NAME erfunden**, und das ist
                          die Sorte, die dieser Absatz sonst nicht kennt: seine ganze Disziplin
                          zielt auf veraltete Zahlen, während der Name daneben ungeprüft
                          durchläuft. Ein Name ist genauso ein `git ls-files` wert wie eine Zahl.
                          ⛔ Hier stand „313", ein Stand vom 2026-07-31, und der Commit, der die
                          Datei anlegte, hat DIESE Zeile nicht nachgeführt — derselbe Fehler, den
                          der Sources-Absatz oben dreiundzwanzigmal protokolliert, nur in der Suite,
                          die niemand blockiert und deshalb niemand nachzählt. ⛔ Drei Zahlen
                          kursierten für DIESE eine Suite: 305 hier, 294 in den Schrittnamen von
                          `full-tests.yml`, 311 auf der Platte am 2026-07-28 — dann 314, dann 313.
                          Die Workflow-Beschriftung ist founder-gated und bleibt vorerst falsch (#208).
                          Und die Suite ist NICHT das blockierende Bundle — das baut aus
                          `Tests/CISmoke` (**206** Dateien, `git ls-files 'Tests/CISmoke/*.swift' | wc -l`,
                          2026-08-08 nach `TheToneSystemTravelsWithTheTakeTests.swift` (#493 — der erste
                          Wächter in dieser Kette über einer PERSISTIERTEN Lücke statt über einer Zahl,
                          einer Größe oder einer Zeichenkette, und der erste, dessen Defekt eine
                          ASYMMETRIE zwischen zwei Achsen DERSELBEN Entscheidung war. `Project`
                          speichert `a4Hz` seit es dieses Format gibt; das TONSYSTEM — die Cent-Tabelle,
                          die einen Take zu Maqām Rāst statt 12-TET macht — lebte nur in
                          `@AppStorage("toneSystemID")`, also im INSTRUMENT und nie in der Datei. Einen
                          Rāst-Loop speichern, das Instrument auf 12-TET stellen, den Loop öffnen: 12-TET.
                          Und `open(_:)` endet auf `applyTuning()`, das die GLOBALE Tabelle
                          gewissenhaft an jede Stimme schiebt.
                          ⭐ **Das ist #312/#338 auf einer anderen Straße.** Jene zwei haben dasselbe
                          „zwei Stimmungen gleichzeitig" INNERHALB einer Sitzung geschlossen (erst der
                          Sub, dann `bioVoice` + `LaneVoiceRack`). #338 ist in v10.79.374 ausgeliefert,
                          und meine eigene Deploy-Notiz dazu bittet den Founder, Maqām und dann A4 zu
                          probieren — er steht also unmittelbar vor genau der Asymmetrie, die diese
                          Scheibe entfernt: einer der beiden Regler klebt am gespeicherten Take, der
                          andere nicht.
                          ⭐ **OPTIONAL, und die Optionalität IST der Entwurf.** Ein nicht-optionales
                          `String` mit `?? "edo12"` hieße: jeder vor diesem Build geschriebene Take
                          BEHAUPTET 12-TET — und der Öffnen-Pfad handelt danach, zieht also einen
                          Spieler, der Gamelan gewählt hat, auf einen Wert zurück, den diese Datei nie
                          trug. `nil` sagt das einzig Wahre über so eine Datei: **dieser Take nennt kein
                          Tonsystem**, und dann tut die Zeile absichtlich nichts. Deshalb ist es das
                          EINZIGE Feld im Decoder ohne `??` — die Abwesenheit des Rückfalls IST der
                          Rückfall — und deshalb `encodeIfPresent` statt `encode`: ein Take ohne Angabe
                          schreibt KEINEN Schlüssel statt `null`.
                          ⛔ **UND DIE ZÄHLUNG DER AUFRUFSTELLEN WAR FALSCH, in zwei Artefakten
                          gleichzeitig** (Quellkommentar und Wächter-Doc): sie sagte „nur ZWEI
                          `Project.init`-Aufrufstellen im ganzen Repo" und nannte die zwei, die ich
                          bearbeitet hatte. Es sind **VIER** — die vergessene ist `ColabPayloadTests` in
                          `Tests/EchoelmusicTests`, der NICHT-blockierenden Suite (#208), die KEIN echtes
                          Gate kompiliert. **Eine dort vergessene Aufrufstelle kann an keinem der beiden
                          Gates rot werden**; sie wäre nur `swift build` aufgefallen, und dieser Container
                          hat keine Toolchain. Lehre, verschieden von der üblichen Stale-Zahl-Lehre: eine
                          Zählung von Aufrufstellen ist ein `git grep` über das GANZE Repo, und die
                          Hälfte des Baums, die kein Gate kompiliert, ist genau die, in der ein
                          ungezählter Aufrufer unbemerkt sitzt.
                          ⚠️ Und KEIN Default auf dem Initialisierer, was die entgegengesetzte
                          Entscheidung zum `schemaVersion`-Nachbarn ist und aus dem entgegengesetzten
                          Grund: `= nil` hätte alle Aufrufstellen unberührt kompilieren lassen — genau
                          der Fehlermodus, den #440/#443 zweimal bezahlt haben (ein Argument, das keine
                          Aufrufstelle schreibt, taucht in keinem Diff auf).
                          ⚠️ EHRLICHE BENOTUNG, und sie ist die #464-Lage, klar gesagt statt verkleidet:
                          **die Datei lässt sich gegen den Vor-#493-Baum ÜBERHAUPT NICHT benoten** —
                          jeder Verhaltensfall nennt `Project.toneSystemID`, das dort nicht existiert,
                          das Bundle kompiliert also nicht und KEINE Behauptung hat ein Verdikt. Von
                          Hand transkribiert: Rundreise, Legacy-Fall und Abwesend-Schlüssel wären aus
                          ihrem GENANNTEN Grund rot, die drei Quelltext-Scans an ihren Ankern, und ZWEI
                          sind GEGENGEWICHTE (die zweite Stimm-Achse `a4Hz`, und die Rückfall-Toleranz
                          von `TuningSystem.named` auf eine unbekannte id) — beidseitig grün und genau
                          dafür da, die naheliegenden späteren „Aufräumarbeiten" rot zu machen.
                          ⚠️ `SourceText.codeOnly` ist hier PROPHYLAKTISCH und das ist GEMESSEN statt
                          angenommen (#484 und #485 mussten genau diese Behauptung je einmal
                          zurücknehmen): roh gegen gestreift unterscheiden sich **0 von 5**
                          Scan-Verdikten, keine der drei negativen Nadeln steht heute in Prosa. Es
                          bleibt, weil #453 EINE Definition für das ganze blockierende Bündel geschaffen
                          hat — und es hört in dem Augenblick auf, prophylaktisch zu sein, in dem jemand
                          eine Rücknahme schreibt, die `toneSystemID: String? = nil` wörtlich zitiert.
                          ⚠️ Und die Grenze zuerst: die PERSISTENZ-Hälfte ist echtes Verhalten, Ende zu
                          Ende getrieben (`Project` ist `public` und reines `Codable`). Die
                          VERDRAHTUNGS-Hälfte ist ein QUELLTEXT-SCAN, weil beide Stellen in `private`
                          Mitgliedern einer Ansicht liegen, die kein Test dieses Bündels instanziieren
                          kann. **Dass ein Take am Gerät wirklich nach Rāst KLINGT, ist eine Hörprobe —
                          dieselbe, die #312 seit dem 31.07. offen hat.**), davor **205** nach
                          `TheDoorsAreIndividualButtonsTests.swift` (#492 — der dritte der
                          vier Founder-Wünsche auf dem 2491-Screenshot: *„Das mit den drei Punkten als
                          einzelnde Buttons anzeigen."* `TransportOverflowMenu` ist gelöscht, seine zwei
                          Einträge sind Kacheln in `EchoelStudioView.quickDoorRow`.
                          ⭐ **Der Wächter existiert nicht wegen der Löschung, sondern wegen dessen, was
                          dahinter hängt:** Live Colabo und Learn sind die EINZIGEN globalen Türen der App,
                          die SHEETS sind statt Panels — #290 hat aufgeschrieben, warum sie keine Chips sein
                          dürfen (die Grammatik der Chip-Leiste ist „dieser Chip wählt, was die Platte
                          zeigt", ein Chip, der ein Modal öffnet, wäre ein lügender Reiter), und diese
                          Begründung hat das Menü überlebt. Mit dem Menü weg ist `quickDoorRow` der EINZIGE
                          Weg hinein. Ein späteres Aufräumen, das die Zeile einfaltet, macht die App nicht
                          kleiner — es macht zwei Fähigkeiten unerreichbar, also genau der Zustand, für den
                          das Türlos-Register weiter oben existiert.
                          ⚠️ **ZWEI Zeilen statt einer, und das ist Arithmetik, keine Geschmacksfrage.**
                          Jede Kachel trägt die 44-pt-Mindestbreite aus #113, die Zeile setzt 8 dazwischen,
                          `startControlRow` ist 16 je Seite gepolstert: sieben Kacheln brauchen
                          `7×44 + 6×8 = 356` pt. Ein 393-pt-Telefon bietet 361 (fünf übrig), ein 375er 343,
                          ein 360er (iPhone 12/13 mini, beide auf iOS 18) 328 — auf dem schmalsten Gerät,
                          an das diese App ausgeliefert wird, laufen sieben Ziele in einer Zeile um 28 pt
                          über, und selbst bei 4-pt-Lücken bräuchte es 332. **Der Preis steht im Quelltext
                          statt verschwiegen: ~40 pt (die ~32-pt-Zeile plus die 8 pt des `VStack`), also
                          exakt das, was #490 der Platte zurückgegeben hat.** Die Trennlinie ist BEDEUTUNG,
                          nicht Passung: Zeile 2 handelt AM Take (Aufnahme · Keep last · MIDI · Speichern),
                          Zeile 3 VERLÄSST ihn (anderes Projekt öffnen · gemeinsam spielen · Lernen).
                          ⭐ **Das `Spacer(minLength: 0)` am Ende ist eine LAYOUT-KONSTANTE und sieht wie
                          Aufräumrest aus** — genau deshalb hat es eine eigene Behauptung. `expands` teilt
                          die Breite unter den flexiblen Kindern EINES `HStack` gleich auf; drei Kacheln
                          allein wären ein Drittel breiter als die vier darüber, in der Zeile, deren ganzer
                          Auftrag *„die sollen immer gleichgroß sein"* lautet (#481/#482). Ein vierter
                          flexibler Platz, der nichts zeichnet, macht beide Zeilen vierspaltig, und die
                          Lücke landet am ENDE der LETZTEN Zeile, wo sie als Raster liest und nicht als Loch.
                          ⚠️ Eine Grenze, benannt statt verzweigt: ohne MultipeerConnectivity ist Zeile 3
                          zweispaltig und die Breiten laufen auseinander. Jedes ausgelieferte Target hat das
                          Framework, und ein untestbarer `#else` ist schlimmer als eine benannte Grenze.
                          ⭐ **#456 ist im selben Atemzug angewandt, und eine der drei Nachführungen ist die
                          lehrreiche.** Drei Wächter lagen über der gelöschten Fläche.
                          `OneChromeControlHeightTests` und `TapTargetFloorTests` wären ROT geworden — das
                          ist der gute Fall. `TheTransportBarIsDissolvedTests` wäre GRÜN geblieben: seine
                          Migranten-Schleife suchte `"TransportOverflowMenu()"` in einer Zeile, in der es
                          per Konstruktion nie wieder auftaucht, also für immer wahr aus dem falschen Grund
                          (#367). Ersetzt durch `"EchoelIconTile("`, was STRENGER ist — Zeile 1 baut heute
                          keine, die Nadel deckt also alle sieben Kacheln statt einer.
                          ⚠️ **KEIN neues `.sheet`.** Beide Türen hängen längst am Rumpf; diese Scheibe
                          ändert, WER sie antippt, nicht wie viele es sind. Die Präsentations-Zahlen (14 auf
                          der Kette, 16 dateiweit) sind unverändert, und das Gegengewicht
                          `testBothSheetsStillExist` hält beide Identitäten fest, während #479 die ANZAHL hält.
                          ⚠️ **EHRLICHE BENOTUNG, gegen den Elternbaum GEMESSEN statt behauptet — und die
                          MECHANIK zählt mehr als die Zahl.** SECHS der sieben Behauptungen sind
                          Regressionen, aber sie zerfallen: **ZWEI** scheitern an etwas, das der Elternteil
                          aktiv ENTHÄLT (`TransportOverflowMenu` und die zwei toten Notification-Cases),
                          **DREI** an einem fehlenden ANKER — `quickDoorRow` gibt es dort nicht, sie werfen
                          also `DoorAnchorMissing`; das ist EINE Abwesenheit, dreimal gemeldet, und sie als
                          drei Befunde zu verbuchen wäre der #433-Defekt in der schmeichelhaften Richtung.
                          **EINE** (der Mount) liegt dazwischen: `startControlRow` existiert und nennt die
                          Zeile bloß nicht. Die siebte ist ein GEGENGEWICHT, beidseitig grün.
                          ⛔ **Und `SourceText.codeOnly` stand im ersten Entwurf als „TRAGEND" — der exakte
                          Überclaim, den #484 einen Zyklus zuvor zurücknehmen musste, wiederholt in der
                          Datei, die ihn zitiert.** Gemessen: roh gegen gestreift unterscheiden sich
                          **0 von 14** Verdikten (7 Behauptungen × 2 Bäume). Der Grund ist die SKOPIERUNG,
                          nicht Glück: die ⛔-Rücknahme im Receiver nennt die gelöschten Cases sehr wohl,
                          sitzt aber außerhalb des klammer-gematchten `switch`, und das eine dateiweite
                          `case "learn":` in Prosa steht 2.300 Zeilen entfernt. Es bleibt, weil #453 EINE
                          Definition von „Code, nicht Prosa" für das ganze blockierende Bündel geschaffen
                          hat — und weil die Form, die es TRAGEND machen würde, einen Kommentar entfernt
                          ist: eine künftige Rücknahme in dieser Datei, die `TransportOverflowMenu()`
                          wörtlich schreibt, färbt den negativen Scan auf KORREKTEM Code rot.
                          ⚠️ Und die Grenze zuerst: JEDE Behauptung ist ein QUELLTEXT-SCAN. Dass die zwei
                          Zeilen rendern, dass ein Finger die 44 pt trifft, dass VoiceOver die Etiketten
                          spricht und dass sich die zweizeilige Platte auf einem 360-pt-Telefon gut liest,
                          sind vier Geräteproben und alle vier offen. Auch die Breiten-Arithmetik oben ist
                          Rechnen über Konstanten, keine Messung eines gerenderten Layouts.),
                          davor **204** nach `TheTempoBoxShowsTheClockTests.swift` (#491 — der erste Wächter in
                          dieser Kette über einer DUBLETTE: zwei Kästen in EINER Zeile rendern dieselbe
                          Eigenschaft. `BodyTempoField` zeigte unlocked `cameraRPPG.displayBPM`, und
                          `PulseMonitorMiniLive` — die Pille daneben — rendert `cameraRPPG.displayBPM`. Der
                          Founder hat es am 2026-08-07 im Screenshot von 2491 eingekreist: *„Transport, bpm ,
                          Schloss und Biofeedback bar zu einer schöneren Ebene ohne doppelt bpm zusammen
                          fassen."*
                          ⭐ **UND ES WAR ZUGLEICH EIN LÜGENDES CONTROL, was die Reparatur ENTSCHIEDEN hat.**
                          Die Uhr läuft NICHT auf dem Puls — `EchoelStudioView` treibt sie durch die
                          generative Abbildung (`StudioCalculator.tilted(genreTempo(...))`), ein 144-bpm-Puls
                          kann also über einer 72-bpm-Uhr stehen. Und `toggleLock` übernahm den GEZEIGTEN
                          Wert: Sperren verschob die Musik um eine Tempo-Oktave in einem Tipp, während es
                          sich als „friere ein, was du hast" ausgab. **Die Invariante „die Sperre fängt die
                          Zahl, die du siehst" war nie gebrochen — die ZAHL war falsch**, und deshalb ist die
                          `toggleLock`-Zeile unverändert und trotzdem korrekt geworden.
                          ⛔ **DIE NAHELIEGENDE REPARATUR IST DIE VERBOTENE.** Einen der beiden Kästen zu
                          löschen entfernt die Dublette in einer Zeile — und der Founder-Satz vom 2026-07-04,
                          im Kopf von `BodyTempoField.swift` zitiert, endet auf *„beide behalten"*. Also nicht
                          einen Kasten entfernen, sondern jeden Kasten die Tatsache zeigen lassen, für die er
                          BENANNT ist: die Pille ist die Herzfrequenz, das Tempo-Feld ist die Uhr. VIER der
                          sechs Behauptungen stehen nur dafür da, den billigen Weg rot zu machen.
                          ⚠️ EHRLICHE BENOTUNG, gegen den Elternbaum GEMESSEN statt behauptet: **ZWEI**
                          Regressionen (`testTheUnlockedReadoutIsTheClock` — der Elternteil deklariert
                          `followingValue { liveBodyBPM > 0 ? liveBodyBPM : transport.tempo }`, die
                          kein-`liveBodyBPM`-Hälfte ist dort FALSCH; und
                          `testNoLabelClaimsTheBoxFollowsYourPulse` — der Elternteil trägt DREI solche
                          Etiketten im CODE, dieser Baum keins). Die anderen VIER sind beidseitig grün und
                          heißen deshalb Gegengewichte (#433).
                          ⚠️ `SourceText.codeOnly` ist hier TRAGEND und das ist GEMESSEN, nicht angenommen
                          (#484 musste genau diese Behauptung zurücknehmen): die Rücknahme-Kommentare dieser
                          Scheibe zitieren die entfernten Zeichenketten wörtlich — `"your pulse"` steht im
                          ROHTEXT von `BodyTempoField.swift` auf BEIDEN Bäumen **3×**, im CODE **3× auf dem
                          Elternteil / 0× hier**. Ein Rohtext-Scan wäre also auf KORREKTEM Code rot. Dieselbe
                          Kollision wie #486: dieses Repo schreibt auf, was es entfernt hat.
                          ⚠️ Und die Grenze zuerst: ALLE sechs sind QUELLTEXT-SCANS. Dass die Zeile RENDERT,
                          dass die zwei Zahlen am Gerät jetzt verschieden aussehen und dass die Anordnung
                          „schöner" ist, sind Geräteproben und alle drei offen. Ebenfalls offen und hier
                          benannt statt verschwiegen: nach dem Entsperren trägt `transport.tempo` noch den
                          4-stelligen Wert, auf den die Sperre geglitten ist, die Anzeige lässt also Stellen
                          fallen (71,2345 → 71,2). Das ist eine Formatierungs-Änderung und keine
                          Uhr-Änderung — und sie ersetzt das weit schlimmere Verhalten davor, bei dem
                          Entsperren den Kasten auf den ROHEN Puls springen ließ.),
                          davor **203** nach `TheHeaderShowsTheLoopTests.swift` (#490 — **die Zahl bewegt sich
                          NICHT, und das ist der ganze Eintrag: derselbe Commit LÖSCHT
                          `HeaderSpectrumIsALeafTests.swift` und LEGT diesen an.** Der Wächter über den
                          Farbbalken verlor sein ganzes Subjekt (die Balken sind gelöscht), der neue nagelt
                          fest, was an ihre Stelle tritt — die Loop-Anzeige im Marken-Header, das E-Logo
                          RECHTS der Monitor-Kacheln, und die Tatsache, dass die Kopfzeile selbst weiterhin
                          NICHTS Lebendes liest. **Das ist die #374-Lehre wörtlich, zum ersten Mal in diesem
                          Absatz statt im Sources-Absatz: eine unveränderte Zahl ist kein Beleg dafür, dass
                          sich nichts geändert hat.** Wer diese Kette auf Lückenlosigkeit prüft, findet hier
                          zwei gleiche Zahlen hintereinander und muss wissen, dass dazwischen ein TAUSCH
                          liegt — dieselbe Form wie #373→#374, wo eine Löschung plus eine Anlage die 108
                          stehen ließen. ⚠️ Und ehrliche Benotung: von fünf Behauptungen sind VIER
                          Regressionen gegen den Elternbaum (Montage der Anzeige `False→True`, gelöschte
                          Datei `True→False`, gieriger Flügel `2→1`, Marke nach den Kacheln `False→True`) und
                          EINE ein Gegengewicht, beidseitig grün (die Kopfzeile liest nichts Lebendes) —
                          gemessen mit einer Python-Transkription gegen `git show HEAD:…`, nicht geschätzt.
                          ⛔ Und `SourceText.codeOnly` ist hier TRAGEND und nicht Prophylaxe, aber aus einem
                          ANDEREN Grund als mein Entwurf behauptete: er schrieb, das zurückgenommene
                          `.frame(maxWidth: .infinity, alignment: .trailing)` im ⛔-Kommentar zähle roh als
                          zweiter gieriger Flügel. Gemessen: NEIN — die Zeichenkette ist über zwei
                          Kommentarzeilen umbrochen und bildet sich nie. Roh gegen gestreift unterscheiden
                          sich die Verdikte von **genau EINER** der fünf Behauptungen, und zwar der
                          Lebend-Lese-Prüfung, weil mein eigener einführender Kommentar sagt, das Blatt lese
                          „`Transport` und `@AppStorage` only". Die #443-Klasse, an mir selbst gefangen: die
                          METHODE in einem Satz ist auch eine Behauptung.), davor **203** nach
                          `EveryIconOnlyControlSpeaksTests.swift` (#489 — der erste Wächter in
                          dieser Kette, der für einen Defekt geschrieben wurde, den es NICHT GIBT, und dessen
                          ganzer Wert deshalb in der MESSMETHODE liegt statt im Befund. Gemeldet war „das
                          `•••`-Menü ist die EINE der sechs Kacheln ohne gesprochenes Etikett". Es trägt
                          `.accessibilityLabel("More — Live Colabo; Learn and news")` — 37 Zeilen unter der
                          `EchoelIconTile`, die es benennt. Alle SECHS Aufrufstellen sind etikettiert.
                          ⛔ **ZWEI EIGENE SCANNER WAREN UNSOUND, hintereinander, in EINEM Zyklus.** Fassung 1
                          (festes ±14-Zeilen-Fenster um die Kachel): **8 Fehlalarme**. Fassung 2 (Brace-Match
                          plus Chain-Walk mit 3-Zeilen-Blank-Lookahead): **4 Fehlalarme** —
                          `BodyTempoField:173`, `EchoelStudioView:1837`, `:9830`, `WorkspaceView:576`, alle
                          etikettiert. ⭐ **Die Ursache ist eine Eigenschaft DIESES Repos und gehört deshalb
                          hierher und nicht nur in den Dateikopf:** `SourceText.codeOnly` erhält die
                          Zeilen-ANZAHL, also werden die 30-bis-40-Zeilen-⛔/⭐-Blöcke, die diese Codebasis
                          schreibt, zu 30-bis-40 LEEREN Zeilen. Ein Etikett kann beliebig viele Leerzeilen
                          unter dem Block sitzen, zu dem es gehört. **Jedes feste Fenster und jeder begrenzte
                          Blank-Lookahead ist hier per KONSTRUKTION unsound, nicht durch Pech** — und je mehr
                          Prosa das Repo ansammelt, desto falscher wird ein solcher Scan. Fassung 3 überspringt
                          ALLE Leerzeilen, wenn die nächste nicht-leere mit `.` beginnt, UND zählt
                          Klammer-Tiefe mit, damit ein mehrzeiliger Modifier die Kette nicht beendet
                          (`BodyTempoField`s Ternär setzt mit `:` fort, nicht mit `.`). Gemessen über 347
                          Dateien: **47** `label:`-Blöcke mit `Image(systemName:)`, davon **22** mit
                          zusätzlichem Text und **25** icon-only, davon **NULL** stumm; breiteste überquerte
                          Kette **25 Zeilen**.
                          ⛔ **Das ist die #443-Klasse — „die METHODE in einem Satz ist auch eine Behauptung" —
                          von mir ZWEIMAL begangen, im Zyklus direkt nach dem Commit, dessen Text davor warnt.
                          Und der teurere Teil ist, was FAST passiert wäre: eine „Reparatur" an korrektem Code.**
                          Sechs redundante Etiketten auf Bedienelemente, die schon eines haben, hätten JEDEN
                          Test bestanden und wären als Barrierefreiheits-Verbesserung durchgegangen.
                          ⚠️ **EHRLICHE BENOTUNG: KEINE der vier Behauptungen ist eine Regression.** Alle vier
                          sind auf dem Elternbaum grün, weil es nichts zu reparieren gab. Ihr Wert liegt
                          vollständig VORWÄRTS, und die zwei Gegengewichte sind der eigentliche Inhalt: ein
                          verkürzter Lookahead lässt `maxChainGap` einbrechen, ein verengter Sweep lässt die
                          Icon-Only-Zahl einbrechen — **beide werden rot, BEVOR die Etiketten-Behauptung es
                          wird**, die Wiedereinführung einer der zwei unsoliden Formen ist also fangbar. Das
                          so zu sagen ist die #433-Regel: die eigenen Tests in der schmeichelhaften Richtung
                          falsch einzuordnen ist derselbe Defekt wie in der harschen.
                          ⚠️ Und die Grenzen zuerst, weil ein Sweep breiter WIRKT als er ist: alle vier
                          Behauptungen sind QUELLTEXT-SCANS. Der Scan sieht NUR die Form
                          `… label: { Image(systemName:) }` über mehrere Zeilen — ein einzeiliges `label:`,
                          ein `Label` mit verborgenem Titel, ein Icon in einem eigenen View-Typ und jedes
                          `Image` als Tap-Ziel ohne `label:`-Block sind ihm unsichtbar; die App hat mehr
                          Icons als 25. `accessibilityHidden` zählt bewusst als erfüllt (dekoratives Glyph in
                          einer schon benannten Zeile ist korrektes SwiftUI, und es zu verbieten wäre die
                          #364-Falle). Dass VoiceOver einen Satz WIRKLICH spricht, dass er sich vorgelesen gut
                          liest und dass das Bedienelement erreichbar ist, sind drei Geräteproben und alle drei
                          offen — dieselbe Schicht-Grenze, die #480 eine Woche zuvor bezahlt hat),
                          davor **202** nach `TheSignKeysSayWhatTheyDoTests.swift` (#488 — der erste Wächter in
                          dieser Kette über einer ACCESSIBILITY-Zeichenkette, die es GAR NICHT GAB, und der
                          erste, dessen Defekt auf dem EINEN app-weiten Bedienelement saß. Die − und +
                          Tasten von `EchoelNumberPad` — geöffnet von jedem `EchoelValueField`, also von
                          **118** Parameter-Zeilen — trugen kein `.accessibilityLabel`. SwiftUI benennt
                          einen solchen Knopf nach seinem SF-Symbol, VoiceOver sprach also „minus" und
                          „plus": die Wörter für genau die Arithmetik, die diese Tasten NICHT tun. Sie
                          setzen das VORZEICHEN und lassen den Betrag unberührt.
                          ⭐ **Und die Wörter waren nicht bloß falsch, sie waren VERGEBEN.** Diese App HAT
                          ein echtes Inkrement/Dekrement — `EchoelValueField`s
                          `accessibilityAdjustableAction`, mit dem Wischen hoch/runter den Wert wirklich
                          verstellt (#480 hat genau das gemessen). Zwei verschiedene Affordanzen unter
                          einem Satz Wörter, und die falsche trug sie.
                          ⭐ **Die Schicht ist die Lehre, und #480 hat sie EINE WOCHE ZUVOR schon einmal
                          bezahlt:** ein Accessibility-Etikett ist unsichtbar, solange VoiceOver aus ist —
                          kein Screenshot, kein Design-Durchgang, kein UI-Review zeigt es je. Deshalb
                          konnte diese Auslassung auf dem meistbenutzten Bedienelement der App überleben,
                          während dieselbe Klasse im sichtbaren Text regelmäßig gefangen wird.
                          ⭐ **DER ZWEITE, STÄRKERE DEFEKT KAM ERST BEIM MESSEN — und er ist die
                          #135-Klasse.** Das Tor war `negative ? allowsNegative : true`: das `+` war
                          IMMER aktiv. Auf einer Zeile ohne negative Untergrenze kann aber gar kein
                          führendes Minus existieren (`−` ist gesperrt, `append` schreibt nur Ziffern,
                          `appendDecimal` schreibt keins) — die Taste war dort ein beweisbarer No-op, der
                          live aussah. Gemessen statt geschätzt: von **118** `EchoelValueField`-Zeilen in
                          `Sources/` haben **DREI** eine negative Untergrenze (`EchoelFXView`: Flanger
                          Feedback −0,95…0,95 · Comp Threshold −48…0 · Limiter Ceiling −12…0). Auf **115
                          von 118** war das `+` also ein lügendes Control. Jetzt hängt das PAAR an
                          `allowsNegative` und dimmt gemeinsam.
                          ⛔ **UND DIE ERSTE MESSUNG SAGTE „NULL negative Zeilen" — der #443-Defekt in
                          seiner leisesten Form.** Mein Scan suchte ein `range:`-Argument;
                          `EchoelFXView.field`, `EchoelStudioView.param` und `knob` reichen den Bereich
                          POSITIONELL durch (drittes Argument). Ein Scan, der nach einem Label sucht, das
                          die Aufrufstellen nicht schreiben, meldet nicht „ich sehe nichts", sondern
                          „es gibt nichts" — und daraus wäre „das Paar ist überall tot, weg damit"
                          geworden. Die METHODE in einem Satz ist auch eine Behauptung.
                          ⭐ Die Regel selbst ist deshalb in `NumberPadEntry.signed` GEHOBEN, wie
                          `acceptsDigit` davor: eine `private`-Methode auf einem SwiftUI-`View` ist vom
                          blockierenden Bündel nicht messbar, und was diese zwei Tasten tun, ist genau
                          das, was ein Nutzer missverstehen kann. Idempotent per Konstruktion (der Rumpf
                          wird ohne führendes Minus genommen, bevor eines gesetzt wird), also kann
                          zweimal Drücken weder stapeln noch umschalten.
                          ⚠️ Der PREIS ist zwei gedimmte Zellen auf 115 von 118 Zeilen statt einer. Das ist
                          der Tausch: ein sichtbar totes Bedienelement ist ehrlicher als eines, das live
                          aussieht und nichts kann. **Absichtlich KEIN `accessibilityHint`** — der Hinweis
                          gehört der Zeile, die den Pad geöffnet hat (#416: eine Entscheidung, ein Ort).
                          ⛔ **EHRLICHE BENOTUNG, und sie ist die #464-Lage, klar gesagt statt verkleidet:
                          die Datei lässt sich gegen den Elternbaum ÜBERHAUPT NICHT benoten** — vier ihrer
                          neun Methoden treiben `NumberPadEntry.signed`, das dort nicht existiert, das
                          Bündel kompiliert also nicht und KEINE Behauptung hat ein Verdikt. Von Hand
                          transkribiert: **ZWEI** sind Regressionen aus ihrem GENANNTEN Grund
                          (`testBothSignKeysCarryASpokenLabel`, `testPlusIsGatedLikeMinus`), **EINE** auf
                          der i18n-Hälfte (`testBothLabelsAreInTheCatalogWithGerman`, Schlüssel abwesend),
                          **EINE** rot durch ANKER-Abwesenheit statt aus ihrem Grund
                          (`testTheLabelsDoNotClaimArithmetic` wirft, weil `.accessibilityLabel(` dort
                          fehlt — die #486-Form, und sie gehört gezählt, nicht als Befund verbucht),
                          **EINE** echtes Gegengewicht beidseitig grün
                          (`testAtLeastOneShippedRowCanStillGoNegative`), und **VIER** sind
                          VORWÄRTS-Wächter auf einem Symbol, das derselbe Commit anlegt — sie konnten nie
                          rot sein, und sie als Regressionen zu verbuchen wäre der #433-Defekt.
                          ⛔ **UND DIE GANZE BENOTUNG DARÜBER WAR EINE ANTWORT AUF DIE FALSCHE FRAGE —
                          die Datei kompilierte auch gegen den EIGENEN Baum nicht.** Der Absatz erklärt
                          sorgfältig, warum sie gegen den ELTERNTEIL kein Verdikt hat, und setzt dabei
                          stillschweigend voraus, dass sie DANACH baut. Sie tat es nicht: CI/CD auf
                          `fdca36f` meldete `** TEST BUILD FAILED **` mit drei `error:`-Zeilen, alle in
                          `TheSignKeysSayWhatTheyDoTests.swift:206-207`. Ursache ist reine Syntax und
                          nicht Logik — **Swift erlaubt keinen Zeilenumbruch zwischen einem
                          Optional-Chaining-`?` und dem folgenden Subscript**; `)?` + Umbruch + `["de"]`
                          parst als frisches Array-Literal („expected ',' separator"). Der
                          i18n-Katalog-Lesevorgang war vierfach verschachtelt und über zwei Zeilen
                          umbrochen. Jetzt schrittweise, mit dem Grund an der Stelle. ⭐ **Und der
                          #478-Diskriminator hat GENAU SO funktioniert, wie er aufgeschrieben ist:**
                          `TEST BUILD FAILED` plus eine `error:`-Zeile, die eine Repo-Datei nennt =
                          mein Commit, kein Infrastruktur-Flake — die Unterscheidung, die einen Tag
                          zuvor eingeführt wurde, hat beim ersten echten Anwendungsfall die Stunde
                          Fehlersuche gespart. ⚠️ **Die Lehre ist NICHT „Syntax prüfen" — ohne lokale
                          Toolchain kann ich das nicht. Sie ist: eine Benotungs-Prosa, die eine
                          Compile-Frage beantwortet, muss sagen, gegen WELCHEN Baum** — „gegen den
                          Elternbaum nicht benotbar" liest sich wie „gegen den eigenen grün", und
                          genau diese Lücke hat einen roten Merge-Gate einen Zyklus lang getragen.
                          ⚠️ `SourceText.codeOnly` ist hier TRAGEND und gemessen, nicht prophylaktisch
                          (#453/#484/#485): derselbe Commit schreibt einen ⛔-Block über `signKey`, der
                          `"minus"`, `"plus"` UND das zurückgenommene `negative ? allowsNegative : true`
                          wörtlich zitiert — ein Rohtext-Scan wäre auf KORREKTEM Code rot. Wieder die
                          Kollision aus #486: dieses Repo schreibt auf, was es entfernt hat.
                          ⚠️ Und die Grenze zuerst: die vier Verhaltensfälle rechnen eine reine Funktion,
                          alles andere sind QUELLTEXT-SCANS plus ein JSON-Lesevorgang auf dem Katalog.
                          Dass VoiceOver den Satz wirklich SPRICHT, dass er sich vorgelesen gut liest und
                          dass die zwei gedimmten Zellen am Gerät als gesperrt erkennbar sind, sind alle
                          drei Geräteproben und alle drei offen.),
                          davor **201** nach `EveryPitchedVoiceFollowsTheToneSystemTests.swift` (#338 — der
                          erste Wächter in dieser Kette über einem FÄCHER: nicht „ist dieser Wert richtig",
                          sondern „bekommen ihn ALLE, die ihn brauchen". `applyTuning()` reichte die
                          12-Eintrag-Cent-Tabelle an den globalen PolySynth und den Sub, aber NICHT an
                          `bioVoice` und NICHT an `LaneVoiceRack` — also an keine Stimme, die eine Lane
                          spielt. Dieselbe Lücke wie #312, eine Ebene tiefer.
                          ⭐ **Und der teuerste Befund kam von BEIDEN Pflicht-Reviewern unabhängig: mein
                          Rack-Fächer wäre beim Start ein garantierter NO-OP gewesen.**
                          `EchoelStudioView.onAppear` läuft im ersten SYNCHRONEN appear-Pass,
                          `LaneVoiceRack.attachAll` erst später aus dem asynchronen Start-Task von
                          `EchoelmusicApp` — zum Zeitpunkt des Fächers existieren die Stimmen gar nicht.
                          Das Rack LATCHT deshalb beide Achsen und sät sie am Ende von `attachAll`.
                          **BEIDE, nicht nur die neue**: die schon vorhandene
                          `setTuning(a4Hz:)`-Aufrufstelle trug dieselbe geerbte Aussetzung, sie war nur
                          nie gemessen worden. Der Latch liegt im RACK und nicht in `EchoelmusicApp`,
                          weil das eine dritte Kopie des Schlüssels `"toneSystemID"` gewesen wäre (#416).
                          ⛔ **Die BEGRÜNDUNG, die den `bioVoice`-Fächer bisher blockierte, war falsch —
                          und sie stand in drei Dateien.** Sie lautete „die Stimme klingt nie, `arm()`
                          hat keinen Aufrufer". `arm()` tort nur den ATEM-Trigger; der MIDI-Pfad
                          (`apply(controller:)` → `playNote`) ist ungetort, und sein Drain wird beim
                          Start installiert. Zurückgenommen, wo sie stand.
                          ⚠️ EHRLICHE BENOTUNG: das Bundle lässt sich gegen den Elternbaum ÜBERHAUPT
                          NICHT benoten — `BioReactiveSynthVoice.setTuningCents` existiert dort nicht,
                          die Datei kompiliert also gar nicht (#464-Lage). Von Hand transkribiert wären
                          NEUN der zwölf Nadeln rot, drei sind Prämissen-Anker.
                          ⚠️ Und die Grenze zuerst: 12-TET ist eine Null-Tabelle, also Faktor exakt 1.0
                          und bitgleich — genau das macht den unbedingten Fächer sicher. Dass eine
                          Lane-Note am Gerät wirklich in Maqām oder Gamelan klingt, ist eine Hörprobe
                          und offen.), davor **200** nach `RadiusHasOneSpellingTests.swift` (#483 — der erste Wächter in
                          dieser Kette über einer ZAHL, die in einer Konstante längst einen NAMEN hatte, und
                          der erste, dessen Regel WERT-basiert statt zeichenketten-basiert ist. `EchoelTheme`
                          deklariert `radiusSmall` 4 · `radius` 8 · `radiusLarge` 12 — und NEUNZEHN
                          `cornerRadius:`-Aufrufstellen in sieben Dateien buchstabierten die Zahl (10×`8`,
                          3×`4`, 6×`12`). Render-neutral per Konstruktion: jedes Literal war GLEICH der
                          Konstante, in die es faltet.
                          ⛔ **NEUNZEHN GEFALTET, ACHTZEHN SCAN-SICHTBAR — und die Differenz ist ein Defekt,
                          den DIESE SCHEIBE SELBST ERZEUGT HAT.** Der Parser des Wächters sieht ein Literal
                          nur UNMITTELBAR hinter `cornerRadius:` (über Leerzeichen hinweg); ein Ternär
                          versteckt es. Die erste Fassung faltete deshalb in `FloatingVisualWindow` den
                          RAHMEN auf `EchoelTheme.radiusLarge` und ließ die `clipShape`-Zeile zwei Zeilen
                          darüber als `windowSize.isFullscreen ? 0 : 12` stehen — also genau die Spaltung,
                          die der Commit überall sonst entfernt, mit sichtbarer Folge: wer das Token auf 14
                          setzt, bewegt den Rand und nicht den Beschnitt, ein Haarriss auf der schwebenden
                          Karte. Vom #483-Reviewer gefunden, von Hand nachgefaltet. **Die Lehre gehört dem
                          SCAN, nicht der Zeile: eine wert-basierte Prüfung ist nur so breit wie ihre Syntax**
                          — die drei blinden Flecken (Ternär, Tabulator, berechneter Ausdruck) stehen deshalb
                          im Kopf des Wächters, statt sich still auf sie zu verlassen.
                          ⭐ **Warum ausgerechnet hier und nicht irgendwo im Repo: die Referenz des Founders
                          war eine der achtzehn.** #481/#482 setzen die Kopfzeilen-Kacheln als das eine
                          Knopf-Format („orientiere dich an denen oben rechts"); `HeaderMonitors.swift` —
                          genau diese Kacheln — schrieb `8`, während `EchoelIconTile`, die eigens danach
                          gebaute KOPIE, die Konstante liest. Ein Verschieben des Tokens hätte also die KOPIE
                          bewegt und die REFERENZ auf 8 stehen lassen: das eine Paar, dessen Auseinanderlaufen
                          der Founder wörtlich verboten hat, und die #416-Form in ihrer leisesten Ausprägung.
                          ⭐ Die Regel pflegt sich selbst, weil sie auf den WERT sieht: verboten ist ein
                          `cornerRadius:`-Literal, das GLEICH einer benannten Konstante ist. Wer `radius` von
                          8 auf 10 setzt, macht damit jedes `10` illegal und jedes `8` wieder legal — der
                          Wächter folgt der Entscheidung, statt einen Zeitpunkt einzufrieren.
                          ⚠️ Die WERTE der drei Konstanten sind ABSICHTLICH nicht festgenagelt, und das ist
                          die #364-Bedingung: ein Test, der 8/4/12 behauptet, färbt jede gewöhnliche
                          Design-Anpassung rot — und so wird ein Wächter gelöscht.
                          ⚠️ ACHT Literale bleiben stehen (4×`6`, 3×`2`, 1×`1`), weil es für sie kein Token
                          gibt; `testAnUnnamedValueIsStillAllowed` ist das Gegengewicht gegen das
                          naheliegende Aufräumen „dann benenne eben alle", das für jede Ein-Ort-Zahl eine
                          app-weite Konstante prägen würde.
                          ⛔ **EHRLICHE BENOTUNG — und die erste Fassung hatte sie in der schmeichelhaften
                          Richtung falsch, also den #433-Defekt, gefangen beim Transkribieren VOR dem Commit
                          und nicht im Review.** Sie schrieb „EINE Regression, drei Gegengewichte beidseitig
                          grün". Gegen den Elternbaum gemessen sind es **ZWEI** Regressionen — der
                          Wert-Scan (auf dem Elternteil an den 18 für ihn sichtbaren Stellen rot, NICHT an
                          19 — die neunzehnte ist das Ternär aus dem ⛔-Block oben)
                          UND `testTheReferenceAndTheCopyReadTheSameToken`, dessen
                          Kopfzeilen-Hälfte dort ebenfalls rot ist. Und `testAnUnnamedValueIsStillAllowed`
                          trug eine zweite Behauptung (`unnamed.count == literals.count`), die auf dem
                          Elternteil bei 8 von 26 rot war — sie war also gar kein Gegengewicht, sondern eine
                          dritte, schwächere Kopie der Regression. Gelöscht statt gelockert, mit ⛔-Vermerk an
                          ihrer Stelle. Stand: zwei Regressionen, eine Prämisse (#367-Anker: die drei
                          Konstanten müssen überhaupt existieren), zwei Gegengewichte.
                          ⚠️ `SourceText.codeOnly` ist hier TRAGEND und nicht Prophylaxe, gemessen statt
                          behauptet: `cornerRadius: 8` steht nach dem Falten noch **genau einmal** in
                          `Sources/` — im ⛔-Kommentar, den derselbe Commit über die zwei Kopfzeilen-Modifier
                          schreibt, um das Gesetz festzuhalten. Ein Rohtext-Scan wäre also auf KORREKTEM Code
                          rot. Dieselbe Kollision wie in #486: dieses Repo schreibt auf, was es entfernt hat,
                          und ein negativer Scan trifft zwangsläufig auf seinen eigenen Nachruf.
                          ⚠️ Und die Grenze zuerst: JEDE Behauptung ist ein QUELLTEXT-SCAN. Dass die neunzehn
                          Stellen unverändert RENDERN, folgt aus der Gleichheit von Literal und Konstante und
                          nicht aus einer Messung; dass die Kacheln am Gerät gleich aussehen, bleibt eine
                          Sichtprobe.),
                          davor „199" nach `TheBreathingPracticeIsInTheMainViewTests.swift` (#486 — der erste
                          Wächter in dieser Kette über einer Fläche, die eine FOUNDER-ENTSCHEIDUNG umsetzt,
                          indem sie KEINE Tür baut. Founder 2026-08-07 verlangte „Training für kohärentes
                          Atmen" neben der Chanten/Summen/Tönen/Singen-Hälfte, die #485 aufs Mischpult
                          gelegt hat. Wie bei #485 war die FÄHIGKEIT längst da — sogar doppelt:
                          `BreathGuideView` (gepacter Kreis, Kontraindikationen, Halte-Bestätigungstor) und
                          `MeditationView` (Dauer, Sitzungsaufnahme, Historie). Beide türlos (#276).
                          ⭐ **Und türlos ist hier kein Versäumnis, sondern die Entscheidung selbst — deshalb
                          fügt diese Scheibe einen Streifen hinzu und keine Tür.** `decisions.csv` Zeile 200,
                          2026-07-12, wörtlich: *„Meditation View nicht extra. Alles findet in der Main View
                          statt und ist Teil des Produktionsprozesses."* Eine Chip- oder Sheet-Tür zu einem
                          eigenen Atem-Bildschirm ist exakt das, was abgelehnt wurde; der Ask wäre erfüllt und
                          die Entscheidung gebrochen. Die Übung kommt stattdessen IN `bioPanel`, direkt unter
                          `BioStripView` — die gemessene Hälfte und die aktive Hälfte in EINEM Panel.
                          ⭐ **Der Streifen liegt in `BreathGuideView.swift` statt in einer neuen Datei, und
                          das ist eine Entscheidung mit zwei Gründen.** (1) Die Sources-Zahl bleibt bei 349 —
                          diese Scheibe bewegt sie nicht, was der Absatz darüber als eigene Lehre führt: aus
                          zwei aufeinanderfolgenden Ständen lässt sich keine Richtung ableiten, weil
                          verschiedene VORGÄNGE dieselbe Zahl verschieden bewegen. (2) Wichtiger: die
                          #416-Spannung bleibt SICHTBAR. Zwei Atemführungen in einer Datei sind schwerer zu
                          vergessen als zwei in zwei Dateien.
                          ⚠️ **`BreathCoachStrip` MUSS ein `View`-`struct` bleiben, und das ist die teuerste
                          Zeile der Scheibe.** `pacer.guidance` wird ~30×/s neu geschrieben — das DREIFACHE
                          der Rate, die den 10.76.41/50-Freeze verursacht hat. Die naheliegende spätere
                          Vereinfachung („ist doch nur ein Streifen, falte ihn als `@ViewBuilder`-Fragment in
                          `bioPanel`") ist genau dieser Freeze. **Und das Argument, das NICHT trägt, gehört
                          mitgeschrieben, weil es sich richtig anfühlt:** „`bioPanel` beherbergt heute keinen
                          `Picker`, also kann nichts zerrissen werden." Das ist eine Aussage über den
                          heutigen Baum, keine Regel.
                          ⛔ **UND DIE ERSTE FASSUNG DIESER BEGRÜNDUNG WAR FALSCH, in DREI Artefakten
                          gleichzeitig (Quellkommentar, Wächter-Kopf, hier) — und zwar in der Richtung, die
                          die Regel WEICHER klingen lässt, als sie ist.** Sie lautete: „`panel(_:_:)` nimmt
                          einen `@escaping` Builder, der in `EchoelPanel`s EIGENEM Rumpf ausgewertet wird —
                          ein eingefalteter Lesezugriff landete also auf `EchoelPanel`." Gemessen statt
                          behauptet: **`bioPanel` hat auf seiner obersten Ebene GAR KEINEN
                          `panel(...)`-Wirt** — der einzige `panel(`-Treffer in der ganzen Deklaration war
                          dieser Satz selbst, den ich in den Montage-Kommentar geschrieben hatte. Sein
                          `VStack` erreicht den Schirm über `dropdownContent`, dessen eigener
                          FREEZE-RULE-Vermerk es wörtlich sagt: **im WURZEL-Rumpf ausgewertet, DAUERHAFT.**
                          Ein eingefalteter Lesezugriff landet also unmittelbar auf `EchoelStudioView.body`
                          — dem Rumpf, der JEDEN `.menu`-Picker des Instruments hält. Nicht einen Sprung vom
                          Freeze entfernt, sondern der Freeze. **Der Nachbar-Eintrag #485 zwei Bildschirme
                          weiter oben beschreibt den GEGENFALL korrekt** (`mixerPanel` geht sehr wohl durch
                          `panel("Mix", …)`), und genau daher stammt der Fehler: die Form eines wahren
                          Satzes über ein ANDERES Panel wurde übernommen, ohne den Wirt dieses Panels
                          nachzuschlagen — dieselbe Klasse wie der zurückgenommene #461-Satz über
                          `BioStripView`. `AnyView(bioPanel)` ist ebenfalls keine Grenze (10.76.50). Ein
                          `View`-`struct` ist unter jedem dieser Fälle eine; die Abwesenheit eines Pickers
                          unter keinem.
                          ⭐ **Die Sicherheits-Hälfte ist ABSICHTLICH zwei Behauptungen und nicht eine.**
                          `BreathPattern` schreibt sein Gesetz selbst auf: die UI hält Resonanz vorgewählt und
                          wählt NIE selbsttätig ein Halte-Muster. Dieser Streifen hat keinen Muster-Picker,
                          also muss er (a) `.resonance` erzwingen und (b) `BreathPacer.contraindications`
                          rendern — die GETEILTE Konstante, nie eine lokale Kopie, damit der Wortlaut nicht
                          von der Führung darüber wegdriften kann. Eine einzelne Behauptung auf einer der
                          beiden Hälften ließe die andere zum „Vereinfachen" frei.
                          ⛔ **UND BEIDE HÄLFTEN WAREN IN DER ERSTEN FASSUNG FALSCH GEBAUT — drei Reviewer
                          fanden es unabhängig, jeder Punkt nachgemessen.** (a) Die Erzwingung war
                          `if pacer.pattern.hasHolds`, begründet mit „wenn die TÜRLOSE Vollbild-Führung sie
                          auf Box stehen gelassen hat" — ein Satz, der seine eigene Widerlegung enthält: eine
                          türlose Fläche kann nichts stehen lassen. Gemessen sind es DREI Schreiber von
                          `pacer.pattern` in `Sources/` — `BreathGuideView`s Picker (nur aus `BioSourceView`,
                          NULL Instanziierungen), `MeditationView` (nur über `showMeditation`, gar kein
                          Setzer) und diese Zeile. **Heute kann kein erreichbarer Pfad ein Halte-Muster
                          hierher reichen.** Die Erzwingung bleibt — sie ist es, was diesem Streifen erlaubt,
                          die Einverständnis-Karte ehrlich wegzulassen, sobald eine der beiden wieder eine Tür
                          bekommt —, aber sie ist jetzt UNBEDINGT: `hasHolds` ist für `.coherent` (5/5)
                          falsch, die bedingte Form ließ also ein Muster durch, das die Bildunterschrift nicht
                          beschreibt. (b) Die Karte hing an `if !pacer.isRunning`, gestützt auf den
                          Doc-Kommentar der Konstante („vor einer Sitzung gezeigt"). **Man lese die vier
                          Zeilen statt des Kommentars:** „atme sanft, nie pressen" und „hör auf, wenn dir
                          schwindlig wird" sind WÄHREND-Anweisungen, die zweite ist die einzige, die ein
                          unerwünschtes Ereignis benennt, und die vierte ist der von CLAUDE.md
                          vorgeschriebene Selbstbeobachtungs-Hinweis. Alle vier verschwanden genau während
                          der Sitzung. Dazu schoben sie bei jedem Start/Stopp ~7 umbrochene Zeilen ins Layout
                          — der #382-Schub, in genau dem Panel, für das #382 geschrieben wurde. Jetzt
                          unbedingt, wie in `BreathGuideView`. **Lehre: die Garantie „kann nicht vom Wortlaut
                          der Führung abweichen" deckte den WORTLAUT und nicht die SICHTBARKEIT — und die
                          Abweichung saß in der Sichtbarkeit.**
                          ⛔ **UND DIE SCHEIBE HAT DEN #485-DEFEKT EINEN COMMIT NACH #485 WIEDERHOLT.** Der
                          Start/Stopp-Knopf stand auf `.frame(minHeight: 34)` OHNE `.contentShape`, begründet
                          mit „der Nachbar-Knopf eine Zeile tiefer pinnt auch 34" — dieselbe Form falscher
                          Referenz wie #485 (`masterDoorButton`): der Nachbar hat dieselbe Auslassung und ist
                          nur nie geprüft worden. Unter `.buttonStyle(.plain)` trifft der Hit-Test den
                          GLYPHEN-Lauf des Etiketts (~15–17 pt, in #485 gemessen), der Rahmen vergrößert also
                          das LAYOUT und nicht das Ziel — unter WCAG 2.5.8s 24-pt-Boden, von HIGs 44 ganz zu
                          schweigen. Jetzt 44 + `contentShape`, mit eigenem Wächter, weil
                          `TapTargetFloorTests` eine gepinnte Liste auf ANDERE Dateien ist und nichts rot
                          geworden wäre. **Und dies ist die EINZIGE Tür zum Anhalten des Pacers.**
                          ⭐ **Der Bildschirm bleibt jetzt wach — und die Entscheidung dazu war schon
                          getroffen, nur an der unerreichbaren Fläche.** `updateKeepAwake()` führt
                          `showMeditation` in seiner ODER-Kette; diese Flagge hat keinen Setzer. Eine
                          Atem-Sitzung mit GESTOPPTEM Transport ist genau der Fall, in dem jeder andere Term
                          falsch ist — der Schirm dimmte und sperrte mitten in der Übung. `breathPacer.isRunning`
                          ist ergänzt, und zwar in EINEM Modifier (`.onChange(of: showMeditation ||
                          breathPacer.isRunning)`) statt in einem zweiten: die Kette wächst nicht (10.76.34),
                          und die tote Flagge bleibt verdrahtet statt still zu verschwinden. `isRunning`
                          kippt zweimal pro Sitzung, das Freeze-Gesetz ist also nicht berührt — es ist
                          `guidance` mit ~30 Hz, und das bleibt im Blatt.
                          ⛔ **ZWEI TEXTE WAREN ÜBERZOGEN, und der laufende war der schlimmere.** Er sagte
                          „Die Zahlen oben sind Dein Körper, der antwortet" — eine BEHAUPTUNG, an keine
                          Messung gebunden. `start` pact; es startet die Kamera nicht, und `BioStripView`
                          rendert ohne Quelle für ALLE VIER Metriken „—". Die erreichbare Folge ist: Bio-Panel
                          auf → Start → „Dein Körper, der antwortet" über vier Gedankenstrichen. Das ist
                          genau der Zustand, in dem ein App-Store-Prüfer landet (kein Gurt, keine
                          HealthKit-Freigabe, rPPG-Akquise fragil per #304/#410/#484) — die lügendes-Control-
                          Klasse, die #435 und #480 zurückgenommen haben. Jetzt „Watch HRV and coherence
                          above as you settle": eine Einladung kann nicht falsch sein. Der gestoppte Text
                          nannte 6/min „die Rate, auf die die Herzfrequenz-Zahlen oben am stärksten
                          reagieren" — was die EIGENE zitierte Wissensseite dieser App widerlegt
                          (`BioScienceInfo`: „Die genau beste Rate ist individuell — meist zwischen 4,5 und 7
                          … Echoelmusic pact und misst sie; es verordnet sie nicht"). Drei Fehler in einem
                          Nebensatz: er stülpte eine Populations-Aussage über DIESEN Nutzer, er nannte die
                          eine angezeigte Metrik, die bei 0,1 Hz NICHT gipfelt (mittlere HF in bpm — es
                          gipfelt die AMPLITUDE der Schwingung, also HRV und Kohärenz), und er ließ die
                          Absicherung weg, die die zitierte Seite bewusst trägt. Dazu nannte er ein ZWEITES
                          kuratiertes Muster: `.resonance` (4 s ein / 6 s aus) ist nicht `.coherent` (5/5) —
                          Titel und Text sagten zwei Namen für eine Sache. Jetzt wird die TECHNIK beschrieben
                          statt benannt, mit „usually" und mit „Deine eigene beste Rate ist individuell".
                          ⛔ **EHRLICHE BENOTUNG — und die erste Fassung dieses Absatzes hatte sie in der
                          SCHMEICHELHAFTEN Richtung falsch, also den #433-Defekt in genau dem Absatz, der
                          „ehrliche Benotung" überschrieben ist.** Sie behauptete „VIER rot durch Abwesenheit,
                          EINE echte Montage-Erkenntnis, DREI beidseitig grün". Die drei angeblich grünen
                          öffnen jeweils mit dem Extrahieren von `BreathCoachStrip`, das es auf dem
                          Vor-#486-Baum nicht gibt — ihre Nichtleer-Behauptung feuert zuerst, sie sind
                          ebenfalls rot, und zwar aus dem billigen Grund statt aus dem genannten. Gezählt
                          statt erinnert: **ALLE Methoden sind rot, und alle strip-lesenden wegen DERSELBEN
                          einen Abwesenheit** — eine Abwesenheit vielfach gemeldet, nicht viele Befunde.
                          (⛔ Hier stand „ALLE ACHT"; die Reviewer-Nachlese hat zwei Methoden HINZUGEFÜGT,
                          also war die Ordinalzahl einen Commit später falsch — dieselbe Lehre wie im
                          #461-Eintrag: eine Ordnungszahl überlebt nicht einmal eine Umsortierung, eine
                          Anzahl nicht einmal eine Ergänzung.) **EINE**
                          ist eine echte Montage-Erkenntnis (`testTheStripIsMountedInTheBioPanel` extrahiert
                          `bioPanel`, das auf dem Elternteil existiert, besteht seine Nichtleer-Behauptung und
                          wird auf `.contains("BreathCoachStrip()")` rot, also aus genau dem Grund, den sein
                          Name nennt).
                          ⛔ **UND DIESE BENOTUNG WAR IN DREI WEITEREN PUNKTEN FALSCH — gefunden von zwei
                          Reviewern, die den Scanner nachgebaut und jede Behauptung gegen BEIDE Bäume
                          getrieben haben.** (1) Sie zitierte „6849 Zeichen roh, 2280 gestreift" als BELEG
                          ÜBER DEN ELTERNTEIL; das sind die NACH-Zahlen, der Elternteil ist 5255/1987. Die
                          Schlussfolgerung überlebt, die Zahlen beschrieben den Baum, den der Commit gerade
                          erzeugt hatte — dieselbe Klasse wie die #473-Zeilenzahl am falschen Objekt. (2)
                          „GENAU ZWEI beidseitig grün" — es sind DREI, und der Satz zwei Zeilen darüber sagt
                          es selbst („besteht seine Nichtleer-Behauptung"). Eine Tatsache behauptet und im
                          eigenen Zähler weggelassen, in der schmeichelhaften Richtung. (3) Der Mechanismus
                          „die Nichtleer-Behauptung feuert" galt für FÜNF von sieben; eine feuerte früher (am
                          Struct-Scan), eine hatte GAR KEINE Nichtleer-Klammer — die eine strip-lesende
                          Methode ohne #367-Bracket, jetzt nachgerüstet. **Eine Behauptungs-Zählung wird hier
                          bewusst NICHT mehr genannt: die Datei ist nach ihrer Benotung zweimal bearbeitet
                          worden, und eine Pro-Behauptung-Bilanz ist eine Zahl, die beim nächsten Schnitt
                          abläuft.** Was nicht abläuft, ist die FORM — eine Abwesenheit, vielfach gemeldet,
                          plus eine echte Montage-Erkenntnis.
                          ⛔ **UND `SourceText.codeOnly` HAT IN DREI FASSUNGEN DREI VERSCHIEDENE URTEILE
                          BEKOMMEN, jedes zum Zeitpunkt des Schreibens gemessen und keines dauerhaft.** (1)
                          Der Entwurf schrieb, der Montage-Kommentar nenne `BreathCoachStrip` in Prosa, der
                          Stripper sei damit tragend — falsch, der ROHE Text enthielt den Namen genau einmal,
                          und das war der echte Aufruf; das ist der exakte Überclaim, den #484 EINEN Zyklus
                          zuvor zurücknehmen musste. (2) Die Rücknahme schrieb „prophylaktisch, gestreift
                          gegen roh 0 Abweichungen" — beim Schreiben wahr. (3) **Heute ist er TRAGEND, und
                          zwar gemessen:** der Wächter behauptet die ABWESENHEIT von
                          `if pacer.pattern.hasHolds`, und dieselbe Scheibe schreibt genau diese Zeichenkette
                          in einen Rücknahme-Kommentar in `BreathGuideView.swift`, der erklärt, warum die
                          bedingte Form ersetzt wurde. Roh: vorhanden. Gestreift: abwesend. Ohne den Stripper
                          ist die Behauptung auf KORREKTEM Code rot. **Die Lehre ist die Umkehrung der
                          üblichen: ein negativer Scan und ein Rücknahme-Kommentar, der das Zurückgenommene
                          BEIM NAMEN nennt, kollidieren per Konstruktion — weil dieses Repo aufschreibt, was
                          es entfernt hat. #453s geteilte Definition ist es, was das Schreiben von beidem
                          überhaupt zulässt.**
                          ⚠️ **Und die Grenze zuerst: JEDE Behauptung ist ein QUELLTEXT-SCAN.**
                          `BreathCoachStrip` liegt hinter `#if canImport(SwiftUI)` und bezieht `pacer` per
                          `@Environment`; von hier ist nichts renderbar. Dass der Streifen am Gerät erscheint,
                          dass der Kreis sich wie ein Atem liest, dass ~6/min sich richtig anfühlt und dass
                          ein Mensch ihm folgen kann, sind ALLE Geräteproben und ALLE offen. Nichts hier sagt,
                          dass die Übung wirkt — nur, dass sie da ist, vom geteilten Pacer gepact wird und
                          quelltext-seitig sicher ist.
                          ⚠️ Und eine EHRLICHE GRENZE der Fähigkeit selbst, festgenagelt statt behoben: die
                          Führung stoppt auf `onDisappear`, man kann also nicht mit eingeklapptem Panel
                          weiteratmen. Das ist die sichere Richtung — ein unsichtbar laufender Pacer ist ein
                          Zustand, den niemand sehen oder stoppen kann —, aber es IST eine Grenze.
                          `testTheGuideCannotRunInvisibly` macht ihr Entfernen zu einer Entscheidung statt zu
                          einer Nebenwirkung.
                          ⚠️ **DREI WEITERE GRENZEN, alle von der Nachlese gefunden, alle benannt statt
                          behoben.** (1) `onDisappear` deckt NICHT alles: SwiftUI feuert es nicht für eine
                          Ansicht hinter einem präsentierten `.sheet`/`.fullScreenCover`, und
                          `EchoelStudioView` trägt 14 davon — eines zu öffnen lässt den Pacer laufen, mit
                          seinem einzigen Stopp-Knopf unerreichbar. Löst sich beim Schließen von selbst,
                          gehört aber genannt, weil der Absatz darüber die Eigenschaft ALLGEMEIN behauptet
                          hatte. (2) **VoiceOver kann der Führung überhaupt nicht folgen:** der Kreis ist
                          korrekt `accessibilityHidden`, die Takt-Information lebt damit ganz in
                          `pacer.instruction`, und das trägt weder `.updatesFrequently` noch eine
                          Live-Region — ein blinder Nutzer bekommt einen Start-Knopf und einen Satz. Von
                          `BreathGuideView` geerbt, nicht hier eingeführt. (3) Reduce Motion ist GRÖBER als
                          im Vorbild: die Vollbild-Führung hält eine lebende Prozentzahl im statischen Kreis,
                          hier bleibt nur die Phasen-Anweisung (alle 4 s / 6 s) — man weiß OB, nicht WO.
                          ⚠️ **FOUNDER-FRAGE, die diese Scheibe ERST BEANTWORTBAR macht (#487):** CLAUDE.mds
                          Sicherheits-Liste bindet „nicht beim Führen von Fahrzeugen" und „nicht unter
                          Alkohol/Drogen" an BRAINWAVE-ENTRAINMENT, und `EntrainmentEngine` ist unmontiert —
                          strikt gelesen gelten sie also nicht. Aber #486 ändert die Prämisse, auf der diese
                          Lesart ruhte: **zum ersten Mal ist überhaupt ein entspannungs-induzierender Pacer
                          erreichbar, und zwar aus der HAUPT-Performance-Ansicht**, also im Auto, auf der
                          Bühne, überall. Ich behaupte nicht, dass die Zeilen nötig sind; ich behaupte, dass
                          die Frage vorher gegenstandslos war und es jetzt nicht mehr ist. Gehört neben #450
                          (ob der kuratierte Satz überhaupt einen Raten-Boden haben soll).),
                          davor „198" nach `TheVoiceIsOnTheBoardTests.swift` (#485 — der erste Wächter in dieser
                          Kette über einer TÜR statt über einem Wert, einer Größe oder einer Dauer, und der
                          erste, dessen ehrliche Benotung lautet: **er fängt rückwärts fast nichts.** Founder
                          2026-08-07: Training für kohärentes Atmen plus Chanten · Summen · Tönen · Singen,
                          und das „braucht einen zusätzlichen Mixer-Slot für Audio-in".
                          ⭐ **Die FÄHIGKEIT war seit #298/#299 fertig — Monitoring mit FeedbackGuard-Duck,
                          Session-Claim, Pegel, Latenz-Hinweis pro Route.** Gefehlt hat, dass ihre einzige Tür
                          hinter dem MASTER-Panel saß, also UNTER der Summe der Ebenen statt NEBEN ihnen. Damit
                          war die eine Ebene, die ein Performer mit dem eigenen Körper macht, die einzige
                          klingende Ebene, die auf dem Brett fehlte, das #330 gebaut hat, um jede klingende
                          Ebene zu halten. Die Scheibe fügt eine TÜR hinzu, keine zweite Kopie: beide Zeilen
                          lesen und schreiben die EINE `AudioEngine`, genau wie der Click-Streifen die EINE
                          `MetronomeVoice`.
                          ⚠️ **`feedbackGuardActive` wird ABSICHTLICH nicht gelesen.** Die Flagge wird aus
                          dem ~15-Hz-Meter-Poll geschrieben, ein Lesezugriff meldete also einen Rumpf für die
                          Dauer des Monitorings als 15-Hz-Beobachter an — und die fünf Streifen dieses Bretts
                          tragen acht ziehbare `EchoelValueField`s, also eine lebende Scrub-Anker-Gefahr
                          (#375/#376), nicht bloß verschwendete Arbeit.
                          ⛔ **UND DIE ERSTE FASSUNG NANNTE DEN FALSCHEN RUMPF — den EINEN Fehler, den
                          `EchoelStudioView` an anderer Stelle schon ausdrücklich zurücknimmt, hier einen
                          Commit später wieder eingesammelt.** Sie schrieb: `mixStripCard` nimmt einen
                          NICHT-escaping `@ViewBuilder`, der Inhalt werde also „INNERHALB `mixerPanel`
                          ausgewertet, also innerhalb des Rumpfes, der jeden `.menu`-Picker des Instruments
                          beherbergt … der 10.76.41/50-Freeze wörtlich". Die Prämisse stimmt, die
                          Schlussfolgerung folgt nicht: ZWEI escaping-Grenzen liegen darüber — `mixerPanel`
                          geht durch `panel("Mix", …)` in `EchoelPanel`, das seinen Builder in seinem EIGENEN
                          Rumpf auswertet, und die Streifen sitzen in `AdaptiveCardGrid`, das dasselbe tut.
                          Der Lesezugriff landet auf `AdaptiveCardGrid`, NIE auf `EchoelStudioView.body`. Und
                          dieses Panel beherbergt **null** `Picker` und **null** `.menu` (gemessen), es gibt
                          dort also gar nichts abzureißen. Die ehrliche Größe stand längst im Baum, von der
                          #298-Nachlese an `AudioEngine.updateFeedbackGuard` geschrieben: *„No `.menu` Picker
                          lives in that sheet, so this was never the 10.76.50 freeze — but it is the same
                          mechanism."* #485 hat daraus „der Freeze wörtlich" gemacht. **Lehre, und sie ist
                          nicht die übliche Stale-Zahl-Lehre: eine Begründung, die im selben File bereits als
                          ⛔-Rücknahme steht, wird trotzdem neu erfunden, wenn sie sich dramatisch liest.**
                          Die ENTSCHEIDUNG (Flagge nicht lesen) ist von der Korrektur unberührt; beide
                          Reviewer fanden es unabhängig, jede Behauptung ist von mir nachgemessen.
                          ⭐ Und der Toggle darf nicht lügen: `setInputMonitoring` gibt `Bool` zurück und
                          `isInputMonitoring` ist `private(set)`, bleibt bei verweigerter Mikrofon-Berechtigung
                          also false — ohne einen Schreibvorgang auf beobachtbaren Zustand zeigte der Schalter
                          weiter „an" über einem Mikrofon, das niemand liest. Ein `@State micMonitorRefused`
                          invalidiert den Rumpf, die Bindung liest neu, der Schalter fällt zurück UND sagt
                          warum. (`AudioInputPickerView` bekommt dieselbe Invalidierung gratis aus dem
                          `inputs.refresh()`, das es aus einem ANDEREN Grund ruft — wissenswert, bevor jemand
                          das hier per Kopieren jener Aufrufstelle „vereinfacht".)
                          ⚠️ Das Pegel-Feld steht auch bei ausgeschaltetem Monitoring da, und das ist kein
                          totes Bedienelement: `inputMonitorGain`s `didSet` schreibt den Mixer nur im Betrieb,
                          `setInputMonitoring(true)` wendet den gespeicherten Wert beim Einschalten an — die
                          Zahl IST also der Pegel, den man bekommt. NICHT persistiert, und das ist eine
                          Entscheidung: ein Monitor-Gain ist ein Rückkopplungsrisiko, jeder Start beginnt beim
                          konservativen 0,6 statt bei dem, was ein anderer Raum gebraucht hat.
                          ⛔ **EHRLICHE BENOTUNG — und die erste Fassung war zu HART gegen sich selbst, was
                          derselbe Defekt ist wie zu weich.** Sie schrieb „FÜNF der sechs Methoden … alle fünf
                          aus DEMSELBEN billigen Grund … EINE Abwesenheit, fünfmal gemeldet. Der Wert der
                          Datei liegt vollständig VORWÄRTS." Es sind VIER dieser Art, nicht fünf, und beide
                          Reviewer haben es unabhängig gemessen: `testTheMicStripIsMountedInsideTheMixBoard`
                          extrahiert `mixerPanel`, das auf dem Elternteil existiert und 4427 Zeichen lang ist
                          — seine Nichtleer-Behauptung BESTEHT, rot wird es an `.contains("micMixStrip")`,
                          also aus genau dem Grund, den sein Name nennt. Ein echter Mount-Befund. Der Fehler
                          ging in die SICHERE Richtung, aber die eigenen Belege zu UNTERschätzen ist derselbe
                          #433-Defekt wie sie zu überschätzen — und er stand im Absatz mit der Überschrift
                          „gezählt statt erinnert". **Stand jetzt: SIEBEN Methoden** (die Nachlese fügt den
                          `@ViewBuilder`-Pin und die Engine-Torung der Fehlermeldung hinzu), sechs rot gegen
                          den Vor-#485-Baum, davon fünf Abwesenheits-Artefakte und einer ein echter Befund.
                          ⛔ **UND `SourceText.codeOnly` STAND IM ERSTEN ENTWURF ALS „LOAD-BEARING" — der exakte
                          Überclaim, den #484 EINEN Commit zuvor zurücknehmen musste, wiederholt in der Datei,
                          die ihn zitiert.** Gemessen statt behauptet: gestreift gegen roh unterscheiden sich
                          die Verdikte von **0 der 17** Behauptungen (15 vor der Nachlese). Der Grund gehört
                          aufgeschrieben, weil er nicht offensichtlich ist und aufhören wird zu gelten: der
                          Extraktor ankert auf der DEKLARATIONS-Zeile, und der Doc-Block — der die Flagge sehr
                          wohl nennt, **EINMAL**; die erste Fassung dieses Satzes schrieb „zweimal", und
                          `grep -c feedbackGuardActive` über die ganze Datei liefert 1 — steht DARÜBER, also
                          außerhalb jedes extrahierten Blocks. Der Rumpf trägt heute keine
                          Kommentare. Wer einen hinzufügt, der die Flagge nennt, macht den Stripper zum
                          Einzigen zwischen diesem Wächter und einem durch Prosa erkauften Grün.
                          ⛔ **ZWEI ECHTE DEFEKTE FAND DIE NACHLESE ZUSÄTZLICH, beide in der Fläche selbst.**
                          (1) Die Fehlermeldung hing allein an `micMonitorRefused`, und das erzeugte einen
                          SICHTBAREN Widerspruch: hier verweigern → „Choose input…" öffnen → dort erlauben und
                          einschalten (`AudioInputPickerView` kennt dieses `@State` nicht) → schließen — und
                          die Karte zeigte den Toggle AN zusammen mit „could not start". Zwei Türen auf EINE
                          Engine mit einem ungeteilten Stück View-Zustand, also genau das, was die
                          „Tür-statt-Kopie"-Formulierung verhindern soll. Jetzt zusätzlich auf
                          `!audioEngine.isInputMonitoring` getort — die Engine ist die eine Quelle der
                          Wahrheit dafür, ob gerade gehört wird. (2) Der „Choose input…"-Knopf war ein nacktes
                          `Text` unter `.buttonStyle(.plain)`, also ~15–17 pt Trefferfläche, unter HIG 44 und
                          unter WCAG 2.5.8 24 — während die ANDERE Tür zu demselben Sheet (`masterDoorButton`)
                          seit jeher 34 pt plus volle Breite hat. `TapTargetFloorTests` ist eine gepinnte
                          Liste und kein Sweep, es wurde also nichts rot.
                          ⚠️ **Und eine Behauptung ist ENGER gefasst statt gestrichen:** „der Toggle darf nicht
                          lügen" gilt für die zwei genannten Fälle (Berechtigung verweigert, kein gültiges
                          Eingabeformat) — nachgemessen: kein Pfad gibt `false` zurück, nachdem er
                          `isInputMonitoring = true` gesetzt hat. Es gibt aber einen Pfad, der `true`
                          zurückgibt, ohne dass etwas zu hören ist: `wasRunning` wird gefangen, und der
                          Neustart-Zweig entfällt komplett, wenn die Engine gestoppt war. Vorbestehend in
                          `AudioEngine`, von `micMonitorRefused` NICHT abgedeckt, jetzt am Ort benannt.
                          ⚠️ Und die Grenze zuerst: alle Behauptungen sind QUELLTEXT-SCANS. Dass der Streifen
                          rendert, dass der Schalter ein echtes Mikrofon fasst, dass der Duck hörbar ist und
                          dass Selbstmonitoring über diese Route latenz-erträglich ist, sind Geräteproben —
                          alle offen.),
                          davor „197" nach `AStalledAcquisitionSaysSoTests.swift` (#484 — der erste Wächter in
                          dieser Kette über einer DAUER: über etwas, das kein Einzelbild und kein Einzelwert
                          zeigen kann. Gerätelog 2490 lief 97 s Kamera-Akquise ohne Lock und ohne
                          Wechsel der Meldung. ⭐ **Und das Aufschlussreichste ist, dass die OBERFLÄCHE NICHT
                          GELOGEN HAT** — meine erste Lesung des Logs behauptete das Gegenteil und war
                          nachprüfbar falsch. Jede gezeigte Sache war ehrlich. Gefehlt hat nicht Wahrheit,
                          sondern ZEIT: keine Fläche wusste, wie lange die ehrliche Meldung schon dieselbe
                          war. **Lehre, verschieden von den Wahrheits-Scheiben dieses Absatzes: eine Reihe
                          für sich wahrer Aussagen kann als Gruppe irreführen, und kein Wächter über einer
                          EINZELNEN Behauptung sieht das.**
                          ⛔ **UND DIE BELEG-LISTE DIESER SCHEIBE WAR SELBST ZU STARK — in drei Artefakten
                          gleichzeitig (hier, Dateikopf des Wächters, Quellkommentar).** Sie zählte VIER
                          unabhängige Prüfungen auf; es sind **DREI**. (1) „nur Logdatei, **nie gerendert**"
                          ist falsch: die erreichbare „Diagnostics"-Zeile in `EchoelStudioView` rendert
                          `EchoelCrashLog.currentLog()`, `SafeModeView` die Vorsitzung — die schärfere Lesung
                          ist, dass das opt-in-Diagnose-Blatt plausibel der WEG war, auf dem diese Zeile einen
                          Menschen erreicht und in die Irre geführt hat. (2) „`signalQuality` hat null
                          Verbraucher": zu stark — null **UI**-Verbraucher, einen Breadcrumb-Verbraucher.
                          (3) `displayBPM` nie vorgerückt UND `isLocked` durchgehend falsch sind **DIESELBE
                          Tatsache**: beide sind byteweise `pulseTrustworthy`, können also gar nicht
                          auseinandergehen. **Eine Korroborations-Liste mit einer Dublette korroboriert
                          weniger, als sie aussieht** — und diese Liste stand ausgerechnet unter der
                          Überschrift „ich habe geprüft statt angenommen".
                          ⭐ EINE DEFINITION: `acquisitionCue` ist jetzt zwei Schichten — `placementCue`
                          (augenblicklich: was stimmt mit dem Kontakt gerade nicht) plus die Dauer-Aufwertung
                          darüber. Der Publish-Tick setzt die Stall-Uhr zurück, indem er
                          `placementCue != .finding` FRAGT, statt Helligkeit / Bewegung / Amplitude / Lock
                          erneut zu prüfen — Tick und Schirm können also nie uneins darüber sein, was
                          `.finding` ist (#416). Drei Verhaltensweisen fallen aus dieser einen Zeile heraus,
                          statt eigenen Code zu brauchen: ein Lock setzt das Fenster zurück, der
                          Berechtigungsdialog zählt nicht mit, und wer eine Minute gegen `.tooBright` kämpft,
                          beginnt seine 45 s ab dem Augenblick, in dem der Kontakt endlich gut wird.
                          ⚠️ WANDUHR, nicht `frame.timestamp` — #434 hat genau diese Verwechslung eine Datei
                          weiter bezahlt: ein Frame-Stempel steht still, genau wenn eine Dauer gebraucht wird.
                          Und `stop()` räumt die Anker auf ihren „kein Take"-Sentinel, #454s Gesetz ein Feld
                          später — seit der Nachlese ebenso der FEHLGESCHLAGENE Start: der Zweig, der
                          `isRunning` zurücknimmt, muss die Uhr mitnehmen, sonst trägt ein untätiger
                          Publisher einen Anker ungleich null, während das Feld-Doc „0 heißt: kein Take
                          läuft" behauptet.
                          ⚠️ 45 s ist eine WAHL in einem gemessenen Fenster, kein hergeleitetes Optimum: von
                          unten begrenzt durch Akquisen, die GELINGEN (#415s ~19 s Neu-Akquise, ~32 s kalt in
                          Log 2490), von oben durch den Fehlschlag, den sie benennt (97 s). Der Wächter
                          verteidigt das FENSTER, nicht die Zahl.
                          ⚠️ ABSICHTLICH NICHT GESAGT: „nimm einen Brustgurt". `bioPanel` trägt diese Route
                          schon wörtlich. ⛔ Die erste Fassung nannte es „das Panel, das die Messkarte
                          beherbergt" und behauptete, ein VoiceOver-Nutzer erreiche die Route „unmittelbar VOR
                          der Karte" — beides falsch: das Panel beherbergt `BioStripView`, und der Gurt-Satz
                          kommt DANACH; das „unmittelbar davor" war aus einem Kommentar über den
                          Routing-Knopf geborgt. Ebenso falsch: „die Header-Kachel wird bernsteinfarben, und
                          genau das öffnet das Panel" — die FARBE öffnet nichts, sie zieht den Blick; das
                          ANTIPPEN öffnet.
                          ⭐ **DER TEUERSTE BEFUND DER NACHLESE IST EINE COMPLIANCE-KANTE, und sie war
                          unsichtbar, weil sie in einer VoiceOver-Schicht saß (#480s Lehre, eine Woche
                          später erneut bezahlt).** Die ausgelieferte erste Fassung sagte „Signal, but no
                          steady rhythm" mit dem Kurz-Etikett „No rhythm" — gerendert in einer Kachel, deren
                          Accessibility-Etikett *Heart rate* lautet. VoiceOver sprach also „Heart rate.
                          Signal, but no steady rhythm." Das ist eine Lesart von „dein Herzschlag ist
                          unregelmäßig" — und niedrige Autokorrelation bei weiter feuerndem Peak-Zähler ist
                          *auch* das, was ein unregelmäßiger Rhythmus auf einer PPG-Spur erzeugt: der Satz
                          konnte als kardiologische Beobachtung MISSVERSTANDEN und dabei zufällig RICHTIG
                          sein. Die schlechteste verfügbare Kombination für ein nicht-medizinisches
                          Instrument, und das Wort „Rhythmus" brauchte der Entwurf nie. **Subjekt beider
                          Sätze ist seither das SIGNAL, nie der Körper** (`Tests/CISmoke`-Wächter
                          `testNeitherStallVariantMakesTheBodyTheSubject`).
                          ⭐ **ZWEITER BEFUND, von beiden Reviewern unabhängig: die Klassifikation war ein
                          `&&` und musste ein `||` sein.** Sie testete `conf ≥ 0,6 && acf < 0,4`, der
                          FALSE-Zweig war damit ein Auffangbecken, das conf 0,5 / acf 0,5 mitnahm — also
                          echte korroborierte Periodizität, die bloß die Nur-Stark-Klausel nicht erreicht
                          hatte, genau das Band, für das `strongAutoFloor` existiert — und schickte diese
                          Nutzer „die Hand wärmen".
                          ⭐ **DRITTER: die Aufteilung wurde ~10 Hz NEU GERECHNET.** Beide Eingaben liegen in
                          diesem Band auf ihren Schwellen, und `CameraAnalyzer.isUncorroboratedRipple` treibt
                          die Konfidenz aktiv DURCH die 0,6-Linie (`*= 0.9` je Peak-Durchgang) — ein
                          festhängender Take wechselte also mehrmals pro Sekunde zwischen zwei Etiketten und
                          zwei ENTGEGENGESETZTEN Anweisungen. Jetzt eine LATCH (`stallWasRhythmless`), einmal
                          im Tick entschieden. Jeder andere Klassifikator dieser Datei benutzt einen Zähler
                          oder ein Fenster; dieser hatte keins.
                          ⭐ **VIERTER: `capture.isInterrupted` fiel NICHT gratis heraus.** Nichts stoppt
                          diesen Publisher auf `scenePhase`; während iOS die Session hält, friert JEDE
                          Eingabe von `placementCue` ein — ein in `.finding` eingefrorener Take rechnete die
                          GANZE Unterbrechung ins Fenster und kam mit „still nothing to read — try another
                          finger" für eine Lücke zurück, die das System verursacht hat. Dieselbe „gib dem
                          Körper die Schuld für eine System-Tatsache", die der Case entfernen soll, eine
                          Schicht tiefer.
                          ⛔ **EHRLICHE BENOTUNG — und die erste Fassung war hier schmeichelhaft.** Sie sagte
                          „nur die QUELLTEXT-SCANS konnten vor diesem Commit rot sein". Wahr ist das
                          Härtere: die Wächter-Datei lässt sich gegen den Vor-#484-Baum **überhaupt nicht**
                          benoten — jede Behauptung nennt `PulseCue.stalled`, das dort nicht existiert, das
                          Bundle kompiliert also nicht und KEINE Behauptung hat ein Verdikt. Das ist die
                          #464-Lage, klar gesagt statt verkleidet. Der Wert der Datei liegt vorwärts: die
                          Scans fangen eine spätere Entfernung, die Verhaltensfälle sind GEGENGEWICHTE gegen
                          die naheliegenden Aufräumarbeiten — `.finding` auch actionable machen (ein
                          Bernstein, das immer an ist, trägt keine Information), die Quellen-Route im Hinweis
                          wiederholen, die zwei Etiketten zusammenlegen, und zu einer Formulierung
                          zurückkehren, deren Subjekt der Körper ist.
                          ⚠️ Und `SourceText.codeOnly` ist in diesem Wächter **PROPHYLAKTISCH**, nicht
                          tragend — die erste Fassung nannte es „LOAD-BEARING". Gemessen statt behauptet:
                          gestreift gegen roh unterscheiden sich die Verdikte von **0 der 18** Quelltext-
                          Behauptungen. Es bleibt, weil #453 EINE Definition von „Code, nicht Prosa" für das
                          ganze blockierende Bundle geschaffen hat und eine private Ausnahme genau der Defekt
                          ist, den jene Scheibe entfernt hat.
                          ⚠️ Und die Grenze zuerst: die Verdrahtungs-Hälfte ist Quelltext, kein Lauf —
                          `CameraRPPGBioPublisher` liegt hinter `#if canImport(AVFoundation)`,
                          `acquisitionSince` ist `private`, und es zu treiben braucht eine Kamera. Dass 45 s
                          sich für einen Wartenden richtig anfühlen und dass die bernsteinfarbene Kachel
                          wirklich zum Panel führt, sind Geräteproben. Und die AKQUISE ist damit NICHT
                          repariert (#304/#410) — die App hört nur auf, so zu tun, als sei nichts.),
                          davor „196" nach `OneChromeControlHeightTests.swift` (#481 — der erste Wächter in
                          dieser Kette über einer GRÖSSE, und der erste, dessen Auslöser eine Behauptung war,
                          die der Quelltext selbst schon widerlegte. Founder 2026-08-07, zwei Screenshots, die
                          Transport-Zeile eingekreist: *„Die größe der Buttons anpassen, die sollen immer
                          gleichgroß sein. Orientiere dich an denen oben rechts."* Gemessen vor der Änderung:
                          `startButton` 64×56 · `PlaybackToggleButton` 44×48 · `BodyTempoField` 76×32 und Sperre
                          30×32 · `TransportOverflowMenu` 30×32 · die drei Header-Kacheln 38/38/54×32 mit
                          44er-Trefferrahmen. **Drei Höhen in EINER Zeile** — und der Kommentar an der 48
                          begründete sie mit *„Ableton's transport strip is UNIFORM-height — ours was 56 / 32 /
                          48"*, wählte dann aber eine VIERTE Zahl. Die Beobachtung war richtig, die Reparatur
                          folgte nicht aus ihr; das ist die #416-Form (eine Entscheidung, sechs Schreibstellen,
                          nichts das ihr Auseinanderlaufen merkt).
                          ⭐ Die REFERENZ ist nicht gewählt, sondern benannt: die drei Header-Kacheln waren
                          untereinander schon einig, also wird IHRE Geometrie zur einen Definition
                          (`EchoelTheme.controlHeight` 32 / `controlTapHeight` 44) und jeder Chrome-Knopf liest
                          sie. Der Trefferrahmen sitzt in der Header-Schreibweise NACH Hintergrund und Rand —
                          davor gestellt wüchse das BILD statt der Trefferfläche, also genau das Gegenteil des
                          #113-Idioms, und es sähe im Diff wie eine Reparatur aus.
                          ⚠️ Die Hälfte, die die Datei verdient, ist das GEGENGEWICHT und nicht der Pin: das
                          naheliegende Aufräumen danach ist „mach die Analyse-Pille auch gleich groß", und das
                          wäre doppelt falsch — ihr Puls-Trace ist auf 34 pt festgenagelt (passt nicht in 32),
                          und der Founder hat EINE WOCHE ZUVOR (#305, *„etwas größere Anzeige für Analyse ist
                          besser"*) genau diese Anzeige GRÖSSER verlangt. Eine Anzeige zwischen Bedienelementen
                          ist die Hardware-Grammatik, die diese Zeile kopiert. Dazu ein zweites Gegengewicht:
                          die Tempo-Sperre erreicht die 44 als EINZIGE per Outset (32 + 6 + 6), hängt also still
                          an der Konstante — steht in keiner der beiden Dateien, jetzt aber im Wächter.
                          ⚠️ `FloatingVisualLayout.startButtonHeight` ist ABSICHTLICH nicht mitgezogen: seine
                          Summe ist der Bodenabstand der angedockten Visual-Karte, und die neue 32 hineinzugeben
                          schöbe das Bild in einem Knopfgrößen-Commit um 24 pt. Der Name überschreibt damit seine
                          Aufgabe — Vermerk steht an der Deklaration und in `FloatingVisualLayoutTests`, dessen
                          Prosa („`EchoelStudioView` builds the button from the SAME three constants") sonst die
                          #456-Klasse geworden wäre.
                          ⚠️ ALLE Behauptungen sind QUELLTEXT-SCANS: dass die Zeile am Gerät EBEN aussieht und
                          dass ein Finger die 44 trifft, bleiben Sichtproben.), davor „195" nach
                          `TheFXDoorNamesAControlThatExistsTests.swift` (#480 — der erste
                          Wächter in dieser Kette über einer ACCESSIBILITY-Zeichenkette, und der erste, dessen
                          Defekt VIER ZEILEN unter seiner eigenen Widerlegung stand. Der „All parameters"-Knopf
                          in `effectsPanel` sagte VoiceOver „every parameter as a slider"; `EchoelFXView.swift`
                          deklariert NULL `Slider(` (gemessen), und der Kommentar direkt über dem Knopf war
                          eigens geschrieben worden, um genau diese Formulierung zu streichen — „NOT 'as
                          sliders' — numeric parameters are `EchoelValueField`s". Jemand hat die Prosa
                          korrigiert und den String stehen lassen.
                          ⭐ **Was diese Scheibe von den übrigen Wahrheits-Scheiben unterscheidet, ist die
                          SCHICHT.** Ein Accessibility-Hinweis ist unsichtbar, solange VoiceOver aus ist — kein
                          Screenshot, kein Design-Durchgang und kein UI-Review hätte ihn je gezeigt. Deshalb
                          konnte eine Behauptung neben ihrer eigenen Widerlegung monatelang überleben, während
                          dieselbe Klasse im sichtbaren Text regelmäßig gefangen wird.
                          ⚠️ EHRLICHE GRÖSSE, weil „VoiceOver wurde belogen" größer klingt als es ist: das ist
                          KOPIE, kein kaputtes Affordance. `EchoelValueField` installiert eine
                          `accessibilityAdjustableAction`, Wischen hoch/runter verstellt es also exakt so wie
                          einen `Slider`. Verborgen hat das falsche Wort das, was ein Slider NICHT hat —
                          Doppeltipp zum Tippen einer exakten Zahl. Jedes Feld sagt das in seinem EIGENEN
                          Hinweis, die Tür wiederholt es deshalb bewusst nicht (#416).
                          ⛔ **UND DIE KORREKTUR, DIE DEN DEFEKT GEFANGEN HAT, WAR SELBST ÜBERZOGEN** — in die
                          andere Richtung: „the app has no raw `Slider`", unqualifiziert. Es sind **ZWEI**, beide
                          der Look-Scrub (`EchoelStudioView` + `FloatingVisualWindow`), beide absichtlich und am
                          Ort begründet. Das UI-Gesetz sagt „no raw `Slider`/`Stepper` **for parameters**", und
                          ein stufenloser Morph zwischen BENANNTEN Looks ist keine Parameter-Zeile —
                          `FloatingVisualWindow` schreibt das wörtlich an seine Stelle („a live VJ control over
                          the visual, not a Studio parameter row"). Die GESCOPETE Behauptung überlebt, die
                          absolute nicht.
                          ⭐ Und die neue Formulierung ist nicht erfunden: das Panel beschreibt sich in seinem
                          eigenen sichtbaren Blurb als „filter → modulation → delay → dynamics" — dieselben vier
                          Stufen in derselben Reihenfolge. Die Accessibility-Schicht sagt seit #480 also das,
                          was die sichtbare Schicht sagt, statt etwas Drittes.
                          ⚠️ EHRLICHE BENOTUNG: von vier Behauptungen ist **genau EINE** eine Regression
                          (gemessen: auf `HEAD` rot an exakt der genannten Zeile, danach grün). Die anderen drei
                          sind GEGENGEWICHTE gegen das naheliegende Aufräumen „streich das Wort ‚Slider' aus der
                          Kopie" — das nähme die EHRLICHE Look-Scrub-Kopie mit und ließe den einen echten
                          `Slider` des Instruments für VoiceOver unbenannt. Eines davon nagelt das UI-Gesetz
                          selbst fest: genau ZWEI rohe `Slider(` in `Sources/`, beide auf `lookScrub`, und NULL
                          `Stepper(`.
                          ⚠️ Alle vier sind QUELLTEXT-SCANS: dass VoiceOver den Satz spricht, dass der Knopf am
                          Gerät erreichbar ist und dass die neue Formulierung sich VORGELESEN gut liest, bleiben
                          Geräteproben. Die Erreichbarkeit ist stattdessen von Hand gemessen — `effectsPanel`
                          kommt aus `dropdownContent` für `.effects` (Effects-Chip), und `showAllFX` hat genau
                          einen Setzer.
                          ⚠️ Der SF-Symbol-Name `slider.horizontal.3` auf dem Knopf ist ausdrücklich erlaubt und
                          KEIN Defekt: es ist das übliche Glyph für „Parameter" (SF Symbols hat keines für ein
                          Zahlenfeld), und ein Symbolname ist keine Behauptung über einen Bedienelement-Typ.
                          Nicht auf Grundlage dieser Datei „reparieren"),
                          davor „194" nach `RequestedDrumVelocityIsTheEmittedByteTests.swift` (#474 — der erste
                          Wächter in dieser Kette, der GANZ VERHALTENSBASIERT ist: `MIDIFileExporter` ist
                          `public`, Foundation-only und deterministisch, also treibt jede der sechs
                          Behauptungen die ausgelieferte Funktion und liest die ausgelieferten Bytes. Kein
                          Quelltext-Scan, und das ist selten genug, um es hinzuschreiben.
                          ⭐ **Der Defekt war eine ARGUMENT-BEDEUTUNG, die sich zwischen zwei Überladungen
                          gespalten hatte.** `drumEvents` teilte ±20 um `velocity`, damit die Dynamik einer
                          akzentuierten Figur den Export überlebt — bei LEERER `accents`-Liste nahm aber jede
                          Zelle den leisen Zweig, ein Aufrufer mit 100 bekam überall 80, und die verlangte
                          Zahl stand nirgends in der Datei. Die Type-0-Überladung `export(steps:tempo:velocity:)`
                          hat gar keine Akzente und lieferte `velocity` immer wörtlich: **zwei Exporter
                          desselben Rasters, ein Argumentname, zwei Bedeutungen.** Ohne Akzent-Information gibt
                          es keine Dynamik zu bewahren, nur ein erfundenes Leiser.
                          ⚠️ Die NAHT ist `accents.isEmpty` und nichts Feineres, und ein Gegengewicht nagelt
                          genau das fest: ein VORHANDENES Akzent-Array, dessen Zellen alle `false` sind, behält
                          die −20. Der Aufrufer hat etwas gesagt („keine davon ist akzentuiert"); wer gar keins
                          liefert, hat nichts gesagt. Die Naht zu weiten ist eine zweite Entscheidung.
                          ⚠️ EHRLICHE BENOTUNG: von sechs Behauptungen sind ZWEI Regressionen (der Defekt und
                          seine Property-Fassung), vier sind GEGENGEWICHTE und beidseitig grün — denn das
                          naheliegende Aufräumen danach lautet „der Exporter liefert, was man verlangt, weg mit
                          dem Split", und das würde jede wirklich akzentuierte Figur still einebnen.
                          ⚠️ Und die Grenze zuerst: **kein Export, den ein Nutzer heute erzeugen kann, ändert
                          sich** — gemessen, nicht angenommen: `export(clip:)` hat null Aufrufstellen in
                          `Sources/`, und der EINE lebende `exportCombined`-Aufruf (die MIDI-Export-Tür in
                          `Studio/EchoelStudioView.swift`) übergibt `steps: []`, `drumEvents` sendet also gar
                          nichts. Geändert wird der VERTRAG einer schlafenden API.
                          ⛔ Der Quellkommentar, den #474 ersetzt, behauptete das Gegenteil („it would alter
                          shipped export bytes") — drei Absätze nachdem er selbst festgestellt hatte, dass der
                          Pfad keinen lebenden Aufrufer hat. Eine Behauptung neben ihrer eigenen Widerlegung,
                          die Klasse, die diese Datei überall sonst zurücknimmt),
                          davor „193" nach `TheNoteEngineOutlivedItsEditorTests.swift` (#475 — der erste Wächter in dieser
                          Kette über einer LÖSCHUNG, deren gefährliche Hälfte das ÜBERLEBENDE ist. Der Founder hat den
                          Noten-Editor am 2026-07-26 gestrichen; #178 nahm die Tür, #470 hob das eine Gesetz heraus, das
                          die Löschung sonst mitgenommen hätte, und #475 löscht die 987-Zeilen-`struct PianoRollView: View`
                          plus `RollDragAnchor`/`RollDrag`. **Die DATEI bleibt**, weil `PianoRollModel` darin liegt — die
                          Notenmaschine UND der `MusicalFrame`-Publisher, an dem Visual, Licht und Raum hängen.
                          ⭐ **Deshalb ist genau EINE der fünf Behauptungen eine Regression** (`testTheEditorStructIsGone`,
                          rot auf jedem Vor-#475-Baum); die anderen vier sind GEGENGEWICHTE, beidseitig grün, und sie sind
                          der eigentliche Zweck: ein Lösch-Commit, der nur „das Ding ist weg" behauptet, lädt die nächste,
                          größere Löschung ein. Festgenagelt wird das, was NIE gehen darf — Modell, Publish, der
                          Start-Installierer in `EchoelmusicApp`, und beide Hälften des Playback-only-Stopps.
                          ⚠️ Die Reihenfolge der Scheibe ist die Lehre und nicht die Löschung: VOR dem Schneiden wurde
                          geprüft, welche Wächter über der Fläche liegen (#456), und **ZWEI** wären rot geworden —
                          `EveryReachableRowStatesItsGridTests`, dessen Rückwärts-Prüfung („die Erlaubnisliste darf ihre
                          Einträge nicht überleben") auf die „Vel"-Zeile des Rolls zeigte, UND die dritte Behauptung von
                          `TheUnitToPeriodLawSurvivesTheViewTests`, die das Vorhandensein der Aufrufstelle in der
                          Ansicht verlangte. Beide im selben Commit mitgezogen.
                          ⛔ **Diese Zeile sagte „genau EINER", und der Commit-Text auch — nicht weil jemand falsch
                          gezählt hätte, sondern weil die zweite unter einer anderen Überschrift stand („verliert ihre
                          dritte Behauptung") und dadurch aus der Bilanz fiel. Der Vorgang war korrekt, die BUCHFÜHRUNG
                          nicht. **Lehre, verschieden von den Zähl-Lehren dieses Absatzes: eine Behauptung, die man
                          ZURÜCKZIEHT, ist trotzdem eine, die rot geworden wäre** — wer sie in einen eigenen Satz
                          auslagert, meldet der nächsten Sitzung eine kleinere Wächter-Dichte, als das Repo hat.
                          ⛔ **UND NACH dem Schneiden kam der Rest — die #472-Lehre, wörtlich angewandt.** `git grep`
                          fand DREI verwaiste Nachbarn (`RollHitTest` und `RollFitMath` mit null Produktions-Aufrufern,
                          `RollNoteOps` überlebt mit einem), **sechs** aufruferlose `PianoRollModel`-Mitglieder, und in
                          `TheUnitToPeriodLawSurvivesTheViewTests` eine dritte Behauptung, deren eigene Fehlermeldung die
                          Anweisung für genau diesen Fall trug („if the call site went away too, this assertion should be 
                          deleted together with the lane, deliberately"). Zurückgezogen statt gelockert.
                          ⛔ **Und die SECHS sind mit der falschen Methode ZWEIMAL falsch gezählt worden, in beide
                          Richtungen — das ist der lehrreichste Teil der ganzen Scheibe.** Ein
                          `\b<name>\b`-Sweep gab `audition` 37 Treffer in `Sources` — alle unbeteiligte Prosa über
                          `BeatPlayer`s Sample-Audition — und `musicalKey` sechs, die eine LOKALE VARIABLE in
                          `NoteNamingTests` sind. Nachgezählt auf der wörtlichen AUFRUF-Form (`audition(pitch:`,
                          `stampChord(`, …), und der eine überlebende `isSharp(`-Treffer entpuppte sich als TEST-
                          METHODENNAME. **Ein namensförmiger grep beantwortet eine Frage über NAMEN; „ruft das jemand"
                          ist eine andere Frage.**
                          ⛔ **UND DANN HAT GENAU DIESE DISZIPLIN AUF DEM EINEN MITGLIED UNTER-GEZÄHLT, ZU DEM SIE
                          NICHT PASST.** Die Liste stand auf SIEBEN und enthielt `pitchCount`. Das ist ein
                          gespeichertes `let`, keine `func` — es HAT keine Aufruf-Form —, und es wird EINE Zeile unter
                          der eigenen Deklaration gelesen: `public static var highPitch: Int { lowPitch + pitchCount
                          - 1 }`. `highPitch` ist sehr lebendig (u. a. `foldToBar` auf dem LIVE-MIDI-Import-Pfad).
                          **Die Lehre ist nicht „sorgfältiger zählen" — sie ist, dass eine gegen ÜBER-Zählung getunte
                          Regel auf den Mitgliedern, für die sie nicht entworfen wurde, FALSCH-NEGATIVE produziert.
                          Eine Eigenschaft ist keine Funktion; miss sie als Eigenschaft.**
                          ⚠️ Alle fünf Behauptungen sind QUELLTEXT-SCANS: dass die
                          Ausgabestufe wirklich Frames bekommt, entscheidet ein Geräte-Lauf.
                          ⚠️ Und der Skip gattert auf das VERZEICHNIS, nicht auf die Dateien — die #472-Reviewer-Auflage,
                          hier von Anfang an eingebaut: eine `fileExists`-Klammer um jeden Lesevorgang machte aus genau
                          der Katastrophe, gegen die diese Datei steht, ein grünes SKIP),
                          davor „192" nach `TheAutomationRowLawHasItsOwnFileTests.swift` (#472 — der ZWEITE
                          Hoist-Wächter in zwei Zyklen, und der erste, dessen eigentlicher Ertrag ein
                          BLOCKER ist, den vorher niemand aufgeschrieben hatte. Der Hoist selbst ist die
                          #470-Form: `TimelineAutomationRowMath` — rein, Foundation-only und in Produktion
                          von `Core/TimelineStore.swift` gelesen — lag in
                          `Studio/TimelineAutomationRow.swift`, dessen andere 344 Zeilen (gezählt ab `#if canImport(SwiftUI)`) eine Ansicht sind,
                          die nichts montiert. Genau die Falle, die das Register drei Bildschirme weiter
                          oben von Hand benennt: „türlos" ist eine Eigenschaft der ANSICHT, „löschbar" eine
                          der DATEI, und ein „lösch die türlose Datei"-Aufräumen hätte den Store gebrochen.
                          Jetzt getrennt; die Arithmetik ist unverändert.
                          ⭐ **DER FUND IST NICHT DER HOIST, SONDERN WARUM DIE LÖSCHUNG TROTZDEM NICHT
                          KOMMT.** Das Register sagt „die richtige Scheibe ist das Herausheben des reinen
                          Kerns, DANN die Löschung der Ansichts-Hälfte", und der Dateikopf der Ansicht sagt
                          seit #121, sie „retires in the Slice 6 cleanup". Beide sind älter als das, was
                          wirklich blockiert: **FÜNF Quelldateien zitieren diese Ansicht in Prosa, und zwei
                          der Zitate tragen Code, der ausgeliefert wird.** `Studio/EchoelValueField.swift` —
                          das EINE app-weite Parameter-Bedienelement — zitiert die Ansicht ZWEIMAL, mit
                          ZWEI VERSCHIEDENEN Prämissen. ⛔ Hier stand „zeigt ZWEIMAL auf
                          `TimelineAutomationRow.handleEnded`"; nur EINES der beiden tut das (der Block
                          `REVERT — one main-actor turn later`, dessen Prämisse ist, dass `onEnded` NACH
                          einem `@GestureState`-Reset geliefert werden kann — die Grundlage des
                          #377/#378-Revert-bei-Abbruch-Entwurfs). Das andere (`⚠️ HONEST LIMIT
                          (unchanged):`) nennt die Ansicht ohne Mitglied, für die Eigenschaft, dass SwiftUI
                          beim Zurücksetzen eines `@GestureState` NEU AUSWERTET — die erklärte Grenze
                          desselben Entwurfs. Zwei Prämissen blockieren HÄRTER als ein doppeltes Zitat; die
                          Korrektur weicht nichts auf, sie verhindert die Suche nach einer zweiten
                          `handleEnded`-Stelle, die es nicht gibt. `DSP/EchoelDDSP.swift` benutzt die
                          Türlosigkeit der Zeile als Prämisse in seiner `outputLevel`-Erreichbarkeits-
                          Argumentation, und `Core/AutomationPlayer.swift` trägt eine ⛔-Rücknahme, die die
                          Zeile NAMENTLICH nennt — eine Rücknahme, deren ganzer Wert das Benennen ist. Den
                          Wirt zu löschen, ohne diese Prosa vorher umzusiedeln, ist der #456-Defekt in
                          dreifacher Größe: eine lebende Datei, die auf eine Erklärung zeigt, die es nicht
                          mehr gibt, liest sich als „die Regel wurde zurückgezogen". **Lehre, und sie ist
                          allgemeiner als dieser Fall: eine registrierte Entblockung ist erst dann eine
                          Entblockung, wenn man NACH dem Ausführen noch einmal grept — #472 hat den
                          Kern-Blocker entfernt und dabei einen zweiten gefunden, den dieselbe
                          Register-Zeile nicht kannte.**
                          ⚠️ EHRLICHE BENOTUNG: von fünf Behauptungen ist EINE eine Regression im
                          gewöhnlichen Sinn (`testTheLawHasItsOwnFileAndTheOldViewIsGone` — bei #472 hieß er
                          noch `…AndTheViewNoLongerDeclaresIt`; #473 hat ihn umbenannt, weil der alte Name
                          ein Verfahren beschrieb, das der Code nicht mehr nimmt, und diese Zeile im selben
                          Commit mitgezogen, weil eine Register-Zeile, die auf eine umbenannte Methode
                          zeigt, exakt die #456-Klasse ist), deren
                          erste Hälfte eine Datei liest, die es vor diesem Commit nicht gab. Der Rest sind
                          Pins: die lebende Aufrufstelle, das Alias-Verhalten, und ein COMPILE-Pin auf die
                          **sieben** Mitglieder, die mit der Ansicht ihren einzigen Aufrufer verlieren. Keine
                          davon konnte gestern rot sein. ⛔ Hier stand „fünf", und der Widerspruch war
                          INNERHALB dieser Datei: der #475-Eintrag zwei Bildschirme weiter oben sagt an
                          derselben Sache „**sieben**", und der Wächter selbst nennt sie SEVEN und zählt sie
                          im eigenen Doc-Kommentar auf. Gemessen statt erinnert:
                          `grep -n "public static" Sources/Echoelmusic/Sequencer/TimelineAutomationRowMath.swift`
                          liefert ACHT, davon ist `sameParameter` der eine mit Produktions-Aufrufer — also
                          sieben. **Der Fehler ist nicht die veraltete Zahl, sondern dass sie neben ihrer
                          eigenen korrekten Fassung stand**: zwei Stellen desselben Absatzes über dieselbe
                          Messung, und nur eine wurde beim Schreiben nachgezählt.
                          ⚠️ Und die Verhaltens-Hälfte DOPPELT `Tests/EchoelmusicTests/TimelineAutomationRowTests`
                          mit Absicht — normalerweise der #416-Defekt. Der Grund, warum sie es hier nicht
                          ist: jene Suite ist die NICHT-blockierende (#208), und `sameParameter` ist das
                          einzige Mitglied dieses Typs mit einem Produktions-Aufrufer. Ein Gesetz, das
                          entscheidet, welche Automationsspur ein Parameter trifft, soll einen Merge rot
                          färben können.
                          ⛔ **UND DIE PLATZIERUNGS-BEGRÜNDUNG WAR IN DREI DATEIEN GLEICHZEITIG FALSCH**
                          (neue Quelle, Ansichts-Kopf, Wächter): „next to the `AutomationCanvasMath` and
                          `AutomationTarget` it composes with". `AutomationTarget` steht in
                          `Core/AutomationPlayer.swift`, nicht in `Sequencer/`. Gefangen, indem die
                          Deklaration nachgeschlagen wurde statt einem Satz zu glauben, der sich gut las —
                          dieselbe Klasse wie die +∞-Behauptung in #470, nur eine Ebene abstrakter. Die
                          ehrliche Fassung: ZWEI von drei Kollaborateuren (`AutomationCanvasMath`,
                          `AutomationPoint`) liegen in `Sequencer/`, der dritte beim VERBRAUCHER — die
                          Platzierung folgt der Mehrheit und ist keine reine Wahrheit.
                          ⚠️ Was der Wächter NICHT kann: zwei seiner fünf Behauptungen sind
                          QUELLTEXT-SCANS, beweisen also, wo Text steht, und nicht, dass die App etwas
                          tut. Und nichts hier sagt, dass die Automations-Zeile erreichbar ist — sie ist es
                          nicht, und #472 ändert das nicht),
                          davor „191" nach `TheUnitToPeriodLawSurvivesTheViewTests.swift` (#470 — der erste
                          Wächter in dieser Kette über einem HOIST statt über einem Wert oder einer Fläche,
                          und deshalb der erste, bei dem der Beweis vor dem Schreiben eine falsche eigene
                          Behauptung gefangen hat. `PianoRollView.occurrencePeriod(forUnit:)` war korrekte
                          Arithmetik am falschen Ort: ein `@MainActor`-View-Static in einer Ansicht, die seit
                          #178 niemand instanziiert; CLAUDE.md hält seit Wochen fest, dass genau dieses Hoisten
                          die Löschung der Ansicht entblockt. Neues Zuhause ist `RollHitTest` und nicht
                          `NoteOperators`, weil `velocity(forY:laneHeight:)` dort der EINE Erzeuger der Einheit
                          ist, die die Funktion verbraucht — Y → Einheit → Periode ist EINE Kette, und beide
                          Enden waren schon rein. Die RANGE bleibt bei `NoteOperators`: der Boden FRAGT sie,
                          statt 64 zu wiederholen.
                          ⛔ **UND DIE ERSTE FASSUNG DES WÄCHTERS WÄRE AUF KORREKTEM CODE ROT GEWESEN.** Sie
                          behauptete, JEDE nicht-endliche Einheit nehme den Boden-Zweig — „NaN-sicher per
                          Argument-Reihenfolge". Für NaN und −∞ stimmt das; **+∞ passiert den Guard**, und
                          `Int((1/∞).rounded())` ist **0**, also UNTER `periodRange`. Dasselbe gilt für jede
                          Einheit über 2. Gefunden beim Nachrechnen vor dem Commit, nicht im Review — und der
                          Doc-Kommentar an der Deklaration trug denselben Fehler. Beide sind jetzt ehrlich; die
                          Arithmetik ist ABSICHTLICH unverändert, weil #470 ein Umzug ist und eine
                          Verhaltensänderung in einem Umzugs-Commit die „nichts ändert sich"-Behauptung genau
                          dann aufhebt, wenn niemand mehr hinsieht. Gedeckt ist der ausgelieferte Pfad trotzdem:
                          `NoteOperators`' init klemmt, und `testTheShippedChainIsLegalWhereTheMapAloneIsNot`
                          nagelt genau diese Rettung fest.
                          ⚠️ EHRLICHE BENOTUNG: von den sechs Behauptungen ist **genau EINE** eine Regression
                          (`testTheViewNoLongerDeclaresItsOwnCopy`). Alle Verhaltensfälle treiben ein Symbol,
                          das DERSELBE Commit anlegt — sie konnten nie rot sein, und sie als Regressionen zu
                          verbuchen wäre der #433-Defekt in der Datei, die #433 zitiert.
                          ⚠️ Und die Grenze: die Ansicht bleibt türlos, diese Arithmetik ist aus der App also
                          weiterhin unerreichbar. Gehoben wird sie nicht, weil ein Nutzer wartet, sondern weil
                          eine türlose Kopie genau der Ort ist, an dem eine spätere Löschung aus Versehen eine
                          Entscheidung mitnimmt. Die ~995-Zeilen-Ansicht selbst zu löschen ist eine eigene,
                          founder-sichtbare Scheibe — kein Nebeneffekt eines Hoists),
                          davor „190" nach `TheFlashCeilingIsOneNumberTests.swift` (#466 — die WCAG-Blitzgrenze
                          hatte DREI unabhängige Deklarationen (`FlashGuard.maxFlashHz` kanonisch per
                          DESIGNATION, `EntrainmentEngine.maxVisualFlashHz`, `BioEntrainmentDirector.maxVisualHz`),
                          alle auf 3.0. **Kein heutiger Defekt — der Defekt ist die FORM**: eine Lockerung in
                          EINER Datei bliebe unbemerkt, und das an der einen Konstante, die CLAUDE.md unter
                          SAFETY WARNINGS führt. NICHT zusammengeführt, weil das Layering es verbietet: `Bio/`
                          referenziert kein `Studio/`, und `DSP/` ist per Hygiene Foundation-only, kann also
                          gar nicht ketten. Drift wird stattdessen ROT. ⛔ Ehrliche Benotung: zwei der vier
                          Behauptungen sind KEINE Regressionen, sie sind auf dem Vor-#466-Baum grün. Mitgenommen
                          wurde eine FALSCHE Paritäts-Behauptung an `EntrainmentEngine.minBreathsPerMinute`
                          („Matches BreathPacer/ResonanceFinder" — 4,5 gegen 5,0; nur die 7,0-Decke fällt
                          zusammen). Die ZAHL blieb absichtlich stehen: `breathTargetHz` KLEMMT auf dieses
                          Fenster, ein Anheben auf 5,0 ließe einen echt 4,6/min atmenden Körper als 5,0 lesen —
                          erfundene Zahl, Klasse #424/#426),
                          davor „189" nach `HRVIsNotWrittenToHealthTests.swift` (#463 — der erste Wächter in
                          dieser Kette über einer ENTSCHEIDUNG statt über einem Wert, und der erste, dessen
                          Grading ehrlich lautet: **KEINE der fünf Behauptungen ist eine Regression, alle
                          fünf sind auf dem Vor-#463-Baum grün.** Der Defekt war reine PROSA — und zwar in
                          zwei Dateien gleichzeitig. ⛔ **Die erste Fassung nannte als Grund „keine der
                          beiden Kopien konnte die andere widerlegen" und schrieb „Beides falsch" — und das
                          ist die schmeichelhafte Fassung, nicht die zutreffende.** `HealthKitWriter`s Kopf
                          sagte „we don't have real SDNN ms": schlicht falsch. `HealthWritePolicy`s Regel 2
                          sagte „our `hrvNormalized` is a 0…1 control value, not SDNN in ms": buchstäblich
                          WAHR — `hrvNormalized` IST ein 0…1-Regelwert — und irreführend nur durch
                          Implikatur, weil sie das eine HRV-Feld nennt, das NICHT in Millisekunden ist, und
                          den Leser schließen lässt, es gebe kein anderes. **Ein wahrer Satz als Begründung
                          ist schwerer zu fangen als ein falscher: ihm widerspricht nichts.** DREI Erzeuger
                          eines GEMESSENEN Wertes schreiben echte Millisekunden-SDNN in
                          `BioSampleFrame.hrvSDNNms`, ZWEI davon liegen schon
                          auf der Leitung (`/echoelmusic/bio/heart/sdnn` — der HealthKit-Erzeuger nicht,
                          weil `BioEgressPolicy.allowsEgress` `.healthKit`/`.watch`/`.oura` verweigert;
                          ⛔ die erste Fassung schrieb „einer davon"), und Apples Typ heißt buchstäblich
                          `heartRateVariabilitySDNN` in ms — die Plattform will exakt das, was der Kommentar
                          als fehlend behauptete. Die ENTSCHEIDUNG steht und ist richtig; nur ihre Begründung
                          war widerlegbar, und CLAUDE.md nennt genau diese Klasse: ein „NICHT tun"-Vermerk
                          mit falscher Begründung ist schlimmer als keiner, weil die nächste Sitzung die
                          Begründung widerlegt und es dann TUT — hier: ein kamera-abgeleiteter Wert in einer
                          Gesundheitsakte.
                          ⭐ **Die WAHRE Begründung ist zweiteilig und beide Hälften sind im Baum prüfbar.**
                          (1) SDNN ist kein Punktwert, sondern ein Spread über ein GENANNTES Intervall, und
                          sein Wert skaliert mit dessen Länge — dieselbe Task-Force-Tabelle, die der
                          #461-Eintrag oben schon zitiert, liest 24-h-SDNN 141±39 ms gegen einen
                          5-Minuten-SDNN-Index von 54±15 ms in derselben Population. `HealthKitWriter.write`
                          stempelt `start: date, end: date`. Für eine Herzfrequenz ist das richtig, für eine
                          Intervall-Statistik ist es eine Lüge, die stromabwärts niemand rückgängig machen
                          kann — und Apples eigene Samples tragen sehr wohl eine echte
                          `startDate`/`endDate`-Spanne, die Null-Länge ist also KEINE Grenze der API,
                          sondern unser Verzicht darauf, das benutzte Intervall zu nennen. (2) Unsere zwei
                          Erzeuger rechnen nicht dieselbe Größe, und zwar auf DREI unabhängigen Achsen:
                          **(a) Fensterlänge** — Kamera 10 s, Gurt `maxRRIntervals = 64`, dort ausdrücklich
                          gewählt, damit 0,04 Hz LF auflöst; ein 10-s-Fenster kann keinen vollen Zyklus von
                          etwas Langsamerem als 0,1 Hz enthalten, vom LF-Band (0,04…0,15 Hz) überlebt also
                          knapp die Hälfte (0,10…0,15 sind ~45 % der Bandbreite), und der ~0,1-Hz-Resonanz-
                          gipfel, auf den dieses Produkt zielt, sitzt exakt AUF diesem Boden statt sicher
                          darin. **(b) Fenster-Stabilität** — die 64 ist eine SCHLAG-Zahl, keine Dauer:
                          ~38 s bei 100 bpm, ~85 s bei 45 bpm. Das schwächt (1) nicht ab, es verstärkt es —
                          es gäbe auch für den Gurt keine einzelne Zahl, die man ohne Rechnung je Sample in
                          ein `endDate` schreiben könnte. **(c) Schätzer** — `sdnn(rrMs:)` liest flach,
                          `sdnn(segments:)` schließt isolierte Schläge aus; `CameraRPPGBioPublisher` hält
                          genau das am Ort fest („SDNN is the ONLY remaining definitional split …
                          Registered, not fixed here"). Zwei Größen unter einem Feldnamen (#458), und Apple
                          Healths eigene Serie ist eine dritte.
                          ⚠️ **Die RICHTUNG ist strukturell, die GRÖSSE ist NICHT gemessen** — nirgends in
                          diesem Repo steht, wie viel tiefer ein 10-s-SDNN auf einem echten Take liest, und
                          keine Zahl in diesem Absatz darf so gelesen werden. Das steht auch am Ort, in
                          Regel 2 selbst. Eine Asymmetrie, die NICHT von der Größe handelt und deshalb
                          dazugehört: der Gurt torrt seine HRV-Veröffentlichung auf
                          `RRIntervalHygiene.canStateHRV`, der Kamerapfad veröffentlicht SDNN ohne jedes
                          Äquivalent — sie unterscheiden sich also auch darin, WANN sie sprechen.
                          ⛔ **Und der Schlusssatz der ersten Fassung war eine ABHAK-LISTE:** „Stamping a
                          real interval and unifying the two windows would remove the objections above". Wer
                          beides erledigt, hat (c) nicht angefasst — und (c) ist eine MESSFRAGE (passt der
                          Gurt-Ausschluss zu rPPG-Lücken?), keine Bearbeitung. #458 ist kein Schlüssel, der
                          die Entscheidung aufsperrt; ob Echoel überhaupt zu einer Gesundheits-HRV-Serie
                          beitragen soll, bleibt eine Founder-Frage.
                          ⭐ **Das Gegengewicht ist die Hälfte, die zählt** — die #343-Falle: ein nackter
                          „der HRV-Bezeichner ist abwesend"-Scan ist auch auf einer Datei grün, die ihren
                          ganzen Schreibpfad verloren hat. Derselbe Wächter nagelt deshalb `toShare:
                          [hr, resp]` als GANZE Liste fest (ein drittes Element passt nicht mehr hinein) und
                          prüft in einer eigenen Behauptung, dass echte SDNN überhaupt noch existiert: würde
                          eine spätere Scheibe `HRVMetrics.sdnn` löschen, würde der zurückgenommene Kommentar
                          wieder WAHR und der neue falsch — und diese Datei wäre das Einzige, was es merkt.
                          ⛔ **Und die erste Fassung dieses Gegengewichts hatte die #343-Falle EINE Ebene
                          tiefer wieder offen:** die zwei Typ-Nadeln (`.heartRate`, `.respiratoryRate`)
                          stehen JE ZWEIMAL in der Datei — einmal in `requestAuthorization`, einmal in
                          `write(_:)`. Wer die ganze Sample-Bau-Hälfte löscht, lässt alle drei Behauptungen
                          grün: ein Schreiber, der autorisiert und nichts schreibt. Zwei zusätzliche Nadeln
                          ankern jetzt auf Token, die NUR in `write(_:)` vorkommen
                          (`HealthWritePolicy.values(for: frame)`, `store.save(samples)`) — je 1× im Code,
                          nachgezählt statt angenommen.
                          ⚠️ `SourceText.codeOnly` ist hier TRAGEND und nicht Prophylaxe (#453), gemessen:
                          `heartRateVariabilitySDNN` steht im Rohtext **1×** und im Code **0×** — der
                          korrigierte `HealthKitWriter`-Kopf nennt den Bezeichner absichtlich als Wegweiser
                          für die nächste Sitzung, ein Rohtext-Scan wäre also auf KORREKTEM Code rot.
                          ⚠️ Und die Grenze: nichts hier ruft HealthKit auf. `HealthKitWriter` liegt in
                          `#if canImport(HealthKit)` und braucht ein Gerät; die Schreibpfad-Behauptungen sind
                          QUELLTEXT-SCANS, und `testTheWrittenValuesAreStillAPairOfPhysicalReadings` ist ein
                          COMPILE-Pin im Testgewand — er scheitert durch Nicht-Bauen, nicht durch Assertion.
                          Steht so im Dateikopf, damit sein Grün nicht als Laufzeit-Tatsache gelesen wird),
                          davor „188" nach `TheDemoSourceAgreesWithItsOwnKnobTests.swift` (#461 — der erste
                          Wächter in dieser Kette über einer Quelle, die GAR NICHTS MISST, und der erste,
                          dessen Defekt eine bereits BEZAHLTE Lehre war, die eine Quelle übersprungen hat.
                          `HRVNormalization` existiert, weil #97 fand, dass die drei LIVE-Quellen je einen
                          EIGENEN Teiler für dasselbe `hrvNormalized`-Feld trugen (Kamera ÷200, Gurt ÷100,
                          HealthKit ÷100); es faltete sie auf EINE 100-ms-Decke. **Die Demo-Quelle war in
                          dieser Prüfung nicht dabei und behielt einen VIERTEN Teiler** — 120 für RMSSD.
                          ⭐ **Und es ist keine bloß willkürliche Konstante, sondern ein Bruch einer
                          Invariante, die jeder Erzeuger einhält:** `hrvNormalized ==
                          HRVNormalization.normalize(<die ms-Metrik DIESER Quelle>)` — Kamera
                          (`normalize(analyzer.rmssd)` neben `hrvRMSSDms: analyzer.rmssd`), Polar (dieselben
                          zwei Zeilen), HealthKit (gegen SDNN, weil es kein Schlag-zu-Schlag-RR hat) und
                          `FaceExpressionBioPublisher`, das sie LEER erfüllt (es veröffentlicht
                          `hrvNormalized: 0` und gar keine ms-Metrik). ⛔ Die erste Fassung schrieb „die drei
                          LIVE-Quellen" und „jede echte Quelle EXAKT", die zweite „es sind **VIER** Erzeuger"
                          — und war damit in dem Satz um eins daneben, der eine Aufzählung korrigiert.
                          `git grep -n "BioSampleFrame(" -- Sources` findet **SECHS** Konstruktionsstellen über
                          **FÜNF** Erzeuger-Typen: die vier oben plus die Demo selbst, und die Kamera baut zwei
                          (die Ausfall-Halte-Wiederholung KOPIERT die Felder des gehaltenen Frames, erhält die
                          Invariante also, statt sie herzuleiten). Einer der vier besteht nur trivial. Und
                          „exakt" ist auf keiner Quelle wörtlich wahr — Kamera und
                          Gurt runden zweimal unabhängig (`Float(normalize(Double))` neben `Float(Double)`),
                          sind also ebenfalls nur bis auf Darstellung gleich, dieselbe Klasse wie die neuen
                          5,96e-8 der Demo. Die Schlussfolgerung überlebt beide Korrekturen; die AUFZÄHLUNG
                          nicht — und eine Aufzählung ist genau das, was eine spätere Sitzung grept. Die
                          Demo veröffentlichte ein Paar, das KEIN Konverter dieser App versöhnen kann: bei
                          `hrvNormalized` 0,50 schickte sie 60 ms, während die Hausregel sagt, 60 ms IST
                          0,60.
                          ⚠️ GEMESSEN, jede Zahl mit ihrem Raster (#448): **flach +20 % relativ** über
                          0,2…5/6, schlimmster absoluter Fehler **1/6 ≈ 0,16667 — das analytische Supremum
                          bei h = 5/6**, das der 701-Punkte-Sweep des Wächters gar nicht trifft; abgetastet
                          erreicht er **0,16660**. ⛔ Die erste Fassung schrieb „+0,167" ohne zu sagen,
                          welche der beiden Zahlen das ist — genau die Auslassung, die #448 in diesem Absatz
                          schon einmal gekostet hat. Die +11 % an der Oberkante sind kein kleinerer Fehler,
                          sondern `normalize`, das klemmt. Nach der Reparatur ist der größte Rest **5,96e-8**
                          (reine `Float`-Darstellung). ⛔ Und „mehrere Verbraucher tun das" ist GESTRICHEN:
                          `HRVNormalization.normalize` hat in `Sources/` genau DREI Aufrufstellen und alle
                          drei liegen auf der ERZEUGER-Seite (zwei Publisher plus `EchoelBioEngine`, das den
                          Schnappschuss schreibt, den `HealthKitBioPublisher` später veröffentlicht — „alle
                          drei sind ERZEUGER" war die lockere zweite Fassung; tragend ist, dass keine davon
                          den Regler aus einem Leitungswert NEU rechnet). Kein App-interner Verbraucher tut
                          das: die zwei VERBRAUCHER von `hrvRMSSDms` lesen ihn direkt, und der einzige weitere
                          Lesezugriff in `Sources/` ist die Ausfall-Halte-Wiederholung der Kamera, die
                          `held.hrvRMSSDms` weiterträgt — ein Durchreichen, kein Verbrauch. Belastbar ist nur
                          die Aussage über einen
                          EXTERNEN OSC-Empfänger, und die ist hypothetisch. Eine erfundene Stützbehauptung
                          ausgerechnet in dem Satz, der die Schwere begründet, ist die Klasse, die diese
                          Datei überall sonst zurücknimmt.
                          ⭐ Der Anker ist RMSSD und nicht SDNN, weil das die RR-Quellen-Konvention ist und
                          die Demo eine RR-Quelle imitiert: sie veröffentlicht RMSSD und pNN50, Größen, die
                          nur eine RR-Quelle hat. Auf SDNN zu ankern wäre eine DRITTE Regel gewesen.
                          ⚠️ **SDNN und pNN50 laufen ABSICHTLICH NICHT rund, und das symmetrisch aussehende
                          Aufräumen ist die Falle.** Auch auf Kamera und Gurt ist `normalize(hrvSDNNms) !=
                          hrvNormalized` — der Regler hängt dort ebenfalls an RMSSD. SDNN dieselbe Decke zu
                          geben wäre keine Konsistenz, sondern machte Demo-SDNN BITGLEICH mit Demo-RMSSD:
                          ein Paar, das kein Körper erzeugt, und eines, das die Demo für einen Empfänger
                          unbrauchbar macht, der beide gegeneinander plottet. Genau dafür steht
                          `testSDNNAndPNN50AreDeliberatelyNotRoundTripped` da. ⛔ **Und der Halbsatz „auf
                          beiden Seiten grün", der hier stand, gilt seit #464 nicht mehr** — dieselbe Methode
                          ist gegen den Vor-#464-Baum ROT, weil ihre Nadel dort das invertierte `* 90`
                          festnagelte. Ein Gegengewicht kann zum Regressionstest werden, sobald die Zeile,
                          die es festhält, sich bewegt; „grün auf beiden Seiten" ist eine Aussage über EINE
                          Baseline und altert genau wie eine Zahl. ⛔ Hier stand „die dritte Behauptung", und das war beim
                          Schreiben richtig und einen Commit später falsch: die Reviewer-Nachlese hat einen
                          Test EINGEFÜGT und die Reihenfolge geändert, womit die Ordnungszahl still auf
                          einen anderen Test zeigte. **Eine ORDNUNGSZAHL ist noch brüchiger als eine
                          Zeilennummer** — die Datei sagt an anderer Stelle, eine zitierte Phrase sei
                          belastbar und eine Zeilennummer nicht; eine Ordnungszahl überlebt nicht einmal
                          eine Umsortierung innerhalb derselben Datei. Ab jetzt steht überall der NAME.
                          ⭐ **Was #461 hier als „NICHT repariert" registriert hat, ist mit #464 repariert —
                          und genau dafür wurde es aufgeschrieben.** `* 90` lag UNTER der 100-ms-Decke, die
                          Demo veröffentlichte SDNN also an jedem Punkt UNTER RMSSD, während die
                          Ruhe-Beziehung andersherum läuft. Jetzt `ceilingMs * restingSDNNOverRMSSD` mit
                          einem BENANNTEN Verhältnis 1,25 — dem KONSERVATIVEN Ende der schon hier zitierten
                          Klammer (Kurzzeit-Ruhestudien ≈1,25, Task-Force-SDNN-Index/RMSSD ≈2,0), weil eine
                          Demo eine Spanne nicht überzeichnen darf, die niemand gemessen hat. Gemessen vor
                          dem Schreiben: das veröffentlichte Band wandert **18…81 ms → 25…112,5 ms**, und
                          das OSC-Tor ist
                          `hrvSDNNms > 0`, das 25 so sicher nimmt wie 18. Die NICHT-Rundreise bleibt per
                          Konstruktion kaputt (1,25·h ≠ h auf dem ganzen 0,2…0,9-Band, darüber sättigt
                          `normalize` auf 1,0) — das Gegengewicht ist also nicht aufgeweicht, es hat nur
                          seine Nadel mitbewegt, im SELBEN Commit und mit Begründung.
                          ⚠️ Und die ehrliche Einordnung der zwei NEUEN Behauptungen, weil die naheliegende
                          schmeichelhafter wäre: `restingSDNNOverRMSSD > 1` und der Richtungs-Sweep sind
                          KEINE Regressionen — sie hätten auf dem alten Baum nicht einmal kompiliert, die
                          Konstante gab es nicht.
                          ⛔ **UND DIE ERSTE FASSUNG DIESES ABSATZES HAT IHRE EIGENE BENOTUNG DREIMAL
                          FALSCH GEMACHT — beide Reviewer fanden es unabhängig, ich habe jede Zahl
                          nachgeschlagen.** Sie schrieb „pro Baseline genau EINE rote Behauptung: den
                          RMSSD-Scan gegen den Vor-#461-Baum, den SDNN-Scan gegen den Vor-#464-Baum", und
                          zwei Zeilen davor „hätten nicht einmal kompiliert" — **zwei Sätze, von denen der
                          zweite den ersten aufhebt.** (1) `git show c93ae1b^` trägt `* 120` UND `* 90`,
                          der heutige SDNN-Scan ist dort also ebenfalls rot: **ZWEI** gegen Vor-#461. (2)
                          `demoSDNNms` ist ein DATEIWEITER Helfer auf der neuen Konstante — die Datei
                          kompiliert gegen KEINEN der beiden alten Bäume, es kann dort also gar nichts
                          benotet werden. (3) Es sind **VIER** symbolabhängige Stellen, nicht zwei (der
                          Verhältnis-Test, beide Schleifen-Behauptungen, das `("SDNN", …)`-Tupel im
                          Band-Test). Die ehrliche Fassung: das ist eine HISTORISCHE ERZÄHLUNG, keine
                          ausführbare Prüfung — jede Baseline ist still mit der ZEITGENÖSSISCHEN Fassung
                          des Wächters gepaart, und nur unter dieser Paarung stimmt „genau eine". Die
                          Vorwärts-Wächter-Einordnung überlebt, die Zählung und die Ausführbarkeit nicht.
                          ⛔ **Und die dritte Falschstelle desselben Commits war eine erfundene
                          OBERFLÄCHE, in FÜNF Artefakten gleichzeitig** (Quelle, Wächter, Commit-Text,
                          hier, decisions.csv): „der Wert, den `BioStripView` zeigt" und „beide Enden
                          innerhalb `BioStripView`s 3…300-Fenster". `git grep -n hrvSDNNms --
                          Sources/Echoelmusic/Studio` liefert NICHTS — die „HRV"-Zelle IST RMSSD, und
                          `plausibleHRVms` gilt nur für dieses Feld. **In `Sources/` begrenzt GAR KEIN
                          Plausibilitätsfenster `hrvSDNNms`**; das einzige Tor ist `> 0`. Der einzige
                          Verbraucher ist `OSCSender`. ⭐ Die Lehre ist schärfer als die übliche
                          Stale-Zahl-Lehre, weil der RICHTIGE Satz vierzig Zeilen höher in DERSELBEN
                          Datei stand („die zwei VERBRAUCHER von `hrvRMSSDms`") — wahr, über RMSSD. Der
                          neue Satz hat seine FORM für ein anderes Feld wiederverwendet und die
                          Verbraucherliste behalten: **ein Satz, der von einem benachbarten wahren Satz
                          abgeschrieben ist, erbt dessen Glaubwürdigkeit und nicht dessen Subjekt.**
                          ⛔ Und die Bezifferung des Verhältnisses war ebenfalls zu stark: „das
                          KONSERVATIVE Ende der zitierten Klammer" — zitiert ist genau EIN Ende (Task
                          Force, ≈2,0); das untere stand als unbelegte Prosa da („Größenordnung 50 gegen
                          40 ms"). Ein Reviewer setzt die übliche Kurzzeit-Norm (Nunan et al. 2010) auf
                          50/42 ≈ 1,19, was 1,25 leicht DARÜBER legt statt darauf — **nicht verifiziert**,
                          der Proxy sperrt die Journale. 1,25 ist damit eine GEWÄHLTE runde Zahl nahe dem
                          unteren Rand einer 1,2…2,0-Klammer, keine zitierte Größe.
                          ⛔ Nebenbefund derselben Runde, pre-existing und in zwei Dateien: `BioSimulator`s
                          Kopf sagte „(oder, in DEBUG, auto-on)" und `docs/architecture.html` „in DEBUG
                          builds only" — beides falsch, `start(publishing:)` hat EINE Aufrufstelle im
                          Quellen-Dropdown der Puls-Pille, ohne jedes `#if DEBUG`. Beide gestrichen; die
                          zweite stand auf der VERÖFFENTLICHTEN Seite.
                          ⛔ Die ZUORDNUNG war falsch — hier stand „Task Force 1996:
                          Ruhe-SDNN über RMSSD auf 5-Minuten-Aufzeichnungen", und das ist die falsche
                          Tabelle: das Normwert-Paar SDNN 141±39 ms / RMSSD 27±12 ms stammt aus
                          **24-Stunden**-Aufzeichnungen; die Kurzzeit-Größe desselben Dokuments ist der
                          **SDNN-Index** (Mittel der 5-Minuten-SDNNs), 54±15 ms. Kurzzeit-Ruhestudien legen
                          die beiden näher zusammen (Größenordnung 50 gegen 40 ms). Die RICHTUNG ist über
                          alle robust, das VERHÄLTNIS nicht — und gebraucht wird nur die Richtung.
                          ⛔ **Und die BEGRÜNDUNG des Nichtreparierens war selbst-untergrabend.** Sie
                          lautete: das zu ändern hieße ein Verhältnis zu wählen, also Physiologie zu
                          erfinden. Aber `* 90` IST ein gewähltes Verhältnis — nirgends hergeleitet und
                          gegen jede Referenz oben invertiert. Eine erfundene Konstante mit dem Argument
                          stehen zu lassen, ihr Ersatz wäre erfunden, behandelt den Amtsinhaber als
                          evidenzfrei-neutral, obwohl er genauso erfunden ist wie jeder Ersatz — und die
                          Evidenz, die angeblich fehlt, steht zwei Zeilen darüber. Die ehrliche Fassung ist
                          enger: **der Amtsinhaber ist ebenfalls erfunden und invertiert; ihn zu ersetzen
                          ist billig und die Evidenz steht oben, aber es ändert ausgelieferten Output und
                          gehört in eine eigene Scheibe.** Diese Scheibe auf Arithmetik zu begrenzen ist
                          Umfangsdisziplin, kein Beweisurteil — nicht als „es gibt keine Evidenz" lesen und
                          das invertierte Paar für immer stehen lassen. ⭐ **Und das ist der Punkt, an dem
                          dieser Absatz sich selbst bewährt hat: #464 ist die eigene Scheibe, EINEN Zyklus
                          später, und sie hat exakt die Begründung benutzt, die hier korrigiert wurde.** Die
                          LEHRE ist deshalb nicht „Vermerke veralten", sondern die Umkehrung: eine
                          Nicht-Reparatur, deren Begründung ehrlich als schwach ausgewiesen ist, wird
                          eingelöst — eine, die sich als Prinzip tarnt („das wäre Erfinden"), bleibt für
                          immer stehen.
                          ⚠️ Was der Wächter NICHT kann, und das steht als ERSTES in seinem Kopf:
                          `BioSimulator.nextFrame()` ist `private` und die Klasse `@MainActor` — es gibt
                          KEINEN Weg, den ausgelieferten Generator hier zu treiben. Jede Behauptung ist
                          entweder Arithmetik auf `HRVNormalization` oder ein QUELLTEXT-SCAN darauf, dass
                          `BioSimulator.swift` diese Arithmetik wirklich schreibt; tragend sind sie nur
                          GEMEINSAM (die #431/#440-Form).
                          ⛔ **UND DIE ERSTE FASSUNG HAT IHRE EIGENEN TESTS FALSCH EINGEORDNET — der
                          wörtliche #433-Defekt, begangen in der Scheibe, die #433 zitiert.** Hier stand
                          „die zwei Regressionen sind auf dem alten Baum rot (0,167 bzw. das Literal
                          `* 120`)", und dasselbe stand im Testkopf und im Commit-Text. Der Rundreise-Test
                          ist auf dem alten Baum GRÜN und konnte gar nichts anderes sein: er wertet seinen
                          eigenen privaten Helfer aus, und der trägt die NEUE Formel, im Testfile
                          ausgeschrieben. Nichts in dieser Datei liest den Multiplikator der Quelle je ALS
                          ZAHL — es kann nicht, der Generator ist unerreichbar. **Es gibt genau EINE
                          Regression: den Quelltext-Scan.** Die 0,167 ist eine MESSUNG des alten Verhaltens,
                          keine Behauptung, die diese Datei aufstellen kann. Die Lehre, die #433 schon
                          bezahlt hat und die nicht gehalten hat: **die eigenen Tests falsch einzuordnen ist
                          schwerer zu sehen als ein Wächter, der nicht scheitern kann — weil so oder so
                          alles grün ist.** Neu dazu: ein MUSEUMS-Test, der die entfernte Formel selbst
                          rechnet und die 0,1 in der Bandmitte festhält, ausdrücklich als Dokumentation und
                          beidseitig grün — damit die GRÖSSE eines behobenen Defekts nicht nur in einer
                          Commit-Nachricht überlebt.
                          ⛔ **Und die eine echte Regression war zu locker verankert (#408).** Sie suchte
                          das nackte Token `HRVNormalization.ceilingMs` im GANZEN File — also war ein Baum
                          grün, in dem RMSSD ein Literal `100` trägt und `ceilingMs` auf der SDNN-Zeile
                          steht: exakt der #97-Defekt zurück, plus die SDNN-Vereinheitlichung, gegen die
                          das Gegengewicht daneben steht. Jetzt ist der ganze Ausdruck festgenagelt. Der
                          Wächter war in seiner strengen Hälfte (SDNN, zeilengenau) rigoros und in seiner
                          TRAGENDEN locker.
                          ⛔ **Und der Verifikations-Satz der Nachlese war selbst falsch — in dem Absatz,
                          dessen Aufgabe es ist, Verifikation zu behaupten.** Der Commit-Text sagte
                          „`hrvRMSSDms: hrvNormalized * 120` … im Quelltext abwesend UND im Rücknahme-
                          Kommentar vorhanden". Der Kommentar zitiert `hrvNormalized * 120` OHNE das
                          `hrvRMSSDms:`-Präfix, enthält die gesuchte Zeichenkette also gar nicht — sie steht
                          nirgends in der Datei. Meine Python-Prüfung hatte das FRAGMENT gemessen und ich
                          habe das Ergebnis auf die NADEL übertragen. Folgenlos für den Test (beide Formen
                          sind abwesend), aber es ist dieselbe Klasse wie alles andere hier: eine Messung,
                          die etwas anderes misst als der Satz behauptet, in dem sie zitiert wird. **Als
                          Nebenwirkung ist auch der `codeOnly`-Grund in diesem Wächter abgelaufen:** mit der
                          engen Nadel liefern Rohtext und `codeOnly` auf beiden Bäumen IDENTISCHE Ergebnisse,
                          der Stripper ist dort also Prophylaxe und nicht mehr tragend — was am Ort steht,
                          statt als „load-bearing" weiterbehauptet zu werden.
                          ⚠️ Und die härteste Grenze: nichts davon ist am Gerät gesehen. Die zwei
                          Verbraucher von `hrvRMSSDms` sind der OSC-Ausgang
                          (`/echoelmusic/bio/heart/rmssd`) und die Zahl in `BioStripView`; ob je jemand auf
                          die Demo-Zahl schaut, ist eine Geräte-Frage. Die Arithmetik ist so oder so
                          falsch, und deshalb wird sie repariert und nicht vertagt),
                          davor „187" nach `VisualFineTuneReflowsTests.swift` (#292 Slice 4 — der erste
                          Wächter in dieser Kette über einer Fläche, die von ZWEI Wirten mit
                          VERSCHIEDENEM Innenabstand gerendert wird, und deshalb der erste, dessen
                          schärfste Behauptung ein FEHLENDER Default ist. `visualAdjustFields` läuft
                          im `visualPanel` (in `EchoelPanel`, 14) UND im `visualVJOverlay` (eigener
                          `VStack`, 8). In EINER Spalte ersetzt `AdaptiveCardGrid` den Abstand des
                          Wirts — ein Literal im ViewBuilder hätte also eine der beiden Flächen im
                          HOCHFORMAT still umgesetzt, dort wo gar nichts reflowt und es folglich
                          nichts einbringt. Also ein Parameter, und `spacing: CGFloat` OHNE Default:
                          ein Argument, das keine Aufrufstelle schreibt, taucht in keinem Diff auf
                          (#440/#443).
                          ⭐ Zwei Gitter statt eines, und der Grund ist die Bildunterschrift dazwischen:
                          der #269-Hinweis zur Detail-Zeile wrappt und will die volle Breite.
                          ⛔ **Und die erste Fassung pries diese Teilung als GRATIS, was sie nicht ist.**
                          Sie schrieb „das Ergebnis ist in beiden Spaltenzahlen identisch mit einem
                          Sechser-Gitter" — auf einer FRISCHEN INSTALLATION falsch. Der #269-Hinweis ist
                          dort kein Randfall, sondern der Normalfall: `LookBlendMap` sagt es selbst
                          („Mit den ausgelieferten Defaults — Stil 5 (Aurora), styleB 0, blend 0 — ist
                          dieser Anteil NULL"), also ist `detailReach < 0.001` und der Absatz zwischen den
                          Gittern WIRD gerendert. Sechs Karten mit einem umbrechenden Absatz dazwischen
                          sind nicht identisch mit sechs Karten in einem Gitter. Wahr bleibt das
                          Schwächere: die Karten landen in DENSELBEN PAAREN und derselben Zeilenfolge, und
                          die Naht ist unsichtbar, solange der Hinweis verborgen ist.
                          ⭐ **Und selbst dann ist sie unsichtbar aus einem Grund, den die erste Fassung
                          nicht nannte.** „Zwei Karten füllen eine Zeile" ist notwendig und nicht
                          hinreichend: der Abstand zwischen der Zeile von Gitter 1 und der ersten Zeile
                          von Gitter 2 ist der Abstand des WIRTS, in einem Sechser-Gitter wäre es
                          `LazyVGrid`s eigener. Sie fallen nur zusammen, weil das Argument GLEICH dem
                          Wirtsabstand ist. `spacing == Wirtsabstand` leistet also zweierlei — es macht
                          das Hochformat bitgleich UND die Zwei-Gitter-Naht im Querformat unsichtbar.
                          ⚠️ Energy bleibt bewusst DRAUSSEN: es steht allein zwischen zwei
                          vollbreiten Kindern, ein Gitter darum ordnete EINE Karte an — und ein Gitter,
                          das eine Karte anordnet, ordnet nichts an (#359 Schritt 2 hat aus genau
                          diesem Grund eines gelöscht).
                          ⛔ EHRLICH ZU DEN EIGENEN TESTS, weil die naheliegende Formulierung
                          schmeichelhafter wäre: von den fünf Behauptungen sind vier Regressionen,
                          und die fünfte (Energy/Knopf/Bildunterschrift bleiben draußen) ist ein
                          GEGENGEWICHT gegen das Alles-ins-Gitter-Aufräumen. Sie ist auf dem alten
                          Baum trotzdem rot — aber nur, weil der Anker `private var` hieß und die
                          Signatur sich geändert hat, nicht weil sie etwas gefangen hätte. Eine
                          signaturbedingte Rotfärbung als Regression zu verbuchen wäre dieselbe
                          Selbst-Fehleinordnung wie im #433-Eintrag.
                          ⚠️ Und die Grenze steht als ERSTES im Dateikopf: alle fünf sind
                          QUELLTEXT-SCANS. SwiftUI-Layout ist von hier nicht erreichbar — „zwei
                          Spalten lesen sich auf dem Gerät gut", „der Spaltenbruch sitzt zwischen
                          sinnvollen Parametern" und „das Overlay passt im Querformat noch in seine
                          Decke" sind alle drei Geräteproben. ⚠️ Und die bindende Decke des Overlays ist
                          die BREITE, nicht die Höhe — die erste Fassung nannte nur `maxHeight: 360`, also
                          die auffällige. `visualVJOverlay` ist auch `maxWidth: 560`; abzüglich seiner
                          14-pt-Polsterung und der 10-pt-Rinne des Gitters sind das **261 pt je Spalte**,
                          während `AdaptiveCardGrid` erst bei `isAccessibilitySize` auf eine Spalte
                          zurückfällt — eine GROSSE, aber nicht barrierefreie Textgröße zeichnet dort also
                          weiter zwei Spalten mit einer `@ScaledMetric`-Wertebox, die mitgewachsen ist.
                          Das inline-Panel hat diese Enge nicht. Arithmetik aus Konstanten, keine Messung:
                          der Punkt ist, dass das Band benennbar ist und vors Gerät gehört. Dazu ein Nebenbefund, der NICHT
                          mitrepariert ist: dieselbe Änderung machte zwei Nachbar-Wächter rot
                          (`VisualPresetValuesAreReachableTests` ankerte auf `private var …: some View`,
                          `SectionHeadingIsOneTreatmentTests` auf Gleichheit mit dem nackten Namen).
                          Beide sind im selben Commit mitgezogen — die #456-Lehre: wer eine Fläche
                          ändert, `git grep`t sie in `Tests/CISmoke`, nicht nur in `Sources/`),
                          davor „186" nach `RMSSDReadsOnlyAdjacentBeatsTests.swift` (#425 — der erste
                          Wächter in dieser Kette über einer Zahl, die eine ANDERE Zahl als ihren
                          Nachbarn LAS: `CameraAnalyzer.calculateRMSSD()` lief flach über
                          `rrIntervals`, und diese Liste ist ZWEIMAL verdichtet — ein `continue` an
                          jedem Peak-Abstand außerhalb 0,3…1,5 s, dann eine IQR-Verwerfung, beide in
                          frische Arrays. RMSSD und pNN50 lesen AUFEINANDERFOLGENDE Paare; eine
                          Differenz über einen entfernten Schlag hinweg ist ein Artefakt der
                          Entfernung, kein Schlag-zu-Schlag-Wert. `HRVMetrics` sagt das an seinen
                          `segments:`-Überladungen seit Monaten, der Gurt pool't seit
                          `acceptedSegments` innerhalb der Runs, und `rrWindowMs`' Doc benennt
                          namentlich DIESE Datei als den Gegenbeispiel-Pfad („Do NOT read the camera
                          path as the good example"). Die Behauptung stand also geschrieben da, und
                          nichts machte sie rot.
                          ⭐ **Die Reparatur ändert KEINE Akzeptanzentscheidung, und das ist der
                          Entwurf, nicht die Einschränkung.** Der naheliegende Griff — den vorhandenen
                          `RRIntervalHygiene` darüberlaufen lassen, der genau diese Runs zurückgibt —
                          wäre falsch gewesen: er liefert sie als NEBENPRODUKT einer eigenen
                          Akzeptanzpolitik (Band + Malik-20-%-Schritt, für einen Brustgurt getunt),
                          und die Kamera hat ihre Entscheidung schon getroffen. Eine dritte Politik
                          über eine bereits verdichtete Reihe hätte die Nachbarschaft nicht
                          zurückgeholt, sondern die Verfügbarkeit gesenkt. `RRAdjacency` leitet die
                          Runs stattdessen aus `beatTimes` ab — der absoluten Zeit des ZWEITEN
                          Schlags jedes Intervalls, die der Analyzer seit #343 ohnehin 1:1 mitführt.
                          Der Test ist exakt statt statistisch: Intervall `i` beginnt bei
                          `endTimes[i] − intervals[i]`, und das IST `endTimes[i−1]` genau dann, wenn
                          kein Schlag dazwischen fehlt.
                          ⚠️ **GEMESSEN VOR DEM SCHREIBEN, und die erste Zeile der Tabelle ist die
                          wichtigste: auf sauberem Kontakt ist es ein NO-OP.** Kein Loch, ein Run,
                          bitgleich — und das ist exakt und nicht ungefähr, weil `rmssd(rrMs:)` durch
                          `count − 1` teilt und `rmssd(segments:)` durch die Paarzahl, was für EINEN
                          Run dieselbe ganze Zahl ist. Transkribiert und mit einer 60-bpm-RSA-Reihe
                          getrieben (10-s-Fenster, 600 Seeds je Zeile) bläht das Poolen über Lücken
                          beide Metriken auf, immer in dieselbe Richtung: **0 % ohne Artefakte,
                          +2,8 % RMSSD bei 5 %/5 %, +4,9 % bei 15 %/10 %, +8,3 % bei 25 %/15 %,
                          +9,6 % bei 35 %/20 %**, pNN50 dabei +2,3…4,1 Prozentpunkte. Das ist der
                          Take, den der Founder wirklich bekommt — #304/#410 sind offen, WEIL die
                          Akquise fragil ist.
                          ⛔ **DIE ARTEFAKT-RATEN SIND ANNAHMEN, KEINE MESSUNGEN.** Nichts in diesem
                          Repo hält fest, wie oft ein Geräte-Take einen Schlag verliert oder erfindet;
                          die Zeilen sind ein Modell an gewählten Raten, also ist die FORM (monoton,
                          einseitig, null bei null) der Befund und die einzelne Prozentzahl
                          illustrativ. Ein einzelner Seed las +15420 % — und **diese Zahl wird
                          absichtlich NICHT als schlimmster Fall zitiert**: ihr segmentierter Nenner
                          war 0,2 ms, sie misst also einen kleinen Divisor und keinen großen Fehler.
                          Dieselbe Klasse wie die zurückgenommene „0,4712" im #448-Eintrag, nur früh
                          genug gesehen.
                          ⭐ **SDNN bleibt ABSICHTLICH flach, und das ist die teuerste Behauptung der
                          Scheibe.** Es ist ein SPREAD und hat keine Nachbarschaftsforderung — das
                          sagt `HRVMetrics` an genau der Stelle, an der es die `segments:`-Formen
                          einführt. Was ein symmetrisch aussehendes Nachziehen IMPORTIEREN würde, ist
                          `sdnn(segments:)`s Ausschluss ISOLIERTER Schläge (der Kompensationspausen-
                          Fall), und auf einem schlecht kontaktierten Kamera-Take ist fast jeder Run
                          Länge 1. Gemessen an der Fixtur des Wächters — drei angenommene Intervalle,
                          jedes mit einer Lücke auf beiden Seiten: `sdnn(rrMs:)` liest **50,0 ms**,
                          `sdnn(segments:)` liest **0,0**. Für einen Take mit echten Intervallen 0 zu
                          veröffentlichen ist schlimmer als das Artefakt, das es entfernen soll, und
                          ob der Gurt-Ausschluss zur Lückenstruktur der Kamera passt, ist UNGEMESSEN.
                          Der Quelltext-Scan macht daraus eine Entscheidung statt eines Zufalls.
                          ⛔ **UND DER WÄCHTER WÄRE IN SEINER ERSTEN FASSUNG AUF KORREKTEM CODE ROT
                          GEWESEN — gefunden beim Nachrechnen, nicht beim Review.** Er fensterte den
                          Publisher ab dem ERSTEN `hrvSDNNms:`, und das erste ist die
                          AUSFALL-HALTE-Wiederholung ~90 Zeilen früher, die `held.hrvSDNNms`
                          weiterreicht und `HRVMetrics` gar nicht erwähnt. Die naheliegende
                          „Reparatur" — die Behauptung lockern — hätte genau den Wächter entwaffnet,
                          der zwischen SDNN und einer stillen Symmetrisierung steht. #408s Lehre noch
                          einmal: **ein Scan muss auf ein Token ankern, das NUR an der gemeinten
                          Stelle steht, und diese Eindeutigkeit nachzuschlagen gehört zum SCHREIBEN
                          des Scans, nicht zum Review.**
                          ⚠️ Welche Behauptung überhaupt scheitern KANN, steht im Dateikopf: die zwei
                          Quelltext-Scans sind die Regressionen (vorher stand dort eine
                          handgeschriebene flache Schleife bzw. `pnn50(rrMs: rrMs)`) — belegt durch
                          Lesen des alten Codes, nicht durch einen Lauf, denn `RRAdjacency` existiert
                          auf dem alten Baum nicht, die Datei hätte dort gar nicht kompiliert. Die
                          SDNN-Hälfte und der 1:1-Wächter sind GEGENGEWICHTE, beidseitig grün. Und die
                          Verhaltensfälle treiben einen Typ, den derselbe Commit erst anlegt — sie
                          können nie rot gewesen sein und behaupten nur, was eine spätere
                          Vereinfachung wegnähme.
                          ⚠️ Und die härteste Grenze: nichts davon ist am Gerät gemessen. Ob ein
                          echter Take Lücken in der Größenordnung der Tabelle hat, entscheidet ein
                          Gurt- oder Kamera-Take, kein zweites Modell),
                          davor „185" nach `TheTransportBarIsDissolvedTests.swift` (#456 — der erste
                          Wächter in dieser Kette über einer GELÖSCHTEN Fläche statt über einem Wert, und
                          die Fortsetzung von #455 aus DEMSELBEN Founder-Screenshot: v10.79.371 (2488)
                          trug drei rote Markierungen. Die erste war das durchgestrichene Tempo-Feld
                          (#455). Die zwei anderen sind Kreise mit Pfeilen — das „•••"-Überlaufmenü und
                          die `1.1.1 / loop 1/32`-Positionsanzeige, beide in die Transport-Zeile des
                          Instruments darunter zeigend. In der Markup-Grammatik dieses Founders heißt das
                          MIGRIEREN (#411, wörtlich: „soll dort hin wo der rote Pfeil hinzeigt
                          migrieren"). Beide Kinder sind umgezogen; die Leiste, die sie hielt — die letzte
                          Chrome-Transport-Leiste — ist GELÖSCHT und nicht leer stehen geblieben. Eine
                          geleerte Hülle ist der schlechtere Ausgang: sie liest sich wie ein Platz, an den
                          man Dinge zurücklegt, und sie bleibt ein dritter dauerhafter Vorfahr über dem
                          Instrument.
                          ⭐ **ZWEI ZEILEN UND NICHT EINE — und die Begründung stand schon da, geschrieben
                          von #411 für genau diesen Fall.** Der Doc-Kommentar von `startControlRow` hat die
                          Ein-Zeilen-Variante bereits bepreist und die Antwort benannt: *„the cheapest
                          answer is to move `TransportPositionView` and the '•••' overflow OUT of the
                          chrome bar as well and give this row a second line — NOT to send the tempo back
                          up."* Der Grund ist eine Messung: die Analyse-Pille ist das einzige flexible
                          Kind, eine einzelne Zeile gibt ihr also auf einem 393-pt-Telefon nur, was nach
                          ▶ + ⏸ + Tempo + Schloss + „•••" + Positionsanzeige übrig ist — und der Founder
                          hat am 2026-07-31 ausdrücklich verlangt, diese Pille GRÖSSER zu machen
                          (#305/#307).
                          ⛔ **UND DIE ZAHL, DIE HIER STAND, WAR ERFUNDEN — beim ZITIEREN einer Zahl.**
                          Sie lautete „rund ein Drittel ihrer Breite" und berief sich auf genau den
                          Doc-Kommentar, der eine Zeile höher zitiert wird. Der sagt etwas anderes:
                          **rund 150 pt statt 300**, also die HÄLFTE — und er sagt es über die Zeile mit
                          VIER Kindern, nicht über die mit sechs. Beide Hälften des Zitats waren falsch,
                          und es stand in vier Dateien gleichzeitig (Quelle, Wächter, Commit-Text, hier).
                          Was die Quelle wirklich trägt: vier Kinder halbieren die Pille bereits; die zwei
                          Zuwanderer nehmen zusätzlich ~30 pt Chip, ~100 pt Anzeige und zwei weitere
                          8-pt-Lücken — eine einzelne Zeile lässt also deutlich WENIGER als ein Drittel.
                          Die Schlussfolgerung (zwei Zeilen) überlebt, die Zahl nicht.
                          Zeile 1 ist deshalb bitgleich mit vorher, und DAS ist es, was den Satz „nichts,
                          was heute existiert, lässt sich noch zusammendrücken" zu einer Tatsache statt zu
                          einer Hoffnung macht. Behauptung 2 des Wächters ist die Hälfte, die das
                          festhält: genau ZWEI innere `HStack(spacing: 8)`, nie einer.
                          ⭐ **Und die Gefahr, die vor dem Löschen abgefangen wurde, ist die eigentliche
                          Lehre dieser Scheibe:** die kanonische Fassung des `fixedSize`-plus-`minHeight`-
                          Gesetzes — des Gesetzes, das #455 einen Tag zuvor gekostet hat — stand auf dem
                          Rahmen genau dieser Leiste, während ZWEI ANDERE Rahmen derselben Datei sie
                          namentlich zitieren. Die Leiste zu löschen, ohne den Vermerk vorher zu
                          verschieben, hätte zwei lebende Rahmen auf eine Erklärung zeigen lassen, die es
                          nicht mehr gibt. Er sitzt jetzt auf `topBar`s Rahmen. **Ein Gesetz, dessen
                          kanonische Fassung auf einem gelöschten Wirt lag, ist schlimmer als kein
                          Gesetz** — die nächste Sitzung liest zwei Verweise ins Leere und schließt daraus,
                          die Regel sei zurückgezogen worden.
                          ⛔ **UND DIE LÖSCHUNG HAT EINEN WÄCHTER IM BLOCKIERENDEN BUNDLE ROT GEMACHT —
                          das ist der teuerste Befund dieser Scheibe und BEIDE Reviewer fanden ihn
                          unabhängig.** `ChromeDynamicTypeTests` führte eine Tabelle der drei Chrome-Leisten
                          und nagelte pro Leiste DREI Dinge fest: den Mount (`TransportBar()`), die
                          `.frame(minHeight: 44)` und das `.fixedSize` direkt darüber. #456 hat alle drei
                          entfernt, also feuerten drei Behauptungen gleichzeitig — **der Wächter hat
                          funktioniert**, nicht versagt, und sein eigener Doc-Kommentar sagte schon
                          „aktualisiere diese Erwartung im selben Commit — lösche die Prüfung nicht".
                          ⚠️ **Und der Preis des späten Findens ist die eigentliche Lehre:** solange #396
                          lebt, meldet `Echoelmusic CI/CD Pipeline` auf JEDEM Push `failure`, dieses Rot
                          war also von der Wirt-Leiche nicht zu unterscheiden, ohne die Testnamen im
                          Job-Log zu lesen. **Vor dem Löschen eines Chrome-Elements: `git grep` es in
                          `Tests/CISmoke`, nicht nur in `Sources/`.** Ein Commit, der eine Fläche
                          entfernt, muss die Wächter über dieser Fläche im selben Atemzug mitziehen —
                          sonst hat man einen Wächter gegen die eigene Änderung geschrieben, während man
                          einen anderen gegen sie ins Messer laufen ließ.
                          ⚠️ **Die Höhen-Arithmetik geht auf, aber knapper als zuerst behauptet — und sie
                          ist Quelltext, keine Messung.** Entfernt werden die 44 pt `minHeight` der
                          Leiste; hinzu kommen eine ~32 pt hohe zweite Zeile IM Instrument **plus die
                          8 pt Abstand des neuen `VStack`**, also ~40 pt. Netto gewinnt die spielbare
                          Fläche ~4 pt, nicht ~12. ⛔ Die erste Fassung schrieb „≥44 pt (der `minHeight`
                          der Leiste **plus ihr Abstand**)" und ließ die 8 pt auf der Gegenseite weg —
                          zweimal in dieselbe Richtung daneben: die Chrome ist ein `VStack(spacing: 0)`,
                          es gibt dort gar keinen Abstand dazuzurechnen, und der Abstand, den es WIRKLICH
                          gibt, entsteht durch die Änderung selbst. Die RICHTUNG stimmt weiterhin, die
                          Marge war um den Faktor drei zu großzügig. Ob sich die Zeile auf einem
                          393-pt-Telefon RICHTIG liest, bleibt eine Geräteprobe.
                          ⚠️ **Eine Begründung ist mit dem Umzug ABGELAUFEN, und sie steht am Ort statt
                          still weiterzugelten:** `TransportOverflowMenu` verschickt seine Türöffnungen
                          weiter über `.echoelChromeDoor`, obwohl es jetzt in derselben Ansicht sitzt, die
                          die Benachrichtigung entgegennimmt — eine Rundreise innerhalb einer View. Der
                          alte Grund („Chrome greift nicht in Studio-Zustand") gilt für dieses Kind nicht
                          mehr. Behalten wird es trotzdem, weil `.echoelChromeDoor` ANDERE Erzeuger hat
                          (die Monitor-Kacheln im Header): sie durch eine direkte Bindung zu ersetzen
                          machte aus einer Definition zwei — die #416-Bedingung.
                          ⛔ **UND EINE „GEMESSENE" ZAHL DIESER SCHEIBE WAR ERFUNDEN, gefunden von der
                          Nachlese — die einzige Sorte Fehler, vor der dieser Absatz zwanzigmal warnt.**
                          Hier stand, die `.contentShape(Rectangle().inset(by: -6))` des Menüs überlappe
                          bei 8 pt Zeilenabstand seine Nachbarn um 2 pt, das spätere Geschwister gewinne
                          die Treffer-Prüfung, folgenlos. Nachgesehen statt angenommen: zwischen den zwei
                          Kindern der zweiten Zeile steht ein `Spacer(minLength: 0)`. Der Abstand nach
                          rechts ist der ganze freie Platz der Zeile (~300 pt auf einem 393-pt-Telefon),
                          nach links die `.padding(.horizontal, 16)` der Zeile selbst. **Es überlappt
                          nichts.** Senkrecht reicht die −6 in die 8-pt-Lücke des VStack, und das Kind
                          darüber (`startButton`) trägt gar keine eigene Trefferform. Die Zahl war nicht
                          veraltet — sie ist nie gemessen worden, sie klang nur plausibel, weil 12 pt
                          minus 6 minus 8 sich rechnen lässt, wenn man den Spacer nicht ansieht. **Und
                          die Gefahr ist die umgekehrte der üblichen: eine erfundene KOSTEN-Angabe lädt
                          die nächste Sitzung ein, eine Überlappung „zu reparieren", die es nicht gibt —
                          und das Verkleinern der −6 setzt den Knopf unter die 44-pt-Grenze, für die
                          #113 existiert.** Die Rücknahme steht auch am Bedienelement selbst.
                          ⚠️ Was der Wächter NICHT kann, und das steht als ERSTES in seinem Kopf: alle
                          fünf Behauptungen sind QUELLTEXT-SCANS. SwiftUI-Layout ist von hier nicht
                          erreichbar, „die Zeile liest sich gut" und „die Chrome ist jetzt kürzer" bleiben
                          Sichtproben. Gemessen: auf `1348fc4` sind 1a/1b/2/3 ROT (Struct vorhanden, Mount
                          vorhanden, ein einziger innerer HStack, kein migriertes Kind), die drei
                          Gegengewichte 4a/4b/5 sind auf BEIDEN Seiten grün — so gesagt, statt sie als
                          Regressionstests zu verkleiden.
                          ⭐ Und das dritte Gegengewicht ist das, das eine spätere Vereinfachung fangen
                          soll: `TransportPositionView` liest `transport.position`, bei 120 BPM also ~10 Hz.
                          Es in `EchoelStudioView` zu montieren ist NUR deshalb erlaubt, weil der Zugriff in
                          SEINEM eigenen Body liegt (10.76.41/50). Seine zwei Labels einzufalten — die
                          naheliegende „Vereinfachung" für eine Zwei-Label-Ansicht — wäre exakt die Form des
                          Ship-Blockers: der Playhead würde den Body neu bauen, der jeden `.menu`-Picker des
                          Instruments beherbergt. Genau dafür ist der Typ seit #456 nicht mehr `private`,
                          und der Grund steht an der Deklaration),
                          davor „184" nach `TheTempoFieldCannotEatTheScreenTests.swift` (#455 — der
                          erste Wächter in dieser Kette über einem LAYOUT-Defekt, und der einzige,
                          dessen Mechanismus vor dem Eintreten schon ZWEIMAL im Repo aufgeschrieben
                          war. Founder-Screenshot v10.79.371 (2488), das Tempo-Feld durchgestrichen:
                          im LOOP-Modus stand die Box rund ein Drittel des Bildschirms hoch, während
                          Schloss und Puls-Pille daneben auf ihren normalen 32 pt saßen.
                          ⭐ **Und niemand hat einen Kommentar ignoriert — DAS ist der Befund.**
                          `EchoelValueField`s Scrub-Schicht ist ein nacktes `Rectangle()`, das JEDE
                          angebotene Höhe annimmt (sein eigener Kommentar endet mit „Do not remove
                          that without removing this greediness at the source"), und `WorkspaceView`
                          sagt von der anderen Seite, dass ein VStack seine Kinder nach Flexibilität
                          sortiert und eine solche Zeile deshalb ∞ meldet und den freien Platz mit dem
                          Instrument darunter TEILT. Beides stimmt. Nur war der Schutz eine Eigenschaft
                          der LEISTE (`.fixedSize` + `.frame(minHeight: 44)` auf den drei Chrome-Bars)
                          und nicht des BEDIENELEMENTS — und #411 hat das Feld auf Founder-Wunsch aus
                          der Transport-Leiste in `EchoelStudioView.startControlRow` verschoben. Jedes
                          Wort der Freeze-Sicherheits-Begründung dieses Umzugs war richtig; die
                          LAYOUT-Hälfte ist einfach nicht mitgereist, weil nichts sagte, dass sie muss.
                          **Die #416-Form in ihrer leisesten Ausprägung: eine Entscheidung, zwei
                          Besitzer, und nichts, das ihr Auseinanderlaufen bemerkt.**
                          ⚠️ Nur der GESPERRTE Zweig war je gierig — die folgenden Zweige pinnen ihre
                          eigenen Rahmen (kompakt `76×32`, breit: gepolsterte Texte). Ein
                          Flow-Modus-Screenshot hätte nichts gezeigt.
                          ⭐ Die Reparatur sitzt deshalb am BEDIENELEMENT und nicht an der neuen Zeile:
                          die nächste Leiste, in der es landet, erbt sie. `startControlRow` bleibt
                          bewusst unberührt, damit es genau EINE Antwort auf „warum dehnt sich das
                          Tempo-Feld nicht" gibt.
                          ⚠️ **Der Gegengewichts-Test ist der teure Teil:** das naheliegende Aufräumen
                          danach ist „das Bedienelement schützt sich jetzt selbst, die Leisten brauchen
                          es nicht mehr" — und das wäre still falsch. `CompositionHeaderStrip` beherbergt
                          das A4-Kammerton-Feld, ein ANDERES gieriges Control, von dem `BodyTempoField`
                          nichts weiß; ihm den Pin zu nehmen öffnet dieselbe Spaltung eine Leiste höher,
                          auf genau dem Feld, dessen versehentliche Verstellung #391, #392 und #440
                          gekostet hat.
                          ⚠️ Was der Wächter NICHT kann, und es steht als ERSTES im Dateikopf: alle fünf
                          Behauptungen sind Quelltext-Scans. SwiftUI-Layout ist von hier nicht erreichbar,
                          „die Box ist 35 pt und nicht 217" bleibt eine Geräte-Sichtprobe. Gemessen: nur
                          Behauptung 1 ist auf `7415421` rot, die vier anderen sind Prämissen und
                          Gegengewichte und beidseitig grün — so gesagt statt als Regressionstests
                          verkleidet. Und die `codeOnly`-Streifung (#453) ist hier tragend, nicht
                          hygienisch: die Prosa dieser Scheibe zitiert alle drei gesuchten Zeichenketten,
                          und `WorkspaceView` nennt den Modifier in einem Kommentar fünf Zeilen über dem
                          echten),
                          davor „183" nach `AFreshTakeStartsWithNoHeldFrameTests.swift` (#454 — der
                          Zwilling des Eintrags direkt darunter, eine Ebene TIEFER: #447 hat den
                          VERBRAUCHER dagegen gehärtet, dass ein messungsloser Frame Zustand zerstört,
                          und beim Nachlesen fiel auf, dass der ERZEUGER denselben Frame nach einem
                          Stopp gar nicht hätte schicken dürfen. `CameraRPPGBioPublisher.stop()` setzt
                          fünfundzwanzig ANDERE Pro-Take-Felder zurück und ließ DREI stehen (gezählt, nicht
                          geschätzt: 29 Zuweisungen im klammer-gematchten Rumpf, minus `publishTask`
                          und minus diese drei).
                          ⚠️ EHRLICHE REIHENFOLGE, weil die naheliegende Hälfte die harmlosere ist:
                          `tick` ist eine LOKALE Variable von `publishTask`, ein neuer Take beginnt
                          also wieder bei 0, während `lastGoodPublishTick` den Zählerstand des VORIGEN
                          Takes trug — `tick - lastGoodPublishTick` war stark NEGATIV, damit
                          `<= bioHoldTicks`, damit veröffentlichte der Ausfall-Halt den Frame des
                          vorigen Takes für das ganze
                          Neu-Akquise-Fenster (#415 hat dort ~19 s gemessen). ⛔ **NICHT „ab dem ersten
                          Tick", wie die erste Fassung schrieb:** der Veröffentlichungspfad liegt hinter
                          `tick % 10 == 0` UND hinter dem Wahrheits-Tor
                          `inboundRateEMA >= minMeasurableInboundHz`, der früheste Republish ist also
                          `tick == 10`, rund 1 s hinein — und eine frameslose erste Sekunde drückt den
                          neu gesäten EMA auf 15·0,9^10 ≈ 5,2, unter die 6,0, und überspringt auch den.
                          **Das ist zu großen
                          Teilen MASKIERT** und wird hier so gesagt: der gehaltene Frame trägt den
                          Stempel des vorigen Takes, also lässt `usableBio()` ihn nach 6 s verfallen,
                          jeder Verbraucher, der darauf HANDELT, dedupliziert auf dem Stempel oder tort
                          auf Frische, und `latestBio` wurde
                          von einem Stopp ohnehin nie geleert. Ein Neustart später als 6 s kostet
                          messbar nichts.
                          ⭐ **Die Hälfte, die NICHTS maskiert, ist `lastValidCoherence` auf dem
                          ERFOLGS-Pfad.** ⛔ Die erste Fassung schrieb „liegt gar nicht auf dem
                          Halte-Pfad" — falsch, und zwanzig Zeilen über dem Code, der es widerlegt: der
                          Halte-Zweig klingt das Feld ab (`*= 0.9`) UND veröffentlicht es. Nicht auf dem
                          Halte-Pfad liegt der ERFOLGS-Rückfall
                          `coherence.valid ? coherence.coherence : lastValidCoherence * 0.9`, dessen
                          Rückschreiber NUR bei gültigem Fenster läuft. Solange die Kohärenz ungültig
                          ist, trägt also JEDER
                          wirklich lebende Frame, mit neuem Stempel, echtem Puls und durch jedes
                          Frische-Tor, eine Zahl aus dem VORIGEN Take. Nichts stromabwärts kann
                          das fangen — der Frame IST frisch, nur diese eine Zahl gehört zu einem anderen
                          Take. Der Kommentar über der Zeile nennt die Absicht, die dabei verletzt wird
                          („Kohärenz über TRANSIENTE Ungültigkeit halten"), und ein Stopp/Start ist nicht
                          transient.
                          ⛔ **UND ZWEI GRÖSSENANGABEN IN DIESEM ABSATZ WAREN FALSCH, in
                          entgegengesetzte Richtungen.** (a) „einmal skaliert" lag um ~8× daneben, weil
                          die beiden Hälften NICHT unabhängig sind: `lastValidCoherence > 0` setzt eine
                          gültige Erfolgs-Veröffentlichung voraus, und derselbe Pfad setzt auch
                          `lastGoodBioFrame` — der Halte-Zweig aus Hälfte 1 feuert also bei JEDEM
                          Publish-Tick des neuen Takes und klingt das Feld jedes Mal um 0,9 ab. Bei den
                          hier zitierten ~19 s ist das `0,9^19 ≈ 0,135`, dann noch einmal skaliert:
                          **≈12 % des alten Wertes, nicht 90 %.** Was überlebt, ist der tragende Teil —
                          sobald der Halt aufhört zu feuern, klingt nichts mehr ab, es ist also eine
                          abgestandene KONSTANTE. (b) „Am Anfang eines Takes gibt es noch nicht genug
                          RR" hat die DAUER unterschätzt und die HÄUFIGKEIT überschätzt.
                          `HRVCoherence.minIntervals` ist 16, und die Kamera SAMMELT keine RR-Reihe —
                          `CameraAnalyzer` baut sie bei jedem Durchgang komplett aus einem festen
                          10-s-Peakfenster neu, 16 Intervalle brauchen also ≥17 saubere Peaks in 10 s,
                          d. h. anhaltend ≳102 bpm. Der `OSCSender`-Kopf hält das längst fest („auf der
                          KAMERA wird sie vielleicht nie erreicht"). Bei jedem RUHEPULS bleibt
                          `lastValidCoherence` damit für die ganze Prozesslebensdauer 0 und diese Hälfte
                          ist GEGENSTANDSLOS — und wenn ein Anstrengungs-Take sie doch schreibt, dauert
                          der Defekt den GANZEN nächsten Take. **Lehre: eine Hälfte, die ich „die
                          unmaskierbare" genannt habe, war gleichzeitig schlimmer und viel seltener als
                          behauptet — beide Richtungen gehören gemessen, bevor eine Größenangabe steht.**
                          ⚠️ **Die beiden Anker müssen GEMEINSAM geräumt werden, und das ist keine
                          Ordnungsliebe:** `Int.min` ist ein Sentinel INNERHALB einer Subtraktion.
                          `tick - Int.min` läuft über und bringt Swift zum Absturz. Das Einzige, was
                          das je verhindert hat, ist die Auswertungsreihenfolge — die Bindung
                          `if let held = self.lastGoodBioFrame` steht davor und schließt kurz, und die
                          zwei Felder sind nur gemeinsam `nil`/`Int.min`. Das Vertauschen der zwei
                          Bedingungen liest sich wie Aufräumen und macht aus einem frischen Start einen
                          Absturz; genau dafür steht die vierte Behauptung des Wächters da, und sie ist
                          ein GEGENGEWICHT — auf dem alten Code war sie schon grün.
                          ⚠️ Was der Wächter NICHT kann, und das steht als ERSTES in seinem Kopf: alle
                          Behauptungen sind QUELLTEXT-SCANS. Die drei Felder sind `private`, der
                          Publisher liegt hinter `#if canImport(AVFoundation)`, und ihn zu treiben
                          braucht eine Kamera — es gibt hier keinen Verhaltenstest zu schreiben, und die
                          Zahlen oben stammen aus dem Lesen des Codes, nicht aus einem Lauf.
                          ⚠️ Und er HÄTTE DEN FEHLER NICHT GEFUNDEN: ein Scan kann nur die Form
                          behaupten, für die sich schon jemand entschieden hat. Der Defekt war eine
                          AUSLASSUNG in einer Methode, die zwanzig andere Felder zurücksetzt — kein
                          Wächter über den zurückgesetzten Feldern hätte das bemerkt. Gemessen vor und
                          nach der Reparatur: die drei Zuweisungs-Behauptungen sind auf `880eb1c` alle
                          FALSCH und danach alle wahr, die vier Prämissen-Behauptungen auf beiden Seiten
                          wahr),
                          davor „182" nach `AHeldFrameCannotResetTheHoldTests.swift` (#447 — der erste
                          Wächter in dieser Kette über einem Frame, das GAR NICHTS MISST und trotzdem
                          alles zerstören konnte: `observe` führte den Rückwärtsuhr-Reset VOR dem
                          `guard let measured` aus, also konnte JEDER Frame mit einem älteren Stempel
                          `rate`, `horizon` und das Gewicht löschen — auch der eine, den das System
                          ABSICHTLICH mit eingefrorenem Stempel und ohne Atem erzeugt
                          (`CameraRPPGBioPublisher`s Puls-Halte-Wiederholung, `held.timestamp` +
                          `breathRate: 0`).
                          ⭐ Der Auslöser ist ENGER als „Quellen verschachteln", und genau das macht
                          daraus eine Ein-Anweisungs-Verschiebung statt eines Umbaus: JEDE echte
                          Messung stempelt `CFAbsoluteTimeGetCurrent()` beim EMPFANG — Kamera, BLE,
                          Demo und HealthKit gleichermaßen (#98c2 ist der Grund für die
                          Handgelenks-Hälfte). Echte Messungen sind also quellenübergreifend monoton;
                          die Halte-Wiederholung ist der EINE Stempel im System, der absichtlich
                          rückwärts geht. Mit einer Quelle ist das harmlos, weil der eingefrorene
                          Stempel GLEICH der letzten Messung ist und der Reset ein striktes `<`
                          braucht. Erst eine ZWEITE Quelle öffnet die Lücke — und
                          `healthBio.startIfAlreadyAuthorized` läuft auf App-Ebene, unabhängig von der
                          Quellenwahl der Puls-Pille.
                          ⚠️ GEMESSEN, weil „es setzt zurück" untertreibt: 1-Hz-Kamera-Frames, EIN
                          HealthKit-Frame, dann Halte-Wiederholungen — das Gewicht ging **1,0 → 0,0 in
                          EINEM Spur-Sample** und blieb dort, `rate` und `horizon` auf 0. Nichts
                          erholt sich, bis ein neuer GEMESSENER Frame kommt, und während eines
                          Puls-Aussetzers kommt keiner. Das ist der volle Sprung, den #434 mit diesem
                          Typ entfernt hat, im exakten Fall, für den er gebaut wurde — angekommen
                          durch einen Wächter, der für ein anderes Problem geschrieben war.
                          ⭐ Deshalb ist die halbe Datei ein GEGENGEWICHT: der Reset ist kein Müll.
                          Ohne ihn sitzt `lastMeasuredAt` nach einem NTP-Rücksprung in der Zukunft,
                          der `now > lastMeasuredAt`-Wächter darunter verwirft JEDEN späteren Frame
                          für immer, und `weight` zertifiziert weiter eine Rate, die niemand mehr
                          atmet — die #433-Erfundene-Zahl durch die Hintertür. Die Reparatur MUSS
                          eine Verschiebung sein, und beide Hälften stehen als Test da.
                          ⚠️ Was sie NICHT abdeckt, und das steht als eigener Block im Dateikopf: zwei
                          ECHTE Messungen verschiedener Quellen können durch ein Veröffentlichungs-
                          Rennen weiter in falscher Stempel-Reihenfolge ankommen (beide stempeln
                          Empfangszeit, auf verschiedenen Actors, Mikrosekunden auseinander). Dieser
                          Fall setzt weiter zurück, und er SOLL es — nichts hier kann ihn von einem
                          Uhrsprung unterscheiden. Ihn zu entfernen braucht Zustand PRO QUELLE
                          (`BioEventPublisher`s Form), also eine Entwurfsentscheidung darüber, welcher
                          Halt gewinnt, keine Umsortierung. #447 behält diese Hälfte.
                          ⚠️ Und die härteste Grenze, unverändert seit #433/#434/#444/#448: nichts
                          davon ist hörbar oder aufgezeichnet — `RecordController.onStep` beginnt mit
                          `guard armed else { return }`, `arm()` hat null Aufrufer (#204). Repariert
                          WIRD es deshalb, nicht trotzdem),
                          davor „181" nach `OneDefinitionOfAParameterRangeTests.swift` (#441 — der erste
                          Wächter in dieser Kette über einer DREIFACHEN Definition, und der erste, der
                          eine davon ABSICHTLICH stehen lässt. Jeder der 17 Sound-Panel-Parameter hatte
                          seinen Bereich dreimal aufgeschrieben: als Literal an der
                          `param(`/`knob(`-Aufrufstelle, noch einmal in `SoundPrompt.clamp`, und ein
                          drittes Mal in der handgeschriebenen Modelltabelle des #430-Wächters nebenan.
                          Die ersten beiden sind jetzt EINE Konstante (`SynthPatch.Bounds`); die dritte
                          bleibt von Hand, weil ein Wächter, der die geprüfte Konstante liest, eine
                          falsche Konstante nicht fangen kann.
                          ⭐ **Der eine, der wirklich etwas gekostet hat, ist `filterLFORate`:** Zeile
                          0…20 Hz, Prompt klemmte auf 0…12. #430 hat genau diesen Unterschied gesehen
                          und als harmlos abgetan, weil die ausgelieferte Bank bei 1,2 Hz endet — und
                          damit auf die FALSCHE Population geschaut. Die Zeile lässt einen FINGER bis 20,
                          und `SoundPrompt.apply` endet mit einem UNBEDINGTEN `clamp(&p)`. Ein auf 19 Hz
                          gezogener Wert kam als 12 zurück — **nicht nur bei erkannten Wörtern**: ein
                          völlig unbekannter Prompt formt nichts und klemmt trotzdem, der Wert starb also
                          an Text, den die Engine ignoriert. Das ist der `Drone Bed`-Defekt aus #430, ein
                          Feld weiter und in der schwerer zu bemerkenden Richtung: **eine Fixtur hält
                          keinen nutzergesetzten Wert, also wurde nie etwas rot.**
                          ⚠️ Die zweite Abweichung ist KOSMETISCH und steht als solche da: der Prompt
                          hatte für `attack` einen Boden von 0,001 s, die Zeile beginnt bei 0. Gemessen
                          statt angenommen — `EchoelDDSP`s Hüllkurve erzwingt in ihrer `.attack`-Stufe
                          ohnehin eine ~3-ms-Mindestrampe (`minAttackSamples`), 0 und 0,001 sind also
                          derselbe Klang, und der erklärte Zweck des Bodens („ein musikalisches Minimum
                          unter jedem ausgelieferten Onset") war eine Schicht tiefer längst erfüllt.
                          ⭐ Die RICHTUNG ist eine Regel und keine Einzelfallentscheidung: wo die zwei
                          sich widersprachen, gewinnt die ZEILE und der Prompt WEITET. Weiten kann keinen
                          ausgelieferten oder nutzergesetzten Wert abschneiden — genau die Invariante,
                          die #430s `decay`-Reparatur sicher machte —, während das Verengen einer Zeile
                          einem Bedienelement still Reichweite nimmt, die der Nutzer schon hat.
                          ⛔ **Und diese Scheibe ERZEUGT eine Lücke, die sie selbst schließen muss:**
                          alle Verhaltens-Behauptungen lesen `Bounds` auf BEIDEN Seiten, ein VERENGEN
                          bewegt also Zeile und Prompt gemeinsam und nichts wird rot — während die Zeile
                          dann einen Patch abschneidet, den sie vorher erreichte. Vor #441 standen dem
                          die vier Volltext-Pins des #430-Wächters im Weg; #441 ersetzt deren
                          Bereichs-Hälfte durch eine Bindung. Die Konstante wird deshalb den DATEN
                          verantwortlich gemacht: jeder ausgelieferte Patch-Wert muss in seinen eigenen
                          Bereich passen (`testEveryShippedPatchFitsInsideItsOwnBound`).
                          ⛔ **UND DIESER WÄCHTER WISCHTE IN SEINER ERSTEN FASSUNG DIE FALSCHE
                          POPULATION — während er, der Commit-Text und der Nachbar-Wächter gleichlautend
                          behaupteten, „`Drone Bed`s 6,0-s-Decay ist der Wert, der das beißen lässt".**
                          `Drone Bed` liegt gar nicht in `SynthPatch.factory`; es wird von
                          `GenrePatches.patch("EE", "Drone Bed", … d: 6.0, …)` gebaut und über
                          `MusicStyle.synthPatch` erreicht — eine eigene Population, die genauso in
                          `currentPatch` landet. Das Decay-Maximum der Werksbank ist **1,5**, der Wächter
                          hatte auf dem einen Feld, das er NANNTE, also 85 % Luft: `Bounds.decay` ließe
                          sich auf `0...5` verengen — der wörtliche #430-Defekt — bei grünem Repo.
                          **Das ist derselbe Methodenfehler, den der Nachbar-Wächter im eigenen Kopf
                          festhält** („die dritte GENANNTE Quelle, `MusicStyle.synthPatch`, war dem Scan
                          unsichtbar"), begangen in der Scheibe, die ihn zitiert, einen Absatz nachdem
                          sie #430 „die falsche Population" vorgeworfen hat. Jetzt über alle DREI Bänke,
                          mit Nichtleer-Boden pro Bank; gemessene Maxima: decay 6,0 · release 7,5 ·
                          reverbDecay 8,5 · cutoff 8000 · attack 3,5 · vibratoRate 6,2 — kein Wert
                          außerhalb.
                          ⭐ **Und die Daten können ausgerechnet das Feld nicht schützen, für das die
                          Scheibe existiert:** der höchste ausgelieferte `filterLFORate` ist über alle
                          drei Bänke **1,2 Hz**, ein Zurück-Verengen auf `0...12` bliebe also unbemerkt.
                          Der gerettete Wert war ein NUTZER-gesetztes 19 Hz, und keine Fixtur hält so
                          etwas — das ist die ganze Form des Defekts. Diese EINE Decke ist deshalb von
                          Hand festgenagelt, mit einer zweiten Behauptung, die rot wird, sobald ein
                          ausgelieferter Patch die 12 erreicht und die Prämisse damit entfällt. Bewusst
                          EIN Feld und nicht siebzehn (#430s eigene Lehre: alles festnageln macht jede
                          gewöhnliche Panel-Änderung rot, und so wird ein Wächter gelöscht).
                          ⚠️ Vier weitere Nachlese-Befunde, alle Prosa-Wahrheit: `FilterCutoffClampTests`
                          und `EchoelDDSP.cutoffRange` trugen beide weiter „`SoundPrompt` und der Knopf
                          behalten ihre Literale — das Einfalten ist eine eigene Aufgabe", während #441
                          genau diese Aufgabe war (der überlebende, WAHRE Teil: `RoleRhythm.swift`s
                          `TimbreTrim.trimmed` ist weiter eine ungeschützte Kopie auf dem LEBENDEN Pfad);
                          der Nachbar-Wächter widersprach sich zwischen Doc-Kommentar und Innenkommentar
                          derselben Funktion; `Bounds` behauptete „jeder Parameter, den das Panel
                          rendert" statt der ÜBERSCHNEIDUNG mit `SoundPrompt` (`unisonVoices`,
                          `unisonDetuneCents`, `outputLevel` fehlen absichtlich); und die zwei
                          Quelltext-Scans lasen den ROHTEXT, obwohl #453 zwei Commits zuvor genau dafür
                          `SourceText.codeOnly` geschaffen hat.
                          ⭐ Letzteres war beim Schreiben prophylaktisch und ist es **im selben Commit
                          nicht mehr**: die Korrektur der veralteten Bereichs-Notiz neben der
                          Decay-Zeile setzt `SynthPatch.Bounds.decay` in einen KOMMENTAR — gemessen 2×
                          roh, 1× im Code, alle anderen 1/1.
                          ⚠️ Und die Kettung kostet eine Plattform: `EchoelDDSP.swift` liegt vollständig
                          in `#if canImport(Accelerate)`, `SynthPatch` ist damit Accelerate-only. Kein
                          Workflow kompiliert Swift woanders (`quick-test.yml` sagt das über sich
                          selbst), die Entscheidung steht mit ihrem Fluchtweg neben der Konstante.
                          ⚠️ Was der Wächter NICHT kann: zeigen, dass irgendetwas davon HÖRBAR ist — ob
                          19 Hz besser klingt als 12, ist eine Geräteprobe. Prüfbar ist nur, dass die
                          Zahl, die die Zeile anbietet, die Zahl ist, die die App behält),
                          davor „180"
                          nach `ASnappedValueIsLegalForItsRowTests.swift` (#442 — der erste
                          Wächter in dieser Kette über einem RUNDUNGSFEHLER, der einen Wert AUS
                          SEINEM EIGENEN BEREICH herausträgt: `ScrubPrecision.snapped` klemmte und
                          RASTETE DANN, und Rasten geht zum NÄCHSTEN Gitterpunkt — auf einer
                          `0…0,995`-Zeile mit 2 Stellen wird aus dem geklemmten 0,995 also 1,00,
                          eine halbe Rasterstufe ÜBER dem deklarierten Maximum; auf `0,4…0,6` bei
                          ganzen Zahlen wird 1,0 festgeschrieben, also zwei Drittel des Bereichs
                          daneben.
                          ⭐ **Und das Vertauschen der zwei Zeilen ist NICHT die Reparatur** — das
                          ist der Grund, warum es eine eigene Datei gibt und keinen Ein-Zeilen-Diff.
                          Rastern-dann-Klemmen landet exakt AUF einer nicht-gerasterten Grenze, und
                          die Anzeige formatiert seit #432 den GERASTERTEN Wert: die Zeile zeigte
                          dann eine Zahl und behielte eine andere — genau der Defekt, den #432
                          geschlossen hat. Keine der beiden Reihenfolgen erfüllt beide
                          Versprechen. Gerastert wird deshalb nach INNEN: nächster Gitterpunkt,
                          eine Stufe zurück nach innen, falls der draußen lag.
                          ⛔ **Und die erste Fassung dieser Reparatur hätte `0,95` von FÜNF
                          ausgelieferten Zeilen genommen** — deshalb trägt der Vergleich ein
                          `slack` und ist kein nacktes `>`. Eine Grenze kommt als
                          `Double(range.upperBound)` an, und für eine `Float`-Zeile ist das nicht
                          das Literal: `Float(0.95)` ist `0,9499999880790710`. #430 hat 11 von 86
                          Grenzen in diesem Zustand gemessen. Ein nacktes `landed > upperBound`
                          liest `0,95 > 0,94999998…` als echten Überschuss und senkt das Maximum
                          der Zeile auf `0,94`. Die ALTE Reihenfolge war dagegen aus Versehen
                          immun, weil sie zuerst klemmte — und genau deshalb ist die naheliegend
                          aussehende Änderung die gefährliche.
                          ⚠️ GEMESSENER UMFANG, bevor irgendetwas geändert wurde: auf dem
                          heutigen Baum ändert die Scheibe NICHTS. Alle 74 aus Literalen
                          erreichbaren Bereichsgrenzen in `Sources/` liegen schon auf dem Raster
                          ihrer eigenen Zeile, und wo die Grenze auf dem Raster liegt, kann
                          monotones Runden sie nicht überschreiten. Über 23 ausgeliefert-geformte
                          Bereiche × 2001 Abtastwerte — **46 023 Vergleiche, 0 Abweichungen**; die
                          `Float`-Umlauf-Grenzen ebenfalls 0; 200 000 Zufallsfälle inklusive
                          absichtlich nicht-gerasterter Grenzen: 0 Bereichs- und 0
                          Raster-Verletzungen. Entfernt einen MECHANISMUS, keinen heutigen Defekt —
                          und kauft die NÄCHSTE Zeile, in einer Datei, die schon eine
                          `Cutoff`-Zeile über 80…18000 Hz mit `decimals: 0` ausliefert.
                          ⚠️ Das Versprechen heißt deshalb „auf dem Raster UND im Bereich bis auf
                          `slack`" und nicht exakte Enthaltung; und wo ein Bereich GAR KEINEN
                          Gitterpunkt enthält (`0,4…0,6` bei ganzen Zahlen), gewinnt IM-BEREICH
                          über AUF-DEM-RASTER: eine Zahl außerhalb des Bereichs erreicht eine
                          Engine, eine nicht-gerasterte kann nur falsch angezeigt werden.
                          ⛔ **Nebenbefund derselben Runde, und er ist die #445-Klasse in einer
                          Zeile:** `ScrubNotifiesOnlyOnRealChangeTests` suchte
                          `V(ScrubPrecision.snapped(running,` — diese Schreibweise gibt es seit
                          #427 nicht mehr (der Vergleich zog nach `ScrubPrecision.carriesTarget`,
                          wo der Aufruf unqualifiziert `snapped(...)` heißt). Der Wächter war
                          also seit #427 ROT und **niemand konnte es sehen, weil #396 das
                          blockierende Bundle vor jedem Testlauf tötet**. Gefunden beim Prüfen
                          der #442-Reichweite, nicht durch einen Lauf. Jetzt zwei Nadeln, weil die
                          Eigenschaft eine KETTE ist: der Zug muss das Prädikat fragen, und das
                          Prädikat muss in `V` vergleichen),
                          davor „179"
                          nach `SourceText.swift` + `OneDefinitionOfCodeNotProseTests.swift`
                          (#453 — die erste Scheibe dieser Kette, die ZWEI Dateien auf einmal legt und
                          von der ich vorher wusste, dass sie es tut: eine DEFINITION und ihr Waechter.
                          Registriert war sie als „`codeOnly`-Helfer ist ZWEIMAL im blockierenden
                          Bundle". Gezaehlt: **ELF Kopien in FUENF materiell verschiedenen Formen** —
                          Zeile loeschen · Zeile leeren · am ersten `//` abschneiden · trimmen und
                          beides · `/* … */` ZUERST strippen. Meine eigene Registrierung war um den
                          Faktor 5,5 daneben, und das ist die #416-Form in ihrer breitesten Auspraegung:
                          eine Entscheidung, elf Orte, nichts das merkt, wenn sie auseinanderlaufen.
                          ⚠️ EHRLICHER UMFANG: auf dem heutigen Baum stimmen die elf fuer JEDE
                          `contains`-Behauptung ueberein. ⛔ **Die Begruendung dafuer war zur Haelfte
                          falsch, und sie stand in dieser Zeile, im Dateikopf des Waechters und im
                          Commit-Text: „keine gescannte Zeile ein `//` in einem String-Literal".**
                          `EchoelStudioView.swift` — von `EveryReachableRowStatesItsGridTests` bei
                          JEDEM Lauf gescannt — traegt die WeatherKit-Attributions-URL in
                          `URL(string: "https://developer.apple.com/…")`, und genau diese EINE Zeile
                          ist die, auf der die abschneidenden Formen und der geordnete Scanner
                          auseinandergehen. Der erste Anlauf migrierte deshalb nur DREI und stellte
                          die anderen acht auf eine beidseitig gepruefte Erlaubnisliste; die
                          NACHLESE hat alle acht eingefaltet und die Liste ersatzlos entfernt — ein
                          Freibrief, dessen Praemisse nicht galt, wird nicht korrigiert, sondern
                          zurueckgezogen. Verdikt-neutral ist die Migration trotzdem, und der
                          schaerfste Fall ist der Gitter-Waechter, weil sein Suchwort auch in Prosa
                          steht: `decimals:` sitzt 9× in `EchoelValueField.swift`, 8× in
                          `EchoelStudioView.swift`, 2× in `EchoelFXView.swift` und je 1× in
                          `BodyTempoField.swift`/`WorkspaceView.swift` in Zeilenkommentaren — unter
                          einer Form, die nachlaufende Kommentare BEHAELT, haette jeder davon
                          innerhalb der Zeilenspanne einer Aufrufstelle den Waechter als PROSA
                          befriedigt. Beidseitig gemessen sind die Aufrufstellen-Zahlen (1/1 · 4/4 ·
                          46/46 · 1/1 fuer `EchoelValueField(`, 44/44 fuer `field(`) und die
                          Ohne-`decimals:`-Mengen ([131] auf `BodyTempoField`, sonst leer) IDENTISCH.
                          Die Liste im Waechter ist seither ein BODEN, keine Volkszaehlung: sie nennt
                          die elf und prueft, dass jede noch delegiert, verlangt aber NICHT, dass
                          jeder kuenftige delegierende Waechter eingetragen wird — ein neuer
                          Waechter, der zum geteilten Scanner greift, ist genau das gewollte
                          Verhalten, und eine Regel, die ihn dafuer rot macht, waere die
                          #364-Falle. Die Gegenrichtung haelt `testNoUnlistedFileDeclaresItsOwnStripper`,
                          das von einer ZWOELFTEN privaten Kopie handelt und gar keine Liste braucht.
                          ⛔ **UND DIE ZWOELFTE WAR SCHON DA (#477, 2026-08-07).**
                          `TimingVerdictReachesTheScreenTests` (#408) ist aelter als #453 und trug ein
                          privates `func codeOnly`, das nicht einfaltete; die Erkennungs-Nadel des
                          Waechters — `func codeOnly` ohne `SourceText.codeOnly` — waehlt es
                          DETERMINISTISCH aus (die Logik gegen den Baum nachgebaut liefert genau diese
                          eine Datei). Die Handzaehlung sagte ELF, der ausfuehrbare Test haette ZWOELF
                          gesagt, und die Zahl in allen drei Artefakten (hier, Dateikopf, Commit-Text)
                          kam von der Zaehlung.
                          ⚠️ **GENAU GESAGT, weil die schmeichelhafte Fassung „der Waechter hat es beim
                          ersten Lauf genannt" lautet und das eine Behauptung ueber einen LAUF ist:** die
                          Behauptung WAERE auf jedem Lauf gescheitert, der sie erreicht hat — ob ein Lauf
                          sie je erreicht hat, ist UNWISSBAR. Sie taucht in keinem geleerten CI-Log auf,
                          und nach #445 beweist diese Abwesenheit nichts (#396 toetet einen Simulator-Klon
                          mitten in der Suite, der ueberlebende leert eine nicht-deterministische
                          Teilmenge). Das ist SCHLIMMER als ein uebersehenes Rot, nicht besser: ein
                          Wächter, dessen Verdikt niemand beobachten kann, ist noch keiner.
                          ⭐ **Die Lehre ist eine ueber VORRANG, nicht ueber Sorgfalt: wenn eine
                          Handzaehlung und ein ausfuehrbarer Waechter sich widersprechen, ist der
                          Waechter die MESSUNG und die Zaehlung eine Erinnerung.** Und der Grund, warum
                          die Antwort ein Tag lang liegen blieb, ist #445 in seiner teuersten Form: #396
                          faerbt JEDEN CI/CD-Lauf `failure`, eine Conclusion ist damit kein Ergebnis,
                          und dieser rote Wächter war von der Wirt-Leiche nur durch Lesen des Job-Logs
                          zu unterscheiden. Ein Wächter, der eine richtige Antwort gibt, die niemand
                          abholt, ist kein Wächter.
                          ⚠️ Die Migration ist VERDIKT-NEUTRAL und das ist gemessen, nicht angenommen:
                          von den zwei Dateien, die dieser Test scannt, unterscheiden sich die beiden
                          Streif-Formen auf `AudioEngine.swift` in **0 Zeilen** (die zwei Byte-Offsets
                          der Reihenfolge-Behauptung sind bitgleich) und auf `EchoelStudioView.swift`
                          in **genau 1** — der WeatherKit-URL-Zeile aus dem Absatz oben, die keinen der
                          vier Anker traegt.
                          ⚠️ Und die WAHRE Kopienzahl liegt weit ueber zwoelf, weil der Waechter nach
                          NAMEN erkennt (gemessen 2026-08-07): 8 Dateien deklarieren `stripComment`,
                          3 `stripComments`, 2 `sourceLines` und **60** `codeLines` — davon streifen
                          **58** selbst und **keine** faltet ein. Das ist #460 und bleibt bewusst
                          offen: die Nadel zu weiten faerbt ~70 Dateien in EINEM Commit rot, und das
                          ist eine Migration, keine Waechter-Aenderung.
                          ⭐ **Was NICHT prophylaktisch ist, und es steht andersherum als man erwartet:
                          die GRUENDLICHSTE Form ist die gefaehrlichste.** Zwei der elf strippen
                          `/* … */` VOR den Zeilenkommentaren. Ein `/*`, das gar kein Blockanfang ist —
                          in einer `///`-Zeile, in einem String —, oeffnet damit einen Phantom-Block und
                          frisst alles bis zum naechsten `*/`. In `Sources/` liegen **8 solche `/*` in
                          6 Dateien**, eines davon (`` `/echoelmusic/bio/breath/*` ``) in
                          `BreathPattern.swift`, das `ThePacedRateMustBeReadableTests` scannt. Eine
                          positive Behauptung wuerde dort rot, eine NEGATIVE gruen auf nichts — genau
                          das, wogegen das blockierende Bundle existiert. Die Reparatur ist deshalb die
                          REIHENFOLGE und nicht die Gruendlichkeit: `SourceText.codeOnly` laeuft jede
                          Zeile einmal in der Reihenfolge des Compilers durch, ein Anfuehrungszeichen
                          schaltet String-Zustand um, also kann weder `//` noch `/*` aus einem Literal
                          heraus feuern. Die Zeilenzahl bleibt erhalten, weil mehrere Waechter auf der
                          REIHENFOLGE zweier Treffer behaupten.
                          ⚠️ Gemessen, bevor irgendetwas migriert wurde: die neue Definition und die
                          alte Form liefern fuer alle 11 lebenden Behauptungen der drei migrierten
                          Dateien **identische Ergebnisse** (0 Abweichungen ueber
                          `RespirationEstimator` · `BreathPattern` · `BreathGuideView` ·
                          `MeditationView`). Die Scheibe entfernt einen MECHANISMUS, keinen heutigen
                          Defekt — so gesagt, statt als Bugfix verkleidet.
                          ⚠️ Was sie NICHT kann: keine ihrer Behauptungen ist ein Lauf, und Raw Strings
                          sowie verschachtelte Bloecke sind bewusst NICHT behandelt — beides trifft
                          heute keine Scan-Zielscheibe, und ein Waechter ueber einem Fall, den es nicht
                          gibt, ist die #367-Falle),
                          davor „177"
                          nach `TheWristReadingIsNotUnderweightedTests.swift` (#448 — der erste
                          Wächter in dieser Kette über einer Konstante, die NIE GEWÄHLT WURDE. Der
                          Kopf von `BreathHold.swift` leitet die TEILUNG her (Gnadenfrist = Release =
                          horizon/2, gekettet an `BioSource.freshnessWindow`, damit der Einfluss genau
                          dann erlischt, wenn der Bus dem Frame nicht mehr traut — #426s Form). Den
                          ANSTIEG leitet er nirgends her: `up` benutzte schlicht denselben Teiler
                          `half`, den die ABLAUF-Seite gewählt hatte.
                          ⭐ Die Rechnung kostet ausgerechnet die Quelle, deren ganze Prämisse
                          „ein Messwert von vor einer Minute ist immer noch deiner" ist: 90 s
                          Fenster heißt 45 s Anstieg, eine Handgelenks-Atemrate verbringt ihr ganzes
                          nutzbares Leben mit Steigen und Fallen und berührt Vollgewicht für EINEN
                          Augenblick. Kontinuierlicher Mittelwert über die 90 s: exakt **1/2**.
                          `.oura` (600 s) ist schlimmer und hat heute keinen Produzenten.
                          ⭐ **Die Reparatur erfindet keine Zahl — sie verallgemeinert, was der
                          LEBENDE Pfad ohnehin tut.** 3 s ist, worüber Kamera/BLE — die einzige lebende
                          Quelle — heute schon ansteigt; `BreathHold.maximumAttack = 3.0` deckelt das
                          für jede Quelle.
                          ⛔ **Die erste Fassung begründete die 3 s anders — „DREI Frames bei der
                          ~1-Hz-Anwendungsrate, die kürzeste Rampe, die auf einer so abgetasteten Spur
                          als Rampe liest" — und diese Herleitung ist FALSCH, an einer Tatsache, die
                          `BreathHold.swift` zweihundert Zeilen tiefer selbst festhält.** Die Rampe wird
                          nicht an Frame-Ankünften abgetastet: `RecordController.onStep` liest sie als
                          `breathHold.weight(at: CFAbsoluteTimeGetCurrent())` bei JEDEM Transport-Schritt,
                          und `BioAutomationRecorder.minTickInterval` steht per Default auf genau einem
                          Schritt, dezimiert also nichts. `Transport.stepDuration(atTempo:)` ist
                          `60/bpm/4` über eine 30…300-Klemme, die Spurrate also **2–20 Hz — 8 Hz beim
                          Standard-Tempo 120**, wo 3 s ~24 Keyframes sind und nicht drei. Die Zahl bleibt,
                          die Begründung war eine nachgeschobene Rationalisierung. Die ehrliche lautet:
                          der Anstieg ist eine SLEW-GRENZE AUF DER SPUR, und eine Slew-Grenze hat nichts
                          damit zu tun, wie lange die Messung eines Sensors frisch bleibt.
                          ⭐ Die `min(releaseSeconds, …)`-FORM ist zweifach tragend, und deshalb
                          behauptet der Wächter sie direkt: Kamera (3 s) und `.fallback` (2,5 s)
                          bleiben BITGLEICH — jede Behauptung in `TheGapClimbCannotChangeTheResumeTests`
                          misst also weiter, was sie maß —, und #444s Theorem braucht
                          `elapsed > half >= attack` an jedem Neustart, um `up > 1` zu folgern. Eine
                          nackte Konstante über der Release irgendeiner Quelle hätte diesen Beweis
                          still gebrochen, ohne dass die Nachbardatei rot geworden wäre: sie treibt
                          nur das Kamera-Fenster.
                          ⚠️ Gemessen, MIT genanntem Raster (alle 0,5 s über ein volles 90-s-Leben):
                          Mittel **0,4972 → 0,7293**. Die exakten kontinuierlichen Mittel sind
                          rasterfrei und sauberer: **1/2 → 11/15**. Kamera und `.fallback`: max |Δ|
                          exakt **0** an jedem Abtastwert.
                          ⛔ **Die Zahl, die der `BreathHold`-Kopf dafür trug — „mean weight 0.4712" —
                          ist zurückgenommen**, weil sie ohne Raster dastand.
                          ⛔ **UND DIE ERSTE RÜCKNAHME WAR SELBST FALSCH — im Absatz über falsche
                          Zahlen.** Sie sagte „keine Abtastung der alten Form ergibt sie … weder
                          reproduzierbar noch widerlegbar". Doch: **0,4712 = 90/191 exakt** — genau
                          dieses 0,5-s-Raster, nur bis t = 95 s statt bis 90 gefahren. Die Spur summiert
                          so oder so zu 90 (alles jenseits des Horizonts ist 0), die zehn zusätzlichen
                          Null-Abtastwerte ziehen den Mittelwert also von 90/181 auf 90/191. Über
                          Schritt ∈ {0,05 … 5} × Ende ∈ [90, 130] gewischt ist das der EINZIGE Treffer.
                          Die alte Zahl war damit UNTERSPEZIFIZIERT, nicht unreproduzierbar, und sie las
                          tief, weil ihr Fenster zehn Abtastwerte reiner Nach-Ablauf-Stille enthielt.
                          **Eine gemessene Zahl trägt in diesem Repo ihr Raster, oder sie ist keine
                          Messung — und eine Rücknahme trägt die Suche, die gescheitert ist, oder sie
                          ist keine Rücknahme.**
                          ⚠️ Was NICHT repariert ist: das Flacker-Dreieck. Auf Kamera/BLE ist der
                          Anstieg unverändert, eine langsamer als ihr Horizont flackernde Quelle
                          zeichnet also exakt dieselbe Form. Das Artefakt war an diesem Fenster nie
                          die Schuld der Anstiegsrate, sondern die Form von `min(up, down)` selbst.
                          ⚠️ **Und #448 FÜGT auf dem reparierten Fenster eines HINZU** — die erste
                          Fassung schrieb „Kamera/BLE unverändert" und hörte auf, was sich wie
                          „überall unverändert" liest. Auf dem HANDGELENK wird die Flackerform ein
                          SÄGEZAHN (3 s Anstieg, 45 s Abfall), und eine steile Flanke schiebt
                          Wechselenergie ins Atemband. Vom Reviewer gemessen, Anteil der AC-Energie in
                          0,05–0,5 Hz, alt → neu: 60-s-Flackerperiode **1,28 % → 27,25 %** · 120 s
                          0,09 % → 2,98 % · 180 s 0,07 % → 1,88 % · 300 s 0,06 % → 1,43 %. Die
                          Amplitude ist bei jeder gewischten Periode bitgleich, und der größte Schritt
                          zwischen zwei Keyframes beträgt beim langsamsten zulässigen Tempo 0,1667
                          Gewichtseinheiten — nach der `|hr − br|/2`-Skalierung also ≤ 0,083
                          Spur-Einheiten, eine Größenordnung unter dem 0,4286-Sprung, gegen den #434
                          existiert, und exakt das, was Kamera/BLE heute schon ausliefert. Es wird also
                          bei keinem zulässigen Tempo ein Sprung wiedereingeführt; der Einschwinger ist
                          real und steht deshalb hier statt unter einem kamera-begrenzten Satz.
                          ⚠️ Und die härteste Grenze, unverändert seit #433/#434: nichts davon ist
                          hörbar oder aufgezeichnet — `RecordController.onStep` beginnt mit
                          `guard armed else { return }`, `arm()` hat null Aufrufer (#204). Repariert
                          WIRD es deshalb, nicht trotzdem. Und **kein Gate hat es gesehen** (#451)),
                          davor „176"
                          nach `ARejectedCrossingIsNotFreshnessTests.swift` (#452 — der erste
                          Wächter in dieser Kette über einer LATCH, die den Messwert der VORIGEN
                          Technik weiterbehauptet — mit voller Konfidenz, während der Körper etwas
                          atmet, das das Band gar nicht lesen kann. `ingest` setzte
                          `lastCrossT = t` AUSSERHALB des Annahme-Zweigs, und die Frische-Logik maß
                          die Veralterung von genau dieser Variable. `ratePerMinute` hält seinen
                          letzten ANGENOMMENEN Wert für immer (die Datei sagt das an der
                          Deklaration selbst). Also hielt ein Körper, dessen Atmung Durchgänge
                          erzeugt, die das Band VERWIRFT, den Anker in Bewegung: Veralterung blieb
                          null, Frische blieb auf 1,0 festgenagelt, und der alte Wert wurde weiter
                          zertifiziert.
                          ⭐ **Das ist die DRITTE Latch in EINER Datei, und die Datei benennt die
                          anderen zwei selbst** — den Frische-Term („fängt den Take, der in einer
                          flachen Spur endet") und das Hüllkurven-Veto („fängt den, der in einer
                          VERRAUSCHTEN endet"), mit dem eigenen Satz, jeder sei „die HALBE Antwort"
                          und keiner ersetze den anderen. Beide Hälften handeln von einer Spur, die
                          DEGRADIERT. Dieser dritte Fall ist eine vollkommen SAUBERE Spur, die
                          einfach aus dem Band wandert: die Hüllkurve ist gesund, also schweigt das
                          Veto, und der Anker lief weiter, also feuerte die Frische nie. **Eine
                          Taxonomie mit zwei Fällen ist kein Beweis, dass es zwei sind.**
                          ⭐ Und der Auslöser ist ein Muster, das ECHOEL SELBST VORGIBT: Box (3,75)
                          und 4-7-8 (3,158) liegen beide unter `reportableRange` (#435). `ingest`
                          und `refreshConfidence` Zeile für Zeile transkribiert und aus
                          `BreathPattern.sample` getrieben — 120 s Resonanz, dann 180 s 4-7-8 —
                          veröffentlichte der Schätzer an ALLEN 66 ganzzahligen Ruhepulsen 45…110
                          im Mittel **5,985/min bei Konfidenz exakt 1,000**, während der Körper mit
                          3,158 atmete: **+89,5 % Fehler, zertifiziert**. Am ANNAHME-Anker fallen
                          alle 66 auf Konfidenz 0,000 und veröffentlichen nichts — die ehrliche
                          Antwort: wir können dieses Tempo nicht lesen, also sagen wir nichts, statt
                          die Zahl der vorigen Technik zu wiederholen.
                          ⛔ **Hier stand „Box genauso (11 verworfene Durchgänge, Konfidenz 1,000)"
                          — eine unqualifizierte Behauptung aus EINEM Puls, und 60 ist genau der
                          Puls, den der #435-Eintrag drei Bildschirme weiter unten selbst als
                          entartet benennt** (16-s-Zyklus = exakt 16 Schläge). Gewischt: ausgeliefert
                          veröffentlicht Box an 66/66 Pulsen, davon **16 mit der STALEN
                          Resonanz-Zahl** (>5/min); mit der Reparatur an **45/66**, stale-Zahl
                          **0/66**. Die Reparatur macht Box also nicht still — sie nimmt der Zahl
                          die fremde Herkunft. ⛔ Und die zweite Fassung nannte diese 45 „jede davon
                          Box' EIGENE Rate": sie sind box-ABGELEITET, aber sie lesen 3,8168…4,7743
                          für einen Körper bei 3,7500, also **+1,8 % bis +27,3 %, Mittel +8,8 %** —
                          der Quantisierungsfehler aus #435, unrepariert. Eine Formulierung, die ihn
                          verschweigt, behauptet ihn als behoben.
                          ⛔ **Und „es kostet im Band NICHTS" war am unteren Rand FALSCH, zweimal
                          hintereinander.** Erste Fassung: nur bei 6/min gemessen. Zweite: 4,00 und
                          28,04 dazu — und trotzdem daneben, weil die zahlende Scheibe UNTER 4 liegt.
                          Der Annahme-Boden ist `minRate/tolerance` = **3,7736**, und #426 hat
                          `HealthWritePolicy` bewusst auf 3,7 gesenkt, um genau diese Scheibe
                          zuzulassen. Gewischt über dieselben 66 Pulse: **3,78/min 64/66 → 51/66 ·
                          3,80/min 66/66 → 58/66 · ab 3,85 bis 30 unverändert** (4,00 · 6,00 · 12 ·
                          20 · 28,04 · 30: 0 Abweichungen). Die Richtung stimmt und ist ebenfalls
                          gemessen — die stillgelegten Messwerte lagen bei 3,78 um +2,8…+8,3 %
                          daneben —, aber die ehrliche Formulierung ist „kostet ab ~3,85/min
                          nichts", nicht „kostet im Band nichts".
                          ⭐ Die In-Band-Hälfte ist ohnehin ein THEOREM und nicht ein Sweep:
                          `lastAcceptT` hat genau EINEN Schreiber und EINEN Leser, kann also
                          `ratePerMinute`/`amplitude`/`periodEMA`/`crossingCount` gar nicht
                          erreichen; und wo JEDER Durchgang angenommen wird, gilt ab dem zweiten
                          `lastAcceptT == lastCrossT`. Genau deshalb ist die Scheibe oben der ganze
                          Preis: sie ist exakt die Menge der Takes mit VERWORFENEN Durchgängen.
                          ⚠️ Ein verworfener Durchgang senkt die Konfidenz nur, wenn die entstehende
                          LÜCKE `1,5·periodEMA + pullLagAllowance` (≈16,8 s bei 6/min) übersteigt —
                          ein 20-s-Zyklus in einen 6/min-Take gespleißt drückt sie auf 0,5329 und sie
                          erholt sich; ein Verwurf durch einen zu SCHNELLEN Durchgang kostet direkt
                          nichts. Unter HR-Rauschen senken BEIDE Varianten auf denselben Takes
                          (sd 4/8/12/16 bpm, je 30 Takes: 7/7/4/7 gegen 7/9/5/8) — dort ist der
                          Einbruch der Hüllkurve zuzuschreiben, nicht dem Anker.
                          ⚠️ Und die Erholung gehört neben die „Konfidenz 0,000", sonst liest sich
                          die Reparatur wie eine Aussperrung: nach 180 s 4-7-8 zertifiziert
                          wiederaufgenommene Resonanzatmung nach **3,71 s** wieder (ausgeliefert:
                          0,63 s, weil sie nie de-zertifiziert hatte).
                          ⚠️ Der Sweep ist ein MODELL und wird NICHT festgenagelt, aus demselben
                          Grund, aus dem #435 seinen eigenen nicht festnagelt: die Zahlen stammen aus
                          meiner Transkription, sie festzunageln hieße die Transkription festnageln
                          statt das Produkt. Behauptet wird, was der AUSGELIEFERTE Typ tut, wenn man
                          ihn direkt treibt.
                          ⚠️ **DIE GANZE 4-7-8-/BOX-AUSSAGE HÄNGT AM HALTE-MODELL, und diese Grenze
                          fehlte in der ersten Fassung, obwohl sie die tragende ist.**
                          `BreathPattern.sample` gibt über `holdFull`/`holdEmpty` eine FLACHE
                          Amplitude zurück, also genau EIN aufsteigender Nulldurchgang pro Zyklus.
                          Der #435-Eintrag hält das Gegenmodell als mindestens ebenso plausibel und
                          am Gerät UNGEMESSEN fest: ohne Atemantrieb relaxiert der Puls während des
                          Haltens zur Ruhelinie, das ergibt einen ZWEITEN Durchgang pro Zyklus und
                          4-7-8 impliziert ≈6,3/min — mitten im Band, angenommen, konfident
                          veröffentlicht, von Resonanzatmung nicht zu unterscheiden. Unter DIESEM
                          Modell tut #452 nichts und BEIDE Latch-Tests werden rot. Kein Grund, sie
                          abzuschwächen: der Grund, warum ein Gurt-Take das entscheidet und nicht
                          ein drittes Modell.
                          ⛔ **Und NICHT behauptet wird der Fall ÜBER dem Band — die BEGRÜNDUNG der
                          ersten Fassung war dabei falsch.** Sie lautete: die Fixtur (1,0 s ein /
                          0,9 s aus, 31,6/min) erzeuge keinen Verwurf, weil „die Glättung Zyklen
                          verschmilzt". Das beschrieb MEINE TRANSKRIPTION, die `BreathPattern.init`
                          übersprang. Im ausgelieferten Typ klemmt `minActiveSeconds = 1.0` beide
                          Schenkel, dieselbe Konstruktion ist also 1,0/1,0 = **exakt 30,0/min** —
                          unter der Annahme-Decke 31,8 — und **kein Muster aus Ein- und Ausatmung
                          kann überhaupt schneller als 30/min pacen**. Der Fall über dem Band ist
                          nicht „ungemessen durch eine Fixtur, die sich seltsam verhielt", sondern
                          durch diesen Fixtur-Typ UNERREICHBAR. Niemanden auf die Glättung ansetzen.
                          ⚠️ Und die härteste Grenze zuerst, weil sie diesmal für die ganze Scheibe
                          gilt: **KEIN Gate hat diesen Code gesehen** (#451 — die Läufe stehen in
                          der Warteschlange, siehe ⛔ unten). Weder Kompilieren noch Ausführen ist
                          belegt. ⛔ Und meine erste #451-Diagnose nannte als zweiten Beleg einen
                          „seit 17:49 laufenden, 2 h über seinem 40-Minuten-Timeout hängenden"
                          Compile-Check. Nachgeprüft: dieser Lauf ist `cancelled`, und der
                          CI/CD-Lauf desselben Commits (`1a3d8b9`) hat sehr wohl gebaut — er stand
                          nur **1 h 51 min in der Warteschlange** (erstellt 17:49:58, „Build for
                          Testing" **success** 19:44:16, danach „Run Tests" rot = das bekannte
                          founder-gated #396). Zwei verschiedene Zustände, von mir zu einem
                          verschmolzen. ⛔ **UND DIE ZWEITE FASSUNG WAR AUCH FALSCH, und diesmal
                          hat sie den Founder GELD gekostet — nicht in Euro, sondern in einer
                          Frage, die er nie hätte beantworten sollen.** Sie lautete: „repo-WEIT
                          null `push`-Läufe seit 18:33:27Z und null in `queued` … die Signatur
                          einer Actions-Quote/Abrechnungs-Sperre". Daraus wurde eine Bitte an den
                          Founder, Actions-Minuten/Billing zu prüfen; seine Antwort war **„Es
                          sollen keine Kosten entstehen"**. Drei Messungen widerlegen die Diagnose
                          vollständig: (1) das Repository ist **öffentlich** (`search_repositories`:
                          `"private": false`, `"visibility": "public"`) — Standard-Runner sind
                          damit kostenlos, es gibt kein Kontingent zum Ausschöpfen und nichts zu
                          bezahlen; (2) **alle 28 Workflows** stehen auf `state: "active"`, sind
                          also nicht einzeln abgeschaltet; (3) **die Läufe existieren**: `17e1f82`
                          hat vier Läufe, angelegt **21:14:58Z**, alle in `queued`. Der wahre
                          Befund ist eine LATENZ, keine Sperre — die Anlage kam rund eine
                          halbe Stunde nach dem Push, und danach stand der CI/CD-Lauf desselben
                          Tages schon einmal **1 h 51 min** in der Warteschlange, bevor ein
                          macOS-Runner ihn nahm. Warten kostet nichts. **Die Lehre ist nicht die
                          übliche Stale-Zahl-Lehre dieses Absatzes, sondern eine über
                          ESKALATION: ich habe eine Ursache an den Founder gemeldet, ohne die EINE
                          Eigenschaft nachzuschlagen, die sie entscheidet (Sichtbarkeit des
                          Repos) — und die Eskalation hat nach Geld gefragt. Eine Frage an den
                          Founder ist teurer als jede Messung; wer eskaliert, misst vorher.**
                          Der überlebende Teil des Befunds ist schwächer und harmlos: die Gates
                          hatten diesen Code beim Schreiben dieser Zeile noch nicht gesehen, weil
                          sie in der Schlange standen),
                          davor „175"
                          nach `ThePacedRateMustBeReadableTests.swift` (#435 — der erste
                          Wächter in dieser Kette über einem WIDERSPRUCH ZWISCHEN ZWEI EIGENEN
                          TEILEN der App statt über einem falschen Wert in einem: `BreathPattern.curated`
                          pact vier Raten (Resonance 6,0 · Coherent 6,0 · Box 3,75 · 4-7-8 3,1579),
                          und `RespirationEstimator.reportableRange` ist `[3,7736 … 31,8]`. **ZWEI der
                          vier liegen UNTER der Untergrenze** — während der Nutzer der Atemführung der
                          App folgt, kann die Atemmessung der App die verlangte Rate nicht zurücklesen.
                          `BreathGuideView` bietet ausdrücklich einen „treibe den Ball aus deinem
                          GEMESSENEN Atem"-Modus an, der auf `breathRate > 0` schaltet, und
                          `BioStripView` zeigt eine Atem-Zahl.
                          ⛔ **Und die erste Fassung dieses Eintrags begründete das mit zwei Sätzen, die
                          BEIDE falsch sind — beide vom Bio-Reviewer gefunden, beide von mir nachgeprüft.**
                          (1) „der dort nie angehen kann" gilt nur für 4-7-8; für Box schaltet er an
                          etwa fünf von sechs Ruhepulsen sehr wohl an. (2) „`bioNormalized` … die MUSIK
                          hört auf, dem Atem zu folgen" ist doppelt falsch und dieses Repo sagt das an
                          zwei Stellen schon selbst: der einzige Aufrufer ist
                          `RecordController.captureBio` — eine aufgezeichnete Automationsspur, kein
                          lebender Audiopfad —, und `RecordController.onStep` beginnt mit
                          `guard armed else { return }`, während `arm()` NULL Aufrufer in `Sources/` hat
                          (#204, #433). Ich habe genau die Behauptung neu eingetragen, die zwei
                          Retraktionen streichen. Die WIRKLICH lebenden Verbraucher sind
                          `ModulationMatrix` (`.breathRate` hat einen Produzenten, erreicht also den
                          Carrier-Picker der FX-Bio-Modulation), `BioEventPublisher` → Atem-Onsets → OSC
                          `/echoelmusic/bio/breath/*` und der Follow-Modus selbst.
                          ⭐ Die zwei scheitern VERSCHIEDEN, und das ist der Fund, der mehr wert ist als
                          der Boolesche. Modelliert wurde nur der fragliche Mechanismus (die Atemperiode
                          wird zwischen Nulldurchgängen der Herzschlagreihe gelesen, ein Zyklus rastert
                          also auf ganze Schläge, und ein Durchgang überlebt nur, wenn die implizierte
                          Rate im Band landet), gewischt über Puls 45…110: Resonance/Coherent **121 von
                          121** Zweigen angenommen, Mittel 6,0140 (+0,23 %). **Box** liegt 0,62 %
                          darunter und geht NICHT still: 54 von 127 Zweigen kommen durch, Mittel
                          **3,8590 — also +2,91 % ZU HOCH**, und an 12 der 66 Pulse wird gar nichts
                          angenommen, Puls 60 exakt (16-s-Zyklus = genau 16 Schläge, beide
                          Quantisierungen ergeben 3,75). Das ist die #426-Klasse — ein EINSEITIGER
                          Filter am Rand — an einer zweiten Stelle. **4-7-8** liegt 16,3 % darunter:
                          **0 von 131**, stumm an allen 66 Pulsen.
                          ⭐ Deshalb ist die Reparatur weder „Band weiten" (eine Messentscheidung an
                          eine UI-Liste anpassen) noch „Technik ändern" (Box 4-4-4-4 und 4-7-8 sind
                          benannte Praktiken, absichtlich angeboten) — sondern die Tatsache KETTEN und
                          SAGEN: `pacedRateIsReportable` fragt `RespirationEstimator.reportableRange`
                          statt sie zu wiederholen (#416/#426-Form), und `measurementNote` ist DARAUS
                          ABGELEITET statt pro Muster hingeschrieben, damit Text und Arithmetik nicht
                          auseinanderlaufen können.
                          ⚠️ Was der Wächter NICHT behauptet, und das steht als eigener ⛔-Block im
                          Dateikopf: die Sweep-Zahlen sind ein MODELL des Annahmebandes und der
                          Schlag-Quantisierung, nicht `RespirationEstimator` selbst — sie festzunageln
                          hieße mein Modell festnageln statt das Produkt, die teurere Sorte Grün.
                          Behauptet wird nur, was aus den ausgelieferten Typen entscheidbar ist.
                          ⛔ **UND DIE ERSTE FASSUNG LIEFERTE EINE BILDUNTERSCHRIFT AUS, DIE FÜR BOX
                          FALSCH IST — zwanzig Zeilen unter einem Doc-Kommentar desselben Commits, der
                          das Gegenteil sagt.** Sie lautete „Echoel can't read your breath rate at this
                          pace — … the live breath readout won't follow it", versprach also STILLE. Box
                          wird nicht still: es veröffentlicht an etwa fünf von sechs Ruhepulsen und liest
                          ~3 % ZU HOCH. Einer Nutzerin zu sagen, eine LEBENDE Anzeige sei tot, ist die
                          lügendes-Control-Klasse umgekehrt. Die Lehre ist nicht „Text prüfen", sondern:
                          **eine aus einem Booleschen ABGELEITETE Bildunterschrift erbt nur, was der
                          Boolesche weiß** — und dieser weiß „unter dem Band", nicht „still". Die neue
                          Fassung behauptet nur das modellfrei Entscheidbare: die Rate liegt unter dem
                          Band, der Schätzer veröffentlicht nur INNERHALB — also kann die Anzeige diese
                          Rate nie zeigen, sie bleibt leer oder liest zu hoch.
                          ⛔ **Und die Aussage „die Notiz erscheint genau dann, wenn die Rate draußen
                          liegt … wird deshalb NICHT geprüft (#367)" war an VIER Stellen gleichzeitig
                          falsch** (hier, im Dateikopf, im Commit-Text und im Testkopf): die Datei prüft
                          genau das, zweimal, an beiden Bandenden. Beide Reviewer fanden es unabhängig.
                          Die Behauptungen BLEIBEN — ihr Wert ist nicht, dass sie heute scheitern können,
                          sondern dass `measurementNote` eine Bearbeitung davon entfernt ist, ein
                          GESPEICHERTER Text pro Muster zu werden, und sie dann das Einzige sind, was
                          das Auseinanderlaufen bemerkt. Der Dateikopf sagt das jetzt so.
                          ⛔ **Und der Boolesche allein nagelt nichts Unterscheidendes fest:** auf dem
                          ausgelieferten Satz fällt `measurementNote != nil` exakt mit `hasHolds`
                          zusammen, ein `hasHolds ? … : nil` bestand also JEDE Behauptung der Datei.
                          `testTheNoteFollowsTheBandAndNotTheHolds` bricht die Koinzidenz mit zwei
                          synthetischen Mustern, auf denen beide Eigenschaften auseinandergehen.
                          ⚠️ Und die ehrliche Grenze der Türen: BEIDE Flächen,
                          die diesen Picker zeigen, sind heute unerreichbar (`BreathGuideView` nur aus
                          dem türlosen `BioSourceView` (#276), `MeditationView` nur unter
                          `showMeditation`, einem der drei Präsentations-Flags ohne jeden Setzer). Die
                          Zeile ist trotzdem geschrieben, aus demselben Grund wie bei #433/#434: die
                          Arithmetik ist falsch, ob eine Tür existiert oder nicht, und eine später
                          eintreffende Tür darf nicht auf einem stillen Widerspruch aufsetzen.
                          ⛔ **Die ANNAHME, auf der das ganze Modell ruht, stand nirgends: GENAU EIN
                          aufsteigender Nulldurchgang pro Atemzyklus.** Die erste Fassung wischte die
                          Halte-Phasen als Randfrage weg („nichts hier misst das") und nannte den Rest
                          gesichert — dabei sind die Halte-Phasen genau das, was die Annahme bricht.
                          Unter dem Halte-Modell DIESER Datei (Amplitude bleibt stehen) überlebt sie
                          (Box 19 Durchgänge in 300 s gegen 18,75 erwartete, 4-7-8 16 gegen 15,8). Unter
                          dem physiologisch mindestens ebenso plausiblen Modell — kein Atemantrieb
                          während des Haltens, der Puls RELAXIERT also zur Ruhelinie — erzeugt 4-7-8s
                          7-s-Halt einen ZWEITEN Durchgang pro Zyklus, und der Schätzer veröffentlicht
                          konfident ≈6,3/min: fast exakt das Doppelte der gepacten 3,158, mitten im
                          Band, von Resonanzatmung nicht zu unterscheiden. Robust über Relaxations-
                          Zeitkonstanten 1–5 s. Die plausible Fehlfunktion ist also eine ERFUNDENE
                          IN-BAND-RATE — schlimmer als die Stille, vor der die Notiz warnt, und die
                          Klasse, die dieses Repo mit #424 und #426 schon zweimal bezahlt hat. Keines
                          der beiden Halte-Modelle ist am Gerät gemessen; das entscheidet ein Gurt-Take,
                          kein drittes Modell.
                          ⚠️ **Nebenbefund derselben Runde, und er sitzt auf einer SICHERHEITS-Doku:**
                          `BreathPacer.minRate = 5.0` trug den Satz „we do not push below it so the
                          guide can never drive an unsafely slow pace" — während der ausgelieferte
                          Satz Box mit 3,75 und 4-7-8 mit 3,158 pact und die Konstante nichts klemmt
                          (einziger Leser: `ResonanceFinder`s Sweep; `defaultRate` hat null Leser).
                          `RecordAnchor` hielt „constrain NOTHING" längst fest, nur hatte niemand das
                          mit der SICHERHEITS-Formulierung auf der Konstante selbst abgeglichen.
                          Korrigiert am Ort: sicher ist der Führer durch die PRO-SEGMENT-Klemmung in
                          `BreathPattern.init` plus das Halte-Einverständnis — ein langsamer ZYKLUS aus
                          sanften Segmenten ist nicht die Gefahr, ein langer Einzelatemzug oder ein
                          langer Halt wäre es, und die sind gedeckelt. Ob der kuratierte Satz überhaupt
                          einen Raten-Boden haben soll, ist eine Founder-Frage (#450)),
                          davor „174"
                          nach `TheGapClimbCannotChangeTheResumeTests.swift` (#444 — der erste
                          Wächter in dieser Kette über einer REGISTRIERTEN REPARATUR, die sich beim
                          Nachrechnen als NO-OP herausstellte. Der #434-Dateikopf hielt ein Artefakt fest
                          („eine periodisch flackernde Quelle erzeugt ein glattes Dreieck statt einer
                          abklingenden Hülle") UND benannte seine Ursache samt Reparatur („`up` darf
                          während einer offenen Lücke weiterklettern … Freezen von `up` außerhalb des
                          Gnadenfensters ist die Kandidaten-Reparatur"). **Das Artefakt ist echt, die
                          Ursache nicht** — Freezen ändert auf KEINER Eingabe irgendetwas. Der Beweis
                          sind drei Zeilen: ein Neustart verlangt `now − lastMeasuredAt > graceSeconds`
                          und `graceSeconds == horizon/2`; `runStartedAt` wird nur an einer Messung
                          VORGERÜCKT, und seine einzige andere Zuweisung — der Rückwärtsuhr-Reset
                          `self = BreathHold()` — setzt es GEMEINSAM mit `lastMeasuredAt` auf −∞, also
                          gilt `runStartedAt ≤ lastMeasuredAt` in beiden Fällen; damit ist bei JEDEM
                          Neustart `elapsed > half` und folglich `up > 1`, der `min` nimmt also immer
                          `down`. Das Freezen setzt `elapsed ≥ half`, also wieder `up ≥ 1` — DERSELBE
                          Zweig. (⚠️ „bei JEDEM Neustart" ist in GENAU EINEM Fall leer statt wahr, und
                          die erste Fassung behauptete es dort als wahr: bei der ERSTEN Messung ist
                          `horizon` noch 0, `weight(at:)` kehrt an seinem `horizon > 0`-Wächter um und
                          `up` entsteht gar nicht. Die Folgerung ist dort STÄRKER, nicht schwächer.)
                          Gemessen zusätzlich zum Argument, weil eine Algebra-Behauptung über
                          ausgelieferten Code auch nur eine Behauptung ist: 6 000 zufällige Verläufe
                          ergaben **61 769 Neustarts** und der größte Unterschied zur gefreezten Variante
                          über alle Abtastwerte aller Verläufe war **exakt 0**; eine unabhängige
                          gegnerische Wiederholung fand 102 921 Neustarts und ebenfalls 0.
                          ⛔ Beide Läufe meldeten außerdem „kleinstes `up` an einem Neustart" (1,000224
                          bzw. 1,0000009939619714), und die erste Fassung zitierte die erste Zahl hier
                          wie eine MARGE. Sie ist keine Eigenschaft des Codes, sondern eine des
                          Zufallsgenerators: die Neustart-Bedingung ist eine STRIKTE Ungleichung, das
                          Infimum von `up` an einem Neustart ist also exakt 1 und wird nie angenommen —
                          ein dichterer Sweep meldet für immer eine kleinere Zahl. Tragend ist das
                          Theorem, nicht die Ziffer. ⚠️ Und die Abdeckung heißt jetzt, was sie ist:
                          `BioSource.freshnessWindow` deklariert VIER verschiedene Werte über sechs Fälle
                          (6 s · 90 s · 600 s für `.oura` · 5 s); gewischt wurden die drei mit einem
                          Produzenten in `Sources/`. `half` kürzt sich aus dem Vergleich heraus, der
                          ungewischte Wert ist also eine Abdeckungs-Notiz und kein Loch im Beweis.
                          ⭐ Das Dreieck ist ANSTIEGSRATE == ABKLINGRATE, und das hat in dieser Datei
                          nie jemand entschieden: `down` fällt mit `1/half`, `up` steigt mit
                          `elapsed/half` — also mit derselben Rate, allein weil `up` denselben Teiler
                          wiederverwendet. Der Dateikopf leitet die TEILUNG her (Gnadenfrist = Release =
                          horizon/2, gekettet an das Frische-Fenster der Quelle); die ANSTIEGSRATE leitet
                          er nirgends her — sie ist Nebenwirkung der Konstante, die für die Ablauf-Seite
                          gewählt wurde. Die teure Folge ist nicht das Flackern, sondern das Handgelenk:
                          90 s Horizont heißt 45 s Anstieg, eine HealthKit-Messung verbringt also ihr
                          ganzes nutzbares Leben mit Steigen und Fallen (Mittel **0,4712** — das ist die 0,5-s-Abtastung über 0…95 s, also mit zehn Nach-Ablauf-Nullen; rasterfrei ist der Mittelwert exakt **1/2**, siehe die Doppel-Rücknahme im #448-Eintrag oben —, Vollgewicht
                          für EINEN Augenblick). ⛔ Damit ist auch die Zeile im #434-Kopf korrigiert, die
                          „volles Gewicht für 45 s" behauptete — es ist ein Dreieck, kein Plateau; die
                          Regressions-Aussage gegen die alte 2-s/4-s-Paarung überlebt trotzdem. Die
                          Entkopplung ist eine eigene Scheibe. Die naheliegende Variante — eine
                          abklingende Hülle, bei der eine ständig ausfallende Quelle weniger Vertrauen
                          verdient — ist ABGELEHNT, nicht bloß vertagt: der Bus traut dem Frame weiter,
                          ihren Einfluss zu senken erfindet also ein Misstrauen, das nichts gemessen hat
                          (die #433-Begründung), und auf einer aufgezeichneten Spur ist das Ergebnis von
                          einem wirklich unregelmäßiger atmenden Körper nicht zu unterscheiden;
                          `testTheRampRateDoesNotRememberEarlierDropouts`
                          ist das Gegengewicht, das daraus einen roten Test macht statt einer Nebenwirkung.
                          ⛔ **Und der Formtest KONNTE seine wichtigste Behauptung in der ersten
                          Fassung nicht scheitern lassen — #367 in seiner leisesten Form.** Der Trog
                          wurde als `weights.min()` über die GANZE Spur genommen, und `t = 0` ist per
                          KALTSTART-Konstruktion 0 (die erste Messung nimmt den Neustart-Zweig, während
                          `horizon` noch 0 ist, `weight(at:)` kehrt am eigenen Wächter um). Dieser eine
                          Abtastwert nagelte das Minimum für immer auf 0, während die Fehlermeldung
                          „eine Lücke länger als das Frische-Fenster muss die gehaltene Rate vollständig
                          zurückziehen" behauptete. Der Reviewer hat es bewiesen, indem er `down` bei
                          0,2 abfing — genau der beschriebene Defekt — und der Test blieb GRÜN; rot
                          wurde nur die Flankensteilheit, also eine ANDERE Behauptung. Nicht „ein
                          Wächter, der nicht scheitern kann", sondern **einer, der nicht aus seinem
                          GENANNTEN Grund scheitern kann.** Der Trog wird jetzt ab `t ≥ horizon`
                          gemessen.
                          ⚠️ Welcher der drei Tests überhaupt scheitern KANN, steht im Dateikopf: nur der
                          gewischte Stetigkeitstest (160 Wiederaufnahme-Punkte, die SWEPT-Form des
                          Ein-Punkt-Tests aus #434 — keine zweite Kopie einer lebenden Behauptung (#416),
                          sondern die Verallgemeinerung, weil der Fehler, gegen den sie steht, ein
                          REFACTOR der Resume-Regel ist, den ein einzelner handgewählter Punkt übersteht)
                          und der Dreiecks-Formtest. Der dritte ist heute grün und soll es sein.
                          ⭐ Die LEHRE ist mehr wert als das Artefakt und ist die schärfste Fassung von
                          #167: **eine registrierte Folgearbeit mit BENANNTER Ursache ist die teuerste
                          Sorte falscher Notiz in diesem Repo.** Die nächste Sitzung kann ihr nicht
                          widersprechen — sie setzt sie um, misst nichts, und liefert einen Diff ab, der
                          wie eine Reparatur aussieht), davor „173"
                          nach `TheBreathTermFadesInsteadOfSteppingTests.swift` (#434 — der
                          erste Wächter in dieser Kette über einem Defekt, den die VORIGE Scheibe
                          bewusst gekauft hatte: #433 hörte auf, einen UNGEMESSENEN Atem als Ruhe
                          einzumischen, und schrieb den Preis in die eigene Doku statt ihn zu
                          verstecken — der Wert der Bio-Automationsspur SPRINGT seither um |hr − br|/2,
                          sobald eine Messung erscheint oder verschwindet. Bei 120 bpm über der
                          gepacten 6/min-Resonanzrate sind das **0,4286**, also 43 % des Spurbereichs.
                          ⛔ Und ausgerechnet DIESE Zahl trug die erste Fassung an vier Stellen als
                          „schlimmster Fall, genau an der Rate, auf die das Produkt zielt" — beides
                          falsch. Das Maximum von |hr − br|/2 ist **0,5** (50 bpm mit ≥24/min oder
                          120 bpm mit ≤3/min), und die Paarung 120/6 ist untypisch: 120 bpm kommt
                          normal mit 18–24/min (Sprung 0,143 → 0,000), gepactes Atmen mit 55–75 bpm
                          (0,036–0,107). 0,4286 ist die Zahl, GEGEN die gemessen wird, nicht die, die
                          ein Körper meistens erzeugt.
                          ⭐ Die Reparatur ist HALTEN, nicht GLÄTTEN, und der Unterschied ist die
                          ganze Begründung: eine Tiefpass-Glättung des Ausgangs erfände Erregungswerte,
                          die kein Körper erzeugt hat. Gehalten wird die letzte GEMESSENE Rate,
                          ausgeblendet nur ihr EINFLUSS — `hr + w·(br − hr)/2` ist eine Konvexkombination
                          mit Gewichten `((2−w)/2, w/2)`, der Ausgang bleibt also zu jedem Zeitpunkt
                          innerhalb der konvexen Hülle von `{hr, (hr+br)/2}`. Ein Ratenbegrenzer auf
                          dem Ausgang hat diese Eigenschaft NICHT: während seiner Rampe gibt er einen
                          Wert aus, den kein `(hr, br)`-Paar erzeugt — auf einer AUFGEZEICHNETEN Spur
                          ist der von einer Messung nicht zu unterscheiden. Diese Formulierung stammt
                          vom Reviewer und ist schärfer als die der ersten Fassung.
                          ⛔ **UND DIE ERSTE FASSUNG WAR AUF IHREM HAUPTFALL EIN NO-OP, mit acht
                          grünen Tests.** Das Gewicht wurde auf `frame.timestamp` gelesen — und ein
                          Frame-Stempel STEHT STILL, genau wenn die Ausblendung gebraucht wird:
                          `CameraRPPGBioPublisher` wiederholt beim Puls-Halten ausdrücklich mit
                          `held.timestamp` (sein eigener Kommentar sagt, dass Verbraucher, die darauf
                          deduplizieren, einen No-op sehen) und `breathRate: 0`, während
                          `EngineBus.usableBio()` diesen eingefrorenen Frame gegen die WANDUHR am Leben
                          hält. Das Gewicht blieb also für die ganze Haltezeit auf 1 und fiel danach in
                          EINEM Spur-Sample auf 0 — der volle Sprung, unverändert. **Kein einziger der
                          acht Verhaltenstests konnte das sehen, weil alle die Zeit synthetisch
                          vorwärts trugen.** Lehre: **zwei Uhren in einem Signalpfad sind kein Detail,
                          und ein Test, der beide aus derselben Variable speist, prüft keine von
                          beiden.** `testTheFadeIsReadOnTheReadingClock` ist die Regression.
                          ⛔ **Zweiter Selbstfund, von BEIDEN Reviewern unabhängig gemeldet: der
                          Kaltstart sprang.** Die erste Fassung nahm die allererste Messung von der
                          Rampe aus (`… : 1`) mit dem Argument, eine Rampe brauche einen Vorgängerwert,
                          mit dem sie stetig sein könne. Auf SPUR-Ebene gibt es den: `usableBio()`
                          filtert auf Frische, nicht auf Atem, also schreibt ein Take erst
                          Herz-allein-Werte (rPPG braucht ~19 s bis zum Lock, #415) — und der Atem kam
                          dann als voller 0,4286-Sprung. Gemessen, acht Herz-Frames dann Atem bei 1 Hz:
                          **0,4286** mit der Ausnahme, **0,1429** ohne sie. Der Beleg, der die Ausnahme
                          gerechtfertigt hatte, kam aus einer Fixtur, deren Array BEIM ERSTEN GEMESSENEN
                          FRAME BEGANN — sie konnte die eigenen Kosten nicht sehen.
                          ⭐ Die zwei Konstanten sind jetzt EINE Kettung, und beide alten Werte waren
                          auf verschiedene Weise falsch. „2 s Gnadenfrist absorbiert zwei ausgefallene
                          Frames" war schlicht Arithmetik, die das Hinschreiben nicht überlebt: zwei
                          ausgefallene Frames bei ~1 Hz sind eine **3-s**-Lücke, und die Abbruchprüfung
                          ist `Lücke > Gnadenfrist`. Und die 4 s waren gegen ein „10-s-Analysefenster"
                          hergeleitet, **das es für den Atem nicht gibt** — die einzige 10 in der Kette
                          ist der PULS-Peakdetektor in `CameraAnalyzer.detectPeaks`;
                          `RespirationEstimator` ist rekursiv und seine Gültigkeitsregel ist
                          perioden-SKALIERT. Der Horizont ist jetzt das Frische-Fenster der QUELLE
                          selbst (`BioSource.freshnessWindow`), halbiert: volles Gewicht in der ersten
                          Hälfte, lineare Ausblendung über die zweite. Damit trägt EINE Invariante beide
                          Enden — **der Einfluss des Atem-Terms erlischt genau dann, wenn der Bus dem
                          Frame nicht mehr traut, aus dem er stammt** — und es ist eine echte Kettung an
                          eine Konstante, die diese Frage schon entscheidet (#426s Form). Kamera/BLE
                          (6 s) → 3 s + 3 s, HealthKit/Watch (90 s) → 45 s + 45 s.
                          ⭐ Und das behebt eine REGRESSION, die niemand gesucht hatte:
                          `HealthKitBioPublisher` liefert eine echte Atemrate, einmal pro neuer Messung,
                          Minuten auseinander, in einem 90-s-Fenster. Unter den festen 2 s + 4 s kam eine
                          Handgelenks-Atemrate für ~83 ihrer 90 nutzbaren Sekunden mit Gewicht 0 an —
                          still abgeschaltet, genau die „lügendes Control"-Klasse. Der Preis der
                          Kettung ist ehrlich zu nennen: die Kamera-Ausblendung dauert 3 s statt 4, der
                          Schritt pro Frame ist damit 1/3 statt 1/4 des Sprungs (0,1429 statt 0,1071).
                          ⚠️ Was er NICHT kann, und das steht als ERSTES im Dateikopf: zeigen, dass
                          irgendetwas davon HÖRBAR oder AUFGEZEICHNET wird. `RecordController.onStep`
                          beginnt mit `guard armed else { return }`, `arm()` hat NULL Aufrufer in
                          `Sources/`, #204 hält den Controller als türlos fest. Repariert WIRD er
                          deshalb, nicht trotzdem. ⚠️ Und ein Artefakt ist gemessen und NICHT behoben:
                          eine PERIODISCH flackernde Quelle erzeugt ein glattes Dreieck statt einer
                          abklingenden Hülle — eine Schwingung im Atemband, auf einer aufgezeichneten
                          Spur schwerer als Fehler zu erkennen als die Rechteckform, die sie ersetzt.
                          Eigene Scheibe, keine Mitnahme. ⛔ **Und die URSACHE, die dieser Eintrag hier
                          und der #434-Dateikopf gleichlautend dazu benannten — „`up` darf während einer
                          offenen Lücke weiterklettern, DAHER das Dreieck" —, ist mit #444 widerlegt:
                          `up` ist bei jedem Neustart schon > 1, der `min` nimmt also immer `down`, und
                          die vorgeschlagene Reparatur ist ein No-op** (Beweis + Messung im
                          #444-Eintrag oben). Das Artefakt bleibt, die Kausalkette ist gestrichen),
                          davor „172" nach `EveryReachableRowStatesItsGridTests.swift` (#440 — der erste
                          Wächter in dieser Kette, dessen wichtigste Behauptung eine ERLAUBNIS ist und
                          kein Verbot, und der deshalb den Abschluss der #427/#430-Familie bildet statt
                          ihre Fortsetzung: nachdem #427 sechs Visual-Zeilen und #430 einundzwanzig
                          Sound-Zeilen vom 4er-Default geholt haben, ist die interessante Frage nicht
                          mehr „welche Zeile ist falsch", sondern „welche darf bleiben, und warum".
                          Gemessen (paren-gematcht über `Sources/`, Kommentarzeilen entfernt — `git
                          grep -c` zählt ZEILEN und nicht STELLEN, die #431-Falle): **62 Aufrufstellen,
                          davon vier ohne eigenes `decimals:`**. Zwei sind repariert, zwei stehen
                          begründet auf der Erlaubnisliste.
                          ⭐ Die zwei reparierten sind ungleich, und die zweite ist die schwerere.
                          Die FX-Bio-Mod-Zeile „LFO rate" (0,05…8 Hz) war eine reine Inkonsistenz —
                          die ANDERE Zeile desselben Namens (Patch-Filter-LFO, 0…20 Hz) steht seit
                          jeher auf 2, der ausgelieferte Default `lfoRateHz` = 0,5 (`FXModRoute.init`) liegt
                          exakt auf diesem Raster und beide Grenzen auch. Die KAMMERTON-Zeile
                          (`WorkspaceView`, 380…500 Hz) war etwas anderes: der Kopf ihres eigenen
                          Kommentarblocks verspricht „exact to 0.01 Hz", während `decimals` das SNAP-
                          RASTER ist (#430) und die Zeile auf der Vorgabe 0,0001 Hz anbot. Das
                          Founder-Video vom 2026-08-02, im selben Kommentar zitiert, zeigt `483,4352`
                          auf dem Schirm — vier Stellen ließen ein versehentliches Scrollen wie eine
                          Einstellung aussehen. Der Wert ist PERSISTIERT und stimmt jede Stimme.
                          ⚠️ Und er KOSTET: ein gespeichertes 442,3456 rastert beim ersten Antippen
                          auf 442,35, also 0,0197 Cent — rund 250× unter der ~5-Cent-Unterschieds-
                          schwelle, damit unhörbar, aber ein SCHREIBVORGANG auf einem persistierten
                          Wert, und als solcher neben der Zeile benannt statt durchgewunken.
                          ⛔ **Und dieselbe Prüfung hat den #427-Eintrag in DIESER Datei widerlegt** —
                          er zählte Kammerton und gesperrtes Tempo als die zwei, die „beide sagen
                          „editable to 0.0001" im eigenen Kommentar". Nur `BodyTempoField` sagt das;
                          die A4-Zeile sagte immer 0,01. Der #427-Eintrag oben trägt die Korrektur mit
                          der Lehre: eine Behauptung über ZWEI Dinge wird geprüft, indem man BEIDE
                          nachschlägt.
                          ⭐ Das eigentliche Stück Arbeit ist deshalb der GEGENGEWICHTS-Test. Der
                          aufgeräumt aussehende nächste Schritt ist ein Durchgang, der ALLE
                          verbliebenen Stellen auf 2 setzt — und der würde still das eine Bedienelement
                          vergröbern, mit dem ein Performer auf eine externe Uhr zieht (gesperrtes
                          Tempo, `toggleLock` rundet auf 1e-4 und persistiert). Die Erlaubnisliste
                          nennt beide Ausnahmen samt Grund (`BodyTempoField` absichtlich,
                          `PianoRollView`s „Vel" unerreichbar seit #178) und prüft AUCH die
                          Gegenrichtung: ein Eintrag, dessen Zeile es nicht mehr gibt, ist ein
                          veralteter Freibrief und wird rot. Als Nebenwirkung fiel dabei
                          `BodyTempoField`s Kommentar „…, like Kammerton" — die Gleichsetzung war nur
                          zufällig wahr, weil BEIDE Zeilen still die 4 erbten.
                          ⚠️ Was er NICHT kann, und das steht im Dateikopf: keine seiner Behauptungen
                          ist ein Lauf. Vier sind Quelltext-Scans, einer ist Arithmetik auf
                          `ScrubPrecision.gridded`; dass eine Zeile RENDERT, dass ein Finger über sie
                          reist und dass 2 Stellen sich für einen LFO richtig ANFÜHLEN, ist eine
                          Geräteprobe. **Und er hatte eine benannte Blindstelle — sie ist mit #443
                          GESCHLOSSEN, im selben Wächter:** der Scan sieht `EchoelValueField(`-Aufruf-
                          stellen, also auch die INNERHALB der drei weiterreichenden Helfer.
                          `param`/`knob` waren sicher, weil #430 ihr `decimals` ausdrücklich PFLICHT
                          gelassen hat; `EchoelFXView.field` hatte `decimals: Int = 2`, und seine 43
                          Aufrufstellen (33 davon still) waren dem Scan unsichtbar. #443 nimmt den
                          Default weg und schreibt die Zahl an allen 33 hin, plus zwei Hälften in
                          `EveryReachableRowStatesItsGridTests`: ein eigener paren-gematchter Scan über
                          `field(` und eine Behauptung auf der DEKLARATION, dass `decimals` keinen
                          Default hat. ⚠️ Ehrlich zum Umfang: die 33 Zeilen waren alle KORREKT bei 2.
                          Die INVARIANTE — der Teil, der sich beim Umzählen nicht bewegt — lautet: kein
                          ausgelieferter Wert liegt neben dem Raster SEINER EIGENEN Zeile, weder eines
                          der 86 Bereichsenden noch eine Zuweisung an diese 43 Parameter in
                          `EchoelFXChain`, `FXCuratedLibrary` oder `GenreFX`.
                          ⛔ **Und die Zahl, die das belegen sollte, ist ZWEIMAL gestorben — die zweite
                          ist die lehrreiche.** Erste Fassung „63 ausgelieferte Zuweisungen"
                          (nicht reproduzierbar); ich ersetzte sie durch „316" und erklärte die Lehre für
                          gezogen; der Reviewer leitete unabhängig 424 her, mein eigener Neulauf unter
                          angegebener Zerlegung 320. Alle drei sind sich über NULL daneben einig. Der
                          Defekt ist weder die Ziffer noch die fehlende Dateiliste, sondern dass
                          „Zuweisung" drei syntaktische FORMEN umspannt (Punkt-Zuweisung, gespeicherter
                          Default, benanntes Argument) — die Summe ist also gar keine Messung. Deshalb
                          eine Invariante und keine Gesamtzahl. **Die schärfere Lehre als die übliche
                          Stale-Zahl-Lehre dieses Absatzes: eine Zahl mit genannter Datei-Liste kann
                          IMMER NOCH unreproduzierbar sein, wenn die FORM des Gezählten offen bleibt.**
                          ⚠️ „Auf dem Raster" heißt WIE GESCHRIEBEN: nach dem `Float`-Umlauf sind 11 der
                          86 Bereichsenden nicht bitgenau (0,95 → Δ 1,19e-08 in fünf Zeilen, 0,1 →
                          Δ 1,49e-09), also 6 über der 1e-9-Toleranz, die der Nachbartest in derselben
                          Datei benutzt — folgenlos, weil `snapped` klemmt und dann rastert, aber genau
                          die Formulierung, die dieser Nachbartest schon einmal als „bit-for-bit"
                          zurücknehmen musste. Die Scheibe entfernt den MECHANISMUS, keinen Defekt; was sie
                          kauft, ist die NÄCHSTE Zeile, in einem Fenster, das schon eine
                          `Cutoff`-Zeile über 80…18000 Hz mit `decimals: 0` ausliefert. **Die Lehre ist
                          die von #430 in ihrer schärfsten Form: ein Argument, das keine Aufrufstelle
                          schreibt, taucht in keinem Diff auf — und ein Scan über die Blätter sieht den
                          Ast nicht, an dem sie hängen.**),
                          davor „171" nach `TheShownNumberIsTheKeptNumberTests.swift` (#432 — der erste
                          Wächter in dieser Kette über zwei RUNDUNGSREGELN für dieselbe Zahl, und der
                          Abschluss der #135/#416/#427/#431-Familie: das eine Parameter-Bedienelement
                          rundete, was es ZEIGT, anders als das, was es BEHÄLT. Behalten läuft über
                          `.rounded()` (half-away-from-zero), Zeigen über `EchoelDecimalText.string` →
                          `String(format: "%.Nf", …)`, also C-`printf` (half-to-EVEN auf dem exakten
                          Binärwert). Sie stimmen überall überein außer an einem exakten dyadischen
                          Gleichstand — und dort genau zur HÄLFTE, nämlich wenn der gerade Nachbar der
                          UNTERE ist: gemessen **30 von 60** bei jeder der fünf benutzten Stellenzahlen
                          (0,125 las „0,12" und schrieb 0,13; 0,25 las „0,2" und schrieb 0,3; 0,5 las
                          „0" und schrieb 1).
                          ⭐ Und die Reichweite ist kein Sonderfall: auf der Spanne der Cutoff-Zeile
                          allein weichen **8990 der 17980 Halbzahlen in 20…18000** ab, also jede
                          zweite. Erreichbar ist ein Gleichstand nur für einen Wert, den noch nichts
                          gerastert hat — und das ist die interessante Menge: ein ausgeliefertes
                          Patch-Literal, ein von Bio oder „Describe it" geschriebener Wert, oder eine
                          ABGELEITETE Bindung wie `EchoelStudioView.visualEnergy`, deren Getter aus
                          zwei anderen Werten neu rechnet und konstruktionsbedingt neben dem Raster
                          landet (#427 maß dort 62 von 101 Positionen).
                          ⭐ Die Reparatur ist EINE Regel pro Bedienelement, keine neue: `ScrubPrecision.gridded`
                          ist der Rasterschritt aus `snapped` herausgehoben, beide Anzeigen
                          (`EchoelValueField.numberString`, `EchoelNumberPad.fmt`) formatieren jetzt den
                          GERASTERTEN Wert, `snapped` ist darüber neu definiert und die private
                          Zweitkopie derselben Arithmetik im Tastenfeld ist weg — eine Definition statt
                          drei (#416). ⚠️ Gerastert wird, GEKLEMMT nicht: Rastern bewegt eine Zahl um
                          weniger als eine halbe Stufe, Klemmen um beliebig viel. Eine Anzeige, die
                          klemmt, behauptet einen Wert innerhalb eines Bereichs, in dem er nicht liegt
                          — die schlechtere Lüge.
                          ⚠️ Was er NICHT kann: `numberString` und `fmt` sind beide `private` in
                          SwiftUI-Views, also hält die KOPPLUNG allein der Quelltext-Scan; zwei der
                          fünf Tests sind seit der Neudefinition von `snapped` fast tautologisch und
                          sagen das im Dateikopf. Die eigentliche Regression ist
                          `testTheOldFormatterDisagreedWithTheCommit`, das die gemessene Hälfte
                          festnagelt und rot wird, sobald jemand `gridded` „zur Konsistenz mit printf"
                          auf half-to-even umstellt.
                          ⛔ **Und die erste Fassung dieser Scheibe hielt einen Modellfehler für einen
                          Befund und hat daraufhin die eigene Beweislast VERKLEINERT.** Ein
                          Python-Modell meldete 64 Abweichungen auf gewöhnlichen Nicht-Gleichständen,
                          alle der Form „-0" → „0" bei `decimals: 0` — wäre das echt, träfe es sechs
                          ausgelieferte Zeilen (Transpose ±12/±24, Detune, Trim −48…0, Pan −1…1). Es
                          war ein Fehler des MODELLS (ein naives `floor(x + 0.5)`), nicht des Codes:
                          Swifts `.rounded()` ist `toNearestOrAwayFromZero`, also IEEE-754
                          `roundToIntegralTiesAway`, und das ERHÄLT das Vorzeichen der Null. Meine
                          Antwort darauf war, den No-op-Sweep auf nichtnegative Werte zu begrenzen und
                          das ehrlich hinzuschreiben — und genau das ist die schwächere Aussage im
                          Gewand der stärkeren: „sicher für jede Anzeige der App" kann sich nicht auf
                          einen Sweep stützen, der die halbe ausgelieferte Domäne auslässt. Der Sweep
                          deckt die negativen Bereiche jetzt mit ab, auf der IEEE-Regel statt auf
                          einem Modell (Reviewer-Gegenprobe: 120 000 Werte, null Abweichungen).
                          ⚠️ Das Versprechen des Titels gilt NUR für die RUNDUNG, nicht für die
                          Klemme: `999` in eine 0…1-Zeile getippt zeigt `999` in der 30-pt-Anzeige und
                          schreibt `1,00` fest — ein viel größerer sichtbarer Unterschied als jeder
                          Gleichstand, absichtlich erhalten, weil ein Bereichs-PRÄFIX die normale
                          Mitte einer gültigen Eingabe ist (#431). ⚠️ Und die Prosa der Datei war an
                          einer Stelle falsch, wo nichts rot wird: sie sagte „die fünf
                          Stellenzahlen" und zählte VIER auf, wobei „2 quer durch FX" konkret falsch
                          ist — sechs Dynamik-Zeilen des FX-Fensters stehen auf 1), davor „170"
                          nach `SoundRowsCanReachTheShippedPatchesTests.swift` (#430 — der
                          erste Wächter in dieser Kette, der eine RASTERWEITE an den DATENBESTAND
                          kettet statt an eine Regel: `EchoelValueField.decimals` ist nicht die
                          Anzeige sondern das SNAP-RASTER (`ScrubPrecision.snapped`), und die zwei
                          Helfer `param`/`knob` reichten es nicht durch — SIEBZEHN Zeilen des
                          Sound-Panels erbten damit die Vorgabe 4, plus VIER weitere direkte Zeilen
                          derselben Fläche (Swell ↔ Strike, Sub level/presence/heat). Einundzwanzig
                          Zeilen zeigten „0.5000" und „2400.0000 Hz", während jeder FX-Parameter,
                          der Master-Pegel und die Wetter-Mischer auf 2 stehen — auf der Fläche
                          hinter dem Sound-Chip, also der, die Ship-Gate 2 („Kontrolle") meint.
                          ⭐ Der Punkt ist NICHT „überall 2", und genau das unterscheidet diese
                          Scheibe von #427/#354 A: DREI Zeilen müssen abweichen, und WELCHE wurde
                          aus dem ausgelieferten Bestand GEMESSEN, nicht gewählt. `attack` liefert
                          0,002/0,003/0,004/0,005/0,008 s und `noiseLevel` 0,006
                          (`SynthPatch.swift:424`) UND 0,008 (`GenrePatches.swift:228`) — ein
                          Zweier-Raster lässt VIER Anschläge auf null zusammenfallen (0,005
                          eingeschlossen, weil `Float(0,005)` = 0,004999999888 unter der halben
                          Stufe liegt) und bildet beide Rauschböden auf dieselbe 0,01 ab, also je
                          3 Stellen. `filterCutoff` spannt 20…18000 Hz und ALLE 44 ausgelieferten
                          Werte (160…8000) sind ganzzahlig, also 0 — was die drei ANDEREN
                          Cutoff-Zeilen der App (`EchoelFXView:480`, `EchoelStudioView:2474` und
                          `:2502`) längst sagen.
                          ⛔ **Und die erste Fassung dieser Scheibe behauptete „0 daneben,
                          gemessen" über 496 Literale — falsch, und die Ursache ist eine METHODE,
                          keine Zahl.** Die 496 deckten nur `SynthPatch.swift` und
                          `PatchLibrary.swift`; die dritte GENANNTE Quelle, `MusicStyle.synthPatch`,
                          war dem Scan zweifach unsichtbar — `GenrePatches.patch(...)` reicht jedes
                          Feld unter einem ANDEREN Argumentnamen durch (`d:`, `bright:`,
                          `revDecay:`) und BERECHNET zwei davon (`GenrePatches.swift:363-364`).
                          Neu gemessen mit paren-gematchtem Parser über alle 34 `patch(`-Aufrufe
                          UND mit den `SynthPatch.init`-Vorgaben für jedes ausgelassene Feld: **78
                          Patches, 1326 Wert/Zeile-Paare**. Derselbe Defekt wie bei der
                          #431-Zählung — die Methode in einem Satz ist auch eine Behauptung.
                          ⭐ Was die ehrliche Messung fand: **EIN** ausgelieferter Wert lag
                          außerhalb seiner Zeile (`Drone Bed` `d: 6.0` gegen eine Decay-Zeile 0…5;
                          `snapped` klemmt VOR dem Runden, ein Antippen hätte 6,0 s als 5,0 s
                          zurückgeschrieben) — behoben durch WEITEN auf 0…10, nie durch Runden des
                          Patches, die #424-Lehre auf einem anderen Pfad. **65** Werte liegen
                          neben dem Raster und ALLE 65 sind BERECHNET (32 Helligkeiten, 33
                          Obertonpegel, alle aus dem Genre-Lift); sie sind von der
                          Exaktheits-Forderung ausgenommen — nach QUELLE und FELD, nicht nach
                          Zeile, weil dieselben zwei Felder in Werksbank und Bibliothek
                          handgeschrieben sind. Alle **1260** AUTORIERTEN Wert/Zeile-Paare (991
                          Literale + 269 `SynthPatch.init`-Vorgaben) sind exakt auf dem Raster
                          ihrer Zeile; das ist der Anspruch, der Attacks 0,002…0,008 s und die
                          zwei Rauschböden schützt.
                          ⛔ **Und diese Zeile stand einen Commit lang auf „1261 AUTORIERTE
                          Literale" — zweifach falsch, ausgerechnet in dem Satz, der die Grenze
                          zwischen autoriert und berechnet ZIEHT.** 1261 ist die ON-GRID-Zahl
                          (1326 − 65), nicht die autorierte (1326 − 66): der eine Überschuss ist
                          `Berlin Seq`, dessen `bright: 0.40` auf exakt 0,43 gehoben wird und rein
                          zufällig auf dem Raster landet. Und „Literale" war die zweite Hälfte:
                          269 der 1260 Werte hat nie jemand geschrieben, sie kommen aus den
                          `init`-Vorgaben. Dieselbe Klasse wie die 496, die sie ersetzt hat.
                          ⚠️ **Nachlese-Befund, der eine Behauptung des ersten Commits
                          zurücknimmt:** dessen Text sagte „der einzige andere Schreiber
                          (`applyArticulation`) bleibt in 0,25…1,25". Falsch —
                          `SoundPrompt.clamp` (`DSP/SoundPrompt.swift`) ist ein zweiter, aus
                          DERSELBEN Fläche erreichbarer Schreiber („Describe it") und klemmte
                          `decay` auf 0…5: jeder erkannte Beschreibungs-Begriff schrieb `Drone
                          Bed`s 6,0 s als 5,0 zurück, also der gerade behobene Defekt eine
                          Bedienung weiter. Umgekehrt klemmte `reverbDecay` dort auf 0…12, während
                          seine Zeile 0…10 spannt — der Prompt konnte einen Wert erzeugen, den die
                          Zeile beim ersten Antippen wieder einfängt. Beide Grenzen ziehen jetzt
                          mit der Zeile; die verbleibenden Abweichungen (`attack`-Boden 0,001,
                          `filterLFORate` 0…12 gegen Zeile 0…20) sind gemessen folgenlos und
                          stehen als solche im Quellkommentar. **Zwei Definitionen EINES Bereichs
                          bleiben die #416-Bedingung** — sie wirklich single-zu-sourcen ist
                          registriert, nicht getan.
                          ⛔ **Der Wächter hatte außerdem einen Anspruch, der NICHT SCHEITERN
                          KONNTE, und ich habe ihn gelöscht statt abgeschwächt:** er verlangte,
                          dass die berechneten Felder um höchstens eine halbe Rasterstufe runden —
                          die Schranke leitete sich aber aus DEMSELBEN `decimals` ab wie das
                          Runden, skaliert also mit, und die einzige andere Fehlerart (Verlassen
                          des Bereichs) ist durch `min(1, x + k·(1-x))` konstruktiv ausgeschlossen
                          und ohnehin schon von Anspruch 1 gedeckt. Übrig blieb ein
                          Fließkomma-Abstand von 4,7e-9 zwischen Schranke und gemessenem Drift —
                          die einzige erreichbare Fehlschlag-Ursache wäre ein Fehlalarm gewesen.
                          Die #367-Klasse, in einem Wächter, dessen eigener Scan-Abschnitt davor
                          warnt. **Neu dazugekommen ist stattdessen ein QUELLEN-Scan über die vier
                          Zeilen, die vom Hausdefault abweichen** (Noise 3 · Cutoff 0 · Attack 3 ·
                          Decay 0…10) — ohne ihn ist die Zeilentabelle des Tests eine Handkopie,
                          und ein „Aufräumen" von Attack auf 2 Stellen in `EchoelStudioView.swift`
                          hätte alle Tests grün gelassen. Bewusst nur die vier Abweichler: alle
                          siebzehn festzunageln macht jede gewöhnliche Panel-Änderung rot, und so
                          wird ein Wächter gelöscht. Die letzte Hälfte verbietet, dass `decimals`
                          je wieder einen DEFAULT bekommt — denn genau das war der Mechanismus:
                          ein Argument, das keine Aufrufstelle schreibt, taucht in keinem Diff
                          auf. ⚠️ Was er NICHT kann: beweisen, dass die Zeilen rendern, und
                          beurteilen, ob 3 Stellen sich für eine Hüllkurve richtig ANFÜHLEN — das
                          ist eine Geräteprobe. Steht so im Dateikopf), davor „169"
                          nach `TheArousalFloorSitsBelowThePacedBreathTests.swift` (#433 — der
                          erste Wächter in dieser Kette über einem Defekt, den ein REVIEWER-BERICHT
                          eingeführt hat und dessen Korrektur die halbe Scheibe ist. Der #429-Reviewer
                          nannte die Atem-Skala in `bioNormalized` (`Sequencer/RecordAnchor.swift`) „den
                          AUSGELIEFERTEN Aufnahmepfad, gerufen bei JEDEM Schritt auf lebendem Bio,
                          erreichbarer als der, den du repariert hast" — und ich habe das wörtlich in die
                          Aufgabe übernommen. **Beide Hälften falsch:** `RecordController.onStep` beginnt
                          mit `guard armed else { return }`, `arm()` hat NULL Aufrufer in `Sources/`, und
                          Task #204 hält den Controller längst als türlos fest. Und „das ganze
                          Resonanzband liest 0" stimmte auch nicht — der alte Boden 6,0 flachte 5…6 ab,
                          8/10/12 gaben 0,111/0,222/0,333.
                          ⭐ Die WAHRE, schärfere Aussage ist eine, die der Bericht nicht hatte:
                          `BreathPacer.defaultRate` ist EXAKT 6,0. Der Atemtrainer der App pact
                          voreingestellt genau auf den Boden, also las der Atem-Term am eigenen Ziel
                          exakt null. Ein Boden, der die gepacte Rate verschluckt, ist keine
                          Ruhe-Referenz, sondern ein blinder Fleck an der Stelle, auf die das Produkt
                          zielt. ⛔ Und meine erste Fassung schrieb hier „`BreathPacer.defaultRate` ist
                          exakt 6,0" als TRÄGER der Aussage plus „die Spanne des Pacers ist 5…12" — die
                          zweite Hälfte ist schlicht falsch und die erste hängt an einer toten Konstante:
                          `BreathPacer.minRate`/`maxRate` haben außer `ResonanceFinder` KEINEN Verbraucher,
                          `defaultRate` gar keinen, und `BreathPacer.tick` pact `pattern.cycleSeconds`. Der
                          echte gepacte Satz ist `BreathPattern.curated`: **6,0 · 6,0 · 3,75 · 3,158**. Die
                          Aussage stimmt also — Resonance UND Coherent sind exakt 6,0 —, aber aus den
                          Segmenten, nicht aus der Konstante. Boden jetzt 3,0 (die Untergrenze von
                          `BioSampleFrame.plausibleBreathRate`); der Wächter behauptet diese GLEICHHEIT
                          und leitet die gepacten Raten aus den Mustern ab statt aus einem Band.
                          ⭐ Zweite Hälfte, vom Reviewer nicht genannt und beim Nachlesen gefunden:
                          `usableBio()` prüft nur die FRISCHE, nicht `hasMeasuredBreath`. Ein
                          Gurt-Frame trägt `breathRate: 0`, und das wurde als Ruhe EINGEMISCHT — es
                          halbierte den Erregungswert für einen Körper, dessen Herz das Gegenteil sagte.
                          Genau die #215-Begründung („eine konstante 0 ist von einem stillen Performer
                          nicht zu unterscheiden"), einen Pfad weiter. Ohne Messung steht der Herz-Term
                          jetzt allein. Die Oberkante 24 bleibt absichtlich schmaler als das Tor (40):
                          Erregungsdecke, kein Gültigkeitstest — auf 40 zu weiten kostete jeder
                          realistischen Rate ~43 % Reiseweg (⛔ „an JEDER Rate" stand hier und gilt nur
                          unterhalb der heutigen Oberkante — darüber sättigt das schmale Fenster und der
                          Verlust fällt auf 27 % bei 30/min, 13,5 % bei 35 und 0 bei 40), dieselbe
                          Asymmetrie und dieselbe Ablehnung wie bei #429.
                          ⚠️ Und die zweite Hälfte KOSTET etwas, das erst die Nachlese gemessen hat: die
                          alte Funktion war STETIG in `breathRate`, die neue springt beim Erscheinen oder
                          Verschwinden einer Messung um |hr − br|/2 — bei 6/min und 120 bpm **0,43**, also
                          43 % des Spurbereichs, genau an der gepacten Rate. Aus einem glatten BIAS wird
                          ein SPRUNG. Der Aussetzer ist real (`CameraRPPGBioPublisher` schaltet Atem hart
                          bei `confidence >= 0.4`, und die Puls-Halte-Wiederholung nullt `breathRate`), und
                          nichts glättet danach. Die richtige Vollendung ist HALTEN, nicht Glätten — als
                          eigene Scheibe registriert. Gelandet wird trotzdem, weil eine erfundene Ruhe eine
                          dauerhafte Lüge ist und der Sprung eine reparierbare.
                          ⚠️ Was er NICHT kann, und das steht als ERSTES im Dateikopf: zeigen, dass
                          irgendetwas davon heute HÖRBAR oder AUFGEZEICHNET wird. Der Pfad ist dormant;
                          repariert WIRD er deshalb, nicht trotzdem — dieselbe Arithmetik nach einer Tür
                          bräuchte eine Hörprobe. FÜNF der ACHT Tests sind auf dem alten Fenster rot
                          (⛔ „vier der sieben" stand an FÜNF Stellen gleichzeitig: `testTheHeartTermIsUntouched`
                          stand unter „Gegengewichte, vorher wie nachher grün" und ist rot, weil es den Atem
                          AUSSERHALB des Tors festnagelt — alter Wert bei (85, 0) war 0,25, nicht 0,5. Die
                          eigenen Tests falsch einzuordnen ist derselbe Defekt wie ein Wächter, der nicht
                          scheitern kann, nur schwerer zu sehen), die anderen drei halten fest, was sich
                          NICHT bewegen darf.
                          ⛔ **Lehre, verschieden von der Stale-Zahl-Lehre dieses Absatzes: ein
                          Reviewer-Befund in der FORM des vorigen Befunds ist kein Beleg.** Dieser hier
                          war die perfekte Fortsetzung von #429 — gleiche Sache, größerer Einsatz — und
                          genau deshalb habe ich ihn nicht nachgeprüft, bevor er in einer Aufgabe stand.
                          Beide Behauptungen brauchten je einen `grep`, und beide fielen.),
                          davor „168" nach `TheBreathScaleSpansWhatTheGateAdmitsTests.swift` (#429 — der
                          erste Wächter in dieser Kette, der eine SKALA an ein TOR kettet statt an eine
                          Messung: `ModSource.breathRate.range` war `4...30`, abgeschrieben von
                          `RespirationEstimator.minRate`/`maxRate` — und ZWEI Quelldateien nannten genau
                          diese Stelle als die letzte lebende Kopie und lehnten die Reparatur je ab
                          („nicht wert, die Abbildungskurve für jede Route blind zu ändern"). Der Defekt
                          ist einer der REICHWEITE: die Menge der Werte, die je bei `normalizedValue`
                          ankommen kann, ist exakt `BioSampleFrame.plausibleBreathRate` (`3...40`), weil
                          `isMeasured` alles andere vorher verwirft. Eine Skala ab 4 ließ `[3, 4)` also
                          zugelassen-und-tot: das Tor nannte den Frame eine Messung, die Skala gab ihm
                          NULL Tiefe — ununterscheidbar von einem Körper, der nicht atmet. Gemessen:
                          3,5/min → 0,000000, 3,9/min ebenso.
                          ⭐ Der Punkt ist, an WAS gekettet wird. Nach #426 wäre `reportableRange`
                          (3,7736…) der naheliegende Griff gewesen und ist zweifach falsch: er prägt eine
                          FÜNFTE Atem-Zahl und lässt `[3, 3.7736)` weiter tot — HealthKit reicht durch,
                          was die Uhr meldet, und ist von unserem Kamera-Schätzer nicht begrenzt. Das
                          Tor ist das einzige Band, das die Frage „was kann hier überhaupt ankommen"
                          beantwortet. Die untere Grenze bleibt ein LITERAL, die Kettung steht im
                          Wächter — dieselbe Form wie `HealthWritePolicy` seit #426.
                          ⚠️ Die OBERE Grenze ist absichtlich NICHT mitgezogen, und das ist der Grund,
                          warum die Asymmetrie als eigener Test dasteht statt als Kommentar: `3...40`
                          kostet PAUSCHAL 27 % Reiseweg bei JEDER Rate in 3…30 (das Verhältnis 27/37
                          hängt nicht von der Rate ab) — absolut 0,170 bei 20/min, 0,270 bei 30/min —
                          und trifft damit jede Rate, die ein sitzender Performer wirklich atmet, um
                          Auflösung fürs Hecheln zu kaufen. ⛔ Hier stand „bei 20/min 0,27", an FÜNF
                          Stellen gleichzeitig: 0,27 ist der RELATIVE Verlust, der bei jeder Rate
                          gleich ist, UND der absolute bei 30/min — eine Zahl in zwei Einheiten, an
                          die falsche Rate geheftet. Der gemessene Preis der
                          Änderung, die WIRKLICH passiert ist: +0,037037 bei 4/min, monoton fallend auf
                          EXAKT null bei 30 und darüber (6/min 0,0769 → 0,1111, 12/min 0,3077 → 0,3333).
                          Sie bewegt sich in die Richtung, die das Produkt will: das HRV-Resonanzband
                          (~4,5–6/min, das `BreathPacer` vorgibt) lag in den unteren 8 % jeder Atem-Route.
                          ⛔ **UND DIE ERSTE FASSUNG BEHAUPTETE HIER, ES SEI UNHÖRBAR — beide Hälften
                          falsch, und es ist genau die Behauptung, der eine künftige Sitzung glaubt,
                          wenn sie entscheidet, ob eine Bereichsänderung gefahrlos ist.** Sie lautete
                          „KEINE ausgelieferte Route bindet `.breathRate` — der Enum-Case kommt nur in
                          den eigenen `switch`es seiner Datei vor". `hasProducer` ist für `.breathRate`
                          WAHR, also setzt `FXModCarrier.allChoices` (gebaut aus
                          `ModSource.allCases.filter`) „Breath rate" in den LEBENDEN Carrier-Picker der
                          FX-Bio-Modulation, und `FXModulation.swift` hat einen eigenen `switch` auf
                          `ModSource`. **Ein grep über EINE Datei kann `allCases` nicht sehen.** Wahr
                          ist das Schwächere: nichts PERSISTIERT eine Atem-Route und keine Vorgabe
                          bindet sie (`FXBioModulator.routes` lebt nur im Speicher, startet leer, der
                          „+"-Knopf legt eine Kohärenz-Route an) — ein frischer Start klingt gleich,
                          eine in der Sitzung gebaute Route nicht. Der Wächter
                          `testTheBreathCarrierIsOfferedToTheUser` macht daraus eine Tatsache statt
                          einer Behauptung. Was BLEIBT: keine Hörprobe kann bestätigen, dass die Kurve
                          die RICHTIGE ist.
                          Die tiefere Frage bleibt offen und steht in beiden Dateien: die Skala ist
                          LINEAR über einen 10×-Bereich, während Rate ungefähr logarithmisch empfunden
                          wird. DREI der ACHT Tests sind auf der alten Konstante rot; der Rest hält
                          fest, was sich NICHT bewegen darf, und sagt das im Dateikopf. ⛔ Hier stand
                          „nur ZWEI der sechs", während ein Doc-Kommentar 80 Zeilen tiefer in
                          DERSELBEN Datei den dritten schon rot nannte — und gezählt wurde über eine
                          Datei mit sieben Methoden. Zwei einander widersprechende Sätze in einer
                          Datei, und keiner davon stimmte.
                          ⛔ **Und der FÜNFTE Atem-Bereich stand die ganze Zeit da und wurde von
                          keiner der beiden Aufzählungen erfasst:** `RecordAnchor.bioNormalized`
                          skaliert Atem über `6.0...24.0`, wird bei JEDEM Schritt aus
                          `RecordController` auf lebendem Bio gerufen und liest damit über das GANZE
                          HRV-Resonanzband exakt 0 — der #429-Defekt wörtlich, auf dem AUSGELIEFERTEN
                          Aufnahmepfad, während #429 den ruhenden repariert hat. Als eigene Scheibe
                          registriert (#433), nicht mit eingefaltet. Die Aufzählungen in
                          `RespirationEstimator` („VIER") und `HealthWritePolicy` („DREI") standen
                          beide falsch da — in Dateien, deren erklärter Zweck es ist, den nächsten
                          unbemerkten Bereich zu verhindern. ⛔ Beim Schreiben stand `EngineBus.plausibleBreathRate` in DREI
                          Quell-Doks und wanderte von dort in meinen Testcode — die Konstante gehört
                          `BioSampleFrame`, `EngineBus` ist nur die DATEI. Ohne Compiler in dieser
                          Sitzung fängt so etwas kein Gate vor dem Push; korrigiert, auch in den drei
                          Alt-Stellen), davor „167" nach `TheKeypadCannotTypeWhatItCannotKeepTests.swift` (#431 — der
                          erste Wächter in dieser Kette über der EINGABE statt über der Anzeige oder dem
                          Zug, und der erste, der eine ausgelieferte Zahl absichtlich VERSCHLECHTERT, um
                          eine Lüge zu beenden: `EchoelNumberPad.commit()` rastert auf `10^-decimals`,
                          `append` deckelte aber nur die LÄNGE bei neun Zeichen. Auf einer Zwei-Stellen-
                          Zeile tippte man `0,375`, LAS `0,375` in der 30-pt-Anzeige und bekam `0,38`.
                          Reichweite paren-gematcht über `Sources/`, Kommentarzeilen AUSGENOMMEN:
                          **62 Konstruktionsstellen — 40 mit `decimals: 2`, 11 mit `0`, 10 auf dem
                          4er-Default, 1 weiterreichend** (`EchoelFXView.field`). Die elf
                          Null-Stellen-Zeilen waren nie betroffen, `allowsDecimal` sperrt dort schon
                          die Trennzeichen-Taste. ⛔ Hier stand „64 Stellen … gezählt statt
                          geschätzt", und 64 ist die rohe `git grep -c`-ZEILEN-Zahl von VOR dem
                          Kommentar, den dieselbe Scheibe hinzufügte — die dritte Auflage dieses
                          Repos, die darauf hereinfällt, in einem Baum, dessen
                          `Core/EchoelDecimalText.swift` fünf Zeilen davor warnt. Zwei weitere
                          Verräter standen im selben Satz: die Aufschlüsselung summierte auf 61
                          statt auf ihre eigene Gesamtzahl, und „dazu die zwei weiterreichenden
                          Helfer" zählte Zeilen doppelt, die schon in den 40/11/10 stecken. **Lehre,
                          verschieden von der üblichen Stale-Zahl-Lehre: die METHODE in einem Satz
                          ist auch eine Behauptung — meine sagte „paren-gematcht", während der
                          Matcher Kommentare mitnahm.**
                          ⭐ Der Punkt ist die GRENZE der Reparatur, nicht die Reparatur: `clamped` kann
                          die festgeschriebene Zahl ebenfalls von der Anzeige wegbewegen (`999` auf einer
                          0…1-Zeile gibt `1,0`), und das GENAUSO zu behandeln wäre falsch statt bloß
                          größer. Eine Nachkommastelle jenseits des Rasters kann kein weiterer Tastendruck
                          retten; ein Bereichs-PRÄFIX ist die normale Mitte einer gültigen Eingabe (`8`
                          liegt außerhalb `20…18000` auf dem Weg zu `800`). Abgelehnt wird also nur, was
                          schon unerreichbar ist, nicht was bloß unfertig ist.
                          ⚠️ Und es KOSTET etwas, das ohne Nachrechnen unsichtbar bleibt: die Ablehnung
                          SCHNEIDET AB, wo das Rastern GERUNDET hat — `0,375` schrieb vorher `0,38` fest
                          und schreibt jetzt `0,37`. Dazu blockiert sie gelegentlich einen harmlosen
                          Tastendruck (eine dritte `0` in `0,500` rastert auf sich selbst zurück). Beides
                          angenommen, weil ein Bedienelement nicht eine Zahl zeigen und eine andere
                          speichern darf (#135, #416, #427). Und der Preis ist GRÖSSER als das
                          Musterbeispiel nahelegt — `0,375` ist der GLEICHSTAND, wo beide Verfahren
                          0,005 verlieren; der ehrliche schlimmste Fall ist `0,379`: vorher `0,38`
                          (Fehler 0,001), jetzt `0,37` (Fehler 0,009). **Der maximale
                          Quantisierungsfehler VERDOPPELT sich**, von einer halben Rasterstufe auf
                          knapp eine ganze. Angenommen, weil der alte Fehler kleiner und UNSICHTBAR
                          war und der neue auf dem Schirm steht. ⚠️ Was er NICHT kann: nur EINER
                          seiner sieben Tests ist auf dem alten Code rot (der Verdrahtungs-Scan); die
                          anderen messen eine reine Funktion, die es vorher nicht gab, und stehen
                          gegen ihre spätere Lockerung. Und `EchoelNumberPad.snapped` ist `private`,
                          die Commit-Arithmetik ist hier also NACHGEBILDET — dieselbe Lücke wie beim
                          #427-Wächter, und der Grund, warum der Quelltext-Scan als eigene Hälfte
                          danebensteht.
                          ⛔ **Und der Scan hatte in seiner ersten Fassung ein Loch, durch das die
                          Nachlese sofort gelaufen ist:** er verlangte nur die Zeichenkette
                          `NumberPadEntry.acceptsDigit`. Wer `decimals: 4` fest verdrahtet hätte —
                          eine Konstante statt des Rasters der Zeile — hätte ALLE Tests grün gelassen,
                          während jede `decimals: 2`-Zeile den Defekt zurück hat. **Ein Wächter über
                          einem AUFRUF muss das Argument festnageln, das den Aufruf bedeutungsvoll
                          macht**, sonst prüft er nur, dass irgendwo ein Name steht. Zweite Hälfte
                          jetzt: `decimals: decimals`. Dazu zurückgenommen: die Behauptung, `snapped`
                          im Tastenfeld sei weiter tragend — auf dem EINZIGEN heutigen Aufrufer ist
                          sie redundant, weil `EchoelValueField.apply` dieselbe Klemm-dann-Raster-
                          Operation in derselben Reihenfolge fährt; und die Behauptung, das Tippen
                          von OK schreibe „die Zahl, die die Anzeige zeigte" — `%.Nf` rundet
                          HALF-TO-EVEN, `snapped` HALF-AWAY, sie trennen sich an jedem exakten
                          dyadischen Gleichstand (`0,125` liest „0,12", schreibt `0,13`). Das ist der
                          #431-Defekt, der auf dem Leer-Puffer-Pfad ÜBERLEBT, als eigener Posten
                          registriert (#432) statt in diese Scheibe gezogen), davor „166" nach `ADerivedRowStillScrubsTests.swift` (#427 Nachlese — der erste
                          Wächter in dieser Kette über einem Defekt, den die Scheibe SELBST erzeugt hat
                          und ihr eigener Wächter nicht sehen konnte: `EchoelValueField` trägt seit #376
                          ein ungerastertes Ziel durch die Ereignisse eines Zuges und vertraute ihm nur
                          bei ROHER Gleichheit gegen den gespeicherten Wert. Das gilt für eine
                          gespeicherte Bindung und NICHT für eine abgeleitete: `visualEnergy` — der EINE
                          Bild-Regler (#228) — hat keinen eigenen Zustand, sein Getter rechnet
                          `VisualEnergy.position(matching:motion:)` über die zwei Werte, die sein Setter
                          geschrieben hat. Über die 101 Zweier-Raster-Stellen ist dieser Umlauf auf
                          **39** bitgenau, schlimmster Rest 2,2e-16. An 62 von 101 Stellen wurde das
                          Ziel also bei JEDEM Ereignis verworfen — genau das Vor-#376-Regime, dessen
                          gemessene Totzone für eine 0…1-Zeile mit 2 Stellen bei ≈135 pt/s liegt.
                          Simuliert gegen die ausgelieferten Konstanten kam ein 3-s-Zug bei 10, 40, 60
                          und 120 pt/s auf **0,01 und blieb dort**, bei 135 sprang er auf **1,00**: der
                          eine Bild-Regler war unter dem Finger ein Zwei-Zustands-Schalter. Bei
                          `decimals: 4` liegt dieselbe Schwelle bei ≈2,7 pt/s — die Scheibe hat die
                          Fragilität nicht erzeugt, sondern ERREICHBAR gemacht.
                          ⭐ Die Reparatur sitzt im GETEILTEN Bedienelement, nicht in `visualEnergy`:
                          im Getter zu rastern hätte funktioniert und eine zweite Kopie der
                          Raster-Konstante neben `decimals: 2` gestellt — der Doppel-Definitions-Defekt
                          aus #416. Das Prädikat war schlicht zu streng; es fragte „ist das Ziel der
                          gespeicherte Wert", während sein eigener Kommentar „beschreibt das Ziel noch
                          die Zahl auf dem SCHIRM" sagt. `ScrubPrecision.carriesTarget` rastert beide
                          Seiten und bildet beide durch `V` ab — und die zweite Hälfte ist die, die eine
                          spätere Vereinfachung fallen lassen würde: `Double(Float(17999,9))` rastert
                          auf 4 Stellen zu 17999,9004, das Ziel auf 17999,9, ein Double-seitiger
                          Vergleich würde also die Cutoff-Zeile bei JEDEM Ereignis neu ansetzen.
                          ⚠️ Was er NICHT kann: beweisen, dass ein Finger auf dem Gerät reist. Die
                          ≈135 pt/s und die 39/101 sind Simulation und Arithmetik, kein Lauf. Und nur
                          EINER seiner sechs Tests ist auf dem alten Prädikat rot; die anderen fünf
                          halten fest, was sich NICHT ändern darf, und sagen das im Dateikopf),
                          davor „165" nach `VisualPresetValuesAreReachableTests.swift` (#427 — der erste
                          Wächter in dieser Kette über einer EINBAHNSTRASSE in der Oberfläche statt
                          über einem falschen Wert: sechs der sieben Zeilen im Visual-Panel nahmen
                          `EchoelValueField`s Vorgabe `decimals: 4`, und `decimals` ist nicht die
                          Anzeige sondern das RASTER (`ScrubPrecision.snapped`). Auf 0…1 bot die App
                          damit vier Nachkommastellen an, wo jeder FX-Parameter, die Master-Lautstärke
                          und die Wetter-Mischer auf zwei stehen. Die Scheibe setzt die sechs auf 2 —
                          und genau das kann eine Voreinstellung UNERREICHBAR machen: der Preset-Chip
                          leuchtet nur, solange die Werte noch übereinstimmen, also wäre ein Preset mit
                          einer dritten Nachkommastelle eine Tür, durch die man nur hinaus kommt, ohne
                          dass irgendwo etwas rot wird. Heute liegt jeder Wert in `VisualPreset.factory`
                          auf dem Zweier-Raster (Intensity 0,8·0,95·1,1·1,2·1,4 · Motion
                          0,45·0,42·0,7·1,1·1,4 · Spread 1,35·1,2·1,0 · Vapors Palette 0,82/1,12);
                          der Wächter macht den ersten, der es nicht tut, zu einem roten Test.
                          ⚠️ Die `Float`→`Double`-Stufe gehört zur Messung und nicht zum Rauschen:
                          `VisualPreset` speichert `Float`, die Zeilen sind `Double`, also hält die App
                          nie die 0,45 sondern 0,44999998807907104. Der Versatz ist ~1e-8 und der
                          Vergleich der App läuft auf 1e-4, vier Größenordnungen gröber — geprüft wird
                          deshalb der KONVERTIERTE Wert, weil ein Test auf dem Literal eine Zahl misst,
                          die die App nie hat. ⚠️ Was er NICHT kann: `sameOnDisplayGrid` ist `private`
                          in `EchoelStudioView`, das Prädikat ist hier also NACHGEBILDET — ändert
                          jemand die Vergleichs-Stellenzahl der App, bleibt diese Datei grün. Das ist
                          eine echte Lücke und der Grund, warum die zweite Hälfte (Quelltext-Scan auf
                          ein ausdrückliches `decimals:` in jeder der sieben Zeilen, rot vor #427)
                          daneben steht: die beiden scheitern aus verschiedenen Gründen. Und die
                          Scheibe ist bewusst auf EIN Panel begrenzt — mit einer Zahl, die größer
                          ist als die naheliegende: es bleiben ZEHN Aufrufstellen auf der Vorgabe,
                          aber zwei davon sind die Helfer `param`/`knob`, die zusammen SIEBZEHN
                          Zeilen im Sound-Panel rendern (neun davon 0…1). Es sind also
                          fünfundzwanzig ZEILEN, nicht zehn — vierundzwanzig erreichbare, weil
                          `PianoRollView`s „Vel" in einer türlosen Datei sitzt. Von den acht direkten
                          Stellen wollen zwei die vier Nachkommastellen ausdrücklich (Kammerton A4,
                          gesperrtes Tempo, beide sagen „editable to 0.0001" im eigenen Kommentar) —
                          genau deshalb ist das KEINE App-weite Regel, sondern die #364-Falle, wenn
                          man sie dazu macht.
                          ⛔ **UND DIE HÄLFTE DIESES SATZES ÜBER DEN KAMMERTON WAR FALSCH — geprüft
                          bei #440, mit zwei `grep`s, die beim Schreiben nicht gemacht wurden.** Nur
                          `BodyTempoField` sagt „editable to 0.0001 BPM" (drei Stellen, u. a. der
                          eigene Dateikopf). Der Kommentar der A4-Zeile sagt seit jeher
                          „exact to 0.01 Hz" (`WorkspaceView.swift`) — die Zeile war also nicht
                          absichtlich auf vier Stellen, sondern lief auf der Vorgabe, während der Kopf
                          desselben Kommentarblocks zwei versprach. Das ist keine Geschmacksfrage: der
                          Wert ist PERSISTIERT und stimmt jede Stimme, und das Founder-Video vom
                          2026-08-02 zeigt `483,4352` auf dem Schirm. #440 setzt die Zeile auf 2 und
                          macht damit ihren eigenen Kommentar wahr; der KOSTENPUNKT steht neben ihr
                          (schlimmster Fall eine halbe Rasterstufe, 0,005 Hz, bei 440 Hz also
                          0,0197 Cent — hörbar nicht, ein Schreibvorgang schon).
                          ⛔ **Und an DIESER Stelle stand „sechs Zeilen darüber", an vier Stellen
                          gleichzeitig** (hier, ein zweites Mal im #440-Eintrag oben, im Quellkommentar
                          und im Wächter) — der Abstand ist 29 Zeilen, und er war schon vor der Scheibe
                          13. **Ein Zeilenabstand INNERHALB einer Datei ist die brüchigste Tatsache,
                          die dieses Repo aufschreibt: der Commit, der ihn behauptet, verschiebt ihn
                          im selben Atemzug.** Ersetzt durch „der Kopf desselben Kommentarblocks" —
                          eine Beschreibung, die eine Einfügung überlebt. Ebenfalls korrigiert: die
                          0,0197 Cent standen an einem BEISPIEL (442,3456 → 442,35), dort sind es
                          0,0172; die Zahl ist die obere SCHRANKE bei 440 Hz. Ein Beispiel ist keine
                          Schranke, und gebraucht wird die Schranke. **Die Lehre ist
                          die des Absatzes über der Plattform-Tabelle in ihrer schärfsten Form: eine
                          Behauptung über ZWEI Dinge wird geprüft, indem man BEIDE nachschlägt — hier
                          stimmte eine Hälfte, und die zweite ist mitgereist, weil der Satz sich gut
                          las.** Damit bleibt genau EINE Stelle, die die vier Stellen ausdrücklich
                          will, und das ist der Grund, warum #440 sie in
                          `Tests/CISmoke/EveryReachableRowStatesItsGridTests.swift` als
                          Gegengewicht festnagelt statt sie mitzukehren),
                          davor „164" nach `TheBreathEdgeReachesHealthTests.swift` (#426 — der erste
                          Wächter in dieser Kette, der eine KONSTANTE an eine ANDERE Konstante kettet,
                          statt ein Verhalten oder eine Anzeige zu prüfen: `HealthWritePolicy`
                          verwarf jede Atemmessung unter 4,0/min, weil ihre untere Grenze aus
                          `RespirationEstimator.minRate` abgeschrieben war — der Rate, die der
                          Schätzer ANZIELT, während er seit #424 im weiteren `reportableRange`
                          (3,7736…31,8) MELDET. Ein Körper, der genau die Resonanzrate atmet, kam
                          damit auf dem Schreibweg nur mit **214 von 360** Phasen durch (Puls 42;
                          217 bei 46, 218 bei 50, 209 bei 55, 219 bei 62, 217 bei 70, 137 bei 84,
                          210 bei 90, 146 bei 100) — neun Pulse, kein sauberer darunter.
                          ⛔ **Und diese neun Zahlen standen hier eine Fassung lang als VERLUSTE**
                          („verlor 214 von 360"), während Commit-Text, Quelle und Testkopf sie
                          übereinstimmend als DURCHGELASSENE führen — verloren gingen 146 bei Puls
                          42. Derselbe Absatz zitiert zwei Bildschirme weiter oben im #424-Eintrag
                          dieselben Zahlen richtig herum („von 344 auf 214"). Eine Zahl ohne ihre
                          RICHTUNG ist keine Messung; wer eine Zählung überträgt, überträgt zuerst,
                          was gezählt wurde.
                          ⭐ **Und der Schaden ist nicht „weniger Samples", sondern VERZERRUNG**, was
                          diesen Befund von einem konservativen Filter unterscheidet: der Schnitt lag
                          fast genau auf dem Mittelwert der korrigierten Verteilung, also überlebte
                          die hohe Hälfte. Mittlerer Fehler der GESCHRIEBENEN Teilmenge gegen die
                          ganze veröffentlichte Population: Puls 42 **+0,1522 vs +0,0497**, 46
                          +0,1430 vs +0,0492, 62 +0,1212 vs +0,0457, 90 +0,1093 vs +0,0415 — Faktor
                          ~3 auf Daten, die in einer Gesundheitsakte landen und in
                          `PerformerSignature` gelernt werden. Die Reparatur ist WEITEN, nicht RUNDEN
                          (#424 hat genau auf diesem Pfad bezahlt: eine geklemmte Meldung
                          veröffentlichte 4,000 an 358 von 360 Phasen für einen 3,5/min-Körper, also
                          eine erfundene Zahl innerhalb der Policy-Grenze).
                          ⭐ Der Punkt ist die KETTUNG, und die Bauweise ist bewusst: die Grenze
                          bleibt ein LITERAL (3,7), weil das, was Echoel in eine Gesundheitsakte
                          schreibt, sich nicht als Nebenwirkung einer DSP-Nachjustierung weiten darf
                          — `testThePolicyAdmitsEverythingTheEstimatorCanReport` wird rot, sobald
                          `bandTolerance` steigt, und macht die Weitung zu einer Entscheidung statt
                          zu einer Folge. ⚠️ Was er NICHT kann: beweisen, dass der Kamerapfad einen
                          echten 4/min-Atmer 15 s lang hält (#304/#410), und beweisen, dass
                          `HealthKitWriter` das Sample wirklich ablegt (braucht HealthKit + Gerät).
                          Beides steht im Dateikopf), davor „163" nach
                          `MoodKnobsSayWhatTheyDoTests.swift` (#354 Slice A — der
                          erste Wächter in dieser Kette, der eine ANZEIGE an eine ENGINE-Tatsache
                          kettet statt eine der beiden für sich zu prüfen: zwei der acht
                          Mood-Regler (`darkness`, `romance`) werden vom Komponisten je EINMAL
                          auf dem LEBENDEN Pfad gelesen, als `> 0.6` (Voicing eine Oktave runter)
                          und `> 0.5` (Septime dazu) — der Rest ihrer Reise ist wirkungslos. Die
                          Zeilen boten dabei VIER Nachkommastellen an, weil
                          `EchoelValueField.decimals` auf 4 defaultet und diese acht der GRÖSSTE
                          Satz 0…1-Felder der App waren, die nie einen Wert übergaben (jeder
                          FX-Parameter, die Master-Lautstärke und die Wetter-Mischer stehen auf
                          2). Gemessen wird jetzt beides: die zwei Klippen über ALLE angebotenen
                          Genres (0,20 vs 0,59 bitgleich, 0,61 anders) UND dass die
                          Panel-Bildunterschrift die zwei Schwellen NENNT.
                          ⛔ **UND DIE ERSTE FASSUNG DIESER SCHEIBE LIEFERTE EINE ÜBERZOGENE
                          BILDUNTERSCHRIFT AUS — genau die Klasse Fehler, gegen die sie gebaut
                          war, nur auf der Anzeige-Seite.** Sie versprach „adds the 7th above
                          0.50" pauschal; die einzige Leserstelle ist aber
                          `if mood.romance > 0.5, !tones.contains(6)`, und **9 der 16 angebotenen
                          Genres tragen die Septime schon** — `.selfObservation`, das
                          AUSGELIEFERTE STANDARD-GENRE, darunter. Für den Klang, den ein
                          Erstnutzer hört, versprach die Zeile also etwas, das der Regler dort
                          unter keiner Stellung tut. Die Bildunterschrift nennt jetzt die
                          Einschränkung samt Zahl („7 of the 16 offered"), und zwei neue Tests
                          nageln sie fest: Bit-Identität 0,49↔0,51 auf allen neun lushen Genres
                          und der 7/16-Schnitt direkt gegen `harmonicProfile`. Zwei weitere
                          Behauptungen derselben Fassung waren ebenfalls falsch und sind
                          zurückgenommen: „die EINZIGEN 0…1-Felder" (`Energy` und `Hue` im
                          Visual-Panel stehen ebenfalls auf dem 4er-Default) und die Begründung
                          des Darkness-Zählers, die `dubTechno`/`trap` „handgebaute Zweige"
                          nannte — beide laufen durch `composeHarmonic`, und `trap` ist gar nicht
                          angeboten. Der wahre Grund für „mindestens eins" statt einer Zahl ist
                          `VoiceLeader.resolve`, das die Lage danach neu oktaviert.
                          **Lehre: ein Wächter über einer Anzeige muss die Anzeige AUCH gegen die
                          Daten prüfen, nicht nur gegen ihr eigenes Vorhandensein.**
                          ⭐ Der Punkt ist die KETTE, nicht die einzelne Behauptung: wenn eine
                          spätere Scheibe `romance` stufenlos macht, wird der Verhaltenstest ROT —
                          absichtlich, als Erinnerung, die Bildunterschrift im selben Commit
                          mitzuziehen, nicht als Argument für die Klippe. ⛔ `darkness` ist
                          bewusst NICHT für dieselbe Behandlung vorgemerkt: Register ist per
                          Konstruktion gerastert (`key.degree(_:octave:)` bewegt sich in ganzen
                          Oktaven, alles feinere verlässt die Tonart, und `VoiceLeader.resolve`
                          oktaviert die Lage danach ohnehin neu) — ein „Gradient" dort wäre eine
                          erfundene Zahl, damit ein Regler stufenlos AUSSIEHT. ⚠️ Was er NICHT
                          kann: beweisen, dass die Bildunterschrift auf dem Gerät erscheint, und
                          beweisen, dass `EchoelValueField` `decimals` befolgt — beide Hälften sind
                          Quelltext-Scans und sagen das im Dateikopf. Und der Gegengewichts-Test
                          („die anderen sechs sind KEINE Schalter") fehlt absichtlich: den halten
                          `LivelinessReachesTheDensityDecisionTests` (#418) und
                          `LivelinessMovesTheStillnessGateTests` (#419) schon, und eine zweite,
                          schwächere Kopie einer lebenden Behauptung ist genau der
                          Doppel-Definitions-Defekt aus #416),
                          davor „162" nach `TheBandHoldsAtEveryRestingPulseTests.swift` (#424 dritte
                          Fassung — der erste Wächter in dieser Kette, der eine ACHSE hinzufügt statt
                          eines Falls, und er entstand, weil die zweite Fassung eine Konstante an
                          EINEN Puls angepasst hatte. Alle Sweeps von #424 liefen auf `meanBPM: 60`,
                          und 60 ist bei 4 Atemzügen/min der EINE entartete Puls: der Zyklus sind
                          exakt 15 Schläge, der Nulldurchgang landet auf der Grenzperiode punktgenau,
                          und 1,00002 räumt ihn ab. Daneben ist der Mechanismus schlichte
                          Schlag-Quantisierung — bei N Schlägen pro Atemzyklus rundet der Durchgang
                          auf `floor(N)`/`ceil(N)`, die Forderung ist also ≈ 1 + 1/(2N), am langsamen
                          Rand **1 + 2/Puls**. Gemessen bei 4/min: Puls 46 → 1,0439 · 50 → 1,0403 ·
                          58 → 1,0347 · 70 → 1,0287 · 90 → 1,0223; **16 der 66 ganzzahligen Pulse in
                          45…110 brauchen mehr als 1,02**, und an genau denen hat die ausgelieferte
                          1,02 NICHTS geräumt: 19 von 360 Phasen weiter still bei Puls 46, 21 bei 50,
                          27 bei 62, 32 bei 70, 44 bei 90 — bitgleich mit dem Zustand VOR #424. Die
                          Reparatur wirkte bei 60 und 110 bpm und nirgends sonst.
                          ⭐ **Und das eigentliche Argument für den breiteren Wert ist nicht die
                          Stille, sondern eine VERZERRUNG, die vorher niemand gesehen hat:** das enge
                          Band war am langsamen Rand ein EINSEITIGER Filter — von den zwei
                          quantisierten Perioden, auf die ein 4/min-Zyklus fallen kann, nahm es nur
                          die SCHNELLE an. Mittlerer Report auf einem exakt 4,0/min atmenden Körper
                          über alle 360 Phasen, 1,02 → 1,055: Puls 42 **+0,259 → +0,050** · 46 +0,239
                          → +0,049 · 62 +0,190 → +0,046 · 90 +0,152 → +0,042. Faktor 4–5 auf dem
                          Fehler, der beim Verbraucher ankommt. Der ausgelieferte Wert **1,055** ist
                          deshalb aus einem FENSTER abgeleitet und nicht aus einem Minimum: unten
                          Physiologie (jeder Puls bis ~37 bpm braucht 1 + 2/37 ≈ 1,054), oben
                          Messqualität (der 4/min-Report hält 3,99993 bis 1,067 und fällt bei 1,068
                          auf 3,8197, weil das Band dann eine Periode annimmt, die nicht der
                          Atemzyklus ist). ⚠️ **Und er kostet etwas, das nur ABSEITS des Fixture-Pulses
                          existiert und deshalb fast unterschlagen worden wäre:** weil der Report dort
                          knapp UNTER 4,0 landet und `HealthWritePolicy` nicht klemmt sondern
                          VERWIRFT, fallen die health-schreibbaren Samples eines 4/min-Körpers von
                          344 auf 214 von 360 (Puls 42), 341 → 217 (46), 316 → 210 (90). Weniger
                          Samples, jedes ~5× näher an der Wahrheit — ein Tausch, und er steht als
                          Tausch da. **Lehre, und sie ist die Schwester der #424-Lehre eine Zeile
                          weiter unten: die sagt „ist eine Grenze an einem ENDE falsch, miss das
                          andere ENDE". Diese sagt: miss die andere ACHSE.** Ein Phasen-Sweep an
                          einem einzigen Puls ist eine Stichprobe, wie viele Phasen er auch hat.
                          ⚠️ Was er NICHT kann: beweisen, dass der Kamerapfad an irgendeinem Puls
                          einen echten 4/min-Atmer trägt (#304/#410), und ein konstanter Puls ist
                          selbst eine Fixtur — ein echter Take driftet, und Drift bewegt N stetig.
                          Er behauptet die schwächere, prüfbare Aussage: bei FESTEM Puls irgendwo im
                          Bereich sind die beworbenen Grenzen messbar.
                          ⛔ **VIERTE RUNDE (DSP-Reviewer auf `ab713ef`, jeder Befund von mir
                          nachgerechnet): die Wächter-Datei war an drei Stellen falsch, und der
                          Aufhänger ist, dass die HÄRTESTE davon in dem Absatz stand, der die
                          Puls-Auswahl gegen den Vorwurf der Rosinenpickerei verteidigt.** Er nannte
                          55, 84 und 100 „entartet … null Stille sogar vor #424" und stellte sie als
                          KONTROLLE hin. Beide Hälften falsch: 55 ist mit 13,75 Schlägen/Zyklus gar
                          nicht entartet, und die Stille vor #424 beträgt dort 112 · 223 · 214 von
                          360 — die drei SCHLECHTESTEN im Satz. Der Mechanismus stand dabei
                          verkehrt herum: ein entarteter Puls ist der Messerschneiden-Fall, nicht
                          der sichere (der Durchgang landet exakt auf der Grenzperiode, also
                          schweigt er an zwei Dritteln aller Phasen und jedes ε > 0 räumt ihn ab —
                          genau deshalb zeigte 60 bpm 240/360). **Es gab in diesem Satz nie eine
                          Kontrolle; alle neun Pulse sind vor #424 rot.** Dazu: „diese vier Tests
                          sind bei 1,02 rot" galt für EINEN (die anderen drei sagen in ihren eigenen
                          Doc-Kommentaren das Gegenteil), der Hochkanten-Test konnte über
                          `restingPulses` GAR NICHT scheitern (Anforderung 1,0 an allen neun; der
                          Defekt sitzt bei Puls 60/61 — jetzt angehängt), und der veröffentlichte
                          Vertrag auf `docs/architecture.html` war um ~19× zu eng (gemessen +1,42
                          statt +0,07 über `maxRate`, weil den Report nicht die Messung begrenzt
                          sondern das ANNAHME-Band). **Der Wert ist auf 1,06 gestiegen:** 1,055 lag
                          nur 0,0018 über der bindenden Anforderung (1,0532 bei Puls 38) und deckte
                          Puls 34 (1,0595) nicht; 1,06 deckt jeden Puls ab 31 und ist messbar
                          kostenlos (alle Innen-Fehler, alle 4/min-Reports, alle health-schreibbaren
                          Zahlen, das Stale-Fenster und die Ruhe-Hand bitgleich). Und das
                          „FENSTER" ist zurückgenommen: die obere Wand bei 1,067 war eine
                          Eigenschaft des 60-bpm-Fixtures, kein Messqualitäts-Limit),
                          davor „161" nach `TheBandEdgeIsMeasurableTests.swift` (#424 — der erste
                          Wächter in dieser Kette über einem Defekt an BEIDEN Enden eines Bandes,
                          von denen die Diagnose nur EINES nannte: `RespirationEstimator` warb mit
                          4…30 Atemzügen/min und VERWARF einen Nulldurchgang komplett, wenn dessen
                          Jitter die implizierte Rate einen Hauch darüber oder darunter schob —
                          keine Periode, kein Zähler, keine Rate. Über alle 360 Ganzgrad-Phasen,
                          60-s-Takes, Ruhepuls: `ratePerMinute` blieb bei **30/min an 61 von 360**
                          Phasen null (das war der berichtete Fall) und bei **4/min an 240 von
                          360** — dem LANGSAMEN Rand, den niemand angesehen hatte, viermal
                          schlimmer. Die Reparatur ist eine Formregel und keine Zahl: ANNEHMEN in
                          einem weiteren Band als man MELDET (`[minRate/tol, maxRate*tol]`).
                          ⛔ **UND DIE ERSTE FASSUNG DIESER SCHEIBE HAT DABEI SELBST EINEN DEFEKT
                          AUSGELIEFERT — den einzigen in dieser Kette, der auf einem
                          GESUNDHEITSDATEN-Pfad landet, und ich habe ihn erst durch den
                          DSP-Reviewer gesehen.** Sie nahm `tol = 1,2` und KLEMMTE den Report auf
                          `[minRate, maxRate]` zurück, „damit der veröffentlichte Vertrag gleich
                          bleibt". Beides falsch. Die kleinste Toleranz, die die Stille an BEIDEN
                          Rändern beseitigt, ist per Bisektion **1,00111** (⛔ und AUCH diese Zahl
                          gilt nur für den 60-bpm-Fixture — der Eintrag über diesem misst den
                          langsamen Rand über die Puls-Achse und findet dort 1,0439; die 1,00111 ist
                          die Forderung des SCHNELLEN Randes und die bindet nie) — 1,2 war das
                          ~180-fache davon; und zusammen mit der Klemme las sich ein Körper UNTERHALB des
                          Bandes als sichere Messung: bei 3,5 Atemzügen/min veröffentlichte der
                          Schätzer an **360 von 360** Phasen, davon an **358** mit `ratePerMinute`
                          exakt 4,000 (vorher: 37 Veröffentlichungen, nie auf der Grenze).
                          `HealthWritePolicy.respiratoryRange` war `4...40` (seit #426 `3,7...40`) und ENTHÄLT die 4,0 —
                          die erfundene Zahl wäre als Atemfrequenz-Sample nach Apple Health
                          geschrieben und in `PerformerSignature` gelernt worden. Jetzt **ohne
                          Klemme** (und bei 1,02, was einen Commit später auf 1,055 korrigiert wurde
                          — siehe den Eintrag darüber): 3,5/min veröffentlicht an 61 Phasen, nie auf
                          der Grenze; der Report überschießt `maxRate` um höchstens 0,064/min am
                          Fixture-Puls und 0,074 bei 90 bpm. **Lehre, und sie ist
                          allgemeiner als dieser Parameter: ein SÄTTIGENDER Ausgang auf einem
                          Messpfad erfindet Daten am Anschlag — und wie weit diese Erfindung reicht,
                          entscheidet genau die Konstante daneben.** ⛔ Zweitens war „im Bandinneren
                          bit-identisch" als Allaussage FALSCH: gewischt in 0,25er-Schritten bewegt
                          sich der Report bei 4,0–4,75 und ab 20,5 bis 30 — Jitter schiebt auch eine
                          INNERE Rate über die alte Grenze. Wahr ist die engere Aussage, die der
                          Test festnagelt: bit-identisch bei 5, 6, 10, 15 und 20, und wo es sich
                          bewegt, wird es besser (4,25: 0,4226 → 0,3661; 24: 4,9626 → 2,2217; von den
                          43 Raten, die sich bewegen, werden 36 besser, 6 sind im schlimmsten Fehler
                          bitgleich und EINE ist schlechter: 21,5/min um 0,0108/min. ⛔ Hier stand
                          „0,0044", an vier Stellen gleichzeitig, weil ich 90 Phasen abgetastet und
                          es einen Sweep genannt habe — im selben Absatz, der eine unter-gewischte
                          Behauptung zurücknimmt). ⛔ Drittens ging dabei eine Klammer
                          eines FREMDEN Parameters still kaputt: die untere Schranke von
                          `pullLagAllowance` wird bei 28/min gemessen, nah genug am Rand, dass die
                          neue Toleranz sie von ≈0,74 s auf ≈0,87 s schiebt. Eine Konstante, die als
                          „von beiden Seiten geklammert" dokumentiert war, verlor eine Klammer durch
                          eine Änderung zwanzig Zeilen weiter unten.
                          ⚠️ Seine wichtigste Hälfte ist der Gegengewichts-Test, nicht die
                          Regression: der naheliegende Einwand gegen ein weiteres Annahme-Band ist
                          „dann kommt Rauschen rein", und `testAStillHandStillPublishesNothing`
                          zeigt, dass das Band gar nicht der Rauschfilter ist — das Hüllkurven-Veto
                          ist es, eine ruhige Hand bleibt bei beiden Toleranzen bei identischer
                          Konfidenz weit unter dem Tor. ⛔ Und zwei seiner Schwellen waren in der
                          ersten Fassung RUNDE ZAHLEN statt Messwerten: der Innen-Test verlangte
                          pauschal `< 1,0`, während die schlechteste Phase bei 15/min auf 1,123
                          und bei 20/min auf 2,190 liegt — VOR UND NACH der Änderung gleich. Er
                          wäre also auf dem Code rot gewesen, den er schützt, und die naheliegende
                          Reparatur (auf 2,5 lockern) wäre genau der Fehler, den #404 Slice 2 hier
                          schon einmal bezahlt hat: die Schwelle so wählen, dass der eigene Code
                          sie besteht. Jetzt pro Rate aus dem Sweep, mit genanntem Messwert und
                          Marge. Was er NICHT kann: beweisen, dass der Kamerapfad einen echten
                          4/min-Atmer trägt — 15 s pro Zyklus, und die Akquise ist #304/#410),
                          davor „160" nach `ResonanceBreathingNeedsMoreThanOneWindowTests.swift` (#343 — der
                          erste Wächter in dieser Kette über einer BLINDSTELLE statt über einem Fehler: der
                          Code war für jede NORMALE Atemfrequenz richtig und nur für die eine falsch, auf die
                          das Produkt zielt. `CameraRPPGBioPublisher` baute pro Veröffentlichung einen FRISCHEN
                          `RespirationEstimator` und fütterte ihn nur mit dem neuesten 10-s-Analysefenster;
                          die Atemrate liest sich aus dem Abstand ZWEIER aufsteigender Nulldurchgänge, ein
                          Fenster über EINEN Atemzyklus enthält höchstens einen. Bei 6 Atemzügen/min — der
                          HRV-Resonanzrate, die `BioScienceInfo` zitiert und `BreathPacer` vorgibt — IST der
                          Zyklus 10 s. Simuliert über die ausgelieferten Konstanten über ALLE 360
                          Ganzgrad-Startphasen: `confidence` 0,458–0,625 und damit an JEDER ÜBER dem
                          0,4-Tor, während `ratePerMinute` an 345 Phasen 0 blieb und an 15 eine erfundene
                          7,4 meldete. „Atem gemessen: ja. Rate: null — oder falsch." Bei 15/min war
                          derselbe Code an 278 von 360 Phasen richtig; deshalb fiel es nie auf, und deshalb
                          hat die Datei einen dritten Test, der genau das festhält: der Befund ist
                          RATENABHÄNGIG, das Fenster war nie „zu kurz" im Allgemeinen.
                          ⛔ Und dieser Absatz stand bis 2026-08-06 auf „vier Startphasen · jedes Mal 0 ·
                          0,46–0,50 · bei jeder Phase richtig" — VIER Behauptungen, alle aus vier
                          Stichproben gezogen, alle vom Sweep widerlegt. Der Nullpunkt-Start von
                          `smooth`/`prevSmooth` erzeugt an einem schmalen Phasenband einen Nulldurchgang,
                          der kein Atemzug ist; vier Stichproben laufen daran vorbei. **Die Lehre ist
                          nicht „mehr Stichproben", sondern: eine Aussage über ALLE Phasen darf nicht aus
                          einer Handvoll gezogen werden — man wischt oder man formuliert schwächer.** Die Reparatur ist NICHT ein längeres Fenster (#340 nennt
                          die 10 s den größten Einzelposten im Bio→Audio-Budget), sondern EIN Schätzer pro
                          Take, jeder Herzschlag genau einmal eingespeist — wofür `CameraAnalyzer.beatTimes`
                          neu entsteht: die Fenster überlappen zu ~90 % und Intervall-WERTE tragen keine
                          Identität, „neuer als der zuletzt verbrauchte Schlag" ist die einzige exakte
                          Entdopplung. ⚠️ Was er NICHT kann und was im Dateikopf steht: die Verhaltens-Hälfte
                          treibt den REINEN Schätzer mit einer synthetischen RSA-Reihe — sie beweist die
                          Arithmetik und die Blindstelle, nicht dass der Kamerapfad an einem echten Finger
                          trägt; die Akquise selbst ist offen (#304/#410). Die Verdrahtungs-Hälfte ist ein
                          Quelltext-Scan, ankert deshalb ZUERST auf der Existenz der Eigenschaft (sonst die
                          #367-Falle: ein Scan, der nur die alte Form verbietet, ist auf einer Datei grün,
                          die beide verloren hat) und streift Kommentare ab, weil die Quelle die kaputte Form
                          beim Namen nennt),
                          davor „159" nach `TheManifestArgumentOrderIsTheCompilersTests.swift` (#420 — der
                          erste Wächter in dieser Kette über einer Datei, die GAR NICHT KOMPILIERT, und der
                          einzige, der `Sources/` nicht anfasst: `Package.swift` listete im `.target(`-Aufruf
                          `swiftSettings:` VOR `resources:`. In `PackageDescription.target` sind alle Labels
                          nach `name` defaultiert, also gibt die falsche REIHENFOLGE keine Ordnungs-Meldung —
                          die Überladungsauflösung landet woanders und meldet zwei Unwahrheiten: einmal eine
                          Label-Liste, die es so nicht gibt, und einmal „`Array<String>` hat kein Member
                          `.process`" auf der Ressourcen-Zeile, die dadurch nach einem Ressourcen-Fehler
                          aussieht. Sie war keiner: `resources` war in `path`s Position gebunden.
                          ⛔ **Der Grund, warum das unbemerkt blieb, ist der eigentliche Befund und gehört in
                          die Doctor-Sektion A:** `ci.yml:165` läuft als `swift package resolve || true`. Mit
                          der Maske kann ein ungültiges Manifest gar nichts rot färben — der Fehler stand
                          einfach in JEDEM CI/CD-Log als Rauschen. Gleichzeitig sagt der SESSION-START-Block
                          dieser Datei jeder frischen Sitzung als ERSTES `swift build` und `swift test`; was
                          sie zurückbekam, war ein Manifest-Fehler in einer Datei, die sie nicht angefasst
                          hatte. Kaputtes Instrument PLUS maskiertes Signal — genau das Paar, für das es die
                          `doctor`-Skill gibt. Das `|| true` steht in einer founder-gated Datei und ist
                          BERICHTET, nicht editiert; der Wächter ist die Hälfte, die mir zusteht.
                          ⚠️ Was er NICHT kann, und das ist hier wichtiger als sonst: er KOMPILIERT das
                          Manifest nicht (kein SwiftPM-Schritt im blockierenden Bundle, keine lokale
                          Toolchain). Er nagelt die EINE Form fest, die kaputt war, plus die Reihenfolge aller
                          benutzten Labels gegen die kanonische Liste — ein anderer Manifest-Fehler zöge
                          vorbei. Er beweist deshalb AUCH NICHT, dass `swift build`/`swift test` laufen: das
                          Test-Target zeigt auf `Tests/EchoelmusicTests`, 313 Dateien, die die iOS-Sim-Gates
                          nie kompilieren. Blockade entfernt ist nicht dasselbe wie Weg frei.
                          ⛔ **UND GENAU DAS IST EINEN COMMIT SPÄTER EINGETRETEN — der Satz „ein anderer
                          Manifest-Fehler zöge vorbei" war keine Floskel, sondern eine Vorhersage mit einer
                          Halbwertszeit von einem Lauf.** Der `b78adca`-Job-Log zeigt `incorrect argument
                          labels` = NULL Treffer (die Reihenfolge ist repariert) und an derselben Stelle
                          jetzt: `Package.swift:25:15: error: 'v18' is unavailable` · `note: 'v18' was
                          introduced in PackageDescription 6.0`. Zeile 1 sagt `swift-tools-version: 5.10`.
                          **Das Manifest parste nach #420 IMMER NOCH NICHT** — es gab ZWEI Fehler, und die
                          Überladungsauflösung zeigte immer nur den ersten. Repariert mit der String-Form
                          `.iOS("18.0")` (die dokumentierte Ausweichform für ein Deployment-Ziel, das die
                          Tools-Version noch nicht kennt); die Tools-Version NICHT gebumpt, weil 6.0 den
                          Default-Sprachmodus auf Swift 6 kippt und zusammen mit `-warnings-as-errors` aus
                          heutigen Nebenläufigkeits-Warnungen Build-Fehler macht — das ist eine eigene
                          Scheibe mit explizitem `.swiftLanguageMode(.v5)`, kein Beifang. Der Wächter hat
                          dafür eine ZWEITE Hälfte bekommen, die die REGEL kodiert statt meiner Reparatur:
                          ein `.vNN`-Fall muss zur Tools-Version passen. **Zwei Lehren, und die zweite ist
                          die allgemeinere:** (1) eine ehrliche Grenzen-Notiz ist keine Absolution — wenn
                          sie so schnell zutrifft, gehört die Lücke geschlossen, nicht nur benannt. (2) Bei
                          einem maskierten Fehlerkanal (`|| true`) beweist „der Fehler ist weg" NICHT „es
                          ist heil": man sieht immer nur den vordersten Fehler, und jede Reparatur legt den
                          nächsten frei. Der Log ist die Quelle, nicht das Gefühl),
                          davor „158" nach `LivelinessMovesTheStillnessGateTests.swift` (#419 — der zweite
                          Wächter derselben Woche über DEMSELBEN Regler, und der Grund, warum der erste
                          nicht genügte: #418 verdrahtete Liveliness an die zwei melodischen
                          Dichte-Entscheidungen, und BEIDE liegen hinter `!profile.sustained`. Acht der
                          sechzehn angebotenen Genres sind Flächen — `.selfObservation`, das
                          AUSGELIEFERTE STANDARD-GENRE, darunter. Für den Klang, den ein Erstnutzer hört,
                          hat der Regler also weiterhin nichts getan. #418 hat das im eigenen Kopf
                          festgehalten statt es zu verschweigen; dieser Wächter ist die Fortsetzung.
                          Auf einer Fläche sitzt die Bewegung nicht in der Notendichte, sondern in
                          `heartbeatOnsets`: ein Erregungs-TOR (gehalten vs. pulsierend) und zwei
                          Schritt-Stufen darüber. Diese drei Literale gehen jetzt durch dieselbe
                          `densityThreshold`-Form wie #418, mit einer KLEINEREN Spanne (0,2 statt 0,3) —
                          und diese Verkleinerung ist eine Founder-Doktrin, keine Geschmacksfrage: auf dem
                          melodischen Pfad entscheidet der Regler, wie DICHT eine schon bewegte Textur
                          gefüllt wird, hier entscheidet er, ob die Fläche ÜBERHAUPT sich bewegt. Der
                          2026-07-09-Ruf „Flächen still" ist das, was der Founder an den meditativen
                          Genres mochte. Seine wichtigste Hälfte ist deshalb der GEWISCHTE Test, dass ein
                          RUHENDER Körper unter KEINER Reglerstellung pulsiert — ein handgeschriebenes
                          Paar hätte eine spätere Spannen-Änderung bestanden, die genau das bricht. Die
                          zweite ist die Bit-Identität ALLER DREI Literale bei 0,5, die dritte ein
                          Quelltext-Scan über alle SECHS Aufrufstellen, der den defaultierten Parameter
                          erst verdient: ein Aufrufer, der still die Neutralstellung nimmt, wäre der
                          #418-Defekt eine Funktion tiefer und im Diff unsichtbar. ⚠️ Was er NICHT kann:
                          „klingt es besser" und „ist 0,2 die richtige Reise" sind Hörproben, und die
                          Fixtur-Bandbreite ist eng — deshalb rechnet der Take-Test `busy` aus
                          `BioComposer.musicalState` NEU und behauptet das Band ZUERST, sonst könnte eine
                          spätere Änderung der Erregungs-Arithmetik ihn grün lassen, ohne etwas zu
                          beweisen),
                          davor „157" nach `SmoothingStepsTheFrameGapNotThePollRateTests.swift` (#336 — der
                          erste Wächter in dieser Kette über einem Pfad, den HEUTE NIEMAND ERREICHT, und der
                          das im eigenen Kopf als erstes aufschreibt: `ModRoute.smoothingTau` hat den Default
                          0, die ausgelieferte Matrix ist leer, und in `Sources/` gibt es keinen Schreiber —
                          die Glättung, deren Schrittweite hier korrigiert wird, läuft in keinem heutigen
                          Take. Er entsteht trotzdem, weil #136 `ModRoute` eine Oberfläche geben wird und
                          JEDER dort eingestellte Slew sonst zehnfach zu langsam gewesen wäre: der alte Code
                          reichte eine KONSTANTE `tickSeconds = 0.1` an `BioNormalizer.alpha` weiter, während
                          die Frames mit ~1 Hz ankommen (dieselbe Poll-vs-Anwendungsrate-Verwechslung, die
                          in CLAUDE.md schon #315/#332/#336 erzeugt hat — dies ist die dritte Stelle). Seine
                          lehrreichste Hälfte ist nicht der Normalfall, sondern die drei Ränder: der ERSTE
                          Frame hat keinen Vorgänger und muss auf die nominale Periode fallen statt auf 0
                          (ein `dt` von 0 gibt `alpha` = 0 und friert die Route für immer ein), ein
                          rückwärts laufender oder doppelter Stempel darf kein nicht-positives `dt` geben,
                          und eine echte Lücke (App im Hintergrund) wird bei 5 s GEDECKELT statt befolgt —
                          sonst springt der erste Frame nach dem Aufwachen auf den Rohwert und macht aus der
                          Glättung einen Sprung. Dazu ein Quelltext-Scan, der der BINDUNG folgt statt der
                          Zeile (#413-Falle) und verlangt, dass keine Konstante mehr an `alpha` geht.
                          ⚠️ Was er NICHT kann: hörbar belegen, dass die Slew-Zeit jetzt stimmt — dafür
                          braucht es die #136-Oberfläche und ein Ohr. Er misst die ARITHMETIK, nicht den
                          Klang, und sagt das in beiden Dateien),
                          davor „156" nach `LivelinessReachesTheDensityDecisionTests.swift` (#418 — der
                          erste Wächter in dieser Kette über einem Regler, der NICHTS TAT: drei Schreiber
                          (Mood-Knopf, Mood-Pad-Zug, `WeatherMood.blend`), null erreichbare Leser, und
                          fünfzehn ausgelieferte Mood-Presets mit Werten von 0,05 bis 0,92, die sich alle
                          gleich verhielten. Seine wichtigste Hälfte ist deshalb NICHT die reine Funktion,
                          sondern der Sweep über `MusicStyle.offered`, der verlangt, dass zwei
                          Liveliness-Werte bei sonst identischem Körper, Genre und Seed VERSCHIEDENE Takes
                          ergeben — ein korrekter Kern ohne erreichbaren Aufrufer wäre genau derselbe
                          Defekt mit mehr Schritten. Die zweite Hälfte ist der Bit-Identitäts-Test bei 0,5
                          (dem `MoodProfile`-Default), weil hier zum ersten Mal in dieser Kette
                          AUSGELIEFERTER KLANG geändert wird und jeder, der den Regler nie anfasst, exakt
                          den heutigen Take behalten muss. Was er NICHT kann: „klingt es besser" — das ist
                          eine Hörprobe, und der Spann-Wert (±0,15 auf der busy-Achse) ist bewusst als EINE
                          Zeile zum Ändern gebaut, nicht als eingestellter Wert.
                          ⛔ **UND SEINE ERSTE FASSUNG WAR ROT AUF DEM CODE, DEN SIE SCHÜTZTE — durch ein
                          Gesetz, das in DREI Dateien dieses Repos steht und in einem brandneuen Kommentar
                          trotzdem RÜCKWÄRTS zitiert wurde.** Der NaN-Test verlangte `isFinite`; die Funktion
                          benutzte `clamp01`, also `min(max(x, 0), 1)` — genau die NaN-DURCHLÄSSIGE
                          Argument-Reihenfolge, vor der CLAUDE.md, `FloatingPointClamp.swift` und der
                          `genreAnchorCount`-Wächter ACHTZIG ZEILEN ÜBER `clamp01` in derselben Datei warnen.
                          Der Kommentar behauptete das Gegenteil („mit NaN zuerst gibt 0"). Nicht-endlich
                          liest jetzt als NEUTRALE 0,5, nicht als 0: `clamped(to:)` bildet NaN auf die UNTERE
                          Grenze ab, ein schlechter Wetter-Wert hätte also jeden Take still ausgedünnt.
                          **Lehre, und sie unterscheidet sich von „Zahl nachführen": ein dreifach
                          dokumentiertes Gesetz schützt nicht davor, es rückwärts zu zitieren — was schützt,
                          ist der Test, der es ausrechnet.** Dazu drei engere Fassungen aus derselben
                          Nachlese: die Schranke gilt für das RASTER, nicht für den Take (die verdoppelten
                          Arp-Anschläge verschieben jede spätere RNG-Ziehung, und der Beat wird NACH der
                          Melodie gezogen); der Puls-Aufrufer bekam einen ZWEITEN Körper, weil der erste
                          `busy`-Wert unter seinem ganzen Band lag und die Hälfte nur per Quelltext-Scan
                          gedeckt war; und der Scan folgt jetzt der BINDUNG statt der Zeile — dieselbe
                          #413-Falle, eine Datei weiter),
                          davor „155" nach `TheGenerateLineExplainsItsNoteCountTests.swift` (#413 — der
                          erste Wächter in dieser Kette über einer BREADCRUMB statt über einem Verhalten
                          oder einer Anzeige, und deshalb der erste, dessen beide Hälften Quelltext-Scans
                          sind und der das im eigenen Kopf als Grenze aufschreibt statt es zu verschweigen.
                          Er prüft, dass die `generate[…]`-Zeile alle FÜNF Dichte-Treiber nennt (Genre ·
                          lebender Frame · `busy` · Tempo-Ausdünnung · Stimmungs-Lebendigkeit — die
                          fünfte kam mit #418 zurück, siehe den ⛔-Block weiter unten) und dass `busy` aus
                          `BioComposer.musicalState` mit demselben `input` neu gerechnet wird, das der
                          Komponist bekam — eine zweite Herleitung wäre eine Zahl, die vom Klang abweichen
                          und im Log trotzdem maßgeblich aussehen kann. Was er NICHT kann und was deshalb
                          im Dateikopf steht: dass die Zeile das Gerät erreicht (Geräte-Lesung) und dass
                          das gedruckte `busy` GLEICH dem ist, das `compose` benutzt hat — das gilt durch
                          Konstruktion, und Konstruktion ist genau das, was eine spätere Änderung bricht.
                          ⛔ **Und seine erste Fassung wäre auf KORREKTEM Code rot gewesen** — der
                          Concurrency-Reviewer hat es gefunden, ich habe es nachgeprüft: sie behauptete
                          alle fünf Feldnamen auf der Breadcrumb-ZEILE, `codeLines` hält aber PHYSISCHE
                          Zeilen, und die Quelle hebt das Literal absichtlich in eine eigene
                          `densityText`-Anweisung eine Zeile darüber — genau der Hoist, den der
                          Quellkommentar verteidigt, weil das Einfalten in ein Literal mit schon zehn
                          Interpolationen die #287-Form ist, die das blockierende Gate rot gemacht hat.
                          Die Annahme des Scans („eine Anweisung = eine Zeile") wurde also von der
                          Reparatur widerlegt, zu deren Schutz er geschrieben war. **Lehre, und sie ist
                          nicht „Scan verbreitern": ein Quelltext-Scan muss der BINDUNG folgen, nicht der
                          Zeile, sobald das Gemessene gehoben werden darf — und dieses Repo hebt
                          absichtlich und wiederholt.** Jetzt zwei verkettete Hälften: die Feldnamen auf
                          dem Literal, plus die Forderung, dass die Breadcrumb `densityText` überhaupt
                          interpoliert — ohne die zweite wäre ein perfekt gebautes Literal grün, das
                          nirgends im Log ankommt. ⛔ **Und ein FÜNFTES Feld, `live=` (Stimmungs-
                          Lebendigkeit), stand in der ersten Fassung und ist wieder raus** — der
                          Code-Reviewer fand es, ich habe es nachgezählt: JEDER Lesezugriff auf
                          `mood.liveliness` im Komponisten liegt entweder im aufruferlosen
                          `ambientMelody` oder in `if profile.leadDensity > 0`
                          (`BioComposer.swift:2422…2544`), und ALLE 33 ausgelieferten Genres setzen
                          `leadDensity: 0.0` — eine Invariante, die `LeadRoleAbsenceTests` im selben
                          blockierenden Bundle längst festnagelt. Das war die DRITTE falsche Fassung
                          desselben Aufzählungspunktes und die subtilste: kein veralteter Name, sondern
                          ein LEBENDER Wert auf einem TOTEN Pfad, in genau der Zeile, die gegen
                          Teilantworten gebaut wurde. **Der größere Befund dahinter ist NICHT
                          mitrepariert und als eigene Aufgabe registriert:** der Liveliness-Regler im
                          Mood-Panel, der Mood-Pad-Zug und `WeatherMood.blend` SCHREIBEN alle drei
                          `mood.liveliness` — drei Schreiber, null erreichbare Leser, also ein lügendes
                          Control im #135-Sinn und ein Loch in der #349-Behauptung „Wetter ist hörbar".
                          ⛔ **UND `live=` IST NOCH AM SELBEN TAG WIEDER EINGEZOGEN, weil #418 ihm einen
                          Leser gegeben hat** — dreimal derselbe Aufzählungspunkt, dreimal richtig zum
                          Zeitpunkt des Schreibens. **Die Lehre ist deshalb nicht „genauer hinsehen",
                          sondern: eine Treiber-Liste gilt nur für den Commit, in dem sie steht — wer
                          einem toten Wert einen Leser gibt, muss zur Diagnose zurücklaufen, die ihn tot
                          erklärt hat.** Mit einer Grenze, die BLEIBT und in beiden Dateien steht: beide
                          Entscheidungen liegen hinter `!sustained`, und 8 der 16 angebotenen Genres —
                          das ausgelieferte Standard-Genre `.selfObservation` eingeschlossen — erreichen
                          sie nie. Für das Genre, das ein Erstnutzer hört, ist der Regler weiter inert
                          (#419)),
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
                          ungeprüft**. HUNDERTFÜNFUNDSECHZIG FRÜHERE Stände in zwölf Tagen (⛔ hier stand „sechs“, und die Zahl war nur mitgeschoben: der frühere Text sagte „fünf Tagen“ für 07-29…08-01, also VIER — der Off-by-one wurde beim Erhöhen geerbt statt geprüft. 07-29 bis 08-02 sind fünf; mit dem 08-07-Stand sind es zehn, und dieser Absatz hat die Spanne diesmal MIT der Zahl nachgeführt statt sie stehen zu lassen) — der aktuelle Wert 206 ist hier NICHT mitgezählt (⛔ und hier stand „192“, während der Kopf des Absatzes schon 193 sagte UND die 192 in der Liste FEHLTE: der #475-Commit hat den Kopf erhöht und BEIDE Buchhaltungs-Stellen liegen lassen. #474 trägt 193 und 192 nach. **Eine Zahl erhöhen ist drei Änderungen** — Kopf, Liste, dieser Satz —, und wer nur die erste macht, hinterlässt einen Absatz, der sich selbst widerspricht) (⛔ und der Sprung ist 177→179, nicht 177→178: dieser Commit legt ZWEI Dateien an, eine Definition und ihren Wächter. Die 178 war nie ein Stand und steht deshalb NICHT in der Liste — wer die Kette auf Lückenlosigkeit prüft, prüft das Falsche) (⛔ hier stand „176“, während der Kopf dieses Absatzes schon 177 sagte UND 176 zur ersten Zahl der Liste geworden war — der Satz widersprach sich also selbst, in dem Absatz, dessen einziger Zweck das Mitzählen ist. Beim Voranstellen einer Zahl gehört DIESER Satz mit nachgeführt), anders als im Sources-Absatz oben (⛔ **und diese Liste trägt seit #490 ZWEI GLEICHE Zahlen hintereinander — 203·203 — und das ist KEIN Tippfehler, sondern der Tausch:** derselbe Commit löscht `HeaderSpectrumIsALeafTests.swift` und legt `TheHeaderShowsTheLoopTests.swift` an. Wer die Kette auf Lückenlosigkeit prüft, darf eine Dublette hier also nicht wegkürzen — sie ist die einzige Spur eines Vorgangs, den die Zahl selbst nicht zeigen kann. Dieselbe Form wie #373→#374, wo eine Löschung plus eine Anlage die 108 stehen ließ, nur dass die Kette DORT keine Dublette trägt, weil der Stand damals nicht mitgezählt wurde: **die Historie kannte den Fall schon einmal und hat ihn unsichtbar verbucht**) 205·204·203·203·202·201·200·199·198·197·196·195·194·193·192·191·190·189·188·187·186·185·184·183·182·181·180·179·177·176·175·174·173·172·171·170·169·168·167·166·165·164·163·162·161·160·159·158·157·156·155·154·153·152·151·150·149·148·147·146·145·144·143·142·141·140·139·138·137·136·135·134·133·132·131·130·129·128·127·126·125·124·123·122·121·120·119·118·117·116·115·114·113·112·111·110·109·108·107·106·105·104·103·102·101·100·99·98·97·96·95·94·93·92·91·90·89·88·87·86·85·84·83·82·81·80·79·78·77·76·75·74·73·72·71·70·69·68·67·66·65·64·63·62·61·60·59·58·57·56·55·54·53·52·51·50·49·48·47·46·45·41·39·30·21 — bei der
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

## KEY TESTS (314 files under `Tests/EchoelmusicTests/` — `git ls-files` re-run 2026-08-07 nach #469)

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
- ⛔ **ZWEI ROTS, DIE GLEICH AUSSEHEN — und solange #396 lebt, ist das die einzige Unterscheidung, die zählt.** `Echoelmusic CI/CD Pipeline` meldet auf JEDEM Push `failure`, also sagt die Conclusion allein NICHTS. Im Job-Log stehen die beiden Fälle EINE Zeile auseinander und nirgendwo sonst: **`** TEST EXECUTE FAILED **` = #396** (kompiliert, Host stirbt beim Ausführen, harmlos) · **`** TEST BUILD FAILED **` = der BUILD ist gestorben** — ⛔ hier stand „= DEIN Commit", und das ist eine Fassung zu kurz, siehe den Punkt direkt darunter. Umgekehrt ist **`▸ Test build Succeeded`** der einzige Beleg, dass eine neue Testdatei überhaupt baut. Belegt am 2026-08-07 an `f489a6e`: `ASnappedValueIsLegalForItsRowTests.swift` fehlte `@testable import Echoelmusic`, neun „cannot find 'ScrubPrecision' in scope", Bundle tot — bei einer Conclusion, die von #396 nicht zu unterscheiden war. **Wer die Conclusion liest und aufhört, hat nichts geprüft.**
- ⛔ **UND DAS WAREN NICHT ZWEI ROTS, SONDERN DREI — der dritte sieht exakt aus wie der zweite und ist NICHT dein Commit.** `** TEST BUILD FAILED **` heißt „der Build ist gestorben", nicht „deine Datei kompiliert nicht". Belegt am 2026-08-07 an `998af71` (Lauf 31186349705, Job 92891930582, ganzer Job-Log 689 Zeilen): **4 `error:`-Zeilen, davon NULL mit einer Datei unter `Sources/` oder `Tests/`** — alle vier nennen `/Applications/Xcode_26.2.app/…/iPhoneSimulator26.2.sdk/…/_StoreKit_SwiftUI.framework/Modules/module.modulemap` gegen ein `.pcm` in `DerivedData/ModuleCache.noindex`: *„has been modified since the module file … was built: mtime changed"*. **Der Diskriminator ist deshalb EINE Frage: nennt IRGENDEINE `error:`-Zeile eine Datei aus dem Repo?** Null von vier → Infrastruktur. Die Antwort darauf ist ein erneuter Lauf, keine Code-Änderung — und wer stattdessen die eigene Scheibe debuggt, debuggt korrekten Code.
- ⭐ **Und es ist ein FLAKE, kein vergifteter Cache — gemessen, nicht vermutet, und die naheliegende Diagnose war meine erste.** Gegen den unmittelbar davor liegenden Commit derselben Reihe verglichen (`1118b55`, Lauf 31184026431, Job 92885354981): **gleiches Runner-Image `20260707.563`, gleicher Cache-Schlüssel `macOS-spm-<hash>-iPhone 17`, in BEIDEN Läufen „Cache restored from key" + „Cache restored successfully"** — und der eine druckt `▸ Test build Succeeded`, der andere zwei Minuten später `** TEST BUILD FAILED **`. Identische Eingaben, verschiedenes Ergebnis. **Und der Beweis kommt vom Commit DANACH:** `b06b8ca` (Lauf 31186573809) ist eine reine Prosa-Änderung ÜBER demselben Baum — dieselben drei `Tests/CISmoke`-Dateien, die `998af71` angelegt hatte — und sein „Build for Testing" ist `success`. Der Inhalt, den der rote Lauf angeblich nicht kompilieren konnte, kompiliert. **Ein `TEST BUILD FAILED` ist also erst dann eine Aussage über deinen Commit, wenn eine `error:`-Zeile eine Repo-Datei nennt** — sonst ist der billigste nächste Schritt ein leerer Folge-Commit, nicht eine Stunde Fehlersuche.
- ⚠️ **Der LATENTE Defekt daneben ist echt und founder-gated (#478):** `ci.yml:127` und `:349` cachen `~/Library/Developer/Xcode/DerivedData` — dort liegt `ModuleCache.noindex` — unter einem Schlüssel, der NUR `Package.swift`/`Package.resolved` hasht, also nichts über die Xcode- oder SDK-Version. Ein `.pcm`, das gegen ein älteres SDK gebaut wurde, wird damit auf einen Runner mit neuerem SDK zurückgespielt, und die Fehlanpassung ist STÄNDIG vorhanden: die zwei Zeitstempel derselben Meldung sind **`.pcm` 2026-07-20T05:58:14Z** gegen **modulemap 2026-07-28T05:57:08Z**, acht Tage auseinander — und BEIDE Läufe oben haben genau dieses `.pcm` zurückgespielt. Nur einer ist darüber gestolpert. Die Reparatur wäre eine Zeile (Xcode-/SDK-Version in den Cache-Schlüssel), liegt aber in `.github/workflows/**` → BERICHTEN, nicht editieren.
- ⛔ **Und meine eigene erste Lesung dieser Sache war falsch, in genau der Datei, die man dafür aufschlägt:** ich hatte notiert, `ci.yml` cache „nur `~/.swiftpm` und `.build`, DerivedData NICHT" — und daraus geschlossen, ein Cache könne über Läufe hinweg gar nicht vergiften. Zeile 127 sagt das Gegenteil, und sie stand die ganze Zeit da. Die SCHLUSSFOLGERUNG (nicht mein Commit) überlebt, die BEGRÜNDUNG nicht. **Lehre in der Familie dieses Absatzes: wer aus einer Konfigurationsdatei argumentiert, liest die Zeile, statt sich an sie zu erinnern** — dieselbe Klasse wie das abgelaufene `EchoelModalBank`-Rezept, nur in einer Datei, die ich für zu klein zum Nachschlagen hielt.
- ⭐ **UND #396 IST EIN TEILWEISER HOST-TOD, NICHT EIN TOTALER — das ändert, was ein Zyklus über einen neuen Wächter behaupten darf.** Der Log zeigt `NSMachErrorDomain Code=-308 "(ipc/mig) server died"` für EINEN Simulator-Clone, während **Clone 1 weiterläuft und einzelne `passed`-Zeilen druckt**. (⛔ **DIE RÜCKNAHME WAR SELBST FALSCH, und das ist die dritte Fassung dieses Satzes.** Sie lautete: „die erste Fassung schrieb ‚auf **Clone 2**' … nennt die Nummer des toten aber nirgends, die Ziffer war geraten". Sie steht sehr wohl im Log, nur nicht in der Fehlerzeile: der Umgebungs-Dump des gescheiterten Launches trägt `"RUN_DESTINATION_DEVICE_NAME" = "Clone 2 of iPhone 17"`, direkt über dem `Code=-308`. Nachgeschlagen an Lauf `31153418893` (`4787b8b`). **Clone 2 stirbt, Clone 1 läuft weiter** — die ERSTE Fassung war richtig, meine Korrektur hat eine belegte Ziffer zu einer geratenen erklärt, weil ich den Ausschnitt gelesen habe statt den Log. Lehre, verschieden von der Stale-Zahl-Lehre: **eine Rücknahme ist auch eine Behauptung und braucht dieselbe Messung wie das, was sie zurücknimmt** — „steht nirgends" ist eine Aussage über den GANZEN Log, nicht über die Zeilen, die man gerade vor sich hat.) Belegt am 2026-08-07 an `a5aafe2`: alle 10 Fälle von `OneDefinitionOfAParameterRangeTests` und alle 6 des Nachbarn stehen dort namentlich als `passed`, bei `** TEST EXECUTE FAILED **` als Gesamtverdikt. **Also ist „lief grün“ für einen neuen Wächter belegbar — man liest die Testnamen im Job-Log, nicht die Conclusion und nicht nur `▸ Test build Succeeded`.** Die schwächere Formulierung („kompiliert nachweislich, Ausführung durch #396 unbelegt“) war bis hierher richtig und ist ab jetzt zu schwach, wenn die Namen im Log stehen.
- ⛔ **UND DIE UMKEHRUNG DIESES GESETZES GILT NICHT — das fehlte in der ersten Fassung, und es ist die Hälfte, die eine Sitzung wirklich braucht.** Ein Testname IM Log beweist „gelaufen"; sein FEHLEN beweist gar nichts. Der Log trägt nur die Ausgabe, die der ÜBERLEBENDE Clone vor dem Tod des anderen noch geleert hat, und das ist ein Bruchteil des Bundles. Gemessen am selben Tag, `Tests/CISmoke` = **182 Dateien**: `5584ffd` (Job 92762010894, `original_length` 5263 Zeilen, also der GANZE Log, keine Kürzung) druckte **28 Suiten / 166 `passed`**, alle auf `Clone 1`; `4be555e` (Lauf 31144230149) druckte **19 Suiten** — DERSELBE Zweig, DIESELBE Scheibe, verschiedene Teilmengen. Der neue Wächter `AHeldFrameCannotResetTheHoldTests` steht in KEINEM der beiden, obwohl er in beiden nachweislich KOMPILIERT (`▸ Test build Succeeded`). **Die Zuteilung ist nicht deterministisch, also ist Neu-Laufen eine Lotterie und kein Beweisverfahren.** Ehrliche Formulierung für einen Wächter ohne Treffer: „kompiliert nachweislich, Ausführung unbelegt" — nicht „grün", nicht „rot". ⚠️ Und der Erkennungs-Marker aus dem Absatz darüber ist NICHT immer da: `5584ffd` hat `** TEST EXECUTE FAILED **`, aber **null** `Code=-308` und **null** `server died` (`4be555e` hat beide). Der verlässliche Diskriminator bleibt `TEST EXECUTE FAILED` gegen `TEST BUILD FAILED`; die Mach-Zeile ist ein Bonus, kein Kriterium. Das ist die schärfste bisherige Fassung von #445.
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
