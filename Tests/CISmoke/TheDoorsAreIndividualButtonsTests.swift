// TheDoorsAreIndividualButtonsTests.swift
// Echoel — #492. The "•••" overflow is dissolved; its two entries are buttons.
//
// FOUNDER, 2026-08-07, third of four asks marked in red on the v10.79.374 (2491) screenshot:
// *"Das mit den drei Punkten als einzelnde Buttons anzeigen."*
//
// ⭐ WHAT MAKES THIS WORTH A GUARD IS NOT THE DELETION — it is that the two doors behind that
// menu are the ONLY global doors in the app that are sheets rather than panels. There is no
// chip that can reach Live Colabo or Learn (#290 says why, and its reasoning survived the menu:
// the chip strip's grammar is "this chip selects what the plate shows", so a chip that opened a
// modal would be a lying tab). With the menu gone, `quickDoorRow` is the only way in. A later
// tidy-up that folds this row away does not make the app smaller — it makes two features
// unreachable, which is the exact failure this repo's doorless-surface register exists for.
//
// ⚠️ WHAT THIS GUARD CANNOT DO, stated first so its green is not read as more than it is.
// EVERY assertion is a SOURCE-TEXT SCAN. It shows that a `Button` is written, never that it
// renders, never that a finger reaches it, never that VoiceOver speaks the label, and never
// that the two-line plate reads well on a 360 pt phone. Those are device probes and all four
// are open. The width arithmetic that forced two lines (7×44 + 6×8 = 356 pt against 361/343/328
// of usable width) is arithmetic over constants, not a measurement of a rendered layout.
//
// ⚠️ HONEST GRADING against the parent tree, MEASURED rather than assumed — every needle below
// transcribed and driven against `git show HEAD:…` as well as against this tree:
//   · SIX assertions are REGRESSIONS (red there, green here), and they split by MECHANISM,
//     which matters more than the count:
//       – TWO fail on something the parent actively CONTAINS: `TransportOverflowMenu` still
//         declared and built, and the two dead notification cases still in the receiver.
//       – THREE fail because their ANCHOR does not exist yet — `quickDoorRow` is absent, so
//         they throw `DoorAnchorMissing`. That is ONE absence reported three times, not three
//         findings, and calling it three would be the #433 defect in the flattering direction.
//       – ONE (the mount) is in between: `startControlRow` exists on the parent and simply
//         does not name the row.
//   · ONE is a COUNTERWEIGHT, green on both sides: both sheets still exist. It exists because
//     the tempting reading of "dissolve the menu" is "remove the doors", and because the
//     presentation chain the black-screen law guards (10.76.34) must be UNCHANGED by this
//     slice — this commit moves who taps the sheets, not how many sheets there are.
//
// ⚠️ `SourceText.codeOnly` (#453) IS PROPHYLACTIC HERE, NOT LOAD-BEARING — measured, because
// claiming otherwise is exactly the overclaim #484 had to retract one cycle earlier. Raw text
// against stripped text: **0 of 14 verdicts differ** (7 assertions × 2 trees). The reason is
// SCOPING, not luck: the receiver's ⛔ retraction does name the deleted cases, but it sits
// outside the brace-matched `switch`, and the one file-wide `case "learn":` in prose is 2,300
// lines away from it. It stays because #453 made ONE definition of "code, not prose" for the
// whole blocking bundle and a private exception is the defect that slice removed — and because
// the shape that WOULD make it load-bearing is one comment away: a future retraction inside
// this file that writes `TransportOverflowMenu()` verbatim turns the negative scan red on
// correct code. This repo writes down what it removed, so a negative scan meets its own
// obituary sooner or later (#486, #488).

import Foundation
import XCTest

/// Thrown when a scan's anchor is gone. NOT a skip — a skip passes CI (#454), and "the thing I
/// guard moved" is a failure, not an absence of a checkout.
private struct DoorAnchorMissing: Error, CustomStringConvertible {
    let reason: String
    var description: String { reason }
}

final class TheDoorsAreIndividualButtonsTests: XCTestCase {

    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"
    private static let workspace = "Sources/Echoelmusic/Studio/WorkspaceView.swift"

    // MARK: - 1. the ask itself: two buttons, not a menu

    /// The founder asked for the entries as individual buttons. A `Menu` inside this row would
    /// satisfy "the tiles are here" while re-creating exactly what was asked to go away.
    func testTheTwoDoorsAreIndividualButtons() throws {
        let doors = try declarationBody(of: "private var quickDoorRow: some View {",
                                        in: Self.studio)
        XCTAssertTrue(doors.contains("showLiveColabo = true"), """
            `quickDoorRow` no longer opens Live Colabo.

            It is one of only two global doors that are sheets rather than panels, so no chip \
            can reach it — this row is the only way in (#290).
            """)
        XCTAssertTrue(doors.contains("showLearn = true"), """
            `quickDoorRow` no longer opens Learn. Same reason as Live Colabo: sheet, not panel, \
            so there is no chip that reaches it.
            """)
        XCTAssertFalse(doors.contains("Menu {"), """
            A `Menu` is back inside `quickDoorRow`.

            The founder asked for these entries as INDIVIDUAL buttons \
            (*"Das mit den drei Punkten als einzelnde Buttons anzeigen"*). Re-folding them into \
            a menu satisfies the letter of "the doors are on the plate" against the whole point \
            of the ask.
            """)
    }

