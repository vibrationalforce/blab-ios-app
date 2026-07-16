# PLAN — Menüleisten-Auflösung (Founder 2026-07-16, Screenshot rot markiert)

**Founder-Auftrag:** „Das sollte doch in der Leiste unten alles aufgelöst werden
und nach oben bzw. in die Timeline spuren verteilt werden." (8 sichtbare Chips:
Comp · Session · Sound · Mix · FX · Mood · Synth · Video)

## Ist-Zustand (verifiziert auf HEAD, 2026-07-16)

`EchoelStudioView.StudioMenu` hat 11 Cases; die Chip-Reihe (`studioChips`,
Z. ~1132) filtert `.master`/`.export`/`.bio` BEREITS heraus (S1 historisch
geliefert): Master + Export leben in der Transport-•••-Overflow-Tür, Bio in
der Header-Puls-Pille („Bio details…"). Chrome-Türen setzen `activeMenu`
weiter auf gefilterte Cases → der Panel-Host (`menuDropdownHost`) MUSS alle
11 Cases behalten, nur die Chip-Reihe filtert.

## Chip-Inventur → Zielort

| Chip | Panel-Inhalt | Ziel | Scheibe |
|---|---|---|---|
| Comp | Genre · Tonart · Kammerton · Tempo-Lock · Loop-Länge | TEILS OBEN (Header hat Key/Tempo seit #24); Rest prüfen | S5 |
| Session | Name · Ort · Wetter | OBEN (Header-Session-Zeile existiert) | S5 |
| Sound | Patch-Editor der Primär-Stimme (currentPatch) | SPUR (per-Instrument-Patch = Task #23!) | S4 |
| Mix | 3 Bus-Strips (Bass / Melodic Pad+Lead / Drums): Level+Filter+Drive | SPURKOPF der zugehörigen Built-in-Lanes | **S2 (nächster)** |
| FX | FX-Charakter + Delay-Sync + Stage-Editoren | Charakter global (bleibt/•••); Stages evtl. per Spur später | S6 |
| Mood | 8 Kompositions-Charakter-Felder | OBEN zu Comp (beides = Komposition) oder bleibt | S5 |
| Synth | Visual-Fenster-Toggle + Look | bleibt (Fenster-Steuerung) | — |
| Video | Aufnahme-Bibliothek | bleibt (Bibliothek; ••• hat „video"-Tür) | — |

## S2 — Mix-Strips → Spurköpfe (nächster Zyklus)

**Offene Design-Fragen (ZUERST klären, nicht blind bauen):**
1. **Lane↔Bus-Mapping:** `TimelineLane` hat KEINE Rolle. Die Lanes
   „EchoelBass"/„EchoelDrums"/Melodic-Lanes entstehen wo (TimelineStore-
   Migration? Multi-Roll-Slots?) — dort die ehrliche Quelle fürs Mapping
   finden (Name-Matching wäre eine Lüge). Kandidat: die Slot→Voice-Zuordnung
   des LaneVoiceRack / MultiRollFanout.
2. **recompose-Kopplung:** `mixBinding` (EchoelStudioView) ruft
   `recomposeIfRunning()`; `drumsBinding` treibt BeatPlayer LIVE. Ein
   Spurkopf-Feld muss dasselbe tun → Notification (`.echoelMixChanged`?)
   oder die Logik in MixerStore ziehen (besser: Store-seitiger Hook, dann
   binden Studio UND Spurkopf identisch).
3. **Freeze-Regel:** LaneFX-Expansion liest Doc-Level-Werte (edit-only) —
   MixerStore/TrackFXStore sind low-frequency Stores, im Environment
   vorhanden → Spurkopf-Bindings render-sicher.
4. **Duplikat-Phase:** Strips erst im Spurkopf ERGÄNZEN, Mix-Chip bleibt bis
   Founder-Verify auf dem Gerät, DANN Chip entfernen (Reihenfolge wie
   Bio-Strip→Menü-Host B3).

**Scheiben:** S2a Mapping-Quelle + Store-Hook (pur, getestet) · S2b
Spurkopf-UI (LaneFX-Sektion erweitert, EchoelValueField) · S2c Mix-Chip
entfernen nach Geräte-Verify.

## Reihenfolge

S2 (Mix→Spurkopf) → S4 (Sound→Spur, reitet auf #23 per-Instrument-Patch) →
S5 (Session/Mood/Comp-Konsolidierung oben) → S6 (FX-Stages). Jede Scheibe:
Council, Test-first wo pur, Pflicht-Reviewer, Gates, Deploy.

**Gesetze:** Sheet-Kette wächst nicht (Panels wandern, keine neuen Modals) ·
kein 10-Hz-Read in Ancestors · EchoelValueField überall · eine Scheibe pro
Zyklus.
