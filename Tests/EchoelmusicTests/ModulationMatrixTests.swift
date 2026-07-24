import XCTest
@testable import Echoelmusic

final class ModulationMatrixTests: XCTestCase {

    // A bio frame with controllable fields.
    private func frame(
        hr: Float = 120, hrv: Float = 0.5, br: Float = 12,
        phase: Float = 0.5, coh: Float = 0.5, motion: Float = 0.5,
        src: BioSource = .fallback
    ) -> BioSampleFrame {
        BioSampleFrame(
            timestamp: 0, heartRateBPM: hr, hrvNormalized: hrv,
            breathRate: br, breathPhase: phase, coherence: coh,
            motionEnergy: motion, source: src
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

    // MARK: - HRV-trust source gate

    func testBioSource_onlyBLEProvidesTrustedHRV() {
        XCTAssertTrue(BioSource.ble.providesTrustedHRV)
        for s: BioSource in [.fallback, .healthKit, .oura, .watch, .cameraPPG] {
            XCTAssertFalse(s.providesTrustedHRV, "\(s) must not be trusted for HRV")
        }
    }

    func testOutput_trustedGate_passesOnBLE() {
        let r = ModRoute(source: .hrv, destination: dest("x"), requiresTrustedSource: true)
        XCTAssertEqual(ModulationMatrix.output(for: r, frame: frame(hrv: 0.8, src: .ble)), 0.8, accuracy: 1e-6)
    }

    func testOutput_trustedGate_silentOnWeakSources() {
        let r = ModRoute(source: .hrv, destination: dest("x"), requiresTrustedSource: true)
        for s: BioSource in [.fallback, .healthKit, .oura, .watch, .cameraPPG] {
            XCTAssertEqual(ModulationMatrix.output(for: r, frame: frame(hrv: 0.8, src: s)), 0, "\(s) must gate to 0")
        }
    }

    func testOutput_noTrustRequirement_passesOnWeakSource_backwardCompatible() {
        // Default requiresTrustedSource == false → unchanged behavior.
        let r = ModRoute(source: .hrv, destination: dest("x"))
        XCTAssertEqual(ModulationMatrix.output(for: r, frame: frame(hrv: 0.8, src: .cameraPPG)), 0.8, accuracy: 1e-6)
    }

    func testEvaluate_trustedRouteDropsOutOnWeakSource() {
        let m = ModulationMatrix(routes: [
            ModRoute(source: .hrv, destination: dest("brightness"), requiresTrustedSource: true)
        ])
        XCTAssertNil(m.evaluate(frame(hrv: 0.9, src: .watch))[dest("brightness")])
        XCTAssertEqual(m.evaluate(frame(hrv: 0.9, src: .ble))[dest("brightness")] ?? -1, 0.9, accuracy: 1e-6)
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

    func testRoute_codableRoundTripPreservesTrustFlag() throws {
        let r = ModRoute(source: .hrv, destination: dest("x"), requiresTrustedSource: true)
        let back = try JSONDecoder().decode(ModRoute.self, from: JSONEncoder().encode(r))
        XCTAssertTrue(back.requiresTrustedSource)
    }

    func testRoute_decodesWithoutTrustKey_defaultsFalse() throws {
        let r = ModRoute(source: .hrv, destination: dest("x"), requiresTrustedSource: true)
        let data = try JSONEncoder().encode(r)
        guard var obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return XCTFail("route did not encode to a JSON object")
        }
        obj.removeValue(forKey: "requiresTrustedSource")
        let stripped = try JSONSerialization.data(withJSONObject: obj)
        let back = try JSONDecoder().decode(ModRoute.self, from: stripped)
        XCTAssertFalse(back.requiresTrustedSource)
    }

    // MARK: - smoothingTau (engine-side; pure matrix is unaffected)

    func testOutput_ignoresSmoothingTau() {
        // Smoothing is applied by ModulationEngine, not the pure matrix output.
        let r = ModRoute(source: .coherence, destination: dest("x"), smoothingTau: 2.0)
        XCTAssertEqual(ModulationMatrix.output(for: r, frame: frame(coh: 0.5)), 0.5, accuracy: 1e-6)
    }

    func testRoute_smoothingTauClampedNonNegative() {
        XCTAssertEqual(ModRoute(source: .hrv, destination: dest("x"), smoothingTau: -3).smoothingTau, 0)
    }

    func testRoute_codableRoundTripPreservesSmoothingTau() throws {
        let r = ModRoute(source: .hrv, destination: dest("x"), smoothingTau: 0.35)
        let back = try JSONDecoder().decode(ModRoute.self, from: JSONEncoder().encode(r))
        XCTAssertEqual(back.smoothingTau, 0.35, accuracy: 1e-6)
    }

    func testRoute_decodesWithoutSmoothingKey_defaultsZero() throws {
        let r = ModRoute(source: .hrv, destination: dest("x"), smoothingTau: 0.5)
        let data = try JSONEncoder().encode(r)
        guard var obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return XCTFail("route did not encode to a JSON object")
        }
        obj.removeValue(forKey: "smoothingTau")
        let stripped = try JSONSerialization.data(withJSONObject: obj)
        let back = try JSONDecoder().decode(ModRoute.self, from: stripped)
        XCTAssertEqual(back.smoothingTau, 0)
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

    // MARK: - Data-loss hardening (decodeIfPresent LAW + lossy route array)

    /// Mutate one encoded route's JSON dict, return the re-serialized route data.
    private func route(_ r: ModRoute, mutate: (inout [String: Any]) -> Void) throws -> Data {
        let data = try JSONEncoder().encode(r)
        guard var obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "test", code: 1)
        }
        mutate(&obj)
        return try JSONSerialization.data(withJSONObject: obj)
    }

