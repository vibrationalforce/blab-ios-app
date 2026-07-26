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

    // MARK: - Persistence tolerance (#170)

    /// Plants RAW bytes under the router's storage key. `save()` can only ever write
    /// well-formed JSON for the CURRENT schema, so the failure this guards against —
    /// a stored route the decoder cannot read — is unreachable through the public API.
    /// Without this seam a test could only assert that valid data stays valid, which is
    /// exactly the unfalsifiable shape to avoid.
    private func plantRoutes(_ json: String, into d: UserDefaults) {
        d.set(Data(json.utf8), forKey: "signalGraph.routes.v1")
    }

    /// THE REGRESSION TEST. One unreadable route used to fail the whole array decode:
    /// `load` returned early, the graph kept its empty defaults, and the FIRST subsequent
    /// edit called `save()` — writing those defaults back over the file. The user's entire
    /// patchbay, gone for good. Now the bad edge alone is dropped.
    func testLoad_oneCorruptRoute_keepsTheOthers() {
        let d = freshDefaults()
        // Middle element is missing the required `sinkPortID` → it alone must fail.
        plantRoutes("""
        [{"id":"\(UUID().uuidString)","sourcePortID":"bus.musical","sinkPortID":"adm.out",
          "enabled":true,"amount":1,"converterID":"music→spatial"},
         {"id":"\(UUID().uuidString)","sourcePortID":"bus.bio","enabled":true,"amount":1},
         {"id":"\(UUID().uuidString)","sourcePortID":"blehrs.in","sinkPortID":"osc.out",
          "enabled":true,"amount":1}]
        """, into: d)

        let r = SignalRouter(defaults: d)
        XCTAssertEqual(r.graph.routes.count, 2, "the two readable routes must survive the one bad one")
        XCTAssertTrue(r.isConnected("bus.musical", "adm.out"))
        // The strap route is the one with teeth: `blehrs.in` is the heart-strap's ONLY
        // start hook (applyRouting reads hasEnabledRoute(fromSource:)), so losing it
        // silently disconnects the user's sensor with no visible cause.
        XCTAssertTrue(r.graph.hasEnabledRoute(fromSource: "blehrs.in"))
    }

    /// The precondition that makes the test above falsifiable: this file really is
    /// undecodable strictly. If it weren't, the assertions would pass against the old
    /// all-or-nothing decoder too and would prove nothing.
    func testLoad_thePlantedFile_failsAStrictDecode() {
        let d = freshDefaults()
        plantRoutes("""
        [{"id":"\(UUID().uuidString)","sourcePortID":"bus.bio","enabled":true,"amount":1}]
        """, into: d)
        let data = d.data(forKey: "signalGraph.routes.v1")
        XCTAssertNotNil(data)
        XCTAssertNil(try? JSONDecoder().decode([SignalRoute].self, from: data ?? Data()),
                     "precondition: the strict decode must fail on this file")
    }

    /// Bounded loss must stay bounded: what survived the tolerant load must still be
    /// there after the next edit persists. This is the half that actually prevents the
    /// wipe — tolerating the read is useless if the write then flattens it.
    func testLoad_survivorsArePersistedByTheNextEdit() {
        let d = freshDefaults()
        plantRoutes("""
        [{"id":"\(UUID().uuidString)","sourcePortID":"bus.musical","sinkPortID":"adm.out",
          "enabled":true,"amount":1,"converterID":"music→spatial"},
         {"id":"\(UUID().uuidString)","sourcePortID":"bus.bio"}]
        """, into: d)

        let r1 = SignalRouter(defaults: d)
        r1.connect("midi.in", "midi.out")          // any edit → save()
        let r2 = SignalRouter(defaults: d)         // reload from what was just written
        XCTAssertTrue(r2.isConnected("bus.musical", "adm.out"),
                      "the survivor must not be lost by the save that follows the tolerant load")
        XCTAssertTrue(r2.isConnected("midi.in", "midi.out"))
    }

    /// A stored blob that is not an array at all stays "nothing usable": the router keeps
    /// its (empty) defaults rather than crashing or inventing routes.
    func testLoad_notAnArray_keepsDefaults() {
        let d = freshDefaults()
        plantRoutes(#"{"routes":[]}"#, into: d)
        let r = SignalRouter(defaults: d)
        XCTAssertTrue(r.graph.routes.isEmpty)
        XCTAssertFalse(r.graph.ports.isEmpty, "the code-defined inventory is unaffected")
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
