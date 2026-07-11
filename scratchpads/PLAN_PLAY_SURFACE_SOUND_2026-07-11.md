# PLAN — Play-Surface Sounds: rework, level, deepen (Founder 2026-07-11)

**Founder brief (verbatim):** "Play surface sounds überarbeiten und angleichen. Die
sind teilweise zu laut oder zu leise und klingen zu gleich. (die Synthese
Einstellungen sollen auch tiefer sein / Level pro Instrument / die ganzen effekte
und texture etc. Wie klassisches Plugin)"

Three distinct complaints → three cycles. The Play-surface sounds ARE `SynthPatch`
presets (played through a dedicated touch `PolySynthVoice`); the same patches feed
the generative synth, so every fix helps app-wide.

## Cycles (Ralph — one per TestFlight, TDD; render-path work → audio-thread-reviewer)

- **Cycle 1 — Level per instrument ("teils zu laut/zu leise") — SHIPPED.**
  `SynthPatch.outputLevel` (optional, unity-default, migration-safe) → applied as a
  voice gain folded into the master-gain smoother (click-free). Factory roster
  auto-loudness-matched via a pure heuristic (`loudnessEstimate`/`loudnessNormalized`).
  "Level" control in the patch editor. audio-thread-reviewer: clean.

- **Cycle 2 — Differentiation ("klingen zu gleich").**
  The factory patches sit in a narrow timbral band (harmonicity 0.85–0.97, brightness
  0.4–0.7). Widen the spread so each is audibly its own instrument: push spectralShape /
  filter character / attack profile / unison apart, add a few genuinely distinct voices
  (e.g. a hollow pluck, a glassy bell, a reedy lead, a fat detuned saw, a soft sine
  pad). Now safe because Cycle 1 keeps divergent timbres loudness-matched. Pure data +
  a test asserting the roster spans a wide timbral fingerprint (no two patches near-
  identical). No render change.

- **Cycle 3 — Deeper synthesis + effects + texture ("wie klassisches Plugin").**
  Expose the params the editor doesn't yet surface and add a per-instrument FX/texture
  layer so a patch reads like a plugin instrument:
    · editor: filter LFO depth, envelope curve, timbre-transfer blend, noise color, the
      new level — grouped like a plugin (Osc/Filter/Env/FX/Level).
    · per-patch FX/texture: drive/saturation, chorus/ensemble width, a texture/air layer
      — stored on the patch, applied through the existing EchoelFX/DSP (no new deps).
  Biggest cycle; split further if needed. Any render-path add → audio-thread-reviewer.

## Guardrails
- outputLevel optional → old patches decode to unity (never silently re-level a saved sound).
- All parameter UI via `EchoelValueField` (Uncodixfy); editor stays adaptive + professional.
- Render-path changes stay allocation/lock-free; default values bit-identical.
- Loudness heuristic is honest — a rendered-RMS calibration is a later device/CI refinement.
