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

| ASC display name | Bundle ID | Role | Target status |
|---|---|---|---|
| Echoelmusic | `com.echoelmusic.app` | Main app (iOS + universal) | ✅ defined (`Project.swift`, `project.yml`) |
| Echoelmusic AUv3 | `com.echoelmusic.app.auv3` | Audio Unit v3 extension (embedded) | ✅ defined |
| Echoelmusic Clip | `com.echoelmusic.app.clip` | App Clip | ⏳ ASC-registered, **target deferred** |
| Echoelmusic Notification Service | `com.echoelmusic.app.notification-service` | Notification Service extension | ⏳ ASC-registered, **target deferred** |
| Echoelmusic watchOS | `com.echoelmusic.app.watchkitapp` | watchOS companion | ✅ defined |
| Echoelmusic Widgets | `com.echoelmusic.app.widgets` | WidgetKit extension | ✅ defined |

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
- **Extra target:** `Project.swift` also declares `com.echoelmusic.app.voice` (an `EchoelVoice`
  AUv3). It is **not** in the owner's ASC bundle set above — confirm whether to register it in
  ASC or fold it into `com.echoelmusic.app.auv3`.
- **TestFlight signing** is pure App Store Connect API key (no Match). Required GitHub Actions
  secrets: `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`,
  `APP_STORE_CONNECT_PRIVATE_KEY`, `APPLE_TEAM_ID`. See `.github/workflows/testflight.yml`.

## Cross-platform vision

iPhone is the instrument and the hub; every other surface extends it meaningfully — see
`scratchpads/PLAN_MULTIPLATFORM_LINKING.md`.
