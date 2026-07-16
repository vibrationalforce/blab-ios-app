# PLAN #58 — MIDI/MPE-Editing-Station ausbauen

**Founder (2026-07-16):** die MIDI/MPE-Editing-Station ist „noch sehr rudimentär".
**Ziel:** von „malen + löschen" zu einer echten Pro-Piano-Roll — ohne die
launch-fähige Sheet-Kette zu vergrößern, ohne Audio-Thread-Risiko, jede Scheibe
ein Ralph-Wiggum-Takt mit pure/testbarem Kern.

## Ist-Zustand (Audit 2026-07-16, `PianoRollView.swift` 1018 Zeilen)

Vorhanden:
- Tap → Note setzen (Draw-Length 1/2/4 Segmented).
- Horizontal ziehen über leere Fläche → Note über N Steps.
- Tap auf Note → Inspector (Len + Vel als `EchoelValueField`, Löschen).
- Zoom ±, Clear-All, Play/Stop (nur Live-Take, Clip-Editor ist stumm).
- Physik-Farbe pro Reihe/Note (CIE-Ton→Licht am Kammerton), Bar-Linien /4.
- MPE-Expression existiert NUR global bio-abgeleitet
  (`MPEExpression.from(coherence:breath:)` in `trigger`), NICHT pro Note editierbar.

Die EINE `canvasDrag`-Geste macht heute ausschließlich create-or-select. Es gibt:
- **KEIN** Verschieben einer bestehenden Note (Pitch/Step) — man muss löschen + neu.
- **KEIN** Edge-Resize (Länge nur über das Zahlenfeld).
- **KEINE** Velocity-Lane (nur Zahlenfeld pro selektierter Note).
- **KEINE** Mehrfachauswahl / Gruppen-Move/Delete.
- **KEINE** Pro-Note-MPE-Expression (Bend/Slide/Pressure-Override).
- **KEIN** Undo/Redo im Roll-Model (TimelineStore hat es, der Roll nicht).

## Design-Rückgrat (Echoel-Muster)

Die Geste bleibt EINE `DragGesture`; sie verzweigt über einen **pure, getesteten
Hit-Test** (wie `AutomationCanvasMath`): Klassifiziere den Drag-Start in
`.empty(pitch,step)` / `.body(id)` / `.rightEdge(id)`. Move + Resize + Create
teilen sich diesen Kern — die View bleibt dünn, die Geometrie ist unit-testbar
ohne Host. Kein neuer Sheet-Slot (der Roll ist schon präsentiert). Kein
Audio-Thread-Code (reines Model-Mutieren auf `@MainActor`).

## Reihenfolge (Divergenz vom Audit-Vermerk „velocity-lane first" — begründet)

Der Audit notierte „velocity-lane first". ABER: Velocity IST bereits numerisch
editierbar (Inspector-`EchoelValueField`), während **Verschieben komplett fehlt**
— das ist die Lücke, die jeder Nutzer sofort als „rudimentär" fühlt. Council-
Sicht (User-Advocate + Shipper): die gefühlte Rudimentär-Grenze ist „ich kann
eine Note nicht bewegen". Darum Move/Resize zuerst, Velocity-Lane als S4. Das ist
eine bewusste, reversible Umsortierung eines Audit-VORSCHLAGS (kein Founder-
Verdikt) — bei Founder-Widerspruch triviale Rückordnung.

### Slice 1 — Hit-Test-Kern (pure, test-first) · KEIN View-Change — ✅ FERTIG (9656b48, APPROVE)
- **Neu** `Sources/Echoelmusic/Studio/RollHitTest.swift`: `enum RollHit`
  (`.empty(pitch:Int, step:Int)`, `.body(id:UUID)`, `.rightEdge(id:UUID)`) +
  `static func classify(x:Double, y:Double, notes:[Note], stepW:Double,
  rowH:Double, highPitch:Int, lowPitch:Int, stepCount:Int, edgeSlop:Double)
  -> RollHit` (Double statt CGFloat → CoreGraphics-frei, wie AutomationCanvasMath).
  Reihenfolge: Notes-first (obenauf) mit Edge-Zone (letzte `edgeSlop`-Punkte der
  Note-Breite, gekappt auf halbe Note → `.rightEdge`), sonst `.body`; kein Treffer
  → `.empty`. Deterministisch, keine Zufälligkeit, keine Allokation im Hot-Path.
