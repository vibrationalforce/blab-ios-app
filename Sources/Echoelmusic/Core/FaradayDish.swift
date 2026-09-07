//  FaradayDish.swift
//  Echoel — the physics of a dish of water on a loudspeaker, as a pure value type.
//
//  WHY THIS EXISTS (founder 2026-09-07, verbatim: "ich will auch wirklich reale Wasser Klang
//  Bilder haben, wie als wenn ein Lautsprecher mit Wasser füllt"). The picture he means is the
//  classic experiment: a shallow layer of water on a speaker cone, a lamp above, and a standing
//  lattice of ripples that appears the moment the tone is loud enough and vanishes the moment
//  it is not. Those ripples are FARADAY WAVES — a parametric instability of the free surface
//  under vertical shaking. This file computes what that experiment does for one tone; it draws
//  nothing. Slice 2 gives it a shader, Slice 3 a library row. Until then it has NO production
//  caller, and that is the point of this slice: zero pixels change, the physics is pinned first.
//
//  THE THREE FACTS THE PICTURE DEPENDS ON — each a measurable statement, each pinned by the
//  guard `TheWaterDishObeysFaradayTests`:
//
//    1. THE RESPONSE IS SUBHARMONIC. The surface oscillates at HALF the drive frequency
//       (Faraday 1831; Benjamin & Ursell 1954: the principal Mathieu tongue). The lattice a
//       200 Hz tone makes has the wavelength of a 100 Hz wave. This is a LENGTH fact, not a
//       rate fact: using the drive frequency instead of half of it renders every pattern
//       2^(2/3) ≈ 1.59× too fine — a full octave of fineness, checkable with a ruler.
//
//    2. THE WAVELENGTH COMES FROM THE DISPERSION RELATION, solved in full:
//           ω² = (g·k + σ·k³/ρ) · tanh(k·h)
//       for k, at ω = 2π·(f_drive/2). Above ~100 Hz drive the depth factor is ≥ 0.99 for a
//       3 mm layer and the gravity term is under 11 %, so it reduces to the capillary branch
//       ω² ≈ σk³/ρ ⇒ k ∝ f^(2/3): one octave up, wavelength × 0.63. Below that the gravity
//       term is alive (at 20 Hz it is 58 % of the restoring force) and the ratio is NOT
//       2^(2/3); the guard pins BOTH halves so a "simplification" to the pure power law
//       goes red at the bass end, where the founder's speaker actually lives.
//
//    3. THERE IS A THRESHOLD, AND IT RISES WITH PITCH. Below a critical cone acceleration the
//       surface stays a flat mirror; above it the lattice grows as the square root of the
//       excess (the supercritical Landau onset). For weak damping the threshold is
//           a_c = 8·ν·k·ω / tanh(k·h)          (Landau–Lifshitz; Douady 1990)
//       which is 0.9 g at 200 Hz for water and 42 g at 2 kHz — so on a real speaker the
//       bass patterns and the treble does not, and a silent speaker is a mirror. That is
//       the honest version of "the sound draws the picture": SILENCE = FLAT.
//
//  ⚠️ ONE TONE, NOT A CHORD — and this corrects what I told the founder. The reply promised the
//  new look would be "fed from up to five sounding notes". The physics does not license that:
//  Benjamin–Ursell's subharmonic result holds for SINGLE-frequency forcing; multi-frequency
//  forcing opens harmonic and combination tongues whose winner depends on amplitude ratio and
//  relative phase, and a parametric instability with a threshold cannot be built by adding up
//  per-note linear responses (`scratchpads/PLAN_PHYSICAL_VISUALS_2026-09-07.md`, NICHT-bauen:
//  "a chord-driven Faraday dish"). So the dish is driven by ONE tone — the renderer's eased
//  `toneHz`, the sounding pitch — and says so. If the other notes are ever to be SEEN, they
//  reach the picture as COLOUR (a linear channel), never as lattice geometry.
//
//  ⚠️ WHAT IS A CHOICE HERE, NAMED SO IT CAN BE ARGUED WITH (every other number is water):
//    · `speakerAccelerationAtFullDrive` = 200 m/s² ≈ 20 g. The app has no accelerometer on the
//      speaker; `drive` in 0…1 is an amplitude the caller chooses (breath, master level) and this
//      constant says what "full" means. It is derived, not guessed: a cone producing 100 dB SPL
//      at 1 m (p ≈ 2 Pa) from a 12-inch piston (S ≈ 0.05 m²) accelerates at
//      a = p·2πr / (ρ_air·S) ≈ 2·6.28 / (1.2·0.05) ≈ 209 m/s². In a speaker's piston band the
//      acceleration is flat with frequency at constant loudness, so one number serves all pitches.
//      At this drive, patterns reach ≈ 1.3 kHz and the treble above stays flat. Founder-tunable.
//    · `saturationExcess` = 1: full pattern strength at twice the threshold. The square-root
//      onset shape is physics; where it saturates is a rendering decision.
//    · `capillaryFraction` is offered to the shader as a symmetry driver (Binks & van de Water
//      1997: in a low-viscosity fluid the lattice symmetry rises with drive frequency, squares
//      → hexagons → higher, governed by the dispersion relation). The QUANTITY is measured;
//      mapping it to an n-fold lattice is a stated choice in Slice 2, not a claim of physics.
//
//  ⚠️ NO MYSTICISM. This is fluid mechanics with three literature constants and a dispersion
//  relation; nothing here knows or claims anything about water "memory", intention, or a
//  person. User-facing copy may say "the tone sets the ripple spacing, the loudness sets
//  whether ripples appear" and nothing more.
//
//  WHERE IT RUNS. On the MAIN ACTOR, once per draw frame at most (60 Hz), on the CPU: two
//  64-step bisections and a handful of transcendentals. It never touches the audio thread and
//  never runs per fragment — the shader receives the RESULT (a wavenumber, a strength) as
//  uniforms. Foundation only, no allocation beyond the returned struct.

