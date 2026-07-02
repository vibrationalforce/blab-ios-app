# Echoel — Inspiration Intake (the Knowledge Funnel)

**How we integrate the repo's own history + external inspiration (deep research,
shared screenshots, repo links, MCP/agent/tool ecosystems) WITHOUT diluting the
optimized Echoel vision.**

The rule: **the vision is the filter, not the inbox.** Nothing is adopted because
it is impressive. Everything is scored against `memory/vision.md` and lands in a
tier. We record *what we evaluated and why we did/didn't adopt it* — so we never
re-litigate, and we never drift. The self-applying form lives in
`.claude/skills/vision-gate/SKILL.md`; the machine-readable ledger is
`inspiration.csv` (repo root, mirrors `decisions.csv`).

---

## The funnel

```
external input (repo history lesson · deep research · screenshot · repo link · MCP/agent/tool)
        │
        ▼
[ VISION GATE ]  ── score against memory/vision.md + the 8 founder principles
        │
        ├─ ADOPT → PRODUCT    fits a LIVE/ROADMAP pillar · iOS-native-feasible · on-brand · no realtime risk
        ├─ ADOPT → PIPELINE   helps us BUILD/TEST/MARKET (dev tooling, agents, CI) — never in-app
        ├─ WATCH              promising but not now → park with a review date
        └─ REJECT             off-vision / overclaim / redundant → log the reason, close it
        │
        ▼
log to inspiration.csv (+ this ledger) · if PRODUCT and material → also decisions.csv
```

## The gate — to be ADOPT→PRODUCT it must pass ALL

1. **Serves a dimension** — Body / Sound / Space / Light / Vibration / Data
   (or an explicit North-Star tier, labeled as concept, never shipped copy).
2. **iOS-native feasible on iPhone** — or honestly tiered ROADMAP / NORTH STAR.
3. **On-brand** — no wellness/esoteric, no quantum/super-AI overclaim; open-standard
   preferred; accessibility-first; the code stays the truth.
4. **Realtime-safe** — does not threaten audio-thread sanctity or the single main
   beat clock; heavy media goes on its own GPU/capture queue reading the bus snapshot.

If it fails #1 it's usually WATCH or REJECT. If it helps us ship but isn't a
feature, it's PIPELINE. When unsure: WATCH with a review date beats premature adoption.

## How the repo "stays smart"

- **History → durable lessons**, not re-discovery. The crash crucible, the silence
  saga, the breadth-first oscillation — distilled in `memory/vision.md` principles and
  `SESSION_LOG.md`. Past mistakes are encoded as rules, so we don't repeat them.
- **External inspo → ledger entries**, not scope creep. Every carousel/repo/research
  drop gets one row with a verdict. Re-seeing it later = look up the row, not re-debate.
- **Adoption → one cycle.** A PRODUCT adoption enters the Ralph loop as exactly one
  feature/cycle, built green, shipped, logged. No batching imported ideas.

---

## Ledger (running; newest first)

### 2026-06-19 — Corey Haines `marketingskills` (MIT, 45 skills) → ADOPT→PIPELINE
- Founder: adopt the marketing pack "optimized" into the repo, keep CLAUDE.md tidy.
- **Verdict: ADOPT→PIPELINE** — it markets the App Store app + `docs/` site; it is
  **never in-app / never touches `Sources/`**. MIT, self-contained, zero build/audio risk.
- **Optimized form:** vendored whole + functional at `.claude/skills/marketing/`
  (upstream LICENSE + README kept; their `CLAUDE.md`/`AGENTS.md` dropped so they don't
  shadow Echoel). Front door = new `echoel-marketing` skill: iPhone-instrument priority
  map (ASO/copy/CRO/site first; revops/sales/cold-email = low relevance) + HARD brand
  guardrails (no wellness/esoteric/overclaim; claim only what ships). CLAUDE.md gets ONE
  pointer line. `decisions.csv` 2026-06-19. Review 2026-09-19.

### 2026-06-17 — Two "top Claude tools" + "Fable 5 OS / Jarvis" carousels (17 tools)
- **claude-video** (FFmpeg frames + Whisper) → **ADOPT→PIPELINE** — analyze device
  screen-recordings for QA + promo reels. Not in-app.
- **Skill architecture (SKILL.md)** & **markdown long-term memory (Obsidian-vault pattern)**
  → **ALREADY ADOPTED** — we run `.claude/skills/` + `memory/`+`scratchpads/`+`decisions.csv`.
  Validation, not a to-do.
- **graphify / open-design / impeccable / design-extract** → **WATCH** — only touch the
  `docs/` marketing site; optional polish, not product.
- **Local voice (Whisper STT + Kokoro TTS)** → **WATCH** — on iOS the equivalent is
  Siri/App Intents, already wired (`EchoelIntentInbox`).
- **caveman / codeburn / career-ops / browser-harness** → **REJECT** — terse-output risks
  rigor / pure ops / irrelevant / redundant with the Playwright MCP.
