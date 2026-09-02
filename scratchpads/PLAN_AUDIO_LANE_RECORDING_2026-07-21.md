# PLAN — wire real audio-lane recording (task #13, CLIP-2 follow-through)

> ⛔ **SCOPE NOTE (audit 2026-09-02): this plan predates the product definition of 2026-07-25**
> (`docs/dev/PRODUCT_DEFINITION.md`, Editor ≠ Workstation). Where it names timeline / clips /
> arrangement / multitrack / lanes-as-tracks / AUv3 / broadcast / drums / piano-roll surfaces, those
> are CUT and that part is history — do not execute it. Nothing below was edited; check the
> definition before building from any line here.


## Befund (investigiert 2026-07-21, während DMMW-Ultraprogramm-Sichtung)

`HEALING_DMMW_2026-07-15.md` listet CLIP-2 als CRITICAL: "Record-arm auf Audio/Video-Lane
nimmt STILL nichts auf." Direkter Code-Read zeigt: das ist **bereits ehrlich behoben**, nicht
mehr ein stiller Bug —

- `RecordSource.captureImplemented` (`TrackInstrument.swift:144-146`) ist NUR für
  `.midiInput`/`.bio` `true`. `RecordPlan.targets(in:)` (`RecordAnchor.swift:82-89`) filtert
  darüber — eine geamte Audio-Spur zählt heute NICHT als Record-Target. Der Kommentar dort
  (Zeile 78-79) dokumentiert das explizit als den CLIP-2-Fix: kein stiller Leer-Take mehr.
- Das UI gated den Arm-Button separat über `lane.recordSource.canRecord`
  (`ArrangeTimelineView.swift:1174`) — die Spur lässt sich ARMEN (UI reagiert), aber ein Take
  erzeugt für sie schlicht nichts, ohne Fehler/Crash. Ehrlich, aber das Feature fehlt real.

**Was WIRKLICH fehlt (real, nicht kosmetisch):** `TakeRecorder.captureAudio(laneID:mediaRef:
durationSeconds:)` existiert und ist voll implementiert (`TakeRecorder.swift:106-109`,
`finish()` committet sie sauber als `AudioClipFactory.clip`) — aber **niemand ruft sie auf**
(`grep captureAudio(` findet nur die eigene Definition). `RecordController` hat Hooks für
MIDI (`recordNoteOn/Off`) und Bio (`captureBio` im Step-Poll), aber KEINEN Hook für Audio.

**Der fehlende Baustein existiert bereits, unbenutzt:** `MultiTrackRecorder`
(`Audio/MultiTrackRecorder.swift`) ist ein voll gebauter, audio-thread-sicherer Mic→.caf-
Recorder (RetroCapture-Pattern: raw-pointer-Tap, kein `self` im Callback, Session-Upgrade auf
`.playAndRecord`/Downgrade danach, Latenz-Kompensation via `LatencyCompensation.current()`).
Er ist bereits am Engine verdrahtet (`AudioEngine.swift:125,499` —
`multiTrackRecorder.prepareForRecording(engine: masterEngine)`), aber **niemand ruft
`startRecording()`/`stopRecording()`** (nur `.isRecording` wird an zwei Stellen in
`EchoelmusicApp.swift` GELESEN, nie geschrieben). Ein zweiter kompletter "gebaut-aber-
abgeschaltet"-Fund wie #66, diesmal in der Audio-Aufnahme.

## Warum kein Blind-Bau diesen Zyklus

Das Verdrahten selbst berührt: Session-Kategorie-Wechsel (`.playback`→`.playAndRecord`) MIT
laufender Kamera/rPPG (Route-Resilienz-Gefahrenzone, `avaudio-route-resilience`-Skill-Domäne),
einen async `stopRecording()` aus einem synchronen Transport-Stop-Callback
(`RecordController.commitOnStop()` ist nicht `async`), fehlende Dauer-Messung
(`MultiTrackRecorder.stopRecording()` liefert nur `[URL]`, keine Sekunden — `recordingSeconds`
müsste am Stop-Zeitpunkt gelesen werden, BEVOR sie zurückgesetzt wird), und
Latenz-Kompensation beim Platzieren der Region (`lastCompensation` existiert, wird aber von
niemandem in eine Tick-Korrektur übersetzt). Jeder dieser Punkte ist on-device nur wirklich zu
verifizieren (Bluetooth-Headset-Timing, Kamera+Mic-Koexistenz, tatsächliche Sync-Genauigkeit
zum Beat) — exakt das Muster, das Automation-S2 zu Recht "device-gated" gemacht hat.

