# W2 — Video Engine (CameraSession + VideoRecorder + ClipTrimmer)

**Status:** Ready-to-execute. Activates AFTER W2_RECORDER ships green.
**Dependencies:** AVFoundation only. No external dep needed. Uses existing `AudioEngine` for A/V sync.
**Estimated cycles:** 7 atomic commits, ~3 day equivalent of focused work.
**Crash-safety strategy:** Same as W2_RECORDER — files dormant first, then wired in separate cycles.

---

## Goal

Capture 1080p30 video (front or back camera) WHILE the BeatPlayer pattern is playing. Audio track of the video file comes from the master audio bus (so the video records what the user hears, including the beat). Optional trim (in/out points) before export.

## Non-Goals (defer to v10.3+)

- Multi-clip timeline / sequencing
- Real-time filters / color grading
- Slow-motion / time-lapse
- Picture-in-picture / multi-camera
- Stabilization (hardware support varies; defer)

---

## Architecture

```
CameraSession (NEW, @MainActor @Observable)
├── captureSession: AVCaptureSession         ← managed lifecycle
├── videoDevice: AVCaptureDevice             ← front/back toggle
├── videoInput: AVCaptureDeviceInput
├── videoOutput: AVCaptureVideoDataOutput    ← delegates frames to writer
├── audioInput: AVCaptureAudioDataInput      ← NIL (we use AudioEngine for sync)
├── isRunning: Bool
└── methods: start(), stop(), togglePosition()

VideoRecorder (NEW, @MainActor @Observable)
├── assetWriter: AVAssetWriter?              ← H.264 + AAC mux
├── videoInput: AVAssetWriterInput
├── audioInput: AVAssetWriterInput
├── isRecording: Bool
├── duration: Double
├── lastURL: URL?
└── methods: startRecording(), stopRecording() async -> URL

ClipTrimmer (NEW, @MainActor @Observable)
├── sourceURL: URL
├── inPoint: Double                          ← seconds
├── outPoint: Double                         ← seconds
└── method: exportTrimmed() async throws -> URL  ← AVAssetExportSession
```

**A/V Sync source:** Audio frames flow from `AudioEngine.masterMixer` via a new `installTap` (separate bus from RetroCapture and MultiTrackRecorder; reuse if possible). Video frames flow from `AVCaptureVideoDataOutput.sampleBufferDelegate`. Both append to `AVAssetWriter` with their natural timestamps; AssetWriter handles muxing.

---

## Cycle Plan (one commit per cycle)

### W2-V1 — `CameraSession.swift` skeleton (DORMANT)

**File:** `Sources/Echoelmusic/Video/CameraSession.swift` (NEW)

Note: `Sources/Echoelmusic/Video/CameraCapture.swift` already exists (5623 bytes) as part of legacy v8 code. We don't replace it — we create a focused `CameraSession.swift` for v10 and let the old `CameraCapture` stay deprecated. Cleanup later.

Contents:
- `AVCaptureSession` lifecycle (configure, start, stop)
- Configurable preset (default `.high` for 1080p30)
- Front/back toggle
- Stub video output delegate
- No recording logic yet

**Commit:** `feat(video): CameraSession skeleton — dormant`

### W2-V2 — `VideoRecorder.swift` skeleton (DORMANT)

**File:** `Sources/Echoelmusic/Video/VideoRecorder.swift` (NEW)

Contents:
- `AVAssetWriter` setup with H.264 video + AAC audio inputs
- Codec settings: 1080×1920, ~8 Mbps, 30fps, AAC 44.1 kHz stereo
- Frame append method (called by `CameraSession`)
- `prepareForRecording()`, `startRecording()`, `stopRecording() async -> URL`
- Tail-time handling (flush remaining frames before finalize)

**Commit:** `feat(video): VideoRecorder skeleton — AVAssetWriter scaffold`

### W2-V3 — Camera permission UX + tab integration

**Files:**
- `Sources/Echoelmusic/Studio/VideoTab.swift` (NEW)
- `Sources/Echoelmusic/Studio/StudioRoot.swift` (UPDATE — replace VideoTabPlaceholder)

Permission flow:
- On VideoTab appear: check camera permission status
- If `.notDetermined`: show "Tap Start to enable camera" hint
- If `.denied`: show "Camera access denied. Open Settings."
- If `.authorized`: show preview + REC button immediately

