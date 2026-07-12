# Inventar-Report: Ableton Live 12.x — vollständiger Funktions-Stand (bis Beta 12.4.5)

(Deep-Research-Agent, 2026-07-12, Founder-Auftrag: "Ableton 12 Beta kommt
ständig mit neuen Funktionen … Wir machen eine zukunftsorientierte Version,
hängen sogar Ableton 20 ab." Schwester-Report:
RESEARCH_FRONTIER_ABLETON20_2026-07-12.md. Quellen: Web-Such-Snippets —
Direktabrufe scheiterten am Agent-Proxy (403); Lücken sind explizit markiert.)

## Versions-Zeitleiste

| Version | Datum | Kern |
|---|---|---|
| 12.0 | 03/2024 | MIDI Transformations/Generators, Keys & Scales global, Meld, Roar, Granulator III, Sound Similarity Search, verbesserte Browser-Tags |
| 12.1 | 2024 | Auto Filter/Shifter-Updates, Limiter neu, Mixer im Arrangement, Linked-Track-Editing |
| 12.2 | 06/2025 | Bounce to New Track, Auto Shift, Expressive Chords, Step-Recording, Automations-Editing per Tastatur |
| 12.3 | 2025 | **Stem Separation** (Music.AI-Lizenz, lokal, Suite-only: Vocals/Drums/Bass/Other), Splice-Integration im Browser, Generators: **Sting** + **Patterns**, Push-Standalone-Erweiterungen |
| 12.4 | 05/2026 | **Link Audio** (Audio-Streaming zwischen Link-Geräten), Workflow-Polish |
| Beta 12.4.5 | laufend | **Extensions SDK (JS/TS)** — Dritt-Extensions in Live, frühes Beta |

## MIDI-Transformations (Vollliste, alle skalen-bewusst seit 12.0)

Arpeggiate · Chop · Connect · Glissando · LFO · Ornament · Quantize ·
Recombine · Span · Strum · Time Warp · Velocity Shaper.
Dazu Note Utilities: Humanize, Add Intervals, Fit to Scale, Invert, Mirror.

## MIDI-Generators

Rhythm · Seed · Shape · Stacks (12.0) + Sting · Patterns (12.3).
Alle erzeugen in die Clip-Notenliste (destruktiv-editierbar), skalen-bewusst
über die globale Keys&Scales-Einstellung.

## Piano Roll / Noten-Editing

- **Note Chance** (Wahrscheinlichkeit pro Note) + **Velocity Ranges**
  (Zufallsspanne) — seit Live 11. KEINE Repeats/Ramp/Occurrence-Operators
  (das ist Bitwig-Territorium, in Live bis 12.4.5 NICHT vorhanden).
- **MPE-Editing-Tab** (seit 11): Pitch/Slide/Pressure-Kurven pro Note
  editierbar — Desktop-Maus-Workflow.
- Fold to Scale (G), Scale Highlighting, Chord-Eingabe via Expressive Chords
  (12.2), Step-Recording (12.2).
- **Take Lanes** seit Live 11 — Audio UND MIDI Comping.

## Automation

- A-Taste zeigt Lanes; **Alt+Drag krümmt ein Segment** (eine Krümmungszahl
  pro Segment — exakt unser AutomationLane-`curvature`-Modell).
- **KEINE Shape-Presets/Stempel** in der Arrangement-Automation (die
  "Shapes" in Marketing-Material = LFO/Shaper-MIDI-Tools, nicht Automation).
  → UNSERE CHANCE: Shape-Stempel + gezeichnete Formen auf Touch.
- Draw Mode (B) rastert auf Grid-Steps; 12.2: Keyboard-Editing der Punkte.
- Tempo-Automation auf der Main-Spur.
- Trennung: **Automation (absolut) vs. Modulation (relativ)**; Clip-Envelopes
  können unlinked (eigene Loop-Länge) laufen — Polyrhythmik-Trick.

## Tuning Systems (seit 12.0)

- `.scl`/`.ascl`-Import, REFERENCE_PITCH-Zeile, pro Set gespeichert.
- Roll zeigt Tuning-Töne statt MIDI-Namen; alle Live-Instrumente folgen
  AUSSER Drum Synths; Dritt-Plugins nur via MPE ±48 Semitone Pitch-Bend.
- Kein dynamisches Retuning während der Wiedergabe.
- → Echoel-Vergleich: unser Kammerton/Tonsystem-Modell ist FREQUENZ-echt bis
  in die Farbe (SpectralColor) — Live färbt nichts nach Physik.

## Stem Separation (12.3)

Music.AI-Modell, läuft lokal, Suite-only. Vocals/Drums/Bass/Other, direkt
aus dem Clip. (Echoel: nicht relevant für v10-Scope — wir GENERIEREN.)

## Link Audio (12.4)

Audio-Streams zwischen Link-Teilnehmern im LAN (Jam-Fokus). Latenz-Angaben
nicht verifizierbar (403). — Echoel-Einordnung: unser SharePlay-Puls+Partitur-
Modell (decisions 2026-07-10B) streamt KEIN Audio und bleibt darum
physik-ehrlich über WAN; Link Audio ist LAN-Jam, kein Konkurrent des
"Wir streamen den Puls"-Modells.

## Push-3-only (nicht iPhone-relevant, der Vollständigkeit halber)

Standalone-Betrieb, MPE-Pads, 12.3-Standalone-Erweiterungen, Audio-Interface.

## Extensions SDK (Beta 12.4.5)

JS/TS-Extensions, App-Store-artiger Vertrieb angedeutet. Frühe Beta, API-
Oberfläche unbekannt (403-Lücke). Strategisch: Ableton öffnet sich für
Dritt-UI — bestätigt, dass "eine Surface, viele Module" die Richtung ist.

## Lückenliste (nicht verifizierbar wegen Proxy-403)

- Exakte 12.4.5-Beta-Release-Notes (nur Foren-Snippets).
- Link-Audio-Latenzzahlen und Teilnehmer-Limit.
- Extensions-SDK-API-Umfang.
- Detailverhalten Velocity-Ranges bei überlappenden Noten.

## Konsequenz für Echoel (Priorisierung → PLAN_DMMW_PROFI_LEVEL)

1. **Note-Operators (Chance/Repeats/Ramp/Occurrence) pro Note** — Live hat
   nur Chance+Velocity-Range; Bitwig-Niveau auf Touch = überholt Live 12
   sofort. Reines Modell-Feature (Note-Codable-Migration nötig, decodeIfPresent
   wie bei AutomationPoint.curvature).
2. **Strum/Humanize/Articulate als Ein-Gesten-Transform** auf BioComposer-
   Output/Roll-Selektion — Live braucht dafür Tool-Panels.
3. **Automations-Canvas mit Krümmung + Shape-Stempeln** — Live kann nur
   Alt+Drag-Krümmung; Stempel + Touch-Zeichnen = voraus.
4. **Bio-Operators** (Kohärenz→Chance, Puls→Ramp) + **Bio als per-Note-
   Expression** — hat NIEMAND im Feld (Frontier-Report Befund 6).
