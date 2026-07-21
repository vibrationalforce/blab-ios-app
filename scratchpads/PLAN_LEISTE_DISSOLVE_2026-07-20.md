# PLAN — untere Leiste auflösen + adaptive Spurköpfe + Genre→BodyVibe (Founder 2026-07-20)

Founder-Screenshot (v10.79.309/2417), drei rote Markierungen + Text:
1. **Untere Leiste komplett auflösen** (`studioChips` = Sound·Mix·FX·Mood·Synth·Video).
   „Video kann gelöscht werden" (großes X).
2. **Spurköpfe → adaptives Design**, das auf jede Bildschirmgröße passt.
3. **Genre-Auswahl → auch in EchoelBodyVibe.**

## Befund (Code)
- Die Leiste ist `EchoelStudioView.studioChips` = `StudioMenu.allCases` minus
  {master, export, bio, composition, session}. Jeder Chip öffnet ein `.menu`-Dropdown
  (`menuContent` switch) das einen bestehenden Panel-Builder wiederverwendet — KEINE Sheets.
- **Orphan-Gefahr (CLAUDE.md-Gesetz):** einen Chip entfernen, dessen Funktion NICHT
  woanders erreichbar ist, macht die Funktion unerreichbar (wie das tote toolsSection).
  Also je Chip ZUERST Ersatz-Erreichbarkeit prüfen, DANN Chip entfernen.
