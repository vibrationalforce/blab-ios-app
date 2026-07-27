# App Store Submission Readiness — Checklist

Everything needed to submit Echoelmusic to the App Store (beyond TestFlight).
Status: ✅ done · ⚠️ partial/needs-owner · ❌ missing/blocker. Companion to
`APP_STORE_CONNECT.md` (identity) and `FEATURE_MATRIX.md` (what ships).

> **TestFlight ≠ App Store.** TestFlight build **1477 VALID** ships now. App
> Store *release* additionally needs screenshots, privacy labels, age rating,
> and review info below. None of these block TestFlight beta testing.

## 1. Identity & build  — ✅ (see APP_STORE_CONNECT.md)
- App name **Echoelmusic** · Apple ID **6757957358** · SKU **Simsalabimbam** · category `public.app-category.music` · iOS 18 · version `10.0.0`.
- ✅ `ITSAppUsesNonExemptEncryption: false` set (Info.plist + project.yml + Widgets + Clip) → no export-compliance prompt per upload.
- ✅ Privacy usage strings present: Health (share), Microphone, Camera, PhotoLibraryAdd, Motion, Bluetooth, LocalNetwork.
- ✅ TestFlight signing = ASC API key (no Match). Secrets: `APP_STORE_CONNECT_KEY_ID/ISSUER_ID/PRIVATE_KEY`, `APPLE_TEAM_ID`.

## 2. App Store metadata (`fastlane/metadata/<locale>/`)  — ⚠️
- ✅ **en-US + de-DE** subtitle/keywords/promotional_text/description brand-cleaned (dropped wellness, meditation, "Super Intelligence AI", "16K/1000fps", "100+ instruments/AI effects" — false/roadmap claims that fail review).
- ⚠️ **10 other locales** (ar-SA, es-ES, fr-FR, hi, it, ja, ko, pt-BR, ru, zh-Hans) still carry the same overclaims in keywords + promotional_text + description. **Decision:** either (a) ship only en-US + de-DE for v1 (recommended — App Store does not require all locales), or (b) localize the cleaned copy. Do NOT machine-translate brand copy blindly.
- ⚠️ **en-US/de-DE description body** still describes the full *vision* (framed by the honest "CONCEPT – IN DEVELOPMENT" opener). Before real submission, remove specific false specs ("16K", "1000fps", "SUPER INTELLIGENCE", "100+") — keep the concept framing. Owner-voice, not auto-rewritten.
- [ ] **Release notes / "What's New"** per locale (`release_notes.txt`) — verify current.
- [ ] Verify **marketing_url / support_url / privacy_url** resolve (echoelmusic.com/…).

## 3. Screenshots  — ❌ BLOCKER for submission (`fastlane/screenshots/` empty)
- Required device sizes (App Store, 2026): **6.9"** (iPhone 16 Pro Max, 1320×2868) **and 6.5"** (1284×2778) — Apple derives smaller from 6.9" if omitted, but at least one 6.9" set is mandatory. iPad sizes only if iPad is a supported destination (currently iPhone-only → not needed).
- 1–10 per size. Show: BioStrip live (Demo), a Metal visual, the MIDI export share sheet.
- ⚠️ Generated on device/simulator (Fastlane `snapshot` config exists: `Snapfile`). The `Framefile.json` caption "Wellness"/localized still needs brand-clean if used.

## 4. App Privacy (Nutrition Labels in ASC)  — ❌ required, owner-fill
- Per `privacy.html`: **no accounts, no analytics, no third-party SDKs, all on-device.** Likely answer: **"Data Not Collected"** for most categories.
- **Health data** (heart rate, HRV via HealthKit): used on-device for app functionality, **not linked to identity, not used for tracking** → declare as *Health & Fitness · App Functionality · not linked · no tracking* (or "not collected" if never leaves device — confirm the exact ASC wording with how HealthKit read-only is treated).
- Capture the final answers here once entered.

## 5. Age rating questionnaire  — ❌ required
- No objectionable content → expected **4+**. Note: app has **health/biofeedback** features (disclaimers present) and **visual flashing capped at 3 Hz** (W3C/epilepsy) — answer the medical/health questions truthfully (it is NOT a medical device; creative/self-observation only).

## 6. App Review information  — ⚠️ prepare
- **Demo account:** none needed (no login).
- **Review notes (draft):** "Echoelmusic is a bio-reactive music instrument. Biometrics come from HealthKit or a Polar H10; **a reviewer without hardware will see the app auto-start a clearly-labeled 'Demo' bio source after ~4s**, so all bio-reactive features are testable without a sensor. Biofeedback is for creative/self-observation, NOT medical diagnosis (see in-app + health.html). HealthKit is read-only, on-device."
- Contact: Michael Terbuyken · echoel@tropicaldrones.com.

## 7. Review-guideline risk areas  — ⚠️ pre-check
- **HealthKit (§1.4, §5.1.3):** read-only, on-device, clear non-medical disclaimers ✅. Don't write fabricated data to Health.
- **No misleading metadata (§2.3):** the overclaim cleanup above directly serves this — finish it before submission.
- **Concept/"in development" (§2.1):** the app must be functional & not a beta/demo on the public Store. Ensure the shipped feature set (LIVE tools) genuinely works on device before release (currently device-unverified — see below).
- **App Group / iCloud:** iCloud disabled; App Group `group.com.echoelmusic` — resolve the `Appfile` `.shared` comment discrepancy (APP_STORE_CONNECT.md).

## 8. Pre-submission gating (the real blocker)  — ❌
- **Device verification:** the LIVE tools (audio output, beat playback, tab navigation, no launch crash) are **CI-green but NOT runtime-verified**. App Store release REQUIRES the app actually works on device. → Run build 1477 on an iPhone and confirm §"CLEAR SOFTWARE" checklist (CLAUDE.md) before submitting.

## Summary — what's blocking App Store submission (not TestFlight)
1. ❌ **Screenshots** (6.9" set) — none exist.
2. ❌ **Privacy nutrition labels** + **age rating** — owner must complete in ASC.
3. ⚠️ **Metadata overclaim cleanup** finished for en/de; description specifics + 10 locales pending.
4. ❌ **On-device verification** that the LIVE features actually work.
5. ⚠️ **Review notes** drafted above — paste into ASC.

Identity, signing, encryption flag, privacy strings, and a VALID build are ✅ done.
