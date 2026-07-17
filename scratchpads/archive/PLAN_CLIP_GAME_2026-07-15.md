# PLAN — Clip-Game aufräumen (founder 2026-07-15: "seamless workflow, kein unbeholfenes Rumdrücken, am Ende steuert EchoelAI alles")

## Architektur-Leitplanke (EchoelAI-ready — das WICHTIGSTE Prinzip)
Jede Clip-Operation MUSS als **Store-Methode** existieren (TimelineStore), mit purer,
getesteter Mathematik darunter (TimelineRegion/TimelineSnap). Gesten sind nur DÜNNE
Trigger auf diese Methoden — NIE View-lokale Edit-Mathematik. Dann ist die spätere
EchoelAI-Toolschicht (à la `ParameterToolCore`, ADR 2026-07-12, hinter
`FeatureFlags.echoelAI`) trivial: ein `TimelineToolCore` mappt Intents („schneide alle
Clips am Takt 4", „schiebe die Bassspur 2 Takte nach hinten") 1:1 auf dieselben
Store-Calls, die auch der Finger nutzt. Editing/Sound/Musik/Video-AI = EIN Befehlskern,
zwei Frontends (Touch + Sprache/Modell).

Stand heute (gut): split/merge/resize/trimStart/move/duplicate/remove sind bereits
Store-Methoden mit purem Kern + Tests. Die Gesten-Lücken unten sind reine UI-Arbeit.

## AUDIT — was das Clip-Game heute kann / wo es klemmt
| Interaktion | Stand | Bewertung |
|---|---|---|
| Tap Clip | Audition (nur Audio) | ok |
| Long-press Clip | Menü: Edit·Split·Join·Move-to-playhead·Duplicate·Delete | ok (v226/v235) |
| Trim hinten/vorne | Zieh-Griffe, Leaf-Preview, Snap | ok (v231/v236) |
| Long-press leere Spur | Import on the spot | ok (v238) |
| Playhead | greifbar, Snap, 60 fps Glide | ok (v230–237) |
| **Clip VERSCHIEBEN** | **NUR über Menü „Move to playhead"** | **#1-LÜCKE — das ist das „unbeholfene Rumdrücken"** |
| Clip auf andere Spur ziehen | fehlt | Teil der #1-Lücke |
| Undo/Redo | fehlt komplett | #2 — ohne Undo kein furchtloses Editieren |
| Multi-Select + Combine/Batch | fehlt (Task #43) | #3 |
| Snap-Feedback (Haptik/Guides) | fehlt | #4 — Politur |
| Overlap-Regeln beim Ablegen | keine (Regionen können überlappen) | mit #1 beobachten, Regel später |

## ZYKLEN (Ralph, je 1 Punkt)
- **C1 (JETZT): Drag-to-move.** Clip mit dem Finger packen und verschieben — horizontal
  (Zeit, Snap beim Loslassen) UND vertikal (auf eine andere Spur GLEICHER Art).
  Store: `moveRegion(id:toStartTick:laneOffset:)` (Kind-Check im Store). Test-first.
  Geste: DragGesture(min 8) auf dem Clip-Körper; Trim-Griffe (oben drüber) gewinnen
  ihre Zonen; Tap/Long-press fallen weiter durch. Leaf-Preview via moveDelta-@State
  (kein Root-Churn), zIndex während des Zugs. „Move to playhead" bleibt als Menü-Weg.
- **C2: Undo/Redo** im TimelineStore (Dokument-Snapshots, begrenzte Historie; Toolbar-
  Knopf + Shake später). Öffnet auch EchoelAI den „mach das rückgängig"-Befehl.
- **C3: Multi-Select** (Tap-Halten-Tap? Auswahl-Chip) + Combine + Batch-Delete/Move (Task #43).
- **C4: Snap-Feedback** — Haptik-Tick beim Einrasten + Magnet an Nachbar-Clip-Kanten.
- **C5: Overlap-Regel** beim Ablegen (verdrängen/kürzen/ablehnen — Founder-Geschmack).
- **C6: TimelineToolCore (EchoelAI)** — Intents → Store-Calls, hinter FeatureFlags.echoelAI,
  modellfrei testbar (wie ParameterToolCore). Editing-AI-Fundament.

## Council (Kurzform)
· Architect: Store-first erzwingen — Gesten dünn halten; genau so bleibt EchoelAI ein Mapping, kein Umbau. 
· Shipper: C1 ist der fühlbarste Gewinn; eine Geste, ein Store-Call, Tests da. 
· Skeptik: ScrollView-Konflikt (Clip-Drag vs. Timeline-Pan) — Präzedenz: Trim-Griffe gewinnen device-verifiziert; Move nutzt dasselbe Muster. DEVICE-VERIFY im nächsten Build. 
→ proceed mit C1.
