// TheNarrationHeadingNamesItsDriverTests.swift
// Echoel — #644: the narration card's HEADING claimed a body over a paragraph that denied it.
//
// WHAT THIS GUARDS. `BioExplanation.text(for:tempo:)` has marked its own provenance since #627:
// while the demo generator drives, the paragraph opens "EchoelAI (demo signal) — ", and when
// nothing was read it opens "tempo holds at N BPM; no pulse measured yet" with the phrase
// " from your live signal," deliberately removed. That file's own comment explains at length why
// such a marker must LEAD rather than trail — "a qualifier placed anywhere but the front
// corrects a claim the reader has already accepted". The disclosure row directly above it read,
// unconditionally, "What your body is doing to the sound". Same defect as #640 (Sound panel),
// #641/#642 (FX headers) and #643 (the two always-on sentences).
//
// ⛔ THE FIRST CUT USED A `Bool` AND CLOSED ONLY HALF OF IT. `synthetic == false` meant BOTH
// "a real body" and "nothing was measured", so the heading still said "your body" over "no pulse
// measured yet" — and `BioExplanation`'s own doc records that as the COMMON case (device log
// 2494, `body=0` in every generate breadcrumb for ~475 s). Both mandatory reviewers found it
// independently, and `TheMetricSheetRowsSayWhoseBodyTests` had written the defect down IN
// ADVANCE, one slice earlier. `BioNarrationDriver` has three cases; `.nothingMeasured` drops the
// possessive rather than inventing a subject.
//
// ⚠️ THE SURFACE IS DOORLESS BY FOUNDER DECISION, and that is said first because it changes what
// this slice may claim. `memory/decisions.md` (2026-07-12) records it verbatim: "Die Erklärung
// da brauchen wir erstmal nicht. Das kommt später in nem richtig funktionierenden EchoelAI…" —
// so this is the `moodPadsSection` shape (decided), not an undecided orphan drifting toward
// task #326. Nobody can read either the heading or the paragraph today. Copy on a PARKED surface
// is still fixed, so the door that a real EchoelAI command layer eventually brings does not
// arrive carrying a false claim. It is NOT a user-visible fix and must not be quoted as one, and
// of the three surfaces this family has touched it is the LEAST read, not the most: measured
// mounts are `BodyShapesThisSoundLine()` 1, `AlwaysOnBioPanelStrip()` 1, this one 0.
//
// ⭐ WHY THE WHOLE DISCLOSURE MOVED INTO A LEAF. The heading needs the same fact the paragraph
// used, and that fact now lives on `StudioCaption`. ⛔ THE FIRST DRAFT JUSTIFIED THE MOVE WITH A
// PRESENT-TENSE FREEZE HAZARD — "reading it in `liveNarrationBanner` would put an `@Observable`
// read into a body `EchoelStudioView.body` evaluates" — AND THAT IS REFUTED BY THIS FILE'S OWN
// PARAGRAPH ABOVE (#425): nothing mounts `liveNarrationBanner`, so a read placed there today
// reaches no body and carries no freeze risk. The construction is still right, for a PROSPECTIVE
// reason: the day the surface is doored, the read would be in the Picker-hosting body, and the
// leaf is what re-dooring needs anyway.
//
// KIND (§1): **MIXED, and the end-to-end half is what the review bought.** The three states and
// their three strings now live on `BioNarrationDriver`, a pure `Sendable` enum, and
// `BioExplanation.driver(for:)` decides between them — so claims 1a–1f DRIVE THE SHIPPED
// FUNCTION and read the rendered heading. The rest is a SOURCE-TEXT SCAN, because a `private`
// SwiftUI struct in another file cannot be mounted from this bundle.
//
// GRADING (#433 / §3), DRIVEN in Python against the parent (4ffa60d) — and the first draft of
// this block mislabelled THREE of its own entries by reasoning about them instead of running
// them, which is the second cycle running that this exact block has had to retract a label.
//   · **8 SCAN VERDICTS, all green on this tree, all red on the parent.** Of those:
//     — **6 RED BY MEASUREMENT** (they read files the parent has): 2b, 3a, 4a, 4b, 5a, 6b.
//     — **2 RED BY CONSTRUCTION** (they read `LiveNarrationDisclosure.swift`, which this commit
//       creates, so on the parent `codeText` throws): 2a and 7a. Not evidence — written down
//       rather than folded into the count, the way #642 had to.
//   · **6 FORWARD, BEHAVIOURAL (1a–1f)** — the three states and their three strings, driven
//     through `BioExplanation.driver(for:)` and `BioNarrationDriver.heading`. They cannot be
//     red-on-parent either: the enum does not exist there, so a bundle containing them does not
//     compile.
//   · **1 COUNTERWEIGHT green on both trees** — 6a, that the paragraph still marks itself. It
//     drives a function the parent has, so its green there is real.
//   ⛔ **6b AND 7a WERE FILED AS COUNTERWEIGHTS AND ARE NOT.** `caption.driver` occurs zero
//     times on the parent, so the `== 1` count fails there; and 7a's file is absent. Both are
//     red-on-parent, one by measurement and one by construction. A counterweight is an assertion
//     that is GREEN ON BOTH TREES — that is the whole point of the category, and calling a
//     regression one inflates the "what must not change" half of the report.
//   · **Stripper: TRAGEND — 2 of the 8 scan verdicts flip raw-vs-stripped on this tree, 0 of 8
//     on the parent.** Driven, not assumed, and the first draft named the wrong two: they are
//     **3a and 4a**, not 4a/4b. 3a flips because the next RAW line after the text write is the
//     three-line comment this slice inserted; 4a because `EchoelStudioView`'s own ⛔ retraction
//     quotes the banned literal in full. Both are green only because `SourceText.codeOnly`
//     blanks comments — one keystroke from load-bearing, which is the note
//     `TheNarrationCannotClaimABodyItDidNotReadTests` already carries for the same reason.
//
// ⚠️ #364: a different honest shape is not forbidden. Dropping the heading, folding it into the
// paragraph, or marking at the card level would all satisfy the law and turn claims 1/4 red —
// that is the moment to rewrite this file. Claim 1 pins whole sentences, so an ordinary copy
// edit goes red too; that is a stricter pin than the law needs, and it is disclosed rather than
// hidden. What is forbidden silently is a heading that names a body the paragraph does not.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheNarrationHeadingNamesItsDriverTests: XCTestCase {

    private static let leaf = "Sources/Echoelmusic/Studio/LiveNarrationDisclosure.swift"
    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"
    private static let caption = "Sources/Echoelmusic/Studio/StudioCaptionView.swift"
    private static let director = "Sources/Echoelmusic/Sequencer/BioMusicDirector.swift"

    /// A frame every clause can read (`heartRateBPM > 0` and `coherence > 0` are the gates
    /// `BioStateSummary` applies), so `driver` turns on the SOURCE alone.
    private func measured(_ source: BioSource) -> BioSampleFrame {
        BioSampleFrame(timestamp: 1000, heartRateBPM: 64, hrvNormalized: 0.45,
                       breathRate: 12, breathPhase: 0.3, coherence: 0.62,
                       motionEnergy: 0, source: source)
    }

    /// A frame that arrived and measured nothing — every gate in `BioStateSummary` is `> 0`.
    private func silent(_ source: BioSource) -> BioSampleFrame {
        BioSampleFrame(timestamp: 1000, heartRateBPM: 0, hrvNormalized: 0,
                       breathRate: 0, breathPhase: 0, coherence: 0,
                       motionEnergy: 0, source: source)
    }

    // MARK: - 1  the three states, driven

    /// 1 — FORWARD, and the strong kind (§1). The heading is decided by a pure function and
    /// rendered from one `switch`, so this drives the states and reads the string a player
    /// would see.
    func testTheHeadingAnswersAllThreeStates() {
        // 1a — a measured real body.
        XCTAssertEqual(BioExplanation.driver(for: measured(.cameraPPG)), .body)
        XCTAssertEqual(BioNarrationDriver.body.heading,
                       "What your body is doing to the sound", """
            The real-body heading changed wording. This slice adds two wordings; it does not \
            rename the row.
            """)
        // 1b — the demo generator, measuring normally.
        XCTAssertEqual(BioExplanation.driver(for: measured(.fallback)), .simulatedDemo)
        XCTAssertEqual(BioNarrationDriver.simulatedDemo.heading,
                       "What the simulated demo source is doing to the sound", """
            The demo heading changed wording or went back to claiming a body. The paragraph \
            beneath it opens "EchoelAI (demo signal) — " in this state.
            """)
        // 1c — no frame at all: the case #506's doc calls the COMMON one.
        XCTAssertEqual(BioExplanation.driver(for: nil), .nothingMeasured)
        XCTAssertEqual(BioNarrationDriver.nothingMeasured.heading,
                       "What is shaping the sound", """
            The no-reading heading names somebody. The paragraph beneath it says "no pulse \
            measured yet" — a possessive here is the first cut's defect, which a `Bool` could \
            not express and both reviewers caught.
            """)
        // 1d — a frame that ARRIVED and measured nothing is the same case, on either source.
        XCTAssertEqual(BioExplanation.driver(for: silent(.cameraPPG)), .nothingMeasured)
        XCTAssertEqual(BioExplanation.driver(for: silent(.fallback)), .nothingMeasured, """
            A demo frame that measured nothing is being called the demo DRIVER. Nothing is \
            driving: every clause was dropped, so the heading must claim nobody — the demo's \
            own "(demo signal)" prefix is a statement about the SOURCE and stays either way.
            """)
    }

    /// 1e/1f — FORWARD. The heading and the paragraph share ONE predicate, which is the whole
    /// reason the driver is computed in `BioExplanation` and not beside the call site.
    func testTheHeadingAndTheParagraphAgreeAboutWhetherAnythingWasRead() {
        for (label, frame) in [("nil", BioSampleFrame?.none),
                               ("silent camera", .some(silent(.cameraPPG))),
                               ("silent demo", .some(silent(.fallback)))] {
            let paragraph = BioExplanation.text(for: frame, tempo: 100)
            XCTAssertTrue(paragraph.contains("no pulse measured yet"), """
                \(label): the paragraph stopped saying nothing was measured, so claim 1c's \
                premise is gone. Re-derive both together — they are one predicate by design.
                """)
            XCTAssertEqual(BioExplanation.driver(for: frame), .nothingMeasured, """
                \(label): the paragraph says "no pulse measured yet" and the heading names \
                somebody. One card, two answers — the defect this file exists for.
                """)
        }
        // …and the converse: a read body must NOT get the no-reading heading.
        let live = BioExplanation.text(for: measured(.cameraPPG), tempo: 100)
        XCTAssertFalse(live.contains("no pulse measured yet"))
        XCTAssertEqual(BioExplanation.driver(for: measured(.cameraPPG)), .body)
    }

    // MARK: - 2–5  the wiring

    /// 2a — the leaf renders the published driver rather than deriving its own.
    func testTheLeafRendersTheCaptionsDriver() throws {
        let leaf = try codeText(Self.leaf)
        XCTAssertTrue(squeezed(leaf).contains("Text(caption.driver.heading)"), """
            `LiveNarrationDisclosure` no longer renders `caption.driver.heading`. A second, \
            independent answer can observe a different instant than the paragraph one line \
            below it — the way #641 had to be fixed twice.
            """)
        XCTAssertTrue(squeezed(leaf).contains("accessibilityLabel(caption.driver.voiceOverLabel)"), """
            The spoken LABEL stopped naming the driver. A `Button`'s label replaces its visible \
            text for VoiceOver and a hint is user-suppressible, so a marker carried only by the \
            hint lets a listener get a different answer than a reader. Every sibling surface in \
            this family prefixes the label.
            """)
    }

    /// 2b — the field it reads exists on the caption.
    func testTheCaptionCarriesTheDriver() throws {
        XCTAssertTrue(try codeText(Self.caption).contains("var driver: BioNarrationDriver"), """
            `StudioCaption` lost its `driver` field. The heading then has nowhere to get the \
            fact from except a second read, which is the defect this slice removed.
            """)
    }

    /// 3a — REGRESSION. The driver is written on the statement AFTER the text, from the same
    /// `frame`. Adjacency is the whole guarantee.
    ///
    /// ⛔ NOT A FIXED LINE WINDOW. The first draft took `lines[textAt ..< textAt + 8]`, which
    /// `Tests/CISmoke/CLAUDE.md` §2 (#408) calls unsound by construction: `SourceText.codeOnly`
    /// blanks comments while PRESERVING line count, so the three-line retraction this slice
    /// itself inserted between the two writes already ate three of the eight slots. The next
    /// reviewer to widen that block would have turned this red on correct code. The NEXT
    /// NON-BLANK code line is exact and cannot rot.
    func testTheDriverIsWrittenOnTheNextStatement() throws {
        let lines = try codeText(Self.studio)
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let textAt = lines.firstIndex(where: {
            $0.contains("caption.text = BioExplanation.text(")
        }) else {
            return XCTFail("""
                `caption.text = BioExplanation.text(` is gone from \(Self.studio) — re-anchor \
                this scan rather than letting it pass on nothing (#454).
                """)
        }
        let next = lines[(textAt + 1)...].first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        XCTAssertEqual(next?.trimmingCharacters(in: .whitespaces),
                       "caption.driver = BioExplanation.driver(for: frame)", """
            The driver write is no longer the statement immediately after the text write. Two \
            writes that can drift apart in time are two facts, and the heading then describes a \
            different take than the paragraph — invisible until someone switches source.
            """)
    }

    /// 4a/4b — REGRESSION, measured red on the parent. Neither the heading nor its spoken half
    /// may live as a literal in the root file: there is one definition, on `BioNarrationDriver`.
    func testTheRootFileHoldsNeitherHalfOfTheOldClaim() throws {
        let studio = try codeText(Self.studio)
        XCTAssertFalse(studio.contains("\"What your body is doing to the sound\""), """
            `EchoelStudioView` holds the heading literal again. The three strings are owned by \
            `BioNarrationDriver.heading`; a literal here is a second definition (#416).
            """)
        XCTAssertFalse(studio.contains("how your body shapes the music"), """
            The VoiceOver hint claims a body again. It is unconditional prose about the \
            CONTROL — the provenance belongs in the label, which the driver owns.
            """)
    }

    /// 5a — REGRESSION. One spelling of "is this the demo" on this path (#639).
    func testThePredicateHasOneSpellingOnThisPath() throws {
        XCTAssertFalse(try codeText(Self.director).contains("source == .fallback"), """
            `BioExplanation` went back to an inline `== .fallback`. `BioSource.isSynthetic` is \
            the one definition, and the heading beside it now asks the same question (#416).
            """)
    }

    // MARK: - 6–7  what must NOT change

    /// 6a — COUNTERWEIGHT, and the one that would invalidate the whole slice. Marking the
    /// heading is only correct BECAUSE the paragraph marks itself.
    ///
    /// ⚠️ IT DUPLICATES A STRONGER CHECK ON PURPOSE, and says so rather than pretending
    /// otherwise: `TheNarrationCannotClaimABodyItDidNotReadTests` asserts the same prefix by
    /// DRIVING the function. Here it is a premise pin — if that guard is ever retired, this file
    /// still knows what its own argument rests on (#416 read forwards, not backwards).
    func testTheParagraphStillMarksItself() {
        XCTAssertTrue(BioExplanation.text(for: measured(.fallback), tempo: 100)
                        .hasPrefix("EchoelAI (demo signal) — "), """
            `BioExplanation` no longer prefixes the demo narration. The heading above it is now \
            conditional on the same source — if the paragraph stops naming it, this file's \
            premise is gone and the fix belongs there, not here (#627).
            """)
    }

    /// 6b — REGRESSION (the grading block retracts its first label). The root body did not
    /// acquire the read the leaf exists to hold.
    ///
    /// ⛔ THE FIRST DRAFT'S NEEDLE WAS `caption.synthetic&&` AND COULD NOT FAIL FOR ITS OWN
    /// REASON (#367). Its message said "reads it in a condition" while the needle matched only a
    /// left-hand `&&` — `if caption.driver == …`, a ternary, everything a real regression would
    /// write, sailed past. A COUNT is exact: the file legitimately contains the WRITE, and
    /// nothing else.
    func testTheRootBodyDidNotAcquireTheRead() throws {
        let studio = try codeText(Self.studio)
        XCTAssertEqual(studio.components(separatedBy: "caption.driver").count - 1, 1, """
            `caption.driver` occurs more than once in \(Self.studio). Exactly one occurrence is \
            legal — the write in `generate()`. A second is a READ in a view property, and \
            `EchoelStudioView.body` hosts every `.menu` Picker of the instrument (10.76.41/50).
            """)
    }

    /// 7a — REGRESSION BY CONSTRUCTION, and the one the review added. Both existing doorlessness
    /// guards
    /// anchor on the NAME `liveNarrationBanner` inside `EchoelStudioView.swift`; the renderable
    /// unit is now a top-level struct in its own file, so mounting it from anywhere else would
    /// leave both of them green while the surface went live. Every "parked surface" sentence in
    /// this file's header depends on this staying 1.
    func testTheDisclosureIsStillMountedOnlyByTheParkedProperty() throws {
        let all = try [Self.studio, Self.leaf, Self.caption].map(codeText).joined(separator: "\n")
        XCTAssertEqual(all.components(separatedBy: "LiveNarrationDisclosure(").count - 1, 1, """
            `LiveNarrationDisclosure(` is constructed somewhere new. That is welcome — the \
            founder parked this surface on 2026-07-12 pending a real EchoelAI command layer, and \
            re-dooring it is a founder call, not a refactor. When it happens, the "nobody can \
            read this" sentences in this file's header and in the leaf's own header become false \
            and move in the SAME commit (#456).
            """)
    }

    // MARK: - source access

    private struct NarrationAnchorMissing: Error { let reason: String }

    private func squeezed(_ code: String) -> String { code.filter { !$0.isWhitespace } }

    private func codeText(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path),
            "Sources/ not present in this checkout")
        let url = root.appendingPathComponent(relative)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw NarrationAnchorMissing(reason: """
                \(relative) is missing while the tree is present — renamed or moved. Re-anchor \
                this scan; do not let it skip (#454).
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: url, encoding: .utf8))
    }
}
