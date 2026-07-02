# PLAN — Bio-Generative Music Instrument (Echoelmusic.com + Apple App)

**Owner directive (2026-06-12):** Generate heartbeat loops OR whole pieces from biodata.
Use case: sound for **meditation / self-observation** AND export as **.wav (various quality
settings)** to process further in **Ableton (desktop) / FL Studio Mobile**. **Set key (Tonart)**
yourself. **Sound design shaped by prompt** → produces settings (character, filter, …). Sounds,
melody, rhythm, tempo are **computed from biodata**. Option to **lock to a BPM** (e.g. 75) for
professional processing. **Sync-free** (for meditation/self-observation) also possible.

This sharpens Echoel to its defensible wedge (see STRATEGY_USP_2026-06-12). Video/RTMP/multitrack
stay CUT.

---

## 0. Apple Developer Team "Sandbox" — how we emulate it

There is no local Xcode/Swift toolchain in this Linux container. The Apple dev-team sandbox is
emulated by the CI/CD pipeline, which runs the REAL Apple toolchain:
- **Compile sandbox:** "Echoelmusic CI/CD Pipeline" (macOS runner, swift build/test) — the per-commit
  gate every cycle waits on (green before stacking the next).
- **Archive sandbox:** `testflight.yml` `compile_check` job + `build_only=true` dispatch = Xcode 26.2
  iOS archive compiler (catches iOS-strictness the macOS swift-build misses — see decisions.csv
  2026-06-11 pointer-conversion note).
- **TestFlight sandbox:** full `testflight.yml` run (`build_only=false`) → archive → export →
  upload → "landed in App Store Connect" verification. Dispatched via PAT `workflow_dispatch`.
- **UI smoke (when available):** `ios-simulator` MCP for screenshot/tap on a booted sim.
- **Web sandbox:** `gstack`/Playwright MCP for dogfooding Echoelmusic.com.
Rule unchanged: every cycle = write code+tests → self-review → commit → push → poll CI green →
only then stack the next. iOS-pointer/raw-audio changes additionally verified via a build_only run.

---

## 1. Product model — two modes (the elegant core)

| Mode | Transport | Bio role | Output | For |
|---|---|---|---|---|
| **Studio (BPM-locked)** | fixed BPM (user picks, e.g. 75) | modulates timbre/dynamics/variation + seeds melody/rhythm, but grid stays locked | grid-quantized → **WAV + MIDI**, DAW-ready | producers (Ableton/FL handoff) |
| **Flow (sync-free)** | free-running; tempo follows heart rate continuously | drives everything live, no fixed grid | continuous audio → **WAV** | meditation / self-observation |

One toggle switches them. Both are recordable/exportable.

## 2. Capability → code map (honest: exists vs NEW)

| Capability | Status | Work |
|---|---|---|
| Bio → timbre | LIVE (BioReactiveSynthVoice / EchoelDDSP) | reuse |
| Bio → tempo | LIVE (ModulationEngine tempo route) | extend (lock vs free) |
| Bio → **melody** | **NEW** | BioComposer → in-key notes |
| Bio → **rhythm** | **NEW** | heartbeat/onset → pattern density |
| **Heartbeat loop** generator | **NEW** | 1/4-bar bio-seeded loop into pattern+roll |
| **Whole piece** | NEW (reuses Arrangement!) | chain generated sections |
| **Key / Tonart** selection | **NEW** | MusicalKey + Scale + quantize-to-scale |
| **BPM lock (75…)** | PARTIAL | tempo set exists; add lock mode (bio off tempo) |
| **Sync-free** meditation | **NEW mode** | free transport, HR→tempo continuous |
| **Prompt sound design** | **NEW** | semantic prompt → SynthPatch (character/filter/…) |
| **Multi-quality WAV export** | PARTIAL | SingleExport hardcodes 44.1/16 → add presets |
| MIDI export to FL/Ableton | LIVE (MIDIFileExporter) | surface for generated melody |
| Run inside FL Studio Mobile | target exists (AUv3, deferred) | revive AUv3 = bio-synth as plugin |

## 3. Build phases (each = one+ CI-green commit, pure kernels first)

- **G1 — Musical foundation:** `MusicalKey` (root + `Scale`: major/minor/dorian/phrygian/lydian/
  mixolydian/pentatonic-maj/pentatonic-min/harmonic-minor/chromatic) + `quantize(pitch)`→nearest
  in-scale + `degrees`. Pure value type, fully tested. *(START HERE.)*
