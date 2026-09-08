//  WaterCaustics.swift
//  Echoel — the light a rippled water surface throws on the floor beneath it, as a pure
//  value type. It draws nothing and, in this slice, has NO production caller (the W1 shape
//  that landed `FaradayDish` at #1100: pin the physics before a pixel depends on it).
//
//  WHY THIS EXISTS. Founder 2026-09-08: "generative and physical association Visuals weiter
//  entwickeln". The shipped look `fieldDepthCaustics` (style 7, in the DEFAULT slider
//  sequence, so every user sees it) calls itself CAUSTICS and is not one: it computes
//  `pow(0.5 + 0.14 * (sum of three sine layers), gamma)` — a brightness curve on a sine sum.
//  Two things follow. The sounding pitch never reaches it (its only length scale is
//  `mix(3.0, 5.0, breath)`, the exact defect Slice 1 of the physical-visuals plan removed
//  from `fieldWater`), and the bright filaments are drawn rather than derived — a real
//  caustic is a SINGULARITY of a ray map, not a steep power curve.
//
//  This file is the law that replaces it. Its input is the surface Echoel ALREADY solves
//  rigorously: `FaradayDish` turns the sounding tone into a standing-wave number and a
//  supercritical pattern strength, and `MetalBioView` already carries both to the GPU as
//  `dishK` / `dishStrength`. So the picture on the floor is downstream of the same physics
//  as the picture on the surface — the dish seen from above, and the light it casts, are
//  one experiment rendered twice.
//
//  THE PHYSICS, AND IT IS RAY OPTICS ONLY:
//
//    1. REFRACTION AT A NEARLY-FLAT SURFACE. A vertical ray meeting a surface of slope
//       ∇h refracts by Snell's law; for small slopes the ray inside the water is tilted
//       from vertical by (1 − 1/n)·|∇h|, so after a depth D it lands at
//           x' = x + D·(1 − 1/n)·∇h(x)
//       The sign is the physical one and is checkable by eye: at a point just downhill of
//       a crest the normal tilts back toward the crest, the ray bends toward the crest, and
//       CRESTS FOCUS. For water n = 1.333 the deflection coefficient is 0.2498 — a quarter
//       of the slope, not the whole of it, which is why a pool floor pattern is so much
//       coarser than the ripples making it.
//
//    2. INTENSITY IS THE INVERSE JACOBIAN. Energy is conserved inside a ray tube, so the
//       illumination on the floor is I = I₀ / |det J| with
//           J = I + β·Hess(h),   β = D·(1 − 1/n)
//       and det J = (1 + β·h_xx)(1 + β·h_yy) − (β·h_xy)². The bright filaments of a real
//       caustic are exactly the locus det J = 0; the dark ground between them is |det J| > 1.
//       Nothing here is drawn — the network, its cusps and its dark cells all fall out of
//       one determinant.
//
//    3. THERE IS A FOCUSING DEPTH, AND IT IS SHORT. For a single ripple of amplitude a and
//       wavenumber k the crest curvature is a·k², so the first caustic forms at
//           D_focus = 1 / ((1 − 1/n)·a·k²)
//       Measured at the saturated amplitude this file ships (0.25 mm) under a 200 Hz tone
//       (k = 1730.2 rad/m from the same full gravity–capillary solve `FaradayDish` runs):
//       5.35 mm. That is why the pattern on the
//       bottom of a shallow dish is sharp rather than a blur — and it is a LENGTH the pitch
//       moves: an octave up multiplies k by ≈2^(2/3) and therefore divides the focusing
//       depth by ≈2^(4/3), so a lead note focuses roughly two and a half times shallower
//       than a bass note. Everything a viewer sees change with pitch comes from that.
//
//  ⚠️ THREE THINGS THIS IS NOT, each killed by name in the plan's refutation list
//  (`scratchpads/PLAN_PHYSICAL_VISUALS_2026-09-07.md`) — stated here so a later reader does
//  not mistake this file for a quiet revival of one of them:
//    · NOT the rejected DEPTH SLIDER. That knob was the dish's WATER DEPTH h inside
//      tanh(k·h), which is provably inert (≥0.998 for every audio ripple). `D` here is a
//      different quantity — the distance from surface to floor in the projection — and it is
//      not inert: the focus number is strictly proportional to it, so it moves the picture
//      from smooth bands through first focus into a folded network. Whether it becomes a
//      CONTROL is a later decision; nothing here ships one.
//    · NOT the rejected DIFFRACTION / AIRY look, which was killed for conflating an acoustic
//      frequency with an optical wavelength. No optical wavelength appears in this file.
//      Geometric ray optics is wavelength-independent; the only length the tone sets is the
//      MECHANICAL ripple wavenumber, through the dispersion relation of water.
//    · NOT the rejected THIN-FILM colour law, killed as "a rigorous half laundering an
//      arbitrary half" because nothing in acoustics sets the optical path difference. Here
//      every quantity feeding the determinant is already solved from the tone by shipped
//      code: k from `FaradayDish.wavenumber`, the pattern's existence from its threshold.
//      The one exception is named in the next paragraph rather than hidden.
//
//  ⚠️ WHAT IS A CHOICE HERE, NAMED SO IT CAN BE ARGUED WITH:
//    · `rippleAmplitudeAtFullPattern` = 0.25 mm. `FaradayDish.Response.patternStrength` is a
//      dimensionless 0…1 (a supercritical onset), not a height; the saturated Faraday
//      amplitude of a real dish depends on the container and the driving history. This
//      constant says what "full lattice" is worth in metres. It is chosen inside the range
//      photographs of such dishes show (a fraction of the ripple wavelength) and it is
//      founder-tunable: raising it makes the floor pattern focus SHALLOWER and read sharper.
//    · `intensityCeiling` = 8. A caustic is a genuine singularity — det J reaches zero and
//      ray optics predicts infinite brightness there, which real light resolves with
//      diffraction and a renderer must resolve with a bound. This is a FLASH-SAFETY quantity
//      as much as an aesthetic one: an unbounded intensity riding a moving surface is a
//      full-luminance excursion, and the 3 Hz WCAG ceiling is defended by bounding it here
//      rather than by hoping the caller clamps.
//
//  ⚠️ NO MYSTICISM. Snell's law, a Jacobian and one dispersion relation. Nothing in this
//  file knows or claims anything about water "memory", intention, or a person. User-facing
//  copy may say "the tone sets the ripple spacing and the ripples focus the light" and
//  nothing more.

