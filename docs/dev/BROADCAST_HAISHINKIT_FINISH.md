# Broadcast (RTMP/SRT) — HaishinKit FINISH spec

**Status:** destination config + routing + UI + the `#if canImport(HaishinKit)` seam all
ship (`Stream/BroadcastPublisher.swift`, `Studio/BroadcastView.swift`, router sinks
`rtmp.out`/`srt.out`). What remains is adding the dependency and the A/V capture path.

**Why this is a doc, not a blind commit:** HaishinKit 2.x is async/restructured (RTMP and
SRT moved to separate products), the exact 2.x API can't be compile-verified in the CI-only
sandbox (no Swift toolchain), TestFlight can't device-verify a stream while Apple's daily
upload cap is in effect, and the camera is already owned by the rPPG publisher (contention —
see step 4). Adding a heavy external dep + version-specific API blind would risk reding the
**all-targets** compile gate. So this is staged as one verified pass for a compiler+device session.

---

## 1. Add the dependency (the one sanctioned external dep — CLAUDE.md TECH STACK)

HaishinKit 2.x splits products: `HaishinKit` (core/media), `RTMPHaishinKit` (RTMP),
`SRTHaishinKit` (SRT, pulls libsrt). Package: `https://github.com/HaishinKit/HaishinKit.swift`,
pin an **exact** recent tag (verify latest at release time, e.g. `2.2.0`).

**XcodeGen `project.yml`** (the app build / TestFlight path — the source of truth for the app target):
```yaml
packages:
  HaishinKit:
    url: https://github.com/HaishinKit/HaishinKit.swift
    exactVersion: 2.2.0
targets:
  Echoelmusic:
    dependencies:
      - package: HaishinKit
        product: HaishinKit
      - package: HaishinKit
        product: RTMPHaishinKit
      # - package: HaishinKit          # add only when wiring SRT
      #   product: SRTHaishinKit
```
**`Package.swift`** (keeps `ci.yml`'s macOS `swift build`/`swift test` resolving; ci is macOS-only,
so no Linux break): add the same `.package(url:exact:)` and the products to the `Echoelmusic` target deps.

Switch the seam: `BroadcastPublisher` currently guards on `#if canImport(HaishinKit)`; the RTMP
types live in `RTMPHaishinKit` in 2.x, so guard the engine code on `#if canImport(RTMPHaishinKit)`
(and `import RTMPHaishinKit`). `engineAvailable` should reflect that product.

**First gate check:** push ONLY the dep + import change, confirm `xcode-compile-check` stays green
(proves dep resolution + product names). If it reds, the API/product names are wrong — fix or revert
that single commit; the branch returns to green. Only then add the capture code (step 3).

## 2. Camera/audio ownership decision (REQUIRED before capture)

`CameraRPPGBioPublisher` owns an `AVCaptureSession` for rPPG (finger on lens). HaishinKit's
`MediaMixer` also wants camera+mic. They cannot both own capture. Decision: **broadcast and rPPG
are mutually-exclusive modes.** When the user goes live, stop the rPPG session first
(`cameraRPPG.stop()`), and drive bio during a broadcast from BLE HR / HealthKit instead. Surface this
in `BroadcastView` ("Going live uses the camera for the scene; heart rate comes from a paired
sensor while streaming."). Wire the stop in `BroadcastPublisher.start()` via a weak ref to the rPPG
publisher (inject in `EchoelmusicApp`).

## 3. A/V capture path (HaishinKit 2.x async API — verify against docs.haishinkit.com/swift/latest)

Sketch (validate exact signatures with the compiler — 2.x is async and evolving):
```swift
#if canImport(RTMPHaishinKit)
import HaishinKit
import RTMPHaishinKit

private let mixer = MediaMixer()
private let connection = RTMPConnection()
private lazy var stream = RTMPStream(connection: connection)

func startRTMP() async throws {
    try await mixer.attachAudio(AVCaptureDevice.default(for: .audio))
    try await mixer.attachVideo(AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back))
    await mixer.addOutput(stream)
    _ = try await connection.connect(url)          // e.g. rtmp://a.rtmp.youtube.com/live2
    _ = try await stream.publish(streamKey)
    isLive = true
}
```
SRT: same shape with `SRTConnection`/`SRTStream` from `SRTHaishinKit`, `connect` to the `srt://` URL.
Map all `try`/throws to `statusMessage` (honest failures). `stop()` → `try await stream.close()` /
`connection.close()` and `mixer` teardown; set `isLive=false`.

## 4. Verify
- Compile gate green WITH the dep (step 1 first, then step 3).
- Device: enter a YouTube/Twitch ingest URL + key, Go Live, confirm the stream appears; confirm rPPG
  is stopped and BLE/HealthKit HR still drives bio; confirm `stop()` ends cleanly and re-enables rPPG.
- Mastering: the four `Master` R128 numbers **may** be used to confirm what the mix carries —
  since #316b (2026-08-01) they are measured at `AutoMixChain.chainOutputNode`, after EQ,
  auto-gain and the limiter, with the −1 dB output trim added back. The two LEVEL BARS in the
  same panel are still pre-chain and are not a delivery check.
  ⛔ History, because this bullet has said two opposite things: it first claimed the readout
  "already shows what's going out", which #316 showed was false (the meter then tapped
  `masterMixer`, the chain's INPUT), and #316 replaced it with a prohibition plus the
  condition for lifting it — "needs a post-chain measurement, symbol containing
  `masterOutputLUFS`". That condition is met; the prohibition is lifted. A stream still
  carries its own encoder, so an external meter on the RECEIVED stream remains the only check
  of what the viewer hears — that part was never about the measurement point.

## 5. Update on completion
Flip `BroadcastView`'s "engine not installed" copy, mark Broadcast ✅ in `DMMW_ARCHITECTURE.md`
(§ Signal Router + FEATURE_MATRIX), and log the decision (camera-exclusive mode) to `decisions.csv`.
