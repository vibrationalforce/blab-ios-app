// TheMetronomeAccentHasADoorTests.swift
// Echoel — the one metronome option whose three siblings all had a row. #924.
//
// WHAT WAS WRONG. `MetronomeVoice` exposes four settable options. Three have controls in
// `metronomeRow` (the Tempo panel): `enabled`, `beatsPerBar`, `level`. The fourth,
// `accentDownbeat`, had **no writer anywhere under `Sources/`** — found by
// `scripts/doorless-state.py`, which flags settable class state with no door.
//
// ⭐ WHY THIS ONE IS DIFFERENT FROM THE OTHER 22 UNGUARDED ENTRIES ON THAT LIST, and the
// distinction is the whole reason it was worth a slice. Measured 2026-08-31: of the 33 hits, 10
// already carry a guard and the rest are DSP tuning constants (`inharmonicity`, `fmRatio`,
// `onsetNoiseDecay` …) in files like `EchoelCellular` and `EchoelModalBank`, which are
// TEST-ONLY and have no production path at all. The tool's own rule sorts them: *a tuning
// constant with no writer is fine, a knob whose doc names a user who cannot turn it is the
// defect.* `accentDownbeat` is neither of those exactly — its doc names no user — but it is a
// third thing the rule implies: **an option sitting beside three siblings that all have rows,
// in a panel the player can open.** Absence there reads as a decision nobody made.
//
// ⭐ AND IT IS THE ONE THAT MAKES A SIBLING AUDIBLE. `beatsPerBar` only means something because
// beat 0 sounds different; the render block's test is
// `let isDownbeat = (beatIndex == 0) && audioAccent`. With the accent off, "Beats per bar"
// becomes an invisible setting — so the two rows belong together, and shipping the number
// without the switch was the asymmetry.
//
// ⚠️ NOT A NEW FEATURE. Every layer already existed and was already reachable-by-default: the
// property, its `didSet` mirror to the `nonisolated(unsafe)` audio value, and the render-block
// read. This slice adds a door to built behaviour, which is why it is a Ralph-sized change and
// not a product question.
//
// ⚠️ A `Bool` IS A `Toggle`, NOT AN `EchoelValueField`, and that is the UI law read correctly.
// CLAUDE.md's parameter rule says every adjustable NUMERIC parameter uses `EchoelValueField`,
// and warns in the same breath: read the word "numeric" — a parameter whose values have names
// is a Picker, and by the same logic an on/off is a Toggle. The sibling `enabled` row is a
// `Toggle`; this matches it rather than inventing a 0/1 number field.
//
// ⚠️ HONEST GRADING (#433/#464/#486). This file COMPILES against the parent tree, so every
// claim has a verdict there. **Two are red on the parent** — the row and its placement, which
// is the finding. **Three are counterweights** (#343), green on both: they catch a tree that
// adds the row but breaks the chain that makes it audible, or that converts the Bool into a
// number field, or that moves the row outside the `enabled` block where it would be the
// "adjustable but inaudible" control this repo keeps removing (#135/#164/#227).
//
// ⚠️ WHAT NO TEST HERE CAN SAY: whether a player wants the accent off. The switch is offered,
// the default is unchanged (on), and nothing about the shipped sound moves until someone taps.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheMetronomeAccentHasADoorTests: XCTestCase {

    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"
    private static let voice = "Sources/Echoelmusic/Audio/MetronomeVoice.swift"

    // MARK: - the door

    func testTheAccentRowExistsAndBindsTheVoice() throws {
        let code = SourceText.codeOnly(try rawText(Self.studio))
        XCTAssertTrue(code.contains("Toggle(isOn: $metronome.accentDownbeat"), """
            No control writes `accentDownbeat`. It is the only one of MetronomeVoice's four \
            settable options without a row, while `enabled`, `beatsPerBar` and `level` all have \
            one in the same panel — and it is the option that makes `beatsPerBar` audible at all.
            """)
    }

    func testTheAccentRowSitsInsideTheEnabledBlock() throws {
        let code = SourceText.codeOnly(try rawText(Self.studio))
        guard let rowStart = code.range(of: "if metronome.enabled {") else {
            return XCTFail("`metronomeRow` no longer gates its detail rows on `metronome.enabled`.")
        }
        let after = code[rowStart.upperBound...]
        // The accent row must appear in the gated block, before that block's closing depth.
        var depth = 1
        var index = after.startIndex
        var body = ""
        while index < after.endIndex, depth > 0 {
            let ch = after[index]
            if ch == "{" { depth += 1 }
            if ch == "}" { depth -= 1; if depth == 0 { break } }
            body.append(ch)
            index = after.index(after: index)
        }
        XCTAssertTrue(body.contains("$metronome.accentDownbeat"), """
            The accent control is outside the `if metronome.enabled` block, so it is offered \
            while the click is silent. That is the "adjustable but inaudible" control this repo \
            keeps removing (#135/#164/#227) — the sibling rows are inside for exactly that reason.
            """)
    }

    // MARK: - counterweights: the row must move sound, and stay a switch

    func testTheAccentStillMirrorsToTheAudioValue() throws {
        let code = SourceText.codeOnly(try rawText(Self.voice))
        XCTAssertTrue(code.contains("didSet { audioAccent = accentDownbeat }"), """
            `accentDownbeat` no longer mirrors into `audioAccent`. The property is `@MainActor` \
            observable state and the render block cannot read it directly, so without this \
            `didSet` the new control is decorative — a switch that changes a number nobody hears.
            """)
    }

    func testTheRenderBlockStillReadsTheAudioValue() throws {
        let code = SourceText.codeOnly(try rawText(Self.voice))
        XCTAssertTrue(code.contains("(beatIndex == 0) && audioAccent"), """
            The click no longer decides its downbeat from `audioAccent`. That single expression \
            is what connects the new switch to sound AND what makes `beatsPerBar` meaningful; \
            without it both rows are settings with no consequence.
            """)
    }

    /// ⛔ THE FIRST DRAFT OF THIS CLAIM WAS RED ON A CORRECT TREE, and only driving it showed
    /// that. Its needle was `EchoelValueField(label: "Accent"` — and `EchoelStudioView` already
    /// has TWO of those, for the field-arp accent and the pad accent, both genuinely numeric
    /// (0…1) and both unrelated to the click. **A needle taken from a LABEL collides with every
    /// other row that happens to use the same word**; the needle has to name the BINDING, which
    /// is unique. Same class as #921b's bare type-name needle, one window apart — the second
    /// time in this session, so it is written down as a pattern rather than an accident.
    func testTheSwitchIsAToggleAndNotANumberField() throws {
        let code = SourceText.codeOnly(try rawText(Self.studio))
        XCTAssertFalse(code.contains("value: $metronome.accentDownbeat"), """
            The accent was wired through a value field rather than a switch. CLAUDE.md's
            parameter rule covers adjustable NUMERIC parameters and says in the same breath to \
            read that word: a named choice is a Picker, and an on/off is a Toggle — its sibling \
            `enabled` row is one. A 0/1 number field here would obey the rule's letter against \
            its purpose.
            """)
    }

    // MARK: - helpers

    private func rawText(_ relativePath: String) throws -> String {
        let path = try repoRoot().appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw XCTSkip("""
                \(relativePath) is not present — this guard inspects source text, so it SKIPS \
                rather than reporting a green it did not earn (#454)
                """)
        }
        return try String(contentsOf: path, encoding: .utf8)
    }

    private func repoRoot() throws -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
