// AReclaimedFloorIsNotAddedToTheWaitTests.swift
// Echoel — the re-seed floor is a deadline to collapse into, never a debt to add. BLOCKING. #398.
//
// WHAT THIS PINS, IN ONE SENTENCE: an automatic re-seed that is already claimed for a later
// instant must PULL a second trigger to that instant, and must not delay a user edit at all.
//
// ⛔ BOTH HALVES WERE WRONG IN THE SHIPPED CODE, AND BOTH CONTRADICTED THE COMMENT DIRECTLY
// ABOVE THEM. `scheduleGenerate` kept one `Date` (`lastSeedAt`) for two different facts — "a
// take was generated at T" and "the next automatic re-seed may not run before T" — and then
// subtracted it as though it were always the first:
//
//   auto:  delay = minAutoSeedGap - (now - lastSeedAt)
//   user:  delay = minUserGap     - (now - lastSeedAt)
//
// With `lastSeedAt` holding a FUTURE claim, `now - lastSeedAt` is negative and both lines ADD
// the unspent claim to a full fresh floor. The named case in the comment — lock-snap and evolve
// tick landing together — moved a re-seed claimed for t+5 s out to t+11 s instead of collapsing
// into it, and every further trigger inside the window added another gap, unbounded. On the user
// side, changing the genre one second into a 6 s claim delayed the sound by six seconds, under a
// doc line promising "a user edit stays instant".
//
// ⚠️ WHY THIS IS ALSO A DIAGNOSTIC FIX AND NOT ONLY A FEEL FIX. `generate(…)` prints `sinceLast=`
// from the SAME variable (#390, and `ReSeedIntervalIsMeasuredBeforeItIsResetTests` pins the
// read-before-write ordering that makes it printable at all). While a claim could live in that
// variable, the printed number was the distance to a re-seed that had not happened — negative or
// far too small. The founder is being asked for exactly that log to settle whether the
// "unharmonisch" verdict is re-seed overlap. A field that can lie is worse than no field.
//
// ⚠️ WHY THE ARITHMETIC IS BEHAVIOURAL HERE AND THE WIRING IS A SCAN. `RegenSchedule` is a pure
// value type, so the numbers below are driven for real — these are not source greps. But whether
// `EchoelStudioView` actually ASKS it is a fact about a SwiftUI view method that this bundle
// cannot instantiate, so that half is a scan. The two are deliberately in one file: a correct
// core nobody calls is the exact failure this repo has paid for before (a "verified" door with a
// dead caller), and splitting them would let one go green while the other rots.
//
// NEEDS-FOUNDER-VERIFY: change the genre while a take is playing. The new sound must follow
// within about half a second, not after a pause long enough to wonder whether the tap landed.

import Foundation
import XCTest
@testable import Echoelmusic

final class AReclaimedFloorIsNotAddedToTheWaitTests: XCTestCase {

    // MARK: - The automatic side: a standing claim is a deadline, not a debt

    /// ⛔ THE HEADLINE REGRESSION. Two automatic triggers inside one window must land on the SAME
    /// instant. The old arithmetic pushed the second one a full gap PAST the first.
    func testASecondAutoTriggerCollapsesIntoTheClaimInsteadOfMovingIt() {
        // A take ran 1 s ago; the first trigger therefore claims a floor 5 s out.
        let first = RegenSchedule.decide(auto: true, sinceLastSeed: 1, untilFloor: -1)
        XCTAssertEqual(first.delay, 5, accuracy: 1e-9, """
            the first automatic trigger no longer waits out the remainder of the gap \
            (\(RegenSchedule.minAutoSeedGap) s minus the 1 s already elapsed).
            """)
        XCTAssertEqual(first.claimFloorIn, 5, """
            the automatic branch no longer claims the floor at SCHEDULE time. Without the claim \
            a co-firing trigger computes a fresh full gap and the two re-seed twice in a row — \
            the burst the gap exists to prevent.
            """)

        // 0.1 s later the lock-snap fires. 4.9 s of the claim are still unspent.
        let second = RegenSchedule.decide(auto: true, sinceLastSeed: 1.1, untilFloor: 4.9)
        XCTAssertEqual(second.delay, 4.9, accuracy: 1e-9, """
            a co-firing automatic trigger no longer COLLAPSES into the standing claim (#398).

            It got \(second.delay) s where 4.9 s lands it on the same instant as the trigger \
            0.1 s earlier. The shipped defect returned \(RegenSchedule.minAutoSeedGap + 4.9) s \
            — a full fresh gap ADDED to the unspent claim — so the pair that the source comment \
            names by name (lock-snap + evolve tick landing together) pushed the re-seed from \
            t+5 s out to t+11 s, and each further trigger inside the window added another gap \
            with no bound. That is an anti-seed lockout, not anti-flood.
            """)
    }

