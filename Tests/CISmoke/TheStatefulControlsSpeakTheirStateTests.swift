// TheStatefulControlsSpeakTheirStateTests.swift
// Echoel — #621 (Ultraaccessible-Audit batch A): four verified VoiceOver gaps closed.
//
// WHAT THIS GUARDS. The 2026-08-19 Ultraaccessible audit (founder directive) confirmed
// four completeness gaps, all of the same family — a control whose STATE or NAME is
// visible but unhearable:
//   1. the sound-preset Menu's `.accessibilityLabel` replaced `Text(currentPatch.name)`
//      and no `.accessibilityValue` restored it — the active timbre was unhearable on
//      the ship-gate-2 surface;
//   2. the mood-preset Menu, same class;
//   3. the tuning banner's `.combine` sat on the OUTER HStack and swallowed the
//      "Standard" recovery button (focus + hint) — the control that rescues a
//      wrong-sounding instrument, hidden exactly from the user who cannot see it;
//   4. the "Describe it" TextField had no label, so VoiceOver announced the EXAMPLE
//      placeholder "warm lush pad" as the field's name.
//
// KIND (§1): SOURCE-TEXT SCAN throughout — proves the modifiers sit at the sites, never
// that VoiceOver speaks them correctly. The spoken result is a device probe (registered
// with the next build's probes).
//
// GRADING (#433, parent = the commit before #621): the four fix claims are FORWARD
// (this commit writes them). Counterweights (the banner Button + its hint, the field's
// honesty hint) are green on both trees. The banner's combine-count claim is red on the
// parent for its named reason (the combine existed but on the wrong element — the
// order check distinguishes the two states, not mere presence: #367).
//
// Stripper: delegates to `SourceText.codeOnly` (#453). MEASURED PROPHYLAKTISCH
// (0 of 6 verdicts flip raw vs stripped on either tree): the #621 comments name laws,
// not needles — none quotes an anchor or a modifier spelling that a window contains.
//
// ⚠️ #364: values/labels may be reworded (the value strings derive from live state and
// are not pinned); what is pinned is PRESENCE of the value/label modifier at each site
// and the combine's position before the recovery button. Restructuring stays legal —
// move the needles in the same commit.

import Foundation
import XCTest

final class TheStatefulControlsSpeakTheirStateTests: XCTestCase {