import Foundation

/// The Faraday-wave physics of a shallow liquid layer shaken vertically by ONE tone.
enum FaradayDish {

    /// The liquid. Every field is an SI quantity with a literature value; nothing is tuned.
    struct Fluid: Equatable {
        /// Surface tension σ, N/m.
        var surfaceTension: Double
        /// Density ρ, kg/m³.
        var density: Double
        /// Kinematic viscosity ν, m²/s.
        var kinematicViscosity: Double
        /// Layer depth h, m. The founder's dish is a few millimetres deep.
        var depth: Double

        /// Water at 20 °C on a speaker cone, 3 mm deep.
        static let water = Fluid(surfaceTension: 0.0728,
                                 density: 998.0,
                                 kinematicViscosity: 1.0e-6,
                                 depth: 0.003)
    }

    /// What the dish does for one tone at one loudness.
    struct Response: Equatable {
        /// The drive frequency after the 20 Hz … 20 kHz clamp, Hz.
        var driveHz: Double
        /// The surface's own frequency — always `driveHz / 2` (subharmonic response), Hz.
        var responseHz: Double
        /// Wavenumber k of the surface wave, rad/m, from the full dispersion relation.
        var wavenumber: Double
        /// Wavelength λ = 2π/k, m — the ripple spacing a ruler would measure.
        var wavelength: Double
        /// Share of the restoring force that is surface tension, 0…1. Near 0 = gravity wave,
        /// near 1 = capillary wave. Rises with pitch; offered to the shader as a symmetry driver.
        var capillaryFraction: Double
        /// tanh(k·h), 0…1 — 1 means the layer is "deep" for this wavelength.
        var depthFactor: Double
        /// Critical cone acceleration a_c below which the surface stays flat, m/s².
        var thresholdAcceleration: Double
        /// The cone acceleration the caller's `drive` represents, m/s².
        var driveAcceleration: Double
        /// (a − a_c) / a_c — negative below threshold, 0 at onset, positive above.
        var excess: Double
        /// Standing-wave strength 0…1: 0 below threshold, √(excess / saturationExcess) above,
        /// capped at 1. The square root is the supercritical onset law; the cap is a choice.
        var patternStrength: Double
        /// True when the drive exceeds the threshold — the lattice exists at all.
        var isPatterned: Bool
    }

    /// g, m/s².
    static let gravity = 9.81

    /// The drive frequencies this model answers for — the same clamp the renderer applies to
    /// `toneHz`. Outside it the caller is clamped, not refused; non-finite is refused.
    static let driveHzRange: ClosedRange<Double> = 20.0 ... 20000.0

    /// What `drive = 1` means in m/s² — see the header for the derivation (≈ 20 g, a loud
    /// 12-inch cone at 100 dB SPL). NEEDS-FOUNDER-VERIFY: on device, is the pitch at which the
    /// lattice fades to a mirror where his ear expects it? This constant moves that pitch.
    static let speakerAccelerationAtFullDrive = 200.0

    /// The excess at which `patternStrength` reaches 1: twice the threshold.
    static let saturationExcess = 1.0

    /// Bisection depth for both solvers — 64 halvings of a log-spaced bracket is far below
    /// Double resolution on any quantity here; the guard pins the results, not this number.
    static let bisectionSteps = 64

    // MARK: - The dispersion relation