## Slices (nächste Zyklen, jeweils mit Pflicht-Reviewer audio-thread-reviewer)

- **S1 — RecordController-Audio-Hook (pure Wiring, testbar ohne Gerät):** `RecordController`
  bekommt eine schwache Referenz auf einen Recorder-Protokoll (`AudioTakeRecording`: `func
  startRecording()`, `func stopRecording() async -> (url: URL, seconds: Double)?`) statt direkt
  `MultiTrackRecorder` zu importieren (hält `RecordController` weiterhin Engine-frei/portabel,
  wie der Datei-Header verlangt). `onStep` startet ihn, sobald ein `.audioInput`-Target im
  Plan auftaucht; `commitOnStop` wird `async` (Transport-Stop-Subscriber muss das erlauben —
  ERST prüfen, ob `addStopSubscriber` einen async Closure akzeptiert oder umgebaut werden muss).
- **S2 — Dauer + Latenz:** `MultiTrackRecorder.stopRecording()` um eine Sekunden-Angabe
  erweitern (das `recordingSeconds`-Feld existiert schon, nur nicht im Rückgabewert) und
  `lastCompensation` in eine Tick-Korrektur am Take-Start (`RecordAnchor`) einspeisen, damit die
  aufgenommene Region beat-genau sitzt (Bluetooth ≈150-250ms sonst hörbar versetzt).
- **S3 — Gate umlegen + Device-Verify:** `captureImplemented` um `.audioInput` erweitern (EINE
  Zeile, aber NUR nachdem S1/S2 gegen ein echtes Gerät verifiziert sind — Mic-Permission-Flow,
  Kamera+Mic gleichzeitig, Kopfhörer-Routen, tatsächliche Sync-Genauigkeit). Das ist der
  Moment, in dem der Arm-Button für Audio-Spuren erstmals wirklich etwas aufnimmt.

## Council (kompakt)
- **Architect:** `MultiTrackRecorder` wiederverwenden statt neu bauen — koppelt nichts Neues,
  der Recorder ist bereits Engine-verdrahtet. Concern: `RecordController` muss Engine-frei
  bleiben (Datei-Header-Gesetz) → Protokoll-Abstraktion, kein direkter Import.
- **DSP/Audio-Thread Purist:** Tap-Pattern von `MultiTrackRecorder` ist bereits korrekt
  (raw-pointer, kein `self`, kein Alloc im Callback) — S1/S2 selbst berühren den Render-Pfad
  nicht, nur Start/Stop-Steuerung. Trotzdem Pflicht-Review, weil Session-Kategorie-Wechsel
  während laufender Kamera ein bekanntes Bruchmuster ist.
- **Skeptic:** der teuerste Fehler wäre, S3 (Gate umlegen) VOR echtem Geräte-Test zu ziehen —
  dann bekäme der Founder eine UI, die verspricht aufzunehmen, aber schlecht synchronisiert
  oder beim Kamera+Mic-Konflikt abstürzt. Reihenfolge strikt S1→S2→S3, S3 nur nach Verify.
- **Shipper:** S1 ist so geschnitten, dass sie ohne Gerät baubar + testbar ist (Protokoll-Mock);
  S2 teils pure (Latenz-Mathe), teils Geräte-Verify; S3 ist der einzige User-sichtbare Schritt
  und bewusst zuletzt.
- **User-Advocate:** heute ist der Zustand ehrlich (Arm-Button tut sichtbar nichts Schlimmes),
  aber unvollständig — das ist die richtige Founder-Erwartung "kann ich meine Stimme über den
  Beat aufnehmen?" und verdient, fertig gebaut zu werden.

→ **Gate: proceed mit S1 im nächsten Zyklus** (reines Wiring + Test, kein Geräte-Risiko).
S2/S3 bleiben je ein eigener, geräte-gegateter Zyklus.

## S1 — SHIPPED (2026-07-21, commit b1a38b9)

RecordController.AudioTakeRecording hook wired, FeatureFlags.audioLaneRecording default OFF.
audio-thread-reviewer: PASS-WITH-NOTES — found + fixed a real re-entrancy race (overlapping
Transport.stop() could drop a mic take mid-async-finish); guard + regression test added before
push. CI green (Xcode Compile Check + Echoelmusic CI/CD Pipeline, run 29857396468 et al.).

S2 (duration/latency correctness) and S3 (device-verified captureImplemented flip) remain
device-gated, each its own future cycle. Nothing further to do on this plan until a device run.
