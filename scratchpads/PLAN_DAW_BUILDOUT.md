# PLAN — Full DAW build-out ("alle EchoelTools super ausgearbeitet")

Owner direction (2026-06-09): build toward a full-fledged DAW; present every Echtool
beautifully. Pianoroll, Arrangement, Clip View, Video Editing, iPhone high-quality
capture (Blackmagic-class), AUv3 plugins + own Instruments/FX, immersive visuals that
react to biofeedback + sound. **Non-negotiable: the user has full control.**
Method: Ralph Wiggum — one shippable, compile-verified, TestFlight-VALID cycle at a time.
Doctrine: open standards, depend on almost nothing; audio thread lock-free; iPhone-first.

## Sequencing principle
Deepen what is LIVE before adding new surfaces. Each cycle ships and is testable on device.
Order = value ÷ risk, biased to "make the instrument feel pro + fully controllable."

### Phase A — Instruments feel pro (sampler → real instrument)
- A1 ✅ **Pad sound design**: per-pad amp envelope (Level/Attack/Length) + Preview + persistence (THIS cycle, build pending). Sampler is now shapeable.
- A2 **Pitch / tune per pad** (playback-rate with linear interpolation, ±24 st) + choke groups (e.g. closed/open hat). Audio-thread resampling — prototype carefully.
- A3 **Per-pad FX sends** (reuse EchoelFX: filter/drive/reverb send) with user-controlled amounts.
- A4 **Synth (DDSP) patch UI**: expose the existing ADSR/brightness/harmonicity/reverb as a real editor (the engine already has them) → "own Instrument" #1.

### Phase B — Composition surfaces (the DAW core)
- B1 ✅ **Piano roll v1** (`Studio/PianoRollView.swift`): pitch×16-step grid (2 octaves + octave shift) drives the live DDSP synth via controllerEvents on the SHARED PatternEngine clock (`pattern.onTick`); opens from the Tools tab; releases on stop/close. Next (B1.1): note length/legato, velocity per note, polyphony, scroll/zoom, snap.
- B2 **Clip View** (session/launchpad): pattern + piano-roll clips as launchable cells; per-track clip slots; quantized launch.
- B3 **Arrangement / timeline**: arrange clips on a tempo timeline; loop region; playhead; basic automation lane (reuse ModulationMatrix for param automation).
- B4 **Mixer**: per-track level/pan/mute/solo + sends + master (EchoelMix); metering exists.

### Phase C — Capture & media (Blackmagic-class)
- C1 **CameraHub** (per SPEC_CAMERA_PIPELINE): ONE AVCaptureSession fanning out to rPPG/video/visuals. Foundation for everything camera.
- C2 **High-quality capture**: manual controls (ISO/shutter/WB/focus), 4K, HEVC; ProRes where device-supported (17 Pro). "Blackmagic-style" manual UI. (Research: ProRes RAW = 17-Pro+SSD only — offer, don't require.)
- C3 **Video editing (Clip View for video)**: trim, multi-clip timeline, export H.264/HEVC. (NLE depth incremental.)

### Phase D — Visuals & light reacting to bio + sound
- D1 **Immersive visuals engine**: wire the dormant Metal renderer (MetalBioView/BioVisualRenderer) into the live flow, driven by EngineBus bio + audio RMS/pitch. User-controllable params (mode, intensity, palette, which bio signal drives what). Epilepsy-safe (≤3 Hz).
- D2 **Audio-reactive layer**: feed master RMS/pitch (already on AudioEngine) into visuals + Art-Net light.
- D3 **sACN** (after Art-Net) for large light rigs; cue list.

### Phase E — Plugin/ecosystem polish
- E1 **AUv3 expansion**: ship the bio-reactive generator AUv3 as a polished product; add an **effect AUv3** (EchoelFX) so Echoel runs inside Logic/AUM as both instrument and FX.
- E2 **Own Instruments/FX presets** + preset browser (user save/load/share).

## Cross-cutting: "User has full control"
Every generated/auto behavior must be user-overridable and visible:
- Bio = modulation source, never forced (tempo-follow is opt-in; routes are user-painted in the Sync matrix).
- Sounds: per-pad shape + tune + sends; synth patch editor; presets.
- Visuals/light: user picks mappings + intensity; can disable.
- Capture: manual camera controls.
Nothing sounds/acts on launch until the user acts (already enforced: launch-silence gate).

## Status pointers
- Roadmap (tech SOTA): `scratchpads/STRATEGY_STATE_OF_THE_ART_2026-06-06.md`
- Architecture truth: `scratchpads/ARCHITECTURE_AUDIT_2026-06-09.md`
- Feature reality: `docs/dev/FEATURE_MATRIX.md`
- Camera fan-out: `scratchpads/SPEC_CAMERA_PIPELINE.md`

## Next cycle after A1
A2 (pad pitch + choke) OR B1 (piano roll) — owner picks. Default if unspecified: **B1 piano roll**
(biggest "feels like a DAW" leap; drives the already-live synth).
