// TheWayOutSurvivesRotationTests.swift
// Echoel — a fullscreen picture must not put its own exit under the sensor housing. #583.
//
// WHAT THIS GUARDS. `FloatingVisualWindow` bleeds the fullscreen picture past the safe area so the
// visual is edge-to-edge. The edge set was `[.bottom, .horizontal]` in EVERY orientation, and the
// comment above it justified that with: keep the TOP safe area so the toolbar never hides under
// the notch — you must still be able to manipulate the visual (founder).
//
// ⛔ THE DEFECT IS THAT THE JUSTIFICATION IS PORTRAIT-ONLY, and nothing said so. In portrait the
// sensor housing is a `.top` inset, which is exactly the edge the modifier keeps — so the sentence
// is true, and has been true every time anyone checked it, because everyone checked it upright.
// Rotate the phone and the housing becomes a HORIZONTAL inset: the modifier then protects the one
// edge that was never at risk and opens the one that is. What sits at that edge is not decorative
// — `FloatingVisualLayout.ChromeFit` calls resize and close "the two ways out", and they are the
// LAST two items of the bar, i.e. the two nearest the trailing edge (~10–38 pt and ~46–74 pt in,
// against a landscape housing inset of roughly 59 pt).
//
// ⭐ AND #580 IS WHY THIS BECAME URGENT RATHER THAN THEORETICAL. Before that slice the window came
// up at `.small`, where the modifier passes `[]` and nothing bleeds; fullscreen was something the
// user chose. Since #580 fullscreen IS the launch state, so a cold launch in landscape — or a
// rotation while fullscreen — is the default path into it. Landscape is shipped: the iPhone
// orientation list carries LandscapeLeft and LandscapeRight.
//
// ⭐ WHY A STATIC EDGE SET AND NOT A PADDING ON THE BAR. Padding the toolbar back out of the safe
// area keeps the picture edge-to-edge in landscape too, and it is the fix I could not verify.
// `.ignoresSafeArea` is applied to the `GeometryReader`, so what a child's `safeAreaPadding` or a
// proxy's `safeAreaInsets` reports INSIDE that reader is precisely the SwiftUI semantics no test
// in this repo can settle — there is no simulator here (§0). Guessing at layout semantics and
// shipping it as a stability fix would be the same defect in a new place. An edge set has no
// ambiguity. Portrait — the orientation the founder has used and approved — is left byte-identical.
//
// ⚠️ HONEST LIMITS.
//   · 13 tests, 17 assertions (`grep -c 'func test'` and `grep -c XCTAssert`, not counted by eye).
//     Two are END-TO-END BEHAVIOUR on the pure decision; the rest are a SOURCE-TEXT SCAN, because
//     everything else here is a `private` member of a `View` no test bundle can instantiate.
//   · DEVICE PROBE, open and NOT covered: that landscape fullscreen still LOOKS right once it
//     stops bleeding sideways. It will letterbox by the housing inset on a notched phone. That is
//     a deliberate trade — a reachable exit beats an edge-to-edge picture — but whether the
//     letterbox reads as broken is a founder judgement this file cannot make.
//     NEEDS-FOUNDER-VERIFY: open the visual fullscreen, rotate both ways, and check (a) the X and
//     the contract arrows are fully tappable, (b) the picture still looks intentional.
//   · This guard does NOT prove the housing inset is ~59 pt or that a button was covered. It
//     proves the app no longer bleeds into the edge that carries them, which is the decision.
//
// ⭐ GRADING (§3). This file names `FloatingVisualLayout.fullscreenBleedsHorizontally`, created by
// this same commit, so it DOES NOT COMPILE against the parent tree and NO assertion has a verdict
// there. Hand-transcribed instead, needle by needle against `git show HEAD:`:
//   · ONE finding (#486): the parent bleeds horizontally in every orientation. Driven needle by
//     needle against the parent, 6 of the 12 source needles are red there — five by absence of a
//     symbol this commit creates, one because the parent still carries the retracted expression.
//     That is the single finding counted six times, not six findings. The behavioural pair could
//     not have had a verdict there at all.
//   · The remaining 6 needles, and 13 of the 17 assertions, are COUNTERWEIGHTS — green on both
//     trees, and they are the point (#343): portrait is UNCHANGED, floating sizes still bleed
//     nothing, the two exits are still the last two items of the bar and still absent from the
//     shed budget, landscape is still shipped, fullscreen is still the launch state. A "fix" that
//     quietly letterboxed portrait, or let the budget start shedding an exit, would sail past a
//     guard that only asserted the new line.
//   · Stripper: **PROPHYLAKTISCH (0 of 12 needles flip)**, measured raw vs. stripped on both
//     trees. The retracted edge set is quoted in prose in this very file and in the window, but
//     no needle searches for it bare — each negative needle carries its surrounding code, which
//     prose does not reproduce.
//
// ⛔ AND THE FIRST MEASUREMENT OF THAT LINE WAS PRODUCED BY A BROKEN TRANSCRIPTION, which is worth
// more than the number it corrected. §0 says a guard that cannot run here is graded by
// reimplementing it in Python — and my reimplementation of `SourceText.stripLine` dropped the
// CONTENTS of every string literal instead of keeping them (the real one appends inside the
// `inString` branch). So every needle that searches for a quoted string reported "absent after
// stripping", and two counterweights here looked red on a correct tree while, in the sibling
// slice, a needle looked reassuringly green for the wrong reason. The transcription is the
// measuring instrument; an unverified instrument produces confident numbers in both directions.
// Cheap tell, and the one that caught it: a needle whose disappearance under stripping has no
// comment to blame it on.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheWayOutSurvivesRotationTests: XCTestCase {

    // MARK: - END-TO-END: the decision itself

    /// COUNTERWEIGHT, and the one that matters most. Portrait is the orientation the founder has
    /// actually used; this slice must not have touched it. The housing is a `.top` inset there,
    /// the modifier keeps `.top`, and the sides are free to bleed.
    func testPortraitStillBleedsToTheSides() {
        XCTAssertTrue(FloatingVisualLayout.fullscreenBleedsHorizontally(isLandscape: false),
                      "Portrait must be byte-identical to before #583 — edge-to-edge sideways.")
    }

    /// THE FINDING (1 of 1). In landscape the housing occupies a horizontal edge, which is where
    /// the bar's two exits sit, so the picture must stop there.
    func testLandscapeDoesNotBleedIntoTheEdgeThatCarriesTheExits() {
        XCTAssertFalse(FloatingVisualLayout.fullscreenBleedsHorizontally(isLandscape: true),
                       "In landscape the sensor housing IS the horizontal inset. Bleeding into it "
                       + "puts the close and contract buttons under the cutout.")
    }

    // MARK: - SOURCE-TEXT SCAN: the view must ask the decision, not restate it

    func testTheWindowAsksTheSharedDecision() throws {
        let src = try source("Sources/Echoelmusic/Studio/FloatingVisualWindow.swift")
        XCTAssertTrue(
            src.contains("FloatingVisualLayout.fullscreenBleedsHorizontally(isLandscape:"),
            "The edge set must come from the drivable decision, not from a second literal.")
        XCTAssertTrue(src.contains(".ignoresSafeArea(edges: fullscreenBleedEdges)"),
                      "One modifier, one owner of what it is given.")
    }

    /// The retracted form must not survive. Written as the WHOLE conditional rather than as the
    /// bare `[.bottom, .horizontal]`, because that array is still legitimately present — it is
    /// what portrait returns — and forbidding it outright would forbid the correct code (#364).
    func testTheOrientationBlindEdgeSetIsGone() throws {
        let src = try source("Sources/Echoelmusic/Studio/FloatingVisualWindow.swift")
        XCTAssertFalse(src.contains("windowSize.isFullscreen ? [.bottom, .horizontal] : []"),
                       "This is the exact expression that bled sideways in every orientation.")
    }

    /// COUNTERWEIGHT. A floating card is inside the safe area on every edge and must stay there —
    /// the whole bleed is a fullscreen affordance, and a regression here would push the small
    /// window's own chrome under the housing at every size.
    func testFloatingSizesStillBleedNothing() throws {
        let src = try source("Sources/Echoelmusic/Studio/FloatingVisualWindow.swift")
        XCTAssertTrue(src.contains("guard windowSize.isFullscreen else { return [] }"),
                      "Only fullscreen bleeds. Every floating size stays inside the safe area.")
    }

    /// COUNTERWEIGHT on the freeze law. Orientation is read as an environment value, which changes
    /// only on rotation; deriving it from a live publisher or a per-frame geometry read in THIS
    /// body would make the window rebuild at that rate and tear down any open menu below it.
    func testOrientationComesFromTheEnvironmentNotFromALiveValue() throws {
        let src = try source("Sources/Echoelmusic/Studio/FloatingVisualWindow.swift")
        XCTAssertTrue(src.contains("@Environment(\\.verticalSizeClass) private var vSize"),
                      "The established spelling of orientation in this codebase.")
        XCTAssertTrue(src.contains("vSize == .compact"),
                      "On iPhone a compact vertical size class IS landscape.")
    }

    /// COUNTERWEIGHT. The same spelling is used one directory over for the same question. Two
    /// definitions of "is this landscape" is the #416 defect waiting to happen, and this pins that
    /// the older one still exists to be consistent with.
    func testTheStudioDecidesOrientationTheSameWay() throws {
        let src = try source("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        XCTAssertTrue(src.contains("@Environment(\\.verticalSizeClass) private var vSize"))
        XCTAssertTrue(src.contains("vSize == .compact"))
    }

    // MARK: - COUNTERWEIGHTS: what makes the finding a finding

    /// The two exits must remain the last two items of the bar. If they ever moved inward, the
    /// horizontal inset would stop being the thing that hides them and this whole slice would be
    /// guarding a fact that no longer holds — green for a reason that no longer exists (§4).
    func testTheTwoExitsAreStillTheLastTwoItemsOfTheBar() throws {
        let src = try source("Sources/Echoelmusic/Studio/FloatingVisualWindow.swift")
        guard let exit = src.range(of: "\"Exit fullscreen\""),
              let hide = src.range(of: "\"Hide visual\"") else {
            return XCTFail("The two exit buttons were renamed — re-anchor this scan (#454).")
        }
        XCTAssertTrue(exit.lowerBound < hide.lowerBound,
                      "Resize/contract precedes close; close is the trailing-most control.")
    }

    /// COUNTERWEIGHT. Neither exit may become sheddable. `ChromeFit` is the budget of OPTIONAL
    /// chrome, and the two ways out are deliberately not represented in it — if they ever gained
    /// a field, a narrow card could drop the exit on its own, which is the same loss by a
    /// different route.
    ///
    /// ⛔ THE FIRST VERSION OF THIS TEST COULD NOT FAIL, which is the one thing a guard may never
    /// be (#367). It set all six fields true, rebuilt the same value, and compared them — adding
    /// a seventh field would have left both sides carrying its default, so the assertion stayed
    /// green through exactly the change it claimed to catch. Reflection over the field NAMES can
    /// fail, and fails for the stated reason.
    func testNeitherExitIsPartOfTheShedBudget() {
        let fields = Mirror(reflecting: FloatingVisualLayout.ChromeFit())
            .children.compactMap(\.label).sorted()
        XCTAssertEqual(fields,
                       ["gridToggle", "lookSlider", "miniTransport",
                        "studioChip", "videoRecord", "wavRecord"],
                       "ChromeFit's fields changed. That is allowed — but if the new one is an "
                       + "exit, a narrow card can now shed the way out on its own, which is the "
                       + "same loss #583 fixed by a different route.")
    }

    /// COUNTERWEIGHT. Landscape is genuinely shipped on iPhone; without that the defect would be
    /// unreachable and this guard would be pinning a decision nobody can hit (#367).
    func testLandscapeIsAShippedOrientation() throws {
        let plist = try rawSource("Resources/iOS/Info.plist")
        XCTAssertTrue(plist.contains("UIInterfaceOrientationLandscapeLeft"))
        XCTAssertTrue(plist.contains("UIInterfaceOrientationLandscapeRight"))
    }

    /// COUNTERWEIGHT on the reason it became urgent: the launch seed still forces fullscreen, so
    /// the landscape path into the picture is the DEFAULT one and not a corner.
    func testFullscreenIsStillTheLaunchState() throws {
        let src = try source("Sources/Echoelmusic/Studio/WorkspaceView.swift")
        XCTAssertTrue(src.contains("floatingSizeRaw = FloatingVisualWindow.WindowSize.fullscreen.rawValue"),
                      "#580 seeds fullscreen at launch. If that ever changes, this slice stops "
                      + "being urgent — but it does not stop being correct.")
    }

    /// COUNTERWEIGHT. The bar keeps its own horizontal padding; the fix is about the SAFE AREA,
    /// not about the bar's internal spacing, and confusing the two later would undo it.
    func testTheBarKeepsItsOwnPadding() throws {
        let src = try source("Sources/Echoelmusic/Studio/FloatingVisualWindow.swift")
        XCTAssertTrue(src.contains(".padding(.horizontal, 10)"))
    }

    // MARK: - source access (§0/§2 — one stripper, skip on no tree, FAIL on a moved anchor)

    private struct RotationAnchorMissing: Error { let reason: String }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    /// Verbatim, for files that are not Swift — running a Swift comment stripper over a plist
    /// would be a category error, and `//` is not a comment there.
    private func rawSource(_ relativePath: String) throws -> String {
        let root = repoRoot()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        let path = root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw RotationAnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — it was renamed or moved. \
                Re-anchor this scan; do not let it skip (#454).
                """)
        }
        return try String(contentsOf: path, encoding: .utf8)
    }

    private func source(_ relativePath: String) throws -> String {
        SourceText.codeOnly(try rawSource(relativePath))
    }
}