- **VAULT HUD + reskin-per-client** → **REJECT** — agency play; Echoel is one consumer app.

### 2026-06-17 — BAM (Imaginando) as DAW+visuals benchmark
- → **BENCHMARK (informs PRODUCT)** — confirms the integrated DAW+visuals core direction;
  drove the Metal bio-visual foundation (build 1867). Not a dependency.

### 2026-06-17 — Deep research: "multidimensional" positioning
- → **ADOPT→PRODUCT/POSITIONING** — MPE freed the term; Dolby/Apple own spatial/immersive.
  Logged in `decisions.csv` (2026-06-17). Drove the 5-dimension website + sub-bass/LFE.

### 2026-06 — "Claude for Creative Work" MCP connectors (Ableton/Resolume/Blender/Adobe…)
- → **PIPELINE / COMPLEMENTARY** — agent *controllers*; Echoel is the live bio *source*.
  An agent can drive Ableton/Resolume while the body (Echoel) is the input. Not embeddable in iOS.

### 2026-06 — Earlier carousel (Superpowers / Remotion / Agent Browser)
- **Remotion** → **ADOPT→PIPELINE** (promo reels on CI; `remotion-best-practices` skill installed).
- **Playwright / gstack / agent-browser** → **ADOPT→PIPELINE** (docs/site E2E + visual QA).
- **Superpowers** → **WATCH** (dev shell, minor).

---

_Update this ledger + `inspiration.csv` whenever new inspo arrives. Run the gate
before adopting anything. PRODUCT adoptions also get a `decisions.csv` row._

## 2026-06-17 — Video / Video-AI / broadcast / collab gate (founder ask + WWDC2026/382)

