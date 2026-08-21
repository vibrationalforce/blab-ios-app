// AGrainCannotClickOrRunAwayTests.swift
// Echoel — #684. Blocking bundle, because the other suite cannot fail a merge (#208).
//
// WHAT THIS GUARDS. `EchoelGranular` is new DSP destined for the audio thread, and a
// granular stage has exactly two ways to ruin a take that a compiler cannot see:
//   1. A CLICK. A grain whose envelope does not start and end at zero splices a step
//      discontinuity into the signal, once per grain, forever. Claim 1 pins the envelope.
//   2. A RUNAWAY. Grains sum, so density silently doubles as a volume control unless the
//      sum is normalised — and a wet stage that gets louder as you turn a texture knob is
//      how a limiter ends up doing the mixing. Claims 4 and 6 pin the ceiling and the pool.
// Claims 2 and 3 are the boundary laws every stage in this repo owes: an exact bypass and
// a non-finite input that cannot escape or poison the ring buffer.
//
// ⛔ CLAIM 5 RECORDS THAT IT IS NOT WIRED, and it forbids nothing (#364). The core ships
// alone on purpose: making it a chain stage also means the switch-crackle rule, `FXPreset`
// round-trip, `GenreFX` and a panel row, and half of that is worse than none. The day
// somebody wires it, claim 5 goes red BY DESIGN and its message names the file header to
// correct in the same commit (#456). A red there is the good news.
//
// ⚠️ HONEST LIMITS. 6 tests, 19 assertion statements (5+3+3+3+1+4; counted in Python over
// lines whose first token is XCTAssert). Everything here is executed behaviour on the real
// type — no mocks, no host, no source scanning except claim 5. What no test can prove: that
// it SOUNDS like a granular effect. Grain size, density and spray are taste, and taste is a
// device probe (NEEDS-FOUNDER-VERIFY once it is wired and reachable).
//
// ⚠️ THE BOUND IN CLAIM 4 IS DERIVED, NOT WISHED FOR. Worst case is every one of the 8
// pool slots sounding at window peak with a hard-panned gain of 1, divided by the densest
// normalisation (overlap 3.5 → ×1/1.75): 8 / 1.75 ≈ 4.58. The test asserts 5.0 and not a
// tidier 2.0 precisely because a bound that the maths does not support is a test that
// passes today and reds on an input nobody predicted. The scheduler spaces grains out, so
// the typical peak is far below this — but "typical" is not a guarantee.
//
// ⭐ GRADING (§3). FORWARD in full: the type does not exist at the parent, so every claim
// is red there by one absence (#486). Numbers hand-derived (#442): `window` is
// 0.5 − 0.5·cos(2πx), so x=0 → 0.5 − 0.5·1 = 0, x=0.5 → 0.5 + 0.5 = 1, x=1 → 0 again.

import Foundation
import XCTest
@testable import Echoelmusic

final class AGrainCannotClickOrRunAwayTests: XCTestCase {

    // MARK: - 1: the envelope opens and closes at exactly zero

    /// The no-click promise, and the only part of it that is a pure function. A window
    /// that starts at anything but 0 puts a step into the signal once per grain.
    func testTheGrainEnvelopeStartsAndEndsAtZero() {
        XCTAssertEqual(EchoelGranular.window(0), 0, accuracy: 1e-6,
                       "A grain that opens above zero splices a step into the signal.")
        XCTAssertEqual(EchoelGranular.window(1), 0, accuracy: 1e-6,
                       "A grain that closes above zero clicks on its last sample.")
        XCTAssertEqual(EchoelGranular.window(0.5), 1, accuracy: 1e-6,
                       "The envelope must reach unity at the centre or grains lose level.")
        XCTAssertEqual(EchoelGranular.window(1.5), 0, accuracy: 1e-6, """
            A position past the grain's end must contribute NOTHING. Wrapping the cosine \
            instead would restart the window mid-signal — a click by another route.
            """)
        XCTAssertEqual(EchoelGranular.window(.nan), 0, accuracy: 1e-6,
                       "A non-finite position must read as silence, never as a gain.")
    }

    // MARK: - 2: mix 0 is an exact bypass and schedules nothing

    /// Not "close to" the input — identical. A stage that colours its own bypass cannot be
    /// A/B'd, and this one is destined to sit in a chain where every stage claims the same.
    func testZeroMixReturnsTheInputExactlyAndLaunchesNoGrain() {
        let g = EchoelGranular(sampleRate: 48000)
        g.mix = 0
        g.density = 1
        var allExact = true
        for i in 0..<4800 {
            let x = Float(i % 97) / 97.0 - 0.5
            let (l, r) = g.processStereo(x, -x)
            if l != x || r != -x { allExact = false; break }
        }
        XCTAssertTrue(allExact, """
            A bypassed grain stage changed the signal. Bypass must be bit-exact for finite \
            input — that is what makes an A/B honest.
            """)
        XCTAssertEqual(g.activeGrainCount, 0, """
            Grains were scheduled while the stage was bypassed. The house switch-crackle \
            rule is that a bypassed stage FREEZES, so re-enabling starts from silence.
            """)
        g.mix = 0.5
        _ = g.processStereo(0.1, 0.1)
        XCTAssertGreaterThan(g.activeGrainCount, 0, """
            Turning the mix up scheduled nothing. An enabled effect that never launches a \
            grain is indistinguishable from a broken one (#454 — without this the claim \
            above would pass on a stage that does nothing at all).
            """)
    }

