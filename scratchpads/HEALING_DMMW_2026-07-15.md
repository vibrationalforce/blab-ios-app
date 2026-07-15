# DMMW-Wendepunkt: Deep-Audit-Synthese + Heilungsprogramm (2026-07-15)

Founder-Mandat: "Einmal Deep Audit und alles heilen, aufräumen — funktioniert alles
und sind wir architektonisch und designtechnisch gut strukturiert? … Wendepunkt vom
einfachen Instrument zur digitalen multidimensionalen Multimedia Workstation."

Quellen: zwei Ultracode-Workflows (28 Agenten gesamt, jede CRITICAL/HIGH-Behauptung
adversarial verifiziert): wf_9c6f33b7 (MIDI/Audio-Clips + AUv3, alle 11 REAL) und
wf_b436ca6c (Architektur/Design/Ehrlichkeit/Safety; 10 verifiziert: 8 REAL, 2 PARTIAL).
Volle Evidenz: Sandbox `/tmp/.../tasks/{wtdm5l634,werzkthg6}.output`.

## Wendepunkt-Verdict (ehrlich)

**Was die DMMW schon trägt:** EngineBus als typisierter Bus (inkl. MusicalFrame-
Ebene für Renderer) · TimelineStore als vorbildlicher Store-first-Command-Core
(pure Mathematik, Undo, Persistenz, Video-Lanes) · ParameterRegistry/ApplyRouter
vereinheitlicht DDSP- und AUv3-Parameter · die drei hart erarbeiteten UI-Gesetze
(Freeze-Regel, Modal-Decke [11 von ~19-Crash-Grenze], Uncodixfy) sind IM CODE
durchgesetzt, nicht nur dokumentiert · Audio-Thread-Disziplin und 3-Hz-Blitzgesetz
in der Tiefe sauber · ehrliche Gap-Kommentare als Kultur.

**Die strukturelle Schuld (warum "Instrument → DMMW" jetzt Heilung braucht):**
Der Clip-Pfeiler hat einen Command-Core — Instrument, Visual und Licht NICHT
(private View-Methoden im 4.321-Zeilen-EchoelStudioView, stringly @AppStorage mit
bereits divergierten Defaults, View-koordinierte Doppel-Sender-Writes). Die
Wiedergabe-Engines hinken der Spur-UI hinterher (MIDI-Fensterung, stumme
Audio-Lanes, inertes Pan, AU-Routing). Genau an diese Wand stoßen EchoelAI,
Broadcast-Automation und jeder Headless-Pfad, wenn wir sie auf dem heutigen Stand
bauen würden.

## Verifizierte Defekte, gemergte Heilungs-Reihenfolge (Ralph, 1/Zyklus)

### Welle 1 — Es KLINGT wie es aussieht (Founder-Schmerz, alle CRITICAL)
1. **H1 = M1** MIDI-Region-Fensterung (M1a pure ✓, ArrangementLoadPlan pure ✓ →
   M1b Player-Verdrahtung → M1c LaneNotePump) — Clips spielen ihre Takte.
2. **H2 = A1** Audio-Lanes verdrahten (AudioLanePlayer + AVAudioEngine-Sink,
   contentOffset ehrlich) — Audio-Clips klingen im Arrangement.
3. **H3** SamplerVoice-Sample-Swap-Race (installBuffer non-atomic vs. Render-Read;
   Fix: Command-Queue/atomic swap im bestehenden SPSC-Muster; audio-thread-review).
4. **H4** Per-Lane Pan/Gain-Fan-out in die Rack-Voices (inertes Pan; B09-Twin).
5. **H5 = U1** AU-Instrument-Assignment wirklich routen (Engine-Pfad pro Lane).

### Welle 2 — Datensicherheit + tote Türen (HIGH)
6. **H6** mediaRef RELATIV persistieren (Container-Pfad stirbt beim App-Update;
   resolveRef ist schon die eine Heimat — bare/relative refs schreiben, absolute
   legacy weiter auflösen). STILLER DATENVERLUST-Fix, klein.
7. **H7** SurfaceHost-Identität (Fold/Unfold → stopEverything killt Live-Session;
   .id()/Branch-Vereinheitlichung — winziger Fix, großer Live-Schutz).
8. **H8** Donuts-Look: Renderer unerreichbar aber Default-ON → entweder im
   Floating-Fenster rendern oder Selector ehrlich entfernen (Founder-Ton beachten).
9. **H9 = U2/U3** AU-Effekt-Inserts pro Lane + musicalContext/transportState.
10. **H10** MIDIInput-Flut (#30): Batch-Queue statt Task-per-Event + Mirror-Parsing
    vom CoreMIDI-Thread nehmen.
11. **H11** MIDI-Clip-Edit-Tür clip-scoped + Rückschreiben (M3) · **H12** Combine-
    Datenverlust-Guard (M4) · **H13** Audio-Audition/Edit-Tür mit Offset (A2/A3).

### Welle 3 — DMMW-Struktur (Command-Cores + Aufräumen)
12. **H14** InstrumentController-Core (start/stop/generate raus aus der View;
    Intents/EchoelAI/Notifications rufen den Core). PARTIAL-verifiziert: Fakten
    stimmen, Zuschnitt mit Council.
13. **H15** VisualStore + LightMasterStore (@AppStorage-Divergenz heilen:
    studio.loopBars .eight vs .four ist BEREITS auseinander).
14. **H16** Aufräum-Inventar mit Founder-Urteil: Broadcast-Sink ehrlich machen
    (Route ausblenden bis Engine), toter toolsSection/Fullscreen-Cover-Zwilling
    (Modal-Budget!), 6 schlafende Cores keep/wire/delete, Doku-Drift (4 Stellen),
    Directory-Drift (Video*-Dateien in Sequencer/ etc. — reine Moves, xcodegen).
15. **H17** MicrophoneManager-FFT vom Main-Thread (MEDIUM) · RetroCapture-Tap-Log.

### Bereits erledigt in diesem Block
- v246 Video-Monitor (Videospur rendert; beide Gates grün).
- M1a `RegionNoteWindow` + `ArrangementLoadPlan` (pure, getestet).

## Gesetz für alle Heilungs-Zyklen
Test-first wo pur · Pflicht-Reviewer (ui-state + code; audio-thread bei H3/H4/H2) ·
Gates grün · Deploy-Bump · deutsches Delta. Keine neuen Features, bis Welle 1+2
durch sind (God-Mode: "Tiefe Heilung aller angefangenen Baustellen").
