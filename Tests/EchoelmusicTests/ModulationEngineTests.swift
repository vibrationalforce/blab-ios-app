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
        // Route targets a key with no handler → no crash, no effect.
        let engine = ModulationEngine(matrix: ModulationMatrix(routes: [route(.coherence, "no.handler")]))
        engine.apply(frame(coh: 1.0)) // must not crash
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
    // Task, so let it settle before ticking.
    func testTick_dedupsOnFrameTimestamp() async {
        let bus = EngineBus()
        let engine = ModulationEngine(matrix: ModulationMatrix(routes: [route(.coherence, "x")]))
        var count = 0
        engine.register("x") { _ in count += 1 }

        bus.publish(bio: frame(coh: 1.0, ts: 100))
        try? await Task.sleep(for: .milliseconds(20))
        engine.tick(from: bus)
        engine.tick(from: bus) // same timestamp → no re-apply
        XCTAssertEqual(count, 1)

        bus.publish(bio: frame(coh: 1.0, ts: 200))
        try? await Task.sleep(for: .milliseconds(20))
        engine.tick(from: bus) // new timestamp → applies again
        XCTAssertEqual(count, 2)
    }

    func testTick_noFrame_doesNothing() {
        let bus = EngineBus()
        let engine = ModulationEngine(matrix: ModulationMatrix(routes: [route(.coherence, "x")]))
        var called = false
        engine.register("x") { _ in called = true }
        engine.tick(from: bus) // bus has no latestBio yet
        XCTAssertFalse(called)
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
