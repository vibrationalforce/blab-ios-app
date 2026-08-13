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
// ⛔ WHERE THE DOOR IS NOW (#290, 2026-07-31). The transport-bar "•••" entry this file was
// originally written against is GONE — that panel is a permanent chip. Two of the four tests
// here went red on it, and the honest repair was to re-point them at the chip rather than
// delete them: what #272 protects is that saving and recording are NAMED before the panel
// opens, not the particular control that did the naming. Each rewritten test carries the
// refutation at its own site.
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

    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"

    /// ⭐ THE ONE STRING THE FOUNDER ACTUALLY READ — now on a CHIP, not in the "•••".
    ///
    /// ⛔ THE DOOR MOVED, IT DID NOT DISAPPEAR (#290, 2026-07-31). This test used to scan
    /// `WorkspaceView.swift` for `door: "export"` — the transport-bar overflow entry. #290
    /// promoted four of those six entries to permanent chips, so that entry (and the
    /// `case "export":` receiver it posted to) is gone by design, and the two tests that
    /// pinned them went red on `a7b50e8`/`098e661`.
    ///
    /// Deleting them was the wrong repair: #272's protection is not "the overflow menu
    /// contains a string", it is **saving and recording are NAMED before the panel opens**.
    /// A permanent chip satisfies that more strongly than a buried menu entry did. So the
    /// guard is re-pointed at what carries the naming today — the chip label, its VoiceOver
    /// `fullName`, and the fact that `.export` is actually IN the standing strip. Take any
    /// of the three away and the founder is back to hunting for controls that exist.
    ///
    /// ⛔ AND THE WORD "RECORD" WAS REQUIRED HERE UNTIL #482 (2026-08-07), one commit AFTER
    /// it stopped being true. #482 moved Record, keep-last, Export MIDI, Save and Open out
    /// of this panel into `quickActionRow` — permanent tiles that name themselves — and left
    /// `fullName` promising four controls the panel no longer holds. **The guard had flipped
    /// from protecting an honest string to pinning a false one, silently green**, which is
    /// worse than no guard: the next session reads a passing assertion as evidence. The
    /// asserted words now name what the panel really settles, and "record" is not among them
    /// BY DESIGN — the recording control moved to a place where it needs no door to announce
    /// it. "loop" replaces it because the loop length Record uses is still in here and is the
    /// one thing that tile cannot say about itself. (#272's protection is unchanged: the
    /// door names what is behind it. Only what is behind it changed.)
    func testTheSaveExportChipNamesSavingAndRecording() throws {
        let label = try exportReturn(inProperty: "label")
        XCTAssertTrue(label.lowercased().contains("save"), """
        the Save/Export chip label no longer says "Save": \(label)
        That single word is what the founder searched for and did not find (#272). The chip \
        is the only place this panel is named before it opens, so the word has to be here.
        """)

        let fullName = try exportReturn(inProperty: "fullName")
        for word in ["save", "loop"] {
            XCTAssertTrue(fullName.lowercased().contains(word), """
            the Save/Export chip's VoiceOver name no longer says "\(word)": \(fullName)
            The 12 pt chip cannot carry everything behind it, so `fullName` is where a \
            VoiceOver user learns what the panel actually settles before opening it.
            """)
        }
    }

    /// The chip has to be in the STANDING strip. `label`/`fullName` are only reached if the
    /// menu is on screen at all, and `.export` is not reachable from anywhere else since the
    /// "•••" entry went away — `visibleChips` appends `displayedMenu` only once something has
    /// already selected it.
    ///
    /// ⭐ THE PREMISE NARROWED WITH #568 AND IS WHOLE AGAIN SINCE #572. For one build a
    /// maturity filter hid every chip but Sound on the first three launches, so "the standing
    /// strip" meant "the strip at maturity". The founder rejected that on device — *"Du hast
    /// mega viel gelöscht"* — and the filter is gone, so this assertion once again proves the
    /// door is on screen for every user on every launch. The episode is worth the four lines:
    /// a guard whose premise quietly narrows is the failure mode §4 names, and this one
    /// narrowed and widened again inside two days.
    func testTheSaveExportChipIsInTheStandingStrip() throws {
        let lines = try codeLines(Self.studio)
        guard let strip = lines.first(where: { $0.contains(".sound, .effects") }) else {
            XCTFail("the explicit `studioChips` array is gone from \(Self.studio). If the "
                    + "strip is built some other way now, move this guard with it — do not "
                    + "delete it, it is the only thing proving Save/Export has a door at all.")
            return
        }
        XCTAssertTrue(strip.contains(".export"), """
        `.export` is no longer in the standing chip strip: \(strip.trimmingCharacters(in: .whitespaces))
        Since #290 removed the transport-bar "•••" entry, this array is the ONLY door to that \
        panel. ⛔ This message used to add "…the panel that holds Save, Open, Record and \
        keep-last"; #482 moved those four into `quickActionRow`, so dropping the chip no \
        longer strands them. What it DOES strand is everything they need and cannot say \
        themselves: the loop length Record uses, the keep-last availability sentence, the \
        place toggle that shapes the save name, Reset sound and Diagnostics. Still #272, \
        smaller blast radius — and the tiles would keep working while their settings became \
        unreachable, which is the harder version to notice.
        """)
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

    /// ⛔ AND THE FLAG THAT MUST NOT COME BACK. The first cut of #272 wrote
    /// `showExport = true` in the chrome door, believing the panel opened collapsed. It does
    /// not: `menuPanelHost` applies `.environment(\.echoelPanelForceOpen, true)` and
    /// `EchoelPanel.body` then ignores its `isExpanded` binding entirely. The write only
    /// stamped `true` into a persisted key nothing honours — harmless today, and a door that
    /// silently undoes a user's collapse the day `forceOpen` goes away.
    ///
    /// ⛔ THE ORIGINAL SHAPE OF THIS TEST IS GONE, and that is why it went red on
    /// `a7b50e8`/`098e661`: it scanned the `case "export":` line of the `.echoelChromeDoor`
    /// receiver, and #290 deleted that case along with the only control that posted it. The
    /// hazard did not go with it — `showExport` is still declared and still passed as an
    /// `isExpanded:` binding, so the next person to add a door can still "helpfully" write
    /// it. Widened from one line to the whole file: nothing may ASSIGN it.
    func testNothingWritesTheDeadDisclosureFlag() throws {
        let lines = try codeLines(Self.studio)
        // The declaration itself assigns (`private var showExport = false`) and is excluded
        // by its `@AppStorage` attribute, which sits on the same physical line. The live
        // read — `isExpanded: $showExport` — carries no `=` and needs no exclusion.
        let writes = lines.filter {
            $0.contains("showExport") && $0.contains("=") && !$0.contains("@AppStorage")
        }
        // Built as a local `let` rather than inline in the message: a `map`+`joined` chain
        // inside a string interpolation inside an assert argument is how #287 blew the Swift
        // type-checker's budget and reddened this very bundle (`3379bb3`, HARNESS_LEDGER).
        let offenders = writes.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
        XCTAssertTrue(writes.isEmpty, """
        something assigns `showExport` again:
        \(offenders)

        The studio dropdown forces every panel open, so this changes nothing visible and \
        persists a value no reachable control can undo. If `echoelPanelForceOpen` was \
        removed deliberately, fix this guard and the #272 comments in the SAME commit — \
        `testTheDropdownStillForcesItsPanelsOpen` is the one that catches that case.
        """)
    }

    /// The `return` line of one `StudioMenu` case inside ONE computed property of the enum.
    ///
    /// ⚠️ REGION-SCOPED ON PURPOSE. `case .export:` appears three times in this file — the
    /// chip label, the VoiceOver `fullName`, and the panel builder (`return AnyView(utilityRow)`).
    /// A whole-file filter would conflate them, and a guard on "the label" could then pass on
    /// a match that is really the panel content — a green earned by the wrong line is the
    /// failure mode this whole bundle exists to prevent.
    private func exportReturn(inProperty property: String) throws -> String {
        let lines = try codeLines(Self.studio)
        guard let start = lines.firstIndex(where: { $0.contains("var \(property): String {") }) else {
            XCTFail("`StudioMenu.\(property)` is gone from \(Self.studio) — if the chip naming "
                    + "moved somewhere else, move this guard with it rather than deleting it.")
            return ""
        }
        // The property's own closing brace: eight spaces at the enum's member indentation.
        // Stopping there is what keeps `fullName`'s region from running to end-of-file.
        let end = lines[(start + 1)...].firstIndex { $0 == "        }" } ?? lines.endIndex
        guard let hit = lines[start..<end].first(where: { $0.contains("case .export:") }) else {
            XCTFail("`StudioMenu.\(property)` has no `.export` case any more. Since #482 that "
                    + "panel holds the loop length, the place-in-the-name toggle, Reset sound "
                    + "and Diagnostics; an unnamed door to them is #272.")
            return ""
        }
        return hit.trimmingCharacters(in: .whitespaces)
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
