// SaveDoorNamingTests.swift
// Echoel — #272. The founder reported "Session speichern und Loops aufnehmen fehlt" about
// four controls that were already built: Save, Open, Record and keep-last all live in
// `utilityRow`. Nothing on the path to them said so — the transport-bar menu entry read
// "Export — WAV loop" and the panel title read "Export". Naming was the whole defect.
//
// This is the third time this exact shape has cost a cycle: #59 (weather and place were
// wired, every string that advertised them said something else), #188 (MIDI export restored
// but its door invisible until the subtitle named it), now #272. What each of those fixes
// changed was a STRING, and a string is exactly what silently drifts back — someone
// shortens a chip to fit, or "tidies" a subtitle.
//
// ⚠️ WHY A SOURCE SCAN. `StudioMenu` and `utilityRow` are `private` members of a view;
// `@testable import` grants `internal`, not `private`, and there is no simulator here, so
// nothing in this bundle can instantiate the surface. The realistic regression is textual,
// and a textual check catches exactly it. The house pattern is `ChromeDynamicTypeTests`.
//
// ⛔ HONEST LIMIT, stated because the first version of the #272 commit message claimed the
// opposite ("NOT unit-testable in this bundle") and used that to ship unguarded: this proves
// the WORDS are present in the source. It cannot prove the menu entry is reachable, that the
// panel renders, or that any of it is legible on a device. Do not read a green here as "the
// founder can find Save".
//
// ⚠️ It scans SOURCE TEXT: if the checkout is not at the path this file was compiled from it
// SKIPS rather than passes — a silent pass on an unscanned tree is the `continue-on-error`
// lie the `doctor` skill exists to catch.

import Foundation
import XCTest

final class SaveDoorNamingTests: XCTestCase {

    /// Repo root, derived from this file's compile-time path (`Tests/CISmoke/…` → up two).
    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()   // CISmoke
            .deletingLastPathComponent()              // Tests
            .deletingLastPathComponent()              // repo
        let sources = root.appendingPathComponent("Sources/Echoelmusic")
        guard FileManager.default.fileExists(atPath: sources.path) else {
            throw XCTSkip("source tree not present at \(sources.path) — this test inspects "
                          + "source text, so it SKIPS rather than reporting a green it did "
                          + "not earn")
        }
        return root
    }

    /// Every line of `path` that is not a whole-line comment. Comments are dropped because
    /// both files QUOTE the old "Export — WAV loop" spelling in their own prose so the
    /// history stays legible — matching those would pass on the very drift this guards.
    private func codeLines(_ path: String) throws -> [String] {
        let url = try repoRoot().appendingPathComponent(path)
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
    }

    private static let workspace = "Sources/Echoelmusic/Studio/WorkspaceView.swift"
    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"

    /// ⭐ THE ONE STRING THE FOUNDER ACTUALLY READ. The transport-bar "•••" entry is the only
    /// place this panel is named before it opens, so it has to carry both words he used.
    func testTheTransportDoorNamesSavingAndRecording() throws {
        let lines = try codeLines(Self.workspace)
        let entry = lines.filter { $0.contains(#"door: "export""#) }
        XCTAssertFalse(entry.isEmpty,
                       "the export chrome door is gone from \(Self.workspace) — if it moved, "
                       + "move this guard with it rather than deleting it")
        for line in entry {
            XCTAssertTrue(line.lowercased().contains("save"),
                          "the transport-bar entry for the export door no longer says "
                          + "\"Save\": \(line.trimmingCharacters(in: .whitespaces)). That single "
                          + "word is what the founder searched for and did not find (#272).")
            XCTAssertTrue(line.lowercased().contains("record"),
                          "the transport-bar entry no longer says \"record\": "
                          + "\(line.trimmingCharacters(in: .whitespaces)). Loop recording lives "
                          + "in that panel and this is the only place it is named before "
                          + "the panel opens.")
        }
    }

    /// The panel behind that door must agree with it. A door promising "Save" onto a panel
    /// headed "Export" is the same defect one step further in.
    ///
    /// ⛔ THE COMMA IS LOAD-BEARING, and leaving it out is how the first version of this file
    /// went red in CI. `utilityRow` ends with `}   // panel("Save & Export")` — a
    /// block-closing marker whose line does not START with `//`, so `codeLines` keeps it, and
    /// it contains the bare prefix. The count was 2, not 1. Matching the CALL (title followed
    /// by a comma, since `panel` always takes a subtitle) excludes the marker without having
    /// to strip trailing comments, which cannot be done safely — `//` occurs inside string
    /// literals.
    func testThePanelTitleAgreesWithTheDoor() throws {
        let lines = try codeLines(Self.studio)
        let title = lines.filter { $0.contains(#"panel("Save & Export","#) }
        XCTAssertEqual(title.count, 1,
                       "the utility panel is no longer titled \"Save & Export\". If it was "
                       + "renamed deliberately, the transport-bar entry and the chip label "
                       + "have to move in the SAME commit — that mismatch is #272.")
    }

    /// ⛔ AND THE FLAG THAT MUST NOT COME BACK. The first cut of #272 also wrote
    /// `showExport = true` in this door, believing the panel opened collapsed. It does not:
    /// `menuPanelHost` applies `.environment(\.echoelPanelForceOpen, true)` and
    /// `EchoelPanel.body` then ignores its `isExpanded` binding entirely. The write only
    /// stamped `true` into a persisted key nothing honours — harmless today, and a door that
    /// silently undoes a user's collapse the day `forceOpen` goes away.
    func testTheExportDoorDoesNotWriteTheDeadDisclosureFlag() throws {
        let lines = try codeLines(Self.studio)
        let door = lines.filter { $0.contains(#"case "export":"#) }
        XCTAssertFalse(door.isEmpty, "the export door case is gone — move this guard with it")
        for line in door {
            XCTAssertFalse(line.contains("showExport"),
                           "the export door writes `showExport` again: "
                           + "\(line.trimmingCharacters(in: .whitespaces)). The dropdown forces "
                           + "every panel open, so this changes nothing visible and persists a "
                           + "value no reachable control can undo.")
        }
    }

    /// The environment flag the finding above rests on. If someone removes `forceOpen` from
    /// the dropdown host, the disclosure bindings become live again — and the reasoning in
    /// the three comments this slice left behind stops being true. Fail loudly there rather
    /// than let those comments quietly become the wrong-reason kind CLAUDE.md warns about.
    func testTheDropdownStillForcesItsPanelsOpen() throws {
        let lines = try codeLines(Self.studio)
        XCTAssertTrue(lines.contains { $0.contains(#"echoelPanelForceOpen, true"#) },
                      "the studio dropdown no longer forces its panels open. Every "
                      + "`isExpanded` binding in it is live again, including `showExport`, "
                      + "which persists as false — so the export door now really does land "
                      + "on a collapsed panel, and the #272 comments explaining why it "
                      + "cannot are stale. Fix the door and those comments together.")
    }
}
