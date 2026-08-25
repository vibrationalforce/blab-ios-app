// TheDeviceChecklistOnlyAsksWhatExistsTests.swift
// Echoel — #816: the founder's ONE device checklist asked for four things that cannot be
// done at all, and nothing in the repo could say so.
//
// WHY THIS EXISTS. `scratchpads/FOUNDER_DEVICE_SESSION.md` was written 2026-07-16 to bundle
// every device-bound question into a single session, because the founder is the only device
// tester and device time is this project's scarcest resource. Measured 2026-08-25, four of its
// seven sections asked for probes on surfaces that no longer exist: the piano-roll editor
// (`struct PianoRollView` deleted, #475), a drum lane (`DrumSynthVoice`/`LaneDrumKitVoice`/
// `DrumNoteMap` deleted, #166/#167), an AUv3 host test (target removed 2026-07-24), a
// `laneAUInstruments` flag (zero occurrences in `Sources`+`Tests`), and a warp hearing test in
// an audio-clip editor whose door went with #121 Slice 4.
//
// ⭐ THE DEFECT CLASS IS #525 AT DOCUMENT SCALE. That entry names the cost exactly: "ein
// Verify-Posten, der auf ein entferntes Bedienelement zeigt, kostet den Founder eine
// Geräteprobe, die nichts entscheiden kann". Here it was not one item but four sections, and
// the reason it survived is structural rather than careless: `scripts/founder-verify.py`
// deliberately does NOT scan `scratchpads/` (its own head: scratchpads are session prose, not
// asks). So this file was a SECOND checklist that the tool printing the founder's shopping
// list could not see, and no guard watched. Claim 4 pins that exclusion, because it is the
// whole reason the document now has to carry a pointer to the tool.
//
// ⚠️ THE SCAN IS SCOPED TO CHECKBOX ITEMS, and that is not fussiness — it is #491. The
// document's ⛔ table QUOTES every struck name in order to withdraw it, so a naive
// file-wide negative scan would match its own retraction and go red on a correct tree. An ask
// is a checkbox; the retraction is prose. An item is the `- [ ]` line plus its indented
// continuation lines, because the ask is written across both (the old `laneAUInstruments`
// entry ran to a second line).
//
// ⚠️ HONEST LIMIT, and it runs toward FALSE GREENS. The needle list is FIXED and names five
// surfaces known to be gone. A stale ask about some sixth deleted surface passes unseen. This
// guard makes the KNOWN rot impossible to re-introduce; it does not make the document
// self-checking. The only real fix for that would be markers the tool can scan, which is the
// direction the rewritten document points.
//
// ⛔ THE OPPOSITE ERROR IS THE ONE I ACTUALLY MADE, and this guard can encourage it. The
// first draft of the rewritten checklist deleted the four impossible sections AND seven asks
// that are perfectly performable (multiRoll double lane, bass at A≠440, poly unchanged, stuck
// note on a mid-take instrument change, live same-region change, silent launch), on the
// reasoning that they "belong in the NEEDS-FOUNDER-VERIFY markers". Measured: the tool covers
// none of them, and nothing had been written there. **A removal justified by "it belongs
// elsewhere" is only a removal once the move has happened.** Claim 1 going red means the ask
// names a surface that is GONE — it never means an ask should be dropped because it is
// inconvenient. If the surface exists, the ask stays.
//
// #364 — NOTHING HERE FORBIDS A RETURN. If the roll, the drums, an AUv3 target or a clip
// editor is rebuilt, claim 2 goes red on purpose and its message names the ⛔ table as the
// prose to update in the same commit; the checklist may then ask for that probe again.
//
// KIND (§1): **REGRESSION, source-text scans.** Claim 1 would have fired on each deletion
// commit — the document already named these surfaces, so the moment the code went, the guard
// goes red. It is graded as a real regression guard for this defect, not a preventive one.

import XCTest

final class TheDeviceChecklistOnlyAsksWhatExistsTests: XCTestCase {

    /// Surfaces measured absent on 2026-08-25, spelled the way the old checklist spelled them.
    /// Every needle was driven against the pre-#816 document before it shipped: all five match
    /// there (six findings across four asks) and none matches the rewritten one.
    private static let struckSurfaces = [
        "laneAUInstruments",
        "AUv3",
        "Drums-Spur",
        "Audio-Clip-Editor",
        "Velocity-Lane"
    ]

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

