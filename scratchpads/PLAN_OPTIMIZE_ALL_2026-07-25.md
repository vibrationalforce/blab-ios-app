# PLAN — "Sensoren · Sound · Visuals · Bedienung auf allen Ebenen optimieren"

**Founder 2026-07-25:** *"Einmal Sensoren, Sound, Visuals, und Bedienung auf allen
Ebenen optimieren. Gesundheit, Qualität, Latenz, vr/xr, immersive Erfahrung, spatial
audio und visuals."* Scored against the four quality axes
(`docs/dev/PRODUCT_DEFINITION.md`).

## Scope decision made up front (Council, 2026-07-25)

**XR = an OUTPUT TARGET over open standards, NOT a new platform.** No visionOS/ARKit
target before the ship gate. Spatial audio/visuals are hardened as *quality of the
existing output stage* (Layer 2). Re-opening this is a deliberate ship-gate slip, not
a side effect.

---

## What the four audits found (each verified against source, file:line in the reports)

### SENSORS — three CRITICALs, all "the number shown is not the number driving"
1. **Stalled camera published a frozen pulse with a fresh timestamp**
   (`CameraRPPGBioPublisher.swift:520` fell through to the publish block) → defeated
   every `freshBio`/`usableBio` gate; music+visual ran off a dead body through the 6 s
   detect window and up to an 18 s cold-restart backoff, while the UI said
   "recovering". **FIXED this cycle.**
2. **The only "trusted HRV" source has zero artifact rejection** —
   `PolarH10BioPublisher.swift:417` appends raw RR; one missed/extra beat inflates
   RMSSD by tens of ms, and it is displayed as a real ms figure. The *untrusted*
   camera path does clean its intervals (`CameraAnalyzer.swift:578`). Irony worth
   keeping in mind: the chest strap we call most accurate is the least filtered.
3. **A fabricated HRV of 0.5 is published as a real reading** —
   `EchoelBioEngine.swift:36` default + `HealthKitBioPublisher.swift:113`, plus two
   `?? 0.5` fallbacks downstream. A Watch with no HRV sample yet drives brightness and
   humanisation off an invented "medium HRV".
4. HIGH: displayed BPM is octave-folded and slewed, the BUS gets the RAW value
   (`:624-642` vs `:690`) — screen 98, synth 196.
5. HIGH: camera adds ~1 s of gratuitous latency (`guard tick % 10 == 0`, `:689`);
   BLE adds up to 1 s more via a fixed 1 s poll instead of publishing on arrival.
6. MEDIUM: **the 120 Hz bio-loop target in CLAUDE.md is fiction** — real path is a
   1 Hz publish into a 10 Hz poll; `AdaptiveQuality.bioHz`/`oscHz` have zero
   consumers. Restate the perf row honestly rather than pretend.

**Verified clean, do not chase:** the ÷200-vs-÷100 normalisation bug is genuinely
fixed (all sources route through `HRVNormalization.ceilingMs = 100`); BLE dropout
handling and the camera recovery ladder are robust; safety copy is compliant.

### SOUND — the chain is real, the render path is not yet clean

1. **CRITICAL: two audio-thread violations remain in the patch drain** — the render
   block allocates (C4) and sends an ObjC message (`caseInsensitiveCompare`, C5).
   Both are exactly the class of defect the `swift-audio.md` rules forbid outright,
   and both are in the path that runs on every patch change while playing.
2. **CRITICAL: filter cutoff is capped at 8 kHz (C1)** — the SVF cannot open past it,
   so every patch is lidded. A TPT SVF rewrite fixes C1 together with H7 (denormals)
   and H8 (zipper noise on cutoff moves) in one file.
3. **CRITICAL: export has no peak ceiling (C3)** — the master −1 dBFS trim is a live-bus
   thing; the exported file can exceed 0 dBFS and clip on decode.
4. **HIGH: measured latency ≈ 23–25 ms (C2)** vs the <10 ms target and the >15 ms FAIL
   line in CLAUDE.md. Biggest single lever is `setLatencyMode(.low)`; the target row is
   fiction until that is done and re-measured.
5. **HIGH: no anti-alias lowpass after `saturate` (H6)** — the one nonlinear stage folds
   its harmonics back down as inharmonic grit, which is precisely the opposite of the
   founder's "organic/professional" bar.
6. **Spatial, audio side:** an `AVAudioEnvironmentNode` spike is the cheapest native
   route to actually hearing placement (zero external deps).

**Correction to CLAUDE.md this audit forced:** the "API Gotchas" row for
`SpatialAudioEngine` describes a type that **does not exist anywhere in `Sources/`**.
It is fiction and must be deleted, not implemented against.

### VISUALS — the immersive half is weaker than it looks
1. **CRITICAL: thermal mitigation is inert for 9 of 10 looks** —
   `visualDetailScale` only scales `ringDensity`, which only reaches `fieldRings`;
   `targetFPS` and `allowSpectralDonuts` have zero consumers. Under thermal pressure
   the app believes it is degrading and is not.
2. **CRITICAL: note→colour latency ≈ 0.9 s** (60 Hz poll → `freshMusical` → weight
   ease 0.30 → RGB ease 0.18 → gate). The instrument's differentiator is
   sound↔image coupling, and the image is nearly a second late.
3. HIGH: anti-banding dither is applied in linear space while quantisation happens in
   sRGB → highlight banding survives, shadow grain is over-strong.
4. HIGH: no analytic AA anywhere (zero `fwidth`/`dfdx`); Chladni/Lissajous nodal lines
   reach ~1.3 px at high coherence → shimmer.
5. HIGH: **the physical colour is diluted to ~68 % chroma** before it is seen, and a
   luminance floor forces a deep red and a bright green to equal luminance — deleting
   exactly the eye-sensitivity truth the CMF mapping exists to carry.
