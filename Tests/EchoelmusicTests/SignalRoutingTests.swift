// SignalRoutingTests.swift
// Echoel — the universal patchbay's pure logic: type-aware connect (same-kind +
// converter), direction/duplicate guards, port inventory churn (endpoints come and
// go), intelligent default suggestions, and Codable round-trip for saved patches.

#if canImport(AVFoundation) && canImport(Accelerate)
import XCTest
import Foundation
@testable import Echoelmusic

final class SignalRoutingTests: XCTestCase {

    private func graph() -> SignalGraph {
        SignalGraph(ports: [
            SignalPort(id: "bus.bio",     name: "Bio",      kind: .controlBio,     direction: .source, transport: .internalBus),
            SignalPort(id: "bus.musical", name: "Music",    kind: .controlMusical, direction: .source, transport: .internalBus),
            SignalPort(id: "midi.out",    name: "MIDI Out", kind: .controlChange,  direction: .sink,   transport: .coreMIDI),
            SignalPort(id: "artnet.0",    name: "Art-Net",  kind: .light,          direction: .sink,   transport: .artNet),
            SignalPort(id: "audio.master",name: "Master",   kind: .audio,          direction: .sink,   transport: .audioIO)
        ])
    }

    func testSameKind_connectsDirectly_noConverter() {
        var g = SignalGraph(ports: [
            SignalPort(id: "a", name: "A", kind: .light, direction: .source, transport: .internalBus),
            SignalPort(id: "b", name: "B", kind: .light, direction: .sink, transport: .artNet)
        ])
        XCTAssertEqual(g.check(sourceID: "a", sinkID: "b"), .ok(converterID: nil))
        let r = g.connect(sourceID: "a", sinkID: "b")
        XCTAssertNotNil(r)
        XCTAssertNil(r?.converterID)
        XCTAssertEqual(g.routes.count, 1)
    }

    func testCrossKind_usesConverter_whenCatalogHasOne() {
        var g = graph()
        // controlBio → controlChange exists in the default catalog ("bio→cc").
        XCTAssertEqual(g.check(sourceID: "bus.bio", sinkID: "midi.out"), .ok(converterID: "bio→cc"))
        let r = g.connect(sourceID: "bus.bio", sinkID: "midi.out")
        XCTAssertEqual(r?.converterID, "bio→cc")
        // controlMusical → light exists ("music→light").
        XCTAssertEqual(g.check(sourceID: "bus.musical", sinkID: "artnet.0"), .ok(converterID: "music→light"))
    }

    func testIncompatibleKinds_rejected() {
        var g = graph()
        // No converter controlBio → audio.
        XCTAssertEqual(g.check(sourceID: "bus.bio", sinkID: "audio.master"), .incompatibleKinds)
        XCTAssertNil(g.connect(sourceID: "bus.bio", sinkID: "audio.master"))
        XCTAssertTrue(g.routes.isEmpty)
    }

    func testWrongDirection_andUnknownPort() {
        var g = graph()
        // midi.out is a sink → cannot be a source.
        XCTAssertEqual(g.check(sourceID: "midi.out", sinkID: "artnet.0"), .wrongDirection)
        XCTAssertEqual(g.check(sourceID: "bus.bio", sinkID: "nope"), .unknownPort)
    }

    func testDuplicate_rejectedSecondTime() {
        var g = graph()
        XCTAssertNotNil(g.connect(sourceID: "bus.bio", sinkID: "midi.out"))
        XCTAssertEqual(g.check(sourceID: "bus.bio", sinkID: "midi.out"), .duplicate)
        XCTAssertNil(g.connect(sourceID: "bus.bio", sinkID: "midi.out"))
        XCTAssertEqual(g.routes.count, 1)
    }

    func testRemovePort_dropsTouchingRoutes() {
        var g = graph()
        g.connect(sourceID: "bus.bio", sinkID: "midi.out")
        g.connect(sourceID: "bus.musical", sinkID: "artnet.0")
        g.removePort("midi.out")
        XCTAssertNil(g.port("midi.out"))
        XCTAssertEqual(g.routes.count, 1)                    // only the artnet route survives
        XCTAssertEqual(g.routes.first?.sinkPortID, "artnet.0")
    }

