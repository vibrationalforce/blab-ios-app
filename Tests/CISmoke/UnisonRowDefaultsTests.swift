// UnisonRowDefaultsTests.swift
// Echoel — #281. `unisonVoices` / `unisonDetuneCents` are the engine's single biggest
// thin→rich lever, and until this slice their only editor was `PatchEditorView.swift` — a
// file with ZERO instantiation sites, queued for deletion by #132 Slice 6. Deleting it would
// have removed the last way to reach two persisted parameters, which is a capability loss
// wearing a cleanup's clothes. The rows now live in `soundPanel`, behind the Sound chip.
//
// ⭐ WHAT THIS FILE ACTUALLY PINS, and it is not "the rows exist". It is that TWO FILES AGREE
// on one number. `PolySynthVoice.apply` plays an unspecified patch with `?? 2` voices at
// `?? 7` cents — so a row that displays `?? 1` and `?? 0` (which is what `PatchEditorView`
// did) shows you something other than what you hear, and the first drag jumps the sound
// before the number moves. The port fixed that by mirroring the engine's fallbacks. Nothing
// but a cross-file check can keep them mirrored: change the engine default alone and every
// other test in the repo stays green while the readout starts lying again.
//
// ⚠️ WHY A SOURCE SCAN. `soundPanel` and both bindings are `private` members of a view;
// `@testable import` grants `internal`, not `private`, and there is no simulator in this
// environment. The realistic regression is textual and a textual check catches exactly it.
// House pattern: `ChromeDynamicTypeTests`, `SaveDoorNamingTests`.
//
// ⛔ HONEST LIMIT: this proves the rows are WRITTEN and the two fallbacks match. It cannot
// prove the panel renders them, that the chip reaches it, or that unison sounds right. That
// is device-verified only.

import Foundation
import XCTest

final class UnisonRowDefaultsTests: XCTestCase {

    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"
    private static let poly = "Sources/Echoelmusic/Tools/PolySynthVoice.swift"

    /// ⛔ THE OTHER HALF OF "the readout agrees with the ear", found in review AFTER the first
    /// version of this file shipped without it. Two genre patches persist `uni: 4` while
    /// `EchoelPolyDDSP.maxUnison` is 3 and `setUnison` clamps to it — and `EchoelValueField`
    /// clamps on WRITE only, never on display. Without a clamp in the GETTER those patches
    /// showed "4" while three voices played: the identical defect this slice set out to end,
    /// one field over. The row's own `range:` does not catch it, which is why this is checked
    /// separately from the row's existence.
    func testTheVoicesRowCannotDisplayMoreVoicesThanTheEnginePlays() throws {
        let studio = try codeLines(Self.studio)
        XCTAssertTrue(studio.contains { $0.contains("Swift.min(currentPatch.unisonVoices ?? 2,") },
                      "the Voices row no longer clamps its READ to the engine's maximum. Any "
                      + "patch storing more than `EchoelPolyDDSP.maxUnison` voices — two genre "
                      + "patches do — now displays a number the engine will not play.")
        let engine = try codeLines("Sources/Echoelmusic/DSP/EchoelDDSP.swift")
        XCTAssertTrue(engine.contains { $0.contains("unisonCount = min(max(count, 1), Self.maxUnison)") },
                      "EchoelPolyDDSP no longer clamps `setUnison` to `maxUnison`. If the "
                      + "ceiling moved or went away, the Sound panel's read-clamp has to move "
                      + "with it — otherwise the row starts hiding voices instead of inventing "
                      + "them, which is the same lie mirrored.")
    }

    /// Repo root, derived from this file's compile-time path (`Tests/CISmoke/…`, three levels
    /// up: CISmoke → Tests → repo. The sibling files say "up two" and are off by one; the code
    /// is right in all of them).
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

    /// Every line of `path` that is not a whole-line comment. Both files explain the `?? 2`
    /// rule in prose sitting directly beside the code, and those comments DO quote the
    /// spellings searched for here — so without this filter every assertion below would pass
    /// on the prose alone, after the code it describes had been deleted.
    private func codeLines(_ path: String) throws -> [String] {
        let url = try repoRoot().appendingPathComponent(path)
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
    }

    /// ⭐ THE CROSS-FILE AGREEMENT. Both halves are asserted in ONE test on purpose: split in
    /// two, a failure reads as "the panel is wrong" or "the engine is wrong" when the actual
    /// defect is that they disagree, and the repair is to decide ONE number and write it twice.
    func testTheRowsShowTheSameUnisonDefaultTheEngineActuallyPlays() throws {
        let engine = try codeLines(Self.poly)
        XCTAssertTrue(engine.contains { $0.contains("patch.unisonVoices ?? 2")
                                     && $0.contains("patch.unisonDetuneCents ?? 7") },
                      "PolySynthVoice no longer plays an unspecified patch at 2 voices / 7 "
                      + "cents. If that default changed deliberately, change the Sound panel's "
                      + "two bindings in the SAME commit — otherwise the rows display a unison "
                      + "setting the engine does not use, which is what #281 fixed.")

        let studio = try codeLines(Self.studio)
        XCTAssertTrue(studio.contains { $0.contains("currentPatch.unisonVoices ?? 2") },
                      "the Voices row no longer falls back to 2. `PatchEditorView` used 1 and "
                      + "that was the defect: the row read \"1\" while two voices sounded.")
        XCTAssertTrue(studio.contains { $0.contains("currentPatch.unisonDetuneCents ?? 7") },
                      "the Detune row no longer falls back to 7 cents — same defect as the "
                      + "Voices row, one field over.")
    }

    /// And the rows themselves. Without this the bindings could survive with nothing rendering
    /// them — a guard that stays green while the guarded thing is gone (#251's lesson).
    ///
    /// ⚠️ SAME-LINE COUPLED, stated as a trade-off rather than left to be discovered: the label
    /// and the binding must sit on ONE physical line. Reflowing that call — a formatter, a
    /// rename pushing it past a column limit — turns the blocking gate red with a message that
    /// says the row was deleted. Pairing is still right: the label alone is too generic to
    /// match ("Voices" could be any row) and the binding alone would pass on its declaration.
    /// If this ever fires on a reflow, re-pair the tokens; do not delete the assertion.
    func testBothUnisonRowsAreMountedInTheSoundPanel() throws {
        let studio = try codeLines(Self.studio)
        for (label, binding) in [("Voices", "unisonVoicesBinding"),
                                 ("Detune", "unisonDetuneBinding")] {
            XCTAssertTrue(studio.contains { $0.contains(#"label: "\#(label)""#)
                                         && $0.contains(binding) },
                          "the \(label) row is gone from the Sound panel. It is the ONLY editor "
                          + "for its parameter in the app — `PatchEditorView` is doorless and "
                          + "queued for deletion (#132 Slice 6), so removing this row does not "
                          + "leave a second way in.")
        }
    }
}
