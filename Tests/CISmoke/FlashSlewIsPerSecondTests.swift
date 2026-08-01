// FlashSlewIsPerSecondTests.swift
// Echoel — a flash-rate bound expressed per TICK is not a bound. In the BLOCKING bundle.
//
// WHAT THIS GUARDS (#370). `FlashGuard.slewedDimmer` caps the luminance move per CALL
// (`maxDelta: Double = 0.08`). Nothing in `FlashGuard` knows how often it is called — the two
// senders that call it set their own loop interval in two OTHER files
// (`Sync/ArtNetSender.swift`, `Sync/SACNSender.swift`, both `.milliseconds(33)`), and nothing
// binds the two together. Halve the interval and the flash rate doubles, silently.
//
// That matters because the bound is a SAFETY bound: WCAG 2.3.1 / the epilepsy ceiling this repo
// pins at `FlashGuard.maxFlashHz = 3.0`. `BioPhaser` already reached this conclusion and wrote it
// down at `Sync/BioPhaser.swift:35-41` — a per-tick cap lets a fast poll sneak extra flashes
// through, so the guarantee has to live as a per-SECOND velocity.
//
// ⛔ THE PARAGRAPH THAT STOOD HERE IS NOW FALSE AND IS KEPT AS A CORRECTION, not deleted. It read:
// "It adds the rate-correct primitive and NOTHING calls it yet … a green here means the primitive
// is correct, never that the senders are rate-safe — they are not, yet." That was true of #370 and
// stopped being true with #372, which wired both senders through it. A file whose header still
// says "nothing calls this" is exactly how a later reader concludes the wiring is still owed and
// does it twice.
//
// ⚠️ WHAT A GREEN HERE MEANS NOW. Both senders build their loop interval from
// `FlashGuard.senderTickMilliseconds` and cap with `FlashGuard.senderTickDelta` — the per-second
// velocity resolved at that same interval — so the two cannot drift apart. The binding is to the
// NOMINAL interval, not a measured one: a timer that fires late still gets the nominal step. That
// residual is stated in `FlashGuard` and is NOT covered by anything below.
//
// ⛔ AND IT DOES NOT FIX THE KNOWN AMPLITUDE GAP, which is deliberately out of scope: a RATE cap
// bounds ≤3 Hz only for flashes of amplitude ≳0.4, and `Sync/ArtNetSender.swift` records that
// residual as an accepted, Council-noted design. An adversarial pass over this cluster killed a
// finding that had re-reported that documented residual as an overlooked defect. Booking this
// slice as "flash limit repaired" would repeat exactly that overreach.
//
// ⚠️ Behavioural, not a source scan — `FlashGuard` is a pure Foundation enum, so every assertion
// below runs real arithmetic. There is no simulator here and no fixture: a green proves the
// maths, never that a lamp behaved.

import Foundation
import XCTest
@testable import Echoelmusic

final class FlashSlewIsPerSecondTests: XCTestCase {

    // MARK: - The constant is DERIVED from what ships, not invented

