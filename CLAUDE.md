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

⛔ **Was hier stand und 2026-07-27 gestrichen wurde, weil es nichts davon (mehr) gibt:** „Beat Maker (16-step × 8-track sequencer + sampler)" — Drums, Pad-Stimmen, Sample-Import und die Sample-Bibliothek sind mit #166/#167 gelöscht, der Step-Grid überlebt nur als Takt-Clock · „Multi-track Recorder (mic over beats)" — **KORRIGIERT 2026-07-31: „nie gebaut" war falsch.** `MultiTrackRecorder` existiert und wird unbedingt konstruiert (`AudioEngine.swift:345` (Stand 2026-08-14; die Voice-Woche hat sie verschoben)); durchgereicht wird es nur hinter `FeatureFlags.audioLaneRecording` (`EchoelmusicApp.swift:1179` (Stand 2026-08-14)), und dieser Key wird NIE an `UserDefaults.register(defaults:)` übergeben (registriert sind nur `multiRoll`, `voiceKindRouting`, `instrumentHome`) — löst also zu `false` auf. Ehrlich ist: **gebaut, flag-gated AUS, türlos (#204)**. Der Unterschied ist nicht kosmetisch: „nie gebaut" lässt eine Session neu bauen, was schon da ist · „Video Capture & Trim" — **halb**: der SCHNITT ging mit #121 Slice 3, die AUFNAHME nicht. `VisualRecorder` wird in `EchoelmusicApp.swift:181` konstruiert, die Aufnahmetaste sitzt im erreichbaren `FloatingVisualWindow`, und `videoPanel` → `VideoLibraryPanelContent` ist die erreichbare Bibliothek mit mp4-Export. (Die REC-Taste im `showVisual`-Vollbild ist die TOTE Zweitkopie — nicht mit ihr verwechseln.) · „RTMP Live Stream" — nie verlinkt (`BroadcastPublisher` ist ein Compile-Guard-Gerüst). **MPE** bleibt aus dem I/O-Satz gestrichen — aber ⛔ **die BEGRÜNDUNG, die hier stand („`mpeEnabled`/`expressionEnabled` haben seit dem Tools-Grid-Removal keinen Schreiber"), ist mit #713 hinfällig**: beide sind jetzt persistiert und haben zwei Schalter in der Routing-Fläche. Wahr ist seither eine ANDERE Hälfte: **MPE OUT ist real und schaltbar, MPE IN nicht** (#548 — `MIDIBusPublisher` parst MPE-Verkehr, unterscheidet aber keine Zonen, und `apply(controller:)` läuft für Slide/Air/Pressure in ein `break`). Ein „MPE"-Satz im I/O-Set würde also weiterhin die Hälfte behaupten, die fehlt. Diese Zeile ist die Identitäts-Zeile der Datei — sie muss der Wahrheit folgen, sonst plant die nächste Session aus ihr heraus Features, deren Fundament abgerissen ist.

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
- **Architecture (audited 2026-06-09 — `scratchpads/ARCHITECTURE_AUDIT_2026-06-09.md`):** `EngineBus` = `@MainActor @Observable` control plane (snapshots) + lock-free `SPSCQueue`. 3 topics — `bioFrames` / `controllerEvents` / `bioEvents`. **Bio flows over the `latestBio`/`latestBioEvent` snapshot; the SPSC queue is drained only for `controllerEvents` (MIDI).** `bioFrames`/`bioEvents` queues are reserved/undrained (snapshot is the correct path for slow bio). Modules couple only via the bus. ⛔ **Diese Zeile sagte „(10 Hz poll)" und genau diese Zahl hat #315, #332 und #336 erzeugt — drei Zeitkonstanten, die aus ihr abgeleitet und dadurch um das 10- bis 60-Fache daneben lagen. Der POLL ist 10 Hz, die ANWENDUNGSRATE ist ~1 Hz**, weil jeder Verbraucher auf `frame.timestamp` dedupliziert und jeder verdrahtete Publisher mit ~1 Hz sendet (`CameraRPPGBioPublisher` `tick % 10` in einer 0,1-s-Schleife, Polar 1 s, Simulator 1 s, HealthKit 500-ms-Poll hinter einem 4–5-s-Sensor). ⛔ **Und die Zahl steht seit #577 nicht mehr als Literal im Code, sondern als `CameraRPPGBioPublisher.activeTickSeconds`** — die Schleife kann auf `heldTickSeconds` (0,5 s) zurückfallen, ABER nur solange iOS die Kamera hält und seit sechs Sekunden nichts ankommt, also in einem Zustand, in dem der Publish-Pfad eine Zeile früher schon an `inboundRateEMA` schließt. **Die ~1-Hz-Decke gilt damit unverändert für jeden Tick, der überhaupt veröffentlichen kann.** Der Wächter wurde dabei rot und ist mit-repariert: seine Verankerung war `milliseconds(100)`, also eine SCHREIBWEISE statt des Gesetzes; sie zeigt jetzt auf die benannte Konstante und zusätzlich auf die Bedingung des Rückfalls. **Für jede Zeitkonstante gilt die 1 Hz, nicht die 10** — der Poll ist nur die Obergrenze, die ein schnellerer Publisher erreichen könnte. Ein Wächter im blockierenden Bundle (`Tests/CISmoke/BioApplyRateIsTheDedupedRateTests.swift`) hält die Publisher-Kadenz und die Deduplizierung fest, damit diese Zeile nicht wieder still altert. ⛔ **UND ES GIBT EINE VIERTE UND FÜNFTE AUFLAGE, in einer Richtung, die dieser Absatz bisher nicht abdeckte** (gefunden in der #459-Nachlese, 2026-08-07, beide in `CameraAnalyzer.swift`): der `beatTimes`-Doc-Kommentar und danach der `rrSegments`-Doc-Kommentar schrieben „wird etwa einmal pro Sekunde neu geschrieben". Die ~1 Hz ist die **LESE**-Rate des Publishers; **geschrieben** werden beide Arrays in `detectPeaks`, das hinter `peakTick % 4` auf einem 15-fps-Feed sitzt — **~3,75 Hz**. Der Fehler ist also nicht Poll-gegen-Anwendung derselben Größe, sondern **SCHREIB-Rate gegen LESE-Rate zweier verschiedener Größen**, und er ist in der SICHEREN Richtung passiert (die reale Rate ist höher, die `@ObservationIgnored`-Begründung wird damit stärker) — weshalb nichts ihn je rot gemacht hätte. **Regel: eine Rate gehört zu genau EINER Operation; wer „~1 Hz" aus einem Nachbar-Kommentar übernimmt, übernimmt zuerst, WELCHE Operation dort gemeint war.**
- **Live pipeline:** HealthKit + **camera rPPG (live, locks on device)** + Demo → bio snapshot. (**Universal BLE HR (0x180D) = GEBAUT + VERDRAHTET**, aber **KORRIGIERT 2026-07-26 — die Tür ist NICHT die Patchbay.** Die alte Fassung hier behauptete, der Source-Port `blehrs.in` starte/stoppe `PolarH10BioPublisher` via `applyRouting` [`hasEnabledRoute(fromSource:"blehrs.in")`]. Das galt nur von B4 [2026-07-12] bis **BLE-3 [2026-07-15]**, das die Kopplung wieder entfernte: `applyRouting` war damit ein ZWEITER Lifecycle-Besitzer, der einen über die Pulse-Pille gestarteten Gurt bei JEDEM unbeteiligten Patchbay-Edit mitten in der Performance killte. **Heute hat der Gurt genau EINEN Besitzer: das Source-Dropdown der Pulse-Pille [`startBioSource`].** `blehrs.in` ist ein reiner Datenfluss-Port; `hasEnabledRoute(fromSource:)` hat **keinen Produktions-Aufrufer** — nicht daraus einen Start-Hook zurück-ableiten. Gerät-Verify wartet auf Gurt-Eintreffen [NEEDS-FOUNDER-VERIFY]. Deep Audit `scratchpads/DEEP_AUDIT_2026-07-12.md` ist an dieser Stelle ebenfalls überholt.) Pipeline weiter: bio snapshot → BioReactiveSynthVoice (EchoelDDSP; **silent until user-armed** — und „user-armed" war bis #277 eine Handlung OHNE Bedienelement: `arm()` hatte null Produktions-Aufrufer, `isArmed` konnte nie `true` werden, jeder Atem-Onset lief in `guard isArmed` und wurde verworfen. Der Satz war die ganze Zeit zutreffend und beschrieb trotzdem eine Tür, die es nicht gab; seit #277 ist der Schalter „Body voice" im `bioPanel`) + OSCSender (`/echoelmusic/bio/*`) + **ADMOSCSender** (`/adm/obj/{n}/*` immersive object out). CoreMIDI-Noteneingang → controllerEvents → EINE monophone Performer-Stimme (Noten · Pitch-Bend · Vorrang vor der Atem-Hüllkurve). ⛔ **Hier stand „CoreMIDI **MPE** → controllerEvents → synth **notes**" und beide fett gesetzten Wörter waren falsch (#548).** Gemessen: `MIDIBusPublisher` PARST MPE-Verkehr, unterscheidet aber keine Zonen — sein eigener Kopf sagt „MPE master vs. member channel disambiguation, RPN 6,6 zone detection, and channelPressure are intentionally NOT wired in this first cycle". Der Verbraucher `BioReactiveSynthVoice.apply(controller:)` behandelt `.noteOn`/`.noteOff`/`.pitchBend` und läuft für `.slide` (CC 74 Timbre), `.airCC` und `.channelPressure` in **ein einziges `break`** — genau die drei Dimensionen, die MPE erst zu MPE machen — und liest `event.channel` **nirgends**, also dort, wo ein Member-Kanal ankäme. „notes" im Plural war ebenfalls unerreichbar: `heldByController` ist ein einzelner `Bool`, `playNote` setzt eine `synth.frequency`. ⭐ **Die Wortwahl ist von `docs/faq.html` übernommen, nicht neu erfunden** — vier andere Flächen (FAQ, `architecture.html`, App-Store-Text, `ContentPipeline/CLAIMS.md`) waren längst ehrlich; **diese Zeile war der einzige Ausreißer**, und sie ist Zeile 39 der Datei, die jede Session zuerst liest. Eine fünfte Schreibweise wäre #416. Wächter: `Tests/CISmoke/TheMPEDimensionsReachNoVoiceTests.swift` — er pinnt den **VERBRAUCHER**, nicht diese Prosa (ein Negativ-Scan auf CLAUDE.md träfe die ⛔-Blöcke, in denen die Datei absichtlich zurückgenommene Behauptungen zitiert — #491). Er wird rot an dem Tag, an dem jemand einen echten MPE-Empfänger baut, also genau dann, wenn diese Zeile zurückgeändert werden MUSS. BioEventGraph → breath/motion onsets. ⛔ **Hier stand „ModulationEngine wired (bio→tempo)" — vier Wörter, die eine LEBENDE Fähigkeit behaupten, und gemessen 2026-08-12 (#541) ist es ein Sink ohne Erzeuger.** Wahr ist die Maschine: `ModulationEngine` wird beim App-Start konstruiert, `start(subscribing: bus)` läuft, die 100-ms-Schleife tickt, und das Tempo-Ziel ist registriert (`EchoelmusicApp`, `ModDestinationKey.tempo` → `beatPlayer.pattern.glideTempo`, hinter dem globalen BPM-Lock und oktav-gefaltet). Was fehlt, ist die ROUTE: **die Default-Matrix ist LEER** — die Datei sagt das selbst zweimal — und `git grep -n "\bModRoute(" -- Sources` liefert **genau EINEN** Treffer, den `LossyDecoded`-Decoder in `ModulationMatrix.swift` selbst. ⚠️ **Die Wortgrenze im Befehl ist nicht Kosmetik:** ohne sie trifft er zusätzlich `FXModRoute(` in `EchoelFXView` — ein anderer Typ eines anderen Systems — und druckt zwei Zeilen neben einer Prosa, die „einen" sagt. Genau der `EchoelModalBank`-Fehler: ein zitiertes Rezept, das man ausführt und das der Behauptung widerspricht, wird als Widerspruch gelesen, nicht als ungenauer Befehl. **Null Produktions-Konstruktionsstellen, keine erreichbare Matrix-Fläche.** Ein von einem älteren Build persistiertes Dokument WÜRDE weiterhin das Tempo ziehen (`load()` gewinnt über die leere Default-Matrix) — genau die #527-Lage der Audio-Spuren, und deshalb nicht abklemmen. Ehrlich ist: **verdrahtet, türlos, ohne Route wirkungslos.** Der Unterschied ist nicht kosmetisch: „wired (bio→tempo)" ist die Zeile, aus der eine Bio-Fläche oder ein Store-Text „der Körper steuert das Tempo" ableitet — dieselbe Über-Behauptung, die #496 auf dem FX-Panel zurücknehmen musste, nur eine Ebene weiter oben. Wächter: `Tests/CISmoke/TheTempoDestinationHasNoRouteTests.swift` — er verbietet das Verdrahten NICHT (#364) und nennt in seiner Fehlermeldung die Prosa, die dann mitzuziehen ist. **EchoelBeat ist TOT** (korrigiert 2026-07-27): velocity/accent, swing und Per-Pad-Sample-Import standen hier weiter als live, obwohl der Founder die Drums am 2026-07-26 entfernt hat (#166). `BeatPlayer.attach(to:)` hängt nur noch `previewVoice` ein — kein Pad-Voice, kein `pattern.onStep`. Es kann heute KEIN Drum-Klang entstehen. **Der vollständige Abriss (#167) ist am 2026-07-31 FERTIG**: `DrumSynthVoice`, `LaneDrumKitVoice` und `DrumNoteMap` sind als Dateien gelöscht, ebenso `PhysicalVoiceRef.drums` und `LaneVoiceRack.kits`/`setDrumsInsert`. Die Enum-Cases `LaneVoiceKind.drums` / `TrackInstrument.drums` BLEIBEN. ⛔ **Die erste Fassung dieser Zeile begründete das mit „persistierte rawValues, ein unbekannter verwirft beim Decode die ganze Spur" — BEIDE Hälften sind falsch, und die Begründung stand gleichzeitig in vier Quelldateien.** `LaneVoiceKind` ist gar nicht `Codable` und erreicht nie die Platte (`Timeline.swift` sagt das selbst). `TrackInstrument` ist es, aber `TimelineLane`s Decoder wickelt ihn in `try? … ?? nil` — genau damit #167 überlebbar ist: ein unbekannter Case wird zu „kein eingebautes Instrument", die Spur mit Regionen, Clips, Mixer und Patch bleibt vollständig. Die WAHREN Gründe sind schwächer und stehen jetzt an den Cases selbst: `TrackInstrument.drums` löschen kostet einer Altspur ihre Instrument-WAHL (Founder sagte „erstmal"), `LaneVoiceKind.drums` ist ein toter Case ohne Produzenten, der eine eigene Entscheidung braucht. **Lehre: ein „NICHT löschen"-Kommentar mit falscher Begründung ist schlimmer als keiner — die nächste Session kann ihn nicht widerlegen.**
- **Vokal-Kette (Founder-Ask 2026-08-20) — WAS AUF SEINER STIMME LIEGT UND WAS NICHT (#700/#701):** **Monitoring + Autotune sitzen auf dem Monitorpfad** (`input → notchEQ → [voiceTunePitch] → monitorMixer`, beide `AVAudioUnit`-GRAPHknoten, kein Swift-DSP-Insert; Charakter-Presets #681 in derselben Tür `AudioInputPickerView`) — **Harmonizer und Granular NICHT.** Die zwei liegen in `EchoelFXChain`, und weder dieser Typ noch `EchoelHarmonizer`/`EchoelGranular` kommen in `Sources/Echoelmusic/Audio/` vor (vier `EchoelFXChain(`-Stellen: zwei Vorschauen in `FXCuratedLibrary` plus die zwei SYNTH-Stimmen). Sie bearbeiten die erzeugte MUSIK, nie den Sänger. Nach AUSSEN ist nichts über-behauptet — Store-Text, `ContentPipeline/CLAIMS.md` und `EchoelFXView`s Kopf sind zeilenweise geprüft und ehrlich. ⛔ **Neu ist nur der ORT, nicht der Befund:** `PLAN_VOCAL_CHAIN_2026-08-20.md`, `decisions.csv:398`, `VoicePitchCorrector.swift` und `EchoelGranular.swift` sagen es alle schon — diese Zeile ist die erste, die eine Sitzung zuerst liest. **Kette auf den Monitorpfad = V1b, nicht V1a** (`decisions.csv:398`: V1a = leere Pass-Through-AU; Mechanismus per #669 schon entschieden), beides hinter V0 = Geräteprobe des Monitor-Schalters. „Voice clone" ist eine offene Founder-Frage, kein Zustand. Wächter: `Tests/CISmoke/TheVocalChainStopsAtTheAutotuneTests.swift` (#364: er verbietet V1b NICHT; sein Kopf trägt die zwei Rücknahmen dieser Zeile — erfundenes SESSION_LOG-Zitat und der V1a-Namensdreher — damit sie nicht in der immer-geladenen Datei liegen).
- **Protected DSP triad (READ-ONLY, now implemented):** BioSignalDeconvolver (detrend·notch·validity), HilbertSensorMapper (1D→2D Hilbert curve), BioEventGraph (heartbeat/breath/motion detectors). Pure value types, SKILL.md contracts under `.claude/skills/`.
- **SDK:** iOS 18 deployment floor (Package.swift + project.yml + Resources/iOS/Info.plist synced). Xcode 26.2 in `testflight.yml`. App Group `group.com.echoelmusic`.
- **Root view (RE-FOCUS 2026-07-06B — founder: "die Leute brauchen gar keine Atemübung. Es geht um Performance und Entspannungssteigerung dadurch, dass sich die Musik mit dem Biofeedback generativ verändert"): the bio-generative INSTRUMENT is the app HOME.** This supersedes the same-day 2026-07-06A "Session is home" flip (the founder tested it and rejected the breathing-exercise framing within hours). `WorkspaceView` body = brand header (`topBar`) + `CompositionHeaderStrip` + `EchoelStudioView()` + `FloatingVisualWindow`. (⛔ Hier stand „persistent `TransportBar`“ — mit #456 am 2026-08-07 aufgelöst: die Leiste hielt seit #411 nur noch zwei Kinder, und der Founder hat beide per Screenshot-Pfeil in die Transport-Zeile des Instruments geschickt. Die Chrome ist zwei Leisten, nicht drei.) **The Session experiment (`SessionView`/`SessionEngine`/`SessionGuide`/`SessionClock`/`EntrainmentEngine`) stays in code, compiling, but NOTHING presents it** — do not re-add a Session door/card without a founder ask; equally, do not delete those files without one (they hold the tested flash-safety/latency/pacing laws, reusable for future bio-visual work). The product bar now: the generative MUSIC must sound organic/professional and the VISUAL must be part of the experience ("wow", contemplative) — quality work goes there, not into new surfaces.
- **Studio shell internals:** brand header (`topBar`) + `CompositionHeaderStrip` + `EchoelStudioView` (the instrument) + the floating immersive visual (`FloatingVisualWindow`, toggled from the header monitor). ⛔ **Was hier stand, war ab #411 halb und ab #456 ganz falsch — und es ist die Zeile, aus der eine Session die Chrome-Struktur liest:** „persistent `TransportBar` (Play/Stop + tempo-lock button + `TransportPositionView` loop/position leaf … der eine Tempo-Regler ist das kompakte `BodyTempoField` in der TransportBar-Chrome selbst (`WorkspaceView.swift:345`))“. Davon stimmt heute NICHTS mehr: Play/Stop ging mit #289 als `PlaybackToggleButton` ins Instrument, das Tempo-Feld mit #411 in `EchoelStudioView.startControlRow`, und mit #456 sind auch die letzten zwei Kinder — das „•••“-Überlaufmenü und `TransportPositionView` — dorthin gewandert; die Leiste ist gelöscht. Der EINE Tempo-Regler ist weiterhin genau einer, er sitzt nur im Instrument. **Und die Zeilennummer war der übliche Zusatzfehler** — dieselbe Lehre wie im Absatz über die Modal-Slots: eine zitierte Phrase überlebt eine Einfügung, eine Zeilennummer nicht. **The former 6-surface bottom bar (Arrange · Clips · Compose · Mix · Bio · Browse) is REMOVED from navigation** — **von den sechs ist nur noch EINE als Datei da: `BioSourceView`** (unerreichbar, aber restaurierbar). Die Liste, die hier stand („ClipView/ArrangementView/ChannelRackView/BioSourceView … reversible by restoring the bottom bar"), war am 2026-07-27 zu drei Vierteln falsch und hätte eine Session glauben lassen, die Mix- und Clip-Flächen ließen sich durch Wiedereinhängen der Leiste zurückholen: **`ClipView` (807dc0d) und `ArrangeTimelineView` (eb58e7a) sind mit #121 Slice 4 gelöscht, `BrowserView` und `ChannelRackView` mit #167 (2026-07-27)** — letzteres mischte 8 Kanäle, die keinen Klang mehr erzeugen. Wiederherstellen hieße hier neu bauen, nicht wieder anhängen. Do not "restore" them without a founder ask. **Video page = designed + DEFERRED** (`scratchpads/PLAN_VIDEO_PAGE.md`). The old `StudioRoot` Tools/Works/Sync/Well TabView is long gone.
- **Presentation (stability, as-shipped — corrected 10.76.38):** the device-confirmed-launching `EchoelStudioView` uses **MANY `AnyView`-wrapped `.sheet`/`.fullScreenCover` modifiers** chained on the body. Counted by grep 2026-07-27 on `EchoelStudioView.body`: **8 `.sheet` + 2 `.fullScreenCover` + 3 `.alert` + 1 `.fileImporter` = 14 presentation modifiers** on the chain (dateiweit 16, auf der Kette 14 — nur die 14 sind das Metadata-Budget; **beide Zahlen sind seit #479 in `ResetSoundClearsWhatTheLaunchLineReportsTests` festgenagelt**, die Zähl-Provenienz in `memory/LEDGER_COUNTS.md` §D). Diese Zahl liest eine Sitzung, BEVOR sie einen Modal anhängt — an Kopfraum zu glauben, den es nicht gibt, ist der Weg zurück zum Black-Screen-SIGSEGV. Each has its own `isPresented:`/`item:` binding and an `AnyView(...)`-erased content closure. This is the baseline that launches — the earlier "ONE `.sheet(item:)` + ONE `.fullScreenCover(item:)` via computed bindings" note was **aspirational, never the shipping code**, and is removed to stop a future session "fixing" the launching code into a regression. **THE REAL RULE (learned the hard way, 10.76.34/build 2068 black screen): do NOT keep GROWING this modifier chain.** Adding sheets pushed the body's aggregate generic type past the SwiftUI metadata-decoder stack limit → SIGSEGV at first render, before any view appears (presents as a black screen, or "Safe Mode oder Black Screen" alternating once the self-healing net catches every other launch). The chain was "just under" the limit at 10.76.9/21; three sheets added 10.76.25/27/29 tipped it over (an `AnyView`-split of the chain did NOT save it — 10.76.35 still crashed; only reverting to the 10.76.21 body did). To add a NEW modal: **reuse/replace an existing slot, or consolidate the whole chain into a single `.sheet(item:)` enum FIRST** — never just append another `.sheet`. (Separately: never drive two modals true at once — that installs an invisible tap-blocking layer, the "can't click anything" hang.) **Also (10.76.41, "Tonart-Menü friert ein / kann plötzlich nicht mehr auswählen"): never read a HIGH-FREQUENCY `@Observable` (the ~10 Hz `CameraRPPGBioPublisher` finger/confidence/waveform, any bio snapshot, a playhead) directly in `EchoelStudioView.body` or in a computed `var` that `body` evaluates — `AnyView(...)` is NOT an observation boundary, so those reads register the WHOLE root body as a 10 Hz observer and every rebuild tears down any open `.menu` Picker popover (the freeze; worse while playing). Confine such reads to their own small leaf `View` struct (e.g. `BioStripView`, `PulseMeasurementView`) so only that view churns; the Picker-hosting body stays still.** **AND (10.76.48, "Sobald Biofeedback läuft kann ich nicht mehr auswählen"): the camera-freeze had a SECOND, non-SwiftUI cause — a high-frequency producer on a background queue must NOT hop to `@MainActor` per item. `CameraRPPGBioPublisher.onFrame` did a `Task { @MainActor }` PER captured frame (~30/s before the analyzer's frame-skip); that flood of tiny main-actor task submissions starved the SwiftUI executor → the open `.menu` Picker stopped responding while bio ran. Fix pattern: the background closure pushes into a lock-protected `RGBSampleQueue` (`@unchecked Sendable`, `NSLock`, capped) with ZERO actor hop; the EXISTING 10 Hz `publishTask` drains+feeds the `@MainActor` analyzer in one batch (carry a `timestamp` so rate maths is unchanged). Rule: never `Task { @MainActor }` per frame from a 30 fps source — batch into an existing low-rate main-actor poll via a Sendable queue.** **AND (10.76.50, the ACTUAL recurring menu-freeze cause — found after 41/43/47/48 each fixed a real-but-insufficient cause): the churn was in `WorkspaceView` (the ROOT, ABOVE every surface), NOT in `EchoelStudioView`. `WorkspaceView.topBar` read `cameraRPPG.waveform`/`detectedBPM`/`isLocked` directly to feed the header `PulseMonitorMini` — `waveform` updates ~10 Hz during biofeedback, so `WorkspaceView.body` rebuilt 10×/s and tore down any open `.menu` Picker in the surface BELOW it. Every prior audit scoped to `EchoelStudioView` and correctly found it clean — the 10 Hz read was one level up. FIX: confine the live reads to a leaf (`PulseMonitorMiniLive` reads the publisher in its OWN body); `WorkspaceView` only reads `isRunning` (start/stop). **RULE: when a freeze/churn persists after the obvious view is proven clean, AUDIT THE PARENT/ROOT (`WorkspaceView`, any always-on header/HUD that reads live bio) — a 10 Hz read in ANY ancestor of the menu host rebuilds the whole subtree. Header/monitor tiles that show live bio MUST read it in their own leaf, never via values passed down from a parent body.**
- **✅ TESTFLIGHT PIPELINE: GREEN (verified 2026-05-30).** Prior "deploy blocker" note is resolved — `testflight.yml` runs #1404–#1407 on `main` all succeeded across every platform (iOS upload + Summary), preflight confirms App Store Connect secrets are present and valid. Dispatch + poll from the sandbox via `bash scripts/check-testflight.sh dispatch` (token in gitignored `.claude/settings.local.json`). Push the feature branch's newer work (bio synth / OSC / Polar) to TestFlight with a full `build_only=false` run once a branch verification run is green.
- **Latest batch (2026-07-12, 24h-Mandat, on branch, gates green, TestFlight-FREEZE bis Profi-Milestone):** **A3 drawable automation canvas** (tap-add / drag-move / segment-bend / double-tap-delete; `AutomationCanvasMath` pure) · **A4 bio-operators** (coherence shifts the chance threshold, roll stays seeded) · **L1 Grand Master + Blackout** (Art-Net + sACN; blackout wins, return slews) · **P1 idle-voice skip** (frames not blocks, 2.5 s window > dub-echo tail; audio-thread-reviewed) · **B2 per-track pan** (`TimelineLane.pan`, honest `sourceNode.pan`/AVAudioMixing engine path, sends deliberately absent) · **B3 Bio into the menu host** (always-on strip removed; ⛔ #705 schrieb hier „beide Hälften sind falsch" über „‚Bio' chip + header long-press" — und das war die `MultiTrackRecorder`-Falle: **beide Hälften waren am 2026-07-12 WAHR.** Ein „Bio"-Chip wurde mit B3 wirklich ausgeliefert (`PLAN_DMMW_PROFI_LEVEL_2026-07-12.md:33`, Commit 8ec7f11) und am 2026-07-14 wieder ENTFERNT (`PLAN_PER_INSTRUMENT_SYNTH_2026-07-14.md:77`); #290 lehnte die RÜCKKEHR ab („a second door to the same panel"). Der Langdruck ist seit 2026-07-29 nur noch der zweite Weg. **Eine datierte Zeile für falsch zu erklären, die wahr-und-überholt ist, löscht genau die Tatsache, die eine spätere #290-Debatte braucht: der Chip wurde probiert und gezogen.** Heutige Tür: TAP auf die Puls-Pille, #706) · **B4 BLE strap door — ZURÜCKGENOMMEN am 2026-07-15 durch BLE-3**, die Patchbay ist NICHT die Tür des Gurts (siehe Pipeline-Zeile) · **B5 sample door on every drum channel strip** (slot-reuse) · **W1 LyricsModel** (deterministic singing syllabification + melisma, pure; W-track per founder 2026-07-12C) · **EchoelAI foundation N0–N4** (`scratchpads/ECHOELAI_ADR_2026-07-12.md`: `EchoelParameterRegistry` [keyPath-stable, DDSP inventory] + `BrainBackend`/`FoundationModelsBrain` [Tier-1, `#if canImport(FoundationModels)`+iOS 26, else unavailable] + `ParameterToolCore` [model-free tool logic] + vocabulary data — ⛔ **„ALL behind `FeatureFlags.echoelAI` default OFF" IST FALSCH, und zwar in beide Richtungen. Gemessen 2026-08-07: `git grep -n "FeatureFlags.echoelAI" -- Sources` liefert GENAU EINEN Treffer, und der ist ein KOMMENTAR** (`EchoelAI/BrainBackend.swift:10`). Der Schalter hat null Leser; nichts ist hinter ihm. **(a)** `BrainBackend` und `FoundationModelsBrain` haben außerhalb von `EchoelAI/` überhaupt keinen Verbraucher — sie sind AUS, weil sie niemand ruft, nicht weil eine Flagge sie ausschaltet. **(b)** Und die gefährlichere Hälfte: `EchoelParameterRegistry` steht in dieser Aufzählung, liegt aber in `Core/` und ist in FÜNF Dateien live (`AutomationPlayer`, `ParameterApplyRouter`, `EchoelDDSP`, `EchoelmusicApp`) — der Satz erklärt einen LEBENDEN Typ für flag-gated aus. `ParameterToolCore` ebenso, gelesen von `ParameterApplyRouter`. **Die Sicherheits-Eigenschaft „Release bit-identical" stimmt weiterhin, aber sie kommt vom fehlenden AUFRUFER, nicht von einer Flagge** — wer später eine Aufrufstelle hinzufügt und sich auf `FeatureFlags.echoelAI` als Absicherung verlässt, hat gar keine. Entweder wird die Flagge wirklich verdrahtet oder sie wird gelöscht; heute ist sie Dekoration. (Der EchoelAI-Safety-Owner aus `ultracode-teams` ist genau dafür da.) Unverändert wahr: der LLM berührt den Audio-Thread nicht.) · **Body Science learn section** (`BioScienceInfo`: cited HRV-resonance research — Lehrer/Vaschillo, Goessl 2017 — facts + self-observation, NO health claim, test-guarded; report `scratchpads/REPORT_SOUND_PAIN_EVIDENCE_2026-07-12.md`). **Healing/organ/tissue/wound theme = pre-Echoel (BLAB/Syng) legacy, never code here, stays a hard REJECT red line.**
- **Latest work (2026-06-23, on branch, gates green):** **Adaptive Quality** (AdaptiveQuality core + ResourceGovernor: thermal/battery/measured-FPS → tier → MetalBioView detail/reduce-motion **+ OSCSender's bio-egress rate via `PollingRateCeiling`, a CEILING and not a target** — corrected 2026-07-28 twice over: the governor never drove MetalBioView's frame RATE (`MetalBioView.swift:399` (Stand 2026-08-14) pins `preferredFramesPerSecond = 60` statically, and `AdaptiveQuality.swift` says so itself), and the one consumer wired since — `bioHz` → `OSCSender` (34e2355) — was missing. `targetFPS` / `oscHz` / `allowSpectralDonuts` have NO consumer, by design. This is the line a session reads before touching a quality knob, so both halves being wrong was the dangerous kind of stale) · **camera-session resilience** (runtime-error/interruption observers + frame-stall watchdog — fixes the silent ~68–200 s rPPG freeze) · **rPPG saturation-hold** · **composition cohesion** (BioComposer structure/detail RNG split — "homogener klingen") · **master −1 dBFS true-peak trim** · **EchoelFX bio-reactive modulation** (FXModulation core in `Core/` + FXBioModulator ~30 Hz; body→FX-param routing, UI section) · **EchoelFX Bitcrush + Stereo Widener** stages (wired chain/VM/UI/FXPreset/bio-mod) · **VJ visuals** (live in-fullscreen control overlay + shader hue/saturation palette, physical-colour default preserved). EchoelFX deepening = 4 workstreams (1 bio-mod + 2 algorithms shipped; 3 macro-morph + 4 CI-polish pending).
- **Prior TestFlight ship (2026-06-18):** rPPG fix (torch + exposure lock), real frequency-domain HRV coherence (Lomb-Scargle + Welch), resonance breath guide, tap-to-learn bio metrics, Art-Net flash-safety. Base build 1543 (app + Widget + AUv3, camera rPPG, universal BLE, ADM-OSC, EchoelLux Art-Net, launch silence).
- **Absent (not wired — do not claim as shipping):** RTMP/streaming (BroadcastPublisher is a compile-safe scaffold behind `#if canImport(HaishinKit)`; HaishinKit not integrated), Video-SCHNITT (⛔ korrigiert 2026-07-31: hier stand „video capture/edit" — die CAPTURE ist erreichbar und darf sehr wohl als shipping gelten, nur der EDIT ging mit #121 Slice 3), multitrack audio (gebaut, flag-gated AUS, türlos — siehe den ⛔-Absatz „Was hier stand und 2026-07-27 gestrichen wurde" ganz oben und #204; „absent" stimmt für den Nutzer, „nicht gebaut" nicht für den Entwickler). **EchoelStore** (`Core/EchoelStore.swift`) = compiling but UNREACHABLE: `ProUnlockView` exists and is never presented (`WorkspaceView.swift:141` (Stand 2026-08-14)), so nothing is purchasable today. Corrected 2026-07-25 — the old "ZERO consumers" + "legacy subscription product IDs" wording was false on both halves: the one compiled product is the NON-CONSUMABLE `com.echoelmusic.app.pro` (`ProGate.swift`). **Aber das ist ÜBRIGGEBLIEBEN, nicht der Plan** (korrigiert 2026-07-28): die zweite Founder-Entscheidung vom 2026-07-10, wörtlich festgehalten in `WorkspaceView.swift` über `body`, hebt das Einmal-Pro auf — v1.0 komplett kostenlos, v1.1 = „Echoel Live" Jahres-Abo, v1.2 = Per-Event-Host-Gebühr. `ProUnlockView`/`EchoelStore`/`ProGate` bleiben im Code, um dafür UMGEWIDMET zu werden: nicht löschen, vor v1.1 nicht wieder präsentieren. **Push/CloudKit:** `aps-environment=production` + iCloud/CloudKit entitlements ARE declared and `AnnouncementCenter` (registerForRemoteNotifications + CKQuerySubscription) EXISTS — but hard-gated OFF for v1.0 via `AnnouncementCenter.cloudKitConfigured = false` (zero CloudKit/push calls execute; launch-crash fix v10.79.148). Its Learn-view toggle is HIDDEN while the gate is false (2.1 audit 2026-07-16). Before flipping the gate in v1.1: deploy the CloudKit "Announcement" schema to Production FIRST. (The old "zero push code" claim here was stale — corrected 2026-07-16.) **Art-Net + sACN (unicast) are live.** **VocoderCore-MAPPING / BioModulation** = pure tested cores, **not yet wired** (foundations) — ⭐ korrigiert 2026-08-14: die ANALYSE-Hälfte (`VoiceAnalyzer`/`VoiceFrame`) ist seit #592a verdrahtet (Voice-Capture-Kette, Sound-Panel-Tür); unverdrahtet ist nur noch `VocoderMapping` (Ausgabe-Hälfte). **FeedbackGuard** (audio-input live monitoring): ENGINE wired (AudioEngine ~15 Hz Duck-Loop, Tests grün) — aber die UI-Tür (`AudioInputPickerView`, `showInput`) ist seit dem Tools-Grid-Removal (2026-07-02) UNERREICHBAR; gleiches Schicksal für PatchbayView (Routing!), MeditationView, PatchEditorView, SampleBrowserView, AutomationView, BroadcastView, SpectralDonutView — alle Slots existieren, einziger Trigger war das tote `toolsSection`/`openTool` (Deep Audit 2026-07-12; tote Slots = SLOT-REUSE-Reservoir an der Modal-Decke). **BEHOBEN (2026-07-12 batch + seither):** PatchbayView (Routing/Master-Panel), ~~SampleBrowserView (B5, Drum-Channel-Strip-Tür)~~ — **GELÖSCHT 2026-07-27 (#167)**; die B5-Tür starb schon mit den Drums (#166), die Datei ist jetzt auch weg. Genau die „verifiziert erreichbar"-Falle, vor der derselbe Absatz warnt: Slot + Setzer beweist keine Erreichbarkeit, und ein Eintrag hier veraltet still, **FeedbackGuard/AudioInputPicker** (Master-Panel „Audio input"-Tür, EchoelStudioView.swift `masterDoorButton`) ist wieder erreichbar. **NICHT erreichbar** (Stand 2026-07-31, per Zählung der Instanziierungsstellen): ~~`PatchEditorView`~~ — **GELÖSCHT 2026-07-31 (#132 Slice 6)**, kein Eintrag mehr in dieser Liste, weil es die Datei nicht mehr gibt; der lebende Timbre-Editor ist und war `soundPanel` hinter dem Sound-Chip. `AutomationView` (Datei existiert nicht), `SpectralDonutView`, `SampleBrowserView` (mit #167 gelöscht), ~~`FileWaveformView`~~ — **GELÖSCHT 2026-07-28 (#132 Slice 5, `2245671`)** zusammen mit `WaveformView` und `WaveformCache`; kein Eintrag mehr in dieser Liste, weil es die Datei nicht mehr gibt. Der reine Kern `WaveformReducer` BLEIBT, jetzt test-only und mit Nachruf im eigenen Datei-Kopf. **Genau die Falle, vor der dieser Absatz zweimal warnt:** der Eintrag stand hier als Gegenwarts-Tatsache, geschrieben am selben Tag als PLAN für genau diesen Commit — wer ihn danach las, hätte eine türlose Waveform-Ansicht wieder aufmachen wollen, die es nicht mehr gibt. **KORREKTUR 2026-07-26 (die „verifiziert 2026-07-21"-Zeile war FALSCH für zwei ihrer Einträge):** `AutomationView.swift` existiert im Repo nicht mehr — es kann keine Tür haben. Und **`SpectralDonutView` ist UNERREICHBAR:** ihr einziger Instanziierungsort liegt im `.fullScreenCover(isPresented: $showVisual)`, und `showVisual`s einziger Setzer war `openTool`, aufrufbar nur aus `toolsSection`, **das nichts rendert**. Dieselbe tote Kette nimmt den MIDI-**Import** (`midiImportPresented` / `importMIDI()`) und die REC-Taste im Visual-Vollbild mit. ⛔ **Und hier stand „die ‚Donuts'-Pille im Synth-Reiter ist live antippbar und wirkungslos" — beide Hälften falsch, seit #227, und der Quelltext sagt das seither selbst** (`EchoelStudioView.swift`, beide Phrasen wörtlich grep-bar: `PILL STOOD HERE AND WAS REMOVED (#227)` plus `#227 removed the only reachable control that could set`). Die Pille im Synth-Reiter ist **GELÖSCHT**, also weder antippbar noch vorhanden. Der überlebende Umschalter sitzt IM `.fullScreenCover(isPresented: $showVisual)` — und dort ist er **vollständig verdrahtet**: derselbe Cover trägt den `if spectralDonuts`-Zweig, der `SpectralDonutView` baut. Er ist **unerreichbar, nicht wirkungslos**, dieselbe Klasse wie `ImmersiveStageView`. ⭐ **Der Unterschied ist nicht Wortklauberei, und deshalb steht die Rücknahme hier statt einer stillen Reparatur: „wirkungslos" lädt die nächste Sitzung ein, ein totes Bedienelement zu löschen — sie fände keins und würde beim Suchen ein FUNKTIONIERENDES hinter einer fehlenden Tür finden.** Der Halbsatz über `FloatingVisualWindow` bleibt wahr (gemessen: `grep -n spectralDonuts` in dessen Datei = 0 Treffer) — er begründet nur nicht mehr, was er begründen sollte. ⚠️ **Und diese Zeile bekommt bewusst KEINEN Wächter.** `VisualLookTruthTests` (#227) deckt die Persistenz-Hälfte ab und sagt in seinem eigenen Kopf, dass es die Pille NICHT beweisen kann. Ein Text-Scan auf CLAUDE.md wäre hier die #364/#486-Falle in Reinform: diese Datei ZITIERT zurückgenommene Behauptungen absichtlich in ⛔-Blöcken, ein negativer Scan träfe also zwangsläufig seine eigene Rücknahme — genau die Kollision, die #486 und #491 bezahlt haben. **3 der 14 Präsentations-Slots hängen an Flags, die niemand setzen kann** = freier Kopfraum an der Metadata-Decke, statt einen 17. anzuhängen. Der tote Tools-Katalog selbst ist mit `f371d27` gelöscht (`ToolCat`/`ToolItem`/`toolItems`/`openTool`/`toolsSection`/`toolGroup`/`gridChip`/`gridChipLabel`, 157 Zeilen) — die drei Modifier stehen absichtlich weiter da, als wiederverwendbare Slots. **Er nahm dabei die einzige Oberfläche für drei Opt-ins mit:** „Save to Apple Health" (persistiert! mit `083cec8` als `HealthWriteOptInRow` im Bio-Panel zurückgeholt — ein persistiertes Gesundheits-Einverständnis MUSS einen erreichbaren Aus-Schalter haben) sowie `midiOut.mpeEnabled` / `expressionEnabled` — **mit #713 ERLEDIGT**: zwei persistierte Schalter („MPE note layout", „Per-note expression") im `midiOutSection` der erreichbaren Routing-Fläche, Default aus, EIN Besitzer (`MIDIOutput.applyOutputPreferences()` liest die Keys; PORT-ÖFFNUNG und Schalter rufen dieselbe Methode — die `MIDIInput.applyNetworkSessionPreference()`-Form. ⛔ #713 schrieb hier „Start"; `startIfNeeded()` hängt an `enabled`s didSet, also an der persistierten `midi.out`-Route — bei ausgeschalteter Route läuft beim Start GAR NICHTS, #714). Der zweite Schalter ist deaktiviert, solange der erste aus ist, weil der Sendepfad `if mpeEnabled, expressionEnabled` liest. Wächter: `Tests/CISmoke/MIDIOutQualitySwitchesTests.swift`. **Nicht geräteverifiziert**. ZWEI LEHREN: (1) „per direktem Code-Read verifiziert" heißt nur etwas, wenn die Kette bis zum RENDERNDEN Elternteil verfolgt wurde — Slot + Setzer beweist keine Erreichbarkeit. (2) **Vor dem Löschen eines UI-Blocks prüfen, welche Modelle er als EINZIGER schreibt** — ein Toggle mit persistiertem Flag hinterlässt beim Löschen einen unwiderruflichen Zustand, keine Lücke. **Keine Zeilennummern in diesem Absatz:** die erste Fassung zitierte Nummern, die derselbe Commit um 157 verschob. MeditationView bleibt bewusst türlos (Founder: Teil des Produktionsflusses, keine eigene Tür gewollt). **BroadcastView bleibt türlos — korrekt so**, solange HaishinKit/RTMP nicht verlinkt ist (eine Tür zu einem nicht funktionierenden Backend wäre ein Halbfertig-Feature). **BioVisualParams** (immersive flash-safe pulse) is **wired**. See `docs/dev/FEATURE_MATRIX.md` + `scratchpads/DEEP_AUDIT_2026-07-12.md`.
  ⛔ **DREI TÜRLOSE FLÄCHEN FEHLTEN IN DIESEM REGISTER (nachgetragen 2026-08-07, jede per Zählung der Instanziierungsstellen).** Das Register ist die Liste, aus der eine Sitzung ableitet, was sie noch aufmachen oder löschen darf — eine Lücke darin ist teurer als eine falsche Zahl, weil sie gar nicht erst als Frage auftaucht.
  · **`AnalysisScopeView`** (#347 Slice 1) und **`AnalysisPoincareView`** (#347 Slice 3b): `git grep -n "AnalysisScopeView(\|AnalysisPoincareView(" -- Sources` außerhalb der eigenen Dateien = **0**. ⛔ **Hier stand „Ihre zwei Geschwister derselben Epic sind sehr wohl montiert (`AnalysisSpectrumView` und `AnalysisWavefrontView`, beide in `EchoelStudioView`)" — gemessen 2026-08-21 (#680) ist das falsch, und zwar für ALLE VIER:** `git grep -n "AnalysisSpectrumView(\|AnalysisWavefrontView(" -- Sources` = **0**; der einzige Treffer in `EchoelStudioView` ist ein KOMMENTAR an der ehemaligen Montagestelle, der es selbst sagt („All four analysis views are now in that state; the Field panel shows no meters at all"). Das zweite Paar ist NACH dem 2026-08-02 geparkt worden, mit derselben Begründung und derselben Zusage („Restoring any of them is one line here plus its caption"). **Der Quelltext war die ganze Zeit ehrlich; falsch war das Register — also genau die Liste, die eine Sitzung liest, BEVOR sie in den Quelltext schaut.** Lehre, verschieden von der Stale-Zahl-Lehre: die eine Hälfte dieses Satzes war gemessen („= 0"), die andere aus dem Gedächtnis mitgeschrieben — **wer eine Register-Zeile über einen Nachbarn mit-behauptet, misst den Nachbarn mit.** **Das ist KEIN Defekt und muss so dastehen:** die Entscheidung ist am 2026-08-02 per Founder-Screenshot mit rotem X gefallen und im Quelltext an der Montagestelle festgehalten. Also türlos ABSICHTLICH, wie `ImmersiveStageView` und `BroadcastView` — nur stand es nirgends im Register, und genau das ist der Zustand, den der Doctor-Sektion-C-Text „unerreichbar UND nirgends aufgeschrieben" nennt.
  · **`TimelineAutomationRow` = GELÖSCHT (#473, 2026-08-07).** Der Eintrag stand hier als türlos-aber-nicht-löschbar, weil `TimelineAutomationRowMath` in DERSELBEN Datei lebte und `Core/TimelineStore.swift` es ruft — ein „lösch die türlose Datei"-Aufräumen hätte den Store gebrochen. **#472 hat den Kern herausgehoben, #473 hat die Ansicht gelöscht**: `struct TimelineAutomationRow: View` plus `TimelineAutomationTargetOption` und `TimelineAutomationHeadCell`, alle drei mit null externen Verweisen. Die Datei ist weg; `Sequencer/TimelineAutomationRowMath.swift` bleibt und ist unverändert.
    ⛔ **UND DIE ERSTE FASSUNG DIESER ZEILE HAT DIE #475-LEHRE WÖRTLICH WIEDERHOLT, EINEN ZYKLUS SPÄTER: sie schrieb „415 Zeilen `struct TimelineAutomationRow`".** 415 ist die **DATEI** (`git show --stat`, 415 Löschungen). Der `struct` läuft von 217 bis 414, ist also **198** Zeilen; die ganze `#if canImport(SwiftUI)`-Hälfte mit allen DREI Typen sind **344** (72–415). Und der Widerspruch stand schon im Baum: `TimelineAutomationRowMath.swift` und dieselbe CLAUDE.md sagen seit #472 „344 Zeilen" über die Ansicht. **Dieselbe Zahl an das falsche OBJEKT geheftet — nicht veraltet, sondern von Anfang an dem falschen Ding zugeordnet**, und das ist der Grund, warum das Repo jetzt zwei Zahlen für eine Sache trug. Belastbar ist die GRÖSSE des Eingriffs (415 Löschungen), weil die sich nie wieder ändert; für die Ansicht nennt man die Ansicht.
    ⭐ **DIE PROSA-ZITATE IN FÜNF DATEIEN SIND UMGESIEDELT, NICHT VERWORFEN — es sind SECHS Zitate, weil `EchoelValueField` zwei trägt — und das war der eigentliche Blocker, den keine Register-Zeile vorhergesagt hatte** (die #472-Lehre: eine registrierte Entblockung ist erst dann eine, wenn man NACH dem Ausführen noch einmal grept). `Core/PerTrackParameterKeyPath.swift` hatte einen ZEIGER auf den `DATA MODEL (honest):`-Block der Ansicht — der Block ist jetzt dort EINGERÜCKT statt ein drittes Mal zitiert, denn dieselbe Zeile hatte schon eine `:11-16`-Zeilenspanne an #472 verloren. **Zwei Zitat-Ausfälle, zwei Mechanismen, eine Datei: ein Zeiger ist nur so haltbar wie das, worauf er zeigt.** Die zwei `EchoelValueField`-Prämissen stehen jetzt als HISTORISCHER Beleg — die SwiftUI-Behauptungen sind unverändert, der Zeuge im Repo ist weg, und die zweite (`⚠️ HONEST LIMIT`) wird dadurch SCHÄRFER: diese Datei ist der einzige verbliebene Abhängige. `DSP/EchoelDDSP.swift` benutzte die Türlosigkeit als Prämisse — „null Instanziierungsstellen" hätte ein Wieder-Einhängen still falsifiziert, „gelöscht" kann das nicht, das Argument ist also STÄRKER geworden. `Core/AutomationPlayer.swift`s ⛔-Rücknahme bleibt, gerade WEIL der Code, den sie korrigiert, nicht mehr nachlesbar ist. Und `Sequencer/ClipAutomationEdit.swift` zitierte „TimelineAutomationRow's static helpers" — seit #472 falsch, nach #473 gegenstandslos.
    ⛔ **UND DAS NACH-DEM-SCHNEIDEN-GREPEN HAT EINEN VERWAISTEN NACHBARN GEFUNDEN, den niemand aufgeschrieben hatte:** `AutomationPlayer.extraAutomatableDescriptors` hatte von #473 bis #559 **null** Aufrufer in `Sources/` — sein einziger Leser war `TimelineAutomationTargetOption`. NICHT mitgelöscht: es ist das Placebo-Gesetz in ausführbarer Form („biete nur einen Parameter an, der wirklich Audio bewegt") und genau das, was eine künftige Automations-Fläche zuerst braucht. ⭐ **Und genau so ist es gekommen: seit #559 liest es `Studio/AutomationStatusStrip.swift`** (die Automations-Anzeige im Sound-Panel). Der Eintrag bleibt als BELEG dafür, dass „türlos, aber nicht löschbar" eine eigene Kategorie ist — und weil der Vermerk an der Deklaration steht, konnte er dort im selben Commit mitgezogen werden statt hier zu verjähren.
    ⚠️ Der Wächter ist im SELBEN Commit mitgezogen (#456): `TheAutomationRowLawHasItsOwnFileTests` LAS die gelöschte Datei über ein `try` hinter einem verzeichnis-weiten Skip — die Löschung wäre sonst ein hartes Rot auf korrektem Baum geworden. Ersetzt durch etwas STRENGERES: die Datei muss ABWESEND sein, und ein Lauf über `Sources/` verlangt **genau EINE** Deklaration von `enum TimelineAutomationRowMath` (die alte Form fragte nur, ob EINE benannte Datei sie nicht wiederholt — eine Zweitkopie irgendwo anders wäre durchgegangen). Der Test ist dabei umbenannt, weil sein alter Name ein Verfahren beschrieb, das der Code nicht mehr nimmt (#374).
    ⚠️ **Was sich NICHT geändert hat: Timeline-Automation ist weiter unerreichbar.** `AutomationPlayer` hat keinen Produktions-Schreiber; eine von einem älteren Build persistierte Kurve SPIELT (über `applyStep` auf jedem Transport-Schritt), aber keine Fläche kann heute eine zeichnen. #473 hat eine Ansicht entfernt, die nichts montiert hat — keine Fähigkeit.
  · **`PulseMeasurementView` — VIERTE türlose Fläche, nachgetragen 2026-08-12 (#525), und die einzige dieser Liste, die von sich selbst BEHAUPTET hat, auf dem Schirm zu sein.** Gemessen: `git grep -n "PulseMeasurementView(" -- Sources` = **EINE** Stelle (`Studio/BioSourceView.swift`), `git grep -n "BioSourceView(" -- Sources` = **NULL**. Die Kette endet einen Sprung höher. Ihr Dateikopf sagte trotzdem in der ersten Zeile „shown above the controls while a take is playing" — seit dem Tools-Grid-Removal (2026-07-02) falsch. ⛔ **Hier stand die „TEUERSTE Auslassung dieses Registers", und ihre MESSUNG war richtig, ihre SCHLUSSFOLGERUNG falsch (#703).** Wahr bleibt: `CameraRPPGBioPublisher.coachingHint` (= `acquisitionCue.fullHint`) hat GENAU EINEN Leser, und der ist diese türlose Ansicht. Daraus wurde hier „die rPPG-Abhilfe erreichte einen sehenden Nutzer nirgends" — und **das ist seit #523/#569 unwahr**: `BioStripView` rendert DIESELBE Zeichenkette über `acquisitionCue.fullHint` als Banner, sichtbar im `bioPanel`, gegated durch `cueWarrantsFullHintOnScreen` — **die Tür ist die PULS-PILLE** (`PulseMonitorMiniLive`-Tap → Chrome-Tür „bio"), KEIN Chip: `.bio` fehlt in `EchoelStudioView.studioChips` (#704). **Tot ist die PROPERTY, nicht die FÄHIGKEIT** — und der Quelltext hat das die ganze Zeit richtig gesagt (`PulseCue`: „UNTIL THIS PROPERTY HAD A CONSUMER"; `BioStripView`: „before this line"). Wächter der POSITIVEN Hälfte: `TheStallRemedyReachesTheScreenTests.testTheStripRendersTheStallRemedy` — ein neuer wäre #416. Ein Dateikopf, der „ist auf dem Schirm" sagt, bleibt trotzdem der Grund, warum das lange niemandem auffiel. ⛔ **NICHT LÖSCHEN, und zwar aus dem #472-Grund:** in diesem Dateikopf steht die kanonische Fassung des 10.76.41/50-Freeze-Gesetzes für diese Form, und die Präsentations-Zeile weiter oben zitiert die Ansicht NAMENTLICH als Musterbeispiel (dort neben `BioStripView` — die ist über die Puls-Pille erreichbar, diese nicht; das Beispiel gilt der FORM, nicht der Erreichbarkeit). Eine türlose ANSICHT und ein tragender Nachbar in EINER Datei. Wächter: `Tests/CISmoke/ThePulseReadoutHasNoDoorTests.swift` — er verbietet das Wieder-Aufmachen NICHT (#364), er nennt in seiner Fehlermeldung die **sechs** Prosa-Stellen, die dann im selben Commit mitzuziehen sind.
  · **Die AUDIO-SPUR-Schicht — FÜNFTER Eintrag, nachgetragen 2026-08-12 (#527), und der erste, der keine ANSICHT ist, sondern eine verdrahtete Maschine ohne Erzeuger.** `AudioLanePlayer` wird beim App-Start konstruiert (`EchoelmusicApp`) und vom Transport bei JEDEM prime/apply/stop gefahren — das ist wahr und bleibt es. Sein Dateikopf sagte zusätzlich „audio lanes now sound in time with the arrangement", und **das ist eine Fähigkeitsbehauptung ohne Produzenten**. Gemessen (Kommentare gestrippt): **FÜNF** `TimelineRegion(`-Konstruktionsstellen, und jede ist abgehakt — `TimelineStore.migrate(sections:)` sät eine LEERE `Audio 1`-Spur und legt jede Region auf die MIDI-Spur · `ensureComposerRegion` und `ensureUserMidiRegion` bauen ihren Clip per Konstruktion mit `kind: .midi` · `RecordController` und `AudioClipFactory` sind die einzigen zwei, die eine audio-tragende Region erzeugen KÖNNEN, und diese Kette ist türlos (`AudioClipFactory` wird nur von `TakeRecorder` gerufen, `TakeRecorder` nur von `RecordController` konstruiert, und `RecordController.arm()` hat NULL Aufrufer — #204). Die Arrangement-Fläche, die eine erzeugt hätte, ging mit #121 Slice 4.
    ⛔ **UND DAS IST KEIN LÖSCH-ARGUMENT, sondern das Gegenteil — der Punkt, an dem sich dieser Eintrag von den vier darüber unterscheidet.** `TimelineDocument` wird PERSISTIERT und beim Start dekodiert; ein Projekt, das ein Build mit erreichbarem Recorder-Pfad geschrieben hat, kann weiterhin eine Audio-Region tragen, und dieser Koordinator ist das Einzige, was sie abspielen würde. Die Schicht als „tot" abzuklemmen macht aus „offensichtlich abwesend" ein „still stumm". Die leere Audio-Spur im Default-Dokument bleibt ebenfalls absichtlich — der Founder hat die Mehrspur-Form („mehrere") ausdrücklich verlangt.
    ⚠️ **Und der ranked board-Eintrag, der diese Schicht als „WIRED" führt, ist damit halb korrigiert:** verdrahtet ja, klingend nein. Wer daraus eine Löschung ableitet, leitet sie aus der falschen Hälfte ab. Wächter: `Tests/CISmoke/TheAudioLanesHaveNoProducerTests.swift` — er verbietet das Wieder-Aufmachen NICHT (#364) und trägt fünf Gegengewichte, die genau die naheliegende „Aufräum"-Löschung rot machen.
  · **Die MODULATIONS-MATRIX — SECHSTER Eintrag, nachgetragen 2026-08-12 (#541), und der zweite nach der Audio-Spur, der keine ANSICHT ist, sondern eine laufende Maschine ohne Erzeuger.** `ModulationEngine` wird beim Start konstruiert, `start(subscribing:)` läuft, die 100-ms-Schleife tickt, und `ModDestinationKey.tempo` ist als Ziel registriert. Gemessen fehlt die ROUTE: die Default-Matrix ist LEER (die Datei sagt es zweimal selbst), und `git grep -n "\bModRoute(" -- Sources` liefert **genau EINEN** Treffer — den `LossyDecoded`-Decoder in `ModulationMatrix.swift` (ohne die Wortgrenze kommt `FXModRoute(` dazu, ein fremder Typ). Null Produktions-Konstruktionsstellen. `Studio/BioModulation.swift` ist KEINE Fläche (es hält `ClockSource` und `BoundParameter`, reine Werttypen, null externe Verbraucher) — wer aus dem Dateinamen eine Matrix-UI erwartet, sucht falsch.
    ⛔ **Und das ist wieder KEIN Lösch-Argument, aus dem #527-Grund:** die Matrix wird PERSISTIERT und beim Start dekodiert (`load()` gewinnt über die leere Default), also kann ein Dokument aus einem Build mit erreichbarer Fläche weiterhin das Tempo ziehen. Abklemmen macht aus „offensichtlich abwesend" ein „still stumm". Ebenfalls tragend und nicht anzufassen: der `outputTap`, der JEDE angewandte Modulation als `/echoelmusic/mod/<key>` über OSC schickt — die Adresse steht im OSC-Abschnitt dieser Datei als real.
    ⚠️ Der Unterschied zu den vier Ansichts-Einträgen darüber: dort ist die Fläche weg und die Fähigkeit klar abwesend. Hier LÄUFT alles bis auf den letzten Zentimeter, und genau deshalb hat die CURRENT-STATE-Zeile vier Monate „wired (bio→tempo)" behauptet. Wächter: `Tests/CISmoke/TheTempoDestinationHasNoRouteTests.swift`.
- **P1 "Sound complete" — ALREADY BUILT (audited 2026-07-01; corrects the old "Clips/Arrangement UI not wired" note):** the melodic/DAW core is done and wired — **polyphonic synth** (`PolySynthVoice`) + **bass** (`SubBassVoice`) + ~~hybrid sample/synth drums~~ (`BeatPlayer` + `DrumSynthVoice` — **entfernt 2026-07-26, #166/#167; klingt nicht mehr**); **full patch editor + presets** (`SynthPatch`/`PatchStore` + `soundPanel`, favorites/community/save-as, live-apply, tested. ⛔ Hier stand `PatchEditorView` als der Editor „DOORLESS since 2026-07-25" — die Datei ist mit #132 Slice 6 gelöscht; der Editor war die ganze Zeit `soundPanel` hinter dem Sound-Chip); **breakbeat loop-cut** (`LoopCutter`/`LoopBarLength` in the Studio UI); **MIDI export** — **AUSGELIEFERT** (korrigiert 2026-07-28): `exportMIDI()` wird wieder aufgerufen, aus dem Export-Schacht heraus (#188 hat die Tür in den VORHANDENEN Slot zurückgeholt, kein neuer Sheet). `MIDIFileExporter` intakt und getestet. Der App-Store-Text behauptet den MIDI-Export — nicht entfernen, ohne `fastlane/metadata` mitzuziehen; Clips + Arrangement UI **DELETED** by the pure-instrument epic (#121 Slice 4 — `ClipView` 807dc0d, `ArrangeTimelineView` eb58e7a; `ClipStore`/`ArrangementStore`/`AutomationLane` model retires in Slice 5).
  **CRAFT-TOOL DOORS — the #131a craft-editor slot is GONE again (2026-07-26).** It was shipped 2026-07-25 (`f2cbf34`/`bda8f41`) to door the piano roll, and it held exactly ONE case; when the founder said *"Pianoroll soll raus"* the honest move was to take the slot with it rather than leave an undoored enum (the lying-`toolItems` trap). **Der Modifier-Zähler steht EINMAL, im Presentation-Absatz oben** — dort benannt, hier nicht nachgesprochen (⛔ #707 zitierte ihn hier wörtlich, und das Zitat traf nur sich selbst: `grep` fand die zitierte Schreibweise genau einmal, nämlich in diesem Zeiger; #708); seine Provenienz — die zwei Anker-Fehler und die Historie 12→16→15→14 — liegt in `memory/LEDGER_COUNTS.md` §D. Alerts und der File-Importer sitzen auf DERSELBEN Kette und kosten dieselben Metadaten. **The NEXT editor re-introduces the slot as `enum` + `@State` + ONE `.sheet(item:)` + an out-of-body content builder — NEVER a bare appended modifier**, and a case is added ONLY together with its door. Three of the 14 slots (`showVisual`, `showMeditation`, `midiImportPresented`) have no setter at all and are the first place to look for room. `sampleBrowserTrack` was the fourth and is DELETED (2026-07-27): once `SampleBrowserView` itself went, the slot pointed at a type that no longer compiles — a slot is only reusable while its content still builds.
  · **`PianoRollView` = GELÖSCHT (#475, 2026-08-07).** Der Eintrag stand hier als „DOORLESS AND UNMOUNTED" samt der Entblockungs-Bedingung („hoisting that one pure function into a core file is what unblocks deleting the struct") — **#470 hat gehoben, #475 hat gelöscht**: **987** Zeilen `struct PianoRollView: View` plus die zwei privaten Gesten-Typen `RollDragAnchor`/`RollDrag`. Die Datei `Studio/PianoRollView.swift` BLEIBT, weil sie `PianoRollModel` enthält — die Notenmaschine UND den `MusicalFrame`-Publisher, also die Wirbelsäule der Ausgabestufe (Visual · Licht · Raum). `RollSelection` ist ebenfalls geblieben, jetzt test-only (**acht** Behauptungen in `Tests/EchoelmusicTests/NoteTests.swift`), die `WaveformReducer`-Form. ⛔ **DREI ZAHLEN DIESES EINTRAGS WAREN FALSCH, und die Reviewer-Nachlese fand INSGESAMT NEUN Falschbehauptungen in der #475-Prosa — die höchste Zahl, die eine Scheibe in dieser Kette je produziert hat.** (1) „988 Zeilen“: die `struct` läuft von 1305 bis Dateiende 2291, also **987**. (2) „neun Behauptungen“: neun ist `grep -c RollSelection`, das den Testnamen `func testRollSelection_…` mitzählt; die Behauptungen sind **acht**. (3) „2291 → 1278 Zeilen“ ist **ersatzlos GESTRICHEN statt korrigiert** — der Stand beim Löschcommit war 1325, und die Nachlese hat ihn im selben Zug wieder bewegt. **Eine Zeilenzahl einer LEBENDEN Datei ist keine Tatsache, sondern ein Datum**, und dieser Absatz trägt bereits zwei Lehren darüber; belastbar ist die GRÖSSE des Eingriffs (`git show --stat` auf den Commit: 54 Einfügungen / 1020 Löschungen, netto **−966**), weil die sich nie wieder ändert. Ebenfalls aus derselben Nachlese und schwerer als jede Zahl: die #475-Prosa erklärte `pitchCount` für aufruferlos (es hat einen Leser, `highPitch`), zitierte ZWEI grep-Rezepte, die derselbe Commit falsifizierte, und ließ einen ⚠-DORMANT-Kommentar stehen, der eine GELÖSCHTE `PianoRollView.transport` als „den einzigen Produzenten“ benannte und behauptete, die Flagge „kann nicht mehr gesetzt werden“ — während `WorkspaceView` sie auf dem ⏸-Pfad live setzt. **Das ist die teuerste Sorte: ein Vermerk, der einen lebenden Mechanismus für tot erklärt, lädt die nächste Sitzung ein, seine Invariante als Ballast zu behandeln.** **Consequence to state plainly: there is NO note editor in the app any more** — the generated take can be heard, mixed and exported, not corrected.
    ⭐ **UND DIE LÖSCHUNG HAT DREI NACHBARN VERWAIST, was keine Register-Zeile vorhergesagt hatte** (gemessen NACH dem Schneiden, die #472-Lehre): `Studio/RollHitTest.swift` und `Studio/RollFitMath.swift` haben seither **null** Produktions-Aufrufer, `Studio/RollNoteOps.swift` überlebt mit genau einem (`stableSeed`, gerufen von `PianoRollModel`). Keiner ist mitgelöscht — `RollHitTest` trägt das #470-Gesetz, das die Löschung überleben SOLLTE, und im blockierenden Bundle pinnt es `TheUnitToPeriodLawSurvivesTheViewTests`. Dessen dritte Behauptung („die Lane ruft das Gesetz noch") ist im selben Commit zurückgezogen, weil die Lane weg ist — der Wächter hatte diese Anweisung in der eigenen Fehlermeldung stehen. **Sieben `PianoRollModel`-Mitglieder sind ebenfalls aufruferlos** und im Dateikopf namentlich aufgeschrieben statt still gelöscht.
  · **`PatchEditorView.swift` IST GELÖSCHT (#132 Slice 6, 2026-07-31).** Die Vorgeschichte gehört hierher, weil sie zweimal in die falsche Richtung gelesen wurde: die Datei war seit dem Tools-Grid-Removal türlos, und meine frühere Behauptung, das Instrument könne „keinen Klang formen oder speichern", war FALSCH — `soundPanel` (an `dropdownContent` `.sound`, erreichbar über den Sound-Chip) IST der lebende Timbre-Editor und war es die ganze Zeit. Blockiert war die Löschung von fünf persistierten Parametern, deren einzige Zeile in der türlosen Datei stand; sie sind portiert (**`unisonVoices`/`unisonDetuneCents` mit #281, `spectralShape`/`noiseColor` und `outputLevel` mit #286**), jeder mit gerenderter Zeile UND Wächter im blockierenden Bundle (`Tests/CISmoke/UnisonRowDefaultsTests.swift`). Die **Preview-Tastatur** war kein Parameter, sondern eine Urteilsfrage — entschieden: die Spielfläche deckt sie ab, nicht portiert. Die **Preset-Leiste** (laden · favorisieren · speichern · Save-as · löschen · einreichen) ist da (⛔ hier stand „fehlte nie“ — in diesem SHALLOW-Klon, gepfropft auf `24e9420`, liefert `git log -S` auf die Aufrufstellen nur den Graft; die Gegenwart ist belegbar, die Vorgeschichte nicht, und genau solche unbelegten „schon immer“-Sätze streicht diese Datei an anderer Stelle selbst): `presetRow` hält alle sechs, seit `Tests/CISmoke/SoundPanelPresetBarTests.swift` auch nachweislich — und DAS ist der Grund, warum die Löschung nichts gekostet hat. ⚠️ Die `outputLevel`-Hälfte hing einen Monat an einer Begründung, die faktisch falsch war (ein Quellkommentar erklärte einen manuellen Trim für unvereinbar mit `loudnessNormalized()`; das läuft **einmal** beim Bau der `static let factory`-Liste und kann eine Nutzer-Eingabe nie überschreiben, was das Feld-Doc seit dem ersten Tag sagt). **Lehre: ein „gehört dem Founder"-Vermerk mit prüfbarer Begründung gehört geprüft, bevor er eine Aufräumarbeit blockiert.**
  · **`ImmersiveStageView` (spatial stage) stays doorless — deliberately.** Ship-gate item 4 makes light/space "demonstrable, not required for v1" (#131c).
  · **Correction to a claim I made about the roll:** presenting it is NOT what publishes `MusicalFrame`. That publish is in `PianoRollModel`'s tick handler (`PianoRollView.swift`) on the shared sequencer tick, installed once at app start (`pianoRoll.start(...)` in `EchoelmusicApp`) — so the visual/light output stage is lit whether or not the roll is open. The door is load-bearing for EDITING, not for the spine.
  · **NEEDS-FOUNDER-VERIFY:** launch (the +1 modifier vs the black-screen law). ⛔ Die zweite Hälfte — „and the roll's Stop, which cascades the ONE-Stop law … and ends the whole bio session" — ist **HINFÄLLIG**: dieser Knopf saß in der `PianoRollView`-`struct`, die #475 gelöscht hat. Ein Verify-Posten, der auf ein entferntes Bedienelement zeigt, kostet den Founder eine Geräteprobe, die nichts entscheiden kann. Der ÜBERLEBENDE Produzent des Playback-only-Stopps ist das Transport-■ in `WorkspaceView` (`pianoRoll.requestPlaybackOnlyStop()`, #179), und den pinnt `OneStartControlTests.testThePlaybackOnlyStopHasAReachableProducer` im blockierenden Bundle.
  Music theory is fully in-house. The real remaining frontier is **P3 Video** (⛔ korrigiert 2026-07-31: „no recorder/trim/export yet" war falsch für zwei Drittel — RECORDER und EXPORT existieren und sind erreichbar, `VisualRecorder` + `FloatingVisualWindow`s Aufnahmetaste + `videoPanel` → `VideoLibraryPanelContent` mit mp4-Share. Was fehlt, ist der TRIM/SCHNITT, mit #121 Slice 3 absichtlich entfernt) and **P4 Broadcast**. See `scratchpads/PLAN_REDOOR_CRAFT_TOOLS_2026-07-25.md`.
- **Files:** **369** Swift under `Sources/` (Stand 2026-08-21, #696 — gemessen, nicht fortgeschrieben: der Zuwachs gegenüber 368 ist GENAU EINE Datei, `DSP/EchoelGranular.swift` (#684), belegt mit `git log --diff-filter=A --name-only`. Der vorige Stand war 2026-08-20 — seit #644s Commit waren es 368 GETRACKTE; die erste Fassung dieser Zeile schrieb „367 getrackt plus die in diesem Commit angelegte `Studio/LiveNarrationDisclosure.swift`", was am Tag des Schreibens stimmte und beim ersten `git commit` ungültig wurde — **eine Zahl, die eine UNGETRACKTE Datei mitzählt, beschreibt einen Zustand, der genau einen Commit lang existiert**; #644s Review fand den Stand bei 362, also SECHS daneben und schon vor dieser Scheibe veraltet; `git ls-files 'Sources/**/*.swift' | wc -l`, die ZÄHL-KETTE — jeder frühere Stand, die Taxonomie ±0/+1/+2/−1 und jede ⛔-Rücknahme — steht seit 2026-08-12 in `memory/LEDGER_COUNTS.md` §B (#538); MESSEN statt zitieren, und dort nachführen), **ZERO Metal files** — corrected 2026-07-25; the old "~212 Swift + 1 Metal (`Video/Shaders/ChromaKey.metal`)" was stale twice over: the count was long out of date and `ChromaKey.metal` was DELETED by Slice 3 (video-cut removal) together with its directory. `MetalBioView` compiles its shader inline at runtime, so the app ships no `.metal` source at all. | **Swift 100%** | top-level dirs under `Sources/Echoelmusic/`: `Audio Bio Core DSP EchoelAI Resources Sequencer Stream Studio Sync Tools Video Views`, plus the two loose top-level files `EchoelmusicApp.swift` and `MicrophoneManager.swift`. NOTE: the "four pillars" (EchoelTools/Works/Sync/Well) referenced by older vision docs were **never built as modules** — `EngineBus` is the one real coupling spine; `Views/` now holds only `MetalBioView` + `OnboardingView` (its long deprecated list is gone).

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
  auflösen.** ⭐ **HALB ÜBERHOLT 2026-08-14 (EchoelVoice-Woche): die „0 Treffer"-Messung für
  `VoiceAnalyzer` gilt nicht mehr** — seit #592a konstruiert `VoiceCaptureEngine` den
  Analyser und füttert ihn mit echten 4096-Sample-Fenstern; die Kette erreicht eine
  erreichbare Tür (Sound-Panel → „Voice timbre"). Der ehrliche Split heute:
  **`VoiceAnalyzer` + `VoiceFrame` = VERDRAHTET** · **`VocoderMapping` = weiter 0
  Verbraucher** · **`BrainwaveModulation` = weiter 0 Verbraucher** (beides nachgemessen
  2026-08-14). Wer diesen Block liest, um zu entscheiden, was noch zu bauen ist, baut den
  Analyser NICHT neu.

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
  reached by a TAP auf die Puls-Pille (⛔ diese Zeile SAID „reached by the \"Bio\" chip" und war die ACHTE und stärkste Fundstelle des #705-Idioms — sie überlebte, weil die Nadel `Bio chip` die ZITIERTE Form `the "Bio" chip` nicht trifft, also genau die häufigste Schreibweise; #706 hat die Nadel normalisiert) — that is deliberate (B3, 2026-07-12): the always-on strip was
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
| **Watch** | Target existiert und ist **NICHT eingebettet** (`project.yml` hält `- target: EchoelmusicWatch` unter den App-Abhängigkeiten auskommentiert), `EchoelWatchApp.swift` liest den App-Group-Container **dieses Geräts** | **ein TRANSPORT — und das ist eine Entscheidung, keine HealthKit-Aufgabe (#549).** ⛔ Hier stand „Handgelenk-HealthKit-HR → **App Group** → Telefon", und diese Route existiert nicht: **ein App-Group-Container ist PRO GERÄT.** Uhr und Telefon teilen kein `UserDefaults(suiteName:)` — genau deshalb ist derselbe Code für das Widget (dasselbe Telefon) richtig und kann zwischen Handgelenk und Telefon in KEINE Richtung ein Byte tragen. Gemessen: `git grep -n "WatchConnectivity\|WCSession" -- Sources` liefert **nichts**. Wer C7 wie beschrieben umsetzt, schreibt korrekten HealthKit-Code gegen einen Kanal, den es nicht gibt — und **merkt es nicht**, weil `refreshFromSharedStore()` bei leerem Container nil liefert und die Uhr den plausiblen Leerzustand rendert („Start a session on iPhone."): eine verdrahtete Route, die nichts überträgt, sieht identisch aus wie eine unverdrahtete. `WCSession` ist ein NEUES Framework ⇒ Council/Founder VOR dem ersten HealthKit-Aufruf. ⚠️ `project.yml:296` trägt dieselbe falsche Route — **berichten, nicht editieren** (founder-gated). Wächter: `Tests/CISmoke/TheWatchHasNoTransportTests.swift`. **Harte Grenze bleibt:** ~4–5 s Latenz → Anzeige, Trend, langsame Modulation (HRV/Kohärenz), **niemals Beat-Sync** |
| **iPad** | **vier Einstellungen + ein Wächter, in EINEM Commit** (`TARGETED_DEVICE_FAMILY` an App · Widget · beiden Test-Bundles, dazu `Tests/CISmoke/DeviceFamilyIsPhoneOnlyTests.swift` — harte Gleichheit im BLOCKIERENDEN Bundle — **plus zwei Prosa-Blöcke**, die beim Ändern falsch werden: der `#`-Block über der Einstellung und die ⛔-Notiz unter dieser Tabelle) | eine dort funktionierende Bio-Quelle — kein iPad hat eine rückseitige LED, und `CameraCapture` koppelt die rPPG-Beleuchtung an `device.hasTorch`; der BLE-Gurt ist gebaut+verdrahtet, die Watch käme als zweite Quelle infrage — **plus** #292 (heute reflowen **4 von 10** Panels; Befehl siehe die Zeile „Kein ‚nie'" unter dieser Tabelle. ⛔ Diese Zelle stand auf „2 von 11", während die Zeile „Kein ‚nie'" schon „2 von 10" sagte — DIESELBE Tatsache, zwei Zahlen, 12 Zeilen auseinander, weil #359 Schritt 3 nur die untere nachführte. Der Absatz unter dieser Tabelle trägt fünf Lehren über seine eigenen Zählfehler und keine davon lautete „such nach der ZWEITEN Stelle"; sie lautet jetzt so) |
| **Vision / XR** | kein Target; `visionOS` kommt in `Sources/` nur in Plattform-Guards vor (`MicrophoneManager`, `AudioInputManager`, `SPSCQueue`, `MemoryPressureHandler`) | der natürliche Sitz ist die **Ausgabe-Stufe, die schon existiert**: `ImmersiveStageView` (türlos, absichtlich — Ship-Gate 4 sagt „demonstrierbar, nicht erforderlich"), ADM-OSC-Raum, das Visual. Bio-Quelle bliebe Telefon oder Gurt |
| **Mac** | kein Target, kein Catalyst-Flag | offen |

⛔ **Was hier bis 2026-07-31 stand, war doppelt irreführend, und die zweite Fassung desselben Tages auch.** Erst: „iPhone-only for v10 MVP. iPad / Mac / Watch / Vision deferred to v1.1+" — während `project.yml` an ALLEN VIER iOS-Targets `TARGETED_DEVICE_FAMILY: "1,2"` setzte, die App also an iPad ausgeliefert wurde. Niemand hatte das entschieden; es war ein Default, den niemand nachgelesen hat. Dann, nach der Korrektur auf `"1"` (#292), las sich der Absatz wie ein **Ausschluss** von iPad/Vision — genau falsch herum, wie der Founder Stunden später klarstellte. Die Entscheidung (v1.0 = iPhone) steht; ihre BEGRÜNDUNG ist Sequenzierung und der fehlende Sensor auf iPad, nicht ein Verzicht auf das Ökosystem.

⛔ **Und die iPad-Zeile trug bis zur Reviewer-Nachlese am selben Tag einen Slogan, der in VIER Dateien gleichzeitig stand und in jeder falsch war:** „Wiederanschalten ist EINE Zeile" (hier, in `project.yml`, im Commit-Text und in `decisions.csv`) — während der Wächter, den **derselbe Commit** installierte, wörtlich sagt „change the settings AND this test in the same commit". Zwei Sätze aus einem Changeset, die einander widersprechen; der eingängigere war der falsche. Es sind vier Einstellungen plus der Wächter plus zwei Prosa-Blöcke, die beim Ändern falsch werden. **Lehre, weil sie sich von der üblichen unterscheidet:** hier war nicht eine Zahl veraltet, sondern eine Behauptung wurde nie geprüft, weil sie gut klang und niemandem wehtat — und sie ist genau der Satz, aus dem eine künftige iPad-Rückkehr ihren Aufwand schätzt. Ein Slogan, der Arbeit KLEINER macht als sie ist, ist gefährlicher als eine falsche Zahl.

⛔ **Dieser Satz war bis 2026-07-31 eine BEHAUPTUNG, kein Zustand** — und er stand hier, während `project.yml` an ALLEN VIER iOS-Targets `TARGETED_DEVICE_FAMILY: "1,2"` setzte, die App also an iPad ausgeliefert wurde. Niemand hatte das entschieden; es war ein Default, den niemand nachgelesen hat. Founder-Frage („Sind alle Fenster adaptiv für alle Geräte?") plus Delegation („Du entscheidest zukunftsweisend") → jetzt wirklich `"1"` (#292), abgesichert durch `Tests/CISmoke/DeviceFamilyIsPhoneOnlyTests.swift`.

**Der entscheidende Grund ist der SENSOR, nicht das Layout, und er gehört hierher, weil aus dieser Zeile heraus über Plattformen geplant wird:** `CameraCapture` koppelt die rPPG-Beleuchtung an `device.hasTorch`, und kein iPad hat eine rückseitige LED. Auf iPad läuft der Finger-auf-Linse-Puls also ohne Licht — genau die Bedingung, die der 2026-06-18-Fix als Ursache fürs Nicht-Locken identifiziert hat. Ein iPad-Build stellt die eigene Prämisse („Dein Körper spielt es") auf ein Gerät, auf dem die Hauptquelle degradiert ist.

**Kein „nie".** Die großen Flächen sind die Zukunft als **AUSGABE** — externer Bildschirm/Beamer (#206), ADM-OSC-Raum —, nicht als zweite App-Oberfläche. Kommt iPad als Instrumenten-Fläche zurück, braucht es eine dort funktionierende Bio-Quelle (der BLE-Gurt ist gebaut und verdrahtet) plus den Adaptivitäts-Durchgang #292. **Der Durchgang passiert ohnehin:** iPhone allein spannt 375–440 pt, erlaubt Querformat und läuft mit ungedeckeltem Dynamic Type — heute reflowen **4 von 10** Panels: `mixerPanel`, `soundPanel` (mit sieben Gittern), seit #292 Slice 3 `moodPanel` (mit zwei) und seit #292 Slice 4 `visualPanel` (mit zwei). Die anderen sechs — `menuPanelHost`, `bioPanel`, `videoPanel`, `tempoToolsPanel`, `masterPanel`, `effectsPanel` — stapeln weiter starr. ⚠️ **`visualPanel` ist der erste Eintrag dieser Liste, der seine Gitter NICHT im eigenen Rumpf hat**, und das ist genau die Falle, vor der der ⛔-Absatz unter diesem warnt: sie sitzen in `visualAdjustFields(spacing:)`, das der Rumpf aufruft. Wer die Liste per `grep` über Panel-Rümpfe nachführt, findet `visualPanel` nicht — man folgt dem AUFRUFER, sonst zählt man es beim nächsten Mal wieder als starr. ⭐ Und Slice 4 hat als erste eine Fläche mitgenommen, die gar kein Panel ist: `visualVJOverlay` rendert dieselbe Definition und reflowt seither ebenfalls — es steht bewusst nicht im Zähler, weil der Nenner Panels zählt, aber es ist der Grund, warum `spacing` dort ein ARGUMENT ist (14 im Panel, 8 im Overlay; in einer Spalte ERSETZT das Gitter den Abstand des Wirts, ein Literal hätte also eine der beiden Flächen im Hochformat still umgesetzt). Wächter: `Tests/CISmoke/VisualFineTuneReflowsTests.swift`. ⛔ **UND DIESE ZWEITE FLÄCHE HAT KEINE TÜR — der Satz oben liest sich, als hätte sie eine, und das ist die Sorte Lücke, die keine Zahl anzeigt** (gemessen 2026-08-08, #505): `visualVJOverlay` ist an genau EINER Stelle montiert, im `.fullScreenCover(isPresented: $showVisual)`, und `showVisual` hat in `Sources/` KEINEN Schreiber von `true` — wortgrenzen-genau sind es zwei Schreiber im Code, der eigene `@State`-Initialisierer und der Schließen-Knopf, beide `false` (offene Aufgabe #270). Beide Sätze — „reflowt ebenfalls" und „tote Zweitkopie" — sind wörtlich WAHR, und nebeneinandergelegt widersprechen sie sich nur scheinbar; das REGISTER war irreführend, weil nur einer von beiden hier stand. ⭐ Die Folge ist eine ASYMMETRIE, keine Abschwächung: ein hartes **8** würde das ERREICHBARE Panel umsetzen (lebende Kosten, heute), ein hartes **14** nur eine Fläche, die niemand öffnen kann. Das Argument verteidigt also in genau EINER Richtung etwas Lebendes und ist in der anderen Buchführung für den Tag, an dem die Tür zurückkommt. ⛔ Und der teuerste Einzelbefund saß im Wächter selbst: seine Grenzen-Notiz BAT den Founder um eine Querformat-Geräteprobe „des VJ-Overlays" — eine Bitte, die niemand erfüllen kann, in dem Register, aus dem der NEEDS-FOUNDER-VERIFY-Rückstand triagiert wird. Zurückgezogen statt umformuliert; Claim 6 desselben Wächters wird rot, sobald die Tür zurückkommt, und nennt die neun Dateien, deren „türlos"-Prosa dann im selben Commit mitzuziehen ist. (Der Nenner war bis #359 Schritt 3 elf; `sessionPanel` ist mit diesem Schritt gelöscht, sein einziger Inhalt `placeRow` sitzt jetzt in „Save & Export". Zähl mit `grep -c "private var \w*Panel\w*: some View"`, nicht aus dem Kopf — genau diese Zeile trägt vier Absätze über ihre eigenen Zählfehler. ⚠️ Und der Befehl misst die NAMENSFORM, nicht die Sache: er zählt `menuPanelHost` mit, das der Wirt ist und kein Panel, und übersieht `utilityRow`, das eines der Dropdown-Panels IST und nicht reflowt. Die zehn stimmen als Zahl, die MENGE ist um je einen daneben — wer die Panels einzeln durchgeht, muss beide Abweichungen kennen.)

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
Tests/EchoelmusicTests/ ← die NICHT-blockierende Suite. **MESSEN, nicht zitieren:**
                          `git ls-files 'Tests/EchoelmusicTests/*.swift' | wc -l` (2026-08-21: 314).
                          Das BLOCKIERENDE Bundle ist eine ANDERE Suite — es baut aus
                          `Tests/CISmoke` (`git ls-files 'Tests/CISmoke/*.swift' | wc -l`); wie dort
                          ein Wächter geschrieben, benotet und gemeldet wird, steht in
                          `Tests/CISmoke/CLAUDE.md`. Die Beschriftung in `full-tests.yml` nennt eine
                          dritte Zahl und bleibt vorerst falsch — founder-gated (#208).
                          ⭐ **Ein Name ist genauso ein `git ls-files` wert wie eine Zahl** — die
                          Disziplin dieses Absatzes zielt auf veraltete ZAHLEN, während ein
                          erfundener Dateiname daneben ungeprüft durchläuft (#474).
                          ⛔ **Die ZÄHL-KETTE — jeder frühere Stand, jede ⛔-Rücknahme — liegt in
                          `memory/LEDGER_COUNTS.md` §C (#702; §A = `Tests/CISmoke`, §B = `Sources`).
                          KEINE Zeile ist gelöscht. Wer eine Zahl nachführt, führt sie DORT nach.**
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

**LIVE (4 — a producer derives each from the frame):** Coherence → **filter cutoff · brightness · harmonicity · noise level** | HRV → **brightness** | Heart rate → **vibrato depth AND rate · brightness** | Breath phase → **amplitude (the breath swell)**

⛔ **„HRV → brightness · **reverb mix**" ist am 2026-08-12 GESTRICHEN (#546), und der Grund ist eine Klasse, die diese Tabelle bisher nicht kannte.** `applyBioReactive` SCHREIBT `reverbMix` wirklich aus `hrvVariability` (`EchoelDDSP.swift:2195`) — die Zeile war also nicht erfunden, sondern an der Zuweisung korrekt abgelesen. Aber `reverbMix` wird an **genau einer** Stelle GELESEN, innerhalb von `if Self.useConvolutionReverb, reverbMix > 0, …` (`EchoelDDSP.swift:1503`), und `useConvolutionReverb` steht auf `false` **ohne jede Zuweisung** in `Sources/` (`git grep -n "useConvolutionReverb *=" -- Sources` liefert die Deklaration und sonst nichts). Die Stufe kann keinen Klang erzeugen. ⭐ **Der Unterschied zu #496 ist die Richtung, und deshalb steht er hier:** dort waren es drei Kanäle OHNE ERZEUGER — nichts schrieb sie. Hier schreibt ein Erzeuger sauber in einen **Verbraucher, der zur Laufzeit ausgeschaltet ist**. Dem Wert einen Sprung weit zu folgen sieht nach Sorgfalt aus und hört einen Sprung zu früh auf. **Eine Abbildung ist live, wenn der Schreibvorgang einen UNGATED Lesevorgang erreicht** — der billige Test ist ein `grep` auf die LESER des Ziels, nicht nur auf seine Schreiber. ⚠️ **Nicht mit dem Reverb der FX-Fläche verwechseln:** `EchoelReverb` in `EchoelFXChain` ist algorithmisch, wird von den Genre-Presets eingeschaltet, und eine Bio-ROUTE auf seine Parameter ist über die Modulationsmatrix erreichbar — der Hinweis „coherence → reverb" in `EchoelFXView` ist WAHR und darf aus diesem Absatz heraus nicht „korrigiert" werden. Tot ist allein die Convolution-Stufe in `EchoelDDSP`, die nur der Always-on-Pfad berührt. Wächter: `Tests/CISmoke/DisabledReverbIsNotClaimedLiveTests` (#335) deckt jetzt auch die In-App-Zeile ab; **diese Prosa bekommt bewusst KEINEN Text-Scan** (#491 — die Datei zitiert zurückgenommene Behauptungen absichtlich, ein negativer Scan träfe seine eigene Rücknahme).

⛔ **UND DIESE ZEILE WAR EINEN ZYKLUS LANG EINS-ZU-EINS, WÄHREND DIE ENGINE ES NICHT IST** (gemessen 2026-08-08 bei #498, an `EchoelDDSP.applyBioReactive` auf dem verankerten Patch-Pfad, also dem ausgelieferten). Sie sagte „Coherence → Harmonicity | HRV → Brightness | Heart rate → Vibrato | Breath phase → Envelope" — **ein Ziel je Kanal, und Kohärenz allein bewegt VIER.** Das ist keine veraltete Zahl, sondern eine Form, die von Anfang an zu ordentlich war: eine Tabelle mit vier Zeilen und vier Pfeilen liest sich vollständig. **#496 hat die ÜBER-Behauptung dieser Tabelle korrigiert (sieben Kanäle, drei ohne Erzeuger) und ihre UNTER-Behauptung dabei stehen lassen** — beide Fehler saßen in derselben Zeile, und nur einer fiel auf, weil nur einer sich als Zahl zählen ließ. Wer eine Bio-Fläche AUS dieser Tabelle baut, hätte damit eine frische Untertreibung auf genau den Bildschirm geliefert, den #496 gerade für eine Übertreibung repariert hat. **Lehre, verschieden von der Stale-Zahl-Lehre: eine Aufzählung wird gegen den CODE geprüft, nicht gegen ihre eigene Symmetrie.**

⚠️ **EINE BEDINGTE ABBILDUNG STEHT ABSICHTLICH NICHT IN DER ZEILE, weil ihre Nennung MEHR irreführen würde:** auf dem `.harmonicSeries`-Map-Profil übernimmt HRV die Harmonizität ganz (`0.40 + hrv * 0.50`) und überschreibt den Kohärenz-Term darüber. Sie zu nennen suggerierte, ein Spieler könne sehen, welches Profil aktiv ist — kann er nicht, es ist eine Patch-Eigenschaft. Was oben steht, gilt unter JEDEM Profil. Der Typ, der diese vier Kanäle für die Oberfläche beschreibt, ist `Studio/AlwaysOnBioChannel.swift`, und sein Dateikopf trägt dieselbe Messung samt Ausnahme.

⛔ **DREI WEITERE STANDEN HIER ALS GLEICHRANGIG UND HABEN KEINEN PRODUZENTEN** (gemessen 2026-08-08, #496): **Breath depth → Noise · LF/HF → Spectral tilt · Coherence trend → Shape morphing.** `git grep -n "PolyBioParams(\|BioParams(" -- Sources` findet GENAU ZWEI Konstruktionsstellen — `PolySynthVoice` und `BioReactiveSynthVoice` —, und **beide** schreiben die Literale `breathDepth: 0.5`, `lfHf: 0.5`, `coherenceTrend: 0`. `BioSampleFrame` hat weder ein Tiefen- noch ein LF/HF- noch ein Trend-Feld. Konsequenz je Zeile, an ihrem Verbraucher nachgelesen: `breathFactor` ist auf jedem Frame exakt 1,0 (die Zeile reduziert sich auf ein Zurückschreiben des Patch-Werts, was der eigentliche #279-Fix ist); `lfHfRatio` wird im Rumpf gar nicht gelesen (der Sanitizer sagt das selbst); und `trendMag = abs(0)` heißt, das Deadband gewinnt IMMER — der ganze steigend/fallend-Spektralmorph ist unerreichbar.

⭐ **Zwei der drei waren am VERBRAUCHER längst aufgeschrieben, `coherenceTrend` als einziges nicht** — und genau deshalb hat diese Tabelle es überlebt. **Die Lehre ist nicht „Tabelle nachführen", sondern: ein ⛔-Vermerk am Verbraucher erreicht die Zeile nicht, die eine Sitzung ZUERST liest.** Diese Tabelle ist die Stelle, aus der Store-Text, Website und Panel-Kopie ihre Bio-Behauptungen holen; die #496-Scheibe musste die Fläche reparieren, die genau daraus „sieben" hätte machen können. Wächter: `Tests/CISmoke/TheAlwaysOnBioPathIsNamedTests.swift` nagelt die Pins an BEIDEN Konstruktionsstellen fest und verbietet der Panel-Kopie, die drei zu nennen. **Nicht als „live" zitieren, in keiner nutzersichtbaren Kopie** — der Code für alle drei bleibt bewusst stehen, weil ein echter Produzent (z. B. ein Trend aus der Kohärenz-Historie) eine eigene Scheibe ist und genau diese Zweige antreiben wird.

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

## TEMPO INVARIANT — T1·T2·T3 (ratified 2026-08-13, founder handover)

⭐ **Der Flow-Servo BLEIBT.** `BioComposer.tempo(for:)` rechnet unter `.flowFree`
`hr·(1−Kohärenz) + 72·Kohärenz`: die Uhr folgt dem Puls und konvergiert von ihm WEG, je
ruhiger der Körper wird. Das ist ausgeliefert und am Gerät abgenommen (2026-06-22, verfeinert
07-03/07-04) — und es widersprach einer Doktrin-Zeile, die HR→Tempo pauschal verbot. **Ein
Invariant, das das ausgelieferte Produkt verletzt, ist kein Invariant, sondern eine Falle für
jede spätere Sitzung:** sie repariert entweder funktionierendes Audio oder lernt, die Doktrin
zu ignorieren. Das Verbot war gegen „dein Herzschlag IST der Beat" gemeint — rohes Signal, 1:1,
mit jedem Artefakt zitternd. Der gebaute Servo ist kohärenz-gegated, geglidet und geklammert.
Deshalb wird die Regel PRÄZISIERT, nicht gelöscht.

- **T1 — Tempo-Quellen sind aufzählbar und werden geloggt.** Das Tempo darf nur von (a) einer
  Nutzer-Geste (Lock, Feld-Edit, Tap, geladenes Projekt), (b) dem Flow-Servo, (c) einer
  Automations-Lane gesetzt werden. Die Transport-Play-Zeile trägt `tempoSource=`.
  ⚠️ **Die Aufzählung ist VIER, nicht drei** — der Beschluss sah einen Pfad nicht: die
  Modulations-Matrix-Destination `ModDestinationKey.tempo` in `EchoelmusicApp` ist eine
  vom Nutzer konfigurierte ROUTE, die einen Bio-Wert trägt; weder Servo (anderer Mechanismus,
  andere Klammer) noch gespeicherte Kurve. Sie heißt `.modulationRoute` und ist heute schlafend
  (leere Default-Matrix, null `ModRoute(`-Konstruktionsstellen, #541). Sie in eine der drei zu
  falten hieße, ein falsches Wort in genau die Log-Zeile zu schreiben, für die T1 existiert.
- **T2 — Rohe Herzfrequenz erreicht die Uhr nie direkt.** Kein Pfad darf eine BPM-Schätzung
  (rPPG, BLE, HealthKit) ohne Servo (Kohärenz-Blend + Klammer + Glide) oder ohne ausdrückliche
  Nutzer-Geste an den Takt geben. `.studioLocked` ist beweisbar unabhängig von `heartRateBPM`.
  ⚠️ **Die Zahlen stehen im CODE, nicht hier.** Der Beschluss nennt „Klammer 40–160" und das
  ist zum Zeitpunkt der Ratifizierung exakt richtig (`min(max(pulled, 40), 160)`) — sie hier
  ein drittes Mal auszuschreiben wäre die #416-Falle in dem Dokument, das Tempo-Mehrdeutigkeit
  gerade beendet. Wer die Klammer prüft, liest `BioComposer.tempo(for:)`.
- **T3 — CI-erzwungen, nicht dokument-erzwungen.** `Tests/CISmoke/TempoInvariantTests.swift`
  IST das Invariant. Prosa, die einem grünen Test widerspricht, ist veraltete Prosa.

⭐ **Der Engpass ist `PatternEngine`, und das ist der Grund, warum `Transport.setTempo` KEIN
`source:` bekommen hat.** Gemessen 2026-08-13: jedes `transport?.setTempo(…)` in `Sources/`
steht in `PatternEngine.swift` (sechs Stellen, davon drei auf dem TICK-Pfad eines laufenden
Glides). `Transport.setTempo` hat keinen eigenen Produktions-Aufrufer. Die Quelle an den zwei
`PatternEngine`-Methoden zu benennen benennt sie also für die ganze App, während das Relais ein
Relais bleibt — ein `source:` dort müsste auf dem Audio-Rate-Pfad etwas wiederholen, das er
nicht wissen kann, und ein Breadcrumb dort loggte mit 20 Hz. `source:` hat an beiden Methoden
**keinen Default** (#431/#440/#443: ein defaultetes Argument, das keine Aufrufstelle schreibt,
taucht in keinem Diff auf). Claim 4 des Wächters nagelt den Engpass fest, Claim 5 den fehlenden
Default.

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
| `auto-merge-claude.yml` | **Entscheidet, was `main` erreicht** — siehe den ⛔-Absatz direkt unter dieser Tabelle |

⛔ **DIESE TABELLE HAT VIER MONATE LANG DEN WORKFLOW VERSCHWIEGEN, DER ENTSCHEIDET, WAS `main` ERREICHT** (nachgetragen 2026-08-21, #683). Sie nannte fünf von vierzehn Dateien in `.github/workflows/`, und `auto-merge-claude.yml` war keine davon — genau die Register-Lücke, die diese Datei an anderer Stelle „teurer als eine falsche Zahl" nennt, weil sie gar nicht erst als Frage auftaucht.

**Der Befund, gemessen: der Merge nach `main` wartet auf KEIN Gate.** Der Workflow feuert auf `push` nach `claude/**` und merged sofort. Er hat **kein `needs:`**, **keinen `workflow_run:`**-Trigger und liest **keine** fremde Conclusion (`grep -n "needs:\|workflow_run\|conclusion" .github/workflows/auto-merge-claude.yml` → nichts) — er KANN also strukturell nicht auf `Xcode Compile Check` oder die CI/CD-Pipeline warten. Die drei laufen parallel, und der Merge gewinnt. Er pusht direkt (`git push origin main`), es gibt keinen Pull Request, der die Checks dazwischenstellen würde.

⭐ **Und das ist keine Theorie:** #681 ist am `Xcode Compile Check` gescheitert (Lauf 32457537356, `f61be63`) und steht trotzdem auf `origin/main`. #682 hat zehn Minuten später repariert — aber in diesen zehn Minuten hat `main` nicht kompiliert, und nirgends stand, dass das möglich ist.

⚠️ **Das VERHÄLTNIS gehört dazu, sonst liest sich der Absatz alarmistischer als der Zustand ist:** der TestFlight-Dispatch im selben Workflow steht auf `if: false` (abgeschaltet 2026-06-16 wegen Apples Upload-Kontingent). Ein ungetesteter Merge erreicht also `main`, aber **nie einen Nutzer**; Deploy bleibt absichtlich (`.deploy/release`). Fällt dieses `if: false`, ändert sich die Schwere des Befunds sofort — deshalb ist es mitgepinnt.

**Reparatur ist founder-gated** (`.github/workflows/**` = berichten, nicht editieren). Wächter: `Tests/CISmoke/TheAutoMergeWaitsForNoGateTests.swift` — er verbietet das Gate NICHT (#364); er wird an dem Tag rot, an dem der Founder eins einbaut, und nennt in seiner Fehlermeldung diesen Absatz als die Prosa, die dann im selben Commit mitzuziehen ist.

⛔ **UND DER ZWILLING DAZU (#697/#698/#699): ein Commit, der NUR `CLAUDE.md`, `memory/**` oder `scratchpads/**` anfasst, löst KEINEN eigenen Merge aus.** Die Filter stehen NICHT hier — sie sind schon in `ContentPipeline/README.md` unter #252 aufgezählt, zusammen mit `README.md`, `fastlane/**` und `.deploy/release`, die dasselbe Loch haben; eine dritte Abschrift wäre #416. ⭐ **Was #697 dort NICHT gelesen hat und was diesen Absatz kostet:** es schrieb „erreicht `main` NIE durch Automatik" — und `ContentPipeline/CLAIMS.md` sagte im selben Baum das Gegenteil („ein Commit, der beide anfasst, zieht diese Datei mit nach `main`"). Der Merge nimmt `${{ github.sha }}`, also die GANZE Vorgeschichte: ein Gesetzes-Commit fährt als **PASSAGIER** mit (gemessen: `c86a351` auf #695, `4ef259b` auf #697, `main` liest seither 369). **Die Über-Behauptung war aus dem Repo widerlegbar, eine Stunde bevor ich den Workflow las** — und die Momentaufnahme von `main`, die ich als Beleg zitierte, sieht bei „nie" und „noch nicht" identisch aus. ⚠️ Der Befund überlebt schwächer und echt: die Drift hält **bis zum nächsten Code-Commit** (unbegrenzt lang) und wird **dauerhaft**, wenn ein Zweig darauf ENDET — der Normalfall am Ende eines 24-h-Mandats; Signal gibt es keins. ⚠️ Und sie ist nicht folgenlos für `docs/`: `auto-merge-docs.yml` diffed `origin/main..<sha>`, ein einzelner Nicht-docs-Commit in der Delta setzt `docs_only=false`, der Cherry-Pick wird übersprungen und der Job endet trotzdem grün (`HARNESS_LEDGER`). Ein wartender Gesetzes-Commit **blockiert also den Docs-Merge**. Wächter: `Tests/CISmoke/TheLawFileNeverReachesMainByItselfTests.swift` (#364: verbietet nichts, wird rot, wenn ein Filter sich öffnet).

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
/echoelmusic/bio/synthetic       float 0|1  — 1 = Demo-Generator, 0 = echter Körper (#639).
                                 PREPENDED und auf den BATCH gegated: begleitet jeden Frame,
                                 der mindestens einen gemessenen Wert sendet, und fehlt in
                                 einem stummen Frame ganz — #245 bleibt unangetastet. 0 ist
                                 hier eine TATSACHE, kein fehlender Messwert. EIGENE Adresse,
                                 KEIN zusätzliches Argument: ein zweiter Float auf
                                 `/heart/bpm` bräche jeden Integrator auf dem alten Vertrag.
                                 Über UDP nicht reihenfolge-garantiert → als ZUSTAND latchen.
                                 ⛔ ADM-OSC, Art-Net und sACN tragen weiterhin KEINE Herkunft,
                                 und die Gründe sind VERSCHIEDEN: `/adm/obj/{n}/*` ist ein
                                 FREMDER Standard-Adressraum — dort etwas zu erfinden wäre das
                                 Gegenteil der Offene-Standards-Haltung. ⛔ Für DMX stand hier
                                 „hat gar keinen Platz für Metadaten (ein echtes ‚geht nicht')"
                                 und das ist FALSCH: ein Universum hat 512 Slots,
                                 `ArtNetSender.dmxChannels` belegt VIER (Dimmer + R + G + B),
                                 acht bei 16 Bit. Es fehlt eine KONVENTION, nicht der Platz —
                                 ein schwächeres Argument als ein „geht nicht", und genau die
                                 Sorte Über-Behauptung, die diese Scheiben-Familie abbaut.
                                 Die Event-Adressen unten tragen sie ebenfalls nicht
                                 (anderer Codepfad, `drainAndSendEvents`).
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
| `LEDGER_COUNTS.md` | **Zähl-Ketten (Provenienz).** ~580 KB. **NICHT beim Sitzungsstart lesen** — nur öffnen, wenn eine Zahl nachzuführen ist (#538) |

**SESSION START (mandatory):**
1. Restore context from `memory/` — **but not by reading the directory whole.** The
   SessionStart hook already `cat`s the small files (`people` · `user` · `vision` ·
   `project_knowledge` · `preferences`) and prints SLICES of the two big ones
   (`decisions.md` tail-400, `inspiration_intake.md` head-60 + tail-120), each with the
   command that reads the rest. ⛔ **„Read ALL files in `memory/`" stand hier und war
   die Anweisung, die sich selbst widerlegt:** der Hook schneidet seit #533 zwei Dateien,
   weil sie zusammen 191 875 B kosteten — eine Prosa-Zeile, die „lies alles" sagt, hebt
   genau die Messung auf, für die der Schnitt existiert. Seit #538 liegt zusätzlich
   `LEDGER_COUNTS.md` dort, das allein ~580 KB wiegt; wer die Zeile wörtlich befolgt,
   verbrennt mehr Budget als das gesamte Gesetz dieser Datei ausmacht.
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
