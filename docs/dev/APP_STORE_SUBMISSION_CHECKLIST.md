# App Store Submission Readiness — Checklist

Everything needed to submit Echoelmusic to the App Store (beyond TestFlight).
Status: ✅ done · ⚠️ partial/needs-owner · ❌ missing/blocker. Companion to
`APP_STORE_CONNECT.md` (identity) and `FEATURE_MATRIX.md` (what ships).

> **TestFlight ≠ App Store.** TestFlight build **2576 (v10.79.457) VALID** ships now. App
> Store *release* additionally needs screenshots, privacy labels, age rating,
> and review info below. None of these block TestFlight beta testing.

## 1. Identity & build  — ✅ (see APP_STORE_CONNECT.md)
- App name **Echoelmusic** · Apple ID **6757957358** · SKU **Simsalabimbam** · category `public.app-category.music` · iOS 18 · version `10.0.0`.
- ✅ `ITSAppUsesNonExemptEncryption: false` → no export-compliance prompt per upload. Measured 2026-09-07: it is set in exactly ONE file, `Resources/iOS/Info.plist:114`, and that is the only one that matters — the main bundle's key answers the prompt. The old "(Info.plist + project.yml + Widgets + Clip)" was false in three of its four places. Re-derive: `grep -rn ITSAppUsesNonExemptEncryption Resources/ project.yml`.
- ✅ Privacy usage strings present: Health (share), Health (update), Microphone, Camera, PhotoLibraryAdd, Bluetooth, LocationWhenInUse, LocalNetwork. ⛔ "Motion" stood in this list and there is NO `NSMotionUsageDescription` — correctly so: `git grep -l "import CoreMotion" -- Sources` → 0, nothing measures motion. A checklist that reports a string the plist does not have is exactly the shape that gets one ADDED to "close the gap", and an unbacked purpose string is a §2.5.4 finding. Re-derive: `grep -n UsageDescription Resources/iOS/Info.plist`.
- ✅ TestFlight signing = ASC API key (no Match). Secrets: `APP_STORE_CONNECT_KEY_ID/ISSUER_ID/PRIVATE_KEY`, `APPLE_TEAM_ID`.

## 2. App Store metadata (`fastlane/metadata/<locale>/`)  — ⚠️
- ✅ **en-US + de-DE** subtitle/keywords/promotional_text/description brand-cleaned (dropped wellness, meditation, "Super Intelligence AI", "16K/1000fps", "100+ instruments/AI effects" — false/roadmap claims that fail review).
- ✅ **Decision (a) was taken and executed.** `ls -a fastlane/metadata/` returns exactly `en-US` and `de-DE`; the ten other locale directories no longer exist, so there is no overclaim left to clean there. Keep it this way for v1 — machine-translating brand copy is how a false claim re-enters through a language nobody on this project reads.
- ✅ **Done, re-verified 2026-09-07 by measurement.** None of "16K", "1000fps", "SUPER INTELLIGENCE" or "100+" appears in either description, and there is no "CONCEPT – IN DEVELOPMENT" opener any more. Both bodies were re-checked clause-by-clause against the code and no §2.3 over-claim was found: drums, clips/timeline, piano roll, AUv3, video trim, RTMP, multitrack, purchases and mic monitoring are all absent; MPE is described as OUT-only with the input side named as plain MIDI notes; the nineteen genre names match `MusicStyle.offered` exactly. Lengths are measured by `Tests/CISmoke/TheStoreTextClaimsOnlyWhatShipsTests.swift`'s siblings and by `python3 -c "print(len(open('fastlane/metadata/en-US/description.txt',encoding='utf-8').read()))"` — not quoted here (a number in a checklist is a date). ⚠️ Re-run this check after ANY feature removal — this repo deleted six shipping features in two months, and #184 had to strip twelve false claims from this same text.
- [ ] **Release notes / "What's New"** per locale (`release_notes.txt`) — verify current.
- [ ] Verify **marketing_url / support_url / privacy_url** resolve (echoelmusic.com/…).

