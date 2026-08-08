//
//  TheTempoFieldAsksWhichVariantTests.swift
//  Echoelmusic — CISmoke (blocking bundle)
//
//  #504. `BodyTempoField` carried TWO defaults that no call site writes, and one of them made
//  a whole unreachable branch look alive.
//
//  MEASURED, NOT ASSUMED. `git grep -n "BodyTempoField(" -- .` finds exactly ONE construction
//  in the whole repo (`EchoelStudioView.startControlRow`, since #411) and it passes
//  `compact: true`. Everything else the search returns is prose. So:
//
//  · `var compact: Bool = false` — the `false` had no writer, and every non-compact arm of the
//    three ternaries in that file (`spacing: compact ? 6 : 10`, the "Tempo" word label,
//    `width: compact ? 30 : 34`) is unreachable while reading as live code.
//  · `var onLockChanged: () -> Void = {}` — `TempoLockAlwaysAsksForARecomposeTests` had already
//    written this hole down as one a text scan cannot close: "a second `BodyTempoField(compact:)`
//    built without the argument would pass this guard and post nothing — the same defect, one
//    level of indirection out." A no-op default is invisible to a scan because it appears in no
//    diff. A REQUIRED argument is caught by the compiler, at the call site that forgets it.
//
//  This is the #440/#443 lesson applied to a second control: an argument that no call site
//  writes appears in no diff. Removing the default costs nothing that ships (the one call site
//  already names both) and turns an invisible dead arm into something a future author must ask
//  for out loud.
//
//  ⚠️ WHAT THIS FILE DELIBERATELY DOES NOT ASSERT, and the omission is the #416 rule, not an
//  oversight: it does not pin the existence of the wide arm. Three guards in this same bundle
//  already needle those ternaries verbatim — `OneChromeControlHeightTests`
//  (`.frame(width: compact ? 30 : 34, height: EchoelTheme.controlHeight)`), `TapTargetFloorTests`
//  (`HStack(spacing: compact ? 6 : 10)`) and `TheTempoBoxShowsTheClockTests` (which expects TWO
//  accent-tint reads of `liveBodyBPM`, one per arm). A fourth copy would be noise, and deleting
//  the arm is already a three-guard event — which is precisely why #504 did NOT delete it: that
//  is a multi-file change to a control the founder marked twice in one week (#455, #491), not a
//  cleanup.
//
//  ⚠️ HONEST GRADING (#433), transcribed against the parent tree rather than claimed. TWO of the
//  four assertions are regressions — the two "no default" scans, red on any tree before #504
//  because the defaults are literally there. The other two are COUNTER-WEIGHTS, green on both
//  sides: they hold the premise that makes the removal sound (exactly one construction site, and
//  it names both arguments). If a second construction ever appears, the count assertion goes red
//  and the author has to decide about the wide arm on purpose.
//
//  ⚠️ AND THE LIMIT FIRST: every assertion here is a SOURCE-TEXT SCAN. Nothing renders. That the
//  transport row still lays out, that the tempo box is the same size on device, and that the lock
//  still recomposes are three device checks and all three stay open.
//
//  ⛔ `SourceText.codeOnly` (#453) IS PROPHYLACTIC HERE, and the first draft of this paragraph
//  called it LOAD-BEARING — the exact over-claim #484 and #485 each had to retract once and #486
//  twice, repeated in the file that cites them. Measured before committing, raw text vs stripped,
//  across both trees: **0 of 8 needle verdicts differ**. The reason is a near miss and worth
//  writing down, because it will stop being true: the ⛔ retractions this same commit writes into
//  `BodyTempoField.swift` DO quote the removed defaults, but wrapped across comment lines
//  (`var compact: Bool =` / `false`), so neither full needle ever forms in the prose. One
//  re-flowed sentence turns this into a false RED on correct code.
//
//  The helper stays anyway: #453 made ONE definition of "code, not prose" for the whole blocking
//  bundle, and a private exemption is the defect that slice removed.
//

import Foundation
import XCTest

final class TheTempoFieldAsksWhichVariantTests: XCTestCase {

    private static let field = "Sources/Echoelmusic/Studio/BodyTempoField.swift"
    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"

    // MARK: - 1. the two defaults are gone (the regressions)

