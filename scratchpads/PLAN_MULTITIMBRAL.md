# PLAN — Multitimbral arrangement (founder: "an instrumental needs more elements, not one Fläche")

## Problem
Every melodic layer (bass · pad · pulse · lead) plays through ONE PolySynthVoice =
one patch = one timbre → the layers fuse into a single surface. SubBassVoice already
gives the low end a distinct sub timbre. Drums are silenced in the generate path.

## Goal
Each layer sounds like its OWN instrument: a harmony voice (pad + pulse), a distinct
LEAD voice (melody), and the existing SubBass for the low end. That is the root fix
for "one surface".

## Approach — additive, isolation over cleverness (can't test audio/CPU in sandbox)
Reuse the proven, tested `PolySynthVoice` wholesale as a SECOND instance rather than
making `EchoelPolyDDSP` internally multitimbral (which would touch the audio-thread
core and risk a render race). Two isolated voices = far lower crash risk; CPU is the
tradeoff, mitigated by a SMALL lead voice + device verification (ResourceGovernor
already throttles).

## Steps (Ralph-Wiggum: one safe commit each; build green throughout)

### Step 1 — Role foundation (PURE, no audio change) ✅ this build
- `Note.role: NoteRole` (`.harmony` default, `.lead`, `.bass`) — Codable, legacy-safe.
- BioComposer tags: composeHarmonic lead → `.lead`, bass → `.bass`, pad/pulse → `.harmony`;
  trap 808 → `.bass`, trap bell → `.lead`; ambient line → `.lead`; dub stabs → `.harmony`.
- Nothing routes on role yet → zero audible/behaviour change. Tested.

### Step 2 — Lead voice + routing (DEVICE-GATED, next build)
- Add a second `PolySynthVoice` (small: maxVoices ~3) as the LEAD instrument; attach
  BEFORE `audioEngine.start()` (build-1363 rule); own genre LEAD patch (bright/plucky,
  distinct from the warm harmony patch).
- Playback split: in the piano-roll tick trigger, send `.lead` notes to the lead voice,
  everything else to the harmony voice. (SubBass already tracks the low end.)
- Per-genre LEAD patch in GenrePatches (a distinct lead character per genre).
- Lifecycle: create/inject in the app root exactly like the existing voice; arm/disarm,
  allNotesOff on stop, launch-silence preserved.
- CPU mitigation: lead voice small; if device shows dropouts/thermal, lower harmony
  voice count or lead harmonics. Founder verifies on device (dropouts/kratzen + timbre).

### Step 3 — polish (later): moving bass line, tasteful percussion, per-layer FX sends.

## Risks
- CPU (two voices) — mitigated by small lead voice + device gate + ResourceGovernor.
- Launch order / black-screen / 10 Hz observe rules — follow the existing voice's exact
  wiring pattern; no new live-bio reads in any ancestor body.
- Voice-count during dense chords — lead is few-note; harmony keeps its cap.
