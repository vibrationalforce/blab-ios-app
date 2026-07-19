// MIDIFileExporterTempoTests.swift
// Pins the SMF tempo meta 3-byte field. A very slow tempo must SATURATE at the
// format max (0xFFFFFF ≈ 3.576 BPM) instead of overflowing — dropping the top
// byte, which read back ~6× too fast. Realistic tempos stay byte-identical.
// tempoMeta is the single source of truth shared by grid/notes/combined export.

import XCTest
@testable import Echoelmusic

final class MIDIFileExporterTempoTests: XCTestCase {

    // tempoMeta = [0x00, 0xFF, 0x51, 0x03, b16, b8, b0]
    private func tempoField(_ bytes: [UInt8]) -> UInt32 {
        precondition(bytes.count == 7, "tempoMeta is a 7-byte event")
        return (UInt32(bytes[4]) << 16) | (UInt32(bytes[5]) << 8) | UInt32(bytes[6])
    }

    func testTempoMeta_normalTempo_isExactAndByteIdentical() {
        // 120 BPM → 500000 µs/quarter = 0x07A120, well under the 3-byte max.
        let m = MIDIFileExporter.tempoMeta(120)
        XCTAssertEqual(Array(m.prefix(4)), [0x00, 0xFF, 0x51, 0x03])
        XCTAssertEqual(tempoField(m), 500_000)
        XCTAssertEqual(Array(m.suffix(3)), [0x07, 0xA1, 0x20])
    }

    func testTempoMeta_verySlowTempo_saturatesAt3ByteMax_noOverflow() {
        // 1 BPM → 60_000_000 µs/quarter does NOT fit the 3-byte field. It must
        // clamp to 0xFFFFFF (~3.576 BPM), NOT overflow to 0x93 0x87 0x00 (which a
        // DAW reads as ~6.21 BPM).
        let m = MIDIFileExporter.tempoMeta(1)
        XCTAssertEqual(tempoField(m), 0xFF_FFFF)
        XCTAssertEqual(Array(m.suffix(3)), [0xFF, 0xFF, 0xFF])
        XCTAssertNotEqual(Array(m.suffix(3)), [0x93, 0x87, 0x00], "the old overflow bytes")
    }

    func testTempoMeta_boundary_saturatesAtAndBelowFormatFloor() {
        // Slowest exactly-representable tempo ≈ 60_000_000 / 0xFFFFFF ≈ 3.576 BPM.
        let justAbove = 60_000_000.0 / Double(0xFF_FFFF) + 0.05   // ~3.63 BPM
        XCTAssertLessThan(tempoField(MIDIFileExporter.tempoMeta(justAbove)), 0xFF_FFFF)
        XCTAssertEqual(tempoField(MIDIFileExporter.tempoMeta(3.0)), 0xFF_FFFF, "3 BPM saturates")
    }

    func testExportEmbedsTempoMeta_gridAndNotes() {
        // Grid and notes exporters embed the SAME tempoMeta bytes (dedupe holds).
        let expected = MIDIFileExporter.tempoMeta(90)
        XCTAssertTrue(contains(MIDIFileExporter.export(steps: [[true, false]], tempo: 90),
                               subsequence: expected), "grid export embeds tempoMeta")
        XCTAssertTrue(contains(MIDIFileExporter.export(notes: [], tempo: 90),
                               subsequence: expected), "notes export embeds tempoMeta")
    }

    private func contains(_ data: Data, subsequence: [UInt8]) -> Bool {
        let bytes = [UInt8](data)
        guard subsequence.count <= bytes.count, !subsequence.isEmpty else { return false }
        for start in 0...(bytes.count - subsequence.count)
        where Array(bytes[start..<start + subsequence.count]) == subsequence {
            return true
        }
        return false
    }
}
