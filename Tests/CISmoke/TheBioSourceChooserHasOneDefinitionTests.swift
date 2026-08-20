// TheBioSourceChooserHasOneDefinitionTests.swift
// Echoel — #616 (GUI-Board Zeile 6, UX#4). `Tests/CISmoke` is the blocking bundle.
//
// WHAT THIS GUARDS. #616 made the bio-source chooser VISIBLE (a "Bio source" row in
// `bioPanel`) and hoisted the three menu entries into ONE definition
// (`BioSourceOption`) shared with the pulse pill's long-press context menu. Four
// laws, each with its own failure mode already paid for elsewhere:
//  (1) the raw ids are the on-the-wire contract with `selectBioSource`'s PRIVATE
//      `BioSourceKind(rawValue:)` guard, which drops anything else SILENTLY — a
//      mismatched id is a menu entry that does nothing (#135 lying-control class);
//  (2) every label starts "Play with" — under bare sensor names this menu was a
//      hidden Start (#234, the founder's "3 Knöpfe zum Start" count);
//  (3) ONE definition, TWO consumers (#416) — inline label copies are how the two
//      surfaces drift apart;
//  (4) the row is mounted where the caption says it is ("Choose your bio source
//      below"), and the pill's menu + its teaching hint survive as the shortcut.
//
// ⚠️ LIMITS (§1): claims 1–2 are END-TO-END BEHAVIOUR on the shipped enum — the
// strong kind. Claims 3–5 are SOURCE-TEXT SCANS: they prove where text sits, not
// that the row renders or the menu opens. Claim 3's label scan covers the
// DEFINITION AND ITS TWO CONSUMERS only — an inline copy in a FOURTH file (an
// onboarding view, WorkspaceView) passes silently; that scope is deliberate
// (#364: scanning all of Sources/ would red every future comment that quotes a
// label), so a new chooser surface must be added to the file list here. Whether the row reads well at AX sizes,
// and whether the Menu opens above the keyboard-free panel, are DEVICE PROBES —
// registered open, not implied covered. `bioPanel` reachability is the Bio chip's
// premise (sibling guards), not re-proven here.
//
// ⚠️ HONEST GRADING (#433/#464), transcribed in Python against the parent
// (b04e0e8) and this tree — worktree 17/17 green, parent 10 red. Claims 1–2 are
// FORWARD (the type is born with #616 — they cannot compile against the parent;
// per §3 ONE finding, #486). Parent reds, by kind: the `enum`/`allCases`/row/
// window needles are the same single absence; TWO reds are the DEFECT ITSELF,
// red on the parent for exactly their named reason — the BLE label counted 2
// there (inline in HeaderMonitors + quoted in the bioPanel caption string), and
// the pill posted `.echoelSelectBioSource` at 3 sites (one per inline button).
// The camera/sim label needles and claim 5's remaining needles (context menu
// presence, "Bio details…", the hold-hint, `selectBioSource(` definition) are
// COUNTERWEIGHTS — green on both trees, and the point of the file.
// Stripper (#453): TRAGEND, MEASURED — 2 of 14 source verdicts flip
// raw-vs-stripped on this tree, and they are the CAMERA and BLE label needles
// (each quoted once in a comment: the pill's own doc block paraphrases the menu,
// and the Routing button's ⛔ block cites the BLE entry verbatim; the stripper
// blanks both, string literals survive). ⛔ The first draft of this paragraph
// GUESSED the two flips as `enum BioSourceOption` and `.contextMenu` — both
// measured 0. A stripper claim without the measurement is the exact retraction
// class §2 documents three of; the numbers above are from the run.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheBioSourceChooserHasOneDefinitionTests: XCTestCase {

    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"
    private static let header = "Sources/Echoelmusic/Studio/HeaderMonitors.swift"
    private static let option = "Sources/Echoelmusic/Studio/BioSourceOption.swift"

    // MARK: - claim 1 (BEHAVIOUR) — the ids ARE the parser's literals

    func testTheIdsMatchTheParsersLiterals() {
        XCTAssertEqual(Set(BioSourceOption.allCases.map(\.rawValue)),
                       ["camera", "ble", "sim"], """
            `BioSourceOption`'s raw values no longer match the literal set \
            `selectBioSource` parses (its private `BioSourceKind(rawValue:)` guard \
            drops unknown ids SILENTLY). A mismatched id is a menu entry that does \
            nothing — the #135 lying-control class. If a fourth source ships, add \
            its case to BOTH enums, this set, and the chooser surfaces together.
            """)
        XCTAssertEqual(BioSourceOption.allCases.count, 3, """
            The chooser offers \(BioSourceOption.allCases.count) entries instead of \
            three. A new source is a product decision (sensor + publisher + \
            lifecycle owner), not a menu edit — wire the publisher first, then \
            widen this count in the same commit.
            """)
    }

    // MARK: - claim 2 (BEHAVIOUR) — every label admits it starts the music

    func testEveryLabelSaysPlayWith() {
        for option in BioSourceOption.allCases {
            XCTAssertTrue(option.menuLabel.hasPrefix("Play with"), """
                "\(option.menuLabel)" dropped the "Play with" prefix. Every entry \
                routes to `selectBioSource`, which STARTS a full generative session \
                when idle — under a bare sensor name this menu is a hidden Start \
                (#234, the founder's "3 Knöpfe zum Start"). Rename freely BEHIND \
                the prefix; the prefix is the honesty.
                """)
        }
        XCTAssertTrue(BioSourceOption.ble.menuLabel.contains("scans for one"), """
            The BLE label lost "scans for one". The music starts from neutral \
            defaults immediately, whether or not a strap is ever found — the label \
            must carry both halves or it promises a measurement it may never get.
            """)
    }

    // MARK: - claim 3 (SOURCE-TEXT) — one definition, two consumers

    func testOneDefinitionTwoConsumers() throws {
        let optionFile = try source(Self.option)
        XCTAssertEqual(optionFile.components(separatedBy: "enum BioSourceOption").count - 1, 1,
                       "BioSourceOption's declaration moved or duplicated — re-anchor (#454).")
        let studio = try source(Self.studio)
        let header = try source(Self.header)
        for (name, code) in [("EchoelStudioView", studio), ("HeaderMonitors", header)] {
            XCTAssertEqual(code.components(separatedBy: "ForEach(BioSourceOption.allCases)").count - 1, 1, """
                \(name) no longer iterates `BioSourceOption.allCases` exactly once. \
                Zero means the surface grew its own inline entry list again (the \
                drift #616 removed); two means a second chooser appeared — widen \
                this guard deliberately with it.
                """)
        }
        // The three labels live ONLY in the definition — an inline copy anywhere
        // else is the drift this file exists to prevent.
        for label in ["Play with camera light",
                      "Play with a Bluetooth strap — scans for one",
                      "Play with the simulation"] {
            var hits = optionFile.components(separatedBy: label).count - 1
            hits += studio.components(separatedBy: label).count - 1
            hits += header.components(separatedBy: label).count - 1
            XCTAssertEqual(hits, 1, """
                "\(label)" appears \(hits) time(s) across the definition and its two \
                consumers; exactly one (in BioSourceOption) is lawful. A second copy \
                is the two-spellings defect (#416); zero means the label changed — \
                change it in BioSourceOption and move this needle in the same commit.
                """)
        }
    }

    // MARK: - claim 4 (SOURCE-TEXT) — the row sits where the caption points

    func testTheRowSitsWhereTheCaptionPoints() throws {
        let studio = try source(Self.studio)
        XCTAssertEqual(studio.components(separatedBy: "private var bioSourceRow: some View {").count - 1, 1,
                       "bioSourceRow declaration missing/duplicated — re-anchor (#454).")
        let row = slice(studio, from: "private var bioSourceRow: some View {", to: "\n    }")
        XCTAssertFalse(row.isEmpty, "bioSourceRow slice empty — re-anchor (#454).")
        XCTAssertEqual(row.components(separatedBy: "selectBioSource(option.rawValue)").count - 1, 1, """
            The row's entries no longer call `selectBioSource` directly. That method \
            is the ONE owner of source switching (BLE-3: a second lifecycle owner \
            killed straps mid-performance) — the row may not grow its own start path.
            """)
        // Mount window: caption ("Choose your bio source below") < row < the always-on strip.
        // All three anchors asserted unique (#408).
        // ⛔ THE RIGHT EDGE MOVED IN #643. It was `Text(AlwaysOnBioChannel.bioPanelSentence)`,
        // rendered by `bioPanel` itself; the sentence had to learn whose channels it names and
        // the flag for that must come from the same frame the rows use — a read `bioPanel` may
        // not do (10.76.41/50) — so it moved into `AlwaysOnBioPanelStrip`, which renders at the
        // same place on screen. The window this claim protects is unchanged in MEANING: the
        // chooser sits between the caption that points at it and the always-on block below.
        for anchor in ["Choose your bio source below",
                       "\n            bioSourceRow\n",
                       "AlwaysOnBioPanelStrip()"] {
            XCTAssertEqual(studio.components(separatedBy: anchor).count - 1, 1,
                           "bioPanel window anchor `\(anchor.prefix(40))` not unique — re-anchor (#408).")
        }
        if let caption = studio.range(of: "Choose your bio source below"),
           let mount = studio.range(of: "\n            bioSourceRow\n"),
           let sentence = studio.range(of: "AlwaysOnBioPanelStrip()") {
            XCTAssertTrue(caption.upperBound <= mount.lowerBound
                            && mount.upperBound <= sentence.lowerBound, """
                `bioSourceRow` is mounted outside the window the caption promises \
                ("Choose your bio source below" → the row must follow that sentence, \
                before the always-on block). Moving the row is fine — \
                move the caption's pointer and this scan with it.
                """)
        }
    }

    // MARK: - claim 5 (SOURCE-TEXT, COUNTERWEIGHTS) — the long-press shortcut survives

    func testThePillShortcutSurvives() throws {
        let header = try source(Self.header)
        XCTAssertEqual(header.components(separatedBy: ".contextMenu {").count - 1, 1, """
            The pulse pill lost its long-press context menu. The row in bioPanel is \
            the DISCOVERABLE door; the pill's menu is the performer's shortcut and \
            the only chooser reachable without opening a panel — removing it is a \
            product decision, not a cleanup.
            """)
        XCTAssertEqual(header.components(separatedBy: "Bio details…").count - 1, 1, """
            The "Bio details…" entry left the pill's menu. It is the one place a \
            VoiceOver user exploring the menu learns the bio panel exists — the \
            three entries above it are all commitments to start playing.
            """)
        XCTAssertEqual(header.components(separatedBy: "Touch and hold to choose a bio source.").count - 1, 1, """
            The pill's accessibilityHint no longer teaches the long-press exactly \
            once. With the bioPanel caption's old instruction retired (#616), this \
            hint is the last teacher of the shortcut — keep exactly one (zero makes \
            the gesture invisible; a second copy is the drift this file forbids).
            """)
        // The chrome stays notification-decoupled: the pill posts, never calls.
        XCTAssertEqual(header.components(separatedBy:
            "NotificationCenter.default.post(name: .echoelSelectBioSource,").count - 1, 1, """
            The pill's entries no longer post `.echoelSelectBioSource` (or post it \
            twice). HeaderMonitors is a chrome leaf — it names the choice; the \
            studio owns the publishers and the switch (BLE-3 one-owner law).
            """)
        let studio = try source(Self.studio)
        XCTAssertEqual(studio.components(separatedBy: "private func selectBioSource(").count - 1, 1, """
            `selectBioSource` moved or duplicated — it is the ONE owner both \
            chooser surfaces route to; re-anchor this file and the row's call scan.
            """)
    }

    // MARK: - helpers (§0/§2 — the ONE stripper, skip on no tree, FAIL on moved anchors)

    private func slice(_ code: String, from: String, to: String) -> String {
        guard let start = code.range(of: from),
              let end = code.range(of: to, range: start.upperBound..<code.endIndex) else {
            return ""
        }
        return String(code[start.lowerBound..<end.lowerBound])
    }

    private struct AnchorMissing: Error { let reason: String }

    private func source(_ relativePath: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources").path) else {
            throw XCTSkip("source tree not present under \(root.path)")
        }
        let path = root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw AnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — renamed or \
                moved. Re-anchor this scan; do not let it skip (#454).
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }
}
