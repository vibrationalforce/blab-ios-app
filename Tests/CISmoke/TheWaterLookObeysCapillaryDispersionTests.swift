//
//  TheWaterLookObeysCapillaryDispersionTests.swift
//  Echoelmusic — CISmoke
//
//  #1078 — the Water look's wavelength is the SOUNDING PITCH's, not the breath's.
//
//  WHY THIS LOOK AND NOT THE CYMATICS ONE. The founder asked for "echte
//  Wasserklangbilder". The obvious target was `fieldChladni`, which is compiled and
//  whose pitch→pattern map really is a hash. It was the wrong target: style 1 is
//  unreachable through three independent filters — `LookBlendMap.sequence(from:)` drops
//  any index outside `library`, the customiser iterates `LookBlendMap.library`, and the
//  launch snap rewrites a hand-edited index away — so repairing it changes zero pixels
//  for zero users. `fieldWater` is index 3, sits in `LookBlendMap.defaultSequence`, and
//  carried the SAME class of defect in a picture everybody actually sees: its spatial
//  frequency was `mix(4.0, 7.0, breath)`, so the wavelength of a WATER look was set by
//  breathing and the sounding pitch never reached the function at all.
//
//  THE PHYSICS THIS PINS, and only this. A shallow dish on a speaker is a Faraday
//  parametric instability; for h ≈ 2–5 mm every audio ripple is deep water, so the
//  surviving wavenumber follows the capillary branch k ∝ f^(2/3), i.e. λ ∝ f^(−2/3).
//  One octave up ⇒ the net is 2^(2/3) ≈ 1.5874× finer. THE EXPONENT is the physical
//  content and is what claim 2 asserts. The ANCHOR is a chosen dish size and is
//  deliberately NOT pinned to a value — pinning it would freeze an artistic choice as
//  if it were a law, which is the inverse of this file's point.
//
//  ⚠️ SOURCE-TEXT SCAN. Nothing here compiles Metal or renders a pixel. It asserts that
//  the shipped shader text carries the law and that the arithmetic of the constants it
//  actually contains stays inside the screen's sampling limits. Whether the water LOOKS
//  right at a bass note is a device probe and stays open.
//  NEEDS-FOUNDER-VERIFY: play a low bass note and then a lead two octaves up — the net
//  must visibly coarsen and refine with the pitch, and neither end may go flat or moiré.
//
//  ⚠️ `SourceText.codeOnly` resets string state per LINE, so the Metal `//` comments
//  inside the shader's Swift string literal are stripped as if they were code. Every
//  needle below therefore sits LEFT of any `//` on its line — checked, not hoped
//  (the same note `GlitterCannotBecomeAFlashTests` had to write for this file).
//

import Foundation
import XCTest

final class TheWaterLookObeysCapillaryDispersionTests: XCTestCase {

    private static let viewPath = "Sources/Echoelmusic/Views/MetalBioView.swift"

