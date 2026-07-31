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
    /// can only clear a value it can still find. Rename this and those installs keep the launch
    /// look-snap skipped forever, with no reachable control able to undo it.
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
    ///
    /// ⚠️ THIS ONLY GUARDS THE SNAP BECAUSE THE VIEWS NOW DERIVE THEIR DEFAULT FROM
    /// `defaultSequence`. In #227's first cut they each re-typed `"3,5,7"`, so this test asserted
    /// against a constant the snap never read: change either literal and it stayed green while the
    /// fresh install got snapped. Both declarations are `LookBlendMap.string(from:
    /// LookBlendMap.defaultSequence)` now — if anyone re-types a literal there, this test goes
    /// back to guarding nothing, and it will not tell you.
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

    // MARK: - #269 — the "Detail" row's reach

    /// THE FACT THAT MAKES THE CAPTION NECESSARY, and the one that would make it a lie if the
    /// defaults ever change. `visual.detail` reaches the screen only through `fieldRings`, so
    /// with the shipped defaults (primary style 5 = Aurora, styleB 0, blend 0) its reach is
    /// exactly zero. If someone ships Rings as the default look, this test goes red and the
    /// caption must be removed in the SAME commit — a caption saying "no visible effect" over
    /// a row that now works is the same defect pointing the other way.
    func testWithTheShippedDefaultsTheDetailRowCannotChangeThePicture() {
        let reach = LookBlendMap.detailReach(style: StudioDefaultKeys.visualStyle.value,
                                             styleB: StudioDefaultKeys.visualStyleB.value,
                                             blend: StudioDefaultKeys.visualBlend.value)
        XCTAssertEqual(reach, 0, accuracy: 1e-9,
                       "the shipped defaults now DO give Detail a share of the picture — good "
                       + "news, but the #269 caption in the Field panel is stale and must go")
    }

    /// And the predicate has to mirror the renderer, not approximate it: B is only evaluated
    /// above the shader's own 0.001 blend threshold (`float2 fb = (blend > 0.001) ? … : fa`),
    /// and below it the A field IS the picture.
    func testDetailReachMirrorsTheRenderersOwnBlendArithmetic() {
        let rings = LookBlendMap.ringsStyleIndex
        XCTAssertEqual(LookBlendMap.detailReach(style: rings, styleB: 5, blend: 0), 1, accuracy: 1e-9,
                       "pure Rings ⇒ Detail shapes the whole picture")
        XCTAssertEqual(LookBlendMap.detailReach(style: 5, styleB: rings, blend: 0), 0, accuracy: 1e-9,
                       "Rings parked in the B slot at blend 0 is NOT on screen — the shader "
                       + "skips the B field entirely below the threshold")
        XCTAssertEqual(LookBlendMap.detailReach(style: 5, styleB: rings, blend: 0.25),
                       0.25, accuracy: 1e-9, "a quarter-blend into Rings ⇒ a quarter of the reach")
        XCTAssertEqual(LookBlendMap.detailReach(style: rings, styleB: 5, blend: 0.25),
                       0.75, accuracy: 1e-9, "…and the complement when Rings is the A look")
        XCTAssertEqual(LookBlendMap.detailReach(style: rings, styleB: rings, blend: 0.4),
                       1, accuracy: 1e-9, "Rings on both sides is still the whole picture")
        XCTAssertEqual(LookBlendMap.detailReach(style: 5, styleB: 7, blend: 0.5), 0, accuracy: 1e-9,
                       "no Rings anywhere ⇒ no reach")
    }

    /// The renderer CLAMPS the style before bucketing (`Float(min(max(style, 0), 9))`, then
    /// `si < 0.5` selects Rings), so a negative persisted index draws as Rings. An `==` test
    /// would call that "no reach" and show the caption over a working row. Close to
    /// unreachable — the launch snap and the look slider only ever write library indices —
    /// but the doc calls this a mirror, and a mirror has to hold at the edges too.
    func testANegativePersistedStyleRendersAsRingsAndCountsAsReach() {
        XCTAssertEqual(LookBlendMap.detailReach(style: -1, styleB: 5, blend: 0), 1, accuracy: 1e-9,
                       "the shader clamps a negative style to 0 = Rings, so Detail DOES reach it")
        XCTAssertEqual(LookBlendMap.detailReach(style: 5, styleB: -4, blend: 0.5),
                       0.5, accuracy: 1e-9, "same on the B side, once actually blending")
    }

    /// Edge cases: a corrupted persisted blend must not make the caption flicker or the
    /// predicate return something outside 0…1.
    func testDetailReachIsFiniteAndBoundedForAnyStoredBlend() {
        for bad in [Double.nan, Double.infinity, -Double.infinity, -3, 42] {
            let r = LookBlendMap.detailReach(style: LookBlendMap.ringsStyleIndex, styleB: 5, blend: bad)
            XCTAssertTrue(r.isFinite, "reach must stay finite for a stored blend of \(bad)")
            XCTAssertGreaterThanOrEqual(r, 0)
            XCTAssertLessThanOrEqual(r, 1)
        }
        XCTAssertEqual(LookBlendMap.detailReach(style: LookBlendMap.ringsStyleIndex,
                                                styleB: 5, blend: .nan),
                       1, accuracy: 1e-9,
                       "a NaN blend reads as 0 (no blending), so the A look is the whole picture")
    }
}
