# Research: Sound → Color / Light Translation for a Bio-Reactive iOS Instrument

Date: 2026-06-20
Author: research agent (web-cited)
Scope: physics + color science + perception + biofeedback visualization, with an
adversarial "established vs contested" split and concrete engine recommendations.

> Network access WAS available. All claims below carry inline source URLs. Where a
> source is a vendor/wiki/forum rather than a peer-reviewed paper, it is flagged.

---

## TL;DR for the color engine

1. The "multiply audio Hz by 2^40 to reach visible light" trick is **arithmetically
   real but physically meaningless as an analogy** — use it (if at all) as an artistic
   convention, never as a scientific claim. Audio spans ~10 octaves; visible light spans
   barely ~1 octave, so the two ranges are not structurally comparable.
2. For wavelength→sRGB, **CIE 1931 color-matching functions (CMFs) → XYZ → sRGB with
   gamut clamping is the accurate path**; Dan Bruton's piecewise approximation is fine
   for a fast "looks-right" spectrum but is not colorimetrically correct.
3. Map **pitch-class to hue through OKLCH (perceptually uniform), not raw wavelength or
   HSV**, so the 12 chromatic steps look evenly spaced and animate without hue drift.
4. The visible spectrum is a **line, not a loop**; the violet→red bridge (magenta /
   "line of purples") is **non-spectral** and must be synthesized. A perceptual hue
   circle (OKLCH hue 0–360) closes the loop cleanly — this is the right tool for
   octave-equivalent pitch-class → hue.
5. Only a **few** cross-modal correspondences are robust enough to hard-code: higher
   pitch → lighter / brighter, louder → bigger / more salient. Specific
   pitch→hue mappings are **idiosyncratic / synesthete-specific** — expose as a preset,
   don't bake in.
6. For chords/spectra, **don't sum in RGB** (washes to white). Mix amplitude-weighted in
   a perceptual space, cap the number of partials, and treat saturation/chroma as a
   dispersion measure (consonant/narrow = saturated, noisy/broad = desaturated).
7. For HRV coherence, the validated signal is **a smooth, sine-like ~0.1 Hz oscillation
   (≈5.5–6 breaths/min) and heart–breath phase-locking**. Visualize as smoothness /
   order / symmetry, slow and breath-paced. Respect **WCAG 2.3.1: nothing flashes >3×/s**.

---

## Q1 — Octave-analogous sound→light translation (PRIORITY)

