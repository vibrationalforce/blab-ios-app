# Preferences

User preferences for development workflow, communication, and tooling.

## Development Style
- **Protocol:** Ralph Wiggum Lambda -- one fix per cycle, no batching
- **Commits:** Conventional commits (feat:, fix:, docs:, etc.)
- **Testing:** TDD when adding new functionality
- **Logging:** os_log only, never print()
- **Concurrency:** Swift 6 strict concurrency, async/await + @MainActor

## Communication
- **Tone:** Direct, no filler, no emojis unless requested
- **Answer-first / brief (2026-06-30):** founder shared a `/brief`-style command carousel
  ("Shortest possible answer. No fluff. No preamble. Just the answer."). Lead with the
  result/fix, minimal process narration. Report fixes, not the journey. Short replies.
- **Science only:** No esoteric terminology, evidence-based claims only
- **Branding:** "Echoelmusic" -- never "BLAB" or "Vibrational Force"

## Tooling
- **CI:** GitHub Actions (testflight.yml primary)
- **Build:** Tuist + Fastlane + Codemagic
- **Dependencies:** Zero external dependencies policy
- **SDK Target:** iOS 26 (deadline April 28, 2026)

## Session Workflow
- Read scratchpads/SESSION_LOG.md and memory/ at session start
- Update memory/ at session end with new discoveries
- 4-phase workflow: Plan -> Implement (TDD) -> Verify -> Ship

---

## Observed (2026-06 session) — demonstrated working preferences
- **Honesty over cheerleading.** Explicitly asks "Überleg mal ehrlich" / "ehrlich". Wants the real state, including "I never ran it / can't verify from sandbox," not green-washing. Green CI ≠ works.
- **Strong delegation / autonomy.** Repeatedly says "du entscheidest", "mach alles", "Loop Mode". Prefers me to decide + act + verify rather than ask — but still wants honest checkpoints before outward-facing/irreversible steps.
- **Fahrplan discipline:** `docs/dev/FEATURE_MATRIX.md` is the roadmap (code-truth). The website MIRRORS code, never drives it ("if the website disagrees, the code wins"). Avoid marketing-driven overclaiming.
- **Brand purity (hard):** never "wellness"/"meditation"/"healing"/"16K"/"Super Intelligence AI" overclaims in user-facing copy (App Store, Info.plist, website). Biofeedback is core, NOT wellness. Use "self-observation, not medical diagnosis".
- **CI-verified, not blind:** every change verified via `testflight.yml` (compile_check or full ship) before trusting it. Don't blind-build unverifiable things (watch embed, camera concurrency) — architect + flag for a device session instead.
- **SDK doctrine:** speak open standards (AUv3/MIDI/OSC/Link/Art-Net), depend on almost nothing; vendor SDKs only behind an explicit logged decision.

### Drift to confirm (memory above may be stale)
- Build pipeline is **GitHub Actions `testflight.yml`** (pure xcodebuild + ASC API key), not Codemagic. macOS=Catalyst decided.
- Deployment floor is **iOS 18** (CLAUDE.md), not iOS 26.
- One sanctioned dependency (**HaishinKit**, RTMP) — not strictly zero.
- "12 EchoelTools" is a **taxonomy over real modules**, not 12 Swift types (see FEATURE_MATRIX).
- Note: user tolerates structured ✅/🔴 status emojis in chat despite the older "no emojis" line.

## Deployment (REMEMBER — confirmed by founder 2026-06-20)
- **No GitHub token is needed to deploy.** TestFlight is wired as a TOKENLESS deploy:
  bump `.deploy/release` (any edit) and `git push` → `testflight.yml` runs on that branch
  using App Store Connect credentials stored as CI-side GitHub repo secrets.
- **There is no upload limit to worry about** (founder: "es gibt kein Limit" — extra set up).
- Do NOT block on tokens or the MCP workflow-dispatch (403). Just bump `.deploy/release`.
