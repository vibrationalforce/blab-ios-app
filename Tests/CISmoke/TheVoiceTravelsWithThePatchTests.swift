// TheVoiceTravelsWithThePatchTests.swift
// Echoel — a captured voice can ride a saved patch, and old patches stay readable. #593a.
//
// WHAT THIS GUARDS. The persistence half of EchoelVoice: `SynthPatch` gains a voice
// half (`voiceProfileTaps` + mandatory-at-save `voiceProfileLabel` + clamped
// `voiceProfileBlend`), decoded as a UNIT keyed on the taps under the #95-hardened
// `decodeIfPresent` law — one old patch must never nuke the library again. The apply
// path hands an embedded profile through the #591a staging, and `clearVoiceProfile`
// strips the voice half from the patch MEMORY before re-applying, or Clear could
// never clear an embedded-profile patch (the Council's sharpest concern, #593).
// NO AUDIO persists — the taps are a max-normalized spectral envelope.
//
// ⚠️ HONEST LIMITS. 7 tests, 20 `XCTAssert*` statements (hand-counted per test,
// 4+3+4+2+2+3+2; the one `XCTUnwrap` in test 5 and the TWO in test 7 also fail
// their tests and sit outside this count — assertions, not failure points). Tests 1–5 are END-TO-END BEHAVIOUR on the shipped pure Codable type
// (real JSONEncoder/JSONDecoder, no mocks); tests 6–7 are SOURCE-TEXT JOINS (the
// apply/clear flow sits on a `@MainActor` voice whose poly engine a test host can
// construct but whose recall drain needs the render loop). What no test here can
// prove: that an embedded profile SOUNDS like the captured voice after a recall —
// device probe (NEEDS-FOUNDER-VERIFY, folds into the existing voice-capture probe:
// capture, save-as, switch patch, recall the saved one — your colour must return).
// The SAVE flow that writes the profile into a patch is #593b — no door sets these
// fields yet, and this file deliberately does not pretend one exists.
//
// ⭐ GRADING (§3). This file drives fields this same commit adds — against the parent
// tree it DOES NOT COMPILE (unknown members), so no assertion has a verdict there;
// the decode logic was hand-transcribed in Python (JSON semantics re-implemented)
// against the worktree and all driven assertions reproduce. Tests 6–7's needles are
// FORWARD guards except the `tryEnqueue(patch.resolved())` counterweight (green on
// both trees — the point is that #593 did not add a second enqueue path). Stripper:
// all 5 source needles measured raw vs stripped on the worktree — 0 of 5 verdicts
// flip → PROPHYLAKTISCH (the #593 comments name members, never call syntax).

import Foundation
import XCTest
@testable import Echoelmusic

final class TheVoiceTravelsWithThePatchTests: XCTestCase {

    // MARK: - 1–5. The model (END-TO-END, real coders)

    /// The whole voice half survives an encode→decode roundtrip, exactly.
    func testTheVoiceHalfRoundtrips() throws {
        let taps = (0..<64).map { Float($0 % 7) / 7 + 0.01 }
        let patch = SynthPatch(name: "Mine", voiceProfileTaps: taps,
                               voiceProfileLabel: "Michael", voiceProfileBlend: 0.7)
        let data = try JSONEncoder().encode(patch)
        let back = try JSONDecoder().decode(SynthPatch.self, from: data)
        XCTAssertEqual(back.voiceProfileTaps, taps,
                       "the measured envelope must come back bit-for-bit")
        XCTAssertEqual(back.voiceProfileLabel, "Michael")
        XCTAssertEqual(back.voiceProfileBlend, 0.7)
        XCTAssertEqual(back, patch, "the synthesized == must see the voice half too")
    }

