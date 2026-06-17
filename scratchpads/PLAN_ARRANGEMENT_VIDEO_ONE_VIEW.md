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
