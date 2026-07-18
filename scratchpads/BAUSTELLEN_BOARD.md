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

## AKTIV (in dieser Reihenfolge ziehen)

| # | Baustelle | Founder-Quelle | Nächste Slice | Verify-Weg | Route |
|---|-----------|----------------|---------------|------------|-------|
| A1 | **Piano Roll adaptiv + Pro-Funktionen** | „passt immer noch nicht…adaptiv" + „mehr Funktion… siehe Ableton… Echoel twist" (07-17) | Adaptiv v286 ✓, R1 v287 ✓, **R2 Akkord-Stempel KOMPLETT + DEPLOYT v290 ✓** (b22a6c2): Kern `RollChordStamp` (e126994, code-reviewer PASS) + UI Chord-Modus-Toggle (5f51b23, ui-state-reviewer PASS 0 Defekte) — Tap stempelt kohärenz-gewählten, voice-geführten Akkord, alle Gates grün. Nächste: **R3 Breath-Arp-Stempel KOMPLETT** (86e9f7a, ui-state-reviewer 0 Defekte): zweiter Roll-Modus (wind-Symbol, exklusiv zum Chord) — Tap arpeggiert den kohärenz-Akkord mit dem LIVE-Atem (RollChordStamp+BreathArp). **R4 per-Note-Chance KOMPLETT + DEPLOY v292 ✓** (50eb030): untere Paint-Lane bekam Vel⇄Cha-Toggle (Label tippen) — im Cha-Modus setzt/zeigt jeder Balken die Note-Abspiel-Wahrscheinlichkeit 0…1; `setChance` spiegelt `setMPE` (Clamp, andere Operatoren bleiben, Default→nil), Body bendet Schwelle live (A4). ui-state-reviewer 0 Defekte, alle 4 Gates grün. **R5 per-Note-OCCURRENCE KOMPLETT + DEPLOY v294 ✓** (bd33b1b + @MainActor-Fix fb8f6e9, code-reviewer fing 1 build-red): Paint-Lane-Toggle jetzt 3-fach Vel→Cha→Occ — im Occ-Modus malt jeder Balken die Occurrence-PERIODE als 1:N-Ratio (voller Balken = jede Schleife 1:1, halb = 1:2 …); bei Playback via `operatorAllows→hits` gegated (hörbar). Repeats bewusst NICHT (braucht W2-Sub-Step-Clock → wäre stummer No-Op, kein lügender Halb-Pfad). `setOccurrence` spiegelt `setChance`, Map ist echte Inverse. ui-state-reviewer 0 Defekte. Nächste: Repeats erst nach W2-Clock | **HÖRTEST v290 offen:** klingen die Akkorde musikalisch + zur Tonart? Verändert Kohärenz die Farbe spürbar? **R5 Occ:** Note auf 1:2 malen, Loop → spielt sie nur jede 2. Runde? | PLAN_ROLL_PRO.md |
| A2 | **Harmony-Serie H1+H2+H3** | Scaler-Analyse-Ask (07-17) | KOMPLETT + AN (H2-Flip 411e972 grün, in v287) | Hörtest: erzählt die Harmonie eine Geschichte? | Rollback je 1 Wort |
| A3 | **Hörtests v285–v287** (VoiceLeading·Humanize·Journey·Roll·Bio-Spur) | Modus-Lehre 07-17 | v287 DEPLOYT — wartet auf Ohr | Founder-Urteile | — |
| A4 | **BodyVibe B1 — EchoelBodyVibe-Instrument** | Screenshot „Bio Instrument → EchoelBodyVibe" (07-17) | ENGINE ✓ in v287 (45dc157: .bioVoice-Allokation + eigene Rack-Instanz, Sequencer-Gate, SPSC-Kontrakt geschützt). Nächste: B1-UI (Create-from-Within-Panel) + Umbenennung NACH Geräte-Klang-Verify | Bio-Spur klingt + reagiert auf Puls auf Gerät | Kein lügendes Label |
| A5 | **BodyVibe B2 — Kamera-Modulator Stufe 1** | „Grimassen/Smile/Arme als Modulator" (07-17) | FUNDAMENT ✓ (d624fcc grün) + Mapping-Kontrakt ✓ (62ef41f grün) + CAPTURE-SEITE ✓ (901ebf5, Gates laufen): `BioSource.faceCam` + `FaceExpressionBioPublisher` (ARKit, rPPG-Sicherheitsmuster, `FeatureFlags.cameraExpression` OFF → unverdrahtet/byte-identisch). Concurrency-Review PASS, Bio-Safety PASS(1/2/3/5). **HARTER BLOCKER für die Verdrahtungs-Slice (Bio-Safety HIGH):** die eine `NSCameraUsageDescription` beschreibt nur Heck-Fingerpuls — MUSS vor Flag-ON auf Front-Gesichts-Tracking erweitert werden (5.1.1/GDPR), Info.plist braucht Founder-Freigabe. Nächste (Verdrahtungs-Slice): `BioSourceKind.face` + Dropdown (capability-gated) + Default-Route faceSmile→Param + Info.plist-String + Puls-Koexistenz-Entscheid | Lächeln verändert hörbar die Komposition — **Gerät offen (folgt mit Verdrahtungs-Slice)** | RESEARCH_BODYVIBE_CAMERA; Copy: „Expression/Steuerung", NIE „Emotion" |
| A6 | **Chips auflösen C** (Sound·Mix·FX·Mood·Synth·Video weg) | 2 Screenshots (07-17) | Erst wenn A4 die Spur-Panels trägt; Video-Voraussetzung (Photos-Save) GEBAUT | Untere Leiste leer/weg auf Gerät, nichts unerreichbar | PLAN_BODYVIBE §C |
| A7 | **Automation in der Timeline + Clip-Launch/Performance** | „Automation … in der Timeline direkt" + „Play Button auf den Clips und Performance Mode" (07-17) | T1 ✓ (f60a0e9 grün, in v288). P0-Core ✓ (750c293, Golden-Gate adversarial verifiziert) + P1-UI ✓ (7fcf9cb, Play-Glyph+Performance-Toggle) — Gates laufen. **PLAN audio-lane-launch Council-signiert ✓** (3ef1b45, `PLAN_AUDIO_CLIP_LAUNCH.md`): Loop-Restart-Mathe existiert schon (`LaunchTiming.loopWrapped`), nur AudioLanePlayer-Verdrahtung fehlt (Engine mit Stille-Historie #22 → PLAN-first). **S1 ✓** (41fac9c + Test-Härtung 595653c, Gates laufen): AudioLanePlayer Override-Türen + 9 SpySink-Tests, unsichtbar/kein Caller. audio-thread-reviewer CLEAN (golden gate verifiziert), code-reviewer clean (kein Crash/Stille-Bug). **S2 ✓** (bf38ff8 + LOW-Fix 31023c0, Gates laufen): TimelineRegionPlayer Audio-Dispatch — launchRegion erlaubt .audio, applyLaunchTransitions routet an setLaunchOverride/clearLaunchOverride (Anker t.atTick), alle 4 Reset-Pfade paaren clearAllLaunchOverrides. audio-thread-reviewer CLEAN, code-reviewer clean. INERT bis S3. **S3a ✓** (c0a05c2 + Wrap-Re-Trigger-Fix 91deeff): Override-Lifecycle — prime überspringt Overrides, shiftLaunchOverrides (Wrap-Anker-Fold), pruneLaunchOverrides (Struktur-Edit), applyWrappedOverrides (bar-alignter Loop wird AM Song-Wrap neu getriggert → kein stiller Takt, Audio im Lockstep mit MIDI), 6 Tests inkl. echtem transportStep-Wrap-Pfad. audio-thread-reviewer x2 CLEAN. **S3b ✓** (2d2e151): launchGlyphOverlay isMidi→isLaunchable(midi‖audio) → Play-Knopf auf Audio-Clips, Video/Bio ausgeschlossen. ui-state-reviewer 0 Defekte, alle 4 Gates grün. **A7 KOMPLETT → DEPLOY v10.79.291.** | Founder: Performance-Mode → Audio-Clip-Play tappen, Clip loopt hörbar (Hör-/Fühl-Bitte in Deploy-Note v291) | Freeze-Gesetz ✓, keine 2. Sheet ✓, Golden Gate ✓ |
| A8 | **AUv3-Register-Reparatur** | Log build 2394: self-probe -3000, raw 101 comps alle Apple | ANSAGE an Founder gegeben | App löschen + TestFlight-Neuinstallation → nächster Log zeigt ownAUv3 true | Geräte-Register korrupt, kein App-Bug |
| A9 | **App-Group-Puls-Brücke** (AUv3 in fremden Hosts) | Founder-Q „AUv3?" | GEBAUT ✓ (6a568d8, Freshness+5.1.3+10Hz) in v288 | EchoelBodyVibe in GarageBand vom echten Puls gespielt | — |

## OFFEN (nach AKTIV nachrücken)

| # | Baustelle | Founder-Quelle | Nächste Slice | Verify-Weg |
|---|-----------|----------------|---------------|------------|
| O1 | Clip-Handhabung rudimentär + Zittern (Task #56) | 07-16, „weiter offen auf 2373" | Slice-Review offene MEDIUMs; Founder-Repro-Clip anfordern | Clip ziehen/trimmen ruckelfrei auf Gerät |
| O2 | Warp im Audio-Clip-Editor (#54) | 07-16 „neuste Technologie" | Plan liegt; nächste Slice nach C | Audio-Clip folgt Tempo hörbar |
| O3 | MIDI/MPE-Station ausbauen (#58) | 07-16 „sehr rudimentär" | A1 ist die laufende Slice; danach: Velocity-Lane-Edit, Scale-Lock (Scaler #5) | Founder editiert Clip vollständig im Roll |
| O4 | Scaler #4 — Atem-Pattern-Generatoren | Scaler-Analyse | KERN ✓ (6c2a6b9 Slice-1 + a6e4818 Slice-2 grün: Atemphase→Richtung, Tiefe→Dichte, Akkord-Walk, Puls→Swing, Motion→Strum). **VERDRAHTET ✓** (86e9f7a, ui-state-reviewer 0 Defekte, Gates laufen): Roll-Toolbar-Modus „Breath Arp" (wind-Symbol, exklusiv zum Chord-Stamp) — Tap arpeggiert den kohärenz-gewählten Akkord mit dem LIVE-Atem. Nächste: nur noch Gerät | Arp folgt hörbar dem Atem — **HÖRTEST offen** (Roll: wind-Knopf an, leere Zelle tippen) |
| O5 | Per-Instrument EchoelSynth (#23) | ältere Serie | **PLAN+Council ✓**. **S1 ✓ (b2f7750):** `setLanePatch`+4 Tests, Gates grün. **S2 ✓ (3280aa9+aef9b67):** `.patch(lane)`-Editor-Tür, Gates grün, code+ui-state-reviewer CLEAN. **S2b ✓ SHIPPED (05e8d37):** `rollPatchSink` — Primär-Roll-Lane wendet ihren `lane.patch` bei Region-Load auf die globale Stimme an (nil-Guard: kein Clobber des Live-Sounds); audio-thread-reviewer CLEAN, 2 Tests. **JETZT vollständig hörbar** (Sekundär via slotPatchSink, Primär via rollPatchSink). → **Deploy-Kandidat für Founder-Hörtest** (nach Gates grün + code-reviewer). Offen: S3 Live-Drag-Preview auf Sekundär-Lane [gerät-gated, optional]. | **2 Spuren, 2 Klangfarben, beide hörbar** — Gerät-Hörtest = Closeout |
| O6 | Audio-Loop-Import + Record-Capture Gerät (#13) | ältere Serie | Geräte-Verify des bestehenden Pfads | Loop landet in Lane, Record schreibt Clip |
| O7 | Immersive-Stage-Automation (#20) | ältere Serie | AutomationGestureRecorder anbinden | Puck-Fahrt wird aufgezeichnet + spielt zurück |
| O8 | rPPG-Sättigung Auto-Recovery (#25) | Log-Serie | device-iterate (nicht blind tunen) | Log zeigt Recovery ohne Neustart |
| O9 | EchoelPublish (#51) · Website-SEO (#52) | 07-15 | Marketing-Pipeline, nach Produkt-Baustellen | Founder-Review |
| O10 | EchoelWeather-Synth (#59) · EEG-Quelle (#61) · Bio-Session-Brain (#60) | 07-16 | Ideen-Parkplatz — erst nach A-Serie | — |
| O11 | Sampler-Name statt UUID (UX-Niggle) | 07-17 Beobachtung | **GEFIXT (MediaLibrary.uniqueName)**: Import speichert lesbaren Quell-Namen statt `<UUID>.ext`; `sampleRefDisplayName` zeigt jetzt "MyLoop" statt UUID. code-reviewer clean (1 LOW: stale H6-Kommentar korrigiert). 5 Tests. Reitet nächsten Deploy | Spur zeigt Sample-Namen (Gerät-Verify) |
| O12 | Mood-Feintuning | 07-17 Beobachtung | Nach Hörtest-Feedback | Founder-Ohr |

## ARCHITEKTUR-AUDIT-BACKLOG (2026-07-18, ultracode 54 Agenten — `scratchpads/ARCHITECTURE_AUDIT_2026-07-18.md`)

> 32 bestätigte Befunde. Kernbotschaft: **zwei Wurzeln entriegeln fast alles** —
> (A) tote/eingefrorene Bio-Freshness-Disziplin, (B) falsch dokumentierte DSP-Thread-Invariante.
> Die 5 billigsten Hebel, nach Report-Rang (jeder klein & reversibel):

| # | Fix | Datei | Entriegelt | Status |
|---|-----|-------|-----------|--------|
| AU1 | **Arrangement additive Codable** (kein stiller Song-Verlust) | Sequencer/Arrangement.swift | #39/#40/#11 | ✅ 66f94dc GRÜN (beide Gates) |
| AU2 | ModulationEngine Freshness-Gate (Bio löst zu neutral) — **NICHT der 1-Zeiler den der Report behauptet; braucht Design** (Tempo 0→30BPM-Skalierung) | Core/ModulationEngine.swift:144 | #60, halb #61 | offen — eigener Design-Zyklus |
| AU3 | DDSP-Header-Invariante korrigieren (Doc-Fix) | DSP/EchoelDDSP.swift:44 | #59, schützt jeden DSP-Edit | ✅ 277a543 (+Präzisierung), concurrency-reviewer verifiziert. Deckte NEUEN Ticket-Befund auf → AU6 |
| AU6 | **Bio-Pfad Cross-Thread-COW-Hazard:** `applyBioReactive→updateSpectralEnvelope` schreibt `harmonicAmplitudes`-Array um (nicht-atomar) auf PolySynthVoice/AUv3-Direktpfad | DSP/EchoelDDSP.swift:1287 + PolySynthVoice/AUv3 | #23-Klasse Audio-Stabilität | offen — audio-review+device Pflicht, eigener Zyklus (Bio via SPSC ODER Array-Write render-seitig) |
| AU4 | MicrophoneManager `guard !isRecording` + Session-Teardown (#22-Klasse) | MicrophoneManager.swift:194/269 | #13 | ✅ 0077a59 grün, audio-thread-reviewer APPROVED (re-entry-guard + downgradeToPlaybackAfterRecording statt setActive(false)). PRÄVENTIV (Pfad dormant), reitet nächsten Feature-Deploy — kein eigener Hörtest. Follow-ups geloggt: recordingRouteNeeded→Refcount vor Mic-Entkopplung; wahrscheinlicherer Live-Pfad = AudioEngine.stop():632 (unberührt, #22 gilt gefixt) |
| AU5 | AudioEngine Meter-Props `@ObservationIgnored` (60-Hz-Freeze-Landmine) | Audio/AudioEngine.swift:59-67 | #11 | offen — mechanisch, launchGeneration-Muster |

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
> PLAUSIBLE/Gerät-Verify: SPSCQueue OSAtomic-Race (:153) — höchstes latentes Risiko, kein Ralph-Quick-Win.
> #66 (tote Türen) = eigener Closeout-Loop.

## BLOCKIERT (wartet auf Founder)

| # | Baustelle | Wartet auf |
|---|-----------|-----------|
| B1 | **a) Externe AUv3 fehlen in der Liste** | `echoel_diag.log` nach iPhone-Neustart (self-probe-Zeile + scan-Zeilen). Workaround kommuniziert: GarageBand einmal öffnen registriert AUv3 neu. |
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
