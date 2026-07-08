//
//  LookBlendMapTests.swift
//  Echoelmusic — the stufenlos look slider's pure position ⇄ crossfade mapping, now
//  over a USER-CUSTOMIZABLE sequence (founder 2026-07-08: "man soll das was im slider
//  passiert selbst customizen … mehr Optionen"). All mapping takes the active sequence.
//

import XCTest
@testable import Echoelmusic

final class LookBlendMapTests: XCTestCase {

    private let seq = LookBlendMap.defaultSequence   // [3, 5, 1] — Water · Aurora · Cymatics

    func testExactStops_renderPureLooks() {
        for (i, style) in seq.enumerated() {
            let m = LookBlendMap.blend(at: Double(i), sequence: seq)
            XCTAssertEqual(m.a, style, "stop \(i) is pure look \(style)")
            XCTAssertEqual(m.b, style, "no B pass at a stop")
            XCTAssertEqual(m.frac, 0)
        }
    }

    func testMidPositions_crossfadeBetweenNeighbours() {
        let m = LookBlendMap.blend(at: 1.4, sequence: seq)
        XCTAssertEqual(m.a, seq[1])
        XCTAssertEqual(m.b, seq[2])
        XCTAssertEqual(m.frac, 0.4, accuracy: 0.001)
    }

    func testClamping_andGarbageInputs() {
        let maxP = LookBlendMap.maxPosition(for: seq)
        XCTAssertEqual(LookBlendMap.blend(at: -3, sequence: seq), LookBlendMap.blend(at: 0, sequence: seq))
        XCTAssertEqual(LookBlendMap.blend(at: 99, sequence: seq), LookBlendMap.blend(at: maxP, sequence: seq))
        XCTAssertEqual(LookBlendMap.blend(at: .nan, sequence: seq).a, seq[0],
                       "NaN clamps to the first look instead of crashing the slider")
    }

    func testRoundTrip_positionSurvivesPersistence() {
        // The slider must reopen where the user left it: position → (a,b,frac) → position.
        for p in stride(from: 0.0, through: LookBlendMap.maxPosition(for: seq), by: 0.25) {
            let m = LookBlendMap.blend(at: p, sequence: seq)
            let back = LookBlendMap.position(a: m.a, b: m.b, frac: m.frac, sequence: seq)
            XCTAssertEqual(back, p, accuracy: 0.01, "round-trip at \(p)")
        }
    }

    func testStyleNotInSequence_readsAsPositionZero() {
        // A persisted look that isn't on the current slider sequence (retired, or the
        // sequence was edited) reads as position 0 — never a crash or a bogus position.
        // 0 = Rings, not in the default [3,5,1] sequence.
        XCTAssertEqual(LookBlendMap.position(a: 0, b: 3, frac: 0, sequence: seq), 0)
    }

    func testNearestName_matchesTheCloserStop() {
        XCTAssertEqual(LookBlendMap.nearestName(at: 0, sequence: seq), LookBlendMap.name(for: seq[0]))
        XCTAssertEqual(LookBlendMap.nearestName(at: 1.6, sequence: seq), LookBlendMap.name(for: seq[2]))
        XCTAssertEqual(LookBlendMap.nearestName(at: 99, sequence: seq), LookBlendMap.name(for: seq.last!))
    }

    // MARK: - Customizable sequence

    func testSequenceParse_dropsGarbageAndDeduplicates() {
        XCTAssertEqual(LookBlendMap.sequence(from: "3,5,1"), [3, 5, 1])
        XCTAssertEqual(LookBlendMap.sequence(from: " 3 , 5 ,5, x, 99 "), [3, 5],
                       "trims spaces, drops dupes, drops out-of-range & non-numeric")
        XCTAssertEqual(LookBlendMap.sequence(from: ""), LookBlendMap.defaultSequence,
                       "empty falls back to the calm default")
        XCTAssertEqual(LookBlendMap.sequence(from: "nonsense"), LookBlendMap.defaultSequence)
    }

    func testSequenceParse_dropsRetiredLookIndices() {
        // Pre-curation persisted sequences may carry retired looks (2 Plasma, 4 Prism,
        // 7 Depth, 8 Scope, 9 Fractal) — they are dropped gracefully, the rest stays.
        XCTAssertEqual(LookBlendMap.sequence(from: "3,5,7,2"), [3, 5],
                       "the old default keeps its curated survivors")
        XCTAssertEqual(LookBlendMap.sequence(from: "3,5,1,4"), [3, 5, 1],
                       "the brief Prism-era default drops Prism, keeps the rest")
        XCTAssertEqual(LookBlendMap.sequence(from: "7,8,9,2,4"), LookBlendMap.defaultSequence,
                       "an all-retired sequence falls back to the default")
    }

    func testStringRoundTrip() {
        let s = LookBlendMap.string(from: [3, 5, 1])
        XCTAssertEqual(s, "3,5,1")
        XCTAssertEqual(LookBlendMap.sequence(from: s), [3, 5, 1])
    }

    func testToggling_addsInCanonicalOrder_andRemoves() {
        // Add 0 (Rings) to [3,5,1] → canonical library order puts it first.
        XCTAssertEqual(LookBlendMap.toggling(0, in: [3, 5, 1]), [0, 1, 3, 5])
        // Remove an existing look.
        XCTAssertEqual(LookBlendMap.toggling(5, in: [3, 5, 1]), [3, 1])
    }

    func testToggling_neverEmptiesTheSequence() {
        // The slider must always have at least one look to show.
        XCTAssertEqual(LookBlendMap.toggling(3, in: [3]), [3],
                       "removing the last look is refused")
    }

    func testMaxPosition_isZeroForSingleLook() {
        XCTAssertEqual(LookBlendMap.maxPosition(for: [3]), 0)
        XCTAssertEqual(LookBlendMap.maxPosition(for: [3, 5, 1]), 2)
    }

    func testEmptySequence_fallsBackGracefully() {
        // Defensive: blend/position on an empty sequence use the default, never crash.
        let m = LookBlendMap.blend(at: 1.0, sequence: [])
        XCTAssertTrue(LookBlendMap.defaultSequence.contains(m.a))
    }

    func testLibrary_isTheCuratedSoundLinkedRoster() {
        // Curation 2026-07-08 ("weniger ist mehr" + "Prism soll weg"): five looks,
        // each sound/bio-linked, in canonical (ascending) order. Retired: 2 Plasma,
        // 4 Prism, 7 Depth, 8 Scope, 9 Fractal (still compiled in the shader,
        // reversible).
        XCTAssertEqual(LookBlendMap.library.map(\.index), [0, 1, 3, 5, 6])
        XCTAssertEqual(LookBlendMap.library.map(\.index), LookBlendMap.library.map(\.index).sorted(),
                       "canonical order stays ascending so toggling() inserts sensibly")
        // The default sequence only uses curated looks.
        for i in LookBlendMap.defaultSequence {
            XCTAssertTrue(LookBlendMap.library.contains { $0.index == i })
        }
    }
}
