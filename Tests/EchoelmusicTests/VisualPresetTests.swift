// VisualPresetTests.swift
// Echoel — immersive visual presets stay inside the clamped, flash-safe ranges.

import XCTest
@testable import Echoelmusic

final class VisualPresetTests: XCTestCase {

    func testFactorySpansAuraToZentrifuge() {
        let f = VisualPreset.factory
        XCTAssertGreaterThanOrEqual(f.count, 8, "a useful spread of presets")
        XCTAssertEqual(f.first?.name, "Aura", "ordered softest-first")
        XCTAssertEqual(f.last?.name, "Zentrifuge", "…to most energetic")
        // Ordering intent: energy (intensity·motion·detail) trends upward.
        let energy = { (p: VisualPreset) in Double(p.intensity * p.motion) * Double(p.detail) }
        XCTAssertLessThan(energy(f.first!), energy(f.last!), "Aura is calmer than Zentrifuge")
    }

    func testAllPresetsWithinSafeSliderRanges() {
        for p in VisualPreset.factory {
            XCTAssert((0...1.5).contains(p.intensity), "\(p.name) intensity in range")
            XCTAssert((8...90).contains(p.detail), "\(p.name) detail in range")
            XCTAssert((0...1.5).contains(p.motion), "\(p.name) motion ≤1.5 (flash-safe headroom)")
            XCTAssert((0.5...1.5).contains(p.spread), "\(p.name) spread in range")
        }
    }

    func testInitClampsOutOfRange() {
        let p = VisualPreset(id: "x", name: "X", intensity: 9, detail: 999, motion: -3,
                             spread: 9, blurb: "")
        XCTAssertEqual(p.intensity, 1.5)
        XCTAssertEqual(p.detail, 90)
        XCTAssertEqual(p.motion, 0)
        XCTAssertEqual(p.spread, 1.5)
    }

    func testStableUniqueIDs() {
        let ids = VisualPreset.factory.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "preset ids are unique (stable selection)")
    }
}