    /// The row has to be MOUNTED. A property nobody builds is the doorless-surface shape this
    /// repo keeps paying for, and it would leave both sheets with no producer at all.
    func testTheDoorRowIsMounted() throws {
        let row = try declarationBody(of: "private var startControlRow: some View {",
                                      in: Self.studio)
        XCTAssertTrue(row.contains("quickDoorRow"), """
            `startControlRow` no longer builds `quickDoorRow`.

            Both doors then have no producer whatsoever: they are sheets, so no chip reaches \
            them, and #492 deleted the `.echoelChromeDoor` cases that used to. Live Colabo and \
            Learn would compile, present correctly, and be unreachable.
            """)
    }

    // MARK: - 2. the menu is gone from the whole of Sources/

    /// Scoped to `Sources/` rather than to one file: the failure this catches is somebody
    /// re-introducing the overflow ANYWHERE, not moving it back to its old address.
    func testNoOverflowMenuSurvivesInSources() throws {
        let workspace = try source(Self.workspace)
        XCTAssertFalse(workspace.contains("struct TransportOverflowMenu"), """
            `TransportOverflowMenu` is declared again.

            #492 deleted it on the founder's ask. If a future control genuinely needs an \
            overflow, it needs its own name and its own reason — not the resurrection of the \
            one that was pointed at with a red circle.
            """)
        let studio = try source(Self.studio)
        XCTAssertFalse(studio.contains("TransportOverflowMenu()"), """
            `EchoelStudioView` builds `TransportOverflowMenu()` again — the control the founder \
            asked to be replaced by individual buttons.
            """)
    }

    // MARK: - 3. both doors speak

    /// An icon-only control must say what it is (#489). Both labels are inherited verbatim from
    /// the menu entries they replace — "Live Colabo" alone would not tell a first-time listener
    /// that it is about playing WITH someone in the room.
    func testBothDoorsSpeak() throws {
        let doors = try declarationBody(of: "private var quickDoorRow: some View {",
                                        in: Self.studio)
        for (door, label) in [("Live Colabo", "Live Colabo — play together nearby"),
                              ("Learn", "Learn and news")] {
            XCTAssertTrue(doors.contains(".accessibilityLabel(\"\(label)\")"), """
                The \(door) tile lost its spoken label.

                Its whole visible content is an SF Symbol, so without this modifier SwiftUI \
                names the button after the glyph — VoiceOver would read "dot radiowaves left \
                and right" or "book". An accessibility label is invisible with VoiceOver off, \
                so no screenshot and no design pass will ever show this missing (#480).
                """)
        }
    }

    // MARK: - 4. the equal-width counterweight

    /// ⭐ THIS IS THE ASSERTION THE FILE EXISTS FOR, and it guards a line that looks like
    /// tidying. `expands` gives each flexible child of an `HStack` an equal share, so three
    /// tiles alone would be a third wider than the four above them — in the row whose entire
    /// brief is the founder's *"die sollen immer gleichgroß sein"* (#481/#482). The trailing
    /// `Spacer(minLength: 0)` is a fourth flexible slot that draws nothing, so both lines are
    /// four-up and all seven tiles are one width on every device.
    ///
    /// Deleting it is a one-character-looking change with a visible consequence, and nothing
    /// else in the tree would notice.
    func testTheEqualWidthCounterweightIsPresent() throws {
        let doors = try declarationBody(of: "private var quickDoorRow: some View {",
                                        in: Self.studio)
        XCTAssertTrue(doors.contains("Spacer(minLength: 0)"), """
            `quickDoorRow` lost its trailing `Spacer(minLength: 0)`.

            That blank is a LAYOUT CONSTANT, not leftover scaffolding: without it this line \
            spreads three `expands` tiles across the width four tiles occupy above, so line 3 \
            renders a third wider than line 2 and the founder's "immer gleichgroß" breaks on \
            the row it was asked for.
            """)
        XCTAssertEqual(doors.components(separatedBy: "expands: true").count - 1, 3, """
            `quickDoorRow` no longer passes `expands: true` to exactly three tiles.

            Equal width comes from every tile in BOTH lines being flexible. A fixed-width tile \
            here takes its share out of the equalisation and the two lines stop matching.
            """)
    }

    // MARK: - 5. the notification cases went with their producer

