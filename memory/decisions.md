# Decisions Log

Architectural and strategic decisions with context and rationale.

---

### 2026-07-18 #23 per-Lane-SynthPatch: staged, persist-first (Council)
- **Founder-Quelle #23:** jede MIDI-Spur trägt ihre eigene optionale `SynthPatch` —
  per-Instrument-Klangfarbe pro Spur, wie in einem echten DAW.
- **Befund (investigiert):** der Kern ist SCHON DA — `TimelineLane.patch` persistiert
  (Codable), Sekundär-Lanes wenden `lane.patch` bei Region-Load an
  (`MultiRollFanout.patch → slotPatchSink → LaneVoiceRack.applyPatch`). Die EINE Lücke:
  die `.patch`-Editor-Tür (`ArrangeTimelineView:428`) öffnet `PatchEditorView(initial:
  synth.appliedPatch)` OHNE `onApply` → editiert die GLOBALE geteilte `PolySynthVoice`,
  nie `lane.patch`. Und die Primär-Roll-Lane == globale Stimme (kein persistierter
  per-Lane-Patch).
- **Council:** **stage it — persist first (Linux-CI-testbar), Live-Preview-auf-der-
  richtigen-Stimme später (geräteabhängig).** Slices: **S1** `TimelineStore.setLanePatch`
  + Tests (pur, 0 Geräterisiko, Pitch-Familie-Spine) → **S2** `.patch(lane)`
  Modal-Payload an bestehendem Case (KEINE neue `.sheet`) + persist via `onApply` →
  **S2b** Primär-Lane-Patch-Anwendung bei Play/Load → **S3** (GERÄTE-GATED) lane-bewusstes
  Live-Apply-Ziel. Golden-Gate: globaler Editor byte-identisch wenn keine Lane übergeben.
- **Gate: proceed** — PLAN geschrieben (`scratchpads/PLAN_PER_LANE_PATCH.md`), nächster
  Takt baut S1. **Verify:** zwei MIDI-Spuren, je eine andere Klangfarbe, beide beim Play
  hörbar unterschiedlich (heute klingen alle gleich) — Gerät-Hörtest = Closeout.

### 2026-07-17 ECC-MUSTER adoptiert, kein Paket-Import (Baustellen-Board + Verify-Loop)
- **Founder (Reel „Everything Claude Code", bennyautomates):** „Hiermit können wir die
  ganzen offenen Baustellen strukturieren und erfolgreich abschließen."
- **Befund:** ECC = github.com/affaan-m/everything-claude-code (Affaan Mustafa, MIT,
  228k Stars): 67 Agents · 278 Skills · 94 Commands · Hooks · Instinct/Memory ·
  AgentShield. Wertvoller Kern für uns: **Verification-Loop** (nichts ist fertig ohne
  definierten Verify-Weg) + **Board-Orchestrierung** + Continuous-Learning (= unser
  HARNESS_LEDGER, existiert schon).
- **Council:** Wholesale-Import würde die Echoel-getunte Harness (Council, Triage-
  Skills, 15 Reviewer-Agents, memory/, Ledger) duplizieren und die harten Gesetze mit
  278 generischen (web/SaaS-lastigen) Skills verwässern; Plugin-Install ist zudem eine
  User-Level-Aktion. Der echte Founder-Schmerz: 20+ Baustellen ohne EINE Übersicht.
- **Executed:** `scratchpads/BAUSTELLEN_BOARD.md` (AKTIV ≤6 · OFFEN · BLOCKIERT ·
  ERLEDIGT — jede Zeile mit Founder-Quelle, nächster Slice und **Verify-Weg**) +
  `.claude/skills/baustellen/SKILL.md` (Closeout-Loop: Board → Slice → Gates → Deploy
  → Verify-Spalte → Ledger). Gesetz: **keine Baustelle schließt ohne Founder-Verify.**
- **Offen gelassen:** selektiver ECC-Import (`npx ecc consult`) nur per Founder-Entscheid.

### 2026-07-10B GESCHÄFTSMODELL v2 + LAUNCH JETZT (supersedet das Einmal-Pro vom selben Vormittag)
- **Founder-Vorschlag (verbatim-Kern):** "Vielleicht ist das was man mit Pro freischaltet
  ein Jahresabo für weltweites Live musizieren und Biofeedback Sessions ansonsten hat man
  als free User vollen Zugriff… Host fee pro Veranstaltung. Die Konzerte kosten für
  Zuschauerinnen nichts (YouTube, Insta, TikTok)… das Instrument war bisher perfekt bevor
  es zu kompliziert wird erstmal launchen."
- **Drei bestätigte Entscheide (AskUserQuestion):** (1) Alles frei + Live-Abo,
  (2) sofort launchen — Live in v1.1, (3) Preisrahmen 29,99 €/Jahr + Host-Fee 9,99 €/Event.
- **Council-Einordnung:** Ein Abo für den laufenden VERBINDUNGS-Dienst widerspricht dem
  "kein Abo"-Beschluss NICHT — der galt dem Instrument. SharePlay (FaceTime, bis 32,
  E2E) = Apples kostenlose Realtime-Infrastruktur → das Abo hat fast keine Serverkosten.
- **Der strategische Durchbruch (hebt die alte North-Star-Einordnung auf):** Weltweites
  Live-Musizieren ist für Echoel PHYSIK-EHRLICH machbar, weil wir generativ sind — wir
  syncen **Puls + Partitur (Kontrolldaten, taktquantisiert — NINJAM-Prinzip), nicht
  Audio**; beide Geräte rendern lokal dieselbe Musik. "Wir streamen nicht Audio, wir
  streamen den Puls." Kein Audio-streamender Wettbewerber kann das kopieren.
- **Executed:** Pro-Chip + Unlock-Sheet aus WorkspaceView ENTFERNT (v1.0 zeigt keine
  Kauf-UI). ProGate/EchoelStore/ProUnlockView bleiben compiling, unpresented — werden in
  v1.1 auf das auto-renewable "Echoel Live" umgewidmet (nicht löschen, nicht vorher zeigen).
- **Roadmap:** v1.0 freies Instrument JETZT → v1.1 Echoel Live (SharePlay-Sessions,
  Jahresabo) → v1.2 Broadcast (P4 RTMP) + Host-Fee + Cause-Events (Partner-Modell
  United We Stream; kein eigener Server — der bleibt gestrichen).
- **ASC-To-do geändert:** KEIN non-consumable mehr anlegen; stattdessen (zu v1.1) das
  Auto-renewable-Abo "Echoel Live".

### 2026-07-10 ECOSYSTEM: Einkommen zuerst · serverlos ohne Login · Gemeinsam ehrlich (Plan E1–E7)
- **Founder-Auftrag (verbatim-Kette):** "Echoelmusic langfristig auf stabiles Einkommen,
  Producer, Health, Accessibility zu trainieren" + Apple Login / Wetterdaten (geringes
  Kontingent) → Visuals & Kompositions-Parameter / Standort → private Session-Namen /
  Push für Features & Online-Events / weltweit gemeinsam realtime musizieren /
  "biofeedback gemeinsam verbinden für mehr Kohärenz".
- **Drei bestätigte Gabelungen (AskUserQuestion):**
  1. **Serverlos ohne Login** — der Job hinter "Login+Push" ist Retention/Events;
     CloudKit-Public-DB + `CKQuerySubscription` = Broadcast-Push an ALLE Geräte ohne
     Konto, Server oder laufende Kosten. Sign-in-with-Apple NUR falls später echte
     Community-Profile kommen. Die dokumentierte Keine-Konten-Privacy bleibt wahr
     (präzisieren zu: "kein Konto — Push über iCloud").
  2. **Echoel Pro gated NUR Erweiterungen** — EIN non-consumable
     `com.echoelmusic.app.pro` (14,99–19,99 €). Frei für immer (hart codiert in
     `ProGate.alwaysFree`): Bio-Messung, Klangerzeugung, Sicherheit, Accessibility.
     Pro: Export-Format-Presets, AUv3, erweiterte Preset-Packs, Video-FX. Die toten
     Abo-IDs (monthly/yearly) sind ENTFERNT — sie widersprachen dem Beschluss
     2026-07-06 "kein Abo". Unlock-View-Copy ist ehrlich: unshipped = "in development".
  3. **Einkommen zuerst** — E1 Pro-Flow vor Ort/Wetter/Push/Gemeinsam.
- **Gemeinsam-Kohärenz aufgelöst gegen 2026-06-20** (nie Cross-Person-Readout):
  verbunden musizieren JA — aber jeder sieht die EIGENE Zahl, nebeneinander
  (`LiveColaboView`, Multipeer, ColabPayload kind "bio"). KEIN Gruppen-Sync-Score.
  Weltweit-Realtime-Jam = NORTH STAR (Physik >50 ms + Server) — nie in Produkt-Copy;
  Stufen: Multipeer-Tempo-Sync → LinkKit (Founder-Ok nötig, Lizenz frei) → North Star.
- **Umwelt = zweite physikalische Realität** (Masterplan §1 Vision-Fit JA): E2 Ort in
  Session-Namen (whenInUse, Toggle default OFF, on-device), E3 WeatherKit 1 Fetch/Session
  → BioComposer-Seeds + Visual-Palette, Apple-Attribution Pflicht, offline stiller Fallback.
- **Executed heute:** ProGate + EchoelStore-Umbau + ProUnlockView + Pro-Chip im
  WorkspaceView-Header (E1a–c). Founder-To-do: Produkt in App Store Connect anlegen.
- **Plan:** Session-Plan-File (E1–E7) · Guardrails: kein Server, kein Login, kein Abo,
  kein Cross-Person-Score, keine Wellness-Copy, Entitlements nur die vier genannten.

### 2026-07-06B RE-FOCUS (supersedes the same-day shell flip): NO breathing exercise — the product is bio-generative music performance
- **Founder trigger (verbatim, after testing the Session-as-home build):** "nein die Leute
  brauchen gar keine Atemübung. Es geht bei der App um eine Performance und
  Entspannungssteigerung dadurch, dass sich die Musik mit dem Biofeedback generativ verändert
  und dadurch ein kontemplativerer Zustand entsteht. Die Musik soll dementsprechend organisch
  und professionell klingen. Bisher haben wir da noch viel Luft nach oben und die visuals sind
  auch noch nicht ganz angekommen."
- **What this supersedes:** the 2026-07-06A "Session IS the app" shell flip (and that part of
  the strategy synthesis). The AUDIT's structural findings remain valid (god-view fragility,
  dead code, re-seed churn); the MARKET findings remain valid (one-time unlock, first-run is
  everything, no medical claims). Only the PRODUCT FORM conclusion changed: not a breathing
  app — a bio-generative music instrument whose quality bar is organic/professional sound +
  visuals that are part of the experience.