    private func shader() throws -> String {
        var dir = URL(fileURLWithPath: #filePath)
        while dir.pathComponents.count > 1 {
            if FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("Package.swift").path) { break }
            dir = dir.deletingLastPathComponent()
        }
        let url = dir.appendingPathComponent(Self.viewPath)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("ANCHOR MISSING: \(Self.viewPath) could not be read — a missing anchor "
                    + "is a finding, not a pass.")
            return ""
        }
        return SourceText.codeOnly(text)
    }

    /// The one line the whole file hangs on, read once so three claims share an anchor.
    private func scaleLine(_ code: String) throws -> String {
        guard let r = code.range(of: "float scale = clamp(") else {
            XCTFail("ANCHOR MISSING: fieldWater's `float scale = clamp(` line is gone or "
                    + "reworded. If the law moved to the CPU as a uniform, re-anchor this "
                    + "file there and say so in the doc block — do not delete the claims.")
            return ""
        }
        let rest = code[r.lowerBound...]
        guard let end = rest.firstIndex(of: ";") else { return "" }
        return String(rest[..<end])
    }

    // 1 — THE PITCH REACHES THE LOOK. Signature, call site and the scale line, plus the
    // absence of the breath-driven scale it replaced. All four on one claim because they
    // are one wiring: any three without the fourth is a half-connected law.
    func testTheWavelengthIsDrivenByTheSoundingPitch() throws {
        let code = try shader()
        XCTAssertTrue(
            code.contains("float fieldWater(float2 p, float toneHz, float phase, float coh, float breath)"),
            "fieldWater no longer takes `toneHz`. Its wavelength is then set by something "
            + "other than the sounding pitch, and the doc block above it claims otherwise.")
        XCTAssertTrue(code.contains("fieldWater(pf, toneHz, phase, coh, breath)"),
                      "styleField stopped passing `toneHz` to fieldWater — the parameter "
                      + "exists and nothing fills it.")
        XCTAssertTrue(try scaleLine(code).contains("toneHz"),
                      "fieldWater's `scale` no longer reads `toneHz`; the capillary law "
                      + "has been disconnected from the pitch.")
        XCTAssertFalse(code.contains("float scale = mix(4.0, 7.0, breath)"),
                       "The pre-#1078 breath-driven scale is back. Breath is the DRIVE "
                       + "AMPLITUDE in a Faraday cell, not the wavelength — putting it back "
                       + "on `scale` swaps the two knobs again.")
    }

    // 2 — THE EXPONENT IS THE PHYSICS. Read the literal out of the shipped line and do the
    // arithmetic on it, rather than asserting a spelling: `0.6666667`, `2.0/3.0` and
    // `0.66666667` are the same law and must all pass, while a linear or logarithmic
    // "simplification" must not. Tolerance is 0.5 % on the OCTAVE RATIO, which is the
    // quantity a person can measure on two still frames with a ruler.
    func testOneOctaveMakesTheNetTwoThirdsOfAPowerFiner() throws {
        let line = try scaleLine(try shader())
        guard !line.isEmpty else { return }
        guard let exponent = Self.lastNumber(in: line) else {
            XCTFail("No numeric exponent found in fieldWater's scale line: \(line)")
            return
        }
        let octaveRatio = pow(2.0, exponent)
        let capillary = pow(2.0, 2.0 / 3.0)          // 1.5874…
        XCTAssertEqual(octaveRatio, capillary, accuracy: capillary * 0.005,
                       "One octave scales the Water net by \(octaveRatio)×, not the "
                       + "capillary 2^(2/3) = \(capillary)×. A Faraday surface on a "
                       + "2–5 mm dish is deep water for every audio ripple, so the "
                       + "gravity–capillary relation collapses to k ∝ f^(2/3). An exponent "
                       + "of 1.0 (linear) or 0.5 would render a net that changes with pitch "
                       + "but is no longer this physical law, and the doc block, this file "
                       + "and any user-facing copy would all have to change with it.")
    }

    // 3 — THE PICTURE STAYS BETWEEN THE TWO LIMITS THE SCREEN IMPOSES. Neither end of the
    // clamp may be flat (a wave longer than the frame is a gradient, not a net) nor
    // aliased (a period below a few pixels is moiré, and moiré is a flash risk, not just
    // ugly). Computed from the shipped constants, so a future retune of the anchor or the
    // clamps is checked instead of trusted. `pf` spans 2.0 units across the frame.
    func testNeitherClampEndGoesFlatOrAliases() throws {
        let line = try scaleLine(try shader())
        guard !line.isEmpty else { return }
        let numbers = Self.numbers(in: line)
        guard numbers.count >= 2 else {
            XCTFail("Could not read the clamp bounds from: \(line)")
            return
        }
        let hi = numbers[numbers.count - 1]           // clamp upper bound
        let lo = numbers[numbers.count - 2]           // clamp lower bound
        XCTAssertLessThan(lo, hi, "The clamp bounds are inverted or misread: \(line)")

        let span = 2.0                                // pf ∈ [-1, 1]
        let slowestPeriod = 2.0 * Double.pi / lo
        XCTAssertLessThanOrEqual(
            slowestPeriod, 1.25 * span,
            "At the low clamp the primary train's period is \(slowestPeriod) coordinate "
            + "units against a frame of \(span) — less than one ripple fits, so a bass note "
            + "renders a gradient rather than a water net.")

        // The FASTEST of the three trains carries the aliasing risk, not the primary one.
        let fastestRatio = 1.545
        XCTAssertTrue(line.contains("clamp("), "scale line lost its clamp: \(line)")
        let fastestPeriod = 2.0 * Double.pi / (hi * fastestRatio)
        XCTAssertGreaterThan(
            fastestPeriod, 0.05,
            "At the high clamp the fastest train's period is \(fastestPeriod) coordinate "
            + "units — about \(Int(fastestPeriod / span * 1170)) px on a phone-width axis. "
            + "Below roughly 0.05 units the net samples into moiré.")
    }

    // 4 — THE FLASH BUDGET IS UNCHANGED BY STRUCTURE, NOT BY LUCK — and this is the claim
    // that makes #1078 a two-file change instead of a safety re-derivation. `FlashGuardTests`
    // budgets Water at (0.68, folds: false) → 1.70 Hz, from the PRODUCT of two phase-bearing
    // factors t = 0.4·phase and 0.7t. `scale` multiplies the SPATIAL coordinate only, and
    // breath carries no phase. So pin the four phase-bearing terms verbatim: if any of them
    // moves, that table row is stale and this message says where.
    //
    // COUNTERWEIGHT (#367). Claims 1–3 are all satisfied by a shader that deleted `breath`
    // from this look entirely — which would silence the one bio channel in it while every
    // scan above stayed green. The last assertion is the counterweight: breath must still
    // reach the field, on the amplitude where the physics puts it.
    func testTheFlashBearingTermsAreUntouched() throws {
        let code = try shader()
        XCTAssertTrue(code.contains("float t = phase * 0.4;"),
                      Self.budgetMessage)
        XCTAssertTrue(code.contains("sin(p.x * scale + t) * cos(p.y * (scale * 0.818) - t * 0.7)"),
                      Self.budgetMessage)
        XCTAssertTrue(code.contains("sin(length(p) * (scale * 1.545) - t * 1.1)"),
                      Self.budgetMessage)
        XCTAssertTrue(code.contains("sin((p.x + p.y) * (scale * 0.727) + t * 0.5)"),
                      Self.budgetMessage)
        XCTAssertTrue(code.contains("clamp(0.5 + mix(0.12, 0.24, breath) * w, 0.0, 1.0)"),
                      "Breath no longer reaches fieldWater's amplitude. The look would then "
                      + "have NO bio channel at all — every other claim in this file would "
                      + "still pass, which is why this assertion exists. In a Faraday cell "
                      + "the drive amplitude is where breath belongs; if it moves elsewhere, "
                      + "re-derive the flash budget, because a phase-bearing partner would "
                      + "add a sideband.")
    }

    private static let budgetMessage = """
        A phase-bearing term in fieldWater changed. `FlashGuardTests\
        .testEveryReachableLookObeysTheThreeHzLaw` budgets Water at (0.68, folds: false) \
        → 1.70 Hz, derived from t = 0.4·phase multiplied by cos(… − 0.7t): a product of two \
        phase-bearing factors, giving a 0.4 + 0.28 sideband. Re-derive that row in the same \
        commit, and check the fold rule too — an abs() or a square on a phase-bearing \
        quantity doubles the count. The Water row is NOT free headroom: Aurora already sits \
        at exactly 3.00 Hz against the 3.0 Hz WCAG law with zero margin.
        """

    private static func numbers(in text: String) -> [Double] {
        var out: [Double] = []
        var current = ""
        for ch in text {
            if ch.isNumber || ch == "." {
                current.append(ch)
            } else {
                if let v = Double(current) { out.append(v) }
                current = ""
            }
        }
        if let v = Double(current) { out.append(v) }
        return out
    }

    /// The exponent is the last TOP-LEVEL argument of `pow(…)` on the scale line.
    ///
    /// ⛔ The first draft took `firstIndex(of: ")")` after `pow(`, which stops at the inner
    /// `max(toneHz, 20.0)` and reads the exponent as 20.0 — a guard that would have gone RED
    /// on a correct tree and been "fixed" by loosening the tolerance. Depth-count instead:
    /// a needle that parses nested calls has to actually parse them.
    private static func lastNumber(in text: String) -> Double? {
        guard let p = text.range(of: "pow(") else { return nil }
        var depth = 1
        var arg = ""
        var i = p.upperBound
        while i < text.endIndex {
            let c = text[i]
            if c == "(" { depth += 1 }
            if c == ")" {
                depth -= 1
                if depth == 0 { break }
            }
            arg.append(c)
            i = text.index(after: i)
        }
        guard depth == 0 else { return nil }
        var inner = 0
        var last = ""
        for c in arg {
            if c == "(" { inner += 1 }
            if c == ")" { inner -= 1 }
            if c == "," && inner == 0 { last = "" } else { last.append(c) }
        }
        return numbers(in: last).last
    }
}
