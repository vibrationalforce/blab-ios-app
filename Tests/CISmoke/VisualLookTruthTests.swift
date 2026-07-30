// VisualLookTruthTests.swift
// Echoel — #227: what the visual readout claims must be what the visual renders. BLOCKING bundle,
// because the other suite cannot fail a merge (#208).
//
// WHAT WENT WRONG. `visual.spectralDonuts` defaulted to `true`, so a FRESH INSTALL opened with a
// filled "Donuts" pill and a readout saying "Donuts" — while the only visual a player can reach,
// `FloatingVisualWindow`, renders from `visual.style`/`styleB`/`blend` and never reads that key.
// `SpectralDonutView` is constructed at exactly one place, inside `EchoelStudioView`'s
// `.fullScreenCover(isPresented: $showVisual)`, and `showVisual`'s only setter was the deleted
// `openTool`. So the claim was unreachable from the first launch onward — the #164/#227 shape.
//
// ⚠️ WHAT THIS FILE CANNOT REACH, said plainly so the coverage is not overread. It cannot prove
// the pill is gone, cannot prove the readout is unconditional, and cannot prove `showVisual` still
// has no setter — all three live inside `private` members of a view, and no test in this bundle can
// instantiate one. What it CAN pin is the persisted contract underneath: the key string (which the
// launch normalisation must still be able to find), the default (which decides what a fresh install
// claims), and the invariant that the flip newly exposes.

import Foundation
import XCTest
@testable import Echoelmusic

final class VisualLookTruthTests: XCTestCase {

    /// ⛔ THE KEY STRING MAY NOT MOVE — and the reason is the opposite of the usual one.
    /// Normally a renamed key silently resets everyone to the default, which is bad. Here the
    /// default is where we WANT everyone, so a rename would look harmless. It is not: an install
    /// carrying a stored `true` is exactly who `normaliseUnreachableDonutMode()` exists for, and it
    /// can only clear a value it can still find. Rename this and those players keep hidden Blend
    /// controls forever, with no control able to undo it.
    func testThePersistedKeyIsStillTheOneOlderInstallsWroteTo() {
        XCTAssertEqual(StudioDefaultKeys.visualSpectralDonuts.key, "visual.spectralDonuts",
                       "the donut key moved — an install that stored `true` before #227 can no "
                       + "longer be normalised, and nothing in the UI can reach that value either")
    }

    /// A fresh install must not claim a renderer it cannot show. This is the assertion the slice
    /// exists for; if it goes red, the app once again opens saying "Donuts" over a Metal field.
    func testAFreshInstallDoesNotClaimTheDonutRenderer() {
        XCTAssertFalse(StudioDefaultKeys.visualSpectralDonuts.value,
                       "the default is `true` again. While `SpectralDonutView`'s only construction "
                       + "site sits behind a cover with no setter, `true` is a claim the app cannot "
                       + "honour — and it is the state of every first launch. If the donut renderer "
                       + "has been re-doored, flip this test and the pill in the SAME commit.")
    }

    /// ⭐ THE INVARIANT THE FLIP NEWLY EXPOSES, and the reason this file is worth its place.
    ///
    /// `EchoelStudioView`'s launch closure snaps the persisted look back into the slider's sequence
    /// when it has fallen out of it — but that snap is guarded by `if !spectralDonuts`. With the old
    /// default it never ran on a fresh install, so nothing checked that the shipped default look is
    /// one the slider can actually land on. It runs on every fresh install now. A default outside
    /// the sequence would be silently rewritten at first launch: the player would get a look nobody
    /// chose, and the "default 5 (Aurora) — a richer look out of the box" note in `StudioDefaultKeys`
    /// would quietly stop being true.
    func testTheDefaultLookIsOneTheSliderCanActuallyLandOn() {
        XCTAssertTrue(LookBlendMap.defaultSequence.contains(StudioDefaultKeys.visualStyle.value),
                      "the default visual style (\(StudioDefaultKeys.visualStyle.value)) is not in "
                      + "the default slider sequence \(LookBlendMap.defaultSequence). Since #227 the "
                      + "launch snap runs on a fresh install, so this default would be overwritten "
                      + "before the player ever sees it — move one of the two, not neither.")
        XCTAssertEqual(StudioDefaultKeys.visualStyleB.value, 0,
                       "the default BLEND partner is no longer 0. A non-zero default means a fresh "
                       + "install starts mid-crossfade between two looks, which is not a look "
                       + "anyone picked")
        XCTAssertEqual(StudioDefaultKeys.visualBlend.value, 0,
                       "the default blend amount is no longer 0 — same reason as above")
    }

    /// And the sequence itself must be usable: a one-entry sequence gives `maxPosition == 0`, which
    /// hides the slider entirely (`if LookBlendMap.maxPosition(for:) > 0`). With the Donuts pill
    /// removed that would leave the look strip with NO control at all — a panel row that only
    /// reports. Pinned here rather than in the view, which no test can reach.
    func testTheDefaultSequenceLeavesAnActualSliderOnScreen() {
        XCTAssertGreaterThan(LookBlendMap.maxPosition(for: LookBlendMap.defaultSequence), 0,
                             "the default look sequence no longer spans a draggable range, so the "
                             + "look strip would render a label and nothing to drag")
    }
}