### The arithmetic (confirmed)
- Speed of light c = 299,792,458 m/s ≈ 2.998e8 m/s (exact, by SI definition).
  ([UCAR](https://scied.ucar.edu/learning-zone/atmosphere/visible-light),
  general physics)
- Visible band: ~380–760 nm ≈ ~790–395 THz; commonly cited as ~430 THz (red) to
  ~750 THz (violet).
  ([byjus](https://byjus.com/physics/the-electromagnetic-spectrum-visible-light/),
  [UCAR](https://scied.ucar.edu/learning-zone/atmosphere/visible-light),
  [Wikibooks](https://en.wikibooks.org/wiki/Electromagnetic_radiation/Visible_light))
- A440 × 2^40 = 440 × 1.0995e12 ≈ **4.84e14 Hz = 484 THz** → lands in green/cyan.
  So ~40 doublings is the correct order of magnitude to lift audio into the visible band.
  (computed; consistent with the sources above)

### Is it physically sound?
**No, not as a physical equivalence — only as a chosen mapping convention.** The
spectrum sources are explicit that the analogy breaks down:
- Humans hear ~10 octaves; the visible spectrum is **less than one octave** (highest
  visible frequency is only ~2× the lowest).
  ([Physics Van / Illinois](https://van.physics.illinois.edu/ask/listing/2048),
  [Quora discussion](https://www.quora.com/Sound-has-octaves-Does-light))
- Doubling a visible frequency takes you straight out of the visible range (430 THz → 860
  THz = UV). So "octave equivalence," central to pitch, has **no visual counterpart** —
  there is no second visible octave to map onto.
  ([Physics Van](https://van.physics.illinois.edu/ask/listing/2048))
- Sound and light are different phenomena (mechanical pressure waves vs. electromagnetic
  radiation); the "octave" correspondence is numerical, not a shared physical mechanism.
  ([Physics Van](https://van.physics.illinois.edu/ask/listing/2048))

### Prior art (and where it goes wrong)
- Newton (Opticks, 1704) forced the spectrum into **seven** colors to match the seven
  diatonic notes — an aesthetic/numerological choice, not an observation; he also bent
  the line into the first color wheel.
  ([Wikipedia: Line of purples](https://en.wikipedia.org/wiki/Line_of_purples),
  [ColorSift](https://colorsift.com/articles/magenta-color-doesnt-exist-design-secret-weapon),
  [ResearchGate fig](https://www.researchgate.net/figure/Newtons-suggested-analogy-between-the-seven-musical-notes-and-the-seven-spectral-hues_fig1_360467871))
- Scriabin's color-keyboard ("Prometheus") is often cited as synesthesia but was a
  **constructed system** based on Newton + Theosophy/Blavatsky mysticism; scholars doubt
  he was actually synesthetic.
  ([Wikipedia/Scriabin context via search](https://jimtheobscuredotcom.wordpress.com/2012/11/16/alexander-scriabin-1872-1915-musical-colour-wheel/),
  [Interlude](https://interlude.hk/extraordinary-splashes-colour-music-synaesthesia/))

### CONTESTED / pseudoscientific (note, do NOT endorse)
- **Hans Cousto's "Cosmic Octave"** (Die kosmische Oktave, 1978): octave-doubles
  planetary orbital periods up into audible (and onward to color) frequencies. The
  mapping is just repeated doubling of a proportion; sources stress these are
  **translations, not transmissions** — no planet emits a note, and the health/"resonance"
  claims are dismissed as pseudoscience.
  ([Planetware (proponent)](https://www.planetware.de/octave/),
  [Sound Medicine Academy: "Cosmic Healing or Marketing Myth?"](https://www.soundmedicineacademy.com/pages/sound-healing-blog/healing-with-the-planetary-frequencies),
  [Harmonance (proponent)](https://harmonance.com/resources/a-comprehensive-guide-to-planetary-frequencies-the-symphony-of-celestial-bodies))
- **432 Hz / Solfeggio / chakra-frequency** mappings: 432 Hz is just a reference-pitch
  choice; "cosmic/DNA/Schumann 7.83 Hz" links require rounding and cherry-picking and
  are pseudoscience.
  ([This Week in Science](https://thisweekinsciencenews.com/blog/2026/03/23/432-hz-tuning-history-health-claims-and-what-science-really-shows/))

**Recommendation:** if you offer an "octave lift to light" mode, label it clearly as an
artistic mapping, keep esoteric terms out of UI (per brand rules), and prefer the
pitch-class→hue-circle approach (Q4) which is perceptually honest.

---

## Q2 — Wavelength → sRGB best practice

- **Most accurate / well-regarded:** single wavelength → CIE 1931 **color-matching
  functions** → XYZ tristimulus → linear sRGB (matrix) → clamp/scale into gamut →
  gamma-encode. CIE 1931 is the standard mathematical model of human color perception
  (CIE, 1931).
  ([Baeldung: Converting Light Frequency to RGB](https://www.baeldung.com/cs/rgb-color-light-frequency),
  [sqlpey survey of methods](https://sqlpey.com/algorithm/methods-for-wavelength-to-rgb-color-conversion/))
- Monochromatic wavelengths sit **on the spectral locus**, which is largely **outside the
  sRGB gamut** — you must desaturate/clip toward white or scale, so even the "correct"
  method approximates on a display.
  ([Baeldung](https://www.baeldung.com/cs/rgb-color-light-frequency))
- **Dan Bruton's algorithm** (Texas A&M; from a Fortran spectrum program) is a piecewise-
  linear approximation with intensity falloff at the ends. It is fast and "looks like a
  rainbow" but is **not** the CIE CMFs — boundaries are subjective, and it skews red at
  the extremes.
  ([Bruton via Eureca](https://www.eureca.de/5116-1-Bruton-color-mapping.html),
  [rsmith-nl implementation](https://github.com/rsmith-nl/wavelength_to_rgb),
  [sqlpey](https://sqlpey.com/algorithm/methods-for-wavelength-to-rgb-color-conversion/))

**Recommendation:** Precompute a 380–780 nm → sRGB lookup table once at startup using the
CIE 1931 CMFs (tables are public-domain), with explicit gamut handling. This is accurate,
audio-thread-safe (table read only), and avoids per-frame matrix math. Use Bruton only if
you want the stylized, slightly redder "physics rainbow."

---

## Q3 — Perceptually uniform color spaces for the hue mapping

- Perceptually uniform spaces (CIELAB, CIELUV, OKLab, CAM16-UCS) arrange colors so equal
  perceived differences are equal distances — better than HSV/raw wavelength.
  ([Wikipedia: Oklab](https://en.wikipedia.org/wiki/Oklab_color_space),
  [mohanvadivel](https://mohanvadivel.com/thoughts/perceptual-uniform-color-space))
- **CIELAB**: has hue-linearity flaws, notably a **blue→purple shift** when only
  lightness/chroma change.
  ([Wikipedia: Oklab](https://en.wikipedia.org/wiki/Oklab_color_space))
- **OKLab/OKLCH** (Björn Ottosson, 2020): predicts lightness/chroma/hue well, is simple,
  numerically well-behaved, fixes the blue region, and **OKLCH is the polar form** (hue
  angle + chroma) — ideal for a hue wheel. CSS adopted OKLCH as a recommended interpolation
  space for gradients / color-mix().
  ([Ottosson "A perceptual color space"](https://bottosson.github.io/posts/oklab/) — note: 403 on fetch, but widely mirrored;
  [Wikipedia: Oklab](https://en.wikipedia.org/wiki/Oklab_color_space),
  [colors.jarhalab OKLCH](https://colors.jarhalab.com/wiki/oklch-color),
  [Color.js spaces](https://colorjs.io/docs/spaces))
- **CAM16-UCS**: very good fit to Munsell data but **complex, numerically unstable, not
  always invertible**, and aggressively compresses chroma — interpolation desaturates too
  fast. Overkill / fragile for real-time animation.
  ([Wikipedia/Color.js discussion via search](https://colorjs.io/docs/spaces),
  search synthesis)
- For interpolation specifically: CIELAB/CIELUV/HSV drift toward purple; CAM16
  desaturates; **OKLab interpolates most evenly**.
  ([Wikipedia: Oklab](https://en.wikipedia.org/wiki/Oklab_color_space))

**Recommendation:** Use **OKLCH** as the working space for hue mapping and all color
blends/animations. Best accuracy-for-cost; stable; gradient-friendly; designer-legible.

---

## Q4 — Non-spectral magenta / "line of purples" — closing the loop (PRIORITY)

- The **line of purples** is the edge of the chromaticity diagram between extreme red and
  extreme violet. Every point on it (except the endpoints) is **non-spectral**: no single
  wavelength produces it — only a mixture of long + short wavelengths.
  ([Wikipedia: Line of purples](https://en.wikipedia.org/wiki/Line_of_purples))
- Magenta/purple therefore **cannot** be assigned a wavelength; it exists only because the
  spectrum was bent into a circle. Goethe argued (and modern systems agree) that
  non-spectral magenta is **essential to a complete color circle**.
  ([ColorSift](https://colorsift.com/articles/magenta-color-doesnt-exist-design-secret-weapon),
  [Wikipedia: Line of purples](https://en.wikipedia.org/wiki/Line_of_purples),
  [Quora: spectrum is a line](https://www.quora.com/Why-do-we-have-a-color-wheel-when-the-electromagnetic-spectrum-is-a-line))
- Color scientists "close the loop" precisely by adding this synthesized purple bridge —
  the hue circle is a perceptual construct, not a physical one.
  ([Britannica: visible spectrum](https://www.britannica.com/science/color/The-visible-spectrum))

### Why this matters for pitch-class
Pitch-class is **circular** (octave equivalence: C maps to C). The visible spectrum is a
**line** that doesn't loop. So you should **NOT** map pitch-class via wavelength (it would
have a discontinuity at the red/violet ends). Instead map the 12 chromatic pitch-classes
onto a **perceptual hue circle** (OKLCH hue 0–360°, 30° per semitone), which is already a
closed loop with the purples synthesized for you. This makes the circle-of-fifths or
chromatic wheel land on a seamless, evenly-spaced hue ring.

**Recommendation:** Pitch-class → OKLCH hue angle (12 equal steps, choice of offset/
direction as a preset). Do not route pitch-class through wavelength→RGB.

---

## Q5 — Cross-modal correspondences: robust vs idiosyncratic (PRIORITY-adjacent)

### ESTABLISHED (robust across populations — safe to hard-code)
- **Higher pitch ↔ brighter / lighter**: consistent across studies; whiter/brighter light
  pairs with higher pitch, darker with lower pitch. Shown to be a **low-level sensory**
  effect (not just decision bias), and present in infants, young children, and the
  congenitally blind for some dimensions.
  ([Spence: Crossmodal correspondences tutorial review (Attention, Perception &
  Psychophysics, 2011)](https://link.springer.com/article/10.3758/s13414-010-0073-7),
  [Lightness/pitch is low-level sensory](https://link.springer.com/article/10.3758/s13414-019-01668-w))
- **Higher pitch ↔ smaller / higher in space; louder ↔ bigger / more salient**: pitch
  reliably maps to size, elevation, brightness, spatial frequency, angularity.
  ([Spence 2011 review](https://link.springer.com/article/10.3758/s13414-010-0073-7),
  [elevation/size pitch correspondences](https://pmc.ncbi.nlm.nih.gov/articles/PMC11652408/),
  [Eitan & Timmers 2010, Cognition — pitch cross-domain mappings](https://www.academia.edu/1189997/Eitan_and_and_R_Timmers_Beethoven_s_last_piano_sonata_and_those_who_follow_crocodiles_Cross_domain_mappings_of_auditory_pitch_in_a_musical_context_Cognition_114_2010_pp_405_422_))
- **Pitch ↔ vertical height ("high"/"low")**: very robust; present in 1-year-olds and the
  blind, though the blind may map to proximity instead of verticality (so verticality is
  partly visual-experience-dependent).
  ([Eitan/Timmers](https://www.academia.edu/1189997/Eitan_and_and_R_Timmers_Beethoven_s_last_piano_sonata_and_those_who_follow_crocodiles_Cross_domain_mappings_of_auditory_pitch_in_a_musical_context_Cognition_114_2010_pp_405_422_),
  [role of visual experience](https://www.sciencedirect.com/science/article/abs/pii/S0010027718300593))
- **Musicians are more consistent** than non-musicians in gestural pitch/loudness/tempo
  mappings — so consistency itself is partly learned/trainable.
  ([Frontiers: Musicians are more consistent](https://www.frontiersin.org/journals/psychology/articles/10.3389/fpsyg.2014.00789/full))
- **Timbre ↔ color** correspondences exist and are systematic enough to study, but are
  weaker/less universal than pitch↔brightness.
  ([Frontiers: Color and tone color (2024)](https://www.frontiersin.org/journals/psychology/articles/10.3389/fpsyg.2024.1520131/full))

### IDIOSYNCRATIC / synesthete-specific (do NOT hard-code; expose as preset)
- **Specific pitch→hue / note→color** (e.g., "C is red"): these vary per individual and
  per synesthete; there is no universal note→hue table. Scriabin's and others' tables
  conflict. Treat any fixed note→color scheme as an artistic preset.
  ([cross-modal review notes weaker hue specificity](https://link.springer.com/article/10.3758/s13414-010-0073-7),
  [synesthesia is individual](https://interlude.hk/extraordinary-splashes-colour-music-synaesthesia/))

**Recommendation:** Hard-code only pitch→lightness/brightness and loudness→size/saturation.
Make pitch-class→hue (and any note→color) a user-selectable mapping with a sensible default,
explicitly framed as a convention, not a fact.

---

## Q6 — Additive mixing for chords & spectra (PRIORITY)

### The core problem (confirmed)
**Additive mixing tends toward white**: summing many colored lights raises luminance and
desaturates — a full chord summed naively goes gray/white. Saturation is purity; broad
spectral content = low saturation; narrow content = high saturation.
([Harvard Schwartz, Lecture 17: Color](https://scholar.harvard.edu/files/schwartz/files/lecture17-color.pdf),
[meta-display saturation/bandwidth relationship](https://arxiv.org/pdf/2105.01313))

### Principled approaches
1. **Amplitude/loudness-weighted blend, not equal sum.** Weight each partial's color by
   its (perceptual) loudness so dominant notes dominate the color. This mirrors how mix
   color-coding overlaps bands — overlapping content darkens/densifies rather than just
   brightening.
   ([kickpunchslap: color-coding frequencies](https://www.kickpunchslap.com/color-coding-frequencies-will-transform-your-mix/))
2. **Limit the number of partials/bins** contributing (e.g., top-N loudest, or octave-
   folded pitch-class bins) to prevent the wash-to-white from dozens of FFT bins.
3. **Blend in a perceptual space (OKLab), not linear RGB**, so the mean color is
   perceptually centered and hue is preserved instead of drifting toward purple/gray.
   ([Wikipedia: Oklab interpolation](https://en.wikipedia.org/wiki/Oklab_color_space))
4. **Decouple chroma from the blend and drive it from spectral dispersion/consonance.**
   Compute hue as the (circular) loudness-weighted mean of pitch-class hues; compute
   **chroma/saturation inversely from spectral spread** — a pure/consonant tone (narrow,
   coherent) → high chroma; a noisy/dissonant cluster (broad) → low chroma. This is the
   color-science fact "narrow bandwidth = high saturation" applied directly.
   ([meta-display bandwidth↔saturation](https://arxiv.org/pdf/2105.01313),
   [Harvard Schwartz](https://scholar.harvard.edu/files/schwartz/files/lecture17-color.pdf))
5. **Lightness from overall loudness** (louder = brighter), per Q5 robust mapping — but
   cap it so loud chords don't blow out to white.

There is **no single canonical "color of a chord" standard** in the literature; the
defensible recipe is the one above (perceptual-space weighted blend + dispersion-driven
chroma + partial limiting). FFT-bin→color spectroscope displays exist (mixing tools,
patents) but are visualization conventions, not perceptual standards.
([visual mix patents via search](https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/6490359))

**Recommendation (color-of-a-chord):**
- hue = circular mean of pitch-class hues, weighted by per-note loudness
- chroma = f(spectral concentration / consonance) — narrow→saturated, broad→desaturated
- lightness = f(total loudness), clamped
- blend math in OKLab; cap to top-N partials; smooth temporally to avoid flicker.

---

## Q7 — HRV coherence / biofeedback visualization (PRIORITY)

### What the evidence says coherence IS
- Cardiac **coherence** = degree of resonance between **respiration and heart-rate
  oscillations**; high coherence shows as a **smooth, sine-like ~0.1 Hz oscillation** in
  the inter-beat-interval time series.
  ([Methods for HRVB: systematic review & guidelines (PMC10412682)](https://pmc.ncbi.nlm.nih.gov/articles/PMC10412682/),
  [Resonance frequency assessment guide (PMC7578229)](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC7578229/))
- **Resonance-frequency breathing** is ~4.5–7.0 breaths/min, most commonly **~5.5/min**;
  breathing near this rate produces large baroreflex oscillations. This is the validated
  target to entrain toward.
  ([PMC7578229](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC7578229/),
  [Resonance breathing & HRV/BP/mood (PMC5575449)](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC5575449/))
- Real-time feedback typically shows **heart rate + respiration together**, often with
  **color-coded** indication of how close the pattern is to target; coherence scores rise
  with positive emotion.
  ([Global coherence-frequencies study, Sci Rep 2025](https://www.nature.com/articles/s41598-025-87729-7),
  [HeartMath blog](https://www.heartmath.com/blog/article/recent-studies-show-hrv-coherence-biofeedback-helps-the-heart-stay-resilient-under-stress/))
- VR/immersive nature scenery has been used successfully as the feedback display medium —
  supports an "immersive visual" approach.
  ([HRVB with immersive VR nature (PMC6763967)](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC6763967/))

> Note: HeartMath's "coherence score" framing is partly proprietary/commercial; the
> peer-reviewed, vendor-neutral core is **smoothness + ~0.1 Hz dominance + heart–breath
> phase-locking**. Build the visual on those, not on a brand metric.

### Validated/recommended visual metaphors (accessible, low-jargon)
- **Smoothness / order vs. jaggedness**: a smooth, regular wave or breathing orb when
  coherent; irregular/jagged when not. Directly mirrors the validated sine-like signal.
  ([PMC10412682](https://pmc.ncbi.nlm.nih.gov/articles/PMC10412682/))
- **Phase-locking / symmetry**: show heart and breath curves converging / aligning when
  entrained — the literal definition of coherence (resonance between the two).
  ([PMC7578229](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC7578229/))
- **Slow breath-paced motion** at ~5.5/min as a pacer the user follows (expand/contract).
  ([PMC5575449](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC5575449/),
  [makevisible: coherent breathing](https://www.makevisible.com/blog/introducing-coherent-breathing))

### Accessibility / flash-safety (mandatory)
- **WCAG 2.3.1**: nothing may flash **more than 3 times per second** (unless below the
  general + red flash thresholds). The 3–30 Hz band is most seizure-provoking; **red**
  flashing is especially dangerous.
  ([W3C Understanding 2.3.1](https://www.w3.org/TR/UNDERSTANDING-WCAG20/seizure-does-not-violate.html),
  [MDN: seizure disorders](https://developer.mozilla.org/en-US/docs/Web/Accessibility/Guides/Seizure_disorders))
- A general flash = a ≥10% relative-luminance opposing change with the darker state below
  0.80; saturated-red transitions get a stricter test. Test with **PEAT**.
  ([W3C](https://www.w3.org/TR/UNDERSTANDING-WCAG20/seizure-does-not-violate.html),
  [Adobe: epilepsy accessibility](https://adobe.design/stories/design-for-scale/improving-product-accessibility-for-users-with-epilepsy))
- Because coherent breathing is ~0.1 Hz, a breath-paced coherence visual is naturally far
  below 3 Hz — keep all transitions slew-limited and avoid saturated-red strobing
  (Echoel already slew-limits Art-Net flashes; apply the same to the screen visual).

**Recommendation:** Drive the coherence visual from a smoothness/order metric +
heart–breath phase alignment, animated at breathing pace (~0.1 Hz), with a clear numeric
coherence value (science-first, per brand). Cap all luminance transitions well under 3 Hz;
never strobe red. Keep copy non-esoteric ("coherence", "heart–breath alignment"), not
"healing/chakra".

---

## ESTABLISHED vs CONTESTED — quick split

| Claim | Status |
|---|---|
| c = 299,792,458 m/s; visible ≈ 380–760 nm ≈ ~395–790 THz (~1 octave) | ESTABLISHED |
| Audio×2^40 lands in visible band (arithmetic) | ESTABLISHED (math), but a convention, not physics |
| "Sound octaves = light octaves" as a physical equivalence | CONTESTED / false (only ~1 visible octave; no octave equivalence in light) |
| CIE 1931 CMFs → XYZ → sRGB is the accurate wavelength→color path | ESTABLISHED |
| Bruton algorithm is a fast approximation, red-skewed, not colorimetric | ESTABLISHED |
| OKLab/OKLCH is perceptually uniform, blue-region-correct, best for interpolation | ESTABLISHED (well-supported) |
| Magenta/purples are non-spectral; hue circle is a perceptual construct | ESTABLISHED |
| Higher pitch → brighter/lighter; louder → bigger; pitch → height (robust) | ESTABLISHED (psychophysics) |
| Specific note→hue tables (Scriabin etc.) are universal | CONTESTED / idiosyncratic (synesthete/constructed) |
| Additive mixing washes to white; chroma ∝ narrow bandwidth | ESTABLISHED |
| HRV coherence = smooth ~0.1 Hz heart–breath resonance; ~5.5 breaths/min target | ESTABLISHED |
| HeartMath proprietary "coherence score" as the metric | PARTLY CONTESTED / vendor (use vendor-neutral smoothness+phase) |
| WCAG ≤3 flashes/sec; red flash most dangerous | ESTABLISHED (standard) |
| Cousto "Cosmic Octave", 432 Hz / Solfeggio / chakra / "planetary/healing frequencies" | CONTESTED / pseudoscience — do NOT endorse |

---

## Concrete recommendations for Echoel's color engine

1. **Pitch-class → hue via OKLCH hue angle** (12 × 30°), closed loop (handles magenta for
   free). Default mapping is a labeled convention; expose offset/direction as a preset.
   Do NOT route pitch-class through wavelength→RGB.
2. **Optional "spectrum/light" mode**: precompute a CIE-1931-CMF wavelength→sRGB LUT
   (380–780 nm) at startup with explicit gamut clamping; offer Bruton as a stylized
   alternative. Label any audio→light octave-lift as an artistic mapping.
3. **Lightness ← loudness, brightness ← pitch height** (robust cross-modal); cap lightness
   so loud passages don't blow to white.
4. **Color of a chord/spectrum**: circular loudness-weighted mean of pitch-class hues
   (in OKLab), **chroma driven by spectral concentration/consonance** (narrow→saturated,
   broad→desaturated), lightness from total loudness, top-N partial limiting, temporal
   smoothing. Never sum in RGB.
5. **Coherence visual**: smoothness/order + heart–breath phase alignment, breath-paced
   (~0.1 Hz), with a legible numeric coherence value alongside (science-first). Use the
   existing slew-limiter; ban red strobing; verify with PEAT-style checks (<3 Hz).
6. **Brand/safety**: keep all user-facing copy free of Cousto/432/Solfeggio/chakra/healing
   terms; frame mappings as conventions, biofeedback as self-observation not diagnosis.

---

## Sources (primary list)
Physics/octave: [Physics Van/Illinois](https://van.physics.illinois.edu/ask/listing/2048),
[UCAR](https://scied.ucar.edu/learning-zone/atmosphere/visible-light),
[byjus](https://byjus.com/physics/the-electromagnetic-spectrum-visible-light/),
[Wikibooks](https://en.wikibooks.org/wiki/Electromagnetic_radiation/Visible_light).
Wavelength→RGB: [Baeldung](https://www.baeldung.com/cs/rgb-color-light-frequency),
[Bruton/Eureca](https://www.eureca.de/5116-1-Bruton-color-mapping.html),
[sqlpey](https://sqlpey.com/algorithm/methods-for-wavelength-to-rgb-color-conversion/),
[rsmith-nl](https://github.com/rsmith-nl/wavelength_to_rgb).
Perceptual spaces: [Ottosson OKLab](https://bottosson.github.io/posts/oklab/),
[Wikipedia Oklab](https://en.wikipedia.org/wiki/Oklab_color_space),
[Color.js](https://colorjs.io/docs/spaces),
[OKLCH wiki](https://colors.jarhalab.com/wiki/oklch-color).
Purples/magenta: [Wikipedia Line of purples](https://en.wikipedia.org/wiki/Line_of_purples),
[ColorSift](https://colorsift.com/articles/magenta-color-doesnt-exist-design-secret-weapon),
[Britannica](https://www.britannica.com/science/color/The-visible-spectrum).
Cross-modal: [Spence 2011 review](https://link.springer.com/article/10.3758/s13414-010-0073-7),
[Lightness/pitch low-level](https://link.springer.com/article/10.3758/s13414-019-01668-w),
[Eitan & Timmers 2010](https://www.academia.edu/1189997/Eitan_and_and_R_Timmers_Beethoven_s_last_piano_sonata_and_those_who_follow_crocodiles_Cross_domain_mappings_of_auditory_pitch_in_a_musical_context_Cognition_114_2010_pp_405_422_),
[Musicians more consistent](https://www.frontiersin.org/journals/psychology/articles/10.3389/fpsyg.2014.00789/full),
[Timbre↔color](https://www.frontiersin.org/journals/psychology/articles/10.3389/fpsyg.2024.1520131/full).
Chord/spectrum color: [Harvard Schwartz Lecture 17](https://scholar.harvard.edu/files/schwartz/files/lecture17-color.pdf),
[bandwidth↔saturation](https://arxiv.org/pdf/2105.01313),
[mix color-coding](https://www.kickpunchslap.com/color-coding-frequencies-will-transform-your-mix/).
HRV coherence: [HRVB methods/guidelines](https://pmc.ncbi.nlm.nih.gov/articles/PMC10412682/),
[Resonance assessment](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC7578229/),
[Resonance breathing](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC5575449/),
[Global coherence Sci Rep](https://www.nature.com/articles/s41598-025-87729-7),
[Immersive VR HRVB](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC6763967/).
Flash safety: [W3C 2.3.1](https://www.w3.org/TR/UNDERSTANDING-WCAG20/seizure-does-not-violate.html),
[MDN seizures](https://developer.mozilla.org/en-US/docs/Web/Accessibility/Guides/Seizure_disorders),
[Adobe epilepsy](https://adobe.design/stories/design-for-scale/improving-product-accessibility-for-users-with-epilepsy).
Contested: [Planetware (Cousto)](https://www.planetware.de/octave/),
[Sound Medicine Academy critique](https://www.soundmedicineacademy.com/pages/sound-healing-blog/healing-with-the-planetary-frequencies),
[432 Hz science](https://thisweekinsciencenews.com/blog/2026/03/23/432-hz-tuning-history-health-claims-and-what-science-really-shows/),
[Scriabin synesthesia doubt](https://interlude.hk/extraordinary-splashes-colour-music-synaesthesia/).
