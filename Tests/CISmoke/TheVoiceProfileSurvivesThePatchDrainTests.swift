// TheVoiceProfileSurvivesThePatchDrainTests.swift
// Echoel — the measured voice must survive the recall drain that wipes it. #591.
//
// WHAT THIS GUARDS. Trap 1 of `scratchpads/PLAN_ECHOEL_VOICE.md`, verified at source:
// every patch recall ends in `ResolvedPatch.apply(to:)` on the audio thread, whose
// `applyTimbre` call is UNCONDITIONAL — for a patch without a built-in instrument that is
// `clearTimbreProfile()`, and a measured voice profile dies with it. `ResolvedPatch` is
// deliberately POD (no Array), so the profile cannot ride inside it. The repair under
// test: the profile is STAGED in `EchoelPolyDDSP` (`customTimbre`, fixed slots behind a
// raw pointer allocated once — no CoW, no ARC on the audio-thread fan; the hardened form
// of the `tuningCents` discipline, review #591a) and `drainCustomTimbre(reassert:)`
// re-fans it AFTER each patch drain, keeping the render order patch → voice timbre → bio.
//
// ⚠️ HONEST LIMITS. 7 tests, 20 assertion statements (`grep -c "XCTAssert"`, measured —
// the 27 first written here was a from-memory number again, the §3 failure class this
// bundle logs every time it happens; most of the 20 run inside forEachVoice loops, so
// executed checks scale with the pool size). Tests 1–6 are END-TO-END BEHAVIOUR on the
// shipped `EchoelPolyDDSP` + `ResolvedPatch` + `EchoelDDSP` (the drain method is called
// directly — a unit test is single-threaded, which is exactly why the engine half is
// testable while `PolySynthVoice`'s private render block is not). Test 7 is a SOURCE-TEXT
// ORDERING SCAN of that render block. NOT covered: true cross-thread timing (the torn-read
// argument is the documented `tuningCents` discipline, not provable here), the audible
// result (device probe, founder), and any UI door — none exists yet; the capture flow
// (#592) brings it, and until then `applyVoiceProfile` has no production caller (booked
// in the plan, deliberately, the way `loadTimbreProfile` itself was).
//
// ⭐ GRADING (§3). The file names `setCustomTimbre`/`drainCustomTimbre`/`applyCustomTimbre`,
// created by this same commit — it does NOT COMPILE against the parent; no assertion has
// a verdict there. ONE forward-looking finding (#486). Transcribed instead (§0): the
// drain's version/active/reassert state machine was reimplemented in Python and driven
// through every scenario below (fan, wipe-and-reassert, deactivation edge incl. the
// same-block clear+recall pair, NaN sanitize, no-refan-without-reason, short-input
// refusal), all agreeing with these assertions. Stripper on the ordering scan: measured
// on both trees — all three needles occur exactly once raw AND stripped in the worktree
// (0 of 3 verdicts flip → PROPHYLAKTISCH; on the parent the drain needle is absent, which
// is the same one absence).

import Foundation
import XCTest
@testable import Echoelmusic

final class TheVoiceProfileSurvivesThePatchDrainTests: XCTestCase {

    private func ramp64() -> [Float] { (1...64).map { Float($0) / 64 } }

    // MARK: - END-TO-END on the shipped engine

    func testAMeasuredProfileReachesEveryVoice() {
        let poly = EchoelPolyDDSP(maxVoices: 3)
        poly.setCustomTimbre(ramp64(), blend: 1)
        poly.drainCustomTimbre(reassert: false)
        poly.forEachVoice { voice in
            XCTAssertTrue(voice.hasTimbreProfile)
            XCTAssertEqual(voice.timbreProfile ?? [], ramp64(),
                           "every pooled voice must carry the measured envelope")
            XCTAssertEqual(voice.timbreBlend, 1)
        }
    }

    /// THE TRAP, on the real pathway: a patch with no built-in instrument wipes the
    /// profile via its unconditional `applyTimbre` — and the reassert restores it.
    func testThePatchDrainWipesAndTheReassertRestores() {
        let poly = EchoelPolyDDSP(maxVoices: 2)
        poly.setCustomTimbre(ramp64(), blend: 1)
        poly.drainCustomTimbre(reassert: false)
        let plainPatch = SynthPatch(name: "Plain").resolved()
        poly.forEachVoice { plainPatch.apply(to: $0) }
        poly.forEachVoice {
            XCTAssertFalse($0.hasTimbreProfile,
                           "this is trap 1 itself — if this holds, the recall no longer "
                           + "clears unconditionally and the reassert may be obsolete; "
                           + "re-read the plan before 'fixing' this assertion")
        }
        poly.drainCustomTimbre(reassert: true)
        poly.forEachVoice {
            XCTAssertTrue($0.hasTimbreProfile, "the reassert is the whole repair")
            XCTAssertEqual($0.timbreProfile ?? [], ramp64())
        }
    }

