// TheWorkBoardDoesNotQueueDeletedSurfacesTests.swift
// Echoel — #819: the board a session is told to pull work from had nine rows pointing at
// surfaces that no longer exist.
//
// WHY THIS EXISTS. `.claude/skills/baustellen/SKILL.md` says: read the board, pull the top open
// slice. `scratchpads/BAUSTELLEN_BOARD.md` calls itself "die eine Übersicht". It was last kept on
// 2026-07-21; since then #121 Slice 4 (clips + arrangement), #166/#167 (drums), #475 (the note
// editor) and the 2026-07-24 AUv3 removal deleted the surfaces NINE of its waiting rows still
// name — including A1, the FIRST row a session would pull. Measured 2026-08-25:
// `git grep -l launchGlyphOverlay -- Sources` → 0, `git grep -n "RollChordStamp(" -- Sources` → 0
// construction sites, no AUv3 target in `project.yml`, no clip-editor door.
//
// ⭐ SAME DEFECT CLASS AS #816, ONE LEVEL UP. That slice fixed a checklist that spent the
// founder's DEVICE time on impossible probes. This one is a queue that spends a SESSION's cycle
// on impossible work — and it is worse in one respect: the board presents itself as the single
// overview, so a session that trusts it never looks for the live queue at all.
//
// ⚠️ SCOPE IS THE THREE WAITING TABLES, and it has to be. The board's law is that nothing is
// deleted — its ERLEDIGT and audit tables name the removed surfaces on purpose, forever. A
// file-wide negative scan would match the board's own history (#491). A row counts as LIVE only
// while it carries no VOID marker, which is exactly the annotation this slice added.
//
// ⛔ TWO ANCHOR FAULTS IN THE FIRST DRAFT, both caught by DRIVING and neither by re-reading:
// 1. The range was taken with `split("## AKTIV")`, and the board's new status paragraph NAMES
//    "## AKTIV" in prose — so the range opened inside the documentation of the guard and
//    collapsed to three rows. Headings are matched at LINE START here for that reason.
// 2. Fixing that dropped the needle count from six to three, because resetting at every `## `
//    heading also closed the range at `## OFFEN`. **A needle set that suddenly stops matching is
//    a signal that the SCOPE moved, not that the file got clean** — the tempting read is the
//    reassuring one. All six needles are driven against the pre-#819 board: 8 findings over 8
//    rows, and zero over the annotated one.
//
// #364 — NOTHING HERE FORBIDS A RETURN. If clips, the roll or an AUv3 target come back, the
// matching row stops being void and the VOID marker has to go; this guard then goes red and says
// so, which is the correct moment to re-open that row.
//
// KIND (§1): **REGRESSION, source-text scans.** Claim 1 would have fired on each deletion
// commit — the rows already named these surfaces.

import XCTest

final class TheWorkBoardDoesNotQueueDeletedSurfacesTests: XCTestCase {

    /// Spelled the way the BOARD spells them, not the way the code does — every one is driven
    /// against the pre-#819 board and matches there.
    private static let deletedSurfaces = [
        "AUv3", "launchGlyphOverlay", "Audio-Clip-Editor",
        "RollChordStamp", "Velocity-Lane", ".patch(lane)"
    ]

    /// The three tables that mean "someone still has to act on this".
    private static let waitingTables = ["## AKTIV", "## OFFEN", "## BLOCKIERT"]