- **G2 — BioComposer (generative core):** pure kernel `compose(bio, key, mode, bars) -> [Note] +
  rhythm`. Mappings: HR→tempo+density, HRV/coherence→consonance+contour, breath→phrase arc,
  heartbeat onset (BioEventGraph)→accents. Deterministic-from-seed so it's testable. Drives
  PolySynthVoice + PatternEngine + PianoRollModel.
- **G3 — Transport modes + Generate UI:** Studio(lock BPM picker, default 75) vs Flow(sync-free)
  toggle; "Generate loop" / "Regenerate" / "Generate piece" actions; key picker. Lives in a new
  "Compose" surface (or BeatTab section) — NOT a 6th tab.
- **G4 — Prompt sound design (OWNER DECISION 2026-06-12: smartest INDEPENDENT variant — offline,
  free, private; WITH suggestions + a LARGE preset database. No API.):**
  - `SoundPrompt.parse(text) -> patch deltas` over a rich curated vocabulary
    (warm/bright/dark/soft/metallic/airy/punchy/glassy/deep/percussive/lush/thin/hollow/wide/
    gritty/clean/evolving/plucky/pad/lead/drone…) + intensity modifiers (very/slightly/super)
    + combinable terms, applied to SynthPatch params (brightness, harmonicity, noise, cutoff/res,
    attack/release, reverb, vibrato). On-device, deterministic. NO network, NO LLM.
  - **Suggestions:** the app proposes prompts/keywords (chips) + "did you mean / try also".
  - **Large factory preset database:** a sizeable curated `SynthPatch` library (genre/mood-tagged),
    browsable + searchable, seedable as starting points for prompts. Persisted via PatchStore.
  - Optional future LLM remains explicitly OUT per owner (independence/privacy).
- **G5 — Export quality:** SingleExport presets {44.1 kHz/16-bit (stream), 48 kHz/24-bit (DAW),
  96 kHz/24-bit (master)} for WAV + keep AAC; expose MIDI export of the generated melody/drums.
- **G6 — Meditation mode polish:** sync-free ambient continuity, breath-pacer integration, Works-tab
  session record → WAV export; epilepsy/safety + "self-observation, not diagnosis" copy intact.
- **G7 (later) — AUv3 revival:** bio-synth as an Audio Unit so it runs INSIDE FL Studio Mobile /
  AUM / GarageBand — directly serves "weiterverarbeiten".

## 4. Echoelmusic.com plan (honest, focused)

- Reposition hero: **"Your heartbeat composes — lock it to 75 BPM and finish it in your DAW, or let
  it breathe sync-free for meditation."** Body as the instrument.
- Sections: Bio-generative composer · Key + BPM-lock vs Sync-free · Prompt sound design · WAV/MIDI
  export to Ableton/FL · Meditation/self-observation · Open standards (OSC/ADM-OSC/Art-Net/sACN)
  for the pro/installation niche.
- Truth: keep FEATURE_MATRIX LIVE/ROADMAP honesty; REMOVE video/streaming overclaims; never claim
  "invented coherence" (HeartMath); drop phantom comparisons. Safety warnings present.
- Update `docs/architecture.html` + `docs/tools.html` to match.

## 5. Apple ecosystem plan

- **iPhone** (primary) — the composer + modes + export.
- **Widget** (live bio glance) — exists, keep.
- **Watch** — HR source + glance (compile-verified; embedding needs local Xcode — owner-gated).
- **AUv3** (G7) — bio-synth plugin inside FL Studio Mobile / AUM / Logic / GarageBand.
- **Files / Share / iCloud / AirDrop** — WAV+MIDI out to Ableton (desktop) & FL Studio Mobile.
- Pricing: research says instrument buyers pay **once** ($4–30); reconsider current subscription.

## 6. Risks / honesty

- Generative "whole pieces" that sound musical (not random) is the hard part — keep mappings
  musical (scale-locked, phrase-shaped), iterate by ear on TestFlight. Start with LOOPS, earn
  "whole pieces".
- Prompt sound-design must not overclaim "AI"; it's semantic mapping (deterministic) unless/until
  an LLM is wired.
- 96 kHz/24-bit export on iPhone = bigger files/thermals; offer but default 48/24.
- Audio-thread rules unchanged; protected Rausch triad untouched.

**First action: build G1 (MusicalKey + Scale), CI-gated.**
