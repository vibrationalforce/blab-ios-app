# Echoel — Vision (North Star, tiered)

Durable knowledge. Read at session start with the rest of `memory/`. This is the
**optimized Echoel vision** — the filter every external idea is measured against
(see `memory/inspiration_intake.md` + `.claude/skills/vision-gate/`).

> **Echoel is a bio-reactive instrument — your body plays it, and its output is
> multidimensional (sound, image, light, space).** Over open standards, no SDK
> lock-in; the bio-reactive object *source*, not a renderer. *Create From Within.*

⛔ **The sentence above is the RATIFIED one** (PRODUCT_DEFINITION.md, founder-delegated
2026-07-25). The variant that stood here — "sound, space, light, **vibration**", no
*image* — predated it and diverged from the canon in the one file the vision-gate skill
scores against: it dropped the VISUAL, which is a ship-gate check, and promoted haptics
into the sentence. Vibration/haptics stay real as an output-stage subscriber (sub-bass
voice + Core Haptics), listed below — not in the one sentence. Caught by the 2026-08-28
brand audit; if the canon sentence ever changes, it changes THERE first and here second.

Echoel — Physical Computing · Biofeedback · Multimedial & Multidimensional.
iPhone-first. On-device, private, free. The body is the controller.

---

## The five dimensions (one instrument, never new tabs)

**Body** (the differentiator) → **Sound** → **Image** → **Light** → **Space** (the
canonical pillars; vibration/haptics ride the output stage), with **Data**
(OSC · MIDI 2.0 · MPE **out** — in is not built, #548 · Art-Net/sACN · ADM-OSC) as the
connective layer. (⛔ "MPE / AUv3" stood here: AUv3 was removed 2026-07-24 and MPE-IN has
no zone parser — naming either in the spine re-sold two struck capabilities.)

---

## TIER 1 — LIVE (shipping; code-verified, TestFlight 1867 / v10.17.0)

- **Body as controller** — HR/HRV/breath/coherence via HealthKit + universal BLE
  (any 0x180D) + camera rPPG (locks on device) + Demo → 10 Hz bus snapshot.
- **Bio-generative music** — in-key melody/rhythm/tempo, seeded/reproducible. **16 genres are
  OFFERED** in the picker (`MusicStyle.offered`) out of 33 declared in the taxonomy
  (`MusicStyle`) — the 2026-07-24 curation set 8, #254 took it to 16 on 2026-07-30. Source of
  truth: `Sources/Echoelmusic/Sequencer/MusicStyle.swift`; count it, do not read it.
  ⛔ This said "8 … out of 25 … and 8 is the number the App Store text claims" — all three
  wrong, and the third was made wrong BY #428, which recounted the store text without
  touching the sentence that cites it. ("12 genres" here was never true of either number.)
- **Synthesis & export** — DDSP harmonic-plus-noise + polyphonic pad/lead + sub-bass, FX
  chain, LUFS WAV, MIDI export. (`EchoelCellular` has ZERO production consumers and
  `EchoelModalBank`'s only caller was the deleted drum voice — neither makes a sound today.)
- **Light** — native Art-Net + sACN, zero-dependency UDP (strongest non-audio dimension).
- **Space** — ADM-OSC immersive object out (`/adm/obj/{n}/*`) → L-ISA / d&b / FletcherMachine.
- **Vibration / LFE** — dedicated pushable sub-bass voice + Core Haptics infra.
- **Visual** — Metal GPU bio-renderer (HR→pulse ≤2 Hz WCAG, coherence→hue, breath→spread).
- **Open spine** — OSC, MIDI 2.0 (mono in: notes + pitch-bend; **MPE OUT** since #713 —
  MPE IN is not built, #548), RTP-MIDI. **Apple**: Widgets shipped (WidgetKit).
  **AUv3 removed 2026-07-24 (#122/#123)** — Echoel is neither a plugin nor a host.

## TIER 2 — ROADMAP (planned; partially wired or authorized, not built)

- ⛔ **Live RTMP/SRT broadcast — CUT, not roadmap** (Editor ≠ Workstation, 2026-07-25;
  "broadcast" struck from the identity line 2026-07-31). HaishinKit stays unlinked.
  Honest tier per `inspiration_intake.md`: WATCH. Re-entry needs a founder ask, not a plan.
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
- ⛔ ~~Realtime live broadcast as a brand pillar~~ — struck 2026-07-31 with the identity
  line; Cinema/Theater/Performance are served by the OUTPUT stage (light/space/visual),
  not by streaming. Kept only so the strike is findable here too.
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

1. **(RESOLVED 2026-07-31)** "Live Broadcast" — the gate answered: CUT (Editor ≠
   Workstation) and struck from the identity line. WATCH tier; no longer an oscillation.
2. **CLAUDE.md "v10 Target" diagram describes an app never built** (Beat/Record/Video/
   Share tabs); the as-built is one `EchoelStudioView`. Same file contradicts itself.
3. **(RESOLVED 2026-06-18)** FEATURE_MATRIX reconciled to code (MetalBioView LIVE, 23 genres,
   sACN unicast live, new vocoder/biomod cores flagged not-yet-wired).
4. **Bus topic `bioFrames` is reserved but undrained** (`bioEvents` IS drained — sole consumer `OSCSender.drainAndSendEvents`, OSC egress only; ⛔ both stood here as undrained, audit 2026-08-28); bio flows over the
   snapshot (per-RR heartbeat events have no synth sink). Lock-free design partly aspirational.
5. **North-Star concepts (auto-driving, dive-flying) have no written bridge** to the
   roadmap — intentionally, but keep them parked, not leaking into copy.

_Last synthesized: 2026-06-18. Re-audit when the brand promise and the
shipping reality drift further than one cycle apart._
