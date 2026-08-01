// BioFollowsTheBodyTests.swift
// Echoel — #331. Blocking bundle.
//
// ⭐ THE ONE NUMBER THIS FILE EXISTS FOR: `smoothCoeff` inside
// `EchoelDDSP.applyBioReactive`. It is a per-CALL one-pole coefficient, and the rate it is
// tuned for is not written anywhere near it — which is exactly how it sat at `0.92` (τ = 0.2 s
// at 60 Hz, the caller this function was written for and never got) while every bio publisher
// in the repo emits ~1 Hz. At 1 Hz that same 0.92 is τ = 12 s: a change in the player's body
// was 8 % delivered after a second and 57 % after ten. Reverting it is one token, the revert
// compiles, and no other test in either bundle would notice.
//
// So this file asserts the BEHAVIOUR the constant exists to produce — "the sound follows the
// body within a couple of frames" — never the constant itself. A future re-tune (0.75 is named
// in the source as the sanctioned one-token softening) stays free; only a return to the 60 Hz
// unit error trips it.
//
// ⚠️ WHAT THIS FILE DELIBERATELY DOES NOT GUARD, because the first draft of it did and the
// assertion would have been theatre: the deletion of `_spectralUpdateCounter`. That counter
// looked like the gate on the spectral rebuild and was not one — `brightness` carries
// `didSet { updateSpectralEnvelope() }`, so the envelope was already rebuilt on every call and
// the counter only fired a second, identical rebuild every sixth. A test written to "prove the
// spectrum is no longer stale" would have passed against the pre-#331 code too. The second test
// below therefore states what is actually true and worth pinning: one new bio frame must reach
// the spectral envelope, via whichever mechanism. That invariant predates #331 and outlives it.

import XCTest
@testable import Echoelmusic

final class BioFollowsTheBodyTests: XCTestCase {

    /// Two calls — i.e. ~2 s of real bio — must carry the sound MOST of the way to the new
    /// body reading. At the shipped 0.6065 that is 63 %; at the old 0.92 it is 15 %; at the
    /// sanctioned 0.75 fallback it is 44 %. The 0.35 floor passes all three of the values a
    /// human might reasonably choose for a ~1 Hz stream and fails the 60 Hz one, which is the
    /// only line this test is drawing.
    func testTwoBioFramesCarryTheSoundMostOfTheWayToTheBody() {
        // `settled` and `moving` get the IDENTICAL constant reading, so the only difference
        // between them is how many frames each has had. No target formula is hardcoded here —
        // the settled engine measures it, which keeps this test alive across a re-voicing of
        // the brightness mapping itself.
        let settled = EchoelDDSP(harmonicCount: 32, sampleRate: 48000)
        for _ in 0..<400 { settled.applyBioReactive(coherence: 1.0) }

        let moving = EchoelDDSP(harmonicCount: 32, sampleRate: 48000)
        let start = moving.brightness
        moving.applyBioReactive(coherence: 1.0)
        moving.applyBioReactive(coherence: 1.0)

        let span = settled.brightness - start
        XCTAssertGreaterThan(abs(span), 0.05, """
            Precondition failed, not the property under test: full coherence must move \
            brightness away from its resting value at all. start=\(start) \
            settled=\(settled.brightness). If this fires, the brightness mapping changed and \
            this test needs a new stimulus, not a wider tolerance.
            """)

        let progress = (moving.brightness - start) / span
        XCTAssertGreaterThan(progress, 0.35, """
            Bio smoothing is tuned for a caller that does not exist. Two bio frames delivered \
            only \(progress) of the change; the body must reach the sound within a couple of \
            frames because applyBioReactive runs ONCE PER NEW BIO FRAME (~1 Hz), not at 60 Hz. \
            A coefficient of 0.92 gives 0.15 here — that is the 60x unit error #331 removed. \
            See the smoothCoeff block in EchoelDDSP.applyBioReactive before widening this.
            """)
    }

    /// One new bio frame must reach the spectral envelope — the only route by which
    /// `brightness` becomes something the ear can hear. Today that happens through
    /// `brightness`'s own `didSet`; this test does not care which mechanism delivers it, only
    /// that removing the mechanism cannot pass silently.
    func testOneBioFrameReachesTheSpectralEnvelope() {
        let s = EchoelDDSP(harmonicCount: 32, sampleRate: 48000)
        s.applyBioReactive(coherence: 0.0)
        let dark = s.harmonicAmplitudes

        s.applyBioReactive(coherence: 1.0)
        let opened = s.harmonicAmplitudes

        XCTAssertEqual(dark.count, opened.count, "harmonic table must not be resized by bio")
        let changed = zip(dark, opened).contains { abs($0.0 - $0.1) > 1e-6 }
        XCTAssertTrue(changed, """
            A new bio reading did not reach the spectral envelope. brightness feeds \
            computeShapeAmplitudes, so a change in the body that never rebuilds the harmonic \
            table is inaudible no matter how fast the smoothing is.
            """)
    }
}
