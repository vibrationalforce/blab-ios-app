> ⛔ **SUPERSEDED — do not execute (banner 2026-08-28).** This plan commands scope the Editor ≠ Workstation boundary (docs/dev/PRODUCT_DEFINITION.md, 2026-07-25) has CUT or that #121/#166/#167 dismantled. History only; ROADMAP.md + vision.md win over any PLAN file.

# PLAN — Professional Production Suite (the All-in-One pivot)

**Decision (2026-06-20, founder):** Echoel pivots from "focused bio instrument +
object SOURCE that interoperates" to **the all-in-one professional production
environment** — performance / broadcast / installation / content production.
First wave authorized: **Clips/Session + Arrangement · Ableton Link · Broadcast
RTMP · Video capture/edit foundation.**

> This supersedes the prior positioning in `memory/vision.md` ("interop, NOT a
> general DAW/NLE"). vision.md + ROADMAP updated to match. The founder's call wins.

## Honest framing (kept, not buried)
- This is a **multi-quarter** build and a deliberate move away from two standing
  principles: *near-zero deps / no SDK lock-in* (RTMP needs HaishinKit; Link needs
  the Ableton C++ lib; NDI = proprietary SDK) and *one-paradigm / no breadth-first*.
  We mitigate by **one Ralph cycle at a time, CI-green + device-verified each step**,
  and by reusing what already ships (the bio bus, EchoelStudioView, EngineBus).
- Each dep is added in its OWN isolated cycle and gated.

## Ist-Stand (code-verified 2026-06-20)
- **Clips/Session: DONE & WIRED** — `Clip`/`ClipStore` + `ClipView` (Tools → Clips),
  injected at app root. Capture/launch/rename live. (FEATURE_MATRIX was stale.)
- **Arrangement: BUILT, UNWIRED** — `Arrangement`/`ArrangementSection`/`ArrangementCursor`
  (pure, tested) + `ArrangementStore` (full CRUD, persists "song.json") +
  `ArrangementPlayer` (rides PatternEngine via `transportStep`). **No UI, not injected,
  transportStep never fed.** ← Wave-1 first build.
- **Multitrack:** `MultiTrackRecorder.swift` skeleton only.
- **Video:** `CameraCapture`/`CameraAnalyzer` = rPPG only; no recorder/trim wired.
- **AUv3 HOST:** zero code (we ship the generator *plugin*, not a host).
- **RTMP/Broadcast:** zero code; HaishinKit not in deps.
- **Spatial audio:** ADM-OSC object source LIVE; binaural/multichannel/Atmos staged.
- **Light/physical translation:** Art-Net + sACN LIVE.

## Realization sequence (one CI-green cycle each)

### Wave 1
1. **Arrangement timeline UI** (this cycle) — `Studio/ArrangementView.swift` on the
   existing store/player; inject `ArrangementStore`+`ArrangementPlayer` at app root;
   feed `transportStep` through `PianoRollModel`'s onTick (before note trigger, so a
   section's clip is loaded at the 15→0 wrap). Tools → "Arrangement". No new deps.
2. **Ableton Link** — isolated dep cycle. Link is C++ (LinkKit) → needs an explicit
   dep-exception decision (violates no-C++). Wrap in `Sync/AbletonLink.swift`
   (@MainActor @Observable), tempo/start-stop sync to the shared clock. GATE: confirm
   the C++ exception before adding.
3. **Broadcast RTMP** — add **HaishinKit** (MIT, pinned) in its own cycle; build-verify
   empty; then `Stream/RTMPPublisher.swift` (@MainActor @Observable) + a Stream sheet
   (URL/key in Keychain, bitrate) + A/V pipeline (master tap → CMSampleBuffer; camera
   → video) + reconnect/thermal clamp. Per `PLAN_W3_STREAM`. Allowed new dir `Stream/`.
4. **Video capture/edit foundation** — `Video/CameraHub` fan-out (one AVCaptureSession
   → rPPG + record + visual), `Video/VideoRecorder.swift` (AVAssetWriter H.264/AAC),
   a trim lane in the Arrangement view, MP4 export (VideoToolbox). Per
   `PLAN_ARRANGEMENT_VIDEO_ONE_VIEW` + `SPEC_CAMERA_PIPELINE`.

### Wave 2 (after Wave 1 verified on device)
5. **Multitrack audio** recording/console (flesh out `MultiTrackRecorder`).
6. **AUv3 HOST** — `AVAudioUnitComponentManager` discovery + host graph +
   `AUViewController` plugin-UI hosting. Large new subsystem; own mini-plan.
7. **Spatial audio Stage 1** — on-device head-tracked binaural (`AVAudioEnvironmentNode`/PHASE).
8. **Installation** — shared clock (Link/PTP) + multicast OSC/sACN + external display out.

### Wave 3 (north-star convergence)
9. Visual mapping (external display warp/edge-blend; NDI = gated dep), spatial video,
   visionOS immersive, multichannel/Atmos authoring.

## Guardrails that still hold
Audio-thread sanctity · protected DSP triad read-only · accessibility-first ·
`EchoelValueField` for params · one `EchoelStudioView` (sheets/pillars, not a tab
explosion) · science-only copy · CI-green + device-verified before claiming.
