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

---

# ULTRAWELLE (Founder-Mandat 2026-07-15 abends, 8h+: "gesamte DMMW... ein Bereich
# nach dem anderen perfekt, accessible bis Profi")

Quelle: Ultrascan wf_232c22de-6d4 (41 Agenten: 10 Bereichs-Auditoren + 31
adversariale Verifikationen; 27 REAL, 2 REFUTED). Volle Evidenz:
`/tmp/.../tasks/wicqmv010.output`. Geräte-Log Build 2361 als Anker.

## Bereich 1 — LIVE-SESSION ÜBERLEBT (Log-Schmerz, zuerst)
- **U-B1.1 = RPPG-1 [HIGH]** Finger-Halte-Boden 0.18 > R der dunklen
  Belichtungssperre (0.15–0.17 bei bright 0.08–0.10) → präsenter Finger liest
  finger=no, Fenster-Reset, 92 s nie Lock (Session 2). FIX: HOLD-Floor
  CameraAnalyzer:780 0.18→0.12 (ACQUIRE bleibt 0.28; Rot-Dominanz-Ratios bleiben).
  Session 3 beweist: bright 0.10 ist lockbar, der Detektor war der Killer.
- **U-B1.2 = BLE-1 [CRITICAL] + BLE-2 [HIGH]** Gurt-Scan völlig unsichtbar (kein
  View liest polarH10.state/connectedDeviceName) + kein Timeout/Fehlzustand.
  FIX: PulseMonitorMiniLive-Leaf zeigt Scanning/Connecting/Name✓/BT-aus; ~20 s
  Watchdog → .notFound ("Elektroden befeuchten").
- **U-B1.3 = BLE-3 [HIGH] + BLE-4 [HIGH]** Doppel-Besitzer (Patchbay blehrs.in
  stoppt Pill-gestarteten Gurt bei JEDEM Routing-Edit; Kamera+Gurt gleichzeitig
  möglich) + Zombie-Scan (CB-Delegates ohne isPublishing-Guard, zweiter Central).
  FIX: EIN Besitzer = Pill (applyRouting-Block raus, Bio-Panel-Text richtig);
  isPublishing-Guards + Central-Reuse.
- **U-B1.4 = T2 [MEDIUM] + T1-Schritt-1** generate[]-Label ehrlich (reason-Param,
  applyVariation="variation", Zuweisung in den Task-Body) + Stop-Quellen-
  Breadcrumbs an jedem pattern.stop()-Call-Site (transport-bar/record/roll/export).
- **U-B1.5 = T1-Schritt-2 [FOUNDER-GATED]** ■ pausiert Musik, Bio-Session lebt
  weiter (Puls-Pill = der EINE Bio-Aus-Schalter)? Widerspricht dokumentiertem
  "ONE Stop"-Founder-Entscheid → Frage im Status-Delta, NICHT eigenmächtig.

## Bereich 2 — CLIPS/DAW PROFI (4 CRITICAL/HIGH-Kette)
- **U-B2.1 = CLIP-1 [CRITICAL]** M1c: Sekundär-MIDI-Lanes ohne Fensterung
  (LaneNotePump %16-Faltung; TimelineRegionPlayer:369/419 lädt volle Melodie).
  FIX: RegionNoteWindow auch dort + Takt-Zyklus statt %16. Test-first.
- **U-B2.2 = CLIP-2 [CRITICAL]** Record-arm auf Audio/Video-Lane nimmt STILL
  nichts auf (TakeRecorder:65 break). FIX ehrlich: canRecord=false + "soon"-Hint;
  echte Mic-Capture = eigener Zyklus (Task #13).
- **U-B2.3 = CLIP-3..6 [HIGH]** Struktur-Edits erst nach Stop+Play hörbar ·
  Audio-Clip-Edit-Tür lädt Clip nicht · Playhead kosmetisch (immer Takt 1, kein
  Relocate) · Clip-Gain/Fades verworfen, keine Crossfades (Klicks).
- **U-B2.4 = PERF-01 [HIGH]** Lane-Sink-Format-Wechsel mid-song pausiert Engine
  (seit F2 Crash→Pause, besser, aber hörbar). FIX: Formate beim Prime vorwärmen.

## Bereich 3 — AUv3 (AU-1 Format-Pre-Flight in globalen Pfaden [Crash],
AU-2 globale Chains nicht restauriert, AU-3 Scan-Bursts, AU-4 Guidance).

## Bereich 4 — STRUKTUR (H14-CORE InstrumentController-API · H15-KEYSTORE
VisualStore/CompositionStore · H15-LIGHT LightMasterStore · H15-LOOPBARS 8vs4).

## Bereich 5 — UX ACCESSIBLE→PRO (UX-1 [CRITICAL] Kamera-verweigert = Bio still
tot + irreführendes "Cover camera" + kein Settings-Pfad · UX-2 Play spielt
Stille, einzige Klang-Tür unbeschriftet · UX-3 HealthKit-Prompt kontextfrei ·
UX-5 Dynamic Type Bio-Zahlen · UX-10 Pill 30pt<44pt · UX-8 MIDI-Learn).

## Bereich 6 — ULTRACLEAN (H16-2 zwei tote fullScreenCover am Root [Modal-Budget!]
· H16-3 Donuts=H8 · H16-5/6 Doku-Drift · H16-7 Directory-Moves). H16-1 REFUTET.

## Bereich 7 — MARKETING-EHRLICHKEIT (MKT-1..4 [HIGH]: FAQ erfindet Orchester-
Sektionen, "EchoelWarmth"-Suite, MIDI-2.0-Claim, Audio-to-MIDI — Brand-Gesetz
"claim only what ships" verletzt, docs/ fixen; MKT-7 "meditation"-Keyword;
MKT-11 echte Differenzierer unterverkauft = #52-SEO-Liste). PIPELINE only.

## Bereich 8 — PERF (H17 FFT von Main [PERF-02] · PERF-03 Meter-Poll 60 Hz).

Gesetz unverändert: 1 Punkt/Zyklus · test-first wo pur · Pflicht-Reviewer ·
Gates grün · Deploy-Bump · deutsches Delta.
