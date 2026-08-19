// BioSoundMappingTests.swift
// Pins the fixed body→sound routing map (REIHENFOLGE item 2: "which parameters does
// my biofeedback move?"). This is a STABLE design fact rendered in the reachable bio
// guide — a pure value, so it needs no live 10 Hz observation and is CI-verifiable.
// The routing (which source drives which target) mirrors EchoelDDSP.applyBioReactive.

import XCTest
@testable import Echoelmusic

final class BioSoundMappingTests: XCTestCase {

    func testMapCoversTheFourStripMetrics_inStripOrder() {
        // Same four sources the bio strip shows, same display order (HR·HRV·Coh·Breath),
        // so the guide reads top-to-bottom consistently with the strip.
        XCTAssertEqual(BioSoundMapping.all.map(\.id),
                       ["heartRate", "hrv", "coherence", "breath"])
    }

    func testEveryEntryIsFullyPopulated() {
        for m in BioSoundMapping.all {
            XCTAssertFalse(m.source.isEmpty, "\(m.id) needs a source label")
            XCTAssertFalse(m.target.isEmpty, "\(m.id) needs a target label")
            XCTAssertFalse(m.direction.isEmpty, "\(m.id) needs a direction phrase")
        }
    }

    func testIdsAreUnique() {
        XCTAssertEqual(Set(BioSoundMapping.all.map(\.id)).count, BioSoundMapping.all.count)
    }

    // The routing targets must match the real applyBioReactive design (audited):
    // coherence→brightness/filter/harmonics, HR→vibrato, HRV→brightness, breath→filter motion.
    //
    // ⛔ THIS ASSERTION USED TO DEFEND THE OVER-CLAIM IT EXISTS TO PREVENT (#638). It read
    // `target("hrv").contains("reverb") || contains("space")` and its comment said
    // "HRV→reverb", so a session correcting the copy would have been turned RED by the guard
    // over it. The write is real — `applyBioReactive` sets `reverbMix` from `hrvVariability` —
    // but `reverbMix`'s only reader sits inside `if Self.useConvolutionReverb`, a flag that is
    // `false` with no assignment in `Sources/`. CLAUDE.md struck the mapping at #546 and this
    // file was not among the places it corrected.
    //
    // ⚠️ Two lessons, and the second is the uncomfortable one. (1) A routing pin must follow
    // the value to an UNGATED READ, not to a write. (2) A test can be the thing that KEEPS a
    // false claim alive: it made the wrong copy load-bearing, so removing the claim looked
    // like breaking a guarantee. That is worse than no test, and it is the mirror of #364 —
    // there a guard forbids correct work by accident, here it forbade it on purpose because
    // its premise was wrong.
    //
    // ⚠️ `Tests/EchoelmusicTests` is compiled by NO gate (#208), so this assertion has never
    // actually run in CI. It is fixed here anyway: an unexecuted assertion is still read by
    // the next session as a statement of what the routing IS.
    func testRoutingTargetsMatchTheEngineDesign() {
        func target(_ id: String) -> String {
            BioSoundMapping.all.first { $0.id == id }?.target.lowercased() ?? ""
        }
        XCTAssertTrue(target("coherence").contains("filter") || target("coherence").contains("bright"))
        XCTAssertTrue(target("heartRate").contains("vibrato"))
        XCTAssertTrue(target("hrv").contains("bright") || target("hrv").contains("tone"), """
            HRV's target must name what it actually moves. `hrvDev` is one of three terms \
            summed into `targetBrightness` on the anchored-patch path, and it is the only \
            thing HRV moves unconditionally.
            """)
        XCTAssertFalse(target("hrv").contains("reverb"), """
            HRV's target names the reverb again. `reverbMix` IS written from HRV, and its \
            only reader is gated on `EchoelDDSP.useConvolutionReverb`, which is false with no \
            writer in `Sources/` — so nothing sounds. ⚠️ A player CAN already make HRV move \
            the ALGORITHMIC `EchoelReverb` by building an FX bio route (`FXBioModulator` \
            writes `c.reverb.mix`; the door is `EchoelFXView`'s "Add bio modulation…"), but \
            that is a route he chose, not an automatic mapping, and this table describes only \
            automatic ones. If the row is ever meant to describe that, change this assertion \
            in the same commit.
            """)
        XCTAssertTrue(target("breath").contains("filter") || target("breath").contains("swell"))
    }

    // No wellness/therapy/esoteric claim anywhere in the copy (brand red line).
    func testCopyMakesNoHealthClaim() {
        let banned = ["heal", "cure", "therapy", "medical", "diagnos", "chakra", "solfeggio"]
        for m in BioSoundMapping.all {
            let blob = "\(m.source) \(m.target) \(m.direction)".lowercased()
            for word in banned {
                XCTAssertFalse(blob.contains(word), "\(m.id) copy must not contain '\(word)'")
            }
        }
    }
}
