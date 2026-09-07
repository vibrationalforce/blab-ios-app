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
///
/// ⛔ #1057 (`04f6b3d0`) CHANGED THE SHAPE OF THE ANSWER AND THIS FILE DID NOT MOVE WITH IT
/// (#1095). The caption no longer BRANCHES — the ternary's donut arm is deleted, because a
/// new `if donutIsThePicture { … } else { … }` above it now owns the whole donut state with
/// its own sentence, and the Rings-only sentence runs only under `if !donutIsThePicture,`.
/// Same property ("the caption asks which picture is on screen"), different address. Claim 1
/// anchored on `Text(spectralDonuts` and went RED the moment #1057 landed; it shipped red in
/// 457 and 458 and never fell inside the 200-line job-log window (#807).
/// `scripts/moved-needles.py 04f6b3d0` names this file on the first run (#1093).
/// Claim 4's premise changed too: the nine field-only rows ARE hidden in donut mode now — behind
/// `donutIsThePicture`, whose second term (`!isProjectingExternally`) is exactly the projector
/// case the old message warned about. So claim 4 keeps asserting the rows are not DELETED and
/// stops calling hiding the wrong fix; the two-term condition itself is pinned by
/// `TheDonutHidesTheDialsItCannotHearTests` and is not repeated here (#416).
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
    //
    // Since #1057 the question is asked ABOVE the caption, not inside it: the Rings-only
    // sentence may only render while the Metal field is the picture, so its `if` must carry
    // `!donutIsThePicture` as a term. The donut state's own sentence is owned and pinned by
    // `TheDonutHidesTheDialsItCannotHearTests` ("Switch back to the field to use them.").
    func testTheRingsOnlyCaptionRunsOnlyWhileTheFieldIsThePicture() throws {
        let code = SourceText.codeOnly(try source(Self.studio))
        let sentence = "Detail shapes the Rings look only"
        guard let at = code.range(of: sentence) else {
            XCTFail("""
                The Rings-only caption ("\(sentence)") is gone from `EchoelStudioView`. If the \
                wording changed, re-anchor this needle; if the caption was removed, say in this \
                file what now tells a player that Detail has no reach on a look without Rings.
                """)
            return
        }
        // The `if` that guards the sentence is the code line four above it. Comments are
        // stripped (`SourceText.codeOnly`) so the ⛔ prose above the `Text` — which quotes
        // both names — cannot satisfy the scan; the stripper keeps each comment line's
        // indentation, so the window is the last SIX NON-BLANK code lines, not a byte count
        // (a 400-byte window measured 707 bytes short on the real tree — first draft).
        let window = code[code.startIndex..<at.lowerBound]
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .suffix(6)
            .joined(separator: "\n")
        XCTAssertTrue(window.contains("if !donutIsThePicture,"), """
            The Rings-only caption is no longer guarded by `!donutIsThePicture`. In donut mode \
            Detail sets the band count, so this sentence would call the ONE live control inert \
            — the #1003 defect back in its original form. The guard must be a term of the \
            caption's own `if`, not a check somewhere else in the body.

            Code scanned before the sentence: \(window)
            """)
        XCTAssertTrue(window.contains("detailReach("), """
            The Rings-only caption no longer consults `LookBlendMap.detailReach` — it is shown \
            regardless of whether Detail can reach the field. Claim 3 of `LookBlendMap`'s own \
            guards owns the arithmetic; this file only requires that the caption asks it.

            Code scanned before the sentence: \(window)
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

    // 4 — COUNTERWEIGHT: the sibling rows are not deleted.
    //
    // ⛔ Until #1095 this said "stay on screen" and its message called hiding them "the
    // tempting wrong fix". #1057 hid them — behind `donutIsThePicture`, which is FALSE while a
    // projector is attached, so the beamer's controls stay live. That is the fix the old
    // message was afraid of, done with the exception it asked for. What must not happen is the
    // rows being DELETED for tidiness; that is all this claim asserts now.
    func testTheOtherAdjustRowsAreNotDeleted() throws {
        let text = try source(Self.studio)
        for label in ["label: \"Motion\"", "label: \"Spread\"", "label: \"Hue\"",
                      "label: \"Saturation\"", "label: \"Texture\"", "label: \"Glitter\""] {
            XCTAssertTrue(text.contains(label), """
                The visual adjust row \(label) is gone. Hiding it in donut mode is correct \
                (#1057, behind `donutIsThePicture`); deleting it is not: `ExternalDisplayScene` \
                renders `MetalBioView` from the same keys, so with a projector attached these \
                rows are live even while the on-device picture shows donuts. A control that is \
                inert HERE is not inert THERE.
                """)
        }
    }
}
