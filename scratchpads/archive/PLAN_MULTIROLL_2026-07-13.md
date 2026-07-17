# PLAN — Multi-Roll (Per-Spur-Engine-Routing), 2026-07-13

Founder-delegiert (decisions.csv 2026-07-13): Per-Spur-Engine-Routing VOR weiterer
UI-Verteilung, damit Per-Spur-Belegung/-Sound/-Automation HÖRBAR wird statt nur
sichtbar. Grounded Seam-Map (Agent 2026-07-13) + Council (proceed).

## Ist-Zustand (warum heute alle MIDI-Spuren EINE Stimme teilen)
- Stimmen = prozessweite Singletons in `EchoelmusicApp.init` (polyVoice(12) +
  leadVoice(3) + touchVoice(6) + subBass + bioVoice), je ein `AVAudioSourceNode`
  → EIN `masterMixer`. Kein Per-Spur-Node.
- `TimelineRegionPlayer` spielt nur `rollLaneID` = erste nicht-bio MIDI-Spur
  (`TimelineScheduling.swift:64`); alle anderen MIDI-Spuren sind für die
  Wiedergabe UNSICHTBAR. `loadClip` tauscht Clip-Content in die EINE `pianoRoll`.
- Note→Stimme in `PianoRollView.outputVoice(for:)` = nach Note-ROLLE (lead/normal),
  NICHT nach Spur.
- `PianoRollModel` = eine geteilte Instanz. Lane level/pan → geteilte Stimme
  (`ArrangeTimelineView` → `pianoRoll.mixGain` / `synth.setPan`).
- `TimelineLane.instrument/effects` (AUPluginRef) = persistiert, UNVERDRAHTET.

## GESETZE (halten in JEDEM Zyklus)
@MainActor-Stimmen; Note-Handoff nur über die lock-freie SPSC-Queue je Stimme;
kein alloc/lock/ObjC im Render; **attach-before-start** (Build-1363: Source-Nodes
VOR `audioEngine.start()` attachen); DSP/ bleibt isoliert (AUv3).

## Zyklen (Risiko aufsteigend, je ≥1 Zyklus)
- [x] **Z1 — Slot-Logik (pure, test-first):** `LaneVoiceSlotMap` (assign lowest
      free / reuse stable / release / cap → nil) + Tests. KEINE App-/Audio-
      Änderung. (Die `LaneVoicePool`-Klasse + App-Verdrahtung bewusst NACH HINTEN
      geschoben — sie fügt N vorab-allokierte Stimmen dem launch-kritischen
      Startup-Pfad hinzu, und Memory/CPU sind LOKAL NICHT messbar. Sie kommt mit
      Z3, wo sie verdrahtet UND auf dem Gerät messbar deployt wird.)
- [ ] **Z2 — Per-Spur-Roll-Content:** ein `PianoRollModel` pro MIDI-Spur (Option a
      der Seam-Map — reine Instanz-Vervielfachung, Note-Logik unverändert), ODER
      `[laneID: [Note]]`. Noch keine Audio-Verdrahtung — nur der Content-Split +
      Tests.
- [ ] **Z3 — LaneVoicePool + Playback-Fan-out (DEVICE-GATED, hier messen):**
      `LaneVoicePool` (fixe N, `maxVoicesPerLane` konservativ, vor start()
      attached, Env-inject) verdrahten; `TimelineRegionPlayer` über ALLE nicht-bio
      MIDI-Spuren fan-outen (nicht nur `rollLaneID`); Note→Spur-Stimme über den
      Pool (Fallback geteilte Stimme jenseits N). **N + maxVoices auf dem Gerät
      messen (<30% CPU, <200MB) und tunen — NICHT blind hochsetzen.**
- [ ] **Z4 — onTick-Fan-out:** ein Clock (`PatternEngine`/Transport), N Roll-Sinks;
      jeder Lane-Roll `trigger(step)` aus dem geteilten Transport-Step.
- [ ] **Z5 — Per-Spur-Mix/Pan:** `TimelineLane.level/pan/mute/solo` → SEINE Stimme
      (mixGain auf dem Lane-Roll, setPan auf der Lane-Stimme). Ersetzt den
      „erste-MIDI-Spur besitzt den Mixer"-Shortcut (`Timeline.swift:147-158`).
- [ ] **Z6 — Per-Spur-Instrument:** persistierten `TimelineLane.instrument/effects`
      (AUPluginRef) verdrahten → eine Spur wählt Patch/Plugin. Der sichtbare
      „Instrument/FX pro Spur"-Payoff wird real. Nutzt das AUv3-Host-Load je Spur.

## Ehrliche Grenze (bis Z3 wirkt)
Bis der Fan-out landet, teilen weiter alle MIDI-Spuren die eine Melodie-Stimme —
die Editor-/Belegungs-Türen bleiben „ehrliche Absicht". Jenseits von N Spuren
(nach Z3) teilen Spuren die Haupt-Stimme (dokumentierte Grenze).

## Messen (weil lokal kein Build)
CI (Linux SwiftPM + macOS/iOS Xcode) verifiziert Kompilierung + Tests, aber NICHT
Device-CPU/Memory. Z3 (der erste Zyklus, der reale Stimmen dem Startup zufügt)
MUSS auf dem Gerät gemessen werden (TestFlight-FREEZE dafür kurz aufheben) bevor N
final ist.
