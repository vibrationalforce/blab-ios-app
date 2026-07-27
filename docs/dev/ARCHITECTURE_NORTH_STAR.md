# Echoel — Architecture North Star (multidimensional DMW)

> ⛔ **SUPERSEDED 2026-07-25 — HISTORY ONLY, DO NOT PLAN FROM THIS FILE.**
> The canonical scope decision is `docs/dev/PRODUCT_DEFINITION.md`: "DMMW" is retired
> and Echoel is a bio-reactive **instrument**, not an all-in-one pro suite. The
> workstation half this document targets was dismantled on purpose (epic #121 —
> AUv3 target + AUv3 hosting, video cut, DAW UI). Concretely wrong below: the DMW
> target itself, "AUv3 keeps ingesting DSP by path", and the `xcode-compile-check
> (AUv3)` gate — that scheme no longer exists. The one part still worth reading is
> the *method* (parallel planning, serial CI-green Ralph cycles), not the target.

Status: ADOPTED 2026-06-20 (founder: full pivot → all-in-one pro suite, "perfekte
Architektur für langfristig State-of-the-Art Software"). This is the canonical
TARGET architecture. Precedence: `memory/vision.md` (WHY) → this ADR (target
HOW) → the four pillar PLANs (detailed steps) → `docs/dev/ROADMAP.md` (backlog).

Product arc: **Create from within → produce professional → bring it to live (wings).**

## Principle: parallel planning, serial CI-green execution
The whole DMW (DAW + AUv3 host + video/NLE + broadcast + visual mapping + spatial
A/V) is built by **one shippable Ralph cycle at a time** on a stable foundation —
never a big-bang reorg (that would leave the shipping app red for weeks and is the
exact "build long in a short-term direction" trap we are avoiding). We set the
target on paper first (this doc), then execute additively. The app stays a
working superset after every cycle.

## The 6 foundation pillars

1. **Unified Transport / Clock** — `Core/Transport.swift` (added 2026-06-20, pure +
   tested, additive). The ONE musical clock (bar/beat/step/ppq, priority-ordered
   subscribers) that the sequencer, arrangement, future video playhead, MIDI clock
   and Ableton Link all ride. Plan: `scratchpads/PLAN_TRANSPORT_CLOCK.md`.
2. **Modularization (SwiftPM, leaf-first)** — `EchoelmusicApp → EchoelUI →
   {EchoelAudio, EchoelSequencer, EchoelSync} → {EchoelBio, EchoelDSP} → EchoelCore`.
   DSP/ is already pure (Foundation+Accelerate) → `EchoelDSP` is cycle 1. The
   protected Bio triad moves byte-identical under a Council + founder gate. AUv3
   keeps ingesting DSP by path (it is not an SPM product). Plan:
   `scratchpads/PLAN_MODULARIZATION.md`.
3. **Unified Project document + Undo/Redo** — `EchoelDocument` (schema-versioned,
   App Group) composing the 8 scattered stores; a `CommandStack` adopted store-by-
   store via the existing private `persist()` seam; legacy files kept as rollback.
   Plan: `scratchpads/PLAN_UNIFIED_PROJECT_AND_UNDO.md`.
4. **EchoelUI design system + IA** — `Studio/UI/` (tokens with semantic roles,
   `EchoelButton/Panel/Row/Sheet/EmptyState`; `EchoelValueField` frozen). IA = "one
   home, depth on demand": a workspace switcher (no tab-explosion / no god-view) +
   eyes-free Live mode; bio strip is the universal front door. Plan:
   `scratchpads/PLAN_ECHOELUI_DESIGN_SYSTEM.md`.
5. **EngineBus / concurrency hardening** — keep the @MainActor @Observable control
   plane + lock-free SPSC; add clear Sendable boundaries + backpressure for video /
   broadcast / Link as those land.
6. **Sync & I/O** — MIDI clock (Swift/CoreMIDI, no dep) first; Ableton Link (C++
   LinkKit, FREE, Council-gated) second; ADM-OSC / Art-Net / sACN already live.

## Master execution order (each = one CI-green, shippable cycle)
**Foundation (additive, low risk, do first):**
- T1 ✅ `Transport` type + tests (no wiring). · T2 PatternEngine relays into Transport
  (no behaviour change). · T3 Arrangement → Transport subscriber. · T4 PianoRoll →
  subscriber. · T5 BeatPlayer + tempo route → Transport. · T6 timer moves into
  Transport (device-gated).
- U1 EchoelUI tokens. · U2 chrome components. · U3 adopt in home. · U4 adopt in sheets.
- D1 EchoelDocument model. · D2 pure migration. · D3 coordinator + lazy migrate.
**Sync/features (on the foundation):**
- MIDI clock (leader+follower) · Ableton Link (gated) · Video foundation (CameraHub +
  recorder) · Broadcast RTMP (HaishinKit) · per-store Undo adoption.
**Modularization (own track, gated, leaf-first):** EchoelDSP → EchoelCore → EchoelBio
(triad, gated) → EchoelSync → EchoelAudio → EchoelSequencer → EchoelUI.

Cross-cutting build restructures (modularization) are interleaved deliberately, not
run in parallel with feature cycles, to avoid collisions. Protected Rausch DSP triad
stays read-only throughout. Every cycle gates on the real `xcode-compile-check`
(AUv3) + `ci.yml` (build+test), then ships to TestFlight.
