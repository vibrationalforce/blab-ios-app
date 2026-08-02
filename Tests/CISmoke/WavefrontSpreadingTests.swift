// WavefrontSpreadingTests.swift
// Echoel — a picture that claims physics has to obey it. #385.
//
// WHAT THIS GUARDS. `WavefrontField` is the arithmetic behind the radial view the founder asked
// for on 2026-08-02 ("Schallwellen breiten sich ja in alle Richtungen gleichmäßig aus"), built
// after he struck out the oscilloscope and the Poincaré plot. Those two are lab conventions —
// a voltage against time, a statistic over heartbeat intervals — and neither looks like sound
// leaving a source. The replacement only earns the word "physical" if the falloff law and the
// propagation are actually the ones on the page, so this is a REAL unit test of a pure core, not
// a source scan.
//
// ⭐ IT PINS LAWS, NOT NUMBERS, and that distinction is what keeps it useful. `traverseSeconds`,
// `emitRateHz` and `nearFieldRadius` are look decisions the founder may want changed after seeing
// it on a device; pinning them would turn a legitimate tuning pass into a red for no reason,
// which is how a guard gets deleted instead of updated. What is pinned is what cannot change
// without the picture ceasing to be physical: amplitude falls monotonically with distance, never
// rises above its value at the source, and propagation is a function of ELAPSED TIME rather than
// of how many frames happened to be drawn.
//
// ⚠️ THE 1/r-VERSUS-1/r² QUESTION IS DELIBERATELY NOT ASSERTED AS AN EXPONENT. The textbook line
// is that INTENSITY falls with the square of distance; PRESSURE AMPLITUDE — what swings, and what
// a drawn wave depicts — falls as 1/r. Both are correct about different quantities, and the file
// explains which one it draws and why. A test that hard-coded `1/r` would forbid a future,
// equally defensible switch to an energy-based rendering; the monotonicity and ceiling
// assertions below hold for BOTH laws and fail for anything that is neither.
//
// ⚠️ HONEST LIMIT. This proves the model, never the picture: nothing here renders a pixel, and
// there is no simulator in the blocking bundle. NEEDS-FOUNDER-VERIFY: does it read as a wave
// spreading out, and does it replace the two struck views or does one of them come back?
//
// `Tests/CISmoke` is the blocking bundle.

import Foundation
import XCTest
@testable import Echoelmusic

final class WavefrontSpreadingTests: XCTestCase {

    // MARK: - Spreading

    /// A wave gets weaker as it spreads, everywhere, always.
    func testAmplitudeFallsWithDistanceAndNeverExceedsTheSource() {
        let a0 = 0.8
        var previous = WavefrontField.spreadingAmplitude(emitted: a0, atRadius: 0)

        XCTAssertEqual(previous, a0, accuracy: 0.0001, """
            The amplitude AT THE SOURCE is not the emitted amplitude (\(previous) vs \(a0)). The \
            near-field softening exists so the 1/r law stays finite at r = 0; it must not also \
            scale the source itself, or every ring is drawn quieter than the sound that made it \
            and the whole picture under-reports loudness.
            """)

        for step in 1...60 {
            let r = Double(step) / 20.0          // 0.05 … 3.0, well past the view edge
            let a = WavefrontField.spreadingAmplitude(emitted: a0, atRadius: r)

            XCTAssertLessThanOrEqual(a, previous + 0.000_001, """
                Amplitude ROSE with distance at r = \(r) (\(a) after \(previous)). A spreading \
                wave distributes the same energy over a growing surface, so it can only get \
                weaker. A picture where a ring brightens as it travels is not a wave — it is an \
                animation, and it is exactly what this view exists instead of.
                """)
            XCTAssertLessThanOrEqual(a, a0 + 0.000_001, """
                Amplitude at r = \(r) is \(a), above the emitted \(a0). Energy cannot be gained \
                by spreading. Whatever falloff law is in use, this ceiling holds for all of them, \
                and a violation means the softening term has been rearranged into a gain.
                """)
            XCTAssertGreaterThanOrEqual(a, 0, """
                Amplitude at r = \(r) is negative (\(a)). A negative amplitude compared with a \
                `>` gate downstream, or handed to a `Canvas` opacity, is a different bug than a \
                weak ring — not a safer one.
                """)
            previous = a
        }
    }

