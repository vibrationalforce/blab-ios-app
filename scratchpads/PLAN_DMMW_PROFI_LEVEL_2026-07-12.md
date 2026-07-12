# PLAN — DMMW auf Profi-Level (TestFlight-Freeze-Batch)

**Founder 2026-07-12:** "Arbeite erstmal alles durch bevor du wieder einen
TestFlight rausschickst. Ich teste erst wieder, wenn die gesamte DMMW auf
Profi Level ist." → **FREEZE:** kein `.deploy/release`-Bump bis zum Milestone.
Branch-Commits + Gates laufen weiter (jeder Commit bleibt CI-grün). Letzter
ausgelieferter Build: v10.79.182 (war schon unterwegs).

## Definition "Profi-Level-Milestone" (Auslieferungs-Kriterium)

Ein Build, in dem die DMMW-Säulen als EIN kohärentes Instrument stehen:
Header = Puls · Marke · Video/Lux/BioSynth-Monitore; Spuren tragen ihre
Türen (Sound/Sample/Automation/Mix); untere Doppel-Strukturen sind weg;
Farben vollständig (Purpur-Naht ✓); Bio-Quellen wählbar (Kamera + Gurt);
Spatial-Kern rund (S4); keine bekannten UI-Fallen. Dann EIN Deploy + Founder-Test.

## Batch-Reihenfolge (jeder Punkt = 1 Commit-Zyklus, Gates grün)

- [x] B1 — Header-Monitore EchoelVideo + EchoelLux (Founder-Skizze) — DONE.
- [x] B1b — AUv3-Sichtbarkeit (Founder: "sehe nur die Apple AUv3"):
      Registrierungs-Observer + passingTest-Enumeration + Scan-Breadcrumb — DONE.
      Verify am Milestone: Breadcrumb "auv3 scan: … makers: …" im Founder-Log.
- [x] B1c — Kammerton-Farbgesetz über 392–466 Hz + Frequenz-Echtheit als Tests — DONE.
- [ ] B2 — E2b Mix→Spuren: laneMixStrip trägt Gain/Pan/Sends-Zugang pro Spur;
      ChannelRack bleibt als Master-Übersicht im Mix-Panel.
- [ ] B3 — E-Bio-Abschluss: untere BioStripView fällt (Header-Monitor ist der
      Ersatz, Founder-Anweisung "in vereinfachter Form da oben"); Tap-to-learn
      + Quellen-Dots wandern in ein kompaktes Bio-Popover hinter dem
      Header-Puls (kein neues Sheet — Slot-Reuse showInput? NEIN — Popover/
      Dropdown im bestehenden Menü-Host).
- [ ] B4 — #21 BLE-Herzgurt: PolarH10BioPublisher.start()-Hook (Quelle-Picker
      im Bio-Popover: Kamera/Gurt/Demo) + applyRouting-Tür. NEEDS-FOUNDER-
      VERIFY mit Gurt am Milestone.
- [ ] B5 — SampleBrowser als Drum-Spur-Tür (ArrangeModal .sample, laneDoor
      auf Drum-Lanes; Slot sampleBrowserTrack existiert).
- [ ] B6 — #19 BLE-MIDI-Kopplung: CABTMIDICentralViewController als Inhalt
      des bestehenden Input-/Routing-Panels (kein neues Sheet).
- [ ] B7 — Spatial S4: EchoelSpaceReverb (Audit-Schatz) prüfen → RoomModel→
      Reverb-Param-Mapping als pure Kopplung + Tests; audio-thread-reviewer
      PFLICHT, falls Render-Pfad berührt wird.
- [ ] B8 — V2 Offbeat-Anker: test-first Diagnose (Trap-Groove 132 vs bio ~53,
      PatternEngine Swing/Anchor), Fix im Sequencer-Kern.
- [ ] B9 — Visual-Polish-Paket: Wärme/Sättigungs-Kette prüfen (0.80-Mix +
      0.82-Saturation + Floor stapeln sich), Stil-QA je Style mit Purpur-
      Farben; ggf. ein "Vivid"-Preset für den VJ-Regler.
- [ ] B10 — Docs/Wahrheits-Sync: CLAUDE.md (Input/Routing re-doored, BLE-Status
      nach B4, Header-Monitore), FEATURE_MATRIX, SESSION_LOG.
- [ ] B11 — Abschluss: voller ui-state- + code-review-Pass über den gesamten
      Batch-Diff, DANN ein .deploy/release-Bump (Milestone-Build) + Founder-
      Report mit Testpunkten.

## "Ableton 20"-Spur (Founder 24h-Mandat 2026-07-12: "nicht nur einholen
## sondern abhängen") — läuft PARALLEL zur B-Reihe, gleiche Gesetze

Quellen: RESEARCH_ABLETON12_INVENTAR_2026-07-12.md +
RESEARCH_FRONTIER_ABLETON20_2026-07-12.md. Reihenfolge nach
Gewinn-pro-Aufwand; jedes Feature TDD (Modell zuerst, Surface danach).

- [x] A0 — AutomationLane-Krümmung (Ableton Alt+Drag als Modell) — DONE
      (e5a49a0, curvature −1…1, shapedFraction, 6 Tests, decodeIfPresent).
- [x] A1 — **Note-Operators-Modell** — DONE (2492488 Modell + 2513bb8 Wiring:
      Chance+Occurrence gaten im Trigger; Repeats warten auf Sub-Step-Clock W2):
      `NoteOperators` (chance 0…1 · repeats 1…n mit Velocity-Ramp ·
      occurrence n-ter-Loop) als optionales Feld auf `Note` —
      decodeIfPresent-Migration wie curvature; deterministische Auswertung
      (seed = loopIndex×noteID-Hash, KEIN Math.random im Audio-Pfad);
      PatternEngine/BeatPlayer werten beim Scheduling aus. TDD.
