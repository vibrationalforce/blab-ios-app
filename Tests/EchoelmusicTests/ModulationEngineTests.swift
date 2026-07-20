import XCTest
@testable import Echoelmusic

@MainActor
final class ModulationEngineTests: XCTestCase {

    private func frame(coh: Float = 0.5, hr: Float = 120, ts: TimeInterval = 0) -> BioSampleFrame {
        BioSampleFrame(
            timestamp: ts, heartRateBPM: hr, hrvNormalized: 0.5,
            breathRate: 12, breathPhase: 0.5, coherence: coh,
            motionEnergy: 0.5, source: .fallback
        )
    }

    private func route(_ source: ModSource, _ key: String, mode: ModMode = .live) -> ModRoute {
        ModRoute(source: source, destination: ModDestination(key), mode: mode)
    }

    // MARK: - dispatch

    func testApply_dispatchesNormalizedValueToRegisteredHandler() {
        let engine = ModulationEngine(matrix: ModulationMatrix(routes: [route(.coherence, "seq.tempo")]))
        var got: Float = -1
        engine.register("seq.tempo") { got = $0 }
        engine.apply(frame(coh: 1.0))
        XCTAssertEqual(got, 1.0, accuracy: 1e-6)
        engine.apply(frame(coh: 0.25, ts: 1))
        XCTAssertEqual(got, 0.25, accuracy: 1e-6)
    }

    func testApply_emptyMatrix_doesNotCallHandler() {
        let engine = ModulationEngine()
        var called = false
        engine.register("seq.tempo") { _ in called = true }
        engine.apply(frame(coh: 1.0))
        XCTAssertFalse(called, "empty matrix must apply nothing (zero-behavior-change default)")
    }

    func testApply_unregisteredDestination_isSilentlyIgnored() {
        // Route targets a key with no handler → no crash, and no OTHER handler fires.
        let engine = ModulationEngine(matrix: ModulationMatrix(routes: [route(.coherence, "no.handler")]))
        var otherCalled = false
        engine.register("some.other") { _ in otherCalled = true }
        engine.apply(frame(coh: 1.0)) // must not crash
        XCTAssertFalse(otherCalled, "an unregistered route must not trigger unrelated handlers")
    }

    func testApply_multipleDestinations_eachGetsItsValue() {
        let engine = ModulationEngine(matrix: ModulationMatrix(routes: [
            route(.coherence, "a"),
            route(.heartRate, "b")
        ]))
        var a: Float = -1, b: Float = -1
        engine.register("a") { a = $0 }
        engine.register("b") { b = $0 }
        engine.apply(frame(coh: 0.3, hr: 200))
        XCTAssertEqual(a, 0.3, accuracy: 1e-6)
        XCTAssertEqual(b, 1.0, accuracy: 1e-6)
    }

    func testApply_holdRoute_emitsHeldValueRegardlessOfBio() {
        let engine = ModulationEngine(matrix: ModulationMatrix(routes: [
            route(.coherence, "seq.tempo", mode: .hold(value: 0.6, drift: 0))
        ]))
        var got: Float = -1
        engine.register("seq.tempo") { got = $0 }
        engine.apply(frame(coh: 0.0))
        XCTAssertEqual(got, 0.6, accuracy: 1e-6)
    }

    // MARK: - per-route smoothing (M.4)

    private func smoothedRoute(_ source: ModSource, _ key: String, tau: Float) -> ModRoute {
        ModRoute(source: source, destination: ModDestination(key), smoothingTau: tau)
    }

    func testApply_smoothingZero_isInstant() {
        // Default tau 0 → output jumps to the raw value (unchanged behavior).
        let engine = ModulationEngine(matrix: ModulationMatrix(routes: [route(.coherence, "x")]))
        var got: Float = -1
        engine.register("x") { got = $0 }
        engine.apply(frame(coh: 1.0, ts: 0)); XCTAssertEqual(got, 1.0, accuracy: 1e-6)
        engine.apply(frame(coh: 0.0, ts: 1)); XCTAssertEqual(got, 0.0, accuracy: 1e-6)
    }

    func testApply_smoothing_seedsAtFirstValue_noStartupRamp() {
        // First sample emits the raw value (no ramp up from 0).
        let engine = ModulationEngine(matrix: ModulationMatrix(routes: [smoothedRoute(.coherence, "x", tau: 0.5)]))
        var got: Float = -1
        engine.register("x") { got = $0 }
        engine.apply(frame(coh: 0.7, ts: 0))
        XCTAssertEqual(got, 0.7, accuracy: 1e-6)
    }