    func testUpsert_replacesByID() {
        var g = graph()
        g.upsert(SignalPort(id: "midi.out", name: "Renamed", kind: .controlChange, direction: .sink, transport: .coreMIDI))
        XCTAssertEqual(g.ports.filter { $0.id == "midi.out" }.count, 1)
        XCTAssertEqual(g.port("midi.out")?.name, "Renamed")
    }

    func testSuggestions_crossBoundaryOnly_andLiveKinds() {
        let g = graph()
        let s = g.suggestedConnections()
        // bio→midi.out, music→midi.out, music→artnet.0 are valid cross-boundary edges.
        XCTAssertTrue(s.contains { $0.sourceID == "bus.bio" && $0.sinkID == "midi.out" })
        XCTAssertTrue(s.contains { $0.sourceID == "bus.musical" && $0.sinkID == "artnet.0" })
        // No suggestion into audio.master (no converter), and none internal→internal.
        XCTAssertFalse(s.contains { $0.sinkID == "audio.master" })
    }

    func testCatalog_reachableKinds() {
        let cat = ConverterCatalog.default
        let reach = cat.reachableKinds(from: .controlMusical)
        XCTAssertTrue(reach.contains(.controlMusical))   // identity
        XCTAssertTrue(reach.contains(.light))
        XCTAssertTrue(reach.contains(.spatial))
    }

    func testGraph_codableRoundTrip() throws {
        var g = graph()
        g.connect(sourceID: "bus.musical", sinkID: "artnet.0", amount: 0.5)
        let data = try JSONEncoder().encode(g)
        let back = try JSONDecoder().decode(SignalGraph.self, from: data)
        XCTAssertEqual(back, g)
        XCTAssertEqual(back.routes.first?.amount, 0.5)
        XCTAssertEqual(back.routes.first?.converterID, "music→light")
    }

    func testTransport_industryStandards_andHonestStatus() {
        // The standards the founder asked about are all typed.
        let all = Set(SignalTransport.allCases)
        for t: SignalTransport in [.coreMIDI, .midi2, .mpe, .rtpMIDI, .osc, .admOSC,
                                   .artNet, .sacn, .audioIO, .auv3, .abletonLink,
                                   .bleHRS, .rtmp, .srt, .ndi] {
            XCTAssertTrue(all.contains(t))
        }
        // Honest: shipping transports are live; not-yet-wired ones are roadmap.
        XCTAssertEqual(SignalTransport.artNet.status, .live)
        XCTAssertEqual(SignalTransport.osc.status, .live)
        XCTAssertEqual(SignalTransport.midi2.status, .roadmap)
        XCTAssertEqual(SignalTransport.rtmp.status, .roadmap)
        XCTAssertEqual(SignalTransport.ndi.status, .roadmap)
    }

    func testRoute_clampsAmount() {
        let r = SignalRoute(sourcePortID: "a", sinkPortID: "b", amount: 9)
        XCTAssertEqual(r.amount, 1, accuracy: 1e-9)
        let r2 = SignalRoute(sourcePortID: "a", sinkPortID: "b", amount: .nan)
        XCTAssertEqual(r2.amount, 1, accuracy: 1e-9)
    }

    func testDefaultInventory_containsNoRoadmapPorts() {
        // Guideline 2.1 (App Store audit 2026-07-16): the shipped patchbay must not
        // show named-but-unbuilt endpoints — a reviewer opening Routing sees only
        // features that exist. RTMP/SRT return the moment their transport goes .live.
        let inventory = SignalRouter.defaultInventory()
        XCTAssertTrue(inventory.allSatisfy { $0.transport.status == .live },
                      "shipped inventory is live-only")
        let ids = Set(inventory.map(\.id))
        XCTAssertFalse(ids.contains("rtmp.out"))
        XCTAssertFalse(ids.contains("srt.out"))
        // The doors that DO ship stay present.
        for id in ["bus.bio", "bus.musical", "midi.in", "blehrs.in", "midi.out",
                   "osc.out", "adm.out", "artnet.out", "sacn.out", "audio.master"] {
            XCTAssertTrue(ids.contains(id), "live port \(id) must remain")
        }
        // The full typed inventory still carries the roadmap ports (re-add = flip status).
        let full = Set(SignalRouter.allPortsIncludingRoadmap().map(\.id))
        XCTAssertTrue(full.contains("rtmp.out") && full.contains("srt.out"))
    }
}
#endif
