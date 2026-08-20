// TheFXHeadersSayWhoseBodyTests.swift
// Echoel — #641: the FX sheet's two section headers claimed a body over rows already marked Demo.
//
// WHAT THIS GUARDS, and it is the cheapest kind of defect to find and the easiest to walk past.
// The "All parameters" sheet carries two sections, and since #635b / #498 every ROW in both of
// them says whose reading it is: the live contribution rows draw a "Demo" chip from
// `BioModContribution.synthetic`, the always-on channel rows mark themselves from
// `frame.source`. The two HEADERS above them went on asserting, unconditionally:
//   · "Live — body → sound"
//   · "Always on — body → timbre"
// So on one screen every row said "Demo" and the heading over them said "body". That is the
// same contradiction #640 removed from the Sound panel, and the MIRROR IMAGE of #637, where the
// marking lived in the section header and the rows drew unmarked numbers. Both directions fail
// the same reader: whichever of the two a person scans first is the one that lies to them.
//
// ⭐ NEITHER HEADER ADDS A NEW SOURCE OR A NEW CADENCE. The Live header asks
// `modulator.liveOrigin`, published by the same ~10 Hz throttled, change-gated branch
// that already publishes `liveContributions` — a property this body reads about thirty lines
// above (⛔ two drafts said "one line up"; it is ~30, and nobody checked). The always-on header
// derives from `frame`, already bound at the top of ITS body and handed to every row.
// ⚠️ NOT THE ABSOLUTE "NO NEW OBSERVATION" THIS BLOCK CLAIMED FIRST. `if a, b` short-circuits,
// so with `isRunning == false` the old body read only `isRunning` while a header reads its
// property unconditionally — a new observation EDGE, in a state the shipping app cannot reach
// (`FXBioModulator.stop()` has no production caller; `start()` runs once at launch). True as
// "no new observation in any state the app reaches"; the absolute version is what the next
// reader would have relied on instead of re-deriving it.
//
// ⚠️ `contains`, NOT `allSatisfy`, on the bio half, and claim 1e is what makes that a decision
// rather than a coincidence. One bio route on the demo plus one LFO route would make
// `allSatisfy` false, and the header would claim a body for a section that is half simulated.
//
// ⛔ AND THE STATE THAT PARAGRAPH ORIGINALLY DESCRIBED WAS A LIVE OVER-CLAIM FOR ONE CYCLE
// (#642). An LFO carrier is a real oscillator and is deliberately NEVER marked synthetic
// (`BioModContribution.synthetic`'s own doc), so a section of only LFO routes fell through the
// demo test and rendered "Live — body → sound" over rows in which no body is involved at all —
// the product's core claim, printed over an oscillator. #641's own review registered it and
// this file recorded it as "PRE-EXISTING and untouched"; a registered over-claim is still an
// over-claim on the founder's screen. `FXModulation.liveOrigin(routes:sourceIsSynthetic:)` now
// answers all FOUR states and `LiveModOrigin.heading` owns all four strings in one `switch`.
//
// ⚠️ TWO STRINGS IN THIS FILE ARE DELIBERATELY *NOT* TOUCHED, and naming them is half the point
// of the slice — the honesty family's real risk now is over-correction, not under-correction:
//   · `"Let the body shape the effects: e.g. coherence → reverb, breath → filter…"` renders when
//     there are NO routes, and
//   · `"Start a session to watch the body move these parameters."` renders when the modulator is
//     NOT running.
// Both are INSTRUCTIONS about what the instrument does, on screens where nothing is being
// claimed about a current reading. Marking them would be a fresh false implication (that a demo
// is running when none is) and would cost the product its own sentence for nothing. Claim 5
// pins both, so a later "sweep the file for `body`" cannot quietly take them.
//
// KIND (§1): **MIXED, AND THE MIX IS THE POINT OF #642.** The Live heading's four states are
// now decided by a pure function in `Core/FXModulation.swift`, so claims 1a–1f DRIVE IT AND READ
// THE RENDERED STRING — end-to-end behaviour, the strong kind. Everything else stays a
// SOURCE-TEXT SCAN, because `BioModLiveView` and `AlwaysOnBioView` are `private` SwiftUI structs
// in another file that this bundle can neither mount nor render: that a view puts the published
// value on screen, and that a header does not grow a second source, are only readable as text.
// What stays a DEVICE PROBE: that the changed headings read well above their rows.
//
// GRADING (#433 / §3), transcribed in Python against the parent (b1effab) and this tree:
//   ⚠️ **THE END-TO-END CLAIMS CANNOT BE "RED ON PARENT", AND SAYING SO IS NOT A CONFESSION.**
//     `FXModulation.liveOrigin` and `LiveModOrigin` do not exist on b1effab, so a bundle
//     containing claims 1a–1f does not COMPILE there. "Red on parent" is true by construction
//     and therefore measures nothing — the honest category for them is **FORWARD** (§3): they
//     pin behaviour the next edit could break, not a defect this commit removed. Their strength
//     comes from being behavioural, not from a colour on an old tree. Two families of guards
//     have been over-sold in this repo by quoting a red that only proved a symbol was new.
//   · **2 RED-ON-PARENT ASSERTIONS** — 1g, that `BioModLiveView` holds no `"Live — "` literal of
//     its own (on b1effab it holds two, and this is what keeps a fifth spelling from growing
//     back beside the `switch`, #416), and claim 3's middle assertion, that the view renders
//     `modulator.liveOrigin.heading`. Both measured, not reasoned.
//   · **6 FORWARD assertions (1a–1f)** — the four states, the `enabled` filter, and `contains`
//     rather than `allSatisfy`. 1b and 1c also act as counterweights: `.body` and `.noRoutes`
//     both keep the plain heading, so the slice adds wordings and renames nothing.
//   · **10 COUNTERWEIGHTS, green on both trees** — 2a/2b (the always-on section untouched), 3a
//     (the raw gate), 3c (no derivation from the contributions), 4a/4b (the footer clause),
//     5a/5b (the two instructional strings) and 6a/6b (each header answers from the value its
//     own rows use). 12 scan verdicts total, all green on this tree.
//   · 3b is the one assertion this slice REWROTE rather than kept: it scanned the modulator for
//     `anyBioRoute&&`, an expression #642 deleted when the arithmetic moved into the pure
//     function. Its subject survives as 1e/1f, measured instead of scanned (§4 — a guard over a
//     changed surface moves in the SAME commit).
//   · **Stripper: TRAGEND — 4 of the 12 scan verdicts flip on this tree, 3 of 12 on b1effab.**
//     Driven raw and stripped against both, not reasoned. The four are 1g, 3c, 4b and 6a, and
//     three of them are `XCTAssertFalse`s whose forbidden text this file or the edited view
//     QUOTES in a ⛔ block — a retraction has to name what it retracts, which is precisely how a
//     negative scan without a stripper convicts a correct tree. (⛔ The first draft of this line
//     said "the two … (4b and 6a) are unchanged here" and carried the count forward from the
//     e8482e5 measurement. Both halves were wrong, in a paragraph whose subject is that verdicts
//     must be driven.) ⚠️ NOT applied to any string literal — claims 1a–1f
//     compare values, and claims 2a/2b/4a/5a/5b compare literals raw, because `squeezed` removes
//     the spaces INSIDE a literal and made two assertions false on their own tree one slice ago.
//
// ⚠️ #364: a different honest shape is not forbidden. Dropping the arrow form, folding the two
// sections into one, or marking at the sheet level instead would all satisfy the law and turn
// claims 1/2 red — that is the moment to rewrite this file. What is forbidden silently is a
// heading that claims a body over rows that say otherwise.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheFXHeadersSayWhoseBodyTests: XCTestCase {

    private static let fxView = "Sources/Echoelmusic/Studio/EchoelFXView.swift"
    private static let modulator = "Sources/Echoelmusic/Tools/FXBioModulator.swift"

    // MARK: - 1  the Live heading, driven — all four states, end to end

    private func route(_ carrier: FXModCarrier, enabled: Bool = true) -> FXModRoute {
        FXModRoute(carrier: carrier, target: .reverbMix, enabled: enabled)
    }

    /// 1 — FORWARD, and the strong kind (§1). The Live heading is no longer a ternary in a
    /// `private` view that only a text scan can reach: `FXModulation.liveOrigin` decides, and
    /// `LiveModOrigin.heading` renders. So the guard drives the four states and reads the string
    /// the founder would see.
    ///
    /// ⚠️ `.noRoutes` KEEPS THE PLAIN HEADING ON PURPOSE (1c). With nothing enabled the section
    /// renders its empty-state invitation, so the heading is the section's NAME and claims
    /// nothing about a current reading. Printing "LFO → sound" there would invent an oscillator
    /// that does not exist — the over-correction this family has already had to retract twice.
    func testTheLiveHeadingAnswersAllFourStates() {
        // 1a — a bio route on the demo generator.
        XCTAssertEqual(
            FXModulation.liveOrigin(routes: [route(.bio(.coherence))], sourceIsSynthetic: true),
            .simulatedDemo)
        XCTAssertEqual(LiveModOrigin.simulatedDemo.heading, "Live — simulated demo → sound", """
            The demo heading changed wording. Every row beneath it has carried a "Demo" chip \
            since #635b; a heading that asserts a body over them makes the screen say two things \
            at once, and the heading is the half a scanning reader takes.
            """)
        // 1b — COUNTERWEIGHT. A measured body still gets the section's own name.
        XCTAssertEqual(
            FXModulation.liveOrigin(routes: [route(.bio(.coherence))], sourceIsSynthetic: false),
            .body)
        XCTAssertEqual(LiveModOrigin.body.heading, "Live — body → sound", """
            The real-body heading is gone. This slice adds wordings for three cases; it does not \
            rename the section. If the heading genuinely changed, several prose sites quote it \
            by name and move in the SAME commit (#456).
            """)
        // 1c — COUNTERWEIGHT, and the deliberate one: no routes, no claim, plain name.
        XCTAssertEqual(FXModulation.liveOrigin(routes: [], sourceIsSynthetic: true), .noRoutes)
        XCTAssertEqual(LiveModOrigin.noRoutes.heading, LiveModOrigin.body.heading, """
            `.noRoutes` grew its own heading. With nothing enabled the section shows its \
            empty-state invitation and the heading is a NAME; a state-specific string there \
            would describe a driver that is not running.
            """)
        // 1d — the state #642 exists for.
        XCTAssertEqual(
            FXModulation.liveOrigin(routes: [route(.lfo)], sourceIsSynthetic: true), .lfoOnly, """
            An LFO-only section is being classified by the SOURCE again. An LFO carrier is a \
            real oscillator and is deliberately never marked synthetic, so the source flag says \
            nothing whatever about a section that contains no bio route.
            """)
        XCTAssertEqual(LiveModOrigin.lfoOnly.heading, "Live — LFO → sound", """
            The LFO heading changed wording or went back to claiming a body. "body → sound" over \
            rows driven by an oscillator is the product's core claim printed over a defect.
            """)
    }

    /// 1e/1f — FORWARD, and the two ways this function can be wrong without being obviously
    /// wrong. `enabled` is filtered because `contributions(routes:frame:now:)` — the thing that
    /// builds the rows — filters on it in its first line; a heading computed over a different
    /// set describes a different section than the one below it (#416). And the bio test is
    /// `contains`, not `allSatisfy`, so a mixed section cannot claim a pure body.
    func testTheLiveHeadingUsesTheSameRouteSetItsRowsDo() {
        // 1e — a switched-off bio route may not mark a section it cannot touch.
        XCTAssertEqual(
            FXModulation.liveOrigin(
                routes: [route(.bio(.coherence), enabled: false), route(.lfo)],
                sourceIsSynthetic: true),
            .lfoOnly, """
            A DISABLED bio route is still deciding the heading. The rows below are built from \
            enabled routes only; a heading that counts the disabled one describes a section the \
            reader is not looking at.
            """)
        // …and with nothing enabled at all, that is `.noRoutes`, not a claim.
        XCTAssertEqual(
            FXModulation.liveOrigin(
                routes: [route(.bio(.coherence), enabled: false)], sourceIsSynthetic: true),
            .noRoutes)
        // 1f — `contains`, not `allSatisfy`: half-simulated is not a body.
        XCTAssertEqual(
            FXModulation.liveOrigin(
                routes: [route(.bio(.coherence)), route(.lfo)], sourceIsSynthetic: true),
            .simulatedDemo, """
            A section that is half demo-driven is claiming a body (or an LFO). `allSatisfy` \
            here would let one LFO route launder a demo reading into "body → sound".
            """)
    }

    /// 1g — REGRESSION, measured red on b1effab, and the only assertion in claim 1 that is.
    /// The four strings live in `LiveModOrigin.heading`, one `switch`. A literal in the view
    /// beside it is how a fifth spelling grows (#416).
    func testTheViewHoldsNoHeadingStringOfItsOwn() throws {
        let live = try block(startingAt: "private struct BioModLiveView", in: try codeText(Self.fxView))
        XCTAssertFalse(live.contains("\"Live — "), """
            `BioModLiveView` holds a "Live — …" string literal again. The heading's four states \
            and four strings are owned by `LiveModOrigin.heading`; a literal here is a second \
            definition of the same decision, free to drift out of step with the `switch`.
            """)
    }

    // MARK: - 2  the always-on header

    /// 2 — REGRESSION. Same for the always-on section, whose rows mark themselves from the very
    /// frame this header now reads.
    func testTheAlwaysOnHeaderCanNameTheDemoSource() throws {
        let code = try codeText(Self.fxView)
        // Unsqueezed for the same reason as claim 1 — this is a string literal, not code.
        XCTAssertTrue(code.contains("\"Always on — simulated demo → timbre\""), """
            The "Always on — body → timbre" heading is unconditional again. `AlwaysOnBioRow` \
            marks each channel from `frame.source`; the heading over them has to answer from \
            the same frame or the section contradicts itself.
            """)
        XCTAssertTrue(code.contains("\"Always on — body → timbre\""), """
            The real-body heading is gone — see claim 1. `AHeldReadingSaysSoTests`' own file \
            header quotes this string.
            """)
    }

    // MARK: - 3  both headings ask the SAME gate — the regression the review caught

    /// 3 — REGRESSION against the first cut of #641, and the assertion this whole follow-up
    /// exists for. The first version derived the Live heading in the view from
    /// `liveContributions.contains(where: \\.synthetic)`. Those flags are computed behind
    /// `bus?.usableBio()` — a FRESHNESS gate — while the always-on heading three rows down reads
    /// `bus.latestBio` RAW, which is never cleared. Past `.fallback`'s 5 s window every
    /// contribution stops contributing, `synthetic` collapses to false, and the sheet renders
    /// "Live — body → sound" directly above "Always on — simulated demo → timbre" from the SAME
    /// frame, permanently. **The slice re-created its own defect one section away**, and a
    /// source-text scan of the view could never have seen it.
    ///
    /// ⚠️ THE TWO REGIMES STAY SPLIT. `TwoFreshnessRegimesAreDeliberateTests` pins that the FX
    /// routes gate on `usableBio()` while the always-on timbre path reads raw, and unifying THOSE
    /// is an audible change needing a hearing test. What this pins is narrower and is not in
    /// tension with it: the two HEADINGS may not be derived through different gates.
    func testBothHeadingsAskTheRawGate() throws {
        let modulator = try codeText(Self.modulator)
        XCTAssertTrue(squeezed(modulator).contains("bus?.latestBio?.source.isSynthetic"), """
            `FXBioModulator` no longer derives `liveOrigin` from the RAW frame. If it \
            went back to the freshness-gated `frame`, the Live heading contradicts the \
            always-on heading directly beneath it for every demo frame older than 5 s.
            """)
        let view = try block(startingAt: "private struct BioModLiveView", in: try codeText(Self.fxView))
        XCTAssertTrue(squeezed(view).contains("modulator.liveOrigin.heading"), """
            The Live heading no longer renders `modulator.liveOrigin.heading`. Deriving it in \
            the view from `liveContributions` is precisely the first cut's defect — those flags \
            answer a different gate than the heading below them.
            """)
        XCTAssertFalse(squeezed(view).contains("liveContributions.contains(where:"), """
            The Live heading derives from the contributions again. See above: same value, \
            different gate, contradictory headings on one screen.
            """)
    }

    // ⛔ 3b STOOD HERE AND IS RETIRED BY #642, not deleted quietly. It scanned the modulator for
    // `anyBioRoute&&`, the conjunction that kept a bare source test from marking an LFO-only
    // section "simulated demo". That expression no longer exists: the arithmetic moved into
    // `FXModulation.liveOrigin`, where the same subject is MEASURED by claims 1e/1f instead of
    // spelled. Its own ⚠️ note recorded the opposite over-claim ("body → sound" over LFO rows) as
    // "PRE-EXISTING and untouched" — that is what #642 fixed. §4: a guard over a changed surface
    // moves in the SAME commit as the surface, and a scan whose needle the commit deleted would
    // otherwise have gone red for the right reason with the wrong message.

    // MARK: - 4  the held clause stops naming the body as sender

    /// 4 — REGRESSION, and the one that is reworded rather than made conditional. The footer
    /// explains a MECHANISM ("what does held mean"), not who is in the room, so its honest
    /// subject is the signal under both sources — no read, no branch, no second string to keep
    /// in step. `AlwaysOnBioRow`'s VoiceOver took the same route at #484.
    func testTheHeldClauseNamesTheSignalNotTheBody() throws {
        let code = try codeText(Self.fxView)
        XCTAssertTrue(code.contains("the signal has stopped arriving"), """
            The held clause no longer names the signal. `AHeldReadingSaysSoTests` needs this \
            sentence to keep distinguishing "no reading" from "held" — that half is unchanged; \
            what moved is only its subject.
            """)
        XCTAssertFalse(code.contains("your body has stopped sending it"), """
            The held clause names the body as the sender again. While the demo generator drives \
            that is false twice over — nothing your body sent has stopped, because your body was \
            never sending it — and it now sits under a heading that says "simulated demo".
            """)
    }

    // MARK: - 5–6  what must NOT change

    /// 5 — COUNTERWEIGHT, and the guard against this family's real remaining risk. Both strings
    /// below render precisely when nothing is being claimed about a current reading: one with no
    /// routes, one with the modulator stopped. They are INSTRUCTIONS about what the instrument
    /// does. Marking them would imply a demo is running when none is — a fresh false claim made
    /// by the machinery built to remove false claims.
    func testTheInstructionalStringsAreLeftAlone() throws {
        let code = try codeText(Self.fxView)
        XCTAssertTrue(code.contains("Let the body shape the effects"), """
            The no-routes invitation was reworded or marked. It renders when there are NO \
            routes, so it claims nothing about a current reading — it says what the instrument \
            is for. A "sweep the file for the word body" cleanup is how this one gets taken.
            """)
        XCTAssertTrue(code.contains("Start a session to watch the body move these parameters"), """
            The not-running line was reworded or marked. Same reasoning: it renders when the \
            modulator is STOPPED, so there is no source to name and nothing to qualify.
            """)
    }

    /// 6 — COUNTERWEIGHT, and the one that makes the whole slice worth more than two strings.
    /// Each header must answer from the SAME value its own rows use. If either grew its own
    /// read, the header and the rows under it become two independent tests of "is this
    /// synthetic" — free to disagree inside one section, which is the defect this fixes rather
    /// than a smaller version of it (#416).
    func testEachHeaderAnswersFromTheSameValueItsRowsUse() throws {
        let code = try codeText(Self.fxView)
        let live = try block(startingAt: "private struct BioModLiveView", in: code)
        let always = try block(startingAt: "private struct AlwaysOnBioView", in: code)
        XCTAssertFalse(squeezed(live).contains("bus."), """
            `BioModLiveView` acquired a bus read. Its rows are drawn from \
            `modulator.liveContributions`; a header answering from a different source can \
            disagree with the rows directly beneath it — and it would also be a NEW live read \
            in a view that hosts `.menu` Pickers (10.76.41/50).
            """)
        XCTAssertEqual(squeezed(always).components(separatedBy: "bus.latestBio").count - 1, 1, """
            `AlwaysOnBioView` no longer reads `bus.latestBio` exactly once. One read, bound to \
            `frame` and handed to both the header and every row, is what stops the section \
            straddling two instants — the #637 defect, where two reads of a freshness-gated \
            value produced a marked bar beside an unmarked number.
            """)
    }

    // MARK: - source access

    private struct FXAnchorMissing: Error { let reason: String }

    private func squeezed(_ code: String) -> String { code.filter { !$0.isWhitespace } }

    private func codeText(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path),
            "Sources/ not present in this checkout")
        let url = root.appendingPathComponent(relative)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FXAnchorMissing(reason: """
                \(relative) is missing while the tree is present — renamed or moved. Re-anchor \
                this scan; do not let it skip (#454).
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: url, encoding: .utf8))
    }

    /// A declaration's body by brace matching — never a fixed line window. This repo writes
    /// 30–40-line comment blocks and `SourceText.codeOnly` preserves line count, so any window
    /// is unsound by construction and rots as the prose grows (#408).
    private func block(startingAt anchor: String, in code: String) throws -> String {
        guard let start = code.range(of: anchor) else {
            throw FXAnchorMissing(reason: """
                `\(anchor)` is gone from \(Self.fxView) — renamed or restructured. Re-anchor \
                rather than letting the scan skip (#454).
                """)
        }
        var depth = 0
        var out = ""
        for ch in code[start.lowerBound...] {
            out.append(ch)
            if ch == "{" { depth += 1 }
            if ch == "}" { depth -= 1; if depth == 0 { break } }
        }
        guard depth == 0, out.count > 200 else {
            throw FXAnchorMissing(reason: """
                Brace matching from `\(anchor)` returned \(out.count) characters — the \
                extraction failed, and every negative assertion over it would pass over \
                nothing (#454).
                """)
        }
        return out
    }
}
