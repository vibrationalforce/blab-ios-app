# App Store Listing — v1.0 Launch (2026-07-10)

Source of truth for what goes into App Store Connect for the v1.0 submission.
Grounded in `docs/dev/FEATURE_MATRIX.md` (claim only LIVE) and the brand
guardrails (`.claude/skills/echoel-marketing/SKILL.md`). Business model v2:
the instrument is FREE, no purchase UI in v1.0 — the "Echoel Live" yearly
subscription arrives in v1.1 and is deliberately NOT mentioned anywhere here.

Primary locale: **en-US** (brand rule: American English). German (de-DE)
localization = post-launch follow-up.

---

## Name (30 chars max)

```
Echoelmusic: Biofeedback Synth
```
(30/30 — brand + the two highest-signal keywords.)

## Subtitle (30 chars max)

```
Your heartbeat makes music
```
(26/30 — the USP sentence, verbatim from the vision.)

## Keyword field (100 bytes max, no words repeated from name/subtitle, commas without spaces)

```
hrv,coherence,meditation,beat,sequencer,midi,mpe,drum,generative,pulse,breath,instrument,dj,live,daw
```
(100/100 bytes — "daw" added 2026-07-16 to use the last 4 bytes; high-signal
for the studio-handoff audience. No repeats of: echoelmusic, biofeedback,
synth, your, heartbeat, makes, music.)

## Promotional Text (170 chars max, updatable without release)

```
Launch: the first bio-reactive performance instrument. Your pulse, breath and motion compose live music and visuals — free, private, no account, on your iPhone.
```
(159/170.)

## Description (conversion only — not indexed by Apple)

```
Your body is the instrument.

Echoelmusic turns your heartbeat, breath and motion into live, professional
generative music — with immersive visuals that pulse with you. No account,
no ads, no cloud: everything happens on your iPhone.

PLAY WITH YOUR PULSE
• Measure your pulse with just your finger on the camera — or connect any
  Bluetooth heart-rate strap (Polar, Wahoo, Garmin and more), or Apple Health.
• Real heart-rate-variability coherence, computed with research-grade
  frequency analysis. Numbers first: HR, HRV, breath and coherence always
  visible. For self-observation — not medical diagnosis.
• No sensor around? Demo mode plays instantly.

COMPOSE FROM YOUR BODY
• One tap generates music in your key: 23 genres from dub techno to
  synthwave to meditation.
• Choose key and scale (10 scales), concert pitch A4 from 432 to 444 Hz,
  tempo locked in the studio or flowing with your heart.
• Polyphonic synthesizer with a deep patch editor and preset library,
  drum sequencer with velocity, accent and swing, piano roll, loop cutter,
  and a production FX chain (tape delay, chorus, filter, dynamics).

TAKE IT TO YOUR STUDIO AND YOUR SHOW
• Export stamped MIDI files (artist · date · key · BPM · tuning) straight
  into Ableton, Logic or FL Studio.
• Full MIDI and MPE in and out; use Echoelmusic as an AUv3 plugin inside
  Logic, GarageBand or AUM.
• Stream your live bio data as OSC and ADM-OSC objects into immersive
  audio rigs, and drive stage lights over Art-Net and sACN — open
  standards, no vendor lock-in.

SEE YOUR PULSE
• An immersive, GPU-rendered visual breathes with your body — flash-safe,
  Reduce-Motion aware, and recordable as share-ready video clips.

PLAY TOGETHER, NEARBY
• Two iPhones on the same Wi-Fi share a session with one tap, and can show
  each person's own live pulse and coherence side by side — measured, never
  merged into a score.

PRIVATE BY DESIGN
• Free. No account. No ads. No tracking. Your biosignals are processed on
  your device and are never collected by us.

Safety: visual flash rates are capped at 3 Hz (WCAG). Bio readings are for
creative control and self-observation, not for medical use.
```

## What's New (v1.0)

```
The first release: your heartbeat makes music. Bio-reactive synthesis,
23-genre generative composer, drum sequencer, piano roll, MIDI/MPE, AUv3,
immersive visuals, OSC/ADM-OSC, Art-Net/sACN — free, private, no account.
```

## Category

- Primary: **Music**
- Secondary: **Health & Fitness** (bio/self-observation angle) — alternative:
  Entertainment. Recommendation: Music + Health & Fitness.

## Age rating

4+ (no objectionable content; safety warnings shipped in-app).

## Price

Free. **No IAP configured for v1.0.** (Echoel Live sub = v1.1; do NOT create
the old non-consumable — superseded 2026-07-10B.)

---

## App Review notes (paste into "Notes for Review")