    /// Non-finite inputs produce nothing, not `nan`.
    func testNonFiniteInputsProduceZero() {
        for bad in [Double.nan, Double.infinity, -Double.infinity] {
            XCTAssertEqual(WavefrontField.spreadingAmplitude(emitted: bad, atRadius: 0.5), 0,
                           accuracy: 0.0001, """
                A non-finite EMITTED amplitude produced something other than zero. These values \
                reach a `Canvas` opacity; a `nan` there makes the shape silently disappear, which \
                reads as a broken renderer rather than as a bad audio frame.
                """)
            XCTAssertEqual(WavefrontField.spreadingAmplitude(emitted: 0.5, atRadius: bad), 0,
                           accuracy: 0.0001, """
                A non-finite RADIUS produced something other than zero. A `nan` radius makes \
                `Canvas` skip the ring entirely — the same invisible failure as above, one \
                argument over.
                """)
        }
    }

    // MARK: - Propagation

    /// Propagation is a function of TIME, not of how many frames were drawn.
    ///
    /// ⭐ THIS IS THE #315/#332/#337 CLASS, asserted rather than commented. A per-frame advance
    /// makes the ring spacing — the part of the picture that carries the physics — depend on the
    /// frame rate, so the geometry changes silently under thermal throttling or Low Power Mode.
    /// Two half-steps must land where one whole step lands.
    func testPropagationIsRateBasedNotPerFrame() {
        let once = WavefrontField.advanced(radius: 0, dt: 0.5)

        var twice = 0.0
        for _ in 0..<2 { twice = WavefrontField.advanced(radius: twice, dt: 0.25) }

        XCTAssertEqual(once, twice, accuracy: 0.000_001, """
            One 0.5 s step (\(once)) and two 0.25 s steps (\(twice)) put a front at different \
            radii. Then the ring SPACING depends on the frame rate, and the picture's geometry — \
            the thing that makes it a wave diagram rather than a decoration — changes under \
            thermal throttling, Low Power Mode, or on a slower device, with nothing to show for \
            it. Derive the advance from the measured interval, never from a per-frame constant.
            """)

        var four = 0.0
        for _ in 0..<4 { four = WavefrontField.advanced(radius: four, dt: 0.125) }
        XCTAssertEqual(once, four, accuracy: 0.000_001, """
            Four 0.125 s steps (\(four)) disagree with one 0.5 s step (\(once)) — same defect as \
            above, and checked at a second subdivision because a linear advance is the ONE shape \
            where this can hold at every subdivision. If it holds for two and not for four, the \
            advance has picked up a per-call term.
            """)
    }

    /// A stalled frame may not teleport the field.
    func testALongStallIsCapped() {
        let huge = WavefrontField.advanced(radius: 0, dt: 60)
        let oneSecond = WavefrontField.advanced(radius: 0, dt: 1.0)
        XCTAssertEqual(huge, oneSecond, accuracy: 0.000_001, """
            A 60 s `dt` advanced the field by \(huge) instead of the one-second cap \
            (\(oneSecond)). After a stall or a clock jump an uncapped step moves every ring to \
            the edge at once — a single large luminance edge, which is one flash, in a view whose \
            whole safety argument is that it never produces one.
            """)

        for bad in [Double.nan, Double.infinity, -1.0, 0.0] {
            let r = WavefrontField.advanced(radius: 0.5, dt: bad)
            XCTAssertTrue(r.isFinite && r >= 0.5, """
                `dt` = \(bad) produced radius \(r) from 0.5. A bad interval must fall back to a \
                small forward step, never to `nan` and never BACKWARDS — a ring that moves \
                inward is a wave converging on its source, which is the opposite of what this \
                view claims.
                """)
        }
    }

    // MARK: - Colour of the moment