6. HIGH: `BioVisualParams` is 5/6 dead — only `pulseHz` is read. HRV never reaches the
   Metal visual at all.
7. HIGH: ~10 heap allocations per frame on the main thread inside `draw(in:)`.
8. **120 fps is fiction** — pinned 60, never reassigned. No GPU-time measurement
   exists in the repo, so any "frame budget" claim is unverified.

### SPATIAL / XR — the export is real, the monitoring does not exist
- **Already shipping:** full ADM-OSC object output in 3 dialects, ONE consistent
  coordinate convention (az 0 = front, +az = left, verified consistent across
  `SpatialScene`, `ImmersiveStageMath`, `SpatialSceneOSC`), ~800 lines of tests, live
  over the Patchbay. A producer with L-ISA / SPAT / IEM can render Echoel today.
- **The honest gap:** *scene position affects EGRESS ONLY — moving a puck changes OSC
  and never changes what you hear.* The only audible placement is `TimelineLane.pan`,
  which is unlinked from `SpatialObject.position` **and sign-inverted** relative to
  azimuth (AVAudioMixing −1 = left vs azimuth +90 = left). Wiring it naively swaps L/R.
- `ImmersiveStageView` (the only spatial authoring surface, and the only
  `streamsScene` toggle) has **zero call sites** — doorless.
- No scene persistence (a placement dies on relaunch), no elevation/extent editing,
  no listener pose on the wire, `BinauralPanner`/`VBAPPanner`/`AmbisonicsEncode` all
  written and unwired, no `AVAudioEnvironmentNode`/PHASE anywhere.
- **"Spatial visuals" today means a 2D immersive canvas, not depth** — no parallax or
  3D scene exists. Say this plainly rather than implying otherwise.

---

## Sequence (one Ralph slice per cycle, reviewer + both gates each)

Ordered by harm × cheapness, not by domain. Each line ≤3 files.

1. ✅ **Camera truth-gate** — stop publishing a frozen pulse as live; carry the held
   frame's real timestamp. *Shipped this cycle.* Follow-up owed: six consumers read
   `latestBio` raw with no freshness gate at all (Sync/OSC·ADM·ArtNet·sACN,
   BioReactiveSynthVoice, PolySynthVoice) — the truth-gate stops the lie at the
   source, it does not give those a policy.
2. **Audio-thread patch drain** — remove the allocation (C4) and the ObjC
   `caseInsensitiveCompare` (C5) from the render block. Straight hard-rule
   violation; goes first among the sound work regardless of audibility.
3. **BLE signal hygiene** — RR physiological range + ectopic-difference filter, HR
   range guard. Closes the "most accurate source is the least filtered" irony.
4. **Kill the invented 0.5 HRV** — honest 0 (or optional) when no sample has arrived;
   drop the two `?? 0.5` fallbacks.
5. **TPT SVF rewrite** — lifts the 8 kHz cutoff lid (C1) and takes denormals (H7) +
   cutoff zipper (H8) with it. The single biggest "sounds lidded" fix.
6. **One BPM, not two** — publish the octave-folded value; keep the slew display-only.
7. **Export peak ceiling (C3)** — a rendered file must not clip; the live-bus trim
   does not cover export.
8. **Thermal mitigation that actually mitigates** — scale `drawableSize` by
   `detailScale` (the one lever every look obeys) + correct the 120 fps claim to 60.
9. **Note→colour onset** — feed `MusicalFrame` note-ons into the existing
   `TouchRippleChannel` so the onset is instant while the slow cloud ease stays. This
   is the single biggest "wow" win and adds no surface.
10. **Latency: `setLatencyMode(.low)` + re-measure (C2)** — then write the REAL number
    into CLAUDE.md instead of the <10 ms target it does not meet.
11. **Anti-alias after `saturate` (H6)** — stop the one nonlinear stage folding grit
    back into the band. Directly serves the "organic" bar.
12. **Sensor latency** — camera publishes every tick, BLE publishes on arrival
    (≈2 s → ≈0.1 s on the BLE path).
13. **Door the spatial stage** — `case stage` on the existing `CraftEditor` enum + one
    switch arm. Modifier count stays 12; this is exactly what that slot was built for.
14. **Spatial you can HEAR** — bridge azimuth+distance to the existing pan/gain with
    the sign flip pinned by a test (an `AVAudioEnvironmentNode` spike is the native,
    dependency-free alternative worth costing first). First slice where spatial stops
    being export-only.
15. **Colour truth** — move the luminance floor past `energy`, wire `vp.complexity`.
16. **Render hygiene** — hoist the per-frame allocations, single `freshMusical`.
17. **Honesty pass on CLAUDE.md** — 120 Hz bio loop, 120 fps and <10 ms audio are all
    unreachable as built; state the real numbers, and DELETE the `SpatialAudioEngine`
    "API Gotchas" row (the type does not exist).

**Deferred (needs the platform, post ship-gate):** head-tracked listener orientation
(`CMHeadphoneMotionManager`), stereoscopic/6-DoF visuals, room-anchored AR.

## Guards that apply to every slice here

- Sheet chain stays at 12 — a new editor is an enum case, never a modifier.
- No high-frequency `@Observable` read in a root/ancestor body.
- Audio-thread lock/alloc-free; protected Rausch triad READ-ONLY.
- Flash ≤3 Hz — and remember the lesson: **a clamped input proves nothing about the
  output rate.** Non-monotone ops (square, `abs`, product of two phase-bearing
  factors) multiply it; additive superposition unions the counts.
- Every capability needs a door; no health claim; `EchoelValueField` for numbers.
