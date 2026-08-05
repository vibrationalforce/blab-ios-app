// FieldSoundSurvivesRelaunchTests.swift
// Echoel — #402. A user who picked a Field patch did not get it back after a relaunch.
//
// ⭐ THE DEFECT WAS AN ORDERING ONE, and it hid behind a comment that asserted the opposite.
// `EchoelStudioView.onAppear` applies the stored Field patch during the first SYNCHRONOUS appear
// pass. The app's async startup task runs AFTER that pass — the repo states this in its own words
// above the play-surface level restore — and then applied `SynthPatch.touchDefaultID` to the same
// voice unconditionally. Second write wins, so the factory default replaced the user's choice on
// every launch. The line above that apply read "or the user's own touch patch overrides", which is
// precisely why the ordering was never checked.
//
// ⭐ THIS FILE IS MOSTLY REAL BEHAVIOUR, NOT A SCAN — unusual for this bundle and the reason the
// fix was shaped as a pure resolver. `SynthPatch.launchTouchPatch(storedID:in:)` takes the stored
// id as a plain `String` and a patch list, so every branch of "which patch wakes up" is decidable
// here with no simulator, no `UserDefaults` and no view. Only the last test is a scan, and it
// guards the one thing a pure function cannot: that the startup task actually asks.
//
// ⛔ WHAT IT STILL CANNOT PROVE. That the apply lands on an attached voice, that the user hears
// the right patch, or that the `onAppear` apply is not itself a no-op on a not-yet-attached voice
// (`setGain` provably is — the startup task says so). Those need a device pass. What is settled
// here is that both launch paths now resolve a stored id to the SAME patch.

import Foundation
import XCTest
@testable import Echoelmusic

final class FieldSoundSurvivesRelaunchTests: XCTestCase {

    /// A factory patch that is NOT the play-surface default — stands in for "the user picked
    /// something else". Derived rather than hard-coded so a re-ordered factory list cannot turn
    /// this file into a test of nothing.
    private func someOtherFactoryPatch() throws -> SynthPatch {
        let other = SynthPatch.factory.first { $0.id != SynthPatch.touchDefaultID }
        return try XCTUnwrap(other, """
        `SynthPatch.factory` holds no patch other than the play-surface default, so "the user \
        picked a different one" cannot be expressed. If the factory list really shrank to one, \
        this whole file needs rewriting against a constructed patch instead.
        """)
    }

    // MARK: - The defect itself

    /// ⭐ THE HEADLINE, and the assertion that was RED before #402: a stored choice comes back.
    func testAStoredChoiceIsWhatTheFieldWakesUpOn() throws {
        let chosen = try someOtherFactoryPatch()
        let resolved = SynthPatch.launchTouchPatch(storedID: chosen.id.uuidString,
                                                   in: SynthPatch.factory)
        XCTAssertEqual(resolved?.id, chosen.id, """
        a stored Field selection no longer survives launch — `launchTouchPatch` resolved \
        \(resolved?.name ?? "nothing") instead of "\(chosen.name)".

        That is #402 exactly: the user picks a Field sound, relaunches, and silently gets the \
        factory default back. The failure is invisible in the UI (the chip still shows their \
        choice) because only the VOICE was overwritten.
        """)
    }

    /// The other half of the same guarantee — and the reason the resolver exists rather than a
    /// bare `if` at the call site. Applying the default when nothing is stored must keep working;
    /// a fix that honoured the user by dropping the default would leave a fresh install on
    /// whatever the voice happened to init with.
    func testWithNothingStoredTheFactoryFieldDefaultWakesUp() {
        let resolved = SynthPatch.launchTouchPatch(storedID: "", in: SynthPatch.factory)
        XCTAssertEqual(resolved?.id, SynthPatch.touchDefaultID, """
        with no stored selection the play surface no longer wakes up on the factory Field patch.

        That patch is deliberately the RESPONSIVE one (quick attack, unison width) so a fresh \
        install answers a finger immediately instead of the mushy pad it used to launch on.
        """)
    }

    // MARK: - The forgiving ladder

    /// A deleted patch must not leave the play surface on nothing. This is the branch a user
    /// reaches by picking a patch and later deleting it — reachable today, since the sound panel
    /// can delete a saved patch.
    func testAStaleSelectionFallsBackToTheDefaultRatherThanNothing() {
        let deleted = UUID().uuidString
        let resolved = SynthPatch.launchTouchPatch(storedID: deleted, in: SynthPatch.factory)
        XCTAssertEqual(resolved?.id, SynthPatch.touchDefaultID, """
        a stored id that no longer matches any patch now resolves to \
        \(resolved.map { "\($0.name)" } ?? "nothing").

        A user who deletes the patch they had selected would get a silent or wrong play surface \
        with no way to tell why.
        """)
    }

