# SPEC — Ecosystem Targets, Execution-Ready Diffs

Companion to `PLAN_ECOSYSTEM_LOOP.md`. The plan *sequences*; this file gives the
**exact, copy-paste diffs** so each follow cycle is pure execution — no design.

**Locked decisions (this cycle):**
- **Generator:** XcodeGen `project.yml` is canonical (CI). `Project.swift` is reference only.
- **Order (value ÷ signing-risk):** Widgets → watchOS → Mac(Catalyst) → visionOS → tvOS →
  Notification Service → App Clip → feature-depth (RTMP/Lux/AI/EchoelLoop).
- **macOS = Mac Catalyst first** (decided): toggle Catalyst on the *existing* iOS target —
  fastest shippable Mac app, reuses 100% of the SwiftUI/AVFoundation code, Universal Purchase
  under `com.echoelmusic.app`. Native AppKit/`EchoelmusicMac` deferred to post-paid-threshold.
  *Owner-overridable* — if you want native Mac, that's a larger separate target (Tuist has it).
- **App Group `group.com.echoelmusic`** is the cross-surface data bus everywhere.
- **Signing-safe pattern:** new target dependency OFF → CI compile (isolated scheme) →
  embed as dependency + verify provisioning → `build_only=false` ship.

---

## CROSS-CUTTING PREREQUISITE — Cycle CX (do before any widget/watch *content*)

Two real gaps found in the app today; every glance/companion surface depends on them:

1. **`BioFeedbackPublisher` is dormant.** It publishes `BioVitals` → App Group at ~1 Hz, but
   `start(publishingFrom:)` is **never called**. Both the AUv3 bridge and the Widget read an
   empty store until this is wired.
2. **No `WidgetCenter` reload.** Widgets only refresh on WidgetKit's ~minutes budget unless the
   app nudges them when fresh vitals arrive.

**CX diff (≤3 files):**
- `Sources/Echoelmusic/EchoelmusicApp.swift` — own a `BioFeedbackPublisher`, call
  `.start(publishingFrom: bus)` once the `EngineBus` exists (on first appear / scenePhase
  `.active`); `.stop()` on `.background`.
- `Sources/Echoelmusic/Core/BioFeedbackPublisher.swift` — after `manager.publish(...)`, throttle
  a widget nudge (≤ once / 10 s to respect budget):
  ```swift
  #if canImport(WidgetKit)
  import WidgetKit
  // inside the loop body, after publish, gated by a 10 s timestamp:
  WidgetCenter.shared.reloadTimelines(ofKind: "EchoelBioWidget")
  #endif
  ```
- (no third file needed)

**Acceptance:** with a live/Demo bio source, the App Group store updates and the widget shows
non-placeholder numbers within ~10 s.

---

## TARGET 1 — Widgets  ✅ scaffold done (C2)

- **Bundle:** `com.echoelmusic.app.widgets` · **product:** app-extension · **platform:** iOS
- **Files (created C2):** `Sources/EchoelmusicWidgets/EchoelBioWidget.swift`,
  `EchoelmusicWidgets.entitlements`, `Resources/EchoelmusicWidgets/Info.plist`,
  `project.yml` target + `EchoelmusicWidgets` scheme. Shared source: `BioFeedbackManager.swift`.
- **C3 embed diff:** add to the `Echoelmusic` target in `project.yml`:
  ```yaml
      dependencies:
        - target: EchoelmusicWidgets
  ```
  Then CI `build_only=true` → confirm provisioning for `…app.widgets` resolves under automatic
  signing; then `build_only=false`.
- **C4 content:** depends on **CX**. Add Lock-screen families `.accessoryRectangular`,
  `.accessoryInline` to `supportedFamilies` once the small/medium pair is verified on device.

---

## TARGET 2 — watchOS companion

- **Bundle:** `com.echoelmusic.app.watchkitapp` · **product:** watch2App (SwiftUI watchOS app) ·
  **platform:** watchOS · **deployment:** watchOS 10.0 (add to `options.deploymentTarget`).
- **HARD CONSTRAINT (CLAUDE.md):** Apple Watch HR has ~4–5 s latency → **display/trend only,
  NO beat-sync.** The watch is a *bio source + glance*, never a transport clock.
