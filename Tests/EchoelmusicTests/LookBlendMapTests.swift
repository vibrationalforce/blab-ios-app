//
//  LookBlendMapTests.swift
//  Echoelmusic — the stufenlos look slider's pure position ⇄ crossfade mapping.
//

import XCTest
@testable import Echoelmusic

final class LookBlendMapTests: XCTestCase {

    func testExactStops_renderPureLooks() {
        for (i, style) in LookBlendMap.looks.enumerated() {
            let m = LookBlendMap.blend(at: Double(i))
            XCTAssertEqual(m.a, style, "stop \(i) is pure look \(style)")
            XCTAssertEqual(m.b, style, "no B pass at a stop")
            XCTAssertEqual(m.frac, 0)
        }
    }

    func testMidPositions_crossfadeBetweenNeighbours() {
        let m = LookBlendMap.blend(at: 1.4)
        XCTAssertEqual(m.a, LookBlendMap.looks[1])
        XCTAssertEqual(m.b, LookBlendMap.looks[2])
        XCTAssertEqual(m.frac, 0.4, accuracy: 0.001)
    }

    func testClamping_andGarbageInputs() {
        XCTAssertEqual(LookBlendMap.blend(at: -3), LookBlendMap.blend(at: 0))
        XCTAssertEqual(LookBlendMap.blend(at: 99), LookBlendMap.blend(at: LookBlendMap.maxPosition))
        XCTAssertEqual(LookBlendMap.blend(at: .nan).a, LookBlendMap.looks[0],
                       "NaN clamps to the first look instead of crashing the slider")
    }

    func testRoundTrip_positionSurvivesPersistence() {
        // The slider must reopen where the user left it: position → (a,b,frac) → position.
        for p in stride(from: 0.0, through: LookBlendMap.maxPosition, by: 0.25) {
            let m = LookBlendMap.blend(at: p)
            let back = LookBlendMap.position(a: m.a, b: m.b, frac: m.frac)
            XCTAssertEqual(back, p, accuracy: 0.01, "round-trip at \(p)")
        }
    }

    func testRetiredStyle_readsAsPositionZero() {
        // A persisted busy look (e.g. Prism = 4) is not on the slider — read as 0,
        // never a crash or a bogus position.
        XCTAssertEqual(LookBlendMap.position(a: 4, b: 0, frac: 0), 0)
    }

    func testNearestName_matchesTheCloserStop() {
        XCTAssertEqual(LookBlendMap.nearestName(at: 0), LookBlendMap.names[0])
        XCTAssertEqual(LookBlendMap.nearestName(at: 1.6), LookBlendMap.names[2])
        XCTAssertEqual(LookBlendMap.nearestName(at: 99), LookBlendMap.names.last)
    }

    func testListsStayInSync() {
        XCTAssertEqual(LookBlendMap.looks.count, LookBlendMap.names.count,
                       "every look needs a display name")
    }
}
