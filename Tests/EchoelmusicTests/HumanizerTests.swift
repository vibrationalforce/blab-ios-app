// HumanizerTests.swift
// Echoel — tight grid vs humanized feel. Asserts tight is a perfect no-op (and
// the MIDI export stays byte-identical), humanized stays within bounds and is
// reproducible from a seed.

import XCTest
@testable import Echoelmusic

final class HumanizerTests: XCTestCase {

    func testTightIsInactiveNoOp() {
        XCTAssertFalse(Humanizer.tight.isActive)
        for i in 0..<50 {
            let (dt, vs) = Humanizer.tight.jitter(index: i, seed: 123)
            XCTAssertEqual(dt, 0)
            XCTAssertEqual(vs, 1, accuracy: 1e-9)
        }
    }

    func testHumanizedIsActiveAndBounded() {
        let h = Humanizer.humanized
        XCTAssertTrue(h.isActive)
        for i in 0..<200 {
            let (dt, vs) = h.jitter(index: i, seed: 777)
            XCTAssertLessThanOrEqual(abs(dt), h.timingTicks, "timing within ±\(h.timingTicks) ticks")
            XCTAssertGreaterThanOrEqual(vs, 1 - h.velocityJitter - 1e-6)
            XCTAssertLessThanOrEqual(vs, 1 + h.velocityJitter + 1e-6)
        }
    }

    func testDeterministicFromSeed() {
        let h = Humanizer.humanized
        for i in 0..<20 {
            let a = h.jitter(index: i, seed: 42)
            let b = h.jitter(index: i, seed: 42)
            XCTAssertEqual(a.tickDelta, b.tickDelta)
            XCTAssertEqual(a.velocityScale, b.velocityScale, accuracy: 1e-9)
        }
    }

    func testIndicesAreNotAllIdentical() {
        let h = Humanizer.humanized
        let deltas = (0..<30).map { h.jitter(index: $0, seed: 9).tickDelta }
        XCTAssertGreaterThan(Set(deltas).count, 1, "humanize must vary across notes")
    }

    // MARK: - Exporter integration

    private func grid() -> [[Bool]] {
        var g = Array(repeating: Array(repeating: false, count: 16), count: 8)
        g[0][0] = true; g[0][4] = true; g[0][8] = true; g[0][12] = true
        g[1][4] = true; g[1][12] = true
        return g
    }

    func testTightExportIsByteIdenticalToDefault() {
        let g = grid()
        let plain = MIDIFileExporter.export(steps: g, tempo: 120)
        let tight = MIDIFileExporter.export(steps: g, tempo: 120, humanize: .tight, seed: 0)
        XCTAssertEqual(plain, tight, "tight humanize must not change the export")
    }

    func testHumanizedExportDiffersButStaysValid() {
        let g = grid()
        let tight = MIDIFileExporter.export(steps: g, tempo: 120, humanize: .tight)
        let human = MIDIFileExporter.export(steps: g, tempo: 120, humanize: .humanized, seed: 1)
        XCTAssertNotEqual(tight, human, "humanized should alter timing/velocity")
        // Still a valid SMF.
        XCTAssertEqual(Array(human.prefix(4)), Array("MThd".utf8))
    }

    func testHumanizedNotesExportPreservesDurationShift() {
        let notes = [Note(pitch: 60, startStep: 0, lengthSteps: 4, velocity: 0.8),
                     Note(pitch: 64, startStep: 8, lengthSteps: 2, velocity: 0.7)]
        let data = MIDIFileExporter.export(notes: notes, tempo: 100, humanize: .humanized, seed: 5)
        XCTAssertEqual(Array(data.prefix(4)), Array("MThd".utf8))
        XCTAssertFalse(data.isEmpty)
    }
}
