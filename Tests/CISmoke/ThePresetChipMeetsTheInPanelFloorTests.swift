// ThePresetChipMeetsTheInPanelFloorTests.swift
// Echoel — the visual-preset chip is its own tap target, so it must meet the floor.
// BLOCKING bundle.
//
// #1144, closing the last CODE finding of the visual deep audit
// (AUDIT_VISUAL_2026-09-06, "Preset chips sit 2 pt under the in-panel floor their two
// neighbouring strips cite as law"). The chip read `frame(minHeight: 32)` while
// `touchPatchChip` and the look chips beside it read 34 and both cite 34 as the house
// in-panel floor (#617).
//
// ⚠️ THE PRECISE CLAIM, because the obvious one is FALSE and this file exists partly to
// stop it being repeated. Two rows in `EchoelStudioView.swift` are SMALLER still — 26 and
// 28 — and both are CORRECT: each is a visual pill sitting inside a 44 pt `contentShape`
// target (the 28 literally, the 26 through `chipTapTarget`), so there the `minHeight` is a
// LOOK. The preset chip had no such wrapper, so its `minHeight` WAS the tap target. The
// defect was that difference, not the number 32.
//
// ⛔ AND THE STRUCTURAL GUARD THIS FILE WAS NEARLY REPLACED BY DOES NOT EXIST, on purpose.
// The tempting rule is "every sub-34 `minHeight` must sit inside a 44 pt target". Measured
// before writing it: the 26 pt pill's `chipTapTarget {` call site is FORTY-FIVE lines above
// its `minHeight`, with a long comment block between. A text-proximity check would need a
// window wide enough to match almost anything, i.e. it would pass by accident later. A
// guard that cannot fail honestly is worse than none, so this file pins only what is
// exactly checkable and says so.
//
// ⚠️ THIS FORBIDS NO IMPROVEMENT (#364). Raising the chip to a full 44 pt target keeps
// claim 1 true (it asserts a FLOOR, not equality) and would only need claim 2's neighbour
// pin re-read. The padding is deliberately NOT pinned: 11 and 12 both occur beside a 34 pt
// height in that file, so padding is a look and not the floor — the audit's "change it to
// 11 to match exactly" half does not hold.

import XCTest

final class ThePresetChipMeetsTheInPanelFloorTests: XCTestCase {

    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"

    private func code(_ rel: String) throws -> String {
        let r = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: r.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(r.path)") }
        let path = r.appendingPathComponent(rel)
        guard FileManager.default.fileExists(atPath: path.path) else {
            struct AnchorMissing: Error { let path: String }
            throw AnchorMissing(path: rel)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }

    private func count(_ needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    // MARK: - 1 · No self-tap-target chip sits below the floor

    func testNoChipHeightSitsBelowThirtyFourExceptTheTwoWrappedPills() throws {
        let studio = try code(Self.studio)

        // The exact literal the audit found. It must be gone: that row is its own tap
        // target, so its height IS the target and 32 was 2 pt under the house floor.
        XCTAssertEqual(count("frame(minHeight: 32)", in: studio), 0, """
            A `frame(minHeight: 32)` is back in EchoelStudioView. If it is a chip that is its \
            OWN tap target, it is 2 pt under the 34 pt in-panel floor that `touchPatchChip` \
            (#617) and the look chips cite as law. If it is a pill inside a 44 pt \
            `contentShape` target, the height is only a look — but then say so at the line, \
            the way the 26 and 28 pt rows do, or the next reader cannot tell the two apart.
            """)

        // The two legitimate sub-34 rows, pinned by value so that this file goes red if a
        // THIRD small height appears — at which point a human decides which kind it is.
        XCTAssertEqual(count("frame(minHeight: 26)", in: studio), 1, """
            The 26 pt menu-chip pill changed. It is legitimate ONLY because `menuChip` wraps \
            it in `chipTapTarget`, which applies `.frame(minWidth: 44, minHeight: 44)` plus \
            `.contentShape(Rectangle())`. If that wrapper went, the height became a tap \
            target and must meet the floor.
            """)
        XCTAssertEqual(count("frame(minHeight: 28)", in: studio), 1, """
            The 28 pt sound-prompt pill changed. Same reasoning as the 26: it is legitimate \
            only while the `.frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())` \
            two lines below it survives.
            """)
    }

    // MARK: - 2 · The preset chip matches the neighbour that carries the law

    func testThePresetChipAndItsNeighbourAgree() throws {
        let studio = try code(Self.studio)

        // `touchPatchChip` is the ONE home of the 34 pt rationale (#416). This guard cites
        // it rather than restating it, so the law does not grow a second copy here.
        XCTAssertEqual(count("""
            .padding(.horizontal, 11).frame(minHeight: 34)
            """, in: studio), 2, """
            The two 11 pt chip strips (`touchPatchChip` and the look chips) no longer read \
            34. They are where the in-panel floor is DEFINED (#617); the preset chip was \
            raised to match them. If they move, move the preset chip in the same commit and \
            re-read this file's header.
            """)

        XCTAssertGreaterThanOrEqual(count("frame(minHeight: 34)", in: studio), 3, """
            Fewer than three rows meet the 34 pt in-panel floor. The preset chip was raised \
            to 34 by #1144 precisely to join its two neighbours; if the floor itself is being \
            replaced (e.g. everything moves to 44), that is an improvement this guard does \
            not forbid — but the header above and the comment at the preset chip both \
            describe 34 and must be rewritten in the same commit.
            """)
    }
}
