// TheStageStatusLineHasNoDoorTests.swift
// Echoel — #1051. Blocking bundle. SOURCE-TEXT SCAN (`Tests/CISmoke/CLAUDE.md` §1): it proves
// where construction sites sit, never that anything renders.
//
// ⭐ WHY THIS FILE EXISTS, AND IT IS NOT "ADMStreamStatusLine IS UNREACHABLE". Unreachable is not
// a defect here — `ImmersiveStageView` is parked on purpose (ship gate 4 makes light/space
// "demonstrable, not required for v1"). The defect is **unreachable AND unwritten-down**, which
// this one was: `ADMStreamStatusLine` occurs zero times in `CLAUDE.md`, zero times in any
// register, and its own doc comment described the parent as though the parent were a screen.
//
// ⭐ IT IS THE SECOND `BreathGuideView`-SHAPED FIND (#947 was the first). `doctor --section C`
// asks "is this view built AT ALL", so a construction site inside dead code still counts as a
// call. This line has exactly ONE — `ImmersiveStageView.swift:245` — and `ImmersiveStageView`
// has zero of its own. Unreachable ONE HOP DOWN, invisible to the section that exists to find
// exactly this.
//
// ⚠️ WHERE THE REGISTER LIVES, AND WHY NOT IN `CLAUDE.md`. `CLAUDE.md` is 938 B under its hard
// 150,000 B ceiling (`TheLawFileStaysUnderItsCeilingTests`). A register line for a leaf inside a
// parked surface is exactly the trade that guard exists to make conscious, and the cheaper half
// wins: the note sits at the DECLARATION SITE, where the next reader of the type is already
// standing, and this guard is what stops it rotting. Claim 4 therefore reads the SOURCE note, not
// the law file — a deliberate difference from `TheBreathGuideHasNoDoorTests`, whose subject was
// registered centrally because it carries a safety law.
//
// ⚠️ WHAT MUST NOT BE READ INTO THIS (#364). It does NOT forbid dooring the Immersive Stage. If a
// founder ask brings the stage back, the honest move is a door on the PARENT — this leaf is
// already mounted — and to move the declaration-site note in the SAME commit. Claim 2 goes red on
// that day BY DESIGN, and its message says so.
//
// ⛔ AND IT MUST NOT BE READ AS "THE DOT MECHANISM IS UNPROVEN" (#367). Claim 3 is the
// counterweight: the twin `NetworkOutputHeader` IS constructed, in `PatchbayView`, a live
// operator surface. Without it this file would read as "the whole network-status feature is
// dead", which is false and is the kind of over-reach a negative claim invites.
//
// ⚠️ HONEST GRADING. No local Swift toolchain (§0). **Six assertions across four claims** —
// stated rather than left to be counted from the file's shape, which is how three gradings in
// this bundle miscounted this week. Each was transcribed against today's tree and every needle
// re-derived by `grep` first, comment-stripped: `ADMStreamStatusLine(` = 1,
// `ImmersiveStageView(` = 0, `NetworkOutputHeader(` = 1, plus the three file-local needles.
// All six are **green on today's tree**: **0 regression catches, 6 COUNTERWEIGHTS (#343)** —
// correct, and the whole point, because this slice added a REGISTER and not code. Booking them
// as catches would be the flattering direction (#433/#464). What they buy is the day someone
// doors the stage, adds a second mount, or deletes the note.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheStageStatusLineHasNoDoorTests: XCTestCase {

    private static let leafFile = "Sources/Echoelmusic/Studio/NetworkActivityDot.swift"
    private static let parentFile = "Sources/Echoelmusic/Studio/ImmersiveStageView.swift"
    private static let liveTwinFile = "Sources/Echoelmusic/Studio/PatchbayView.swift"

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
    /// `SourceText.codeOnly` is the one definition of "code, not prose" (#453) — this repo writes
    /// long ⛔ blocks that NAME the views they discuss, and a raw scan would read the note this
    /// very slice added as a construction site. That is not hypothetical: #1050 retracted a pin
    /// whose 14 was 9 call sites plus 5 comment mentions of the same token.
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

    private func code(_ relative: String) throws -> String {
        let url = try repoRoot().appendingPathComponent(relative)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("ANCHOR MISSING: \(relative) could not be read — a missing anchor is a "
                    + "finding, not a pass (#454).")
            return ""
        }
        return SourceText.codeOnly(text)
    }

    /// claim 1 — exactly ONE construction site, and it is the parent the note names.
    /// `struct ADMStreamStatusLine` is a declaration, not a call, so the `(` is load-bearing.
    func testTheStatusLineIsBuiltInExactlyOnePlaceAndItIsTheNamedParent() throws {
        let all = try sourcesCode()
        let calls = all.components(separatedBy: "ADMStreamStatusLine(").count - 1
        XCTAssertEqual(calls, 1, """
            `ADMStreamStatusLine` no longer has exactly one construction site (found \(calls)). \
            If a SECOND appeared it may now be reachable and the declaration-site note in \
            \(Self.leafFile) must move in this commit; if it dropped to zero it became a plain \
            orphan and the note's "one hop down" reasoning is wrong.
            """)

        XCTAssertTrue(try code(Self.parentFile).contains("ADMStreamStatusLine("), """
            The one construction site is no longer in \(Self.parentFile). The declaration-site \
            note names that file as the parent; re-anchor both together.
            """)
    }

    /// claim 2 — and that parent is itself unreachable, which is the entire argument. Without
    /// this the leaf would just be an ordinary child of a live surface (#343).
    func testTheParentStageIsItselfUnreachable() throws {
        let all = try sourcesCode()
        let parentCalls = all.components(separatedBy: "ImmersiveStageView(").count - 1
        XCTAssertEqual(parentCalls, 0, """
            `ImmersiveStageView` is constructed \(parentCalls)× now. `CLAUDE.md` parks it \
            deliberately (ship gate 4: light/space demonstrable, not required for v1), so a \
            builder appearing is a scope decision, not a typo. If it is intended, the status \
            line may be reachable again — follow the chain to a RENDERING parent (a construction \
            site is not a door, #525) and move the declaration-site note in \(Self.leafFile) \
            with it.
            """)
    }

    /// claim 3 — the counterweight (#367). The twin leaf in the same file IS reachable, so this
    /// file's subject is one parked surface, not a dead feature.
    func testTheTwinHeaderIsReachableSoTheFeatureIsNotDead() throws {
        let all = try sourcesCode()
        let twinCalls = all.components(separatedBy: "NetworkOutputHeader(").count - 1
        XCTAssertEqual(twinCalls, 1, """
            `NetworkOutputHeader` is constructed \(twinCalls)× (expected 1, in \
            \(Self.liveTwinFile)). This claim exists so nobody reads claim 1 as "network status \
            is dead code" — the dot, the three states and the 2 Hz tick all ship on the routing \
            surface. If this dropped to zero the WHOLE file became doorless and the note above \
            `ADMStreamStatusLine` understates the situation.
            """)

        XCTAssertTrue(try code(Self.liveTwinFile).contains("NetworkOutputHeader("), """
            The twin's construction site left \(Self.liveTwinFile). Say where it went, in the \
            declaration-site note, in this commit.
            """)
    }

    /// claim 4 — the register exists AT ALL, and it is at the declaration site rather than in
    /// `CLAUDE.md` (938 B of headroom, see this file's header). This is the thing that turns
    /// "unreachable" from a defect into a recorded decision, and it is what was missing.
    func testTheDeclarationSiteCarriesTheRegister() throws {
        let raw = try String(contentsOf: try repoRoot().appendingPathComponent(Self.leafFile),
                             encoding: .utf8)
        XCTAssertTrue(raw.contains("DOORLESS — AND ONE HOP DEEPER THAN A TOOL LOOKS"), """
            The doorless register above `ADMStreamStatusLine` in \(Self.leafFile) is gone. That \
            note IS the register for this surface — nothing in `CLAUDE.md` names it — so \
            deleting it returns the leaf to the state this slice repaired: built, mounted inside \
            a parked view, and written down nowhere. Deliberately read from RAW text: the \
            register is prose, and stripping comments before looking for it would guarantee a \
            failure (the #1050 mistake, upside down).
            """)
    }
}

// NEEDS-FOUNDER-VERIFY: none. Every claim here is a source-text fact; there is nothing on screen
// to look at, which is precisely what the file records.