    /// A patch saved BEFORE #593 — no voice keys at all — decodes with the half nil.
    /// This is the #95 law the whole decoder exists for.
    func testAPrePatchDecodesWithNoVoiceHalf() throws {
        let old = Data(#"{"name":"Old"}"#.utf8)
        let patch = try JSONDecoder().decode(SynthPatch.self, from: old)
        XCTAssertNil(patch.voiceProfileTaps)
        XCTAssertNil(patch.voiceProfileLabel)
        XCTAssertNil(patch.voiceProfileBlend)
    }

    /// Decode sanitizing: negative taps clamp to 0, a missing label defaults to
    /// "Voice" (never nil beside real taps), an out-of-range blend clamps to 0…1.
    func testDecodeEngineShapesTheVoiceHalf() throws {
        let dirty = Data(#"{"name":"D","voiceProfileTaps":[-0.5,2.0],"voiceProfileBlend":3.5}"#.utf8)
        let patch = try JSONDecoder().decode(SynthPatch.self, from: dirty)
        XCTAssertEqual(patch.voiceProfileTaps, [0, 2.0],
                       "a negative tap is not a level, it is a sign error — clamp, "
                       + "the same shape setCustomTimbre applies engine-side")
        XCTAssertEqual(patch.voiceProfileLabel, "Voice",
                       "taps without a label degrade to a LABELED profile — the "
                       + "share-label law must not turn into silent data loss")
        XCTAssertEqual(patch.voiceProfileBlend, 1, "blend clamps into 0…1")
        let low = Data(#"{"voiceProfileTaps":[1],"voiceProfileBlend":-2}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(SynthPatch.self, from: low).voiceProfileBlend, 0)
    }

    /// An EMPTY taps array is no profile: the whole half decodes nil, so a label
    /// cannot claim a voice that is not there.
    func testEmptyTapsDropTheWholeHalf() throws {
        let empty = Data(#"{"voiceProfileTaps":[],"voiceProfileLabel":"Ghost"}"#.utf8)
        let patch = try JSONDecoder().decode(SynthPatch.self, from: empty)
        XCTAssertNil(patch.voiceProfileTaps)
        XCTAssertNil(patch.voiceProfileLabel,
                     "a label beside zero taps would be a voice CLAIM with no voice")
    }

    /// A patch WITHOUT a voice half encodes none of the three keys — every existing
    /// patch file stays byte-stable in what it carries (encodeIfPresent, synthesized).
    func testAVoicelessPatchEncodesNoVoiceKeys() throws {
        let plain = SynthPatch(name: "Plain")
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(plain), encoding: .utf8))
        XCTAssertFalse(json.contains("voiceProfileTaps"),
                       "a nil half must not stamp keys into every patch on disk")
        XCTAssertFalse(json.contains("voiceProfileLabel"))
    }

    // MARK: - 6–7. The apply/clear joins (SOURCE-TEXT)

    /// The apply path: an embedded profile goes through the #591a staging (the
    /// drain-surviving pathway), with the patch's own blend; and there is still
    /// exactly ONE enqueue of the resolved patch (no second apply path grew).
    func testAnEmbeddedProfileAppliesThroughTheStaging() throws {
        let poly = try source("Sources/Echoelmusic/Tools/PolySynthVoice.swift")
        XCTAssertEqual(codeOccurrences(
            of: "applyVoiceProfile(taps, blend: patch.voiceProfileBlend ?? 1)", in: poly), 1,
            "the embedded profile must ride the #591a staging — a direct "
            + "loadTimbreProfile would be wiped by this very recall's drain (trap 1)")
        XCTAssertEqual(codeOccurrences(of: "if let taps = patch.voiceProfileTaps", in: poly), 1,
                       "a patch WITHOUT a profile must leave a live capture alone — "
                       + "the #591a survival design; an unconditional clear here would "
                       + "end every capture at the next genre change")
        XCTAssertEqual(codeOccurrences(of: "patchCommands.tryEnqueue(patch.resolved())", in: poly), 1,
                       "one resolved-patch enqueue site — the counterweight")
    }

    /// The clear loop-break: Clear strips the voice half from the patch MEMORY
    /// before re-applying, or an embedded-profile patch could never be cleared.
    /// ⚠️ HONEST LIMIT (steward #593a): count-1 + ordering proves the strip EXISTS
    /// after the declaration, not brace-matched CONTAINMENT — relocating the strip
    /// into a later member would stay green while Clear breaks again. Deleting it
    /// goes red (the primary mutation is covered). Tighten to brace-matched
    /// extraction (#408) on the next touch.
    func testClearStripsTheMemoryBeforeReapplying() throws {
        let poly = try source("Sources/Echoelmusic/Tools/PolySynthVoice.swift")
        XCTAssertEqual(codeOccurrences(of: "p.voiceProfileTaps = nil", in: poly), 1,
                       "clearVoiceProfile must strip the remembered patch's taps — "
                       + "re-applying an embedded-profile patch unstripped re-installs "
                       + "the very profile Clear exists to remove (Council, #593)")
        let clearAt = try XCTUnwrap(poly.range(of: "public func clearVoiceProfile()"))
        let stripAt = try XCTUnwrap(poly.range(of: "p.voiceProfileTaps = nil"))
        XCTAssertTrue(clearAt.lowerBound < stripAt.lowerBound,
                      "the strip lives inside clearVoiceProfile, after its declaration")
    }

    // MARK: - helpers (§0/§2 — one stripper, skip on no tree, FAIL on a moved anchor)

    private struct PatchAnchorMissing: Error { let reason: String }

    private func codeOccurrences(of needle: String, in stripped: String) -> Int {
        stripped.components(separatedBy: needle).count - 1
    }

    private func source(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        let path = root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw PatchAnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — renamed or moved. \
                Re-anchor this scan; do not let it skip (#454).
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }
}
