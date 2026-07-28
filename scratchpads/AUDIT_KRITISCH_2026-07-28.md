# Kritischer Produkt-Audit Echoelmusic — 2026-07-28

**Auftrag (Founder):** „Suche nach potentiellen Errors, issues, Crashs, Löchern und Fehlern.
Performance, Resourcen Management, Qualität optimieren. Sei Kritisch mit dem Produkt
Echoelmusic und mache Verbesserungsvorschläge."

**Methode:** fünf parallele Fach-Audits (Crash/Stabilität · Performance · Ressourcen ·
Bio/Sensorik · Produkt-Ehrlichkeit), danach eine adversariale Nachprüfung jedes Befundes
gegen den echten Quelltext. **Nur Befunde, die ich selbst am Code mit `datei:zeile` belegt
habe, stehen hier.** Was ein Agent behauptet und ich nicht verifizieren konnte, ist unten
im Abschnitt „Nicht bestätigt" — mit Absicht sichtbar und nicht weggelassen.

**Was dieser Audit NICHT kann:** kompilieren (keine lokale Toolchain — CI ist der einzige
Compiler), Klang beurteilen, Gerät beobachten. Jeder Befund unten ist *statisch* belegt.
Wo ein Geräte-Verify nötig ist, steht es dabei.

---

## Die Rangfolge

Sortiert nach **(Schaden × Eintrittswahrscheinlichkeit) ÷ Reparaturkosten**, nicht nach
technischer Eleganz. P0 = ein Nutzer verliert Klang, Arbeit oder Vertrauen, ohne etwas
falsch gemacht zu haben.

### P0 — trifft echte Nutzer, still, ohne Ausweg

| # | Befund | Beleg | Slice |
|---|--------|-------|-------|
| 1 | **Audio-Interruption verstummte das Instrument bis zum Neustart** ✅ GESHIPPT `2f57efd` | s.u. | erledigt |
| 2 | **Kamera-Stopp kann abstürzen (EXC_BAD_ACCESS)** | `CameraCapture.swift:518` + `:547`, `CameraRPPGBioPublisher.swift:1164-1165` | 1 Datei |
| 3 | **Zweiter Start einer frischen Installation zeigt fälschlich „Safe Mode"** | `LaunchGuard.swift:46-54`, `EchoelmusicApp.swift:304-308` + `:976` | 1 Zeile |

**#2 im Detail.** `CameraCapture.stop()` ist **asynchron** — sie schiebt den Teardown auf
`sessionQueue` und kehrt sofort zurück (`CameraCapture.swift:518-533`). Der Aufrufer
`CameraRPPGBioPublisher.stop()` setzt danach `capture.onFrame = nil`
(`CameraRPPGBioPublisher.swift:1165`) — auf dem MainActor, während auf der Video-Queue
noch `onFrame?(pixelBuffer)` (`CameraCapture.swift:547`) laufen kann. `onFrame` ist
`nonisolated(unsafe)` (`:18`); Laden-und-Aufrufen eines Optional-Closures ist nicht atomar.
Die Freigabe des Closure-Kontexts unter dem laufenden Aufruf ist ein klassischer
Use-after-free. Auslöser ist die häufigste Bio-Geste überhaupt: Pulse-Pille aus.
**Fix:** dieselbe Form, die im selben File schon bewiesen funktioniert — ein
`NSLock`-geschützter Halter wie `RGBSampleQueue`, oder minimal: `onFrame = nil` **vor**
`capture.stop()` ziehen und in `captureOutput` den Closure einmal in eine lokale Variable
laden. Die Reihenfolge allein schließt das Fenster nicht ganz; sie verkleinert es. Der
Lock schließt es.

**#3 im Detail.** `LaunchGuard.beginLaunch()` zählt jeden Start hoch (`:46`), und
`confirmHealthy()` — das einzige, was zurücksetzt — hängt am `.task` von `mainContent`
(`EchoelmusicApp.swift:976`). Bei `hasCompletedOnboarding == false` wird `mainContent`
**nie gebaut** (`:304-308`); es läuft `OnboardingView`. Ein neuer Nutzer, der das
Onboarding nicht in einem Zug durchklickt (Anruf, weggewischt, vom System beendet), hat
beim **zweiten** Start Zähler = 2 = Schwelle → Crash-Recovery-Bildschirm, ohne dass je
etwas abgestürzt ist. Das ist der erste Eindruck des Produkts.
**Fix:** `LaunchGuard.confirmHealthy()` in `OnboardingView.onAppear` — dass das Onboarding
rendert, IST der Beweis, dass der Start überlebt hat.

