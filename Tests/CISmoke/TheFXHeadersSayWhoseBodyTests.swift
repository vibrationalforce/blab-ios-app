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
// `modulator.sourceIsSynthetic`, published by the same ~10 Hz throttled, change-gated branch
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
//     to quote what it retracts) and 6a. ⛔ 6a's flip was attributed here to `AlwaysOnBioView`'s
//     doc comment "twice", and that is impossible as written: that doc block sits ABOVE the
//     `private struct AlwaysOnBioView` anchor, so it is outside the extracted block entirely —
//     the block contains exactly one `bus.latestBio`, the code line. The three raw `bus.` hits
//     that actually make 6a stripper-dependent are in **`BioModLiveView`**'s own doc comments.
//     The measurement (1 flip on the parent) was right and its explanation was fiction, which
//     is the more dangerous half: a number can be re-derived, a wrong mechanism gets believed.
//   ⚠️ TWO BASELINES NOW, and both are stated because the file grew a claim after it shipped.
//     Against **e8482e5** (before #641) the numbers above hold. Against **ce92d75** (#641 as
//     first shipped) the only red assertions are the five of claims 3 and 3b — the review
//     regression: the Live heading derived from the freshness-gated contributions while the
//     always-on heading read raw, so the two contradicted each other past `.fallback`'s 5 s
//     window. Everything else is green there, which is exactly what a follow-up that fixes a
//     derivation and changes no wording should look like. Measured against both, 15/15 green
//     on this tree.
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
    private static let modulator = "Sources/Echoelmusic/Tools/FXBioModulator.swift"

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
            `FXBioModulator` no longer derives `sourceIsSynthetic` from the RAW frame. If it \
            went back to the freshness-gated `frame`, the Live heading contradicts the \
            always-on heading directly beneath it for every demo frame older than 5 s.
            """)
        let view = try block(startingAt: "private struct BioModLiveView", in: try codeText(Self.fxView))
        XCTAssertTrue(squeezed(view).contains("modulator.sourceIsSynthetic"), """
            The Live heading no longer asks `modulator.sourceIsSynthetic`. Deriving it in the \
            view from `liveContributions` is precisely the first cut's defect — those flags \
            answer a different gate than the heading below them.
            """)
        XCTAssertFalse(squeezed(view).contains("liveContributions.contains(where:"), """
            The Live heading derives from the contributions again. See above: same value, \
            different gate, contradictory headings on one screen.
            """)
    }

    /// 3b — COUNTERWEIGHT, and the reason `sourceIsSynthetic` is a conjunction rather than a
    /// bare source test. An LFO carrier is a real oscillator and is deliberately never marked
    /// synthetic; a set of only LFO routes contains no body and no demo, so a bare source test
    /// would have put "simulated demo → sound" over rows nothing simulated drives — trading one
    /// false claim for another.
    ///
    /// ⚠️ REGISTERED, NOT FIXED: in that same LFO-only state the heading falls back to
    /// "body → sound", which over-claims in the other direction. That is PRE-EXISTING and
    /// untouched — `BioModContribution` carries no carrier-kind field, so naming it needs its
    /// own slice. Recorded here rather than left implied, because claim 3 above reads as if the
    /// LFO question were settled and it is not.
    func testTheProvenanceIsConjoinedWithHavingABioRoute() throws {
        let modulator = try codeText(Self.modulator)
        XCTAssertTrue(squeezed(modulator).contains("anyBioRoute&&"), """
            `sourceIsSynthetic` is no longer conjoined with "is any route a bio route". A bare \
            source test marks an LFO-only section "simulated demo → sound", which is a fresh \
            false claim made by the machinery built to remove false claims.
            """)
        XCTAssertTrue(squeezed(modulator).contains("ifcase.bio=route.carrier"), """
            The bio-route test is gone or changed shape. It is the half that keeps an all-LFO \
            section out of the demo heading.
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
