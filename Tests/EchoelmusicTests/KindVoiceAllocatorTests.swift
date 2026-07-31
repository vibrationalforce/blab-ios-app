// KindVoiceAllocatorTests.swift
// Echoel — S2-W2-1 (dissolution, "Spur = Instrument"): the PURE allocator that
// binds a rank slot + its lane's voice KIND to a physical voice in the
// heterogeneous rack pool. Laws pinned here (plan §3 S2-W2-1): determinism,
// rank stability, first-rank-wins contention, poly fallback on exhaustion,
// sampler → its unit when one exists (S2-W3), bioVoice → poly (documented v1),
// zero units = the flag-OFF shape.
//
// ⛔ THE `.drums` TESTS CHANGED MEANING WITH #167, THEY WERE NOT DELETED. `PhysicalVoiceRef`
// no longer HAS a `.drums` case, so nothing can assert `.drums(0)` any more — but
// `LaneVoiceKind.drums` still exists, and what a drums lane resolves to is worth pinning:
// it must come back as a playable poly voice and never as silence. The contention/stability
// laws moved onto `.subBass`, which still has a physical unit and can therefore still lose one.
// ⛔ "as a persisted rawValue" stood here and is FALSE — `LaneVoiceKind` has no `Codable`
// conformance and never reaches disk (`Timeline.swift` says so; `TrackInstrument` is the one
// persisted lane enum). The test earns its place on the never-silence law alone.

import XCTest
@testable import Echoelmusic

final class KindVoiceAllocatorTests: XCTestCase {

    private func allocate(_ entries: [(Int, LaneVoiceKind)],
                          subs: Int = 1,
                          samplers: Int = 1) -> [Int: PhysicalVoiceRef] {
        KindVoiceAllocator.allocate(ordered: entries.map { (slot: $0.0, kind: $0.1) },
                                    subUnits: subs, samplerUnits: samplers)
    }

    // MARK: - The happy path: each kind gets its physical voice

    func testAllocate_bindsEachKindToItsPhysicalVoice() {
        let map = allocate([(0, .poly), (1, .sampler), (2, .subBass), (3, .poly)])
        XCTAssertEqual(map[0], .poly(0))
        XCTAssertEqual(map[1], .sampler(0))
        XCTAssertEqual(map[2], .subBass(0))
        XCTAssertEqual(map[3], .poly(3))
    }

    /// #167: the kind survives its voice. A lane persisted as `.drums` must resolve to a
    /// SOUNDING poly voice — the failure this pins is silence, which is what would happen if
    /// someone "cleaned up" the `.drums` arm out of the fallback list.
    func testAllocate_drumsKind_alwaysResolvesToPoly() {
        XCTAssertEqual(allocate([(0, .drums)])[0], .poly(0))
        // Both lanes asserted, not just the second: two drums lanes must land on their OWN
        // poly slots. Checking only slot 1 would pass even if slot 0 vanished from the map.
        let two = allocate([(0, .drums), (1, .drums)])
        XCTAssertEqual(two[0], .poly(0), "two drums lanes: the first is poly, not silent")
        XCTAssertEqual(two[1], .poly(1), "two drums lanes: the second gets its OWN poly slot")
    }

    func testAllocate_polySlotIndexIsTheRankSlot() {
        // Poly binding preserves the rank → the existing 4-voice rack addressing
        // (voice(slot:)) keeps working unchanged for poly lanes.
        let map = allocate([(0, .subBass), (1, .poly), (3, .poly)])
        XCTAssertEqual(map[1], .poly(1))
        XCTAssertEqual(map[3], .poly(3))
    }

    // MARK: - Contention: first rank wins, rest fall back to poly (never silence)

    func testAllocate_contentionIsByRank_notInputOrder() {
        // Same entries, shuffled input — the LOWER rank must still win the unit.
        let shuffled = allocate([(2, .subBass), (0, .subBass)], subs: 1)
        XCTAssertEqual(shuffled[0], .subBass(0))
        XCTAssertEqual(shuffled[2], .poly(2))
    }

    func testAllocate_secondSubLane_fallsBackToPoly() {
        let map = allocate([(0, .subBass), (1, .subBass)], subs: 1)
        XCTAssertEqual(map[0], .subBass(0))
        XCTAssertEqual(map[1], .poly(1))
    }

    // MARK: - Sampler (S2-W3) + the v1 bioVoice fallback (plan §6)

    func testAllocate_samplerLane_bindsTheSamplerUnit() {
        let map = allocate([(0, .sampler), (1, .poly)])
        XCTAssertEqual(map[0], .sampler(0), "a sampler lane gets the sampler unit (S2-W3)")
        XCTAssertEqual(map[1], .poly(1))
    }

