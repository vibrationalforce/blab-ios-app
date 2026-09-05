import XCTest
@testable import Echoelmusic

/// #1003 — the Detail caption names the inert control, not the live one.
///
/// WHY IT EXISTS. In the full-screen cover with donut mode on, the VJ overlay showed
/// "Detail shapes the Rings look only" — while `SpectralDonutView(bandCount: max(8,
/// Int(visualDetail)))` was drawing the picture in front of the player. So the ONE field on
/// that overlay actually reaching the renderer was captioned as the one that does nothing,
/// and nine genuinely inert fields carried no caption at all. Exactly backwards.
///
/// THE PREDICATE WAS NEVER WRONG. `LookBlendMap.detailReach` answers "how much of the METAL
/// field can Detail shape", and that is correct arithmetic that knows nothing about donut
/// mode — it should not. The defect was in the CAPTION that consumed it, so the fix is at the
/// caption and the predicate is untouched.
///
/// ⭐ THE LESSON IS ABOUT THE SHAPE OF A NOTE, NOT ABOUT DONUTS. `LookBlendMap`'s doc block
/// predicted this expiry verbatim — "wrong the day it is re-doored" — and #747 re-doored the
/// cover months later with nothing moving. **A comment that predicts its own expiry names no
/// owner, so nothing goes red when the day arrives.** That is what this file is: the owner.
///
/// ⚠️ HONEST GRADING. Four claims. 1 and 2 are LOAD-BEARING (red on `HEAD`, where the caption
/// is a single unconditional string and the retraction does not exist). 3 and 4 are
/// COUNTERWEIGHTS green on both trees: 3 pins the consumer the caption now depends on, and 4
/// pins that the eight sibling rows stay VISIBLE — an external display renders `MetalBioView`
/// from the same keys, so hiding them would blank a projector's controls to tidy a caption.
final class TheDetailCaptionKnowsWhichPictureTests: XCTestCase {

    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"
    private static let map = "Sources/Echoelmusic/Studio/LookBlendMap.swift"

    private func source(_ relative: String) throws -> String {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            if FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("Package.swift").path) { break }
            dir = dir.deletingLastPathComponent()
        }
        let url = dir.appendingPathComponent(relative)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("ANCHOR MISSING: \(relative) could not be read — a missing anchor is a "
                    + "finding, not a pass.")
            return ""
        }
        return text
    }

    // 1 — LOAD-BEARING: the caption asks which picture is on screen.
    func testTheCaptionBranchesOnDonutMode() throws {
        let text = try source(Self.studio)
        XCTAssertTrue(text.contains("Text(spectralDonuts"), """
            The Detail caption no longer reads `spectralDonuts`, so it states one truth for \
            two different renderers. In donut mode Detail sets the band count and the old \
            sentence called it inert — telling a player that the one control working in front \
            of them does nothing. That is worse than no caption, because it is trusted.
            """)
        XCTAssertTrue(text.contains("Detail sets how many bands the donuts draw"), """
            The donut branch of the caption is gone. If the wording simply changed, re-anchor \
            this needle; if the branch was removed, claim 1's first half already explains why.
            """)
    }

    // 2 — LOAD-BEARING: the stale premise is retracted where it was written.
    func testTheDoorlessPremiseIsRetractedAtItsSource() throws {
        let map = try source(Self.map)
        XCTAssertTrue(map.contains("#747 re-doored it") || map.contains("**#747 re-doored it**"), """
            `LookBlendMap`'s doc still rests on "that renderer is doorless today" without \
            saying that #747 re-doored the cover. Leaving the premise standing invites the \
            next reader to undo the caption fix on the strength of a sentence that expired.
            """)
    }

    // 3 — COUNTERWEIGHT: the consumer the caption now promises actually exists.
    func testDetailStillReachesTheDonutRenderer() throws {
        let text = try source(Self.studio)
        XCTAssertTrue(text.contains("bandCount: max(8, Int(visualDetail))"), """
            `SpectralDonutView` no longer takes its band count from `visualDetail`. The donut \
            branch of the caption then promises something that stopped being true, which is \
            the original defect with its sign flipped. Move the caption in the same commit.
            """)
    }

    // 4 — COUNTERWEIGHT: the sibling rows stay on screen.
    func testTheOtherAdjustRowsAreNotHidden() throws {
        let text = try source(Self.studio)
        for label in ["label: \"Motion\"", "label: \"Spread\"", "label: \"Hue\"",
                      "label: \"Saturation\"", "label: \"Texture\"", "label: \"Glitter\""] {
            XCTAssertTrue(text.contains(label), """
                The visual adjust row \(label) is gone. Hiding these to "tidy" the caption is \
                the tempting wrong fix: `ExternalDisplayScene` renders `MetalBioView` from the \
                same keys, so with a projector attached they are live even when the on-device \
                picture is showing donuts. A control that is inert HERE is not inert THERE.
                """)
        }
    }
}
