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

    func testBLEStrapPort_isARoutableLiveSource() {
        // NAME CORRECTED 2026-07-26: this was `…ActsAsTheDoor`, and its comment said the
        // port is the strap's ONLY start hook (B4, 2026-07-12). That stopped being true on
        // 2026-07-15 — BLE-3 removed the coupling because `applyRouting` became a SECOND
        // lifecycle owner that killed a pill-started strap on every unrelated Patchbay edit
        // (see EchoelmusicApp.applyRouting). `hasEnabledRoute(fromSource:)` has NO production
        // caller today; the assertions below therefore pin ROUTABILITY (the port is live, is
        // a source, and accepts a bio-compatible sink) — not a lifecycle door. The strap's one
        // owner is the pulse-pill source dropdown.
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

    /// ONE payload, shared by the regression test and its precondition, so that editing the
    /// literal cannot leave the precondition guarding a file nobody loads any more. The
    /// middle element is missing the required `sinkPortID`: a route without its two ports is
    /// not a degraded route, it is not a route, so it must fail even the forgiving decoder.
    private func corruptedRouteFile() -> String {
        """
        [{"id":"\(UUID().uuidString)","sourcePortID":"bus.musical","sinkPortID":"adm.out",
          "enabled":true,"amount":1,"converterID":"music→spatial"},
         {"id":"\(UUID().uuidString)","sourcePortID":"bus.bio","enabled":true,"amount":1},
         {"id":"\(UUID().uuidString)","sourcePortID":"blehrs.in","sinkPortID":"osc.out",
          "enabled":true,"amount":1}]
        """
    }

    /// THE REGRESSION TEST. One unreadable route used to fail the whole array decode:
    /// `load` returned early, the graph kept its empty defaults, and the FIRST subsequent
    /// edit called `save()` — writing those defaults back over the file. Every route the
    /// user had patched, gone for good. Now the bad edge alone is dropped.
    func testLoad_oneCorruptRoute_keepsTheOthers() {
        let d = freshDefaults()
        plantRoutes(corruptedRouteFile(), into: d)

        let r = SignalRouter(defaults: d)
        XCTAssertEqual(r.graph.routes.count, 2, "the two readable routes must survive the one bad one")
        XCTAssertTrue(r.isConnected("bus.musical", "adm.out"))
        XCTAssertTrue(r.isConnected("blehrs.in", "osc.out"),
                      "the element AFTER the bad one must not be lost with it")
    }

    /// The precondition that makes the test above falsifiable — it plants the SAME payload.
    /// If that file decoded strictly, the assertions there would pass against the old
    /// all-or-nothing decoder too and would prove nothing.
    func testLoad_thePlantedFile_failsAStrictDecode() {
        let d = freshDefaults()
        plantRoutes(corruptedRouteFile(), into: d)
        guard let data = d.data(forKey: "signalGraph.routes.v1") else {
            return XCTFail("the seam planted nothing — the precondition proves nothing")
        }
        XCTAssertNil(try? JSONDecoder().decode([SignalRoute].self, from: data),
                     "precondition: the strict decode must fail on this file")
    }

    /// THE OTHER HALF (`SignalRoute.init(from:)`). Element-tolerance alone does NOT survive a
    /// schema change: if a future required field made EVERY stored route throw, all of them
    /// would become holes, the compact would yield `[]`, and the first edit would persist that
    /// emptiness — the same total wipe, one log line richer. So the element decoder must treat
    /// everything except the two port ids as optional. This file is what a route written by an
    /// OLDER version looks like against a NEWER one: only the ports, plus a field this build
    /// has never heard of.
    func testLoad_routeMissingEveryOptionalField_stillLoadsWithDefaults() {
        let d = freshDefaults()
        plantRoutes("""
        [{"sourcePortID":"bus.musical","sinkPortID":"artnet.out","futureField":42}]
        """, into: d)

        let r = SignalRouter(defaults: d)
        XCTAssertEqual(r.graph.routes.count, 1, "a route is identified by its ports, nothing else")
        let route = r.graph.routes.first
        XCTAssertEqual(route?.enabled, true, "a stored route defaults to enabled, not silently muted")
        XCTAssertEqual(route?.amount, 1.0)
        XCTAssertNil(route?.converterID)
    }

    /// The clamp in the memberwise `init` was BYPASSED on load, because the synthesized decoder
    /// assigned fields directly; the forgiving decoder delegates to that `init` instead.
    /// PRE-EMPTIVE, not a closed live bug — nothing reads `route.amount` today (#171), and
    /// `JSONDecoder` throws on non-conforming floats, so a stored NaN was never representable.
    ///
    /// BOTH arms are needed: `1.0` is ALSO the missing-key fallback, so the out-of-range case
    /// alone would pass against a decoder that ignored `amount` entirely. The in-range arm is
    /// what proves the value is actually read.
    func testLoad_amount_isReadAndClampedOnLoad() {
        let inRange = freshDefaults()
        plantRoutes("""
        [{"sourcePortID":"bus.musical","sinkPortID":"artnet.out","amount":0.4}]
        """, into: inRange)
        XCTAssertEqual(SignalRouter(defaults: inRange).graph.routes.first?.amount, 0.4,
                       "an in-range amount must survive — not silently become the default")

        let tooHigh = freshDefaults()
        plantRoutes("""
        [{"sourcePortID":"bus.musical","sinkPortID":"artnet.out","amount":7.5}]
        """, into: tooHigh)
        XCTAssertEqual(SignalRouter(defaults: tooHigh).graph.routes.first?.amount, 1.0)
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
    /// its (empty) defaults rather than crashing or inventing routes. HONEST LABEL: this one
    /// behaves identically before and after the change, so it is a non-regression guard on
    /// the boundary between "unreadable" and "readable but empty" — not a regression test.
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
