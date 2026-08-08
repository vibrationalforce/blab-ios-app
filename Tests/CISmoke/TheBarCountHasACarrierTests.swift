// TheBarCountHasACarrierTests.swift
// Echoel — the loop length has exactly one place on screen, and the Record tile is not it. #502.
//
// WHAT THIS GUARDS, AND WHY IT IS A PIN RATHER THAN A FIX. #482 made the four export controls
// icon-only tiles. Its own comment then recorded the cost as *"the bar count is gone from the
// screen entirely"* and left "whether the row deserves a state line under it" as a founder-
// visible layout call. Both halves needed correcting, in opposite directions:
//
//   1. The count was NOT gone. #456 had moved `TransportPositionView` out of the chrome
//      transport bar and #490 gave it the middle of the brand header, where it renders
//      `loop \(barInLoop + 1)/\(bars)` from the same `@AppStorage("studio.loopBars")` key with
//      the same `.eight` default. The number `exportLabel` used to say ("Record 8 bars → send")
//      is permanently on screen one band up — and it already was on the day the comment said
//      it was not. Two slices the same afternoon, and the one that removed the text did not
//      know the one that restored the number had landed.
//   2. The half that IS real — mid-take there are no WORDS, only a glyph swap — is now DECIDED
//      rather than deferred. The founder's second red outline on 2494 (2026-08-08) covers this
//      exact stack and asks for *"Usability und kompactheit … aufräumen"*. A permanent fourth
//      line spends the height the ask is about; a conditional one is the `LockCueDoesNot-
//      ShoveTheControls` (#382) class in the very stack that guard was written for, and its
//      REMOVAL would fire on a take end the user did not trigger. So: no line.
//
// ⭐ THE POINT IS THE COUPLING, NOT ANY ONE FACT. Three things now have to move together, and
// before this file nothing noticed if they drifted: the header names the loop length · the
// Record tile stays icon-only (which is WHY the header has to name it) · the tile's spoken
// label still carries all four states (which is why removing the words cost sighted users
// only, not VoiceOver users). Assert any one alone and the other two are free to go: a tree
// that deleted `exportLabel` outright passes a header-only scan, and a tree that deleted the
// header readout passes a label-only scan. That is the #343 trap, and it is the reason this
// file looks broader than "one claim".
//
// ⭐ AND WRITING IT TURNED UP THE ONE REAL DEFECT, which is why this file is not prose-only.
// The premise "both sides read the same key with the same default" was a CLAIM, and checking
// it failed: `EchoelStudioView` reads `StudioDefaultKeys.loopBars.key` / `.value` (the named
// single source), while `WorkspaceView` spelled `"studio.loopBars"` and `.eight` out by hand —
// under a comment instructing the reader to keep them equal. That instruction is exactly the
// mechanism H15-LOOPBARS already defeated once, in this very pair of views. Slice 2 points the
// header at the constant, so the two cannot drift.
//
// ⚠️ HONEST GRADING, IN BOTH DIRECTIONS (#433/#486/#489), transcribed against both trees rather
// than asserted. TWO of the seven methods go red on the parent —
// `testTheCountComesFromThePersistedLoopLength` and
// `testNeitherSideSpellsTheKeyOrTheDefaultByHand` — and they are **ONE defect reported twice**:
// the single hand-written declaration in `WorkspaceView`. Counting that as two findings would
// be the flattering direction of the same error this bundle keeps correcting. Both are red for
// their STATED reason, not by anchor absence: every anchor resolves on the parent tree.
//
// The other five are green on both trees. They are FORWARD pins, and the specific edit they
// exist to catch was already on the plan:
// `scratchpads/PLAN_TIDY_THE_INSTRUMENT_BAND_2026-08-08.md` listed "put `exportLabel` back on
// screen" as slice 2.
//
// ⚠️ `SourceText.codeOnly` IS LOAD-BEARING HERE, AND THAT IS MEASURED, NOT ASSUMED (#484/#485
// each had to retract the stronger claim): the sweep looks for the literal `"studio.loopBars"`
// anywhere under `Sources/`, and this same slice writes that literal INTO a retraction comment
// in `EchoelStudioView.swift` explaining what the header readout replaced. Raw: present.
// Stripped: absent. Without the stripper the sweep would be red on CORRECT code — the #486/#491
// collision again, because this repo writes down what it removed.
//
// ⚠️ LIMITS FIRST. Every assertion is a SOURCE SCAN over `codeOnly` text (#453); nothing here
// renders. It cannot prove the header readout is VISIBLE (that it is unconditional in `topBar`
// is pinned by `TheHeaderShowsTheLoopTests`, deliberately not duplicated here — #416), it
// cannot prove "loop 1/8" READS as a bar count to a human, and it cannot prove VoiceOver
// speaks the four states. NEEDS-FOUNDER-VERIFY: mid-take, is the missing wording actually
// missed, or is the glyph plus the header count enough?
//
// `Tests/CISmoke` is the blocking bundle. Anchor absence THROWS rather than skipping (#454) —
// a `fileExists` bracket around a scan turns exactly the catastrophe this file guards into a
// green run.