    /// ⚠️ THE CASE ABOVE CANNOT TELL THE TWO CONSTRAINTS APART, AND SAYING SO IS PART OF THE
    /// GUARD. In a plain two-trigger chain the standing claim was itself computed from the gap,
    /// so `untilFloor` and `minAutoSeedGap − elapsed` are equal by construction — that test pins
    /// the OLD-vs-NEW formula (4.9 s against the shipped 10.9 s), not which constraint won. This
    /// one separates them: the gap is long satisfied, only the claim still stands, so a result of
    /// 3 s can only come from honouring the claim and a result of 0.45 s only from ignoring it.
    func testAStandingClaimGovernsEvenAfterTheGapIsSatisfied() {
        let d = RegenSchedule.decide(auto: true, sinceLastSeed: 10, untilFloor: 3)
        XCTAssertEqual(d.delay, 3, accuracy: 1e-9, """
            an automatic trigger no longer waits for a claim that already stands (#398).

            It got \(d.delay) s. 0.45 s would mean the claim was dropped and two automatic \
            re-seeds fire 3 s apart — the burst the gap exists to prevent, entered from the \
            other side. \(RegenSchedule.minAutoSeedGap + 3) s would be the shipped defect: the \
            unspent claim ADDED to a fresh full gap.
            """)
        XCTAssertEqual(d.claimFloorIn, 3, "the claim must be re-stamped at the instant it resolves to")
    }

    /// A claim that has ALREADY elapsed must not hold anything back — otherwise the lockout comes
    /// back through the other door.
    func testAnExpiredClaimIsIgnored() {
        let d = RegenSchedule.decide(auto: true, sinceLastSeed: 30, untilFloor: -20)
        XCTAssertEqual(d.delay, RegenSchedule.quietWindow, accuracy: 1e-9, """
            a long-idle instrument no longer re-seeds after just the quiet window. Both \
            constraints are satisfied — a full gap has passed and no claim stands — so nothing \
            may extend the wait beyond the coalescing window itself.
            """)
    }

    /// The floor is a FLOOR: it can never shorten the quiet window that coalesces a Picker sweep.
    func testTheQuietWindowIsNeverUndercut() {
        for since in [0.0, 5.9, 6.0, 6.1, 1_000.0] {
            for floor in [-100.0, -1.0, 0.0, 0.2] {
                let d = RegenSchedule.decide(auto: true, sinceLastSeed: since, untilFloor: floor)
                XCTAssertGreaterThanOrEqual(d.delay, RegenSchedule.quietWindow, """
                    since=\(since) floor=\(floor) produced \(d.delay) s, under the quiet window. \
                    Scrolling a Picker fires onChange per highlighted option; without the window \
                    a sweep through the genre menu recomposes once per option.
                    """)
            }
        }
    }

    // MARK: - The user side: the cancelled trigger's claim is not the user's debt

    /// ⛔ THE SECOND HALF, AND THE ONE THE FOUNDER CAN FEEL. `scheduleGenerate` cancels the
    /// pending task on its first line, so a standing claim belongs to a re-seed that will never
    /// run. Charging the user for it is charging them for nothing.
    func testAUserEditIgnoresAClaimItHasAlreadyCancelled() {
        // Genre tap 1 s into a 6 s claim, with a take generated 2 s ago.
        let d = RegenSchedule.decide(auto: false, sinceLastSeed: 2, untilFloor: 5)
        XCTAssertEqual(d.delay, RegenSchedule.quietWindow, accuracy: 1e-9, """
            a user edit is again delayed by a re-seed that was cancelled before this line ran \
            (#398).

            It got \(d.delay) s. The shipped defect returned \(RegenSchedule.minUserGap + 5) s — \
            the user floor PLUS the whole unspent claim — so changing the genre one second into \
            a claim meant six or more seconds of the old sound, under a doc line two rows up \
            promising that a user edit stays instant.
            """)
        XCTAssertNil(d.claimFloorIn, """
            a user edit now moves the AUTOMATIC floor. It must not: the automatic invariant is \
            about automatic triggers flooding each other, and `generate(…)` re-stamps \
            `lastSeedAt` on its own when it actually runs. Letting a burst of taps push the \
            floor forward would starve the evolve tick — the same lockout, entered from the \
            user's side.
            """)
    }