- **Executed (v10.79.79):** (1) instrument = home again (WorkspaceView restored; Session stack
  stays in code, compiling, UNPRESENTED — do not re-add without founder ask, do not delete
  either: it holds the tested flash-safety/latency/pacing laws); (2) drum re-seeds now stage
  at the loop boundary (PatternEngine.loadAtBoundary) so evolve/lock re-seeds land melody+drums
  together on the downbeat — the audible mid-bar chop is gone; (3) Start stages the immersive
  visual fullscreen (Stop restores, user mid-take choice wins).
- **Standing quality bar (founder):** organic, professional generative music; visuals as part
  of the experience; wow in the first 10 seconds. Improvements go INTO the instrument, not
  into new surfaces.

---

### 2026-07-06 STRATEGIC SYNTHESIS: "optimal form" = the Session IS the app (two adversarial research streams)
- **Founder trigger:** "Der durchgehende ton soll komplett entfernt werden [erledigt]. Ansonsten
  Deep Audit und Deep Marketing Research... Was ist Echoelmusic in optimaler Form? Wie generiere ich
  langfristig solides Einkommen und wie muss sie dafür aufgebaut sein? Ich bin mit der Qualität nicht
  zufrieden." Full synthesis: `scratchpads/STRATEGY_OPTIMAL_FORM_2026-07-06.md`.
