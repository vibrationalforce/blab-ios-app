// ChromeBudgetFitsTests.swift
// Echoel — the floating visual's toolbar must fit inside the card it sits in.
//
// WHAT THIS GUARDS (#365). The founder reported the window "geht über den Rand hinaus"
// with the Echoel logo no longer properly visible. `FloatingVisualLayout.cardSize` was
// never the bug — it is provably fit-with-margins on every path. The CHROME BAR was: an
// `HStack` of rigid-width children ending in `.frame(maxWidth: .infinity)`, which clamps
// a view UP to the proposal and never DOWN past its own children. The bar reported its
// oversize width, the enclosing `VStack` adopted it, and the background, border and
// clip shape were drawn at THAT width — outside the card, off the screen, logo first.
//
// ⭐ THE ASSERTION THAT MATTERS is the loop at the bottom: for every device width × size
// step × busy state, the retained items must fit. That loop is not decoration — it FOUND
// TWO REAL DEFECTS in the fix while it was being written, neither of which is visible by
// reading the code:
//   1. The first shed order dropped the WAV control at the medium step while a take was
//      recording — and that control IS the take's stop button. Shedding it is worse than
//      the overflow it solved: the overflow is ugly, this loses a recording.
//   2. After pinning the busy recorders, the MEDIUM step still overflowed by eight points
//      (252 vs 244 on a 393 pt phone). Eight points. The `cycleSize` guard had been
//      written to skip only `.small`; it has to skip both.
// Both came out of arithmetic, not inspection. That is the whole reason this file exists.
//
// ⚠️ WHAT A GREEN HERE DOES NOT MEAN. The costs in `ChromeCost` are RESERVES, not
// measurements — Foundation cannot measure a `Text`, so text-bearing items carry a
// conservative constant. A green proves the BUDGET is self-consistent and that the shed
// rule still protects the stop buttons. It cannot prove that the rendered row fits: that
// needs real SF Symbol advances, real Atkinson metrics and the user's Dynamic Type, i.e.
// a device. Being conservative is the safe direction — it sheds one item too early rather
// than one too late, and shedding early is invisible while shedding late is the bug.
//
// ⛔ CORRECTION TO THIS FILE'S OWN FIRST VERSION (found while working #351). The fullscreen
// assertion below used to justify itself with "fullscreen is the app's HOME on every cold
// launch". That is FALSE: the window's size is `@AppStorage("visual.floating.size")`
// defaulting to `WindowSize.small`, so a cold launch shows the SMALL floating card and
// fullscreen is only reached by cycling the resize button. I wrote it from a half-memory of
// the CLAUDE.md line about the visual being a home surface — which is about the window being
// VISIBLE (`visual.floating.visible` does default to true), not about its SIZE. The assertion
// was right; its stated reason was invented. Nothing downstream depended on it, which is
// exactly why it would have survived: a false sentence inside a PASSING test is invisible
// until someone plans from it.

import Foundation
import XCTest
@testable import Echoelmusic

final class ChromeBudgetFitsTests: XCTestCase {

    // MARK: - The same arithmetic the view will perform, re-derived independently

    /// Re-implements the bar's width from `ChromeCost` rather than calling a helper in the
    /// type under test. If `chromeFit` and this disagree, one of them is wrong and the
    /// test says so — which is the point of not sharing the code.
    private func barWidth(_ f: FloatingVisualLayout.ChromeFit, wavBusy: Bool) -> CGFloat {
        typealias C = FloatingVisualLayout.ChromeCost
        var total = C.logo + 2 * C.iconButton   // logo, resize, close — never shed
        var items = 3
        if f.lookSlider    { total += C.lookSlider;    items += 1 }
        if f.studioChip    { total += C.studioChip;    items += 1 }
        if f.miniTransport { total += C.miniTransport; items += 1 }
        if f.gridToggle    { total += C.iconButton;    items += 1 }
        if f.videoRecord   { total += C.iconButton;    items += 1 }
        if f.wavRecord     { total += wavBusy ? C.wavRecording : C.iconButton; items += 1 }
        return total + C.gap * CGFloat(items) + C.horizontalPadding
    }

