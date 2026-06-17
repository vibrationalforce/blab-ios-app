# PLAN — Echoel Creative Expansion: agent-tools, realtime media, "physical AI"
Date: 2026-06-17 · Branch: claude/piano-roll-clip-view-wozlie
Basis: deep research (cited) + file-grounded feasibility/architecture audit.

## 0. Founder ask
Saw agent-tooling repos (Superpowers, Remotion `skills`, Agent Browser, Claude skills/MCP/agents). Wants Echoel to "do all that too" across music arrangement · film/video edit · video-AI · visual · light/laser/mapping · holographic · content · live broadcast. Asks if we're "further with physical/quantum/super AI". Wants: healthy stable architecture, realtime feeling everywhere, a better Echoel version, and more repos/skills/MCP/agents to adopt.

## 1. Deep-research verdict (cited)
- **Anthropic "Claude for Creative Work" (Apr 2026): 9 MCP connectors** — Ableton, Resolume Arena/Wire (live VJ), Splice, Blender, Adobe, Autodesk, Affinity, SketchUp. + Higgsfield MCP (Kling/Veo/Seedance/Flux video gen), music MCPs (Ableton MIDI Remote, ElevenLabs, FFmpeg, Whisper). 10k+ MCP servers mid-2026.
- These are **MCP/desktop/agent-side** — open standard, vendor-built. **Not embeddable in an iOS app.**
- **On-device AI**: Apple **Core AI** (WWDC 2026, replaces Core ML) + MLX; real-time MIDI→expressive synth (~150ms). Echoel DDSP/BioComposer already on-device generative.
- **Physical AI**: $81B (2026); = sense/reason/act in the physical world. Echoel = embodied/physical-computing creative AI → **defensible**. **Quantum AI / super-AI = not applicable, banned overclaim.**
- **iOS realtime media feasible natively**: NDI HX3 (~50ms/4K), RTMP/SRT (HaishinKit), Syphon/Spout, Resolume/MadMapper mapping, Amazon IVS broadcast SDK. "Holographic" = projection/gauze/Pepper's-ghost, not literal.

## 2. Honest feasibility split (file-grounded)
### Shared repos = PIPELINE-ONLY (build/test/market, NOT in-app)
- Remotion → render promo/social reels on CI (`remotion-best-practices` skill already installed).
- Playwright/agent-browser/gstack → E2E + visual QA of docs/ site.
- Superpowers → dev shell (minor).
- **Claude skills/agents/MCP (already in repo) = our real moat** (audio-thread/dsp/bio-safety reviewers, protected-triad SKILL.md). Keep investing.
Reframe: Echoel is the **bio-source/instrument**; the MCP connectors are agent **controllers**. Complementary — an agent can drive Ableton/Resolume while the body (Echoel) is the live input. "Do all that too" = use them to ship/market faster, not embed.

### In-app native reality (file:line)
| Area | Status | Evidence |
|---|---|---|
| Music arrangement | ✅ SHIPPABLE/done | PatternEngine 8×16 + piano roll + clips + BioComposer |
| Light / laser / mapping-out | ✅ LIVE (strongest non-audio) | ArtNetSender, SACNSender, ADMOSCSender (native, tested) |
| Video / film edit | ROADMAP, ~0 wired | only CameraCapture/Analyzer (rPPG); no VideoRecorder/ClipTrimmer |
| Visual | PARTIAL/weak | only SwiftUI Canvas (BioVisualView); **NO Swift Metal at all**; .metal shaders orphaned |
| Broadcast (RTMP) | NOT wired (despite authorized) | HaishinKit 0 refs in Sources/ |
| Video-AI / holographic | ROADMAP | no CoreML, no visionOS code |
| On-device "AI" | PARTIAL, honest | OnDeviceModelGate (iOS26, never cloud) + deterministic fallback |

## 3. Architecture & realtime health (founder's priority)
**Audio realtime is healthy & disciplined** — EngineBus (snapshot + SPSC), exemplary render drains (pre-alloc, no locks), single main-queue beat clock (load-bearing — moving it caused real SIGTRAPs 1769/1777). Keep `.claude/rules/swift-audio.md` sacred.
**#1 risk = main-actor overload**: beat clock + 10Hz bio polls + ALL SwiftUI @Observable + the Canvas visual already share main. Adding a 2nd heavy main consumer (video preview, NLE scrub, main-driven Metal) WILL starve the clock.
**Safe pattern for heavy media:** GPU on its own MTLCommandQueue + CADisplayLink reading bus.latestBio snapshot; video/RTMP on dedicated AVCapture/VideoToolbox queues + separate ring buffer off the master tap; new SPSC topics not new drains; never the audio/main render path.

## 4. Physical-AI framing (honest copy)
USE: "bio-reactive, embodied / physical-AI instrument — your body drives on-device generative music, light, space and vibration in real time; privacy-first, open-standard, no cloud."
DO NOT USE: quantum AI, super AI/AGI, wellness/healing/Solfeggio/chakra.

## 5. Ranked next steps
**Pipeline (low risk, adopt now):** (1) keep/extend Claude agent fleet; (2) Remotion promo reels; (3) Playwright/gstack site QA.
**In-app (pick ONE foundational realtime track, build it right):**
- **Option V — Metal visual renderer** (greenfield, CADisplayLink + own MTLCommandQueue, reads EngineBus). Most visible "realtime feeling"; establishes the GPU architecture that video/mapping/holo/broadcast-overlay all reuse; hosts the orphaned shaders. Higher effort (greenfield).
- **Option B — RTMP live broadcast via HaishinKit** (audit's pick: authorized dep, biggest marketing↔code gap, no greenfield GPU; dedicated VideoToolbox queue + ring buffer). Ships "live broadcast" credibly with camera+audio.
- **Option D — doc-accuracy + small wins**: correct FEATURE_MATRIX (cites deleted MetalBioView/BioVisualRenderer); finish sub-bass; tidy. Lowest risk.

**Recommendation:** ship sub-bass (in flight) → adopt Remotion pipeline (cheap) → then **Option V (Metal visuals)** as the foundational in-app realtime dimension, because "visual" is central to the multidimensional vision and it lays the correct GPU groundwork everything else (mapping/holo/video/broadcast overlay) builds on. (RTMP is a strong alternative if "live broadcast" is the priority.)

## 6. Open decision for founder
Which foundational in-app realtime track first: **Metal visuals (V)** vs **RTMP broadcast (B)** vs **doc-accuracy/small wins (D)**?