    func testRoute_decodesWithoutIdKey_getsFreshUUID() throws {
        // `id` was one of the 7 naked `try decode` fields — a renamed/removed key
        // must now degrade to a fresh UUID, not throw the route away.
        let r = ModRoute(source: .coherence, destination: dest("x"))
        let stripped = try route(r) { $0.removeValue(forKey: "id") }
        let back = try JSONDecoder().decode(ModRoute.self, from: stripped)
        XCTAssertEqual(back.source, .coherence)          // route survived
        XCTAssertEqual(back.destination, dest("x"))
    }

    func testRoute_decodesWithoutBehaviourKeys_usesNeutralDefaults() throws {
        // mode/depth/invert/enabled all have neutral defaults → dropping every one
        // of them still yields a live, full-depth, non-inverted, enabled route.
        let r = ModRoute(source: .hrv, destination: dest("y"),
                         mode: .hold(value: 0.3, drift: 0.2), depth: 0.4, invert: true, enabled: false)
        let stripped = try route(r) {
            $0.removeValue(forKey: "mode"); $0.removeValue(forKey: "depth")
            $0.removeValue(forKey: "invert"); $0.removeValue(forKey: "enabled")
        }
        let back = try JSONDecoder().decode(ModRoute.self, from: stripped)
        if case .live = back.mode {} else { XCTFail("mode should default to .live") }
        XCTAssertEqual(back.depth, 1.0, accuracy: 1e-6)
        XCTAssertFalse(back.invert)
        XCTAssertTrue(back.enabled)
    }

    func testRoute_missingSource_throws() throws {
        // source/destination are the route's IDENTITY — deliberately kept required
        // so an undecodable one throws and the matrix drops JUST that route.
        let r = ModRoute(source: .coherence, destination: dest("x"))
        let noSource = try route(r) { $0.removeValue(forKey: "source") }
        XCTAssertThrowsError(try JSONDecoder().decode(ModRoute.self, from: noSource))
        let noDest = try route(r) { $0.removeValue(forKey: "destination") }
        XCTAssertThrowsError(try JSONDecoder().decode(ModRoute.self, from: noDest))
    }

    func testMatrix_dropsOneCorruptRoute_keepsTheRest() throws {
        // THE blast-radius test: a retired ModSource case (unknown raw value) on ONE
        // route must drop only that route, not vaporize the whole matrix.
        let m = ModulationMatrix(routes: [
            ModRoute(source: .coherence, destination: dest("a")),
            ModRoute(source: .hrv, destination: dest("b")),
            ModRoute(source: .motion, destination: dest("c"))
        ])
        let data = try JSONEncoder().encode(m)
        guard var obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var routes = obj["routes"] as? [[String: Any]], routes.count == 3 else {
            return XCTFail("matrix did not encode to a 3-route JSON object")
        }
        routes[1]["source"] = "someRetiredSourceCase"   // unknown ModSource raw value
        obj["routes"] = routes
        let corrupted = try JSONSerialization.data(withJSONObject: obj)
        let back = try JSONDecoder().decode(ModulationMatrix.self, from: corrupted)
        XCTAssertEqual(back.routes.count, 2, "the two intact routes must survive")
        XCTAssertEqual(Set(back.routes.map(\.destination)), [dest("a"), dest("c")])
    }

    func testMatrix_decodesWithoutRoutesKey_isEmptyNotThrow() throws {
        let empty = try JSONSerialization.data(withJSONObject: [String: Any]())
        let back = try JSONDecoder().decode(ModulationMatrix.self, from: empty)
        XCTAssertTrue(back.routes.isEmpty)
    }
}