import Foundation

/// Ray optics of a rippled water surface lit from above: what the floor beneath it sees.
/// Pure value type, Foundation-only, no state, no drawing.
enum WaterCaustics {

    // MARK: - Constants

    /// Refractive index of water for visible light at room temperature (≈1.333 across the
    /// band; the dispersion between red and violet is ~1 %, far below anything this look
    /// resolves, and geometric caustics are wavelength-independent anyway).
    static let waterIndex = 1.333

    /// Saturated Faraday ripple amplitude, metres — a NAMED CHOICE, see the header.
    /// Founder-tunable: larger = the floor pattern focuses shallower and reads sharper.
    static let rippleAmplitudeAtFullPattern = 0.00025

    /// Upper bound on rendered caustic intensity — a NAMED CHOICE and a flash-safety
    /// quantity, see the header. Ray optics diverges at the caustic; this is the bound.
    static let intensityCeiling = 8.0

    /// The same value as an exact Metal token. The shader bounds its own division rather
    /// than calling back into Swift, so the bound must be ONE number in both places — this
    /// is a flash-safety quantity, and a silent drift here is a luminance excursion.
    static let intensityCeilingMetalLiteral = "8.0"

    // MARK: - Refraction

    /// The fraction of the surface slope that becomes ray tilt inside the water:
    /// `1 − 1/n` (small-angle Snell). 0.2498 for water — a quarter, not all, of the slope.
    /// Returns 0 for a non-physical index rather than a negative deflection.
    static func deflectionCoefficient(index: Double = waterIndex) -> Double {
        guard index.isFinite, index >= 1 else { return 0 }
        return 1.0 - 1.0 / index
    }

