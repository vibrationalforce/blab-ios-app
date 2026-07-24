# PLAN — Loop-Mode Produktions-Pipeline (Founder 2026-07-24)

**Founder-Fragen (wörtlich):** „Loops von 2,4,8,16,32 Takten rendern? Stems?
Video Mitschnitt ebenfalls im Loop Takt genau geschnitten?"

Gehört zur Loop-Mode-Hälfte der Zwei-Modi-Ansage (Flow=Meditation / Loop=Produktion).

## Ground-Truth (read-only Explore, verifiziert file:line)

### 1. Loops 2/4/8/16/32 Takte rendern → ✅ EXISTS
- `LoopBarLength` (1/2/4/8/16/32) `Sequencer/LoopCutter.swift:13`; Default `.eight`.
- Picker zeigt alle sechs: `Studio/EchoelStudioView.swift:3223` (`loopLengthSelector`).
- N-Takt-Loop rendert echt in **WAV** (taktgenau, Live-Capture-Bounce via RetroCapture):
  `Audio/LoopExporter.swift:61` (`exportWav(bars:)`) + `:101` (`exportRecentLoop`).
- Takt-Mathe: `DSP/StudioCalculator.swift:110` (`barSeconds`/`loopSeconds`/`loopSamples`),
  Schnitt-Fenster `loopTrimWindow` `:166`. Datei-Write `Audio/SingleExport.swift`.
- Hinweis: Live-Capture-Bounce, KEIN Offline-/manualRenderingMode (bewusst, „zero crash risk").

### 2. Stems (per-Spur/Bus) → ❌ ABSENT
- Repo-weit KEIN Stem-Export (0 funktionale Treffer). Nur **Master-Mix-Bounce**.
- ⚠️ **Falsches „done": Task #105** stand als completed, aber im Code existiert kein
  Per-Spur-/Bus-Export. (MEMORY/RECONCILE-Fund — Tracker korrigieren.)
- Grund: `SingleExport`/`LoopExporter` greifen nur den Master-Mix (`retroCapture`),
  kein Per-Lane-Tap. Kein UI, kein dormant core.

### 3. Video-Mitschnitt taktgenau zum Loop → ❌ ABSENT (jetzt V1-Core gebaut)
- `Video/VisualRecorder.swift` nimmt das bio-reaktive Metal-Visual als mp4 auf,
  **freilaufende Wall-Clock** (`:154`), kein Takt-Bezug.
- `Video/VideoMuxer.swift:49` end-aligned auf `min(video,audio)` Sekunden — reine Wall-Clock.
- Null Takt/Loop-Kopplung im ganzen `Video/`-Verzeichnis.

### Bonus: Flow/Loop-Modus schon als Enum da
- `Sequencer/BioComposer.swift:22` `ComposerMode`: `flowFree` („tempo follows the heart,
  for meditation") vs `studioLocked` („fixed BPM for DAW handoff"). Genau die Zweiteilung.

## Slices

### VIDEO-LOOP-CUT (Founder-Frage 3)
- ✅ **V1 GESHIPPT** — Commit `79fb850`, Reviewer PASS. Pure `VideoMuxAlignment.loopAligned(
  videoDuration:audioDuration:loopSeconds:secondsSinceBarStart:)` + 9 Tests. Schneidet exakt
  einen Loop (bars × barSeconds) aus BEIDEN Spuren, phasen-gelockt auf denselben Downbeat wie
  der Audio-Bounce (`loopTrimWindow`-Gesetz). Foundation-frei, Linux-CI. `endAligned` (#96)
  byte-identisch. KEIN Runtime-Wiring.
- ▶ **V2 (device-verified Slice)** — Wiring: `VideoMuxer.mux(…, loopSeconds:secondsSinceBarStart:)`
  optional (nil = heutiges Verhalten, byte-identisch), `VisualRecorder.stop(loopSeconds:)` optional,
  Caller im Loop-Export (EchoelStudioView) reicht `loopBars`→loopSeconds + PatternEngine-
  `secondsSinceBarStart` durch. A/V-Sync = geräteverifizierbar → NACH Freeze-Lift oder mit
  audio/av-Review + watch-clip-Verify. (#96-Historie: A/V-Desync ist heikel → isoliert testen zuerst.)

### STEMS (Founder-Frage 2) — braucht PLAN + Council + Audio-Thread-Review
- Neue Arbeit: Per-Bus-Taps am `AudioEngine` (Drums/Bass/Poly/… je eigener Tap → eigene WAV).
  Audio-Thread-sensibel (Tap-Installation, kein Alloc/Lock im Render). Eigener Zyklus, eigener PLAN.
- Reines Instrument hat keine DAW-Spuren mehr → „Stems" = die generativen Voices/Busse.

### LOOP-LÄNGEN (Founder-Frage 1) — ✅ fertig, nur Device-Verify
- Existiert komplett. Falls Founder eine fehlende Länge vermisst: Picker offeriert 1/2/4/8/16/32.

## Status
- ✅ V1 (Video-Loop-Cut-Core) geshippt `79fb850` — Gates werden geprüft.
- Nächster Zyklus-Kandidat: V2-Wiring (device-gated) ODER Stems-PLAN ODER die schon geplanten
  G2 (Ambient-Genres) / M1 (Flow/Loop-Schalter). Founder-Priorität entscheidet.
- Alles NEEDS-FOUNDER-VERIFY hinter TestFlight-Freeze.
