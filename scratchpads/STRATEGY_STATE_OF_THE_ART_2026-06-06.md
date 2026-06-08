# State-of-the-Art Roadmap — "Vorbei am Industriestandard bis ganz nach vorne"

**Date:** 2026-06-06 · **Mode:** Echoelmusic.com (accessible · immersive · multidimensional · media art + production + self-observation · *Create From Within*)
**Method:** 5 parallel deep-research agents (synthesis · multidimensional control · immersive/spatial · visuals/video/light · biofeedback). Each report is cited; key uncertainties flagged. This file is the synthesis + adoption plan.

**Doctrine reminder (the filter for every decision below):** open standards, depend on almost nothing; audio thread = no malloc/locks/GCD; iPhone-first; biofeedback is core but **NO health/medical claims** (self-observation only). "Newest engines only" — but *only where it survives the on-device real-time bar*.

---

## The one-line verdict per pillar

| Pillar | Industry standard | Newest SOTA (2025–26) | Open protocol (our lane) | Echoel move |
|---|---|---|---|---|
| **Synthesis** | Hand-DSP (VA/FM/wavetable/granular/modal) | RAVE v2, DAC codec, HT-Demucs, diffusion morph | ONNX→CoreML; MIT-licensed models | Keep hand-DSP on audio thread; add CoreML/RAVE **latent layer OFF-thread**, bio-driven |
| **Multidim. control** | **MPE = 3D** (MIDI Assoc.) | ROLI Airwave (air/gesture); MIDI 2.0 high-res rolling out | MPE · MIDI 2.0 · OSC | **Bio = our extra dimensions**; carry over MIDI 2.0 per-note + OSC; stay MPE-baseline |
| **Immersive/spatial** | L-ISA · d&b Soundscape · FletcherMachine · SPAT (all proprietary renderers) | L-ISA Sound Spaces; MPEG-H broadcast; active acoustics (Constellation/Vivace) | **ADM-OSC** (we already emit it) | Stay the **bio-reactive object SOURCE**; validate vs renderers; native-protocol fallback |
| **Visuals/Video/Light** | Resolume/TouchDesigner/Notch; DMX/Art-Net/sACN | StreamDiffusion real-time AI; UE5.6 ST2110; ProRes RAW (17 Pro) | **OSC · NDI · Art-Net · sACN** | OSC-out first; **native Art-Net/sACN (no SDK)**; optional NDI sender; skip Syphon/ProRes RAW |
| **Biofeedback** | HRV/RMSSD + resonance breathing (solid); rPPG/EEG (noisy) | 2025 rPPG robustness; Fraunhofer IIS affective sensing | **BLE HRS (0x180D) · HealthKit · LSL · OSC** | Most *scientifically honest* bio-instrument; show numbers, claim nothing |

---

## 1. Synthesis & sound engines — "newest only" ≠ "neural everywhere"

**Finding (skeptical):** No source verifies ANY neural synth running real-time on an iPhone audio thread at <10 ms. RAVE/DAC/Demucs benchmarks are laptop/Mac/RPi/desktop. RNN-DDSP (2022) is now first-gen/legacy. Neutone SDK = desktop/JUCE; Vital engine = not reusable; Surge XT = GPL (viral, App-Store-incompatible) → borrow ideas, never link.

**Adopt:**
1. **Keep the hand-written DSP on the render thread** (`EchoelDDSP`/modal/cellular). Correct, SOTA-competitive, doctrine-safe. Do NOT replace with RNN-DDSP.
2. **Neural OFF the audio thread, via CoreML (ONNX-imported), as a generator/morph stage** — not a per-sample renderer. Highest-leverage "newest" target: **RAVE v2 → ONNX → CoreML**, run in latent/block mode, latent driven by `bioFrames`. **Prototype on-device latency FIRST** — that number is the gate, and the literature does not give it.
3. **DAC (MIT)** as the neural-codec/latent backbone if we want timbre-space morphing (prefer over legacy EnCodec/SoundStream).
4. **HT-Demucs (MIT)** as an **offline** on-device feature only (stem extract / resample / chop) via the iOS-26 CoreML export. Never marketed as live.
5. Bio-driven timbre morphing (SoundMorpher / unified-timbre-transfer) = roadmap research, **not** real-time on iPhone yet.

