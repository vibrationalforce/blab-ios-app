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

### Slice 2 — Note verschieben (Body-Drag → Pitch+Step) · ✅ GEBAUT (Review+Gates ausstehend)
- **Model** `PianoRollModel.move(id:toPitch:toStartStep:)` (clamp Pitch in
  low…high, Start in 0…stepCount-len, Länge bleibt, No-op bei Miss). 4 Tests.
- **View** `canvasDrag`: EIN `RollDrag`-Enum (create/move), am Touch-Down via S1
  klassifiziert; `.body`/`.rightEdge` → Move (Note folgt Finger per geclamptem
  Delta), `.empty` wie bisher create/select. Edge-Resize kommt in S3.
- **Audio-sicher:** `active[id]=note`-Snapshot beim Attack ⇒ Move-während-Play
  gibt alte Tonhöhe frei, re-attackt neu, kein hängender Ton. Kein Render-Change.
- Optional (später): Pitch beim Ziehen audibel vorhören.

### Slice 3 — Edge-Resize (rechte Kante ziehen → Länge) · ✅ GEBAUT (Review+Gates ausstehend)
- `.rightEdge` vom Move abgespalten → `RollDrag.resize(id:origStart:)`; live-follow
  ruft `setLength` (existiert, clampt Tail an Takt). Neue reine Länge-vom-Finger-
  Regel `RollHitTest.resizedLengthSteps(fingerStep:startStep:)` (=max(1,f−s+1)),
  3 Tests. Tap auf die Kante = Delta 0 ⇒ nur Auswahl, keine Zufalls-Resize.
- Draw-Length-Picker bleibt für NEUE Notes (Ersteingabe-Bequemlichkeit).

### Slice 4 — Velocity-Lane (Paint) · Audit-Wunsch · ✅ GEBAUT (Review+Gates ausstehend)
- Velocity-Lane als Canvas-Leaf UNTER dem Canvas, in DERSELBEN Horizontal-Scroll
  (VStack{canvas; velocityLane}) → Zeitachsen gekoppelt, kein Offset-Sync; „Vel"-
  Label unter dem Pitch-Gutter. Pro Note ein Balken (Höhe = Velocity, Ton-Farbe);
  vertikaler Drag malt die Velocity der TOPMOST-Note an der Finger-Step-Spalte.
- 2 neue reine Regeln: `RollHitTest.velocity(forY:laneHeight:)` (oben=laut, clamp,
  0-Höhe safe) + `noteToPaint(atStep:notes:)` (topmost covering, wie classify).
  Reuse `setVelocity`. Kein Bio-Read im Leaf ⇒ kein Menü-Freeze. 2 Test-Sets.

### Slice 4b — Velocity-Lane an den Viewport-Boden pinnen (UX, geräteinformiert)
- Slice-4-Review-MEDIUM: die Lane sitzt ~1078 pt (49 Pitch-Reihen) unter dem
  Canvas-Top INNERHALB des Vertikal-Scrolls → unter dem Falz, nur durch Ganz-nach-
  unten-Scrollen erreichbar (Zeit-Lock-Design-Kosten, KEIN Bug — Review APPROVE,
  merge-ok). Ein echtes Pinnen = frozen-row/column (Gutter horizontal-fix +
  vertikal-scrollend, Lane vertikal-fix + horizontal-scrollend) braucht Horizontal-
  Offset-Sync — fragil in der launch-fähigen View, am Gerät nicht CI-verifizierbar.
  Darum ABGESPALTEN + auf die Founder-Geräte-Session gelegt (dort sieht man den
  echten Viewport). Bis dahin: im Build nach unten scrollen. Kein Blocker für S5.

### Slice 5a — Marquee-Auswahl + Highlight + Gruppen-Delete · ✅ GEBAUT (Review+Gates ausstehend)
- `@State selectedIDs: Set<UUID>` + `marqueeRect`. Leerflächen-DRAG wird zum
  Marquee (Promotion aus `.create`, sobald der Finger die Anker-Zelle verlässt →
  **Zero-Distance-Tap-Pfad bleibt unangetastet**). Pure `RollHitTest.notesInRect`
  (AABB-Overlap, halb-offen, corner-order-egal) — 2 Test-Sets. Live-Rubber-Band-
  Overlay, Highlight der selektierten Notes, Inspector „N selected" + Gruppen-Trash
  (`model.remove(ids:)`, getestet). Leerflächen-Drag-CREATE (spanning) ENTFÄLLT —
  ersetzt durch Tap-Create + Kanten-Resize (S3); Hint-Text angepasst.
- **Verhaltensänderung** (Founder-Verify): empty-drag = jetzt Auswahl statt lange
  Note ziehen. Kein Audio/Render-Change (nur Model-Edits + selection state).

### Slice 5b — Gruppen-Move (ausstehend)
- Drag auf eine Note IN der Auswahl verschiebt ALLE selektierten (Delta an alle).

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
