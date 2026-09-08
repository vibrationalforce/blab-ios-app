// TheBreathPhaseIsASineNotAnEnvelopeTests.swift
// Echoel — what the camera actually writes into `breathPhase`, in the BLOCKING bundle.
//
// #1135. Three homes called `RespirationEstimator.amplitude` an ENVELOPE: the contract doc on
// `BioSampleFrame.breathPhase`, the header of `TheVisualBreathIsGatedTests` (which took the
// word from the contract), and the v10.79.461 deploy note (which took it from both). It is
// not one. Read the line that computes it:
//
//     let norm = clamp(smooth / (e * 1.4), -1, 1)      // e = max(env, 1e-6)
//     amplitude = 0.5 + 0.5 * norm
//
// `smooth` is the SIGNED band-passed pulse; `env` is the real envelope and it sits in the
// DENOMINATOR as a normaliser. What comes out is the oscillation divided by its own envelope —
// a normalised sine in [0,1], never the envelope itself.
//
// ⭐ WHY THE WORD WAS EXPENSIVE, AND IT IS NOT A STYLE POINT. An envelope carries NO phase, so
// honouring the sawtooth contract would mean building a phase estimator from nothing — four
// consumers, its own slice, easy to defer forever. A normalised sine DOES carry the phase; it
// carries it in the wrong SHAPE. The estimator already holds both terms a sawtooth needs —
// `lastCrossT` (the upward zero-crossing = inhale onset) and `periodEMA` (the smoothed cycle
// length) — so the repair is `((t − lastCrossT) / periodEMA + 0.5) mod 1`, a shift of held
// values. One wrong noun turned a small slice into an apparently large one, in the doc a
// session reads BEFORE deciding whether to attempt it.
//
// ⚠️ THE CONCLUSION THAT WORD SUPPORTED SURVIVES UNCHANGED, and that is why this is a
// correction and not a reversal: through a symmetric hump like `sin(π · x)` this value still
// peaks at MID-breath, still falls to zero at BOTH lung extremes, and still swells twice per
// breath. #1133 and the v461 note told the founder the right thing for the wrong reason. Both
// halves are recorded so the next session can check the claim instead of inheriting it.
//
// ⛔ THIS GUARD DOES NOT FORBID FIXING THE CONTRACT (#364). Claim 4 is the counterweight: it
// requires `lastCrossT` and `periodEMA` to keep existing, i.e. it protects the repair PATH.
// The day someone makes the camera publish a real sawtooth, claim 1's arithmetic still holds
// (it pins the estimator's own output, not what the publisher does with it) and claim 3's
// prose is what must move in the same commit — the message names every home.

import XCTest

final class TheBreathPhaseIsASineNotAnEnvelopeTests: XCTestCase {

    private static let estimator = "Sources/Echoelmusic/Bio/RespirationEstimator.swift"
    private static let bus = "Sources/Echoelmusic/Core/EngineBus.swift"
    private static let visualGuard = "Tests/CISmoke/TheVisualBreathIsGatedTests.swift"

    private func root() throws -> URL {
        let r = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: r.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(r.path)") }
        return r
    }

