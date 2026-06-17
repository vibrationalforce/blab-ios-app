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
