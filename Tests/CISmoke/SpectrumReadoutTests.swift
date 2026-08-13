// SpectrumReadoutTests.swift
// Echoel — #347 Slice 2. Blocking bundle, because the other suite cannot fail a merge (#208).
//
// ⭐ WHAT THIS PROVES, and why it runs a REAL FFT rather than a hand-built magnitude array:
// the claim under test is not "the arithmetic is the arithmetic I wrote". It is "the number
// shown above the spectrum names the note you are actually playing". That claim only holds
// end to end — window, FFT packing, bin convention, interpolation, note conversion — and any
// one of those links can be right in isolation and wrong in composition. So the test
// synthesises a sine at a known frequency, pushes it through the SAME `EchoelRealFFT` the
// view uses, and asks what the readout says.
//
// The load-bearing test is `testTheBinCentreWouldNameTheWrongNote`. Without interpolation a
// 110 Hz A2 lands in the bin centred on 93.75 Hz, which converts to MIDI 42 — F♯2, three
// semitones wrong. A readout that confidently names the wrong note is worse than no readout
// (#164/#227, the lying-control class), so that gap is what justifies the extra maths and
// it is asserted rather than asserted-about-in-a-comment.

import Foundation
import XCTest
@testable import Echoelmusic

final class SpectrumReadoutTests: XCTestCase {

    private static let sampleRate = 48000.0
    private static let fftSize = 1024          // matches SpectralDonutView's DonutState

    /// One bin is `48000 / 1024` = 46.875 Hz. Every number below is in that light.
    private static let hzPerBin = sampleRate / Double(fftSize)

    private func magnitudes(ofSineAt hz: Double) -> [Float] {
        let fft = EchoelRealFFT(size: Self.fftSize)
        let x = (0..<Self.fftSize).map {
            Float(sin(2 * Double.pi * hz * Double($0) / Self.sampleRate))
        }
        return fft.forward(x).magnitudes
    }

    // MARK: - end to end

    /// Across the instrument's real fundamental range, the readout must land within a small
    /// fraction of a bin. Measured against an independent DFT the error is ≤ 0.32 Hz; the
    /// assertion allows 2 Hz so a change in vDSP's window definition cannot turn a healthy
    /// implementation red, while still being ten times tighter than the ±20 Hz a bin centre
    /// gives — which is the whole point of the file.
    func testTheReadoutLandsWithinAFractionOfABin() {
        for hz in [82.41, 110.0, 220.0, 261.626, 440.0, 880.0, 1234.5] {
            guard let peak = SpectrumReadout.peak(magnitudes(ofSineAt: hz),
                                                  sampleRate: Self.sampleRate) else {
                return XCTFail("""
                    No peak found for a clean \(hz) Hz sine. The readout reports nothing \
                    where there is obviously something — check the fMin/fMax search bounds \
                    and the "peak on the first or last bin" rejection.
                    """)
            }
            XCTAssertEqual(peak.hz, hz, accuracy: 2.0, """
                A \(hz) Hz sine read as \(peak.hz) Hz — \(abs(peak.hz - hz)) Hz off, against \
                a bin width of \(Self.hzPerBin) Hz. Either the parabolic interpolation stopped \
                running (an offset of 0 puts you back on the bin centre) or the bin→Hz \
                convention drifted from `fftSize == magnitudes.count * 2`, which is the one \
                `SpectrumAnalysis` also uses.
                """)
        }
    }

    /// THE reason the interpolation exists. If someone "simplifies" `peak` to return the
    /// winning bin's centre frequency, this test — and only this test — catches it, because
    /// the frequency error alone still looks like a plausible small number.
    func testTheBinCentreWouldNameTheWrongNote() {
        let mags = magnitudes(ofSineAt: 110.0)
        guard let peak = SpectrumReadout.peak(mags, sampleRate: Self.sampleRate) else {
            return XCTFail("No peak for 110 Hz.")
        }
        guard let good = SpectrumReadout.nearestNote(hz: peak.hz, a4Hz: 440) else {
            return XCTFail("110 Hz did not convert to a note.")
        }
        XCTAssertEqual(good.midi, 45, """
            110 Hz must read as MIDI 45 (A2). It read as \(good.midi). A readout that names \
            the wrong note is the lying-control class this repo has paid for twice.
            """)

        // The naive reading, reconstructed here so the gap is visible in the failure output
        // rather than asserted from memory.
        var winner = 1
        for k in 1..<mags.count where mags[k] > mags[winner] { winner = k }
        let binCentre = Double(winner) * Self.hzPerBin
        let naive = SpectrumReadout.nearestNote(hz: binCentre, a4Hz: 440)
        XCTAssertNotEqual(naive?.midi, 45, """
            The bin centre (\(binCentre) Hz) now names the same note as the interpolated \
            reading. That would mean the FFT got finer or the test frequency moved onto a \
            bin boundary — in either case this test no longer demonstrates why the \
            interpolation is needed, so re-pick the frequency instead of deleting it.
            """)
    }

