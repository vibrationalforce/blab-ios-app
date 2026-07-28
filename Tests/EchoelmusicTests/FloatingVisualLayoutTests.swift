// FloatingVisualLayoutTests.swift
// Echoel — boundaries of the floating visual window's ADAPTIVE size (founder
// 2026-07-27: "auch das Fenster, es soll adaptiv sein"). Pure Foundation math —
// runs on CI without a SwiftUI host, same law as RollFitMathTests.
//
// The regression these exist for, stated concretely: the old code took two INDEPENDENT
// fractions of the container (small = 0.38w × 0.30h) with `max(120, …)` floors. On a
// landscape iPhone the FLOOR bound, not the fraction — "small" came out 324 × 120 pt and
// the 44 pt chrome bar left a 324 × 76 picture. That picture is also the play surface.
//
// Honest scope: of the tests below, only the sliver test and the aspect-band test would
// FAIL against the old rule. The orientation, fit and monotonicity tests pass under both
// and are here to pin properties a future rewrite could break — a hardcoded 4:3 would
// satisfy the band but fail the orientation test.

import XCTest
import Foundation
@testable import Echoelmusic

final class FloatingVisualLayoutTests: XCTestCase {

    // Realistic containers (already inside the app chrome, hence shorter than the
    // physical screen). Margin/chrome match FloatingVisualWindow's constants.
    private let portrait = CGSize(width: 393, height: 700)
    private let landscape = CGSize(width: 852, height: 393)
    private let pad = CGSize(width: 1024, height: 1180)
    private let margin: CGFloat = 12
    private let chrome: CGFloat = 44
    /// The three floating steps, READ FROM THE SOURCE rather than re-typed (fullscreen
    /// never reaches this math). A local copy would keep passing while the shipped steps
    /// drifted — the whole point of this slice was changing exactly these numbers.
    private var steps: [CGFloat] {
        [FloatingVisualLayout.smallStep,
         FloatingVisualLayout.mediumStep,
         FloatingVisualLayout.largeStep]
    }

    private func card(_ bounds: CGSize, _ f: CGFloat) -> CGSize {
        FloatingVisualLayout.cardSize(in: bounds, fraction: f, margin: margin, chromeHeight: chrome)
    }
    /// The picture is the card minus the chrome bar — what the founder actually looks at.
    private func picture(_ bounds: CGSize, _ f: CGFloat) -> CGSize {
        let c = card(bounds, f)
        return CGSize(width: c.width, height: c.height - chrome)
    }

    // MARK: - The defect

    /// THE test this slice exists for. Under the old two-fraction rule the landscape
    /// "small" picture was ≈ 324 × 74 → aspect 4.4. Anything above `maxPictureAspect`
    /// is the sliver.
    func testLandscape_smallStep_isNotALetterboxSliver() {
        let p = picture(landscape, steps[0])
        XCTAssertLessThanOrEqual(p.width / p.height,
                                 FloatingVisualLayout.maxPictureAspect + 0.001,
                                 "landscape small must not degenerate into a strip")
        XCTAssertGreaterThan(p.height, 100,
                             "the play surface needs real height for octaves, not 74 pt")
    }

    /// The aspect band holds for EVERY step on EVERY container — portrait, landscape
    /// and a near-square iPad. This is the property "adaptive" has to mean.
    func testPictureAspect_staysInBand_acrossDevicesAndSteps() {
        for bounds in [portrait, landscape, pad] {
            for f in steps {
                let p = picture(bounds, f)
                let aspect = p.width / p.height
                XCTAssertGreaterThanOrEqual(aspect, FloatingVisualLayout.minPictureAspect - 0.001,
                                            "too narrow at \(bounds) step \(f)")
                XCTAssertLessThanOrEqual(aspect, FloatingVisualLayout.maxPictureAspect + 0.001,
                                         "too wide at \(bounds) step \(f)")
            }
        }
    }

    /// It ADAPTS rather than picking one fixed shape: a portrait container yields a
    /// portrait-ish picture, a landscape one a landscape picture. A hardcoded 4:3 would
    /// pass the band test above and fail this one.
    func testAspect_followsTheContainersOrientation() {
        XCTAssertLessThan(picture(portrait, steps[2]).width / picture(portrait, steps[2]).height, 1.0,
                          "a portrait container must not produce a landscape picture")
        XCTAssertGreaterThan(picture(landscape, steps[2]).width / picture(landscape, steps[2]).height, 1.0,
                             "a landscape container must not produce a portrait picture")
    }

