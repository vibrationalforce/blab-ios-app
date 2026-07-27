# App Store Connect — Canonical Identity Map

Single source of truth for Echoel's App Store Connect identifiers, bundle IDs, and the
target ↔ bundle mapping. Mirror the headline facts in `CLAUDE.md` §IDENTITY; keep the full
table here. Update this file whenever a target or identifier changes.

## Account & app

| Field | Value |
|---|---|
| App name | **Echoelmusic** |
| Developer | Echoel (Michael Terbuyken) · Studio Hamburg |
| Apple App ID (ASC) | **6757957358** |
| SKU | **Simsalabimbam** |
| Bundle prefix | `com.echoelmusic` |
| Marketing version | `10.0.0` (`project.yml` → `MARKETING_VERSION`) |
| Build number | `${BUILD_NUMBER:=1}` (`CURRENT_PROJECT_VERSION`) |
| Team ID | via `APPLE_TEAM_ID` GitHub Actions secret (not committed) |
| App category | `public.app-category.music` |
| Deployment floor | iOS 18 |

## Bundle identifiers (App Store Connect registration)

The owner-registered ASC identifier set. Universal Purchase: all primary platforms share the
single `com.echoelmusic.app` ID so one purchase unlocks iOS / macOS / tvOS / visionOS.

> ✅ **One project generator.** `project.yml` (XcodeGen) is the single source of truth —
> `testflight.yml` runs `xcodegen generate` and archives it. The former Tuist `Project.swift`
> (a parallel, never-CI-built generator) was **removed 2026-06-19** (no-JUCE / single-pipeline
> cleanup). The status column below is the ground truth for what ships.

| ASC display name | Bundle ID | Role | CI (`project.yml`) |
|---|---|---|---|
| Echoelmusic | `com.echoelmusic.app` | Main app (iOS + universal) | ✅ **builds + ships** |
| Echoelmusic AUv3 | `com.echoelmusic.app.auv3` | Audio Unit v3 extension | ❌ **TARGET DELETED** (pure-instrument epic #121 Slice 1, 2026-07-24). The bundle ID stays registered in ASC; nothing builds or ships under it. Do not re-declare it without a founder ask. |
| Echoelmusic Widgets | `com.echoelmusic.app.widgets` | WidgetKit extension | ✅ **embedded + ships** |
| Echoelmusic watchOS | `com.echoelmusic.app.watchkitapp` | watchOS companion | ⚠️ compile-verified, **embed blocked** (local Xcode) |
| Echoelmusic Clip | `com.echoelmusic.app.clip` | App Clip | ❌ ASC-registered, **target deferred** |
| Echoelmusic Notification Service | `com.echoelmusic.app.notification-service` | Notification Service extension | ❌ ASC-registered, **target deferred** |

> **Deferred platforms** (macOS / tvOS / visionOS) were previously declared only in the removed
> Tuist `Project.swift`. They are **not currently defined anywhere** and would be re-added to
> `project.yml` in a dedicated, signing-verified cycle when actually built (iPhone-first for now).

### App Group

| App Group | Status |
|---|---|
| `group.com.echoelmusic` | Canonical (entitlements + `CLAUDE.md`). Used by the app + extensions. |

> ⚠️ **Discrepancy to resolve owner-side:** `fastlane/Appfile` reference comments mention
> `group.com.echoelmusic.shared`. The committed entitlements use `group.com.echoelmusic`.
> Confirm which App Group is registered in the Apple Developer portal and make the Appfile
> comment match the entitlements. Mismatched App Group IDs break signing/provisioning.

## Notes & deferred work (iPhone-first scope)

- **iPhone-first MVP.** `.clip` and `.notification-service` are registered in App Store
  Connect but their Xcode targets are **intentionally deferred** to avoid build/signing risk
  this round. Add them only in a dedicated cycle with entitlements + provisioning verified.
- **Former extra target:** the removed Tuist `Project.swift` also declared `com.echoelmusic.app.voice`
  (an `EchoelVoice` AUv3), not in the owner's ASC bundle set. With Tuist gone it is no longer
  declared — and since #121 removed the AUv3 target entirely, there is nothing to fold it into.
  Do not re-declare either without a founder ask.
- **TestFlight signing** is pure App Store Connect API key (no Match). Required GitHub Actions
  secrets: `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`,
  `APP_STORE_CONNECT_PRIVATE_KEY`, `APPLE_TEAM_ID`. See `.github/workflows/testflight.yml`.

## Cross-platform vision

iPhone is the instrument and the hub; every other surface extends it meaningfully — see
`scratchpads/PLAN_MULTIPLATFORM_LINKING.md`.
