# PLAN — "Harmonic Series" bio→sound mapping preset (Triage #3)

Status: PLAN (Phase 1). Not yet implemented. From COLLAB_SYNC_TRIAGE §1.2.

## Goal
A selectable **"Harmonic Series" character** where the body drives the harmonic
structure more literally than today: HR→fundamental reference, HRV→overtone
spread/detune, breath→amplitude LFO, motion→intensity. "Harmonic mapping of
physiological rhythms" — measurable, NO wellness/effect claims.

## CRITICAL: this is NOT greenfield — integrate, don't duplicate
A rich bio→synth mapping system already exists. Before writing anything, read:
- `Core/ModulationMatrix.swift` + `Core/ModulationEngine.swift` — the routing layer.
- `DSP/EchoelDDSP.swift:926` + `:1405` `applyBioReactive(...)` — existing maps
  (coherence→harmonicity, HRV→brightness, HR→vibrato, breath→envelope, breath
  depth→noise, LF/HF→tilt). The new preset must REUSE these params, not add a
  second path.
- `Tools/BioReactiveSynthVoice.swift` + `Tools/PolySynthVoice.swift` — consumers.
- `Bio/BioEventGraph.swift` (PROTECTED — read only; consume its events, never edit).

## Design (integrate as a preset, not a module)
1. Add a `MappingPreset` enum/value (e.g. `.default`, `.harmonicSeries`) surfaced
   in the existing modulation layer — a named set of routings/weights over the
   SAME `applyBioReactive` params. No new audio path, no protected-DSP change.
2. `.harmonicSeries` routings (all above the protected DSP, deterministic):
   - HR (bpm) → fundamental reference / vibrato-rate blend (today HR→vibrato only).
   - HRV → overtone spread (map to harmonicity/brightness so higher HRV = richer/
     more detuned partials): reuse `f·n·(1 + hrv·k)` idea via brightness/harmonicity.
   - Breath phase → amplitude LFO (breath→envelope already exists; deepen).
   - Motion/ACC → intensity/level.
3. UI: one selector in the existing bio/FX mapping section using `EchoelValueField`/
   the standard control — NOT a new sheet (respect the EchoelStudioView modal ceiling,
   audit P1.5). Reuse an existing slot.

## Verify
- Pure mapping math as a testable value type first (TDD): bio input → param output,
  deterministic, in-range clamped. New `HarmonicMappingTests`.
- Then wire the preset selector; device-verify the body audibly shapes the overtones.
- swift build clean; audio-thread audit (no new render-path work — reuses applyBioReactive).

## Open decisions for founder
- Should HR set the actual **fundamental pitch** (strong "body = instrument"), or only
  modulate around the played note? Pitch-following can fight melodic content — safer
  default: modulate timbre/vibrato, offer pitch-follow as an explicit sub-option.

## Sibling roadmap items (from COLLAB_SYNC_TRIAGE, not this plan)
- LinkKit tempo-sync spike — needs founder OK (new dependency).
- SessionState + MultipeerConnectivity local sync (base: `MultipeerSession`).
- `NoteColorPalette` — CHECK vs existing Cousto tone→colour first (may be covered).
- Per-track Kammerton/Tonart — separate music-theory feature.
