// TheFloatingWindowMovesWithoutADragTests.swift
// Echoel — the floating visual window must be movable WITHOUT a drag (#619, A11y#4).
//
// WHAT THIS GUARDS (GUI-Board Zeile 9). The card moved ONLY by a DragGesture on the logo
// handle — a gesture VoiceOver cannot perform, so for a VO user the window was pinned
// wherever it spawned, possibly covering the control they need next. #619 adds four named
// rotor actions on the handle that snap `center` to the corners, backed by pure maths in
// `FloatingVisualLayout.snapCenter`. The drag STAYS: the actions are a second door to the
// same state, not a replacement.
//
// KIND (per §1, labelled per case): the `snapCenter`/`SnapCorner` cases are END-TO-END
// BEHAVIOUR (public, Foundation-level value maths — the strong kind). The wiring cases are
// SOURCE-TEXT SCANS: they prove where text sits in `FloatingVisualWindow.swift`, never that
// VoiceOver actually offers or speaks the actions — that is a DEVICE PROBE and stays open
// (registered with the 2525 probes).
//
// GRADING (#433/#464): this file names `FloatingVisualLayout.SnapCorner`, a symbol created
// by the same commit — against the parent tree the file DOES NOT COMPILE, so no assertion
// has a verdict there (§3: said exactly, not "green"). Hand-transcription instead: the
// behavioural claims are FORWARD (they drive the new function), the two wiring anchors are
// FORWARD (`.accessibilityActions` count 0 → 1), and the two counterweights (drag gesture,
// drag label) are green on both trees — they are the point: a commit that swapped the drag
// FOR the actions would red them.
//
// Stripper: delegates to `SourceText.codeOnly` (#453). MEASURED PROPHYLAKTISCH (0 of 4
// windowed verdicts flip raw vs stripped on either tree): the #619 comment block sits
// ABOVE the `.accessibilityActions` anchor and quotes no needle; the "Move to " absence
// check is 0 raw AND stripped because the view's comment deliberately avoids the phrase.
// Kept through codeOnly anyway so a future comment quoting an action name cannot flip the
// absence verdict — that is the exact class #618 measured TRAGEND next door.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheFloatingWindowMovesWithoutADragTests: XCTestCase {

    private let bounds = CGSize(width: 393, height: 852)   // portrait iPhone reference
    private let card = CGSize(width: 165, height: 220)     // ≈ small-step card
    private let margin: CGFloat = 12                        // FloatingVisualWindow.margin

    // MARK: END-TO-END — the snap maths

    /// "Move to bottom right" lands on the DOCK spot: bottom corners lift by the studio
    /// control band, exactly like `defaultCenter`, so the action never parks the card a
    /// few points lower than any drag would rest. Asserted as edge properties, not as a
    /// restatement of the formula (#442: algebra, not printed values).
    func testTheBottomRightActionLandsOnTheDockSpot() {
        let c = FloatingVisualLayout.snapCenter(.bottomRight, in: bounds, card: card,
                                                margin: margin)
        XCTAssertEqual(bounds.width - (c.x + card.width / 2), margin, accuracy: 1e-9,
                       "the right edge must keep exactly the drag-clamp margin")
        XCTAssertEqual(bounds.height - (c.y + card.height / 2),
                       margin + FloatingVisualLayout.studioControlBandHeight,
                       accuracy: 1e-9, """
            the bottom corners must clear the studio control band — the same lift \
            `defaultCenter` applies. Losing it makes the VO action park the card OVER \
            the primary control, which is worse for a VO user than not moving at all.
            """)
    }

    /// Top corners keep the plain margin on both axes (no band at the top).
    func testTheTopCornersKeepTheMargin() {
        let tl = FloatingVisualLayout.snapCenter(.topLeft, in: bounds, card: card,
                                                 margin: margin)
        XCTAssertEqual(tl.x - card.width / 2, margin, accuracy: 1e-9)
        XCTAssertEqual(tl.y - card.height / 2, margin, accuracy: 1e-9)
        let tr = FloatingVisualLayout.snapCenter(.topRight, in: bounds, card: card,
                                                 margin: margin)
        XCTAssertEqual(bounds.width - (tr.x + card.width / 2), margin, accuracy: 1e-9)
        XCTAssertEqual(tr.y, tl.y, accuracy: 1e-9, "the top row is one height")
    }

    /// Degenerate container (card wider than bounds): the NEAR edge wins — the same
    /// ordering `clamp` uses — and every coordinate stays finite. The view still clamps
    /// at render time, but the pure function must not hand it NaN or a flipped interval.
    func testADegenerateContainerFoldsToTheNearEdge() {
        let tiny = CGSize(width: 100, height: 100)
        let big = CGSize(width: 400, height: 400)
        for corner in FloatingVisualLayout.SnapCorner.allCases {
            let c = FloatingVisualLayout.snapCenter(corner, in: tiny, card: big,
                                                    margin: margin)
            XCTAssertTrue(c.x.isFinite && c.y.isFinite)
            XCTAssertEqual(c.x, big.width / 2 + margin, accuracy: 1e-9,
                           "maxX folded onto minX — left and right agree when nothing fits")
            XCTAssertEqual(c.y, big.height / 2 + margin, accuracy: 1e-9)
        }
    }

    /// The action set is four distinct MOVE actions. #364: the exact wording is free —
    /// only the count, uniqueness, and the "Move to" verb (the promise VoiceOver reads
    /// out) are pinned.
    func testTheCornerSetIsFourDistinctMoveActions() {
        let names = FloatingVisualLayout.SnapCorner.allCases.map(\.rawValue)
        XCTAssertEqual(names.count, 4)
        XCTAssertEqual(Set(names).count, 4, "two corners announcing the same words")
        for name in names {
            XCTAssertTrue(name.hasPrefix("Move to "), """
                a snap action's name no longer starts with "Move to " — VoiceOver reads \
                these verbatim from the rotor, and an action that does not say it moves \
                the window is a mystery button to a blind user. Reword freely behind the \
                verb.
                """)
        }
    }

    // MARK: SOURCE-TEXT — the wiring in FloatingVisualWindow.swift

    private func viewLines() throws -> [String] {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let path = root.appendingPathComponent(
            "Sources/Echoelmusic/Studio/FloatingVisualWindow.swift")
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw XCTSkip("source tree not present at \(path.path)")
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    /// The handle's action builder exists once, gates on fullscreen, and derives from the
    /// ONE definition (`SnapCorner.allCases` + `snapCenter`) instead of restating names.
    func testTheHandleOffersTheActionsFromTheOneDefinition() throws {
        let lines = try viewLines()
        let anchors = lines.indices.filter { lines[$0].contains(".accessibilityActions {") }
        XCTAssertEqual(anchors.count, 1, """
            `.accessibilityActions` is no longer unique in FloatingVisualWindow — re-anchor \
            this window before trusting the assertions below (#408).
            """)
        guard let start = anchors.first else { return }
        let window = lines[start ..< min(start + 12, lines.count)]
        XCTAssertTrue(window.contains { $0.contains("if !windowSize.isFullscreen") }, """
            the fullscreen gate is gone from the action builder. Fullscreen pins the card \
            to the exact centre and ignores `center`, so an action offered there silently \
            edits an invisible state — the builder must emit nothing in fullscreen.
            """)
        XCTAssertTrue(window.contains { $0.contains("FloatingVisualLayout.SnapCorner.allCases") }, """
            the actions no longer derive from `SnapCorner.allCases` — the names' one \
            definition (#416). A hand-written list here is the second spelling this file \
            exists to forbid.
            """)
        XCTAssertTrue(window.contains { $0.contains("FloatingVisualLayout.snapCenter(") }, """
            the action no longer calls the pure snap maths — whatever replaced it is not \
            covered by the behavioural half of this file.
            """)
        // The view restates NO action name: 0 hits file-wide (codeOnly), so a rename in
        // `SnapCorner` can never leave a stale twin behind in the view.
        XCTAssertFalse(lines.contains { $0.contains("Move to ") }, """
            an action name is spelled out in FloatingVisualWindow — the names live ONLY \
            as `SnapCorner` rawValues (#416). Delete the copy; build from `allCases`.
            """)
    }

    /// COUNTERWEIGHTS — green on both trees: the founder's drag and its honest label
    /// survive. The actions ADD a door; a commit that swapped the drag for them (or
    /// re-flattened the label so fullscreen promises a drag it ignores) reds this.
    func testTheDragDoorSurvives() throws {
        let lines = try viewLines()
        XCTAssertEqual(lines.filter { $0.contains("DragGesture(coordinateSpace: .global)") }.count,
                       1, """
            the handle's drag gesture is gone (or duplicated). #619's actions are a \
            SECOND door for VoiceOver, never a replacement — sighted users keep the drag, \
            and the `.global` space is the anti-tremble fix (founder: "zittert").
            """)
        XCTAssertEqual(lines.filter { $0.contains("Echoelmusic — drag to move the visual") }.count,
                       1, """
            the handle's floating-state label is gone or duplicated. It must say "drag to \
            move" exactly where a drag CAN move the card — and only there (fullscreen \
            ignores `center`, so its branch drops the promise).
            """)
    }
}
