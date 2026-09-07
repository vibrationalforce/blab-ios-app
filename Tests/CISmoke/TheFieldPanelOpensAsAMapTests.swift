import XCTest
@testable import Echoelmusic

/// #1068 — the Field panel opens as a MAP, not as a wall.
///
/// FOUNDER, 2026-09-07: *"Es geht vorallem darum das alle Funktionen von Field kompakt und
/// übersichtlich bleiben."* Measured on the tree that ask landed on: the panel carried **27**
/// numeric fields, two switches and roughly seventeen explanatory sentences in ONE scroll. Every
/// one of them is a function he asked for at some point, so the compaction may not delete
/// anything — what it removes is the requirement to scroll past all of it to reach any of it.
///
/// The mechanism is the "Fine tune" disclosure promoted to a helper and applied to the three
/// group headings. Look opens by default; Voice and Self-play start closed.
///
/// ⚠️ WHAT THIS FILE CANNOT SEE. It renders no SwiftUI, so "it now fits on a screen" is the
/// founder's look. What it pins is that the headings really are disclosures, that they carry a
/// VoiceOver value (a chevron is invisible to a screen reader), and — the half that matters most
/// for this ask — that the compaction did not quietly become a deletion.
final class TheFieldPanelOpensAsAMapTests: XCTestCase {

    private func studio() throws -> String {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            if FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("Package.swift").path) { break }
            dir = dir.deletingLastPathComponent()
        }
        let url = dir.appendingPathComponent("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("ANCHOR MISSING: EchoelStudioView.swift could not be read — a missing "
                    + "anchor is a finding, not a pass.")
            return ""
        }
        return text
    }

    // 1 — all three groups are disclosures, through ONE helper. Two spellings of one control is
    // how they drift apart; `groupHeader` learned that in #362.
    func testTheThreeGroupsAreDisclosuresThroughOneHelper() throws {
        let code = SourceText.codeOnly(try studio())
        for title in ["\"Look\"", "\"Voice\"", "\"Self-play\""] {
            XCTAssertTrue(code.contains("collapsibleGroupHeader(\(title), isOpen:"), """
                The \(title) group is not a disclosure any more. The founder's ask for this pass \
                is that all of Field stays "kompakt und übersichtlich" while keeping every \
                function — a group that cannot close is a group you must scroll past. If the \
                heading was renamed, re-anchor this needle in the same commit.
                """)
        }
        XCTAssertTrue(code.contains("private func collapsibleGroupHeader("), """
            The shared disclosure helper is gone. Three hand-written copies of one control is \
            exactly the drift `groupHeader` was introduced to end (#362).
            """)
    }

    // 2 — the disclosure speaks to VoiceOver. A chevron carries the state VISUALLY only, which
    // is the gap #241 closed elsewhere and the reason `showVisualFineTune`'s row carries a value.
    func testTheDisclosureSaysWhetherItIsOpen() throws {
        let code = SourceText.codeOnly(try studio())
        guard let start = code.range(of: "private func collapsibleGroupHeader(") else {
            XCTFail("helper not found — re-anchor claim 2 with claim 1.")
            return
        }
        let body = SourceText.codeWindow(code, from: start.lowerBound, lines: 24)
        XCTAssertTrue(body.contains("accessibilityValue("), """
            The group disclosure has no `accessibilityValue`. Open and closed then sound \
            identical to VoiceOver — the chevron is the only difference and a screen reader \
            cannot see it (#241).
            """)
        XCTAssertTrue(body.contains("minHeight: 44"), """
            The disclosure lost its 44 pt tap target. Without it the hit area is the ~16 pt the \
            11 pt label and 10 pt chevron occupy (#113), and the control the whole panel now \
            depends on becomes the hardest thing in it to press.
            """)
    }

    // 3 — COMPACTION, NOT DELETION. This is the claim the founder's sentence actually asks for:
    // "alle Funktionen … bleiben". A named sample from each group, so a future "tidy-up" that
    // removes a control instead of folding it goes red here rather than on his device.
    func testEveryGroupStillCarriesItsControls() throws {
        let code = SourceText.codeOnly(try studio())
        let mustSurvive = [
            // Look
            "visualLookStrip(showsDonutState: true)",
            "Toggle(isOn: $touchShowGrid)",
            "Toggle(isOn: $spectralDonuts)",
            // Voice
            "EchoelValueField(label: \"Level\"",
            "EchoelValueField(label: \"Glide\"",
            "EchoelValueField(label: \"Position morph\"",
            "touchSyncRows",
            // Self-play
            "fieldSelfPlaySection",
            "fieldVoiceControls",
        ]
        for needle in mustSurvive {
            XCTAssertTrue(code.contains(needle), """
                `\(needle)` is gone from the Field panel. #1068 collapsed the groups precisely \
                so that nothing had to be removed to make the panel readable — the founder's \
                ask names both halves ("alle Funktionen … kompakt und übersichtlich"). If this \
                control was deliberately retired, that is a separate decision and needs its own \
                commit and its own line in the plan, not a quiet drop inside a layout change.
                """)
        }
    }

    // 4 — the defaults ARE the compaction. Opening all three by default would leave the panel
    // exactly as long as before, with three extra chevrons.
    func testVoiceAndSelfPlayStartClosed() throws {
        let code = SourceText.codeOnly(try studio())
        for (flag, value) in [("showFieldLook", "true"),
                              ("showFieldVoice", "false"),
                              ("showFieldSelfPlay", "false")] {
            XCTAssertTrue(code.contains("@State private var \(flag) = \(value)"), """
                `\(flag)` no longer defaults to \(value). The defaults are what makes this a \
                compaction: Field opens showing two buttons, the look controls and two named \
                headings. All three open by default would be the old wall with chevrons on it; \
                all three closed would hide the look controls the panel is mostly about.
                """)
        }
    }
}
