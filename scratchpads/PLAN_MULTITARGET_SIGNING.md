# Multi-Target + Signing + Biofeedback-Sharing — analysis & safe plan

**Date:** 2026-05-31 · From the owner brief to wire all 6 targets, switch the
App Group, rework Fastlane signing, and add App-Group biofeedback sharing.

This records the **as-is state**, the **conflicts** with the brief, and a
**safe incremental path** — so the green TestFlight pipeline is never broken by
a big-bang change.

## As-is (verified in repo)
- `project.yml` has **2** targets: `Echoelmusic` (`com.echoelmusic.app`) and
  `EchoelmusicAUv3` (`com.echoelmusic.app.auv3`). The AUv3 **dependency is
  intentionally commented out** ("Re-enable when …auv3 is registered in ASC").
- Source dirs: only `Sources/EchoelmusicAUv3` exists (2 Swift files).
  **Missing:** `Widgets/`, `WatchOS/`, `EchoelmusicClip/`,
  `EchoelmusicNotificationService/`.
- App Group in **both** entitlements = `group.com.echoelmusic` (NOT `.app`).
- CI signing = App Store Connect API key + automatic + `-allowProvisioningUpdates`
  (green TestFlight uploads today). Fastlane is present but CI builds via
  `xcodebuild` in `testflight.yml`, not a Fastlane lane.

## Conflicts with the brief (why not applied blindly)
1. **App Group `group.com.echoelmusic.app`** ≠ the registered/entitlement value
   `group.com.echoelmusic`. Switching needs: create the new group in ASC →
   update both `.entitlements` → re-provision. Done blindly it breaks signing.
   **Kept `group.com.echoelmusic`.**
2. **Scaffolding clip/notification/watch/widgets now** — their source dirs don't
   exist and the App IDs aren't provisioned for CI; `xcodegen`+archive+signing
   would fail → breaks the green pipeline. Also contradicts the 2026-05-30
   decision ("iPhone-first; document, not scaffold, Clip + Notification-Service").
3. **match/sigh for 6 IDs** — replaces working automatic signing and fails for
   the 4 unprovisioned IDs. **Kept current signing.**
4. **Reading `UserDefaults` on the audio render thread** — forbidden (ObjC/IO/
   locks). Implemented the safe pattern instead (see below).

## Done now (safe, shipped)
- `Core/BioFeedbackManager.swift` + `BioFeedbackPublisher` + tests:
  app→AUv3 vitals over the App Group, **render-thread-safe** (off-thread poll →
  atomic-width Float snapshot the render block reads). On `group.com.echoelmusic`.

## Safe incremental path for the rest (one target per Ralph cycle)
For EACH of {AUv3 (re-enable), Widgets, WatchKit, Clip, NotificationService}:
1. Confirm/register the App ID + an App-Group-enabled provisioning profile in ASC.
2. Create the target's `Sources/<Target>/` with a minimal buildable stub.
3. Add the target to `project.yml` with its `bundleId`, the
   `group.com.echoelmusic` App Group capability, and (for embedded extensions)
   a `dependency` on the main app.
4. `xcodegen generate` → dispatch `testflight.yml build_only=true` →
   confirm green BEFORE the next target. Roll back the one target if it fails.

Only after all are green: optionally migrate signing to `match` (needs a certs
repo) — but automatic signing already works, so this is optional.

## If the owner truly wants `group.com.echoelmusic.app`
Separate migration cycle: register in ASC → update `Echoelmusic.entitlements` +
`EchoelmusicAUv3.entitlements` → change `BioFeedbackManager.appGroupIdentifier`
→ verify a build_only archive signs. Do it alone, not mixed with target work.
