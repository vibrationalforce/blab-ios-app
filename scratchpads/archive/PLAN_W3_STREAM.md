# W3 — Stream Engine (RTMPPublisher via HaishinKit + ShareTab)

**Status:** Ready-to-execute. Activates AFTER W2_VIDEO ships green.
**Dependencies:** **First external dependency** — HaishinKit (MIT, Swift-native RTMP/RTMPS).
**Estimated cycles:** 6 atomic commits, ~3 day equivalent of focused work.
**Crash-safety strategy:** HaishinKit added in dormant cycle (compile-only) before any RTMP code is written. Bisect-safe.

---

## Goal

Push the live A/V feed (audio from `AudioEngine.masterMixer`, video from `CameraSession`) to an RTMP/RTMPS server URL. Targets: YouTube Live, Twitch, Facebook Live, custom (Streamlabs, OBS-relay, restream.io).

## Non-Goals (defer to v1.1+)

- Built-in RTMP server (host streams from the device)
- HLS / DASH output
- WebRTC / low-latency
- Multi-platform simulcast (use restream.io as a relay if needed)
- Stream destinations UI (just URL + key fields; destination is a label)

---

## Dependency: HaishinKit

- Repository: https://github.com/shogo4405/HaishinKit.swift
- License: MIT (App Store safe)
- Pin to exact tag (e.g., `1.10.0` or latest stable at time of integration)
- Justification documented in `memory/decisions.md` 2026-04-26 entry

**Package.swift change:**

```swift
dependencies: [
    .package(url: "https://github.com/shogo4405/HaishinKit.swift", exact: "1.10.0")
],
.target(
    name: "Echoelmusic",
    dependencies: [
        .product(name: "HaishinKit", package: "HaishinKit.swift")
    ],
    ...
)
```

**Supply-chain risk:** accepted vs ~40% schedule risk of rolling our own (per decisions.csv).

---

## Architecture

```
RTMPPublisher (NEW, @MainActor @Observable)
├── connection: RTMPConnection (HaishinKit)
├── stream: RTMPStream (HaishinKit)
├── url: String
├── streamKey: String                    ← stored in Keychain, never plain UserDefaults
├── bitrateKbps: Int                     ← 3000 / 4500 / 6000 default
├── isConnected: Bool
├── isPublishing: Bool
├── streamHealth: StreamHealth           ← .good / .degraded / .lost
├── statsHz, statsKbps, statsDroppedFrames
└── methods:
    ├── connect() async throws
    ├── startPublishing(audio: AVAudioPCMBuffer.Publisher, video: CMSampleBuffer.Publisher) throws
    ├── stopPublishing() async
    └── disconnect()

ShareTab (NEW)
├── URL + Key fields (key masked, eye-toggle)
├── Bitrate picker: 3 / 4.5 / 6 Mbps
├── Big START LIVE button (red while live)
├── Elapsed time + connection-health badge
├── Stats footer: bitrate / dropped frames / latency
└── Disclaimer: "Generic RTMP — not affiliated with YouTube/Twitch/Facebook"
```

---

## Cycle Plan (one commit per cycle)

### W3-S1 — Package.swift: add HaishinKit

Pin to exact stable tag. Build green check.

**Risk:** SPM dependency resolution may fail on first checkout (network, GitHub rate limit). Allow 1 retry buffer in cycle plan.

**Commit:** `chore(deps): pin HaishinKit 1.10.0 for RTMP/RTMPS support`

### W3-S2 — `RTMPPublisher.swift` skeleton (DORMANT)

**File:** `Sources/Echoelmusic/Stream/RTMPPublisher.swift` (NEW)

Contents:
- `import HaishinKit`
- Class structure + property declarations
- All methods stubbed
- Enum `StreamHealth { case good, degraded, lost }`
- Enum `RTMPPublisherError { case invalidURL, connectionFailed, publishFailed, networkLost }`

**Verify path:** Build green with HaishinKit linked.