    /// Faraday pattern strength (dimensionless 0…1, from `FaradayDish.Response`) → ripple
    /// amplitude in metres. Linear in the strength, which is the honest reading of a
    /// supercritical onset already square-rooted upstream; clamped so a caller cannot
    /// drive the surface past saturation.
    static func rippleAmplitude(patternStrength: Double) -> Double {
        guard patternStrength.isFinite else { return 0 }
        let s = Swift.min(1.0, Swift.max(0.0, patternStrength))
        return s * rippleAmplitudeAtFullPattern
    }

    // MARK: - The focus number (the one quantity a renderer needs)

    /// φ = D·(1 − 1/n)·a·k² — dimensionless, and the ONLY thing the picture depends on.
    /// φ = 0 is a flat mirror (uniform floor), φ < 1 is smooth bright banding over the
    /// crests, φ = 1 is the first caustic line, φ > 1 is the folded network.
    /// A renderer passes this as ONE uniform; every metre cancels here.
    static func focusNumber(depthMetres D: Double,
                            amplitudeMetres a: Double,
                            wavenumber k: Double,
                            index: Double = waterIndex) -> Double {
        guard D.isFinite, a.isFinite, k.isFinite, D >= 0, a >= 0, k >= 0 else { return 0 }
        return D * deflectionCoefficient(index: index) * a * k * k
    }

    /// The depth at which a ripple of amplitude `a` and wavenumber `k` first focuses:
    /// the D where `focusNumber` reaches 1. Returns nil for a flat or absent ripple,
    /// where no caustic ever forms at any depth.
    static func focusingDepth(amplitudeMetres a: Double,
                              wavenumber k: Double,
                              index: Double = waterIndex) -> Double? {
        let c = deflectionCoefficient(index: index)
        guard a.isFinite, k.isFinite, a > 0, k > 0, c > 0 else { return nil }
        let d = 1.0 / (c * a * k * k)
        return d.isFinite ? d : nil
    }

    // MARK: - The ray map

    /// det J for the refracted ray map, in DIMENSIONLESS curvature: pass the surface's
    /// second derivatives divided by `a·k²`, so a crest of a single ripple is `-1` and a
    /// trough `+1`. det J = (1 + φ·cxx)(1 + φ·cyy) − (φ·cxy)².
    /// Zero is the caustic itself; negative means the ray map has folded over.
    static func jacobianDeterminant(focusNumber phi: Double,
                                    curvatureXX cxx: Double,
                                    curvatureYY cyy: Double = 0,
                                    curvatureXY cxy: Double = 0) -> Double {
        guard phi.isFinite, cxx.isFinite, cyy.isFinite, cxy.isFinite else { return 1 }
        let a = 1.0 + phi * cxx
        let b = 1.0 + phi * cyy
        let c = phi * cxy
        return a * b - c * c
    }

    // MARK: - What the renderer actually needs (#1117)

    /// The focus number at FULL pattern strength — the one number the picture depends on,
    /// and therefore the one thing the shader has to be handed.
    ///
    /// It also fixes the viewing depth implicitly, because φ = D·(1−1/n)·a·k² can be read
    /// backwards: D = φ / ((1−1/n)·a·k²). So choosing 3.0 is choosing to look at the floor
    /// from three times the focusing depth. That is the honest way round — a renderer has
    /// no metres, and every metre cancels in φ.
    ///
    /// ⚠️ A NAMED CHOICE, and 3.0 is not arbitrary. On the square standing surface the
    /// looks use, h = ½(cos kx + cos ky), the normalised curvature is −½cos kx, so
    /// det J = (1 − ½φ·cos kx)(1 − ½φ·cos ky) and a caustic exists only where cos kx = 2/φ.
    /// **Below φ = 2 there is no caustic anywhere on the surface** — the floor is smooth
    /// banding and the look would be misnamed. 3.0 puts the fold at cos kx = ⅔, which
    /// draws a closed loop around every crest: the pool-floor network. Founder-tunable:
    /// larger = more folds and a busier net; below 2 the network disappears entirely.
    static let renderFocusNumberAtFullPattern = 3.0

    /// The same value as an exact Metal token, so the shader cannot drift from the Swift
    /// law (the `SpectralColor`/`FlashGuard` twinning convention).
    static let renderFocusNumberAtFullPatternMetalLiteral = "3.0"

