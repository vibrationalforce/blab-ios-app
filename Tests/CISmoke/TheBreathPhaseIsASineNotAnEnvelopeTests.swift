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

        // ⛔ #1138 REWROTE THIS COMMENT. It said "the upward crossing is inhale onset and the
        // contract calls that 0.5", i.e. source and contract AGREE at the anchor. They do not:
        // the contract's 0.5 is a LABEL (inhale start), the camera's 0.5 is the MIDPOINT of
        // its own range, which a rising sine passes halfway UP the inhale. Measured, lungs
        // are full at phase 0.230 after the crossing and empty at 0.730 (claim 5), so the
        // crossing sits at contract φ 0.770 — the shipped figure was wrong by 97°. The
        // ASSERTION below is unchanged and still true; only what it was taken to MEAN was not.
        XCTAssertEqual(crossingAmp ?? .nan, 0.5, accuracy: 0.05, """
            At the upward zero-crossing `amplitude` reads ~0.5 — the midpoint of its own \
            range, NOT the contract's inhale start. Claim 5 pins where the lungs actually \
            are. (At the 1 s publish tick the same crossing reads 0.8565; that is a sampling \
            artefact of the coarse grid, not a disagreement.)
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

    // MARK: - 5 · Where the lungs actually are, relative to the crossing

    /// ⛔ THIS CLAIM EXISTS BECAUSE #1135 SHIPPED AN OFFSET THAT WAS WRONG BY 97°. It called
    /// `lastCrossT` "inhale onset" and offered `+0.5`; the camera reading 0.5073 there looked
    /// like corroboration and was a coincidence of two different 0.5s. Nothing was measured.
    /// The numbers below are, at a 0.02 s tick on the shipped filter chain, and they are what
    /// task #30 must build on.
    func testTheLungExtremesSitAtTheMeasuredPhasesNotTheAssumedOnes() {
        let trendTau = 8.0, smoothTau = 0.8, envTau = 6.0
        let dt = 0.02, breathHz = 0.1
        var trend = 0.0, smooth = 0.0, prev = 0.0, env = 0.0
        var seeded = false
        var rec: [(t: Double, a: Double, rising: Bool)] = []

        for i in 0..<60_000 {
            let t = Double(i) * dt
            let hr = 70.0 + 4.0 * sin(2 * Double.pi * breathHz * t)
            if !seeded { trend = hr; seeded = true }
            trend += (1 - exp(-dt / trendTau)) * (hr - trend)
            let hp = hr - trend
            prev = smooth
            smooth += (1 - exp(-dt / smoothTau)) * (hp - smooth)
            env += (1 - exp(-dt / envTau)) * (abs(smooth) - env)
            let norm = Swift.max(-1.0, Swift.min(1.0, smooth / (Swift.max(env, 1e-6) * 1.4)))
            guard t > 900 else { continue }
            rec.append((t, 0.5 + 0.5 * norm, prev <= 0 && smooth > 0))
        }

        let ups = rec.filter { $0.rising }.map { $0.t }
        guard ups.count >= 2 else { return XCTFail("no two upward crossings in the window") }
        let period = ups[1] - ups[0], t0 = ups[0]
        XCTAssertEqual(period, 10.0, accuracy: 0.2, "the driven 6/min cycle must come back out")

        let cycle = rec.filter { $0.t >= t0 && $0.t < t0 + period }
        func phase(_ t: Double) -> Double { ((t - t0).truncatingRemainder(dividingBy: period)) / period }
        let top = cycle.filter { $0.a > 0.9999 }.map { phase($0.t) }
        let bottom = cycle.filter { $0.a < 0.0001 }.map { phase($0.t) }
        guard let tLo = top.min(), let tHi = top.max(),
              let bLo = bottom.min(), let bHi = bottom.max() else {
            return XCTFail("amplitude never reached its clamped extremes")
        }
        let fullCentre = (tLo + tHi) / 2, emptyCentre = (bLo + bHi) / 2

        XCTAssertEqual(fullCentre, 0.230, accuracy: 0.02, """
            Lungs FULL no longer centres at phase 0.230 after the upward crossing. The \
            sawtooth re-anchoring `((t − lastCrossT)/periodEMA + 0.770) mod 1` is derived \
            from exactly this number; if it moved, re-derive the offset before task #30 \
            builds on it, and pull the prose on `EngineBus.breathPhase` with it.
            """)
        XCTAssertEqual(emptyCentre, 0.730, accuracy: 0.02, """
            Lungs EMPTY no longer centres at phase 0.730 — half a cycle after full, as a \
            breath must be.
            """)
        XCTAssertEqual(emptyCentre - fullCentre, 0.5, accuracy: 0.02, """
            The two extremes are no longer half a cycle apart, which would mean the signal \
            stopped being one oscillation per breath.
            """)

        // The shipped `+0.5` against the measured `+0.770`: a quarter-cycle-scale error.
        let correctOffset = 1.0 - fullCentre
        XCTAssertEqual(correctOffset, 0.770, accuracy: 0.02, "the re-anchoring offset")
        XCTAssertGreaterThan(abs(correctOffset - 0.5), 0.2, """
            The offset shipped by #1135 (0.5) is no longer far from the measured one. If the \
            filters ever make them agree, the ⛔ retraction on `EngineBus.breathPhase` becomes \
            wrong prose and must be pulled in the same commit.
            """)

        // The soft clip is real and is not a defect: the widest frame is HELD, not touched.
        XCTAssertEqual(tHi - tLo, 0.148, accuracy: 0.02, """
            The clamped plateau at lungs-full is no longer ~14.8 % of the cycle. `norm` \
            saturates because of the `/1.4`, so `amplitude` is a soft-clipped sine — stated \
            here because claim 1 calls it a "sine" and that word alone would hide the flat top.
            """)
    }
}
