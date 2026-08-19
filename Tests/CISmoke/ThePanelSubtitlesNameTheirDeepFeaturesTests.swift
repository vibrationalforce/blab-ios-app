// ThePanelSubtitlesNameTheirDeepFeaturesTests.swift
// Echoel — the two buried features are NAMED where a player scans (#620, UX#12/13).
//
// WHAT THIS GUARDS (GUI-Board Zeile 10). Two of the instrument's best capabilities were
// undiscoverable by scanning: "Follow the key" (the harmonizer's in-key mode) sits TWO
// levels deep — Effects panel → "All parameters" sheet → Harmonizer section — and
// "Voice timbre" (the instrument learns your voice's colour, #592) sits one level down
// in the Sound panel. Nothing above either named them. #620 puts each feature's EXACT
// control words into its panel's subtitle, so the pointer and the control share one
// spelling (#616's vocabulary law: a pointer with different words teaches a search that
// fails).
//
// KIND (§1): SOURCE-TEXT SCAN throughout. It proves the words sit on the panel lines and
// that each pointer's target control still exists under the same name — never that the
// subtitle renders, that the sheet opens, or that a player finds anything. Those stay
// device probes.
//
// GRADING (#433, parent = the commit before #620): the two subtitle claims are FORWARD
// (the tokens are written by the same commit — red on the parent for their named reason,
// never before). The two coupling counterweights (the toggle in EchoelFXView, the row's
// Text in this file) are green on BOTH trees and are the point: renaming a control
// without moving its pointer reds the pair together, in whichever direction the drift
// runs.
//
// Stripper: delegates to `SourceText.codeOnly` (#453). MEASURED TRAGEND (1 of 4 verdicts
// flips raw vs stripped, on the worktree): the #620 comment above the Sound panel quotes
// `Text("Voice timbre")` verbatim, so the ==1 uniqueness of the row's declaration is 2
// raw and 1 stripped — exactly the class codeOnly exists for. The two subtitle checks
// anchor on the `panel("…"` call lines themselves and cannot be flipped by prose.
//
// ⚠️ #364: the tokens are pinned, not the sentences. Rewording either subtitle stays
// legal while it keeps its feature's control-spelled name; renaming a CONTROL is legal
// too — together with its subtitle token and this file's needles, in one commit.
//
// #620b (review, 0 CRITICAL / 3 WARN / 3 LOW — all taken): W1 the single-line anchor
// would have redded a legal reformat — `declSlice` now joins the anchor with its next
// two continuation lines (the `WeatherIsAMoodRubricTests` precedent); W2 the failure
// message described a "collapsed panel line" that does not exist (these panels mount
// force-open in the dropdown — the honest gain is the subtitle being the opened panel's
// FIRST line); W3 the source comment's claim about the FX-door guard is corrected at
// the site. L1: a vanished decl is one absence — the token check skips instead of
// double-reporting (#486). Stripper re-measured after the reshape: still TRAGEND 1/4,
// same needle (the source comment quoting the row literal).

import Foundation
import XCTest

final class ThePanelSubtitlesNameTheirDeepFeaturesTests: XCTestCase {

    private func codeLines(of relPath: String) throws -> [String] {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let path = root.appendingPathComponent(relPath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw XCTSkip("source tree not present at \(path.path)")
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    /// #620b (review W1): the first version required title and subtitle on ONE physical
    /// line — the exact shape #619b had just hardened another guard away from, and this
    /// very slice wrapped the soundPanel call. Joining the anchor line with its next two
    /// continuation lines follows the sturdier precedent
    /// (`WeatherIsAMoodRubricTests.testTheSaveExportSubtitleNamesTheCity`), so a legal
    /// reformat cannot red the token check (#364).
    private func declSlice(_ lines: [String], anchor: String) throws -> String {
        let hits = lines.indices.filter { lines[$0].contains(anchor) }
        XCTAssertEqual(hits.count, 1, """
            `\(anchor)` is no longer unique in its file — re-anchor before trusting the \
            subtitle check (#408).
            """)
        // #620b (review L1): a vanished decl is ONE absence — skip instead of failing a
        // second assertion over the same missing anchor (#486).
        guard let start = hits.first else {
            throw XCTSkip("anchor `\(anchor)` absent — reported by the count assertion above")
        }
        return lines[start ..< min(start + 3, lines.count)].joined(separator: " ")
    }

    /// The Sound panel's subtitle names "Voice timbre" — with the row's own words.
    func testTheSoundSubtitleNamesTheVoiceTimbre() throws {
        let lines = try codeLines(of: "Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        let decl = try declSlice(lines, anchor: "panel(\"Sound & texture\",")
        // #620b (review W2): the first message said "the collapsed panel line" — these
        // panels have NO collapsed state (they mount only through `dropdownContent`
        // under `echoelPanelForceOpen`, always-open header). The honest gain: the
        // subtitle is the FIRST line of the opened panel, so the feature is named one
        // level up instead of being visible only at the row itself.
        XCTAssertTrue(decl.contains("Voice timbre"), """
            the Sound panel's subtitle no longer names "Voice timbre" (UX#13, #620): it \
            is the first line a player reads when the Sound dropdown opens, and the one \
            surface above the capture row that names the feature. If the ROW was \
            renamed, rename the subtitle token and this needle in the same commit — the \
            words must match the control (#616).
            """)
    }

    /// COUNTERWEIGHT — the pointer's target: the capture row still declares itself with
    /// the same words. Green on both trees; red the day the row is renamed or removed
    /// while the subtitle still points at it.
    func testTheVoiceTimbreRowStillExists() throws {
        let lines = try codeLines(of: "Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        XCTAssertEqual(lines.filter { $0.contains("Text(\"Voice timbre\")") }.count, 1, """
            `Text("Voice timbre")` is gone or duplicated in EchoelStudioView — the Sound \
            panel's subtitle points at this row by name. Removing or renaming the row \
            without moving the subtitle leaves a pointer to a control that does not \
            exist; move both in one commit.
            """)
    }

    /// The Effects panel's subtitle names "Follow the key" — with the toggle's own words.
    func testTheEffectsSubtitleNamesFollowTheKey() throws {
        let lines = try codeLines(of: "Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        let decl = try declSlice(lines, anchor: "panel(\"Effects\",")
        XCTAssertTrue(decl.contains("Follow the key"), """
            the Effects panel's subtitle no longer names "Follow the key" (UX#12, #620): \
            the harmonizer's in-key toggle sits two levels deep (Effects → All \
            parameters → Harmonizer), and this subtitle is the only surface above it \
            that names it. If the TOGGLE was renamed, rename the subtitle token and \
            this needle in the same commit — the words must match the control (#616).
            """)
    }

    /// COUNTERWEIGHT — the pointer's target: the harmonizer toggle still exists under
    /// the same name in the FX sheet. Green on both trees.
    func testTheFollowTheKeyToggleStillExists() throws {
        let lines = try codeLines(of: "Sources/Echoelmusic/Studio/EchoelFXView.swift")
        XCTAssertEqual(lines.filter { $0.contains("Toggle(\"Follow the key\"") }.count, 1, """
            `Toggle("Follow the key"` is gone or duplicated in EchoelFXView — the Effects \
            panel's subtitle points at this toggle by name (#620). Removing or renaming \
            it without moving the subtitle leaves a pointer to a control that does not \
            exist; move both in one commit (and #599b's restore law rides on the toggle's \
            OFF action — read its comment before touching it).
            """)
    }
}