    /// Deactivation hands timbre back to the patch pathway — including the same-block
    /// "clear custom + re-apply patch" pair, which must KEEP the patch's own instrument
    /// spectrum rather than clearing what the recall just restored.
    func testDeactivationHandsTimbreBackToThePatch() {
        // (a) Plain deactivation edge: clear → next drain clears the voices.
        let poly = EchoelPolyDDSP(maxVoices: 2)
        poly.setCustomTimbre(ramp64(), blend: 1)
        poly.drainCustomTimbre(reassert: false)
        poly.clearCustomTimbre()
        poly.drainCustomTimbre(reassert: false)
        poly.forEachVoice { XCTAssertFalse($0.hasTimbreProfile) }

        // (b) Same-block pair: the violin patch's recall runs in the same drain cycle.
        poly.setCustomTimbre(ramp64(), blend: 1)
        poly.drainCustomTimbre(reassert: false)
        poly.clearCustomTimbre()
        let violin = SynthPatch(name: "Violin", timbreProfile: "Violin", timbreBlend: 0.9)
            .resolved()
        poly.forEachVoice { violin.apply(to: $0) }
        poly.drainCustomTimbre(reassert: true)
        let expected = EchoelDDSP.instrumentProfile(.violin)
        poly.forEachVoice { voice in
            XCTAssertTrue(voice.hasTimbreProfile,
                          "the deactivation edge cleared what the patch just restored")
            XCTAssertEqual(voice.timbreProfile ?? [], expected,
                           "after clearing the custom profile, the PATCH's instrument "
                           + "must stand — not the stale measured envelope")
        }
    }

    /// The engineering.md boundary rule at this control input: NaN taps read as 0,
    /// negatives clamp, and a NaN blend deactivates instead of arming a silent profile.
    func testNonFiniteTapsAreSanitized() {
        let poly = EchoelPolyDDSP(maxVoices: 1)
        var taps = ramp64()
        taps[0] = .nan
        taps[1] = -5
        poly.setCustomTimbre(taps, blend: 1)
        poly.drainCustomTimbre(reassert: false)
        poly.forEachVoice { voice in
            let p = voice.timbreProfile ?? []
            XCTAssertEqual(p.first, 0, "a NaN tap must read as 0")
            XCTAssertEqual(p.count >= 2 ? p[1] : -1, 0, "a negative tap must clamp to 0")
            for v in p { XCTAssertTrue(v.isFinite) }
        }
        let poly2 = EchoelPolyDDSP(maxVoices: 1)
        poly2.setCustomTimbre(ramp64(), blend: .nan)
        poly2.drainCustomTimbre(reassert: false)
        poly2.forEachVoice {
            XCTAssertFalse($0.hasTimbreProfile,
                           "a NaN blend must deactivate, never arm a silent profile")
        }
    }

    /// COUNTERWEIGHT to the version gate: without a version change or a reassert the
    /// drain must be a no-op — it must not silently re-fan over state it does not own.
    func testTheDrainDoesNotRefanWithoutAReason() {
        let poly = EchoelPolyDDSP(maxVoices: 2)
        poly.setCustomTimbre(ramp64(), blend: 1)
        poly.drainCustomTimbre(reassert: false)
        poly.forEachVoice { $0.clearTimbreProfile() }
        poly.drainCustomTimbre(reassert: false)
        poly.forEachVoice {
            XCTAssertFalse($0.hasTimbreProfile,
                           "no version change, no reassert — the drain re-fanned anyway")
        }
        poly.drainCustomTimbre(reassert: true)
        poly.forEachVoice {
            XCTAssertTrue($0.hasTimbreProfile, "reassert must still restore")
        }
    }

    /// Short input is refused whole (matching `loadTimbreProfile`), and a zero blend
    /// never arms: in both cases the voices stay exactly as the patch pathway left them.
    func testShortOrSilentInputIsRefused() {
        let poly = EchoelPolyDDSP(maxVoices: 1)
        poly.setCustomTimbre([Float](repeating: 1, count: 63), blend: 1)
        poly.drainCustomTimbre(reassert: false)
        poly.forEachVoice { XCTAssertFalse($0.hasTimbreProfile) }
        poly.setCustomTimbre(ramp64(), blend: 0)
        poly.drainCustomTimbre(reassert: false)
        poly.forEachVoice { XCTAssertFalse($0.hasTimbreProfile) }
    }

    // MARK: - SOURCE-TEXT: the render order is patch → voice timbre → bio

    /// The reassert only repairs the wipe if it runs AFTER the patch drain; and the bio
    /// modulation must run after BOTH so the body modulates around the measured envelope.
    /// All three needles occur exactly once in the file (verified raw and stripped), so
    /// index comparison is sound (#408).
    func testTheRenderOrderIsPatchThenVoiceTimbreThenBio() throws {
        let src = try source("Sources/Echoelmusic/Tools/PolySynthVoice.swift")
        let patch = try XCTUnwrap(src.range(of: "patchCommands.dequeue()"),
                                  "the patch drain anchor moved — re-anchor (#454)")
        let custom = try XCTUnwrap(src.range(of: "drainCustomTimbre(reassert: patchApplied)"),
                                   "the voice-timbre drain left the render block")
        let bio = try XCTUnwrap(src.range(of: "bioCommands.dequeue()"))
        XCTAssertTrue(patch.lowerBound < custom.lowerBound,
                      "the reassert must run AFTER the patch drain, or the wipe wins")
        XCTAssertTrue(custom.lowerBound < bio.lowerBound,
                      "bio must modulate AROUND the measured envelope, so it drains last")
    }

    // MARK: - source access (§0/§2 — one stripper, skip on no tree, FAIL on a moved anchor)

    private struct DrainAnchorMissing: Error { let reason: String }

    private func source(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        let path = root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw DrainAnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — renamed or moved. \
                Re-anchor this scan; do not let it skip (#454).
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }
}