    /// The shipped card width for a floating step, from the shipped constants.
    private func cardWidth(_ bounds: CGSize, fraction: CGFloat) -> CGFloat {
        FloatingVisualLayout.cardSize(in: bounds, fraction: fraction,
                                      margin: 12, chromeHeight: 44).width
    }

    /// Portrait safe-area boxes for the three iPhone widths the app ships to.
    private static let devices: [CGSize] = [
        CGSize(width: 375, height: 700),
        CGSize(width: 393, height: 750),
        CGSize(width: 440, height: 830)
    ]

    // MARK: - The stop button is never the thing that disappears

    func testARunningRecorderKeepsItsStopButtonAtEveryWidth() {
        // Widths from absurdly narrow to a desk display: the pin must hold everywhere,
        // including where NOTHING fits, because that is exactly when a shed-by-rank
        // implementation would drop it.
        for w in stride(from: CGFloat(40), through: 1200, by: 37) {
            let wav = FloatingVisualLayout.chromeFit(cardWidth: w, isFullscreen: false,
                                                     showsTransport: true,
                                                     wavBusy: true, videoBusy: false)
            XCTAssertTrue(wav.wavRecord, """
                At a card width of \(w) pt the budget shed the WAV control while a take was \
                RECORDING. That control is the take's only stop button — shedding it does \
                not tidy the bar, it strands a running recording with no way to end it. \
                Rank decides what goes; being the exit decides that it stays.
                """)
            let vid = FloatingVisualLayout.chromeFit(cardWidth: w, isFullscreen: false,
                                                    showsTransport: true,
                                                    wavBusy: false, videoBusy: true)
            XCTAssertTrue(vid.videoRecord, """
                At a card width of \(w) pt the budget shed the video control while a capture \
                was RUNNING — same defect as the WAV case, same consequence.
                """)
        }
    }

    func testADegenerateWidthStillKeepsARunningRecorder() {
        for bad in [CGFloat(0), -1, .nan, .infinity] {
            let fit = FloatingVisualLayout.chromeFit(cardWidth: bad, isFullscreen: true,
                                                     showsTransport: true,
                                                     wavBusy: true, videoBusy: true)
            XCTAssertTrue(fit.wavRecord && fit.videoRecord, """
                A degenerate card width (\(bad)) dropped a running recorder. The guard for \
                non-finite input must shed to the FLOOR, not below it — the floor includes \
                whatever is currently recording.
                """)
            XCTAssertFalse(fit.lookSlider || fit.studioChip || fit.miniTransport || fit.gridToggle, """
                A degenerate card width returned optional chrome. Returning "everything \
                fits" on input this type cannot reason about is the silent-pass failure \
                the whole budget exists to prevent.
                """)
        }
    }

    // MARK: - The floating card can never be narrower than what it keeps

    func testEveryStepAndBusyStateFitsOnEveryShippedWidth() {
        let steps: [(name: String, fraction: CGFloat, transport: Bool)] = [
            ("large", FloatingVisualLayout.largeStep, true)
        ]
        // ⛔ SMALL AND MEDIUM ARE ABSENT ON PURPOSE, and the reason is the second defect in
        // the header: with a recorder pinned they provably cannot fit (≈252 pt needed
        // against a 147–175 pt small card and a 232–275 pt medium one). `cycleSize` skips
        // both while anything is recording, so those combinations are unreachable rather
        // than broken. Testing them would pin a state the app refuses to enter — and, worse,
        // would invite a future reader to "fix" the budget until they passed, which would
        // mean shedding a stop button. Their IDLE cases are covered below.
        for bounds in Self.devices {
            for step in steps {
                let cw = cardWidth(bounds, fraction: step.fraction)
                for wavBusy in [false, true] {
                    for videoBusy in [false, true] {
                        let fit = FloatingVisualLayout.chromeFit(
                            cardWidth: cw, isFullscreen: false,
                            showsTransport: step.transport,
                            wavBusy: wavBusy, videoBusy: videoBusy)
                        XCTAssertLessThanOrEqual(barWidth(fit, wavBusy: wavBusy), cw, """
                            \(Int(bounds.width))pt phone, \(step.name) step, \
                            wavBusy=\(wavBusy) videoBusy=\(videoBusy): the retained chrome \
                            is wider than the card. This is the founder's original report \
                            ("geht über den Rand hinaus") reappearing — the bar draws past \
                            the card and off the screen, and the logo goes first.
                            """)
                    }
                }
            }
        }
    }

