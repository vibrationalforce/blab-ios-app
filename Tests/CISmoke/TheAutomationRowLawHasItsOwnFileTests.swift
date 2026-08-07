// TheAutomationRowLawHasItsOwnFileTests.swift
// Echoel — #472. The timeline-automation LAW shared a file with an unmounted view.
//
// ⭐ WHAT WAS ACTUALLY WRONG, said narrowly: nothing computed a wrong number.
// `TimelineAutomationRowMath` is pure, correct, and read in production by
// `Core/TimelineStore.swift` — it just lived inside
// `Studio/TimelineAutomationRow.swift`, whose other lines were a SwiftUI view nothing
// mounts. CLAUDE.md's register names the hazard by hand: a plausible "delete the
// doorless file" cleanup would have broken the store. Doorless is a property of a
// VIEW, deletable a property of a FILE, and this repo keeps filing the two together.
// #472 separated them; the arithmetic is byte-identical.
//
// ⭐ #473 THEN DELETED THE VIEW HALF, and this file had to move with it — that is the
// half worth reading. `source()` reads with `try` past a directory-only skip, so the
// assertion that named the view file would have gone HARD RED on a correct tree. A
// commit that removes a surface pulls the guards over that surface in the SAME commit
// (#456). The replacement is stronger, not weaker: instead of asking whether ONE named
// file re-declares the law, it walks `Sources/` and requires EXACTLY ONE declaration
// anywhere — which is the question #416 is actually about.
//
// ⛔ HONEST GRADING, because the flattering version is available. At #472, ONE
// assertion was a regression in the ordinary sense — the half reading a file that did
// not exist before that commit. The rest were pins: the live call site, the alias
// behaviour, and a compile-pin on the members that lose their only caller. None of
// them could have been red the day before, and saying otherwise would be the #433
// defect inside the file that cites it.
// ⚠️ #473 adds two assertions and neither is a regression either. "The deleted file is
// absent" and "exactly one file declares the law" are both GREEN on the pre-#473 tree —
// the first trivially so once the file is gone, the second because there was only ever
// one declaration. They are FORWARD guards against the two ways this can rot: the view
// being resurrected under its old name, and a second copy of the law appearing anywhere.
//
// ⚠️ THE BEHAVIOURAL HALF DUPLICATES `Tests/EchoelmusicTests/TimelineAutomationRowTests`
// ON PURPOSE, which is normally the #416 defect. The reason it is not: that suite is
// the NON-blocking one (#208 — `full-tests.yml` cannot fail a merge), and
// `sameParameter` is the single member of this type with a production caller. A law
// that decides which automation lane a parameter resolves to should be able to fail a
// merge. Everything else stays where it is; this file does not copy the geometry
// cases.
//
// ⚠️ WHAT THIS FILE CANNOT DO. Its scanning half proves where text sits, not that the
// app behaves. And none of it says timeline automation is REACHABLE — it is not, and
// neither #472 nor #473 changes that. #473 only removed a view that nothing mounted;
// `AutomationPlayer` still has no production writer, so a curve persisted by an older
// build can play but no surface today can draw one.
// ⚠️ The prose citations that blocked the deletion — SIX of them, across FIVE files, because
// `EchoelValueField` carries two — are relocated, not discarded:
// the `DATA MODEL (honest):` block is inlined in `Core/PerTrackParameterKeyPath.swift`
// (it had already lost a `:11-16` line range to #472 — a pointer is only as durable as
// what it points at), and the two `EchoelValueField` premises are restated as HISTORICAL
// evidence, which is honest rather than convenient: the SwiftUI claims are unchanged and
// the in-repo witness is gone. Nothing here can verify that relocation — it is prose.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheAutomationRowLawHasItsOwnFileTests: XCTestCase {

    /// ⛔ THE SKIP GATES ON THE DIRECTORY, NOT ON THE FILE, and the first version got that
    /// backwards — caught by the #472 reviewer. It read
    /// `guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip(...) }`,
    /// which means a COMPLETE REVERT of #472 — deleting `Sequencer/TimelineAutomationRowMath.swift`
    /// and putting the law back in the view — makes this guard SKIP instead of FAIL. A guard whose
    /// failure mode is "quietly not run" is the #367 class in its most expensive form: the exact
    /// event it exists to catch is the one event it cannot report.
    ///
    /// The directory check only distinguishes "no source tree here" (a packaging question) from
    /// "the source tree lost something" (the thing being guarded). Past it, the read is `try` and
    /// unguarded, so a missing file is a hard failure with the path in the message.
    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources/Echoelmusic")
        guard FileManager.default.isReadableFile(atPath: sources.path) else {
            throw XCTSkip("source tree not present at \(sources.path) — this half reads source text")
        }
        return SourceText.codeOnly(
            try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8))
    }

    // MARK: - The regression (positive anchor first — #367)

    /// ONE declaration, and it is in the core file. The positive half MUST come
    /// first: a scan that only forbade the declaration in the view would be green on
    /// a tree that had lost both copies.
    ///
    /// ⚠️ The uniqueness half anchors on `enum TimelineAutomationRowMath`, and the `enum `
    /// prefix is the load-bearing part: `TimelineAutomationRowMath` CONTAINS
    /// `TimelineAutomationRow` as a substring, so a scan on the bare VIEW name would be red on
    /// a tree where only the (correct, hoisted) core name appears — and it would also hit the
    /// relocated prose in `Core/AutomationPlayer.swift`, `Core/PerTrackParameterKeyPath.swift`,
    /// `DSP/EchoelDDSP.swift` and `Studio/EchoelValueField.swift` (the CORE name appears in
    /// prose too, in `Sequencer/ClipAutomationEdit.swift` and in this type's own header).
    /// Anchoring on a token that occurs ONLY at the intended site is the #408 law, and
    /// establishing that uniqueness belongs to writing the scan, not to review.
    ///
    /// ⛔ `SourceText.codeOnly` is PROPHYLACTIC here, and the first version of this comment
    /// claimed the opposite with a supporting sentence a grep disproves. Measured:
    /// `git grep -n "enum TimelineAutomationRowMath" -- Sources` returns exactly ONE line in
    /// RAW text, so stripping comments changes nothing today. It is kept because the anchor is
    /// one edit away from being cited in prose (this file's own header nearly does it), which
    /// is exactly how #453 was paid for — but it is labelled prophylactic, per that slice's own
    /// rule. The old sentence also named "four other files" for the CORE name; only one of
    /// those four carries it.
    ///
    /// ⛔ RENAMED BY #473 (was `…AndTheViewNoLongerDeclaresIt`). The old name described an
    /// approach the code no longer takes — it asked whether one specific file re-declared
    /// the law, and that file is deleted. A test name that describes a retired method is
    /// the #374 stale-name trap, and a name is the only carrier of that information here.
    func testTheLawHasItsOwnFileAndTheOldViewIsGone() throws {
        let core = try source("Sources/Echoelmusic/Sequencer/TimelineAutomationRowMath.swift")
        XCTAssertTrue(core.contains("enum TimelineAutomationRowMath"), """
            The hoisted law is not declared in its own file. It was moved next to \
            AutomationCanvasMath and AutomationPoint — two of its three collaborators; \
            AutomationTarget is in Core/AutomationPlayer, so this is a majority, not a \
            clean sweep. If it moved again, move this assertion with it rather than \
            deleting it.
            """)
        XCTAssertTrue(core.contains("func sameParameter("), """
            The one member with a production caller is missing from the core file.
            """)

        // ⛔ THIS HALF WAS REWRITTEN BY #473, AND THE REWRITE WAS MANDATORY, NOT TIDYING.
        // It used to read `Sources/Echoelmusic/Studio/TimelineAutomationRow.swift` and
        // assert the view did not re-declare the law. #473 DELETED that file, and `source`
        // reads with `try` past its directory-only skip — so leaving this line would have
        // turned the deletion into a hard red on a correct tree. That is the #456 law:
        // a commit that removes a surface pulls the guards over that surface in the SAME
        // commit. It cost a real red once already, so it is written down where it happened.
        //
        // ⭐ AND THE REPLACEMENT IS STRICTLY STRONGER, which is why this is not a loss of
        // coverage. The old form asked "does ONE named file avoid re-declaring the law" —
        // a second copy in any OTHER file passed it. This asks the question the #416 law
        // actually cares about: how many files in `Sources/` declare it at all. One.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let deletedView = root
            .appendingPathComponent("Sources/Echoelmusic/Studio/TimelineAutomationRow.swift")
        XCTAssertFalse(FileManager.default.fileExists(atPath: deletedView.path), """
            `Studio/TimelineAutomationRow.swift` is back. #473 deleted it: a 415-line FILE \
            (`git show --stat`) holding an unmounted SwiftUI view — the `struct` itself was \
            198 lines, all three types together 344 — whose only live tenant (this law) moved out in #472, and \
            whose five prose citations were relocated first. If a real automation editor is \
            being built, that is welcome — but build it under a name that does not resurrect \
            the doorless one, and update this assertion deliberately rather than deleting it.
            """)

        let declaring = try filesDeclaringTheLaw()
        XCTAssertEqual(declaring, ["Sources/Echoelmusic/Sequencer/TimelineAutomationRowMath.swift"], """
            The law is declared in \(declaring.count) file(s), not exactly one: \(declaring). \
            A second copy is unreachable AND authoritative-looking — how one decision quietly \
            becomes two (#416).
            """)
    }

    /// Every file under `Sources/` whose CODE (not prose — #453) declares the law.
    ///
    /// ⚠️ The anchor is `enum TimelineAutomationRowMath` and that is not fussiness, it is the
    /// #408 law: the bare view name is a SUBSTRING of the core name, so forbidding it would be
    /// red on a tree where only the correct name appears. The `enum ` prefix settles that.
    /// `SourceText.codeOnly` is prophylactic (see the measurement above), not the mechanism.
    ///
    /// ⚠️ The `XCTSkip` below is a fail-open path, and it is closed only by ORDER: `source()`
    /// has already run twice in the caller and throws its own skip if `Sources/Echoelmusic`
    /// is unreadable, and the file-absent assertion runs BEFORE this call. Do not reorder the
    /// caller so the walk comes first. The inner `try?` is NOT fail-open for the case that
    /// matters — if the one declaring file failed to read, `declaring` is `[]` and the
    /// equality assertion fails.
    private func filesDeclaringTheLaw() throws -> [String] {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources/Echoelmusic")
        guard let walk = FileManager.default.enumerator(atPath: sources.path) else {
            throw XCTSkip("cannot enumerate \(sources.path) — this half reads source text")
        }
        var hits: [String] = []
        for case let relative as String in walk where relative.hasSuffix(".swift") {
            let url = sources.appendingPathComponent(relative)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            if SourceText.codeOnly(text).contains("enum TimelineAutomationRowMath") {
                hits.append("Sources/Echoelmusic/" + relative)
            }
        }
        return hits.sorted()
    }

    /// The live chain. Without this the hoist could be "correct" and orphaned, which
    /// is the same defect with more steps.
    func testTheLiveCallSiteStillReachesIt() throws {
        let store = try source("Sources/Echoelmusic/Core/TimelineStore.swift")
        XCTAssertTrue(store.contains("TimelineAutomationRowMath.sameParameter("), """
            TimelineStore no longer resolves an automation lane through the alias-aware \
            law. If that call was deliberately replaced, this whole type loses its last \
            production caller — say so at the declaration and retire it on purpose, \
            rather than leaving a core nobody calls and a guard nobody can fail.
            """)
    }

    // MARK: - Behaviour of the one live member

    /// Two spellings of the SAME lane must compare equal — a legacy enum rawValue and
    /// its registry keyPath. This is what `TimelineStore` depends on: a curve drawn
    /// under one spelling has to be found again under the other.
    func testTheAliasLawHoldsForTheOneLiveMember() {
        XCTAssertTrue(TimelineAutomationRowMath.sameParameter("masterLevel", "master.amp.level"))
        XCTAssertTrue(TimelineAutomationRowMath.sameParameter("master.amp.level", "masterLevel"),
                      "the relation must be symmetric — the two branches must agree")
        XCTAssertTrue(TimelineAutomationRowMath.sameParameter("transport.tempo.bpm", "tempo"))
        XCTAssertFalse(TimelineAutomationRowMath.sameParameter("masterLevel", "tempo"),
                       "two different known lanes must stay different")
    }

    /// The edge a "simplify" would take away. `AutomationTarget.forParameter` returns
    /// nil for a free keyPath, so the alias branch answers "unequal" for BOTH of them
    /// — which is right (two unknown keyPaths that differ textually are two lanes) and
    /// would be wrong for a key compared with itself. The `a == b` fast path is the
    /// only thing that makes an unknown key equal to ITSELF; deleting it as redundant
    /// would silently orphan every free-keyPath lane in an existing document.
    func testAnUnknownKeyEqualsItselfButNotAnotherUnknown() {
        XCTAssertTrue(TimelineAutomationRowMath.sameParameter("free.key.path", "free.key.path"))
        XCTAssertFalse(TimelineAutomationRowMath.sameParameter("free.key.path", "other.key.path"))
        XCTAssertTrue(TimelineAutomationRowMath.sameParameter("", ""),
                      "even the degenerate key must find its own lane")
    }

    // MARK: - Counterweight

    /// The SEVEN members that lose their ONLY caller once the view is deleted are still
    /// declared — five functions plus `touchRadius` and `tapSlopPoints` (counted, not
    /// remembered: the header's inventory lists the same seven). This is a COMPILE pin in a test's clothing — it fails by not building,
    /// not by an assertion — and it exists so that removing them is a decision someone
    /// makes on purpose (#470's rule: changing what a move commit moved is how "no
    /// behaviour change" stops being true). If a later slice retires them, delete this
    /// method in the same commit and say why.
    func testTheCallerlessMembersAreStillDeclared() {
        XCTAssertEqual(TimelineAutomationRowMath.touchRadius, 28.0)
        XCTAssertEqual(TimelineAutomationRowMath.tapSlopPoints,
                       AutomationCanvasMath.tapSlopPoints,
                       "the tap-slop must stay CHAINED to the shared A3 law, not copied")
        XCTAssertEqual(TimelineAutomationRowMath.x(forTick: 480, pxPerTick: 0.5), 240)
        XCTAssertEqual(TimelineAutomationRowMath.tick(forX: 240, pxPerTick: 0.5, maxTick: 7680), 480)
        XCTAssertNil(TimelineAutomationRowMath.nearestPoint(toX: 0, y: 0, points: [],
                                                            pxPerTick: 0.5, height: 64))
        XCTAssertNil(TimelineAutomationRowMath.hitPointID(atX: 0, y: 0, points: [],
                                                          pxPerTick: 0.5, height: 64))
        XCTAssertTrue(TimelineAutomationRowMath.displayPoints([], movingID: nil,
                                                              toTick: 0, value: 0).isEmpty)
    }
}