    private func root() -> URL {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            if FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("Package.swift").path) { return dir }
            dir = dir.deletingLastPathComponent()
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func text(_ relative: String) throws -> String {
        let url = root().appendingPathComponent(relative)
        guard let s = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("ANCHOR MISSING: \(relative) could not be read. This guard fails rather "
                    + "than skips (§4) — a missing anchor is a finding, not a pass.")
            return ""
        }
        return s
    }

    /// Table rows inside the waiting tables that carry no VOID marker.
    private func liveRows(in board: String) -> [String] {
        var rows: [String] = []
        var inside = false
        for line in board.components(separatedBy: "\n") {
            if line.hasPrefix("## ") {
                inside = Self.waitingTables.contains { line.hasPrefix($0) }
                continue
            }
            guard inside else { continue }
            let row = line.trimmingCharacters(in: .whitespaces)
            guard row.hasPrefix("|") else { continue }
            guard !row.hasPrefix("|---"), !row.hasPrefix("| # |") else { continue }
            guard !row.contains("VOID") else { continue }
            rows.append(row)
        }
        return rows
    }

    // 1 — no row still waiting for action names a surface that is gone.
    func testNoWaitingRowNamesADeletedSurface() throws {
        let board = try text("scratchpads/BAUSTELLEN_BOARD.md")
        let rows = liveRows(in: board)
        XCTAssertGreaterThan(rows.count, 5, """
            The waiting tables parsed to \(rows.count) live rows. Either the board lost its \
            content or its headings changed — in both cases this guard is measuring nothing. \
            The range is matched at LINE START on \(Self.waitingTables); prose naming those \
            headings must not open a range (that was the first draft's fault).
            """)
        for row in rows {
            for surface in Self.deletedSurfaces {
                XCTAssertFalse(row.contains(surface), """
                    A waiting row still queues work on "\(surface)", which no longer exists: \
                    \(row.prefix(90))… Mark the row VOID with its measurement (the board deletes \
                    nothing), or — if the surface came back — remove the marker and update this \
                    guard in the same commit.
                    """)
            }
        }
    }

    // 2 — the surfaces really are gone, so claim 1 fails for its named reason (#367).
    //
    // ⛔ THE FIRST DRAFT CHECKED TWO NAMED FILES and would have passed while its own premise was
    // false — a symbol reintroduced anywhere else in `Sources/` was invisible to it. A claim that
    // can pass on a broken premise is not a claim. It walks the tree now.
    func testTheQueuedSurfacesAreStillAbsentFromTheApp() throws {
        let recovery = "If this is red because the surface RETURNED, that is correct (#364): "
            + "un-void the matching board row in the same commit."
        let sources = root().appendingPathComponent("Sources")
        guard let walk = FileManager.default.enumerator(atPath: sources.path) else {
            XCTFail("ANCHOR MISSING: Sources/ could not be walked. This guard fails rather than "
                    + "skips (§4).")
            return
        }
        var swiftFiles = 0
        var offenders: [String] = []
        for case let relative as String in walk where relative.hasSuffix(".swift") {
            let url = sources.appendingPathComponent(relative)
            guard let body = try? String(contentsOf: url, encoding: .utf8) else { continue }
            swiftFiles += 1
            for symbol in ["launchGlyphOverlay", "RollChordStamp("] where body.contains(symbol) {
                offenders.append("\(relative): \(symbol)")
            }
        }
        XCTAssertGreaterThan(swiftFiles, 300, """
            Walked only \(swiftFiles) Swift files under Sources/ — the walk is broken, so the \
            absence it reports means nothing.
            """)
        XCTAssertTrue(offenders.isEmpty, """
            A queued surface is constructed again: \(offenders.joined(separator: ", ")). \(recovery)
            """)

        let project = try text("project.yml")
        let declaresAUv3 = project.components(separatedBy: "\n").contains {
            $0.trimmingCharacters(in: .whitespaces) == "EchoelmusicAUv3:"
        }
        XCTAssertFalse(declaresAUv3, "An AUv3 target is declared again. \(recovery)")
    }

    // 3 — the board says where the live queue actually is.
    func testTheBoardPointsAtTheLiveQueue() throws {
        let board = try text("scratchpads/BAUSTELLEN_BOARD.md")
        for pointer in ["scripts/founder-verify.py",
                        "scratchpads/FOUNDER_DEVICE_SESSION.md",
                        ".deploy/release"] {
            XCTAssertTrue(board.contains(pointer), """
                The board must name \(pointer). It calls itself "die eine Übersicht" while being \
                a month behind; without these pointers a session trusting it never looks for the \
                queue that is actually current.
                """)
        }
    }
}
