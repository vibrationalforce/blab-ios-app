> ⛔ **SUPERSEDED — do not execute (banner 2026-08-28).** This plan commands scope the Editor ≠ Workstation boundary (docs/dev/PRODUCT_DEFINITION.md, 2026-07-25) has CUT or that #121/#166/#167 dismantled. History only; ROADMAP.md + vision.md win over any PLAN file.

# PLAN — Composition Arrangement + Video Editing in ONE View

Founder directives (2026-06-17):
- "Komposition im Arrangement sowie Video Schnitt in einer Ansicht." — arrangement
  composition AND video editing live in a single unified view.
- "Sämtliche Hardware wird unterstützt." — all hardware is supported (guiding
  principle: open standards, no SDK lock-in; every in/out reaches real devices).

## North star
One screen where the body-generated music is arranged on a timeline (beyond the
single 16-step loop) AND video clips are cut against that same timeline — bio
drives both. The EngineBus stays the spine; this is ONE view, not new tabs
(consistent with the "tools flow into one instrument" decision).

## Today (code truth)
- Music = ONE 16-step loop (PatternEngine + PianoRollModel), re-seeded live. No
  arrangement timeline (no sections/scenes/song length).
- Video = NOT wired. Metal GPU bio-visual renderer EXISTS (MetalBioView) and is
  the intended foundation for visuals/video/broadcast overlay.
- Outputs LIVE: audio, OSC, ADM-OSC, Art-Net, MIDI/MPE OUT (new, virtual source),
  MIDI/MPE IN (1.0/2.0/MPE + RTP network). Roadmap: sACN, RTMP, video capture/edit.

## Sequenced cycles (Ralph loop, each compile-verified, batched upload)
1. **Clip/Arrangement model** — `Clip` (drum pattern + melody [Note] + length) and
   a `Song` of clip slots over a timeline; `ClipStore` (App-Group JSON). Pure
   value types, unit-tested. (Foundation for both arrangement + later video sync.)
2. **Arrangement timeline UI** — a horizontal lane of bars/sections in the one
   view; launch/queue clips at bar boundaries (reuse loadAtBoundary seamless swap).
   Numbers-first, EchoelValueField + EchoelTheme.
3. **Video capture** — AVCaptureSession 1080p30 + AVAssetWriter (Sources/Video,
   already an allowed dir per CLAUDE map). Record against the transport clock.
4. **Video edit lane in the SAME view** — clip in/out trim on a second timeline
   lane aligned to the music bars; the Metal bio-visual is a generatable video
   source too. Audio-locked scrubbing.
5. **Export** — render music + video to MP4 (VideoToolbox H.264/AAC, LUFS master).
6. **Live content** — RTMP via HaishinKit (the one allowed external dep) for
   broadcast of the unified A/V; ADM-OSC/Art-Net already cover spatial+light.

## "All hardware supported" — standing checklist (open standards, no SDK lock-in)
- MIDI: IN + OUT, 1.0/2.0/MPE, USB class-compliant (CoreMIDI auto), RTP network. ✅ (OUT new)
- Heart rate: any BLE 0x180D strap (Polar/Wahoo/Garmin/generic), HealthKit, camera rPPG. ✅
- Spatial: ADM-OSC object out to any compliant renderer (L-ISA, d&b, FletcherMachine). ✅
- Light: Art-Net (✅), sACN (roadmap).
- Sync: OSC (✅), Ableton Link (roadmap).
- Audio: system out / interface (✅), AUv3 host integration (target exists).
- Gap to close for the claim: Ableton Link, sACN, USB-MIDI doc/test matrix, AUv3 ship.

## Constraints
- One feature per cycle; swift build green (-warnings-as-errors) each commit.
- Audio thread untouched (video/arrangement = control plane).
- Apple TestFlight upload quota = 1/day → batch verified cycles, one upload/window.
- No new top-level dirs beyond Sequencer/Stream/Studio/Video (Video already mapped).

---
## EchoelBeat (pro sampler) + EchoelBreak (breakbeat/jungle) — 2026-06-17 directive

Founder: "Echoelbeat aber optimiert samplebasiert mit samples vorhören im
ordnerverzeichnis und FL Studio / Ableton Level sample Manipulation.
Echoelbreak für breakbeats auf meister jungle level."

