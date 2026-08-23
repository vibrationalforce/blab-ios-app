//  TheProScreenSellsNoWorkThatIsNotHappeningTests.swift
//  Echoel — the paywall copy is a claim surface, and no guard read it. #765.
//
//  WHAT WAS WRONG. `ProUnlockView.featureList` listed four "Pro extensions". Three of them
//  carried the detail "In development", and measured against this tree not one had code:
//    · "AUv3 plugin in your DAW" — the AUv3 target was DELETED on 2026-07-24 (#121 Slice 2).
//      `Sources/EchoelmusicAUv3` does not exist and `ContentPipelineClaimsTests` already pins
//      that absence. The work was REMOVED, not started — the opposite of "in development".
//    · "Video FX catalog" — `videoFXCatalog` occurs in exactly two files: the `ProFeature`
//      case and the label itself.
//    · "Export format presets — 4K & aspect ratios" — no 4K and no aspect-ratio export code
//      exists anywhere under `Sources/`.
//  The method's own doc line said "HONEST status — never claim unshipped work as available",
//  and the rows broke it anyway, because "in development" reads as a softener rather than as
//  what it is: a claim about the PRESENT.
//
//  ⭐ WHY IT IS WORTH A GUARD WHILE NOTHING PRESENTS THIS VIEW — this is the whole point, not a
//  caveat. `ProUnlockView` is doorless today, so no user reads it; CLAUDE.md nevertheless orders
//  it KEPT, to be repurposed for the v1.1 "Echoel Live" plan. The day it is re-doored it becomes
//  a PAYWALL — the one surface where a false capability claim is an App Store 2.3 rejection, the
//  failure #184 already paid for by removing twelve of them from the store text. And every AUv3
//  guard in this repo reads `docs/**` (`testEveryAUv3MentionIsADenial`),
//  `ContentPipeline/CLAIMS.md`, `fastlane/metadata` or the deleted target's PATH. **None reads
//  app copy.** A claim's four surfaces are only four if somebody checks the fourth.
//
//  ⚠️ IT DOES NOT FORBID RE-DOORING THE SCREEN, OR BUILDING ANY OF THE THREE (#364). Claim 5 is
//  a tripwire, not a ban: when `ProUnlockView` gains a construction site it goes red and names
//  the copy audit as the same-commit work. Claims 3 and 4 go red the day the capability is
//  really built — which is exactly when the word "planned" must change. In every case the fix is
//  to update the copy together with the code, never to delete the assertion.
//
//  ⚠️ AND IT DOES NOT TOUCH WHAT ECHOEL PRO CONTAINS. The row SET is a pricing decision
//  (founder 2026-07-10, superseded again by the v1.1 plan). #765 changed a false present tense
//  to a true one and added no row, removed none.
//
//  ⚠️ HONEST GRADING (#433/#464). SOURCE-TEXT SCAN throughout — it proves where text sits, never
//  that a screen renders. This file compiles against the parent (it names no new symbol), so
//  every assertion has a verdict there. Transcribed by hand in Python against `git show HEAD:`
//  and the worktree:
//    · Claim 2 is the REGRESSION: red on the parent, green here. FOUR occurrences sat in
//      code there — the three rows AND the header sentence, which is the sharper one:
//      "One purchase unlocks every Pro extension — including the ones still in
//      development, when they ship." A purchase PROMISE attached to work that does not
//      exist. I found it only because the transcription printed a surviving hit after I
//      thought the rows were the whole defect; a row-by-row read would have missed it.
//    · Claims 1, 3, 4, 5 are COUNTERWEIGHTS — green on both. They are the premises that make
//      claim 2 mean something: without them "planned" would be the false word instead.
//
//  ⚠️ `SourceText.codeOnly` IS LOAD-BEARING FOR CLAIM 2, and measured rather than assumed:
//  TRAGEND (1 of 1 verdicts flip). On the WORKTREE the raw file contains "in development" five
//  times — all of them inside the ⛔ block that WITHDRAWS the claim — so a raw scan would be red
//  on the corrected tree, which is the #491 trap in its smallest form. Stripped, the worktree has
//  zero. On the parent the needle sits in code, so both readings are red there.
import Foundation
import XCTest
@testable import Echoelmusic

final class TheProScreenSellsNoWorkThatIsNotHappeningTests: XCTestCase {

    private static let sourcesRoot = "Sources/Echoelmusic"
    private static let screen = "Sources/Echoelmusic/Studio/ProUnlockView.swift"

    /// ANCHOR (#454): a missing file or a renamed member must FAIL, not skip into a green.
    func testTheProScreenAndItsFeatureListArePresent() throws {
        let text = try rawText(Self.screen)
        XCTAssertTrue(text.contains("private var featureList"), """
            `featureList` is gone from \(Self.screen), so every claim below scanned the wrong \
            member or nothing at all. If the Pro copy moved, point this file at its new home in \
            the SAME commit — a paywall whose copy nobody checks is how #184 happened.
            """)
    }

