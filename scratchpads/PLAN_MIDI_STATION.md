# PLAN — MIDI/MPE Editing Station (Task #58, Founder 2026-07-16)

> ⛔ **SCOPE NOTE (audit 2026-09-02): this plan predates the product definition of 2026-07-25**
> (`docs/dev/PRODUCT_DEFINITION.md`, Editor ≠ Workstation). Where it names timeline / clips /
> arrangement / multitrack / lanes-as-tracks / AUv3 / broadcast / drums / piano-roll surfaces, those
> are CUT and that part is history — do not execute it. Nothing below was edited; check the
> definition before building from any line here.


> Founder: „Geht eine Integration in die Midi Instrumente? Die ganze MIDI (MIDI 2.0?/MPE)
> Editing Station ist noch sehr rudimentär oder?" — Ja, sie ist rudimentär. Dieser Plan
> baut die Piano Roll zur ernsthaften Station aus, in Wertreihenfolge:
> Velocity-Lane → Multi-Select+Quantize → per-Note-Expression-Kurven (die USP:
> aufgenommene BIO/MPE-Expression wird pro Note sichtbar + editierbar) → MPE/MIDI-2-Vollständigkeit.
> Investigation read-only 2026-07-16; nichts committed.

---

## 1. CURRENT-STATE MAP (verified, file:line)

### Data model
| Truth | Where |
|---|---|
| `Note` = pitch · startTick/lengthTicks (480 PPQ) · `velocity: Float [0…1]` · `role` · `operators: NoteOperators?` | `Sources/Echoelmusic/Sequencer/Note.swift:29-49` |
| Codable: ticks primary, legacy-step fallback, `decodeIfPresent` throughout; `operators` nur encoded wenn gesetzt (Byte-Identität für plain notes) | `Note.swift:141-176` |
| `NoteOperators` = chance/repeats/ramp/occurrence + **bio-expression DEPTHS** (velocityDepth wired, timingDepth/filterDepth model-only) — das ist eine *generierende* Expression (Body zur Playzeit), KEINE gespeicherte Kurve | `Sequencer/NoteOperators.swift:53-109, 135-175` |
| `NoteExpression` (velocityScale wired; timingOffsetTicks/brightness unwired) | `NoteOperators.swift:38-48` |
| **Es existiert KEIN Speicherort für aufgenommene per-Note-Kurven** (pressure/timbre/bend über die Notendauer) | — |
| `MelodyClip { notes: [Note] }`, Clip-Persistenz JSON | `Sequencer/Clip.swift:19-22, 71-110` |
| Quantize-Primitiv existiert bereits, UI-los: `Note.quantizedStart(toTicks:)` | `Note.swift:127-132` |

### Editing UI (die „Station" heute)
| Truth | Where |
|---|---|
| `PianoRollView`: tap-add / drag-stretch / tap-select EINE Note; Inspector = `EchoelValueField` Len + Vel (nur die selektierte Note); Clear/Zoom. **Keine Velocity-Lane, kein Multi-Select, kein Quantize, keine Expression-Anzeige** | `Studio/PianoRollView.swift:654-982`, Inspector `:781-817` |
| Canvas-Geste: EIN `DragGesture(minimumDistance: 0)` im horizontalen ScrollView | `PianoRollView.swift:950-981` |
| Präsentation: `ArrangeTimelineView` besitzt DEN einen `.sheet(item:)` mit `ArrangeModal`-Enum; `.lane(midi)` → shared Roll (`:341`), `.region` → wegwerf-Modell + Done-Splice (`openRegionEditor :261`, `commitClipEdit :286`, `MelodyBarEdit.splice`) | `Studio/ArrangeTimelineView.swift:53, 206-234, 296-346` |

