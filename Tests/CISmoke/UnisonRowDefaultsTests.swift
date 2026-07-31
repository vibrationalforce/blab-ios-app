// UnisonRowDefaultsTests.swift
// Echoel — #281. `unisonVoices` / `unisonDetuneCents` are the engine's single biggest
// thin→rich lever, and until this slice their only editor was `PatchEditorView.swift` — a
// file with ZERO instantiation sites. Deleting it while they lived only there would have
// removed the last way to reach two persisted parameters: a capability loss wearing a
// cleanup's clothes. The rows now live in `soundPanel`, behind the Sound chip, and that file
// is deleted as of #132 Slice 6 — so these guards are no longer a precaution. They are the
// only thing standing between the five ported rows and a silent capability loss.
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
// ⚠️ THE FILE NOW COVERS ALL FIVE PORTED ROWS, not the two its name mentions: #281's
// `unisonVoices` / `unisonDetuneCents`, and #286's `spectralShape` / `noiseColor` /
// `outputLevel`. They share the two helpers and guard one thing — a row that is the LAST
// editor for an engine-consumed, persisted field. Renaming the file would be churn; leaving
// the newest additions in a file nobody looks in would be worse.
//
// ⛔ HONEST LIMIT: this proves the rows are WRITTEN and the fallbacks match. It cannot
// prove the panel renders them, that the chip reaches it, or that unison sounds right. That
// is device-verified only.

import Foundation
import XCTest

final class UnisonRowDefaultsTests: XCTestCase {

    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"
    private static let poly = "Sources/Echoelmusic/Tools/PolySynthVoice.swift"

    /// #286 — the two NAMED timbre choices ported in the same effort. They live here rather
    /// than in their own file because they need the same two helpers and guard the same thing:
    /// a row that was the last editor for an engine-consumed field. (The file name is now
    /// narrower than its contents; renaming it would be churn for its own sake.)
    ///
    /// A `Picker`, not an `EchoelValueField` — the app-wide numeric law is explicitly about
    /// NUMERIC parameters, and CLAUDE.md warns in the same paragraph against "restoring" a
    /// named choice to a number field in the name of that law. Asserting the picker keeps
    /// anyone from doing it here.
    /// ⛔ THREE WRONG-REASON RISKS IN THE FIRST VERSION, all found in review, all avoided here:
    /// it scanned the WHOLE 6000-line file (so moving the row into a doorless helper would
    /// still pass, while the failure text claimed it was gone from the Sound panel — the exact
    /// "a slot proves nothing about reachability" trap CLAUDE.md warns about); it required the
    /// title and the binding on ONE line, so a reflow would redden the blocking gate; and it
    /// pinned the display string "Noise colour", so a US-spelling fix would fail as a deletion.
    /// This version scopes to `soundPanel`'s own body and matches only the binding names, which
    /// are code, not copy.
    func testTheNamedTimbreChoicesAreMountedAsPickers() throws {
        let body = try soundPanelBody()
        for binding in ["spectralShapeBinding", "noiseColorBinding"] {
            XCTAssertTrue(body.contains { $0.contains(binding) },
                          "\(binding) is no longer used inside `soundPanel`. "
                          + "`PatchEditorView` is deleted (#132 Slice 6), so that row is the "
                          + "only way to choose the value.")
        }
        XCTAssertEqual(body.filter { $0.contains(".pickerStyle(.menu)") }.count, 2,
                       "the Sound panel no longer holds exactly two menu Pickers. These choices "
                       + "have NAMES, so an `EchoelValueField` would be the wrong control even "
                       + "though it could reach the same field — CLAUDE.md says so in the same "
                       + "paragraph as the numeric law.")
    }

