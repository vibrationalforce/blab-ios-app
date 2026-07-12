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

## Gesetze im Batch (unverändert)

Modal-Decke: nur Slot-Reuse · kein 10-Hz-Read in Ancestor-Bodies · ein MTKView ·
nie zwei Modals gleichzeitig · Audio-Thread-Regeln · Rausch-Triade READ-ONLY ·
EchoelValueField für Parameter · Uncodixfy · device-gated Features ehrlich
markieren (NEEDS-FOUNDER-VERIFY am Milestone, kein Blind-Claim).
