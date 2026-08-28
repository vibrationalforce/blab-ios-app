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

### 2026-08-28 — Founder-Dreiklang: Raumfahrtmedizin · Psychonauten · TSMOM/„Einfalt"-Strategie

- **Raumfahrtmedizin → WATCH** (Learn-Content-Kandidat, Review 2026-11-26). Autonome/HRV-
  Forschung in Raumfahrt & Extremumgebungen ist echte, zitierbare Wissenschaft — dieselbe
  Klasse wie die bestehende Body-Science-Sektion (`BioScienceInfo`: Lehrer/Vaschillo,
  Goessl 2017). Als ZITIERTE Learn-Karte („HRV unter Extrembedingungen") on-brand;
  als POSITIONING („wie bei Astronauten") wäre es Overclaim → verboten. Gate-Bedingung
  vor Adoption: echte Paper-Verifikation (eigener Evidence-Report wie
  `REPORT_SOUND_PAIN_EVIDENCE`), aus der Sandbox nicht seriös leistbar. KEIN Health-Claim,
  nur Fakten + Selbstbeobachtung.
- **Psychonauten → REJECT (für Copy), Kern bereits ratifiziert.** Die legitime Hälfte —
  kontemplative Selbstbeobachtung, Innenreise — IST der ratifizierte Produktsatz
  („Create From Within", PRODUCT_DEFINITION). Das WORT trägt Esoterik-/Drogenkultur-
  Konnotation und kollidiert mit der mandatierten Sicherheitswarnung („NOT under the
  influence") und der FDA-General-Wellness-Linie → Brand-Rotlinie. Nie in nutzersichtbare
  Kopie; nicht re-litigieren.
- **TSMOM („time-series momentum", Moskowitz/Ooi/Pedersen 2012) + „Einfalt"-Strategie →
  WATCH mit präziser Adoptions-Bedingung** (Review 2026-10-15). Die Übersetzung auf Echoel
  ist bereits GEBAUT, einmal: #813 leitet aus der Kohärenz-HISTORIE eine vorzeichenbehaftete
  Änderungsrate ab (Momentum des Körpers, nicht sein Pegel) → Spektral-Morph. TSMOM
  generalisiert das: HR-Trend, Atemraten-Trend als weitere Modulationsquellen — „die
  RICHTUNG des Körpers spielt mit". Bedingung: ERST die Founder-Geräteprobe des
  #813-Trends (Hörbarkeit, `fullScaleRisePerSecond`-Skala = NEEDS-FOUNDER-VERIFY), DANN
  fächern — ein unverifiziertes Muster vervielfältigen wäre die Breadth-first-Falle
  (Prinzip 6). „Einfalt" gelesen als Strategie-Bestätigung: ein Instrument, eine
  Grenze (Editor ≠ Workstation), keine neue Fläche — Validierung, kein To-do.

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

---

## 2026-07-02 — Deep-research strategic synthesis (founder doc)

Mostly **validation**: the protected DSP triad, the Core-Bluetooth (not HealthKit) realtime
path, and the **deterministic bio→parameter mapping** are confirmed on-vision AND a **legal
moat** in the 2026 AI "consent crisis" (AFM v UMG/WMG; Spotify/TME synthetic-track purges; EU
AI Act 50(4)) — Echoel replicates no copyrighted training data, so it dodges the generative
"black-box" liability. That's positioning/marketing truth (echoel-marketing), not a code change.
Genuine roadmap WATCH items logged to inspiration.csv: AccessorySetupKit onboarding · C2PA/DDEX
session provenance · Cyborg-Synchrony collective audience biofeedback over OSC (North Star live
pillar) · AVAudioEngine spatial + CMHeadphoneMotionManager head-tracking. **REJECT:** the
five-tone/Jue clinical-anxiety framing (wellness/medical red line — facts may inform cited
tap-to-learn, never a therapy claim). No change to the active professionalization loop.

## 2026-07-02 — PENDING YouTube analysis (network-blocked, awaiting policy widening)
Founder shared these as inspiration; youtube.com is egress-blocked in this env (see
memory/decisions.md 2026-07-02). Once the env network policy allows youtube.com +
*.googlevideo.com, run each through youtube-analyze → vision-gate → verdict + nugget.
- https://www.youtube.com/watch?v=ovj_Gor6nSM
- https://www.youtube.com/watch?v=0UaqjKb3QHM  (from search "Software developer claude solo apple")
- https://www.youtube.com/watch?v=Ffh9OeJ7yxw  (from search "Software developer claude solo apple")
- https://www.youtube.com/watch?v=MzhIr7BfpI0
- https://youtu.be/GQGr4sXlWb0
- Playlist: https://youtube.com/playlist?list=PLRmLTbt9DLCEW7BSqwhnwFwGOw_vC9rUK

---

## 2026-07-02 — Founder legacy-doc dump (12 files) — vision-gate triage

Founder uploaded 12 old planning docs asking "ist noch was Brauchbares bei?":
Übersicht.docx (=Gibberish Master Spec), Musik_Wellness_TraumaForschung.docx,
ProjectKnowledge_Optimized/Gibberish, App_ToDo_Board, AI_README_V10_3,
Dev_Kit_v1 (+ LICENSE/TESTPLAN/Manifest/CONTRIBUTORS), Gibberish_Master.

**Verdict: mostly HISTORICAL/SUPERSEDED; a big chunk OFF-VISION (wellness/esoteric);
a handful of genuinely useful on-vision salvage items.**

### SALVAGE — on-vision, worth keeping/considering
- **TESTPLAN.md** → adopt as an rPPG QA reference: the lighting (daylight/LED warm-cold/
  low-light+torch) × motion (stable/micro/strong) × temperature (ambient/warmed) matrix +
  "freeze on low confidence / fallback values" is exactly our device-verification grid.
  ADOPT-PIPELINE (a docs/dev/RPPG_TESTPLAN.md), timely for the current rPPG hardening.
- **Ableton Link** — already CLAUDE.md-sanctioned + noted planned in PatternEngine/App;
  best concrete tech pickup for the performance-instrument vision. WATCH→build when scheduled.
- **Dolby Atmos / spatial objects** (V10.3 spatial_mixing, "Atmos bed+objects") — aligns with
  the existing ADM-OSC immersive-object direction. WATCH (future pro output).
- **Facial-expression as a bio-input** (Vision framework face landmarks) — on-vision as a
  science-based MODULATION SOURCE if framed neutrally (expression→modulation), dropping the
  "School of Smiling"/wellness framing. ADOPT-PRODUCT candidate (new bio input; not built yet).
- **Shared-coherence multiplayer** (WebRTC/LiveNet performer↔audience) — on-vision; partially
  exists (MultipeerSession). WATCH.
- **OSC / Ableton M4L companion bridge + AUM mapping presets** (Dev_Kit) — fits the open-
  standards / no-SDK-lock-in positioning. WATCH (ecosystem play).
- **Manifest.md "Science + Art, no health-claim" framing** — reinforces current brand; the doc
  itself already quarantines the spiritual layer from the evidence-based core. Reference only.
- LICENSE (MIT code + © brand/artwork) — repo ALREADY has one; no action.

### REJECT — off-vision / banned by brand guardrail (do NOT bring into the app)
Organuhr, Meridiane, Soultuning, Stammbaum-Visualisierung, KI-Trauma-Modelle, Dorn-Methode,
Kinesiologie, Reflexzonen, ätherische Öle/Cremes/Supplements, "Wellness/Therapy" positioning,
"Health & Fitness" category framing. Also superseded tech: JUCE/VST desktop, AudioKit, Android/
Web as core (iPhone-first, Swift-only, HaishinKit sole dep). The umbrella-business empire
(Gastro/Shop/Club/Consulting/Board/Glasses hardware) is founder BUSINESS vision, not app scope.

Note: the "Gibberish" files are just stylized/obfuscated duplicates of the plain docs — no new info.

### 2026-07-02 addendum — Artifacts_1.txt / Artifacts_2.txt (SYNG-era dumps)
Triaged: NO code salvage. Old "SYNG" pre-Echoel prototype — C++ UpdateSystem, Python
VisualProcessor/PerformanceManager stubs, GPL v3 repo tree, Windows build.yml — the exact
C++/CMake/desktop/GPL stack deliberately removed (Swift-only/MIT/iPhone-first now). Only
business/branding/monetization brainstorming (freemium, domains) = business-side, not app.
The in-file "TherapeuticEffects→HarmonicEffects" rename just confirms the de-medicalize direction.

### 2026-07-02 addendum 2 — Atmos/Dante batch + more BLAB code dumps
- **Ableton_Atmos_Live_Workflow / Dolby_Renderer_Config / Dante_Routing_Guide** — the ONE
  genuinely valuable find in the whole legacy dump. Pro live-production workflow: Ableton →
  Dolby Atmos Renderer (Bed 7.1.2 + N objects) → ADM BWF, Dante two-machine routing, binaural
  monitor; "BLAB/Blub receives OSC for visuals & haptics." VALIDATES Echoel's existing ADM-OSC
  output (/adm/obj/{n}/*) as the bio-reactive OBJECT SOURCE into a spatial rig — exactly the
  CLAUDE.md strategy ("bio-reactive object source for accessible immersive media"). ADOPT-PIPELINE:
  write a docs/integration guide "Echoel → Atmos/Ambisonics via ADM-OSC (+ OSC→visuals/haptics)".
  Not app code. Confirms the immersive direction is already correctly built.
- **code.txt / code_2.txt (identical), blab_blub_suite_v2.txt, Code_Bausteine.docx,
  AI_README_V10_3 (dup)** — BLAB C++ "Immersive Sound" core + BLAB/BLUB C++ starter kit +
  HTML/JS sound→light tutorial. Banned brand + discarded C++/JS stack + already-built concept.
  NO salvage.

**ARCHIVE CLOSED (~27 files triaged).** Net on-vision salvage across the ENTIRE legacy dump:
(1) Atmos/ADM integration guide [pipeline/docs], (2) per-track Kammerton/Tonart [music feature],
(3) worldwide-styles/harmony DB [genre depth], (4) Ableton Link, (5) facial-expression bio-input,
(6) shared-coherence multiplayer. Everything else = BLAB/SYNG banned brand / discarded stack /
wellness-esoteric / already-shipped. Do not deep-read further dumps — signal-scan + bucket only.

### 2026-07-08 — Ambient-Tool-Links (Void&Vista · 10K Gyro · Eraform) + Ambient-Rezept + Cousto-Attribution
- **Void & Vista (FOLDS/STRANDS/FRAMES)** — REJECT als Produktmodell (Kontakt-Sample-Libraries,
  25GB-Assets ≠ synthesis-first/zero-deps); ihre UI-als-Kunst-Messlatte = Validierung unseres
  Visual-first-Anspruchs.
- **10K Audio Gyro (ex-NI)** — WATCH/Strukturvalidierung: generative Loops + reaktive GPU-Visuals
  = unser nächster kommerzieller Verwandter, aber MAUS-gesteuert. Body-as-controller bleibt das
  Alleinstellungsmerkmal auf exakt diesem Feld. Nuggets: kuratierte Chord-Packs, Half-Time-FX.
- **Eraform Fraction** — ADOPT-PIPELINE (Pricing): One-time-Payment + wachsende Gratis-Inhalte
  bestätigt MASTERPLAN §2 wörtlich.
- **Ambient-Rezept (Founder):** Slow-Attack-Drone (3–6 s Attack, max Release) = ADOPT-PRODUCT,
  als nächster Sound-Zyklus eingeplant (reine SynthPatch-Params, dient "weicher/wärmer").
  Shimmer/Wash-Reverb + Micro-Harmonizer = WATCH (FX-Workstream; sanftes 2-Voice/7¢-Unison ist
  schon die dezente Harmonizer-Stufe). Field-Recordings/Vinyl-Beds = WATCH nur als SYNTHESE
  (noiseColor/Cellular), keine Sample-Beds (SoundscapeEngine bleibt tot), kein Wellness-Framing.
- **Cousto-Attribution (Founder: "er will erwähnt werden"):** Credit-Zeile in LightScienceInfo
  (.scope) + Visual-Panel-Caption ergänzt — science-first formuliert (Konzept-Credit, mathematisch
  exakt, "artistic convention", KEIN kosmisch/therapeutischer Claim). Rechtslage: Oktav-MATHE ist
  als Methode nicht schutzfähig, wir reproduzieren keine Cousto-TEXTE/Tabellen/Grafiken →
  keine CC-Pflicht entsteht; die Nennung ist freiwillige, korrekte Wissenschaftspraxis. Seine
  Markenbegriffe ("Kosmische Oktave" als Produktname, "Planetentöne"-Branding) NICHT als
  Feature-Namen verwenden — nur beschreibend/attributiv.

## 2026-07-09 — Rapidflow Sphere V3 (founder: "evtl als Inspiration interessant?")
- **Was es ist:** Audio-reaktiver VST-Visualizer (Desktop/DAW): splittet Audio in Frequenzbänder,
  Modifier per Drag-and-drop auf Visual-Parameter (Zoom/Displacement/Farbe/Bewegung), MIDI-CC,
  LFO-Modulation, Video-Recording. Kein iOS, kein SDK.
- **Verdict: WATCH.** Bestätigt die Kategorie (audio-reaktive immersive Visuals) — Echoel macht
  das nativ UND bio-reaktiv (unser Differenzierer). Die eine übertragbare Idee — PER-BAND-
  Reaktivität statt nur Master-Level — liegt bereits geparkt ("trackLevels → Element-Reaktivität:
  Drums/Bass/Lead getrennt", seit v10.79.118; masterLevel→Intensity ist geshippt). Nichts zu
  adoptieren außer dem geparkten Zyklus; kein Dependency-Kandidat.

## 2026-07-10 — AI-Chat "Apple-Stack DAW-Plan" + Fluid Voice (founder: "Ist da was brauchbares bei?")
- **AudioKit-Architektur-Shift — REJECT:** Die Prämisse des Chats (weg von einer Web-DAW)
  trifft uns nicht — Echoel war nie web-basiert und sitzt bereits DIREKT auf Core Audio/
  AVAudioEngine mit eigenem lock-freiem DSP-Kern (zero deps, <10 ms). AudioKit wäre ein
  Wrapper über dieselbe API: nichts gewonnen, eine Dependency verloren.
- **Empfehlungstabelle des Chats (AVFoundation/Metal/Fastlane) — CONFIRMS:** beschreibt
  wortwörtlich unseren Ist-Zustand bzw. den bestehenden Video-Plan (Stage 3–5 gegen die
  Transport-Clock). Externe Validierung, kein neuer Inhalt.
- **openDAW als Konzept-Referenz — WATCH:** ggf. UX-Referenz für Region-Editing bei K3.
- **Swift-Packages-Refactor — REJECT (jetzt):** Umbau ohne Ship-Wert mitten im Launch.
- **⭐ Multichannel-Routing (BiG SiX/Xone 96) — ADOPT-PRODUCT (Roadmap):** der eine echte
  Nugget. Stems (Drums/Synth/Bass/Master) auf getrennte Kanäle eines class-compliant
  USB-Interfaces → das Pult wird Summing-Mixer/Insert-Weg. Passt exakt zu "Sämtliche
  Hardware wird unterstützt"; Zyklus nach den One-View-K-Stufen.
- **Fluid Voice — WATCH (Pipeline):** macOS-Diktat-Tool, braucht Apple Silicon — der
  Founder-Laptop kann das nicht; iPhone-Diktat in der Claude-App erfüllt den Job heute.
  Keine Repo-Integration nötig (diktierter Text ist normaler Text).

## 2026-07-10 — AI-Chat "Killer-Prompt" (FL Studio 2026 Gopher/Transmitter, Leapfrogging)
- **Komplett-Reframe zur macOS-exklusiven Desktop-DAW — REJECT:** widerspricht iPhone-first
  (Founder-bestätigt) UND dem laufenden Launch; der Founder-Rechner könnte das Produkt nicht
  einmal bauen. Feature-Krieg gegen FL/Ableton/Reaper/Resolve ist beschieden (2026-07-09:
  Wedge = Biofeedback + Interop, nicht Parität). Der echte Leapfrog IST unserer: der Körper
  als Controller + generative Puls-Sync-Kollaboration — von keiner Audio-streamenden DAW
  kopierbar. AudioKit/SwiftPM/Fluid-Voice-Punkte: bereits am selben Tag gegated (s. o.).
- **Agentic Command Engine (CoreML/ANE-Voice-Agent) — WATCH:** Copy-Reflex auf ein
  Konkurrenz-Experiment; unser Interface ist der Körper, nicht Chat. On-device-ML-Schicht
  bleibt Tier-2 (Latenz-Prototyp zuerst).
- **⭐ Transient/Sustain-Split (vDSP) — WATCH-ROADMAP:** der brauchbare DSP-Kern. Contained
  Accelerate-Node für den EchoelFX-Workstream; EchoelBreak plant Transient-Detection ohnehin.
  Bio-moduliert (Körper → Attack-Anteil) wäre er ein Alleinstellungsmerkmal. Nach dem
  One-View-Arc.
- **Metal-Timeline (120fps) — REJECT (jetzt):** prämature Optimierung; SwiftUI trägt unsere
  Skala, Metal bleibt dem Bio-Visual vorbehalten (ein GPU-Pfad). Audio-Clock treibt
  Video-Clock = bestätigt den bestehenden Stage-3–5-Plan.

## 2026-07-12 — Founder-Share: Imaginando VS (Warning-Screenshot + 50s-Video)
- Video analysiert (8-Layer-Rail + B-Background, per-Layer-Strip ENABLED/SOLO/ALPHA/
  BRIGHT/SPEED/X/Y/RADIUS/NOISE/GLOW/MONO/GLIDE/TRIG, MIDI-Learn überall, Patch-Header,
  30-FPS-Anzeige, Record-Button; Look: Chromatic-Aberration-Ringe).
- **NEU → ADOPT-PRODUCT (klein):** Photosensitivity-Notice beim ersten Visual-Open mit
  "Show again"-Toggle (VS-Muster). Unser Vorteil bleibt: 3-Hz-Clamp VERHINDERT, VS warnt nur.
- **NEU → ALREADY-POSSIBLE:** VS ist selbst ein AUv3 → seit v175 direkt in Echoelmusic
  hostbar (Plugins-Chip); Echoel-MIDI → VS-Visuals im Plugin-Fenster. Founder-Test.
- **Design-Referenz für Layer 3 (AVObjects, Spatial v2):** die Per-Layer-Strip-Grammatik
  (Enable/Solo + Parameterzeile je visueller Ebene) ist exakt die UI-Form für unsere
  SpatialObject-visualRef-Liste — mit EchoelValueField statt Knobs (Ein-Control-Regel).
  Ergänzt den bestehenden ADOPT-ROADMAP-Eintrag (Bio→Layer-Routing), kein neues Verdict.
- Alles Übrige (9:16-Export, Video-Out, Visuals-as-Plugin) bleibt wie am 2026-07-11 gegated.

## 2026-07-12 — Founder-Share: Demo | Songwriting Studio (id1563264178) — „Können wir besser"
- Was es ist: geführter Songwriting-Bogen (Akkord-Generator + Progressionen → Rhythmus
  passt sich Akkordwechseln an → Lyrics mit Reim-Tool → Mehrspur-Gesangsaufnahme →
  Export Mix/Stems/MIDI/Chord-Sheet), iCloud-Sync + CoWrite; Demo+ 39,99 $/Jahr.
  Neuestes Feature „Suggest in Chords": einsingen → Offline-Notenerkennung (explizit
  ohne AI) → Akkordvorschläge. Rezeption gut bis auf Cloud-Sync-Ausfälle.
- **ADOPT-ROADMAP (Flow):** der geführte Bogen ist die richtige Meßlatte — Echoel hat
  Akkorde/Theorie/MIDI-Export in-house und schlägt Vorlagen mit BIO-Generativität;
  fehlend: Lyrics-Fläche + Mic-Overdub (Multitrack = bestehende Roadmap, nichts Neues).
- **⭐ Hypothese an den Founder:** sein „Word" in der EchoelBioSynth-Panel-Liste
  (Comp/Session/Transpose/Sound/FX/Mood/Synth/**Word**) könnte LYRICS/Songtext meinen —
  Demo-Share stützt das. Bestätigen lassen, bevor E4 die Panels schneidet.
- **ADOPT-ROADMAP (Hum-to-Harmony):** „Suggest in Chords" bio-first gedacht: Stimme =
  Körpersignal; hauseigene Pitch-Detection (Tools/, VocoderCore) + in-house-Theorie →
  einsummen → Akkorde, deterministisch, ohne neue Deps, ohne AI-Claim.
- **WATCH (Lehren):** Cloud-Sync-Beschwerden = Warnung für CollabSync (State klein,
  Protokoll v1 statt Dokument-Sync); Abo-für-Features bestätigt unser Modell
  (freies Instrument, Abo nur für den Live-VERBINDUNGS-Dienst).

## 2026-07-12 — Deep-Research 3-Strang (Founder-Auftrag) + Nachnennungen — KONDENSAT
- **Dreifach-Lücke bestätigt (Positionierung):** kein Bio-AUv3, keine ADM-OSC-Quelle
  auf iPhone, kein kommerzielles Bio→Visual/Licht-Tool. dearVR ist tot (Sennheiser
  2025). „Bio-reaktive Objektquelle" = unbesetzt UND bei uns schon live (ADMOSCSender).
  Claim-Regel: nur nennen was LIVE ist.
- **AUv3-Sandbox-Realität (E4):** Plugin liest kein HealthKit/BLE frei — App-als-
  Sensor-Hub via App-Group/Host-MIDI ist DAS Markt-Muster (deckt PLAN E4). Audio
  Damage „same engine everywhere" + Otoo (standalone+AUv3+Host zugleich) = Vorbilder.
- **Stärkste Feature-Übernahmen (geloggt, je eigener CSV-Eintrag):** Rubato-Zeit-
  Elastizität bio-getrieben · Ribbon/Transit-Ein-Gesten-Morph (= EchoelFX Workstream 3,
  Morph-Regler kann Bio sein) · Scaler-EQ-Idee tonart-getrackt (wir KENNEN den Key) ·
  Hum-to-Harmony (Demo) · MusiKraken-Inputs AirPods-Head/Watch-Crown (WATCH).
- **Spatial-Baurichtung bestätigt:** Hosts sind stereo → intern binaural dekodieren
  (Audio-Brewers-Muster); Isone hosten = Binaural-Vorschau vor eigenem Kern;
  Animoog Galaxy (visionOS) = Präzedenz „Stimmen als Raumobjekte" → SpatialScene-Plan.
- **Licht/Visual-Messlatte:** Fixture-Profiles + Cue-Stacks (Luminair/Blackout),
  BeatTracker+Link (Photon), Timeline-über-Engine (MadMapper 6 → Layer 7). VS-2-
  Modulations-MATRIX (nicht Node-Graph) = die mobile Routing-UX. TDLidar beweist
  „iPhone als Sensor-Peripherie großer Rigs" — exakt unsere OSC-Rolle.
- **BLE-MIDI-Befund (Founder-Frage):** MPE/MIDI2.0-Parsing + RTP-MIDI laufen; BLE-MIDI-
  Geräte erscheinen als CoreMIDI-Quelle sobald GEKOPPELT — es fehlt nur der In-App-
  Kopplungsdialog (CABTMIDICentralViewController als Panel-Inhalt, KEIN neues Sheet).

## 2026-07-12 — Deep-Research: ACE Studio 2.0 (Founder: „alles Sinnvolle übertragen, Zero Deps")
- Was es ist: Desktop-KI-Gesangs-Workstation (Timedomain, Peking; 2.0 Dez 2025,
  140+ Stimmen/8 Sprachen, Server-Render, Abo ~150-200$/Jahr). Kein Mobile, kein Realtime.
- **Übertragen (Konzepte, in-house deterministisch):** Lyrics/Phoneme ALS NOTEN-
  EIGENSCHAFT in der Roll (→ bestätigt „Word"=Lyrics für E4) · Zwei-Kurven-Pitch
  (Basis dunkel/Override weiß → VL3: erkannt vs. korrigiert; Roll: generativ vs.
  gemalt) · Per-Note-Vibrato {depth,speed} · Vocal→MIDI Note-Only (YIN-Segmentierung
  → Roll → MIDI-Export; „Singen wird Komponieren") · Atem als Ereignis — bei uns
  BIO-ECHT aus BioEventGraph statt künstlich eingefügt.
- **WATCH:** semantische Vocal-Macros (Power/Soft/Breathy/Chest über DDSP-Achsen,
  nach VL3) · ACE-Bridge/ARA-Muster (MIDI-Capture im Plugin) für EchoelBioSynth E4.
- **Bestätigt unsere Gesetze:** ihre Top-Beschwerden = Cloud-Render-Latenz + Abo-
  Dark-Patterns → on-device + Einmal-Unlock ist die exakte Gegenposition. KI-Stimm-
  Weights bleiben REJECT-UNTIL-LICENSED (ihr Voice-Donor-Royalty-Modell = einziges
  ethisches Vorbild, FALLS je relevant).

## 2026-07-13 — Founder-Video-Uploads (2 Reels, per neuem video-watch-Skill GESEHEN)
- **Reel 1 (buildwith.conrad, „Claude can't watch video → so I gave it eyes"):** Rezept
  yt-dlp → ffmpeg-Frames → Claude liest Frames als Bilder. **ADOPT-PIPELINE → GEBAUT**
  als `.claude/skills/video-watch` (Script self-tested + End-to-End auf den Uploads
  bewiesen). Local-Upload-Pfad = zero network; YouTube-URL-Pfad in dieser Session
  proxy-blockiert (403 googlevideo) → Freischalten via Environment-Network-Policy
  (youtube.com + googlevideo.com) ODER Founder lädt Datei hoch (funktioniert immer).
  Kein lokales Speech-to-Text — ohne Subs zählt nur das Bild (ehrlich ausweisen).
- **Reel 2 (sebastiankauffmann, „5 beste GitHub-Repos für Claude Code"):** Leads:
  everything-claude-code (Dev-Team R/M/S/T) · claude-mem (~Erinnerung) · last30days-skill
  (24k Stars) · Token-Reduktions-Skill (−20 %) · Design-Output-Skill. **WATCH** —
  Supply-Chain-Regel: nie Skill-Packs aus Videos auto-installieren; wir fahren bereits
  memory/ + decisions.csv + Reviewer-Fleet (deckt claude-mem/Dev-Team-Kern ab).
  Einzeln vision-gaten, wenn der Founder eines konkret will.

## 2026-07-13 — FL Studio Mobile (Founder-Video + Deep-Research, 56 Agenten, adversarisch verifiziert)
Founder: „schau dir per Deep Research alle EFx und Instrumente an und lass dich inspirieren"
(Echoel bleibt Profi-Level, aber das leichte Handling ist attraktiv). Video Frame-für-Frame
gesehen + Research gegen Image-Line-Manual verifiziert.

**Kern-Erkenntnis:** FLs „leichtes Handling" = EINE Idee — man kann keinen falschen Ton spielen.

- **ADOPT-PRODUCT · Scale-Lock + Root-Wahl** (verifiziert, Image-Line Module_Note_Scale):
  12 Notenschalter C–B (snap/filter), one-tap „Scales"-Preset, „Key"=Grundton A–G. Echoel
  hat Key/Scale/Kammerton schon in-house → billig; wrong-note-free schnelles Live-Spiel,
  on-vision. **Höchster-Hebel-Adopt.** (Kammerton=A440 bleibt separat vom Grundton.)
- **ADOPT-PRODUCT · Single-Knob-Morph** (verifiziert, MiniSynth-Manual): ein Modifier-Regler
  morpht Wellenform-Charakter (Saw+Square-Pulsweite) statt vieler Osc-Params → passt exakt
  zu EchoelValueField; ein Charakter/Morph-Knopf für PolySynthVoice.
- **WATCH · Chord-/Strum-Pads pro Skalenstufe** (im Mobile-Video sichtbar; note→chord nur für
  Desktop-FL/VFX-Key-Mapper verifiziert, 2-1). Adopt-fähig NACH Scale-Lock (gleiche Theorie).
- **REJECT · GMSynth/SoundFont** (GM/Consumer-Klang, gegen Profi-/Bio-Identität) · IAA/Audiobus
  (veraltet, wir sind AUv3-Host). Transistor-Bass/Slicer ≈ SubBassVoice+LoopCutter (schon da).
- **Offene Lücke:** Voll-Roster aller FX + Instrumente NICHT unabhängig verifiziert (nur
  MiniSynth + Scale-Modul primärbelegt). Bei Bedarf zweite Research-Runde gezielt auf FX-Liste.

**Roadmap-Einordnung:** Scale-Lock + Morph-Knopf = Prio-Zyklen NACH dem laufenden AUv3-Block
(Founder-bestätigt „AUv3-Struktur JETZT"). Nicht vorgezogen ohne Founder-Ask — nicht verfransen.

### FL Mobile Voll-Roster (Lücke geschlossen, WebSearch Image-Line-Manual 2026-07-13)
**Instrumente (aus Video-Menü):** MiniSynth · DW Sampler (DirectWave-Stil) · GMSynth ·
Transistor Bass (TB-303) · SuperSaw · Slicer · 3x Osc · SoundFont Player · Drum-Kits.
**Effekte (~32 Module, Image-Line-Manual):** Analyzer · Autoduck · Pitcher/Pitcher 2 ·
Chorus · Comb Filter · Compressor · Multiband Compressor · Distortion · Waveshaper ·
Parametric EQ · Graphic EQ · Tuned EQ · Filter · Flanger · Phaser · Tremolo · Gate ·
Leveller · Limiter · Multi FX · Reverb · Reverb 2 · Spacer · Spreader · Stereoizer ·
Tape Delay · Trance Delay · Tape Stop · Tuner · Wow & Flutter · Note Effects (inkl. Scale).
**Echoel-Gap:** EchoelFX hat Bitcrush/Widener/Reverb — es fehlen für Profi-Level: EQ
(parametrisch/grafisch), Kompressor + Multiband + Limiter (deckt sich mit Mastering-Plan
M2/M3), echtes Delay (Tape/Trance), Modulation (Chorus/Flanger/Phaser/Tremolo), Gate/
Autoduck, Distortion/Waveshaper. = eigener FX-Ausbau-Block (nach AUv3 + Scale-Lock).

## 2026-07-14 — Founder 5 reference reels (video-watch → vision-gate)

Founder mandate: "integriere alles was uns wirklich hilft und unsere Arbeit
effektiver macht" + "Natürlich auch alles was kreativ und technisch wertvoll ist."

- **ADOPT→PRODUCT — On-device generative "Idea-Maze" composer.** From @jakebeau_'s
  agentic PLAN→ACT→OBSERVE→REFLECT loop + local brain + idea-maze/leaderboard
  (Anthropic "Effective harnesses for long-running agents"). Echoel reinterpretation:
  the bio-generative engine proposes N musical variations, **scores them by
  bio-fit/coherence**, keeps a ranked leaderboard, the musician picks. Passes all
  four gates — Sound (Tier-1 differentiator), iOS-feasible (BioComposer already
  deterministic/seeded; MVP needs NO LLM), on-brand (body curates the ideas;
  seed-recall is our edge), realtime-safe as a control-plane core. **Cheapest first
  step (this Ralph cycle): a pure, tested `BioVariationMaze` core** — seed + bio
  snapshot → N deterministic variation seeds → bio-fit score → ranked leaderboard;
  Foundation-only, flag-gated OFF, zero audio-thread/UI. Later: LLM-assisted
  proposals via the existing EchoelAI brain; a Touch surface to audition the maze.
- **WATCH — offline voice/singing (HeyGem/OmniVoice).** Reinforces the EXISTING
  Tier-2 flagship AUDIOVISUAL VOCODER (VocoderCore built, wiring next) — accelerate
  that, don't start a parallel voice system. Person voice/face-CLONE specifically =
  REJECT (deepfake identity, off-brand, not bio-driven).
- **ADOPT→PIPELINE — "offline/on-device/free/no-subscription" positioning** + the
  **carousel-reel format**: both go to `echoel-marketing` (validated hook + launch/ASO
  playbook; our green-on-black CI already matches). Never in-app.
- **REJECT — Fincept Bloomberg-clone / HyperFrames code→video / Jarvis agent-app /
  auto-content-farm.** Off-vision; building any is the breadth-first scope-creep the
  constitution warns against (principle 6). EchoelAI stays an assistant behind a flag.

**Single highest-value adoption:** the on-device bio-curated Idea-Maze composer
(ADOPT→PRODUCT). Building the pure core now.

### 2026-07-16 — IG-Reel alan.buildz „Claude ist jetzt dein Kreativstudio" (5 Claude-Tools, Founder-Upload .mp4)
Analysiert via watch-clip (37 s, Contact-Sheet + Frames). Alles PIPELINE-Kandidaten,
nichts für Sources/. Abgleich mit bestehenden Verdikten (kein Re-Litigieren):
- **HyperFrames (heygen) „Claude = dein Video-Editor"** → bleibt **REJECT** (bereits
  gescort: code→video Scope-Creep; zudem externe Cloud — Founder-Media verließe die Maschine).
- **Voicebox (jamiepine; 3-Sek-Voice-Clone + On-Device-Whisper-Diktat)** → Clone-Teil
  fällt unters bestehende Deepfake/Voice-Clone-**REJECT** (nie in-app, nicht bio-getrieben).
  On-Device-Diktat = persönliches Founder-Produktivitäts-Tool, keine Repo-Sache.
- **competitive-ads-extractor** (awesome-claude-skills) → **WATCH→PIPELINE**: erst relevant,
  wenn Echoel Paid/ASO-Konkurrenzanalyse fährt (Launch-Phase); dann als Ergänzung zum
  vendorierten Marketing-Pack prüfen. Kein Adopt jetzt (wir schalten keine Ads).
- **last30days-skill** (Nischen-Recherche letzte 30 Tage) → **WATCH**: redundant zum
  vorhandenen deep-research-Harness; nur übernehmen, falls dessen Recency-Sweeps zu teuer sind.
- **Voice DNA (Claude schreibt im eigenen Stil)** → **WATCH→PIPELINE**: die Idee (Stil-Profil
  aus eigenen Texten) ist für echoel-marketing-Copy nützlich; unsere Brand-Guardrails
  existieren schon — ggf. ein Founder-Stil-Absatz in echoel-marketing statt neuem Skill.
- **Format-Takeaway (das eigentlich Wertvolle):** das Reel selbst — schneller Schnitt,
  nummerierte Tool-Liste, Caption-Overlays, „Kommentiere X und ich schicke dir die Liste"
  als Lead-Hook — ist ein validiertes Muster für #52 (Echoel-Reels). → echoel-marketing.
**Kein App-Code-Impact. Höchster Wert: Reel-FORMAT für #52.**

### 2026-07-16 — YouTube-Vortrag Schmedding „KI Second Brains scheitern" (Founder-Upload, JSON-Summary)
Vision-Gate: trifft REPO-GEDÄCHTNIS + FOUNDER, nicht die App.
- **Validierung (kein Handlungsbedarf):** Sein Layer-5-Mapping empfiehlt für Coding-Agents
  wörtlich „LLM Knowledge Base, Bash/Grep-Navigation im Repo" = unser memory/+scratchpads/
  +CLAUDE.md-System; „Decision Logbook" = unsere decisions.csv. Sein Anti-Markdown-Verdikt
  zielt auf Enterprise-OPS, nicht auf Agent-Repos. EchoelAI N0-N4 (Registry+Tools statt
  Generic-RAG) = sein „use-case-specific pipelines"-Prinzip.
- **ADOPT-PIPELINE (billig, real): systematisches Vergessen.** Collector's-Fallacy trifft
  uns: ~65 PLAN_*-Dateien, viele supersedet → Attention-Verschmutzung. Hygiene-Zyklus:
  supersedete Scratchpads nach scratchpads/archive/ (Session-Start lädt nur Lebendes).
- **ADOPT-RITUAL (der schärfste Punkt): „Der Mann des Buches" = der Founder.** Ungeschriebenes
  Jahres-Wissen (EEG-Beispiel heute) ist der einzige echte SPOF. Ritual: jede erinnerte
  Alt-Planung sofort einwerfen → wird in Tasks + memory/ verankert (Tacit-Knowledge-Capture).
- **REJECT:** „Company Brain" als Produkt-Pivot — off-vision, Scope-Creep. Echoel bleibt Instrument.

### 2026-07-31 — DSPy (Founder-Einwurf: ein Wort, ohne Kontext)
Vision-Gate. **Schon bewertet** — `inspiration.csv:132` (2026-07-10) hat DSPy als einen von
zwölf Posten einer LLM/RAG-Stack-Liste mit REJECT geschlossen. Der Founder fragt es jetzt
EINZELN, also bekommt es eine eigene Zeile statt eines Verweises auf eine Sammelablehnung.

- **Tier: REJECT als Abhängigkeit · ALREADY-ADOPTED als Konzept.** Am Vier-Punkte-Tor
  scheitert es sofort an Punkt 2 (iOS-nativ auf dem iPhone machbar): DSPy ist Python,
  `Package.swift` hat `dependencies: []`, Prinzip 2 der Verfassung ist „open standards,
  near-zero dependencies". Das ist keine Geschmacksfrage.
- **Und der Pipeline-Ausweg trägt hier ausnahmsweise auch nicht** — was er sonst fast immer
  tut. Zwei harte Gründe: (a) ein Optimierer optimiert gegen ein Modell, das er ANSTEUERN
  kann; Apples On-Device-Foundation-Model ist aus Python nicht ansteuerbar, und gegen ein
  Cloud-Modell kompilierte Instruktionen auf ein ~3B-Gerätemodell zu übertragen ist
  unbelegbar. (b) DSPys ganzer Wert hängt an einer METRIK. Echoels tatsächliche Messlatte
  ist „klingt professionell" / „wow" — die Metrik ist das Ohr des Founders. Ohne Metrik ist
  ein Prompt-Optimierer nur ein langsamerer Prompt.
- **Das Konzept läuft längst, in Swift.** `ParameterDescriptor` (keyPath · Anzeigename ·
  min/max · Einheit · Wertelabels) IST eine typisierte Signatur; `ParameterToolCore` ist die
  modellfreie Werkzeuglogik getrennt vom Modell; das ADR-Gesetz „das Modell schreibt NIE
  direkt DSP-State" ist strenger als alles, was DSPy erzwingt. Die Trennung
  Programm-Struktur ↔ Prompt-Text war die eigentliche Idee, und sie ist adoptiert.
- **⛔ KORREKTUR AN DER ALTEN BEGRÜNDUNG (Zeile 132), und sie ist der Grund, warum dieser
  Eintrag nicht bloss ein Verweis ist.** Dort stand: *„Echoel ist ein Zero-Dep-iPhone-
  Instrument OHNE Server/LLM-Feature"*. Die erste Hälfte gilt unverändert. Die zweite wurde
  **zwei Tage später falsch**: am 2026-07-12 landete EchoelAI N0–N4 (Registry + BrainBackend/
  FoundationModelsBrain + ParameterToolCore). Das Urteil bleibt richtig, eine seiner beiden
  Begründungen nicht — genau das Muster, das dieses Repo „Mechanismus richtig, Begründung
  falsch" nennt. Nachgeprüft: `Sources/Echoelmusic/EchoelAI/` hat **null Produktions-
  Aufrufer** ausserhalb sich selbst, `FeatureFlags.echoelAI` ist default AUS, und
  `ParameterApplyRouter` hat keine gebundene Apply-Closure vom Modell her. Das LLM-Feature
  ist Gerüst, nicht Funktion — deshalb ändert es am Urteil nichts.
- **⭐ DER EINE ÜBERTRAGBARE GEDANKE, und er ist heute schon terminiert: BAU ZUERST DIE
  METRIK.** DSPys Lehre ist nicht der Optimierer, sondern dass ohne messbares Ziel gar nicht
  erst optimiert werden kann. Echoel hat genau eine Stelle, an der eine echte Metrik
  ansteht und mit ZERO Deps baubar ist: **#313 Slice 2** (BS.1770-Messbank über
  `EchoelLoudnessMeter` statt der Fünf-Skalar-Heuristik) — war blockiert hinter **#316** (die
  LUFS-Anzeige maß vor der Master-Kette, das Messgerät war selbst falsch). **ENTBLOCKT am
  2026-08-01 durch #316b**: der R128-Tap sitzt auf `AutoMixChain.chainOutputNode`, die vier
  Werte tragen den −1-dB-Trim zurück. Die Reihenfolge hat gehalten; die Sperre ist weg.
  Kein neuer Task, keine neue Abhängigkeit.
**Kein App-Code-Impact. Kein neuer Task. Höchster Wert war: #316 vor #313 — erledigt.**

## 2026-08-15 — herdr (github.com/herdrdev/herdr) — Founder: „Installieren?"
**Tier: WATCH (Founder-Workstation-Tooling, kein Echoel-Task).** Rust-Terminal-Runtime für
Coding-Agents (tmux-artig: Background-Server, Sessions überleben Deckel-zu/Neustart, Panes
mit working/blocked/idle-Status, Socket-API, Claude Code/Codex/Cursor als Gäste; Apache-2.0,
ein Binary, kein Electron). Nachgelesen im Shallow-Clone, nicht nur im README-Marketing.
- **Für DIESE Session-Infrastruktur: nutzlos.** Die 24h-Mandat-Sessions laufen remote
  (claude.ai/code, Container ephemer, Cron weckt) — Persistenz liefert die Plattform, ein
  lokaler Terminal-Server im Container stürbe mit ihm.
- **Für den Founder-Mac: sein Call, kein Repo-Belang.** Sinnvoll ERST, wenn mehrere LOKALE
  Agents in Terminals laufen sollen (der interessante Fall wäre ein lokaler Mac mit Xcode
  für Device-Builds — das wäre aber eine Infrastruktur-Entscheidung, nicht diese Zeile).
  Installation dann via `brew install herdr` (Homebrew-Formel existiert; dem
  `curl | sh`-Installer vorziehen).
- **App/Pipeline-Impact: null.** Keine Code-Abhängigkeit (Zero-Dep-Gesetz unberührt),
  berührt nie `Sources/`, auch nicht ContentPipeline.
**Kein App-Code-Impact. Kein neuer Task.**

## 2026-08-27 — IG-Reel @getintoai: „10 prompts … code with Claude" (Founder-Clip, ohne Text)
14,7-s-Screen-Recording eines Instagram-Carousels: zehn Persona-Prompts („Act as a senior
security engineer…", Tech-Lead-Modus, DevOps usw.). Gegen die Pipeline gescort, nicht gegen
das Produkt (der Clip handelt vom ENTWICKELN, nicht von Bio/Sound/Space).
- **REJECT (redundant), Zeile in inspiration.csv.** Jeder der zehn Prompts existiert hier
  als stärkeres, repo-spezifisches Werkzeug: Team-Fan-out mit Leads (ultracode-teams) statt
  einer Persona, spezialisierte Reviewer-Agents (audio-thread/security/ui-state/concurrency)
  statt „act as senior X", the-council als echter Tech-Lead-Modus (Sitze + Dissens),
  device-log-triage statt „production debugger", doctor/e2e-test-agent statt DevOps-Prompt.
  Der eigentliche Unterschied ist die MESS-Disziplin: Wächter + Python-Transkription + ehrliche
  Gate-Lesung — genau das, was generische Persona-Prompts nicht haben.
- Nr. 5 („rebuild messy code into clean architecture") widerspricht sogar `engineering.md`
  (kein unbeauftragtes Refactoring) — als Arbeitsanweisung hier verboten, nicht nur unnötig.
**Kein App-Code-Impact. Kein neuer Task.**