- [x] A2 — DONE als pure Kerne (a887fb9; Roll-Tür = späterer Zyklus) —
      **Strum + Humanize als Ein-Gesten-Transform** auf Roll-Selektion /
      BioComposer-Output: pure `NoteTransform`-Funktionen (strum: Zeitfächer +
      Velocity-Gefälle; humanize: begrenzte deterministische Jitter) + Tests;
      Tür = bestehender Roll-Kontext (kein neues Modal).
- [x] A3 — DONE (bc218c4: Canvas in AutomationView — Tap=Add auf 16tel-Raster,
      Point-Drag=Move, Segment-Drag=Krümmung [Hoch-Zug wölbt IMMER nach oben],
      Doppel-Tap=Delete via Event-Timestamps, EIN Drag-Gesture; Geometrie pur
      in AutomationCanvasMath, 8 Tests; Shape-Stempel = späterer Zyklus) —
      **Automations-Canvas-Editor** (#24 Hälfte 2): zeichenbare Lane im
      Piano-Roll-Host — Tap=Punkt, Drag=verschieben, Segment-Drag=Krümmung
      (setCurvature), Raster-Snap, Doppel-Tap=löschen; Touch-first, ein
      Canvas-View, kein neues Sheet. Danach: Shape-Stempel (Live hat KEINE).
- [x] A4 — DONE (87fd02e: bioBentChance — Kohärenz verschiebt die Würfel-
      Schwelle nur bei 0<chance<1; Roll bleibt geseedet) —
      **Bio-Operators** (Alleinstellung, macht niemand): Kohärenz→Chance-
      Skalierung, Puls→Ramp-Tempo — Kopplung NoteOperators×BioSnapshot als
      pure Funktion + Tests; Tür über bestehende Bio-Mod-UI.
- [ ] A5 — **Bio als per-Note-Expression** (unbesetzte Marktposition):
      rPPG-Waveform/Atemphase als Expression-Lane pro Note (MPE-out später).
      Erst Modell + OSC/MIDI-Mapping-Design, dann Surface.

## Rundum-Sweep 2026-07-12 (Founder: "alles abklappern aber gründlich")

4 Reports: RESEARCH_DESKTOP_DAWS · RESEARCH_VIDEO_FRONTIER ·
RESEARCH_VJ_MAPPING_VISUAL · RESEARCH_LICHT_LASER_IOS (alle 2026-07-12).
Abgeleitete Spuren (nach Gewinn-pro-Aufwand, laufen NACH/NEBEN A-Spur):

- **P-Spur (Performance, REAPER/FL-Lektionen):** P1 Smart-Disable/Idle-Voices
  (stille Voices + abgeklungener Tail raus aus dem Render → AdaptiveQuality);
  P2 Konzept-Spike Anticipative Rendering fürs Generative (deterministischer
  Loop-Anteil vorausrendern, nur Bio-Voices live; Tier steuert Tiefe).
- **L-Spur (EchoelLux → kleines Lichtpult):** L1 Grand Master + Blackout;
  L2 Gruppen; L3 **Bio-Phaser** (Herz-/Atemphase als Phase-Offset über
  Fixture-Gruppe — MA3-Phaser-Denke, Alleinstellung); L4 GDTF-Subset-Parser
  (Fixture-Library, zero-deps); L5 sACN-Multicast/Priority + Multi-Universe.
  Laser/IDN = WATCH (Safety-Kette, nie Exposure-Verantwortung).
- **VIS-Spur (Visual → Profi):** VIS1 Kompositions-Passes (Basis + Bio-Layer
  + Grade); VIS2 Zustands-Übergänge (Kohärenz-Tier wechselt via Crossfade/
  Morph, Rive-State-Denke); VIS3 4-Punkt-Corner-Pin für Beamer-Out (eine
  Homographie im Metal-Pass — "iPhone als miniMAD mit Gehirn"); VIS4
  ISF-Subset-Pfad prüfen (offline→MSL "Echoel-Shader-Pack").
- **VID-Spur (P3 Video, FCP-iPad-Muster):** Minimal-Set = Capture (HEVC/
  ProRes) · Trim (1 Clip + Overlay) · Proxy-first-Preview · Rec.709+LUT ·
  AutoMix-Mux · Social-Export. Alleinstellung: bio-reaktive Video-FX,
  **puls-synchroner Schnitt (BioEventGraph-Marker)**, Visual-als-Quelle
  (MetalBioView → AVAssetWriter). Kein Multicam/Node-Grading/KI-Roto.
- **Bestätigungen:** Determinismus als Feature vermarkten (Pro-Tools-Hybrid-
  Lektion) · RetroCapture prominent (Bitwig Master Recording/Logic Flashback
  = Standard 2025) · Tonart/Genre als Single-Source-Chord-Track formalisieren
  (Logic 12 + Bitwig 6) · Loopy-2-Pricing (Free+Trial+One-time) · Endlesss tot
  → lokale, standard-offene Architektur ist die richtige Wette · Bio-Position
  im GESAMTEN Feld unbesetzt (VJ/Licht/Generativ-Apps: bestätigt).

## Gesetze im Batch (unverändert)

Modal-Decke: nur Slot-Reuse · kein 10-Hz-Read in Ancestor-Bodies · ein MTKView ·
nie zwei Modals gleichzeitig · Audio-Thread-Regeln · Rausch-Triade READ-ONLY ·
EchoelValueField für Parameter · Uncodixfy · device-gated Features ehrlich
markieren (NEEDS-FOUNDER-VERIFY am Milestone, kein Blind-Claim).
