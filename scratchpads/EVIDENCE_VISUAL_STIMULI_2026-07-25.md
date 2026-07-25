# Evidence review — visual colour, stimuli, geometry: what is actually validated?

**Founder question (2026-07-25):** *"Gibt es bestimmte visuelle Farben, Stimuli oder
heilende geometrische Bilder, Heilzeichen etc? Alles validiert wirksam?"*

Short answer: **no.** Most of the "healing colour / sacred geometry" canon has no
validated effect. A small, specific set of visual mechanisms IS well evidenced, and
exactly one of them is something Echoel can honestly build on. This file records which
is which so the question does not have to be re-litigated.

Companion to `BioScienceInfo` (the in-app, cited, claim-free learn section) and to
`REPORT_SOUND_PAIN_EVIDENCE_2026-07-12.md` (the same exercise for sound).

---

## Verdict table

| Claim | Evidence | Verdict for Echoel |
|---|---|---|
| Sacred geometry (Flower of Life, Sri Yantra, Metatron's cube) heals / balances | None. No controlled trials. Cultural + spiritual tradition, not a clinical finding. | **REJECT** — and a repo red line (BLAB/Syng legacy) |
| "Heilzeichen" / Reiki symbols / Solfeggio-associated glyphs | None. Reiki trials that exist test touch/presence, not glyphs, and are largely null. | **REJECT** — plus App Store health-claim risk |
| Chakra colour maps (root=red … crown=violet) | None. The colour assignment is a 20th-century Western invention, not even consistent with its own source tradition. | **REJECT** |
| Colour psychology (red arouses, blue calms) | Weak and inconsistent. Small effects, strong context dependence, heavy publication bias, poor replication. | **NO CLAIM** — usable as taste, never as a promise |
| Circadian light (bright, ~480 nm-weighted, on the retina) shifts phase / alertness | **Strong.** ipRGC/melanopsin photoreception; Lucas et al. 2014 consensus; CIE S 026 melanopic metrics. | **TRUE but out of reach** — needs light *dose* over minutes–hours, not a phone screen showing a shape |
| Photic driving / SSVEP: a flickering stimulus produces a matching EEG response | **Strong as physiology** — it is the basis of SSVEP brain-computer interfaces. | **Structurally unavailable to us** (see below) |
| Flicker "entrainment" therefore improves mood / focus / healing | Weak, contested, mostly small uncontrolled studies. The EEG response is real; the clinical leap is not. | **NO CLAIM** |
| Paced breathing at ~0.1 Hz (resonance) raises HRV and lowers stress markers | **Strongest in our neighbourhood.** Lehrer & Vaschillo (resonance-frequency model); Goessl et al. 2017 meta-analysis (HRV biofeedback → stress/anxiety). | **ALREADY BUILT, honestly** — `BreathGuideView`, cited in `BioScienceInfo`, framed as self-observation |
| Mid-range fractal imagery (D ≈ 1.3–1.5) lowers physiological stress | Interesting, small samples, uneven replication (Taylor and successors). | **WATCH** — fine as an aesthetic choice, not as a claim |
| Slow, low-contrast, low-spatial-frequency motion reads as calm | Modest, mostly perceptual/affective-rating evidence. | **Taste, not therapy** — this is what our looks already do |

---

## The point worth remembering: our own safety law rules out the studied stimulus

Photic-driving research runs at roughly **4–20 Hz** — that is where the EEG following
response is strong. Echoel caps every visual oscillation at **3 Hz** (W3C WCAG 2.3.1,
epilepsy safety; enforced by `FlashGuard` and pinned by `FlashGuardTests`).

So the frequency band the literature actually studies is the band we deliberately refuse
to enter. Any future pitch of "brainwave entrainment visuals" runs straight into that
wall. This is not a limitation to engineer around — the cap stays, and a shipped visual
already violated it twice this week before the guard caught it (Rings at 5 Hz, the
heartbeat bloom's brightness swing). Treat 3 Hz as the constant and design inside it.

---

## What this leaves that is real, and buildable

1. **Paced breathing.** Validated, already shipped, already cited. The one place where a
   visual demonstrably changes a physiological measure.
2. **Sound↔image coupling.** No health claim needed — it is an *instrument* property, and
   it is the differentiator. Today it is measurably weak: note→colour latency ≈ 0.9 s, and
   `BioVisualParams` is **5/6 dead** (only `pulseHz` is read, so HRV never reaches the
   shader at all). Fixing those buys more expressive range than any new control would.
3. **Geometry as a LOOK, not as a symbol.** A radial/mandala-symmetric look can join the
   library (Rings · Water · Aurora · Depth) purely on aesthetics — with a plain name from
   our own vocabulary, no esoteric naming, no health framing, and a re-derived flash
   budget before it ships (see the honest-limits note in `FlashGuardTests`). That is
   marketable *and* safe.

## What must never ship

Chakra colour maps, Solfeggio, Reiki or "Heilzeichen" glyphs, "healing frequencies", or
any geometry named or sold as therapeutic. This is the pre-Echoel (BLAB/Syng) legacy the
repo already treats as a hard REJECT, and it is simultaneously the fastest route to an
App Store health-claim rejection. The brand line is unchanged: **biofeedback is core,
not wellness.**