### P1 — lügende Controls und stille Datenverluste

| # | Befund | Beleg |
|---|--------|-------|
| 4 | **Fehlgeschlagener WAV-Export sagt nichts** — `busyStatusLabel` mappt `.failed` in den `default:`-Zweig, also auf den leeren String | `EchoelStudioView.swift:3555-3561` |
| 5 | **ADM-OSC-Objekt-Gain ist strukturell auf 0,3 festgenagelt** (−10,5 dB) | `ADMOSCSender.swift:231` |
| 6 | **`/echoelmusic/bio/motion` wird gesendet und ist immer 0** | `OSCSender.swift:258`; alle 6 Publisher schreiben `motionEnergy: 0` |
| 7 | **„Donuts"-Pille im Synth-Reiter ist antippbar und wirkungslos** | `FloatingVisualWindow` liest den `spectralDonuts`-Key nie |

**#5 ist der schärfste der vier und war bisher nirgends notiert.** `admMessages` leitet den
Objekt-Gain aus `0.3 + motionEnergy * 0.7` ab. Da `motionEnergy` in **jedem** Publisher
hart 0 ist (`BioSimulator:85`, `CameraRPPGBioPublisher:896,944`, `FaceExpressionBioPublisher:157`,
`HealthKitBioPublisher:139`, `PolarH10BioPublisher:208`), ist der Gain in **jeder möglichen
Konfiguration** exakt 0,3. Wer Echoel als immersive Objektquelle in einen Renderer hängt —
genau die Positionierung aus der Strategie — bekommt ein um 10 dB abgesenktes Objekt und
sieht keinen Grund dafür. Das ist ein Pro-Interop-Defekt, kein Schönheitsfehler.
**Fix (ehrlich statt tot):** solange es keinen Bewegungssensor gibt, Gain auf `1.0`
konstant senden und die Ableitung erst mit einem echten CoreMotion-Produzenten
zurückholen. Für #6 dieselbe Regel: einen strukturell konstanten Kanal **nicht** senden,
statt ihn zu bewerben.

### P2 — Performance und Ressourcen (messbar, kein Nutzerschaden heute)

| # | Befund | Beleg | Kosten |
|---|--------|-------|--------|
| 8 | `ProfessionalLogger` hält **10 000** Einträge im RAM | `ProfessionalLogger.swift:239-240,295-297` | `LogEntry` = UUID + Date + 4 Strings + Dictionary → mehrere MB, dauerhaft |
| 9 | `RetroCapture` allokiert **11,5 MB im `init`**, nicht beim ersten Gebrauch | `RetroCapture.swift:40,86-91` | 48 000 × 30 s × 2 ch × 4 B = 11 520 000 B — **5,8 % des 200-MB-Budgets**, immer, auch wenn nie aufgenommen wird |
| 10 | `mediaServicesWereReset` lief über den Interruption-Pfad und ließ **den RetroCapture-Tap fallen** | `AudioConfiguration.swift` `handleMediaServicesReset`; `AudioEngine.swift` `onInterruptionResume` | selten, aber dann stiller Datenverlust |

**#10 — KORRIGIERT 2026-07-28 beim Bauen, meine erste Fassung war überzogen.** Sie lautete:
„`prepareGraph()` steigt bei `graphPrepared == true` aus, also kann der Neuaufbau, den
dieser Fall braucht, nicht stattfinden." Das klingt zwingend und hält der näheren Lektüre
nicht stand: `masterEngine` ist ein `let AVAudioEngine()`, ein echtes Neu-Erzeugen ist gar
nicht möglich, und `AudioEngine.start()` ruft ohnehin `prepare()` + `start()`, worauf
AVAudioEngine seinen internen Graphen selbst wieder aufbaut. Ich hätte auf dieser Grundlage
einen spekulativen Umbau eines Wiederherstellungspfads geschrieben, den weder CI noch ich
auslösen können — die teuerste Sorte Fix.

**Was übrig blieb:** der Reset-Handler rief `onInterruptionResume`, und diese Closure macht
ein nacktes `masterEngine.start()` — nicht `AudioEngine.start()`. Für eine Unterbrechung ist
das richtig (der Graph ist gültig, nur pausiert). Für einen Reset nicht, weil er die Objekte
entwertet, auf denen die **Taps** sitzen, und `retroCapture.install(on:)` nur im vollen
`start()`-Pfad läuft. Folge: der 30-s-Vorlaufring füllt sich still nicht mehr, „letzten Loop
behalten" liefert Stille. Kein Absturz, keine Meldung.