    /// Three floor depths, as ratios of the first. φ is strictly proportional to depth, so
    /// evaluating the SAME determinant at three focus numbers is literally looking at three
    /// depths of the same water — the deeper layers are folded further and read finer.
    ///
    /// ⭐ This is what makes the look's own name true. The shipped `fieldDepthCaustics`
    /// stacked three sine layers at increasing SPATIAL FREQUENCY and decreasing brightness
    /// to *suggest* depth; here depth is the actual parameter, and the layers cost two
    /// cosines TOTAL because the surface is the same for all three — only φ differs.
    /// The 1.7 step is inherited from the look it replaces, so its texture is recognisable.
    static let depthLayerFocusRatios: [Double] = [1.0, 1.7, 2.89]

    /// Brightness weight per layer — nearer floor reads strongest. Inherited from the same
    /// look, and normalised away in `layeredIntensity`, so these are a ratio, not a gain.
    static let depthLayerWeights: [Double] = [1.0, 0.55, 0.30]

    /// The intensity that renders as full white. `intensity` is unbounded up to
    /// `intensityCeiling` = 8, and mapping that whole range onto the screen would leave the
    /// ordinary floor almost black. A NAMED CHOICE; monotone, so it cannot add a flash.
    ///
    /// ⚠️ 2.5 IS A DELIBERATELY LOW MAPPING AND THE REASON IS THE SILENT STATE. A flat
    /// surface returns intensity exactly 1, so this divisor alone decides what SILENCE looks
    /// like: at 4.0 the resting floor renders 0.165 after the coherence curve — close enough
    /// to black that a cold launch into this look (it is in `LookBlendMap.defaultSequence`)
    /// would read as a broken screen. At 2.5 it is 0.30, an unmistakably lit calm ground,
    /// and the caustic network still saturates because the filaments run to the ceiling of
    /// 8. Founder-tunable in the OTHER direction too: larger = a darker floor and a
    /// thinner, harder network. NEEDS-FOUNDER-VERIFY on a device.
    static let renderFullBrightIntensity = 2.5

    static let depthLayerFocusRatioMetalLiterals = ["1.0", "1.7", "2.89"]
    static let depthLayerWeightMetalLiterals = ["1.0", "0.55", "0.30"]
    /// Σ of `depthLayerWeights`, as an exact token — the normaliser the shader divides by.
    static let depthLayerWeightSumMetalLiteral = "1.85"
    static let renderFullBrightIntensityMetalLiteral = "2.5"

    /// The floor's illumination at the three depths, weight-averaged and normalised so a
    /// FLAT surface returns exactly 1 — an evenly lit floor, never a black frame and never
    /// a glow. `cxx`/`cyy` are the dimensionless curvatures (`jacobianDeterminant`'s
    /// contract: divided by a·k²). This is the exact computation the shader performs; the
    /// guard drives this function so the two cannot disagree.
    static func layeredIntensity(focusNumber phi: Double,
                                 curvatureXX cxx: Double,
                                 curvatureYY cyy: Double = 0,
                                 curvatureXY cxy: Double = 0) -> Double {
        var acc = 0.0
        var weightSum = 0.0
        for (ratio, weight) in zip(depthLayerFocusRatios, depthLayerWeights) {
            let det = jacobianDeterminant(focusNumber: phi * ratio,
                                          curvatureXX: cxx, curvatureYY: cyy, curvatureXY: cxy)
            acc += weight * intensity(jacobianDeterminant: det)
            weightSum += weight
        }
        guard weightSum > 0 else { return 1 }
        return acc / weightSum
    }

    /// Illumination on the floor: I = 1/|det J|, bounded by `intensityCeiling` because a
    /// caustic is a true singularity (header, choice 2). A flat surface (det J = 1)
    /// returns exactly 1, so an unrippled dish is an evenly lit floor and NOT a bright one.
    static func intensity(jacobianDeterminant det: Double,
                          ceiling: Double = intensityCeiling) -> Double {
        let cap = (ceiling.isFinite && ceiling > 0) ? ceiling : intensityCeiling
        guard det.isFinite else { return cap }
        let magnitude = Swift.abs(det)
        guard magnitude > 1.0 / cap else { return cap }
        return 1.0 / magnitude
    }
}