    /// The screen must not describe unbuilt capabilities as work that is under way.
    func testNoRowClaimsWorkIsUnderWay() throws {
        let code = SourceText.codeOnly(try rawText(Self.screen)).lowercased()
        XCTAssertFalse(code.contains("in development"), """
            A "Pro extensions" row says "in development" again. That is a claim about the \
            PRESENT, and for all three rows it was false: the AUv3 target was DELETED (#121 \
            Slice 2), `videoFXCatalog` exists only as an enum case and a label, and no 4K or \
            aspect-ratio export code exists at all. Work that was removed, or never begun, is \
            "planned" — not "in development". If one of them really starts, say so here AND \
            leave the code that proves it, so claims 3 and 4 below turn red with you.
            """)
    }

    /// Premise for the AUv3 row: the target is gone, so nothing about it can be in progress.
    func testTheAUv3TargetIsStillAbsent() throws {
        let path = try repoRoot().appendingPathComponent("Sources/EchoelmusicAUv3")
        XCTAssertFalse(FileManager.default.fileExists(atPath: path.path), """
            `Sources/EchoelmusicAUv3` exists again. That is welcome work (#191) — and it means \
            the Pro row's "planned, not built yet" has become the false word. Change it in the \
            same commit, and read `ContentPipeline/CLAIMS.md` §1, which forbids the AUv3 claim \
            outright and has to move with it.
            """)
    }

    /// Premise for the Video-FX row: the feature is a name, not an implementation.
    ///
    /// ⚠️ The set is asserted by NAME rather than by count, so adding a second file tells you
    /// WHICH one — a bare number would only say "2" and leave the reader grepping.
    ///
    /// ⛔ I FIRST WROTE THE EXPECTED SET AS TWO FILES, ADDING `Studio/ProUnlockView.swift`, AND
    /// IT WAS RED ON A CORRECT TREE. The screen holds the DISPLAY STRING "Video FX catalog", not
    /// the identifier `videoFXCatalog`; I had run `git grep -in "video fx\|videoFXCatalog"` and
    /// read the union of two patterns as the result of one. Caught by transcribing every claim
    /// in Python against both trees BEFORE pushing — which is the only reason it is a footnote
    /// here instead of #656 again (a guard red on a correct tree for five commits, invisible
    /// inside #396's fog).
    func testTheVideoFXCatalogIsStillOnlyAName() throws {
        let hits = try filesUnderSources(containing: "videoFXCatalog")
        XCTAssertEqual(hits, ["Core/ProGate.swift"], """
            `videoFXCatalog` now appears in \(hits.joined(separator: ", ")) — it used to be the \
            `ProFeature` case and nothing else. If a catalog is being built, the Pro row must \
            stop saying "planned, not built yet" in the same commit. If the enum case merely \
            moved, re-anchor this list rather than deleting it.
            """)
    }

    /// The tripwire: the day this screen gets a door, its copy needs an audit, not a shrug.
    func testTheProScreenStillHasNoDoor() throws {
        let mounts = try filesUnderSources(containing: "ProUnlockView(")
        XCTAssertTrue(mounts.isEmpty, """
            `ProUnlockView` is now constructed in \(mounts.joined(separator: ", ")).

            THIS IS NOT A BAN — re-dooring it is the v1.1 "Echoel Live" plan. It is the moment \
            the copy stops being harmless: an unreachable screen that overstates costs nothing, \
            a PAYWALL that does it is an App Store 2.3 rejection (#184 removed twelve such \
            claims from the store text). In the same commit, walk `featureList` row by row \
            against what actually exists, and pull `fastlane/metadata`, `docs/**` and \
            `ContentPipeline/CLAIMS.md` along with whatever you change — then delete this \
            assertion deliberately rather than to get the gate green.
            """)
    }

    // MARK: - file access

    private func filesUnderSources(containing needle: String) throws -> [String] {
        let base = try repoRoot().appendingPathComponent(Self.sourcesRoot)
        guard let walker = FileManager.default.enumerator(atPath: base.path) else {
            throw XCTSkip("cannot enumerate \(Self.sourcesRoot) — refusing to report a green it did not earn")
        }
        var hits: [String] = []
        for case let relative as String in walker where relative.hasSuffix(".swift") {
            let url = base.appendingPathComponent(relative)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            if SourceText.codeOnly(text).contains(needle) { hits.append(relative) }
        }
        return hits.sorted()
    }

    private func rawText(_ relativePath: String) throws -> String {
        let path = try repoRoot().appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw XCTSkip("""
                \(relativePath) is not present — this guard inspects source text, so it SKIPS \
                rather than reporting a green it did not earn (#454)
                """)
        }
        return try String(contentsOf: path, encoding: .utf8)
    }

    private func repoRoot() throws -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
