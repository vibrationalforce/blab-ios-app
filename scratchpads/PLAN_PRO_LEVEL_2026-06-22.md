# Echoel — Pro-Level Repo Audit & Roadmap (2026-06-22)

> ⛔ **SCOPE NOTE (audit 2026-09-02): this plan predates the product definition of 2026-07-25**
> (`docs/dev/PRODUCT_DEFINITION.md`, Editor ≠ Workstation). Where it names timeline / clips /
> arrangement / multitrack / lanes-as-tracks / AUv3 / broadcast / drums / piano-roll surfaces, those
> are CUT and that part is history — do not execute it. Nothing below was edited; check the
> definition before building from any line here.


Founder directive: reach **highest-level** DAW · Video editing · Mapping · Visuals · Light ·
Streaming for the multi-touch future (touch MacBook / iOS 27). Cover the **full efficacy
spectrum of audiovisual "therapy"** — **NO CLAIMS** (experiment/research, partner with
health/social/education/culture). Clubs & festivals matter → all video/visual/light/laser
to **industry standards**. Piano Roll + Arrangement to **Ableton level** (typed clips:
Audio·MIDI·MIDI2.0·MPE·Video·Visual, with **automation** + MIDI & audio **effects**).

Five parallel read-only audits were run. Findings + prioritized plan below. Build-green is
the only gate (no Swift toolchain in sandbox → every cycle compile-gate-verified).

---

## 1. AUDIOVISUAL "WIRKSPEKTRUM" + CLAIMS — strongest area, nearly done

**Coverage: 8/8 peer-reviewed mechanisms already present** (research-instrument framing, not claims):
HRV-coherence biofeedback, resonance/slow-breath pacing, heart/breath/coherence sonification,
audiovisual entrainment (EchoelEntrainment delta…gamma, flash-clamped ≤3 Hz), circadian/
wavelength light (LightScienceInfo + SpectralColor + Art-Net), colour↔emotion (cited), spatial
(ADM-OSC), vibrotactile/felt bass (SubBass + CoreHaptics). **Claims scan: ZERO violations**;
disclaimers comprehensive; no esoteric terms user-facing (one internal enum `esotericMeditation`
→ shown as "Deep Ambient", harmless).

**Reframe:** "health" → **research + performance + creative self-observation**. Moat = transparency
(real Lomb-Scargle coherence, open standards, on-device/private, tap-to-learn with citations).

**Cheapest next steps:** (a) LOCK the guardrail with a lint/pre-commit rule forbidding
claim/esoteric terms in `Sources/**` + `docs/**` (prevents future drift); (b) `docs/research-spectrum.html`
(mechanism × file × citation table) for institutions; (c) a "Research Edition" note (data export,
on-device privacy, OSC for studies); (d) rename `esotericMeditation` enum for consistency.

## 2. DAW DEPTH (clips · arrangement · automation · channels) — real but shallow

Honest state: typed clips exist (`ClipKind` midi/audio/video/visual) but **only MIDI is playable**;
arrangement is a **single-track** section chain (ArrangementPlayer rides PatternEngine), not parallel
lanes; **NO automation** (ModulationMatrix is bio-driven, not time-based envelopes); channels =
8 drum pads + 1 melody voice + AUv3 instrument/insert/master chains, **no per-track insert FX / sends /
buses / MIDI-FX**. MIDI 2.0 input + MPE present; per-note expression streaming + MIDI-CI roadmap.

**Ranked gaps → cheapest first step:**
1. **Automation lanes** (biggest pillar): `AutomationLane` value type (param key + [(barTime,value)]) on Arrangement/track; playback reads keyframes → param; thin curve UI. ← start pure+tested.
2. **Multi-track arrangement**: `Arrangement.tracks: [ArrangementTrack]` (typed lanes, clips positioned in time) + 2-D cursor + grid UI.
3. **Per-track insert FX**: give each drum pad / channel its own `EchoelFXChain`; a Channel-Rack strip (fader/mute/solo/FX).
4. **Audio clip engine**: `AudioClipPlayer` (AVAudioPlayerNode, trim/loop) — no dep.
5. **Video clip engine**: AVPlayer on the timeline, transport-synced — no dep.
6. **MIDI FX chain** (arp/humanize/scale) pre-instrument (Humanizer exists, export-only today).
7. **Bus/send/aux** model. 8. **Ableton Link** clock (authorized dep, own cycle).

## 3. PIANO ROLL PRECISION — structural; PPQ is the keystone

Step-quantized only (`Note.startStep/lengthSteps: Int`, 16 steps/bar); **no sub-step/PPQ**;
playback is MainActor-timer step-boundary (not sample-accurate); editing is minimal (tap/drag add,
inspector velocity/length) — **no multi-select, marquee, nudge, move-drag, edge-resize, snap options,
draw/select tools, undo**; zoom linked H+V (~3.5×), only 4 octaves, no pitch scroll.