- **Two verified research streams converged on ONE conclusion — ship ONE excellent thing:**
  - **Code/UX audit:** root quality problem = the shell is inverted vs. the approved pivot. App still
    boots into the 2,756-LOC `EchoelStudioView` god-view (89 state, ~20 sheets = black-screen/freeze
    source); the calm `SessionView` is a hidden fullScreenCover. "Holprig" sound is structural
    (generative composer re-seeds on noisy pulse — calm can't emerge from a restless engine; the steady
    `SessionEngine` path exists but is hidden). ~5,000 LOC safely removable (5 unreachable DAW views +
    domain, dead RTMP, BioModulation/CloudSync 0-refs, DUPLICATE `MeditationView` that already has the
    summary/history SessionView lacks).
  - **Market research (107 agents, 18 confirmed / 7 refuted):** consumer wellness market is brutal to
    monetize (Calm ~2.5% conversion ceiling); abo churn near-irreversible (95% never return → only lever
    = first-month retention). rPPG reliably reads only avg HR, not individual HRV/"coherence" — BUT
    contact fingertip PPG (Echoel's modality) is materially more accurate than facial rPPG → valid as a
    self-observation/guidance tool, NOT a measurement-grade differentiator. US regulatory OK for
    on-device no-diagnosis self-observation (FDA general-wellness discretion). **EU LAW (GDPR/MDR/DiGA)
    NOT researched — real gap, founder in Hamburg, must clear before health marketing.**
- **Recommendation (my rational/critical view, pending founder go on scope):**
  1. **Flip the shell — Session = home, Studio behind ONE deliberate door** (audit #1, already covered by
     the 2026-07-02 warm-restart mandate; reversible). This realizes the pivot decided-but-never-shipped.
  2. **Pricing = one-time Pro unlock + generous free tier, NOT subscription** — a solo dev can't win the
     abo-churn treadmill; one-time has no churn, preserves win-back optionality, matches privacy-first.
     Fix `EchoelStore` (subscription IDs contradict this).
  3. **Positioning = self-observation + breath pacing, NEVER "accurate HRV/coherence measurement"** —
     protects trust AND stays out of the regulatory zone.
  4. **Long-term moat = the OSC/ADM-OSC/Art-Net immersive layer** (installation/artist/venue niche pays,
     less saturated) — Phase 2, after the consumer core is genuinely good.
- **Status:** analysis delivered to founder; shell-flip execution offered as the immediate next cycle,
  awaiting founder green-light on scope + pricing direction. Tone-removal shipped v10.79.77 (CI green).

---

### 2026-07-02 STRATEGIC PIVOT: refocus to a calm shell (reduce surface, keep engine)
- **Founder trigger:** "Ich empfinde die ganze App als eine sehr komplexe nicht richtig
  funktionierende und irritierende Umgebung." Proposed drastically reducing to: (1) a
  biofeedback session experience with beautiful music + visuals, (2) render tight audio
  loops, (3) social-media short videos.
- **Council + founder chose 1A + 2A:**
  - **1A — refocus, keep the engine (reversible).** Reduce the *surface*, not the *engine*.
    The DSP/EngineBus/rPPG/generative music work and are the good part; the pain is the maze
    (6 tabs + a Tools menu of ~10 sheets). Move DAW complexity behind ONE "Studio" door;
    delete nothing yet — prune later from evidence (what the founder never opens). NOT a
    hard delete (irreversible) and NOT a greenfield rewrite (riskiest).
  - **2A — wording stays science-first.** The *experience* may be calm/meditative, but the
    WORD "meditation"/wellness stays out (keeps the codified "instrument, NOT wellness" brand
    rule intact). Founder explicitly kept this rule.
- **Executed (v10.79.22):** bottom bar reduced 6 → **Bio · Compose · Studio**; advanced
  surfaces (Arrange/Clips/Mix/Browse) behind a single `StudioDoorView` sheet; default surface
  flipped to Compose (instrument = home). Supersedes the earlier same-day "keep Arrange
  default" decision.
- **Next steps (planned, `scratchpads/PLAN_REFOCUS_CALM_SHELL.md`):** unify Compose's internal
  Picker so generate+visual+play is the default; make "render loop" a clear action; finish the
  deferred **short-video export** (the one genuinely new build); then prune hard from evidence.
- **Also true right now:** the founder is still testing the OLD 79.7 build (log shows
  `generate: 6 notes`) — part of the "half-working/irritating" feeling is an outdated build.
  He must UPDATE TestFlight to judge the real current state.
- **Review:** 2026-08-02.

---

### 2026-07-02 ENVIRONMENT CONSTRAINT: YouTube is blocked in the web sandbox (capability exists, network doesn't)
- **Fact to remember (founder: "merke dir das"):** The `youtube-analyze` capability EXISTS
  (skill + `scripts/analyze-youtube.py` + vision-gate routing). It does NOT work in the
  Claude-Code-on-web remote environment because THIS session's **network policy blocks
  `youtube.com` at the egress gateway** — a hard `403 CONNECT` policy denial (confirmed via
  `curl http://127.0.0.1:46751/__agentproxy/status` → `www.youtube.com:443 connect_rejected`).
  `WebFetch` on a YouTube URL also returns 403; `WebSearch` cannot resolve a video by its
  bare ID (only by title/topic). Same policy blocks context7, perplexity, firecrawl MCP.
- **Do NOT:** retry, pretend to have watched the video, or route around the block via
  third-party mirrors (invidious/piped) — the proxy README explicitly forbids routing around
  an org policy denial.
- **To actually enable YouTube analysis, ONE of:** (a) the founder changes the environment's
  **network policy to allow `youtube.com` (+ `googlevideo.com` for transcripts)** — see
  code.claude.com/docs/en/claude-code-on-the-web (network policy is chosen when the env is
  created); (b) the founder pastes the transcript/title text and I analyze that; (c) run the
  skill in a local/session where YouTube is reachable.
- **When the founder shares a YouTube link here:** state honestly it's network-blocked in this
  env, offer the three unblock paths, and ask for a one-line takeaway if he wants it acted on
  now. Don't silently drop it; don't fake analysis.
- **Review:** 2026-08-01 (re-check whether the env policy was widened).

### 2026-06-19 UI standard: one parameter control (`EchoelValueField`) app-wide
- **Decision:** Every adjustable numeric parameter across the app uses `EchoelValueField`
  (label + value + unit, adjusted by a vertical-fader drag / tap-to-type) — **no raw SwiftUI
  `Slider`/`Stepper` for parameters.** Dimensionless values show as raw decimals (`0.50`), not `%`.
  Migrated the Effects panel (the last outlier, ~40 rows) off `Slider` onto `EchoelValueField`;
  documented as a REQUIRED pattern in CLAUDE.md (UI DESIGN CONSTRAINTS).
- **Reasoning:** Founder asked to align the Effects-section parameter design with the other
  sections (which already used the value field) and to fix this as a long-term, app-wide standard.
  Consistency of reading + interaction; science-first (number, not a knob); accessibility (the field
  has VoiceOver adjustable + type-to-set).
- **Expected outcome:** Identical parameter UX everywhere; new modules inherit it for free; any
  divergence must go through The Council first.
- **Review:** 2026-09-19.

### 2026-06-19 Canonical execution roadmap (`docs/dev/ROADMAP.md`)
- **Decision:** Adopt `docs/dev/ROADMAP.md` as the single source of truth for *execution*
  (the HOW), sitting above the 20+ scattered `scratchpads/PLAN_*` / `STRATEGY_*` docs. It
  references `memory/vision.md` (the WHY) without duplicating it, indexes/subordinates the
  scattered plans (🟢 active / 🟡 gate / ⚪ superseded), and holds ONE pragmatic Now/Next/Later
  backlog + an honesty ledger + review cadence. Precedence: `vision.md` + `ROADMAP.md` win over
  any stray plan.
- **Reasoning:** Founder asked to "give the whole thing the necessary structure — pragmatic and
  open for my vision". `vision.md` already structured the north star/tiers/principles well; the
  missing layer was a single execution thread (the plans had scattered, partly contradictory).
- **Expected outcome:** No more doc scatter as truth; every cycle picks from one backlog; plans
  become inputs not authority; stale ⚪ plans get deleted in `chore:` cycles once rolled up here.
- **Review:** 2026-07-19.

### 2026-06-17 Positioning: "The Multidimensional Production Instrument"
- **Decision:** Reposition Echoel around ONE category-defining idea — "the multidimensional production instrument." Not a renderer competing with Dolby Atmos / Apple Spatial, but the multidimensional SOURCE: one body plays multiple real dimensions at once over open standards. Five pillars by reality: **Body** (LIVE) → **Sound** (LIVE) → **Light** Art-Net/sACN (LIVE) → **Space** ADM-OSC object out (LIVE) → **Vibration** sub-bass/LFE + Core Haptics (LIVE, shipped this cycle). Data (OSC/MIDI 2.0/MPE/AUv3) is the connective layer. Immersive 360°, multichannel render, live broadcast = roadmap.
- **Reasoning:** Deep research — MPE *freed* the word "multidimensional" (MIDI Association renamed Multidimensional→MIDI Polyphonic Expression on 2018 adoption), so no vendor owns it as a category; Dolby/Apple own "spatial/immersive/Atmos." "Felt"/haptic music is going mainstream in 2026 (SoundShirt, Tactus, BASSpak) and aligns with Echoel's accessibility-first brand. visionOS 26/27 supports 360° but no dedicated spatial music-creation app exists → gap. The claim is earned by the open-standard output *dimensions* that already ship.
- **Tagline chosen by founder:** "multidimensional production instrument" (over "instrument" / "studio").
- **Execution:** website reorg (index hero/cap-map/meta, tools.html "One Instrument, Many Dimensions" section); the in-app "tools flow into one" is already done (single EchoelStudioView); add new dimensions as sliders on the one instrument, never new tabs.
- **Review:** 2026-09-17.

### 2026-04-26 v10 Pivot: DAW + Video + Stream (Hybrid Strategy)
- **Decision:** Pivot Echoelmusic from bio-reactive ambient soundscape generator to a unified iPhone-first creation studio combining mobile DAW, video editor, and RTMP live streaming. Hybrid approach: keep the audio infrastructure (AudioEngine, RetroCapture, AutoMixChain, SingleExport, EchoelDDSP, EchoelCellular, SPSCQueue, EchoelStore) and the protected bio DSP (BioEventGraph, HilbertSensorMapper, BioSignalDeconvolver, untouched). Deprecate from main flow: SoundscapeEngine, ClipEngine, MomentCaptureView, BioSourceManager auto-streaming. Build new: PatternEngine + SamplerVoice (16-step × 8-track sequencer), MultiTrackRecorder, CameraSession + VideoRecorder + ClipTrimmer, RTMPPublisher (HaishinKit), and a 4-tab StudioRoot (Beat / Record / Video / Share).
- **Reasoning:** User wants FL Studio Mobile + Ableton + iPhone Camera + InShot + RTMP streaming "in einem Programm" with TestFlight in 3 weeks ("der sich gewaschen hat"). Ground-up rewrite kills the deadline; pure crash-fix on the bio-soundscape abstraction does not deliver a DAW. Hybrid preserves ~60% working audio infrastructure and reaches the new product surface in a focused 3-week sprint.
- **Alternatives considered:**
  - Ground-up rewrite (Echoel Studio fresh repo) — rejected: 4–6 weeks foundation, then features on top, miss deadline
  - Pure Ralph-Wiggum crash-fix mode on existing v9.0 code — rejected: fixes wrong abstraction, doesn't ship the DAW vision
  - Keep SoundscapeEngine as hub, bolt on DAW features — rejected: bio-soundscape mental model fights track/clip mental model
- **Expected outcome:** TestFlight build by 2026-05-17 with all three pillars (Beat / Record / Video / Share) interactive on iPhone. RTMP stream to YouTube test-stream verified. Single dependency added: HaishinKit. Bio-protected DSP unchanged.
- **Review date:** 2026-05-17 (TestFlight upload date — verify deliverables match this decision)

---

## Format

### [DATE] Decision Title
- **Decision:** What was decided
- **Reasoning:** Why this choice was made
- **Alternatives considered:** What else was evaluated
- **Expected outcome:** What we expect to happen
- **Review date:** When to revisit this decision

---

### 2026-03-16 EchoelVoice as First AUv3 Product
- **Decision:** Build EchoelVoice (bio-reactive vocal processor) as first standalone AUv3 plugin
- **Reasoning:** Zero competition in bio+audio+visual AUv3 space. Vocal processing highest-demand category. $14.99 validated.
- **Alternatives considered:** EchoelFX (effects), EchoelSynth (synthesis) — deferred
- **Expected outcome:** First revenue-generating plugin, validates AUv3 pipeline
- **Review date:** 2026-05-17
- **Reviewed 2026-04-17:** AUv3 extension exists in codebase (EchoelmusicAUv3/), disabled pending App Store Connect provisioning. Decision still valid. AUv3 pipeline proven.

### 2026-03-16 iOS 17+ for AUv3 Targets
- **Decision:** Raise AUv3 deployment targets to iOS 17.0
- **Reasoning:** `@Observable` requires iOS 17+. ObservableObject banned per CLAUDE.md.
- **Alternatives considered:** Stay on iOS 15 with ObservableObject — rejected
- **Expected outcome:** Modern SwiftUI patterns, cleaner ViewModel code
- **Review date:** 2026-05-17
- **Reviewed 2026-04-17:** Confirmed correct. All @Observable classes in codebase. Zero ObservableObject found. iOS 17.0 minimum target in Package.swift and project.yml.

### 2026-03-16 Claude Code Enhancement System
- **Decision:** Integrate everything-claude-code patterns (agents, commands, rules)
- **Reasoning:** Structured TDD, planning, security, and verification workflows accelerate development
- **Alternatives considered:** Install full generic repo — rejected, adapted to Echoelmusic context
- **Expected outcome:** Faster iteration cycles, fewer regressions, self-improving system
- **Review date:** 2026-05-17
- **Reviewed 2026-04-17:** Confirmed working. 21 GStack skills + custom Echoelmusic skills active. Plan mode, parallel agents, TDD in active use.

### 2026-03-16 Replace LiquidGlass with EchoelSurface Design System
- **Decision:** Removed all glassmorphism (blur, .ultraThinMaterial, glow blend modes, >8px shadows, pill shapes) and replaced with EchoelSurface — solid fills, subtle 1px borders, shadows capped at 8px, corners capped at 12px
- **Reasoning:** LiquidGlass violated every design constraint in CLAUDE.md (glassmorphism, glow effects, large shadows, scale animations). Corporate design requires Linear/Stripe aesthetic — functional, minimal, precise
- **Alternatives considered:** Keeping LiquidGlass with reduced effects — rejected, fundamentally wrong approach
- **Expected outcome:** Clean, compliant UI matching brand identity. Backward-compatible type aliases prevent breaking existing code
- **Review date:** 2026-05-17
- **Reviewed 2026-04-17:** Confirmed. SoundscapeView audit shows clean design: black background, solid fills, opacity-only animations, no glassmorphism, no glow. Design constraints maintained.

### 2026-03-16 Wire All 12 EchoelTools into App
- **Decision:** Initialize EchoelSeqEngine, EchoelLuxEngine, EchoelAIEngine, OSCEngine in workspace.deferredSetup(). Add Sequencer, Bio, Lighting, AI panels to EchoelStudioView bottom bar (scrollable)
- **Reasoning:** 4 engines had code but were never initialized. 4 views existed but had no navigation path. Users couldn't access major advertised features
- **Alternatives considered:** Leaving uninitialized (broken UX) — rejected
- **Expected outcome:** All 12 EchoelTools accessible from studio workspace
- **Review date:** 2026-05-17
- **Reviewed 2026-04-17:** SUPERSEDED. Architecture changed to focused soundscape generator in v8.0 (stripped from 12-tool suite). SoundscapeEngine is now the single hub. Multi-tool studio workspace no longer exists. This decision is obsolete.

### 2026-03-18 Scheme Check Before Archive in TestFlight CI
- **Decision:** Add "Check Scheme Exists" step to watchOS/macOS/tvOS/visionOS jobs in testflight.yml
- **Reasoning:** Only iOS scheme exists in project.yml. Auto-merge dispatches platform:all, causing 4 jobs to fail on missing schemes
- **Alternatives considered:** Change auto-merge to dispatch ios-only (too limiting for future), remove non-iOS jobs (lose them permanently)
- **Expected outcome:** Non-iOS jobs skip gracefully with warning; ready when schemes are added to project.yml
- **Review date:** 2026-05-17
- **Reviewed 2026-04-17:** Confirmed working. Only iOS scheme in project.yml (verified). Non-iOS CI jobs gracefully skip. iOS TestFlight workflow production-ready. No change needed.

### 2026-03-18 Platform-Aware Skills
- **Decision:** Upgraded testflight-deploy, ship, scan, full-repo-audit to detect Linux/web environment
- **Reasoning:** `swift build` unavailable on Linux/web sessions. Skills must fall back to GitHub CI API checks
- **Alternatives considered:** Only run skills on macOS — rejected, limits CI-driven workflows
- **Expected outcome:** Skills work in all environments (macOS, Linux, web)
- **Review date:** 2026-05-17
- **Reviewed 2026-04-17:** Confirmed. Current session is Linux (swift not available). Skills correctly fall back to CI-based checks. Working as designed.

### 2026-03-20 Integrate GStack Toolkit (All 21 Skills)
- **Decision:** Cloned garrytan/gstack into `.claude/skills/gstack/` with full 21 skills. Merged `/review` and `/ship` commands with Echoelmusic-specific checks (audio thread safety, bio-safety, iOS 26 SDK, Swift 6 concurrency)
- **Reasoning:** GStack adds YC-style planning (/office-hours, /plan-ceo-review, /plan-eng-review), paranoid code review with fix-first flow, browser-based QA, and one-command shipping. Complements existing Ralph Wiggum Lambda workflow
- **Alternatives considered:** Install subset only — rejected per user preference ("Alles"). Prefix GStack skills to avoid conflicts — rejected, merged instead
- **Expected outcome:** 21 new workflow skills, comprehensive review pipeline, faster shipping cadence
- **Review date:** 2026-04-19

### 2026-03-20 Git Worktree Command for Parallel Development
- **Decision:** Added `/worktree` command based on Matt Pocock's pattern for parallel Claude Code sessions
- **Reasoning:** Worktrees enable multiple Claude instances to work independently on the same repo. Massive throughput increase for independent tasks (audio + UI, bio + visual, tests + docs)
- **Alternatives considered:** Single-session sequential work — slower for independent tasks
- **Expected outcome:** Parallel development capability, better utilization of Claude Code sessions
- **Review date:** 2026-04-19

### 2026-04-18 Live Studio Pivot — v9.0 Architecture
- **Decision:** Reposition Echoelmusic from bio-reactive soundscape generator to a DAW + Live Media Production Suite. New tagline: "Record. Stream. Release." One-screen iPhone UI, no window switching.
- **Reasoning:** Bio-only soundscape has limited commercial appeal. Combining pro-level improv recording + instant mastering + live streaming hits a clear market gap. User can produce a release-ready single from a 2:30 session without leaving the app.
- **Alternatives considered:** Incremental bio-feature expansion — rejected (niche ceiling). Full DAW (multitrack) — deferred to v10.
- **Expected outcome:** Broader audience, App Store differentiation, TestFlight feedback loop on live streaming
- **Review date:** 2026-05-18

### 2026-04-18 Bio as Badge (not Tab)
- **Decision:** Removed Bio from `StudioMode` tab strip. Bio now shown as compact HR number + coherence dot in status bar; tap opens CameraMeasurementView.
- **Reasoning:** Bio is ambient context, not an active tool in a DAW workflow. A live performer doesn't switch to a "Bio" tab mid-session. Status bar badge gives constant visibility without consuming a tab slot.
- **Alternatives considered:** Keep Bio tab — rejected (wrong cognitive model for DAW UX)
- **Expected outcome:** Cleaner 4-tab strip (Perform/Mix/Stream/Export), bio always visible without interrupting flow
- **Review date:** 2026-05-18

---

### 2026-03-11 Persistent Memory System
- **Decision:** Created /memory directory for cross-session context retention
- **Reasoning:** scratchpads/ serves session-specific logs; memory/ stores durable knowledge that should persist indefinitely
- **Alternatives considered:** Extending scratchpads/, using .ai/ directory
- **Expected outcome:** Faster session starts, no repeated discovery of known facts
- **Review date:** 2026-05-17
- **Reviewed 2026-04-17:** Confirmed working well. memory/ files (decisions.md, user.md, preferences.md, people.md) restored full context at session start. System working as intended.

---

### 2026-06-01/02 Apple-ecosystem ship + honesty pass (session)
- **Decision:** Ship the focused bio-reactive instrument across 3 Apple surfaces (app + Widget + AUv3) on TestFlight (build 1477), make the website/App-Store metadata honestly mirror the code, and establish FEATURE_MATRIX as the single roadmap. Hold device-bound and decision-gated work (camera, watch embed, CI-matrix, RTMP/Link) rather than blind-build.
- **Reasoning:** Sandbox can verify compile/sign/upload but NOT runtime. Highest integrity = ship what's CI-verifiable, be honest about what isn't, and not overclaim. User wants present+future safe.
- **Key sub-decisions:**
  - **SDK doctrine:** speak open standards, depend on almost nothing. Ableton Extensions deferred; Oura via HealthKit (no SDK); RTP-MIDI + Link = Tier-1 next.
  - **Camera = ONE shared input** (CameraHub fan-out: bio/video/visual/RTMP/spatial); modes mutually exclusive. See SPEC_CAMERA_PIPELINE.md.
  - **macOS = Mac Catalyst first** (native AppKit deferred).
  - **Website mirrors code**, FEATURE_MATRIX is the Fahrplan.
  - **Release auto-demo:** so TestFlight testers without hardware see live bio-reactivity.
- **Lesson logged (correction):** removing the fastlane dev-cert revoke caused dev-cert accumulation → Apple cert-limit → extension archives failed. The revoke was load-bearing (limit mgmt), not just a race; restored it (race-safe for single-platform dispatch).
- **Expected outcome:** A genuinely tester-usable TestFlight build + a clean, honest public face + a documented App Store submission checklist. Next: on-device verification.
- **Review date:** 2026-07-02

---

### 2026-06-02 Camera rPPG + App-Store metadata honesty
- **Decision:** Mark camera rPPG Planned (dormant in code), and brand-clean App Store metadata (en-US + de-DE) — drop wellness/meditation/16K/"Super Intelligence AI"/100+ overclaims. Other 10 locales flagged, not blind-translated.
- **Reasoning:** Misleading metadata fails App Review (§2.3) and violates the brand rule; honest copy that matches the shipped LIVE set is safer and on-brand.
- **Expected outcome:** Review-safe primary-market metadata; remaining locales + screenshots + privacy labels are the documented submission blockers.
- **Review date:** 2026-07-02

### 2026-06-16 Echoel = bio-reactive INSTRUMENT, not wellness (compliance + brand)
- **Decision:** Resolve the "wellness vs instrument" framing conflict (session Layer-4 addendum vs CLAUDE.md) in favor of the **artistic/performance instrument** identity. Achieve App Store §5.1.3 compliance by removing medical/diagnostic, false-feature, and esoteric claims — not by adopting a "wellness" label.
- **Reasoning:** Wellness framing commoditizes Echoel against thousands of meditation apps and contradicts the checked-in brand. The differentiated, defensible position is "the body as controller / first bio-reactive performance instrument." 5.1.3 is about avoiding clinical claims, which we do regardless of the marketing label.
- **Actions:** Rewrote en-US + de-DE App Store descriptions and release notes to the real shipped feature set (no 16K/1000fps/100+ AI/worldwide collaboration); cleaned Android full_description; renamed in-app genre label "Esoteric Meditation" → "Deep Ambient" (only banned term that shipped in-app); website persona "Therapists & Coaches" → "Facilitators & Educators"; Flow-mode copy drops "meditation".
- **Note:** Supersedes/completes the 2026-06-02 metadata-honesty decision (descriptions had regressed to overclaims).
- **Review date:** 2026-07-16

### 2026-06-16 Brainstorming hub + "Everything wires" cross-platform stance
- **Decision:** Add a website Brainstorming menu item that cleanly separates the **honest current TestFlight set** ("In TestFlight now") from **future directions** chosen for real market potential (ideas, not promises). Document cross-platform reach — Apple surfaces (iPhone anchor → iPad/Mac/Watch/TV/Vision), Android, Windows, Linux, adaptive WebApp, XR/VR, AI/edge — as **open construction sites**.
- **Principle ("Everything wires"):** Echoel need not be identical on every device; it wires into any hardware via **open standards** (MIDI 2.0/MPE, OSC, ADM-OSC, BLE Heart Rate, Art-Net/DMX), no SDK lock-in. The **iPhone TestFlight build is the stable anchor**, shipped first; other platforms expand from the same core.
- **Done:** docs/brainstorming.html (+ site-wide nav, sitemap, version.json 10.16.0). Keep current: move items Idea→Live as they ship; never over-promise.
- **Review date:** 2026-07-16

### 2026-06-16 Deploy workflow learned & proven (token-free branch push)
- **Token-free deploy:** `git push origin HEAD:deploy` triggers `deploy-on-tag.yml`, which dispatches `testflight.yml` via the built-in `GITHUB_TOKEN` (workflow_dispatch is the recursion-guard exception). `git push origin HEAD:deploy-dryrun` = build_only archive check (no upload, no quota). Proven by run #1833 (deploy-dryrun = SUCCESS). Sandbox git proxy rejects TAG pushes → we use BRANCH triggers. Personal PAT no longer needed (and the chat-exposed one was revoked).
- **Archive is stricter than SwiftPM CI:** App Intents passed `ci.yml` but failed the Xcode archive — `static var` AppIntent requirements are Swift-6 "global shared mutable state"; must be `static let`. Always pre-verify risky builds with the dryrun before a real deploy.
- **Apple daily upload cap:** exhausted today because `Auto-Merge Claude Branch` auto-merges to `main` and auto-uploads on every feature push. Build is good; only Apple's "wait 1 day" blocks the upload. Pause auto-deploy-on-merge before the next intended deploy.
- **Log access in sandbox:** raw Actions logs live on a blob host NOT in the network allowlist (403). Use `mcp__github__get_job_logs` (server-side) to read CI failures.

### 2026-06-16 SHIPPED — TestFlight build 1837 VALID (token-free deploy proven)
- **Result:** `git push origin HEAD:deploy` → run #1837: Preflight ✅, iOS Archive ✅, Export & Upload ✅, ASC poll `build_number=1837 id=ef72d8fc-c191-43c1-ba41-e810536e0c73 state=VALID uploaded=2026-06-16T07:11:42-07:00`. Dispatched by `github-actions[bot]` via `GITHUB_TOKEN` — no PAT.
- **Why it worked this time:** the daily upload cap had reset, and the two quota-burning auto-upload triggers were disabled first (`auto-merge-claude.yml` Trigger-TestFlight → `if: false`; `trigger-testflight.yml` → `workflow_dispatch` only), so the fresh daily quota went to our intentional build.
- **This build carries:** algorithmic reverb (Room/Hall), harmonizer, per-genre saturation, anti-aliased DDSP, polyphonic synth + deep piano roll, patch editor, hybrid sample+synth drums, sample browser, Siri/Shortcuts intents, on-device bio-music director (iOS 26-gated) + fallback, precise read-only Health/privacy strings, brand-clean copy.
- **Standing ship path:** optional `HEAD:deploy-dryrun` (archive-only, no quota) to pre-verify, then `HEAD:deploy` for the real upload. Keep auto-upload-on-merge OFF.
- **Local note:** Swift is NOT installed in the remote sandbox — cannot `swift build`/`swift test` here; rely on `ci.yml` + the Release archive (deploy-dryrun) as the real compile gate.
- **Review date:** 2026-09-16

### 2026-06-16 Quality loop — build 1840 (scratchy sound + hanging buttons fixed)
- **Trigger:** owner — "Alles optimieren. Vermeide kratzige Sounds und hängende Buttons, ein done Button reicht" + screenshot showing 5 stacked Done buttons on the number pad; then "loop mode until vision + technical highest quality."
- **Audio (no more 'kratzig'):** EchoelSVFilter was clamped at ~SR/2 (normalizedCutoff 0.45 → f≈1.95), so the Chamberlin SVF self-oscillated into a scratchy whine; now bounded to SR/6 (f≤1.0) + min damping 0.05 (max resonance 0.95). Reverb comb + delay feedback states now add 1e-20 to flush denormals (no tail crackle). dsp-reviewer found deeper smoothing opportunities (per-sample cutoff/harmonicity/noise ramps, no double-saturation) — DEFERRED to a later cycle pending device listening, to avoid blind audible regressions (no local Swift compiler in sandbox).
- **UI (no more 'hängende Buttons', 'ein done reicht'):** the 5-Done bug was every numeric field (ParamControl/RotaryKnob/DecimalField) attaching its own `.toolbar(.keyboard)` Done → SwiftUI merges them; fixed by gating each on its own `focused` (one field focused → one Done). Export funcs now `exporter.reset()` so a failed export can't leave the button stuck. Piano-roll 'Clear' moved from the misleading cancellationAction slot to an explicit destructive trash button. Mix Record button guarded against double-tap during async stop.
- **CI lesson (important):** deploy-dryrun was a NO-OP — `build_only=true` skips all archive jobs and the wrapper also set `skip_compile_check=true`, so dryruns 'passed' in ~20s WITHOUT compiling. Fixed deploy-on-tag.yml: dryrun now runs the real Compile Check job (xcodebuild build, iOS device SDK, no signing, no upload). This is the trustworthy pre-ship gate now (esp. since Swift isn't installed locally).
- **Ship:** build 1840 archived clean (Compile Check verified the same tree first), Export & Upload SUCCESS (slow ~10 min Apple upload, not a cap failure), ASC verify confirming. Build 1837 was the prior confirmed-VALID build.
- **Review date:** 2026-09-16

### 2026-06-16 Competitive strategy — moat-first, clip/session wedge, Bio Acceptance gate
- **Positioning:** Do NOT try to out-DAW FL Studio Mobile / Cubasis 3 / Zenbeats / Loopy Pro / Ableton Note — lose on maturity. Win as the ONLY bio-reactive live instrument with open-standard light/spatial/broadcast reach. Lead with the moat (bio-reactivity, generative-from-physiology, MIDI2/MPE·OSC·ADM-OSC·Art-Net, on-device/private/free, accessibility, Rausch triad).
- **Founder rule (gating):** biofeedback for ALL heart devices must be truly solid FIRST → defined as "Bio Acceptance v1" test gate (source coverage Apple Watch/HealthKit + any BLE 0x180D strap + camera rPPG + Demo; <5s reconnect; per-source validity flag; latency ≤1-2s; RMSSD self-computed + reproducible coherence; 30-min zero-crash; hot source-swap). No arrangement/video/light expansion until green. See scratchpads/PLAN_COMPETITIVE_ROADMAP_2026-06-16.md.
- **BIG FIND:** 6 EchoelTools are fully built & compiling but UNREACHABLE (no UI opens them): PianoRollView, PatchEditorView, SampleBrowserView, EchoelFXView, EchoelMixView, ComposeView. Surfacing them (toolbar→sheet, verify @Environment injection, one at a time, dryrun) = lowest-risk highest-leverage Phase-1 win for the current TestFlight.
- **Wedge feature (post-gate):** clip/session launching (build on existing PatternEngine first) — highest identity-fit, lowest new-engine risk; the live-instrument differentiator. Then audio-track recording + Ableton Link (parity), then arrangement, then video/RTMP, then sACN.
- **Verified parity gaps (ranked):** audio-track recording · clip/session launch · Ableton Link · arrangement timeline · deeper MIDI+automation · sampler depth · time-stretch · stems.
- **Review date:** 2026-07-16

### 2026-07-04 NEUSTART — priority reframe (keep engine, fix priorities)
- **Founder trigger:** "wir haben uns verlaufen … Neustart." NOT a code rewrite — the engine
  (DSP/generative music/visuals/EngineBus/patch system) is the good part. The problem is
  priorities: the app spread across DAW + biofeedback + visuals + broadcast while the CORE
  INPUT (camera rPPG at the fingertip) is the least reliable part, so nearly every device
  session was consumed fighting the pulse instead of making music.
- **Agreed reframe (4 pillars, `scratchpads/PLAN_NEUSTART.md`):**
  - **P1** — the pulse must EARN trust; camera is the APPROXIMATE fallback, not the anchor.
    BLE HR (already built) becomes the preferred source; camera labeled "≈".
  - **P2** — the music must be ROBUST to a noisy pulse (drive on the smoothed TREND, never the
    raw number) so a bad reading can never ruin the take.
  - **P3** — ONE screen that does ONE thing perfectly (body → one loop → one visual), then expand.
  - **P4** — honesty everywhere (claim only what ships; "≈" on approximate; not diagnosis).
- **Executed step 1 (v10.79.52):** rPPG TRUST-GATE — a reading may move the shown pulse / latch
  the tempo only when confident AND corroborated by real autocorrelation (acf ≥ 0.4). Device log
  2026-07-04 showed acf 0.14 / conf 0.90 "settling" at a wrong 79 bpm (true pulse ~54); the gate
  makes a bad reading HOLD ("acquiring") instead of showing/seeding a fantasy number.
- **Review:** after founder device-verify of 79.52, proceed to P1 (BLE preferred + "≈ camera" label).

### 2026-07-09 Melody OUT — every curated genre is a pure sustained Fläche preset
- **Founder (verbatim):** "die Melodie in den Genres war zu laut und zu unnatürlich von
  Klangspektrum so reine Wellen Töne sind eher unangenehmen gerade wenn sie aus dem mix so
  rausstechen. Es wäre auch besser wenn die komplett weg sind. Dann können wir uns doch drauf
  einigen, du machst passende presets für Genres in denen wirklich nur chilligenmystische
  Flächen sind oder? Und trotzdem soll es bei jeder session, jedem User und je nach Biofeedback
  immer individuell klingen. Wichtig sind die tighten Loops, damit wir die wav Weiterverarbeitung
  so einfach wie möglich halten."
- **Executed (v10.79.123):** all 6 curated `harmonicProfile`s → `leadDensity 0, sustained: true`
  with distinct characters (minor drone · lydian drone · maj7 [0,3] oct4 vaporwave · dorian m7
  [0,3] oct3 dub · harmonic-minor [0,5] oct3 trap · phrygian [0,1] oct3 sci-fi). Dub/Trap now
  route through `composeHarmonic` like every harmonic genre — `dubMelody`/`trapMelody` (the
  offbeat stabs / exposed dark-bell lead) are retired from the flow but stay defined (reversible);
  their SIGNATURE beats stay hand-built. Breath-swell now applies to all 6 (keys off `sustained`).
- **Guardrails (tests):** curated = pure Flächen (no `.lead`, no notes <4 steps, bar-tight
  `startStep+len ≤ 16`, across seeds AND body states); fingerprints (scale|progression|voicing|
  register) must stay pairwise distinct; `sustained` ⟺ curated membership. Arrangement/pulse
  invariants moved onto retired melodic profiles (.futuristic/.disco).
- **Do NOT** re-add a lead line to a curated genre without a founder ask; the reversible path
  is documented in `BioComposer.compose`.

### 2026-07-09 Echoel AI: interactive, never unprompted — and Apple-native integration as the bar
- **Founder (verbatim):** "Echoel AI soll interaktiver werden und nicht ungefragt Dinge
  anzeigen. Alles soll sich perfekt in die Apple Umgebung integrieren"
- **Rule going forward:** no UI element appears unprompted over the instrument. Status
  belongs where the user looks (inline rows, existing panels); explanations/coaching
  appear on request (disclosure/tap-to-learn) and the choice persists. Apple HIG
  patterns beat custom chrome wherever Apple has one.
- **Executed (v10.79.126):** live EchoelAI narration → quiet disclosure row, default OFF,
  persisted; nonStandardTuningBanner unpresented (builder kept, reversible — the tuning
  row in Composition is the on-request home). KEPT as-is: rPPG recovery/cooling banner
  (honest system state during a user-started measurement, not coaching).
- **Open arc (needs founder-gated scoping):** full HIG pass — Dynamic Type audit, system
  materials, standard gestures; deeper Apple integration candidates (Shortcuts/App
  Intents, Widgets already shipped, HealthKit write?) are FEATURES → vision-gate each.

### 2026-07-10C POSITIONIERUNG: „Der Bio-Dirigent oben auf der Profi-Kette" (Grand Council)
- **Founder-Frage (verbatim-Kern):** „Ich will mit meiner Software einen oben drauf setzen
  … Film Level Animationen und fx Design … farbwerte, Soundeffekte und midi/mpe per
  Biofeedback modulieren oder halt ganz normal produzieren. Multidimensional Multimedia
  in einer Ansicht" — vertraut: Ableton/FL/AUM/InShot; Referenz: Premiere/FinalCut/
  DaVinci/Reaper/ProTools/Resolume/TouchDesigner/OBS.
- **Urteil:** Echoel ersetzt die acht Tools nicht — es **dirigiert** sie. Der Körper ist
  die Modulationsquelle, die keines der acht hat; offene Standards (MIDI/MPE · OSC ·
  ADM-OSC · Art-Net/sACN · Export; später AUv3/RTMP) sind die Zugbrücken.
- **Lane-Formel (Definition von „fertig" für die eine Ansicht):** jede Lane kann
  (a) selbst klingen/leuchten · (b) per Körper moduliert werden · (c) normal automatisiert
  werden · (d) per offenem Standard ein Profi-Tool fernsteuern · (e) sauber exportieren.
  „Film-Level" entsteht bei (b) auf EIGENEM Material (Cymatics, Bio-Grade) — nie als NLE-Nachbau.
- **Via negativa (bindend):** kein Video-NLE (Feinschnitt = InShot/Resolve mit Echoels
  Export) · kein Broadcast-Mischer (OBS = Partner via RTMP) · kein Compositing/CMS in v1 ·
  keine Feature-Paritäts-Roadmap.
- **Dissent protokolliert:** Jobs/Taleb wollten Video ganz delegieren; Auflösung: Video JA
  als eigene Bio-Dimension (Capture gegen Transport-Clock/Trim/Bio-Farb-Grade/Export),
  NEIN als NLE-Anspruch.
- **Reihenfolge bestätigt (kein neuer Plan nötig):** v1.0-Launch → K2a → K2b/B2 → A1/A2 →
  K3 → Video-Block → v1.1 Live → v1.2 Broadcast. AUv3-Aktivierung = wichtigste künftige
  Zugbrücke in den AUM-Workflow des Founders (nach v1.0, vision-gate).
- **Doc:** `scratchpads/STRATEGY_BIO_CONDUCTOR_2026-07-10.md` · Review: 2026-08-09

### 2026-07-11 NFT/Wallet = REJECT · Geld-Pfad = Live-Abo + Verwertungsgesellschaften (Grand Council)
- **Founder-Frage:** „Die NFT-Integration wieder zurückholen? Kann Echoel gleichzeitig ein
  Wallet sein, um generiertes Geld umzusetzen? … GEMA/musichub/Rechteverwertung (Wort etc.)?"
- **Befund:** KEIN NFT/Wallet/Crypto im Code — die alte `security.html` hatte Crypto nur
  BEHAUPTET (Haftungs-Overclaim, längst entfernt). Nichts „zurückzuholen".
- **Urteil (Christensen/Taleb/Munger/Buffett/Naval):**
  - **NFT → REJECT.** Reputativ verbrannt; Apple 3.1.1/3.1.5 (NFTs dürfen keine App-Funktion
    freischalten, In-App-Digitalverkauf IAP-pflichtig); widerspricht der Seriositäts-Ansage.
  - **Wallet → REJECT (absehbare Roadmap).** Macht Echoel zum regulierten Finanzdienst
    (Custody/KYC/AML/Lizenzen je Land) = fetter negativer Tail für Solo-Founder; identisch
    mit dem in STRATEGY_GLOBAL_LIVE verworfenen „Marktplatz mit Payouts/KYC". Das Geld-Modell
    steht bereits Apple-konform: v1.1 Live-Abo + v1.2 Host-Fee via Apple-IAP (Apple = Zahlungs-
    Infrastruktur, kein Wallet nötig).
  - **GEMA/musichub/VG Wort → ADOPT als METADATA-Export, NICHT als In-App-Fintech.** Passt in
    Lane-Formel (e) „sauber exportieren". Session-Stempel um ISRC/IPI/Werktitel anreichern →
    Exporte GEMA/GVL-anmeldefertig. Anmeldung/Release macht der Founder EXTERN (GEMA+GVL,
    musichub/DistroKid). Keine GEMA-API IN der App (schwerer Server + Rechte-Recht = nein).
    VG Wort = Text/Wort, für Musik irrelevant.
- **Dissent (benannt):** Der legitime Kern („wie werde ich bezahlt") ist echt — Antwort ist
  regulär (Abo + Verwertungsgesellschaften), nicht Krypto.
- **Gate:** proceed (Reject Krypto, Adopt Rechte-Metadaten-Pfad); Krypto bleibt WATCH,
  revisitierbar nur falls je Kern-Vision. Nichts gated v1.0. **Signal-Tester-Gruppe** =
  Geräte-Feedback-Schleife (pro Build ein Test-Fokus posten). Review: 2026-08-10.

### 2026-07-12 EchoelAI (Befehls-/Sprach-Schicht) = SPÄTERER eigener Baustein; Erklär-Zeile bis dahin entfernt
- **Founder (verbatim-Kern):** "Die Erklärung da brauchen wir erstmal nicht. Das kommt
  später in nem richtig funktionierenden EchoelAI small oder large language model, dass
  auch Befehle für Echoelmusic entgegennimmt wie Kompositionswünsche, Einstellungen,
  routing, videoschnitt Befehle, songwriting etc."
- **Executed:** `liveNarrationBanner` ("What your body is doing to the sound") aus dem
  EchoelStudioView-Flow entfernt (Builder bleibt compiled, reversibel).
- **Bedeutung:** EchoelAI ist als KOMMANDO-Interface gedacht (nicht nur Narration):
  Kompositionswünsche, Settings, Routing, Videoschnitt, Songwriting. Eigener
  Grand-Council-würdiger Baustein, wenn der Founder ihn aufruft — nichts vorab bauen.

### 2026-07-12 DMMW-Shell v3 + EchoelBioSynth-AUv3 (Founder-Anweisung nach v175)
- **Verbatim-Kern:** "Master, Export, Live und Learn kommt oben in die Leiste neben das
  Schloss. Video ist eine eigene Spur Art (Video Capture + voller Mediathek-Zugriff).
  Mix wird Teil der Spuren (Auflösung und neu organisieren). Comp, Session, Transpose,
  Sound, FX, Mood, Synth [+ 'Word' — unklar, vermutlich Autokorrektur; als 'alle übrigen
  Instrument-Panels' gelesen, Weather inklusive] → eigenes AUv3 Plug-in EchoelBioSynth.
  Plugins wird aufgelöst und Teil der Spuren — Zugriff auf ALLE installierten AUv3,
  unser EchoelBioSynth, weitere eigene und externe Store-Plugins."
- **Bedeutung:** Echoel = Host UND Instrument. Die Spur ist die Einheit (Klangquelle =
  beliebiges AUv3, auch unseres); die Shell behält nur Chrome (Transport + globale
  Türen). Der dormante EchoelmusicAUv3-Target wird zum PRODUKT (EchoelBioSynth).
- **Plan:** scratchpads/PLAN_DMMW_SHELL_V3_2026-07-12.md (E1 Chrome → E2 Mix→Spuren →
  E3 Video-Spur → E4 EchoelBioSynth-AUv3 → E5 per-Spur-Hosting). E1 sofort; E3/E4
  device-gated, E4 mehrwöchig (eigener Plan + Council vor Target-Umbau).

### 2026-07-12 MeditationView: keine eigene Tür — Ein-View-Produkt
- **Founder (verbatim):** "Meditation View nicht extra. Alles findet in der Main View
  statt und ist Teil des Produktionsprozesses."
- Konsistent mit RE-FOCUS 2026-07-06B: Entspannung entsteht DURCH das bio-generative
  Musizieren in der Main View, nicht durch separate Wellness-Screens.
- Konsequenz: MeditationView bleibt kompilierend (Session-Erbe-Regel: nicht löschen,
  nicht präsentieren), der tote `showMeditation`-Cover-Slot ist Slot-Reuse-Reservoir.
  Künftige Meditations-/Entspannungs-Qualität fließt in Musik + Visual der Main View
  (BioComposer/BioSpaceMap/Visual), NIE in einen neuen Screen.

### 2026-07-12C LYRICS/SONGWRITING BESTÄTIGT + HARDWARE-VORBEREITUNG
- **Founder (verbatim):** "Gurt und Watch noch nicht da aber bereite alles vor.
  … Lyrics bzw songwriting wie bei ACE Studio soll es geben ja"
- **Entscheid:** Die W-Spur (Word/Lyrics) ist offiziell Roadmap: Echoels eigener
  Weg = die EIGENE Stimme des Users als Sängerin (AutotuneCore + Skalen-
  Harmonien, VL-Spur) + deterministische Formant-Synthese in-house
  (VocoderCore/EchoelDDSP-Richtung) + Lyrics-auf-Noten-Mapping. NICHT ACE
  kopieren: deren zwei größte Schmerzen (Server-Render-Wartezeit pro Tweak,
  Credits-Abo-Dark-Patterns) sind unsere Gegenposition — on-device,
  deterministisch, Einmal-Unlock. Der AUv3-Slot "Stimme mit MIDI-Songwriting"
  ist marktweit unbesetzt (Deep Research 2026-07-12).
- **Timing:** nach dem Profi-Level-Milestone; pure Foundations (LyricsModel:
  Silben→Noten, Codable, TDD) dürfen früher als kleine Zyklen landen.
- **Hardware:** BLE-Gurt + Watch sind bestellt/kommen. Alles VORBEREITET halten:
  Gurt-Tür im Patchbay (6ba61e5) steht; HealthKit-Pfad (Watch-HR) läuft;
  NEEDS-FOUNDER-VERIFY-Tests sobald Hardware da (Gurt verdrahten → Puls im
  Header; Watch → HealthKit-Quelle).
- **Review:** 2026-08-12.

### 2026-07-15 EchoelPublish-Vision + rote Linie (Founder-Video: Zernio/Late-Werbung)
- **Founder-Ask (verbatim-Kern):** "Nicht nur livestreams auf verschiedenen Plattformen
  sondern auch automatisiert Accounts anlegen und strukturiert posten. Trotzdem
  handgemachter Kontent. Die EchoelVideo mit Biofeedback Reaktion und Musikvideo driven
  Content Produktion auf dem Beat Meridiane direkt in der DMMW und EchoelAI."
- **Zusage (Task #51):** (a) Beat/Bio-Auto-Edit auf dem Tick-Raster via TimelineStore-Ops
  (Store-first → EchoelAI-fahrbar), (b) 9:16-Export, (c) Publish-Türen über offizielle
  APIs (YouTube Data / Meta Graph / TikTok Content Posting) auf EIGENE OAuth-Accounts,
  Multi-Account + Scheduling — v1.2 Broadcast-Ära.
- **ROTE LINIE (dem Founder so kommuniziert):** KEINE automatisierte Account-Erstellung —
  Plattform-ToS ("inauthentic behavior"), Sperr-Risiko echter Accounts, App-Store-Risiko,
  Widerspruch zu "handgemachter Content". Legitime Alternative: Verteilungs-Automatisierung
  auf eigenen Accounts, nie Identitäts-Erstellung.

### 2026-07-16 EEG/Gehirnwellen als Modulationsquelle + Bio-Session-als-Instrument (Founder-Wiederaufnahme)
- **Founder (verbatim-Kern):** "Bio Session soll Teil der instrumente werden. Oder geht da
  sonst was verloren? ... nicht nur Herz rhytmen ... auch gehirnwellen [haffelder.de] ... wir
  haben uns [letztes Jahr] geeinigt wegen den komplexen Daten der Gehirnströme ... beide
  Hemisphären ... fft ... aufwändig ... ästhetisch brauchbare Musik ... direkt per
  oktavierung ... eher unangenehm ... Vielleicht gibts ja mittlerweile da neue Ansätze?"
- **Einschätzung (kein Bau diesen Zyklus — Assessment-Turn):**
  1. **Bio-Session-als-Instrument = richtig, nichts verloren SOLANGE die Session-Dateien
     bleiben.** bioVoice-Spur (BioReactiveSynthVoice) existiert bereits. Session
     (SessionEngine/Guide/Clock/EntrainmentEngine) hält die GETESTETEN Gesetze (Flash-Safety
     ≤3 Hz, Latenzausgleich, Entrainment-Pacing). Weg: Bio wird vollwertiges Spur-Instrument,
     Session-Engine wird der Modulations-Brain DAHINTER (Pacing/Entrainment → Bio-Spur), NICHT
     eine eigene Tür. Gefahr = Session löschen → Gesetze verloren. Additiv planen.
  2. **EEG = ON-VISION** (Marke: "brain rhythm drive sound"). DSP-Basis schon EEG-förmig
     (HilbertSensorMapper für EEG-Elektroden, BioEventGraph EEG-bursts, OSC bio/event/eeg);
     nur EEGSensorBridge (Hardware) entfernt. Alte Einschätzung bleibt korrekt: Audifikation
     (Roh/FFT → Oktavierung → hörbar) klingt unangenehm. NEUER/richtiger Ansatz = dasselbe wie
     beim Herz: Parameter-Mapping-Sonifikation — Bandleistungen (Delta/Theta/Alpha/Beta/Gamma)
     + Hemisphären-Kohärenz/-Asymmetrie als LANGSAME Modulationsquellen in die DDSP-Mappings.
     Haffelders METHODE (Spektralanalyse beider Hemisphären) übernehmen, NICHT das Therapie-
     Framing. Zwei Tore: (a) Hardware — iPhone hat kein EEG, braucht externes BLE (Muse/
     OpenBCI), echte Dep-Entscheidung wie 0x180D-Gurt; (b) HARTE rote Linie: kein Heilungs-/
     Therapie-Claim (Haffelder ist therapie-nah), Anzeige science-first.
- **Status:** 2 Tasks angelegt (Bio-Session-Instrument-Plan; EEG-Modulations-Plan). Reihenfolge
  vs. aktuelle Clip/Warp-Reihe founder-gefragt (offen). review_date: 2026-08-15.

### 2026-07-16 Mess-Stack v1.0: nur Apple-seitig, null Analytics-SDK (Launch-Marketing-Zyklus, Founder-Delegation "Du entscheidest")
- **Entscheid:** Für v1.0 wird AUSSCHLIESSLICH Apple-seitig gemessen: App Store Connect
  App Analytics (Impressions → Product-Page-Views → Conversion-Rate, Downloads,
  D1/D7-Retention), TestFlight-Feedback/-Crashes, Ratings/Reviews, MetricKit
  (Apples Opt-in-System). KEIN Analytics-SDK, kein In-App-Tracking, Website vorerst
  ohne Analytics.
- **Warum:** Privacy ist die Positionierung — das Listing verspricht wörtlich "No
  tracking", das Privacy-Label ist "Data Not Collected", die Review-Notes erklären
  "no server, no analytics SDK". Jedes SDK bräche alle drei gleichzeitig. Apples
  eigene Analytics sind SDK-frei (Apple-Opt-in aggregiert) und decken den Launch-
  Funnel vollständig.
- **Ritual:** wöchentlich post-Launch ASC-KPIs lesen → ASO iterieren (Promotional
  Text ist ohne Release änderbar — der schnellste Hebel). Privacy-freundliche
  Website-Analytics (z. B. serverloses Zählen) = separater Founder-Entscheid.
- **Kontext desselben Zyklus:** APP_STORE_LISTING_v1 vollständig gegen Code +
  FEATURE_MATRIX verifiziert (2 Device-Verify-Flags: BLE-Gurt end-to-end, AUv3 im
  Host); Keyword-Feld auf 100/100 Bytes (+",daw"); Presse-Kit `docs/press.html`
  angelegt (Boilerplate kurz/lang, Fact Sheet, Story Angles, Assets, Presse-Kontakt
  = veröffentlichte echoel@tropicaldrones.com; KEIN erfundenes Founder-Zitat —
  "quotes on request").

### 2026-07-16 Bio-Hardware committed: Polar H10 (Herz) + Muse S Athena (Hirn) — #61 Hardware-Tor geklärt
- **Founder-Kauf (Amazon-Warenkorb, Screenshot):** Polar H10 (75,95 €) + Muse S Athena
  Neurofeedback-Headband (493,45 €), beide bestellt.
- **Entscheid Herz-Quelle:** Polar H10 bleibt die gold-standard HRV/Kohärenz-Quelle
  (Brustgurt-EKG, saubere RR-Intervalle) — läuft HEUTE über den universellen BLE-0x180D-
  Empfänger; einzige offene Sache = Geräte-Verify (der ■-Flag im Listing).
- **Entscheid Hirn-Quelle:** Muse S Athena = EEG-Zielhardware (#61). Sendet über EIGENES
  Protokoll (NICHT 0x180D) → braucht neuen MuseBioPublisher + EEG-Felder im Bio-Frame +
  Parameter-Mapping-Sonifikation (Bandleistung + Hemisphären-Kohärenz → DDSP; NICHT
  Audifikation/Oktavierung). Athena kann zusätzlich fNIRS + eigenen PPG-Puls/Atem/Motion.
- **Beide gleichzeitig:** JA — EngineBus ist multi-source (HealthKit+rPPG+BLE+Demo koexistieren
  schon); Herz und Hirn füllen VERSCHIEDENE Frame-Felder, kein Konflikt; iOS hält zwei
  BLE-Peripherals problemlos. Ideal: Herz steuert einen Teil der Parameter, Hirn einen anderen.
- **Muse-allein-Frage:** technisch mit Entwicklung machbar (Muse misst Hirn+Puls+Atem+Motion),
  ABER sein Puls ist optisch/Stirn = verrauschtere HRV als der Brustgurt → für den wissenschaft-
  lichen Kern + Live-Performance bleibt der Polar die Herz-Wahrheit. Darum: BEIDE nutzen.
- **#61 Status:** Hardware-Tor GEKLÄRT (war der Blocker im 07-16-Assessment). Nächster Schritt
  = Plan + Council für den EEG-Ausbau; Reihenfolge (nach S2-W2 oder verschränkt) folgt aus dem
  laufenden projektweiten Audit. Kein Heilungs-Claim (harte rote Linie).

### 2026-07-16 ■-Frage geschlossen + projektweiter Audit → gebündelte Founder-Geräte-Session
- **■-Frage (v258/259, lange offen):** „Soll Musik-Stopp die Bio-Session überleben?" →
  GESCHLOSSEN mit dem Default **fusionierter Stopp** (Musik-Stopp stoppt Bio mit). Grund:
  ist bereits Shipping-Verhalten (EchoelStudioView.swift:641-642). Kein Code-Change. Nur
  neu entscheiden, falls #60 die Bio-Session als Modulations-Brain wiederbelebt.
- **Projektweiter Audit (wf_a57ff877-49d, 7 Agents, 2026-07-16):** gerankte Entscheidungen.
  Autonom (proceed): S2-W2 Slices 5-6 flag-OFF weiter; **Sheet-Chain-Konsolidierung** in
  EchoelStudioView (8×.sheet+1×.cover → EIN .sheet(item:)-Enum) VOR jeder Roadmap-UI
  (SIGSEGV-Schutz); Roadmap-Reihenfolge #58 (MIDI/MPE, Velocity-Lane zuerst) → #54 Warp →
  #60 Bio-Brain; Kleinschulden #57/#62/CI-Guard; #63 Archiv + #52 SEO als Nebengleise.
  Hold-for-founder → ALLES in EINE Geräte-Session gebündelt (scratchpads/FOUNDER_DEVICE_
  SESSION.md): 2 DEFAULT-ON-Flags + S2-W2-Slice-7 + BLE-Gurt + AUv3-im-Host + Screenshots +
  Ein-Feld-Store-Entscheide. Kern-Einsicht: 352 device-unverifizierte Commits + 2 flags auf
  dem Klangpfad = das eigentliche Risiko, nicht ein einzelnes Feature.
- **Deferred:** #36 Oktaver (audio-thread-Zyklus), #61 EEG (Hardware unterwegs), #59/#51
  (net-new, bio-first pre-launch).

---

### 2026-07-17 ARBEITSMODUS GELOCKERT (Founder-Verdikt) + "gebaut-aber-abgeschaltet" beendet
- **Founder (verbatim-Kern):** "Es funktioniert noch nichts und viele Änderungen wurden
  besprochen aber nicht umgesetzt. … Vermeide es auf der Stelle zu treten und lockere
  zu dogmatische Grenzen die wir uns anfangs gesetzt haben." (+ Reel über Claude-Code-
  Systeme: nicht rumprobieren, Systeme bauen.)
- **Diagnose:** Der dominante Fehlermodus war NICHT fehlender Code, sondern
  "gebaut-aber-abgeschaltet/nicht-verdrahtet" (Baustellen-Ledger 2026-07-14):
  fertige Fähigkeiten hinter Default-OFF-Flags mit "erst Geräte-Verify"-Gates,
  die der Founder nie auslösen KONNTE (kein Flag-UI) — ein Deadlock. Dazu
  Ein-Punkt-Ralph-Zyklen, die einzeln grün, aber als Ganzes tretend wirkten.
- **Beschlüsse (gelten ab sofort):**
  1. **voiceKindRouting DEFAULT-ON** (Registration wie multiRoll/laneAUInstruments):
     Drums-/Sub-Bass-Spuren klingen echt. Rollback-Hebel bleibt.
  2. **Integrierte Schnitte statt Ein-Punkt-Zyklen:** pro Zyklus ein ganzer
     hörbarer/fühlbarer User-Weg (die Max-3-Dateien-Regel fällt für kohärente
     Slices). Reviews bleiben, gebündelt pro Slice.
  3. **Jede grüne Runde deployt** — kein Aufstauen bis "Profi-Milestone".
  4. **Kein "gebaut-aber-abgeschaltet" mehr:** was fertig ist, wird hörbar/sichtbar
     gemacht (Registration-ON, Tür einbauen) oder explizit als dormant markiert.
  5. **NICHT gelockert (Physik/Sicherheit, kein Dogma):** Audio-Thread-Gesetze,
     Rausch-Triade READ-ONLY, Flash ≤3 Hz, keine Heilversprechen, Sheet-Ketten-
     Decke, 10-Hz-Freeze-Regel, keine neuen Dependencies ohne Ask.

### 2026-07-20 EchoelBodyVibe = die bio-generative INSTRUMENT-Oberfläche (Founder-Klärung)
- **Founder-O-Ton:** „EchoelBodyVibe vereint im Wesentlichen was Echoelmusic als Instrument
  war, BEVOR wir den radikalen DMMW-Pfad eingeschlagen haben, PLUS alle Erneuerungen, die wir
  seitdem in diesem Bereich aufgenommen haben (Mimik- und Body-Erkennung etc.)."
- **Bedeutung:** „DMMW-Pfad" = der tracks-zentrische DAW-Umbau (heutiges Home = WorkspaceView →
  ArrangeTimelineView-Spuren). **EchoelBodyVibe** ist NICHT nur ein Voice-Kind — es ist (soll
  werden) die OBERFLÄCHE des bio-generativen Instruments: der alte Compose-Flow
  (Genre/Key/Scale/Kammerton/Tempo → generate → play, bio-reaktiv, FX-Charakter, Visual) +
  die neuen Kamera-Bio-Modulatoren (A5 FaceExpressionBioPublisher = Mimik, Körpersprache).
- **Konsequenz für die Leisten-Auflösung:** generative/Charakter-Controls (Genre, Mood, Sound)
  → EchoelBodyVibe; produktionsseitige Controls (Mix, FX, Synth-Instrument) → Spurköpfe.
  „Genre → BodyVibe" (2026-07-20) ist damit eindeutig: Genre gehört in die Instrument-Oberfläche.
- **Status:** die BodyVibe-Oberfläche existiert als eigener Screen noch NICHT (die Teile leben
  heute verstreut in EchoelStudioView). Aufbau = mehrzyklige Arbeit (#67/#68). Review-Datum 2026-08-19.

### 2026-07-20 AUv3 -3000: beide In-App-Theorien widerlegt → Signing/Provisioning
- **Befund (try 1/3 nach Reinstall):** Self-probe der EIGENEN Appex bleibt -3000,
  OBWOHL (a) App-Group-Removal seit v306+ live ist UND (b) reinstall gemacht wurde.
  → cold-registry UND appex-App-Group als Ursache BEIDE widerlegt.
- **Repo/Code sind nachweislich korrekt:** Appex embedded (PlugIns/), AudioComponents
  unter NSExtensionAttributes (augn/echl/Echo), PrincipalClass AudioUnitViewController
  conformt AUAudioUnitFactory synchron, Modulname + fourCCs matchen. KEINE In-Code-Ursache übrig.
- **Restursache = Appex-Prozess-Launch-Denial (Signing/Provisioning-Fakt der Appex),
  NICHT Host-App.** Appex ist REGISTRIERT (AUM listet sie), startet aber nirgends.
- **Entscheidung:** Non-blocking, read-only CI-Schritt ergänzt (testflight.yml, c7e95b7):
  dumpt Appex-SIGNIERTE-Entitlements + embedded.mobileprovision (Name/App-ID/Team) +
  App-Profil zum Vergleich. Nie `exit 1` → grüner Deploy-Pfad unberührt. Council:
  proceed-with-mitigation (vorgeplante FAILED-Pfad-Aktion, reversibel, YAML+bash geprüft).
- **Nächster Schritt:** Diagnose-Output aus dem v312-Build lesen → wenn Appex-App-ID/Profil
  eine nicht-gewährte Capability verlangt oder App-ID/Team-Mismatch/Wildcard → Portal-Fix
  (Capability an com.echoelmusic.app.auv3 gewähren / Profil neu). Danach Gerät-Verify.
- **Review:** 2026-08-19.

### 2026-07-20 (KORREKTUR) AUv3 -3000: NICHT Launch-Denial — Host-Registry-Blindheit
- **Widerruft die frühere 2026-07-20-Entscheidung** ("appex signing/provisioning launch-denial").
  Adversarialer Grill (6 unabhängige Skeptiker, Workflow wf_dd99de9f) hat sie WIDERLEGT.
- **−3000 = invalidComponentID = Registry-FIND-Miss** (Komponente resolved NICHT in DIESEM Prozess),
  emittiert VOR jedem Extension-Launch. Ein launch-denied Appex würde später scheitern (−66748/−66749)
  oder in unseren 10-s-Timeout laufen (eigene Domain, nicht NSOSStatusErrorDomain). Falsches Stadium.
- **Symptom ist prozessweit** (0 Fremd-AUs von ALLEN Herstellern) → Fehler sitzt im HOST-Prozess,
  nicht in der Appex-Signatur (die kann nicht Moog/Imaginando verschwinden lassen). Own-Appex-−3000 =
  Spezialfall derselben Blindheit.
- **Unsaubere Annahme aufgedeckt:** "AUM listet EchoelBodyVibe → registriert" war NIE vom Founder
  bestätigt (vom "Morgen-Test" zu "Fakt" verhärtet). Ganze Launch-Denial-Erzählung stand darauf.
- **Rangliste lebende Theorien:** (1) Host-Prozess-Registry-Blindheit [stärkste] · (2) Appex-
  Registrierungs-Fehler/veralteter pluginkit-Eintrag (update-in-place nie durch clean-reinstall geklärt)
  · (3) iOS-cold-registry-quirk [teils selbst-widerlegend] · (4) ~~Launch-Denial~~ widerlegt.
- **Entscheidender Test (Founder, Gerät, kein Code/Build): AUM prime-then-rescan** — AUM öffnen/listen,
  prüfen ob eigene Appex namentlich drin, zurück zu Echoel → Rescan. Trennt Host-Blindheit vs
  Registrierungs-Fehler + testet die unbestätigte "AUM-listet"-Prämisse. KEIN Portal-Change auf Verdacht.
- **Code-Fix (ca98371):** Diagnose ehrlich (resolve-miss statt "appex unregistered", prime-then-rescan
  statt blind-reinstall) + Build-Stamp in jeder Scan-Zeile (try N → Build eindeutig). Reviewer 0 Defekte.
- **CI-Appex-Signing-Dump (c7e95b7) inspiziert das falsche Artefakt** (Appex statt Host) — nicht schädlich
  (non-blocking), aber nicht entscheidend; bleibt als Appex-Signatur-Entlastung nützlich.
- **Review:** 2026-08-19.

### 2026-07-20 (KORREKTUR 2) AUv3 Fremd-Discovery: inter-app-audio-Entitlement IST der Gate
- **Widerruft die "IAA = red herring"-Note.** Fokussierte Tiefen-Recherche (Apple DevForums
  127481 + 89762, EXAKTES Symptom "AVAudioUnitComponentManager liefert nur Apple-AUs, 0 Fremd"):
  seit iOS 11 gatet die **inter-app-audio-ENTITLEMENT** die Fähigkeit eines Prozesses, Fremd-
  Audio-Komponenten überhaupt zu SCANNEN. Ohne sie → nur Apple-Builtins (genau Echoels Symptom).
  Das IAA-*Protokoll* ist deprecated, die *Entitlement* gatet das Scannen weiter.
- **Zwei SEPARATE Symptome, früher fälschlich vermengt:** (1) 0 Fremd-AUs = fehlende IAA-
  Entitlement [fixbar]. (2) eigene Appex −3000 = separates pluginkit/Signing-Problem [andere Spur].
  Die Session-Timing-These ist widerlegt (Session ist vor jedem Scan aktiv, per Launch-Sequenz).
- **Zustand:** `inter-app-audio` STEHT in Echoelmusic.entitlements (L41), wird aber beim Signing
  RAUSGESTREIFT — automatisches Signing kann nur Capabilities provisionieren, die die App-ID im
  Portal bereits aktiviert hat, und com.echoelmusic.app hat "Inter-App Audio" NICHT aktiviert.
- **FIX (Founder-Portal-Aktion, EVIDENZBASIERT nicht auf Verdacht):** "Inter-App Audio"-Capability
  auf der App-ID com.echoelmusic.app im Developer-Portal aktivieren → neu archivieren → Signing
  behält die Entitlement → Prozess kann Fremd-AUv3 enumerieren. CI-Step (testflight.yml) meldet
  jetzt PRESENT ✅ / STRIPPED ❌ mit genau dieser Fix-Anweisung.
- **Rest-Unbekannte:** ob Apple die Capability auf iOS 18 noch anbietet/honoriert (IAA seit iOS 13
  deprecated). Test ist billig: aktivieren → CI meldet PRESENT → deployen → Founder scannt. Wenn
  Fremd-AUs erscheinen = GELÖST. Wenn nicht hinzufügbar = definitiv ausgeschlossen.
- Code-seitig bereits erledigt: Registration-Notification-Observer + Re-Scan (Research-Ursache C).
- **Review:** 2026-08-20.

### 2026-07-20 KORREKTUR 3 — AUv3-Entitlement-Verdikt las das FALSCHE Artefakt (Archiv statt .ipa)
- **Auslöser:** v313/2421 CI-Diagnose meldete "inter-app-audio STRIPPED → Portal ändern".
  BEVOR ich das dem Founder als Handlung gab, geprüft: der Dump las
  `Echoelmusic.xcarchive/.../Echoelmusic.app` — das ist das DEVELOPMENT-signierte
  Archiv (`get-task-allow=true`, minimales Team-Profil). Dort fehlen healthkit,
  app-groups UND inter-app-audio ALLE — obwohl healthkit live shippt. Distribution-
  Entitlements werden erst bei `-exportArchive` angewandt. Also war das "STRIPPED"-
  Verdikt am falschen Artefakt gemessen und NICHT aussagekräftig für den Ship-Build.
- **Beinahe-Fehler:** hätte fast einen Portal-Change auf einem Fehlmesswert empfohlen —
  genau das "kein Portal-Change auf Verdacht", das der Founder verboten hat. Zweiter
  Über-Schluss in Folge (nach der Grill-Korrektur), diesmal VOR der Founder-Ansage
  gefangen.
- **Fix:** neuer non-blocking CI-Schritt liest die DISTRIBUTION `.ipa` NACH dem Export
  (das echte hochgeladene Artefakt), dumpt den VOLLEN Host-Entitlement-Satz und
  diskriminiert 3 Fälle: (a) IAA present → Scan-Gate offen, Rest = Host-Blindheit;
  (b) IAA absent ABER healthkit present → App-ID fehlt speziell Inter-App-Audio →
  Portal-Enable IST der Fix; (c) IAA UND healthkit absent → breiteres Provisioning-
  Problem, KEIN Portal-Change darauf. Alter Archiv-Schritt entschärft (nur noch
  roher Pre-Export-Dump, verweist aufs .ipa-Verdikt).
- **Status:** offen — nächster Deploy erzeugt das vertrauenswürdige Verdikt; ERST dann
  Founder-Ansage mit belegtem einzelnem Schritt.

### 2026-07-20 #1 Automation-in-Spur: Option C (precision editor → document.automation), staged S1→S2→S3
- **Founder #1 (REIHENFOLGE):** "Automation in der Spur (im Clip UND clip-übergreifend, alle
  Parameter via EchoelParameterRegistry)." Mandat: ERST PLAN + Council.
- **Befund:** #1 ist zu 90% gebaut — ClipAutomationView (im Clip), TimelineAutomationRow
  (song-wide, document.automation, persistiert+gespielt), Registry-Targets + per-Track
  (track.<laneID>.<base>). DIE Lücke = der Präzisions-Editor `AutomationView` editiert die
  DISKONNEKTIERTE Loop-Schicht (AutomationPlayer.lanes, 1 Takt, masterLevel-default), und
  `.automation` trägt keinen Parameter/Track-Kontext. → getippte Wert/Kurve/Bend-Edits
  persistieren/spielen nicht mit dem Song. Der eine echte Funktionsbug.
- **Council:** Option C (Editor auf document.automation umhängen, Fläche behalten) vor D
  (Editor-Tür löschen, Präzision in die Row falten = mehr Arbeit) und A/B (Loop-Layer
  rausreißen = Playback-Spine anfassen, nein). Store-Spine existiert schon (add/move/remove).
- **Slices:** S1 (pur, getestet, 0 Geräterisiko) Store-Parität setValue/setCurve/setCurvature/
  clearAutomation → S2 (gerätegated) Modal-Payload `.automation(parameter:,laneID:)` am
  BESTEHENDEN Case (keine neue Sheet), Canvas song-absolut, seed auf Parameter → S3
  (gerätegated) Loop-Layer-Editorpfad aufräumen.
- **Gate: proceed** — S1 GEBAUT+committet (813aab4), Reviewer 0 Defekte. Golden: Row-Store +
  Loop-Dispatch unverändert. Verify (S2, Gerät): in Row zeichnen → Präzision öffnen → SELBE
  Kurve, getippt persistiert+spielt.
