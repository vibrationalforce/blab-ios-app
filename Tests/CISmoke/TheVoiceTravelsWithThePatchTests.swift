// TheVoiceTravelsWithThePatchTests.swift
// Echoel — a captured voice can ride a saved patch, and old patches stay readable. #593a–c.
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
// ⚠️ HONEST LIMITS. 11 tests, 47 `XCTAssert*` statements (hand-counted per test,
// 4+3+4+2+2+3+2+8+6+5+8; `XCTUnwrap` census: one in test 5, two in test 7, two in
// test 9 — all fail their tests and sit outside this count, assertions not failure
// points). Tests 1–5 are END-TO-END BEHAVIOUR on the shipped pure Codable type
// (real JSONEncoder/JSONDecoder, no mocks); tests 6–11 are SOURCE-TEXT JOINS (the
// apply/clear/save flow sits on a `@MainActor` voice and a `private` View no test
// host can drive). Test 8 (#593b, re-anchored twice: by the #593c helper, then by
// the #593c REVIEW that replaced the tap-equality proxy with PROVENANCE — the
// synth remembers what the live profile arrived as) covers the save flow; test 9
// the one-definition law + both strips + the in-place ordering (review F4); test
// 10 the required-parameter clear (F5b); test 11 the provenance memory, the
// socket-floor gate (F2) and the third-copy strip (F3). What no test here can
// prove: that an embedded profile SOUNDS like the captured voice after a recall,
// and that Clear STAYS cleared through a knob tweak AND the prompt-Undo arrow on
// device — device probe (NEEDS-FOUNDER-VERIFY: capture, save-as, switch patch,
// recall — your colour must return; then Clear, tweak a knob, tap the Undo arrow,
// save — the colour must NOT return by any of the three).
// ⛔ The sentence that stood here — "no door sets these fields yet" — was true for
// exactly one commit and became this file's own refutation when test 8 arrived
// (#425, review F4): the #593b save-as door DOES set them now, and test 8 pins it.
//
// ⭐ GRADING (§3). Transcribed in Python (stripper re-implemented, EVERY needle in
// the file driven, not only the delta — the §3 blind-spot rule) against BOTH
// trees. Worktree: all 30 source needles + 2 orderings reproduce. Against the
// parent (the first #593c commit): exactly ONE assertion is a true REGRESSION red
// for its NAMED reason (#367): the `(patch.voiceProfileTaps == taps)` zero-count —
// the broken equality proxy EXISTS on the parent, and its breakage (misattribution
// on any patch switch under a surviving profile) is what the review found. The
// other ten parent-reds are ONE absence — the provenance mechanism does not exist
// there — reported once (#486). Counterweights green on both trees: tests 6–7
// wholesale, the artist-name count, the undo-delete snapshot save, the memory-
// read, the F5b needles. Stripper: TRAGEND (1 of 30 verdicts flip) — the
// `synth?.clearVoiceProfile()` zero-count finds the old form quoted in the F5b
// retraction comment when run raw; `codeOnly` blanking that quote is precisely
// the stripper's job (the #491 fragility pre-registered in the #593b header,
// arrived and carried as designed).

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

    /// The #593b save join, re-anchored by #593c: the enrich logic lives in the ONE
    /// helper (`patchCarryingLiveVoice`), labeled through the ONE artist-name
    /// definition, blend 1 — and the un-enriched wholesale call is gone, or save-as
    /// would silently drop a captured voice.
    func testSaveAsEmbedsTheLiveProfileLabeled() throws {
        let studio = try source("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        XCTAssertEqual(codeOccurrences(of: "if let taps = synth.appliedVoiceProfile", in: studio), 1,
                       "the save must read the voice's own memory — the only source "
                       + "that satisfies the #593a length guarantee by construction "
                       + "(appliedVoiceProfile is written solely through "
                       + "applyVoiceProfile's harmonicCount guard)")
        XCTAssertEqual(codeOccurrences(
            of: "SessionContext.typedArtistName(fromStored: session.artistName)", in: studio), 3,
            "the label goes through the ONE definition of 'did the user name "
            + "themselves' (#416) — the stored value is never empty (it holds the E~ "
            + "mark), so a raw isEmpty gate would mislabel every unnamed player; "
            + "count 3 = the artist row's display read + its binding getter + the "
            + "helper's read (the first draft wrote 2 from memory; the transcription "
            + "found the binding getter — measured, not remembered)")
        XCTAssertEqual(codeOccurrences(of: "patch.voiceProfileTaps = taps", in: studio), 2,
                       "the taps ASSIGNMENT is the save, on BOTH provenance branches "
                       + "(embedded-onto-tapless-base, fresh capture) — count 1 means "
                       + "one branch stopped saving taps, which the decoder's "
                       + "taps-keyed unit then nils wholesale on recall (review F3)")
        XCTAssertEqual(codeOccurrences(
            of: "if let label = synth.appliedVoiceProfileLabel", in: studio), 1,
            "misattribution is decided by PROVENANCE, not a proxy — the #593b "
            + "equality guard broke on any patch switch under a surviving profile "
            + "(#593c review F1); the memory travels, the comparison is gone")
        XCTAssertEqual(codeOccurrences(
            of: "(patch.voiceProfileTaps == taps)", in: studio), 0,
            "the broken equality proxy must stay gone — present, a patch switch "
            + "relabels a foreign voice again")
        XCTAssertEqual(codeOccurrences(of: "patch.voiceProfileBlend = 1", in: studio), 1,
                       "blend 1 on the FRESH-capture branch only — applyVoiceProfile's "
                       + "own default; embedded provenance carries its own blend")
        XCTAssertEqual(codeOccurrences(
            of: "patchStore.saveAs(patchCarryingLiveVoice(currentPatch), name: name)", in: studio), 1,
            "save-as saves what the ONE definition returns — nothing else")
        XCTAssertEqual(codeOccurrences(of: "patchStore.saveAs(currentPatch, name: name)", in: studio), 0,
                       "the un-enriched wholesale call must be gone — present, "
                       + "save-as would silently drop a captured voice")
    }

    // MARK: - 9–10. The #593c joins (SOURCE-TEXT)

    /// ONE definition of the voice half of a save (#416), called by BOTH doors —
    /// #593b's check 4 found "Save as…" embedding the live capture while "Save
    /// changes" silently did not, an asymmetry no player could see. And the F2/F5a
    /// strips: a cleared voice must stay cleared through a save AND a knob tweak.
    func testBothSaveDoorsShareTheOneVoiceDefinition() throws {
        let studio = try source("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        XCTAssertEqual(codeOccurrences(
            of: "private func patchCarryingLiveVoice(_ base: SynthPatch) -> SynthPatch", in: studio), 1,
            "the one definition exists exactly once")
        XCTAssertEqual(codeOccurrences(of: "patchCarryingLiveVoice(currentPatch)", in: studio), 2,
                       "BOTH save doors call it — save-as AND the in-place 'Save "
                       + "changes'; one call means the check-4 asymmetry is back")
        XCTAssertEqual(codeOccurrences(
            of: "currentPatch = patchCarryingLiveVoice(currentPatch)", in: studio), 1,
            "the in-place door updates the VIEW copy first, so the store and the "
            + "open editor never disagree about the half")
        let inPlaceAssignAt = try XCTUnwrap(studio.range(
            of: "currentPatch = patchCarryingLiveVoice(currentPatch)"))
        let inPlaceSaveAt = try XCTUnwrap(studio.range(of: "patchStore.save(currentPatch)"))
        XCTAssertTrue(inPlaceAssignAt.lowerBound < inPlaceSaveAt.lowerBound,
                      "the enrichment must run BEFORE the store call — swapped, every "
                      + "needle stays green while the store receives the un-enriched "
                      + "copy (#593c review F4: the silent-green gap)")
        XCTAssertEqual(codeOccurrences(of: "patch.voiceProfileTaps = nil", in: studio), 2,
                       "TWO strips, both load-bearing: the helper's else-branch (F2 — "
                       + "no live profile means the saved copy carries none, or a save "
                       + "right after Clear re-saves the just-cleared voice) and the "
                       + "Clear button's view-copy strip (F5a — with taps still in "
                       + "currentPatch, the next knob tweak re-applies the patch and "
                       + "reinstalls the cleared profile). Count 1 = one of them is "
                       + "gone; this scan cannot say which — read the two sites")
        XCTAssertEqual(codeOccurrences(of: "patchStore.save(d.patch)", in: studio), 1,
                       "COUNTERWEIGHT: undo-delete restores a SNAPSHOT verbatim — "
                       + "routing it through the helper would rewrite history with "
                       + "whatever profile happens to be live at undo time")
    }

    /// The F5b join: Clear reaches the synth through a required parameter, not the
    /// controller's weak reference (set only by `begin()` — nil on the recall-only
    /// path, where the old optional-chained call was a silent no-op).
    func testClearWorksOnTheRecallOnlyPath() throws {
        let controller = try source("Sources/Echoelmusic/Studio/VoiceCaptureController.swift")
        XCTAssertEqual(codeOccurrences(of: "func clearApplied(synth: PolySynthVoice)", in: controller), 1,
                       "the synth is a required parameter — no default, so no call "
                       + "site can forget it (#431)")
        XCTAssertEqual(codeOccurrences(of: "synth?.clearVoiceProfile()", in: controller), 0,
                       "the optional-chained form is the F5b no-op — a Clear button "
                       + "that does nothing exactly when the profile came embedded in "
                       + "a shared patch")
        XCTAssertEqual(codeOccurrences(of: "synth.clearVoiceProfile()", in: controller), 1,
                       "the non-optional call on the parameter — the clear cannot "
                       + "silently skip")
        let studio = try source("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        XCTAssertEqual(codeOccurrences(of: "controller.clearApplied(synth: synth)", in: studio), 1,
                       "the row passes its own @Environment synth — the reference "
                       + "that exists whether or not a capture ever ran this launch")
        XCTAssertEqual(codeOccurrences(
            of: "VoiceCaptureRow(controller: voiceCapture, patch: $currentPatch)", in: studio), 1,
            "the row holds the currentPatch binding — without it the F5a strip has "
            + "nothing to write and Clear cannot stick")
    }

    /// The provenance memory (#593c review F1/F2): the synth remembers what the live
    /// profile ARRIVED as — label set only on an ACCEPTED embed, nil'd on capture and
    /// clear; the save flow reads the socket floor to tell "cleared" from "refused".
    /// And F3: Clear strips the THIRD copy (the prompt-undo snapshot) via onClear.
    func testTheProfileCarriesItsProvenance() throws {
        let poly = try source("Sources/Echoelmusic/Tools/PolySynthVoice.swift")
        XCTAssertEqual(codeOccurrences(
            of: "public private(set) var appliedVoiceProfileLabel: String?", in: poly), 1,
            "the provenance memory exists — without it, 'whose voice is live?' falls "
            + "back to comparing taps against the current base, the broken proxy")
        XCTAssertEqual(codeOccurrences(
            of: "if applyVoiceProfile(taps, blend: patch.voiceProfileBlend ?? 1) {", in: poly), 1,
            "provenance is keyed on the ACCEPTED apply — a refused short half must "
            + "not stamp its label onto whatever profile is actually live")
        XCTAssertEqual(codeOccurrences(
            of: "appliedVoiceProfileLabel = patch.voiceProfileLabel", in: poly), 1,
            "an embedded profile carries its own label into the memory")
        XCTAssertEqual(codeOccurrences(of: "appliedVoiceProfileLabel = nil", in: poly), 2,
                       "TWO nil sites, both load-bearing: the direct-call capture path "
                       + "(fresh capture = this player, unlabeled until saved) and "
                       + "clearVoiceProfile (no profile, no provenance)")
        XCTAssertEqual(codeOccurrences(of: "public var voiceProfileTapFloor", in: poly), 1,
                       "the socket floor is public FOR the save flow — the one "
                       + "definition (#416) of what the engine accepts")
        let studio = try source("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        XCTAssertEqual(codeOccurrences(
            of: "existing.count >= synth.voiceProfileTapFloor", in: studio), 1,
            "the strip is gated on the floor — live-nil means 'player cleared' only "
            + "for a half the engine would have ACCEPTED; stripping a refused short "
            + "half destroys a shared voice the player never heard (review F2)")
        XCTAssertEqual(codeOccurrences(
            of: "patchBeforeSoundChange?.voiceProfileTaps = nil", in: studio), 1,
            "F3: Clear strips the prompt-undo snapshot's voice half — without this, "
            + "Clear → Undo-arrow restores the profile Clear just removed")
        XCTAssertEqual(codeOccurrences(of: "onClear()", in: studio), 1,
                       "the row calls the panel's strip exactly once, in Clear")
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
