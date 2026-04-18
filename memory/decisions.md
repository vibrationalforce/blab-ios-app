# Decisions Log

Architectural and strategic decisions with context and rationale.

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
