# PLAN — Echoel: "The Multidimensional Instrument"
Date: 2026-06-17 · Branch: claude/piano-roll-clip-view-wozlie
Basis: full history/repo + website audit (file-grounded) + deep research (5 angles, cited).

---

## 0. The founder's ask (verbatim intent)
- Reposition Echoel as **"das Multidimensionale"** — a category-defining product designation for multimedia production software.
- Needs: **immersive 360° UX** + **multidimensional sound**.
- A **bass track for vibrations & LFE** is important.
- The various **EchoelTools should flow more into ONE**.
- First: history/repo/chat + website audit + deep research → then this plan.

---

## 1. Deep-research findings (cited) → is "multidimensional" ownable? YES.

1. **"Multidimensional" is FREE in the MIDI/music context.** MPE originally = *Multidimensional* Polyphonic Expression, but the MIDI Association officially renamed it *MIDI* Polyphonic Expression on adoption (2018). So no vendor owns "multidimensional" as a category term — ROLI/MPE vacated it. Echoel already supports MPE, so it can nod to the lineage AND claim the broader word.
   Sources: midi.org MPE spec; roli.com/mpe; musicradar MPE explainer.
2. **"Spatial" / "immersive" / "Atmos" are heavily owned** by Dolby + Apple. Apple even markets Atmos as *"multidimensional sound and clarity"* (descriptive, not a brand category). → Do NOT compete as a renderer; position Echoel as the multidimensional **SOURCE/instrument** that feeds Atmos/L-ISA/d&b via open standards (ADM-OSC, already LIVE).
   Sources: apple.com Atmos artists; techradar Apple spatial format; wavymagazine.
3. **visionOS 26/27 = real 360°/180° immersive + head-tracked spatial audio**, but NO dedicated spatial music-creation apps cited → genuine gap/opportunity. iPhone-first today; Vision Pro = the full 360° UX roadmap.
   Sources: apple.com/newsroom visionOS 26; developer.apple.com/visionos; framesixty visionOS 27.
4. **"Felt"/haptic music is going mainstream in 2026** — haptic suits/chairs, BASSpak, CuteCircuit SoundShirt, Tactus (Deaf-community concerts Tokyo/HK). Validates the **LFE/haptic dimension** AND ties to Echoel's accessibility-first brand.
   Sources: wearable-technologies.com Feb 2026; cutecircuit SoundShirt; soundverse haptic feedback.
5. **Bio-reactive music = scientifically grounded, growing** (HRV→MIDI, GAN biofeedback; biofeedback-instrument market ~$681M 2025→$722M 2026), but incumbents are clinical/wellness. Echoel's edge: bio as a **creative/performance** source, not wellness.
   Sources: ScienceDirect GAN-HRV biofeedback; 360iresearch/alliedmarketresearch market size.

**Verdict:** "Multidimensional" is a defensible, ownable position. The defensible claim is NOT "best spatial renderer" but **"the instrument where ONE body plays multiple real dimensions at once"** — sound, space, light, haptic — over open standards, no SDK lock-in.

---

## 2. The positioning (proposed)

**Echoel — the multidimensional instrument.**
*Your body plays sound, space, light — and vibration — in real time.*

Honesty subline: *On-device, open-standard, free. Immersive 360°, multichannel render and broadcast are in active development.*

Five dimensions, ranked by how real they are TODAY:
| # | Dimension | Status | Mechanism |
|---|-----------|--------|-----------|
| 1 | **Body** (the differentiator) | LIVE | rPPG / BLE 0x180D / Watch / Demo → 10 Hz bio |
| 2 | **Sound** | LIVE | DDSP/modal/cellular, bio-generative composition, FX |
| 3 | **Light** | LIVE | Art-Net + sACN-unicast (EchoelLux) |
| 4 | **Space** | PARTIAL | ADM-OSC object out LIVE; on-device binaural + Atmos = roadmap |
| 5 | **Vibration/Haptic (LFE)** | PARTIAL→shippable | Core Haptics infra LIVE; dedicated sub-bass = this plan |

