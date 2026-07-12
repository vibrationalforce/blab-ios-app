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
- [x] B2 — DONE (c21e423: Pan pro Spur — TimelineLane.pan −1…1 persistiert
      [decodeIfPresent-Migration], rollSlotPan-Spiegel von rollSlotGain,
      TimelineStore.setLanePan, PolySynthVoice.setPan über sourceNode.pan
      [AVAudioMixing → masterMixer = EHRLICHER Engine-Pfad, kein Render-Code],
      Arrange bindet rollSlotPan → synth + leadSynth [initial:true], Pan-Feld
      im Sound&FX-Sheet der Spur [Strip 140pt bleibt M/S/Level]; Sub-Bass
      bewusst center [Mono-Bass]. **Sends bewust NICHT gebaut** — keine
      Aux-Bus-Architektur vorhanden, Placebo-Regel; kommt mit echtem Aux-Bus.
      ChannelRack bleibt Master-Übersicht im Mix-Panel.)
- [x] B3 — DONE (8ec7f11: Strip raus aus dem Dauer-Flow; "Bio"-Chip als
      ERSTER Menü-Punkt + Long-Press auf Header-Puls öffnen das Bio-Dropdown
      [Zahlen/Tap-to-learn/Quelle unverändert als Leaf]; Receiver auf die
      Menü-Zeile umgezogen, Modal-Kette unberührt; Routing-Link für Gurt).
      UI-STATE-REVIEW im B11-Pass. — E-Bio-Abschluss.
- [x] B4 — KERN DONE (6ba61e5: "Herzgurt (BLE)"-Source-Port im Patchbay +
      applyRouting-Start/Stop-Hook; Permission-Prompt = Verdrahtungs-Tap;
      Quelle-Picker Kamera/Gurt/Demo folgt mit B3) — #21 BLE-Herzgurt.
      NEEDS-FOUNDER-VERIFY mit Gurt am Milestone.
- [x] B5 — DONE (121099a, Übersetzung an die Realität: es GIBT keine Drum-Lanes
      auf der Timeline [ClipKind = midi/audio/video/visual] — Drums leben im
      Hackbrett. Tür dort: waveform-Button pro Channel-Strip →
      onSampleBrowse-Hook → activeMenu=nil + bestehender sampleBrowserTrack-
      Slot [Slot-Reuse, Kette wächst nicht; Muster = learn/live-Chrome-Doors]).
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
- [x] B10 — DONE (CLAUDE.md CURRENT STATE: BLE = GEBAUT+VERDRAHTET nach B4
      [war "NIE GESTARTET"], tote-Türen-Zeile teil-behoben [Patchbay/Sample/
      Automation/Patch re-doored, Meditation bewusst türlos], 2026-07-12-Batch-
      Zeile [A3/A4/L1/P1/B2/B3/B4/B5/W1/EchoelAI N0-N4/Body-Science], Heilungs-
      Thema als REJECT-Red-Line notiert). FEATURE_MATRIX/SESSION_LOG-Feinsync
      im nächsten Doku-Tick.
- [~] B11 — LÄUFT: ultracode-Workflow wf_792707e5-72e = adversarieller
      review+verify über 87fd02e..HEAD (33 Dateien) + 5 Design-Briefs. Nach
      Rückkehr: confirmedDefects fixen → DANN .deploy/release-Bump (Milestone)
      + Founder-Report. Kein Bump vor grünem Review + Founder-Freeze-Ende.

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

## W-Spur (Word/Lyrics — Founder-Entscheid 2026-07-12C: "Lyrics bzw
## songwriting wie bei ACE Studio soll es geben ja") — NACH dem Milestone

Eigener Weg, nicht ACE-Kopie (deren Schmerzen = unsere Gegenposition:
on-device deterministisch statt Server-Render, Einmal-Unlock statt Credits):
- [x] W1 — DONE (c24654a: LyricsModel — Syllabifier als deterministische
      GESANGS-Heuristik [offene Silben, de/en-Cluster sch/ch/ck/st, silent-e,
      Konsonant+le-Nukleus, Diphthonge], LyricsDocument/LyricLine/LyricSyllable
      pure Codable [Worttrennstrich-Konvention "Lie-"], LyricsMapper.bind
      [Tick-Ordnung + Pitch-Tiebreak, Melisma hält Silbe über n Noten,
      Überschuss-Noten = Vokalise nil]; 21 Tests, Foundation-only, Linux-CI.
      Split ist DEFAULT — W2-UI erlaubt Hand-Re-Split.)
- [ ] W2 — Lyrics-Lane im Roll (Anzeige unter den Noten, Slot-Reuse).
- [ ] W3 — VL-Kopplung: eigene Stimme singt die Lyrics (AutotuneCore VL1 +
      Skalen-Harmonizer VL2 → Mic-Pfad VL3, device-gated).
- [ ] W4 — Formant-Synthese-Stimme in-house (VocoderCore/DDSP-Richtung) für
      Songwriting ohne eigenes Singen. AUv3-Slot "Stimme mit MIDI-Song-
      writing" ist marktweit unbesetzt (Research 2026-07-12).

## Hardware-Vorbereitung (Gurt + Watch bestellt — "bereite alles vor")

- Gurt-Tür steht (B4/6ba61e5); beim Eintreffen: Patchbay → "Herzgurt (BLE)"
  verdrahten → Permission → Puls im Header (NEEDS-FOUNDER-VERIFY-Testpunkt).
- Watch: HealthKit-Pfad läuft bereits (HealthKitBioPublisher); Watch-App-
  Target existiert als Bundle-ID, KEINE neue Arbeit vor Hardware (4-5 s
  HR-Latenz-Gesetz beachten: nie beat-sync, nur langsame Modulation).

## Rundum-Sweep 2026-07-12 (Founder: "alles abklappern aber gründlich")

4 Reports: RESEARCH_DESKTOP_DAWS · RESEARCH_VIDEO_FRONTIER ·
RESEARCH_VJ_MAPPING_VISUAL · RESEARCH_LICHT_LASER_IOS (alle 2026-07-12).
Abgeleitete Spuren (nach Gewinn-pro-Aufwand, laufen NACH/NEBEN A-Spur):

- **P-Spur (Performance, REAPER/FL-Lektionen):** P1 Smart-Disable/Idle-Voices
  (stille Voices + abgeklungener Tail raus aus dem Render → AdaptiveQuality);
  P2 Konzept-Spike Anticipative Rendering fürs Generative (deterministischer
  Loop-Anteil vorausrendern, nur Bio-Voices live; Tier steuert Tiefe).
- **L-Spur (EchoelLux → kleines Lichtpult):** L1 Grand Master + Blackout —
  DONE (669dad9: masteredDimmer-Gesetz geteilt Art-Net+sACN, Blackout gewinnt
  sofort, Rückkehr über Slew, Master-Änderung sendet auch bei stalem Bio;
  Patchbay-„Licht"-Sektion mit EIN Master-Fader + Blackout-Button);
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
