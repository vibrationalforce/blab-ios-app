// SignalRouterTests.swift
// Echoel — the live patchbay holder: real endpoint inventory, type-aware toggling,
// smart auto-patch, and route persistence that survives a relaunch (and drops routes
// whose ports vanished).

#if canImport(AVFoundation) && canImport(Accelerate)
import XCTest
import Foundation
@testable import Echoelmusic

@MainActor
final class SignalRouterTests: XCTestCase {

    private func freshDefaults() -> UserDefaults {
        let d = UserDefaults(suiteName: "router.test.\(UUID().uuidString)")!
        return d
    }

    func testInventory_hasRealEndpoints() {
        let r = SignalRouter(defaults: freshDefaults())
        XCTAssertNotNil(r.graph.port("bus.bio"))
        XCTAssertNotNil(r.graph.port("bus.musical"))
        XCTAssertNotNil(r.graph.port("artnet.out"))
        XCTAssertNotNil(r.graph.port("adm.out"))
        XCTAssertNotNil(r.graph.port("midi.out"))
    }

    func testBLEStrapPort_isLiveSourceAndActsAsTheDoor() {
        // B4/#21: the universal BLE HR strap's ONLY door is this port — wiring
        // it must read as an enabled from-source route (applyRouting's start
        // condition), and the transport must be honest about being live.
        let r = SignalRouter(defaults: freshDefaults())
        let port = r.graph.port("blehrs.in")
        XCTAssertNotNil(port)
        XCTAssertEqual(port?.transport, .bleHRS)
        XCTAssertEqual(port?.transport.status, .live)
        XCTAssertTrue(port?.direction.canSource ?? false)
        XCTAssertFalse(r.graph.hasEnabledRoute(fromSource: "blehrs.in"))
        // Same-kind routing as bus.bio: any bio-compatible sink opens the door.
        XCTAssertTrue(r.connect("blehrs.in", "osc.out"),
                      "strap (controlBio) must reach a control sink like bus.bio does")
        XCTAssertTrue(r.graph.hasEnabledRoute(fromSource: "blehrs.in"))
    }

    func testToggle_connectsAndDisconnects_typeAware() {
        let r = SignalRouter(defaults: freshDefaults())
        // music → light is valid (music→light converter)
        r.toggle("bus.musical", "artnet.out")
        XCTAssertTrue(r.isConnected("bus.musical", "artnet.out"))
        r.toggle("bus.musical", "artnet.out")
        XCTAssertFalse(r.isConnected("bus.musical", "artnet.out"))
    }

    func testConnect_rejectsIncompatible() {
        let r = SignalRouter(defaults: freshDefaults())
        // bio → audio has no converter
        XCTAssertFalse(r.connect("bus.bio", "audio.master"))
        XCTAssertFalse(r.isConnected("bus.bio", "audio.master"))
    }

    func testMidiThru_sameKindConnects() {
        let r = SignalRouter(defaults: freshDefaults())
        XCTAssertTrue(r.connect("midi.in", "midi.out"))   // note → note
    }

    func testSuggestions_andAutoPatch() {
        let r = SignalRouter(defaults: freshDefaults())
        XCTAssertFalse(r.suggestions().isEmpty)
        r.applyAllSuggestions()
        // after auto-patch there are no more suggestions (all made)
        XCTAssertTrue(r.suggestions().isEmpty)
        XCTAssertTrue(r.isConnected("bus.musical", "artnet.out"))
        XCTAssertTrue(r.isConnected("bus.bio", "osc.out"))
    }

    func testPersistence_routesSurviveReload() {
        let d = freshDefaults()
        let r1 = SignalRouter(defaults: d)
        r1.connect("bus.musical", "adm.out")
        // a new instance on the same defaults restores the route
        let r2 = SignalRouter(defaults: d)
        XCTAssertTrue(r2.isConnected("bus.musical", "adm.out"))
    }

    func testClearAll() {
        let r = SignalRouter(defaults: freshDefaults())
        r.applyAllSuggestions()
        XCTAssertFalse(r.graph.routes.isEmpty)
        r.clearAll()
        XCTAssertTrue(r.graph.routes.isEmpty)
    }

    func testOnChange_firesOnEveryMutation() {
        let r = SignalRouter(defaults: freshDefaults())
        var count = 0
        r.onChange = { count += 1 }
        r.connect("bus.musical", "artnet.out")
        XCTAssertEqual(count, 1)
        if let id = r.graph.routes.first?.id { r.disconnect(id) }
        XCTAssertEqual(count, 2)
    }

    func testHasEnabledRoute_drivesOutputActivation() {
        let r = SignalRouter(defaults: freshDefaults())
        XCTAssertFalse(r.graph.hasEnabledRoute(toSink: "artnet.out"))
        r.connect("bus.musical", "artnet.out")
        XCTAssertTrue(r.graph.hasEnabledRoute(toSink: "artnet.out"))
        r.clearAll()
        XCTAssertFalse(r.graph.hasEnabledRoute(toSink: "artnet.out"))
    }
}
#endif
