// TheTransportBarIsDissolvedTests.swift
// Echoel — #456. Founder screenshot, v10.79.371 (2488): the "•••" overflow and the
// `1.1.1 / loop 1/32` readout are each circled with an arrow drawn INTO the transport row
// below them. In this founder's markup grammar (established by #411's "soll dort hin wo der
// rote Pfeil hinzeigt migrieren") that means MOVE THESE THERE. Both children moved; the bar
// that held them — the last chrome transport bar — is deleted rather than left empty.
//
// ⭐ TWO LINES AND NOT ONE, and the reason is a measurement that was already written down.
// `startControlRow`'s own doc priced the one-line version: folding everything onto one line
// leaves the analysis pill — which the founder asked to make BIGGER on 2026-07-31
// (#305/#307) — with roughly a third of its width on a 393 pt phone once the pause button
// appears, and it named the answer for exactly that case: *"the cheapest answer is to move
// `TransportPositionView` and the '•••' overflow OUT of the chrome bar as well and give this
// row a second line — NOT to send the tempo back up."* Line 1 is therefore bit-for-bit what
// it was, which is what makes "nothing that exists today can be squeezed" a fact rather than
// a hope. Claim 2 is the assertion that keeps it that way.
//
// ⚠️ WHAT THIS FILE CANNOT DO, said first. Every assertion is a SOURCE SCAN. SwiftUI layout
// is not reachable from a unit test here, so "the row reads well on a 393 pt phone" and "the
// chrome is shorter now" are device looks. What is proven is that the bar is gone, that both
// children have exactly one home, that line 1 was not touched, and that the ~10 Hz playhead
// still lives in its own leaf — the freeze law's requirement for mounting it in the body that
// hosts the instrument's Pickers.

import Foundation
import XCTest
@testable import Echoelmusic

/// Thrown when a scan anchor is gone. An uncaught error in a `throws` test method FAILS,
/// which is the point — `XCTSkip` would have been green (the #454 lesson).
private struct MissingAnchor: Error, CustomStringConvertible {
    let reason: String
    var description: String { reason }
}

final class TheTransportBarIsDissolvedTests: XCTestCase {

    // MARK: - 1. the bar is gone, not emptied

    /// RED before #456. An emptied-but-present container is the worse outcome: it reads like a
    /// place to put things back, and it keeps a third always-on ancestor above the instrument.
    func testTheTransportBarStructIsDeleted() throws {
        let workspace = try source("Sources/Echoelmusic/Studio/WorkspaceView.swift")
        XCTAssertFalse(workspace.contains("struct TransportBar: View"), """
            `TransportBar` was re-declared.

            #456 dissolved it on the founder's 2026-08-07 arrows; its two children live in \
            `EchoelStudioView.startControlRow`. If a chrome transport bar is genuinely wanted \
            again, that is a founder ask and this test should be rewritten with it — not \
            deleted so the struct can quietly come back.
            """)
        XCTAssertFalse(workspace.contains("TransportBar()"), """
            Something still mounts `TransportBar()`.
            """)
    }

    // MARK: - 2. the counterweight: line 1 is untouched