    // MARK: - the reference pitch

    /// A readout that assumed 440 would tell a performer tuned to 432 that every note they
    /// play is 32 cents flat. `TuningReference.a4Hz` is user-settable, so the conversion
    /// takes it as a parameter — and this pins that it is actually honoured.
    func testTheReferencePitchIsHonoured() {
        guard let at440 = SpectrumReadout.nearestNote(hz: 432, a4Hz: 440),
              let at432 = SpectrumReadout.nearestNote(hz: 432, a4Hz: 432) else {
            return XCTFail("432 Hz did not convert to a note.")
        }
        XCTAssertEqual(at432.midi, 69)
        XCTAssertEqual(at432.cents, 0, accuracy: 0.001, """
            At A4 = 432 Hz, a 432 Hz tone must read as exactly A4 with zero deviation. It \
            read \(at432.cents) cents off, so the reference pitch is being ignored.
            """)
        XCTAssertEqual(at440.midi, 69)
        XCTAssertEqual(at440.cents, -31.77, accuracy: 0.05, """
            At A4 = 440 Hz the same 432 Hz tone must read as A4 minus ~31.8 cents \
            (1200·log2(432/440)). It read \(at440.cents).
            """)
    }

    // MARK: - the edges

    /// Silence must report NOTHING. An all-zero spectrum has a perfectly valid "largest
    /// bin", and returning it would park the readout on a fixed frequency the moment the
    /// music stops — which reads as a stuck display, not as silence.
    func testSilenceReportsNoPeakAtAll() {
        XCTAssertNil(SpectrumReadout.peak([Float](repeating: 0, count: 512),
                                          sampleRate: Self.sampleRate))
    }

    /// Degenerate and hostile input must return `nil`, never trap and never invent a
    /// frequency. This runs inside a draw loop; a crash is the one outcome worse than a
    /// blank readout.
    func testDegenerateInputCannotProduceANumber() {
        XCTAssertNil(SpectrumReadout.peak([], sampleRate: Self.sampleRate))
        XCTAssertNil(SpectrumReadout.peak([1, 2], sampleRate: Self.sampleRate))
        XCTAssertNil(SpectrumReadout.peak([Float](repeating: 1, count: 512), sampleRate: 0))
        XCTAssertNil(SpectrumReadout.peak([Float](repeating: 1, count: 512),
                                          sampleRate: Self.sampleRate, fMin: 100, fMax: 50))

        // A NaN must not win the comparison and must not poison the interpolation.
        var poisoned = [Float](repeating: 0.01, count: 512)
        poisoned[40] = .nan
        poisoned[41] = .infinity
        poisoned[80] = 1.0
        let peak = SpectrumReadout.peak(poisoned, sampleRate: Self.sampleRate)
        XCTAssertNotNil(peak)
        XCTAssertTrue(peak?.hz.isFinite == true, """
            A non-finite bin produced a non-finite frequency. `Text(String(format:))` renders \
            that as "nan", which looks like a rendering bug rather than a bad input.
            """)
        XCTAssertEqual(peak?.hz ?? 0, 80 * Self.hzPerBin, accuracy: Self.hzPerBin, """
            The peak was not the genuinely largest FINITE bin. An infinity at bin 41 must be \
            skipped, not crowned.
            """)
    }

    // MARK: - the door

