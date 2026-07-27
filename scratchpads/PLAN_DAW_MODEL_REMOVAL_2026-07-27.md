# PLAN — #132 Slice 5: DAW-Modell-Entfernung (pure-instrument epic #121)

Stand 2026-07-27, nach dem ▶-Fix (`73c8e97`) und Deploy v10.79.353 (Build 2470).
Founder-Ansage: „Der ganze DAW Quatsch der nicht funktioniert hat soll erstmal raus."

---

## 0. Der Befund, der den Plan überhaupt nötig macht

„Das DAW-Modell" ist **nicht eine Sache.** Der Reference-Graph zeigt zwei ineinander
verhakte Hälften, und wer sie als eine behandelt, reißt entweder zu wenig oder das
Instrument mit ab:

**A — ARRANGEMENT / REGION / CLIP-WIEDERGABE (reines DAW, heute komplett tot).**
`TimelineRegion` · `AudioClipRegion` · `TimelineRegionPlayer`s Abspiel-Hälfte ·
`AudioLanePlayer` · `TimelineAudioSink` · `ClipLaunchEngine` · `LaunchQuantizer` ·
`ArrangementPlayer` · `ArrangementStore` · `AudioClipPlayer` · `AudioClipFactory` ·
`AudioRegionPlayback` · `WarpedClipPlan` · `StretchPlan` · `TimelineScheduling` ·
`TimelineDragMath`.
Seit `73c8e97` hat `TimelineRegionPlayer.play(document:)` **null Produktionsaufrufer**,
und `transportStep` beginnt mit `guard isPlaying` — die gesamte Schicht ist unerreichbar.

**B — DAS SPUR-/LANE-MODELL (nicht DAW, sondern Instrument-Struktur).**
`TimelineLane` · `TimelineDocument.lanes` · `LaneComposerInput` · `TrackInstrument` ·
`SpatialSceneStore` · `ImmersiveStageView` · `ParameterApplyRouter` ·
`PerTrackAutomationResolver`.