    /// The whole point of storing the rate as `shippedTickDelta / shippedTickSeconds` rather than
    /// as a hand-written "2.42": when the wiring slice replaces the per-tick default with this
    /// rate, the step at the shipped interval must come out UNCHANGED. A hand-rounded 2.42 would
    /// have produced 0.07986 — a 0.17 % behaviour change under a commit message claiming
    /// bit-identity. Small, invisible on a lamp, and precisely the kind of quiet false claim this
    /// repo keeps paying to undo.
    func testTheRateReproducesTheShippedPerTickStepExactly() {
        let step = FlashGuard.maxDelta(perSecond: FlashGuard.senderLuminancePerSecond,
                                       dt: FlashGuard.senderTickSeconds)
        XCTAssertEqual(step, FlashGuard.shippedTickDelta, accuracy: 1e-12, """
            The per-second rate no longer reproduces the shipped per-tick step at the shipped \
            tick interval. Wiring the senders through it would then change the fade speed while \
            claiming to change nothing. If the rate SHOULD change, that is a visible product \
            decision with a device look — make it deliberately and say so.
            """)
        // Sanity on the recorded facts themselves, so a later edit cannot quietly re-anchor the
        // derivation to numbers the senders do not actually use.
        XCTAssertEqual(FlashGuard.shippedTickDelta, 0.08, accuracy: 1e-12, """
            `shippedTickDelta` no longer records 0.08 — the default `maxDelta` of \
            `slewedDimmer`. These two must move together or the constant stops describing \
            anything real.
            """)
        XCTAssertEqual(FlashGuard.senderTickSeconds, 0.033, accuracy: 1e-12, """
            `senderTickSeconds` no longer resolves to 0.033 s — the interval BOTH senders start \
            their loop at. Since #372 this is the SOURCE of that interval, not a record of it, \
            so changing it changes the shipped fade speed. That is a device-visible decision.
            """)
        XCTAssertEqual(FlashGuard.senderTickMilliseconds, 33, """
            The sender tick interval changed. Both senders read it, so this is not a constant \
            edit — it is a change to how fast every fixture fades. Deliberate is fine; silent \
            is not.
            """)
        XCTAssertEqual(FlashGuard.calibrationTickSeconds, 0.033, accuracy: 1e-12, """
            `calibrationTickSeconds` moved. It is a FROZEN historical fact — the interval the \
            0.08 was measured against — not the live interval. Moving it with the live one \
            makes the rate cancel out and silently restores the per-tick behaviour. See the ⛔ \
            note on the constant.
            """)
    }

    // MARK: - The wiring (#372): interval and cap are ONE fact

    /// The bit-identity claim the wiring commit makes. `senderTickDelta` is the rate resolved at
    /// the shipped interval, so it must land back on the 0.08 the senders used before — otherwise
    /// #372 changed the fade speed while its message said it changed nothing.
    func testTheWiredStepIsTheShippedStepAtTheShippedInterval() {
        XCTAssertEqual(FlashGuard.senderTickDelta, FlashGuard.shippedTickDelta, accuracy: 1e-12, """
            The step both senders now pass to `slewedDimmer` is no longer the 0.08 they used \
            before the rate wiring. Every fixture fade changed speed. If that is intended it is \
            a product decision with a device look, not a refactor.
            """)
    }

    /// The step must FOLLOW the interval. This is the whole defect: before #372 a halved interval
    /// doubled the flash rate. Now it halves the step instead, and the fade takes the same
    /// wall-clock time. Asserted against the arithmetic, not against a second hardcoded number.
    func testHalvingTheIntervalHalvesTheStepInsteadOfDoublingTheFlashRate() {
        let full = FlashGuard.maxDelta(perSecond: FlashGuard.senderLuminancePerSecond,
                                       dt: FlashGuard.senderTickSeconds)
        let half = FlashGuard.maxDelta(perSecond: FlashGuard.senderLuminancePerSecond,
                                       dt: FlashGuard.senderTickSeconds / 2)
        XCTAssertEqual(half, full / 2, accuracy: 1e-12, """
            A halved tick no longer produces a halved step. The rate has stopped being \
            rate-invariant, which returns the codebase to the exact defect #370/#372 closed: a \
            faster send loop flashing faster.
            """)
        // Ticks-per-full-travel doubles, seconds-per-full-travel does not — that is the invariant
        // a reader should carry away, so it is asserted rather than described.
        let ticksAtFull = 1.0 / full
        let ticksAtHalf = 1.0 / half
        XCTAssertEqual(ticksAtHalf, ticksAtFull * 2, accuracy: 1e-9, """
            A full 0→1 travel no longer takes twice as many ticks at half the interval, so the \
            wall-clock fade duration is not preserved across a rate change.
            """)
    }