    /// The `- [ ]` line plus the indented lines that continue it. No force unwrap: every
    /// branch binds `current` with `if let`, per the repo-wide ban.
    private func checkboxAsks(in document: String) -> [String] {
        var asks: [String] = []
        var current: String?
        for line in document.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- [ ]") {
                if let open = current { asks.append(open) }
                current = trimmed
            } else if let open = current, line.hasPrefix("      "), !trimmed.isEmpty {
                current = open + " " + trimmed
            } else if let open = current, !line.hasPrefix(" ") {
                asks.append(open)
                current = nil
            }
        }
        if let open = current { asks.append(open) }
        return asks
    }

    // 1 — no ASK names a surface that no longer exists.
    func testNoDeviceAskPointsAtARemovedSurface() throws {
        let doc = try text("scratchpads/FOUNDER_DEVICE_SESSION.md")
        let asks = checkboxAsks(in: doc)
        XCTAssertGreaterThan(asks.count, 3,
            "The checklist parsed to \(asks.count) asks. Either the file lost its content or "
            + "the `- [ ]` convention changed — in both cases this guard is measuring nothing.")
        for ask in asks {
            for surface in Self.struckSurfaces {
                XCTAssertFalse(ask.contains(surface),
                    "The founder is asked to test \"\(surface)\", which does not exist: "
                    + "\(ask.prefix(90))… Device time is the scarcest resource in this project "
                    + "(#525) — either remove the ask or, if the surface came back, move it out "
                    + "of the ⛔ table in the same commit.")
            }
        }
    }

    // 2 — the struck surfaces really are gone, so claim 1 fails for its named reason (#367).
    func testTheStruckSurfacesAreStillAbsentFromTheApp() throws {
        let recovery = "If this is red because the surface RETURNED, that is correct and "
            + "expected (#364): update the ⛔ table in scratchpads/FOUNDER_DEVICE_SESSION.md "
            + "in the same commit, and the checklist may ask for its probe again."

        let roll = try text("Sources/Echoelmusic/Studio/PianoRollView.swift")
        XCTAssertFalse(roll.contains("struct PianoRollView"),
                       "The note editor is back. \(recovery)")
        XCTAssertTrue(roll.contains("PianoRollModel"),
                      "PianoRollModel is the note engine and the MusicalFrame publisher — if it "
                      + "left this file, this guard is reading the wrong anchor.")

        let fm = FileManager.default
        for gone in ["Sources/Echoelmusic/Tools/DrumSynthVoice.swift",
                     "Sources/Echoelmusic/Sequencer/LaneDrumKitVoice.swift",
                     "Sources/Echoelmusic/Sequencer/DrumNoteMap.swift"] {
            XCTAssertFalse(fm.fileExists(atPath: root().appendingPathComponent(gone).path),
                           "\(gone) exists again. \(recovery)")
        }

        let project = try text("project.yml")
        let declaresAUv3 = project.components(separatedBy: "\n").contains {
            $0.trimmingCharacters(in: .whitespaces) == "EchoelmusicAUv3:"
        }
        XCTAssertFalse(declaresAUv3, "An AUv3 target is declared again. \(recovery) "
                       + "(The name also occurs in a comment on the line that records its "
                       + "removal — only a bare target key counts, which is why this is an "
                       + "equality test and not a substring search.)")
    }

    // 3 — the document routes a reader to the tool instead of being a second list.
    func testTheChecklistPointsAtTheToolThatScansTheCode() throws {
        let doc = try text("scratchpads/FOUNDER_DEVICE_SESSION.md")
        XCTAssertTrue(doc.contains("scripts/founder-verify.py"),
            "The checklist must name the tool that prints the code-anchored asks. Without that "
            + "pointer it is again a second list, which is how it rotted for two months.")
        XCTAssertTrue(doc.contains("NEEDS-FOUNDER-VERIFY"),
            "The checklist must name the marker convention, so a reader knows which asks live "
            + "in the code and which live here.")
    }

    // 4 — the tool really does exclude scratchpads, which is WHY claim 3 is needed.
    func testTheToolDeliberatelyDoesNotScanScratchpads() throws {
        let tool = try text("scripts/founder-verify.py")
        XCTAssertTrue(tool.contains("ROOTS = [\"Sources\", \"Tests\", \"CLAUDE.md\"]"),
            "founder-verify.py's ROOTS line changed. If scratchpads/ was ADDED, the rewritten "
            + "checklist's framing ('the tool cannot see this file') is now false and must be "
            + "corrected in the same commit.")
    }
}