**DER TRAGENDE BELEG, korrigiert nach Review — hier genau lesen, sonst prüft die nächste
Session das Falsche:** B bleibt wegen `LaneComposerInput.composeLaneOverrides`, aufgerufen
aus `applyLaneOverrides(input:)` auf dem **Generate-Pfad** (`EchoelStudioView.swift:4119`),
das `doc.lanes` liest. **Das ist die einzige LAUFZEIT-Kante.**
Die erste Fassung dieses Absatzes begründete B mit
`SpatialSceneStore.rebuild(from: [TimelineLane])` — das ist eine **Compile-Kante, keine
Laufzeit-Kante**: ihre beiden Aufrufer liegen in `ImmersiveStageView`, und die View hat
repo-weit NULL Instanziierungen (CLAUDE.md: „stays doorless — deliberately", Ship-Gate 4).
`SpatialSceneStore` wird heute nie aus Spuren neu aufgebaut. Wer B über die Bühne
„verifiziert", findet eine türlose View und schließt daraus entweder fälschlich auf Leben
oder verweigert eine korrekte Löschung.

**C — DER STIMMEN-RACK IN DER MITTE, und das ist die unangenehme Erkenntnis.**
`LaneVoiceRack` wird im LIVE-Studio angehängt, gestartet, mit Insert-FX und Stimmung
versorgt (`EchoelmusicApp.swift:488/492/615`, `EchoelStudioView` an 6 Stellen) — aber
seine **Noten** kamen ausschließlich aus dem Fan-Out. `LaneVoiceRack.noteOn` hat GENAU
EINEN Aufrufer (`EchoelmusicApp.swift:627`, im `slotNoteSink`-Closure), und jede
Feuerstelle dieses Sinks liegt hinter `guard isPlaying`.
**Präzise, weil „tot" hier zu grob wäre: notenlos ≠ ungefüttert** — `feedBio`
(`LaneVoiceRack.swift:473` ← `EchoelmusicApp.swift:612`) läuft weiter pro Tick. Wer das
Rack anfasst, muss diese Kante mitzählen. Der Fan-Out selbst liegt hinter `guard isPlaying`
liegt. Das Rack ist damit heute eine Menge allozierter Stimmen, die **nie eine Note
bekommen**. Kein Regress durch den ▶-Fix (sie klangen vorher auch nur während
Arrangement-Wiedergabe), aber eine lügende Struktur: Insert-FX und Stimmung werden an
Stimmen geschickt, die stumm bleiben.

**Größe:** ~7.000 Zeilen über 24 Dateien. Ein Commit wäre ein Blind-Schnitt ohne lokalen
Compiler — genau das, was der Ralph-Takt verbietet.

---

## 1. Council

**Frage:** In welcher Reihenfolge, und wo hört „erstmal raus" auf, reversibel zu sein?

· **Architect:** A ist ein sauberer Schnitt entlang einer bereits toten Grenze — der
  Reference-Graph zeigt keine Kante von A nach B, die nicht über `TimelineDocument` läuft.
  B anzufassen heißt, den Immersive-Stage-Pfad und die Pro-Spur-Komposition zu berühren:
  eigenes Thema, eigener Founder-Entscheid.
· **Skeptic:** Der teuerste Fehler wäre, C stillschweigend mitzunehmen. „Sekundäre
  MIDI-Spuren gibt es nicht mehr" ist eine **Produktentscheidung**, keine Aufräumarbeit —
  und „erstmal" im Founder-Satz signalisiert Rückholbarkeit, die 15 gelöschte Dateien
  nicht haben.
· **Shipper:** A zerfällt in vier Scheiben, die je einzeln grün gehen können. Die erste
  (Clip-Launch) ist vollständig selbstenthalten und beweist die Methode.
· **User-Advocate:** Der Founder hat den Bug in **einer** Sache gesehen: ▶ spielte einen
  Import. Das ist geheilt und ausgeliefert. Alles Weitere ist Hygiene, die ihn nicht
  blockiert — also ohne Eile, dafür ohne Kollateralschaden.

**→ Verdikt: A in vier Scheiben, streng behavior-neutral. B bleibt. C wird BENANNT, nicht
entschieden — die Frage geht erst an den Founder, wenn A durch ist und sie beantwortbar
formuliert werden kann.** Gate: proceed für 5a.

---

## 2. Die Scheiben

### 5a — Clip-Launch-Schicht (DIESER ZYKLUS) — SCOPE BEIM BAUEN KORRIGIERT

**Ursprünglich geplant** war, hier auch `ClipLaunchEngine` mitzunehmen. Beim Nachsehen im
Code: **falsch.** Die Launch-Schicht ist mit ~40 Stellen quer durch
`TimelineRegionPlayer` gewebt (`launch.removeAll()` in vier Transport-Pfaden,
`applyLaunchTransitions`, `reapplyLaunched`, Prune-Logik im Struktur-Refresh, Phasen-Faltung
beim Song-Loop-Wrap). Das herauszuoperieren wäre Chirurgie an einer 1011-Zeilen-Datei, die
in 5c ohnehin ganz stirbt — Aufwand und Risiko für null Gewinn.
**Notiert, statt still korrigiert**, weil der nächste Leser sonst denkt, `ClipLaunchEngine`
sei vergessen worden.

**Tatsächlich in 5a gelöscht** — nur was NULL Verflechtung hat:
`Sequencer/LaunchQuantizer.swift` (die alte Einzel-Slot-Klasse; keine Referenz außerhalb
der eigenen Datei) · `Studio/ClipLaunchGlyph.swift` (nirgends instanziiert, die Fläche ging
mit Slice 4) · `Tests/…/LaunchQuantizerTests.swift` · `PlayCause.launchQuantized`.
**`ClipLaunchEngine` bleibt und geht mit 5c**, zusammen mit seinem Test.

**Warum `.launchQuantized` mit muss und `.timelineRegion` nicht:** beide sind jetzt
unerreichbar, aber `.launchQuantized`s einziger möglicher Schreiber ist eine gelöschte
Klasse. Ein unerreichbarer Fall, dessen Typ noch existiert, dokumentiert einen ruhenden
Pfad; einer, dessen Typ weg ist, lügt.
**Risiko:** `PlayCause` ist `CaseIterable`, und ein Test zählt `allCases.count` gegen seine
gepinnte Tabelle — beide Stellen mitgeändert. **Kein** Verhalten ändert sich.

### 5b — Audio-Region-Wiedergabe
`AudioLanePlayer` · `TimelineAudioSink` · `AudioClipPlayer` · `AudioRegionPlayback` ·
`AudioClipFactory` · `WarpedClipPlan` · `StretchPlan` · `StretchMode`.
**KANTEN NACH DRAUSSEN — nach Review korrigiert, die erste Fassung schickte die Scheibe in
die falsche Richtung.** Sie nannte `DSP/AudioOutputGuard.swift` und
`Audio/AudioOutputGuard+PCMBuffer.swift` als Referenzen auf `TimelineAudioSink`. Beide sind
**`///`-Prosa, kein Code** — dort ist nichts zu trennen. Die eine echte
Produktions-Konstruktionsstelle fehlte dagegen:
· **`EchoelmusicApp.swift:765`** — `makeSink: { TimelineAudioSink(engine: audioEngine) }`,
  genau die Fabrik, die den zu löschenden `AudioLanePlayer` baut. **Da fängt 5b an.**
· `BeatPlayer.auditionSink` (`BeatPlayer.swift:140/150/151/158`) ist echter Code, muss aber
  NICHT erhalten werden: `BeatPlayer.swift:68` sagt selbst, dass `audition(url:)` und die
  Region-Audition keinen Produktionsaufrufer haben. 5b kann den Audition-Pfad mitnehmen.
· **Nicht einfach mitlöschen:** `DSP/AudioOutputGuard.swift:63-68` dokumentiert eine LEBENDE
  NaN/inf-Lücke über `TimelineAudioSink.scheduleSegment`. Stirbt der Typ, muss dieser Absatz
  UMGESCHRIEBEN werden, nicht gestrichen — die Lücke gilt auch für die überlebende
  `BeatPlayer`-Region-Audition.
**Lehre für diesen ganzen Plan:** eine Referenzliste, die per `grep` entstanden ist, zählt
Kommentare als Kanten und übersieht Aufrufe in Closures. Vor jeder Scheibe: Treffer als
Code-oder-Prosa klassifizieren.

### 5c — Region-/Arrangement-Wiedergabe
`TimelineRegionPlayer`s Abspiel-Hälfte · `ArrangementPlayer` · `ArrangementStore` ·
`Arrangement` · `TimelineScheduling` · `TimelineRegion` · `AudioClipRegion` ·
`TimelineDragMath`.
Das ist die größte Scheibe und die einzige, die `MultiRollFanout` berührt — deshalb ist
sie die letzte VOR der C-Frage, nicht die erste.

### 5d — `Clip` / `ClipStore` / `MediaLibrary`
Zuletzt, und **größer als die erste Fassung dieses Absatzes behauptete.** Sie nannte
`CloudSync`, `AppGroupStore` und `RecordController` — von den dreien ist nur
`RecordController` echter Code (`RecordController.swift:35/62`); die beiden anderen sind
`///`-Prosa (`CloudSync.swift:75`, `AppGroupStore.swift:117`). Dafür fehlten ~10 Dateien mit
echtem `ClipStore`-Code, darunter `EchoelmusicApp.swift:767-769` (die `resolveURL`-Closure),
`TimelineStore`, `TakeRecorder`, `ClipAutomationEdit`, `EchoelStudioView`, `WorkspaceView`.
Vor dem Start dieser Scheibe also erst die Liste neu erheben, Code von Prosa getrennt.
`MediaLibrary` überlebt vermutlich (Datei-Auflösung), das entscheidet der Graph zu dem
Zeitpunkt, nicht dieser Plan.

### DANACH, NICHT VORHER — die C-Frage an den Founder
„Sekundäre MIDI-Spuren erzeugen heute keinen Ton mehr. Sollen sie wiederkommen (dann
brauchen sie eine eigene Notenquelle) oder weg (dann fallen `LaneVoiceRack`,
`MultiRollFanout`, `LaneVoicePool`, `LaneNotePump`, `KindVoiceAllocator`)?"
Erst nach 5c ist das eine Ja/Nein-Frage statt einer Vermutung.

---

## 3. Was dieser Plan bewusst NICHT tut

- **Keine Nutzerdaten löschen.** Das gespeicherte Arrangement bleibt auf dem Gerät, bis
  das Modell entfällt und es schlicht nicht mehr geladen wird. Ein stiller Löschlauf über
  unsichtbare Daten ist unumkehrbar; das wäre dieselbe Übergriffigkeit wie der Bug.
- **B nicht anfassen.** Der Immersive-Stage-Pfad hängt an `TimelineLane`.
- **Nicht auf „es kompiliert schon" wetten.** Kein lokaler Swift-Compiler; jede Scheibe
  geht einzeln durch beide Gates, bevor die nächste beginnt.

## 4. Testlage, ehrlich

Für Löschungen gibt es keine positiven Tests — der Nachweis ist der Reference-Graph plus
das grüne Gate. Wo eine gelöschte Datei eine Testdatei hatte, geht die Testdatei mit; das
ist keine gesunkene Abdeckung, sondern gestrichener Gegenstand. Was **bleiben** muss:
jeder Test, der eine Instrumenten-Eigenschaft pinnt, die zufällig durch eine DAW-Datei
lief — beim Löschen einer Testdatei ist deshalb zu prüfen, ob sie ausschließlich den
gelöschten Typ prüft.
