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
// ⛔ THIS FILE HAS NOW BEEN WRONG ABOUT THE LAUNCH STATE IN BOTH DIRECTIONS, and the second
// time is the one that cost something. The first version justified the fullscreen assertion
// with "fullscreen is the app's HOME on every cold launch" and was corrected (#351) to the
// opposite: `@AppStorage("visual.floating.size")` defaults to `WindowSize.small`, so a cold
// launch shows the SMALL card. That correction was true when it was written and is FALSE
// TODAY. `WorkspaceView`'s instrument-home seed (#580) runs once per launch and writes
// `floatingSizeRaw = WindowSize.fullscreen.rawValue` whenever `FeatureFlags.instrumentHome`
// is on — and that key is one of the exactly three registered ON in `EchoelmusicApp.init()`.
// So fullscreen IS the cold-launch state for every user who has not flipped the dev override.
//
// ⭐ WHY THAT MATTERS HERE AND NOT ONLY AS A TIDY-UP. A reader deciding how much the
// fullscreen case deserves reads this block first. Told it is a state the user must cycle
// into, the fullscreen shed table below looks like an edge case; told the truth — it is the
// FIRST SCREEN — the same table says something else entirely (see the ⚠️ note on
// `testFullscreenFitsAtEveryShippedWidth`). A false sentence inside a PASSING test is
// invisible until someone plans from it, which is exactly what happened twice.

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
        // against a 147–175 pt small card and a 232–275 pt medium one). Every size-setting
        // path skips both while anything is recording, so those combinations are unreachable
        // rather than broken. Testing them would pin a state the app refuses to enter — and,
        // worse, would invite a future reader to "fix" the budget until they passed, which
        // would mean shedding a stop button. Their IDLE cases are covered below.
        //
        // ⛔ THIS SENTENCE WAS FALSE FOR ONE FULL SLICE, AND ONLY THE SENTENCE. It read
        // "`cycleSize` skips both", naming ONE writer, while `exitToStudio` — the "Studio"
        // chip in the same toolbar — set `.small` unconditionally. So the state this file
        // called unreachable had a second, reachable door, and the assertions that are
        // deliberately absent here were absent on a false premise. The fix (#366) gave the
        // rule one owner; `testBothSizeDoorsGoThroughTheOneWidenRule` below is what keeps a
        // third door from re-opening the hole. LESSON: a test that documents why it does NOT
        // cover something is making a claim about the WHOLE codebase, not about the lines it
        // touches — and nothing re-checks that claim when a new caller appears.
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

    /// ⚠️ RENAMED (#1017), because the old name promised the slider and the "Studio" chip
    /// and this test never inspects either of them. It makes ONE assertion, that
    /// the bar does not overflow, and `chromeFit` guarantees that by TAKING ITEMS AWAY. A
    /// name that reads as coverage of the slider and the chip is why nobody noticed that on
    /// the phones the app ships to, neither survives.
    ///
    /// MEASURED (re-derive by driving `chromeFit` across widths; the arithmetic is the
    /// `barWidth` helper above): in fullscreen with the transport shown and nothing
    /// recording, the "Studio" chip needs **431 pt** and the look slider **529 pt**. While a
    /// WAV take runs those become 507 pt and 605 pt. The widest phone in `devices` is 440 pt.
    /// So on 375 / 390 / 393 / 402 / 430 pt phones in portrait the only LABELLED door back to
    /// the instrument is shed, and what is left are two glyphs whose words exist only in
    /// VoiceOver ("Exit fullscreen", "Hide visual").
    ///
    /// ⭐ #1036 ANSWERED THE QUESTION THIS BLOCK PARKED, and the paragraph that stood here is
    /// struck rather than deleted, because its MEASUREMENT is what made the answer cheap. It
    /// read: "This test is NOT changed to assert the chip survives … the repair is a product
    /// decision that is not this session's to take … NEEDS-FOUNDER-VERIFY." The founder took
    /// it on 2026-09-06 ("eine Einheit zum steuern … kompakter und übersichtlicher"), and the
    /// answer was the option this block did not list: neither a re-rank ABOVE the transport
    /// nor a cheaper chip, but a re-rank to LAST among the non-recorder items. Measured over
    /// `devices` × wavBusy × videoBusy — 12 states — the chip shed in 10 before the re-rank
    /// and sheds in 1 after; see `testTheLabelledExitSurvivesEveryShippedWidth`, which pins
    /// that and names the one exception. THIS claim keeps its own job unchanged: the bar
    /// must still fit.
    func testFullscreenFitsAtEveryShippedWidth() {
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

    /// ⭐ #1036 — THE LABELLED WAY BACK MUST SURVIVE ON A PHONE. This is the positive half of
    /// the re-rank, and it is the assertion the block above deliberately did NOT make while
    /// the ranking made it false. It is safe to make now for the #364 reason: it pins a
    /// CAPABILITY the founder asked for, not today's arrangement. A future re-rank, a cheaper
    /// chip, a wrapping bar — any of them may satisfy it; only losing the labelled exit fails.
    ///
    /// THE ONE EXCEPTION IS ASSERTED, NOT EXCUSED. On the narrowest width in `devices` with
    /// BOTH a WAV take and a video capture running, the two pinned stop buttons leave no room
    /// and the chip sheds. That is the type's own law applied consistently — "being the exit decides
    /// that it stays" was written for a running take's only stop button, and a stranded
    /// recording is worse than a longer way out (the resize glyph still leaves fullscreen).
    /// It is spelled as an EXPECTATION rather than skipped, so if a future change happens to
    /// rescue that state this claim goes red and gets tightened instead of silently passing.
    func testTheLabelledExitSurvivesEveryShippedWidth() {
        var shedStates: [String] = []
        for bounds in Self.devices {
            for wavBusy in [false, true] {
                for videoBusy in [false, true] {
                    let fit = FloatingVisualLayout.chromeFit(cardWidth: bounds.width,
                                                             isFullscreen: true,
                                                             showsTransport: true,
                                                             wavBusy: wavBusy, videoBusy: videoBusy)
                    if !fit.studioChip {
                        shedStates.append("\(Int(bounds.width))pt wav=\(wavBusy) video=\(videoBusy)")
                    }
                }
            }
        }
        XCTAssertEqual(shedStates, ["375pt wav=true video=true"], """
            The set of states that shed the labelled "Studio" chip changed. Measured: \
            \(shedStates.isEmpty ? "none" : shedStates.joined(separator: " · ")).

            MORE states than the one expected means the only LABELLED way out of the surface \
            the app cold-launches into is gone again on a phone the app ships to — the defect \
            the founder named on 2026-09-06 and #1036 repaired by moving `studioChip` to last \
            among the non-recorder items in `chromeFit`'s shed array. What may shed instead is \
            information (the transport readout) or a display aid (the grid toggle); an EXIT \
            may not. Restore the ranking, or make the exit survive another way — a cheaper \
            chip and a wrapping bar both satisfy this claim.

            FEWER states — an empty list — is GOOD NEWS and still a red, on purpose: it means \
            375 pt with both recorders running now keeps the chip too. Tighten this claim to \
            the empty list and delete the exception paragraph above it; do not widen the \
            assertion to accept both answers, or it stops measuring anything.
            """)
    }

    // MARK: - The shed order is the documented ranking, not an emergent one

    /// `chromeFit` states its shed ORDER in prose and asks a future change to "argue with it
    /// instead of quietly reordering". Nothing checked that the array under the prose still
    /// matches it, and #1017 is exactly the cycle where that ranking decides a product
    /// question — whether the labelled way back to the instrument survives on a 393 pt phone.
    ///
    /// ⭐ WHY THIS IS THE #364-SAFE SHAPE OF THAT CHECK, and the alternative is not. Asserting
    /// "the chip survives at 393 pt" would pin today's DEFECT: the obvious repair (a cheaper
    /// chip) would leave the ranking untouched and this file would go red on a tree that just
    /// got better. Prefix-ness is invariant under every repair on the table — a cheaper chip
    /// moves the THRESHOLD, a re-rank is a deliberate edit to the documented list one line
    /// away, and only an accidental reorder (the thing the prose asks to be protected from)
    /// breaks it.
    ///
    /// The ranking is restated here rather than read from the type, on purpose and for the
    /// same reason `barWidth` re-derives the arithmetic: a check that imports the list it is
    /// checking cannot disagree with it.
    func testTheShedOrderIsAPrefixOfTheDocumentedRanking() {
        // Cheapest-to-lose first: convenience, then information, then a display aid, then
        // the idle video button, THEN the labelled exit, and last the WAV control.
        //
        // ⭐ #1036 MOVED `studioChip` FROM SECOND TO FIFTH, and this list is the documented
        // ranking the array under `chromeFit` must match — so it moves here in the same
        // commit, which is exactly what this claim's failure message asks for. The reason is
        // the type's own law ("rank decides what goes; being the exit decides that it
        // stays"): the chip is the only LABELLED way out of the surface the app cold-launches
        // into. What now sheds earlier is a readout and a display aid, neither of which is a
        // way out of anything.
        let ranking: [(name: String, keep: (FloatingVisualLayout.ChromeFit) -> Bool)] = [
            ("lookSlider",    { $0.lookSlider }),
            ("miniTransport", { $0.miniTransport }),
            ("gridToggle",    { $0.gridToggle }),
            ("videoRecord",   { $0.videoRecord }),
            ("studioChip",    { $0.studioChip }),
            ("wavRecord",     { $0.wavRecord })
        ]

        for isFullscreen in [false, true] {
            for showsTransport in [false, true] {
                for wavBusy in [false, true] {
                    for videoBusy in [false, true] {
                        // An item that cannot appear at all in this state, and a BUSY recorder
                        // (pinned as its take's stop button), are outside the ranking — they
                        // are not "kept because the budget could afford them".
                        let offered = ranking.filter { item in
                            switch item.name {
                            case "lookSlider", "studioChip": return isFullscreen
                            case "miniTransport":            return showsTransport
                            case "videoRecord":              return !videoBusy
                            case "wavRecord":                return !wavBusy
                            default:                         return true
                            }
                        }
                        // From far below the never-shed floor to a desk display, one point at
                        // a time: a reorder that only shows up in a narrow band still shows up.
                        for w in stride(from: CGFloat(20), through: 1200, by: 1) {
                            let fit = FloatingVisualLayout.chromeFit(
                                cardWidth: w, isFullscreen: isFullscreen,
                                showsTransport: showsTransport,
                                wavBusy: wavBusy, videoBusy: videoBusy)
                            let survivors = offered.map { $0.keep(fit) }
                            // ⛔ #1033 — THIS CHECK WAS INVERTED, AND IT HAD BEEN RED SINCE IT
                            // WAS WRITTEN. It read: "once an item is gone, nothing cheaper to
                            // lose may still be present", and implemented that as "nothing
                            // AFTER the first false may be true". With a cheapest-first ranking
                            // and a ladder that drops in order and stops the moment the bar
                            // fits, the survivors are always a SUFFIX of trues — the cheap ones
                            // go, the expensive ones stay. So everything after the first false
                            // that is still true is the ladder working CORRECTLY, and the old
                            // assertion could only pass when nothing shed or everything did.
                            //
                            // Measured on run 34051139175 (`b89998e0`, before any change to the
                            // ranking): this case FAILED, on a correct tree, in the BLOCKING
                            // bundle. Nothing said so — CI/CD reports `failure` on every push
                            // (#396), so a genuinely red guard is indistinguishable from the
                            // host dying. Fifth recorded instance of that pattern; #1028 was
                            // the fourth, four days ago.
                            //
                            // The invariant the ladder actually guarantees, and the one worth
                            // guarding: no item may be KEPT while something MORE expensive to
                            // lose is already gone. Equivalently the survivor pattern must be
                            // false…false,true…true — never a true before a false. That still
                            // catches the thing the prose asks to be protected from (an
                            // accidental reorder of the shed array, which produces exactly such
                            // a true-before-false), and it is now satisfied by the shipped
                            // ranking across all 16 state combinations × 20…1200 pt.
                            guard let firstKept = survivors.firstIndex(of: true) else { continue }
                            let goneAfter = offered.indices
                                .filter { $0 > firstKept && !survivors[$0] }
                                .map { offered[$0].name }
                            XCTAssertTrue(goneAfter.isEmpty, """
                                At \(Int(w))pt (fullscreen=\(isFullscreen), \
                                transport=\(showsTransport), wavBusy=\(wavBusy), \
                                videoBusy=\(videoBusy)) the budget KEPT \
                                "\(offered[firstKept].name)" while having already dropped \
                                \(goneAfter.joined(separator: ", ")) — items the documented \
                                ranking says are MORE expensive to lose. Either the shed array \
                                in `chromeFit` was reordered without its prose, or a new item \
                                was inserted at the wrong rank. Fix the ranking or the prose, \
                                in the same commit.
                                """)
                        }
                    }
                }
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

    // MARK: - Every door to a narrow size goes through the one rule

    /// Source-text, because the rule lives in a `private` method on a `View` struct and the
    /// defect it guards is "someone added a SECOND writer" — which no behavioural test on
    /// the pure layout type can see. `sizeRaw` is the one stored size; every assignment to
    /// it must be widened first.
    func testBothSizeDoorsGoThroughTheOneWidenRule() throws {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let path = root.appendingPathComponent(
            "Sources/Echoelmusic/Studio/FloatingVisualWindow.swift")
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw XCTSkip("""
                source tree not present under \(root.path) — this case inspects source text, \
                so it SKIPS rather than reporting a green it did not earn
                """)
        }
        let code = try String(contentsOf: path, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }

        // The `@AppStorage` DECLARATION also matches "sizeRaw =" and is not a write the rule
        // applies to: it is the cold-launch default (`.small`), and nothing can be recording
        // before the view exists. Excluding it by `var` keeps the check on assignments.
        let writes = code.filter { $0.contains("sizeRaw =") && !$0.contains("var sizeRaw") }
        XCTAssertFalse(writes.isEmpty, """
            No assignment to `sizeRaw` found in FloatingVisualWindow. The stored window size \
            was renamed; re-anchor this case in the same commit rather than letting it pass \
            over an empty list.
            """)
        for write in writes {
            XCTAssertTrue(write.contains("sizeWideEnoughForARunningTake("), """
                A size is written without the running-take widen rule: \
                \(write.trimmingCharacters(in: .whitespaces)). A card narrower than ≈252 pt \
                cannot hold a running recorder's stop button (the whole subject of this \
                file), so a raw write here strands a live take with no way to end it and \
                overflows the card exactly as the founder first reported. This is the \
                #366 defect: the rule was correct and had a second door around it.
                """)
        }
        XCTAssertTrue(code.contains { $0.contains("private func sizeWideEnoughForARunningTake") }, """
            The widen rule is gone. If the geometry changed so that every size can hold a \
            running recorder, delete this case WITH it and say so in the commit — do not \
            leave a rule with no owner and two callers.
            """)
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