    /// ⭐ THE ASSERTION THAT EARNS ITS PLACE GOING FORWARD.
    ///
    /// The obvious follow-up to #456 is "now put it all on one line after all". That is the
    /// change the measurement above rules out, and it is invisible in a diff that merely
    /// deletes a `VStack`. All four original children must still share ONE `HStack` with the
    /// two newcomers in a different one.
    func testTheFirstLineStillHoldsExactlyTheFourOriginals() throws {
        let row = try declarationBody(of: "private var startControlRow: some View {",
                                      in: "Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        for child in ["startButton", "PlaybackToggleButton()", "BodyTempoField(",
                      "PulseMonitorMiniLive()"] {
            XCTAssertTrue(row.contains(child), "`startControlRow` no longer builds `\(child)`.")
        }
        // Two HStacks inside the row is the shape; one means the lines were merged.
        let hstacks = row.components(separatedBy: "HStack(spacing: 8) {").count - 1
        XCTAssertEqual(hstacks, 2, """
            `startControlRow` has \(hstacks) inner `HStack(spacing: 8)`, expected 2.

            One means the two lines were merged. That is the change #456's own measurement \
            rules out: the analysis pill is the only flexible child, so a single line hands \
            it whatever is left after ▶ + ⏸ + tempo + lock + "•••" + the position readout — \
            and the founder asked for that pill to be BIGGER (#305/#307), not smaller.

            If a device look says one line is fine after all, make that the founder's call and \
            rewrite this test with the evidence. Do not merge them because the code looks \
            tidier that way.

            Row scanned (comments blanked by SourceText.codeOnly):
            \(row)
            """)
    }

    // MARK: - 3. both migrants have exactly one home

    func testBothMigrantsAreMountedInTheStudioRow() throws {
        let row = try declarationBody(of: "private var startControlRow: some View {",
                                      in: "Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        XCTAssertTrue(row.contains("TransportOverflowMenu()"), """
            The "•••" overflow is not in `startControlRow`. One of the founder's two arrows \
            pointed here.
            """)
        XCTAssertTrue(row.contains("TransportPositionView()"), """
            The position/loop readout is not in `startControlRow`. The founder's other arrow \
            pointed here.
            """)
    }

    // MARK: - 4. the freeze law, which is what makes claim 3 safe

    /// `TransportPositionView` reads `transport.position` — ~10 Hz at 120 BPM. Mounting it in
    /// `EchoelStudioView` is only legal because the read happens in ITS body, not in the host's
    /// (10.76.41/50). Inlining its two labels would be the exact shape of that ship-blocker,
    /// and it is a tempting "simplification" for a two-label view.
    func testThePlayheadReadStaysInsideItsOwnLeaf() throws {
        let leaf = try declarationBody(of: "struct TransportPositionView: View {",
                                       in: "Sources/Echoelmusic/Studio/WorkspaceView.swift")
        XCTAssertTrue(leaf.contains("@Environment(Transport.self)"), """
            `TransportPositionView` no longer reads `Transport` in its own body.

            If the read moved UP into `EchoelStudioView`, that is the freeze defect: the ~10 Hz \
            playhead would rebuild the body that hosts every `.menu` Picker in the instrument, \
            and an open Picker popover is torn down on every rebuild (10.76.41/50).
            """)
        let studio = try source("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        XCTAssertFalse(studio.contains("transport.position"), """
            `EchoelStudioView` now reads `transport.position` directly.

            That is a ~10 Hz read in the Picker-hosting body — the freeze law. The playhead \
            belongs in `TransportPositionView`, which is why that struct is not `private`.
            """)
    }

    // MARK: - 5. the geometry note survived its host

    /// The `fixedSize` + `minHeight` pair is a law about EVERY chrome bar, and its canonical
    /// statement used to sit on the frame of the bar #456 deleted — while two other frames in
    /// the same file point at it by name. Deleting the bar without moving the note would have
    /// left two live frames citing an explanation that no longer exists.
    func testTheChromeGeometryLawStillHasItsCanonicalStatement() throws {
        let workspace = try source("Sources/Echoelmusic/Studio/WorkspaceView.swift")
        XCTAssertTrue(workspace.contains(".fixedSize(horizontal: false, vertical: true)"), """
            No chrome bar pins its own height any more.

            `.frame(minHeight:)` alone forwards the proposal downward, so a bar hosting any \
            vertically greedy child (an `EchoelValueField`'s bare scrub `Rectangle()`, for one) \
            reports ∞ and splits the screen with `SurfaceHost`. That is what the founder \
            photographed in v10.79.371 (#455).
            """)
    }

    // MARK: - source access

    /// Comment-stripped source, or a skip when the tree is not present.
    ///
    /// `SourceText.codeOnly` (#453) is load-bearing here, not hygienic: this slice's own
    /// comments quote `TransportBar`, `TransportBar()`, `TransportPositionView()` and
    /// `transport.position` in prose — at least four of the five claims below would pass on an
    /// explanation instead of on code without it.
    private func source(_ relativePath: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let path = root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw XCTSkip("source tree not present under \(root.path)")
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }

    /// The brace-matched body that follows `key`, which must end in its opening brace.
    ///
    /// Brace-matched rather than "from here to the next declaration": both files hold several
    /// members whose text would otherwise leak into the scan, and this repo has already paid
    /// for deriving scope from FILE ORDER more than once.
    private func declarationBody(of key: String, in relativePath: String) throws -> String {
        let text = try source(relativePath)
        guard let start = text.range(of: key) else {
            throw MissingAnchor(reason: """
                `\(key)` not found in \(relativePath) — renamed, reflowed or removed. \
                Re-anchor this scan; do not leave it silent.
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
        XCTAssertEqual(depth, 0, "unbalanced braces while extracting `\(key)` — scan is unsound")
        return body
    }
}
