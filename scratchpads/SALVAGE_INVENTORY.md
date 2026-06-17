# SALVAGE INVENTORY — recover built-but-discarded work onto the stable core

Founder (2026-06-17): "Es gibt viel aus Feature Matrix was schonmal gebaut wurde…
erstmal verworfen weil der stabile Kern gefehlt hat. Tiefer Laser-Scan, dann
setzen wir alles Brauchbare auf das funktionierende Fundament. Stabil, qualitativ,
realtime."

## Finding
51 .swift files were deleted across history. The big cluster (clips / arrangement /
sessions) was removed in DELIBERATE refactors `6222dfa` ("delete surplus tab views —
one window only") and `fbffa66` ("delete clips/arrangement/sessions cluster"),
NOT because it was broken. The models are clean value types WITH TESTS and compile
against today's API (PatternEngine.load(steps:accents:)/play()/isPlaying/onTick;
PianoRollModel.load/allNotesOff; the current `Note` type).

Retrieve any file at its last-good state: `git show fbffa66^:PATH` (or `6222dfa^:` for the UI tab files).

## TIER A — SALVAGE NOW (high value, fits foundation, tested, on-vision)
| File (lines) | What | Notes |
|---|---|---|
| Sequencer/Clip.swift (51) | Clip/DrumPattern/MelodyClip value types | uses current `Note`; pure Codable |
| Sequencer/Arrangement.swift (120) | Arrangement + ArrangementCursor (pure bar-advance) | fully unit-testable, no clock |
| Sequencer/LaunchQuantizer.swift (78) | bar-quantized clip launch on the ONE PatternEngine clock | rides onTick (15→0 wrap); respects single-clock rule |
| Sequencer/ArrangementPlayer.swift (114) | drives PatternEngine across sections | verify against current PatternEngine |
| Core/ClipStore.swift (63) | Session-grid persistence (JSON) | |
| Core/ArrangementStore.swift (87) | Song persistence (JSON) | |
| Core/SessionRecorder.swift (160) | bio-session recorder → Works (EngineBus snapshot, UserDefaults) | self-contained, pure ingest, tested |
| Tests: ClipTests(79) ArrangementTests(142) ArrangementPlayerTests(154) LaunchQuantizerTests(94) SessionRecorderTests | full coverage | restore with the models |

## TIER B — SALVAGE AS ONE-VIEW UI (re-adapt; do NOT restore the old tabs)
ClipView(207, @6222dfa^) · ArrangementView(300) · ClipsTab(42, @6222dfa^) → rebuild as
panels/sheets inside EchoelStudioView. WorksView/WellView/ModulationView/SessionGridView/
SessionHistoryView/SettingsView/SoundDesignView → harvest UI patterns (mod-matrix editor,
coherence/well, session list, settings) into the one view. SequencerAccessibility(+test) →
re-apply a11y to the roll. BeatTab → patterns already in BeatPlayer.

## TIER C — WATCH / later (lower priority or off-vision)
Bio bridges: BioSourceManager, MotionActivityProvider, OuraRingClient (Oura already via HealthKit).
Ambient context: WeatherProvider, CircadianClock (off the instrument vision for now).
Video: ShortContentRenderer (roadmap with the video cycle).
Superseded UI: MasterView, MomentCapture(View), CameraMeasurementView, BioMetricInfo,
Selection, StudioNavigator, StudioRoot (single-view replaces nav).

## Re-integration sequence (Ralph loop, each compile-verified, uploads batched)
1. Clip + Arrangement + ClipTests + ArrangementTests (pure models). ← START
2. LaunchQuantizer + ArrangementPlayer + their tests (transport on onTick).
3. ClipStore + ArrangementStore (persistence).
4. SessionRecorder + test (Works/Sessions).
5. One-view UI: Clips grid (capture/launch) as a panel/sheet.
6. One-view UI: Arrangement timeline.
7. Tier-B harvest (mod-matrix, session list, a11y) as needed.

Principle: models+tests first (stable), UI second (one view), realtime path untouched
(all of this is control-plane; the single PatternEngine clock stays load-bearing).