    // MARK: - 3: a non-finite sample cannot escape, and cannot poison the buffer

    /// The ring buffer is the danger: one NaN written into it comes back out of every
    /// grain that later reads that region, long after the bad sample is gone.
    func testANonFiniteInputNeitherEscapesNorPoisonsTheRingBuffer() {
        let g = EchoelGranular(sampleRate: 48000)
        g.mix = 1
        g.density = 1
        let (badL, badR) = g.processStereo(.nan, .infinity)
        XCTAssertTrue(badL.isFinite && badR.isFinite,
                      "A non-finite input escaped the stage.")
        var allFinite = true
        for i in 0..<9600 {
            let (l, r) = g.processStereo(sinf(Float(i) * 0.01), sinf(Float(i) * 0.011))
            if !l.isFinite || !r.isFinite { allFinite = false; break }
        }
        XCTAssertTrue(allFinite, """
            The buffer stayed poisoned after ONE bad sample — grains kept reading the \
            region it landed in. Sanitise before the write, not after the read.
            """)
        XCTAssertTrue(g.processStereo(0.5, 0.5).0.isFinite,
                      "Still non-finite after a full second of clean input.")
    }

    // MARK: - 4: density is a texture control, not a volume control

    /// See the ⚠️ note in the header for where 5.0 comes from. The point of the claim is
    /// that a BOUND exists at all — an unnormalised grain sum has none.
    func testTheDensestSettingStaysWithinItsDerivedCeiling() {
        let g = EchoelGranular(sampleRate: 48000)
        g.mix = 1
        g.density = 1
        g.grainMilliseconds = 40
        g.spraySeconds = 0.2
        var peak: Float = 0
        var allFinite = true
        for _ in 0..<48000 {
            let (l, r) = g.processStereo(1, 1)
            if !l.isFinite || !r.isFinite { allFinite = false; break }
            peak = Swift.max(peak, Swift.max(abs(l), abs(r)))
        }
        XCTAssertTrue(allFinite, "The dense path produced a non-finite sample.")
        XCTAssertLessThanOrEqual(peak, 5.0, """
            Peak \(peak) exceeds the ceiling the pool size and normalisation allow \
            (8 slots / 1.75 ≈ 4.58). Either the sum lost its normalisation or the pool cap \
            is not holding — both mean density has become a volume control.
            """)
        XCTAssertGreaterThan(peak, 0, """
            The dense path produced pure silence, which would make the ceiling above \
            vacuous (#454).
            """)
    }

    // MARK: - 5: it is not wired yet, and this claim does not forbid wiring it

    /// The header says "PURE CORE ONLY, not a stage of `EchoelFXChain`". This is that
    /// sentence made checkable, so it cannot quietly become false in either direction.
    func testTheCoreHasNoProductionConstructionSite() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present") }
        var sites: [String] = []
        let dir = root.appendingPathComponent("Sources")
        let walker = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)
        while let url = walker?.nextObject() as? URL {
            guard url.pathExtension == "swift",
                  url.lastPathComponent != "EchoelGranular.swift" else { continue }
            let code = SourceText.codeOnly((try? String(contentsOf: url, encoding: .utf8)) ?? "")
            if code.contains("EchoelGranular(") { sites.append(url.lastPathComponent) }
        }
        XCTAssertEqual(sites.sorted(), [], """
            `EchoelGranular` is constructed in \(sites.sorted()) — it is WIRED now. That is \
            the intended next slice, not a defect: delete this claim and correct the ⛔ \
            "PURE CORE ONLY … not a stage of EchoelFXChain" block in the file header in \
            the SAME commit (#456), so the code and the note stop disagreeing.
            """)
    }

    // MARK: - 6: same seed, same grains — and reset() really rewinds

    /// Determinism is what makes every claim above reproducible; without it a failure here
    /// could never be re-run. It also proves the pool cap, which needs a dense run to test.
    func testItIsDeterministicAndResetRewindsCompletely() {
        func render(_ g: EchoelGranular) -> ([Float], Int) {
            g.mix = 1; g.density = 1; g.grainMilliseconds = 30
            var out: [Float] = []
            var maxActive = 0
            for i in 0..<24000 {
                let (l, _) = g.processStereo(sinf(Float(i) * 0.02), sinf(Float(i) * 0.02))
                out.append(l)
                maxActive = Swift.max(maxActive, g.activeGrainCount)
            }
            return (out, maxActive)
        }
        let a = EchoelGranular(sampleRate: 48000, seed: 12345)
        let b = EchoelGranular(sampleRate: 48000, seed: 12345)
        let (outA, maxA) = render(a)
        let (outB, _) = render(b)
        XCTAssertEqual(outA, outB, """
            Two instances with the same seed rendered differently. Without determinism no \
            failure in this file can be reproduced, and the grain pattern is untestable.
            """)
        XCTAssertLessThanOrEqual(maxA, EchoelGranular.maxGrains, """
            \(maxA) grains were live at once against a pool of \(EchoelGranular.maxGrains). \
            The scheduler must DROP a launch when the pool is full — growing it would \
            allocate on the audio thread.
            """)
        XCTAssertGreaterThan(maxA, 0, "No grain ever became active; the run proves nothing.")
        a.reset()
        let (outC, _) = render(a)
        XCTAssertEqual(outA, outC, """
            After `reset()` the stage did not reproduce a fresh instance. The RNG, the \
            spawn accumulator or the delay lines survived the reset, which means a preset \
            recall would inherit the previous take's texture.
            """)
    }
}
