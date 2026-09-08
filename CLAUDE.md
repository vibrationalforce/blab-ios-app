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

⛔ **Was hier stand und 2026-07-27 gestrichen wurde, weil es nichts davon (mehr) gibt:** „Beat Maker (16-step × 8-track sequencer + sampler)" — Drums, Pad-Stimmen, Sample-Import und die Sample-Bibliothek sind mit #166/#167 gelöscht, der Step-Grid überlebt nur als Takt-Clock · „Multi-track Recorder (mic over beats)" — **KORRIGIERT 2026-07-31: „nie gebaut" war falsch.** `MultiTrackRecorder` existiert und wird unbedingt konstruiert (`AudioEngine.swift:345` (Stand 2026-08-14; die Voice-Woche hat sie verschoben)); durchgereicht wird es nur hinter `FeatureFlags.audioLaneRecording` (`EchoelmusicApp.swift:1179` (Stand 2026-08-14)), und dieser Key wird NIE an `UserDefaults.register(defaults:)` übergeben (registriert sind nur `multiRoll`, `voiceKindRouting`, `instrumentHome`) — löst also zu `false` auf. Ehrlich ist: **gebaut, flag-gated AUS, türlos (#204)**. Der Unterschied ist nicht kosmetisch: „nie gebaut" lässt eine Session neu bauen, was schon da ist · „Video Capture & Trim" — **halb**: der SCHNITT ging mit #121 Slice 3, die AUFNAHME nicht. `VisualRecorder` wird in `EchoelmusicApp.swift:181` konstruiert, die Aufnahmetaste sitzt im erreichbaren `FloatingVisualWindow`, und `videoPanel` → `VideoLibraryPanelContent` ist die erreichbare Bibliothek mit mp4-Export. (⛔ Die zweite REC-Taste im `showVisual`-Vollbild ist mit dem Vollbild selbst GELÖSCHT, #1069 — es gibt heute genau EINE Aufnahme-Bedienstelle.) · „RTMP Live Stream" — nie verlinkt (`BroadcastPublisher` ist ein Compile-Guard-Gerüst). **MPE** bleibt aus dem I/O-Satz gestrichen — aber ⛔ **die BEGRÜNDUNG, die hier stand („`mpeEnabled`/`expressionEnabled` haben seit dem Tools-Grid-Removal keinen Schreiber"), ist mit #713 hinfällig**: beide sind jetzt persistiert und haben zwei Schalter in der Routing-Fläche. Wahr ist seither eine ANDERE Hälfte: **MPE OUT ist real und schaltbar, MPE IN nicht** (#548 — `MIDIBusPublisher` parst MPE-Verkehr, unterscheidet aber keine Zonen, und `apply(controller:)` liest `event.channel` nirgends — die drei Dimensionen selbst klingen seit #939/#942). Ein „MPE"-Satz im I/O-Set würde also weiterhin die Hälfte behaupten, die fehlt. Diese Zeile ist die Identitäts-Zeile der Datei — sie muss der Wahrheit folgen, sonst plant die nächste Session aus ihr heraus Features, deren Fundament abgerissen ist.

---

## CURRENT STATE

- **⭐ PRODUCT DEFINITION (canonical, 2026-07-25 — read `docs/dev/PRODUCT_DEFINITION.md` before any scope decision).** Founder delegated the call in full ("Du entscheidest… einfach zu begreifen, zu vermarkten und zu pflegen"); decided via Grand Council.
  **One sentence: Echoel is a bio-reactive instrument — your body plays it, and its output is multidimensional (sound, image, light, space).** There is no second product and no acronym.
  **"DMMW" is RETIRED** (unrepeatable, put a solo dev on DAW turf, infinite maintenance surface; the 2026-07-19 Council already logged "Fokusverlust seit DMMW"). `docs/dev/DMMW_ARCHITECTURE.md` is superseded — history only, do not plan from it. The multidimensional half survives as the instrument's **output stage** (one bus: `BioFrame` + `MusicalFrame` → visual · light/Art-Net+sACN · space/ADM-OSC · haptics), never as its own product. Adding a medium = adding a subscriber, never a new surface.
  **THE BOUNDARY that decides every keep/cut — Editor ≠ Workstation:** is it about the sound being made *now* (KEEP: generative engine, Flow/Loop, **patch editor**, ~~**piano roll**~~ [der Grundsatz gilt, die Instanz nicht: der Founder hat den Noten-Editor am 2026-07-26 gestrichen, #178 nahm die Tür, #475 die 988-Zeilen-`struct` — als Beispiel für „Craft tool, kein DAW" bleibt er lesbar, als Bestandsangabe ist er falsch], genres, output stage, export) or about arranging material *over time* (CUT: timeline/arrangement/clips, multi-track & mixer, audio-file regions, video edit, AUv3 host+target, RTMP, subscriptions)? **Craft tools are instrument controls, not DAW surfaces** — a synth you cannot tune is not an instrument. (⚠ The parenthetical that stood here — *"Hard technical reason the piano roll stays: `PianoRollView` PUBLISHES `MusicalFrame`"* — was FALSE, and line 49 below already said so: the publish lives in `PianoRollModel`'s tick handler, installed once at app start, view or no view. It is corrected here too because THIS is the line a session reads when deciding whether a removal is safe, and as written it would have made one refuse the founder's 2026-07-26 removal on a technical ground that does not exist. **`PianoRollView` = the editor, removed. `PianoRollModel` = the note engine + `MusicalFrame` publisher, KEPT** — that one is genuinely load-bearing.)
  **SHIP GATE "Instrument-Complete v1"** — replaces the dead *"bis die gesamte DMMW auf Profi-Level ist"* (unreachable once the workstation half was dismantled). Five binary checks, all true → v1 is instrument-complete and the App-Store step is the founder's (⛔ "lift the TestFlight freeze" stood here — that freeze was lifted 2026-07-17/07-31 and builds ship every green round; audit 2026-09-02): **1. Klang** (curated genres professional, identity survives, no convergence bug) · **2. Kontrolle** (patch editor reachable — `soundPanel` behind the Sound chip; **the piano-roll half of this check is RETIRED by founder decision 2026-07-26, "Pianoroll soll raus"** — the note editor is gone on purpose, so do not read this gate as blocked by its absence) · **3. Modi** (Flow + Loop) · **4. Ausgabe** (visual live + contemplative on device; light/space demonstrable, not required) · **5. Stabilität** (clean launch, no black screen, no menu freeze).
  ⭐ **WER JEDEN CHECK ENTSCHEIDET — nachgetragen 2026-08-22 (#750), weil „fünf binäre Checks" nicht sagt, welche eine Sitzung selbst schließen kann und welche dem Founder gehören. Ohne das liest sich der Rückstand größer als er ist, und die Freeze-Frage wird nie gestellt.** Gemessen, nicht geschätzt: **1. Klang = FOUNDER-OHR.** Die strukturelle Hälfte ist gepinnt (`GenreFamilyDistinctnessTests`: kein Paar der angebotenen Genres teilt einen hörbaren Fingerabdruck) — dass eines davon GUT klingt, beweist nichts im Repo · **2. Kontrolle = ERFÜLLT, code-belegbar** (`soundPanel` hinter dem Sound-Chip, Preset-Leiste durch `SoundPanelPresetBarTests`) · **3. Modi = ERFÜLLT, code-belegbar** — und der Check meint etwas Engeres, als sein Name nahelegt: **„Loop" ist der MODUS, nicht die Bar-Anzahl.** `ComposerMode.init(locked:)` sagt es selbst — Loop = `studioLocked` (fester BPM für Produktion/DAW-Übergabe), Flow = `flowFree` (Tempo folgt dem Körper). Beide sind EINE Wahrheit, das BPM-Schloss, dessen Knopf in `BodyTempoField` sitzt. ⛔ Erste Fassung: `BioComposer.mode(locked:)` (Name existiert nicht) plus der Loop-Längen-Picker als Beleg — der misst Takte, nicht den Modus. Nachlese im SESSION_LOG · **4. Ausgabe = CODE-HÄLFTE ERFÜLLT seit #748** (schwebendes Fenster + Donut-Renderer, beide mit Tür; ⛔ Vollbild-Feld und VJ-Overlay sind mit #1069 gelöscht), die Hälfte „kontemplativ AUF DEM GERÄT" ist ein Blick, kein Test · **5. Stabilität = NUR GERÄT.** ⚠️ Also: zwei Checks zu, einer halb, und **die zwei offenen sind BEIDE sensorisch** — keine Sitzung kann sie durch Bauen schließen. Wer hier „noch viel zu tun" liest, liest falsch; was fehlt, ist eine Geräte-Session. **Deren Einkaufszettel druckt `python3 scripts/founder-verify.py`** (#752): es sammelt jeden `NEEDS-FOUNDER-VERIFY`-Vermerk aus `Sources/`, `Tests/` und dieser Datei zu einer Liste nach Bereichen — vorher Fließtext und als Warteschlange unsichtbar. ⛔ **Hier stand „heute 50 Bitten in 48 Dateien“ und beide Zahlen waren abgelaufen (#810: das Werkzeug sagt 51 in 49).** Die Zahl ist NICHT nachgeführt, sondern GELÖSCHT — sie ist ein Datum, kein Sachverhalt, und #752 hatte den Befehl schon danebengeschrieben: **die Zeile daneben IST die Messung, der Rückstand steht nirgends mehr als Literal.** ⚠️ Ein Handzählen ersetzt sie nicht: `git grep -l NEEDS-FOUNDER-VERIFY -- Sources Tests CLAUDE.md` liefert **50 Dateien**, weil es die vier NOT-ASKS-Prosastellen und diese Datei mitzählt — zwei Nenner für eine Sache, und genau der Grund, warum hier der BEFEHL steht. Diese Zeile bekommt bewusst KEINEN Wächter: ein negativer Scan auf CLAUDE.md träfe diese Rücknahme selbst (#491). ⛔ **Hier stand „Es weiß NICHT, welche schon beantwortet sind (es gibt keine ‚erledigt'-Konvention)" — mit #773 hinfällig.** Die Konvention ist `VERIFIED-JJJJ-MM-TT` auf DERSELBEN Zeile wie der Marker; markierte Bitten wandern in einen ANSWERED-Abschnitt, werden aber nie gelöscht (das Datum ist die Antwort auf „wann zuletzt bestätigt"). Sie verlangt ein ECHTES Datum, nicht das Wort — sonst hätte das Werkzeug seine eigene Dokumentation als Antwort gelesen (#753 eine Ebene höher). Heute trägt **keine** Bitte die Marke; welche erledigt sind, weiß nur der Founder. ⛔ **Und DIESE Zeile zählte sich selbst als Bitte mit** (#753): der Marker ist auch ein gewöhnliches Substantiv, das Werkzeug las seine eigene Beschreibung als 54. Auftrag. Vier solche Prosa-Stellen — zwei hier, zwei in Wächter-Köpfen — stehen jetzt getrennt unter „NOT ASKS".
- **Branch:** run `git branch --show-current` — the literal used to be pinned here and was wrong for weeks. Prior cycles auto-merged to `main`.
- **Mode:** RALPH WIGGUM LAMBDA — one feature/fix per cycle, build → test → ship → loop
- **Positioning:** "The first bio-reactive performance instrument" — and, per the 2026-06-06 deep-research roadmap, the **bio-reactive object source for accessible immersive multidimensional media art** (open standards: ADM-OSC, MIDI 2.0, OSC, BLE HRS; no SDK lock-in). See `scratchpads/STRATEGY_STATE_OF_THE_ART_2026-06-06.md`.
- **Architecture (audited 2026-06-09 — `scratchpads/ARCHITECTURE_AUDIT_2026-06-09.md`):** `EngineBus` = `@MainActor @Observable` control plane (snapshots) + lock-free `SPSCQueue`. 3 topics — `bioFrames` / `controllerEvents` / `bioEvents`. **Bio flows over the `latestBio`/`latestBioEvent` snapshot; the SPSC queues are drained for `controllerEvents` (MIDI) — and `bioEvents` by exactly ONE consumer, `OSCSender.drainAndSendEvents` (OSC egress only, no synth sink).** Nur `bioFrames` bleibt reserved/undrained. ⛔ Hier stand „`bioFrames`/`bioEvents` … undrained" — halb falsch, in drei Dateien zugleich (Audit 2026-08-28, Details `SESSION_LOG`). Modules couple only via the bus. ⛔ **Diese Zeile sagte „(10 Hz poll)" und genau diese Zahl hat #315, #332 und #336 erzeugt — drei Zeitkonstanten, die aus ihr abgeleitet und dadurch um das 10- bis 60-Fache daneben lagen. Der POLL ist 10 Hz, die ANWENDUNGSRATE ist ~1 Hz**, weil jeder Verbraucher auf `frame.timestamp` dedupliziert und jeder verdrahtete Publisher mit ~1 Hz sendet (`CameraRPPGBioPublisher` `tick % 10` in einer 0,1-s-Schleife, Polar 1 s, Simulator 1 s, HealthKit 500-ms-Poll hinter einem 4–5-s-Sensor). ⛔ **Und die Zahl steht seit #577 nicht mehr als Literal im Code, sondern als `CameraRPPGBioPublisher.activeTickSeconds`** — die Schleife kann auf `heldTickSeconds` (0,5 s) zurückfallen, ABER nur solange iOS die Kamera hält und seit sechs Sekunden nichts ankommt, also in einem Zustand, in dem der Publish-Pfad eine Zeile früher schon an `inboundRateEMA` schließt. **Die ~1-Hz-Decke gilt damit unverändert für jeden Tick, der überhaupt veröffentlichen kann.** Der Wächter wurde dabei rot und ist mit-repariert: seine Verankerung war `milliseconds(100)`, also eine SCHREIBWEISE statt des Gesetzes; sie zeigt jetzt auf die benannte Konstante und zusätzlich auf die Bedingung des Rückfalls. **Für jede Zeitkonstante gilt die 1 Hz, nicht die 10** — der Poll ist nur die Obergrenze, die ein schnellerer Publisher erreichen könnte. Ein Wächter im blockierenden Bundle (`Tests/CISmoke/BioApplyRateIsTheDedupedRateTests.swift`) hält die Publisher-Kadenz und die Deduplizierung fest, damit diese Zeile nicht wieder still altert. ⛔ **UND ES GIBT EINE VIERTE UND FÜNFTE AUFLAGE, in einer Richtung, die dieser Absatz bisher nicht abdeckte** (gefunden in der #459-Nachlese, 2026-08-07, beide in `CameraAnalyzer.swift`): der `beatTimes`-Doc-Kommentar und danach der `rrSegments`-Doc-Kommentar schrieben „wird etwa einmal pro Sekunde neu geschrieben". Die ~1 Hz ist die **LESE**-Rate des Publishers; **geschrieben** werden beide Arrays in `detectPeaks`, das hinter `peakTick % 4` auf einem 15-fps-Feed sitzt — **~3,75 Hz**. Der Fehler ist also nicht Poll-gegen-Anwendung derselben Größe, sondern **SCHREIB-Rate gegen LESE-Rate zweier verschiedener Größen**, und er ist in der SICHEREN Richtung passiert (die reale Rate ist höher, die `@ObservationIgnored`-Begründung wird damit stärker) — weshalb nichts ihn je rot gemacht hätte. **Regel: eine Rate gehört zu genau EINER Operation; wer „~1 Hz" aus einem Nachbar-Kommentar übernimmt, übernimmt zuerst, WELCHE Operation dort gemeint war.**
- **Live pipeline:** HealthKit + **camera rPPG (live, locks on device)** + Demo → bio snapshot. (**Universal BLE HR (0x180D) = GEBAUT + VERDRAHTET**, aber **KORRIGIERT 2026-07-26 — die Tür ist NICHT die Patchbay.** Die alte Fassung hier behauptete, der Source-Port `blehrs.in` starte/stoppe `PolarH10BioPublisher` via `applyRouting` [`hasEnabledRoute(fromSource:"blehrs.in")`]. Das galt nur von B4 [2026-07-12] bis **BLE-3 [2026-07-15]**, das die Kopplung wieder entfernte: `applyRouting` war damit ein ZWEITER Lifecycle-Besitzer, der einen über die Pulse-Pille gestarteten Gurt bei JEDEM unbeteiligten Patchbay-Edit mitten in der Performance killte. **Heute hat der Gurt genau EINEN Besitzer: das Source-Dropdown der Pulse-Pille [`startBioSource`].** `blehrs.in` ist ein reiner Datenfluss-Port; `hasEnabledRoute(fromSource:)` hat **keinen Produktions-Aufrufer** — nicht daraus einen Start-Hook zurück-ableiten. Gerät-Verify wartet auf Gurt-Eintreffen [NEEDS-FOUNDER-VERIFY]. Deep Audit `scratchpads/DEEP_AUDIT_2026-07-12.md` ist an dieser Stelle ebenfalls überholt.) Pipeline weiter: bio snapshot → BioReactiveSynthVoice (EchoelDDSP; **silent until user-armed** — und „user-armed" war bis #277 eine Handlung OHNE Bedienelement: `arm()` hatte null Produktions-Aufrufer, `isArmed` konnte nie `true` werden, jeder Atem-Onset lief in `guard isArmed` und wurde verworfen. Der Satz war die ganze Zeit zutreffend und beschrieb trotzdem eine Tür, die es nicht gab; seit #277 ist der Schalter „Body voice" im `bioPanel`) + OSCSender (`/echoelmusic/bio/*`) + **ADMOSCSender** (`/adm/obj/{n}/*` immersive object out). CoreMIDI-Noteneingang → controllerEvents → EINE monophone Performer-Stimme (Noten · Pitch-Bend · Vorrang vor der Atem-Hüllkurve). ⛔ **MPE IN ist NICHT real, MPE OUT schon** (#548/#713): `MIDIBusPublisher` parst MPE-Verkehr, unterscheidet aber keine Zonen; und der Verbraucher `BioReactiveSynthVoice.apply(controller:)` liest `event.channel` nirgends. ⭐ **Alle DREI Dimensionen klingen seit #942** (Bend seit jeher, Press #939 `expressionGain`, Slide #942 `renderCutoffScale`) — **und das ist trotzdem kein MPE IN**: ohne Zonen (RPN 6,6) gibt es keinen Member-Kanal zu unterscheiden. ⛔ „eine von drei ist nicht MPE" war eine ZÄHLUNG und lief dreimal ab; die Zonen-Hälfte wackelte nie. Wer weiterbaut (Zonen), fängt NICHT am Parser an: `controllerEvents` ist SPSC mit EINEM Verbraucher, und der ist monophon — Zonen ohne zweiten Verbraucher sind wirkungslos (`scratchpads/PLAN_MPE_ZONES_2026-09-01.md`). ⭐ **GESETZ aus dieser Kette, und es gilt über MIDI hinaus: eine Fähigkeits-Behauptung hat so viele Flächen, wie jemand aufzählt** — „alle geprüft" heißt nur „alle, die mir eingefallen sind"; sieben wurden nacheinander gefunden, und das Erkennungszeichen ist, dass alle bisher geprüften dieselbe GATTUNG haben (#766/#768). Wächter: `Tests/CISmoke/TheMPEInputHasNoZonesTests.swift` — er pinnt den VERBRAUCHER, nicht diese Prosa (#491: ein Negativ-Scan auf CLAUDE.md träfe seine eigene Rücknahme). Die sieben Flächen und die vier Rücknahmen dieser Zeile: `memory/LEDGER_COUNTS.md` §N. BioEventGraph → breath/motion onsets. ⛔ **Hier stand „ModulationEngine wired (bio→tempo)" — vier Wörter, die eine LEBENDE Fähigkeit behaupten, und gemessen 2026-08-12 (#541) ist es ein Sink ohne Erzeuger.** Wahr ist die Maschine: `ModulationEngine` wird beim App-Start konstruiert, `start(subscribing: bus)` läuft, die 100-ms-Schleife tickt, und das Tempo-Ziel ist registriert (`EchoelmusicApp`, `ModDestinationKey.tempo` → `beatPlayer.pattern.glideTempo`, hinter dem globalen BPM-Lock und oktav-gefaltet). Was fehlt, ist die ROUTE: **die Default-Matrix ist LEER** — die Datei sagt das selbst zweimal — und `git grep -n "\bModRoute(" -- Sources` liefert **genau EINEN** Treffer, den `LossyDecoded`-Decoder in `ModulationMatrix.swift` selbst. ⚠️ **Die Wortgrenze im Befehl ist nicht Kosmetik:** ohne sie trifft er zusätzlich `FXModRoute(` in `EchoelFXView` — ein anderer Typ eines anderen Systems — und druckt zwei Zeilen neben einer Prosa, die „einen" sagt. Genau der `EchoelModalBank`-Fehler: ein zitiertes Rezept, das man ausführt und das der Behauptung widerspricht, wird als Widerspruch gelesen, nicht als ungenauer Befehl. **Null Produktions-Konstruktionsstellen, keine erreichbare Matrix-Fläche.** Ein von einem älteren Build persistiertes Dokument WÜRDE weiterhin das Tempo ziehen (`load()` gewinnt über die leere Default-Matrix) — genau die #527-Lage der Audio-Spuren, und deshalb nicht abklemmen. Ehrlich ist: **verdrahtet, türlos, ohne Route wirkungslos.** Der Unterschied ist nicht kosmetisch: „wired (bio→tempo)" ist die Zeile, aus der eine Bio-Fläche oder ein Store-Text „der Körper steuert das Tempo" ableitet — dieselbe Über-Behauptung, die #496 auf dem FX-Panel zurücknehmen musste, nur eine Ebene weiter oben. Wächter: `Tests/CISmoke/TheTempoDestinationHasNoRouteTests.swift` — er verbietet das Verdrahten NICHT (#364) und nennt in seiner Fehlermeldung die Prosa, die dann mitzuziehen ist. **EchoelBeat ist TOT** (korrigiert 2026-07-27): velocity/accent, swing und Per-Pad-Sample-Import standen hier weiter als live, obwohl der Founder die Drums am 2026-07-26 entfernt hat (#166). `BeatPlayer.attach(to:)` hängt nur noch `previewVoice` ein — kein Pad-Voice, kein `pattern.onStep`. Es kann heute KEIN Drum-Klang entstehen. **Der vollständige Abriss (#167) ist am 2026-07-31 FERTIG**: `DrumSynthVoice`, `LaneDrumKitVoice` und `DrumNoteMap` sind als Dateien gelöscht, ebenso `PhysicalVoiceRef.drums` und `LaneVoiceRack.kits`/`setDrumsInsert`. Die Enum-Cases `LaneVoiceKind.drums` / `TrackInstrument.drums` BLEIBEN. ⛔ **Die erste Fassung dieser Zeile begründete das mit „persistierte rawValues, ein unbekannter verwirft beim Decode die ganze Spur" — BEIDE Hälften sind falsch, und die Begründung stand gleichzeitig in vier Quelldateien.** `LaneVoiceKind` ist gar nicht `Codable` und erreicht nie die Platte (`Timeline.swift` sagt das selbst). `TrackInstrument` ist es, aber `TimelineLane`s Decoder wickelt ihn in `try? … ?? nil` — genau damit #167 überlebbar ist: ein unbekannter Case wird zu „kein eingebautes Instrument", die Spur mit Regionen, Clips, Mixer und Patch bleibt vollständig. Die WAHREN Gründe sind schwächer und stehen jetzt an den Cases selbst: `TrackInstrument.drums` löschen kostet einer Altspur ihre Instrument-WAHL (Founder sagte „erstmal"), `LaneVoiceKind.drums` ist ein toter Case ohne Produzenten, der eine eigene Entscheidung braucht. **Lehre: ein „NICHT löschen"-Kommentar mit falscher Begründung ist schlimmer als keiner — die nächste Session kann ihn nicht widerlegen.**
- **Vokal-Kette (Founder-Ask 2026-08-20) — WAS AUF SEINER STIMME LIEGT UND WAS NICHT (#700/#701):** ⛔ **JEDE „Tür"/„Sheet"-Nennung dieses Absatzes ist seit #1024 UNERREICHBAR** — das Input-Sheet lebt, kompiliert und ist vollständig verdrahtet, aber nichts setzt `showInput` mehr (Founder-Befehl, siehe die #1024-Zeile im Register unten). Gebaut ja, bedienbar nein. **Monitoring + Autotune sitzen auf dem Monitorpfad** (`input → notchEQ → voiceTunePitch → monitorMixer`; die Tune-Stufe ist seit #858 FEST verdrahtet und bei AUS bypassed — der Live-Umbau starb an fünf Geräte-Logs; beide `AVAudioUnit`-GRAPHknoten; Charakter-Presets #681 in derselben Tür `AudioInputPickerView`) — **Harmonizer auf seiner Stimme SCHALTBAR seit #841 (Tür im Input-Sheet, default AUS, session-lokal wie die Tune-Regler) · Granular auf seiner Stimme SCHALTBAR seit #849 (V1b-3: „Granular texture" im selben Sheet, default AUS; Mix/Grain/Pitch als `EchoelValueField`s mit den Spannen der FX-Panel-Reihen; EIN gemeinsamer `pushVoicePreset()` trägt BEIDE Stufen, damit keine Tür die andere zurücksetzt).** ⭐ #839 (V1b-1) hat die mic-eigene `EchoelFXChain` auf den Monitor-Insert montiert (`MonitorInsertAU`, der V1a-Knoten, dessen `insert in` seine v424-Logs beweisen) — **NEUTRAL: alle 15 Stufen explizit AUS**, Ausgang bit-exakt gleich dem Eingang (E2E-Wächter durch den echten Render-Block; die Werks-Defaults Saturation/Chorus/Limiter=AN sind Synth-Bus-Tuning und werden deshalb aktiv ausgeschaltet). FÜNF `EchoelFXChain(`-Stellen: der Insert + zwei Vorschauen in `FXCuratedLibrary` + die zwei SYNTH-Stimmen. **#841 (V1b-2) hat dem Harmonizer die Tür gegeben**: „Harmony voices" im Input-Sheet (bestehendes Sheet, Kette wächst nicht), zwei BENANNTE Intervall-Picker (`HarmonyInterval`, „keine semitone Schritte") + Mix-`EchoelValueField`; EIN Apply-Pfad in den Insert, den der #840-Raten-Neubau re-appliziert; Diag-Zeile `monitor: harmony on/off`. Default AUS — bis der Sänger schaltet, bleibt alles bit-neutral, und die KLINGENDEN Synth-Instanzen bearbeiten weiter nur die erzeugte MUSIK. Nach AUSSEN ist nichts über-behauptet — Store-Text, `ContentPipeline/CLAIMS.md` und `EchoelFXView`s Kopf sind zeilenweise geprüft und ehrlich. ⛔ **Neu ist nur der ORT, nicht der Befund:** `PLAN_VOCAL_CHAIN_2026-08-20.md`, `decisions.csv:398`, `VoicePitchCorrector.swift` und `EchoelGranular.swift` sagen es alle schon — diese Zeile ist die erste, die eine Sitzung zuerst liest. **Leiter-Stand** (`decisions.csv:398`, Mechanik #669): V1a leere Pass-Through-AU = ✅ gerätebewiesen (`insert in`, v424) · #822 `processInPlace` = ✅ · **V1b-1 Kette neutral montiert = ✅ (#839; Wächter nachweislich AUSGEFÜHRT grün; Geräteprobe = unveränderter Monitor-Klang)** · **V1b-2 Harmonizer-Tür = ✅ (#841, default aus; Geräteprobe = Toggle an → zwei Harmoniestimmen hörbar)** · **V1b-3 Granular-Tür = ✅ (#849, default aus; Geräteprobe = Toggle an → Grain-Wolke unter der Stimme hörbar, AUS → exakt der normale Monitor)** · V0 bleibt die HÖR-Bestätigung, hält den Bau aber nicht an (Founder 2026-08-25, wörtlich beauftragt: „latenzfrei… Harmonizer und Granular… ressourcenschonend“; **KEIN Voice clone**, Frage geschlossen). Wächter: `Tests/CISmoke/TheVocalChainStopsAtTheAutotuneTests.swift` (#364: er verbietet V1b NICHT; sein Kopf trägt die zwei Rücknahmen dieser Zeile — erfundenes SESSION_LOG-Zitat und der V1a-Namensdreher — damit sie nicht in der immer-geladenen Datei liegen).
- **LEBENSZYKLUS-LEITER im Absturz-Log (#859–#862b) — lesen, BEVOR man ein `echoel_diag.log` auswertet.** Jeder Eingriff in den Audio-Graphen schreibt eine Sprosse (beide `start`-Zweige, `stop`, `restartOrDegrade`, alle attach/detach, Interruption, Route-Verlust, Monitoring an/aus als `on N/5` bzw. `off N/5`; seit #878 auch die drei Sitzungs-Kategoriewechsel in `AudioConfiguration` als `session: configure|raise|lower` — das sind ABSICHTLICH nicht alle 15 Session-Aufrufe der Datei). **GESETZ: eine Sprosse steht VOR ihrem Aufruf** — ein Zeuge HINTER dem Schritt sieht nichts; stirbt der Schritt, schweigt das Log, und Schweigen liest sich dann wie „Weg nicht genommen" statt „Weg mitten im Schritt gestorben". **Folge: Stille zwischen zwei Sprossen ist ein BEFUND.** `EchoelCrashLog.breadcrumb` (unbuffered `write(2)` in die exportierte Datei) wird VOR `os_log` geschrieben — `os_log` ist dort unsichtbar und nimmt ein Schloss. Wächter: `TheEngineLifecycleSpeaksInTheDiagLogTests` (Anzahl der Ansprüche: `grep -c "    func test"` — nicht hier zitieren, sie wuchs schon einmal am selben Tag). ⚠️ Der `isInputConnToConverter`-Auslöser hat weiterhin KEINEN Namen; die Leiter repariert keinen Absturz, sie macht das nächste Log aussagefähig.
- **Protected DSP triad (READ-ONLY, now implemented):** BioSignalDeconvolver (detrend·notch·validity), HilbertSensorMapper (1D→2D Hilbert curve), BioEventGraph (heartbeat/breath/motion detectors). Pure value types, SKILL.md contracts under `.claude/skills/`.
- **SDK:** iOS 18 deployment floor (Package.swift + project.yml + Resources/iOS/Info.plist synced). Xcode 26.2 in `testflight.yml`. App Group `group.com.echoelmusic`.
- **Root view (RE-FOCUS 2026-07-06B — founder: "die Leute brauchen gar keine Atemübung. Es geht um Performance und Entspannungssteigerung dadurch, dass sich die Musik mit dem Biofeedback generativ verändert"): the bio-generative INSTRUMENT is the app HOME.** This supersedes the same-day 2026-07-06A "Session is home" flip (the founder tested it and rejected the breathing-exercise framing within hours). `WorkspaceView` body = brand header (`topBar`) + `CompositionHeaderStrip` + `EchoelStudioView()` + `FloatingVisualWindow`. (⛔ Hier stand „persistent `TransportBar`“ — mit #456 am 2026-08-07 aufgelöst: die Leiste hielt seit #411 nur noch zwei Kinder, und der Founder hat beide per Screenshot-Pfeil in die Transport-Zeile des Instruments geschickt. Die Chrome ist zwei Leisten, nicht drei.) **The Session experiment (`SessionView`/`SessionEngine`/`SessionGuide`/`SessionClock`/`EntrainmentEngine`) stays in code, compiling, but NOTHING presents it** — do not re-add a Session door/card without a founder ask; equally, do not delete those files without one (they hold the tested flash-safety/latency/pacing laws, reusable for future bio-visual work). The product bar now: the generative MUSIC must sound organic/professional and the VISUAL must be part of the experience ("wow", contemplative) — quality work goes there, not into new surfaces.
- **Studio shell internals:** brand header (`topBar`) + `CompositionHeaderStrip` + `EchoelStudioView` (the instrument) + the floating immersive visual (`FloatingVisualWindow`, toggled from the header monitor). ⛔ **Was hier stand, war ab #411 halb und ab #456 ganz falsch — und es ist die Zeile, aus der eine Session die Chrome-Struktur liest:** „persistent `TransportBar` (Play/Stop + tempo-lock button + `TransportPositionView` loop/position leaf … der eine Tempo-Regler ist das kompakte `BodyTempoField` in der TransportBar-Chrome selbst (`WorkspaceView.swift:345`))“. Davon stimmt heute NICHTS mehr: Play/Stop ging mit #289 als `PlaybackToggleButton` ins Instrument, das Tempo-Feld mit #411 in `EchoelStudioView.startControlRow`, und mit #456 sind auch die letzten zwei Kinder — das „•••“-Überlaufmenü und `TransportPositionView` — dorthin gewandert; die Leiste ist gelöscht. Der EINE Tempo-Regler ist weiterhin genau einer, er sitzt nur im Instrument. **Und die Zeilennummer war der übliche Zusatzfehler** — dieselbe Lehre wie im Absatz über die Modal-Slots: eine zitierte Phrase überlebt eine Einfügung, eine Zeilennummer nicht. **The former 6-surface bottom bar (Arrange · Clips · Compose · Mix · Bio · Browse) is REMOVED from navigation** — **von den sechs ist nur noch EINE als Datei da: `BioSourceView`** (unerreichbar, aber restaurierbar). Die Liste, die hier stand („ClipView/ArrangementView/ChannelRackView/BioSourceView … reversible by restoring the bottom bar"), war am 2026-07-27 zu drei Vierteln falsch und hätte eine Session glauben lassen, die Mix- und Clip-Flächen ließen sich durch Wiedereinhängen der Leiste zurückholen: **`ClipView` (807dc0d) und `ArrangeTimelineView` (eb58e7a) sind mit #121 Slice 4 gelöscht, `BrowserView` und `ChannelRackView` mit #167 (2026-07-27)** — letzteres mischte 8 Kanäle, die keinen Klang mehr erzeugen. Wiederherstellen hieße hier neu bauen, nicht wieder anhängen. Do not "restore" them without a founder ask. **Video page = designed + DEFERRED** (`scratchpads/PLAN_VIDEO_PAGE.md`). The old `StudioRoot` Tools/Works/Sync/Well TabView is long gone.
- **Presentation (stability, as-shipped — corrected 10.76.38):** the device-confirmed-launching `EchoelStudioView` uses **MANY `AnyView`-wrapped `.sheet`/`.fullScreenCover` modifiers** chained on the body. Heute **14 dateiweit, 13 auf der Kette**, beide seit #479 in `ResetSoundClearsWhatTheLaunchLineReportsTests` festgenagelt. ⛔ Die AUFSCHLÜSSELUNG nach Modifier-Art stand hier und ist **gelöscht statt nachgeführt (#818): ihre SUMME überlebte, während beide geänderten Summanden falsch wurden** — kein Wächter auf die Summe kann das sehen. Messen: `python3 scripts/doctor.py --section D`. Provenienz und die Lehre: `memory/LEDGER_COUNTS.md` §D. Diese Zahl liest eine Sitzung, BEVOR sie einen Modal anhängt — an Kopfraum zu glauben, den es nicht gibt, ist der Weg zurück zum Black-Screen-SIGSEGV. Each has its own `isPresented:`/`item:` binding and an `AnyView(...)`-erased content closure. This is the baseline that launches — the earlier "ONE `.sheet(item:)` + ONE `.fullScreenCover(item:)` via computed bindings" note was **aspirational, never the shipping code**, and is removed to stop a future session "fixing" the launching code into a regression. **THE REAL RULE (learned the hard way, 10.76.34/build 2068 black screen): do NOT keep GROWING this modifier chain.** Adding sheets pushed the body's aggregate generic type past the SwiftUI metadata-decoder stack limit → SIGSEGV at first render, before any view appears (presents as a black screen, or "Safe Mode oder Black Screen" alternating once the self-healing net catches every other launch). The chain was "just under" the limit at 10.76.9/21; three sheets added 10.76.25/27/29 tipped it over (an `AnyView`-split of the chain did NOT save it — 10.76.35 still crashed; only reverting to the 10.76.21 body did). To add a NEW modal: **reuse/replace an existing slot, or consolidate the whole chain into a single `.sheet(item:)` enum FIRST** — never just append another `.sheet`. (Separately: never drive two modals true at once — that installs an invisible tap-blocking layer, the "can't click anything" hang.) **Also (10.76.41, "Tonart-Menü friert ein / kann plötzlich nicht mehr auswählen"): never read a HIGH-FREQUENCY `@Observable` (the ~10 Hz `CameraRPPGBioPublisher` finger/confidence/waveform, any bio snapshot, a playhead) directly in `EchoelStudioView.body` or in a computed `var` that `body` evaluates — `AnyView(...)` is NOT an observation boundary, so those reads register the WHOLE root body as a 10 Hz observer and every rebuild tears down any open `.menu` Picker popover (the freeze; worse while playing). Confine such reads to their own small leaf `View` struct (e.g. `BioStripView`, `PulseMeasurementView`) so only that view churns; the Picker-hosting body stays still.** **AND (10.76.48, "Sobald Biofeedback läuft kann ich nicht mehr auswählen"): the camera-freeze had a SECOND, non-SwiftUI cause — a high-frequency producer on a background queue must NOT hop to `@MainActor` per item. `CameraRPPGBioPublisher.onFrame` did a `Task { @MainActor }` PER captured frame (~30/s before the analyzer's frame-skip); that flood of tiny main-actor task submissions starved the SwiftUI executor → the open `.menu` Picker stopped responding while bio ran. Fix pattern: the background closure pushes into a lock-protected `RGBSampleQueue` (`@unchecked Sendable`, `NSLock`, capped) with ZERO actor hop; the EXISTING 10 Hz `publishTask` drains+feeds the `@MainActor` analyzer in one batch (carry a `timestamp` so rate maths is unchanged). Rule: never `Task { @MainActor }` per frame from a 30 fps source — batch into an existing low-rate main-actor poll via a Sendable queue.** **AND (10.76.50, the ACTUAL recurring menu-freeze cause — found after 41/43/47/48 each fixed a real-but-insufficient cause): the churn was in `WorkspaceView` (the ROOT, ABOVE every surface), NOT in `EchoelStudioView`. `WorkspaceView.topBar` read `cameraRPPG.waveform`/`detectedBPM`/`isLocked` directly to feed the header `PulseMonitorMini` — `waveform` updates ~10 Hz during biofeedback, so `WorkspaceView.body` rebuilt 10×/s and tore down any open `.menu` Picker in the surface BELOW it. Every prior audit scoped to `EchoelStudioView` and correctly found it clean — the 10 Hz read was one level up. FIX: confine the live reads to a leaf (`PulseMonitorMiniLive` reads the publisher in its OWN body); `WorkspaceView` only reads `isRunning` (start/stop). **RULE: when a freeze/churn persists after the obvious view is proven clean, AUDIT THE PARENT/ROOT (`WorkspaceView`, any always-on header/HUD that reads live bio) — a 10 Hz read in ANY ancestor of the menu host rebuilds the whole subtree. Header/monitor tiles that show live bio MUST read it in their own leaf, never via values passed down from a parent body.** ⭐ **DIE KAMERA IST NICHT DER EINZIGE HEISSE ERZEUGER — es sind VIER, und zwei churnen, wenn AUDIO läuft, nicht wenn die Kamera läuft** (#919/#928). `AudioEngine.startMeterPollTimer` schreibt mit **60 Hz** neun `@Observable`-Anzeigen (`masterLevel`, `masterLevelR`, die R128-Werte) · `AutomationPlayer.applyStep` schreibt `masterVolume` bei **jedem Transport-Schritt** — und das ist BEREITS EINMAL PASSIERT (inline im `masterPanel`, riss die Tonart-Picker ab; `MasterVolumeField` ist die Reparatur) · `metronome.bpm` wird von `Transport.onTempoChange(id: "metronome")` bei jeder Tempoänderung geschoben, während eines Glides bis ~20 Hz. **Die Metronom-Fläche ist die gefährlichste der vier**, weil der Wirt `metronome.`-Eigenschaften bereits an ZWEI Stellen liest, die `body` auswertet (`mixerPanel`s Click-Leiste und `metronomeRow`) — zu Recht KALT, weil ein Finger sie dreht; Empfänger und Gewohnheit sitzen also schon im Rumpf, und die heiße Schreibweise unterscheidet sich um ein Wort. Gleiches Gesetz, gleiche Reparatur: der Read gehört ins Blatt. Wächter: `Tests/CISmoke/TheMenuHostReadsNoHotStateTests.swift` — DREI Mengen, die Bio-Menge über vier Vorfahren. Die Zähl-Kette dieser VIER (zwei Rücknahmen, beide Zahlen) liegt in `memory/LEDGER_COUNTS.md` §O. Details in `.claude/skills/swiftui-render-safety/SKILL.md`.
- **✅ TESTFLIGHT PIPELINE: GREEN (verified 2026-05-30).** Prior "deploy blocker" note is resolved — `testflight.yml` runs #1404–#1407 on `main` all succeeded across every platform (iOS upload + Summary), preflight confirms App Store Connect secrets are present and valid. Dispatch + poll from the sandbox via `bash scripts/check-testflight.sh dispatch` (token in gitignored `.claude/settings.local.json`). Push the feature branch's newer work (bio synth / OSC / Polar) to TestFlight with a full `build_only=false` run once a branch verification run is green.
- **Latest batch (2026-07-12)** — the 07-12 changelog paragraph (A3 · A4 · L1 · P1 · B2 · B3 · B4 · B5 · W1 · EchoelAI N0–N4 · Body Science) is MOVED verbatim to `memory/LEDGER_COUNTS.md` §P (audit 2026-09-02; it was 3.7 KB of dated history in the always-loaded file). Two facts from it stay LAW here: (1) `FeatureFlags.echoelAI` has ZERO readers (`git grep -n "FeatureFlags.echoelAI" -- Sources` → one COMMENT hit) — nothing is behind it; `EchoelParameterRegistry` and `ParameterToolCore` are LIVE in `Core/`, off only for lack of a caller. Never rely on that flag as a guard. (2) **Healing/organ/tissue/wound theme = pre-Echoel (BLAB/Syng) legacy, never code here, stays a hard REJECT red line.**
- **Latest work (2026-06-23, on branch, gates green):** **Adaptive Quality** (AdaptiveQuality core + ResourceGovernor: thermal/battery/measured-FPS → tier → MetalBioView detail/reduce-motion **+ OSCSender's bio-egress rate via `PollingRateCeiling`, a CEILING and not a target** — corrected 2026-07-28 twice over: the governor never drove MetalBioView's frame RATE (`MetalBioView.swift:399` (Stand 2026-08-14) pins `preferredFramesPerSecond = 60` statically, and `AdaptiveQuality.swift` says so itself), and the one consumer wired since — `bioHz` → `OSCSender` (34e2355) — was missing. `targetFPS` / `oscHz` / `allowSpectralDonuts` have NO consumer, by design. This is the line a session reads before touching a quality knob, so both halves being wrong was the dangerous kind of stale) · **camera-session resilience** (runtime-error/interruption observers + frame-stall watchdog — fixes the silent ~68–200 s rPPG freeze) · **rPPG saturation-hold** · **composition cohesion** (BioComposer structure/detail RNG split — "homogener klingen") · **master −1 dBFS true-peak trim** · **EchoelFX bio-reactive modulation** (FXModulation core in `Core/` + FXBioModulator ~30 Hz; body→FX-param routing, UI section) · **EchoelFX Bitcrush + Stereo Widener** stages (wired chain/VM/UI/FXPreset/bio-mod) · **VJ visuals** (live in-fullscreen control overlay + shader hue/saturation palette, physical-colour default preserved). EchoelFX deepening = 4 workstreams (1 bio-mod + 2 algorithms shipped; 3 macro-morph + 4 CI-polish pending).
- **Prior TestFlight ship (2026-06-18):** rPPG fix (torch + exposure lock), real frequency-domain HRV coherence (Lomb-Scargle + Welch), resonance breath guide, tap-to-learn bio metrics, Art-Net flash-safety. Base build 1543 (app + Widget + AUv3, camera rPPG, universal BLE, ADM-OSC, EchoelLux Art-Net, launch silence).
- **Absent (not wired — do not claim as shipping):** RTMP/streaming (BroadcastPublisher is a compile-safe scaffold behind `#if canImport(HaishinKit)`; HaishinKit not integrated), Video-SCHNITT (⛔ korrigiert 2026-07-31: hier stand „video capture/edit" — die CAPTURE ist erreichbar und darf sehr wohl als shipping gelten, nur der EDIT ging mit #121 Slice 3), multitrack audio (gebaut, flag-gated AUS, türlos — siehe den ⛔-Absatz „Was hier stand und 2026-07-27 gestrichen wurde" ganz oben und #204; „absent" stimmt für den Nutzer, „nicht gebaut" nicht für den Entwickler). **EchoelStore** (`Core/EchoelStore.swift`) = compiling but UNREACHABLE: `ProUnlockView` exists and is never presented (`WorkspaceView.swift:141` (Stand 2026-08-14)), so nothing is purchasable today. Corrected 2026-07-25 — the old "ZERO consumers" + "legacy subscription product IDs" wording was false on both halves: the one compiled product is the NON-CONSUMABLE `com.echoelmusic.app.pro` (`ProGate.swift`). **Aber das ist ÜBRIGGEBLIEBEN, nicht der Plan** (korrigiert 2026-07-28): die zweite Founder-Entscheidung vom 2026-07-10, wörtlich festgehalten in `WorkspaceView.swift` über `body`, hebt das Einmal-Pro auf — v1.0 komplett kostenlos, v1.1 = „Echoel Live" Jahres-Abo, v1.2 = Per-Event-Host-Gebühr. `ProUnlockView`/`EchoelStore`/`ProGate` bleiben im Code, um dafür UMGEWIDMET zu werden: nicht löschen, vor v1.1 nicht wieder präsentieren. **Push/CloudKit:** `aps-environment=production` + iCloud/CloudKit entitlements ARE declared and `AnnouncementCenter` (registerForRemoteNotifications + CKQuerySubscription) EXISTS — but hard-gated OFF for v1.0 via `AnnouncementCenter.cloudKitConfigured = false` (zero CloudKit/push calls execute; launch-crash fix v10.79.148). Its Learn-view toggle is HIDDEN while the gate is false (2.1 audit 2026-07-16). Before flipping the gate in v1.1: deploy the CloudKit "Announcement" schema to Production FIRST. (The old "zero push code" claim here was stale — corrected 2026-07-16.) **Art-Net + sACN (unicast) are live.** **VocoderCore-MAPPING / BioModulation** = pure tested cores, **not yet wired** (foundations) — ⭐ korrigiert 2026-08-14: die ANALYSE-Hälfte (`VoiceAnalyzer`/`VoiceFrame`) ist seit #592a verdrahtet (Voice-Capture-Kette, Sound-Panel-Tür); unverdrahtet ist nur noch `VocoderMapping` (Ausgabe-Hälfte). **FeedbackGuard** (audio-input live monitoring): ENGINE wired — seit #847/#848 (Founder 2026-08-27: „es soll erst gar kein Piepsen entstehen") **präventiv und pro Band**: `HowlDetector` (vierfache Howl-Signatur, feuert bei leisem Pegel) treibt VIER dynamische Notch-Bänder im Monitorpfad; der ~15-Hz-Duck-Loop bleibt als Breitband-letzte-Verteidigung (Tests grün, Gerät-Verify offen) — aber die UI-Tür (`AudioInputPickerView`, `showInput`) ist seit dem Tools-Grid-Removal (2026-07-02) UNERREICHBAR; gleiches Schicksal für PatchbayView (Routing!), MeditationView, PatchEditorView, SampleBrowserView, AutomationView, BroadcastView, SpectralDonutView — alle Slots existieren, einziger Trigger war das tote `toolsSection`/`openTool` (Deep Audit 2026-07-12; tote Slots = SLOT-REUSE-Reservoir an der Modal-Decke). **BEHOBEN (2026-07-12 batch + seither):** PatchbayView (Routing/Master-Panel), ~~SampleBrowserView (B5, Drum-Channel-Strip-Tür)~~ — **GELÖSCHT 2026-07-27 (#167)**; die B5-Tür starb schon mit den Drums (#166), die Datei ist jetzt auch weg. Genau die „verifiziert erreichbar"-Falle, vor der derselbe Absatz warnt: Slot + Setzer beweist keine Erreichbarkeit, und ein Eintrag hier veraltet still, **FeedbackGuard/AudioInputPicker** — ⛔ **WIEDER TÜRLOS SEIT #1024 (2026-09-06), auf Founder-Befehl.** „das mit dem Audio Input Monitoren klappt immer noch nicht also fliegt das raus", zweimal gesagt, beim zweiten Mal über einem Screenshot von Build 448/2567. ALLE DREI Mikrofon-Türen sind entfernt — der Mix-Streifen `micMixStrip`, der `masterDoorButton` „Audio input" und das Einlade-Banner `PlugInInviteRow`. **Nur die TÜREN**: `AudioInputPickerView` (Picker · Tune-Presets · Harmony · Granular), der `showInput`-Slot (jetzt setzerloser Kopfraum, wie `showMeditation`) und der ganze `AudioEngine`-Monitorpfad samt FeedbackGuard sind unangetastet — Wieder-Betüren sind DREI Aufrufstellen, kein Neubau. Nichts bleibt hängen: `isInputMonitoring` wird nicht persistiert, jeder Start beginnt mit stummem Mikro (vor dem Schnitt geprüft, nicht danach). `RoutePlugInWatcher`/`PlugInInviteRow` sind damit ebenfalls türlos, bleiben aber. Wächter: `Tests/CISmoke/TheMicrophoneHasNoDoorTests.swift` — er verbietet das Wieder-Aufmachen NICHT (#364) und nennt die vier Prosa-Heimaten, die dann mitzuziehen sind. SECHS Wächter wurden im selben Commit repariert (#456), jede gestrichene Nadel wörtlich am Ort zitiert. **NICHT erreichbar** (Stand 2026-07-31, per Zählung der Instanziierungsstellen): ~~`PatchEditorView`~~ — **GELÖSCHT 2026-07-31 (#132 Slice 6)**, kein Eintrag mehr in dieser Liste, weil es die Datei nicht mehr gibt; der lebende Timbre-Editor ist und war `soundPanel` hinter dem Sound-Chip. `AutomationView` (Datei existiert nicht), `SampleBrowserView` (mit #167 gelöscht), ~~`FileWaveformView`~~ — **GELÖSCHT 2026-07-28 (#132 Slice 5, `2245671`)** zusammen mit `WaveformView` und `WaveformCache`; kein Eintrag mehr in dieser Liste, weil es die Datei nicht mehr gibt. Der reine Kern `WaveformReducer` BLEIBT, jetzt test-only und mit Nachruf im eigenen Datei-Kopf. **Genau die Falle, vor der dieser Absatz zweimal warnt:** der Eintrag stand hier als Gegenwarts-Tatsache, geschrieben am selben Tag als PLAN für genau diesen Commit — wer ihn danach las, hätte eine türlose Waveform-Ansicht wieder aufmachen wollen, die es nicht mehr gibt. **KORREKTUR 2026-07-26:** `AutomationView.swift` existiert nicht mehr; `SpectralDonutView` ist erreichbar, aber ⛔ NICHT mehr über die #747-Tür: `visualPanel` → „Full screen", das Vollbild-Feld, das VJ-Overlay und die zweite REC-Taste sind mit #1069 gelöscht. Die EINE überlebende Montagestelle ist `FloatingVisualWindow` (messen, nicht zitieren: `git grep -n SpectralDonutView\( -- Sources`). Herleitung beider Einträge: `memory/LEDGER_COUNTS.md` §G. **Unerreichbar bleibt aus derselben toten Kette nur der MIDI-Import** (`midiImportPresented` / `importMIDI()`). ⛔ **Und hier stand „die ‚Donuts'-Pille im Synth-Reiter ist live antippbar und wirkungslos" — beide Hälften falsch, seit #227.** Die Pille ist **GELÖSCHT** (grep-bar: `PILL STOOD HERE AND WAS REMOVED (#227)`), also weder antippbar noch vorhanden. ⛔ Und der Umschalter, der sie ersetzte, saß im `.fullScreenCover(isPresented: $showVisual)` — mit #1069 ebenfalls gelöscht. Er war **unerreichbar, nicht wirkungslos** — und genau diese Unterscheidung ist das Gesetz: „wirkungslos" lädt eine Sitzung ein, ein totes Bedienelement zu löschen; sie fände keins und stünde vor einem FUNKTIONIERENDEN hinter einer fehlenden Tür. ⚠️ **Diese Zeile bekommt bewusst KEINEN Wächter** — ein Text-Scan auf CLAUDE.md wäre die #364/#486/#491-Falle: die Datei zitiert zurückgenommene Behauptungen absichtlich, ein negativer Scan träfe seine eigene Rücknahme. Die volle Nachlese (der verwaiste Zitat-Zeuge, die Tools-Katalog-Löschung `f371d27`, die Zeilennummern-Lehre) liegt in `memory/LEDGER_COUNTS.md` §G. ⭐ **Mehrere Präsentations-Slots hängen an Flags, die niemand setzen kann** = freier Kopfraum, statt einen 15. anzuhängen. ⛔ Hier standen zwei Namen, während #1024 zwei Absätze weiter oben schon einen dritten erzeugt hatte. **Die Liste wird gedruckt, nicht abgeschrieben: `python3 scripts/doctor.py --section C`** (Datei und Zeile je Flagge). **Er [der tote Tools-Katalog] nahm die einzige Oberfläche für drei Opt-ins mit:** „Save to Apple Health" (persistiert! mit `083cec8` als `HealthWriteOptInRow` im Bio-Panel zurückgeholt — ein persistiertes Gesundheits-Einverständnis MUSS einen erreichbaren Aus-Schalter haben) sowie `midiOut.mpeEnabled` / `expressionEnabled` — **mit #713 ERLEDIGT**: zwei persistierte Schalter („MPE note layout", „Per-note expression") im `midiOutSection` der erreichbaren Routing-Fläche, Default aus, EIN Besitzer (`MIDIOutput.applyOutputPreferences()` liest die Keys; PORT-ÖFFNUNG und Schalter rufen dieselbe Methode — die `MIDIInput.applyNetworkSessionPreference()`-Form.). Der zweite Schalter ist deaktiviert, solange der erste aus ist, weil der Sendepfad `if mpeEnabled, expressionEnabled` liest. Wächter: `Tests/CISmoke/MIDIOutQualitySwitchesTests.swift`. **Nicht geräteverifiziert**. ZWEI LEHREN: (1) „per direktem Code-Read verifiziert" heißt nur etwas, wenn die Kette bis zum RENDERNDEN Elternteil verfolgt wurde — Slot + Setzer beweist keine Erreichbarkeit. (2) **Vor dem Löschen eines UI-Blocks prüfen, welche Modelle er als EINZIGER schreibt** — ein Toggle mit persistiertem Flag hinterlässt beim Löschen einen unwiderruflichen Zustand, keine Lücke. MeditationView bleibt bewusst türlos (Founder: Teil des Produktionsflusses, keine eigene Tür gewollt). **BroadcastView bleibt türlos — korrekt so**, solange HaishinKit/RTMP nicht verlinkt ist (eine Tür zu einem nicht funktionierenden Backend wäre ein Halbfertig-Feature). **BioVisualParams** (immersive flash-safe pulse) is **wired**. See `docs/dev/FEATURE_MATRIX.md` + `scratchpads/DEEP_AUDIT_2026-07-12.md`.
  ⛔ **DREI TÜRLOSE FLÄCHEN FEHLTEN IN DIESEM REGISTER (nachgetragen 2026-08-07, jede per Zählung der Instanziierungsstellen).** Das Register ist die Liste, aus der eine Sitzung ableitet, was sie noch aufmachen oder löschen darf — eine Lücke darin ist teurer als eine falsche Zahl, weil sie gar nicht erst als Frage auftaucht.
  · **Die VIER Analyse-Ansichten (`AnalysisScopeView`, `AnalysisPoincareView`, `AnalysisSpectrumView`, `AnalysisWavefrontView`) sind ALLE türlos — und zwar ABSICHTLICH.** Null Instanziierungsstellen außerhalb ihrer eigenen Dateien; das Field-Panel zeigt keine Messgeräte. Founder-Screenshot mit rotem X am 2026-08-02, im Quelltext an der ehemaligen Montagestelle festgehalten; Wiederanhängen ist dort eine Zeile plus Beschriftung. Kein Defekt, wie `ImmersiveStageView` und `BroadcastView`. **GESETZ: wer eine Register-Zeile über einen NACHBARN mit-behauptet, misst den Nachbarn mit** — dieser Eintrag nannte zwei der vier gemessen und die anderen zwei aus dem Gedächtnis „sehr wohl montiert", und der Quelltext war die ganze Zeit ehrlich. Herleitung: `memory/LEDGER_COUNTS.md` §K (#867).
· **`TimelineAutomationRow` = GELÖSCHT (#473, 2026-08-07).** Der Eintrag stand hier als türlos-aber-nicht-löschbar, weil `TimelineAutomationRowMath` in DERSELBEN Datei lebte und `Core/TimelineStore.swift` es ruft — ein „lösch die türlose Datei"-Aufräumen hätte den Store gebrochen. **#472 hat den Kern herausgehoben, #473 hat die Ansicht gelöscht**: `struct TimelineAutomationRow: View` plus `TimelineAutomationTargetOption` und `TimelineAutomationHeadCell`, alle drei mit null externen Verweisen. Die Datei ist weg; `Sequencer/TimelineAutomationRowMath.swift` bleibt und ist unverändert.
    ⛔ Die 415/198/344-Zahlengeschichte dieser Zeile (dieselbe Zahl ans falsche OBJEKT geheftet — nicht veraltet, sondern von Anfang an falsch zugeordnet) liegt in `memory/LEDGER_COUNTS.md` §I (#856); das GESETZ daraus steht schon in der #475-Zeile darunter: nenne die Größe des Eingriffs, für die Ansicht die Ansicht.
    ⭐ **Die SECHS Prosa-Zitate in fünf Dateien sind UMGESIEDELT, nicht verworfen** — der eigentliche Blocker, den keine Register-Zeile vorhergesagt hatte. Zwei GESETZE daraus, weil sie beim Bauen gebraucht werden: **ein Zeiger ist nur so haltbar wie das, worauf er zeigt** (dieselbe Datei verlor erst eine Zeilenspanne, dann den zitierten Block) · **„türlos, aber nicht löschbar" ist eine eigene Kategorie** (`AutomationPlayer.extraAutomatableDescriptors` stand von #473 bis #559 ohne Aufrufer und war die ganze Zeit richtig behalten — seit #559 liest es `Studio/AutomationStatusStrip.swift`). Welche fünf Dateien, welche zwei Ausfall-Mechanismen und warum zwei der Argumente durch die Löschung STÄRKER wurden: `memory/LEDGER_COUNTS.md` §R (#1142).
    ⚠️ Der Wächter ist im SELBEN Commit mitgezogen (#456): `TheAutomationRowLawHasItsOwnFileTests` LAS die gelöschte Datei über ein `try` hinter einem verzeichnis-weiten Skip — die Löschung wäre sonst ein hartes Rot auf korrektem Baum geworden. Ersetzt durch etwas STRENGERES: die Datei muss ABWESEND sein, und ein Lauf über `Sources/` verlangt **genau EINE** Deklaration von `enum TimelineAutomationRowMath` (die alte Form fragte nur, ob EINE benannte Datei sie nicht wiederholt — eine Zweitkopie irgendwo anders wäre durchgegangen). Der Test ist dabei umbenannt, weil sein alter Name ein Verfahren beschrieb, das der Code nicht mehr nimmt (#374). ⚠️ **Der hier ZITIERTE Name ist der heutige** — die Datei und die Klasse heißen so; wer aus diesem Satz einen neuen Namen sucht, sucht nichts. Der ALTE Name ist in diesem Shallow-Klon nicht mehr nachlesbar (die Datei existiert schon am Graft `545b19e`, `git log --diff-filter=R` über `Tests/CISmoke/` ist leer), also steht er bewusst nirgends — eine erfundene Rekonstruktion wäre schlimmer als die Lücke.
    ⚠️ **Was sich NICHT geändert hat: Timeline-Automation ist weiter unerreichbar.** `AutomationPlayer` hat keinen Produktions-Schreiber; eine von einem älteren Build persistierte Kurve SPIELT (über `applyStep` auf jedem Transport-Schritt), aber keine Fläche kann heute eine zeichnen. #473 hat eine Ansicht entfernt, die nichts montiert hat — keine Fähigkeit.
  · **`BreathGuideView` — SIEBTER Eintrag (#947), und der erste, den ein WERKZEUG fand statt eine Sitzung.** Genau EINE Konstruktionsstelle, in der selbst türlosen `BioSourceView` — also unerreichbar EINEN SPRUNG TIEFER, die Klasse, die `doctor --section C` bis #947 nicht sah. **Nicht löschen:** Atem-Führung mit Resonanz-Default, ≤0,2-Hz-Blitz-Gesetz, Kontraindikations-Bestätigung. Wer sie aufmacht, betürt den ELTERNTEIL. Herleitung und Wächter: `Tests/CISmoke/TheBreathGuideHasNoDoorTests.swift`.
  · **`FaceExpressionBioPublisher` — ACHTER Eintrag (#1002), und der erste, der keine Ansicht und kein Kern ist, sondern eine ganze EINGABE-MODALITÄT.** Gemessen: `git grep -n "FaceExpressionBioPublisher(" -- Sources` → **0**; `BioSourceOption` kennt nur `camera, ble, sim`. Fertig gebaut (ARKit-Blendshapes → smile/brow/jaw als [0..1] auf dem Bus, `.faceCam`, ~10 Hz, Lock-Drain statt Actor-Hop pro Frame), hinter `FeatureFlags.cameraExpression` (default aus). **Nicht löschen, nicht anschalten:** die Front-Kamera-Zweckerklärung ist founder-gated, und die EU-AI-Act-Rahmung im Dateikopf (AUSDRUCK als Steuersignal, NIE eine abgeleitete Emotion) ist der Grund, warum diese Zeile im Register stehen muss — die Lücke war in beide Richtungen teuer: jemand baut Face-Tracking neu, das es gibt, oder verdrahtet TrueDepth ohne die Erklärung. Wächter: `Tests/CISmoke/TheFaceSourceHasNoDoorTests.swift` (#364: er verbietet das Verdrahten nicht).
  · **`PulseMeasurementView` — VIERTE türlose Fläche, nachgetragen 2026-08-12 (#525), und die einzige dieser Liste, die von sich selbst BEHAUPTET hat, auf dem Schirm zu sein.** Gemessen: `git grep -n "PulseMeasurementView(" -- Sources` = **EINE** Stelle (`Studio/BioSourceView.swift`), `git grep -n "BioSourceView(" -- Sources` = **NULL**. Die Kette endet einen Sprung höher. Ihr Dateikopf sagte trotzdem in der ersten Zeile „shown above the controls while a take is playing" — seit dem Tools-Grid-Removal (2026-07-02) falsch. ⛔ **Hier stand die „TEUERSTE Auslassung dieses Registers", und ihre MESSUNG war richtig, ihre SCHLUSSFOLGERUNG falsch (#703).** Wahr bleibt: `CameraRPPGBioPublisher.coachingHint` (= `acquisitionCue.fullHint`) hat GENAU EINEN Leser, und der ist diese türlose Ansicht. Daraus wurde hier „die rPPG-Abhilfe erreichte einen sehenden Nutzer nirgends" — und **das ist seit #523/#569 unwahr**: `BioStripView` rendert DIESELBE Zeichenkette über `acquisitionCue.fullHint` als Banner, sichtbar im `bioPanel`, gegated durch `cueWarrantsFullHintOnScreen` — **die Tür ist die PULS-PILLE** (`PulseMonitorMiniLive`-Tap → Chrome-Tür „bio"), KEIN Chip: `.bio` fehlt in `EchoelStudioView.studioChips` (#704). **Tot ist die PROPERTY, nicht die FÄHIGKEIT** — und der Quelltext hat das die ganze Zeit richtig gesagt (`PulseCue`: „UNTIL THIS PROPERTY HAD A CONSUMER"; `BioStripView`: „before this line"). Wächter der POSITIVEN Hälfte: `TheStallRemedyReachesTheScreenTests.testTheStripRendersTheStallRemedy` — ein neuer wäre #416. Ein Dateikopf, der „ist auf dem Schirm" sagt, bleibt trotzdem der Grund, warum das lange niemandem auffiel. ⛔ **NICHT LÖSCHEN, und zwar aus dem #472-Grund:** in diesem Dateikopf steht die kanonische Fassung des 10.76.41/50-Freeze-Gesetzes für diese Form, und die Präsentations-Zeile weiter oben zitiert die Ansicht NAMENTLICH als Musterbeispiel (dort neben `BioStripView` — die ist über die Puls-Pille erreichbar, diese nicht; das Beispiel gilt der FORM, nicht der Erreichbarkeit). Eine türlose ANSICHT und ein tragender Nachbar in EINER Datei. Wächter: `Tests/CISmoke/ThePulseReadoutHasNoDoorTests.swift` — er verbietet das Wieder-Aufmachen NICHT (#364), er nennt in seiner Fehlermeldung die **sechs** Prosa-Stellen, die dann im selben Commit mitzuziehen sind.
  · **Die AUDIO-SPUR-Schicht — FÜNFTER Eintrag, nachgetragen 2026-08-12 (#527), und der erste, der keine ANSICHT ist, sondern eine verdrahtete Maschine ohne Erzeuger.** `AudioLanePlayer` wird beim App-Start konstruiert (`EchoelmusicApp`) und vom Transport bei JEDEM prime/apply/stop gefahren — das ist wahr und bleibt es. Sein Dateikopf sagte zusätzlich „audio lanes now sound in time with the arrangement", und **das ist eine Fähigkeitsbehauptung ohne Produzenten**. Gemessen (Kommentare gestrippt): **FÜNF** `TimelineRegion(`-Konstruktionsstellen, und jede ist abgehakt — `TimelineStore.migrate(sections:)` sät eine LEERE `Audio 1`-Spur und legt jede Region auf die MIDI-Spur · `ensureComposerRegion` und `ensureUserMidiRegion` bauen ihren Clip per Konstruktion mit `kind: .midi` · `RecordController` und `AudioClipFactory` sind die einzigen zwei, die eine audio-tragende Region erzeugen KÖNNEN, und diese Kette ist türlos (`AudioClipFactory` wird nur von `TakeRecorder` gerufen, `TakeRecorder` nur von `RecordController` konstruiert, und `RecordController.arm()` hat NULL Aufrufer — #204). Die Arrangement-Fläche, die eine erzeugt hätte, ging mit #121 Slice 4.
    ⛔ **UND DAS IST KEIN LÖSCH-ARGUMENT, sondern das Gegenteil — der Punkt, an dem sich dieser Eintrag von den vier darüber unterscheidet.** `TimelineDocument` wird PERSISTIERT und beim Start dekodiert; ein Projekt, das ein Build mit erreichbarem Recorder-Pfad geschrieben hat, kann weiterhin eine Audio-Region tragen, und dieser Koordinator ist das Einzige, was sie abspielen würde. Die Schicht als „tot" abzuklemmen macht aus „offensichtlich abwesend" ein „still stumm". Die leere Audio-Spur im Default-Dokument bleibt ebenfalls absichtlich — der Founder hat die Mehrspur-Form („mehrere") ausdrücklich verlangt.
    ⚠️ **Und der ranked board-Eintrag, der diese Schicht als „WIRED" führt, ist damit halb korrigiert:** verdrahtet ja, klingend nein. Wer daraus eine Löschung ableitet, leitet sie aus der falschen Hälfte ab. Wächter: `Tests/CISmoke/TheAudioLanesHaveNoProducerTests.swift` — er verbietet das Wieder-Aufmachen NICHT (#364) und trägt fünf Gegengewichte, die genau die naheliegende „Aufräum"-Löschung rot machen.
  · **Die MODULATIONS-MATRIX — SECHSTER Eintrag, nachgetragen 2026-08-12 (#541), und der zweite nach der Audio-Spur, der keine ANSICHT ist, sondern eine laufende Maschine ohne Erzeuger.** `ModulationEngine` wird beim Start konstruiert, `start(subscribing:)` läuft, die 100-ms-Schleife tickt, und `ModDestinationKey.tempo` ist als Ziel registriert. Gemessen fehlt die ROUTE: die Default-Matrix ist LEER (die Datei sagt es zweimal selbst), und `git grep -n "\bModRoute(" -- Sources` liefert **genau EINEN** Treffer — den `LossyDecoded`-Decoder in `ModulationMatrix.swift` (ohne die Wortgrenze kommt `FXModRoute(` dazu, ein fremder Typ). Null Produktions-Konstruktionsstellen. `Studio/BioModulation.swift` ist KEINE Fläche (es hält `ClockSource` und `BoundParameter`, reine Werttypen, null externe Verbraucher) — wer aus dem Dateinamen eine Matrix-UI erwartet, sucht falsch.
    ⛔ **Und das ist wieder KEIN Lösch-Argument, aus dem #527-Grund:** die Matrix wird PERSISTIERT und beim Start dekodiert (`load()` gewinnt über die leere Default), also kann ein Dokument aus einem Build mit erreichbarer Fläche weiterhin das Tempo ziehen. Abklemmen macht aus „offensichtlich abwesend" ein „still stumm". Ebenfalls tragend und nicht anzufassen: der `outputTap`, der JEDE angewandte Modulation als `/echoelmusic/mod/<key>` über OSC schickt — die Adresse steht im OSC-Abschnitt dieser Datei als real.
    ⚠️ Der Unterschied zu den vier Ansichts-Einträgen darüber: dort ist die Fläche weg und die Fähigkeit klar abwesend. Hier LÄUFT alles bis auf den letzten Zentimeter, und genau deshalb hat die CURRENT-STATE-Zeile vier Monate „wired (bio→tempo)" behauptet. Wächter: `Tests/CISmoke/TheTempoDestinationHasNoRouteTests.swift`.
- **P1 "Sound complete" — ALREADY BUILT (audited 2026-07-01; corrects the old "Clips/Arrangement UI not wired" note):** the melodic/DAW core is done and wired — **polyphonic synth** (`PolySynthVoice`) + **bass** (`SubBassVoice`) + ~~hybrid sample/synth drums~~ (`BeatPlayer` + `DrumSynthVoice` — **entfernt 2026-07-26, #166/#167; klingt nicht mehr**); **full patch editor + presets** (`SynthPatch`/`PatchStore` + `soundPanel`, favorites/community/save-as, live-apply, tested. ⛔ Hier stand `PatchEditorView` als der Editor „DOORLESS since 2026-07-25" — die Datei ist mit #132 Slice 6 gelöscht; der Editor war die ganze Zeit `soundPanel` hinter dem Sound-Chip); **breakbeat loop-cut** (`LoopCutter`/`LoopBarLength` in the Studio UI); **MIDI export** — **AUSGELIEFERT** (korrigiert 2026-07-28): `exportMIDI()` wird wieder aufgerufen, aus dem Export-Schacht heraus (#188 hat die Tür in den VORHANDENEN Slot zurückgeholt, kein neuer Sheet). `MIDIFileExporter` intakt und getestet. Der App-Store-Text behauptet den MIDI-Export — nicht entfernen, ohne `fastlane/metadata` mitzuziehen; Clips + Arrangement UI **DELETED** by the pure-instrument epic (#121 Slice 4 — `ClipView` 807dc0d, `ArrangeTimelineView` eb58e7a; `ClipStore`/`ArrangementStore`/`AutomationLane` model retires in Slice 5).
  **CRAFT-TOOL DOORS — the #131a craft-editor slot is GONE again (2026-07-26).** It was shipped 2026-07-25 (`f2cbf34`/`bda8f41`) to door the piano roll, and it held exactly ONE case; when the founder said *"Pianoroll soll raus"* the honest move was to take the slot with it rather than leave an undoored enum (the lying-`toolItems` trap). **Der Modifier-Zähler steht EINMAL, im Presentation-Absatz oben** — dort benannt, hier nicht nachgesprochen (⛔ #707 zitierte ihn hier wörtlich, und das Zitat traf nur sich selbst: `grep` fand die zitierte Schreibweise genau einmal, nämlich in diesem Zeiger; #708); seine Provenienz — die zwei Anker-Fehler und die Historie 12→16→15→14 — liegt in `memory/LEDGER_COUNTS.md` §D. Alerts und der File-Importer sitzen auf DERSELBEN Kette und kosten dieselben Metadaten. **The NEXT editor re-introduces the slot as `enum` + `@State` + ONE `.sheet(item:)` + an out-of-body content builder — NEVER a bare appended modifier**, and a case is added ONLY together with its door. Setterlose Slots sind die erste Stelle für Platz — **welche, druckt `python3 scripts/doctor.py --section C`; hier steht bewusst keine Liste**, die Menge bewegt sich in beide Richtungen (#747 nahm einen weg, #1024 legte einen dazu) und jede Abschrift altert. `sampleBrowserTrack` was the fourth and is DELETED (2026-07-27): once `SampleBrowserView` itself went, the slot pointed at a type that no longer compiles — a slot is only reusable while its content still builds.
  · **`PianoRollView` = GELÖSCHT (#475, 2026-08-07).** Der `struct` und die zwei privaten Gesten-Typen `RollDragAnchor`/`RollDrag` sind weg; belastbar ist die GRÖSSE des Eingriffs (`git show --stat`: 54 Einfügungen / 1020 Löschungen, netto **−966**), weil die sich nie wieder ändert. **Die Datei `Studio/PianoRollView.swift` BLEIBT**, weil sie `PianoRollModel` enthält — die Notenmaschine UND den `MusicalFrame`-Publisher, also die Wirbelsäule der Ausgabestufe (Visual · Licht · Raum). `RollSelection` ist geblieben, jetzt test-only (`Tests/EchoelmusicTests/NoteTests.swift`), die `WaveformReducer`-Form. ⛔ **Diese Scheibe produzierte NEUN Falschbehauptungen — die höchste Zahl in dieser Kette; drei davon Zahlen. Die vollständige Nachlese liegt in `memory/LEDGER_COUNTS.md` §E** und gehört dorthin, nicht in die immer-geladene Datei. Was als GESETZ bleibt: **eine Zeilenzahl einer LEBENDEN Datei ist keine Tatsache, sondern ein Datum** — nenne die Größe des Eingriffs; und **ein Vermerk, der einen lebenden Mechanismus für tot erklärt, ist die teuerste Sorte**, weil er die nächste Sitzung einlädt, eine geltende Invariante als Ballast zu behandeln. **Consequence to state plainly: there is NO note editor in the app any more** — the generated take can be heard, mixed and exported, not corrected.
    ⭐ **UND DIE LÖSCHUNG HAT DREI NACHBARN VERWAIST, was keine Register-Zeile vorhergesagt hatte** (gemessen NACH dem Schneiden, die #472-Lehre): `Studio/RollHitTest.swift` und `Studio/RollFitMath.swift` haben seither **null** Produktions-Aufrufer, `Studio/RollNoteOps.swift` überlebt mit genau einem (`stableSeed`, gerufen von `PianoRollModel`). Keiner ist mitgelöscht — `RollHitTest` trägt das #470-Gesetz, das die Löschung überleben SOLLTE, und im blockierenden Bundle pinnt es `TheUnitToPeriodLawSurvivesTheViewTests`. Dessen dritte Behauptung („die Lane ruft das Gesetz noch") ist im selben Commit zurückgezogen, weil die Lane weg ist — der Wächter hatte diese Anweisung in der eigenen Fehlermeldung stehen. **Sieben `PianoRollModel`-Mitglieder sind ebenfalls aufruferlos** und im Dateikopf namentlich aufgeschrieben statt still gelöscht.
  · **`PatchEditorView.swift` IST GELÖSCHT (#132 Slice 6, 2026-07-31).** Die Vorgeschichte gehört hierher, weil sie zweimal in die falsche Richtung gelesen wurde: die Datei war seit dem Tools-Grid-Removal türlos, und meine frühere Behauptung, das Instrument könne „keinen Klang formen oder speichern", war FALSCH — `soundPanel` (an `dropdownContent` `.sound`, erreichbar über den Sound-Chip) IST der lebende Timbre-Editor und war es die ganze Zeit. Blockiert war die Löschung von fünf persistierten Parametern, deren einzige Zeile in der türlosen Datei stand; sie sind portiert (**`unisonVoices`/`unisonDetuneCents` mit #281, `spectralShape`/`noiseColor` und `outputLevel` mit #286**), jeder mit gerenderter Zeile UND Wächter im blockierenden Bundle (`Tests/CISmoke/UnisonRowDefaultsTests.swift`). Die **Preview-Tastatur** war kein Parameter, sondern eine Urteilsfrage — entschieden: die Spielfläche deckt sie ab, nicht portiert. Die **Preset-Leiste** (laden · favorisieren · speichern · Save-as · löschen · einreichen) ist da (⛔ hier stand „fehlte nie“ — in diesem SHALLOW-Klon, gepfropft auf `24e9420`, liefert `git log -S` auf die Aufrufstellen nur den Graft; die Gegenwart ist belegbar, die Vorgeschichte nicht, und genau solche unbelegten „schon immer“-Sätze streicht diese Datei an anderer Stelle selbst): `presetRow` hält alle sechs, seit `Tests/CISmoke/SoundPanelPresetBarTests.swift` auch nachweislich — und DAS ist der Grund, warum die Löschung nichts gekostet hat. ⚠️ Die `outputLevel`-Hälfte hing einen Monat an einer Begründung, die faktisch falsch war (ein Quellkommentar erklärte einen manuellen Trim für unvereinbar mit `loudnessNormalized()`; das läuft **einmal** beim Bau der `static let factory`-Liste und kann eine Nutzer-Eingabe nie überschreiben, was das Feld-Doc seit dem ersten Tag sagt). **Lehre: ein „gehört dem Founder"-Vermerk mit prüfbarer Begründung gehört geprüft, bevor er eine Aufräumarbeit blockiert.**
  · **`ImmersiveStageView` (spatial stage) stays doorless — deliberately.** Ship-gate item 4 makes light/space "demonstrable, not required for v1" (#131c).
  · **Correction to a claim I made about the roll:** presenting it is NOT what publishes `MusicalFrame`. That publish is in `PianoRollModel`'s tick handler (`PianoRollView.swift`) on the shared sequencer tick, installed once at app start (`pianoRoll.start(...)` in `EchoelmusicApp`) — so the visual/light output stage is lit whether or not the roll is open. The door is load-bearing for EDITING, not for the spine.
  · **NEEDS-FOUNDER-VERIFY:** launch (the +1 modifier vs the black-screen law). ⛔ Die zweite Hälfte — „and the roll's Stop, which cascades the ONE-Stop law … and ends the whole bio session" — ist **HINFÄLLIG**: dieser Knopf saß in der `PianoRollView`-`struct`, die #475 gelöscht hat. Ein Verify-Posten, der auf ein entferntes Bedienelement zeigt, kostet den Founder eine Geräteprobe, die nichts entscheiden kann. Der ÜBERLEBENDE Produzent des Playback-only-Stopps ist das Transport-■ in `WorkspaceView` (`pianoRoll.requestPlaybackOnlyStop()`, #179), und den pinnt `OneStartControlTests.testThePlaybackOnlyStopHasAReachableProducer` im blockierenden Bundle.
  Music theory is fully in-house. The real remaining frontier is **P3 Video** (⛔ korrigiert 2026-07-31: „no recorder/trim/export yet" war falsch für zwei Drittel — RECORDER und EXPORT existieren und sind erreichbar, `VisualRecorder` + `FloatingVisualWindow`s Aufnahmetaste + `videoPanel` → `VideoLibraryPanelContent` mit mp4-Share. Was fehlt, ist der TRIM/SCHNITT, mit #121 Slice 3 absichtlich entfernt) and **P4 Broadcast**. See `scratchpads/PLAN_REDOOR_CRAFT_TOOLS_2026-07-25.md`.
- **Files:** Swift-Dateien unter `Sources/` — **MESSEN, nicht zitieren**: `git ls-files 'Sources/**/*.swift' | wc -l`. ⛔ Hier stand ein Literal samt seiner ganzen Zähl-Kette (983 B in der immer geladenen Datei); beides ist mit #818 **gelöscht statt nachgeführt**, weil die Zahl beim Schreiben schon ein Datum war und es wieder geworden ist: #813 legte EINE Datei an (`Core/CoherenceTrend.swift`) und niemand wurde rot. Die ZÄHL-KETTE — jeder frühere Stand, die Taxonomie ±0/+1/+2/−1 und jede ⛔-Rücknahme — steht in `memory/LEDGER_COUNTS.md` §B; **wer eine Zahl nachführt, führt sie DORT nach.** Ein Wächter pinnt POSITIV, dass hier der Befehl steht; ein Negativ-Scan auf die Abwesenheit der Zahl träfe diese Rücknahme selbst (#491)), **ZERO Metal files** — corrected 2026-07-25; the old "~212 Swift + 1 Metal (`Video/Shaders/ChromaKey.metal`)" was stale twice over: the count was long out of date and `ChromaKey.metal` was DELETED by Slice 3 (video-cut removal) together with its directory. `MetalBioView` compiles its shader inline at runtime, so the app ships no `.metal` source at all. | **Swift 100%** | top-level dirs under `Sources/Echoelmusic/`: `Audio Bio Core DSP EchoelAI Resources Sequencer Stream Studio Sync Tools Video Views`, plus the two loose top-level files `EchoelmusicApp.swift` and `MicrophoneManager.swift`. NOTE: the "four pillars" (EchoelTools/Works/Sync/Well) referenced by older vision docs were **never built as modules** — `EngineBus` is the one real coupling spine; `Views/` now holds only `MetalBioView` + `OnboardingView` (its long deprecated list is gone).

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
  BioModulation, CloudSync und — nachgetragen 2026-08-23 (#757) — **`Core/BioSpaceMap`**
  (null Produktions-Aufrufer; die bio→Objekt-Abbildung, die WIRKLICH sendet, steht in
  `Sync/ADMOSCSender` selbst). Dazu — nachgetragen 2026-08-31 (#921) —
  **`Core/VisualModulation`** (nicht mit dem verdrahteten `BioVisualParams` verwechseln;
  Wächter `TheVisualModulationCoreHasNoCallerTests`). Dazu — nachgetragen 2026-09-02 (Audit) —
  **VIER `Sync/`-Kerne mit null Code-Aufrufern außerhalb der eigenen Datei:** `VBAPPanner`,
  `AmbisonicsEncode`, `LightFixtureGroup` (+`LightFixture`), `BioPhaser` (+`BioPhaserSource`) —
  je 1–2 Testdateien, sonst nur Kommentar-Nennungen. Befehl und Zähl-Kette:
  `memory/LEDGER_COUNTS.md` §Q. Nicht löschen (EchoelLux L2/L3 und der EchoelRender-Pfad
  brauchen genau sie), nicht als klingend/leuchtend zitieren. ⛔ #756 nannte `BioSpaceMap` als BELEG dafür, dass die
  Website-Zeile „breath→azimuth, coherence→distance, HRV→elevation" stimmt. Der SCHLUSS
  hält, der ZEUGE nicht — geprüft wurde der Inhalt der Karte, nicht ob jemand sie ruft. NOW WIRED — do NOT list these as unwired: BioVisualParams
  (read by `MetalBioView`; `EchoelBioEngine` names it only in a doc comment — audit 2026-09-02), FeedbackGuard (AudioEngine duck loop; ⛔ seine „Audio input"-Tür
  ist mit #1024 entfernt — ENGINE verdrahtet, TÜRLOS, siehe die #1024-Zeile oben), LearnLibrary (LearnView), EchoelFXView (doored via
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
| **iPad** | **vier Einstellungen + ein Wächter, in EINEM Commit** (`TARGETED_DEVICE_FAMILY` an App · Widget · beiden Test-Bundles, dazu `Tests/CISmoke/DeviceFamilyIsPhoneOnlyTests.swift` — harte Gleichheit im BLOCKIERENDEN Bundle — **plus zwei Prosa-Blöcke**, die beim Ändern falsch werden: der `#`-Block über der Einstellung und die ⛔-Notiz unter dieser Tabelle) | eine dort funktionierende Bio-Quelle — kein iPad hat eine rückseitige LED, und `CameraCapture` koppelt die rPPG-Beleuchtung an `device.hasTorch`; der BLE-Gurt ist gebaut+verdrahtet, die Watch käme als zweite Quelle infrage — **plus** #292 (heute reflowen **5 von 10** Panels; Befehl siehe die Zeile „Kein ‚nie'" unter dieser Tabelle. ⛔ Diese Zelle stand auf „2 von 11", während die Zeile „Kein ‚nie'" schon „2 von 10" sagte — DIESELBE Tatsache, zwei Zahlen, 12 Zeilen auseinander, weil #359 Schritt 3 nur die untere nachführte. Der Absatz unter dieser Tabelle trägt fünf Lehren über seine eigenen Zählfehler und keine davon lautete „such nach der ZWEITEN Stelle"; sie lautet jetzt so) |
| **Vision / XR** | kein Target; `visionOS` kommt in `Sources/` nur in Plattform-Guards vor (`MicrophoneManager`, `AudioInputManager`, `SPSCQueue`, `MemoryPressureHandler`) | der natürliche Sitz ist die **Ausgabe-Stufe, die schon existiert**: `ImmersiveStageView` (türlos, absichtlich — Ship-Gate 4 sagt „demonstrierbar, nicht erforderlich"), ADM-OSC-Raum, das Visual. Bio-Quelle bliebe Telefon oder Gurt |
| **Mac** | kein Target, kein Catalyst-Flag | offen |

⛔ **Was hier bis 2026-07-31 stand, war doppelt irreführend, und die zweite Fassung desselben Tages auch.** Erst: „iPhone-only for v10 MVP. iPad / Mac / Watch / Vision deferred to v1.1+" — während `project.yml` an ALLEN VIER iOS-Targets `TARGETED_DEVICE_FAMILY: "1,2"` setzte, die App also an iPad ausgeliefert wurde. Niemand hatte das entschieden; es war ein Default, den niemand nachgelesen hat. Dann, nach der Korrektur auf `"1"` (#292), las sich der Absatz wie ein **Ausschluss** von iPad/Vision — genau falsch herum, wie der Founder Stunden später klarstellte. Die Entscheidung (v1.0 = iPhone) steht; ihre BEGRÜNDUNG ist Sequenzierung und der fehlende Sensor auf iPad, nicht ein Verzicht auf das Ökosystem.

⛔ **Und die iPad-Zeile trug bis zur Reviewer-Nachlese am selben Tag einen Slogan, der in VIER Dateien gleichzeitig stand und in jeder falsch war:** „Wiederanschalten ist EINE Zeile" (hier, in `project.yml`, im Commit-Text und in `decisions.csv`) — während der Wächter, den **derselbe Commit** installierte, wörtlich sagt „change the settings AND this test in the same commit". Zwei Sätze aus einem Changeset, die einander widersprechen; der eingängigere war der falsche. Es sind vier Einstellungen plus der Wächter plus zwei Prosa-Blöcke, die beim Ändern falsch werden. **Lehre, weil sie sich von der üblichen unterscheidet:** hier war nicht eine Zahl veraltet, sondern eine Behauptung wurde nie geprüft, weil sie gut klang und niemandem wehtat — und sie ist genau der Satz, aus dem eine künftige iPad-Rückkehr ihren Aufwand schätzt. Ein Slogan, der Arbeit KLEINER macht als sie ist, ist gefährlicher als eine falsche Zahl.

⛔ **Dieser Satz war bis 2026-07-31 eine BEHAUPTUNG, kein Zustand** — und er stand hier, während `project.yml` an ALLEN VIER iOS-Targets `TARGETED_DEVICE_FAMILY: "1,2"` setzte, die App also an iPad ausgeliefert wurde. Niemand hatte das entschieden; es war ein Default, den niemand nachgelesen hat. Founder-Frage („Sind alle Fenster adaptiv für alle Geräte?") plus Delegation („Du entscheidest zukunftsweisend") → jetzt wirklich `"1"` (#292), abgesichert durch `Tests/CISmoke/DeviceFamilyIsPhoneOnlyTests.swift`.

**Der entscheidende Grund ist der SENSOR, nicht das Layout, und er gehört hierher, weil aus dieser Zeile heraus über Plattformen geplant wird:** `CameraCapture` koppelt die rPPG-Beleuchtung an `device.hasTorch`, und kein iPad hat eine rückseitige LED. Auf iPad läuft der Finger-auf-Linse-Puls also ohne Licht — genau die Bedingung, die der 2026-06-18-Fix als Ursache fürs Nicht-Locken identifiziert hat. Ein iPad-Build stellt die eigene Prämisse („Dein Körper spielt es") auf ein Gerät, auf dem die Hauptquelle degradiert ist.

**Kein „nie".** Die großen Flächen sind die Zukunft als **AUSGABE** — externer Bildschirm/Beamer (#206), ADM-OSC-Raum —, nicht als zweite App-Oberfläche. Kommt iPad als Instrumenten-Fläche zurück, braucht es eine dort funktionierende Bio-Quelle (der BLE-Gurt ist gebaut und verdrahtet) plus den Adaptivitäts-Durchgang #292. **Der Durchgang passiert ohnehin:** iPhone allein spannt 375–440 pt, erlaubt Querformat und läuft mit ungedeckeltem Dynamic Type — heute reflowen **5 von 10** Panels: `mixerPanel` · `soundPanel` (sieben Gitter) · `moodPanel` (zwei) · `visualPanel` (zwei) · `masterPanel` (EINS, bewusst nur das Target/Tone-Paar — die Leaf-Views und Vollbreiten-Zeilen bleiben absichtlich draußen). Die anderen fünf — `menuPanelHost`, `bioPanel`, `videoPanel`, `tempoToolsPanel`, `effectsPanel` — stapeln weiter starr. Wächter: `MasterPanelReflowsTests` · `MoodPanelReflowsTests` · `SoundPanelReflowsTests` · `VisualFineTuneReflowsTests`. ⚠️ **Der NENNER kommt aus `grep -c "private var \w*Panel\w*: some View" Sources/Echoelmusic/Studio/EchoelStudioView.swift` → 10**, und dieser Befehl misst die NAMENSFORM statt der Sache: er zählt `menuPanelHost` mit (der WIRT, kein Panel) und übersieht `utilityRow` (ein Dropdown-Panel, das nicht reflowt). Die Zehn stimmt als ZAHL, die MENGE ist um je einen daneben. ⚠️ **Der ⛔-Block darunter ist ein ANDERER Befehl und liefert 11** — er ODERt `weatherRow` hinein, weil er die GITTER-TRÄGER sucht, nicht den Nenner. Zwei Zahlen, zwei Fragen; wer sie verwechselt, hält eine für falsch. ⚠️ **Ein Gitter muss nicht im Rumpf seines Panels stehen:** `visualPanel`s zwei sitzen in `visualAdjustFields(spacing:)`, das der Rumpf nur AUFRUFT — wer per `grep` über Panel-Rümpfe zählt, findet sie nicht und zählt das Panel wieder als starr. **Dem AUFRUFER folgen.** ⚠️ **`spacing` ist bei `AdaptiveCardGrid` ein ARGUMENT, kein Literal** (heute 14 im `visualPanel`; der zweite Wirt `visualVJOverlay` mit 8 ging mit #1069): in EINER Spalte ERSETZT das Gitter den Abstand seines Wirts, ein fest verdrahteter Wert hätte also eine der beiden Flächen im Hochformat still umgesetzt. ⛔ **Die PROVENIENZ liegt in `memory/LEDGER_COUNTS.md` §F** — die vier Fassungen der Zahl, die #505-Kette („keine Tür") bis zu #747s Tür samt Asymmetrie-Begründung, die vom Wächter zurückgezogene und seit #747 wieder erfüllbare Founder-Bitte, und der alte Nenner elf. Sie stand bis #912 ZUSÄTZLICH hier: **#746 hat den ZEIGER gesetzt und den Text stehen lassen.** Der Deckel-Wächter konnte das nicht sehen — er prüft, ob die ZIEL-Sektion EXISTIERT, nie ob die QUELLE danach kürzer ist. **Ein Verschieben ist erst eines, wenn BEIDE Seiten gemessen sind**; die zwei Byte-Zahlen stehen in §F.4.

⛔ **Diese Zahl ist DREIMAL hintereinander mit dem falschen Panel begründet worden, und jede Korrektur hat den Fehler geerbt** (2 von 11 → 3 von 11 mit `sessionPanel`, das nie ein Gitter hatte → eine vierte Fassung, die Stunden hielt). **Die vollständige Kette liegt in `memory/LEDGER_COUNTS.md` §F.** Was als GESETZ hierbleibt, weil es beim MESSEN gebraucht wird:

**Ein Gitter kann in einem `private var` liegen, das KEIN Panel ist** — `weatherRow` war genau das. Wer die Zahl nachführt, folgt dem AUFRUFER, nicht der Dateireihenfolge; eine aus der Dateireihenfolge abgeleitete Zuordnung überlebt keine Verschiebung und hat hier zwei Codeänderungen überstanden, ohne dass ein Test rot wurde. Die dritte Zeile unten fragt genau danach —
```
grep -n "AdaptiveCardGrid {\|AdaptiveCardGrid(spacing" Sources/Echoelmusic/Studio/EchoelStudioView.swift
grep -n "private var \w*Panel\w*: some View\|private var weatherRow: some View" Sources/Echoelmusic/Studio/EchoelStudioView.swift
grep -n "^ *weatherRow$" Sources/Echoelmusic/Studio/EchoelStudioView.swift   # WER baut die Zeile ein
```
(die `private struct AdaptiveCardGrid`-Zeile selbst ist kein Treffer). **Die Lehre ist nicht „Zahl nachführen" — sie steht in dieser Datei schon dreimal.**

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
                          `git ls-files 'Tests/EchoelmusicTests/*.swift' | wc -l`.
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

⛔ **Diese Tabelle war einen Zyklus lang EINS-ZU-EINS, während die Engine es nicht ist** (#498): ein Ziel je Kanal, während Kohärenz allein VIER bewegt. **Lehre, verschieden von der Stale-Zahl-Lehre: eine Aufzählung wird gegen den CODE geprüft, nicht gegen ihre eigene Symmetrie** — #496 korrigierte die ÜBER-Behauptung derselben Zeile und ließ die UNTER-Behauptung stehen, weil nur eine sich als Zahl zählen ließ. Herleitung: `memory/LEDGER_COUNTS.md` §J (#867), wo sie mit dem zweiten Beleg #864 steht.

⚠️ **EINE BEDINGTE ABBILDUNG STEHT ABSICHTLICH NICHT IN DER ZEILE, weil ihre Nennung MEHR irreführen würde:** auf dem `.harmonicSeries`-Map-Profil übernimmt HRV die Harmonizität ganz (`0.40 + hrv * 0.50`) und überschreibt den Kohärenz-Term darüber. Sie zu nennen suggerierte, ein Spieler könne sehen, welches Profil aktiv ist — kann er nicht, es ist eine Patch-Eigenschaft. Was oben steht, gilt unter JEDEM Profil. Der Typ, der diese vier Kanäle für die Oberfläche beschreibt, ist `Studio/AlwaysOnBioChannel.swift`, und sein Dateikopf trägt dieselbe Messung samt Ausnahme.

⛔ **DREI STANDEN HIER ALS GLEICHRANGIG UND HATTEN KEINEN PRODUZENTEN** (gemessen 2026-08-08, #496): **Breath depth → Noise · LF/HF → Spectral tilt · Coherence trend → Shape morphing.** ⭐ **EINER DAVON HAT SEIT #813 EINEN — der Trend.** `Core/CoherenceTrend` leitet aus der Kohärenz-HISTORIE eine vorzeichenbehaftete Änderungsrate ab (−1 fallend … +1 steigend), auf dem MainActor gerechnet und über dieselbe SPSC-Queue an den Render-Thread gereicht wie der Rest; beide `…BioParams(`-Stellen schreiben jetzt `coherenceTrend: trend` statt der Literal-0, und der Steigend/Fallend-Spektralmorph ist damit **zum ersten Mal seit seiner Entstehung erreichbar**. Gespeist wird er aus dem ROHEN `frame.coherence`, nie aus `coherenceForSound`: eine Neutral-Ersetzung ist für einen PEGEL richtig und für eine ABLEITUNG falsch, weil die Ersetzung selbst als Bewegung gelesen würde. EINE HISTORIE PRO QUELLE (#920c), plus Schutzstellen für ungemessen, nicht-endlich, langes Loch und dt ≤ 0 — **hier steht bewusst keine Zahl** (#818: die Liste wuchs zweimal in zwei Tagen). ⛔ Hier stand „Drei Übergänge … Quellenwechsel“; der Quellenwechsel war nicht gebaut, und der GETEILTE Zähler, den diese Zeile beschrieb, wurde vom mitlaufenden HealthKit (`coherence: 0`) alle 4–5 s geleert — die Fähigkeit war also über-behauptet, nicht nur die Liste. Herleitung und Messung in `memory/LEDGER_COUNTS.md` §L. ⚠️ **Die anderen ZWEI bleiben tot**: `git grep -n "PolyBioParams(\|BioParams(" -- Sources` findet weiterhin genau zwei Konstruktionsstellen, und beide schreiben `breathDepth: 0.5` und `lfHf: 0.5`. Konsequenz je Zeile, am Verbraucher nachgelesen: `breathFactor` ist auf jedem Frame exakt 1,0 (die Zeile reduziert sich auf ein Zurückschreiben des Patch-Werts, was der eigentliche #279-Fix ist); `lfHfRatio` wird im Rumpf gar nicht gelesen (der Sanitizer sagt das selbst). ⚠️ **Die Skala des Trends ist eine SCHÄTZUNG** (`fullScaleRisePerSecond = 0.05/s`, benannt statt eingestreut) und das Einzige hier, was kein Test entscheiden kann — NEEDS-FOUNDER-VERIFY: Sitzung fahren, Kohärenz steigen und fallen lassen, sagen ob die Klangfarbenverschiebung hörbar-aber-nicht-störend ist.

⭐ **Zwei der drei waren am VERBRAUCHER längst aufgeschrieben, `coherenceTrend` als einziges nicht** — und genau deshalb hat diese Tabelle es überlebt. **Die Lehre ist nicht „Tabelle nachführen", sondern: ein ⛔-Vermerk am Verbraucher erreicht die Zeile nicht, die eine Sitzung ZUERST liest.** Diese Tabelle ist die Stelle, aus der Store-Text, Website und Panel-Kopie ihre Bio-Behauptungen holen; die #496-Scheibe musste die Fläche reparieren, die genau daraus „sieben" hätte machen können. Wächter: `Tests/CISmoke/TheAlwaysOnBioPathIsNamedTests.swift` nagelt die Pins an BEIDEN Konstruktionsstellen fest und verbietet der Panel-Kopie, die drei zu nennen. ⛔ **Und genau das war die halbe Miete (#755): alle drei Kopie-Wächter lesen SWIFT, die WEBSITE stand in keinem** — `docs/overview.html` verkaufte „Breath depth → Noise level" und „LF/HF → Spectral tilt" weiter als Abbildung, auf der Seite, die ein Besucher VOR `architecture.html` liest, die es die ganze Zeit richtig sagte. Seither deckt `WebsitePagesAreFindableAndHonestTests.testTheProducerlessBioChannelsAreNotSoldAsMappings` die Tabelle ab — die WÖRTER bleiben erlaubt (die FAQ nennt LF/HF-ANALYSE, und die ist echt), verboten ist die MAPPING-Behauptung. **Die verbliebenen ZWEI nicht als „live" zitieren, in keiner nutzersichtbaren Kopie** — ihr Code bleibt bewusst stehen. ⭐ Und die Vorhersage dieser Zeile ist eingetreten: sie sagte, „ein echter Produzent (z. B. ein Trend aus der Kohärenz-Historie) ist eine eigene Scheibe und wird genau diese Zweige antreiben" — **#813 IST diese Scheibe, mit exakt dieser Herleitung**. Im selben Commit mitgezogen: die drei Kopie-Wächter und beide Website-Seiten. Die Verbote auf „coherence trend" bzw. „shape morphing" mussten WEG, weil ein Wächter, der eine inzwischen WAHRE Aussage verbietet, selbst der Defekt ist (#364) — und `overview.html` behauptete „coherence trend is not computed at all", also eine negative Falschaussage auf der Seite, die ein Besucher zuerst liest.

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

⚠️ **Web sessions have NO Swift toolchain** (`command -v swift` → nothing): steps 2 and 5 are `git push` + reading the two gates (`Tests/CISmoke/CLAUDE.md` §5); a guard you cannot run is graded by transcription (§0 there). The `swift` lines above are for the founder's Mac.
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

⚠️ No local `swift` in a web session: skip the two `swift` lines and read the last runs instead (`mcp__github__actions_list` → `python3 scripts/gh-run-status.py <overflow-file>`).

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

## KEY TESTS (Anzahl: der `git ls-files`-Befehl in REPO STRUCTURE — hier steht bewusst keine Zahl)

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

**⚠️ WELCHES GATE WAS BEWEIST — die Unterscheidung, die jede Session sonst neu falsch rät.** Kurzfassung, die immer gilt: **`Xcode Compile Check` kompiliert `Sources/` ALLEIN** (Scheme `Echoelmusic` unter `build.targets`; ein grünes Häkchen sagt über eine TESTDATEI nichts) · **`Echoelmusic CI/CD Pipeline` meldet wegen #396 auf JEDEM Push `failure`**, also sagt die Conclusion nichts — man liest die JOB-SCHRITTE. ⛔ **Die ausführliche Fassung stand hier und ist mit #763 nach `Tests/CISmoke/CLAUDE.md` §5/§5b gezogen — 10.019 B, und sie war die DRITTE Kopie einer Entscheidung, deren eine Heimat `.claude/rules/context.md` §3 schon benannt hatte („is not repeated here (#416)").** Schlimmer als redundant: sie war die ÄLTESTE der drei (vor #667/#679/#738/#739), und die immer-geladene gewinnt per Default — eine Sitzung folgte hier einem Rezept, das §5 längst korrigiert hatte. **Wer ein rotes Gate liest, öffnet §5.** Dort steht auch, was NUR dort steht: der Beleg für die Compile-Check-Reichweite, die #210-Nebenwirkung, der #478-Cache-Schlüssel, die Clone-2-Rücknahme.

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
                                 ⛔ ADM-OSC und Art-Net tragen weiterhin KEINE Herkunft — **sACN
                                 seit #789 SCHON**, und die Gründe der drei sind VERSCHIEDEN.
                                 **sACN: ERLEDIGT.** E1.31 hat ein 64-Byte-**Source-Name**-Feld im
                                 Framing-Layer JEDES Datenpakets; `SACNSender` füllte es seit
                                 jeher hart mit „Echoelmusic", eine Demo-Sitzung schreibt dort
                                 jetzt „Echoelmusic (DEMO)". Das ist das EIGENE Feld des
                                 Standards, das ein Pult ohnehin in seiner Quellenliste anzeigt —
                                 nichts erfunden, kein Slot zu patchen. **Art-Net: OFFEN, aber
                                 aus einem PRÄZISEN Grund** — sein Datenpaket (`ArtDMX`, 0x5000,
                                 der einzige Opcode, den `ArtNetSender` baut) trägt gar keinen
                                 Namen; die Identität liegt in `ArtPollReply` (0x2100), einem
                                 Discovery-Paket, das Echoel nicht implementiert. Also fehlt ein
                                 BAU — aber einer, dessen RICHTIGKEIT hier niemand prüfen
                                 kann: 239 Byte fremder Spec, kein Gerät, kein Pult. Das ist eine
                                 andere Klasse als sACN, wo das Feld schon existierte und schon
                                 gefüllt wurde. Dazu: `git grep -ln NWListener -- Sources | wc -l`
                                 → **0** — die App hat gar keinen Eingangs-Socket (#821, gepinnt in
                                 `TheWireSaysWhoseBodyTests`). **ADM-OSC: OFFEN** — `/adm/obj/{n}/*`
                                 ist ein FREMDER Standard-Adressraum, dort etwas zu erfinden wäre
                                 das Gegenteil der Offene-Standards-Haltung, und ob er einen
                                 Hersteller-Namensraum reserviert, ist aus öffentlichen Quellen
                                 nicht messbar (Spec v1.0 = AES-Paper hinter der Paywall, #786).
                                 ⭐ **DIE LEHRE IST ÜBER REGISTER, nicht über DMX:** dieser
                                 Eintrag nannte, was Art-Net und sACN GEMEINSAM haben („tragen
                                 DMX"), und verbarg damit den Unterschied, der die Frage
                                 entscheidet — sACN ist DMX ÜBER E1.31, und der Träger hat einen
                                 Kopf, den die Nutzlast nicht hat. ⛔ Und die Vorgänger-Fassung
                                 sagte für DMX „hat gar keinen Platz für Metadaten" — auch das
                                 war falsch: ein Universum hat 512 Slots,
                                 `ArtNetSender.dmxChannels` belegt VIER (acht bei 16 Bit). Zwei
                                 Rücknahmen an derselben Zeile, beide in Richtung „es geht mehr
                                 als behauptet".
                                 ⭐ **Die Event-Adressen unten tragen sie SEIT #785 auch** —
                                 anderer Codepfad (`drainAndSendEvents` → `eventMessages`) und
                                 bewusst andere Kadenz: die Flagge steht unmittelbar VOR dem
                                 Ereignis, das sie beschreibt, und wird nur bei WECHSEL erneut
                                 gesendet (über Drains gelatcht). Grund: Ereignisse kommen in
                                 Bündeln (Per-RR-Schläge, Atem-Onsets paarweise) — pro Ereignis
                                 zu wiederholen vervielfacht den Verkehr auf genau dem Pfad, der
                                 latenzgeformt ist, ohne Information. Wer mitten in der Session
                                 dazukommt, lernt den Zustand aus dem ~1-Hz-Batch. Die Arität
                                 der Event-Adressen bleibt `[confidence, aux]`.
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
- Run `./review.sh` to surface decisions due for review; `./review.sh --flag` schreibt `REVIEW_DUE` in die Datei zurück
- ⛔ **NICHTS FLAGGT AUTOMATISCH — hier stand ein täglicher Cron als Tatsache.** #510 hat genau diese Behauptung am 2026-08-08 in `.claude/routines/05-decision-review.md` zurückgenommen („unwired as automation") und **diese** Datei stehen lassen, die jede Sitzung ZUERST liest — die #456-Form: Prosa zieht in JEDEM Zuhause mit, nicht nur dort, wo man gerade schreibt, und 16 Tage lang gewann das immer-geladene Zuhause. Gemessen: `git log -S REVIEW_DUE -- decisions.csv` ist über die GANZE Historie leer, und **kein einziger Workflow trägt überhaupt einen `schedule:`-Trigger**; `check-decisions.sh` ist eine crontab-Zeile, die ein Mensch installiert. Die Folge ist nicht kosmetisch: der Rückstand — Zahl mit `./review.sh | grep -c '^REVIEW DUE'` messen, nicht hier ablesen (#803) — sieht betreut aus und ist es nicht. Wächter: `TheDecisionLogIsMachineReadableTests`, Anspruch 7.

### Long-Term Memory (scratchpads/)

The `scratchpads/` directory is session-specific logs and plans:

| File | Purpose |
|------|---------|
| `SESSION_LOG.md` | **Read first — CAPPED**: newest entries are at the END; the hook prints `sed -n '1,80p'`; read `grep -n '^## ' scratchpads/SESSION_LOG.md \| tail -20` + `tail -200`, never the whole ~1.8 MB |
| `HARNESS_LEDGER.md` | **The idea-maze** — proven DEAD-ENDS (don't retry), reliable PLAYBOOKS, shipped leaderboard |
| `ARCHITECTURE_AUDIT_*.md` | Data flow diagrams, env object chains, init sequence |
| `PLAN_*.md` | Feature/fix plans before implementation |

**Start every session** by reading `memory/` first (the hook's slices), then the END of
`scratchpads/SESSION_LOG.md`, then the DEAD-ENDS table of `scratchpads/HARNESS_LEDGER.md`
(~300 KB — index it with `grep -n '^## ' scratchpads/HARNESS_LEDGER.md`, do not read it whole).

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
- Run `swift test` (founder Mac) or transcribe the guard in Python against both trees (web) — confirm RED
- Implement minimal code to pass
- Run `swift test` (Mac) / re-drive the transcription (web) — confirm GREEN
- Refactor while GREEN

**Phase 3 — Verify:**
- `swift build` must pass (`-warnings-as-errors`) — web session: push and read `Xcode Compile Check`
- `swift test` must pass — web session: CI/CD `Build for Testing` + `python3 scripts/gh-test-verdict.py`
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
