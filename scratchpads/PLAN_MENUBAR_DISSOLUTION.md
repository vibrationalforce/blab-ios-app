# PLAN — Menüleisten-Auflösung (KANONISCH, Deep-Audit 2026-07-16)

**Founder-Auftrag, mind. 6× erteilt (07-09→07-16), Deep-Audit beider Seiten
(Auftrags-Historie + HEAD-Inventur) am 2026-07-16.** Bei Widersprüchen gewinnt
der NEUESTE Auftrag. Zwei Unzufriedenheits-Marker (07-14 „längst", 07-16
„sollte doch") = die offenen Reste unten sind der Kern.

## Die kanonische Ziel-Tabelle (Founder 07-14 Rotstift-Pass + 07-16)

| Inhalt | Ziel (Founder-Worte) | Status HEAD |
|---|---|---|
| Bio-Strip | Header-Pille, Tap = Details („komplett nach da oben") | ✅ v199 (Chip weg) |
| Tempo (+Lock) | Transport-Bar neben Play („Das soll da oben hin") | ✅ 8ae8522 |
| Master·Export·Live·Learn | Transport-••• neben dem Schloss | ✅ E1 + 8ae8522 |
| Transpose | GELÖSCHT („Wir erstmal komplett gelöscht") | ✅ v208 |
| **Mix (Bus-Strips)** | **„Mix wird Teil der Spuren in der Timeline"** | ❌ **S2 — JETZT** |
| Sound & texture | „Teil von EchoelSynth" = per Instrument/Spur | ❌ S4 (reitet #23) |
| Genre·Variation·Mood | pro MIDI-Spur, OPTIONAL anschaltbar | Daten ✅ (ce248bf: genreOverride/mood/variationSeed auf TimelineLane, nil=global) · UI ❌ S3 |
| Session (Name/Ort) | „auch nach oben" + manueller Ortsname | teils (Ort manuell ✅ im Panel) · Header-Zeile ❌ S5 |
| Comp Key/Scale/Kammerton | „nach oben wie eingezeichnet" | ❌ S5 (Tempo ist oben, Rest im Panel) |
| Weather | „extra Tool, bei den Instrumenten optional" | ❌ → Task #59 (EchoelWeather-Synth, per-Spur-Toggle) |
| FX | Charakter global; Stages später per Spur | S6 |
| Synth-Chip (Visual) | bleibt (Fenster-Steuerung) | ✅ |
| Video-Chip | eigene Spur-ART + Bibliothek; Chip = Bibliothekstür | Spur ✅ v191 · E3 Capture/Mediathek offen |
| EchoelBioSynth als AUv3 | 07-12-Auftrag; 07-14/16 überschreiben: erst Spurköpfe/Header | Langstrecke E4 (device-gated) |

## S2 — Mix → Spurköpfe (nächste Scheibe; die Design-Fragen sind BEANTWORTET)

**Lane↔Bus-Mapping (Audit-Fund, ehrlich):** `TimelineLane.builtinInstrument:
TrackInstrument?` IST die Quelle — kein Name-Matching:
- `.subBass` → MixerStore.bass + TrackFXStore .bass (Level/Filter/Drive)
- `.drums` / `.breakLoop` → MixerStore.drums-Pfad (drumsBinding = BeatPlayer
  masterLevel LIVE) + .drums-Bus
- `.polySynth` / `.bioVoice` / Roll-Lane → melodic-Bus (+ Pad/Lead-Level)
- Lane ohne builtinInstrument (reine MIDI/Audio/Video) → KEIN Bus-Strip
  (ehrlich: sie hängt an keinem Bus).

**Apply-Kopplung:** LaneFXEditor schreibt heute schon `trackFX.melodic` und
appliziert live (synth+leadSynth, :1375) — dasselbe Muster für .bass/.drums:
Apply-Logik aus EchoelStudioView (setBassFX/setDrumsFX) in einen store-nahen
Helper ziehen ODER in LaneFXEditor mit injizierten Voices replizieren.
`mixBinding`-Levels brauchen `recomposeIfRunning` → Notification
`.echoelMixChanged` (Studio hört, recomposed) — Ausnahme drums (LIVE, kein
recompose nötig).

**Injektionen (billig, Env vorhanden):** ArrangeTimelineView braucht
`MixerStore` (+ ggf. `SubBassVoice`); TrackFXStore/BeatPlayer sind schon da.

**Modal-Budget:** KEIN neuer Sheet — LaneFXEditor (ArrangeModal .laneFX,
EIN item-Sheet) wird um die Bus-Sektion erweitert. Root-Kette unangetastet.

**Scheiben:** S2a Bus-Mapping pur (`TrackInstrument → MixBus?` + Tests) ·
S2b LaneFX-Bus-Sektion (EchoelValueField, nur bei gemapptem builtinInstrument)
· S2c Mix-Chip fällt NACH Founder-Geräte-Verify (Reihenfolge wie Bio B3).

## Reihenfolge (Rest)

S2 (Mix→Spurkopf) → S3 (Genre/Variation/Mood-UI pro Spur — Daten liegen) →
S4 (Sound→Spur via #23) → S5 (Session/Comp-Reste nach oben) → S6 (FX-Stages)
→ E3 (Video-Capture/Mediathek) → E4 (EchoelBioSynth-AUv3, Langstrecke).

**Gesetze:** Root-Sheet-Kette wächst NIE (Slot-Reuse; 0 freie Slots, ~13+3+2
belegt) · kein 10-Hz-Read in Ancestors · EchoelValueField · Chip fällt erst
nach Geräte-Verify · eine Scheibe pro Zyklus.
