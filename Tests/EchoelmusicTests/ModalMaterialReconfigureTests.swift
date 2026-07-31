// ModalMaterialReconfigureTests.swift
// Echoel — the audio-thread contract of `EchoelModalBank.material`.
//
// ⛔ The caller these tests were written FOR is gone: `DrumRenderState.applyPendingRequests`
// assigned `material` FROM THE RENDER BLOCK on every config-version bump, and
// `LaneDrumKitVoice.noteOn` bumped that version whenever a pitch mapped to different drum
// params — so a melodic tom/perc line reconfigured on nearly every note. Both types were
// DELETED with #167 (founder 2026-07-27). Be exact about what is left: `Sources/` does not
// instantiate `EchoelModalBank` ANYWHERE today, so there is no render path holding a bank —
// an earlier version of this header said `material` "is still settable from a render path",
// which was false. `material` remains a plain settable property on a render-CAPABLE type, so
// these tests stay as the guard's specification for its next assigner, not as coverage of a
// live path.
// Two things make such an assignment allocation-free, and both are invisible at the call site:
// the didSet skips `applyMaterial` when the preset is unchanged, and the `.drum` mode-ratio
// table is a `static let` instead of a per-call array literal.
//
// A unit test cannot observe a malloc. Be precise about what each of these does instead —
// review caught the first version of this header claiming coverage it does not have:
//
//  · `testReassigningTheSameMaterial_isSampleIdentical` passes WITH the guard (the assignment
//    does nothing) and WITHOUT it (the re-apply writes bit-identical values). It documents the
//    intended contract; it CANNOT detect the guard's removal. Kept because a reader needs the
//    contract written down somewhere executable, not because it is a regression guard.
//  · `testReturningToAMaterial_leavesTheDecayUntouched` is the one that pins the guard's
//    PREMISE, by using only real transitions (X → Y → X) so `applyMaterial` genuinely runs.
//    It goes red the moment `applyMaterial` touches per-note state — phases, amplitudes,
//    envelope — which is exactly when skipping it would stop being inaudible.
//  · `testSwitchingMaterialMidNote_changesTheTail` is the teeth: it fails if a real material
//    change stops taking effect, so the guard can never be "improved" into swallowing one.
//
// All three compare RENDERED SAMPLES rather than internal state, because the samples are what
// the audibility claim is about.

import XCTest
#if canImport(Accelerate)
@testable import Echoelmusic

final class ModalMaterialReconfigureTests: XCTestCase {

    private let modes = 16
    private let sr: Float = 48000
    private let frames = 512

    /// Excite a bank, render one block, perturb `material` between the blocks, render a second
    /// block, return both concatenated. The perturbation is one of three shapes:
    ///   - `times: n`         — assign the SAME preset n more times (skipped by the guard)
    ///   - `roundTripVia: y`  — x → y → x, two REAL changes that leave the preset where it began
    ///   - `thenSwitchingTo:` — x → y and stay there
    private func render(reassigning material: EchoelModalBank.MaterialPreset,
                        times extraAssignments: Int = 0,
                        roundTripVia detour: EchoelModalBank.MaterialPreset? = nil,
                        thenSwitchingTo switched: EchoelModalBank.MaterialPreset? = nil) -> [Float] {
        let bank = EchoelModalBank(modeCount: modes, sampleRate: sr)
        bank.material = material          // the one real change (default is `.bell`)
        bank.frequency = 180
        bank.noteOn(velocity: 0.9)

        var out = [Float](repeating: 0, count: frames)
        bank.render(buffer: &out, frameCount: frames)

        for _ in 0..<extraAssignments { bank.material = material }
        if let detour {
            bank.material = detour        // real change → applyMaterial runs
            bank.material = material      // real change back → applyMaterial runs again
        }
        if let switched { bank.material = switched }

        var tail = [Float](repeating: 0, count: frames)
        bank.render(buffer: &tail, frameCount: frames)
        return out + tail
    }