### Today (code truth)
- SamplerVoice = one-shot mono WAV, **gain only**. No rate/pitch/start-end/reverse/slice/warp.
- SampleBrowserView = bundled list + Files import + click-to-preview. No folder-tree browse, no waveform.
- Hybrid sample+synth drums (modal) + PadSoundEditor (envelope). No time-stretch (no AVAudioUnitTimePitch).

### EchoelBeat-pro cycles (each compile-verified, lock-free render)
1. Sampler params per pad: **start/end trim, reverse, gain, pitch (playback rate), fades** —
   all index/rate math in the existing lock-free RenderState (no malloc).
2. **Folder browser + waveform preview**: security-scoped folder pick, list audio files,
   draw a downsampled waveform, audition on the preview voice (extend SampleBrowserView).
3. **Velocity layers / round-robin** per pad; choke groups (hi-hat).
4. **Warp / time-stretch to project BPM**: OFFLINE render via AVAudioUnitTimePitch (or a
   phase-vocoder) into the pad buffer at load — zero audio-thread cost, tempo-locked.

### EchoelBreak cycles (jungle/breakbeat)
5. **Transient slicer**: detect onsets in a loaded break (vDSP energy/flux), auto-slice into
   hits, map slices across pads/steps. Manual slice add/move.
6. **Slice sequencer**: re-order slices on the step grid; per-slice reverse/pitch/retrigger/stutter.
7. **Break warp**: stretch the whole break to BPM (reuse cycle 4) so any break locks to the project.
8. Jungle toolkit: ghost-snare rolls, amen-style chops presets, half-time/double-time, swing.

### Feasibility = GREEN
All of the above is bounded AVFoundation + Accelerate on iPhone, fits the lock-free SamplerVoice
pattern; warp is offline (no realtime cost). No new external dependency. Sequence into the
Ralph loop after Mood/Character + AI director; reuse the same one-view philosophy.

---
## One-Shot Sample Player + "recover synths" finding — 2026-06-17

Founder: beats/breaks stay SAMPLE-BASED; has many one-shot samples → wants a
dedicated Sample Player; recover other synthesizers from histories; the extensive
Echoel tools were never properly accessible/immersive/pro in TestFlight.

### History finding (honest, from git --diff-filter=D over all history)
Deleted files were CONSOLIDATIONS, not lost synths: ClipEngine, SoundscapeEngine,
GenrePatches (→ PatchLibrary), SoundDesignView (→ PatchEditorView), SoundscapeView.
No distinct deleted synth engine to revive. The synthesis power ALREADY EXISTS and
is under-exposed:
- EchoelDDSP — additive/harmonic (DDSP), 35+ params, the main melodic voice.
- EchoelCellular — cellular-automata evolving texture.
- EchoelModalBank — physical/modal (drum/bell/string/membrane materials).
- EchoelHarmonizer, EchoelFXChain, EchoelReverb/Delay/ModFX/Dynamics/SVFilter.
→ TASK is EXPOSE (selectable instrument + accessible pro editor), not resurrect.

### One-Shot Sample Player (new instrument) cycles
A. **OneShotSamplePlayer voice** — reuse SamplerVoice (lock-free); a bank of
   one-shots playable from a pad grid / keyboard, pitch-mapped (rate) across keys.
B. **Folder library + waveform preview** (shared with EchoelBeat-pro cycle 2):
   security-scoped folder, list, downsample waveform, audition.
C. Per-slot: start/end/reverse/gain/pitch/ADSR (shared sampler params).
D. Bio hooks: velocity/filter/pitch from the body (optional), MPE-out aware.

### Instrument selector (accessibility/pro exposure)
E. A single "Instrument" picker on the one view choosing the melodic engine:
   DDSP (additive) · Cellular · Modal · Sample Player — all feeding the same
   PolySynthVoice slot + patch editor. Makes the existing engines discoverable.

### Sequence (revised, calm/steady — uploads batched):
Mood/Character → AI director → EchoelBeat-pro sampler params (A/C foundation) →
folder+waveform browser (B) → One-Shot Sample Player (A,D) → instrument selector (E)
→ EchoelBreak slicer → arrangement model → video.
