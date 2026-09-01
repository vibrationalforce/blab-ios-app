// TheBreathGuideHasNoDoorTests.swift
// Echoel — #947. Blocking bundle. SOURCE-TEXT SCAN (`Tests/CISmoke/CLAUDE.md` §1): it proves
// where construction sites sit, never that anything renders.
//
// ⭐ WHY THIS FILE EXISTS, AND IT IS NOT "BreathGuideView IS UNREACHABLE". Unreachable is not a
// defect here — `ImmersiveStageView` and `BroadcastView` are parked on purpose. The defect is
// **unreachable AND unwritten-down**, and this one was unwritten-down for months: it occurs
// **zero** times in `CLAUDE.md`. It is now registered there, and this guard is what stops that
// entry from rotting silently.
//
// ⭐ AND IT IS THE FIRST DOORLESS SURFACE A TOOL FOUND RATHER THAN A SESSION. `doctor
// --section C` asks "is this view built AT ALL", so a construction site inside dead code still
// counts as a call. `BreathGuideView` has exactly ONE — `BioSourceView.swift`'s
// `.fullScreenCover` — and `BioSourceView` is itself in C1's list. Unreachable ONE HOP DOWN.
// The tool's own advice paragraph had warned about that hop in prose ("the caller may itself be
// dead") while the code could not check it; #947 taught it the fixpoint, and the run then
// reported this file plus `PulseMeasurementView` — the latter being the KNOWN POSITIVE that
// `CLAUDE.md` had registered by hand at #525 while the section reported clean. A checker
// validated against a known positive is a measurement; one that has never found its own is not.
//
// ⚠️ WHAT MUST NOT BE READ INTO THIS (#364). It does NOT forbid re-dooring. If a founder ask
// brings the breathing guide back, the honest move is to door its PARENT — the entry itself is
// already mounted — and to move `CLAUDE.md`'s register line in the SAME commit. This guard goes
// red on that day BY DESIGN, and its messages name the prose to carry along.
//
// ⛔ DO NOT DELETE THE FILE IT GUARDS. It carries tested safety work: the resonance-first
// breathing pattern, the ≤0.2 Hz motion ceiling (far under the 3 Hz WCAG limit, and disabled
// entirely under Reduce Motion), and the contraindication acknowledgement that gates the hold
// patterns. Deleting a doorless view whose file holds a safety law is the trap `CLAUDE.md`
// records twice already.
//
// ⚠️ HONEST GRADING. No local Swift toolchain (§0). **6 assertions** — five written out and one
// inside claim 3's two-needle loop; a loop hides its count, so it is stated rather than left to
// be miscounted from the file's shape (the failure mode three gradings in this bundle hit this
// week). Each was transcribed against today's tree and against the tree #947 was cut from, and
// every needle re-derived by `grep` first: `BreathGuideView(` = 1, `BioSourceView(` = 0,
// `reduceMotion` and `BreathPattern` present, `CLAUDE.md` names the view once. They are
// **green on both trees**, i.e. **0 regression catches, 6 COUNTERWEIGHTS (#343)**. That is correct and is the whole point: the
// slice changed a TOOL and a REGISTER, not the code these claims read. Booking them as catches
// would be the flattering direction (#433/#464). What they buy is the future: the day someone
// doors the parent, or adds a second construction site, or deletes the file, exactly one of them
// speaks and names what else must move.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheBreathGuideHasNoDoorTests: XCTestCase {

    private static let guideFile = "Sources/Echoelmusic/Studio/BreathGuideView.swift"
    private static let parentFile = "Sources/Echoelmusic/Studio/BioSourceView.swift"

    private func repoRoot() throws -> URL {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources").path) else {
            throw XCTSkip("source tree not present under \(root.path)")
        }
        return root
    }

    /// Comment-stripped text of every `.swift` file under `Sources/`, one string.
    /// `SourceText.codeOnly` is the one definition of "code, not prose" (#453) — this repo
    /// writes long ⛔ blocks that NAME the views they discuss, and a raw scan would read this
    /// very register's prose as a construction site (#762 fixed exactly that in the doctor).
    private func sourcesCode() throws -> String {
        let root = try repoRoot()
        let dir = root.appendingPathComponent("Sources")
        guard let walker = FileManager.default.enumerator(atPath: dir.path) else {
            XCTFail("Sources/ is present but not enumerable — re-anchor rather than skip (#454).")
            return ""
        }
        var out = ""
        for case let rel as String in walker where rel.hasSuffix(".swift") {
            let text = try String(contentsOf: dir.appendingPathComponent(rel), encoding: .utf8)
            out += SourceText.codeOnly(text) + "\n"
        }
        guard !out.isEmpty else {
            XCTFail("walked Sources/ and read nothing — the scan found nothing, not nothing wrong.")
            return ""
        }
        return out
    }

    /// claim 1 — exactly ONE construction site, and it is the parent this register names.
    func testTheGuideIsBuiltInExactlyOnePlaceAndItIsTheNamedParent() throws {
        let root = try repoRoot()
        let all = try sourcesCode()
        // `struct BreathGuideView` and `extension BreathGuideView` are declarations, not calls.
        let calls = all.components(separatedBy: "BreathGuideView(").count - 1
        XCTAssertEqual(calls, 1, """
            `BreathGuideView` no longer has exactly one construction site (found \(calls)). If a \
            SECOND appeared, it may now be reachable and `CLAUDE.md`'s register line must move in \
            this commit; if it dropped to zero, it became a plain C1 orphan and the register \
            line's "one hop down" reasoning is wrong.
            """)

        let parent = SourceText.codeOnly(
            try String(contentsOf: root.appendingPathComponent(Self.parentFile), encoding: .utf8))
        XCTAssertTrue(parent.contains("BreathGuideView()"), """
            The one construction site is no longer in \(Self.parentFile). The register line names \
            that file as the parent; re-anchor both together.
            """)
    }

    /// claim 2 — and that parent is itself unreachable, which is the entire argument. Without
    /// this the file would just be an ordinary child of a live surface (#343).
    func testTheParentIsItselfUnreachable() throws {
        let all = try sourcesCode()
        let parentCalls = all.components(separatedBy: "BioSourceView(").count - 1
        XCTAssertEqual(parentCalls, 0, """
            `BioSourceView` is constructed \(parentCalls)× now. It was the LAST survivor of the \
            removed six-surface bottom bar and had no builder at all; if it gained one, the \
            breathing guide may be reachable again — check the chain to a rendering parent (a \
            construction site is not a door) and move `CLAUDE.md`'s register line with it.
            """)
    }

    /// claim 3 — the safety work this file holds, pinned as NAMES so a designer may retune the
    /// numbers (#364). Its presence is why "doorless" must never be read as "deletable".
    func testTheFileStillHoldsTheSafetyWorkThatMakesItUndeletable() throws {
        let root = try repoRoot()
        let code = try String(contentsOf: root.appendingPathComponent(Self.guideFile),
                              encoding: .utf8)
        for needle in ["reduceMotion", "BreathPattern"] {
            XCTAssertTrue(code.contains(needle), """
                `\(Self.guideFile)` no longer mentions `\(needle)`. This file is kept DESPITE \
                being unreachable because it carries the reduce-motion opt-out and the pattern \
                model behind the flash-rate ceiling. If that work genuinely moved elsewhere, say \
                where — in `CLAUDE.md`'s register line, in this commit.
                """)
        }
    }

    /// claim 4 — the register line exists at all. It is the thing that turns "unreachable" from
    /// a defect into a recorded decision, and it is what silently went missing for months.
    func testTheRegisterNamesIt() throws {
        let root = try repoRoot()
        let law = try String(contentsOf: root.appendingPathComponent("CLAUDE.md"),
                             encoding: .utf8)
        XCTAssertTrue(law.contains("BreathGuideView"), """
            `CLAUDE.md` no longer names `BreathGuideView`. Unreachable is not a defect; \
            unreachable and UNWRITTEN-DOWN is, and that is exactly the state #947 found it in. \
            If it was re-doored, the register line should say so rather than disappear.
            """)
    }
}
