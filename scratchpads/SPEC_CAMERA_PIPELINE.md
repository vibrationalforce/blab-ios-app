# SPEC — Camera as ONE Shared Real-Time Input (multimedia · multidimensional)

The camera is **not** just a bio source. In the full Echoel vision it is a single
real-time input that **fans out to every layer at once** — bio, video, visuals,
broadcast, spatial. The camera is to multimedia what `EngineBus` is to
bio/MIDI/events: **one typed source, many consumers.**

## Hard constraint (drives the whole design)
You **cannot open the same camera twice** — one `AVCaptureSession` per physical
camera. So there must be **one `CameraHub`** that owns the session and fans each
`CVPixelBuffer` out to consumers. Per-feature capture sessions are forbidden.

```
                         ┌─▶ rPPG analyzer ──▶ bioFrames (EngineBus)      [EchoelBio]
 CameraHub (1 session)   ├─▶ ARKit face mesh ─▶ bioFrames / params        [EchoelBio]
   AVCaptureSession ─────┼─▶ video writer (H.264 / ProRes)                [EchoelVid]
   CVPixelBuffer fan-out ├─▶ Metal texture (chroma key, live layer, AR)   [EchoelVis]
                         ├─▶ RTMP encoder (live broadcast)                [EchoelNet/Stream]
                         └─▶ TrueDepth / world mesh ─▶ spatial/immersive  [visionOS, multidim.]
```

## Consumers across the vision (present status)
| Layer | Camera role | Code today | Status |
|---|---|---|---|
| **EchoelBio** | rPPG finger-pulse + ARKit face/expression → bioFrames | `CameraAnalyzer` (real rPPG: red-channel, 0.7–4 Hz Butterworth, peak+IQR, RMSSD) | **dormant** — not wired to bus (only via deprecated `BioSourceManager`) |
| **EchoelVid** | record / multi-cam / ProRes / NLE | `CameraCapture` (single session, `onFrame`) | PARTIAL |
| **EchoelVis** | live camera layer · chroma key · camera-driven generative/AR | `ChromaKey.metal`, `MetalBioView` | PARTIAL / roadmap |
| **EchoelNet/Stream** | camera → RTMP live broadcast | — (HaishinKit = sanctioned dep) | ROADMAP |
| **Multidimensional** | TrueDepth / face mesh / world tracking → spatial, visionOS immersive | — | ROADMAP |

## Real design tension (must be arbitrated by the Hub)
The same camera **cannot** serve all modes simultaneously:
- rPPG = **finger on the BACK lens + torch on** (photoplethysmography).
- Face tracking = **FRONT camera + ARKit/TrueDepth**.
- Performance video / chroma key = either lens, no torch.

→ These are **mutually exclusive camera modes**. The `CameraHub` owns the active
mode and arbitrates; UI must make the trade-off explicit (you measure pulse OR
film OR face-track — not all at once on one device). A second device (or
Watch/Polar for HR) removes the conflict — which is exactly why HR also comes
from HealthKit/Polar (no camera needed).

## Path (future-safe; every step DEVICE-verified — camera runtime is NOT CI-testable)
1. **`CameraHub`** — single `AVCaptureSession`, Swift-6-safe `CVPixelBuffer`
   fan-out (frames are non-Sendable → confine to a camera actor/queue; hand
   *derived* values — BPM, MTLTexture — to consumers, never raw buffers across
   actors). Replaces per-feature sessions.
2. **rPPG consumer → bioFrames** (the bio bridge; `CameraAnalyzer` already exists).
3. **Video recorder consumer** (EchoelVid).
4. **Metal visual consumer** (live layer + chroma key; texture handoff).
5. **RTMP consumer** (broadcast) — gated on HaishinKit approval.
6. **Spatial consumer** (TrueDepth/world) — visionOS era.

## Why this isn't built blind now
Camera capture is real-time, permission-gated, and **only verifiable on a
device** (session lifecycle, lens/torch, rPPG signal quality, ARKit). Building
the Hub + consumers blind under Swift 6 strict concurrency = the watch-embed
trap. So: architecture locked here (future-safe), website made honest about
dormant rPPG (present-safe), code built in a device session.

## Present-safe done
Website (faq + architecture) now marks camera rPPG **Planned**, not a live launch
biometric. Live bio = HealthKit + Polar H10 + Demo.
