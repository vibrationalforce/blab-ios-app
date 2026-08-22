// TheBreathPlaySwitchHasNoDoorTests.swift
// Echoel — a knob whose doc comment describes a control nobody built. #724.
//
// WHAT WAS WRONG. `BioReactiveSynthVoice.breathPlayEnabled` is `public var … = true` and its
// doc comment ended "Toggle off for pure manual play". Measured across `Sources/`: exactly
// ONE assignment, the declaration itself; zero `$breathPlayEnabled` bindings; zero
// `.toggle()` calls. Nothing can turn it off, so the two-condition gate in
// `consumeBioEventsIfFresh` — `guard isArmed, breathPlayEnabled, !heldByController` — is
// effectively one condition, and the sentence described a capability with no producer. That
// is the same shape CLAUDE.md records for `.motion`, `.eegBurst` and the tempo modulation
// route: an engine that runs to the last centimetre with no surface at the end of it.
//
// ⭐ THE ENGINE HALF IS REAL, AND THAT IS THE POINT OF CLAIM 3. The consumer reads the flag
// on every bio event, so a door is one control away. This is a knob waiting for a surface,
// not dead code — and the counterweight exists so that "clean up the unused flag" cannot pass
// green. Deleting the read is the one change this guard is designed to make red.
//
// ⚠️ IT FORBIDS NOTHING (#364). Giving the flag a door is exactly the work the finding argues
// for; whether it SHOULD have one ("breathe with me" vs "manual only", next to the Body-voice
// arm switch #277) is a founder question, not this file's. On the day a writer appears,
// claim 2 goes red BY DESIGN, and the repair is to move the ⛔ block in
// `BioReactiveSynthVoice.swift` in the SAME commit (#456) — not to relax the assertion.
//
// ⚠️ CLAIM 1 IS SCOPED, NOT A BARE ABSENCE SCAN (#525). The corrected comment QUOTES the
// withdrawn sentence in order to withdraw it, so a plain `contains` would be red on correct
// code, and `codeOnly` cannot rescue it — the text lives in a comment on both trees and the
// stripper blanks it either way. Per line: any line carrying the phrase must also carry
// `SAID`, the same shape `TheAudioLanesHaveNoProducerTests` uses for its header claim.
//
// ⚠️ EVERY NEEDLE IS ANCHORED (#367/#408). A scan that finds nothing passes green forever
// while the defect ships — this session paid for that three times (#705, #711, #716), and
// `scripts/doctor.py` now mechanically reports declaration-shaped needles that name nothing.
// Claims 3 and 4 are the anchors: they assert the declaration and the consuming guard are
// PRESENT before anything is concluded from their absence elsewhere.
//
// ⚠️ AND THE LIMIT FIRST. Nothing here plays audio or proves anything about breath on a
// device. It proves that no line in `Sources/` can turn this flag off, and that a sentence
// and that measurement agree. `Tests/CISmoke` is the blocking bundle; a missing tree SKIPS
// rather than reporting a green it did not earn (#454).

import Foundation
import XCTest
@testable import Echoelmusic

final class TheBreathPlaySwitchHasNoDoorTests: XCTestCase {

    private static let voice = "Sources/Echoelmusic/Tools/BioReactiveSynthVoice.swift"

    // MARK: - 1: the comment no longer promises a control

    func testTheDocNoLongerPromisesAToggle() throws {
        let phrase = "Toggle off for pure manual play"
        let offenders = try rawText(Self.voice)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { $0.contains(phrase) && !$0.contains("SAID") }
        XCTAssertTrue(offenders.isEmpty, """
            `BioReactiveSynthVoice` promises again that you can "\(phrase)", outside a \
            retraction:
            \(offenders.joined(separator: "\n"))
            Nothing in `Sources/` writes `breathPlayEnabled`. If a control HAS been built, \
            claim 2 is red in this same run and the ⛔ block above the declaration is the work.
            """)
    }

    // MARK: - 2: THE FINDING — no line in Sources/ can turn it off

    func testNothingInSourcesWritesTheFlag() throws {
        let writers = try productionWriters()
        XCTAssertTrue(writers.isEmpty, """
            `breathPlayEnabled` now has a writer outside its own declaration: \
            \(writers.joined(separator: ", ")).

            That is GOOD NEWS if it is a real door — this guard forbids building one (#364). \
            The repair is not to relax this assertion: move the ⛔ block above the declaration \
            in `BioReactiveSynthVoice.swift` in the SAME commit (#456), because it states in \
            the present tense that the flag is permanently true.
            """)
    }

    // MARK: - 3: COUNTERWEIGHT — the consumer still reads it

    /// Without this, "delete the unused flag" would pass claim 2 trivially. The engine half is
    /// what makes the finding a missing DOOR rather than dead code.
    func testTheConsumerStillReadsTheFlag() throws {
        let code = try codeOf(Self.voice)
        XCTAssertTrue(code.contains("guard isArmed, breathPlayEnabled, !heldByController"), """
            The breath-event gate no longer reads `breathPlayEnabled`.

            If the flag was DELETED, this finding changed shape: it was "a knob with no door", \
            and removing the knob answers a founder question (breathe-with-me vs manual-only) \
            that was never asked. If the gate was merely reformatted, re-anchor this needle on \
            the new spelling — an unanchored scan is the #367 defect this file exists to avoid.
            """)
    }

    // MARK: - 4: ANCHOR — the declaration is present and is a settable knob

    func testTheDeclarationIsPresentAndPublic() throws {
        let code = try codeOf(Self.voice)
        XCTAssertTrue(code.contains("public var breathPlayEnabled = true"), """
            `public var breathPlayEnabled = true` is not in \(Self.voice).

            Claims 1-3 all reason about this declaration; without it they would pass by \
            scanning for something that is not there. Re-derive the needle from the real \
            declaration rather than deleting this claim.
            """)
    }

    // MARK: - helpers

    /// Files under `Sources/` that assign the flag, bind it, or toggle it — excluding the
    /// declaring file, whose single assignment IS the declaration.
    private func productionWriters() throws -> [String] {
        let base = try repoRoot().appendingPathComponent("Sources")
        guard let walker = FileManager.default.enumerator(atPath: base.path) else {
            throw XCTSkip("cannot walk Sources/")
        }
        // Three shapes, because one regex would miss the two that matter most in SwiftUI:
        // a `$binding` handed to a Toggle, and `.toggle()` on the property itself (#713).
        let needles = ["breathPlayEnabled =", "breathPlayEnabled=",
                       "$breathPlayEnabled", "breathPlayEnabled.toggle()"]
        var hits: [String] = []
        var seen = 0
        for case let rel as String in walker where rel.hasSuffix(".swift") {
            seen += 1
            if rel.hasSuffix("BioReactiveSynthVoice.swift") { continue }
            let text = SourceText.codeOnly(
                try String(contentsOf: base.appendingPathComponent(rel), encoding: .utf8))
            if needles.contains(where: { text.contains($0) }) { hits.append(rel) }
        }
        guard seen > 200 else {
            throw XCTSkip("""
                only \(seen) Swift files walked under Sources/; the tree holds well over three \
                hundred, so this walk saw a partial checkout and would report a green it did \
                not earn (#454)
                """)
        }
        return hits.sorted()
    }

    private func codeOf(_ relativePath: String) throws -> String {
        SourceText.codeOnly(try rawText(relativePath))
    }

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
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources").path) else {
            throw XCTSkip("source tree not present under \(root.path)")
        }
        return root
    }
}
