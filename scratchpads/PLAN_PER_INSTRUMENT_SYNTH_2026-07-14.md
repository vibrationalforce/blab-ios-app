# PLAN — Per-Instrument EchoelSynth + Header dissolve (Founder live pass 2026-07-14)

Founder device-redesign burst (v10.79.198, red-pen screenshots + answers). The
global bottom chip bar (Bio · Comp · Session · Transp · Sound · Mix · FX · Mood)
DISSOLVES into two homes: **(A) the header** (always-on chrome) and **(B) each
MIDI track = an instrument with its own optional EchoelSynth**. This is the
"comprehensive interface, everything split into instruments, ONE bio-timeline
spine" direction (decisions.csv #194/#198), now made concrete per surface.

## Founder directives (verbatim intent)

| # | Panel today | New home | Founder words |
|---|---|---|---|
| 1 | **Bio** strip | **Header** leaf; TAP = full detail | "Der Bio Teil soll komplett nach da oben. Wenn man draufdrückt bekommt man mehr Infos" |
| 2 | **Comp** Key/Scale/tuning/tempo | **UP** near the timeline | "Dieser Teil kommt nach oben wie eingezeichnet" |
| 3 | **Comp** Genre + **Variation** | **Per MIDI track, OPTIONAL** | "Genre und Variation pro Midi Spur einzeln … Es soll ja alles in Instrumente aufgeteilt werden und da soll man das dann optional anschalten und angeben können" |
| 4 | **Session** name/place | **UP**; + manual place entry | "Das hier auch nach oben. Man kann natürlich auch manuell den Ortsnamen eingeben …" |
| 5 | **Weather** ("shapes the sound") | **Optional per-instrument tool** | "Weather shapes the sound wird ein extra Tool, das man bei den Instrumenten optional mit anschalten kann" |
| 6 | **Sound & texture** (Character/Randomize/Brightness/Harmonics/Noise/Cutoff/Reso/LFO/Envelope/Reverb/Vibrato/Sub) | **Part of EchoelSynth** (per-instrument) | "Sound und texture wird auch Teil von Echoel Synth" |
| 7 | **Transpose** | **DELETED** | "Wir erstmal komplett gelöscht" |
| 8 | **Mix** + **FX** | **Part of EchoelSynth** (per-instrument) | "Mix und FX wird auch in EchoelSynth integriert" |
| 9 | **Mood** | **Joins Genre + Variation** (per-track composition group) | "Mood kommt zu Genre und Variationen" |

