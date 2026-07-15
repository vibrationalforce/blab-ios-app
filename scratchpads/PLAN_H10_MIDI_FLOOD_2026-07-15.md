# PLAN H10 — MIDI-Eingangs-Flut (#30) — Audit-Befund + Fix-Design (2026-07-15)

## Befund (read-only Audit, Sources/Echoelmusic/Audio/MIDIInput.swift)

1. **Task-per-Event-Flut:** `handleMIDIEvents` (nonisolated, CoreMIDI-Thread)
   spawnt pro Event ein `Task { @MainActor }` (Zeilen 130/136/141/145/150/165/
   172/178/183). Dichter MPE-Stream (PitchBend pro Finger ~100 Hz × Dimensionen)
   flutet den Main-Executor — exakt die 10.76.48-Krankheit (Kamera-Freeze).
2. **`Mirror(reflecting: packet.words)` PRO PAKET** (Zeile 113) auf dem
   CoreMIDI-Empfangsthread — Reflection + Array-Allokation auf einem
   realtime-nahen Thread. Schlimmer als die Task-Flut.
3. **Reihenfolge-Hazard (Korrektheit!):** separate unstrukturierte Tasks sind
   NICHT FIFO-garantiert — ein noteOff-Task kann vor seinem noteOn-Task laufen
   → hängende Note unter Last.
4. Nebenbefund: `lastNote/lastVelocity` (@Observable) werden pro Event
   geschrieben → View-Churn mit Event-Rate, wo ein Batch reicht.

## Fix-Design (RGBSampleQueue-Muster 10.76.48, MIDI-angepasst)

- **Pures Parsing ohne Mirror:** `withUnsafeBytes(of: packet.words)` →
  `bindMemory(to: UInt32.self)` (allokationsfrei). Die Wort→Event-Logik als
  PURE Funktion `MIDIEventParse.event(word0:word1:) -> MIDIInEvent?`
  (Linux-testbar; MIDI-1.0- und 2.0-Zweige, Bend-Mathe, NoteOn-vel-0=Off).
- **`MIDIInEvent` enum:** noteOn(note,vel,ch) / noteOff(note,ch) /
  cc(num,val,ch) / pitchBend(val,ch).
- **`MIDIEventQueue` (@unchecked Sendable, NSLock, Cap ~512):** CoreMIDI-Thread
  pusht; `push()` gibt true zurück, wenn KEIN Drain geplant war → GENAU EIN
  `Task { @MainActor }` pro Burst (statt pro Event). Main-Drain zieht ALLES
  in FIFO-Ordnung und dispatcht an die bestehenden Callbacks; lastNote/
  lastVelocity einmal pro Batch (letztes noteOn). Latenz = ein Main-Hop
  (wie heute), Ordnung garantiert (eine Queue), Executor-Last O(Bursts).
  WICHTIG: NSLock ist hier ok — CoreMIDI-Empfang ist NICHT der Audio-Render-
  Thread (Regel bleibt: keine Locks im Render).
- **KEIN 10-Hz-Poll** wie bei der Kamera: MIDI ist Performer-Pfad (<10 ms) —
  der Burst-Task IST der Drain, kein Timer.
- Tests: Parse-Fälle (1.0 on/off/vel0/cc/bend ± / 2.0 on 16-bit vel/off/cc
  32-bit/bend) + Queue-Verhalten (FIFO, Cap-Drop ehrlich, ein Drain pro Burst,
  push-nach-Drain-Start planned neuen Drain).
- Reviewer: audio-thread-reviewer (CoreMIDI-Thread-Verhalten) + concurrency.
- 2 Dateien: MIDIInput.swift (Umbau) + Tests/MIDIEventParseTests.swift (neu).
  Verhalten identisch aus Sicht der Callbacks (gleiche Signaturen/Reihenfolge).