    /// ⛔ THE MISTAKE THIS TEST EXISTS FOR, AND IT WAS MINE, CAUGHT BEFORE THE COMMIT. My first
    /// #372 draft wrote `senderLuminancePerSecond = shippedTickDelta / senderTickSeconds` — the
    /// LIVE interval. With that denominator the rate is not a rate: halve the interval and the
    /// rate doubles, so `rate × interval` stays 0.08 and the flash rate doubles exactly as
    /// before. The slice would have shipped a rate-shaped constant over the unchanged defect.
    /// Both arithmetic tests above passed on it, because they vary `dt` while holding the rate
    /// fixed — no runtime assertion can see this, since both constants are `let`. So the check
    /// has to be on the DEFINITION, which is why this one reads source instead of running maths.
    func testTheRateIsAnchoredToTheFrozenCalibrationNotTheLiveInterval() throws {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let path = root.appendingPathComponent("Sources/Echoelmusic/Studio/FlashGuard.swift")
        guard let src = try? String(contentsOf: path, encoding: .utf8) else {
            throw XCTSkip("FlashGuard.swift not readable at \(path.path) — source scan skipped")
        }
        let marker = "senderLuminancePerSecond: Double ="
        guard let r = src.range(of: marker) else {
            return XCTFail("""
                `senderLuminancePerSecond` is no longer declared as a `Double` constant in \
                FlashGuard.swift. If it became computed, this check must be rewritten to \
                inspect the new form — deleting it re-opens the cancellation trap described \
                above.
                """)
        }
        let definition = String(src[r.upperBound...].prefix(120))
        XCTAssertTrue(definition.contains("calibrationTickSeconds"), """
            The luminance rate is no longer derived from `calibrationTickSeconds`: \
            …\(definition.prefix(70))… If its denominator is the LIVE interval, the rate \
            cancels and a faster loop flashes faster again with every other test still green.
            """)
        XCTAssertFalse(definition.contains("senderTickSeconds"), """
            The luminance rate now references `senderTickSeconds` (the LIVE interval): \
            …\(definition.prefix(70))… That is precisely the cancellation this slice was \
            written to avoid.
            """)
    }

    /// The structural half, and the one that actually rots: a sender could go back to writing its
    /// own `.milliseconds(33)`. That compiles, passes every arithmetic test above, and silently
    /// re-opens the split — the constant would then describe a loop nobody runs.
    func testNeitherSenderHardcodesItsOwnTickInterval() throws {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        for name in ["ArtNetSender", "SACNSender"] {
            let path = root.appendingPathComponent("Sources/Echoelmusic/Sync/\(name).swift")
            guard let src = try? String(contentsOf: path, encoding: .utf8) else {
                throw XCTSkip("\(name).swift not readable at \(path.path) — source scan skipped")
            }
            let starts = src.components(separatedBy: "loop.start(interval:")
            XCTAssertGreaterThan(starts.count, 1, """
                `\(name).swift` no longer starts a polling loop at all. If the sender moved to \
                another timing mechanism, that mechanism needs its own binding to \
                `FlashGuard.senderTickMilliseconds` — and this test needs rewriting to check it.
                """)
            for fragment in starts.dropFirst() {
                let call = String(fragment.prefix(90))
                XCTAssertTrue(call.contains("FlashGuard.senderTickMilliseconds"), """
                    `\(name).swift` starts its loop from a literal instead of \
                    `FlashGuard.senderTickMilliseconds`: …\(call.prefix(60))… The interval and \
                    the flash cap are then two facts again, and speeding up this loop raises the \
                    flash rate with nothing going red — the defect #372 exists to close.
                    """)
            }
        }
    }

    /// ⛔ NOT `BioPhaser`'s 0.5/s. The two constants sit in different types, mean the same
    /// physical quantity, and differ by nearly 5×. That is a trap for exactly the reader who
    /// notices it and "unifies" them — which would slow every fixture fade to a fifth of its
    /// shipped speed. Pinned so the gap is a decision, not an accident, in both directions.
    func testTheSenderRateIsDeliberatelyLooserThanThePhaserRate() {
        XCTAssertGreaterThan(FlashGuard.senderLuminancePerSecond, BioPhaser.maxLuminancePerSecond, """
            The sender luminance rate is no longer looser than `BioPhaser`'s. If the two were \
            deliberately unified, that is a visible change to how fast every lamp fades — it \
            needs a founder look, and this test should be rewritten to state the new intent \
            rather than deleted.
            """)
        XCTAssertEqual(FlashGuard.senderLuminancePerSecond / BioPhaser.maxLuminancePerSecond,
                       4.848, accuracy: 0.01, """
            The gap between the two per-second luminance rates changed. It is currently ~4.85×, \
            and the size of that gap is the reason they must not be folded into one constant.
            """)
    }

    // MARK: - dt sanitisation: the half that is actually about safety