    /// The lines of `soundPanel`'s body: from its declaration to the next member declaration.
    /// Scoping matters — see the note above. Comments are already dropped, so the ⛔ prose
    /// inside the panel cannot shift the boundary or satisfy a match.
    private func soundPanelBody() throws -> [String] {
        let lines = try codeLines(Self.studio)
        guard let start = lines.firstIndex(where: { $0.contains("private var soundPanel") }) else {
            XCTFail("`soundPanel` is gone from \(Self.studio) — that is the live patch editor "
                    + "(the Sound chip's panel). If it was renamed, move this guard with it.")
            return []
        }
        let end = lines[(start + 1)...].firstIndex { $0.hasPrefix("    private ") } ?? lines.endIndex
        return Array(lines[start..<end])
    }

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

    /// ⭐ #286's LAST ROW, and the one whose absence kept `PatchEditorView.swift` alive. Both
    /// halves are asserted together for the same reason as the unison pair: the row without the
    /// engine-matching fallback is a readout that disagrees with the ear, and the fallback
    /// without the row is a binding nothing renders.
    ///
    /// `?? 1.0` is not a guess — it is `SynthPatch.level`'s own nil fallback, and `resolved()`
    /// hands exactly that to the engine. If the un-boxing ever changes, this row starts lying
    /// and only a cross-file check like this one notices.
    ///
    /// ⛔ THE FIRST VERSION JUSTIFIED IT WITH "NO genre or library patch sets the field", and
    /// the library half is false: the library IS `SynthPatch.factory + user patches`
    /// (`PatchStore`), and EVERY factory patch sets `outputLevel` through
    /// `loudnessNormalized()`. A save-as from any preset persists it too. Only the GENRE half
    /// holds. The wrong reason mattered because it stood in a failure MESSAGE — the text a
    /// future session acts on — and it points at the same trap the picker test above was fixed
    /// for: someone greps `outputLevel`, finds `loudnessNormalized` as a second writer, and
    /// reads the guard as stale. The fallback is about **nil**, not about who writes.
    ///
    /// ⚠️ SAME-LINE COUPLED, like `testBothUnisonRowsAreMountedInTheSoundPanel` below: the label
    /// and the binding must sit on ONE physical line, so a reflow of that call reddens the
    /// blocking gate with a message that says the row was deleted. Re-pair the tokens if it
    /// ever fires that way; do not delete the assertion.
    func testTheOutputRowIsMountedAndAgreesWithTheEnginesUnityFallback() throws {
        let body = try soundPanelBody()
        XCTAssertTrue(body.contains { $0.contains(#"label: "Output""#)
                                   && $0.contains("outputLevelBinding") }, """
        the Output row is gone from `soundPanel`. It is the ONLY editor for \
        `SynthPatch.outputLevel` in the app — `PatchEditorView` is deleted (#132 Slice 6), so \
        removing this row does not leave a second way in. It was added by #286 precisely so \
        that the deletion would not be a capability loss.
        """)

        // ⚠️ Whole-file, not `soundPanelBody()`, and that is forced rather than sloppy:
        // `outputLevelBinding` is declared BELOW the panel, so scoping to the panel would find
        // nothing. The message therefore names the BINDING, not the row — the assertion above
        // is the one that pins the row to the panel, and it IS scoped.
        let studio = try codeLines(Self.studio)
        XCTAssertTrue(studio.contains { $0.contains("currentPatch.outputLevel ?? 1.0") }, """
        `outputLevelBinding` no longer falls back to unity. A nil `outputLevel` means "no trim \
        stored", and `SynthPatch.level` un-boxes exactly that to 1.0 on the way to the engine — \
        so any other fallback makes the row display a level the voice is not played at. This is \
        about the NIL case; which patches happen to store a value is beside the point.
        """)

        let patch = try codeLines("Sources/Echoelmusic/DSP/SynthPatch.swift")
        XCTAssertTrue(patch.contains { $0.contains("public var level: Float { outputLevel ?? 1.0 }") }, """
        `SynthPatch`'s own unity fallback changed. Change the Sound panel's Output binding in \
        the SAME commit — otherwise the row shows one number while the voice plays another, \
        which is exactly the defect #281 fixed for the unison rows.
        """)
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
                          + "for its parameter in the app — `PatchEditorView` is deleted (#132 "
                          + "Slice 6), so removing this row does not leave a second way in.")
        }
    }
}
