// SpectralSeamTwinTests.swift
// Echoel — the GPU's tone→colour and the CPU's must not disagree by transcription.
//
// WHY THIS FILE EXISTS. `MetalBioView`'s `toneColour` is a hand-written Metal twin of
// `SpectralColor.toneLinearRGB`, and it carried `tViolet = 0.89306425` under a comment that
// called it an "EXACT twin". The true `log2(780/420)` is 0.8930847960834881 — wrong from the
// fifth decimal. The GPU's violet boundary sat at 420.006 nm instead of 420.000 and its
// purple-line seam was 2.06e-5 octaves wider than the CPU's.
//
// Nobody would ever have seen it. That is the point, and it is the reason it survived: the
// error was BELOW perception and ABOVE the reach of every test, because the shader is a Swift
// string compiled on the GPU at launch. Neither gate can typecheck it; a wrong token there is a
// runtime shader-compile failure (a black visual on device) or, as here, a silently wrong
// number. The only defence available is to stop hand-typing derived constants: the seam
// boundaries now live in `SpectralColor` and are INTERPOLATED into the Metal source.
//
// So this file pins the two things that interpolation still leaves open:
//   1. the Metal TOKEN parses back to the Double the CPU actually uses, and
//   2. it does so to the precision Metal has — float32, since MSL has no `double`.
//
// ⚠️ SCOPE, honestly. This proves the two SEAM CONSTANTS agree. It does NOT prove the shader's
// `toneColour` is a faithful twin of `toneLinearRGB` in any other respect — the fold, the CIE
// lobes and the purple-line lift are all still duplicated by hand, and no test in this repo can
// execute Metal. Verifying those needs an eye on a device. Do not read a green run here as
// "CPU and GPU agree"; read it as "the one part that could be checked, is checked".

import XCTest
@testable import Echoelmusic

final class SpectralSeamTwinTests: XCTestCase {

    /// THE ONE THAT MATTERS — and the one that would have gone red on the shipped literal.
    ///
    /// Compared as `Float`, not `Double`, because that is the comparison the GPU performs:
    /// Metal has no `double`, so the token is rounded to float32 before it is ever used.
    /// A `Double`-exact bar would be unmeetable by any decimal literal and would have to be
    /// loosened to an `accuracy:` — at which point the tolerance, not the physics, decides
    /// what counts as agreement. Float-exact needs no tolerance and is the real requirement.
    func testTheMetalSeamTokensRoundTripToTheConstantsTheCPUUses() {
        guard let red = Double(SpectralColor.tRedMetalLiteral),
              let violet = Double(SpectralColor.tVioletMetalLiteral) else {
            return XCTFail("a Metal seam token no longer parses as a number")
        }
        XCTAssertEqual(Float(red), Float(SpectralColor.tRed))
        XCTAssertEqual(Float(violet), Float(SpectralColor.tViolet))
    }

    /// The tokens are pasted verbatim into Metal source that is compiled at RUNTIME, so a
    /// stray character is a black visual on a device, not a build error. Same guard
    /// `FlashGuardTests` puts on `ringsPhaseDampingLiteral`: digits and a dot, nothing else —
    /// no locale comma, no exponent, no `f` suffix.
    func testTheMetalSeamTokensAreValidMetalFloatLiterals() {
        for token in [SpectralColor.tRedMetalLiteral, SpectralColor.tVioletMetalLiteral] {
            XCTAssertFalse(token.isEmpty)
            XCTAssertTrue(token.allSatisfy { $0.isNumber || $0 == "." },
                          "\(token) is not a plain Metal float literal")
        }
    }

    /// The constants must stay DERIVED, not become two more hand-typed numbers a rename could
    /// drift. Asserted against the physics they claim to be — one light octave anchored at
    /// 780 nm, with the pure-spectral span running from 640 nm to 420 nm.
    func testTheSeamBoundariesAreTheOctavePositionsOfTheSpectralEdges() {
        XCTAssertEqual(SpectralColor.tRed, Foundation.log2(780.0 / 640.0), accuracy: 1e-15)
        XCTAssertEqual(SpectralColor.tViolet, Foundation.log2(780.0 / 420.0), accuracy: 1e-15)
        // Ordered and strictly inside one octave, or the span/seam split in `toneLinearRGB`
        // inverts and the purple line swallows the spectrum.
        XCTAssertLessThan(SpectralColor.tRed, SpectralColor.tViolet)
        XCTAssertGreaterThan(SpectralColor.tRed, 0)
        XCTAssertLessThan(SpectralColor.tViolet, 1)
    }

    /// The fold is what "physically correctly octaved" means: two tones an octave apart are the
    /// SAME position in the light circle, so they render the same colour. Checked across five
    /// octaves of A — this is the property the founder asked about, and until now nothing
    /// asserted it in the blocking bundle.
    func testTonesAnOctaveApartGetTheSameColour() {
        let base = SpectralColor.toneLinearRGB(forToneHz: 55.0)
        for octave in 1...5 {
            let up = SpectralColor.toneLinearRGB(forToneHz: 55.0 * pow(2.0, Double(octave)))
            XCTAssertEqual(up.r, base.r, accuracy: 1e-9, "A\(octave) drifted in red")
            XCTAssertEqual(up.g, base.g, accuracy: 1e-9, "A\(octave) drifted in green")
            XCTAssertEqual(up.b, base.b, accuracy: 1e-9, "A\(octave) drifted in blue")
        }
    }

    /// No pitch may render BLACK. This is the whole reason the circle was closed across the
    /// purple line: with the naive fold, at A4 = 440 the pitch class F landed where CIE
    /// response goes to zero and disappeared from the visual (founder, 2026-07-12 — "da fehlt
    /// jetzt gerade das F komplett als Farbe"). Swept finely enough to land inside the seam
    /// many times over, not just on the twelve equal-tempered classes.
    func testNoPitchInTheCircleRendersBlack() {
        for step in 0..<240 {
            let hz = 220.0 * pow(2.0, Double(step) / 240.0)      // one full octave, 240 points
            let c = SpectralColor.toneLinearRGB(forToneHz: hz)
            XCTAssertGreaterThan(max(c.r, max(c.g, c.b)), 0.05,
                                 "a tone at \(hz) Hz renders as good as black")
        }
    }
}