- **Test** `RollHitTestTests`: Edge-Slop-Grenze exakt (inklusiv), Body-Treffer,
  Halb-Note-Kappe (bei slop>halbe Note), Adjazenz-Grenze (halb-offen), leere
  Zelle, überlappende Notes (oberste gewinnt), Clamp, degenerierte Geometrie.
- Risiko: 0 (kein UI-Pfad berührt). CI-verifizierbar. Kein Deploy nötig.
- Code-Review APPROVE (0 HIGH); 3 LOW-Test-Lücken nachgezogen (exakte Slop-Grenze,
  Adjazenz, Kappe-am-Limit) — pinnen `>=`/`<` gegen Regression.

### Slice 2 — Note verschieben (Body-Drag → Pitch+Step) · test-first Model
- **Model** `PianoRollModel.move(id:toPitch:toStartStep:)` (clamp Pitch in
  low…high, Step in 0…stepCount-len, Länge bleibt). Test: Clamp + Idempotenz +
  Überlauf-Schutz.
- **View** `canvasDrag`: Start klassifiziert via S1; `.body` → Move-Modus,
  `onChanged` schiebt Pitch/Step live, `onEnded` committet; `.empty` wie bisher
  create/select. Selected-Note-Feedback bleibt.
- Optional (später, nicht S2): Pitch beim Ziehen audibel vorhören.

### Slice 3 — Edge-Resize (rechte Kante ziehen → Länge)
- `.rightEdge` → Resize-Modus: `onChanged` Preview, `onEnded` `setLength`
  (existiert). Test: Kante am 1-Step-Note, Max-Länge-Clamp, kein Negativ.
- Draw-Length-Picker bleibt für NEUE Notes (Ersteingabe-Bequemlichkeit).

### Slice 4 — Velocity-Lane (Paint) · Audit-Wunsch
- Neues Leaf `RollVelocityLane` unter dem Canvas: pro Note ein vertikaler Balken
  an ihrer Step-x; Drag hoch/runter malt Velocity (reuse `setVelocity`, 0…1).
  Eigenes Leaf ⇒ kein 10-Hz-Read im Roll-Body, keine Sheet-Kette. Test: die
  reine y→velocity-Abbildung (clamp, invertiert).

### Slice 5 — Marquee-Mehrfachauswahl + Gruppen-Move/Delete
- `@State selectedIDs: Set<UUID>`; Leerflächen-Drag = Marquee-Rechteck (pure
  „welche Notes liegen im Rect"-Funktion, testbar); Gruppen-Delete + Gruppen-
  Move (Delta an alle). Inspector zeigt „N selected". Sheet-Kette unberührt.

### Slice 6 — Pro-Note-MPE-Expression-Seam (die echte „MPE-Station")
- `Note` bekommt optionale Per-Note-Expression-Overrides (Bend/Slide/Pressure,
  `decodeIfPresent`, absent ⇒ heutiges globales bio-`MPEExpression` unverändert).
  `trigger` mischt Override über die Bio-Ableitung. Größer — evtl. eigene
  Unter-Strecke; Council vor Start (berührt den `trigger`-Notenpfad + Persistenz).

### Slice 7 (optional/später) — Quantize/Snap-Subdivisions + Triolen
### Slice 8 (optional/später) — Undo/Redo im Roll-Model (TimelineStore-Muster)

## Gesetze eingehalten
- Sheet-Kette wächst NICHT (Roll ist bereits präsentiert; alle Slices sind
  In-View-Leafs/Gesten).
- Kein 10-Hz-Read in Root/Ancestor (Velocity-Lane = eigenes Leaf).
- Kein Audio-Thread-Code (reine `@MainActor`-Model-Mutationen; `trigger` liest
  weiterhin nur vorbereitete Werte).
- `EchoelValueField` bleibt der Parameter-Regler; Lane/Marquee sind Gesten, keine
  neuen Slider.
- Pure Kerne + Tests zuerst; `decodeIfPresent` bei S6-Persistenz.
- Reviewer: code-reviewer je Slice; **audio-thread-reviewer NUR bei S6**
  (`trigger`-Notenpfad). Kein Deploy für unhörbare Kern-Slices; Deploy-Kandidat
  frühestens nach S2/S3 (fühlbares Move/Resize) — Founder-Freeze beachten.

## Erste Scheibe = Slice 1 (Hit-Test-Kern, test-first, Risiko 0).
