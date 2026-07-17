# PLAN — Alles in die Spur + EchoelBodyVibe (Founder-Screenshot 2026-07-17, v281/2388)

## Founder-Direktive (verbatim-Kern)
"Genre, Sound, Mix, FX, Mood, Synth kommt alles in ein Instrument. Bio Instrument
kommt weg bzw. wird in EchoelBodyVibe umgewandelt. Hier wird das gesamte Create
from within Thema was vorher unser Prototyp war integriert. Also als Echoelmusic
noch Instrument only war." — Screenshot: rote Markierung um die unteren Chips
Sound · Mix · FX · Mood · Synth (Video NICHT markiert, bleibt).

## Deutung (Council: proceed)
1. Die globalen Unteren-Leiste-Chips lösen sich in die SPUR auf: jede Spur trägt
   ihr eigenes Genre · Sound(Patch) · Mix · FX · Mood · Synth-Panel (Spur-Editor).
   Das ist #55 Step 3+4 + Baustellen-#3 in einem, jetzt founder-bestätigt.
2. Der Spezial-Status "Bio-Spur"/"Bio voice" verschwindet als KATEGORIE und wird
   das Instrument **EchoelBodyVibe**: das komplette Create-from-Within-Erlebnis
   (BioComposer generate/evolve, Puls→Musik, BioReactiveSynthVoice) als EIN
   Instrument AUF einer Spur — der Prototyp (Instrument-only-Ära) wird Bürger
   der Spuren-Welt, nicht deren Sonderfall.
   WICHTIG (Skeptic): "kommt weg" = TRANSFORMIEREN, nicht löschen — isBio-Lane-
   Plumbing (Bio-Strip, Visual, Automation) bleibt kompilierend, bis BodyVibe
   jede Rolle übernommen hat; Umbenennung erst WENN das Instrument echt klingt
   (kein lügendes Label).

## Slices (Reihenfolge nach Hörbarkeit, jede grüne Runde deployt)
- **A — per-Lane-Composition CORE (läuft):** pure `composeLaneOverrides(base:lanes:)`
  → [laneID:[Note]] via LaneComposerInput.apply (structureSeed geteilt = Kohäsion,
  BioVariationMaze-Muster), Aufruf nach dem Primary-Take in generate(), Schreiben
  NUR in composer-eigene Clips (Ownership-Guard — nie einen user-platzierten Clip
  klobbern). Bit-identisch solange kein Override gesetzt. Test-first.
- **A2 — Spur-Panel UI:** Genre-Picker + Mood + Variation-Würfel + die bestehenden
  Sound(Patch)/FX/Mix-Türen in EINEM Spur-Editor konsolidiert (LaneFXEditor wächst
  zum Instrument-Panel; Sheet-auf-Sheet, Root-Kette wächst nicht, EchoelValueField).
- **B — EchoelBodyVibe:** TrackInstrument .bioVoice → displayName "EchoelBodyVibe";
  eine BodyVibe-Spur bekommt die BioReactiveSynthVoice als echte Rack-Einheit
  (KindVoiceAllocator .bioVoice-Fall — letzte v1-Deferral fällt) UND ihr
  Spur-Panel trägt die Create-from-Within-Steuern (Generate/Evolve/Bio-Quelle).
  Erst hier fällt der Sonderstatus der Bio-Spur.
- **C — Chips auflösen:** Sound/Mix/FX/Mood/Synth aus der unteren Leiste entfernen,
  sobald A2 ihre Funktion pro Spur trägt (Video-Chip bleibt — nicht markiert).

## Gesetze
Sheet-Kette nicht wachsen · 10-Hz-Freeze · Rausch-Triade read-only · Audio-Thread
lock/alloc-frei · decodeIfPresent · bit-identisch ohne Override · kein lügendes Label.
