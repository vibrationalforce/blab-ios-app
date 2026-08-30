# BAUSTELLEN-BOARD — die eine Übersicht (angelegt 2026-07-17, ECC-Muster-Adoption)

> Founder-Direktive (Reel „Everything Claude Code", 2026-07-17): „Hiermit können wir
> die ganzen offenen Baustellen strukturieren und erfolgreich abschließen."
> Adoption = die ECC-MUSTER (Verification-Loop, Board-Orchestrierung), NICHT das
> 278-Skill-Paket (Entscheid decisions.csv 2026-07-17). Loop-Gesetz:
> **Keine Baustelle gilt als geschlossen ohne ihren Verify-Weg** — und der
> Verify-Weg ist fast immer der Founder-Gerätetest (Modus-Lehre).
>
> Pflege: `.claude/skills/baustellen/SKILL.md`. Jede Session: Board lesen →
> oberste offene Slice ziehen → Gates → Deploy → Verify-Spalte aktualisieren.
> Erledigtes wandert nach ERLEDIGT (mit Build-Nummer), nichts wird gelöscht.

## ⛔ STAND 2026-08-25 (#819) — LIES DAS ZUERST: dieses Board war einen Monat ungeführt

**Es ist nicht der lebende Arbeitsvorrat.** Zuletzt geführt am 2026-07-21; seither haben #121
Slice 4 (Clips + Arrangement), #166/#167 (Drums), #475 (der Noten-Editor) und die AUv3-Entfernung
(2026-07-24) Flächen gelöscht, auf die **neun** Zeilen (vier in AKTIV, vier in OFFEN, eine in BLOCKIERT) weiterhin zeigen. Jede davon
trägt jetzt ein ⛔-VOID mit ihrer Messung — **gelöscht wird nichts** (Board-Gesetz).

**Wo der lebende Vorrat steht, seit dieses Board still ist:**
· code-verankerte Geräte-Bitten → `python3 scripts/founder-verify.py`
· Urteils-/Screenshot-/Ein-Feld-Punkte → `scratchpads/FOUNDER_DEVICE_SESSION.md` (#816)
· was in DIESEM Build zu drücken ist → `.deploy/release`
· was zuletzt gebaut wurde → `scratchpads/SESSION_LOG.md`

**Zwei Zeilen sind nicht VOID, sondern eine schärfere Diagnose wert:**
· **REIHENFOLGE-Punkt 2 („Bio-Modulation live sichtbar")** ist NICHT geräte-gegated, wie die
  07-18-Zeile sagt. `ModulationEngine.lastOutputs`/`orderedOutputs` haben **null Verbraucher**
  (`git grep -n 'orderedOutputs' -- Sources` findet nur die Deklaration), und die Matrix hat
  **null Routen** (#541). Ein Messgerät darüber zeigte immer eine leere Liste — eine lügende
  Fläche. Blockiert ist es durch die fehlende ROUTE, nicht durch ein Gerät.
  ⭐ **UND DIESE DIAGNOSE IST IMMER NOCH DIE HALBE (#885, 2026-08-30).** Sie misst die MATRIX,
  und darin stimmt jedes Wort. Punkt 2 fragt aber „welche Parameter bewegt das Biofeedback" —
  und was es HEUTE bewegt, sind die IMMER-AN-Kanäle (`AlwaysOnBioChannel`), nicht die leere
  Matrix. Die haben zwei Türen (Puls-Pille → `bioPanel` → `AlwaysOnBioPanelStrip`; Effekte →
  `showAllFX` → `AlwaysOnBioView`), lesen Bio in ihrem EIGENEN Leaf und tragen 29 Wächter.
  **Punkt 2 ist damit geschlossen — nicht blockiert.** Herleitung + die vier Befehle:
  `HARNESS_LEDGER.md`, Eintrag #885. Diese Zeile war die dritte Heimat derselben halben
  Antwort; die anderen zwei stehen im Ledger und sind im selben Commit mitgezogen (#456).
· **A5 BodyVibe Kamera** lebt unverändert (`FaceExpressionBioPublisher`, `cameraExpression` in
  5 Dateien) und bleibt korrekt founder-gegated (Info.plist-Datenschutztext).

⚠️ **Dieses Board bekommt bewusst KEINEN vollen Text-Wächter.** Seine Historien-Tabellen nennen
die gelöschten Flächen absichtlich weiter (nichts wird gelöscht), ein dateiweiter Negativ-Scan
träfe also seine eigene Vergangenheit (#491). Was gepinnt IST: keine **unmarkierte** Zeile
in den drei Warte-Tabellen (AKTIV · OFFEN · BLOCKIERT) darf eine gelöschte Fläche nennen —
`Tests/CISmoke/TheWorkBoardDoesNotQueueDeletedSurfacesTests.swift`.

## 2026-07-21 Session-Ergänzung B (Ultracode-Sweep, 11-Agent-Triage + Task #79 Slice A)

Founder "Ultracode no sleep mode in Opus 4.8": Workflow-Sweep über ALLE offenen
Backlog-Punkte (#40, #51, #52, #53, #55, #56, #59, #60, #61, #67, #68), je ein
unabhängiger Opus-Agent, read-only, mit Pflicht-Zitat aus decisions.csv/Board vor
jedem `blocked_reason`. Ergebnis: **alle 11 bestätigt weiterhin korrekt blockiert**
(geräte-/founder-/entscheidungs-gated) — keine neuen blind-baubaren Splitter
gefunden, nichts hat sich seit der letzten Prüfung geändert. Volle Zitate je Task
im Workflow-Journal (`wf_2b471bbf-b14`) und in `decisions.csv` (Zeile
`ultracode-sweep-11-tasks-reconfirmed-blocked`).

Parallel dazu lief der bereits geplante **Task #79 Slice A Pilot** (siehe
`scratchpads/PLAN_RHYTHMIC_DIVERSITY_2026-07-21.md`) durch Implement→Review→Commit:

| Punkt | Commit | Verify |
|-------|--------|--------|
| Task #79 Slice A — `GenreFlavor`-Overlay (hatDensityBias/percGhostStep/kickPushEnabled) für die 6 `.fourOnFloor`-Genres | ab7f29b | code-reviewer APPROVED. Deklarativ, RNG-frei, bio-frei — Determinismus unangetastet. `testFourOnFloorKicksEveryBeat` bleibt grün, 2 neue Tests (Cross-Genre-Distinctness + Determinismus) grün. |

Nächster Schritt laut Plan: bei Erfolg (Founder-Ohr-Check auf dem nächsten Build)
Flavor-Overlay auf die übrigen 3 Archetypes (backbeat/offbeat/halfTime) ausrollen,
dann Slice B (stärkere Bio-Kopplung).

## 2026-07-21 Session-Ergänzung (Board war seit 07-18 nicht mehr geführt — Hygiene-Nachtrag, keine Zeilen gelöscht)

REIHENFOLGE (Founder-Verdikt v10.79.183, 5→1→2→3→4) war zu Sessionbeginn bereits vollständig
geschlossen/geräte-verifiziert-abwartend — kein neuer Code-Bedarf dort. Backlog-Triage-Workflow
(8 parallele Survey-Agenten über #40/#51/#52/#55/#56/#59-61/#67/#68) fand fast alles gerät-/
founder-/sequenz-gated (Details je Zeile unten in AKTIV/OFFEN); tatsächlich blind bearbeitbar
waren 2 Punkte, plus 1 direkter Founder-Ohr-Fix:

| Punkt | Commit | Verify |
|-------|--------|--------|
| Task #13 S1 — Audio-Lane-Recording-Hook (`AudioTakeRecording`-Seam, Flag OFF) | b1a38b9 | audio-thread-reviewer PASS-WITH-NOTES, fand+fixte Re-Entrancy-Race vor Push. Verhalten-identisch (Flag OFF) |
| Task #77 — Lead-Melodie in Bar 0 leiser (0.72×), direkte Founder-Ohr-Antwort "am Anfang ... laute Melodie" | 0bc1a9d | code-reviewer fing echten Bug (Dämpfung wiederholte sich jede Loop-Runde) vor Push; korrigierte Verdrahtung in `PianoRollModel.loadArrangement`. Tiefere Beat-Skelett/Progression-Frage bleibt ohren-gated (`decisions.csv:262`) |
| Task #52 — press.html Sitemap + Footer-Link | 01b913f, 34d2771 | docs-only, kein Sources-Risiko |
| Task #56 C6 — TimelineStore.persist() Disk-Write debounced (trailing-edge, ~47 Call-Sites) | 4b75941 | concurrency-reviewer PASS, fing 2 Tests mit falscher Sync-Write-Annahme (auf flushPendingSave() umgestellt) |

**TestFlight Build 2436 deployed** (62abddc → testflight.yml run 29864595254): Archive ✓ →
Export & Upload ✓ → ASC-Verify `state=VALID` (2026-07-21 20:18 UTC). Bündelt außerdem den bereits
laufenden b1a38b9/0bc1a9d/etc.-Stand.

**Bestätigt weiterhin blockiert (kein Code-Handeln, korrekt so):**
- #51 EchoelPublish — explizit auf v1.2 Broadcast-Ära verschoben (`decisions.csv:208`, 2026-07-15
  Entscheidung), kein Plan-Doc jetzt, würde eine bestehende Entscheidung überschreiben.
- #55 Leiste S2-S6 — Founder-Redesign-Entscheidung nötig (Mix/Synth/Sound-Chips tragen
  einzigartige Funktionen, siehe `PLAN_LEISTE_DISSOLVE_2026-07-20.md`).
- #56 Rest (C3/C7) — brauchen die echte Founder-Bildschirmaufnahme.
- #59/#60/#61 — bewusster Ideen-Parkplatz, erst nach der A-Serie (Founder-Sequenzierung, O10).
- #67/#68 BodyVibe — Info.plist-Datenschutztext (Front-Kamera-Beschreibung) braucht
  Founder-Freigabe vor Flag-ON; Track-Panel-Rest ist Geräte-Ohr-Verify.
- #40 DAW#4 Video — kein sicherer nicht-geräte-gebundener Slice in dieser Triage gefunden.

## AKTIV (in dieser Reihenfolge ziehen)

| # | Baustelle | Founder-Quelle | Nächste Slice | Verify-Weg | Route |
|---|-----------|----------------|---------------|------------|-------|
| A1 | ⛔ VOID (#819, gemessen 2026-08-25): `struct PianoRollView` ist mit #475 gelöscht; `git grep -n 'RollChordStamp(' -- Sources` → 0 Konstruktionsstellen, die Paint-Lane (Vel⇄Cha⇄Occ) ging mit der Ansicht. Die KERNE leben (`RollChordStamp`, `BreathArp`, `setChance`, `setOccurrence` in `PianoRollModel`) — der HÖRTEST ist unausführbar. **Piano Roll adaptiv + Pro-Funktionen** | „passt immer noch nicht…adaptiv" + „mehr Funktion… siehe Ableton… Echoel twist" (07-17) | Adaptiv v286 ✓, R1 v287 ✓, **R2 Akkord-Stempel KOMPLETT + DEPLOYT v290 ✓** (b22a6c2): Kern `RollChordStamp` (e126994, code-reviewer PASS) + UI Chord-Modus-Toggle (5f51b23, ui-state-reviewer PASS 0 Defekte) — Tap stempelt kohärenz-gewählten, voice-geführten Akkord, alle Gates grün. Nächste: **R3 Breath-Arp-Stempel KOMPLETT** (86e9f7a, ui-state-reviewer 0 Defekte): zweiter Roll-Modus (wind-Symbol, exklusiv zum Chord) — Tap arpeggiert den kohärenz-Akkord mit dem LIVE-Atem (RollChordStamp+BreathArp). **R4 per-Note-Chance KOMPLETT + DEPLOY v292 ✓** (50eb030): untere Paint-Lane bekam Vel⇄Cha-Toggle (Label tippen) — im Cha-Modus setzt/zeigt jeder Balken die Note-Abspiel-Wahrscheinlichkeit 0…1; `setChance` spiegelt `setMPE` (Clamp, andere Operatoren bleiben, Default→nil), Body bendet Schwelle live (A4). ui-state-reviewer 0 Defekte, alle 4 Gates grün. **R5 per-Note-OCCURRENCE KOMPLETT + DEPLOY v294 ✓** (bd33b1b + @MainActor-Fix fb8f6e9, code-reviewer fing 1 build-red): Paint-Lane-Toggle jetzt 3-fach Vel→Cha→Occ — im Occ-Modus malt jeder Balken die Occurrence-PERIODE als 1:N-Ratio (voller Balken = jede Schleife 1:1, halb = 1:2 …); bei Playback via `operatorAllows→hits` gegated (hörbar). Repeats bewusst NICHT (braucht W2-Sub-Step-Clock → wäre stummer No-Op, kein lügender Halb-Pfad). `setOccurrence` spiegelt `setChance`, Map ist echte Inverse. ui-state-reviewer 0 Defekte. Nächste: Repeats erst nach W2-Clock | **HÖRTEST v290 offen:** klingen die Akkorde musikalisch + zur Tonart? Verändert Kohärenz die Farbe spürbar? **R5 Occ:** Note auf 1:2 malen, Loop → spielt sie nur jede 2. Runde? | PLAN_ROLL_PRO.md |
| A2 | **Harmony-Serie H1+H2+H3** | Scaler-Analyse-Ask (07-17) | KOMPLETT + AN (H2-Flip 411e972 grün, in v287) | Hörtest: erzählt die Harmonie eine Geschichte? | Rollback je 1 Wort |
| A3 | **Hörtests v285–v287** (VoiceLeading·Humanize·Journey·Roll·Bio-Spur) | Modus-Lehre 07-17 | v287 DEPLOYT — wartet auf Ohr | Founder-Urteile | — |
| A4 | **BodyVibe B1 — EchoelBodyVibe-Instrument** | Screenshot „Bio Instrument → EchoelBodyVibe" (07-17) | ENGINE ✓ in v287 (45dc157: .bioVoice-Allokation + eigene Rack-Instanz, Sequencer-Gate, SPSC-Kontrakt geschützt). Nächste: B1-UI (Create-from-Within-Panel) + Umbenennung NACH Geräte-Klang-Verify | Bio-Spur klingt + reagiert auf Puls auf Gerät | Kein lügendes Label |
| A5 | **BodyVibe B2 — Kamera-Modulator Stufe 1** | „Grimassen/Smile/Arme als Modulator" (07-17) | FUNDAMENT ✓ (d624fcc grün) + Mapping-Kontrakt ✓ (62ef41f grün) + CAPTURE-SEITE ✓ (901ebf5, Gates laufen): `BioSource.faceCam` + `FaceExpressionBioPublisher` (ARKit, rPPG-Sicherheitsmuster, `FeatureFlags.cameraExpression` OFF → unverdrahtet/byte-identisch). Concurrency-Review PASS, Bio-Safety PASS(1/2/3/5). **HARTER BLOCKER für die Verdrahtungs-Slice (Bio-Safety HIGH):** die eine `NSCameraUsageDescription` beschreibt nur Heck-Fingerpuls — MUSS vor Flag-ON auf Front-Gesichts-Tracking erweitert werden (5.1.1/GDPR), Info.plist braucht Founder-Freigabe. Nächste (Verdrahtungs-Slice): `BioSourceKind.face` + Dropdown (capability-gated) + Default-Route faceSmile→Param + Info.plist-String + Puls-Koexistenz-Entscheid | Lächeln verändert hörbar die Komposition — **Gerät offen (folgt mit Verdrahtungs-Slice)** | RESEARCH_BODYVIBE_CAMERA; Copy: „Expression/Steuerung", NIE „Emotion" |
| A6 | **Chips auflösen C** (Sound·Mix·FX·Mood·Synth·Video weg) | 2 Screenshots (07-17) | Erst wenn A4 die Spur-Panels trägt; Video-Voraussetzung (Photos-Save) GEBAUT | Untere Leiste leer/weg auf Gerät, nichts unerreichbar | PLAN_BODYVIBE §C |
| A7 | ⛔ VOID (#819): `git grep -l launchGlyphOverlay -- Sources` → 0; `ClipView` und `ArrangeTimelineView` sind mit #121 Slice 4 gelöscht. Der Verify-Weg „Performance-Mode → Audio-Clip-Play tappen" hat keine Fläche. `LaunchTiming` und der AudioLanePlayer-Pfad leben. **Automation in der Timeline + Clip-Launch/Performance** | „Automation … in der Timeline direkt" + „Play Button auf den Clips und Performance Mode" (07-17) | T1 ✓ (f60a0e9 grün, in v288). P0-Core ✓ (750c293, Golden-Gate adversarial verifiziert) + P1-UI ✓ (7fcf9cb, Play-Glyph+Performance-Toggle) — Gates laufen. **PLAN audio-lane-launch Council-signiert ✓** (3ef1b45, `PLAN_AUDIO_CLIP_LAUNCH.md`): Loop-Restart-Mathe existiert schon (`LaunchTiming.loopWrapped`), nur AudioLanePlayer-Verdrahtung fehlt (Engine mit Stille-Historie #22 → PLAN-first). **S1 ✓** (41fac9c + Test-Härtung 595653c, Gates laufen): AudioLanePlayer Override-Türen + 9 SpySink-Tests, unsichtbar/kein Caller. audio-thread-reviewer CLEAN (golden gate verifiziert), code-reviewer clean (kein Crash/Stille-Bug). **S2 ✓** (bf38ff8 + LOW-Fix 31023c0, Gates laufen): TimelineRegionPlayer Audio-Dispatch — launchRegion erlaubt .audio, applyLaunchTransitions routet an setLaunchOverride/clearLaunchOverride (Anker t.atTick), alle 4 Reset-Pfade paaren clearAllLaunchOverrides. audio-thread-reviewer CLEAN, code-reviewer clean. INERT bis S3. **S3a ✓** (c0a05c2 + Wrap-Re-Trigger-Fix 91deeff): Override-Lifecycle — prime überspringt Overrides, shiftLaunchOverrides (Wrap-Anker-Fold), pruneLaunchOverrides (Struktur-Edit), applyWrappedOverrides (bar-alignter Loop wird AM Song-Wrap neu getriggert → kein stiller Takt, Audio im Lockstep mit MIDI), 6 Tests inkl. echtem transportStep-Wrap-Pfad. audio-thread-reviewer x2 CLEAN. **S3b ✓** (2d2e151): launchGlyphOverlay isMidi→isLaunchable(midi‖audio) → Play-Knopf auf Audio-Clips, Video/Bio ausgeschlossen. ui-state-reviewer 0 Defekte, alle 4 Gates grün. **A7 KOMPLETT → DEPLOY v10.79.291.** | Founder: Performance-Mode → Audio-Clip-Play tappen, Clip loopt hörbar (Hör-/Fühl-Bitte in Deploy-Note v291) | Freeze-Gesetz ✓, keine 2. Sheet ✓, Golden Gate ✓ |
| A8 | ⛔ VOID (#819): das AUv3-Target ist am 2026-07-24 entfernt (`project.yml` sagt es selbst). **AUv3-Register-Reparatur** | Log build 2394: self-probe -3000, raw 101 comps alle Apple | ANSAGE an Founder gegeben | App löschen + TestFlight-Neuinstallation → nächster Log zeigt ownAUv3 true | Geräte-Register korrupt, kein App-Bug |
| A9 | ⛔ VOID (#819): kein AUv3-Target mehr. Die App-Group-Brücke selbst lebt und ist harmlos. **App-Group-Puls-Brücke** (AUv3 in fremden Hosts) | Founder-Q „AUv3?" | GEBAUT ✓ (6a568d8, Freshness+5.1.3+10Hz) in v288 | EchoelBodyVibe in GarageBand vom echten Puls gespielt | — |

## OFFEN (nach AKTIV nachrücken)

| # | Baustelle | Founder-Quelle | Nächste Slice | Verify-Weg |
|---|-----------|----------------|---------------|------------|
| O1 | ⛔ VOID (#819): `ClipView` gelöscht (#121 Slice 4). Clip-Handhabung rudimentär + Zittern (Task #56) | 07-16, „weiter offen auf 2373" | Slice-Review offene MEDIUMs; Founder-Repro-Clip anfordern | Clip ziehen/trimmen ruckelfrei auf Gerät |
| O2 | ⛔ VOID (#819): keine Clip-Editor-Tür — `git grep -ln 'clipEditor\|ClipEditorView\|AudioClipEditor' -- Sources | wc -l` → 0. Die Stretch-Kerne (`StretchPlan`, `AudioClipPlayer`) leben unerreichbar weiter. Warp im Audio-Clip-Editor (#54) | 07-16 „neuste Technologie" | Plan liegt; nächste Slice nach C | Audio-Clip folgt Tempo hörbar |
| O3 | ⛔ VOID (#819): der Noten-Editor ist gelöscht (#475, Founder „Pianoroll soll raus"). MIDI/MPE-Station ausbauen (#58) | 07-16 „sehr rudimentär" | A1 ist die laufende Slice; danach: Velocity-Lane-Edit, Scale-Lock (Scaler #5) | Founder editiert Clip vollständig im Roll |
| O4 | Scaler #4 — Atem-Pattern-Generatoren | Scaler-Analyse | KERN ✓ (6c2a6b9 Slice-1 + a6e4818 Slice-2 grün: Atemphase→Richtung, Tiefe→Dichte, Akkord-Walk, Puls→Swing, Motion→Strum). **VERDRAHTET ✓** (86e9f7a, ui-state-reviewer 0 Defekte, Gates laufen): Roll-Toolbar-Modus „Breath Arp" (wind-Symbol, exklusiv zum Chord-Stamp) — Tap arpeggiert den kohärenz-gewählten Akkord mit dem LIVE-Atem. Nächste: nur noch Gerät | Arp folgt hörbar dem Atem — **HÖRTEST offen** (Roll: wind-Knopf an, leere Zelle tippen) |
| O5 | ⚠️ HALB VOID (#819): die ANWENDUNG lebt (`rollPatchSink`, `slotPatchSink`), die EDITOR-Tür `.patch(lane)` ging mit dem `craftEditor`-Slot am 2026-07-26. Per-Instrument EchoelSynth (#23) | ältere Serie | **PLAN+Council ✓**. **S1 ✓ (b2f7750):** `setLanePatch`+4 Tests, Gates grün. **S2 ✓ (3280aa9+aef9b67):** `.patch(lane)`-Editor-Tür, Gates grün, code+ui-state-reviewer CLEAN. **S2b ✓ SHIPPED (05e8d37):** `rollPatchSink` — Primär-Roll-Lane wendet ihren `lane.patch` bei Region-Load auf die globale Stimme an (nil-Guard: kein Clobber des Live-Sounds); audio-thread-reviewer CLEAN, 2 Tests. **JETZT vollständig hörbar** (Sekundär via slotPatchSink, Primär via rollPatchSink). → **Deploy-Kandidat für Founder-Hörtest** (nach Gates grün + code-reviewer). Offen: S3 Live-Drag-Preview auf Sekundär-Lane [gerät-gated, optional]. | **2 Spuren, 2 Klangfarben, beide hörbar** — Gerät-Hörtest = Closeout |
| O6 | Audio-Loop-Import + Record-Capture Gerät (#13) | ältere Serie | Geräte-Verify des bestehenden Pfads | Loop landet in Lane, Record schreibt Clip |
| O7 | Immersive-Stage-Automation (#20) | ältere Serie | AutomationGestureRecorder anbinden | Puck-Fahrt wird aufgezeichnet + spielt zurück |
| O8 | rPPG-Sättigung Auto-Recovery (#25) | Log-Serie | device-iterate (nicht blind tunen) | Log zeigt Recovery ohne Neustart |
| O9 | EchoelPublish (#51) · Website-SEO (#52) | 07-15 | Marketing-Pipeline, nach Produkt-Baustellen | Founder-Review |
| O10 | EchoelWeather-Synth (#59) · EEG-Quelle (#61) · Bio-Session-Brain (#60) | 07-16 | Ideen-Parkplatz — erst nach A-Serie | — |
| O11 | Sampler-Name statt UUID (UX-Niggle) | 07-17 Beobachtung | **GEFIXT (MediaLibrary.uniqueName)**: Import speichert lesbaren Quell-Namen statt `<UUID>.ext`; `sampleRefDisplayName` zeigt jetzt "MyLoop" statt UUID. code-reviewer clean (1 LOW: stale H6-Kommentar korrigiert). 5 Tests. Reitet nächsten Deploy | Spur zeigt Sample-Namen (Gerät-Verify) |
| O12 | Mood-Feintuning | 07-17 Beobachtung | Nach Hörtest-Feedback | Founder-Ohr |
| O13 | ✅ **ALLE DREI BEHOBEN 2026-08-30** — (b) zweite Weigerung in Folge sichtbar (#892: Streak-Zähler `micRefusals`, bewusst NICHT beim Armieren zurückgesetzt) · (c) VoiceOver bekommt die Ansage (#897; Geräteprobe offen) · (a) verweigerte Berechtigung (#896: `permissionDenied` wird in `checkPermission()` aus dem Systemstatus abgeleitet, drei Zustände = drei Gründe; **der UNBESTIMMTE war der eigentliche Hänger**, nicht der verweigerte). Ursprünglicher Eintrag: **Reviewer-Rückstand aus #891/#892 (Mic-Weigerung), NICHT gefixt — hier abgelegt, damit er nicht verschwindet.** (a) **Verweigerte Berechtigung hängt weiter bei 0 %**: der Diskriminator ist `hasPermission`, und bei DENIED zeigt iOS keinen Dialog, `hasPermission` bleibt für immer false, der Abbruch feuert nie. Braucht `MicrophoneManager.permissionDenied` an einer Fläche — die Property hat im ganzen Sprachpfad **null Leser** (die einzigen UI-Verbraucher sind Kamera-Pfade). (b) **Zweite Weigerung in Folge ist unsichtbar**: Text und Knopf sind vor und nach dem zweiten Tipp byte-gleich — genau das „twice in a row" der #890-Geräteprobe. (c) **VoiceOver bekommt gar nichts**: auf dem Abbruch ändert sich am fokussierten Knopf kein Label/Hint/Value; die Meldung ist ein unfokussiertes Geschwister-`Text`. Präzedenz für die Behebung: `Studio/AudioDegradedRow.swift` (Accessibility-Container). | Reviewer 2026-08-30 (audio-thread + ui-state, unabhängig) | (b) ist die billigste und dient direkt der offenen Geräteprobe; dann (c); (a) zuletzt, weil es eine neue Fläche braucht | Weigerung zweimal auslösen — Text muss sich beim zweiten Mal ändern; VoiceOver muss sie ansagen |
| O14 | ✅ **BEHOBEN (#900 + #901-Nachlese + #902, 2026-08-30)** — ⭐ Der ZUGEHÖRIGE `try?`-Teil dieser Zeile ist mit **#902** geschlossen: `releaseRecordRoute` hatte zwei AUSGÄNGE, aber DREI Ergebnisse; ein geworfenes Herunterstufen teilte sich die Zeile mit dem geglückten und wurde von acht `try?`-Aufrufstellen verschluckt. Jetzt eigene, unnummerierte Diag-Zeile, Fehler wird durchgereicht. Bewusst KEIN Wiedereinfügen des Besitzers (Phantom-Halter = #838b-Falle) und KEIN Retry (`recordingRouteNeeded` wird VOR dem werfenden `setCategory` gelöscht, die nächste Sitzungs-Umstellung stuft selbst herunter — es fehlte nur die SICHTBARKEIT). #901 hat zusätzlich den `#877`-Vermerk mitgezogen, dessen Szenario #900 unerreichbar gemacht hatte. Ursprünglich: **BEHOBEN (#900, 2026-08-30)** — der `catch` nilt jetzt `audioEngine`, `inputNode` und `complexDFT` selbst, ohne den Tap anzufassen (Wächter `RecordRouteOwnershipTests.testTheThrowingStartExitDropsItsHalfBuiltGraph`, gegen beide Bäume in Python gefahren). Der ZUGEHÖRIGE Punkt am Ende dieser Zeile — die Startseite gibt die Record-Route mit `try?` frei, und ein werfendes `downgradeToPlaybackAfterRecording()` lässt die Session auf `.playAndRecord` — ist NICHT mitrepariert und bleibt offen. ⛔ Ursprünglicher Text: **Der werfende `startRecording()`-Ausgang räumt nicht auf** — `catch` lässt `audioEngine`, `inputNode` und `complexDFT` stehen (Tap installiert, Engine nicht laufend). ⚠️ **Schwere selbst nachgeprüft und NIEDRIGER als gemeldet**: der #877-TRAP-Vermerk in `stopRecording()` analysiert genau diesen Zustand und nennt ihn „harmless today — the tap dies with the engine, and `startRecording` always builds a FRESH engine". Was #891 WIRKLICH ändert: vorher räumte der unvermeidliche Cancel des Nutzers über `stopRecording()` auf, jetzt nicht mehr — also hält `complexDFT` Speicher bis zum nächsten Start, und die Objekte leben länger. Kein Absturzpfad, den der Bestand nicht schon abgewogen hat. **Zugehörig**: die Startseite gibt die Record-Route mit `try?` frei (still, ein Versuch); wirft `downgradeToPlaybackAfterRecording()`, ist die Besitzer-Menge schon leer und die Session bleibt auf `.playAndRecord` — die Stop-Seite hatte den zweiten Versuch, den #891 vom Abbruchpfad genommen hat. | Reviewer 2026-08-30 (audio-thread) | Am QUELL-Ort reparieren, nicht im Abbruch: der `catch` nilt seine drei Referenzen selbst (ohne den Tap anzufassen — dieselbe Disziplin wie `stopRecording`, sonst ist es die `isInputConnToConverter`-Familie) | Diag-Log nach einem geworfenen Start zeigt keinen zweiten Start auf einer Alt-Engine |

## ARCHITEKTUR-AUDIT-BACKLOG (2026-07-18, ultracode 54 Agenten — `scratchpads/ARCHITECTURE_AUDIT_2026-07-18.md`)

> 32 bestätigte Befunde. Kernbotschaft: **zwei Wurzeln entriegeln fast alles** —
> (A) tote/eingefrorene Bio-Freshness-Disziplin, (B) falsch dokumentierte DSP-Thread-Invariante.
> Die 5 billigsten Hebel, nach Report-Rang (jeder klein & reversibel):

| # | Fix | Datei | Entriegelt | Status |
|---|-----|-------|-----------|--------|
| AU1 | **Arrangement additive Codable** (kein stiller Song-Verlust) | Sequencer/Arrangement.swift | #39/#40/#11 | ✅ 66f94dc GRÜN (beide Gates) |
| AU2 | Bio löst zu neutral — **Ursache gefunden: fehlende Range-Expansion** (depth/curve/invert skalieren runter/formen, aber nichts weitet ein enges Bio-Fenster [z.B. Kohärenz ~0.3–0.6] auf Vollskala) | Core/ModulationMatrix.swift | #60, halb #61 | ✅ **PRIMITIV GEBAUT f486c5c:** `ModRoute.inputLow/inputHigh` Sensitivity-Window (Identity-Default = golden-gate), 10 Tests, code-reviewer CLEAN. UI-Knopf + Founder-Feel-Tuning = device-gated Folge |
| AU3 | DDSP-Header-Invariante korrigieren (Doc-Fix) | DSP/EchoelDDSP.swift:44 | #59, schützt jeden DSP-Edit | ✅ 277a543 (+Präzisierung), concurrency-reviewer verifiziert. Deckte NEUEN Ticket-Befund auf → AU6 |
| AU6 | **Bio-Pfad Cross-Thread-COW-Hazard:** `applyBioReactive→updateSpectralEnvelope` schreibt `harmonicAmplitudes`-Array um (nicht-atomar) auf PolySynthVoice/AUv3-Direktpfad | DSP/EchoelDDSP.swift + PolySynthVoice | #23-Klasse Audio-Stabilität | ✅ **GESCHLOSSEN (nachgemessen 2026-08-30, #886).** Der Dateikopf von `EchoelDDSP.swift` sagt es selbst: BEIDE Besitzer rufen `applyBioReactive` im RENDER-Block (`BioReactiveSynthVoice` und `PolySynthVoice` reihen auf dem Poll in eine SPSC-Queue ein und drainen im Render). Der DRITTE Besitzer — der AUv3-KVO-Poll mit den `BioMirror`-Floats — ist mit #121 Slice 1 verschwunden; `git grep -n BioMirror -- Sources` liefert heute GENAU EINEN Treffer, und der ist der Grabstein-Kommentar. Folge, wörtlich im Kopf: der In-Place-Rewrite passiert „on the ONE render thread that also reads it, so there is no longer a cross-thread array race / COW hazard on any path". ⚠️ Die Spaltenangabe `:1287` ist bewusst entfernt — eine Zeilennummer in einer lebenden Datei ist ein Datum, kein Ort |
| AU4 | MicrophoneManager `guard !isRecording` + Session-Teardown (#22-Klasse) | MicrophoneManager.swift:194/269 | #13 | ✅ 0077a59 grün, audio-thread-reviewer APPROVED (re-entry-guard + downgradeToPlaybackAfterRecording statt setActive(false)). PRÄVENTIV (Pfad dormant), reitet nächsten Feature-Deploy — kein eigener Hörtest. Follow-ups geloggt: recordingRouteNeeded→Refcount vor Mic-Entkopplung; wahrscheinlicherer Live-Pfad = AudioEngine.stop():632 (unberührt, #22 gilt gefixt) |
| AU5 | AudioEngine Meter-Props `@ObservationIgnored` (60-Hz-Freeze-Landmine) | Audio/AudioEngine.swift (`masterLevel`/`masterLevelR`) | #11 | offen — **aber NICHT „mechanisch"**, siehe die korrigierte Notiz unter dieser Tabelle (#886). Die zwei Wörter widersprachen der Notiz zwölf Zeilen tiefer, die denselben Posten „riskanter Live-Meter-Self-Poll-Refactor" nennt: ein Slogan, der Arbeit KLEINER macht als sie ist, ist gefährlicher als eine falsche Zahl |

> HIGH-Befunde außerhalb der Top-5 (eigene Zyklen): AUv3 Cross-Thread-Race + malloc im Render
> (EchoelmusicAudioUnit.swift:226/391 — deferred Target, #50), ~~Colab umgeht Egress-Gate
> (LiveColaboView.swift:78, App-Store 5.1.3)~~ **✅ GEFIXT (b825b54):** `BioEgressPolicy.allowsEgress(f.source)`-Guard
> im Share-Loop (spiegelt ADMOSCSender:178) — HealthKit/Watch/Oura streamen nicht mehr zu Peers;
> security-agent SECURE+vollständig (einziger Bio-Egress-Pfad). Optionale Defense-in-Depth (Gate IN
> sendBio) für späteren Zyklus notiert. FaceExpression-Permission lügt (Info.plist, Founder-OK).
> **AU5** (Meter-Props @ObservationIgnored) = **latent/eingegrenzt, zurückgestellt:** die Props werden NUR
> von `MasterLoudnessGrid` (Leaf-Meter, sichtbarkeits-gegatet) gelesen — EchoelStudioView liest sie NICHT,
> also KEIN Live-Freeze heute; das Shield bräuchte einen riskanten Live-Meter-Self-Poll-Refactor (unter
> No-Compiler nicht blind). Präventiv-only → eigener Gerät-/Compiler-Takt.
> ⛔ **DAS WORT „NUR" IST SEIT #747 FALSCH — der SCHLUSS hält, der ZEUGE nicht (nachgemessen 2026-08-30, #886).**
> `git grep -n "masterLevelR" -- Sources` findet einen ZWEITEN echten Leser: `SpectralDonutView`
> (zweimal, `max(masterLevel, masterLevelR)` als Hüllkurve für Ringdicke und Sway). Der war
> **türlos**, als diese Notiz geschrieben wurde, und ist mit #747 (Knopf „Full screen" im
> `visualPanel`) **erreichbar** geworden — die Prämisse hat sich also geändert, ohne dass jemand
> die Notiz anfasste, und ein Text-Wächter hätte das nie rot gemacht.
> ⭐ **Warum „KEIN Live-Freeze" trotzdem STIMMT, und zwar aus einem Grund, den die alte Notiz gar
> nicht nannte:** `SpectralDonutView` ist ein eigener `View`-`struct` (also eine echte
> Beobachtungsgrenze) und liegt im `.fullScreenCover` als **GESCHWISTER** von `visualVJOverlay`
> in EINEM `ZStack` — nicht als dessen Vorfahre. Es zeichnet ohnehin mit 60 Hz
> (`TimelineView(.animation)`), das ist seine Aufgabe. Die Deckel-Closure selbst liest nichts
> Schnelles: `currentToneHz` = `session.a4Hz` + `rootIndex`, `autoMode`/`spectralDonuts` sind
> `@AppStorage`. **Das Freeze-Gesetz redet über VORFAHREN eines Menü-Wirts** — Geschwister-Churn
> ist harmlos.
> ⚠️ Die Lehre ist die #756-Form: **eine richtige Schlussfolgerung mit falsch gewordenem Beleg ist
> schlimmer als ein offener Posten** — wer sie später als Prämisse benutzt („nichts sonst liest die
> Meter"), leitet daraus eine Freigabe ab, die der Beleg nicht mehr trägt.
> PLAUSIBLE/Gerät-Verify: SPSCQueue OSAtomic-Race (:153) — höchstes latentes Risiko, kein Ralph-Quick-Win.
> #66 (tote Türen) = eigener Closeout-Loop.

## BLOCKIERT (wartet auf Founder)

| # | Baustelle | Wartet auf |
|---|-----------|-----------|
| B1 | ⛔ VOID (#819): kein AUv3-Target mehr — die Bitte um ein Diagnose-Log dafür kostet den Founder eine Probe, die nichts entscheiden kann. **a) Externe AUv3 fehlen in der Liste** | `echoel_diag.log` nach iPhone-Neustart (self-probe-Zeile + scan-Zeilen). Workaround kommuniziert: GarageBand einmal öffnen registriert AUv3 neu. |
| B2 | Hörtest-Urteile v285/v286 (Stimmführung, Humanize) | Founder-Ohr; Rollback je 1 Wort dokumentiert |

## ERLEDIGT 2026-07-17 (Verify-Stand)

| Baustelle | Build | Verify |
|-----------|-------|--------|
| Spur=Instrument-Panel (A/A2), Beats-Timeline, Header | v281–v283 | Founder-Test ✓ (mit Befunden b/c → v284) |
| Sampler hörbar (voiceKindRouting ON + Sampler-Lane) | v282 | CI ✓, Gerät ✓ |
| Photos-Mediathek-Save (Video-Chip-Voraussetzung) | v283 | CI ✓, Gerät offen |
| H12: MIDI-Clip pro Spur, Drums im Editor, Roll-Leiste scrollt | v284 | Founder: b) behoben; Roll-Fit → A1 |
| Harmony H1 VoiceLeader + default-ON | v285 | CI ✓, Hörtest offen (B2) |
| Harmony H3 HRV-Humanize + default-ON | e8d124b/a511205 | Gates laufen; Hörtest offen (B2) |

## ERLEDIGT 2026-07-18 (Härtung — reiten nächsten Feature-Deploy, kein Hörtest)

| Baustelle | Commit | Verify |
|-----------|--------|--------|
| Egress-Sweep KOMPLETT: Art-Net + sACN Bio-Netzausgang auf BioEgressPolicy gegated (letzte 2 ungegateten Netz-Konsumenten; 5.1.3) | bbbf5dd | CI ✓ (beide Gates grün); security-agent SECURE, kein Rest-Leck |
| EchoelLux L1: Blackout/Grand-Master bleibt autoritativ ohne frische/erlaubte Quelle (hält letzte Roh-Farbe, master/slew läuft weiter) — behebt vom Egress-Sweep verbreiterte No-Source-Early-Return-Kante | 65ff88b | code-reviewer PASS (bounded, kein Idle-Resend, egress-clean); Gerät-Verify: Blackout in reiner HealthKit-Session (optional, latent) |
| **Item 1 Automation-in-Spur PLAN+Council** (Spine ~70% gebaut; Lücke = Editier-Reichweite; L1 Draw-into-Clip zuerst) | 760a1ac | PLAN_AUTOMATION_IN_TRACK_2026-07-18.md, Task #70 |
| **Item 1 L1/S1:** `ClipStore.setClipAutomation` Write-Back (die fehlende Editier-Mutation; Clip trägt+spielt schon) + 8 Tests | e30c249 | CI ✓ beide Gates; code-reviewer PASS (2 LOW behoben) |
| **Item 1 L1/S2a:** `ClipAutomationEdit` reines Array-Editier-Gehirn (find-or-create Lane, upsert/move/delete/bend über Clip-Span) + 16 Tests | 11e6c74 | CI ✓ beide Gates; code-reviewer (MEDIUM Snap-Kollision-Test + LOWs behoben) |
| **Item 2 Spine:** `ModulationEngine.lastOutputs` observable Snapshot (welche Params Bio bewegt + wie stark; Control-Plane hatte NUR Timestamp-Dot) + `orderedOutputs` + 6 Tests | e5ac34b | CI ✓ beide Gates; code-reviewer APPROVE (golden-gate); Leaf-View = device-gated (Task #71) |