**Ranked → keystone first:**
1. **PPQ ticks in `Note`** (add `startTick`/`lengthTicks`, derive step; clamp; tests) — unblocks unquantized capture, nudge, swing-snap, tighter export. ← cleanest safe first cycle.
2. **Sample-accurate playback** (AVAudioSourceNode tick) — bigger.
3. Multi-select + marquee + nudge. 4. Move-drag + edge-resize. 5. Draw/Select toggle + snap menu. 6. Independent zoom + pitch scroll + octave range.

## 4. LIGHT / LASER / VIDEO / VISUAL / SPATIAL — light & spatial pro-grade; rest staged

- **LIGHT (Art-Net + sACN): production-grade, tested, flash-safe.** Gaps: **fixture library/profiles**
  (drive a real rig, not 4 fixed channels), **multi-universe** (array of senders), **timecode/genlock**
  (Ableton Link). ← fixture library + multi-universe are no-dep, high-value for clubs.
- **SPATIAL (ADM-OSC): production-grade.** Gaps: timecode sync, multi-object (array), PHASE head-tracking.
- **VISUALS:** MetalBioView + new SpectralDonutView ship on-device; **club projection = Resolume/MadMapper
  over OSC (already possible via VJ_BRIDGE.md)** — amplify the doc; external-display/warp/NDI are Mac-side.
  Orphaned `Video/Shaders/*.metal` (cymatics/harmonics) — wire or document.
- **VIDEO:** capture = rPPG only (not recording); RTMP/SRT scaffold (HaishinKit FINISH spec written,
  camera-vs-rPPG exclusivity decided). **Cheap, no-dep wins: VideoRecorder (AVAssetWriter) + AVPlayer clip
  playback.** NDI = proprietary SDK (gated).
- **LASER:** absent on-device & not feasible natively; **standard path = OSC params relayed to a tethered
  Pangolin/LD2000** → publish the OSC laser namespace + doc (no SDK, no on-device beam = safest).

## 5. NAVIGATION / MENU — clear & functional today; needs a persistent collapsible bar

Current IA: WorkspaceView top switcher (Arrange · Clips · Compose, all ZStack-mounted) + on the
Compose surface a top BioStrip + a horizontally-scrolling **13-chip Tools row** + collapsible
EchoelPanels + ~17 sheets/covers. **Function check: NO dead buttons** — every entry works or is
honestly tagged "soon"/"engine coming" (passes "every screen does something"). The weakness is
exactly what the founder said: navigation is split across a top picker + a scrolling chip row +
menus, and nothing is a single **persistent, collapsible** menu.

**Recommended (low-risk, from the audit):** one **persistent bottom workspace bar** (Arrange ·
Clips · Compose · Tools · Visual), icon-only by default with a chevron to show labels; **Tools**
expands an inline collapsible chip row above it (move the existing `toolsRow` up to WorkspaceView,
shared across surfaces). Surfaces stay mounted (audio lifecycle untouched) → chrome-only change,
low risk. Uncodixfy-compliant (EchoelTheme, ≤8px radius, no glow). Scales to the touch-MacBook as
a left sidebar variant later. Cheapest steps: (1) footer bar replaces the top picker; (2) shared
collapsible Tools row; (3) label/icon toggle; (4) harmonise Arrange/Clips/Patchbay panel vocab.

---

## RECOMMENDED SEQUENCE (each a gate-verified cycle; pure foundations first)

**Wave A — foundations (safe, testable, unblock everything):**
- A1. **Piano-roll PPQ `Note` model** (precision keystone). 
- A2. **AutomationLane data model** (DAW keystone) + arrangement playback hook.
- A3. **Claims guardrail lint** (locks the brand line — cheap, durable).

**Wave B — pro reach (mostly no-dep):**
- B1. Light **fixture library + multi-universe** (club rigs).
- B2. **VideoRecorder (AVAssetWriter)** + **audio/video clip playback** on the timeline.
- B3. Per-track **insert FX** + Channel-Rack strip; MIDI-FX (arp/humanize).
- B4. Navigation restructure (persistent/collapsible menu) per the IA audit.

**Wave C — dependency/device-gated (founder-verified):**
- C1. Ableton Link (timecode/clock sync) — authorized dep, own cycle.
- C2. HaishinKit A/V (per BROADCAST_HAISHINKIT_FINISH.md).
- C3. Multi-track arrangement grid (2-D), sends/buses, NDI (gated), laser OSC relay doc, PHASE head-tracking.

**Sound (separate, founder hears it):** dsp-review found the code is safe/clean; the "cheap vs pro"
levers are unison/detune, envelope-tracked MusicalFrame amplitude (also fixes donut visual sync),
felt-sub-by-default + missing-fundamental, brighter/animated default patch, equal-power harmonicity
crossfade + 10/60 Hz bio-LFO fix. These change the SIGNATURE sound → founder picks (can A/B on device).