    /// Documents the contract, and CANNOT fail either way — see the header. With the guard the
    /// re-assignments are skipped; without it they write bit-identical values. Do not read a
    /// green run here as evidence that the guard is present or that it is safe; the test below
    /// is the one that checks the safety premise.
    func testReassigningTheSameMaterial_isSampleIdentical() {
        for preset in [EchoelModalBank.MaterialPreset.drum, .bell, .plate] {
            let untouched = render(reassigning: preset, times: 0)
            let hammered = render(reassigning: preset, times: 12)
            XCTAssertEqual(untouched.count, hammered.count)
            for i in 0..<untouched.count {
                XCTAssertEqual(untouched[i], hammered[i], accuracy: 0,
                               "\(preset): re-assigning the same material moved sample \(i)")
            }
        }
    }

    /// THE PREMISE, tested where it can actually fail. Every assignment here is a real change
    /// (drum → plate → drum), so `applyMaterial` runs twice mid-note, past the guard. Because it
    /// ends on the preset it began with, the rendered tail must be untouched — which is only
    /// true if `applyMaterial` writes preset-derived config and nothing else. The moment it
    /// touches a phase, a current amplitude or the envelope, this goes red, and that is exactly
    /// the moment skipping the re-apply would stop being inaudible.
    func testReturningToAMaterial_leavesTheDecayUntouched() {
        for (preset, detour) in [(EchoelModalBank.MaterialPreset.drum, EchoelModalBank.MaterialPreset.plate),
                                 (.bell, .drum),
                                 (.plate, .bell)] {
            let untouched = render(reassigning: preset)
            let roundTripped = render(reassigning: preset, roundTripVia: detour)
            for i in 0..<untouched.count {
                XCTAssertEqual(untouched[i], roundTripped[i], accuracy: 0,
                               "\(preset) → \(detour) → \(preset) moved sample \(i): "
                               + "applyMaterial now carries per-note state, so the didSet's "
                               + "equality guard is no longer safe")
            }
        }
    }

    /// The converse, so the guard can never be "improved" into swallowing a real change:
    /// switching material mid-note MUST alter the decaying tail.
    func testSwitchingMaterialMidNote_changesTheTail() {
        let stayed = render(reassigning: .drum, times: 0)
        let switched = render(reassigning: .drum, times: 0, thenSwitchingTo: .bell)
        let tail = frames..<(frames * 2)
        // The first block is identical by construction (same preset, same excitation) — assert
        // that, so a failure in the second half cannot be blamed on divergent setup.
        for i in 0..<frames {
            XCTAssertEqual(stayed[i], switched[i], accuracy: 0,
                           "pre-switch blocks must match; they diverged at \(i)")
        }
        let diverged = tail.contains { abs(stayed[$0] - switched[$0]) > 1e-6 }
        XCTAssertTrue(diverged, "drum → bell mid-note left the rendered tail unchanged")
    }

    /// `.drum`'s ratio table moved to a `static let`. This asserts only what it can see from
    /// outside: after the hoist a struck drum still renders finite, non-silent audio. It does
    /// NOT verify the ratios themselves (they are private, and nothing here reads them) — so
    /// do not treat it as a guard on the Bessel values. A table typo would sail past it.
    func testDrumStillRendersAfterTheRatioTableMoved() {
        let bank = EchoelModalBank(modeCount: modes, sampleRate: sr)
        bank.material = .drum
        bank.frequency = 100
        bank.noteOn(velocity: 1.0)
        var out = [Float](repeating: 0, count: frames)
        bank.render(buffer: &out, frameCount: frames)
        XCTAssertTrue(out.contains { $0 != 0 }, "a struck drum rendered silence")
        XCTAssertTrue(out.allSatisfy { $0.isFinite }, "non-finite sample in the drum render")
    }
}
#endif
