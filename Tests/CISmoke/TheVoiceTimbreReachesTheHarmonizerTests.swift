// TheVoiceTimbreReachesTheHarmonizerTests.swift
// Echoel — "your tone, harmonized" is a JOIN that already exists; pin it. #597a.
//
// WHAT THIS GUARDS. The founder's "Harmonizer Sound mit eigenem Voice clone" (own-
// tone half) was measured BEFORE anything was built, and the measurement said: no
// wiring needed. The voice profile (#592b) shapes `PolySynthVoice`'s DDSP voices;
// that same voice renders through its OWN `fxChain` (`processBuffer` on the render
// path); the harmonizer is a stage of that chain; and the FX sheet's one door drives
// exactly `synth.fxChain`. Four links, all shipped — what #597a added is ONE caption
// sentence so a player can FIND the combination, and this file, so no future slice
// can silently break a link while the caption keeps promising it. Every assertion is
// the class of defect where re-pointing one side leaves a sentence lying (#351).
//
// ⚠️ HONEST LIMITS. 4 tests, 9 `XCTAssert*` statements (hand-counted per test,
// 2+2+3+2; the two `XCTUnwrap`s in test 4 also fail their test and sit outside this
// count — assertions, not failure points). ALL are SOURCE-TEXT JOINS: the chain sits on `@MainActor` voices and the
// render path is an audio-thread closure no test host can drive honestly; the
// harmonizer's SOUND on a captured timbre is a device probe (NEEDS-FOUNDER-VERIFY:
// capture a tone in Sound → Voice timbre, enable FX → Harmonizer, play — the
// stacked voices must carry YOUR colour, not the patch's). END-TO-END coverage of
// the profile pathway itself lives in TheVoiceProfileSurvivesThePatchDrainTests and
// TheCaptureTurnsAToneIntoAProfileTests (#416 — not repeated here).
//
// ⭐ GRADING (§3). The caption assertion (test 4) is the only FORWARD guard (this
// commit writes that sentence); tests 1–3 are COUNTERWEIGHTS — green on the parent
// tree too, because the wiring predates this slice. That distribution is the point:
// this file mostly pins premises that already hold (#343). Stripper: all 8 needles
// measured raw vs stripped on BOTH trees → PROPHYLAKTISCH (0 of 8 verdicts flip;
// `fxChain.noteRenderSkipped()` is raw=5/stripped=3 — two comment mentions — but
// both sides of the flip test agree at want=3). The transcription also corrected
// TWO counts the first draft wrote from memory (reset 2→3, skips 2→3) — the §3
// class, caught before CI this time. Measured, not assumed.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheVoiceTimbreReachesTheHarmonizerTests: XCTestCase {

    /// Link 1+2: the FX sheet's one door drives the SAME chain the voice-profile
    /// synth owns — re-pointing it at another inventory would silently orphan the
    /// caption's promise.
    func testTheFXDoorDrivesTheVoiceProfileSynthsOwnChain() throws {
        let studio = try source("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        XCTAssertEqual(codeOccurrences(of: "EchoelFXView(chain: synth.fxChain,", in: studio), 1,
                       "the deep FX surface must drive synth.fxChain — the chain the "
                       + "captured voice colour actually sounds through")
        XCTAssertEqual(codeOccurrences(of: "applyVoiceProfile(", in: studio), 0,
                       "the studio never applies profiles itself — that stays the "
                       + "controller's job (#592b), one pathway, one owner")
    }

    /// Link 3: the harmonizer is a live stage of the chain's stereo process — not a
    /// bypassed relic. The needle is the processing call, not the declaration.
    func testTheHarmonizerIsAStageOfTheChain() throws {
        let chain = try source("Sources/Echoelmusic/DSP/EchoelFXChain.swift")
        XCTAssertEqual(codeOccurrences(
            of: "if harmonizerEnabled { (l, r) = harmonizer.processStereo(l, r) }",
            in: chain), 1,
            "the harmonizer stage left the stereo process — the caption's promise "
            + "(FX → Harmonizer stacks your tone) would be a lie")
        XCTAssertEqual(codeOccurrences(of: "harmonizer.reset()", in: chain), 3,
                       "the enable-edge willSet, the character reset and the full reset "
                       + "all clear harmonizer state — losing one brings back "
                       + "stale-grain artefacts on re-enable (the first draft counted 2; "
                       + "the transcription found 3 — measured, not remembered)")
    }

    /// Link 4: the poly voice renders THROUGH its chain on the note path, and the
    /// idle skips keep the chain informed (the #343 premises that make link 1 mean
    /// anything at all).
    func testThePolyVoiceRendersThroughItsChain() throws {
        let poly = try source("Sources/Echoelmusic/Tools/PolySynthVoice.swift")
        XCTAssertEqual(codeOccurrences(
            of: "fxChain.processBuffer(left: &scratchL, right: &scratchR, frameCount: count)",
            in: poly), 1,
            "the render path must pass the voice's output through its own chain")
        XCTAssertEqual(codeOccurrences(of: "fxChain.noteRenderSkipped()", in: poly), 3,
                       "the THREE skip paths in renderOnAudioThread must keep telling "
                       + "the chain it was skipped (delay/reverb tails depend on it — "
                       + "the voice's own doc at `noteRenderSkipped()` names three)")
        XCTAssertEqual(codeOccurrences(of: "EchoelFXChain(sampleRate: Float(Self.sampleRate))",
                                       in: poly), 1,
                       "the voice owns exactly one chain — a second would split the "
                       + "sound the FX door claims to control")
    }

    /// The caption: promised only while a profile is APPLIED, and it names the door.
    func testTheCaptionNamesTheDoorOnlyWhenAProfileIsApplied() throws {
        let studio = try String(
            contentsOf: repoRoot().appendingPathComponent(
                "Sources/Echoelmusic/Studio/EchoelStudioView.swift"),
            encoding: .utf8)
        XCTAssertEqual(occurrences(
            of: "FX → Harmonizer stacks it into harmonies", in: studio), 1,
            "the discoverability sentence left the applied-profile caption — "
            + "the #597a slice IS this sentence")
        let captionAt = try XCTUnwrap(studio.range(
            of: "FX → Harmonizer stacks it into harmonies"))
        let gateAt = try XCTUnwrap(studio.range(
            of: "if synth.appliedVoiceProfile != nil {\n                // #597a"))
        XCTAssertTrue(gateAt.lowerBound < captionAt.lowerBound,
                      "the sentence must sit INSIDE the applied-profile branch — "
                      + "promising a harmonized voice colour while no profile is "
                      + "applied would be the lying-caption class")
    }

    // MARK: - helpers (§0/§2 — one stripper, skip on no tree, FAIL on a moved anchor)

    private struct HarmonyAnchorMissing: Error { let reason: String }

    private func codeOccurrences(of needle: String, in stripped: String) -> Int {
        stripped.components(separatedBy: needle).count - 1
    }

    private func occurrences(of needle: String, in raw: String) -> Int {
        raw.components(separatedBy: needle).count - 1
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    private func source(_ relativePath: String) throws -> String {
        let root = repoRoot()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        let path = root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw HarmonyAnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — renamed or moved. \
                Re-anchor this scan; do not let it skip (#454).
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }
}