    /// The receiver's own ⛔ block deleted four cases in #290 for precisely this reason: a
    /// `case` whose only poster is gone compiles silently and reads like a live hook. The two
    /// door tiles live in THIS view and own the `@State` they set, so a notification would have
    /// been a message from the studio to itself.
    ///
    /// ⚠️ This is one of only TWO assertions here that fail on something the parent tree
    /// actively CONTAINS (the other being the overflow scan); three of the remaining four trip
    /// over `quickDoorRow` not existing yet, which is one absence reported three times.
    func testTheDeadNotificationCasesAreGone() throws {
        let receiver = try switchBody(after: "publisher(for: .echoelChromeDoor)) { note in",
                                      in: Self.studio)
        for dead in ["case \"learn\"", "case \"live\""] {
            XCTAssertFalse(receiver.contains(dead), """
                `\(dead)` is back in the `.echoelChromeDoor` receiver with no producer.

                The "•••" overflow was its only poster and #492 deleted it. If a future chrome \
                control needs one of these back, re-add the case TOGETHER with the control, \
                never ahead of it.
                """)
        }
        XCTAssertTrue(receiver.contains("case \"video\""), """
            The `.echoelChromeDoor` receiver lost its REAL producers' cases too.

            The header monitor tiles still post `"video"`, `"routing"` and `"bio"`. #492 removed \
            two dead cases; it did not retire the notification, and a scan that only forbids \
            things is green on a receiver that lost everything (the #343 trap).
            """)
    }

    // MARK: - 6. counterweight: the doors themselves still open

    /// Green on both sides of #492 on purpose. Two things could quietly undo this slice in the
    /// tidy-up direction: removing the sheets along with the menu that used to open them, and
    /// "consolidating" by adding a NEW presentation modifier. The first makes two features
    /// unreachable; the second spends headroom the black-screen law (10.76.34) has none of.
    /// This slice must leave the chain exactly as it found it — `ResetSoundClearsWhatTheLaunchLineReportsTests`
    /// owns the count, this owns the two identities.
    func testBothSheetsStillExist() throws {
        let studio = try source(Self.studio)
        for flag in ["$showLearn", "$showLiveColabo"] {
            XCTAssertTrue(studio.contains(".sheet(isPresented: \(flag))"), """
                The `\(flag)` sheet is gone.

                Dissolving the overflow was about WHO TAPS the door, not about whether the door \
                exists. Without this sheet the tile in `quickDoorRow` sets a flag nothing reads \
                — a lying control, which is the class this repo has retracted twice (#435, #480).
                """)
        }
    }

    // MARK: - source access

    /// Comment-stripped source, a SKIP when there is no checkout, and a FAILURE when the file
    /// itself moved. The distinction is #454's lesson: a skip passes CI, so "no tree" is a
    /// legitimate skip and "the thing I guard was renamed" must never be one.
    private func source(_ relativePath: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else {
            throw XCTSkip("source tree not present under \(root.path)")
        }
        let path = root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw DoorAnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — it was renamed or moved. \
                Re-anchor this scan; do not let it skip.
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }

    /// The brace-matched body that follows `key`, which must end in its opening brace.
    ///
    /// Brace-matched rather than "from here to the next declaration": this file holds ~9,900
    /// lines and several members whose text would otherwise leak into the scan. Deriving scope
    /// from FILE ORDER is a mistake this repo has already paid for more than once.
    private func declarationBody(of key: String, in relativePath: String) throws -> String {
        try braceBody(after: key, in: try source(relativePath), file: relativePath)
    }

    /// The `switch` that opens on the first line of the given closure.
    ///
    /// Anchored on the closure header and then on its `switch`, rather than on `switch note.object`
    /// directly, because more than one receiver in this file switches on a notification payload
    /// — and a scan that matches the wrong one is green on the wrong evidence (#408).
    private func switchBody(after anchor: String, in relativePath: String) throws -> String {
        let closure = try braceBody(after: anchor, in: try source(relativePath),
                                    file: relativePath)
        return try braceBody(after: "switch note.object as? String {", in: closure,
                             file: relativePath)
    }

    private func braceBody(after key: String, in text: String, file: String) throws -> String {
        guard let start = text.range(of: key) else {
            throw DoorAnchorMissing(reason: """
                `\(key)` not found in \(file) — renamed, reflowed or removed. Re-anchor this \
                scan; do not leave it silent.
                """)
        }
        // `start.upperBound` sits just past the opening brace, so the depth starts at 1.
        var depth = 1
        var body = ""
        var i = start.upperBound
        while i < text.endIndex, depth > 0 {
            let c = text[i]
            if c == "{" { depth += 1 }
            if c == "}" {
                depth -= 1
                if depth == 0 { break }
            }
            body.append(c)
            i = text.index(after: i)
        }
        XCTAssertEqual(depth, 0, "unbalanced braces after `\(key)` in \(file) — scan is unsound")
        return body
    }
}