**Zweite Korrektur, aus dem Review desselben Commits — ich hatte schon wieder zu viel
behauptet.** Zwei der drei genannten Auslassungen sind wirkungslos: `prepareForRecording`
weist nur `self.engine = engine` zu (auf ein `let`, also ein No-op), und der Meter-Timer wird
ausschließlich in `stop()` invalidiert, lief also weiter. **Und der Tap-Verlust war unter dem
ALTEN Code vermutlich gar nicht offen:** der Configuration-Change-Watchdog nennt
„media-services rebuild" selbst als Auslöser und ruft `retroCapture.install`. Er griff, weil
`onInterruptionResume` `isRunning = true` setzte. Mein erster Entwurf setzte `isRunning =
false` — und hätte damit genau diesen Auffangnetz-Pfad **entfernt**, während der Commit
behauptete, ihn zu reparieren.

**Und die eigene Prämisse traf mehr, als der Fix abdeckte:** wenn ein Reset Taps entwertet,
dann auch den **Meter-Tap** — und der ist nicht nur Pegelanzeige, sondern der EINZIGE
Schreiber von `_outputRing`, das das immersive FFT-Visual speist (Ship-Gate 4). Er hing in
`setupMasterEngine` hinter derselben Einweg-Sperre. Ein Fix, der den Vorlaufring rettet und
das Visual tot lässt, hätte seine eigene Commit-Nachricht erfüllt und nicht den Nutzer.

**Geshippt** (`f9e5d76` + Nachbesserung): eigener `onMediaServicesReset`-Hook →
`recoverEngine`, `wasInterrupted = true` (sonst ist der Motor „nicht laufend, nicht degraded,
nicht unterbrochen" = unrettbar), `recoveryAttempts = 0` (ein Reset ist ein neuer Fehler,
keine Fortsetzung einer Kabel-Wackel-Serie), und `installMeterTap()` als re-installierbare
Methode, aufgerufen aus `start()`. **Nur compile-verifiziert** — einen Media-Services-Reset
kann ich hier nicht auslösen, und ob Taps ihn überleben, ist Schlussfolgerung aus Apples
„orphaned objects"-Leitlinie, keine Messung.

### P3 — Struktur, nicht Symptom

- **#11 `tanf` pro Sample bleibt möglich**, wenn ein zukünftiger Aufrufer den Cutoff pro
  Sample schreibt. Der Schutz ist heute die Gleichheitsprüfung in `EchoelSVFilter`
  (`:42`, `:112`) plus die Block-Rate-Disziplin von `ParamGlide` — beides Konvention, kein
  Mechanismus. Kein Handlungsbedarf, aber ein Kommentar-Vertrag, der brechen kann.
- **#12 Doctor-Sektion A bleibt der wichtigste offene Struktur-Befund** (#208/#210): das
  blockierende Test-Bundle baut aus `Tests/CISmoke`, die 311 Dateien laufen non-blocking.
  Solange das so ist, beweist „Gates grün" weniger, als es aussieht. Founder-gated.

---

## Was ich NICHT bestätigen konnte (bewusst sichtbar)

- **60-Hz-Meter-Timer**, der angeblich beim Scrollen stehenbleibt: die im Bericht genannte
  `Timer.scheduledTimer`-Stelle existiert in `EchoelStudioView.swift`/`EchoelmusicApp.swift`
  **nicht**. Entweder längst umgebaut oder der Agent hat sie erfunden. Nicht handeln,
  bevor die Stelle jemand zeigt.
- **`vvsinf`/`vDSP_dotpr` pro Sample**: ohne Instruments am Gerät ist jede Aussage dazu
  geraten. Ein Profil vor jeder Optimierung — sonst optimiert man das Falsche schnell.

## Der Vorschlag zur Reihenfolge

1. ✅ **#1 Audio-Interruption** — geshippt (`2f57efd`), Geräte-Verify offen.
2. **#10 Media-Services-Reset** — dieselbe Datei, dieselbe Klasse, ein Slice.
3. **#2 Kamera-Race** — der einzige echte Absturz in der Liste.
4. **#3 falscher Safe Mode** — eine Zeile, trifft jeden neuen Nutzer.
5. **#5 + #6 ADM-OSC/Motion-Ehrlichkeit** — ein Slice, weil derselbe Nullkanal.
6. **#4 stiller Export-Fehler** — ein Slice.
7. **#8 + #9 Ressourcen** — ein Slice, rein mechanisch.
8. **#7 Donuts-Pille** — entweder verdrahten oder entfernen; kein Mittelweg.

Danach ist die Liste abgearbeitet und der nächste Audit sollte **am Gerät** stattfinden,
nicht im Quelltext: was hier statisch findbar war, ist damit gefunden.
