// FXTempoFollowTests.swift
// Echoel — #261: the FX sheet froze the tempo the moment it opened.
//
// WHAT WENT WRONG. `FXViewModel.bpm` was assigned exactly once, in `init`, from a `Double`
// the parent passed at presentation time. Every "Sync · <n> BPM" label, every note-division
// item in the sync menus, and every one-tap character stamp (`applyCharacter` →
// `FXCharacter.apply(to:bpm:genre:)`) then computed at that frozen number. In Flow mode the
// body keeps moving the clock, so the longer the sheet stayed open the further its delay
// times drifted from the take that was actually playing — silently, with a confident number
// on screen.
//
// ⚠️ WHY THE FIX IS NOT `vm.bpm = pattern.tempo`. The clock GLIDES: `PatternEngine.glideTempo`
// eases with a 20 Hz main-queue timer while stopped and once per tick while playing. The FX
// sheet hosts `Menu`s whose ITEM LABELS are built from the tempo, so adopting every glide step
// would rebuild that body ~20×/s and tear an open popover down mid-pick — the freeze class this
// app has already paid for twice with a 10 Hz bio read in an ancestor body. A fix for a stale
// number that installs a freeze is not a fix. So `tempoFollow` decides WHEN to adopt, and the
// live read is confined to an invisible leaf (`FXTempoFollower`).
//
// ⛔ AND THE THRESHOLD IS NOT WHAT BOUNDS THE REBUILD RATE — the first cut of this slice, and
// the first cut of this file, both said it was. The ease is PROPORTIONAL (`tempo += diff * 0.12`),
// so while more than ~17 BPM remain, every single 0.05 s step clears the 2 BPM gap by itself and
// takes the adopt-immediately branch: a 90→150 re-seed rebuilt the sheet eleven times in a row.
// Raising the threshold cannot help, because the step size scales with the glide distance. The
// bound comes from the CALLER instead: `FXTempoFollower` polls every `tempoFollowPollSeconds`
// rather than observing, so no glide can rebuild the sheet faster than 2.5 Hz. What is asserted
// below is the policy; the rate cap is a property of the poll, which no unit test here can see.
//
// BLOCKING bundle, because the other suite cannot fail a merge (#208).
//
// ⚠️ WHAT THIS FILE DOES NOT COVER. It pins the pure decision, not the plumbing: that the leaf
// is actually mounted, that `.task(id:)` really debounces, and that the sheet reads the value
// it was given are SwiftUI behaviours no unit test here can observe. Stated so "the FX tempo is
// tested" is not read into it — the device check is: open FX in Flow mode with the body moving
// the tempo, and watch the Sync header track it.

import Foundation
import XCTest
@testable import Echoelmusic

final class FXTempoFollowTests: XCTestCase {

    /// ⛔ THE ASSERTION THE SLICE EXISTS FOR: a tempo that has genuinely moved is adopted.
    /// Before the fix nothing was adopted at all, ever, so any non-`.ignore` verdict here is
    /// the whole difference between a live sync and a frozen one.
    func testATempoThatHasMovedIsAdopted() {
        XCTAssertNotEqual(FXViewModel.tempoFollow(128, current: 120), .ignore,
                          "the clock moved 8 BPM and the sheet would have kept computing at "
                          + "120 — that is the exact defect this slice removes")
        XCTAssertEqual(FXViewModel.tempoFollow(128, current: 120), .adoptNow,
                       "a gap that large is visibly wrong on screen and is worth one rebuild "
                       + "immediately, without waiting for the glide to settle")
    }

    /// A glide STEP must not rebuild the sheet. This is the half that protects the open menu:
    /// the 20 Hz easing walks the tempo in fractions of a BPM, and every one of those landing
    /// as a rebuild is how a Picker popover gets torn down while the user is picking from it.
    func testAGlideStepWaitsForQuietInsteadOfRebuildingImmediately() {
        XCTAssertEqual(FXViewModel.tempoFollow(120.4, current: 120), .adoptWhenQuiet)
        XCTAssertEqual(FXViewModel.tempoFollow(121.9, current: 120), .adoptWhenQuiet,
                       "just under the visible-gap threshold must still wait — the boundary "
                       + "belongs to the immediate branch, not to this one")
    }