- **Files to create:**
  - `Sources/EchoelmusicWatch/EchoelWatchApp.swift` — `@main` SwiftUI `App`, a single view
    showing live HR/HRV/coherence (reuse the widget's number-first layout idiom).
  - `Sources/EchoelmusicWatch/WatchHeartProvider.swift` — `HKWorkoutSession` +
    `HKLiveWorkoutBuilder` (or `HKAnchoredObjectQuery` for HR) → writes `BioVitals` into the App
    Group via `BioFeedbackManager.publish` so the **phone** consumes wrist HR. (Wrist is a
    *producer* here; phone-side already has the consumer path.)
  - `EchoelmusicWatch.entitlements` — App Group + HealthKit:
    ```xml
    <key>com.apple.security.application-groups</key><array><string>group.com.echoelmusic</string></array>
    <key>com.apple.developer.healthkit</key><true/>
    ```
  - `Resources/EchoelmusicWatch/Info.plist` — `WKApplication=true`, HealthKit usage strings,
    `WKBackgroundModes` = `workout-processing` (for continuous HR).
- **project.yml target block:**
  ```yaml
    EchoelmusicWatch:
      type: application
      platform: watchOS
      deploymentTarget: "10.0"
      sources:
        - path: Sources/EchoelmusicWatch
          type: group
          excludes: ["**/*.md"]
        - path: Sources/Echoelmusic/Core/BioFeedbackManager.swift
      info: { path: Resources/EchoelmusicWatch/Info.plist, properties: { … HK strings … } }
      entitlements: { path: EchoelmusicWatch.entitlements }
      settings:
        base:
          PRODUCT_BUNDLE_IDENTIFIER: com.echoelmusic.app.watchkitapp
          GENERATE_INFOPLIST_FILE: NO
          CODE_SIGN_STYLE: Automatic
          DEVELOPMENT_TEAM: ""
      dependencies: []
  ```
  + isolated `EchoelmusicWatch` scheme. **Embed step** (after compile-green): add
  `- target: EchoelmusicWatch` to the iOS app deps (watch app embeds as a companion).
- **Cycles:** C5 target+source compile-only → C6 embed+provision → C7 HR-streaming content.

---

## TARGET 3 — macOS (Catalyst)  ← decided path

No new target. **Enable Catalyst on the existing `Echoelmusic` target:**
- **project.yml** `Echoelmusic.settings.base` additions:
  ```yaml
        SUPPORTS_MACCATALYST: YES
        SUPPORTED_PLATFORMS: "iphoneos iphonesimulator macosx"
        DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER: NO   # keep com.echoelmusic.app
        MACOSX_DEPLOYMENT_TARGET: "14.0"
  ```
  and the target `platform`/`destinations` gains macCatalyst. (AUv3 already sets
  `SUPPORTS_MACCATALYST: YES` — keep extensions Catalyst-consistent.)
- **Code guards to audit before enabling** (one cycle of `#if targetEnvironment(macCatalyst)`):
  camera/HealthKit/CoreMIDI availability, window sizing, no `UIScreen.main` (banned anyway).
- **Cycles:** C8a Catalyst toggle + guard audit (compile-only on a macCatalyst destination) →
  C8b sign + TestFlight (Mac). Provisioning shares `com.echoelmusic.app` (Universal Purchase).

---

## TARGET 4 — visionOS

- **Bundle:** `com.echoelmusic.app` (Universal Purchase) · **product:** app · **platform:** visionOS
- **Scope:** the immersive bio-reactive visual scene (EchoelVis) as a `RealityKit`/`ImmersiveSpace`
  surface; bio drives material/particle params. Reuse `MetalBioView` content where portable.
- **Files:** `Sources/EchoelmusicVision/EchoelVisionApp.swift` (+ `ImmersiveBioScene.swift`),
  `EchoelmusicVision.entitlements` (App Group), `Resources/EchoelmusicVision/Info.plist`.
- **project.yml:** new target `platform: visionOS`, `deploymentTarget visionOS: "2.0"`, isolated
  scheme. Shares `BioFeedbackManager.swift`. **Not** embedded in the iOS app (separate platform
  app) — ships as its own archive lane.
- **Cycles:** C9 target+stub scene compile-only → C10 immersive content + ship.

---

## TARGET 5 — tvOS

- **Bundle:** `com.echoelmusic.app` (Universal Purchase) · **product:** app · **platform:** tvOS
- **Scope:** big-screen *output* surface for installation/stage — full-screen EchoelVis visual
  fed by bio over the App Group (same device) or, later, over the network (EchoelNet/OSC).
  No transport UI; focus-driven minimal controls.
- **Files:** `Sources/EchoelmusicTV/EchoelTVApp.swift`, `EchoelmusicTV.entitlements`,
  `Resources/EchoelmusicTV/Info.plist`. project.yml `platform: tvOS`, `tvOS: "18.0"`, scheme.
- **Cycles:** C11 target+stub → C11b visual content + ship.

---

## TARGET 6 — Notification Service extension

- **Bundle:** `com.echoelmusic.app.notification-service` · **product:** app-extension (iOS)
- **Scope:** enrich session/stream push payloads (e.g. coherence-milestone, stream-live alerts).
- **Files:** `Sources/EchoelmusicNotificationService/NotificationService.swift`
  (`UNNotificationServiceExtension` subclass), `EchoelmusicNotificationService.entitlements`
  (App Group), `Resources/EchoelmusicNotificationService/Info.plist`
  (`NSExtensionPointIdentifier = com.apple.usernotifications.service`).
- **project.yml:** app-extension target, embed in iOS app deps, scheme. **Prereq:** push
  (APNs) capability + a server/local-notification source — defer content until a notification
  producer exists. Target scaffold can land earlier (compile-only).
- **Cycles:** C12 scaffold → (later) content when push exists.

---

## TARGET 7 — App Clip

- **Bundle:** `com.echoelmusic.app.clip` · **product:** app-clip · **platform:** iOS
- **Scope:** instant, no-install **bio-reactive demo** — Demo bio source → audible synth +
  one visual. ≤10 MB budget: include only `DSP/` + `BioSimulator` + a single view; exclude
  video/stream/sequencer.
- **Files:** `Sources/EchoelmusicClip/EchoelClipApp.swift` + a trimmed view,
  `EchoelmusicClip.entitlements` (App Group + `com.apple.developer.parent-application-identifiers`
  = `$(AppIdentifierPrefix)com.echoelmusic.app`), `Resources/EchoelmusicClip/Info.plist`.
- **project.yml:** `product: app-clip`, associated with the parent app; its own archive/scheme.
  Strict source list (size budget). **Cycles:** C13 scaffold compile-only → C13b demo content.

---

## FEATURE-DEPTH (after surfaces exist) — sequenced, not specced here

Each is its own multi-cycle sub-plan once a host surface is stable:
1. **RTMP live stream** — add **HaishinKit** (the *one* sanctioned dependency; pin exact tag) →
   new `Sources/Echoelmusic/Stream/RTMPPublisher.swift` (dir does not exist yet) → ShareTab.
2. **EchoelLux** — DMX-512 / Art-Net 4 over UDP 6454 (Bonjour `_artnet._udp` already declared).
3. **EchoelStage** — NDI/Syphon output (integrate, don't reimplement projection).
4. **EchoelAI** — on-device CoreML, bio-reactive only (never generative/cloud).
5. **EchoelLoop** — Loopy-Pro-style bio-modulated widget canvas (the Tools-tab payload).

---

## Per-target Definition of Done (every cycle)
1. Main iOS app still archives green (never regressed) — verify the `Echoelmusic` scheme.
2. New target compiles (isolated scheme) **before** embedding; embeds **before** real content.
3. No force-unwrap · no audio-thread alloc · `os_log` only · WCAG ≤3 Hz · science-first display.
4. Conventional commit · `metrics.jsonl` appended · plan backlog advanced.
5. Owner-gated items (below) never guessed.

## Owner-gated (do not guess)
- macOS native vs Catalyst — **defaulted to Catalyst**; override if native wanted.
- `com.echoelmusic.app.voice` (Tuist `EchoelVoice` AUv3) — register / fold into `…auv3` / drop?
- App Group: confirm portal ID is `group.com.echoelmusic` (Appfile comment says `.shared`).
- PAT rotation (pasted in plaintext 2026-06-01) → required before any CI dispatch.