    func testApply_smoothing_rampsTowardTarget() {
        // tau 0.2 s, dt 0.1 s → alpha = 0.1/0.3 = 1/3.
        let engine = ModulationEngine(matrix: ModulationMatrix(routes: [smoothedRoute(.coherence, "x", tau: 0.2)]))
        var got: Float = -1
        engine.register("x") { got = $0 }
        engine.apply(frame(coh: 1.0, ts: 0))          // seed at 1.0
        XCTAssertEqual(got, 1.0, accuracy: 1e-4)
        engine.apply(frame(coh: 0.0, ts: 1))          // (2/3)*1.0
        XCTAssertEqual(got, 0.666667, accuracy: 1e-4)
        engine.apply(frame(coh: 0.0, ts: 2))          // (2/3)*0.6667
        XCTAssertEqual(got, 0.444444, accuracy: 1e-4)
    }

    func testApply_disablingRoute_prunesAndReseedsSmoothing() {
        let engine = ModulationEngine(matrix: ModulationMatrix(routes: [smoothedRoute(.coherence, "x", tau: 0.2)]))
        var got: Float = -1
        engine.register("x") { got = $0 }
        engine.apply(frame(coh: 1.0, ts: 0))          // seed 1.0
        XCTAssertEqual(got, 1.0, accuracy: 1e-4)

        engine.matrix.routes[0].enabled = false
        engine.apply(frame(coh: 1.0, ts: 1))          // route off → handler not called, got unchanged
        XCTAssertEqual(got, 1.0, accuracy: 1e-4)

        engine.matrix.routes[0].enabled = true
        engine.apply(frame(coh: 0.3, ts: 2))          // re-seeds (pruned) → emits raw, no ramp from old 1.0
        XCTAssertEqual(got, 0.3, accuracy: 1e-4)
    }

    func testApply_smoothedRouteToZeroDecays_notInstant() {
        // A smoothed route does not snap to 0 in one tick.
        let plain = ModulationEngine(matrix: ModulationMatrix(routes: [route(.coherence, "x")]))
        let smooth = ModulationEngine(matrix: ModulationMatrix(routes: [smoothedRoute(.coherence, "x", tau: 0.5)]))
        var p: Float = -1, s: Float = -1
        plain.register("x") { p = $0 }; smooth.register("x") { s = $0 }
        plain.apply(frame(coh: 1.0, ts: 0)); smooth.apply(frame(coh: 1.0, ts: 0))
        plain.apply(frame(coh: 0.0, ts: 1)); smooth.apply(frame(coh: 0.0, ts: 1))
        XCTAssertEqual(p, 0.0, accuracy: 1e-6)         // instant
        XCTAssertGreaterThan(s, 0.0)                    // still decaying
        XCTAssertLessThan(s, 1.0)
    }

    // MARK: - registry

    func testRegister_replacesAndUnregisters() {
        let engine = ModulationEngine(matrix: ModulationMatrix(routes: [route(.coherence, "x")]))
        var first = 0, second = 0
        engine.register("x") { _ in first += 1 }
        engine.register("x") { _ in second += 1 } // replaces
        engine.apply(frame(coh: 1.0))
        XCTAssertEqual(first, 0)
        XCTAssertEqual(second, 1)
        engine.unregister("x")
        engine.apply(frame(coh: 1.0, ts: 1))
        XCTAssertEqual(second, 1, "unregistered handler must not fire")
    }

    func testRegisteredDestinations_isSorted() {
        let engine = ModulationEngine()
        engine.register("z") { _ in }
        engine.register("a") { _ in }
        XCTAssertEqual(engine.registeredDestinations, ["a", "z"])
    }

    // MARK: - tick dedup via bus

    // publish(bio:) updates the @MainActor latestBio snapshot via an async
    // Task, so let it settle before ticking. Timestamps must be FRESH (near now)
    // because tick(from:) freshness-gates on usableBio() (#60) — the fallback
    // source's window is 5 s, so ancient fake timestamps would read as stale.
    func testTick_dedupsOnFrameTimestamp() async {
        let bus = EngineBus()
        let engine = ModulationEngine(matrix: ModulationMatrix(routes: [route(.coherence, "x")]))
        var count = 0
        engine.register("x") { _ in count += 1 }

        let t0 = CFAbsoluteTimeGetCurrent()
        bus.publish(bio: frame(coh: 1.0, ts: t0))
        try? await Task.sleep(for: .milliseconds(20))
        engine.tick(from: bus)
        engine.tick(from: bus) // same timestamp → no re-apply
        XCTAssertEqual(count, 1)

        bus.publish(bio: frame(coh: 1.0, ts: t0 + 0.001))
        try? await Task.sleep(for: .milliseconds(20))
        engine.tick(from: bus) // new (still-fresh) timestamp → applies again
        XCTAssertEqual(count, 2)
    }