    /// A clock jump or a resumed-from-background stall hands the caller a huge `dt`. Uncapped,
    /// `rate * dt` authorises an arbitrarily large single luminance leap — which is one flash
    /// edge, i.e. the exact thing the slew limiter exists to prevent. Same 1.0 s cap and same
    /// 0.1 s fallback as `BioPhaser.step`, so the two sanitise identically.
    func testALargeOrHostileDtCannotAuthoriseAnUnboundedLeap() {
        let rate = FlashGuard.senderLuminancePerSecond
        let atCap = FlashGuard.maxDelta(perSecond: rate, dt: 1.0)
        for wild in [2.0, 60.0, 3600.0, Double.greatestFiniteMagnitude] {
            XCTAssertEqual(FlashGuard.maxDelta(perSecond: rate, dt: wild), atCap, accuracy: 1e-12, """
                A dt of \(wild) s produced a step larger than the 1 s cap. After a stall the \
                limiter would then permit a full-range jump in one call — a single flash edge, \
                which is what the cap exists to forbid.
                """)
        }
    }

    /// Non-finite and non-positive `dt` fall back to 0.1 s — NOT to zero. Zero would freeze the
    /// dimmer at its last value on the first bad frame, which reads on stage as a dead fixture;
    /// the fallback keeps the light moving at a bounded, known rate.
    func testNonFiniteOrNonPositiveDtFallsBackToATenthOfASecond() {
        let rate = FlashGuard.senderLuminancePerSecond
        let expected = FlashGuard.maxDelta(perSecond: rate, dt: 0.1)
        for bad in [Double.nan, .infinity, -Double.infinity, 0, -0.5] {
            XCTAssertEqual(FlashGuard.maxDelta(perSecond: rate, dt: bad), expected, accuracy: 1e-12, """
                A dt of \(bad) did not fall back to 0.1 s. NaN reaching a multiplication here \
                poisons the dimmer permanently — the NaN-through-clamp class this repo has \
                already shipped a permanent-silence bug for.
                """)
        }
        XCTAssertGreaterThan(expected, 0, """
            The 0.1 s fallback produces a zero step, so a single bad frame would freeze the \
            fixture at its last value instead of continuing at a bounded rate.
            """)
    }

    /// A hostile RATE is the mirror of a hostile dt and gets the same treatment. Nothing calls
    /// this with a computed rate today; that is exactly when a guard is cheap to add.
    func testANonFiniteOrNegativeRateYieldsNoMovementRatherThanNaN() {
        for bad in [Double.nan, -1.0, -Double.infinity] {
            let step = FlashGuard.maxDelta(perSecond: bad, dt: 0.033)
            XCTAssertTrue(step.isFinite, "A rate of \(bad) produced a non-finite step.")
            XCTAssertEqual(step, 0, accuracy: 1e-12, """
                A rate of \(bad) produced a non-zero step. A negative cap would let \
                `limitedLuminance` move AWAY from its target — a slew limiter running backwards.
                """)
        }
    }

    // MARK: - The bound this is all in service of

    /// The reason the rate is allowed to be as loose as it is: even at the sender rate, a full
    /// 0→1→0 luminance round trip is slower than one third of a second, so the fixture cannot
    /// present more than 3 such cycles per second. This is the arithmetic `FlashGuard.maxFlashHz`
    /// names, done against the constant rather than asserted in a comment.
    func testAFullUpDownPairStaysUnderTheThreeHertzCeiling() {
        let secondsForFullTravel = 1.0 / FlashGuard.senderLuminancePerSecond
        let pairSeconds = 2 * secondsForFullTravel
        // Hoisted out of the message: an arithmetic expression inside a `\(...)` inside a
        // multi-line literal is the shape that made this bundle's build too expensive to
        // type-check on #287. Plain property reads only, inside the string.
        let pairHz = 1.0 / pairSeconds
        let ceilingSeconds = 1.0 / FlashGuard.maxFlashHz
        XCTAssertLessThanOrEqual(pairHz, FlashGuard.maxFlashHz, """
            A full 0→1→0 luminance pair now completes in \(pairSeconds) s (\(pairHz) Hz), \
            faster than the \(ceilingSeconds) s that the \(FlashGuard.maxFlashHz) Hz epilepsy \
            ceiling in `FlashGuard.maxFlashHz` allows. Raising the luminance rate is not a \
            tuning knob — it is the safety bound.
            """)
    }
}