    func testTheIdleSmallAndMediumStepsFit() {
        for bounds in Self.devices {
            for (name, fraction, transport) in [("small", FloatingVisualLayout.smallStep, false),
                                                ("medium", FloatingVisualLayout.mediumStep, true)] {
                let cw = cardWidth(bounds, fraction: fraction)
                let fit = FloatingVisualLayout.chromeFit(cardWidth: cw, isFullscreen: false,
                                                         showsTransport: transport,
                                                         wavBusy: false, videoBusy: false)
                XCTAssertLessThanOrEqual(barWidth(fit, wavBusy: false), cw, """
                    \(Int(bounds.width))pt phone, \(name) step, nothing recording: the \
                    retained chrome still overflows the card. These two steps are the \
                    narrowest the app offers, so they are where an added toolbar item \
                    breaks something first.
                    """)
            }
        }
    }

    func testFullscreenFitsWithTheSliderAndTheStudioChip() {
        for bounds in Self.devices {
            for wavBusy in [false, true] {
                let fit = FloatingVisualLayout.chromeFit(cardWidth: bounds.width,
                                                         isFullscreen: true,
                                                         showsTransport: true,
                                                         wavBusy: wavBusy, videoBusy: false)
                XCTAssertLessThanOrEqual(barWidth(fit, wavBusy: wavBusy), bounds.width, """
                    Fullscreen on a \(Int(bounds.width))pt phone, wavBusy=\(wavBusy): the \
                    chrome overflows. This is the widest state the bar ever has and the one \
                    the founder's report named, so an overflow here is the original bug back.
                    """)
            }
        }
    }

    // MARK: - Floating chrome cannot acquire fullscreen-only items

    func testTheSliderAndStudioChipNeverAppearOnAFloatingCard() {
        for bounds in Self.devices {
            // A deliberately generous width: if the budget could ever ADD these it would
            // be here, where nothing forces a shed.
            let fit = FloatingVisualLayout.chromeFit(cardWidth: bounds.width * 4,
                                                     isFullscreen: false,
                                                     showsTransport: true,
                                                     wavBusy: false, videoBusy: false)
            XCTAssertFalse(fit.lookSlider || fit.studioChip, """
                The budget offered the look slider or the "Studio" chip on a FLOATING card. \
                It may only ever take items away — the two are fullscreen-only in the view, \
                and a budget that can add them would put a control on screen that the view \
                does not build.
                """)
        }
    }

    func testAWiderCardNeverKeepsLessThanANarrowerOne() {
        // Monotonicity. A shed order that is not monotonic produces the behaviour users
        // describe as "it flickers when I resize": an item vanishing as the window GROWS.
        func kept(_ w: CGFloat) -> Int {
            let f = FloatingVisualLayout.chromeFit(cardWidth: w, isFullscreen: true,
                                                   showsTransport: true,
                                                   wavBusy: false, videoBusy: false)
            return [f.lookSlider, f.studioChip, f.miniTransport,
                    f.gridToggle, f.videoRecord, f.wavRecord].filter { $0 }.count
        }
        var previous = kept(60)
        for w in stride(from: CGFloat(60), through: 900, by: 13) {
            let now = kept(w)
            XCTAssertGreaterThanOrEqual(now, previous, """
                Growing the card to \(w) pt REMOVED an item (\(previous) → \(now)). The shed \
                order must be monotonic in width, or a control disappears while the user is \
                making the window bigger.
                """)
            previous = now
        }
    }
}