*Sources: github.com/acids-ircam/RAVE · descriptinc/descript-audio-codec · demucs · arxiv 2508.09126 (Neutone) · arxiv 2410.02144 (SoundMorpher) · vital.audio · surge-synthesizer.github.io*

---

## 2. Multidimensional control — bio is the dimension nobody else has

**Finding:** "5D" is **ROLI marketing**, not a standard. MPE = **3** continuous dims (Pitch/Timbre/Pressure), mostly 7-bit. ROLI "5D" = MPE 3 + 2 velocity (Strike/Lift). ROLI **Airwave** (2025, IR cameras, 27 joints @90fps, ~€299) adds 5 "air" dims but collapses into MPE downstream. **MIDI 2.0** is the real high-res substrate (16/32-bit, per-note controllers, Property Exchange) — OS plumbing ready (CoreMIDI since 2020; Windows native Feb 2026), bottleneck is firmware. Bio-driven expression has **no industry standard** = our open frontier (NIME/arXiv 2025 only).

**Adopt:**
1. **Brand bio as a first-class, named dimension set** stacked on MPE's 3 + air's 5 — "beyond-5D", grounded in real physiology, not marketing. This is the defensible Echoel claim.
2. **Carry bio/air over MIDI 2.0 per-note controllers (32-bit) + Property Exchange**, not 7-bit air-CC (the weak link). Use Property Exchange to self-describe Echoel's bio dimensions to DAWs.
3. **OSC = the lossless bio transport** for installation/broadcast/cross-device (already live `/echoelmusic/bio/*`). MIDI 2.0 = instrument/DAW interop; OSC = the installation multiverse.
4. **Never break MPE baseline** on input — it's how we play with Seaboard/LinnStrument/Logic.

*Sources: midi.org MPE + MIDI 2.0 (Feb 2026) · soundguys Airwave review · sweetwater MIDI 2.0 · arXiv 2505.03073*

---

## 3. Immersive & spatial — we are already in the right lane (ADM-OSC)

**Finding:** Pro immersive = a few **proprietary** object renderers (L-ISA leads touring; d&b Soundscape leads theatre/install; FletcherMachine V2.3; SPAT software). They DON'T interoperate internally — they standardize at the **control layer = ADM-OSC** (founded by L-Acoustics/FLUX/Radio France; contributors incl. BBC, Dolby, d&b, Steinberg, Meyer). Spoken by SPAT, L-ISA, d&b En-Bridge, QLab 5, SpaceMap Go, FletcherMachine, Nuendo, Sound Particles. "4D" = no standard; real version = **convolution active-acoustics** (Meyer Constellation, Müller-BBM Vivace, d&b En-Space) + separate haptics. **MPEG-H** = the broadcast NGA standard (2025 momentum). **Felix Deufel** → founded **ZiMMT Leipzig** (immersive media-art centre); **Grapes 3D Audio Control** = manufacturer-agnostic OSC controller, integrated with Vivace — a direct **peer/reference** to Echoel's controller ambition (but without the bio source).

