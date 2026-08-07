// TheFlashCeilingIsOneNumberTests.swift
// Echoel — #466. A SAFETY limit had three independent declarations.
//
// ⭐ THE DEFECT IS THE SHAPE, NOT A VALUE. All three read 3.0 today, so nothing is currently
// wrong for a user. What is wrong is that the WCAG 2.3.1 epilepsy ceiling — a hard rule
// CLAUDE.md lists under SAFETY WARNINGS, not under preferences — can be relaxed in ONE file
// while the other two keep asserting the old number, and nothing notices. That is the #416
// class applied to the one constant where drift is not a cosmetic problem.
//
//   Studio/FlashGuard.swift            maxFlashHz        = 3.0   ← canonical BY DESIGNATION
//   Bio/EntrainmentEngine.swift        maxVisualFlashHz  = 3.0
//   DSP/BioEntrainmentDirector.swift   maxVisualHz       = 3.0
//
// The irony is load-bearing and is why this file exists: `FlashGuard`'s own `maxPulseRateHz`
// doc argues, in so many words, that "two symbols for one number is the drift surface this
// whole hoist exists to remove". That was written about the 2.5 Hz PULSE ceiling (#141/#344)
// and it was right — but the 3 Hz FLASH ceiling sitting ten lines above it had escaped the
// very hoist that sentence describes.
//
// ⛔ WHY THEY ARE NOT MERGED, said plainly so the next session does not read this as laziness:
// layering forbids it today. `FlashGuard` is in `Studio/`; `Bio/` references no `Studio/` type
// (`git grep -ln FlashGuard -- Sources` → Core · Studio · Sync · Views, no Bio), and `DSP/` is
// kept Foundation-only by hygiene (`project.yml`) so it may not reach `Studio/` at all.
// Merging means MOVING `FlashGuard` to a layer all three can see — a decision about where
// visual-safety law lives, not a tidy-up, and not this slice. If a later slice does move it,
// these assertions stay green and become trivially true. That is the goal state, not a
// failure of this file.
//
// ⛔ HONEST GRADING, because the flattering version is available: **`testTheThreeCeilingsAgree`
// and `testTheCeilingIsTheWCAGNumber` are NOT regressions** — they are green on the pre-#466
// tree too, because all three already read 3.0. This slice installs a FORWARD guard and
// corrects prose; it fixes no runtime behaviour, and claiming otherwise would be the #433
// defect. What it buys is that the next one-file relaxation goes red instead of shipping.
//
// ⭐ THE COUNTERWEIGHT IS THE HALF THAT MATTERS, and it guards against the repair itself.
// The obvious next tidy-up after reading the above is "unify all the flash ceilings" — and
// that would fold `maxPulseRateHz` (2.5) into `maxFlashHz` (3.0). `FlashGuard`'s own doc
// measured what that costs: the look budgets are derived FROM 2.5, Aurora lands on exactly
// 3.00 Hz with zero margin, so raising the pulse ceiling to 3.0 puts Aurora at 3.6 Hz — a real
// epilepsy-law violation introduced by a cleanup. `testThePulseCeilingIsNotTheFlashCeiling`
// makes that specific merge red.
//
// ⚠️ WHAT THIS FILE CANNOT DO. It reads constants; it does not render anything. That every
// shipped look actually obeys the ceiling is `FlashGuardTests.testEveryReachableLookObeysThe
// ThreeHzLaw`'s job (non-blocking bundle), and whether a device strobes is a device look.
// Nothing here proves any of that.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheFlashCeilingIsOneNumberTests: XCTestCase {

    // MARK: - The safety ceiling

    /// The three declarations must agree. Relaxing one alone is the failure mode.
    func testTheThreeCeilingsAgree() {
        XCTAssertEqual(EntrainmentEngine.maxVisualFlashHz, FlashGuard.maxFlashHz, accuracy: 1e-12, """
            EntrainmentEngine.maxVisualFlashHz drifted from FlashGuard.maxFlashHz. These are two \
            copies of ONE rule (WCAG 2.3.1, ≤3 flashes/second). If the ceiling is genuinely being \
            changed, change all THREE declarations in the same commit and get a bio-safety review \
            first — do not delete this check to make the build pass.
            """)
        XCTAssertEqual(BioEntrainmentDirector.maxVisualHz, FlashGuard.maxFlashHz, accuracy: 1e-12, """
            BioEntrainmentDirector.maxVisualHz drifted from FlashGuard.maxFlashHz. This one lives \
            in DSP/, which is Foundation-only by hygiene and therefore CANNOT chain to the \
            canonical symbol — it is the copy most likely to be edited in isolation, which is \
            exactly why it is pinned here.
            """)
    }

    /// Pins the VALUE, not just the agreement. Without this, folding all three onto a shared
    /// but WRONG number would pass the equality test above.
    func testTheCeilingIsTheWCAGNumber() {
        XCTAssertEqual(FlashGuard.maxFlashHz, 3.0, accuracy: 1e-12, """
            The WCAG 2.3.1 general-flash limit is three flashes per second. This is a published \
            accessibility threshold, not a tuning parameter — CLAUDE.md lists it under SAFETY \
            WARNINGS. Raising it is a product-safety decision that belongs to the founder.
            """)
    }

    // MARK: - Counterweights (green before AND after — they guard the repair, not the defect)

    /// The app's own pulse ceiling is STRICTER than WCAG's, and deliberately so. The obvious
    /// "unify the ceilings" cleanup would raise it from 2.5 to 3.0 and put the Aurora look at
    /// 3.6 Hz — a real violation introduced by tidying. `FlashGuard`'s own header measured that.
    func testThePulseCeilingIsNotTheFlashCeiling() {
        XCTAssertEqual(FlashGuard.maxPulseRateHz, 2.5, accuracy: 1e-12, """
            FlashGuard.maxPulseRateHz moved. The look budgets are derived FROM this number and \
            Aurora sits on exactly 3.00 Hz with zero margin — see the doc at the declaration. \
            Raising it to WCAG's 3.0 is not a rounding question.
            """)
        XCTAssertLessThan(FlashGuard.maxPulseRateHz, FlashGuard.maxFlashHz, """
            The app's pulse ceiling must stay STRICTLY below the WCAG ceiling. If these two were \
            folded into one symbol, this is the assertion that says why they must not be.
            """)
    }

    /// The two breath-rate floors legitimately DIFFER, and the comment that once claimed they
    /// matched was false. Pinned as a pair so a later "unify" has to argue with a number.
    ///
    /// ⚠️ The one-way risk: `EntrainmentEngine.breathTargetHz` CLAMPS to its window, so raising
    /// its floor to 5.0 would make a genuinely-4.6/min breather read as 5.0 — an invented rate,
    /// the class #424/#426 already paid for twice on the measurement side.
    func testTheTwoBreathFloorsAreDeliberatelyDifferent() {
        XCTAssertEqual(EntrainmentEngine.minBreathsPerMinute, 4.5, accuracy: 1e-12, """
            EntrainmentEngine's floor is the evidence-based resonance range (~4.5–7/min), not a \
            copy of the pacer's sweep bound. Changing it changes what breathTargetHz clamps a \
            slow breather to.
            """)
        XCTAssertEqual(BreathPacer.minRate, 5.0, accuracy: 1e-12, """
            BreathPacer.minRate is the RESONANCE-SEARCH sweep floor and nothing more — that file \
            retracted its own safety framing in #435. It is pinned here only so the pair below \
            cannot silently become equal.
            """)
        XCTAssertNotEqual(EntrainmentEngine.minBreathsPerMinute, BreathPacer.minRate, """
            These two became equal. That may be correct — but the comment that once asserted they \
            already matched was FALSE (4.5 vs 5.0), and it is the reason this test exists. If the \
            merge is intentional, state which question the surviving number answers; do not let \
            two different decisions collapse into one by accident.
            """)
        // The ceiling, by contrast, genuinely coincides — and coincides is not chained.
        XCTAssertEqual(EntrainmentEngine.maxBreathsPerMinute, ResonanceFinder.maxRate,
                       accuracy: 1e-12, """
            The upper bounds happen to be the same 7.0 in both files. Recorded as a coincidence, \
            not a dependency: nothing derives one from the other, so this assertion is the only \
            thing that would notice them parting.
            """)
    }
}