- **EchoelBodyVibe hat KEINE Oberfläche** — bisher nur Voice-Kind/Kamera-Modulator (A5,
  FeatureFlags #67/#68 in_progress). „Genre → BodyVibe" ist erst umsetzbar, wenn eine
  BodyVibe-Oberfläche existiert. → Ask 3 braucht Founder-Klärung ODER wartet auf #67/#68.

## Chip-für-Chip Verlagerungsziele (Reihenfolge = sicherste zuerst)
| Chip | Funktion | Ersatz erreichbar? | Slice |
|------|----------|--------------------|-------|
| **Video** | Aufnahme-Bibliothek | Founder: LÖSCHEN (X). Visual-Fenster bleibt via Header-Monitor. | **S1 (jetzt)** |
| **Mix** | Level pro Spur | Spurkopf hat bereits Gain (1.00) + M/S je Lane → redundant | S2 (verify + remove) |
| **FX** | Effekte | per-Spur-FX prüfen (PatchbayView/EchoelFX, #37 automation) | S3 |
| **Synth** | immersives Visual-Fenster | Header-Monitor-Icon öffnet es schon | S4 (verify + remove) |
| **Sound** | Klang & Textur | Ziel klären (per-Spur-Patch? BodyVibe?) | S5 |
| **Mood** | Charakter/Bio | → EchoelBodyVibe (braucht Oberfläche) | S6 (mit Ask 3) |

## Ask 2 — adaptive Spurköpfe (parallel, eigener Slice-Strang)
- `laneHeader`/`laneMixStrip`/`laneRow` in `ArrangeTimelineView`. Prüfen: feste Breiten,
  die auf schmalen Geräten clippen (Screenshot zeigt „MIDI 1" leicht links angeschnitten).
- Ziel: Kopf-Zeile (Icon+Name+Chevron) + Mix-Zeile (M/S/Gain/Route) fließend, min/max-Breiten,
  kein Clipping auf kleinstem iPhone. Eigener Slice T1 nach der Leisten-Serie ODER verschränkt.

## Council (kompakt)
- Architect: Chips sind dünne Trigger auf bestehende Panels — Entfernen koppelt nichts neu; nur
  Erreichbarkeit je Funktion sichern. Video = Founder-gelöscht → 0 Kopplung.
- Skeptik: Orphaning ist DER Fehler. Nie einen Chip vor verifiziertem Ersatz entfernen.
- Shipper: kleinste sichere Slice zuerst = Video-Chip raus (1-Zeilen-Filter, reversibel).
- User-Advocate: Founder hat Video explizit ge-X-t → sofort sichtbarer Fortschritt, 0 Risiko.
- Vision-Keeper: „auflösen → alles über die Spuren" ist on-vision (Tracks-zentrisch).
→ **Gate: proceed** mit S1 (Video-Chip entfernen). S2–S6 je eigener Zyklus mit Ersatz-Verify.
   Ask 3 (Genre→BodyVibe) HOLD bis BodyVibe-Oberfläche existiert (#67/#68) — dann Founder-Ask.

## Slices
- **S1 (SHIPPED, `eaa684a`):** `.video` aus `studioChips`-Filter → Video-Chip raus. War sicher
  weil Founder explizit ge-X-t hat und der Ersatz (Header-Monitor) schon lief.
- **S2 VERIFY-ERGEBNIS (2026-07-21) — Annahme widerlegt, NICHT entfernen:** direkt im Code
  gelesen (`EchoelStudioView.mixerPanel`, ~1429-1501) — der Mix-Chip ist NICHT redundant zum
  Lane-Head-Gain. Er ist der EINZIGE Zugang zu: Bass/Melodic/Drums Bus-Filter+Drive-Strips UND
  dem kompletten eingebetteten `ChannelRackView` (pro-Drum-Channel Level/Mute/Solo/Insert-FX/
  Sample-Tür — `ChannelRackView(` kommt EXAKT einmal im ganzen Sources-Baum vor, genau hier).
  Das "Hackbrett" ist seit dem Plan (07-20) hier konsolidiert worden — die Prämisse ist
  überholt. Entfernen würde die B5-Sample-Tür + die einzige Drum-Kanalzug-Oberfläche verwaisen
  (CLAUDE.md-Gesetz-Verstoß). **S2 gestoppt.**
- **S4 VERIFY-ERGEBNIS (2026-07-21) — Annahme ebenfalls widerlegt, NICHT entfernen:** `visualPanel`
  (~2191-2224, der "Synth"-Chip) ist mehr als der Header-Monitor-Toggle — er trägt zusätzlich
  Look-Presets/-Customizer, `MusicColourRowView`, Visual-Adjust-Felder UND `touchSoundSection`
  (welcher Patch die Vollbild-Touch-Fläche spielt + Positions-Morph). Der Header-Monitor-Button
  toggelt nur Sichtbarkeit — er ersetzt keine dieser Einstellungen. **S4 gestoppt.**
- **S5 VERIFY-ERGEBNIS (2026-07-21):** `soundPanel` (~2735+) ist der komplette Patch-Editor
  (Tone/Filter/Envelope/Space+Vibrato/Sub-Bass, alle auf 0.0001 genau) — eindeutig eine primäre
  Editier-Oberfläche, kein Kandidat für Löschung ohne Ersatz-UI. **S5 gestoppt.**
- **S3/S6 nicht mehr einzeln geprüft** — beim gleichen Muster (Panels sind seit dem Plan-Datum
  gewachsen) ist eine ungeprüfte Löschung nicht zu rechtfertigen; siehe Gesamtbefund unten.
- **T1 (offen):** adaptive Spurköpfe (ArrangeTimelineView), fließende Breiten, kein Clipping —
  unverändert vom Chip-Schicksal, kann unabhängig weiterlaufen.

## Gesamtbefund (2026-07-21) — Plan-Prämisse überholt, Kurskorrektur
Die Leiste ist heute kein Restmüll mehr, sondern der einzige Zugang zu mehreren gewachsenen
Haupt-Oberflächen (voller Patch-Editor, Pro-Mixer mit Drum-Kanalzügen, Visual-Look-Customizer).
"Auflösen" im Sinn von "Chip weg, weil eh woanders erreichbar" trifft nur noch auf Video zu
(bereits erledigt). Eine echte Auflösung der restigen Chips bräuchte eine bewusste Redesign-
Entscheidung (WOHIN ziehen diese Oberflächen um — Spur-Ebene? eigener Screen?), keine
Ein-Zeilen-Verify-und-Löschen-Slice. **Empfehlung: S2-S6 auf Founder-Klärung warten** (welche
Ziel-Oberfläche für Mix/Sound/FX/Synth/Mood), nicht blind weiterlöschen. Kein Regressionsrisiko
eingegangen — nichts entfernt, nur die überholte Planannahme korrigiert.