    // MARK: - Fit + monotonicity

    func testCard_alwaysFitsInsideTheContainerWithItsMargins() {
        for bounds in [portrait, landscape, pad] {
            for f in steps {
                let c = card(bounds, f)
                XCTAssertLessThanOrEqual(c.width, bounds.width - 2 * margin + 0.001,
                                         "overflows width at \(bounds) step \(f)")
                XCTAssertLessThanOrEqual(c.height, bounds.height - 2 * margin + 0.001,
                                         "overflows height at \(bounds) step \(f)")
            }
        }
    }

    func testSteps_growStrictly_smallToLarge() {
        for bounds in [portrait, landscape, pad] {
            let areas = steps.map { f -> CGFloat in
                let p = picture(bounds, f)
                return p.width * p.height
            }
            XCTAssertLessThan(areas[0], areas[1], "medium must be bigger than small at \(bounds)")
            XCTAssertLessThan(areas[1], areas[2], "large must be bigger than medium at \(bounds)")
        }
    }

    /// The chrome bar is ADDED to the picture, not carved out of the card: the card is
    /// exactly the picture the aspect rule asked for, plus the bar.
    ///
    /// Deliberately NOT written as "same width with and without chrome" — that comparison
    /// is a trap. On `portrait` both branches happen to be width-bound, so it holds
    /// trivially; on `landscape` removing the chrome enlarges the available height, moves
    /// the binding edge and changes the width by 13%. A reader would take the equality for
    /// a rule and be wrong.
    func testChromeIsAddedToThePicture_notSubtractedFromIt() {
        for bounds in [portrait, landscape, pad] {
            for f in steps {
                let c = card(bounds, f)
                let available = CGSize(width: bounds.width - 2 * margin,
                                       height: bounds.height - 2 * margin - chrome)
                let aspect = FloatingVisualLayout.pictureAspect(forAvailable: available)
                XCTAssertEqual(c.height - chrome, c.width / aspect, accuracy: 0.01,
                               "the card must be its picture plus exactly the bar (\(bounds), \(f))")
            }
        }
    }

    /// A window you cannot move is a fullscreen window with a border. The near-square
    /// container is where the two-edge claim stops binding on one edge and the card
    /// swallowed 92% of the height — this is the cap that fixes it.
    func testLargeStep_leavesRealDragTravel_onANearSquareContainer() {
        let c = card(pad, FloatingVisualLayout.largeStep)
        XCTAssertLessThanOrEqual(c.height,
                                 pad.height * FloatingVisualLayout.maxCardHeightFraction + 0.001,
                                 "large must not swallow the container's height")
        XCTAssertGreaterThan(pad.height - c.height - 2 * margin, 150,
                             "there must be enough travel left for the window to be draggable")
        // The cap scales BOTH axes, so it must not distort the picture it just shrank.
        let p = CGSize(width: c.width, height: c.height - chrome)
        XCTAssertGreaterThanOrEqual(p.width / p.height,
                                    FloatingVisualLayout.minPictureAspect - 0.001)
        XCTAssertLessThanOrEqual(p.width / p.height,
                                 FloatingVisualLayout.maxPictureAspect + 0.001)
    }

    /// …and the cap must not reach the phone-portrait large step, or "large got smaller"
    /// is what the founder sees on the device he actually holds.
    func testCap_doesNotBite_onPortraitPhone() {
        let c = card(portrait, FloatingVisualLayout.largeStep)
        XCTAssertLessThan(c.height, portrait.height * FloatingVisualLayout.maxCardHeightFraction,
                          "the portrait large card must be under the cap on its own")
        XCTAssertGreaterThan(c.width, 330, "portrait large must stay a big picture")
    }

    // MARK: - The studio control band (the docked card must not cover the primary button)

    /// The card once parked on top of the "Create from Within"/Stop button, covering ~40 %
    /// of it — and because the card is the PLAY SURFACE, a tap in the covered strip played
    /// a synth note instead of starting biofeedback. `FloatingVisualWindow.defaultCenter`
    /// lifts the card by `studioControlBandHeight`, and `EchoelStudioView` builds the button
    /// from the SAME three constants. This test is what makes that agreement non-silent:
    /// neither `defaultCenter` nor the button is reachable from a Foundation-level test
    /// (both live behind `#if canImport(SwiftUI) && canImport(MetalKit) && canImport(UIKit)`),
    /// so the shared constants are the only surface a CI test can hold still.
    func testStudioControlBand_isExactlyTheButtonPlusItsPadding() {
        XCTAssertEqual(FloatingVisualLayout.studioControlBandHeight,
                       FloatingVisualLayout.startButtonHeight
                       + FloatingVisualLayout.startButtonTopPadding
                       + FloatingVisualLayout.startButtonBottomPadding,
                       accuracy: 1e-9,
                       "the band must be the button's full vertical footprint, or the docked card covers it")
    }

