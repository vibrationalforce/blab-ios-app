# Echoelmusic — Competitive Analysis & Stable-First Roadmap (2026-06-16)

> ⛔ **SCOPE NOTE (audit 2026-09-02): this plan predates the product definition of 2026-07-25**
> (`docs/dev/PRODUCT_DEFINITION.md`, Editor ≠ Workstation). Where it names timeline / clips /
> arrangement / multitrack / lanes-as-tracks / AUv3 / broadcast / drums / piano-roll surfaces, those
> are CUT and that part is history — do not execute it. Nothing below was edited; check the
> definition before building from any line here.


Trigger: owner — "Are there more EchoelTools for the current TestFlight? Stable first, good
planning is most important. We want to be better than FL Studio, Cubase, Zenbeats, Loopy Pro,
Ableton Note. The arrangement / live-clips / video / visual / light / event / live-broadcast
features are still exciting — once biofeedback (for ALL heart devices) really stands."

## Positioning (do NOT try to out-DAW the incumbents)
Echoel wins as the **only bio-reactive live instrument** with open-standard light/spatial/broadcast
reach — NOT as a more-mature DAW. Lead with the moat; reach parity only where it converts the
generative engine into a *performable* instrument.

### Hard-to-copy moat (lead with these)
- Bio-reactivity as a first-class modulation source (HR/HRV/breath/motion) — none of the 5 rivals.
- Generative composition driven by physiology (not loop arrangement).
- Open standards, no lock-in: MIDI 2.0/MPE, OSC, ADM-OSC immersive, Art-Net light.
- On-device, private, free. Accessibility-first body-as-controller.
- Protected Rausch DSP triad (deconvolver, event graph, Hilbert mapper).

### Capability snapshot (verified June 2026)
- FL Studio Mobile: linear+patterns, multitrack audio, deep roll, **no AUv3 host** (IAA only), ~$14.99.
- Cubasis 3: full DAW, multitrack, **Ableton Link (3.4)** + BT audio rec (3.8), $49.99/often $29.99.
- Zenbeats: linear+clip hybrid, hosts VST/AU/AUv3 + Link + MPE, free + unlocks / Roland Cloud sub.
- Loopy Pro: **best-in-class looper/clip-launch + strong AUv3 host**, one-time ~$29.99.
- Ableton Note: **clip/session-first**, Cloud sync (no Link), offline MIDI edit, $8.99/often $4.99.
- Echoel today: bio-reactive generative + 16-step beats + polyphonic piano roll + patch editor +
  sample browser + WAV/MIDI export + AUv3 *plugin* + OSC/ADM-OSC/Art-Net. **No** audio-track
  recording, **no** linear arrangement, **no** clip/session grid, **no** video/stream, **no** Link.

## Parity gaps that matter (ranked, as a creation tool)
1. Audio-track recording (mic/instrument over the beat) — #1 universal gap. (MultiTrackRecorder scaffolded.)
2. **Clip/session launching** — the live wedge (Loopy/Note core).
3. Ableton Link — cheap credibility, table stakes.
4. Arrangement timeline — finish songs.
5. Deeper MIDI edit + manual automation lanes.
6. Sampler depth (multisample/slice/time-stretch).
7. Time-stretch / tempo-independent audio.
8. Stems export.

## STABLE-FIRST sequencing (founder's rule)

### Phase 0 — GATE: "Biofeedback really stands" (Bio Acceptance v1) — blocks all big features
| Dimension | Acceptance criterion |
|---|---|
| Source coverage | Apple Watch/HealthKit · any BLE 0x180D strap · camera rPPG · graceful Demo; ANT+ explicitly out-of-scope (document, don't fake) |
| Reconnection | BLE auto-reconnect < 5 s; clear connecting/live/lost UI; no crash/freeze on background |
| Signal validity | per-source validity/confidence flag; invalid frames suppressed from synthesis; rPPG "lock vs searching" |
| Latency | HR visible ≤ 2 s (Watch ~4-5 s, never beat-sync); BLE strap ≤ 1 s; never block audio thread |
| Correctness | RMSSD self-computed (not Apple SDNN); coherence reproducible vs a reference within tolerance; method documented |
| Stability | 30-min continuous all-source session, zero crash; permission-denied handled per source |
| Source switching | hot-swap mid-session, no dropout/NaN |
→ Make this an automated test/checklist gate. Until green, no arrangement/video/light expansion.

### Phase 1 — ship into CURRENT TestFlight now (low risk, additive)
- **Surface the already-built-but-unreachable tools** (the big find): `PianoRollView`, `PatchEditorView`,
  `SampleBrowserView`, `EchoelFXView`, `EchoelMixView`, `ComposeView` are fully built & compiling but
  **no UI opens them**. Add entry points (toolbar → sheet), verifying each view's `@Environment`
  deps are injected at the app root, one at a time, dry-run-verified. Pure UI, no engine change.
- Tempo-synced FX (delay note-values via existing TempoSyncOption/StudioCalculator) + character params.
- Ableton Link (clock send/receive) — isolated module, high credibility/effort.
- Bio source-state UI (connecting/live/lost + validity badge) — advances Phase 0 + hardens stability.

### Phase 2 — AFTER Phase 0 green
1. Audio-track recording (mic over beats) — closes biggest gap.
2. **Clip/session view = the wedge** — build on existing PatternEngine data first (no new audio engine);
   converts the generative engine into a live bio-reactive instrument no rival can match.
3. Ableton Link (if not already in Phase 1).
4. Arrangement timeline.
5. Video capture + RTMP broadcast (new AVFoundation + HaishinKit; higher risk).
6. sACN lighting (Art-Net already live).

## Wedge pick
**Clip/session launching** — highest identity-fit, lowest new-engine-risk, and the headline of the two
most-loved rivals. Supported by audio recording + Ableton Link.

## Bottom line
Lock Bio Acceptance v1 first (founder's rule AND moat credibility) → drive the clip/session wedge →
audio recording + Link as supporting parity → then arrangement, then video/visual/light/broadcast.
