# DEEP AUDIT — Echoel: where we are & does the full vision go through? (2026-06-03)

Three parallel read-only audits (history · code-reality · website), file-grounded.
Consolidated here so the conclusion is durable. **Verdict at the bottom.**

---

## 1. History — a pendulum around one stable anchor
Git history was squashed at the v10 pivot (98 commits; v5–v9 survives only as narrative).
Five documented positionings; the throughline is **physiology as a first-class, lock-free,
typed-bus modulation source**. What oscillated is the *output surface + commercial frame*:

`BLAB/wellness (v5–7) → focused soundscape (v8) → 12-tool DAW suite (v9) → DAW+Video+Stream pivot (v10) → bio-reactive instrument re-anchor (2026-05-18)`

The 05-18 strategy is the self-correction: confronted with competitive analysis, the project
**deliberately conceded the DAW and VJ axes** and kept only the bio-native architecture as moat.
Convergence is enforced by *honesty mechanisms* (FEATURE_MATRIX "code wins", SDK doctrine),
not vision statements. Residual: the brand line still advertises breadth the code lacks.
Tell: `SESSION_LOG.md` is still titled "Healing Log".

**Never built despite being headline pivots:** RTMP/HaishinKit (the v10 "Stream Live" flagship —
0 lines, `dependencies: []`), EchoelLux/DMX (brand line only). Protected DSP triad was originally
fabricated citations with dead tests (masked by `skip_tests=true`) → later honestly implemented.

## 2. Code reality — what the running 4-tab app actually delivers
Live tree: `EchoelmusicApp → StudioRoot` → tabs **Tools · Works · Sync · Well** (NOT the
CLAUDE.md Beat/Record/Video/Share). Reachability is the test — dormant code ≠ product.

**REAL & wired (a coherent bio-reactive instrument):**
- EchoelBio (HealthKit/Polar/Demo → bus; DSP triad present) — strongest pillar
- EchoelSynth (DDSP/modal/cellular, audible, bio-mapped)
- EchoelSeq (8×16 sequencer + pads) · EchoelMIDI (MPE in)
- EchoelNet OSC-out (send-only) · Modulation/Sync tab (matrix *understates* this — it's live)
- WellView (breathing/coherence) · one SwiftUI bio-visual

**DORMANT — code exists but UNREACHABLE (recoverable by wiring, not rebuilding):**
- Audio **recording & export** (RetroCapture/SingleExport exist — **no reachable REC/export button**)
- **Metal visuals** (full 120fps/5-mode/chroma pipeline — reachable UI is only an ~80-line SwiftUI Canvas)
- Video / camera capture / rPPG / ShortContentRenderer

**ABSENT — 0 code (from-scratch builds):**
- **Light (EchoelLux/DMX/Art-Net)** · **RTMP/Broadcast** (no HaishinKit) · AR / spatial audio / visionOS

**Honest one-liner:** brand promises *Audio · Video · Light · Broadcast*; code delivers
**Audio + Bio** (real, wired) + one visual + OSC out. Video dormant, Light & Broadcast absent.

## 3. Feature Matrix — how far, with drift
4 LIVE (Synth/Seq/MIDI/Bio) · 5 PARTIAL (FX/Mix/Vis/Vid/Net) · 3 empty-ROADMAP (Lux/Stage/AI).
**Matrix drift to fix:** it OVERSTATES EchoelVis (Metal dormant→only Canvas reachable), EchoelVid
(no reachable surface), EchoelMix (no reachable REC/export); UNDERSTATES Modulation (now live).

## 4. echoelmusic.com — two-tier honesty
- **Gold standard:** architecture.html + overview.html (every roadmap item tagged LIVE/Planned).
- **Still read as a shipping product (fix to mirror the two above):**
  1. **🔴 security.html — material-liability overclaim:** claims AES-256/CryptoKit, cert pinning,
     Face ID/Keychain, **GDPR & CCPA compliance**, "Enterprise-grade security" — the code has
     NONE of these (no network/accounts/crypto). Highest priority.
  2. **index.html L822** "Beats or **healing**" — last clear banned-term in marketing copy.
  3. index bento + JSON-LD featureList present ProRes, AI-directed production, DMX/projection,
     "hosts third-party AUv3 plugins" as shipping.
  4. accessibility.html: "WCAG 2.2 AAA", "20+ Profiles", "6 Platforms" presented as fact.
  5. faq.html: camera-rPPG launch/JSON-LD contradiction; "iOS 15+…visionOS 1+" vs iOS-18 floor.
  6. tools.html: EchoelFX "VST3/CLAP/Ableton/Bitwig/REAPER" (only AUv3 exists); Spectral Morph untagged.
  7. health.html "wellness program/coaches" drift; sitemap `lastmod` stale.
- Menu declutter verified; no broken internal links.

---

## VERDICT — "only a biofeedback tool, or does the whole vision go through?"

**Echoel is already MORE than a biofeedback tool** — the shipping app is a *bio-reactive
instrument* (bio + synthesis + sequencer + MIDI + OSC + modulation). That is the real,
differentiated product and the moat: **physiology, on a lock-free typed bus, driving sound in
real time — what no DAW/VJ tool is built around.**

**The full "multimedia · multidimensional · visuals · light · broadcast" vision CAN go through —
but only one way:** as ONE instrument whose every surface (sound → visual → light → broadcast) is
**driven by the body**, built **one device-verified pillar at a time**. It does NOT go through as
"12 tools at once" — the history proves that breadth-first caused five oscillations and shipped
none of the breadth (RTMP & Light were headline promises with zero code).

**Why it's achievable:** the `EngineBus` architecture is purpose-built for many producers/consumers;
much "missing" capability is **dormant code needing UI wiring, not new builds** (recording, export,
Metal visuals already exist). The bottleneck is **verification (device/macOS) + single-dev bandwidth +
the discipline not to oscillate** — not architecture.

**The sequence that makes the vision real (each phase device-verified):**
1. **Now → App Store:** nail the bio-reactive instrument. **Wire the dormant REC/export + the Metal
   visual** (highest ROI "more" — it exists, just unreachable). This alone turns "biofeedback tool"
   into "a bio-reactive instrument you can play, see, and record."
2. **Video/multidimensional:** the `CameraHub` fan-out (already specced) — bio-driven video & AR.
3. **Light (EchoelLux) + Broadcast (RTMP/HaishinKit):** the genuine from-scratch pillars — each its
   own project, only after 1–2 are solid.

**The coherence test (and the moat):** every surface must fan out from the bio bus —
bio-driven sound, bio-driven visuals, bio-driven light, bio-reactive broadcast. That is what makes
the breadth *one instrument* instead of a feature-dump, and it is exactly what nobody else has.

**Bottom line:** Not "only biofeedback." Not "12 tools at once." **A body-played multimedia
instrument, grown one verified pillar at a time from the bio core.** That version goes through.
The same honesty discipline already established (matrix, code-wins) is what keeps it from
relapsing into breadth-without-depth — starting with fixing security.html.
