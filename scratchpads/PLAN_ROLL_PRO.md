# PLAN — Piano Roll Pro-Funktionen + Echoel-Twist (Founder 2026-07-17)

Founder: "Mach da noch mehr Funktion beim Piano Roll… Siehe Ableton und alle
anderen DAWs was die haben. Das und ein Echoel twist mit hineinbringen."

## DAW-Landkarte (Ableton/FL/Logic/Bitwig) vs. Ist-Stand
HABEN: Draw/Move/Resize, Marquee, Velocity-Lane, Inspector (+MPE per Note),
Quantize-Menü, Undo/Redo, Zoom + adaptiver Fit, Beat-Lineal, Audition.
FEHLEN (Ein-Takt-Scope, phone-tauglich):
- Selektion-Ops: Reverse (Retrograde), Pitch-Invert, Legato, Double/Half-Time,
  Velocity-Ramp (Crescendo), Note-Echo (FL "Flam/Roll"-Familie)
- Scale-Lock: In-Skala-Reihen hervorheben + Zeichnen snappt in die Tonart
  (Ableton Scale Mode / FL Scale-Highlight; Scaler-Adoption #5)
- Fold: nur benutzte/skalen-eigene Reihen zeigen (Ableton Fold) — Phone-Gold
SPÄTER (eigene Slices): Ghost-Notes anderer Spuren, per-Note-Chance/Probability
(braucht Trigger-Support), ChordSuggest-Stempel (Akkord-Stempel, voice-led).

## Echoel-Twist (der Unterschied zu jedem DAW)
1. **Bio-Humanize-Button**: H3-Core `BioComposer.hrvHumanize` auf die SELEKTION
   mit der ECHTEN aktuellen HRV — der Körper lockert genau die Noten, die du
   markierst. Deterministisch pro Anwendung (Seed aus RNG-Draw des Models).
2. **Scale-Lock kennt die Session-Tonart** (nicht ein Dropdown wie Ableton):
   Tonart/Skala kommen aus dem Take-Kontext des Models — ein Schalter, kein Setup.

## Slices
- **R1 (jetzt):** pure `RollNoteOps` Core (Sequencer/ oder Studio/, Foundation-only)
  + Toolbar-Wiring (Ops-Menü im zoomButton-Chrome, KEIN neues Sheet) + Scale-Lock
  (Highlight + Draw-Snap) + Fold + Bio-Humanize. Tests für jede Op (Grenzen,
  Determinismus, Ein-Takt-Invarianten).
- **R2:** ChordSuggest-Stempel (long-press leere Zelle → kohärenz-gewählter,
  voice-geführter Akkord — H2/H1-Cores wiederverwenden).
- **R3:** per-Note-Chance mit Kohärenz-Kopplung (Trigger-Pfad erweitern).

## Gesetze
Kein neues Sheet (Modal-Decke) · kein 10-Hz-Read im Roll-Body (Bio-Snapshot nur
im Button-Tap lesen) · Undo-Pfad des Models für jede Op · Type-Check-Budget:
neue UI als Leaf-Structs · EchoelValueField für neue Parameter · keine
Slider/Stepper.