**Commit:** `feat(stream): RTMPPublisher skeleton — HaishinKit wrapper, dormant`

### W3-S3 — Connect + publish lifecycle

Fill in `connect()` using `RTMPConnection().connect(url)` async pattern. Publish lifecycle uses `RTMPStream(connection:).publish(streamKey)`.

Health monitoring: subscribe to `connection.publish(name:)` callbacks. Update `isConnected`, `streamHealth`.

**Commit:** `feat(stream): RTMP connection + publish lifecycle`

### W3-S4 — Audio + Video pipeline integration

HaishinKit consumes `CMSampleBuffer` for both audio and video. We need to bridge:

- Audio: `RetroCapture.subscribe { buffer, time in ... }` (re-using the subscriber pattern from W2_VIDEO) → convert `AVAudioPCMBuffer` to `CMSampleBuffer` → `stream.append(audioSampleBuffer)`
- Video: `CameraSession.videoOutput.setSampleBufferDelegate(publisher, ...)` → `stream.append(videoSampleBuffer)`

The conversion `AVAudioPCMBuffer → CMSampleBuffer` is non-trivial. Helper: `CMSampleBufferCreate` with `CMBlockBufferCreateWithMemoryBlock`. ~50 lines.

**Commit:** `feat(stream): A/V sample buffer pipeline to RTMPStream`

### W3-S5 — `ShareTab.swift` UI

**Files:**
- `Sources/Echoelmusic/Studio/ShareTab.swift` (NEW)
- `StudioRoot.swift` (UPDATE — replace ShareTabPlaceholder)

UI elements per the architecture spec. Stream key stored in Keychain via `KeychainHelper` (small helper to add).

**Commit:** `feat(studio): ShareTab — URL/key/bitrate + START LIVE button`

### W3-S6 — Network resilience + thermal/auto-bitrate

- Observer for `NWPathMonitor` — pause publishing on network loss, resume on restore
- Thermal observer (`ProcessInfo.thermalState`) — drop bitrate by 1 tier on `.serious`, by 2 tiers on `.critical`
- "Stream lost" UI state with auto-reconnect attempts (3, with 2/4/8s backoff)

**Commit:** `feat(stream): network/thermal resilience + auto-reconnect`

---

## Critical risks

1. **App Store Review.** Apple historically permits RTMP streaming (Streamlabs Mobile, Larix Broadcaster are precedents). Avoid mentioning specific platforms (YouTube/Twitch) in UI copy — generic "RTMP destination" framing.

2. **Stream key UX.** Keys are 16-32 chars, secret. Use SecureField + Keychain. Never log key content. Add "Reveal" eye toggle.

3. **Bandwidth measurement.** Cellular vs WiFi differs hugely. Don't auto-start at 6 Mbps on cellular without warning. Detect `NWInterface.InterfaceType.cellular` and clamp to 3 Mbps with toast.

4. **HaishinKit version churn.** Pin to exact tag. Verify breaking changes on minor upgrades. Don't auto-bump.

5. **A/V drift over long streams.** Re-sync hostTime every ~30s. HaishinKit handles timestamp consistency internally if SampleBuffer.presentationTimeStamp is correctly set.

---

## After this plan completes

Outcomes:
- 4 tabs functional: Beat / Record / Video / Share
- Live stream to any RTMP destination at 720p/1080p, 3-6 Mbps
- Network/thermal resilience
- Privacy: stream key in Keychain, no analytics

This is the **v10 full vision** in TestFlight. After verification, ship to App Store as **Echoelmusic v10.0**.

---

## After v10.0 ships

Trigger `PLAN_W4_POLISH.md`:
- App Store metadata, screenshots, App Preview video
- App Store Review submission
- Marketing: Echoel brand site (docs/), Mastodon/X presence, demo videos
- AUv3 plugin parallel-track: `PLAN_AUV3_STANDALONE.md` (Info.plist fix, ASC bundle ID, separate App Store product)