    private func studioLines() throws -> [String] {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let path = root.appendingPathComponent(
            "Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw XCTSkip("source tree not present at \(path.path)")
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    /// Anchor (unique) → the following window, brace-independent (the sites are modifier
    /// chains, not blocks; 8 lines cover the modifier plus its comment-blanked gap).
    private func window(_ lines: [String], after anchor: String, span: Int = 8) throws -> ArraySlice<String> {
        let hits = lines.indices.filter { lines[$0].contains(anchor) }
        XCTAssertEqual(hits.count, 1, """
            `\(anchor)` is no longer unique in EchoelStudioView — re-anchor this check \
            before trusting it (#408).
            """)
        guard let i = hits.first else {
            throw XCTSkip("anchor `\(anchor)` absent — reported by the count assertion above")
        }
        return lines[i ..< min(i + span, lines.count)]
    }

    /// 1+2 — both preset Menus carry an `.accessibilityValue` right after their label.
    func testThePresetMenusSpeakTheirValue() throws {
        let lines = try studioLines()
        for anchor in ["accessibilityLabel(\"Timbre character / sound preset\")",
                       "accessibilityLabel(\"Mood preset\")"] {
            let w = try window(lines, after: anchor)
            XCTAssertTrue(w.contains { $0.contains(".accessibilityValue(") }, """
                the Menu anchored at `\(anchor)` lost its `.accessibilityValue` — its \
                label REPLACES the visible name for VoiceOver, so without the value the \
                active preset is visible but unhearable (Ultraaccessible bar point 3, \
                #621; house pattern = the bio-source Menu's label + value pair).
                """)
        }
    }

    /// 3 — the tuning banner: combine on the TEXT stack (before the recovery button),
    /// glyph hidden, button + hint intact as their own element.
    func testTheTuningBannersRecoveryButtonIsItsOwnElement() throws {
        let lines = try studioLines()
        let declHits = lines.indices.filter { $0 > 0 && lines[$0].contains("private var nonStandardTuningBanner") }
        XCTAssertEqual(declHits.count, 1, "re-anchor: banner decl no longer unique (#408)")
        guard let start = declHits.first else {
            throw XCTSkip("banner decl absent — reported above")
        }
        // The banner is a short @ViewBuilder var; 50 lines cover it with headroom, and
        // the next decl would re-red the uniqueness check above if the shape changed.
        let w = Array(lines[start ..< min(start + 50, lines.count)])
        let combines = w.indices.filter { w[$0].contains("accessibilityElement(children: .combine)") }
        XCTAssertEqual(combines.count, 1, """
            the tuning banner must carry exactly ONE `.combine` — on the two-Text stack. \
            Zero means the texts announce as fragments; two means the outer merge that \
            swallowed the "Standard" recovery button is back (#621, audit finding 3).
            """)
        let button = w.indices.filter { w[$0].contains("Button(\"Standard\")") }
        XCTAssertEqual(button.count, 1, """
            the banner's "Standard" recovery button is gone — it is the one control that \
            rescues a wrong-sounding instrument, and `DetunedInstrumentSaysSoTests` pins \
            its condition; this file pins its accessibility isolation.
            """)
        if let c = combines.first, let b = button.first {
            XCTAssertLessThan(c, b, """
                the `.combine` sits AFTER the "Standard" button in the banner — that is \
                the outer-container merge (#621 audit finding 3): the recovery button \
                loses individual focus and its hint. The combine belongs on the two-Text \
                stack, which closes BEFORE the button.
                """)
        }
        XCTAssertTrue(w.contains { $0.contains(".accessibilityHidden(true)") }, """
            the banner's tuningfork glyph is announced again — it is decoration; hide it \
            so the merged text element leads (#621).
            """)
        // COUNTERWEIGHT — green on both trees: the button's hint survives the reshape.
        XCTAssertTrue(w.contains { $0.contains("Returns to 12-tone equal temperament") }, """
            the "Standard" button's hint is gone from the banner — it is the only place \
            a VoiceOver user learns what "Standard" returns TO.
            """)
    }

    /// 4 — the "Describe it" field has a NAME distinct from its example placeholder.
    ///
    /// Windowed by TWO anchors (start = the TextField, end = its unique sibling
    /// button), not a fixed span: this chain carries 10+ lines of law comments and a
    /// fixed span ages as they grow — the #619b lesson, learned again in transcription
    /// when a 22-line window missed the label at offset 24.
    func testTheDescribeFieldHasAName() throws {
        let lines = try studioLines()
        let startHits = lines.indices.filter { lines[$0].contains("TextField(\"warm lush pad\"") }
        XCTAssertEqual(startHits.count, 1, "re-anchor: the prompt TextField is no longer unique (#408)")
        let endHits = lines.indices.filter { lines[$0].contains("Button { onShape(text) } label: {") }
        XCTAssertEqual(endHits.count, 1, "re-anchor: the field's sibling button is no longer unique (#408)")
        guard let s = startHits.first, let e = endHits.first, s < e else {
            throw XCTSkip("field → sibling span gone — reported by the anchors above")
        }
        let w = lines[s ... e]
        XCTAssertTrue(w.contains { $0.contains(".accessibilityLabel(\"Describe it\")") }, """
            the prompt field lost its `.accessibilityLabel("Describe it")` — VoiceOver \
            then falls back to the placeholder and announces the EXAMPLE phrase "warm \
            lush pad" as the field's NAME (#621, audit finding 4). The label is the \
            row's visible caption — one vocabulary (#616). If the caption was reworded, \
            move label and needle in the same commit.
            """)
        // COUNTERWEIGHT — green on both trees: the honesty hint stays on the field.
        XCTAssertTrue(w.contains { $0.contains(".accessibilityHint(hint)") }, """
            the field's honesty hint is gone — it is the row's mechanism for telling a \
            VoiceOver user which words actually shape the timbre.
            """)
    }
}
