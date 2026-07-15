# PLAN — P3 Video + Import overhaul (founder 2026-07-15)

Founder ask (verbatim intent):
1. Video: request FULL photo-library access.
2. Image import ("Bilder importieren soll auch gehen").
3. Video CAPTURE — record with the iPhone camera directly INTO the timeline.
4. All iPhone-camera functions + pro settings like the Blackmagic app; manual Kelvin (white balance) entry.
5. MIDI & Audio import must be implemented / improved.
6. Long-press the EMPTY lane in the timeline = "import on the spot" for all track types.

## What already exists (grounding)
- `.lane(TimelineLane)` modal → `editor(forKind:landingLane:)` routes by lane kind:
  audio → `AudioClipView` (import), video → `VideoClipView` (import), midi → `PianoRollView`.
  Reachable today ONLY from the lane-HEAD menu.
- `Video/`: `CameraCapture`, `VideoRecorder`, `VideoMuxer`, `VisualRecorder`.
- `Sequencer/VideoClipFactory`, `Core/MediaLibrary`, `Studio/VideoClipView` + `AudioClipView`.
- Audio + video import into a lane shipped in the D2/E2 series (v216/v217).

## Decomposition (Ralph cycles, cheapest first)
- **V1 (SHIPPED this cycle — long-press empty lane → import):** add a `.contextMenu` on
  the empty lane body that opens `activeModal = .lane(lane)` — the kind-appropriate import/
  editor. No new permission/capability; reuses the existing modal. Freeze-safe (contextMenu
  builds on open), no sheet-chain growth. Founder's item 6.
- **V2 — Full photo-library access:** add `NSPhotoLibraryUsageDescription` (Info.plist,
  founder-authorized) + request `PHPhotoLibrary` authorization in `VideoClipView`'s import;
  handle limited/denied gracefully. Founder item 1.
- **V3 — Image import:** images land as STILL clips on a video lane (a frame shown for N
  bars). Extend `VideoClipFactory`/`MediaLibrary`; picker accepts images. Founder item 2.
- **V4 — Video capture into the timeline:** a "Record video" entry (from the video lane /
  its import view) → `AVCaptureSession` records to a file (`VideoRecorder`), lands it as a
  video clip on the lane at the playhead. Needs `NSCameraUsageDescription` +
  `NSMicrophoneUsageDescription`. Founder item 3.
- **V5 — Pro camera controls (Blackmagic-style):** manual focus / ISO / shutter (exposure
  duration) / white-balance via KELVIN (`AVCaptureDevice` lock + `whiteBalanceGains` from a
  Kelvin→gains conversion), on the capture UI. Founder item 4.
- **V6 — MIDI import improve.** Founder item 5.
- **V7 — Audio import improve.** Founder item 5.

## Laws to respect
- Info.plist edits: founder explicitly asked for library/camera access → authorized (V2/V4).
- No new top-level dirs (`Video/` exists). No sheet-chain growth (use the ONE `.sheet(item:)`).
- Camera is a high-freq source → never `Task { @MainActor }` per frame; batch (see
  CameraRPPG pattern). Freeze rule for any live preview (leaf views only).
- Flash ≤ 3 Hz; audio-thread lock/alloc-free (capture is off the audio thread).