---

## 3. Ranked tracks (SHIPPABLE-NOW vs ROADMAP)

### TRACK A — Sub-bass / LFE / haptic vibration  ★ FIRST CYCLE (SHIPPABLE-NOW)
The audio output is **stereo-only** (`AudioEngine.swift:160-165`, `PolySynthVoice.swift:101`). The composer already writes a bass foundation (`BioComposer.swift:347-352,496-502`) but it plays through the shared voice pool — no separate, pushable sub, no haptic feed.
**Smallest real change:** new `Tools/SubBassVoice.swift` — mono `AVAudioSourceNode`, single low sine/tri one octave below the composed bass root, fixed ~80–120 Hz one-pole LP, public `subGain` (default 0), launch-silence + audio-thread discipline mirrored from `PolySynthVoice`. Attach before `audioEngine.start()`. Feed bass-register notes from `generate()`. One "Sub / Bass" slider. Optional: drive existing `HapticController` from the sub downbeat envelope (infra already shipped) for *felt* bass.
Risk: low–med (audio-thread). Gate: deploy-dryrun + audio-thread-reviewer + device. Protected triad untouched.

### TRACK B — Website reorganization (SHIPPABLE-NOW, pure docs, zero build risk)
- New hero/positioning line (§2). 
- Fold the stale "12 EchoelTools" framing into the **5 dimensions** narrative. `tools.html` is already ~60% there (Body/Sound/Connect/Accessible/Roadmap); extend "Connect" → Space + Light + Data.
- Rewrite the stale per-tool LIVE/ROADMAP table in `architecture.html:347-394`; fix `index.html` capability map (`:674-687`) so ROADMAP nodes aren't shown as peers of LIVE.
- Update `memory/user.md:10` ("12 interconnected EchoelTools" → unified instrument). Keep CLAUDE.md/FEATURE_MATRIX taxonomy (internal).
- Brand rules hold: no esoteric/wellness terms; mark 360°/immersive/multichannel as roadmap.

### TRACK C — Tool unification in-app (LARGELY DONE)
The app is already ONE `EchoelStudioView` (one button + sliders, one `PatternEngine` clock). "Flow into one" = keep adding capability as *sliders/sections on the one instrument*, never new tabs. New sub-bass + future space controls live here. Residual = naming/labels only.

### TRACK D — Immersive 360° UX + multidimensional sound (STAGED ROADMAP)
- **Stage 0 (LIVE):** body-as-spatial-object via ADM-OSC → external renderers. Lead with this.
- **Stage 1 (first internal step):** on-device head-tracked binaural via `AVAudioEnvironmentNode`/PHASE, driving the existing per-voice pan + the ADM mapping (breath→azimuth, HRV→elevation). Stereo out, no format change.
- **Stage 2:** true multichannel bed (5.1/7.1.4) + discrete LFE — needs multichannel AVAudioFormat + spatial mixer (large).
- **Stage 3:** Atmos ADM authoring / visionOS immersive 360° scene (largest; the full "360° UX").
- **360° UX first step:** evolve the existing `BioVisualView` toward the dormant `MetalBioView`, not a new platform yet.

---

## 4. Recommended sequence (loop mode, stable-first)
1. **Cycle 1 — Track A:** sub-bass voice + "Sub/Bass" slider + optional haptic. (Ships a real new dimension; on the founder's explicit list.)
2. **Cycle 2 — Track B:** website reorg around "the multidimensional instrument" + 5 dimensions. (Pure docs; can ride with Cycle 1's ship.)
3. **Cycle 3 — Track D Stage 1:** on-device head-tracked binaural (the first real "multidimensional sound" inside the app).
4. Then re-evaluate toward 360°/visionOS.

Each cycle: implement → deploy-dryrun compile-check → review agent → ship TestFlight → update site → log decision.

---

## 5. Open question for the founder
- Tagline wording: "**the multidimensional instrument**" vs "**the multidimensional studio**" vs keep "instrument". (Instrument = honest to what ships; studio = broader/roadmap-implying.)