    /// ω²(k) for gravity–capillary waves on a layer of depth h — monotone increasing in k,
    /// which is what makes bisection valid.
    static func omegaSquared(wavenumber k: Double, fluid: Fluid) -> Double {
        (gravity * k + fluid.surfaceTension * k * k * k / fluid.density) * tanh(k * fluid.depth)
    }

    /// Solve ω² = (g·k + σ·k³/ρ)·tanh(k·h) for k at the given SURFACE frequency, rad/m.
    /// Returns nil for a non-finite or non-positive frequency.
    static func wavenumber(responseHz: Double, fluid: Fluid = .water) -> Double? {
        guard responseHz.isFinite, responseHz > 0 else { return nil }
        let omega = 2 * Double.pi * responseHz
        let target = omega * omega
        var lo = 1e-3      // rad/m — a 6 km wave, below anything audible
        var hi = 1e7       // rad/m — a 0.6 µm wave, above anything a lamp could show
        for _ in 0 ..< bisectionSteps {
            let mid = (lo * hi).squareRoot()          // geometric midpoint: k spans 10 decades
            if omegaSquared(wavenumber: mid, fluid: fluid) < target { lo = mid } else { hi = mid }
        }
        return (lo * hi).squareRoot()
    }

    /// Critical cone acceleration for the subharmonic Faraday instability, m/s²:
    /// a_c = 8·ν·k·ω / tanh(k·h), the weak-damping result (γ = 2νk², threshold 4γω₀/k for
    /// the principal Mathieu tongue).
    static func thresholdAcceleration(wavenumber k: Double, responseHz: Double,
                                      fluid: Fluid = .water) -> Double {
        let omega = 2 * Double.pi * responseHz
        return 8 * fluid.kinematicViscosity * k * omega / tanh(k * fluid.depth)
    }

    // MARK: - The dish

    /// The dish's answer for ONE tone at one loudness.
    ///
    /// - Parameters:
    ///   - driveHz: the sounding pitch (the renderer's eased `toneHz`). Clamped to
    ///     `driveHzRange`; nil is returned for a non-finite or non-positive value.
    ///   - drive: loudness 0…1, the caller's choice of channel (breath, master level).
    ///     Non-finite reads as 0 (a flat mirror), out-of-range is clamped.
    static func response(driveHz: Double, drive: Double, fluid: Fluid = .water) -> Response? {
        guard driveHz.isFinite, driveHz > 0 else { return nil }
        let f = driveHz.clamped(to: driveHzRange)
        let d = drive.isFinite ? drive.clamped(to: 0 ... 1) : 0
        let responseHz = f / 2
        guard let k = wavenumber(responseHz: responseHz, fluid: fluid), k > 0 else { return nil }
        let gravityTerm = gravity * k
        let capillaryTerm = fluid.surfaceTension * k * k * k / fluid.density
        let threshold = thresholdAcceleration(wavenumber: k, responseHz: responseHz, fluid: fluid)
        let acceleration = d * speakerAccelerationAtFullDrive
        let excess = acceleration / threshold - 1
        let strength = excess <= 0 ? 0 : Swift.min(1, (excess / saturationExcess).squareRoot())
        return Response(driveHz: f,
                        responseHz: responseHz,
                        wavenumber: k,
                        wavelength: 2 * Double.pi / k,
                        capillaryFraction: capillaryTerm / (gravityTerm + capillaryTerm),
                        depthFactor: tanh(k * fluid.depth),
                        thresholdAcceleration: threshold,
                        driveAcceleration: acceleration,
                        excess: excess,
                        patternStrength: strength,
                        isPatterned: excess > 0)
    }

    /// The highest drive frequency that still patterns at this loudness, Hz — the pitch above
    /// which the dish is a mirror. nil when nothing patterns even at 20 Hz (silence, or a drive
    /// too small to cross the bass threshold); the top of `driveHzRange` when everything does.
    /// For a caption ("ripples up to …"), not for the render loop.
    static func highestPatternedDriveHz(drive: Double, fluid: Fluid = .water) -> Double? {
        let d = drive.isFinite ? drive.clamped(to: 0 ... 1) : 0
        guard d > 0 else { return nil }
        func patterned(_ hz: Double) -> Bool {
            response(driveHz: hz, drive: d, fluid: fluid)?.isPatterned ?? false
        }
        guard patterned(driveHzRange.lowerBound) else { return nil }
        guard !patterned(driveHzRange.upperBound) else { return driveHzRange.upperBound }
        var lo = driveHzRange.lowerBound
        var hi = driveHzRange.upperBound
        for _ in 0 ..< bisectionSteps {
            let mid = (lo * hi).squareRoot()
            if patterned(mid) { lo = mid } else { hi = mid }
        }
        return (lo * hi).squareRoot()
    }
}
