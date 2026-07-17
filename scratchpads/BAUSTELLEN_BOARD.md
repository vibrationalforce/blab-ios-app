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
| A1 | **Piano Roll adaptiv + Pro-Funktionen** | „passt immer noch nicht…adaptiv" + „mehr Funktion… siehe Ableton… Echoel twist" (07-17) | Adaptiv in v286 ✓, R1 Ops/Scale-Lock/Bio-Humanize in v287 ✓ (b9e0973, Gates 4/4). Nächste: R2 ChordSuggest-Stempel, Fold via RollRowMap | Founder editiert Clip mit Ops; Bio-Humanize hörbar — **Gerät offen** | PLAN_ROLL_PRO.md |
| A2 | **Harmony-Serie H1+H2+H3** | Scaler-Analyse-Ask (07-17) | KOMPLETT + AN (H2-Flip 411e972 grün, in v287) | Hörtest: erzählt die Harmonie eine Geschichte? | Rollback je 1 Wort |
| A3 | **Hörtests v285–v287** (VoiceLeading·Humanize·Journey·Roll·Bio-Spur) | Modus-Lehre 07-17 | v287 DEPLOYT — wartet auf Ohr | Founder-Urteile | — |
| A4 | **BodyVibe B1 — EchoelBodyVibe-Instrument** | Screenshot „Bio Instrument → EchoelBodyVibe" (07-17) | ENGINE ✓ in v287 (45dc157: .bioVoice-Allokation + eigene Rack-Instanz, Sequencer-Gate, SPSC-Kontrakt geschützt). Nächste: B1-UI (Create-from-Within-Panel) + Umbenennung NACH Geräte-Klang-Verify | Bio-Spur klingt + reagiert auf Puls auf Gerät | Kein lügendes Label |
| A5 | **BodyVibe B2 — Kamera-Modulator Stufe 1** | „Grimassen/Smile/Arme als Modulator" (07-17) | Vision-Face-Publisher (CameraRPPG-Muster, smile/jawOpen/browRaise, 10 Hz EMA) | Lächeln verändert hörbar die Komposition | RESEARCH_BODYVIBE_CAMERA; Copy: „Expression", NIE „Emotion" |
| A6 | **Chips auflösen C** (Sound·Mix·FX·Mood·Synth·Video weg) | 2 Screenshots (07-17) | Erst wenn A4 die Spur-Panels trägt; Video-Voraussetzung (Photos-Save) GEBAUT | Untere Leiste leer/weg auf Gerät, nichts unerreichbar | PLAN_BODYVIBE §C |

## OFFEN (nach AKTIV nachrücken)

| # | Baustelle | Founder-Quelle | Nächste Slice | Verify-Weg |
|---|-----------|----------------|---------------|------------|
| O1 | Clip-Handhabung rudimentär + Zittern (Task #56) | 07-16, „weiter offen auf 2373" | Slice-Review offene MEDIUMs; Founder-Repro-Clip anfordern | Clip ziehen/trimmen ruckelfrei auf Gerät |
| O2 | Warp im Audio-Clip-Editor (#54) | 07-16 „neuste Technologie" | Plan liegt; nächste Slice nach C | Audio-Clip folgt Tempo hörbar |
| O3 | MIDI/MPE-Station ausbauen (#58) | 07-16 „sehr rudimentär" | A1 ist die laufende Slice; danach: Velocity-Lane-Edit, Scale-Lock (Scaler #5) | Founder editiert Clip vollständig im Roll |
| O4 | Scaler #4 — Atem-Pattern-Generatoren | Scaler-Analyse | Nach H2: BreathArp/BreathStrum pure Core | Arp folgt hörbar dem Atem |
| O5 | Per-Instrument EchoelSynth (#23) | ältere Serie | SynthPatch pro MIDI-Spur zu Ende verdrahten | Patch-Wechsel pro Spur hörbar |
| O6 | Audio-Loop-Import + Record-Capture Gerät (#13) | ältere Serie | Geräte-Verify des bestehenden Pfads | Loop landet in Lane, Record schreibt Clip |
| O7 | Immersive-Stage-Automation (#20) | ältere Serie | AutomationGestureRecorder anbinden | Puck-Fahrt wird aufgezeichnet + spielt zurück |
| O8 | rPPG-Sättigung Auto-Recovery (#25) | Log-Serie | device-iterate (nicht blind tunen) | Log zeigt Recovery ohne Neustart |
| O9 | EchoelPublish (#51) · Website-SEO (#52) | 07-15 | Marketing-Pipeline, nach Produkt-Baustellen | Founder-Review |
| O10 | EchoelWeather-Synth (#59) · EEG-Quelle (#61) · Bio-Session-Brain (#60) | 07-16 | Ideen-Parkplatz — erst nach A-Serie | — |
| O11 | Sampler-Name statt UUID (UX-Niggle) | 07-17 Beobachtung | Kleine Slice bei Gelegenheit | Spur zeigt Sample-Namen |
| O12 | Mood-Feintuning | 07-17 Beobachtung | Nach Hörtest-Feedback | Founder-Ohr |

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
