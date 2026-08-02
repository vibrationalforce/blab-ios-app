import Foundation

// WavefrontField.swift
// Echoel — #385. The physics of a spreading wave, as a pure core.
//
// ⭐ FOUNDER ASK, 2026-08-02, with the oscilloscope and the Poincaré plot struck out in red:
// *"Gibt es noch eine Möglichkeit das es mehr physikalisch korrekt wie die Schwingung aussieht?
// Schallwellen breiten sich ja in alle Richtungen gleichmäßig aus."* He is right, and the two
// struck views are the evidence: an oscilloscope trace is a voltage against time and a Poincaré
// plot is a statistic over heartbeat intervals. Both are correct and neither looks like anything
// that happens in a room. A sound leaves its source as a wavefront that expands in every
// direction at once, and gets weaker as it goes because the same energy is spread over a growing
// surface. THAT is the picture, and this file is the arithmetic behind it.
//
// ⚠️ THE THREE HONEST LIMITS, first, because a view that claims physics has to say where the
// claim stops. Each is a decision, not an omission:
//
// 1. THE RADIAL AXIS IS AGE, NOT METRES. A ring's radius is the time since that moment sounded,
//    normalised to the view. Under a constant propagation speed age is exactly proportional to
//    distance, so the GEOMETRY is honest — uniform expansion, correct falloff — without this
//    file inventing a room size it cannot know. A metre scale would be a made-up number wearing
//    a physical unit, which is worse than no unit at all.
//
// 2. THE RINGS ARE ENVELOPE FRONTS, NOT PRESSURE CYCLES. Individual cycles of a 440 Hz tone
//    cross any watchable picture 440 times a second; drawing them would be a strobe, not a
//    diagram, and would break the ≤3 Hz flash law outright. What expands here is a MOMENT of the
//    music — its loudness and its colour — so you watch the sound's history travel outward.
//
// 3. THE CLOCK IS SLOWED. Sound covers a room in milliseconds. `traverseSeconds` gives a front
//    2.5 s to cross the view so a human can follow it. The slow-down is uniform, so every ring
//    keeps its correct relative position and the falloff law still holds exactly — only the
//    playback speed of the whole picture is dilated.
//
// ⚠️ WHY 1/r AND NOT 1/r², since the textbook line is "intensity falls with the square of the
// distance". Both are true and they describe different quantities: INTENSITY (power per area)
// goes as 1/r², and PRESSURE AMPLITUDE — the thing that actually swings, and the thing a drawn
// wave depicts — goes as 1/r. A picture of a wave is a picture of its amplitude, so 1/r is the
// correct law here. Using 1/r² would make the rings vanish about twice as fast as the physics
// they claim to show.
//
// PURE VALUE TYPE: no SwiftUI, no engine, no clock of its own. The view supplies `dt`; every
// entry point is NaN-safe, because these numbers reach a `Canvas` where a `nan` radius silently
// skips a shape and reads as a rendering bug rather than as bad input.

/// The spreading-wave model behind `AnalysisWavefrontView`.
public enum WavefrontField {

    // MARK: - Constants (the three that set the look)

    /// Seconds a front takes to travel from the centre to the edge of the view.
    ///
    /// Long enough that several rings are in flight at once — which is what makes the picture
    /// read as expansion rather than as a blinking circle — and short enough that a phrase you
    /// just played is still on screen.
    public static let traverseSeconds: Double = 2.5

    /// Fronts emitted per SECOND — a rate, never a per-frame count.
    ///
    /// ⚠️ THE REPO LAW (#315/#332/#337), and here it is visible rather than latent: emitting one
    /// front per frame would make the ring SPACING a function of the frame rate. The picture
    /// would silently change its geometry under thermal throttling or Low Power Mode, and the
    /// spacing is the part that carries the physics. At 12 Hz over a 2.5 s traverse, 30 rings are
    /// in flight — dense enough to read as a wave, sparse enough that each ring is separable.
    public static let emitRateHz: Double = 12