    /// The stored value is a raw `String` from `UserDefaults` — nothing guarantees it parses.
    /// Garbage must take the same forgiving path as a stale id, not crash and not return nil.
    func testAnUnparseableStoredValueIsTreatedAsNoSelection() {
        for junk in ["not-a-uuid", "   ", "0", "00000000-0000-0000-0000-00000000000"] {
            let resolved = SynthPatch.launchTouchPatch(storedID: junk, in: SynthPatch.factory)
            XCTAssertEqual(resolved?.id, SynthPatch.touchDefaultID, """
            the unparseable stored value "\(junk)" did not fall back to the factory Field default.

            `touch.patchID` is a raw string in `UserDefaults`; a corrupted or hand-edited value \
            must degrade to the default, never to silence.
            """)
        }
    }

    /// Last rung: a library with no default at all still yields something playable.
    func testALibraryWithoutTheDefaultStillYieldsAPatch() throws {
        let withoutDefault = SynthPatch.factory.filter { $0.id != SynthPatch.touchDefaultID }
        try XCTSkipIf(withoutDefault.isEmpty, "factory holds only the default — nothing to test")
        let resolved = SynthPatch.launchTouchPatch(storedID: "", in: withoutDefault)
        XCTAssertEqual(resolved?.id, withoutDefault.first?.id, """
        with the default absent from the library the resolver no longer falls through to the \
        first available patch, so the play surface would wake up on nothing.
        """)
    }

    /// And an empty library must return `nil` rather than inventing a patch — the call site is
    /// written as `if let`, and a non-nil answer here would apply an empty/garbage voice.
    func testAnEmptyLibraryResolvesToNothing() {
        XCTAssertNil(SynthPatch.launchTouchPatch(storedID: "", in: []), """
        an empty patch library must resolve to nil so the caller's `if let` skips the apply. \
        Returning a synthesized patch here would push an unvetted voice onto the play surface.
        """)
    }

    // MARK: - The one thing behaviour cannot prove: that the startup task asks

    /// ⭐ A CORRECT RESOLVER NOBODY CALLS IS THE SAME DEFECT WITH EXTRA STEPS — every test above
    /// would stay green while the startup task went on applying the default unconditionally.
    ///
    /// ⛔ A SOURCE SCAN, with the limits that implies: it proves the call is written, not that it
    /// runs, and not that it runs before anything else touches the voice. Comments are stripped
    /// first so this file's own subject — and the long `⛔ #402` block now sitting beside the call
    /// — cannot stand in for the code.
    func testTheStartupTaskResolvesThroughIt() throws {
        let lines = try codeLines("Sources/Echoelmusic/EchoelmusicApp.swift")

        XCTAssertTrue(lines.contains { $0.contains("SynthPatch.launchTouchPatch(") }, """
        the app's startup task no longer calls `SynthPatch.launchTouchPatch`.

        Every behavioural test in this file would still pass — the resolver would simply be \
        correct and unused, and the startup task would be back to overwriting the user's Field \
        choice with the factory default on every launch. That is #402 restored in full.
        """)

        XCTAssertTrue(lines.contains { $0.contains("StudioDefaultKeys.touchPatchID.key") }, """
        the startup task no longer reads `touch.patchID`.

        The resolver deliberately does NOT read `UserDefaults` — it lives in `DSP/`, which the \
        AUv3 target compiles without `Core` types. If nobody hands it the stored id, it can only \
        ever answer with the default.
        """)
    }

    // MARK: - Source access

    /// Every non-empty line of `path` with comments removed — whole-line AND trailing. The
    /// quote-parity check approximates "is this `//` inside a string literal" and fails in both
    /// directions (an escaped quote or a `"""` delimiter leaves odd parity and the comment
    /// survives). Copied from `SoundPromptHasADoorTests`, which measured the residue in `Sources/`:
    /// six surviving `//`, all URLs inside string literals, none of them relevant here.
    private func codeLines(_ path: String) throws -> [String] {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("""
            \(url.path) is not present — the scanning half of this file reads source text, so it \
            SKIPS rather than reporting a green it did not earn. The behavioural tests above ran.
            """)
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { Self.stripComment(String($0)) }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private static func stripComment(_ line: String) -> String {
        var quotes = 0
        var previous: Character?
        var index = line.startIndex
        while index < line.endIndex {
            let ch = line[index]
            if ch == "\"" { quotes += 1 }
            if ch == "/", previous == "/", quotes % 2 == 0 {
                return String(line[line.startIndex..<line.index(before: index)])
            }
            previous = ch
            index = line.index(after: index)
        }
        return line
    }
}