    func testAllocate_secondSamplerLane_fallsBackToPoly() {
        let map = allocate([(0, .sampler), (2, .sampler)], samplers: 1)
        XCTAssertEqual(map[0], .sampler(0), "first rank wins the single sampler unit")
        XCTAssertEqual(map[2], .poly(2), "the loser sounds like today (poly), never silence")
    }

    func testAllocate_zeroSamplerUnits_fallsBackToPoly() {
        let map = allocate([(0, .sampler)], samplers: 0)
        XCTAssertEqual(map[0], .poly(0), "no sampler unit ⇒ poly fallback (the flag-OFF shape)")
    }

    func testAllocate_bioVoice_resolvesToPolyInV1() {
        let map = allocate([(0, .bioVoice)])
        XCTAssertEqual(map[0], .poly(0), "bioVoice kind is hold-for-founder — poly fallback")
    }

    // MARK: - Zero units = the flag-OFF shape (bit-identical to today)

    func testAllocate_zeroUnits_isAllPoly() {
        let map = allocate([(0, .drums), (1, .subBass), (2, .poly), (3, .sampler)],
                           subs: 0, samplers: 0)
        XCTAssertEqual(map[0], .poly(0))
        XCTAssertEqual(map[1], .poly(1))
        XCTAssertEqual(map[2], .poly(2))
        XCTAssertEqual(map[3], .poly(3))
    }

    // MARK: - Determinism + stability

    func testAllocate_isDeterministic() {
        let entries: [(Int, LaneVoiceKind)] = [(0, .drums), (1, .poly), (2, .subBass), (3, .sampler)]
        let a = allocate(entries)
        for _ in 0..<10 {
            XCTAssertEqual(allocate(entries), a, "same input must always produce the same map")
        }
    }

    func testAllocate_addingAHigherRankLane_neverMovesLowerRankBindings() {
        // Reconcile stability: a NEW lane appended at a higher rank must not steal
        // or reshuffle what lower ranks already hold.
        let before = allocate([(0, .subBass), (1, .poly)])
        let after = allocate([(0, .subBass), (1, .poly), (2, .subBass)])
        XCTAssertEqual(after[0], before[0])
        XCTAssertEqual(after[1], before[1])
        XCTAssertEqual(after[2], .poly(2), "the sub unit is taken by rank 0 — rank 2 falls back")
    }

    func testAllocate_duplicateSlots_firstEntryWins() {
        // Defensive: a malformed duplicate slot must not flip an established binding.
        let map = allocate([(0, .subBass), (0, .poly)])
        XCTAssertEqual(map[0], .subBass(0))
        XCTAssertEqual(map.count, 1)
    }

    func testAllocate_emptyInput_isEmpty() {
        XCTAssertTrue(allocate([]).isEmpty)
    }

    // MARK: - MultiRollFanout.voiceKind (the document → kind read)

    func testVoiceKind_readsTheLanesInstrument_elsePoly() {
        let bio = TimelineLane(name: "Bio", kind: .midi, isBio: true)
        let roll = TimelineLane(name: "MIDI 1", kind: .midi)
        let drums = TimelineLane(name: "EchoelDrums", kind: .midi, builtinInstrument: .drums)
        let plain = TimelineLane(name: "MIDI 3", kind: .midi)
        let brk = TimelineLane(name: "EchoelBreak", kind: .midi, builtinInstrument: .breakLoop)
        let sub = TimelineLane(name: "EchoelSub", kind: .midi, builtinInstrument: .subBass)
        let doc = TimelineDocument(lanes: [bio, roll, drums, plain, brk, sub], regions: [])

        // NO DRUMS (founder 2026-07-26) — a persisted `.drums`/`.breakLoop` lane now
        // resolves to `.poly`, so slots 0 and 2 are melodic. On their own those two
        // assertions could not tell "read the lane, got poly" from "read nothing"; the
        // `.subBass` lane at slot 3 is what keeps the slot-read claim provable.
        XCTAssertEqual(MultiRollFanout.voiceKind(forSlot: 0, in: doc, rollLane: roll.id), .poly,
                       "a pre-existing drums lane comes back melodic, not silent")
        XCTAssertEqual(MultiRollFanout.voiceKind(forSlot: 1, in: doc, rollLane: roll.id), .poly,
                       "no instrument ⇒ poly (today's voice)")
        XCTAssertEqual(MultiRollFanout.voiceKind(forSlot: 2, in: doc, rollLane: roll.id), .poly,
                       "breakLoop was the other drums alias — also melodic now")
        XCTAssertEqual(MultiRollFanout.voiceKind(forSlot: 3, in: doc, rollLane: roll.id), .subBass,
                       "the slot→lane read itself still works (non-poly kind survives)")
        XCTAssertEqual(MultiRollFanout.voiceKind(forSlot: 9, in: doc, rollLane: roll.id), .poly,
                       "out-of-range slot ⇒ poly, never a crash")
    }
}
