---
name: vision-gate
version: 1.0.0
description: |
  Score external inspiration (shared screenshots/carousels, repo links, deep-research
  findings, MCP/agent/tool ecosystems, "should Echoel do X too?") against the optimized
  Echoel vision, assign a tier (ADOPT-PRODUCT / ADOPT-PIPELINE / WATCH / REJECT), and log
  it — so the repo absorbs inspiration without diluting the vision. Use whenever the user
  shares external tools/repos/screenshots and asks whether to adopt them, or says "make
  the repo smart", "integrate this", "stay on vision". Proactively run it on any inbound inspo.
allowed-tools:
  - Read
  - Write
  - Edit
  - Grep
  - Glob
---

# Vision Gate — keep inspiration on-vision

**Principle: the vision is the filter, not the inbox.** Nothing is adopted because it
is impressive. Everything is scored against `memory/vision.md` and lands in a tier,
then logged so we never re-litigate and never drift.

## Procedure

1. **Read the vision** — `memory/vision.md` (tiers + 8 founder principles) and the
   existing ledger `memory/inspiration_intake.md` + `inspiration.csv` (don't re-evaluate
   an item already logged — point to its row).
2. **For each external input**, apply the gate. To be **ADOPT→PRODUCT** it must pass ALL:
   1. Serves a dimension — Body / Sound / Space / Light / Vibration / Data (or an explicit
      North-Star tier, labeled concept, never shipped copy).
   2. iOS-native feasible on iPhone — else tier it ROADMAP / NORTH STAR honestly.
   3. On-brand — no wellness/esoteric, no quantum/super-AI overclaim; open-standard
      preferred; accessibility-first; the code stays the truth.
   4. Realtime-safe — no threat to audio-thread sanctity or the single main beat clock.
3. **Assign a tier:**
   - **ADOPT→PRODUCT** — passes all four → enters the Ralph loop as exactly ONE
     feature/cycle (no batching). Also add a `decisions.csv` row if material.
   - **ADOPT→PIPELINE** — helps us build/test/market (dev tooling, agents, CI), never in-app.
   - **WATCH** — promising but not now; park with a review date. (Prefer this over premature adoption.)
   - **REJECT** — off-vision / overclaim / redundant; log the reason and close it.
4. **Log it** — append a row to `inspiration.csv` (`date,source,type,idea,pillar,verdict,
   rationale,review_date`) and a bullet under the dated section in
   `memory/inspiration_intake.md`. Default review_date = +90 days (sooner for WATCH).
5. **Report** to the user as a compact table: input → tier → one-line rationale, and name
   the single highest-value adoption (if any). Do NOT silently expand scope.

## Guardrails

- Banned overclaim is an automatic REJECT for any product/copy use: quantum AI, super-AI/
  AGI, wellness/healing/Solfeggio/chakra, "16K", BLAB/Vibrational Force/legacy soundscape.
- Far-future founder ideas (auto-driving, dive-flying, "revolutionize humanity") = NORTH
  STAR: keep parked in `memory/vision.md`, never leak into product copy.
- Most external dev/agent/web tooling is PIPELINE or WATCH — it rarely becomes a feature.
  The two patterns that already are our standard: skill-architecture + markdown memory.
- When the gate result would change the roadmap, surface it and get founder confirmation
  before committing scope.
