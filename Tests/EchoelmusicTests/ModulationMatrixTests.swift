import XCTest
@testable import Echoelmusic

final class ModulationMatrixTests: XCTestCase {

    // A bio frame with controllable fields.
    private func frame(
        hr: Float = 120, hrv: Float = 0.5, br: Float = 12,
        phase: Float = 0.5, coh: Float = 0.5, motion: Float = 0.5
    ) -> BioSampleFrame {
        BioSampleFrame(
            timestamp: 0, heartRateBPM: hr, hrvNormalized: hrv,
            breathRate: br, breathPhase: phase, coherence: coh,
            motionEnergy: motion, source: .fallback
        )
    }

    private func dest(_ k: String) -> ModDestination { ModDestination(k) }

    // MARK: - normalize / clamp

    func testNormalize_midpoint() {
        XCTAssertEqual(ModulationMatrix.normalize(120, in: 40...200), 0.5, accuracy: 1e-6)
    }

    func testNormalize_clampsOutOfRange() {
        XCTAssertEqual(ModulationMatrix.normalize(10, in: 40...200), 0)
        XCTAssertEqual(ModulationMatrix.normalize(999, in: 40...200), 1)
    }

    func testNormalize_degenerateRangeIsZero() {
        XCTAssertEqual(ModulationMatrix.normalize(5, in: 5...5), 0)
    }

    func testClamp01_handlesNaN() {
        XCTAssertEqual(ModulationMatrix.clamp01(.nan), 0)
        XCTAssertEqual(ModulationMatrix.clamp01(2), 1)
        XCTAssertEqual(ModulationMatrix.clamp01(-1), 0)
    }

    // MARK: - ModSource normalization

    func testSource_heartRate_normalizedByItsRange() {
        XCTAssertEqual(ModSource.heartRate.normalizedValue(from: frame(hr: 120)), 0.5, accuracy: 1e-6)
    }

    func testSource_coherence_passesThroughZeroToOne() {
        XCTAssertEqual(ModSource.coherence.normalizedValue(from: frame(coh: 0.8)), 0.8, accuracy: 1e-6)
    }

    func testSource_allCasesHaveValidRange() {
        for s in ModSource.allCases {
            XCTAssertLessThan(s.range.lowerBound, s.range.upperBound, "\(s) range must be non-degenerate")
        }
    }

    // MARK: - output: live

    func testOutput_live_tracksNormalizedSource() {
        let r = ModRoute(source: .heartRate, destination: dest("synth.cutoff"), mode: .live)
        XCTAssertEqual(ModulationMatrix.output(for: r, frame: frame(hr: 120)), 0.5, accuracy: 1e-6)
        XCTAssertEqual(ModulationMatrix.output(for: r, frame: frame(hr: 200)), 1.0, accuracy: 1e-6)
    }

    func testOutput_live_depthScales() {
        let r = ModRoute(source: .coherence, destination: dest("x"), mode: .live, depth: 0.5)
        XCTAssertEqual(ModulationMatrix.output(for: r, frame: frame(coh: 1.0)), 0.5, accuracy: 1e-6)
    }

    func testOutput_invert() {
        let r = ModRoute(source: .coherence, destination: dest("x"), mode: .live, invert: true)
        XCTAssertEqual(ModulationMatrix.output(for: r, frame: frame(coh: 0.2)), 0.8, accuracy: 1e-6)
    }

    func testOutput_disabledRouteIsZero() {
        let r = ModRoute(source: .coherence, destination: dest("x"), mode: .live, enabled: false)
        XCTAssertEqual(ModulationMatrix.output(for: r, frame: frame(coh: 1.0)), 0)
    }

    // MARK: - output: hold (capture)

    func testOutput_holdRigid_ignoresLiveSource() {
        // drift 0 → output is exactly the held value regardless of the source.
        let r = ModRoute(source: .coherence, destination: dest("x"), mode: .hold(value: 0.7, drift: 0))
        XCTAssertEqual(ModulationMatrix.output(for: r, frame: frame(coh: 0.0)), 0.7, accuracy: 1e-6)
        XCTAssertEqual(ModulationMatrix.output(for: r, frame: frame(coh: 1.0)), 0.7, accuracy: 1e-6)
    }

    func testOutput_holdWithDrift_modulatesAroundHeldValue() {
        // held 0.5, drift 0.2. live=1.0 → 0.5 + 0.2*(1-0.5)*2 = 0.5 + 0.2 = 0.7
        let r = ModRoute(source: .coherence, destination: dest("x"), mode: .hold(value: 0.5, drift: 0.2))
        XCTAssertEqual(ModulationMatrix.output(for: r, frame: frame(coh: 1.0)), 0.7, accuracy: 1e-6)
        // live=0.0 → 0.5 + 0.2*(0-0.5)*2 = 0.5 - 0.2 = 0.3
        XCTAssertEqual(ModulationMatrix.output(for: r, frame: frame(coh: 0.0)), 0.3, accuracy: 1e-6)
        // live=0.5 → no deviation
        XCTAssertEqual(ModulationMatrix.output(for: r, frame: frame(coh: 0.5)), 0.5, accuracy: 1e-6)
    }

