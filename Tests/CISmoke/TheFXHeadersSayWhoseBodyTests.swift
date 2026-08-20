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
// ⭐ NEITHER HEADER ADDS AN OBSERVATION, which is why this is a small slice rather than a
// freeze-law question. The Live header derives from `modulator.liveContributions`, which that
// body already reads one line above; the always-on header derives from `frame`, already bound at
// the top of ITS body and handed to every row. Same source as the rows in both cases — so a
// header cannot disagree with what is under it, which is the failure a second, independently
// computed test would have re-introduced (#416).
//
// ⚠️ `contains`, NOT `allSatisfy`, on the Live header, and claim 3 is what makes that a decision
// rather than a coincidence. An LFO carrier is a real oscillator and is deliberately NEVER
// marked synthetic (`BioModContribution.synthetic`'s own doc, and `TheFXRoutesSayWhoseBodyTests`
// carries it as a counterweight). One bio route on the demo plus one LFO route would make
// `allSatisfy` false, and the header would claim a body for a section that is half simulated.
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
// KIND (§1): **SOURCE-TEXT SCAN** throughout. `BioModLiveView` and `AlwaysOnBioView` are
// `private` SwiftUI structs in another file; this bundle can neither mount nor render them, so
// what a header says can only be read as text. The DATA behind it is end-to-end elsewhere
// (`TheFXRoutesSayWhoseBodyTests` drives `BioModContribution.synthetic` itself). What stays a
// DEVICE PROBE: that the changed headings read well above their rows.
//
// GRADING (#433 / §3), transcribed in Python against the parent (e8482e5) and this tree:
//   · **5 RED-ON-PARENT ASSERTIONS across 4 claims** — the two new headings (1a, 2a), the
//     `contains(where:)` derivation (3a) and both halves of the footer clause (4a, 4b). FOUR
//     separate strings, so four findings; #486's "one absence, N times" does not apply here
//     because nothing shared is missing — each is its own edit.
//   · **7 COUNTERWEIGHTS, green on both trees** — 1b and 2b (the real-body headings survive:
//     this slice adds a second wording, it does not rename the sections), 3b (not `allSatisfy`,
//     so an LFO route cannot be swept up), 5a and 5b (the two instructional strings untouched)
//     and 6a/6b (each header still derives from the SAME value its own rows use, which is the
//     thing that makes the fix worth anything).
//   · **Stripper: TRAGEND — 2 of 12 verdicts flip on this tree, 1 of 12 on the parent.**
//     Measured by driving every needle raw and stripped against both, not reasoned. The two are
//     4b (the ⛔ block this slice added quotes the retracted clause verbatim — a retraction has
//     to quote what it retracts) and 6a (`AlwaysOnBioView`'s doc comment names `bus.latestBio`
//     twice while explaining why it reads it). 6a flips on the PARENT too, which is why the
//     stripper is not merely insurance here.
//   ⛔ AND THE MEASUREMENT CAUGHT TWO DEFECTS IN THIS FILE BEFORE IT SHIPPED, both in the
//     flattering direction: claims 1a and 2a were written with `squeezed(...)` and were FALSE
//     ON THEIR OWN TREE (`stripped=False raw=False`) — the squeeze removes the spaces INSIDE a
//     string literal. The tool that earned its place one slice ago on a code expression is the
//     wrong tool for a literal, and only driving it says so. The header count "3 REGRESSIONS /
//     3 COUNTERWEIGHTS / 2 of 8" that stood here was written before any of it ran.
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

    // MARK: - 1–2  each header can name the demo source

    /// 1 — REGRESSION. The live-contribution heading follows its own rows.
    func testTheLiveHeaderCanNameTheDemoSource() throws {
        let code = try codeText(Self.fxView)
        // ⛔ NOT `squeezed(...)` — THE FIRST DRAFT USED IT HERE AND THE ASSERTION WAS FALSE ON
        // ITS OWN TREE. `squeezed` strips every whitespace character, INCLUDING the spaces
        // inside a string literal, so this needle would have had to be written
        // `"Live—simulateddemo→sound"` to match. The squeeze earned its place one slice ago
        // (#640) on a CODE expression a line-wrap could break; a string literal is the one thing
        // it must never touch, because whitespace is part of the value. Measured, not reasoned:
        // driving the model printed `stripped=False raw=False` on the tree that renders it.
        XCTAssertTrue(code.contains("\"Live — simulated demo → sound\""), """
            The "Live — body → sound" heading is unconditional again. Every row beneath it has \
            carried a "Demo" chip since #635b; a heading that asserts a body over them makes the \
            screen say two things at once, and the heading is the half a scanning reader takes.
            """)
        XCTAssertTrue(code.contains("\"Live — body → sound\""), """
            The real-body heading is gone. This slice adds a second wording for one case; it \
            does not rename the section. If the heading genuinely changed, four prose sites \
            quote it by name and move in the SAME commit (#456).
            """)
    }

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

    // MARK: - 3  the LFO exclusion survives

    /// 3 — COUNTERWEIGHT, and the assertion that makes claim 1 a decision instead of an
    /// accident. An LFO carrier is a real oscillator; `BioModContribution.synthetic` is
    /// deliberately false for it. `allSatisfy` would therefore leave a half-simulated section
    /// claiming a body, and `contains` is the only form that reads "any synthetic row is enough".
    func testTheLiveHeaderAsksWhetherANYRowIsSynthetic() throws {
        let body = try block(startingAt: "private struct BioModLiveView", in: try codeText(Self.fxView))
        XCTAssertTrue(squeezed(body).contains("liveContributions.contains(where:\\.synthetic)"), """
            The Live header no longer asks `contains(where: \\.synthetic)`. If it moved to \
            `allSatisfy`, one LFO route alongside one demo-driven bio route puts the plain \
            "body → sound" heading back over a section that is half simulated — and nothing \
            else in the tree would notice, because every row would still be individually right.
            """)
        XCTAssertFalse(squeezed(body).contains("liveContributions.allSatisfy"), """
            The Live header asks `allSatisfy`. See above: an LFO carrier is never synthetic by \
            design, so `allSatisfy` is false exactly when a mixed section most needs marking.
            """)
    }

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