### MPE/MIDI input → engine
| Truth | Where |
|---|---|
| `MIDIInput`: CoreMIDI `._2_0`-Port, RTP-MIDI, batch-queue drain; Callbacks noteOn/noteOff/CC/pitchBend (normalisiert) | `Audio/MIDIInput.swift:60-171` |
| `MIDIBusPublisher` → `EngineBus.controllerEvents`: CC74→`.slide`, CC21-31→`.airCC`, bend→`.pitchBend`; **channelPressure NICHT verdrahtet, MPE-Master/Member-Unterscheidung NICHT verdrahtet, andere CCs gedroppt** (im Header selbst als „MPE-completeness follow-up" markiert) | `Sync/MIDIBusPublisher.swift:12-20, 138-153` |
| Einziger Queue-Konsument: `BioReactiveSynthVoice.drainControllerEvents` — pitchBend → GLOBALER ±2-Halbton-Offset; `.slide/.airCC/.channelPressure` reserviert/ignoriert. **PolySynthVoice drained NICHT** („Does NOT drain controllerEvents", `PolySynthVoice.swift:494`) → externe MPE-Per-Note-Dimensionen erreichen den Haupt-Synth heute gar nicht | `Tools/BioReactiveSynthVoice.swift:209-245` |
| Record-Tee erfasst NUR note/velocity (`onRecordNoteOn/Off`); `MIDINoteRecorder` (pure) baut Notes aus on/off — **einlaufende Bend/CC74/Pressure-Kurven werden bei Aufnahme WEGGEWORFEN** | `MIDIBusPublisher.swift:59-60`, `Sequencer/MIDINoteRecorder.swift:44-79`, `TakeRecorder.swift` (kein cc/bend-Treffer) |

### Playback
| Truth | Where |
|---|---|
| Primär-Roll `trigger(step:)`: Velocity WIRD honoriert (`note.velocity * laneGain * exp.velocityScale` → noteOn); Bio-`NoteExpression.velocityScale` wired; timing/brightness explizit unwired | `PianoRollView.swift:575-589` |
| MPE-OUT: `MPEExpression` aus LIVE-Bio, EINMALIG am note-on (kein kontinuierlicher Stream, nichts Gespeichertes) | `PianoRollView.swift:560-568`, `Audio/MIDIOutput.swift:129-146` |
| Sekundär-Lanes: `LaneNotePump` honoriert Velocity, sonst nichts (Operators/Bio dort bewusst später) | `Sequencer/LaneNotePump.swift:104-110` |
| AUv3-Host bekommt note/velocity bytes, keine Expression | `PianoRollView.swift:586` |

### Export / MIDI 2.0
| Truth | Where |
|---|---|
| `MIDIFileExporter`: SMF 0/1 @ **96 PPQ** (480→96 Downsample), Velocity + Dauer honoriert, Key/Tempo/TimeSig-Meta — **keine CC/PitchBend/Pressure-Events** | `Sequencer/MIDIFileExporter.swift:23-29, 95-141, 155-187` |
| Export-Tür: `EchoelStudioView.exportMIDI()` → `exportCombined` | `Studio/EchoelStudioView.swift:4049-4060` |
| MIDI 2.0/UMP: Encoder + `midi2NoteOnMessages` (per-note bend/CC74 als UMP) EXISTIEREN pure+getestet, aber `MIDIOutput` erzeugt die virtuelle Quelle mit `._1_0` → MIDI-2-Wörter gehen nie auf den Draht | `Sync/MPEExpression.swift:59-88`, `Sync/UMPEncoder.swift`, `MIDIOutput.swift:101` |

### Tests heute
`NoteTests`, `NoteOperatorsTests`, `MIDINoteRecorderTests`, `MelodyBarEditTests`, `LaneNotePumpTests`, `MIDIEventParseTests`, `MIDIFileImporterTests`, `RegionNoteWindowTests` — das pure Fundament ist gut abgedeckt; alles Neue folgt demselben Muster (pure core, Linux-CI).

---

## 2. GAP TABLE — Founder-Vision vs. heute

| # | Vision | Heute | Delta |
|---|---|---|---|
| 1 | Velocity-Lane (Ableton-Stil unter dem Grid, drag-to-paint) | Velocity nur einzeln via Inspector-`EchoelValueField` | Lane-UI + pure Paint-Mathematik. Consumer existiert schon (trigger + Export honorieren Velocity) → sofort ehrlich |
| 2 | Aufgenommene BIO/MPE-Expression pro Note sichtbar + editierbar (**USP**) | Bio-Expression wird live GENERIERT (Operators-Depths, MPE-out one-shot), einlaufende MPE-Kurven bei Aufnahme verworfen; kein Kurven-Speicher | Neues `Note.expressionData` (Kurven) + Capture (Recorder-Tee mit Channel-Bindung) + Consumer (MIDI-out-Streaming, später interner Synth) + Lane-UI |
| 3 | Multi-Select + Quantize | Einzelselektion; `quantizedStart` model-only | Selection-Set + pure Batch-Edit-Core + Toolbar |
| 4 | MPE-Zone vollständig / MIDI 2.0 per-note controllers | channelPressure-Input fehlt, Channel→Note-Bindung fehlt, Haupt-Synth konsumiert keine MPE-Dimensionen, Out ist MIDI 1.0, Export ohne Controller-Events | Input-Vervollständigung + per-note Routing + optional `._2_0`-Source (UMP-Encoder liegt fertig da) |

---

## 3. ATOMIC SLICES (Wertreihenfolge, je ≤3 Dateien, Ralph-Wiggum-konform)

### Slice 1 — Velocity-Lane (erster sichtbarer „Station"-Sprung)
**Dateien (3):** NEU `Sequencer/VelocityLaneMath.swift` · `Studio/PianoRollView.swift` · NEU `Tests/EchoelmusicTests/VelocityLaneMathTests.swift`
- **Pure core** `VelocityLaneMath`: gegeben `[Note]`, `stepW`, ein Drag-Sample `(x, y, laneHeight)` → deterministisch `[(noteID, newVelocity)]` (Note(s) deren startStep-Spalte x trifft; y→0…1 invertiert; Mehrfachnoten auf derselben Spalte alle gemeinsam). Plus `barFrames(notes:stepW:laneHeight:)` fürs Rendering. Foundation-only → Linux-CI.
- **UI**: Lane (~64 pt) UNTER dem Grid, **im selben horizontalen ScrollView** wie `canvas` (scrollt mit, teilt `stepW` → Spalten fluchten), eigener `Canvas`-Leaf. Ein Balken pro Note in `rowTint(note.pitch)`; die selektierte Note hervorgehoben. Kein neues Sheet, kein neuer Root-Slot — alles innerhalb `PianoRollView` (präsentiert wie bisher über `ArrangeModal`).
- **Gesten-Arbitrierung (der bekannte Kampf drag-paint vs. Horizontal-Scroll):** v1 = das iOS-native, garantiert konfliktfreie Muster `LongPressGesture(minimumDuration: 0.15).sequenced(before: DragGesture(minimumDistance: 0))` auf der Lane: kurzer Halt „greift" den Stift (leichtes Haptic), dann malt der Drag; ein sofortiger horizontaler Wisch bleibt Scroll. KEIN `.highPriorityGesture`/`simultaneousGesture` gegen den ScrollView (das ist der dokumentierte Freeze-/Fight-Pfad). Tap ohne Halt = Note der Spalte selektieren. Falls Device-Test den Halt als zäh erweist: Fallback ist ein expliziter „Paint"-Toggle-Chip (wie `isSelecting` in `ArrangeTimelineView:61`), der den Drag exklusiv macht.
- **Render-Sicherheit:** Lane liest nur `model.notes` + `selectedID` (edit-frequent, nicht 10 Hz). KEIN Bio-Read. Playhead bleibt wie gehabt.
- **Consumer (bereits vorhanden, nichts lügt):** `trigger` `PianoRollView.swift:582`, `LaneNotePump.swift:107`, Export `MIDIFileExporter.swift:114/238`.
- **Tests:** Paint-Mapping (Spaltentreffer, Clamp 0…1, Mehrfachnoten, leere Spalte = no-op), Determinismus.
- **Persistenz:** keine Schemaänderung (velocity existiert).

### Slice 2 — Multi-Select + Quantize
**Dateien (3):** NEU `Sequencer/NoteSelectionEdit.swift` · `Studio/PianoRollView.swift` · NEU `Tests/.../NoteSelectionEditTests.swift`
- **Pure core** `NoteSelectionEdit`: `quantize(notes:selection:divisionTicks:strength:)` (strength 0…1 = Anteil des Wegs zum Raster; nutzt `Note.quantizedStart`-Mathematik, IDs bleiben erhalten), `nudge(byTicks:)`, `transpose(bySemitones:)` (Pitch-Clamp 0…127), `scaleVelocity(by:)`. Selektion = `Set<UUID>`; leere Selektion ⇒ ganze Bar (DAW-Konvention, dokumentiert).
- **UI**: „Select"-Toggle-Chip in `transport` (Muster `ArrangeTimelineView.isSelecting:61`); im Select-Modus toggelt Tap Noten in die Selektion (Rahmen-Highlight), Inspector wird zum Batch-Inspector: Quantize-Menü (1/16 · 1/8 · Triole 1/8T = `ticksPerQuarter/3`) + Strength als **`EchoelValueField`** (kein Slider — Hard Law) + Delete. `PianoRollModel` bekommt `replaceNotes(_:)`/`apply(edit:)` (gleiche Datei).
- **Achtung Modal-Gesetz:** das Quantize-„Menü" als kompakte Chip-Reihe im Inspector, NICHT als neues Sheet. `.menu`-Picker ist hier ok (Roll-Body liest kein 10-Hz-Observable; Playhead-Read `pattern.currentStep` existiert bereits im Canvas — beim Umbau prüfen, dass die neuen Inspector-Views ihn nicht erben; ggf. Playhead in eigenen Leaf-Struct ziehen, gleiche Datei).
- **Tests:** Quantize-Grenzen (schon am Raster = identisch; strength 0 = identisch, 1 = exakt), Triolen-Division, ID-Erhalt, Selektion-leer-Semantik, Clamps.
- **Persistenz:** keine Schemaänderung.

### Slice 3 — Per-Note-Expression-Kurven (die USP), in 4 Unterschritten

**3a — Datenmodell (pure):** NEU `Sequencer/NoteExpressionCurve.swift` · `Sequencer/Note.swift` · NEU Tests
- `ExpressionPoint { offsetTicks: Int, value: Float }`; `NoteExpressionCurve = [ExpressionPoint]` mit `value(atTick:)` (linear interpoliert, geklemmt, deterministisch); `NoteExpressionData { pressure/timbre/bend: NoteExpressionCurve? }` (bend −1…1, Rest 0…1), Codable.
- `Note.expressionData: NoteExpressionData?` — **decodeIfPresent + encodeIfPresent**, exakt das `operators`-Muster (`Note.swift:159/172`): plain notes bleiben byte-identisch, alte Builds ignorieren den Key, User-Daten werden nie beim Laden gestutzt.
- `MelodyBarEdit.slice/splice` und `NoteSelectionEdit` operieren auf `Note`-Werten → Kurven reisen automatisch mit (Test schreibt das fest).
- **Tests:** Codable-Roundtrip, Legacy-Decode (Kurve fehlt → nil), Interpolation, Clamps.

**3b — Capture (MPE-Input → Kurve):** `Sequencer/MIDINoteRecorder.swift` · `Sync/MIDIBusPublisher.swift` · Tests
- `MIDINoteRecorder` (pure) erhält `controller(kind: .pressure/.timbre/.bend, value:, channel:, atTick:)`; Channel→offene-Note-Bindung (MPE: Member-Channel identifiziert die Note; bei Nicht-MPE: alle offenen Noten). Beim Schließen wird die gesammelte Kurve (offsetTicks relativ zum note-on, dünn ausgedünnt: min. Tick-Abstand + Werte-Delta) als `expressionData` an die `Note` gehängt.
- `MIDIBusPublisher`: Record-Tee erweitert um `onRecordCC/onRecordBend` **mit Channel** (heute wirft `:59-60` ihn weg); RecordController reicht durch.
- **Tests:** Kurven-Zuordnung per Channel, Re-Trigger schneidet Kurve, Ausdünnung deterministisch, Note ohne Controller ⇒ `expressionData == nil` (Byte-Identität).

**3c — Playback-Consumer (Consumer-Proof-Gesetz: jede editierbare Kurve hat einen benannten Abnehmer):** `Studio/PianoRollView.swift` (trigger) · `Audio/MIDIOutput.swift` · Tests (pure Sampler)
- v1-Consumer = **MIDI/MPE-OUT**: `MIDIOutput` kennt den Member-Channel der Note bereits (`allocateChannel:168`); `trigger` sampelt beim note-on die Kurve und **pro Transport-Step** (der existierende `onTick`-Takt, Main-Actor — KEINE Audio-Thread-Berührung) die aktuellen Werte → `sendExpression` auf dem Note-Channel (bend→0xE0, timbre→CC74, pressure→0xD0). Ehrliche v1-Auflösung: Step-Rate (120 Ticks), dokumentiert im UI-Text.
- Interner Synth: gespeicherte pressure/timbre-Kurve → per-Voice-Parameter braucht neue `NoteCommand`-Arten in `PolySynthVoice` (SPSC-Queue existiert, `:305`) — **eigener späterer Slice**, im Plan benannt, bis dahin sagt die Lane-UI ehrlich „→ MIDI Out" als Ziel. Ohne diesen Slice zeigt die Lane KEINE Behauptung, der interne Synth folge der Kurve.
- Bio-Brücke (der eigentliche USP-Moment): beim Live-Take wird die ohnehin berechnete `MPEExpression` (`PianoRollView.swift:560-568`) über denselben Recorder-Pfad in die aufgenommene Note gestempelt — der Körper wird zur editierbaren Kurve. (Teil von 3c oder eigener Mini-Slice, 2 Dateien.)
- **Tests:** Kurven-Sampling pro Step deterministisch; note-off beendet Stream; MPE-off ⇒ no-op.

**3d — Lane-UI (Kurve sichtbar + editierbar):** NEU `Studio/ExpressionLaneView.swift` (Leaf) · `Studio/PianoRollView.swift` · ggf. `Sequencer/AutomationCanvasMath.swift` wiederverwendet (NICHT anfassen wenn reicht — er ist pure + getestet: tap-add/drag-move/double-tap-delete-Mathematik existiert dort schon)
- Unter der Velocity-Lane ein Dimension-Switcher (Press · Timbre · Bend, Chips) + Kurve DER SELEKTIERTEN Note über deren Tick-Spanne; Punkte per tap-add/drag-move/double-tap-delete (AutomationCanvasMath-Muster). Gesten-Arbitrierung identisch Slice 1 (sequenced long-press-drag).
- Farbige Kurven, aber Science-first: Werte-Label (`EchoelValueField` für den selektierten Punkt). Flash-Gesetz irrelevant (statisch). Kein Bio-Live-Read im Body.

### Slice 4 — MPE-Zone / MIDI-2.0-Vollständigkeit
**4a Input komplett (3 Dateien):** `Audio/MIDIEventParse.swift` · `Sync/MIDIBusPublisher.swift` · `Tests/.../MIDIEventParseTests.swift` — channelPressure (0xD0 / UMP 0xD) parsen → `.channelPressure`-ControllerEvent (Kind existiert laut `BioReactiveSynthVoice.swift:244`); Channel bleibt erhalten (Grundlage der 3b-Bindung). Poly-Aftertouch (0xA0) → gleicher Pfad.
**4b Live-MPE → interner Synth (3 Dateien):** `Tools/PolySynthVoice.swift` (+Tests) — neue `NoteCommand`-Kinds `.bend/.pressure/.brightness` per pitch über die existierende lock-free `noteCommands`-Queue (Control→Render-Handoff-Gesetz erfüllt; kein malloc/lock im Render — Kommandostruktur ist POD). Drain-Entscheidung: der EINE Queue-Konsument bleibt `BioReactiveSynthVoice`s Drain-Ort; er leitet note-gebundene Events an `PolySynthVoice` weiter (Main-Actor-Aufruf → enqueue), statt eines zweiten Drains (SPSC = single consumer, Hard Law). Kein Graph-Umbau, attach-before-start unberührt.
**4c Export mit Expression (2 Dateien):** `Sequencer/MIDIFileExporter.swift` + Tests — gespeicherte Kurven als CC74/Bend/ChannelPressure-Events im SMF; optional PPQ-Lift 96→480 (pure, ein Konstanten-Feld + Tests; DAW-Kompatibilität bleibt, VLQ identisch).
**4d MIDI 2.0 out (2 Dateien, Device-Verify nötig):** `Audio/MIDIOutput.swift` + Tests — optionale `._2_0`-Virtual-Source; `MPEExpression.midi2NoteOnMessages` (`MPEExpression.swift:72-88`) + `UMPEncoder` liegen fertig+getestet da; Setting default OFF bis Device-verifiziert. NEEDS-FOUNDER-VERIFY am Gerät/DAW.

---

## 4. HARD-LAW-KONFORMITÄT (Kurzcheck)

- **Sheet-Kette:** NULL neue Root-Sheets. Alles lebt in `PianoRollView` (bereits über `ArrangeModal .lane/.region` präsentiert). Neue Modalität = keine; Quantize/Dimension-Wahl als Chips/Menu inline.
- **10-Hz-Regel:** Lanes lesen nur Edit-State; kein Bio-Read in Roll/Ancestor-Bodies; ggf. Playhead-Read in Leaf isolieren (Slice 2 Randnotiz).
- **Audio-Thread:** Kurven-Sampling auf dem Main-Actor-`onTick` (wie alles Scheduling heute, `PianoRollView.swift:339`); 4b nutzt ausschließlich die existierende SPSC-`NoteCommand`-Queue.
- **EchoelValueField:** alle Zahlen (Vel, Quantize-Strength, Kurvenpunkt-Wert). Keine Slider/Stepper.
- **Persistenz:** `expressionData` via decodeIfPresent/encodeIfPresent (operators-Muster); nichts wird beim Laden gestutzt; Determinismus via vorhandenem SeededRNG/UUID-fold unberührt.
- **Consumer-Proof:** Velocity-Lane → bestehende Consumer benannt; Expression-Kurve → MIDI-out-Streaming (3c) VOR der Lane-UI (3d) — die UI zeigt nie eine Kurve, die niemand abspielt.
- **Rausch-Triade:** unberührt. **DSP/-Regel:** alle neuen pure Cores liegen in `Sequencer/` (nicht `DSP/`).
- **Kein Wellness-Copy;** UI-Text bleibt technisch („Press/Timbre/Bend", „→ MIDI Out").

## 5. REIHENFOLGE / GATES

1 (Velocity-Lane) → Device-Check Gesten → 2 (Select+Quantize) → 3a→3b→3c→3d (je eigener Zyklus, Tests zuerst) → 4a→4b→4c → 4d (Founder-/Device-Gate).
Jeder Slice einzeln shippbar; Abbruch nach jedem Slice hinterlässt keinen lügenden Zustand.
