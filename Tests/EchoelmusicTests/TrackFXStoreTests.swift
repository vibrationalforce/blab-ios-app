// TrackFXStoreTests.swift
// Echoel — the PER-TRACK FX spine (Module 2 of the comprehensive interface). Guards the
// two load-bearing promises: (1) an un-dialed bus is an EXACT passthrough, so wiring this
// into the render paths is bit-identical until the user acts; (2) settings persist so a
// dialed-in dub filter survives relaunch.

import XCTest
@testable import Echoelmusic

final class TrackFXStoreTests: XCTestCase {

    // MARK: - The passthrough promise (pure)

    func testOffIsPassthrough() {
        XCTAssertTrue(TrackFX.off.isPassthrough)
        var insert = TrackFX.off.makeInsert(sampleRate: 48_000)
        for x in stride(from: -1.0 as Float, through: 1.0, by: 0.19) {
            XCTAssertEqual(insert.process(x), x, accuracy: 1e-6,
                           "an off insert must pass the signal through untouched")
        }
    }

    func testDialedIsNotPassthrough() {
        XCTAssertFalse(TrackFX(filter: .lowPass, cutoffHz: 800).isPassthrough,
                       "a set filter is an active insert")
        XCTAssertFalse(TrackFX(filter: .off, drive: 0.4).isPassthrough,
                       "drive alone is an active insert")
    }

    func testLowPassActuallyFilters() {
        // A dialed low-pass must change a bright signal (not a passthrough).
        var lp = TrackFX(filter: .lowPass, cutoffHz: 500, resonance: 0.707)
            .makeInsert(sampleRate: 48_000)
        var changed = false
        var prev: Float = 1
        for i in 0..<64 {
            let x: Float = (i % 2 == 0) ? 1 : -1        // ~Nyquist tone → heavily attenuated
            let y = lp.process(x)
            if abs(y - x) > 1e-3 { changed = true }
            prev = y
        }
        XCTAssertTrue(changed, "a low-pass at 500 Hz must attenuate a near-Nyquist tone")
        XCTAssertTrue(prev.isFinite)
    }

    func testCodableRoundTrip() throws {
        let fx = TrackFX(filter: .highPass, cutoffHz: 2200, resonance: 3.0, drive: 0.6)
        let data = try JSONEncoder().encode(fx)
        let back = try JSONDecoder().decode(TrackFX.self, from: data)
        XCTAssertEqual(back, fx)
    }

    // MARK: - Store behaviour

    @MainActor
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "trackfx.test.\(UUID().uuidString)")!
    }

    @MainActor
    func testFreshInstallIsAllClean() {
        let store = TrackFXStore(defaults: freshDefaults())
        for bus in FXBus.allCases {
            XCTAssertTrue(store.settings(for: bus).isPassthrough, "\(bus) starts clean")
            XCTAssertNil(store.insert(for: bus, sampleRate: 48_000),
                         "a clean bus installs no insert")
        }
    }

    @MainActor
    func testSetAndGetPerBus() {
        let store = TrackFXStore(defaults: freshDefaults())
        let dub = TrackFX(filter: .lowPass, cutoffHz: 700, resonance: 2.0, drive: 0.3)
        store.set(dub, for: .melodic)
        XCTAssertEqual(store.melodic, dub)
        XCTAssertEqual(store.settings(for: .melodic), dub)
        XCTAssertNotNil(store.insert(for: .melodic, sampleRate: 48_000),
                        "a dialed bus installs an insert")
        XCTAssertTrue(store.settings(for: .bass).isPassthrough, "other buses untouched")
    }

    @MainActor
    func testPersistAcrossReload() {
        let defaults = freshDefaults()
        do {
            let store = TrackFXStore(defaults: defaults)
            store.set(TrackFX(filter: .lowPass, cutoffHz: 640, drive: 0.25), for: .bass)
        }
        let reloaded = TrackFXStore(defaults: defaults)
        XCTAssertEqual(reloaded.bass.filter, .lowPass)
        XCTAssertEqual(reloaded.bass.cutoffHz, 640, accuracy: 1e-3, "the dub filter survives relaunch")
        XCTAssertTrue(reloaded.melodic.isPassthrough, "an untouched bus is still clean")
    }

    @MainActor
    func testResetToClean() {
        let store = TrackFXStore(defaults: freshDefaults())
        store.set(TrackFX(filter: .highPass, cutoffHz: 3000), for: .drums)
        store.resetToClean()
        for bus in FXBus.allCases {
            XCTAssertTrue(store.settings(for: bus).isPassthrough)
        }
    }
}