**Adopt:**
1. **Stay a SOURCE, not a renderer.** Bio → `/adm/obj/{N}/{azimuth|elevation|distance|x|y|z|gain}`; let L-ISA/d&b/FletcherMachine do the physics. (Already shipped: `ADMOSCSender`.)
2. **Conform to ADM-OSC v1.0 ranges; validate per target** with the repo's Python validator (cross-vendor normalization drift is real).
3. **Native-protocol fallback lane** (direct OSC to L-ISA/d&b native namespaces) for width/spread/room-send beyond position+gain.
4. **Don't build the room/"4D" layer — feed it.** Send objects + OSC scene cues into Constellation/Vivace/En-Space; haptics = separate OSC cue stream, not an audio "4D" claim.
5. **Broadcast = target MPEG-H + Apple Spatial Audio downstream** of the same object data.
6. **Position against Grapes, not renderers** — our edge is the *bio* object source, a category no one occupies. **Strategic fit:** Deufel/ZiMMT (immersive venues) + Johannes Bollmann (Panasonic projection servers, free; Messe/venue distribution) = a real EU installation go-to-market for EchoelStage.

*Sources: github.com/immersive-audio-live/ADM-OSC · l-acoustics L-ISA · dbsoundscape · adamson FletcherMachine V2.3 · atsc MPEG-H · mbbm Vivace×Grapes · zimmt.net*

---

## 4. Visuals / Video / Light — the cleanest doctrine wins are here

**Findings (hard iOS constraints):** **Syphon does NOT exist on iOS** (IOSurface/Cocoa) → can't port. **NDI** = the realistic IP-video interop, but iOS senders run ~1080p30 over WiFi and the SDK is proprietary (Vizrt) — bends "no SDK". **ProRes RAW** = 17-Pro-only + external SSD → instrument-misaligned. **StreamDiffusion** = breakout real-time AI visuals (needs GPU/cloud, not on-device iPhone). **Lighting:** DMX-512/Art-Net/sACN entrenched; **Art-Net + sACN are pure open UDP wire protocols → native Swift, ZERO dependency** = the single best doctrine fit in the whole report.

**Adopt (priority order):**
1. **OSC-out to drive external visual engines** (TouchDesigner/Resolume/Notch) — already on the bus, fully open, biggest reach, lowest effort. **Primary integration.**
2. **Native Art-Net output module** (Swift, no SDK), bio → DMX, respecting the existing 3 Hz flash / WCAG limit. Add **sACN** next (multicast, high universe counts, priority/backup). One small self-contained target, zero deps — **highest-ROI roadmap item.**
3. **HEVC** as default high-efficiency capture (free via VideoToolbox) before any ProRes.
4. **RTMP via HaishinKit** stays the live path (already the sole external dep).
5. **Optional NDI sender** for the Metal frame (accept proprietary-SDK + WiFi-latency caveats). **Skip Syphon and ProRes RAW for v10.**

*Sources: syphon.info / Syphon-Framework · docs.ndi.video · advateklighting Art-Net vs sACN · macrumors ProRes RAW 17 Pro · interactiveimmersive StreamDiffusion*

---

## 5. Biofeedback — be the most scientifically honest bio-instrument