    /// `compact` must be asked for, not inherited.
    ///
    /// The positive needle runs FIRST on purpose (#367): a scan that only forbids the old form is
    /// green on a tree that lost the property altogether, which is a worse state than the one it
    /// is guarding against.
    func testTheCompactVariantHasNoDefault() throws {
        let src = try source(Self.field)
        XCTAssertTrue(src.contains("var compact: Bool"), """
            `BodyTempoField` no longer declares `compact` at all.

            If the wide arm was removed and the parameter with it, that is a real decision and \
            this assertion should be deleted together with it — deliberately, in the same commit \
            that updates the three guards which needle the `compact ? … : …` ternaries.
            """)
        XCTAssertFalse(src.contains("var compact: Bool = false"), """
            `compact` got its default back.

            `false` has NO writer: the one construction site in the repo passes `compact: true`. \
            Restoring the default makes every non-compact arm of the three ternaries in this file \
            reachable-looking again while still being dead — the exact state #504 removed. If a \
            second call site genuinely wants the wide variant, let it SAY so.
            """)
    }

    /// `onLockChanged` must be asked for too — a no-op default silently drops the recompose.
    func testTheLockHookHasNoDefault() throws {
        let src = try source(Self.field)
        XCTAssertTrue(src.contains("var onLockChanged: () -> Void"), """
            `BodyTempoField` no longer declares `onLockChanged`.

            The lock has to hand its change on, or a tempo lock stops asking for a recompose — \
            the defect `TempoLockAlwaysAsksForARecomposeTests` exists for.
            """)
        XCTAssertFalse(src.contains("var onLockChanged: () -> Void = {}"), """
            `onLockChanged` got its no-op default back.

            `TempoLockAlwaysAsksForARecomposeTests` documents why that is unfixable by scanning: \
            a second `BodyTempoField(compact:)` built without the argument passes every text \
            check and posts nothing. The compiler can catch it; a scan cannot.
            """)
    }

    // MARK: - 2. the premise that makes the removal sound (counter-weights)

    /// Exactly ONE construction site, repo-wide — that is why removing the defaults is free.
    ///
    /// Comments are blanked first, so the prose mentions of `BodyTempoField(` in
    /// `WorkspaceView`'s and `EchoelStudioView`'s accounts of #411, and in the other guards in
    /// this bundle, cannot inflate the count.
    func testThereIsStillExactlyOneConstructionSite() throws {
        let sites = try constructionSites()
        XCTAssertEqual(sites, 1, """
            Expected exactly 1 `BodyTempoField(` construction in Sources/, found \(sites).

            The whole argument for removing the two defaults is that one call site names both. \
            A SECOND site is the moment somebody has to decide, out loud, whether the wide arm \
            is wanted — this assertion is that moment, not a prohibition on having one.
            """)
    }

    /// …and that one site names both arguments.
    func testTheOneCallSiteNamesBothArguments() throws {
        let src = try source(Self.studio)
        XCTAssertTrue(src.contains("BodyTempoField(onLockChanged:"), """
            The one mount stopped naming `onLockChanged`.

            Without it the tempo lock changes nothing downstream: no recompose is requested.
            """)
        XCTAssertTrue(src.contains("compact: true"), """
            The one mount stopped asking for the compact variant.

            The instrument's transport row is sized for `76×32` plus a `30×32` lock (see \
            `OneChromeControlHeightTests`). The wide arm's padded `Text`s do not fit there.
            """)
    }

    // MARK: - source access

    /// Number of `BodyTempoField(` constructions in code (not prose) across `Sources/`.
    private func constructionSites() throws -> Int {
        let root = try treeRoot()
        let sources = root.appendingPathComponent("Sources")
        guard let walk = FileManager.default.enumerator(at: sources,
                                                        includingPropertiesForKeys: nil) else {
            throw AnchorMissing(reason: "cannot enumerate \(sources.path)")
        }
        var total = 0
        for url in walk.compactMap({ $0 as? URL }) where url.pathExtension == "swift" {
            guard let raw = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let code = SourceText.codeOnly(raw)
            total += code.components(separatedBy: "BodyTempoField(").count - 1
        }
        return total
    }

    /// Comment-stripped source, or a skip when the tree is not present.
    ///
    /// The skip is scoped to the TREE, not the file (#454): skipping whenever a scanned FILE is
    /// missing would turn every claim here green the moment somebody renames one, and a skip
    /// PASSES CI.
    private func source(_ relativePath: String) throws -> String {
        let path = try treeRoot().appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw AnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — it was renamed or moved. \
                Re-anchor this scan; do not let it skip.
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }

    private func treeRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else {
            throw XCTSkip("source tree not present under \(root.path)")
        }
        return root
    }

    private struct AnchorMissing: Error, CustomStringConvertible {
        let reason: String
        var description: String { reason }
    }
}
