// ModalMaterialReconfigureTests.swift
// Echoel — the audio-thread contract of `EchoelModalBank.material`.
//
// `DrumRenderState.applyPendingRequests` assigns `material` FROM THE RENDER BLOCK on every
// config-version bump, and `LaneDrumKitVoice.noteOn` bumps that version whenever a pitch maps
// to different drum params — so a melodic tom/perc line reconfigured on nearly every note.
// Two things make that assignment allocation-free, and both are invisible at the call site:
// the didSet skips `applyMaterial` when the preset is unchanged, and the `.drum` mode-ratio
// table is a `static let` instead of a per-call array literal.
//
// A unit test cannot observe a malloc. What it CAN pin is the claim the skip rests on — that
// re-applying the same preset is audibly a no-op — and its converse, that a real material
// change still takes effect. Without the second half, "optimising" by skipping more would
// pass. The tests deliberately compare RENDERED SAMPLES, not internal state, because the
// samples are what the claim is about.

import XCTest
@testable import Echoelmusic

final class ModalMaterialReconfigureTests: XCTestCase {

    private let modes = 16
    private let sr: Float = 48000
    private let frames = 512

    /// Excite a bank, render one block, reassign `material` `extraAssignments` times, render a
    /// second block, and return both blocks concatenated.
    private func render(reassigning material: EchoelModalBank.MaterialPreset,
                        times extraAssignments: Int,
                        thenSwitchingTo switched: EchoelModalBank.MaterialPreset? = nil) -> [Float] {
        let bank = EchoelModalBank(modeCount: modes, sampleRate: sr)
        bank.material = material          // the one real change (default is `.bell`)
        bank.frequency = 180
        bank.noteOn(velocity: 0.9)

        var out = [Float](repeating: 0, count: frames)
        bank.render(buffer: &out, frameCount: frames)

        for _ in 0..<extraAssignments { bank.material = material }
        if let switched { bank.material = switched }

        var tail = [Float](repeating: 0, count: frames)
        bank.render(buffer: &tail, frameCount: frames)
        return out + tail
    }

    /// The skip's premise: assigning the SAME preset again changes nothing you can hear.
    /// If this ever fails, `applyMaterial` has grown a side effect on per-note state and the
    /// equality guard in the didSet is no longer safe to keep.
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
