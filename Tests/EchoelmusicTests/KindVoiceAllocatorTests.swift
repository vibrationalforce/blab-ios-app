// KindVoiceAllocatorTests.swift
// Echoel — S2-W2-1 (dissolution, "Spur = Instrument"): the PURE allocator that
// binds a rank slot + its lane's voice KIND to a physical voice in the
// heterogeneous rack pool. Laws pinned here (plan §3 S2-W2-1): determinism,
// rank stability, first-rank-wins contention, poly fallback on exhaustion,
// sampler/bioVoice → poly (documented v1), zero units = the flag-OFF shape.
// Zero consumers exist yet — this slice is behavior-frozen foundation.

import XCTest
@testable import Echoelmusic

final class KindVoiceAllocatorTests: XCTestCase {

    private func allocate(_ entries: [(Int, LaneVoiceKind)],
                          drums: Int = 1, subs: Int = 1) -> [Int: PhysicalVoiceRef] {
        KindVoiceAllocator.allocate(ordered: entries.map { (slot: $0.0, kind: $0.1) },
                                    drumUnits: drums, subUnits: subs)
    }

    // MARK: - The happy path: each kind gets its physical voice

    func testAllocate_bindsEachKindToItsPhysicalVoice() {
        let map = allocate([(0, .poly), (1, .drums), (2, .subBass), (3, .poly)])
        XCTAssertEqual(map[0], .poly(0))
        XCTAssertEqual(map[1], .drums(0))
        XCTAssertEqual(map[2], .subBass(0))
        XCTAssertEqual(map[3], .poly(3))
    }

    func testAllocate_polySlotIndexIsTheRankSlot() {
        // Poly binding preserves the rank → the existing 4-voice rack addressing
        // (voice(slot:)) keeps working unchanged for poly lanes.
        let map = allocate([(0, .drums), (1, .poly), (3, .poly)])
        XCTAssertEqual(map[1], .poly(1))
        XCTAssertEqual(map[3], .poly(3))
    }

    // MARK: - Contention: first rank wins, rest fall back to poly (never silence)

    func testAllocate_secondDrumsLane_fallsBackToPoly() {
        let map = allocate([(0, .drums), (1, .drums)], drums: 1)
        XCTAssertEqual(map[0], .drums(0), "first rank wins the single kit")
        XCTAssertEqual(map[1], .poly(1), "the loser sounds like today (poly), never silence")
    }

    func testAllocate_contentionIsByRank_notInputOrder() {
        // Same entries, shuffled input — the LOWER rank must still win the kit.
        let shuffled = allocate([(2, .drums), (0, .drums)], drums: 1)
        XCTAssertEqual(shuffled[0], .drums(0))
        XCTAssertEqual(shuffled[2], .poly(2))
    }

    func testAllocate_secondSubLane_fallsBackToPoly() {
        let map = allocate([(0, .subBass), (1, .subBass)], subs: 1)
        XCTAssertEqual(map[0], .subBass(0))
        XCTAssertEqual(map[1], .poly(1))
    }

    // MARK: - v1 fallbacks (documented in the plan §6)

    func testAllocate_samplerAndBioVoice_resolveToPolyInV1() {
        let map = allocate([(0, .sampler), (1, .bioVoice)])
        XCTAssertEqual(map[0], .poly(0), "sampler lane has no sample source yet — poly fallback")
        XCTAssertEqual(map[1], .poly(1), "bioVoice kind is hold-for-founder — poly fallback")
    }

    // MARK: - Zero units = the flag-OFF shape (bit-identical to today)

    func testAllocate_zeroUnits_isAllPoly() {
        let map = allocate([(0, .drums), (1, .subBass), (2, .poly)], drums: 0, subs: 0)
        XCTAssertEqual(map[0], .poly(0))
        XCTAssertEqual(map[1], .poly(1))
        XCTAssertEqual(map[2], .poly(2))
    }

    // MARK: - Determinism + stability

    func testAllocate_isDeterministic() {
        let entries: [(Int, LaneVoiceKind)] = [(0, .drums), (1, .poly), (2, .subBass), (3, .drums)]
        let a = allocate(entries)
        for _ in 0..<10 {
            XCTAssertEqual(allocate(entries), a, "same input must always produce the same map")
        }
    }

    func testAllocate_addingAHigherRankLane_neverMovesLowerRankBindings() {
        // Reconcile stability: a NEW lane appended at a higher rank must not steal
        // or reshuffle what lower ranks already hold.
        let before = allocate([(0, .drums), (1, .poly)])
        let after = allocate([(0, .drums), (1, .poly), (2, .drums)])
        XCTAssertEqual(after[0], before[0])
        XCTAssertEqual(after[1], before[1])
        XCTAssertEqual(after[2], .poly(2), "kit is taken by rank 0 — rank 2 falls back")
    }

    func testAllocate_duplicateSlots_firstEntryWins() {
        // Defensive: a malformed duplicate slot must not flip an established binding.
        let map = allocate([(0, .drums), (0, .poly)])
        XCTAssertEqual(map[0], .drums(0))
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
        let doc = TimelineDocument(lanes: [bio, roll, drums, plain, brk], regions: [])

        XCTAssertEqual(MultiRollFanout.voiceKind(forSlot: 0, in: doc, rollLane: roll.id), .drums)
        XCTAssertEqual(MultiRollFanout.voiceKind(forSlot: 1, in: doc, rollLane: roll.id), .poly,
                       "no instrument ⇒ poly (today's voice)")
        XCTAssertEqual(MultiRollFanout.voiceKind(forSlot: 2, in: doc, rollLane: roll.id), .drums,
                       "breakLoop resolves to the drums kind (LaneVoiceKind contract)")
        XCTAssertEqual(MultiRollFanout.voiceKind(forSlot: 9, in: doc, rollLane: roll.id), .poly,
                       "out-of-range slot ⇒ poly, never a crash")
    }
}
