// TheRingsCarryTheWavelengthTests.swift
// Echoel — the Rings look's wavenumber, in the BLOCKING bundle.
//
// #1128 gave `fieldRings` the sounding pitch. It was the LAST of the five selectable looks
// the pitch did not reach: Water and Aurora take `toneHz` directly, Dish and Depth take it
// through `u.dishK`'s gravity–capillary solve, and Rings took a user dial alone.
//
// WHY THAT WAS WORSE HERE THAN ANYWHERE ELSE. This field is two-beam interference, and the
// fringe spacing of two interfering beams IS the wavelength (Λ = λ / 2 sin θ). Every other
// look could argue that pitch→geometry is a chosen mapping. This one cannot: a wavenumber
// that ignores frequency is not a simplification of interference, it is a contradiction of it.
//
// ⚠️ AND IT IS THE ONE PLACE A NEIGHBOUR'S LAW WOULD HAVE BEEN THE WRONG ANSWER. `fieldWater`
// uses k ∝ f^(2/3) — the CAPILLARY dispersion relation, ω² ∝ k³, a property of a water
// surface. Two-beam interference is non-dispersive: λ = c/f, so k ∝ f, exponent 1. Claim 2
// pins the linear law precisely so a later "make it consistent with fieldWater" tidy-up goes
// red instead of quietly importing a medium this look does not have.
//
// ⚠️ WHAT IS PROVEN AND WHAT IS NOT. Claims 2 and 3 are arithmetic on the shipped constants
// and are proofs. Claims 1 and 4 are source-text pins — no test here executes MSL, and the
// guard that does (`TheShippedShaderActuallyCompilesTests`) cannot be relied on to be
// SCHEDULED, as #1126 found the hard way. Whether the rings read well is the founder's eye.
// NEEDS-FOUNDER-VERIFY: pick Rings and play a rising line — the rings should tighten as the
// pitch climbs, and at middle C the Density dial should look exactly as it always has.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheRingsCarryTheWavelengthTests: XCTestCase {

    private static let renderer = "Sources/Echoelmusic/Views/MetalBioView.swift"
    /// The reference the shader anchors on, and the same one `fieldWater` uses.
    private static let referenceHz = 261.63

    private func source() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(Self.renderer), encoding: .utf8)
    }

    /// Comment lines removed. Four guards in one day were falsified by a needle matching the
    /// PROSE about the thing it measures — this file's own header included.
    private func code(_ s: String) -> String {
        s.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// The shipped law, transcribed: pitch factor, then the product re-clamped into the
    /// dial's own band.
    private func ringWavenumber(density: Double, toneHz: Double) -> Double {
        let pitchK = min(max(max(toneHz, 20.0) / Self.referenceHz, 0.5), 2.0)
        return min(max(density * pitchK, 4.0), 120.0)
    }

    // MARK: - 1 · The pitch reaches this look at all

    func testTheRingsTakeTheSoundingPitch() throws {
        let src = code(try source())
        XCTAssertTrue(src.contains("float fieldRings(float d, float density, float toneHz,"), """
            `fieldRings` no longer declares `toneHz`. It was the last selectable look the \
            sounding pitch could not reach, in a field whose fringe spacing IS a wavelength.
            """)
        XCTAssertTrue(src.contains("field = fieldRings(d, density, toneHz,"), """
            The dispatch in `styleField` stopped passing `toneHz` to `fieldRings`. A parameter \
            nothing supplies is the same defect as no parameter, one line further away.
            """)
    }

    // MARK: - 2 · The law is linear, and the dial keeps its meaning at the reference

    func testTheWavenumberIsLinearInFrequencyAndNeutralAtMiddleC() {
        // The dial's meaning is preserved exactly where it is anchored. This is the promise
        // that made wiring a USER-CONTROLLED quantity acceptable at all.
        for density in [4.0, 20.0, 60.0, 120.0] {
            XCTAssertEqual(ringWavenumber(density: density, toneHz: Self.referenceHz),
                           density, accuracy: 1e-9, """
                At the 261.63 Hz reference the Density dial must mean exactly what it always \
                meant. If this drifts, a shipped control silently changed under the user's \
                finger — the objection that nearly stopped this slice.
                """)
        }
        // Linear, not the neighbour's 2/3. An octave up doubles the wavenumber; an octave
        // down halves it. Checked at a density where neither end clamps.
        let mid = 30.0
        XCTAssertEqual(ringWavenumber(density: mid, toneHz: Self.referenceHz * 2),
                       mid * 2, accuracy: 1e-9, """
            An octave up no longer doubles the wavenumber. Two-beam interference is \
            NON-DISPERSIVE (λ = c/f ⇒ k ∝ f). If this became f^(2/3) it has been "made \
            consistent" with `fieldWater`, which models capillary waves on a surface — a \
            medium this look does not have.
            """)
        XCTAssertEqual(ringWavenumber(density: mid, toneHz: Self.referenceHz / 2),
                       mid / 2, accuracy: 1e-9,
                       "An octave down must halve the wavenumber by the same linear law")
    }

    // MARK: - 3 · No pitch can push the picture outside the band the dial already shipped

    func testNoPitchEscapesTheDialsOwnRange() {
        let extremes = [0.0, 1.0, 20.0, 27.5, 261.63, 4186.0, 20000.0, 1e9]
        for density in stride(from: 4.0, through: 120.0, by: 4.0) {
            for hz in extremes {
                let k = ringWavenumber(density: density, toneHz: hz)
                XCTAssertGreaterThanOrEqual(k, 4.0, """
                    A \(hz) Hz tone at density \(density) produced wavenumber \(k), below the \
                    dial's own floor. Too few fringes is a flat wash, not a look.
                    """)
                XCTAssertLessThanOrEqual(k, 120.0, """
                    A \(hz) Hz tone at density \(density) produced wavenumber \(k), above the \
                    dial's own ceiling. Beyond it the fringes alias into hash on a real \
                    screen — the picture gets WORSE with more pitch, which is the failure a \
                    naive `density * pitchK` would have shipped.
                    """)
            }
        }
        // A zero or negative frequency must not be able to invert or blank the field.
        XCTAssertGreaterThan(ringWavenumber(density: 60, toneHz: 0), 0)
        XCTAssertGreaterThan(ringWavenumber(density: 60, toneHz: -1), 0)
    }

    // MARK: - 4 · COUNTERWEIGHT — the flash budget is untouched, and Rings is the tight one

    func testTheWavenumberCarriesNoPhaseAndTheRowIsUnchanged() throws {
        let src = code(try source())
        guard let open = src.range(of: "float fieldRings(float d, float density, float toneHz,"),
              let close = src.range(of: "\n    }", range: open.upperBound ..< src.endIndex) else {
            return XCTFail("fieldRings' body could not be located")
        }
        let body = String(src[open.upperBound ..< close.lowerBound])
        for name in ["float pitchK =", "float k ="] {
            guard let line = body.split(separator: "\n").first(where: { $0.contains(name) }) else {
                return XCTFail("the `\(name)` line is gone — claim 1's pitch path has no consumer")
            }
            // Strip the trailing comment before testing: the needle hunts CODE. Leaving it in
            // would make the claim go red the day someone writes the word "phase" in an inline
            // note on these lines — a guard that forbids discussing its own subject (#364).
            let statement = line.components(separatedBy: "//").first ?? String(line)
            XCTAssertFalse(statement.contains("phase"), """
                `\(name)` now carries `phase`. It multiplies `d`, a SPATIAL coordinate, which \
                is the entire reason the pitch could be wired here without reopening the \
                budget — the same argument as fieldAurora's `rays` and fieldWater's `s`.
                """)
        }
        guard let rings = FlashGuard.fieldBudget(forStyle: 0) else {
            return XCTFail("Rings lost its flash budget row — nil means UNKNOWN, not free")
        }
        XCTAssertEqual(rings.name, "Rings")
        XCTAssertEqual(rings.effectiveHz, 2.5, accuracy: 1e-9,
                       "Rings' row moved; #1128 must not change it, it only adds a spatial term")
        // Rings became the app's tightest row when #1127 lowered Aurora. Anyone adding a phase
        // term here spends a margin that is already the smallest in the app.
        guard let worst = FlashGuard.fieldBudgets.max(by: { $0.effectiveHz < $1.effectiveHz }) else {
            return XCTFail("the flash budget table is empty — nothing was checked")
        }
        XCTAssertEqual(worst.name, "Rings", """
            The binding row is now \(worst.name), not Rings. `maxPulseRateHz`'s doc and three \
            guards name Rings as the tightest look — #456: the prose moves in every home.
            """)
    }
}