import Foundation
import XCTest

private struct BarCountAnchorMissing: Error, CustomStringConvertible {
    let what: String
    var description: String { "anchor missing: \(what)" }
}

final class TheBarCountHasACarrierTests: XCTestCase {

    private static let root: String = {
        var url = URL(fileURLWithPath: #filePath)
        url.deleteLastPathComponent()          // Tests/CISmoke
        url.deleteLastPathComponent()          // Tests
        url.deleteLastPathComponent()          // repo root
        return url.path
    }()

    private func source(_ relative: String) throws -> String {
        let path = Self.root + "/" + relative
        guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else {
            throw BarCountAnchorMissing(what: relative)
        }
        return SourceText.codeOnly(raw)
    }

    /// Brace-matched body of the first declaration whose header line contains `needle`.
    /// Returns the text BETWEEN the opening `{` that closes that header line and its match.
    private func body(of needle: String, in text: String) throws -> String {
        guard let head = text.range(of: needle) else {
            throw BarCountAnchorMissing(what: needle)
        }
        guard let open = text.range(of: "{", range: head.upperBound ..< text.endIndex) else {
            throw BarCountAnchorMissing(what: needle + " — no opening brace")
        }
        var depth = 1
        var i = open.upperBound
        let start = i
        while i < text.endIndex, depth > 0 {
            let c = text[i]
            if c == "{" { depth += 1 }
            if c == "}" {
                depth -= 1
                if depth == 0 { break }
            }
            i = text.index(after: i)
        }
        guard depth == 0 else {
            throw BarCountAnchorMissing(what: needle + " — unbalanced braces")
        }
        return String(text[start ..< i])
    }

    // MARK: - 1. The carrier

    /// The header readout is the ONE place the loop LENGTH reaches the screen as a number.
    func testTheHeaderReadoutNamesTheLoopLength() throws {
        let ws = try source("Sources/Echoelmusic/Studio/WorkspaceView.swift")
        let view = try body(of: "struct TransportPositionView: View", in: ws)
        XCTAssertTrue(view.contains(#"Text("loop \(barInLoop + 1)/\(bars)")"#), """
        `TransportPositionView` no longer renders the loop-length label.

        That label is not decoration. Since #482 made the Record tile icon-only, it is the ONLY
        place `studio.loopBars` reaches the screen as a number — the tile used to say
        "Record 8 bars → send" and now says nothing. If this readout was reworded, reword the
        needle here in the SAME commit and re-read the ⭐ block above
        `Text("loop …")` in `WorkspaceView`. If it was REMOVED, the app no longer tells anyone
        how long the loop they are about to record is, and that is a product decision, not a
        tidy-up.
        """)
    }

    /// …and the number really is the loop length, not a local that happens to be named `bars`.
    func testTheCountComesFromThePersistedLoopLength() throws {
        let ws = try source("Sources/Echoelmusic/Studio/WorkspaceView.swift")
        let view = try body(of: "struct TransportPositionView: View", in: ws)
        XCTAssertTrue(view.contains("@AppStorage(StudioDefaultKeys.loopBars.key)"), """
        `TransportPositionView` stopped reading `StudioDefaultKeys.loopBars`.

        The whole claim of this file is that the header shows the SAME number the Record tile
        stopped saying. Both sides read this one key. A readout fed from anywhere else may look
        identical and mean something different.
        """)
        XCTAssertTrue(view.contains("loopBars.rawValue"), """
        `bars` is no longer derived from `loopBars.rawValue` in `TransportPositionView`.

        Guarded separately from the `@AppStorage` line because the declaration can survive while
        the USE moves to something else — at which point the label above would still read
        "loop n/N" with an N that is not the loop length.
        """)
    }

    /// THE REGRESSION. Both declarations read the NAMED default, so they cannot diverge —
    /// a diverging hand-written default already shipped once (H15-LOOPBARS: the chrome said
    /// "loop N/4" while the instrument composed 8 bars).
    func testNeitherSideSpellsTheKeyOrTheDefaultByHand() throws {
        for file in ["Sources/Echoelmusic/Studio/WorkspaceView.swift",
                     "Sources/Echoelmusic/Studio/EchoelStudioView.swift"] {
            let text = try source(file)
            XCTAssertTrue(text.contains("@AppStorage(StudioDefaultKeys.loopBars.key)"), """
            \(file) no longer reads `StudioDefaultKeys.loopBars.key`.

            `@AppStorage` defaults are PER DECLARATION: on a fresh install, where the key is
            unwritten, two declarations with different defaults disagree ON SCREEN — the chrome
            saying "loop N/4" over an instrument composing 8 bars. That bug shipped once, and
            the comment that used to guard against it ("Default MUST match the semantic owner")
            was an instruction to a human, not a mechanism.
            """)
            XCTAssertTrue(text.contains("StudioDefaultKeys.loopBars.value"), """
            \(file) no longer reads `StudioDefaultKeys.loopBars.value`.

            The KEY and the DEFAULT are two halves of one decision and both have to come from
            the named constant. Reading the key from `StudioDefaultKeys` while hard-coding
            `.eight` looks tidy and re-opens exactly the same divergence.
            """)
        }
    }

    /// COUNTERWEIGHT to the one above: the key string must exist in exactly one place. Without
    /// this, a third surface could hard-code `"studio.loopBars"` with its own default and both
    /// assertions above would stay green.
    func testTheKeyStringLivesOnlyInItsOwnDeclaration() throws {
        let owner = "Sources/Echoelmusic/Core/StudioDefaultKeys.swift"
        XCTAssertTrue(try source(owner).contains(#"key: "studio.loopBars""#), """
        `StudioDefaultKeys.loopBars` no longer declares the key `"studio.loopBars"`.

        Everything else in this file assumes this is where the one spelling lives.
        """)
        // Spelled out in steps with explicit types rather than one chained expression: this
        // bundle has no local compiler, and #488 lost a whole gate cycle to a single line of
        // Swift that could not be checked here. `enumerator` yields `Any`, so the cast is not
        // optional decoration.
        let root: String = Self.root + "/Sources"
        var files: [String] = []
        if let walker = FileManager.default.enumerator(atPath: root) {
            for entry in walker {
                guard let relative = entry as? String, relative.hasSuffix(".swift") else { continue }
                files.append(relative)
            }
        }
        XCTAssertFalse(files.isEmpty, "found no Swift sources under \(root) — anchor is wrong")
        var offenders: [String] = []
        for relative in files where !relative.hasSuffix("StudioDefaultKeys.swift") {
            let text = SourceText.codeOnly(
                (try? String(contentsOfFile: root + "/" + relative, encoding: .utf8)) ?? "")
            if text.contains(#""studio.loopBars""#) { offenders.append(relative) }
        }
        XCTAssertEqual(offenders, [], """
        These files spell the loop-length key out by hand instead of reading
        `StudioDefaultKeys.loopBars.key`:

        \(offenders.joined(separator: "\n"))

        A second literal is how the two readouts diverged before (H15-LOOPBARS). Point the new
        site at the constant; if it genuinely needs a DIFFERENT key, it is not this setting and
        should not borrow its name.
        """)
    }

    // MARK: - 2. Why the carrier is needed — the tile is icon-only

    func testTheRecordTileIsStillIconOnly() throws {
        let studio = try source("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        let row = try body(of: "private var quickActionRow: some View", in: studio)
        XCTAssertTrue(row.contains("EchoelIconTile(systemImage: exportIcon"), """
        The Record control is no longer built from `EchoelIconTile(systemImage: exportIcon…)`.

        This is the PREMISE of everything above: the header has to name the bar count because
        this tile stopped saying it. If the tile carries words again, the header readout is no
        longer load-bearing for the count and the ⛔ blocks in both files need re-reading — and
        the six equal-size tiles the founder asked for (#481/#482) have gained an odd one out.
        """)
    }

    /// The words did not vanish for everyone — VoiceOver kept all four states. That asymmetry
    /// is what makes "sighted users only" the honest description of the cost.
    func testVoiceOverStillHearsAllFourStates() throws {
        let studio = try source("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        let row = try body(of: "private var quickActionRow: some View", in: studio)
        XCTAssertTrue(row.contains(".accessibilityLabel(exportLabel)"), """
        The Record tile no longer speaks `exportLabel`.

        An icon-only control whose spoken label was also removed is the lying-control class:
        nothing on screen and nothing in the ear. The whole reason #482 could ship icon-only is
        that VoiceOver lost nothing.
        """)
        let label = try body(of: "private var exportLabel: String", in: studio)
        for state in ["Stop and discard this take", "Recording loop…", "Writing .wav…"] {
            XCTAssertTrue(label.contains(state), """
            `exportLabel` no longer produces "\(state)".

            Its four states are the only remaining wording for what the take is doing. Losing
            one silently narrows what a VoiceOver user is told mid-record, and this file is the
            only thing standing between that and a green run.
            """)
        }
    }

    // MARK: - 3. The decision — no fourth line in this stack

    /// COUNTERWEIGHT, and the one that made this file worth writing. The plan for #502 listed
    /// "put `exportLabel` back on screen" as its next slice; the founder's compactness ask
    /// retired it. A status line here would be a fourth band in the stack #456 just shortened.
    func testNoStatusLineWasAddedUnderTheRecordRow() throws {
        let studio = try source("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        let row = try body(of: "private var quickActionRow: some View", in: studio)
        XCTAssertFalse(row.contains("Text("), """
        `quickActionRow` now renders a `Text`.

        This row is four equal icon tiles by founder decision (#481/#482, *"die sollen immer
        gleichgroß sein"*), and the band it sits in is the one the founder asked to make MORE
        compact on 2026-08-08. A status line here costs that height permanently; a conditional
        one inserts and removes itself around a take, which is the #382 shove in the exact stack
        #382 was written for — and its removal fires on a take END the user did not trigger.

        If a founder ask now NAMES this line, this assertion is what you delete, deliberately,
        in that commit — together with the ⭐ block above `quickActionRow`. Do not weaken it to
        make an unrelated edit pass.
        """)
    }
}