Founder: re-introduce the full "biofeedback meets composition/production/video cut/
visual light/performance/live broadcast/collab + realtime worldwide" vision; asks about
video capture, automatic white balance, "Video AI"; shared WWDC2026/382. Gate result —
resolve the standing Live-Broadcast oscillation (gap #1) and do NOT re-open breadth.

- **WWDC2026/382 is NOT a video session** — it's "Inside Apple Intelligence and Xcode"
  (Foundation Models, Core AI, MLX, App Intents, Xcode 27). Relevant to the AI half only.
- **Foundation Models / Core AI (on-device) → WATCH.** AI is an *enabler*, not one of the
  five dimensions. On-device+private fits the brand. Adopt into product ONLY after a real
  on-device latency/availability probe (same gate as CoreML/RAVE). No AGI/super-AI copy.
- **MLX → REJECT (in-app).** Mac/distributed; at most asset-gen pipeline.
- **Video capture + auto white balance → ROADMAP-WATCH.** Feasible (rPPG CameraCapture
  already coexists with audio via `automaticallyConfiguresApplicationAudioSession=false`),
  but it's the exact pillar that slopped. Adopt only AFTER bio-core depth and only as a
  *bio-reactive* camera (coherence-driven grade/visual), never a generic recorder clone.
- **Live broadcast (RTMP/SRT) → WATCH.** Stop oscillating: stays ROADMAP, HaishinKit is the
  sole sanctioned dep, build only after core + open-standard out-pillars are complete.
- **Realtime worldwide collab → NORTH STAR.** Physics-bounded; honest-feasible is async/loop
  or OSC/MIDI-over-LAN, not "realtime worldwide". Never product copy.

Highest-value move: NOT a new pillar. Finish bio-core *depth* — wire the just-landed
HRVCoherence + BreathPacer into the one EchoelStudioView and the existing live dimensions
(Sound/Light/Space/Vibration already consume the bus). Breadth comes one bio-reactive
pillar at a time, on the stable bus, after the core loop is visible on device.

## 2026-06-17 — Homepage optimization + Blackbox/community-platform direction

Founder: "optimize the entire homepage" (ref unitycodetechno.com — blocked 403, could
not view) + note that Blackbox App's job-placement direction is close to a planned idea,
but for Echoel it's about development/science/art/health/learning, not jobs.

- **Community/collaboration/learning platform → NORTH STAR (parked).** A people+projects+
  learning matching layer is a major pivot beyond "the instrument." Gate: build the
  instrument's traction + audience first; do not graft a platform onto the product site
  now. Most that belongs on the homepage later is a small "collaborate / learn" teaser —
  never as a shipping claim. Logged; awaiting founder go/no-go before any scope.
- **Homepage optimization = in-scope polish**, but the live site is already well-built
  (SEO/OG/structured-data/own CI/Atkinson/16 subpages, honest "concept in development").
  Not broken → "optimize" needs a direction. Reference unreachable (403); need screenshots
  or a specific focus (design refresh / copy / performance / IA / science angle).
- Opportunity now: the homepage's science angle can be strengthened HONESTLY — real
  frequency-domain HRV coherence (HRVCoherence) + a resonance breath guide just landed.

## 2026-06-21 — Spectral light-therapy science review (founder document, PMC-cited)
Founder shared a rigorous, peer-reviewed review of light→physiology (circadian ipRGC/melanopsin
~480nm; bright-light therapy; green ~525nm analgesia; red/NIR photobiomodulation via CCO; blue
antimicrobial; neonatal phototherapy) + empirical colour psychology (global colour–emotion
meta-analysis 1895–2022, Yerkes-Dodson, colour-in-context).

- **ADOPT→PRODUCT (narrow):** Use the WAVELENGTH SCIENCE + colour–emotion data to make Echoel's
  **Light (Art-Net/sACN) + Visual (SpectralColor)** output scientifically accurate, and enrich the
  **"app as a school"** tap-to-learn with cited facts. Facts + self-observation only.
- **REJECT (hard, never re-litigate):** any **therapeutic/medical claim** (treat depression,
  migraine, acne, pain, jaundice). FDA general-wellness red line + principles 3/4. Echoel is NOT a
  therapy/wellness/medical product. No "light therapy mode", no benefit promise, no dosage protocol.
- **WATCH:** circadian-aware palette (warmer/dimmer evening), strictly perceptual framing, no health claim.

Highest-value adoption: a **science-grounded light/colour engine + cited LearnLibrary entries** —
deepens the TIER-1 Light dimension with rigor, stays on the right side of the medical red line.

---

## 2026-07-02 — Deep-research relay: web STT + web bio-visuals for echoelmusic.com

External suggestion (founder relay): local STT via **Whisper-Flow** (WebSocket server),
bio-visuals via **Three.js + MediaPipe FaceMesh + Web Bluetooth**. Scored against vision +
"straight to future Apple hardware / iOS ecosystem".

- **Verdict pattern: the CAPABILITIES are on-vision; the TOOLS are the wrong platform.** The
  suggested stack is a browser/Python glue architecture that directly contradicts principle 2
  (near-zero deps, no SDK lock-in) and Echoel's on-device, no-backend identity. Every piece has
  a *native* equivalent that is already shipping or is the correct Apple path:
  - Whisper-Flow → **Apple SpeechAnalyzer / SpeechTranscriber** (iOS 26, on-device, streaming) — REJECT tool, ADOPT capability natively.
  - Three.js → **Metal / MetalBioView** already ships (TIER-1) — REJECT (redundant).
  - MediaPipe FaceMesh → **ARKit blendShapes / Vision** — WATCH (face as a later body input).
  - Web Bluetooth → **Core Bluetooth** universal 0x180D already ships (TIER-1) — REJECT (redundant).
- **Highest-value nugget: on-device SPEECH as a control/caption modality** — voice as a 6th body
  input (hands-free control, take-tagging, **live captions = accessibility win**, and spoken-word
  into the flagship **AUDIOVISUAL VOCODER**). Apple just shipped the perfect native tool; this is
  the one thing worth planning (one Ralph cycle, sequenced after the vocoder wiring).
- **Apple-ecosystem read:** Apple's on-device Apple Intelligence + SpeechAnalyzer pivot is a
  *tailwind* — "your voice and body never leave your iPhone" is now Apple's own headline. Betting
  native bets *with* Apple's roadmap (Neural Engine, visionOS spatial = the installation North Star);
  a localhost web stack fights it and undercuts the privacy narrative.
- **Website only:** a live browser demo (Three.js + Web BLE + browser STT) is the ONE legit place
  the web stack fits — PIPELINE, never Sources/. But it's heavy and risks being worse than the app;
  prefer the already-logged cheaper route (Hyperframes pre-rendered loop/video) first.

---

## 2026-07-02 — YouTube intake capability + first video

**Capability shipped (pipeline):** `scripts/analyze-youtube.py` + `.claude/skills/youtube-analyze/`
— fetch a video's metadata + transcript → score via vision-gate → log here. Robust (URL/ID
parsing self-tested, yt-dlp→oEmbed metadata fallback, modern+legacy transcript API, clean
network-block error). NETWORK NOTE: this session's policy blocks youtube.com at the proxy
(403), so live fetch needs a session/machine where YouTube is reachable; PyPI is reachable.

**First video — "Use These 17 Claude Plugins" (V2RIVnGCy74):** a Claude Code *plugin* roundup
= DEV TOOL, not the app. Verdict **ADOPT-PIPELINE (selective) / WATCH** (see
`scratchpads/inspiration/youtube-V2RIVnGCy74.md`). Echoel already runs the mature bespoke
equivalent (skills + review sub-agents + rules + markdown memory), so no wholesale install.
Only nuggets: `mcp-builder` for a tiny TestFlight/ASC-status MCP (kill the 400 KB actions_list
dumps), and the plugin/marketplace format if we ever publish our `.claude/` skills. Transcript
was blocked in-session; re-run the tool where YT is reachable to capture the exact 17 list.
