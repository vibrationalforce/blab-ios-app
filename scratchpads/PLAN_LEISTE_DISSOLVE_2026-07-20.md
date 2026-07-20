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
- **S1 (dieser Zyklus):** `.video` aus `studioChips`-Filter → Video-Chip verschwindet aus der
  Leiste. videoPanel-Code bleibt kompilierend (unreferenziert, spätere Löschung eigener Slice).
  Test: falls ein Test die Chip-Menge pinnt, anpassen.
- **S2:** Mix-Chip — verify mixerPanel bietet nichts Einzigartiges (Master ist eigener,
  ausgeschlossener Chip) → entfernen.
- **S3–S5:** FX/Synth/Sound analog (verify → remove).
- **S6:** Mood → BodyVibe (nach Oberfläche + Founder-Ask); dann ist die Leiste leer → ganz raus.
- **T1:** adaptive Spurköpfe (ArrangeTimelineView), fließende Breiten, kein Clipping.