    func testCaptured_latchesCurrentSourceValue() {
        let r = ModRoute(source: .heartRate, destination: dest("tempo"), mode: .live)
        let held = r.captured(from: frame(hr: 120), drift: 0)
        // heartRate 120 normalizes to 0.5; rigid hold → output 0.5 regardless of new frame.
        XCTAssertEqual(ModulationMatrix.output(for: held, frame: frame(hr: 200)), 0.5, accuracy: 1e-6)
        if case .hold(let v, let d) = held.mode {
            XCTAssertEqual(v, 0.5, accuracy: 1e-6)
            XCTAssertEqual(d, 0)
        } else {
            XCTFail("captured() must produce a .hold mode")
        }
    }

    func testCaptured_clampsDrift() {
        let r = ModRoute(source: .coherence, destination: dest("x"))
        let held = r.captured(from: frame(coh: 0.5), drift: 5)
        if case .hold(_, let d) = held.mode { XCTAssertEqual(d, 1) } else { XCTFail() }
    }

    // MARK: - output: response curve

    func testOutput_linearCurveIsIdentity_backwardCompatible() {
        // Default curve is .linear → unchanged from pre-curve behavior.
        let r = ModRoute(source: .coherence, destination: dest("x"))
        XCTAssertEqual(ModulationMatrix.output(for: r, frame: frame(coh: 0.7)), 0.7, accuracy: 1e-6)
    }

    func testOutput_exponentialCurveShapesResponse() {
        // coh 0.5 → exp (x²) 0.25.
        let r = ModRoute(source: .coherence, destination: dest("x"), curve: .exponential)
        XCTAssertEqual(ModulationMatrix.output(for: r, frame: frame(coh: 0.5)), 0.25, accuracy: 1e-6)
    }

    func testOutput_logarithmicCurveShapesResponse() {
        // coh 0.25 → log (√x) 0.5.
        let r = ModRoute(source: .coherence, destination: dest("x"), curve: .logarithmic)
        XCTAssertEqual(ModulationMatrix.output(for: r, frame: frame(coh: 0.25)), 0.5, accuracy: 1e-6)
    }

    func testOutput_curveAppliedAfterInvert() {
        // coh 0.2 → invert 0.8 → exp 0.64.
        let r = ModRoute(source: .coherence, destination: dest("x"), invert: true, curve: .exponential)
        XCTAssertEqual(ModulationMatrix.output(for: r, frame: frame(coh: 0.2)), 0.64, accuracy: 1e-6)
    }

    func testOutput_curveThenDepth() {
        // coh 0.5 → exp 0.25 → depth 0.5 → 0.125.
        let r = ModRoute(source: .coherence, destination: dest("x"), depth: 0.5, curve: .exponential)
        XCTAssertEqual(ModulationMatrix.output(for: r, frame: frame(coh: 0.5)), 0.125, accuracy: 1e-6)
    }

    // MARK: - Codable backward compatibility (curve)

    func testRoute_codableRoundTripPreservesCurve() throws {
        let r = ModRoute(source: .hrv, destination: dest("x"), curve: .sCurve)
        let back = try JSONDecoder().decode(ModRoute.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(back.curve, .sCurve)
    }

    func testRoute_decodesWithoutCurveKey_defaultsLinear() throws {
        // Simulate persisted v1 data that predates the `curve` field.
        let r = ModRoute(source: .coherence, destination: dest("x"), curve: .exponential)
        let data = try JSONEncoder().encode(r)
        guard var obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return XCTFail("route did not encode to a JSON object")
        }
        obj.removeValue(forKey: "curve")
        let stripped = try JSONSerialization.data(withJSONObject: obj)
        let back = try JSONDecoder().decode(ModRoute.self, from: stripped)
        XCTAssertEqual(back.curve, .linear)
    }

    // MARK: - evaluate: aggregation

    func testEvaluate_routesToTheirDestinations() {
        let m = ModulationMatrix(routes: [
            ModRoute(source: .coherence, destination: dest("a"), mode: .live),
            ModRoute(source: .heartRate, destination: dest("b"), mode: .live)
        ])
        let out = m.evaluate(frame(hr: 200, coh: 0.3))
        XCTAssertEqual(out[dest("a")] ?? -1, 0.3, accuracy: 1e-6)
        XCTAssertEqual(out[dest("b")] ?? -1, 1.0, accuracy: 1e-6)
    }

    func testEvaluate_sameDestinationIsAdditiveAndClamped() {
        let m = ModulationMatrix(routes: [
            ModRoute(source: .coherence, destination: dest("a"), mode: .live, depth: 0.6),
            ModRoute(source: .motion,    destination: dest("a"), mode: .live, depth: 0.6)
        ])
        // 0.6 + 0.6 = 1.2 → clamped to 1.0
        XCTAssertEqual(m.evaluate(frame(coh: 1.0, motion: 1.0))[dest("a")] ?? -1, 1.0, accuracy: 1e-6)
    }

    func testEvaluate_skipsDisabledAndZeroRoutes() {
        let m = ModulationMatrix(routes: [
            ModRoute(source: .coherence, destination: dest("a"), mode: .live, enabled: false)
        ])
        XCTAssertNil(m.evaluate(frame(coh: 1.0))[dest("a")])
    }

    // MARK: - Codable round-trip (persistence)

    func testMatrix_codableRoundTrip() throws {
        let m = ModulationMatrix(routes: [
            ModRoute(source: .breathPhase, destination: dest("voice.brightness"),
                     mode: .hold(value: 0.42, drift: 0.1), depth: 0.8, invert: true),
            ModRoute(source: .hrv, destination: dest("synth.cutoff"), mode: .live)
        ])
        let data = try JSONEncoder().encode(m)
        let back = try JSONDecoder().decode(ModulationMatrix.self, from: data)
        XCTAssertEqual(m, back)
    }
}