    /// ⛔ THIS WAS A DOOR TEST AND IS NOW A PARK TEST (#575, founder 2026-08-13). He circled
    /// the whole Signal block on a v10.79.388 screenshot — wavefront, spectrum, both captions,
    /// the `63,0 Hz · B1 +36 ct` readout — and wrote *"Das Brauch da nicht sein. Wenn dann ins
    /// Visual Window übertragen."* `signalSection` is gone, so both assertions that demanded a
    /// mount would have gone red on a correct tree (#364: a guard must not forbid legitimate
    /// work, and an explicit founder instruction is the most legitimate work there is).
    ///
    /// ⚠️ THE SENTENCE THAT STOOD HERE IS STILL TRUE AND NOW CUTS THE OTHER WAY: *"a meter
    /// nobody can open is worth nothing, and this repo keeps a shelf of exactly that."* The
    /// spectrum has joined that shelf. The difference from `SpectralDonutView` — the example
    /// that sentence named — is that this one is parked BY DECISION and the decision is
    /// written at the removal site, which is precisely what turns an orphan into a park
    /// (`doctor` section C: the defect is "unreachable AND written down nowhere").
    ///
    /// So what is asserted is the promise: the file is intact and one line restores it. The
    /// numeric guarantees below (`SpectrumReadout`, the decimal separator, the peak
    /// definition) are UNTOUCHED and still end-to-end — parking a view does not make its
    /// arithmetic wrong, and they are what a re-mount will need to still hold.
    func testTheParkedSpectrumStillExistsAsAFile() throws {
        let code = try source("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        let view = try source("Sources/Echoelmusic/Studio/AnalysisSpectrumView.swift")
        XCTAssertTrue(view.contains("struct AnalysisSpectrumView"), """
            `AnalysisSpectrumView.swift` no longer declares `AnalysisSpectrumView`. It is \
            PARKED, not deleted — the removal note in `EchoelStudioView` promises that \
            restoring it costs one line, and that promise needs the file. If it was genuinely \
            deleted, delete this test with it and say so in the commit.
            """)
        XCTAssertFalse(code.contains("AnalysisSpectrumView(reduceMotion:"), """
            `EchoelStudioView` constructs `AnalysisSpectrumView` again. #575 removed the mount \
            on an explicit founder instruction. If it is being re-mounted on a NEW ask — most \
            likely the "wenn dann ins Visual Window" half he left open — this assertion moves \
            in the same commit and points at the new host; it must not come back silently, and \
            it must not come back into the Field panel.
            """)
    }

    /// The peak readout must go through `EchoelDecimalText`, not `String(format:)` (#267).
    /// A German reader who sets a comma everywhere else must not meet a lone "220.1 Hz".
    func testTheReadoutUsesTheAppsDecimalSeparator() throws {
        let code = try source("Sources/Echoelmusic/Studio/AnalysisSpectrumView.swift")
        XCTAssertTrue(code.contains("EchoelDecimalText.string(peak.hz"), """
            The peak frequency is no longer formatted through `EchoelDecimalText`. #267 \
            removed exactly this class of lone `String(format: "%.1f")` — one surface \
            printing a point while every other prints a comma is the defect, not the format.
            """)
    }

    private func source(_ path: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources/Echoelmusic").path) else {
            throw XCTSkip("""
                Source tree not reachable from the test bundle — skipping rather than \
                reporting a green this file did not earn.
                """)
        }
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// The interpolation's own guard rails, isolated. A flat or symmetric group must fall
    /// back to the bin centre — 0, not a division by a near-zero denominator.
    func testTheOffsetStaysInsideItsOwnBin() {
        XCTAssertEqual(SpectrumReadout.subBinOffset([1, 1, 1], at: 1), 0, accuracy: 1e-12)
        XCTAssertEqual(SpectrumReadout.subBinOffset([0.5, 1, 0.5], at: 1), 0, accuracy: 1e-12, """
            A symmetric peak must interpolate to its own centre. Any other answer means the \
            numerator and denominator are not the parabola's.
            """)
        // Asymmetric: the vertex leans toward the taller neighbour, and never leaves the bin.
        let right = SpectrumReadout.subBinOffset([0.2, 1, 0.9], at: 1)
        XCTAssertGreaterThan(right, 0)
        XCTAssertLessThanOrEqual(right, 0.5)
        let left = SpectrumReadout.subBinOffset([0.9, 1, 0.2], at: 1)
        XCTAssertLessThan(left, 0)
        XCTAssertGreaterThanOrEqual(left, -0.5)
        // Out of range and non-finite: 0, not a crash.
        XCTAssertEqual(SpectrumReadout.subBinOffset([1, 2, 3], at: 0), 0)
        XCTAssertEqual(SpectrumReadout.subBinOffset([1, 2, 3], at: 2), 0)
        XCTAssertEqual(SpectrumReadout.subBinOffset([.nan, 1, 0.5], at: 1), 0)
        // A zero neighbour must floor, not go to -inf and produce a NaN offset.
        XCTAssertTrue(SpectrumReadout.subBinOffset([0, 1, 0.5], at: 1).isFinite)
    }
}
