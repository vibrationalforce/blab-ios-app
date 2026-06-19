---
name: echoel-marketing
version: 1.0.0
description: |
  Echoel-tuned front door to the vendored Corey Haines marketing skill pack
  (.claude/skills/marketing/, MIT). Use whenever the user wants to market Echoel —
  App Store listing/ASO, website copy (docs/), launch, pricing, social/video,
  PR, SEO, positioning, lead capture, email. Routes to the right underlying
  skill, applies an iPhone-instrument priority order, and HARD-ENFORCES Echoel's
  brand guardrails so no generated copy goes off-vision.
allowed-tools:
  - Read
  - Write
  - Edit
  - Grep
  - Glob
  - WebFetch
  - WebSearch
---

# Echoel Marketing — optimized router over the vendored skill pack

The repo vendors Corey Haines' MIT marketing skills at
`.claude/skills/marketing/skills/<name>/SKILL.md` (45 skills) + shared
integration docs at `.claude/skills/marketing/tools/`. This skill is the
**Echoel-optimized entry point**: it picks the right one, in the right order for
*an iPhone-first bio-reactive instrument sold on the App Store + a GitHub-Pages
site (`docs/`)*, and keeps every output on-brand. Read the chosen underlying
`SKILL.md` and follow it, filtered through the guardrails below.

## Non-negotiable brand guardrails (apply to ALL marketing output)

These OVERRIDE anything in the vendored skills. Any draft that violates them is wrong.

- **Banned terms — never in user-facing copy:** "BLAB", "Vibrational Force",
  wellness/therapy/healing/soundscape framing, "healing frequencies", chakras,
  Solfeggio, quantum/super-AI/AGI overclaim, "16K". Biofeedback is **science-based
  modulation**, not wellness.
- **Identity:** Echoel is **the instrument** — "Physical Computing · Biofeedback ·
  Multimedial & Multidimensional", the bio-reactive *source* for immersive media
  (open standards: ADM-OSC, MIDI 2.0, OSC, BLE HRS). Not a renderer, not a
  competitor clone. Tagline: "multidimensional production instrument".
- **No false promises:** claim only what ships (see `docs/dev/FEATURE_MATRIX.md`
  and CLAUDE.md "Absent"). RTMP/streaming, video capture, multitrack = roadmap,
  not shipping. Don't market unreleased features as live.
- **Accessibility-first**, American English, evidence-based. Respect health/safety
  copy rules (self-observation not medical diagnosis; max-3Hz flash). For any
  bio/health claim, defer to the `bio-safety-reviewer` agent.

## Echoel priority map (which vendored skills matter, in order)

1. **App Store first** — `aso` (the listing IS the storefront), `copywriting`,
   `copy-editing`, `cro`, `launch` (TestFlight → App Store).
2. **Website (`docs/`)** — `seo-audit`, `ai-seo`, `schema`, `site-architecture`,
   `content-strategy`, `programmatic-seo`.
3. **Positioning & offer** — `product-marketing`, `marketing-psychology`,
   `offers`, `pricing` (paid app, not B2B SaaS — adapt accordingly).
4. **Reach** — `social`, `video`, `public-relations`, `community-marketing`,
   `co-marketing`, `directory-submissions` (App/AI directories).
5. **Funnel** — `emails`, `lead-magnets`, `free-tools`, `signup`, `onboarding`,
   `popups`, `referrals`, `analytics`, `ab-testing`, `customer-research`,
   `competitor-profiling`, `competitors`.
6. **Low relevance for a solo consumer-app founder (use only if asked):**
   `revops`, `sales-enablement`, `prospecting`, `cold-email`, `sms`,
   `churn-prevention`, `paywalls` — these assume a B2B SaaS sales motion Echoel
   doesn't have; treat as reference, don't force-fit.

## Procedure

1. **Map the ask** to one (or a short sequence) of the skills above. If the ask
   is broad ("market Echoel"), start at App Store + website, not everything.
2. **Read** the chosen `.claude/skills/marketing/skills/<name>/SKILL.md` and its
   `references/`; follow it, but rewrite every line through the guardrails.
3. **Ground in the repo** — pull real facts from `memory/vision.md`,
   `docs/dev/FEATURE_MATRIX.md`, `docs/` site, CLAUDE.md before inventing claims.
4. **Significant marketing moves** (a launch, a pricing change, a positioning
   shift, anything published externally) → run `the-council` + `vision-gate`
   first; external publishing is hard to reverse.
5. **Deliver** the artifact (copy, audit, plan) and say which underlying skill it
   used. Don't bulk-run the whole pack; one job at a time (Ralph loop spirit).

## Notes

- Vendored pack is **PIPELINE** tooling: it helps market the app, it is **never
  shipped in-app** and never touches `Sources/`. Upstream attribution + MIT
  license: `.claude/skills/marketing/LICENSE`, `UPSTREAM_README.md`.
- Some skills reference third-party integrations in
  `.claude/skills/marketing/tools/` — those are external paid services; suggest,
  don't assume the founder uses them.
