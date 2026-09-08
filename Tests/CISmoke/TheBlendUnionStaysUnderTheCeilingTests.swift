// TheBlendUnionStaysUnderTheCeilingTests.swift
// Echoel — the A↔B blend's flash union, in the BLOCKING bundle.
//
// ⛔ THE HOLE THIS CLOSES WAS WRITTEN DOWN BEFORE IT WAS FIXED, and that is the only reason
// it got fixed. `EveryLookHasAFlashBudgetTests` has said since #1114 that the per-look budgets
// "do NOT cover the A↔B blend union", and `FlashGuardTests` says the same. Both were right and
// both left it there.
//
// It is not theoretical. `mix(fieldA, fieldB, t)` at an intermediate `t` puts BOTH
// oscillations into one pixel's luminance, so that pixel sees the UNION of the two flash
// counts — the identical reasoning the shader already applies to the heartbeat bloom
// superposed on the field. And Aurora alone is EXACTLY 3.00 Hz with zero margin, sitting
// inside `LookBlendMap.defaultSequence`. Water↔Aurora at mid-slider is 4.70 Hz by that
// arithmetic: an ordinary drag of the shipped look slider, over the epilepsy limit.
//
// #1124's fix damps the FIELD phase rate — not the heartbeat bloom, which must stay on the
// body's rate — and only while two looks actually coexist.
//
// ⚠️ WHAT IS PROVEN AND WHAT IS NOT. Claims 1, 2 and 4 are arithmetic on the shipped law and
// are proofs. Claim 3 is a source-text pin: it checks that the renderer HANDS the damped
// phase to the fields and the undamped one to the bloom, which no arithmetic here can. And
// none of it is a photometric measurement — the union model is a WORST-CASE bound (two flash
// trains could interleave into fewer perceived transitions, never more), so bounding above is
// the safe direction, not an exact prediction. A device run remains the only way to see it.
// NEEDS-FOUNDER-VERIFY: drag the look slider from Water through Aurora — the motion should
// slow slightly in the middle and be unchanged at either end.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheBlendUnionStaysUnderTheCeilingTests: XCTestCase {

    /// Every ordered pair of selectable looks, including a look blended with itself.
    private var pairs: [(a: Int, b: Int)] {
        LookBlendMap.library.flatMap { first in
            LookBlendMap.library.map { (a: first.index, b: $0.index) }
        }
    }

    private func unionHz(_ a: Int, _ b: Int, _ t: Double) -> Double {
        let hzA = FlashGuard.fieldBudget(forStyle: a)?.effectiveHz ?? FlashGuard.maxFlashHz
        let hzB = FlashGuard.fieldBudget(forStyle: b)?.effectiveHz ?? FlashGuard.maxFlashHz
        let coexistence = 2 * min(t, 1 - t)
        return max(hzA, hzB) + coexistence * min(hzA, hzB)
    }

    // MARK: - 1 · No blend of any two looks can exceed the ceiling

    func testNoBlendOfTwoLooksExceedsTheWCAGCeiling() {
        XCTAssertFalse(pairs.isEmpty, "the look library is empty — nothing was checked")
        // A sweep, not just the midpoint: the union is piecewise linear in `t`, so its maximum
        // sits at t = 0.5, but sampling only there would miss a model that stopped being
        // piecewise linear after an edit.
        let samples = stride(from: 0.0, through: 1.0, by: 0.05)
        for pair in pairs {
            for t in samples {
                let damping = FlashGuard.blendPhaseDamping(styleA: pair.a, styleB: pair.b, blend: t)
                let damped = unionHz(pair.a, pair.b, t) * damping
                XCTAssertLessThanOrEqual(damped, FlashGuard.maxFlashHz + 1e-9, """
                    Styles \(pair.a)↔\(pair.b) at blend \(t) still reach \(damped) Hz after \
                    damping, over the WCAG ceiling of \(FlashGuard.maxFlashHz). Two mixed \
                    looks put both oscillations into one pixel, so the counts ADD. Do not \
                    raise the ceiling — the epilepsy limit is not a tuning knob, and Aurora \
                    already sits at exactly 3.00 with no headroom to borrow.
                    """)
                XCTAssertTrue(damping > 0 && damping <= 1, """
                    Damping for \(pair.a)↔\(pair.b) at \(t) is \(damping), outside (0, 1]. \
                    Above 1 would SPEED the field up; at or below 0 would freeze it, which \
                    reads as a hung renderer rather than a safety measure.
                    """)
            }
        }
    }

    // MARK: - 2 · Exactly 1.0 at either end — the bit-identical promise

    func testASingleLookIsUnaffected() {
        for pair in pairs {
            for t in [0.0, 1.0] {
                let damping = FlashGuard.blendPhaseDamping(styleA: pair.a, styleB: pair.b, blend: t)
                XCTAssertEqual(damping, 1.0, """
                    Damping at blend \(t) for \(pair.a)↔\(pair.b) is \(damping), not exactly 1. \
                    At either end of the slider `mix` shows ONE look, so nothing is superposed \
                    and nothing may change. This is not a nicety: the renderer multiplies the \
                    phase INCREMENT by this factor, and × 1.0 is exact in IEEE 754 — which is \
                    what lets #1124 ship without a device run for every user who does not \
                    blend. A value of 0.999… here silently alters the shipped picture.
                    """)
            }
        }
    }

    // MARK: - 3 · The renderer actually spends the damped phase on the FIELDS only

    func testTheFieldsRunOnTheDampedPhaseAndTheBloomDoesNot() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let renderer = try String(
            contentsOf: root.appendingPathComponent("Sources/Echoelmusic/Views/MetalBioView.swift"),
            encoding: .utf8)

        // Code-shaped needles, not concept-shaped: today's law, after four cases where a
        // needle hunting a WORD matched the prose written about the word.
        XCTAssertTrue(renderer.contains("float phase = u.fieldPhase * 6.2831853;"), """
            The shader's `phase` — the value handed to `styleField` — is no longer taken from \
            `u.fieldPhase`. If it went back to `u.pulsePhase`, the damping computed in \
            `draw(in:)` reaches nothing and the blend union is unbounded again while every \
            claim above still passes, because those test the LAW and not its use.
            """)
        XCTAssertTrue(renderer.contains("cos(beatPhase)"), """
            The heartbeat bloom no longer runs on `beatPhase`. It must use the UNDAMPED \
            `u.pulsePhase`: the beat is the body's rate, and slowing it would make the heart \
            read slower than it beats — the one thing this look is about. Damping belongs to \
            the field, never to the pulse.
            """)
        XCTAssertTrue(renderer.contains("FlashGuard.blendPhaseDamping("), """
            `draw(in:)` no longer calls `FlashGuard.blendPhaseDamping`. The law would then be \
            dead code with a passing test suite — the exact shape #541 and #527 describe, \
            where a mechanism is complete except for its caller.
            """)
    }

    // MARK: - 4 · COUNTERWEIGHT — an unknown style costs the worst case, not nothing

    func testAnUnbudgetedStyleIsTreatedAsTheWorstCase() {
        // 4 is Prism: compiled in the shader, retired from the UI, deliberately unbudgeted.
        let unknown = 4
        XCTAssertNil(FlashGuard.fieldBudget(forStyle: unknown),
                     "style \(unknown) gained a budget row — pick another unbudgeted style for this claim")
        // Blended with Aurora (3.00) it must be treated as 3.00 too, so the mid-blend union is
        // 6.00 and the damping is 0.5 — never 1.
        let damping = FlashGuard.blendPhaseDamping(styleA: unknown, styleB: 5, blend: 0.5)
        XCTAssertEqual(damping, 0.5, accuracy: 1e-12, """
            An unbudgeted style blended with Aurora produced damping \(damping). `nil` from \
            `fieldBudget(forStyle:)` means UNKNOWN, not FREE: a retired look has no row \
            because nobody re-derived it, not because it is calm. Treating it as 0 Hz would \
            make the one case nobody has measured the one case that is never damped.
            """)
    }
}