    /// A restyle that shrinks the button toward nothing would quietly stop the card from
    /// clearing it. Pin the band to a range that keeps a 44 pt HIG-sized control plus air.
    func testStudioControlBand_staysBigEnoughToBeWorthClearing() {
        XCTAssertGreaterThanOrEqual(FloatingVisualLayout.startButtonHeight, 44,
                                    "the primary control must stay at least HIG tap size")
        XCTAssertGreaterThan(FloatingVisualLayout.studioControlBandHeight,
                             FloatingVisualLayout.startButtonHeight,
                             "the band must include the paddings, not just the button")
    }

    /// The clearance the fix actually buys, expressed as the arithmetic it comes from:
    /// the card's own margin plus the band, minus the half-card offset the dock already
    /// applied. Container-independent, which is why it can be asserted without a device.
    func testDockedCard_clearsTheButton_atTheSmallStep() {
        let bounds = CGSize(width: 393, height: 759)   // portrait iPhone, inside app chrome
        let c = card(bounds, FloatingVisualLayout.smallStep)
        let centerY = bounds.height - c.height / 2 - margin
            - FloatingVisualLayout.studioControlBandHeight
        let cardBottom = centerY + c.height / 2
        let buttonTop = bounds.height - FloatingVisualLayout.startButtonBottomPadding
            - FloatingVisualLayout.startButtonHeight
        XCTAssertLessThan(cardBottom, buttonTop,
                          "the docked card must end above the primary button, not on it")
        XCTAssertGreaterThan(buttonTop - cardBottom, 10,
                             "clearance must be visible, not a rounding accident")
    }

    // MARK: - Degenerate input (nothing here may trap or return nonsense)

    func testTinyContainer_returnsSomethingUsable_neverNegative() {
        // Smaller than margins + chrome: the guard hands back the bounds rather than a
        // negative-height card.
        let c = card(CGSize(width: 40, height: 50), 0.5)
        XCTAssertGreaterThan(c.width, 0)
        XCTAssertGreaterThan(c.height, 0)
        XCTAssertLessThanOrEqual(c.width, 40.001)
        XCTAssertLessThanOrEqual(c.height, 50.001)
    }

    func testNonFiniteAndZeroInputs_doNotProduceNaN() {
        for bounds in [CGSize(width: .nan, height: 700), CGSize(width: 393, height: .nan),
                       CGSize(width: 0, height: 700), CGSize(width: 393, height: 0),
                       CGSize(width: -100, height: -100)] {
            let c = card(bounds, 0.5)
            XCTAssertTrue(c.width.isFinite && c.height.isFinite, "NaN card for \(bounds)")
            XCTAssertGreaterThanOrEqual(c.width, 0)
            XCTAssertGreaterThanOrEqual(c.height, 0)
        }
        let nanFraction = FloatingVisualLayout.cardSize(in: portrait, fraction: .nan,
                                                        margin: margin, chromeHeight: chrome)
        XCTAssertTrue(nanFraction.width.isFinite && nanFraction.height.isFinite)
        XCTAssertGreaterThan(nanFraction.width, 0, "a NaN step must fall back, not vanish")
    }

    func testPictureAspect_degenerateBox_fallsBackToSquare() {
        XCTAssertEqual(FloatingVisualLayout.pictureAspect(forAvailable: .zero), 1, accuracy: 1e-9)
        XCTAssertEqual(FloatingVisualLayout.pictureAspect(
            forAvailable: CGSize(width: .nan, height: 100)), 1, accuracy: 1e-9)
    }

    /// An absurdly wide or tall box is exactly where the clamp has to bite.
    func testPictureAspect_extremeBoxes_clampToTheBand() {
        XCTAssertEqual(FloatingVisualLayout.pictureAspect(
            forAvailable: CGSize(width: 2000, height: 100)),
                       FloatingVisualLayout.maxPictureAspect, accuracy: 1e-9)
        XCTAssertEqual(FloatingVisualLayout.pictureAspect(
            forAvailable: CGSize(width: 100, height: 2000)),
                       FloatingVisualLayout.minPictureAspect, accuracy: 1e-9)
    }
}