    /// The user's OWN floor still holds, measured against the last take that really happened.
    func testTheUserFloorStillThrottlesRepeatedTaps() {
        let d = RegenSchedule.decide(auto: false, sinceLastSeed: 0.1, untilFloor: -1)
        XCTAssertEqual(d.delay, RegenSchedule.minUserGap - 0.1, accuracy: 1e-9, """
            taps 0.7–1.5 s apart slip past the quiet window alone — the device log that motivated \
            the user floor shows they did. Removing it brings back one recompose per tap while \
            browsing options.
            """)
        XCTAssertEqual(RegenSchedule.decide(auto: false, sinceLastSeed: 9, untilFloor: -1).delay,
                       RegenSchedule.quietWindow, accuracy: 1e-9,
                       "a decisive, isolated tap must still land fast")
    }

    // MARK: - Hygiene at the boundary

    /// Non-finite and negative inputs are an edge case at every boundary in this repo, not an
    /// impossibility. `max` passes NaN through depending on argument order, and a NaN delay would
    /// reach `Task.sleep`.
    func testNonsenseInputCannotProduceANonsenseWait() {
        for since in [Double.nan, .infinity, -.infinity, -5] {
            for floor in [Double.nan, .infinity, -.infinity] {
                for auto in [true, false] {
                    let d = RegenSchedule.decide(auto: auto, sinceLastSeed: since, untilFloor: floor)
                    XCTAssertTrue(d.delay.isFinite, "auto=\(auto) since=\(since) floor=\(floor) → \(d.delay)")
                    XCTAssertGreaterThanOrEqual(d.delay, RegenSchedule.quietWindow)
                    XCTAssertLessThanOrEqual(d.delay, RegenSchedule.minAutoSeedGap, """
                        a nonsense input produced a wait longer than a full gap. It must degrade \
                        to the conservative floor, never to an unbounded pause.
                        """)
                }
            }
        }
    }

    // MARK: - The wiring (scan — this bundle cannot build a SwiftUI view)

    /// ⛔ A CORRECT CORE NOBODY CALLS IS THE FAILURE THIS REPO HAS ALREADY PAID FOR. The
    /// arithmetic above proves `RegenSchedule`; only this proves the view stopped doing its own.
    func testTheViewAsksTheCoreAndKeepsTheTwoFactsApart() throws {
        let body = try memberBody(startingWith: "private func scheduleGenerate(",
                                  in: "Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        guard !body.isEmpty else { return }
        let text = body.joined(separator: "\n")

        XCTAssertTrue(text.contains("RegenSchedule.decide("), """
            `scheduleGenerate` no longer asks `RegenSchedule` (#398). If the arithmetic moved \
            back inline, both defects in that file's header are reachable again and the tests \
            above would keep passing against a core nobody calls.
                \(body.map { $0.trimmingCharacters(in: .whitespaces) })
            """)
        XCTAssertFalse(text.contains("minAutoSeedGap -") || text.contains("minUserGap -"), """
            `scheduleGenerate` computes a floor by subtraction again (#398). That is the exact \
            shape of the bug: subtracting a date that may hold a FUTURE claim turns "wait out \
            the remainder" into "wait a full fresh gap PLUS the remainder".
            """)
        XCTAssertFalse(text.contains("lastSeedAt ="), """
            `scheduleGenerate` writes `lastSeedAt` again (#398). That variable means "a take was \
            actually generated", it is what `generate(…)`'s `sinceLast=` breadcrumb reports \
            (#390), and a claimed floor written into it makes that diagnostic print the distance \
            to a re-seed that never happened. Claims belong in `seedFloor`.
            """)
    }

    // MARK: - Helpers

    /// Lines of a member, from the line that starts with `prefix` to the closing `}` at that
    /// line's OWN indentation. Structural, not a line count.
    private func memberBody(startingWith prefix: String, in path: String) throws -> [String] {
        let lines = try codeLines(path)
        guard let start = lines.firstIndex(where: { $0.contains(prefix) }) else {
            XCTFail("""
                `\(prefix)` is gone from \(path). If it was renamed, move this guard with it — \
                do not leave a check for a member that no longer exists.
                """)
            return []
        }
        let indent = lines[start].prefix { $0 == " " }.count
        let close = lines[(start + 1)...].firstIndex {
            $0.trimmingCharacters(in: .whitespaces) == "}"
                && $0.prefix { c in c == " " }.count == indent
        } ?? lines.endIndex
        return Array(lines[(start + 1)..<close])
    }

    /// Every line that is not a whole-line comment. Load-bearing: the scan's needles
    /// (`lastSeedAt`, `minUserGap -`) all appear verbatim inside the very comments that explain
    /// why they must not appear in code.
    private func codeLines(_ path: String) throws -> [String] {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources/Echoelmusic")
        guard FileManager.default.fileExists(atPath: sources.path) else {
            throw XCTSkip("""
                source tree not present at \(sources.path) — the wiring assertion inspects source \
                text, so it SKIPS rather than reporting a green it did not earn
                """)
        }
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
    }
}