**The whole bottom chip bar dissolves** (founder: "Jetzt müsste die untere Leiste
komplett aufgelöst sein und entsprechend an anderer Stelle gemerged wiederzufinden
sein"). Final map: Bio→header · Comp key/tempo→up · Session→up · Genre+Variation+
**Mood**→per-track composition group · Sound&texture+**Mix**+**FX**→EchoelSynth
per-instrument · Weather→optional per-instrument · Transpose→deleted. Nothing left
on a global bar.

## ✅ ROOT CAUSE FOUND — "Alles ist still" (from the device log)

**The generative melody is gated by the roll-slot lane's mute/solo/level.**
`Timeline.rollSlotGain` (Timeline.swift:175) = `effectiveGain(first non-bio MIDI
lane = "MIDI 1")`, which is **0** when that lane `isMuted`, when ANY other lane
`isSoloed`, or `level==0`. `ArrangeTimelineView:118 onChange(rollSlotGain)` sets
`pianoRoll.mixGain = gain`; `PianoRollView:529` gates every `noteOn` on
`laneAudible = mixGain > 0.001`. So notes generate, transport plays (`playing=true`,
musical level 1.0 = summed velocities), but **no noteOn reaches the synth** →
total silence. Log confirmed engine started OK + `generate[start]: 10 notes,
playing=true`. Lane defaults are unmuted/level-1 ⇒ this is timeline STATE (MIDI 1
muted, or a foreign solo — the amber "M" on MIDI 1 in the founder's screenshots),
NOT a default bug. Also possible: `suppressBuiltIn` true if an external AUv3 is
assigned to the roll (PianoRollView:451 `auHost?.suppressesBuiltInVoice`).

**Immediate user fix:** unmute MIDI 1 / clear any solo. **Diagnostic shipped:**
`rollMixGain` now in the generate breadcrumb (EchoelStudioView) to confirm in the
next log. **Follow-up fix (UX trap):** make the silenced-because-track-muted state
VISIBLE (pulse button / banner) so the core instrument is never invisibly trapped.

## (superseded) earlier notes — "Alles ist still" (total silence)

Founder: pressing the pulse button + finger on camera → NO sound at all.
- Verified the code path is INTACT + unchanged by recent commits: pulse button →
  `.echoelToggleBio` → `toggleBiofeedback` → `startBiofeedback` (running=true →
  `startBioSource` → `generate()` → `pattern.play()`); AudioEngine.start() is at
  APP level (EchoelmusicApp:453/649), not inside the adaptive-home conditional
  zone; EchoelStudioView.onAppear (audio setup) still fires (always mounted).
- makeComposerInput (v198) is byte-identical to the old inline head when overrides
  are nil (two reviewers + both gates confirmed). It does NOT change note output.
- ⇒ Silence is a RUNTIME/device condition, not visible in this diff. NEED
  `echoel_diag.log`: it records "startup 3/4: audio engine started OK" (or the
  `CRITICAL: Master engine start failed` retry path at AudioEngine.swift:447),
  "Start tapped", "camera started", and the `generate[...]: N notes, playing=` line.
  That pinpoints whether the engine started, generate fired, and notes were > 0.
- Suspects to confirm from the log: (a) audio-session/route failure on device
  (another app held the session; relaunch fixes) → engine start CRITICAL;
  (b) generate produced 0 notes; (c) transport.isPlaying flipped false right after
  play (the `onChange(transport.isPlaying){ if !playing && running { stopEverything() }}`
  guard at EchoelStudioView:615 — a timeline-transport interaction could trip it).
- Until the log resolves this, do NOT build the per-instrument restructure on top —
  fix sound first.

## Done in code (committed, awaiting a bundled deploy)

- #1 Bio → header: header leaf TAP = `.echoelChromeDoor "bio"` (full detail),
  long-press = start/stop; bottom **Bio chip removed**. (HeaderMonitors + studioChips)
- #7 Transpose chip removed from the bar (case/panel stay, reversible).

## Sequenced build (module-by-module; each a Ralph cycle, reviewer-gated)

0. **FIX SILENCE** (blocker — needs the log). No further UI build ships until sound
   is confirmed on device.
1. **Per-track SynthPatch (Sound & texture → EchoelSynth).** TimelineLane already
   can carry a `builtinInstrument`; give each lane its own `SynthPatch` (persist),
   and open the existing PatchEditorView / Sound panel from the TRACK door
   (ArrangeTimelineView), not the global chip. Generate applies the lane's patch to
   that lane's voice (LaneVoiceRack). Global Sound chip → removed once per-track works.
2. **Per-track Genre + Variation (optional).** Lane gains optional `genreOverride`
   + `variationSeed`; when set, the composer composes THAT lane in its own genre
   (multi-genre simultaneously) using BioVariationMaze for the variation. Default
   off = today's single global genre. Reuse makeComposerInput per lane.
3. **Weather as an optional per-instrument tool.** Move the weather-mix influence
   behind a per-lane toggle (default off); the global weather plumbing already
   exists (WeatherMood) — expose it per instrument.
4. **Header-up: Key/Scale/tuning/tempo + Session name/place** (compact top bar or
   header disclosure), + manual place-name entry field. Render-safety: any live
   read stays in a leaf; no growth of the EchoelStudioView sheet chain.
5. **Retire the dissolved chips** as each replacement proves out (honesty interlock,
   like decision #198: a chip falls only when its new home WORKS).

## Guardrails
- Render-safety laws hold (no new .sheet in EchoelStudioView; no 10 Hz read in a
  menu-hosting ancestor; header live reads in leaves).
- Reversible: keep dissolved panels' builders in code until their new home ships.
- Per-track composition must not touch the audio thread with allocation; the
  composer stays on the control plane (BioComposer pure), voices pre-allocated.
- Founder confirmed the per-instrument direction ("optional anschalten und angeben").
