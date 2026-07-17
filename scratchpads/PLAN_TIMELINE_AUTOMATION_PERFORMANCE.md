# PLAN — Automation in die Timeline + Clip-Launch/Performance (Founder 2026-07-17)

## Founder-Direktive (verbatim-Kern, Screenshot = heutiges Automation-Sheet)
"Automations Sektionen sollten in der Timeline direkt sein oder? Das man im
Verlauf des Tracks automatisieren kann. Plus was ist mit den Clips und dem Play
Button auf den Clips und Performance Mode. Mache dafür alles klar."

## Council
- User-Advocate: Das Sheet (Keyframe-Zahlenliste) ist Editor-Denken; der Founder
  will DAW-Denken — die Kurve unter der Spur, über den Song-Verlauf. Ja zur
  Frage: inline ist richtig; das Sheet bleibt als Detail-Editor (Zahlen exakt).
- Architect: Bestände wiederverwenden — AutomationLane (Storage), A3
  AutomationCanvasMath (Zeichen-Mathe), EchoelParameterRegistry (Ziele),
  ArrangeTimelineView (Zeit-Mathe TimelineTime, Zoom/Scroll vorhanden). KEIN
  neues Store-Modell.
- Skeptic: ArrangeTimelineView ist groß (Type-Check-Budget!) — Automation-Zeile
  als eigene Leaf-Struct-Datei. Performance-Mode ist ein TRANSPORT-Thema
  (quantisiertes Umschalten), nicht nur UI — Core zuerst, pure + getestet.
- Shipper: 2 disjunkte Slices parallel: T1 (Timeline-UI) + P0 (Launch-Core ohne
  UI); P1 (Play-Button-UI) NACH T1-Commit (gleiche Datei).
→ proceed.

## Slices
### T1 — Automation-Zeile in der Timeline (UI, läuft)
Pro Spur aufklappbare Automation-Zeile UNTER der Lane-Row (Chevron/Toggle am
Spurkopf): zeigt die AutomationLane-Kurve der Spur über die GANZE Song-Länge
(x = TimelineTime-Ticks, gleiche Skala/Scroll wie Clips), Tap-Add / Drag-Move /
Double-Tap-Delete via AutomationCanvasMath (A3-Muster aus AutomationView).
Ziel-Picker kompakt in der Zeile (bestehende Registry-Ziele). Neue Datei
`Studio/TimelineAutomationRow.swift` (Leaf), ArrangeTimelineView nur Einhänge-
punkte. Sheet (AutomationView) bleibt als Präzisions-Editor erreichbar.

### P0 — Clip-Launch-Core (pure, läuft)
`Sequencer/ClipLaunchEngine.swift`: quantisiertes Starten/Stoppen von Regionen
zur Laufzeit (Launch-Quantisierung Bar/Beat; Zustandsmaschine idle→queued→
playing→queuedStop; pure Tick-Mathe auf TimelineTime). TimelineRegionPlayer
bekommt die minimale API `launch(regionID:quantize:)` / `stopLaunched(...)` —
Override-Schicht ÜBER dem Arrangement (gelaunchte Clips klingen zusätzlich/
statt Arrangement-Region ihrer Lane, letzteres = Lane-Override wie Ableton).
Tests: Quantisierungs-Grenzen, Zustandsübergänge, Determinismus.

### P1 — Play-Button auf dem Clip + Performance-Mode (NACH T1, gleiche Datei)
Clip-Region bekommt im Performance-Mode einen Play-Glyph (Tap = launch quantized,
erneut = queuedStop); Performance-Mode-Toggle im Timeline-Chrome. Kein neues
Sheet. Farb-/Puls-Feedback ≤3 Hz (Flash-Gesetz).

## Gesetze
Type-Check-Budget (Leaf-Dateien) · kein neues Sheet · kein 10-Hz-Read im Body
(Playhead-Leafs wiederverwenden) · Undo für Automation-Edits über bestehenden
Pfad · EchoelValueField für exakte Werte (im Sheet, nicht in der Zeile) ·
Flash ≤3 Hz.