    private func raw(_ relativePath: String) throws -> String {
        let path = try root().appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            struct AnchorMissing: Error { let path: String }
            throw AnchorMissing(path: relativePath)
        }
        return try String(contentsOf: path, encoding: .utf8)
    }

    private func code(_ relativePath: String) throws -> String {
        SourceText.codeOnly(try raw(relativePath))
    }

    private func count(_ needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    // MARK: - 1 · The arithmetic, transcribed from the shipped recursion

    /// Drives the estimator's own maths with the shipped time constants and a clean 6/min
    /// respiratory sinus arrhythmia, then asserts the three properties that separate an
    /// oscillation from an envelope. Every number here was MEASURED by running this
    /// recursion, never predicted (#808).
    func testTheAmplitudeOscillatesAndTheEnvelopeDoesNot() {
        // Shipped constants — RespirationEstimator lines 27/29/31.
        let trendTau = 8.0, smoothTau = 0.8, envTau = 6.0
        let dt = 0.1, breathHz = 0.1                 // 6 breaths per minute
        var trend = 0.0, smooth = 0.0, prev = 0.0, env = 0.0
        var seeded = false
        var amps: [Double] = []
        var envs: [Double] = []
        var crossingAmp: Double?

        for i in 0..<12_000 {
            let t = Double(i) * dt
            let hr = 70.0 + 4.0 * sin(2 * Double.pi * breathHz * t)
            if !seeded { trend = hr; seeded = true }
            trend += (1 - exp(-dt / trendTau)) * (hr - trend)
            let hp = hr - trend
            prev = smooth
            smooth += (1 - exp(-dt / smoothTau)) * (hp - smooth)
            env += (1 - exp(-dt / envTau)) * (abs(smooth) - env)
            let e = Swift.max(env, 1e-6)
            let norm = Swift.max(-1.0, Swift.min(1.0, smooth / (e * 1.4)))
            let amplitude = 0.5 + 0.5 * norm
            guard t > 600 else { continue }          // let the three filters settle
            amps.append(amplitude)
            envs.append(env)
            if prev <= 0, smooth > 0, crossingAmp == nil { crossingAmp = amplitude }
        }

        let lo = amps.min() ?? .nan, hi = amps.max() ?? .nan
        let mean = amps.reduce(0, +) / Double(amps.count)
        XCTAssertEqual(lo, 0.0, accuracy: 0.01, "amplitude must reach the exhale trough")
        XCTAssertEqual(hi, 1.0, accuracy: 0.01, "amplitude must reach the inhale peak")
        XCTAssertEqual(mean, 0.5, accuracy: 0.01, """
            An oscillation divided by its own envelope has mean 0.5 over whole cycles. \
            Measured 0.5000. An envelope does not.
            """)

        // It passes 0.5 TWICE per cycle — the property that makes a symmetric hump
        // double-rate. Measured 2.000 per cycle over 60 cycles at this 0.1 s tick.
        var halfCrossings = 0
        for k in 1..<amps.count where (amps[k - 1] - 0.5) * (amps[k] - 0.5) < 0 {
            halfCrossings += 1
        }
        let cycles = Double(amps.count) * dt * breathHz
        let perCycle = Double(halfCrossings) / cycles
        XCTAssertEqual(perCycle, 2.0, accuracy: 0.1, """
            `amplitude` must cross 0.5 twice per breath cycle (measured 2.000). This is the \
            property that makes `sin(π · x)` peak at MID-breath and go dark at BOTH lung \
            extremes — the visual defect recorded on `EngineBus.breathPhase`.
            """)

        // The REAL envelope, over the same span, is near-constant — it cannot be what
        // `breathPhase` carries. Measured 2.0212…2.4074 at this 0.1 s tick. ⚠️ The bounds
        // below are deliberately wider than that window: the same recursion at the 1 s publish
        // tick gives 1.8963…2.2599, and a guard pinned to one grid would red on the other.
        // The CLAIM is "near-constant", not a specific pair of numbers.
        let envLo = envs.min() ?? .nan, envHi = envs.max() ?? .nan
        XCTAssertGreaterThan(envLo, 1.5, "the true envelope stayed near-constant (measured 2.02)")
        XCTAssertLessThan(envHi, 2.6, "the true envelope stayed near-constant (measured 2.41)")
        XCTAssertLessThan(envHi - envLo, 0.5, """
            The envelope `env` varies by less than 0.5 while `amplitude` spans the full [0,1]. \
            An envelope cannot span [0,1] once per breath — this is the cheapest way to see \
            that calling `amplitude` an ENVELOPE was wrong.
            """)

        // Source and contract AGREE at the anchor: the upward crossing is inhale onset and
        // the contract calls that 0.5. Measured 0.5073 at a 0.1 s tick.
        XCTAssertEqual(crossingAmp ?? .nan, 0.5, accuracy: 0.05, """
            At the upward zero-crossing — inhale onset — `amplitude` reads ~0.5, exactly what \
            the contract calls inhale start. Source and contract agree at the anchor and \
            diverge only in SHAPE between anchors. (At the 1 s publish tick the same crossing \
            reads 0.8565; that is a sampling artefact of the coarse grid, not a second \
            disagreement.)
            """)
    }

    // MARK: - 2 · The code still has the shape the arithmetic assumes

    func testTheEnvelopeIsTheDenominator() throws {
        let est = try code(Self.estimator)
        XCTAssertEqual(count("smooth / (e * 1.4)", in: est), 1, """
            `RespirationEstimator` no longer divides `smooth` by the envelope. Claim 1 \
            transcribes that exact recursion; if the shape changed, the transcription is \
            stale and the docs on `EngineBus.breathPhase` and on `amplitude` describe a \
            value that no longer exists. Re-measure before editing either.
            """)
        XCTAssertEqual(count("amplitude = 0.5 + 0.5 * norm", in: est), 1, """
            The `amplitude = 0.5 + 0.5 * norm` line is gone or was rewritten. That line is \
            why the value spans [0,1] with mean 0.5 — the whole basis of claim 1.
            """)
    }

    // MARK: - 3 · The retraction is in every home the word reached

    func testTheEnvelopeWordIsRetractedInAllThreeHomes() throws {
        // Read RAW: the needles ARE prose, so `codeOnly` would strip the very lines asserted.
        let bus = try raw(Self.bus)
        XCTAssertTrue(bus.contains("SINE-SHAPED POSITION"), """
            `EngineBus.breathPhase` no longer says the camera writes a sine-shaped position. \
            It said "an ENVELOPE" until #1135 and that word made the repair look four times \
            bigger than it is (an envelope carries no phase; this does).
            """)
        XCTAssertTrue(bus.contains("env` is the envelope and it sits in the"), """
            `EngineBus.breathPhase` lost the sentence naming `env` as the DENOMINATOR. That \
            sentence is the evidence for the correction — without it the next session has \
            only an assertion to weigh against the word it replaced.
            """)

        let vis = try raw(Self.visualGuard)
        XCTAssertTrue(vis.contains("THIS PARAGRAPH SAID \"an ENVELOPE\""), """
            `TheVisualBreathIsGatedTests`' header lost its retraction. It inherited the word \
            from `EngineBus`, so correcting only the source leaves the copy asserting the \
            wrong reason for a conclusion that is right (#456: prose moves in EVERY home).
            """)

        let est = try raw(Self.estimator)
        XCTAssertTrue(est.contains("IT IS NOT AN ENVELOPE"), """
            `RespirationEstimator.amplitude` lost the note that it is not an envelope. That \
            is the home closest to the code, and the one a session reads when it wonders why \
            the value looks like a sine.
            """)
    }

    // MARK: - 4 · Counterweight — the cheap repair path must stay reachable

    func testTheSawtoothTermsStillExist() throws {
        let est = try code(Self.estimator)
        XCTAssertTrue(est.contains("lastCrossT"), """
            `lastCrossT` is gone. It is the upward zero-crossing time — inhale onset — and \
            half of the cheap repair `((t − lastCrossT) / periodEMA + 0.5) mod 1`. Without \
            it, honouring the sawtooth contract really would need a new estimator, which is \
            exactly the false picture the word ENVELOPE painted.
            """)
        XCTAssertTrue(est.contains("periodEMA"), """
            `periodEMA` is gone — the smoothed cycle length, the other half of the repair.
            """)
        // #364 in executable form: this guard must never be the reason a fix is refused.
        XCTAssertTrue(true, "honouring the contract is permitted; only the diagnosis is pinned")
    }
}