Preview: `UIViewRepresentable` wrapping `AVCaptureVideoPreviewLayer`.

**Info.plist requirement:** `NSCameraUsageDescription` must exist. Verify in `project.yml` before this cycle reaches device. **Do not edit Info.plist directly without user OK.**

**Commit:** `feat(studio): VideoTab UI with camera preview + permission flow`

### W2-V4 — Wire CameraSession into VideoTab preview

Connect the existing capture session's video preview layer to the UIViewRepresentable. Camera is live but RECORDING button doesn't yet do anything.

**Verification:** Front/back toggle works. Preview renders. App still launches if camera is unavailable (simulator).

**Commit:** `feat(video): CameraSession wired to VideoTab preview`

### W2-V5 — Wire VideoRecorder into VideoTab REC button

REC button → calls `videoRecorder.startRecording()` and `cameraSession.videoOutput.setSampleBufferDelegate(videoRecorder, ...)`.

Stop button → `await videoRecorder.stopRecording() -> URL`, append URL to a session-local clips list.

Audio for the video: install a SECOND tap on `audioEngine.masterMixer` (third tap total — meter + RetroCapture + this). Per `AVAudioMixerNode` docs, multiple taps on the SAME bus are not supported. Solution:
- Add a dedicated `videoMixerNode` (new `AVAudioMixerNode`) after `mainMixerNode`, install tap there.
- OR: pipe RetroCapture's existing tap callback into both ring buffer and VideoRecorder when both are active.

**Choose option B.** Add a method `RetroCapture.subscribe(_: @escaping (AVAudioPCMBuffer, AVAudioTime) -> Void)` that VideoRecorder uses to receive audio buffers. RetroCapture remains the single tap owner.

**Commit:** `feat(video): VideoRecorder consumes audio via RetroCapture subscriber pattern`

### W2-V6 — `ClipTrimmer.swift` + Trim UI

**Files:**
- `Sources/Echoelmusic/Video/ClipTrimmer.swift` (NEW)
- `Sources/Echoelmusic/Studio/VideoTab.swift` (UPDATE — add trim sheet)

ClipTrimmer wraps `AVAssetExportSession` with `timeRange = CMTimeRange(start: inPoint, duration: outPoint - inPoint)`.

UI: dual-thumb slider, video scrubber preview, "Save trimmed" button.

**Commit:** `feat(video): ClipTrimmer + in/out trim sheet`

### W2-V7 — Photo library save / share

After recording or trimming, offer:
- "Save to Photos" (requires `NSPhotoLibraryAddUsageDescription` in Info.plist)
- "Share" (uses ShareLink with the file URL)

**Commit:** `feat(video): save to Photos / share sheet`

---

## Critical risks

1. **Audio session category collision.** `.playAndRecord` is fine for both recording and video capture, but `AVCaptureSession` will try to manage the session category itself. Solution: in `CameraSession.start()`, call `captureSession.usesApplicationAudioSession = true` to defer to our session config.

2. **Backgrounding while recording.** App Store reject if app crashes when phone locks. Add `UIApplication.didEnterBackgroundNotification` observer that calls `videoRecorder.stopRecording()` cleanly. Resume not possible — user must restart.

3. **Storage runaway.** 1080p30 ~7 MB/sec. A 10-minute recording = 4.2 GB. Add disk-space check before start (require 2 GB free). Add visual warning at 80% of available space.

4. **Front camera 30fps + processing.** On older iPhones (pre-A14), real-time 1080p30 encode + audio sync can overrun CPU. Add thermal-state observer (`ProcessInfo.thermalState`) and downgrade to 720p30 if `.serious` or worse.

---

## Bail conditions

- Camera doesn't work in simulator (expected, ok to ship behind device-only check)
- AVCaptureSession + AVAudioSession interaction causes audio dropouts during preview (would need redesign — possibly mute beat during recording, not ideal)
- App Review questions video disclaimer text → add explicit consent screen

---

## After this plan completes

Outcomes:
- VideoTab functional: preview, REC, stop, trim, save/share
- Audio in video matches beat that played
- 1080p30 H.264+AAC MP4 output

Triggers next plan: `PLAN_W3_STREAM.md` (HaishinKit RTMP).
