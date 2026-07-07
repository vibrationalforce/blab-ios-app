# Meditation Coherence Algorithm — Deep Research Synthesis (2026-07-07)

Source: 105-agent deep-research harness (85 verified, 20 hit session limit),
23 sources, 80 claims extracted → 19 confirmed, 0 killed, 9 synthesized findings.
Founder ask: "wie muss der Algorithmus für Musik- und Visual-Generierung sein,
damit Meditierende über Biofeedback eine wahrhaftige Kohärenz-Erfahrung haben;
gestresste Menschen sofort in tiefen Entspannungs-/Bonding-Zustand."

## THE HEADLINE (what the evidence actually says)

Build the instrument around **slow tempo + paced slow breathing**, NOT any
"magic sound". Arousal tracks **tempo, not genre**. There is no magic track,
frequency, or sample — the physiology is driven by tempo and breath rate.

## REPLICATED (build on these — highest confidence)

1. **Music raises parasympathetic/vagal tone** — RMSSD, pNN50, HF power up;
   strongest for SHORT sessions ≤30 min. (2026 Frontiers meta-analysis, 24 RCTs,
   n=1295.) Target these HRV indices. LF/HF is a CONTESTED soft signal, not a
   clean sympathetic gauge (Billman 2013) — don't lean on it.
2. **Slow tempo = parasympathetic; fast = sympathetic.** Descend toward ~60 bpm.
   A tempo-DESCENT (180→150→120→90→60) specifically boosts vagal tone.
   (Meta-analysis + Bretherton 2019, n=58.) → **iso-principle: descend the tempo.**
3. **Arousal tracks TEMPO, not genre/style.** Faster tempo raises ventilation/
   HR/BP; breathing rate rises proportional to tempo. (Bernardi 2006, Heart/BMJ;
   corroborated Bernardi 2009, Watanabe 2015.) → **tempo is the primary lever.**
4. **Sympathetic arousal REQUIRES fast tempo AND fast breathing together.**
   Keeping breath slow prevents tempo-driven arousal. (Watanabe 2015, PLOS One,
   n=52.) → **a slow paced-breath layer is a SAFEGUARD that lets the music be
   lively without arousing the listener.**
5. **~6 breaths/min (0.1 Hz) maximizes HRV.** Resonance band 4.5–6.5 bpm (adults),
   most common ~5.5. (Shaffer & Meehan 2020, Frontiers; Lehrer/Vaschillo.) →
   **ship a fixed 0.1 Hz breath pacing default; optional per-user calibration later.**

## SINGLE-STUDY (credible, use with lighter weight)

6. **Interspersed near-silence** drops resp/HR/BP BELOW baseline — but largely a
   CONTRAST/REBOUND effect (silence most relaxing when it FOLLOWS more-arousing
   material). (Bernardi 2006, "the importance of silence".) → periodic gentle
   near-silent dips, especially after a swell.
7. **Music-engineered breathing works:** a 0.1 Hz amplitude-modulation layer
   slowed listeners' breathing; a rate fixed at **75% of the user's baseline
   breathing rate** produced the LARGEST slowing; EDA/HR/EEG all fell.
   (Leslie/Picard 2019, MIT Media Lab, ACII, n~25.) → the breath swell is an
   **amplitude/brightness modulation** on the pad; personalize toward 75%-baseline.
8. **HRV-biofeedback slow breathing reduces stress/anxiety/depression** in adults;
   FIXED 0.1 Hz ≈ individualized RF training. (Sci Reports 2026 RCT, N=88, medium
   conf — nature.com 403'd, corroborated via search.)

## REFUTED / DEFLATED (do NOT build claims on these)

- **"Weightless" (Marconi Union) as uniquely relaxing** — NO heart-rate advantage
  over silence or other sounds; WORSE than silence on respiration. (Shepherd 2023,
  Psych of Music, N=57.) Never market a single "most relaxing" track.
- **Binaural beats** — overclaimed/unresolved; a 2025 perioperative meta-analysis
  claims large anxiety effects but this stayed UNVERIFIED here and is widely
  considered overclaimed in general relaxation. Do NOT build product claims on them.
- **LF/HF ratio** — contested as a sympathetic index.

## NOT COVERED (open — evidence did NOT return verified answers; do not fabricate)

- **Timbre / spectral tilt / attack softness / mode / harmony / drone-vs-melody /
  dynamic range** — none survived verification. Our drone/soft choices are
  AESTHETIC (founder-led), legitimately, but NOT "evidence-backed" — don't claim so.
- **Nature sounds / pink-white noise / singing bowls** — traditional-use-only here;
  no replicated verification returned. Frame as aesthetic, not clinical.
- **Visual parameters** (motion speed, low spatial frequency, blue-green hue,
  fractal D~1.3–1.5) — ALL landed in the unverified set (infra errors). The
  fractal-D~1.4-for-calm and "complexity raises engagement not relaxation" claims
  are UNVERIFIED, not confirmed. Re-research before claiming.
- **Open-source/CC0 sample libraries** — NOT researched as a set. BUT one hard
  lead surfaced: **VCSL (Versilian Community Sample Library, github.com/sgossner/VCSL)
  is CC0** (public domain, zero attribution) — a clean candidate for a commercial
  iOS app. Needs a dedicated licensing/sourcing pass before shipping any sample.

## ENGINEERING RECIPE (numbers an implementer can use)

| Lever | Value | Evidence |
|---|---|---|
| Target tempo | descend toward **~58–60 bpm** | REPLICATED (dir) + single-study (descent) |
| Tempo = arousal lever | slow it; genre is secondary | REPLICATED |
| Breath pacing | **6 breaths/min = 0.1 Hz** (10 s/cycle; ~5 s in / 5 s out) | REPLICATED |
| Resonance band | 4.5–6.5 bpm; personalize toward 75% of baseline breath rate | REPLICATED / single-study |
| Breath layer form | slow **amplitude + brightness swell** at 0.1 Hz | single-study (MIT) |
| Silence | periodic gentle near-silent dips after a swell | single-study |
| Session length | keep the strong window ≤30 min | REPLICATED |
| Don't | market a magic track; claim binaural/medical benefit | REFUTED |

## HOW WE APPLY IT (Echoel)

1. **selfObservation → true drone** (leadDensity 0, softer/wider) so the timbre is
   coherent and STILL at start (founder: "sphärisch und beruhigend", "kohärentes
   Timbre am Start"). AESTHETIC choice, arousal-consistent.
2. **0.1 Hz breath-swell** modulation on the pad amplitude/brightness — the
   coherence core (replicated). ~10 s cycle. This is also the arousal SAFEGUARD.
3. **Tempo descent** toward ~58 bpm over the first minutes (iso-principle).
4. **Genre + Sound settings** (founder: individual preferences matter hugely) —
   surface, next cycle. Individual preference IS consistent with the evidence
   ("no magic sound; tempo is the lever") — let users pick the world, we keep the
   tempo/breath physiology underneath.
5. **CC0 samples (VCSL etc.)** — separate sourcing/licensing pass before shipping.
6. **Visuals calmer** — motion down; but frame as aesthetic (visual evidence
   unverified), re-research before any calm-claim.

## HONESTY GUARDRAIL

Claim only tempo/breath/parasympathetic (replicated). Do NOT claim singing bowls,
binaural beats, nature sounds, specific frequencies, or "most relaxing" — those
are aesthetic or refuted. No medical claims (self-observation, not diagnosis).
