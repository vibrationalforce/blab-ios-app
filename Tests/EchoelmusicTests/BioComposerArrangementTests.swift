// BioComposerArrangementTests.swift
// Echoel — guards that a harmonic take is an ARRANGEMENT (multiple elements moving
// together: bass · pad · inner pulse · lead), not one static surface. Founder ear-
// feedback 2026-07-02: "an instrumental needs more elements, not just one Fläche."

import XCTest
@testable import Echoelmusic

final class BioComposerArrangementTests: XCTestCase {

    private func input(_ style: MusicStyle, hr: Float = 90, coh: Float = 0.4, seed: UInt64 = 7) -> BioComposer.Input {
        BioComposer.Input(heartRateBPM: hr, coherence: coh,
                          key: MusicalKey(root: 0, scale: .minor),
                          style: style, mode: .studioLocked, lockedTempo: 110, seed: seed)
    }

    private let harmonicStyles: [MusicStyle] =
        [.classical, .jazz, .synthwave, .vaporwave, .futuristic, .oriental]

    func testHarmonicTakesHaveInternalMovement() {
        // Real arrangement = several distinct note-onset positions across the bar
        // (pad + moving inner voice + lead), not one block chord on the downbeat.
        for style in harmonicStyles {
            let comp = BioComposer.compose(input(style))
            let starts = Set(comp.notes.map { $0.startStep })
            XCTAssertGreaterThanOrEqual(starts.count, 4,
                "\(style): a take must have rhythmic movement across the bar, not one surface")
        }
    }

    func testHarmonicTakesLayerSeveralElements() {
        // At least one moment where multiple voices sound at once (chord/pad + bass),
        // i.e. more notes than there are onset positions → genuine layering.
        for style in harmonicStyles {
            let comp = BioComposer.compose(input(style))
            let starts = Set(comp.notes.map { $0.startStep })
            XCTAssertGreaterThan(comp.notes.count, starts.count,
                "\(style): needs stacked voices (layers), not a single monophonic line")
        }
    }

    func testBusierBodyAddsMoreMovement() {
        // A busier body should not reduce the number of elements/onsets.
        let calm = BioComposer.compose(input(.synthwave, hr: 60, coh: 0.9))
        let busy = BioComposer.compose(input(.synthwave, hr: 120, coh: 0.1))
        XCTAssertGreaterThanOrEqual(busy.notes.count, calm.notes.count,
            "a busier take should carry at least as many elements as a calm one")
    }

    func testEveryPulseNoteStaysInKey() {
        // The new inner-pulse layer must never break the in-key guarantee.
        for style in harmonicStyles {
            let key = MusicalKey(root: 0, scale: .minor)
            let comp = BioComposer.compose(input(style))
            for note in comp.notes {
                XCTAssertTrue(key.contains(note.pitch),
                    "\(style): pulse/pad/lead pitch \(note.pitch) must be in key")
            }
        }
    }
}