```
Echoelmusic is a bio-reactive musical instrument. All biosignal processing
is on-device; the app has no server, no account system, and collects no data.

How to test without any accessory:
1. Launch → tap Play. The instrument sounds immediately (Demo bio source).
2. "Generate from Body" composes music from the (demo or real) bio signal.

Camera use: the rear camera + torch measure the user's pulse from a fingertip
placed on the lens (photoplethysmography). No photos or video are captured,
stored, or transmitted. To test: cover the rear lens fully with a fingertip
for ~15 seconds in the bio strip's pulse view.

HealthKit: read-only heart rate/HRV as an optional bio source; optional
opt-in write-back of measured heart/breath rate. Off by default.

Location (optional, off by default): "Place in session name" resolves the
city once to stamp it into the session's file name (e.g.
Echoel_2026-07-10_Hamburg_Am_72bpm_A440). Nothing is stored or transmitted
beyond that name string.

Local network / Bluetooth: OSC, ADM-OSC, Art-Net and sACN send control data
to devices the user explicitly configures (stage lights, immersive audio).
Bluetooth connects standard heart-rate straps. MultipeerConnectivity shares
sessions between two nearby iPhones (peer-to-peer, no server).

Bio readings are presented for creative control and self-observation, not
medical diagnosis — the app states this, visual flash rates are capped at
3 Hz (WCAG 2.3.1), and brainwave-entrainment-style safety warnings ship
in-app.
```

---

## Privacy labels (App Store Connect → App Privacy)

Truthful answer: **"Data Not Collected."**

Rationale: Apple's labels cover data collected by the developer or sent off
device to third parties at the developer's direction. Echoelmusic has no
server, no analytics SDK, no ads, no account. Health/camera/location data
are processed on-device only; OSC/Art-Net/Multipeer transmissions go only to
user-chosen local devices (user-directed, not collection). If App Review
pushes back, the usage-description strings in Info.plist already explain
each permission honestly.

Checklist before submitting:
- [ ] Contact info: not collected
- [ ] Health & fitness: not collected (on-device only)
- [ ] Location: not collected (on-device; only lands in a filename the user keeps)
- [ ] Identifiers/usage data/diagnostics: not collected (no analytics; os_log stays on device;
      MetricKit crash diagnostics are Apple's own opt-in system, not developer collection)

---

## Screenshots (founder to capture on device — suggested order, first 3 carry 90% of views)

1. **The instrument, playing** — bio strip with live HR/HRV/coherence + the
   Composition panel. Caption: "Your heartbeat makes music."
2. **Immersive visual fullscreen** with the pulse visibly driving it.
   Caption: "See your pulse. Flash-safe by design."
3. **Generate from Body** — genre + key selection. Caption: "23 genres,
   your key, your tempo — composed from your body."
4. Piano roll / patch editor. Caption: "A real instrument: synth, drums, FX."
5. Camera pulse measurement (finger on lens). Caption: "Measure with your
   fingertip — no accessories needed."
6. AUv3 in a host / MIDI export share sheet. Caption: "MIDI, MPE, AUv3 —
   plays with your studio."
7. Live Colabo side-by-side bio. Caption: "Play together, nearby — each
   person's own numbers."
8. Routing panel (PatchbayView — the OSC/ADM-OSC/Art-Net door since the
   2026-07-12 slot-reuse; the old "Sync tab" no longer exists). Caption:
   "Open standards for stage, light and immersive audio."

Captions are indexed by Apple since 2025 — keep the keyword-bearing captions
above (heartbeat, pulse, genres, synth, MIDI, AUv3, Art-Net).

Preview video (optional, +20–40% conversion): 15–30 s — finger on lens →
pulse locks → play → music + visual react → "Free. Private. No account."

---

## Claim verification (2026-07-16, against code + FEATURE_MATRIX)

Every description claim re-checked against the repo — all grounded:
camera rPPG / universal BLE 0x180D / HealthKit (LIVE) · real HRV coherence
Lomb-Scargle+Welch (LIVE) · 23 genres, 10 scales, A4 432–444 (LIVE) ·
poly synth + patch editor + presets, drum sequencer velocity/accent/swing,
piano roll, loop cutter, FX chain (LIVE) · stamped MIDI export, MIDI/MPE
in+out (LIVE) · AUv3 plugin (shipped builds 1467/1469) · OSC + ADM-OSC +
Art-Net + sACN unicast (LIVE) · Metal visual + MP4 clip recording (LIVE) ·
nearby session share (`Sync/MultipeerSession` + `Studio/LiveColaboView`,
wired). **Two claims are DEVICE-verify-pending before submission (founder):**
(1) BLE strap end-to-end (strap on order — NEEDS-FOUNDER-VERIFY since B4),
(2) AUv3 inside a third-party host on current builds. If either fails on
device, soften or cut that line before submitting.

## Remaining founder to-dos for submission

1. Screenshots (list above) on a real device (6.7" + 6.1" sets).
2. App Store Connect: paste name/subtitle/keywords/promo/description/notes
   from this file; set category Music + Health & Fitness; price Free;
   privacy "Data Not Collected".
3. Support URL: https://echoelmusic.com (exists) · Marketing URL: same.
4. Full TestFlight run (`build_only=false`) → pick the build → Submit.