    // #60 freshness gate: a stale bio frame must NOT drive the modulation brain,
    // a fresh one must. Proves tick(from:) routes through usableBio(), so a frozen
    // reading (dropped strap / lifted finger / stalled Watch) idles the mod-brain.
    func testTick_ignoresStaleFrame_appliesFreshFrame() async {
        let bus = EngineBus()
        let engine = ModulationEngine(matrix: ModulationMatrix(routes: [route(.coherence, "seq.tempo")]))
        var fired = false
        engine.register("seq.tempo") { _ in fired = true }

        // Stale: the fallback source's window is 5 s; a 100 s-old frame is dead.
        bus.publish(bio: frame(coh: 1.0, ts: CFAbsoluteTimeGetCurrent() - 100))
        try? await Task.sleep(for: .milliseconds(20))
        engine.tick(from: bus)
        XCTAssertFalse(fired, "a stale bio frame must not drive the modulation brain")

        // Fresh: the same route now fires.
        bus.publish(bio: frame(coh: 1.0, ts: CFAbsoluteTimeGetCurrent()))
        try? await Task.sleep(for: .milliseconds(20))
        engine.tick(from: bus)
        XCTAssertTrue(fired, "a fresh bio frame drives the modulation brain")
    }

    func testTick_noFrame_doesNothing() {
        let bus = EngineBus()
        let engine = ModulationEngine(matrix: ModulationMatrix(routes: [route(.coherence, "x")]))
        var called = false
        engine.register("x") { _ in called = true }
        engine.tick(from: bus) // bus has no latestBio yet
        XCTAssertFalse(called)
    }

    // #60 item-2 honesty: once bio goes stale the live-modulation meter must BLANK,
    // not keep displaying the last amounts as if the body were still driving them.
    func testTick_staleFrame_blanksTheMeter() async {
        let bus = EngineBus()
        let engine = ModulationEngine(matrix: ModulationMatrix(routes: [route(.coherence, "seq.tempo")]))
        engine.register("seq.tempo") { _ in }

        // Fresh frame populates the meter (lastOutputs, the item-2 readout).
        bus.publish(bio: frame(coh: 1.0, ts: CFAbsoluteTimeGetCurrent()))
        try? await Task.sleep(for: .milliseconds(20))
        engine.tick(from: bus)
        XCTAssertFalse(engine.lastOutputs.isEmpty, "a fresh frame populates the item-2 meter")

        // A stale frame (100 s old, past the fallback window) must blank it.
        bus.publish(bio: frame(coh: 1.0, ts: CFAbsoluteTimeGetCurrent() - 100))
        try? await Task.sleep(for: .milliseconds(20))
        engine.tick(from: bus)
        XCTAssertTrue(engine.lastOutputs.isEmpty, "stale bio must blank the meter (item-2 honesty)")
    }

    // MARK: - lifecycle

    func testStartStop_togglesIsActive() {
        let bus = EngineBus()
        let engine = ModulationEngine()
        XCTAssertFalse(engine.isActive)
        engine.start(subscribing: bus)
        XCTAssertTrue(engine.isActive)
        engine.start(subscribing: bus) // idempotent
        XCTAssertTrue(engine.isActive)
        engine.stop()
        XCTAssertFalse(engine.isActive)
    }

    // MARK: - output tap

    func testOutputTap_firesForEachActiveOutput() {
        let engine = ModulationEngine(matrix: ModulationMatrix(routes: [
            route(.coherence, "a"), route(.heartRate, "b")
        ]))
        var taps: [String: Float] = [:]
        engine.outputTap = { dest, v in taps[dest.key] = v }
        engine.apply(frame(coh: 0.5, hr: 200))
        XCTAssertEqual(taps["a"] ?? -1, 0.5, accuracy: 1e-6)
        XCTAssertEqual(taps["b"] ?? -1, 1.0, accuracy: 1e-6)
    }

    func testOutputTap_notCalledForEmptyMatrix() {
        let engine = ModulationEngine()
        var calls = 0
        engine.outputTap = { _, _ in calls += 1 }
        engine.apply(frame(coh: 1.0))
        XCTAssertEqual(calls, 0)
    }

    // MARK: - persistence

    func testPersistence_savesAndReloadsMatrix() {
        let suite = "ModulationEngineTests.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let defaults = UserDefaults(suiteName: suite)!

        let e1 = ModulationEngine(defaults: defaults)
        e1.matrix.routes.append(route(.coherence, "seq.tempo", mode: .hold(value: 0.4, drift: 0.1)))
        e1.save()

        let e2 = ModulationEngine(defaults: defaults)
        XCTAssertEqual(e2.matrix.routes.count, 1)
        XCTAssertEqual(e2.matrix.routes.first?.source, .coherence)
        XCTAssertEqual(e2.matrix.routes.first?.destination, ModDestination("seq.tempo"))
    }

    func testInit_noPersistedData_keepsPassedMatrix() {
        let suite = "ModulationEngineTests.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let defaults = UserDefaults(suiteName: suite)!
        let m = ModulationMatrix(routes: [route(.hrv, "x")])
        let e = ModulationEngine(matrix: m, defaults: defaults)
        XCTAssertEqual(e.matrix.routes.count, 1)
        XCTAssertEqual(e.matrix.routes.first?.source, .hrv)
    }
}
