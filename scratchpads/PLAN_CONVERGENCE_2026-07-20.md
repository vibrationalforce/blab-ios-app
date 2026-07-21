# PLAN — "Alles soll funktionieren" Convergence (Founder 2026-07-20)

Founder asked whether to rewrite the whole app (frustration, ~1 week stuck on small
tasks). Answer (with evidence): **NO — converge, don't rewrite.** A 4-axis multi-team
audit (workflow wf_4fea1932) found the app fundamentally sound: only ONE real functional
defect on a reachable surface, ZERO crash/freeze defects (freeze law clean, force-unwrap
free, guarded divisions, NaN clamped, env injection complete). The rest is copy +
accessibility polish. Founder axis: **function · accessible · brand fit.**

Deploy strategy: ACCUMULATE these fixes across cycles, then ONE batch deploy
("convergence pass") — avoid TestFlight thrash (30-60 min/build).

## Ranked worklist (execute one per Ralph cycle)

| # | Item | file:line | Effort | Device? | Status |
|---|------|-----------|--------|---------|--------|
| 1 | **Automation precision editor edits WRONG store** — the row "⋯" + lane "Automation" opens `AutomationView` bound to `AutomationPlayer.lanes` (loop layer, defaults to Master level) instead of `TimelineStore.document.automation`. User sees a blank/wrong editor, keyframes they drew are absent, typed values land in a layer that doesn't play. THE only real functional bug. | ArrangeTimelineView.swift:1207,1065 → AutomationView.swift:68 | L | yes | TODO (careful, next) |
| 2 | German "no sound" banner on HOME → English | ArrangeTimelineView.swift:565,573,595-597 | S | no | ✅ DONE 67b91b8 |
| 3 | Lane-head M/S/record chips "sub-AA touch target" | ArrangeTimelineView.swift:1230,1261 | S | no | ✅ DECLINED — chips 21×28 meet WCAG 2.5.8 AA (h28≥24; w21+3gap=24pt center = spacing exception). Audit's contentShape(-8) would overlap neighbors in the packed 3pt strip → worse. Not applied. |
| 4 | Secondary/unit text fails AA contrast (`dim` #e0e0e0@0.55 near floor on panel fills) | EchoelTheme.swift:20 | S | no | ✅ DONE 8553d64 — dim 0.55→0.65. Recomputed WCAG: on surface #0e0e12 ~5:1→~6.5:1 (clears 4.5 AA); light-on-dark everywhere so NO usage regresses. |
| 5 | Bio strip can't grow w/ Dynamic Type (hard `.system(size:)` + minScale 0.6 → shrinks to ~7pt) | BioStripView.swift:141 | M→L | **yes (sim/device)** | DEFERRED — NOT blind-safe. The 0.6 floor EXISTS to fit narrow phones (SE); raising it truncates ("…"), and a true fix = conditional reflow on sizeCategory, unverifiable without a build/sim (no local compiler). Do with a sim run, not blind. |
| 6 | German copy in Routing/EchoelLux sheet | PatchbayView.swift:126,187,196,206,208 | S | no | ✅ DONE d5775a1 |
| 7 | Esoteric attribution "Hans Cousto's Cosmic Octave" in shipping copy | EchoelStudioView.swift:2219; LightScienceInfo.swift:65 | S | no | ✅ DONE ec22fa5 |
| 8 | Root `.sheet` chain near metadata ceiling (GUARDRAIL, not broken) | EchoelStudioView.swift:690 | M | yes(launch) | STANDING — before ANY new modal there, consolidate to one `.sheet(item:)` enum. Do not append. |

## Honest read (answers the rewrite question)
Hardened core + a punch-list of S-effort surface fixes = a mature codebase nearing ship,
the OPPOSITE of a rewrite candidate. A rewrite would discard the encoded render-safety,
concurrency, and force-unwrap laws and reproduce the (environmental) AUv3 wall 1:1.

## AUv3 — PARKED
−3000 = invalidComponentID = registry find-miss; process-wide 0-third-party = host-side
blindness; scan query audited CORRECT (wildcard + per-type + full enum all return Apple-only)
→ NOT our code, environmental. No more cycles here. Founder device test (clean-install / AUM
prime-then-rescan / VPN & Device Management check) decides; no portal change on guess.
