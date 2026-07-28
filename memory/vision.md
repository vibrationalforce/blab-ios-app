# Echoel — Vision (North Star, tiered)

Durable knowledge. Read at session start with the rest of `memory/`. This is the
**optimized Echoel vision** — the filter every external idea is measured against
(see `memory/inspiration_intake.md` + `.claude/skills/vision-gate/`).

> **The instrument where ONE body plays multiple real dimensions at once —
> sound, space, light, vibration — over open standards, no SDK lock-in.
> The bio-reactive object *source*, not a renderer.** *Create From Within.*

Echoel — Physical Computing · Biofeedback · Multimedial & Multidimensional.
iPhone-first. On-device, private, free. The body is the controller.

---

## The five dimensions (one instrument, never new tabs)

**Body** (the differentiator) → **Sound** → **Space** → **Light** → **Vibration**,
with **Data** (OSC / MIDI 2.0 / MPE / AUv3) as the connective layer.

---

## TIER 1 — LIVE (shipping; code-verified, TestFlight 1867 / v10.17.0)

- **Body as controller** — HR/HRV/breath/coherence via HealthKit + universal BLE
  (any 0x180D) + camera rPPG (locks on device) + Demo → 10 Hz bus snapshot.
- **Bio-generative music** — in-key melody/rhythm/tempo, seeded/reproducible. **8 genres are
  OFFERED** in the picker (`MusicStyle.offered`) out of 25 declared in the taxonomy
  (`MusicStyle`) — the curation is the founder's 2026-07-24 call and 8 is the number the App
  Store text claims. Source of truth: `Sources/Echoelmusic/Sequencer/MusicStyle.swift`.
  ("12 genres" here was never true of either number.)
- **Synthesis & export** — DDSP harmonic-plus-noise + polyphonic pad/lead + sub-bass, FX
  chain, LUFS WAV, MIDI export. (`EchoelCellular` has ZERO production consumers and
  `EchoelModalBank`'s only caller was the deleted drum voice — neither makes a sound today.)
- **Light** — native Art-Net + sACN, zero-dependency UDP (strongest non-audio dimension).
- **Space** — ADM-OSC immersive object out (`/adm/obj/{n}/*`) → L-ISA / d&b / FletcherMachine.
- **Vibration / LFE** — dedicated pushable sub-bass voice + Core Haptics infra.
- **Visual** — Metal GPU bio-renderer (HR→pulse ≤2 Hz WCAG, coherence→hue, breath→spread).
- **Open spine** — OSC, MIDI 2.0/MPE in, RTP-MIDI. **Apple**: Widgets shipped (WidgetKit).
  **AUv3 removed 2026-07-24 (#122/#123)** — Echoel is neither a plugin nor a host.

## TIER 2 — ROADMAP (planned; partially wired or authorized, not built)

- **Live RTMP/SRT broadcast** — HaishinKit authorized (sole sanctioned dep), 0 code yet.
- **AUDIOVISUAL VOCODER (flagship)** — voice+body → sound+visual+light at once; pure cores
  built 2026-06-18 (`VocoderCore`/`FeedbackGuard`/`BioModulation`), wiring next. The unique,
  inclusive edge (no competitor does bio/voice-driven AV vocoding).
  **⛔ The 2026-06-20 "full all-in-one professional production environment" pivot that stood
  here is ITSELF SUPERSEDED (2026-07-24, #121; decisions.csv rows 84/101/102/190/191).** The
  canonical boundary is now `docs/dev/PRODUCT_DEFINITION.md`: **Editor ≠ Workstation** — the
  instrument plus its multidimensional output stage (sound · visual · light · space). DAW,
  AUv3 host, video/NLE and broadcast were dismantled on purpose.
  `scratchpads/PLAN_PRO_PRODUCTION_SUITE.md` plans a product that no longer exists — history
  only, do not plan from it.
- **Echoel AS an AUv3** — deferred, NO code (target deleted 2026-07-24). Hosting third-party
  AU is decided OUT (#190).
- **Multichannel / 360° immersive sound, head-tracked binaural, Atmos authoring.**
- **CoreML / RAVE neural latent layer** — gated on an on-device latency prototype.
- **macOS / visionOS / tvOS / App Clip surfaces.**

## TIER 3 — NORTH STAR (concept, honestly far-future; NEVER product copy)

- **Multidimensional interactive installation worlds / immersive media art** — the
  animating identity; depends on the whole roadmap stack first.
- **Realtime live broadcast as a brand pillar** (Cinema/Theater/Performance).
- **Auto-driving assistant** — parking lot, speculative (`user.md`). No code, no copy.
- **Dive-flying (Tauchfliegen)** — parking lot, North Star (`user.md`). Unrelated to app.
- **Biofeedback + self-observation "revolutionizing humanity"** — emotional north star
  behind *Create From Within*. Expressed ONLY as self-observation, NEVER as a
  health/medical/therapy claim (FDA general-wellness red line).

## BANNED (overclaim — the founder asked, the project refused)

Quantum AI · Super-AI / AGI · wellness/healing/Solfeggio/chakra · "16K" ·
"BLAB" / Vibrational Force / legacy soundscape branding. **The code is the truth;
if the website disagrees, the code wins.**

---

## Founder principles (the constitution)

1. **Stable-first / build-green is the only gate.** Ralph Wiggum: one change/cycle,
   no batching, CI-verified before trusting it.
2. **Open standards, near-zero dependencies, no SDK lock-in.**
3. **Biofeedback is science, not wellness.** Show the number, never promise the benefit.
4. **Brand purity / no overclaim.** Code is truth.
5. **Accessibility-first.** VoiceOver, WCAG ≤3 Hz flash by construction, Atkinson font,
   the "felt"/haptic dimension validated with the Deaf community.
6. **One paradigm: fan out from the bio core.** Every surface is a pillar off the same
   bus. Anti-pattern: breadth-first oscillation (history shows 5 oscillations, 0 breadth).
7. **Audio-thread sanctity.** No malloc/locks/GCD in the render path.
8. **Honesty over cheerleading.** Green CI ≠ works on device.

---

## Standing vision↔code gaps to keep honest (review each cycle)

1. **"Live Broadcast" is a brand pillar with zero code** — and it oscillates
   (cut 06-12, re-listed 06-17). Resolve via the gate, then either build or stop claiming.
2. **CLAUDE.md "v10 Target" diagram describes an app never built** (Beat/Record/Video/
   Share tabs); the as-built is one `EchoelStudioView`. Same file contradicts itself.
3. **(RESOLVED 2026-06-18)** FEATURE_MATRIX reconciled to code (MetalBioView LIVE, 23 genres,
   sACN unicast live, new vocoder/biomod cores flagged not-yet-wired).
4. **Bus topics `bioFrames`/`bioEvents` are reserved but undrained**; bio flows over the
   snapshot (per-RR heartbeat events have no synth sink). Lock-free design partly aspirational.
5. **North-Star concepts (auto-driving, dive-flying) have no written bridge** to the
   roadmap — intentionally, but keep them parked, not leaking into copy.

_Last synthesized: 2026-06-18. Re-audit when the brand promise and the
shipping reality drift further than one cycle apart._