## 3. Screenshots  — ❌ BLOCKER for submission (`fastlane/screenshots/` empty)
- Required device sizes (App Store, 2026): **6.9"** (iPhone 16 Pro Max, 1320×2868) **and 6.5"** (1284×2778) — Apple derives smaller from 6.9" if omitted, but at least one 6.9" set is mandatory. iPad sizes only if iPad is a supported destination (currently iPhone-only → not needed).
- 1–10 per size. Show: BioStrip live (Demo), a Metal visual, the WAV export share sheet.
  (A MIDI export sheet IS openable and IS worth a screenshot — `exportMIDI()` regained its door with #188: the Button is at `EchoelStudioView.swift:2251`, the function at `:10869`. ⛔ This line asserted the opposite for months while `fastlane/metadata/en-US/description.txt` sells MIDI export truthfully — a stale note aimed at DELETING an honest claim, the exact inverse of the #184 defect.)
- ⚠️ Generated on device/simulator (Fastlane `snapshot` config exists: `Snapfile`). ⛔ A "Wellness" caption was claimed here and is NOT in `Framefile.json` (measured 2026-08-28: zero grep hits; the captions read "Your heartbeat plays the instrument" etc. — brand-clean).

## 4. App Privacy (Nutrition Labels in ASC)  — ❌ required, owner-fill
- Per `privacy.html`: **no accounts, no analytics, no third-party SDKs, all on-device.** Likely answer: **"Data Not Collected"** for most categories.
- **Health data** (heart rate, HRV via HealthKit): used on-device for app functionality, **not linked to identity, not used for tracking** → declare as *Health & Fitness · App Functionality · not linked · no tracking* (or "not collected" if never leaves device — confirm the exact ASC wording; note the opt-in Health WRITE of self-measured values in §7).
- Capture the final answers here once entered.

## 5. Age rating questionnaire  — ❌ required
- No objectionable content → expected **4+**. Note: app has **health/biofeedback** features (disclaimers present) and **visual flashing capped at 3 Hz** (W3C/epilepsy) — answer the medical/health questions truthfully (it is NOT a medical device; creative/self-observation only).

## 6. App Review information  — ⚠️ prepare
- **Demo account:** none needed (no login).
- **Review notes (CORRECTED 2026-09-07 — paste this verbatim into ASC):** "Echoelmusic is a bio-reactive musical instrument: your pulse and breath drive the synthesis, the visual and the light output.

  NO HARDWARE AND NO SENSOR ARE NEEDED TO REVIEW IT. If you prefer not to grant camera access, or have no heart-rate strap:
    1. Tap the pulse readout in the header at the top of the screen. This opens the Bio panel.
    2. In the 'Bio source' row, open the menu and choose 'Play with the simulation'.
    3. That choice STARTS a full generative session immediately from a deterministic demo signal, labelled as a demo on screen. Nothing else is required — there is no separate Play step.
  (The same three choices are also on a long-press of the pulse readout.)
  With camera access granted, resting a fingertip on the REAR camera lens gives a real pulse within a few seconds. The torch switches on — that is normal and is how the optical measurement works.

  PRIVACY: no accounts, no analytics, no third-party SDKs, and no server of ours. Health data read from HealthKit is used on-device only. The OSC / ADM-OSC / Art-Net / sACN outputs are off by default and, when switched on, send only to hardware the user addresses on their own local network — that traffic is never accessible to us, which is why the privacy label answers 'Data Not Collected'.

  NOT A MEDICAL DEVICE. Biofeedback here is a creative control signal and a self-observation aid; the app makes no diagnostic or therapeutic claim, in-app or in the listing. Visual flashing is capped below 3 Hz (W3C/WCAG photosensitivity).

  Contact: Michael Terbuyken · echoel@tropicaldrones.com"
  - ⛔ The previous draft promised the app would "auto-start a clearly-labeled 'Demo' bio source after ~4s". All three parts were false, in the one sentence destined for App Review. Measured 2026-09-07: the default source is the camera (`EchoelStudioView.swift:229`); `bioSourceRaw` has exactly ONE writer (`:9552`, inside `selectBioSource`, an explicit user pick) and there is no timer or fallback to `.sim` anywhere; `demoSource.start(publishing: bus)` has exactly ONE production site (`:9497`, inside `case .sim`); and the label is "Play with the simulation" (`BioSourceOption.swift:50`), never "Demo". The visible door is the pulse pill's tap → chrome door "bio" (`HeaderMonitors.swift:388`) → `bioSourceRow` (`EchoelStudioView.swift:3151-3166`); the `.contextMenu` at `HeaderMonitors.swift:397-402` is the long-press alternative, which `BioSourceOption.swift:12` itself calls "the least discoverable gesture we ship" — hence it is named second, not first.
- Contact: Michael Terbuyken · echoel@tropicaldrones.com.

## 7. Review-guideline risk areas  — ⚠️ pre-check
- **HealthKit (§1.4, §5.1.3):** read on-device, clear non-medical disclaimers ✅ — and an OPT-IN WRITE path (`HealthWriteOptInRow` in the Bio panel, default off, `NSHealthUpdateUsageDescription` present): it saves only the heart rate and respiratory rate Echoel itself MEASURES (camera rPPG / BLE strap), never HRV and never the simulation (`HealthWritePolicy` excludes `.fallback`). ⛔ "read-only" stood here; the writer exists (`Bio/HealthKitWriter.swift`) and a reviewer who finds a write prompt the note calls impossible has found a contradiction. Don't write fabricated data to Health — that rule is enforced in code, not just here.
- **No misleading metadata (§2.3):** the overclaim cleanup above directly serves this — finish it before submission.
- **Concept/"in development" (§2.1):** the app must be functional & not a beta/demo on the public Store. Ensure the shipped feature set (LIVE tools) genuinely works on device before release (currently device-unverified — see below).
- **App Group / iCloud:** iCloud disabled; App Group `group.com.echoelmusic` — resolve the `Appfile` `.shared` comment discrepancy (APP_STORE_CONNECT.md).

## 8. Pre-submission gating (the real blocker)  — ❌
- **Device verification:** the LIVE tools (audio output, beat playback, tab navigation, no launch crash) are **CI-green but NOT runtime-verified**. App Store release REQUIRES the app actually works on device. → Run build 2576 (v10.79.457) on an iPhone and confirm §"CLEAR SOFTWARE" checklist (CLAUDE.md) before submitting.

## Summary — what's blocking App Store submission (not TestFlight)
1. ❌ **Screenshots** (6.9" set) — none exist.
2. ❌ **Privacy nutrition labels** + **age rating** — owner must complete in ASC.
3. ⚠️ **Metadata overclaim cleanup** finished for en/de; description specifics + 10 locales pending.
4. ❌ **On-device verification** that the LIVE features actually work.
5. ⚠️ **Review notes** drafted above — paste into ASC.

Identity, signing, encryption flag, privacy strings, and a VALID build are ✅ done.
