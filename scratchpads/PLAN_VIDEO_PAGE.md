# PLAN — Video page (DaVinci-style) · Cycle 6 of the DAW reorg

**Status: DESIGNED, DEFERRED (needs on-device verification).**
Decided 2026-07-01 during the autonomous window (founder unreachable). A full video
page is BIG, greenfield (P3/P4), and — unlike the other reorg cycles — cannot be
proven by the Xcode compile gate + a reviewer alone: it involves the Metal draw loop,
GPU capture, camera/file lifecycle and battery/thermal behaviour that MUST be watched
on a real device. Shipping it blind during a no-questions window violates the cardinal
"crashfrei/stable" rule. So: design captured here, code held for a session where the
founder can device-verify.

## What already exists (reuse, don't rebuild)
- `Video/VisualRecorder.swift` — records the bio-reactive Metal visual + master audio
  to an H.264 `.mp4` (blits the drawable inside the draw loop's command buffer). PROVEN,
  wired to the fullscreen-visual record button in `EchoelStudioView` (record → stop →
  `ExportedFile` → `ShareSheet`).
- `Video/VideoRecorder.swift` (AVAssetWriter sink), `Video/VideoMuxer.swift` (a/v mux).
- `MetalBioView` — the renderer; `VisualRecorder.capture(...)` only runs WHILE this view
  is drawing. This is the key constraint below.

## The hard constraint
VisualRecorder captures ONLY while `MetalBioView` is actively rendering. A "Video page"
that records therefore needs a live Metal view ON that page. But WorkspaceView keeps every
surface MOUNTED (ZStack+opacity), so an always-mounted `MetalBioView` would render
continuously across ALL surfaces → GPU/battery drain + thermal. Must be gated:
- Pause the MTKView (`isPaused = true` / stop its display link) whenever the Video surface
  is not the active surface, resume when active. Requires threading the active-surface
  flag into the `MetalBioView` representable and honouring it in `updateUIView`.

## Proposed design (when device-verifiable)
A **Video** surface (DaVinci "Deliver/Media" foundation — NOT a full NLE):
1. **Preview + record** — an embedded `MetalBioView` (paused unless this tab is active)
   with the proven record/stop button; on stop, save into a Documents/Recordings folder
   (not temp) so it persists.
2. **Recordings library** — enumerate the Recordings folder; each row: filename, duration,
   a thumbnail (AVAssetImageGenerator), tap → in-app playback (`VideoPlayer`), Share
   (existing `ShareSheet`), Delete.
3. **(Later) Trim** — in/out on a scrubber (needs `ClipTrimmer`, not yet built) →
   `AVAssetExportSession` trimmed export. Defer to its own cycle.

## Nav consideration
Bottom bar is already 6 tabs (Arrange · Clips · Compose · Mix · Bio · Browse). A 7th
(Video) is at the iPhone ceiling. DaVinci ships 7 pages, so it's defensible — but consider
grouping if a 7th feels cramped on the narrowest device (verify on device).

## Risks to watch ON DEVICE
- Always-on Metal across surfaces (battery/thermal) — the pause-gating MUST work.
- GPU capture path under AdaptiveQuality tier changes.
- File growth in Documents/Recordings (add size display + delete).
- Camera-session interaction if rPPG is running while previewing the visual.

## Verification
- Xcode compile gate + reviewer (as usual), THEN device: record 10–30 s, confirm playback,
  share, delete; watch thermal/battery over a few minutes; confirm no menu-freeze while the
  preview renders; confirm the preview pauses when you leave the tab (no background GPU).
