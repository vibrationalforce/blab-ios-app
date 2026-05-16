# W2 — Record Engine (MultiTrackRecorder)

**Status:** Ready-to-execute. Activates AFTER Beat-MVP is device-verified green.
**Dependencies:** AudioEngine + BeatPlayer (both shipped). HaishinKit not required.
**Estimated cycles:** 6 atomic commits, ~2 day equivalent of focused work.
**Crash-safety strategy:** Add files in dormant state first (no caller wires them in), verify build, then enable in a separate cycle. Bisect-revertable per cycle.

---

## Goal

Record microphone audio WHILE the BeatPlayer pattern is playing, sample-accurate-aligned, output a 48 kHz mono `.caf` file per mic-track plus a separate `.caf` for the beat-mix-down stem. Result: two synchronized stems that re-mix perfectly when played back together.

## Non-Goals (defer to v10.2+)

- Multi-input device support (USB audio interfaces)
- Punch-in / punch-out / overdub
- Track-level EQ / compression
- Real-time monitoring with zero-latency
- Stem export beyond `.caf` (WAV/AAC handled by `SingleExport` already)

---

## Architecture

```
AudioEngine (existing)
├── masterEngine (AVAudioEngine)
│   ├── inputNode             ← MultiTrackRecorder taps this for MIC stem
│   ├── masterMixer           ← MultiTrackRecorder taps this for BEAT stem
│   │   └── ...beat source nodes (8× SamplerVoice)
│   ├── mainMixerNode         ← RetroCapture taps this (unchanged)
│   └── outputNode
└── microphoneManager (existing, checkPermission only)

MultiTrackRecorder (NEW, @MainActor @Observable)
├── engine: AVAudioEngine (weak)         ← captured at start
├── micFile: AVAudioFile?                ← inputNode tap → file
├── beatFile: AVAudioFile?               ← masterMixer tap → file
├── startHostTime: UInt64?               ← sync anchor
├── isRecording: Bool                    ← public state
├── recordingSeconds: Double             ← public read
├── trackURLs: [URL]                     ← finished file URLs
└── methods:
    ├── prepareForRecording() throws     ← validate permission + space
    ├── startRecording() throws          ← install both taps, capture hostTime
    └── stopRecording() async throws -> [URL]
```

---

## Cycle Plan (one commit per cycle)

### W2-C1 — `MultiTrackRecorder.swift` skeleton (DORMANT)

**File:** `Sources/Echoelmusic/Audio/MultiTrackRecorder.swift` (NEW)

Contents:
- Class declaration `@MainActor @Observable public final class MultiTrackRecorder`
- All public properties listed above (no logic)
- All public methods stubbed with `throw MultiTrackRecorderError.notImplemented` or similar
- Enum `MultiTrackRecorderError`: `permissionDenied`, `engineNotReady`, `diskSpaceLow`, `fileCreationFailed`
- **NOT referenced from anywhere else.** EchoelmusicApp, StudioRoot, BeatTab, AudioEngine — all untouched.

**Verify path:** Build green. Beat-MVP behavior unchanged.

**Commit:** `feat(record): MultiTrackRecorder skeleton — dormant, no wire-up yet`

### W2-C2 — `MultiTrackRecorderTests.swift` for the state machine

**File:** `Tests/EchoelmusicTests/MultiTrackRecorderTests.swift` (NEW)

Coverage:
- Initial state (isRecording=false, trackURLs.isEmpty)
- prepareForRecording throws when permission denied (mock permission)
- startRecording transitions state correctly
- stopRecording transitions back, returns URL array
- Idempotent stop while already stopped (no-op)

**Crash-safety note:** `BioIntegrationTests` is already known-broken (HilbertSensorMapper ghost type). Test target may not even build cleanly. Verify the test target builds — if not, skip this cycle and proceed to C3 (the new tests get masked alongside the existing ones until tech debt cleanup, which is its own future cycle).

**Commit:** `test(record): MultiTrackRecorder state machine tests`

### W2-C3 — Real `installTap` on inputNode (still no UI wire-up)

Wire the actual mic input tap inside `startRecording()`:

```swift
let inputNode = engine.inputNode
let inputFormat = inputNode.outputFormat(forBus: 0)
let outFormat = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
let micURL = makeURL(name: "mic")
let micFile = try AVAudioFile(forWriting: micURL, settings: outFormat.settings)

inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, time in
    try? micFile.write(from: buffer)
}
```

Notes:
- inputNode tap fires on audio thread; the `try?` is the documented Apple pattern for tap writers
- `bufferSize: 4096` matches RetroCapture for consistency
- Sample-rate conversion is handled implicitly when format differs