    /// A single partial is its own centre of mass.
    func testCentroidOfOnePartialIsThatPartial() throws {
        let bins = 512
        let sampleRate = 48_000.0
        let hzPerBin = sampleRate / Double(bins * 2)
        var magnitudes = [Float](repeating: 0, count: bins)
        let k = 20                                       // 20 · 46.875 Hz ≈ 937.5 Hz
        magnitudes[k] = 1

        let centroid = try XCTUnwrap(WavefrontField.centroidHz(magnitudes: magnitudes,
                                                              sampleRate: sampleRate), """
            A spectrum with one clear partial returned no centroid at all. `nil` is reserved for \
            SILENCE — a moment with a tone in it must produce a frequency, or the ring it colours \
            comes out neutral while something was audibly playing.
            """)
        XCTAssertEqual(centroid, Double(k) * hzPerBin, accuracy: 0.5, """
            The centroid of a single partial is not that partial (\(centroid) vs \
            \(Double(k) * hzPerBin) Hz). With one non-zero bin the amplitude-weighted mean has \
            only one term; anything else means the bin→frequency mapping disagrees with the one \
            `SpectrumAnalysis` uses, and the ring colour would then disagree with the meter that \
            sits two rows above it.
            """)
    }

    /// Two equal partials put the centre of mass between them.
    func testCentroidSitsBetweenTwoEqualPartials() throws {
        let bins = 512
        let sampleRate = 48_000.0
        let hzPerBin = sampleRate / Double(bins * 2)
        var magnitudes = [Float](repeating: 0, count: bins)
        magnitudes[10] = 1
        magnitudes[30] = 1

        let centroid = try XCTUnwrap(WavefrontField.centroidHz(magnitudes: magnitudes,
                                                              sampleRate: sampleRate))
        XCTAssertEqual(centroid, 20 * hzPerBin, accuracy: 0.5, """
            Two equal partials at bins 10 and 30 gave a centroid of \(centroid) Hz instead of \
            the midpoint \(20 * hzPerBin) Hz. This is the assertion that separates a CENTROID \
            from a PEAK: a peak-picker would answer with one of the two partials. The panel's \
            readout is allowed to name the loudest partial; a ring is the whole sound at an \
            instant and must answer with its centre of mass.
            """)
    }

    /// Silence has no colour.
    func testSilenceHasNoCentroid() {
        let silent = [Float](repeating: 0, count: 512)
        XCTAssertNil(WavefrontField.centroidHz(magnitudes: silent, sampleRate: 48_000), """
            Silence produced a centroid. It has to be `nil`, because every fallback is a lie the \
            picture then tells: 0 Hz maps to the bottom of the colour scale, so a silent field \
            would emit red rings and look like a bass note nobody played.
            """)

        let noisy: [Float] = [0, .nan, .infinity, 0, 0]
        XCTAssertNil(WavefrontField.centroidHz(magnitudes: noisy, sampleRate: 48_000), """
            A spectrum whose only non-zero bins are non-finite produced a centroid. Those bins \
            must be skipped, leaving no usable weight — the same answer as silence, which is what \
            they actually represent.
            """)
    }

    /// The emission rate and the traverse time together bound how many rings can exist.
    ///
    /// ⛔ NOT A PIN ON EITHER CONSTANT — see this file's header. It pins their RELATIONSHIP to
    /// `maxFronts`, which is the one thing a future tuning pass can break without noticing: raise
    /// `emitRateHz` or `traverseSeconds` past the cap and the view silently starts dropping the
    /// oldest rings mid-flight, so fronts vanish partway out instead of fading at the edge. That
    /// looks like a bug in the physics and is a bug in the bookkeeping.
    func testTheRingBudgetCoversTheFrontsInFlight() {
        let inFlight = WavefrontField.emitRateHz * WavefrontField.traverseSeconds
        XCTAssertLessThanOrEqual(inFlight, Double(WavefrontField.maxFronts), """
            \(WavefrontField.emitRateHz) fronts/s over \(WavefrontField.traverseSeconds) s means \
            \(inFlight) rings are in flight, above the \(WavefrontField.maxFronts) the view will \
            hold. The oldest rings would be discarded before reaching the edge — they would \
            disappear in mid-air, which reads as a rendering fault rather than as the deliberate \
            fade this view uses. Raise `maxFronts` in the same commit as either constant.
            """)
    }
}
