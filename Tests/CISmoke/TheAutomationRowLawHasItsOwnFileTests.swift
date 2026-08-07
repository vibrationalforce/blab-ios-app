// TheAutomationRowLawHasItsOwnFileTests.swift
// Echoel — #472. The timeline-automation LAW shared a file with an unmounted view.
//
// ⭐ WHAT WAS ACTUALLY WRONG, said narrowly: nothing computed a wrong number.
// `TimelineAutomationRowMath` is pure, correct, and read in production by
// `Core/TimelineStore.swift` — it just lived inside
// `Studio/TimelineAutomationRow.swift`, whose other 344 lines are a SwiftUI view
// nothing mounts. CLAUDE.md's register names the hazard by hand: a plausible "delete
// the doorless file" cleanup would have broken the store. Doorless is a property of a
// VIEW, deletable a property of a FILE, and this repo keeps filing the two together.
// #472 separates them; the arithmetic is byte-identical.
//
// ⛔ HONEST GRADING, because the flattering version is available. Of the five
// assertions here, ONE is a regression in the ordinary sense —
// `testTheLawHasItsOwnFileAndTheViewNoLongerDeclaresIt`, whose first half reads a
// file that did not exist before this commit. The rest are pins: the live call site,
// the alias behaviour, and a compile-pin on the members that lose their only caller.
// None of them could have been red yesterday, and saying otherwise would be the #433
// defect inside the file that cites it.
//
// ⚠️ THE BEHAVIOURAL HALF DUPLICATES `Tests/EchoelmusicTests/TimelineAutomationRowTests`
// ON PURPOSE, which is normally the #416 defect. The reason it is not: that suite is
// the NON-blocking one (#208 — `full-tests.yml` cannot fail a merge), and
// `sameParameter` is the single member of this type with a production caller. A law
// that decides which automation lane a parameter resolves to should be able to fail a
// merge. Everything else stays where it is; this file does not copy the geometry
// cases.
//
// ⚠️ WHAT THIS FILE CANNOT DO. Two of the five assertions are SOURCE SCANS, so they
// prove where text sits, not that the app behaves. And none of it says the automation
// row is reachable — it is not, and #472 does not change that. The view half is still
// on disk for a reason recorded in its own header: five source files cite it in prose
// and two of those citations are load-bearing for `EchoelValueField`, which ships.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheAutomationRowLawHasItsOwnFileTests: XCTestCase {

    private func source(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent(relative)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("source tree not present at \(url.path) — this half reads source text")
        }
        return SourceText.codeOnly(try String(contentsOf: url, encoding: .utf8))
    }

    // MARK: - The regression (positive anchor first — #367)

    /// ONE declaration, and it is in the core file. The positive half MUST come
    /// first: a scan that only forbade the declaration in the view would be green on
    /// a tree that had lost both copies.
    ///
    /// ⚠️ The absence half anchors on `enum TimelineAutomationRowMath`, and that is not
    /// fussiness. `TimelineAutomationRowMath` CONTAINS `TimelineAutomationRow` as a
    /// substring, so a scan forbidding the bare view name would be red on a tree where
    /// only the (correct, hoisted) core name appears; and forbidding the bare core name
    /// would be red on the view's own header, which quotes it in prose to say where it
    /// went. `SourceText.codeOnly` handles the second, the `enum ` prefix handles the
    /// first. Anchoring on a token that occurs ONLY at the intended site is the #408
    /// law, and establishing that uniqueness belongs to writing the scan, not to review.
    func testTheLawHasItsOwnFileAndTheViewNoLongerDeclaresIt() throws {
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

        let view = try source("Sources/Echoelmusic/Studio/TimelineAutomationRow.swift")
        XCTAssertFalse(view.contains("enum TimelineAutomationRowMath"), """
            The unmounted automation row declares the law again. That file is doorless \
            (#121 Slice 4/4d removed its editor; nothing constructs the row), so a \
            second copy there would be unreachable AND authoritative-looking — how one \
            decision quietly becomes two (#416).
            """)
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
