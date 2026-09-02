# PLAN — Professionally complete ALL DMMW components (Arrangement → Live Colabo → zentrierte Meditation)

> ⛔ **SCOPE NOTE (audit 2026-09-02): this plan predates the product definition of 2026-07-25**
> (`docs/dev/PRODUCT_DEFINITION.md`, Editor ≠ Workstation). Where it names timeline / clips /
> arrangement / multitrack / lanes-as-tracks / AUv3 / broadcast / drums / piano-roll surfaces, those
> are CUT and that part is history — do not execute it. Nothing below was edited; check the
> definition before building from any line here.


Founder (2026-06-23): "Alle DMMW Komponenten professionell ausarbeiten von Arrangement über Live Colabo
bis zentrierte Meditation." Priority context (prior msg): FIRST the program solid with optimized
architecture + design; then visuals presets (done), in-app EchoelAI chat, cross-device/community.

Synthesised from a 3-agent ground-truth audit (timeline · renderers/router/channels · bio/meditation/collab),
2026-06-23. Reference: docs/dev/DMMW_ARCHITECTURE.md.

## VERDICT: the DMMW is far more built than its reputation
Most of L1–L4 is BUILT+WIRED. The honest gaps are polish (visual timeline, audio-clip playback, mixer
depth, transport unification) + two NEW pillars (Meditation, Live Colabo). Build only real gaps; do not
re-foundation what already ships.

## COMPONENT LEDGER (state → target → cheapest pro slice)

### Timeline (L1)
- Transport — BUILT+TESTED, NOT the live clock (PatternEngine owns it). → Make Transport the single clock.
  Slice: PatternEngine becomes a Transport subscriber (remove its timer); re-run Transport/Pattern tests.
- Arrangement (model/player/store) — BUILT+WIRED; UI is a LIST. → Visual timeline canvas. Slice: TimelineView
  (bars ruler, draggable/resizable clip blocks, playhead from Transport.position.bar). Medium.
- Clips — MIDI playable; Audio/Video/Visual typed-but-inert (honest). → Audio clips first. Slice: wire
  AudioClipPlayer+AudioClipRegion into ArrangementPlayer on section entry/exit. Video/Visual = later.
- Automation — master level + tempo wired; per-bar only. → Song-position automation. Slice: pass
  Transport.position.bar into AutomationPlayer; lanes addressable by song bar.

### Renderers (L4) — ALL BUILT+WIRED (visual/light/spatial, music+bio driven)
- Visual (MetalBioView, SpectralDonutView + presets Aura→Zentrifuge ✅), Light (Art-Net/sACN ✅),
  Spatial (ADM-OSC ✅). Video = STUB/roadmap. → Enrich: add spectrumBands + per-track transient to
  MusicalFrame for "drums punch the visual" reactivity (small, additive).

### Channels / Mix (L2)
- Channel rack — BUILT (8 drum tracks: sample/synth/blend + insert FX + mute/solo/level). Not FL-style
  arbitrary instruments; no pan/sends. → Per-channel pan + a real mixer view; later: per-channel AUv3
  instrument (compose with the hosted AUv3 arc).
- AUv3 host — BUILT+WIRED (discovery/load/play/insert chain/master FX/plugin UI/state save). → Integrate as
  a channel instrument choice + a routable patchbay port.

### Routing (L7)
- Signal Router + Patchbay — BUILT+WIRED, on-demand sender start, honest live/soon. → Wire roadmap
  transports as real adapters: **Ableton Link** (clock — also the Live-Colabo backbone), MIDI 2.0/UMP
  (cores already built: UMPEncoder/MPEExpression), AUv3-as-port.

### NEW pillar — zentrierte Meditation  ← STARTED THIS CYCLE
Foundation Grade-A + wired (BreathPacer resonance ~6/min, BreathPattern, HRVCoherence Lomb-Scargle/Welch,
BreathGuideView, immersive visuals, esotericMeditation genre). SessionRecorder = BUILT-NOT-WIRED.
- ✅ Slice 1 (this cycle): MeditationView — duration picker + breath circle + live coherence + countdown +
  records via SessionRecorder (now injected) + end-of-session summary + recent-sessions history. Tools ▸
  Meditation. Composes tested cores; no audio-thread risk.
- Next: guided programs (7/21-day), streaks/achievements, a coherence-trend chart, a calm "meditation mode"
  that auto-selects esotericMeditation + an Aura-class visual, and a persistent Well/Meditation surface in
  WorkspaceView (currently a Tool).

### NEW pillar — Live Colabo (collaboration)
Today: broadcast-only (MIDI/OSC/ADM/Art-Net/sACN out, RTP-MIDI in). CloudSync BUILT-NOT-WIRED. No Link,
no Multipeer, no shared jam. Professional path (open-standards, no lock-in):
1. **Ableton Link** — tempo/beat sync to any Link app/DAW on the LAN (the cheapest real multi-device win;
   also a router clock port). 
2. **MultipeerConnectivity** — local peer discovery → shared transport (start/stop/tempo) + clip/loop
   exchange for jamming; bio "shared coherence circle" as the Echoel-unique twist.
3. **CloudSync UI** (Phase 1, iCloud entitlement) — cross-device session save + community share of
   loops/presets/visual presets.
Sequenced after Meditation + the timeline polish (heaviest, needs entitlement + device pairing to verify).

## SEQUENCING (each a shippable, gate-green cycle; deploy between)
1. ✅ Meditation Slice 1 (this cycle).
2. Transport unification (lowest-risk architecture win — the founder's "optimized architecture" priority).
3. Visual timeline canvas (Arrangement pro UI).
4. Audio clips in the arrangement.
5. Ableton Link (clock) → first Live-Colabo foundation.
6. Per-channel pan + mixer view; MusicalFrame spectrum/transient enrich.
7. Meditation programs/streaks/trend + Well surface.
8. MultipeerConnectivity jam + CloudSync UI (Live Colabo full).
9. MIDI 2.0 transport, AUv3-as-channel-instrument, Video/Visual clip engines.

## GUARDRAILS
Architecture-first (the founder's stated #1): every cycle keeps build+CI+iOS gate green, no regressions,
lowest-churn, reviewed. Protected Rausch triad untouched. Audio-thread rules. EchoelValueField/EchoelPanel,
≤3 Hz flash, no glow. Claim only what ships (typed-but-inert stays honest). Deploys are autonomous.