**Findings:** Resonance breathing (~0.1 Hz / ~6 bpm, baroreflex) is the **strongest** evidence base; RMSSD is the robust short-term parasympathetic index (Apple gives only SDNN → self-compute RMSSD from RR — we do). "Coherence" *branding* (HeartMath) is scientifically contested → treat coherence as a **measurable DSP metric** (0.1 Hz HR oscillation power), never a mental/spiritual state. **rPPG**: viable for expressive HR, but degrades with motion/light/skin tone/high HR — **fingertip > facial**; not reliable for beat-sync or HRV under movement (this is exactly the owner's "loud music = unstable" observation — physics, not a bug). **EEG** (Muse/Emotiv/OpenBCI): band-power expressive control only, not diagnostic. **Fraunhofer IIS** = Affective Sensing (SHORE® facial + camera pulse + sensors; MRI-Bioface); **Fraunhofer HHI** = Immersive Media — natural research partners. **Regulatory:** FDA 2026 General-Wellness guidance keeps low-risk products OUT of device regulation *iff* no disease/diagnosis/treatment/threshold/"abnormal" claims. CE/EU MDR same: the **claim**, not the sensor, triggers classification.

**Adopt:**
1. **Position as an instrument, not a metric.** "Your breath drives the filter" = control statement, not health claim. Lean in hard.
2. **Allowed:** self-observation, explore, real-time biofeedback for art/performance, general relaxation, creative expression. **Banned:** stress-reduction-as-outcome, therapy, treatment, "improves HRV/health", diagnosis, coherence-as-state, + the existing esoterica ban. **Show the number; never promise the benefit.**
3. **Reframe coherence** as a named DSP metric (0.1 Hz power), number/sparkline only.
4. **In-UI transparency strengthens the wellness-not-medical position:** rPPG affected by motion/light/skin; Watch HR ~4–5 s (no beat-sync); "self-observation, not medical diagnosis" (already correct in CLAUDE.md).
5. **Technical edge:** RR-based RMSSD from BLE HRS (cleanest live HRV); fingertip PPG = high-accuracy path, facial = contactless/expressive (label by fidelity); EEG = band-power control only; **BLE HRS + HealthKit + LSL + OSC** as the open spine into TouchDesigner/Max/research rigs.

*Sources: PMC5575449 (resonance) · PLoS One RMSSD · sciencebasedmedicine (HeartMath critique) · mdpi 14/5/1015 (rPPG 2025) · Fraunhofer IIS affective-sensing · FDA 2026 general-wellness guidance*

---

## Prioritized adoption roadmap (step-by-step, doctrine-first)

**Now / next cycles (low-risk, high-ROI, pure open standards):**
1. ✅ **ADM-OSC bio object source** — shipped (build 1518). Next: per-renderer validation + native fallback lane.
2. **Native Art-Net output** (Swift, no SDK) — bio→light, 3 Hz cap. Then sACN. *Biggest doctrine win.*
3. **OSC-out hardening** as the universal visual-engine driver (document mappings for TouchDesigner/Resolume).
4. **MIDI 2.0 per-note + Property Exchange** for bio/air dimensions (replace 7-bit air-CC dependence); keep MPE baseline.

**Then (medium effort, needs prototyping/verification):**
5. **CoreML/RAVE latent layer OFF the audio thread** — bio-driven neural morph. Gate on an on-device latency prototype.
6. **HEVC capture** default; **NDI sender** (optional) for the Metal frame.
7. **HT-Demucs offline** stem extract (iOS-26 CoreML), never live.

**Strategic / partnerships (parallel, non-code):**
8. **EchoelStage GTM:** Deufel/ZiMMT (immersive venues) + Bollmann (Panasonic servers free, Messe/venue distribution) + Adamson/Roman (FletcherMachine demo). Position vs Grapes; our wedge = the bio object source.
9. **Biofeedback research credibility:** explore Fraunhofer IIS (affective sensing) / HHI (immersive media) as research anchors — strengthens the "scientifically honest" identity (still no health claims).

**Explicitly DON'T:**
- Replace hand-DSP with RNN-DDSP (legacy); link Neutone/Vital/Surge (desktop/GPL/closed).
- Build Syphon (impossible on iOS) or ProRes RAW (17-Pro/SSD-gated) for v10.
- Build a spatial renderer or a room/"4D" engine — feed existing ones via ADM-OSC/OSC.
- Make any health/therapy/wellness-outcome claim — ever.

---

## Cross-cutting identity (the front edge)

Echoel's defensible position is the **intersection** none of the incumbents occupy:
> the **bio-reactive object source** for accessible immersive multidimensional media art — open-standard everywhere (ADM-OSC, MIDI 2.0, OSC, Art-Net/sACN, BLE HRS, HealthKit, LSL), scientifically honest, claim-free, iPhone-first.

ROLI owns gesture; L-ISA/d&b own rendering; Grapes owns the agnostic controller; HeartMath owns (contested) wellness branding. **Nobody owns "the body as a first-class, open-standard control + spatial source for media art."** That is the lane. *Create From Within.*
