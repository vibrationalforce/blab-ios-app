// TheGuideNamesOnlyRealControlsTests.swift
// Echoel — a guide that names a control the app does not have teaches people the app is broken. #589.
//
// WHAT THIS GUARDS. `LearnSection.guide` ("Start Here") is the founder-asked way in — "ein
// leichtes Eintauchen … für alle Sinne — hörbar, sichtbar und spürbar". Its entries NAME shipping
// controls, verbatim, and every named control is a join this file enforces: the guide half lives
// in `LearnLibrary.guideEntries`, the control half in the UI source, and a rename on either side
// without the other is the first-instruction defect this repo has already paid for — #351's
// camera hint promised something untrue at the exact moment it was shown, and the file's own
// comment records what that costs: a new user who follows a wrong instruction and sees nothing
// concludes the app is broken, not that the guide is stale.
//
// ⭐ THE SENSE CLAIMS THEMSELVES WERE VERIFIED BEFORE THE COPY WAS WRITTEN, at these producers —
// re-verify here rather than trusting this header if any goes away:
//   · hörbar — the Play path (`startBiofeedback`), and "Body voice" (`BreathVoiceRow`, the one
//     production caller of `BioReactiveSynthVoice.arm()`; #586 made it survive backgrounding).
//   · sichtbar — the fullscreen visual is the LAUNCH state since #580; `TouchInstrumentView`
//     mounts at every window size; Reduce Motion freezes `uniforms.time`.
//   · spürbar — "Haptic beat (feel)" (`hapticsRow`, `HapticController.beat()` per quarter-note,
//     LIVE since #552) inside the "Tempo & variations" panel; the sub-bass "feel it" line.
//
// ⚠️ HONEST LIMITS. 6 tests, 13 assertion statements (`grep -c`; two loop). Tests 1–4 are
// END-TO-END over the shipped `LearnLibrary` values. Tests 5–6 are SOURCE-TEXT joins. What no
// test here can prove: that the guide READS as easy immersion — that is the founder's device
// probe (open Learn, first section, all three senses in under a minute). NEEDS-FOUNDER-VERIFY.
//
// ⭐ GRADING (§3). This file names `LearnSection.guide`/`guideEntries`, created by this same
// commit — it does NOT COMPILE against the parent; no assertion has a verdict there
// (transcribed instead: the joins' UI-side needles are all green on both trees, because the
// controls pre-exist — the guide is the new half. ONE forward-looking finding, not a
// regression, honestly booked as such: nothing here was red on the parent for a defect reason;
// the parent simply had no guide). Stripper on the two source scans: PROPHYLAKTISCH
// (0 of 5 needles flip, measured raw vs. stripped on both trees — all five are UI literals that
// appear in code, quoted nowhere in prose on the scanned files).

import Foundation
import XCTest
@testable import Echoelmusic

final class TheGuideNamesOnlyRealControlsTests: XCTestCase {

    // MARK: - END-TO-END over the shipped library

    /// The guide opens the library. `LearnView` renders `allCases` in declaration order, so
    /// first case = first thing a newcomer sees — that placement IS the founder's ask.
    func testTheGuideIsTheFirstSection() {
        XCTAssertEqual(LearnSection.allCases.first, .guide)
        XCTAssertEqual(LearnSection.guide.title, "Start Here")
        XCTAssertFalse(LearnLibrary.guideEntries.isEmpty)
        XCTAssertEqual(LearnLibrary.entries(for: .guide), LearnLibrary.guideEntries)
    }

    /// All three senses the founder named must be present as entries — the redundancy is the
    /// accessibility design ("any one of them is a way in"), so losing one sense entry is not
    /// a copy edit, it is the feature narrowing.
    func testAllThreeSensesArePresent() {
        let ids = Set(LearnLibrary.guideEntries.map(\.id))
        for required in ["guide.hear", "guide.see", "guide.feel", "guide.access"] {
            XCTAssertTrue(ids.contains(required),
                          "The guide lost \(required) — hörbar, sichtbar und spürbar was the "
                          + "whole ask, and the access entry is what makes the redundancy "
                          + "explicit for users who rely on one sense.")
        }
    }

    /// The precondition ORDER is the #351 lesson and must survive rewording: the camera reads
    /// nothing before Play, so the pulse entry must put the music first.
    func testThePulseEntryPutsTheMusicFirst() throws {
        let pulse = try XCTUnwrap(LearnLibrary.guideEntries.first { $0.id == "guide.pulse" })
        XCTAssertTrue(pulse.detail.contains("After you press Play"),
                      "The camera has one owner and it starts with the music. An instruction "
                      + "that works only after a precondition must NAME the precondition — "
                      + "#351 is what it cost when this surface promised otherwise.")
        XCTAssertTrue(pulse.summary.contains("Start the music first"))
    }

    /// The red line, at the surface most tempted to cross it. Practice and self-observation
    /// language only — no healing vocabulary in any guide entry, in any of the three fields.
    /// (End-to-end over runtime VALUES, so this cannot collide with prose that mentions the
    /// banned words in comments — the #491 trap does not apply to compiled strings.)
    /// ⛔ THE FIRST DRAFT OF THIS LIST CONTAINED BARE `"heal"` AND WAS RED ON CORRECT COPY —
    /// the substring matches "Apple **Heal**th", which the pulse entry legitimately names as a
    /// source. A guard that turns a correct sentence red gets deleted, and the law goes with it
    /// (#364). Caught by driving the scan before pushing; the list now carries the inflected
    /// forms, none of which is a substring of "Health".
    func testTheGuideMakesNoHealingClaim() {
        for entry in LearnLibrary.guideEntries {
            let text = (entry.title + " " + entry.summary + " " + entry.detail).lowercased()
            for banned in ["healing", "heals ", "heilung", "heilen", "chakra", "solfeggio",
                           "therapy", "therapeutic", "cure", "medicine"] {
                XCTAssertFalse(text.contains(banned), """
                Guide entry "\(entry.id)" contains "\(banned)". Vocal toning and haptics are \
                described as practice and self-observation (the Body Science precedent); the \
                healing theme is a hard product red line, and the guide is the surface most \
                likely to drift across it one adjective at a time.
                """)
            }
        }
    }

    // MARK: - SOURCE-TEXT joins: every named control must exist, verbatim

    func testEveryNamedControlExistsInTheStudio() throws {
        let studio = try source("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        for control in ["Text(\"Haptic beat (feel)\")",
                        "panel(\"Tempo & variations\"",
                        "Text(\"Body voice\")"] {
            XCTAssertTrue(studio.contains(control), """
            The guide names a control this source no longer contains: \(control). Rename the \
            control and the guide entry in `LearnLibrary.guideEntries` in the SAME commit — a \
            guide pointing at a missing control is the #351 defect returned.
            """)
        }
    }

    func testTheVisualControlsTheGuideDescribesExist() throws {
        let window = try source("Sources/Echoelmusic/Studio/FloatingVisualWindow.swift")
        XCTAssertTrue(window.contains("Text(\"Studio\")"),
                      "The guide's first entry routes a newcomer to the \"Studio\" chip.")
        XCTAssertTrue(window.contains("TouchInstrumentView(key:"),
                      "\"Touch it to play notes\" is a guide claim; the play surface must "
                      + "still mount on the picture.")
    }

    // MARK: - source access (§0/§2 — one stripper, skip on no tree, FAIL on a moved anchor)

    private struct GuideAnchorMissing: Error { let reason: String }

    private func source(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        let path = root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw GuideAnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — renamed or moved. \
                Re-anchor this scan; do not let it skip (#454).
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }
}