    /// The near-field reference radius that keeps the 1/r law finite at the source.
    ///
    /// 1/r is a FAR-field law: it holds beyond roughly a wavelength from the source and diverges
    /// at r = 0, where a real source is not a point anyway. `a₀ · r₀/(r₀ + r)` is the standard
    /// softened form — indistinguishable from 1/r once r ≫ r₀, and equal to `a₀` at the source
    /// instead of infinite. Without it the innermost ring would be drawn arbitrarily bright,
    /// which is both wrong and a flash hazard.
    public static let nearFieldRadius: Double = 0.12

    /// Hard bound on fronts held at once. `emitRateHz · traverseSeconds` is 30; the headroom
    /// absorbs a long frame without letting a stalled view accumulate without limit.
    public static let maxFronts: Int = 48

    // MARK: - The physics

    /// Pressure amplitude of a spherical wave at normalised radius `r`, given its amplitude
    /// `a0` at the source.
    ///
    /// Returns 0 for any non-finite input: a `nan` here would propagate into a `Canvas` opacity
    /// and skip the shape entirely, which looks like a broken renderer rather than bad audio.
    /// Never exceeds `a0` — a wave cannot gain energy by spreading, and a guard that lets it is
    /// how a "physical" picture quietly stops being one.
    public static func spreadingAmplitude(emitted a0: Double, atRadius r: Double) -> Double {
        guard a0.isFinite, r.isFinite else { return 0 }
        let radius = Swift.max(0, r)
        let source = Swift.max(0, a0)
        return source * nearFieldRadius / (nearFieldRadius + radius)
    }

    /// A front's normalised radius after `dt` seconds.
    ///
    /// `dt` is sanitised exactly as `FlashGuard.maxDelta` and `BioPhaser.step` do it: non-finite
    /// or non-positive falls back to 0.1 s, and anything above one second is capped at one. The
    /// cap is the safety half — after a stall or a clock jump an uncapped `dt` would teleport
    /// every ring to the edge in a single frame, which is one large luminance edge, i.e. a flash.
    public static func advanced(radius r: Double, dt: Double) -> Double {
        guard r.isFinite else { return 0 }
        let safeDt = (dt.isFinite && dt > 0) ? Swift.min(dt, 1.0) : 0.1
        let span = Swift.max(0.001, traverseSeconds)
        return r + safeDt / span
    }

    /// The amplitude-weighted mean frequency of a spectrum — the "colour" of this moment.
    ///
    /// ⭐ CENTROID, NOT PEAK, and the two answer different questions. The Field panel's readout
    /// names the LOUDEST partial, because a performer checking tuning wants one note. A ring is
    /// the whole sound at an instant, so it wants the centre of mass of the spectrum — the
    /// standard brightness descriptor. A bass note with a bright attack has a peak in the bass
    /// and a centroid well above it, and the ring should show the second.
    ///
    /// Returns `nil` in silence rather than a fabricated frequency: a ring emitted from nothing
    /// should be colourless, not red because 0 Hz maps to the bottom of the scale.
    public static func centroidHz(magnitudes: [Float], sampleRate: Double,
                                  fMin: Double = 30, fMax: Double = 16000) -> Double? {
        let bins = magnitudes.count
        guard bins > 1, sampleRate.isFinite, sampleRate > 0, fMax > fMin, fMin > 0 else { return nil }
        let hzPerBin = sampleRate / Double(bins * 2)
        var weighted = 0.0
        var total = 0.0
        // Skip DC (bin 0) — it carries any offset in the window and no pitch at all.
        for k in 1..<bins {
            let hz = Double(k) * hzPerBin
            guard hz >= fMin, hz <= fMax else { continue }
            let m = Double(magnitudes[k])
            guard m.isFinite, m > 0 else { continue }
            weighted += hz * m
            total += m
        }
        guard total > 0 else { return nil }
        let centroid = weighted / total
        return centroid.isFinite ? centroid : nil
    }
}