    /// The boundary itself, both sides, so the thresholds cannot drift without this failing.
    func testTheVisibleGapBoundaryIsInclusive() {
        let g = FXViewModel.tempoFollowVisibleGap
        XCTAssertEqual(FXViewModel.tempoFollow(120 + g, current: 120), .adoptNow)
        XCTAssertEqual(FXViewModel.tempoFollow(120 + g - 0.001, current: 120), .adoptWhenQuiet)
        // Symmetric: slowing down is the same decision as speeding up.
        XCTAssertEqual(FXViewModel.tempoFollow(120 - g, current: 120), .adoptNow)
    }

    /// Below the floor nothing on screen would change — the readout is two decimals — so a
    /// rebuild would cost a torn-down popover and buy a user-invisible difference.
    func testAChangeTooSmallToSeeIsIgnored() {
        XCTAssertEqual(FXViewModel.tempoFollow(120, current: 120), .ignore)
        XCTAssertEqual(FXViewModel.tempoFollow(120.001, current: 120), .ignore)
        XCTAssertEqual(FXViewModel.tempoFollow(120 + FXViewModel.tempoFollowFloor, current: 120),
                       .adoptWhenQuiet,
                       "the floor is the smallest change that alters the shown number, so it "
                       + "must itself be adopted — not swallowed")
    }

    /// ⛔ AND THE ONE THAT MATTERS BEYOND THE UI: `bpm` feeds `TempoSyncOption`'s division
    /// maths, whose result is written to a delay time. A NaN adopted here would travel into
    /// the audio parameters. Refused at the boundary, in both arguments.
    func testANonFiniteTempoIsNeverAdopted() {
        for bad: Double in [.nan, .infinity, -.infinity, 0, -120] {
            XCTAssertEqual(FXViewModel.tempoFollow(bad, current: 120), .ignore,
                           "\(bad) was accepted as a tempo — it would reach a delay time via "
                           + "TempoSyncOption's division maths")
        }
        XCTAssertEqual(FXViewModel.tempoFollow(120, current: .nan), .ignore,
                       "a NaN already sitting in the view model must not make every comparison "
                       + "false-y and silently freeze the follow again")
    }

    /// ⭐ THE CONSTANT THAT ACTUALLY BOUNDS THE FREEZE RISK, which is why it is pinned from both
    /// sides. It is the poll period, so `1 / it` is the hard ceiling on how often the FX sheet
    /// can be rebuilt — no glide, however large, can beat it. It must span several 0.05 s
    /// stopped-glide steps (`PatternEngine.startStoppedGlide`) so that "the clock read the same
    /// twice" really means the ease has ended, and it must stay short enough that the shown BPM
    /// does not visibly lag a settled clock.
    func testThePollPeriodOutlastsAGlideStepWithoutLaggingTheUser() {
        XCTAssertGreaterThan(FXViewModel.tempoFollowPollSeconds, 0.05 * 4,
                             "the poll must span several glide steps, otherwise two consecutive "
                             + "looks can both land mid-ease and be mistaken for a settled clock")
        XCTAssertLessThan(FXViewModel.tempoFollowPollSeconds, 1.0,
                          "and it must not be so long that the shown BPM lags a settled clock "
                          + "by something a user would notice")
    }

    /// ⛔ THE REGRESSION GUARD FOR THE MISTAKE THIS SLICE ACTUALLY MADE. `PatternEngine` eases
    /// PROPORTIONALLY — `tempo += diff * 0.12` at 20 Hz — so the opening step of a glide is
    /// `remaining * 0.12`, and any glide with more than `tempoFollowVisibleGap / 0.12` ≈ 17 BPM
    /// left produces a step that clears the gap ON ITS OWN and takes `.adoptNow`. That is not a
    /// bug in the policy; it is why the policy alone cannot bound the rebuild rate, and why the
    /// caller polls instead of observing. Asserted so nobody "simplifies" the follower back to
    /// `.task(id: pattern.tempo)` believing the threshold protects them.
    func testALargeGlideStepClearsTheThresholdOnItsOwn() {
        let firstStep = 60.0 * 0.12          // a 90→150 re-seed, first ease step
        XCTAssertGreaterThan(firstStep, FXViewModel.tempoFollowVisibleGap,
                             "a single glide step already exceeds the visible gap, so an "
                             + "observation-driven follower would adopt on EVERY step of a "
                             + "large glide — 20 rebuilds a second, the freeze itself")
        // …and a small glide's step does not, which is the case the threshold does cover.
        XCTAssertLessThan(2.0 * 0.12, FXViewModel.tempoFollowVisibleGap)
    }
}