**Verify path:** Build green. Still no UI to trigger this — code dormant.

**Commit:** `feat(record): MultiTrackRecorder mic input tap implementation`

### W2-C4 — Beat-mix-down tap on masterMixer

Add a second tap inside `startRecording()`:

```swift
let beatFormat = engine.masterMixer.outputFormat(forBus: 0)
// reuse existing tap, or install a new one? RetroCapture taps mainMixerNode; we want masterMixer (pre-AutoMixChain)
let beatURL = makeURL(name: "beat")
let beatFile = try AVAudioFile(forWriting: beatURL, settings: beatFormat.settings)

engine.masterMixer.installTap(onBus: 0, bufferSize: 4096, format: beatFormat) { buffer, time in
    try? beatFile.write(from: buffer)
}
```

CRITICAL: `masterMixer.installTap` may conflict with the meter tap installed by `setupMasterEngine()` (line 133 in AudioEngine.swift). AVAudioMixerNode supports multiple taps on different buses; installing two taps on bus 0 will fail silently or crash on some iOS versions.

Mitigation options:
- A. Use `mainMixerNode` instead (already tapped by RetroCapture — same problem)
- B. Add a new pre-AutoMixChain mixer node specifically for recording
- C. Re-use RetroCapture's existing tap as the beat stem source — RetroCapture already writes a file when recording active; just call `retroCapture.startRecording()` in MultiTrackRecorder.startRecording()

**Choose C.** RetroCapture is purpose-built for this. MultiTrackRecorder delegates beat-stem recording to RetroCapture, manages only the mic stem itself, and combines URLs at stop.

**Commit:** `feat(record): MultiTrackRecorder beat stem via RetroCapture delegation`

### W2-C5 — `Studio/RecordTab.swift` REC UI

**File:** `Sources/Echoelmusic/Studio/RecordTab.swift` (NEW), replace `RecordTabPlaceholder` reference in `StudioRoot.swift`.

UI:
- Mic-permission state badge at top ("Microphone: granted" / "denied — open Settings")
- Big REC button (red while recording)
- Recording elapsed time display
- Track list: shows files after stop, with playback preview
- Master Volume slider (bound to `audioEngine.masterVolume`)

Permission flow:
- On tab appear: if permission is `.undetermined`, show a "Tap REC to enable microphone" hint
- On REC button tap: if undetermined, request permission. If denied, show settings link. If granted, start recording.

**Commit:** `feat(studio): RecordTab UI with REC button + permission flow`

### W2-C6 — A/V sync verification on device

Tooling: ship the recorded `.caf` files with timestamps captured at start. After stop, compute drift:

```swift
let micStartTime = startHostTime
let beatStartTime = retroCapture.startHostTime
let drift = AVAudioTime.seconds(forHostTime: micStartTime - beatStartTime)
log.info("A/V drift: \(drift * 1000) ms")
```

Target: drift < 10 ms (one audio buffer at 48 kHz / 4096 frames = 85 ms — actually we need to nail the same buffer boundary, so target < 1 buffer = 85 ms in practice).

If drift exceeds threshold, log error and prompt user to re-record. v10.1 ships without strict guarantee — quality bar improves in v10.2 with explicit `AVAudioEngine.hostTime` sync.

**Commit:** `feat(record): A/V sync verification + drift logging`

---

## Permissions / Info.plist

`NSMicrophoneUsageDescription` must exist in Info.plist. Per CLAUDE.md, **DO NOT modify Info.plist without explicit user approval.** Before W2-C5 reaches device, verify the key is present via `project.yml` info section.

If missing, separate user-gated cycle: add the key with text like *"Echoelmusic records your voice over the beats you build. The audio stays on your device unless you choose to export."*

---

## After this plan completes

Outcomes:
- Mic recording over beat works on device
- Two-stem output (`mic.caf` + `beat.caf`) on disk
- Simple RecordTab UI: REC, stop, track list
- A/V sync within 1 audio buffer
- Beat-MVP behavior unchanged

Triggers next plan: `PLAN_W2_VIDEO.md` (Camera + AVAssetWriter + ClipTrimmer).

---

## Bail conditions

Stop this plan and re-evaluate if any of:
- Audio session permission interaction blocks beat playback (regression)
- `inputNode.installTap` crashes on attach with `playAndRecord` session
- File write rate exceeds disk throughput (causing buffer overruns) — switch to lower buffer size or stream-buffered writer
- Mic UI fails App Store Review (unlikely with explicit consent flow)

In those cases, re-design instead of patching.
