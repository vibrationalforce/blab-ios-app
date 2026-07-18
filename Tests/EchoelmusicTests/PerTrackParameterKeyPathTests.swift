// PerTrackParameterKeyPathTests.swift
// L2/L4 spine (per-track automation targeting). Pins the pure namespace that
// folds a lane UUID into an engine keyPath ("track.<id>.ddsp.filter.cutoff")
// and parses it back — the critical case being a BASE keyPath that itself
// contains dots (the UUID has none, so the first dot after the prefix ends the
// id). S1 is a pure additive spine: nothing consumes these keyPaths yet.

import XCTest
@testable import Echoelmusic

final class PerTrackParameterKeyPathTests: XCTestCase {

    // MARK: - make / parse roundtrip

    func testMakeParse_roundTrips_withDottedBase() {
        let id = UUID()
        let kp = PerTrackParameterKeyPath.make(laneID: id, base: "ddsp.filter.cutoff")
        XCTAssertEqual(kp, "track.\(id.uuidString).ddsp.filter.cutoff")
        let parsed = PerTrackParameterKeyPath.parse(kp)
        XCTAssertEqual(parsed?.laneID, id)
        XCTAssertEqual(parsed?.base, "ddsp.filter.cutoff")
    }

    func testMakeParse_roundTrips_withSingleTokenBase() {
        let id = UUID()
        let kp = PerTrackParameterKeyPath.make(laneID: id, base: "gain")
        let parsed = PerTrackParameterKeyPath.parse(kp)
        XCTAssertEqual(parsed?.laneID, id)
        XCTAssertEqual(parsed?.base, "gain")
    }

    /// Guards the `firstIndex` (not `lastIndex`) boundary: a base that itself
    /// re-embeds the "track." prefix must still roundtrip — the FIRST dot after
    /// the outer prefix ends the UUID regardless of the base's content. A future
    /// refactor to lastIndex / "strip all track." would break this.
    func testMakeParse_roundTrips_whenBaseReembedsPrefix() {
        let id = UUID()
        let kp = PerTrackParameterKeyPath.make(laneID: id, base: "track.foo")
        XCTAssertEqual(kp, "track.\(id.uuidString).track.foo")
        let parsed = PerTrackParameterKeyPath.parse(kp)
        XCTAssertEqual(parsed?.laneID, id)
        XCTAssertEqual(parsed?.base, "track.foo")
    }

    // MARK: - parse rejects non-per-track / malformed

    func testParse_globalKeyPath_returnsNil() {
        XCTAssertNil(PerTrackParameterKeyPath.parse("ddsp.filter.cutoff"))
    }

    func testParse_prefixButBadUUID_returnsNil() {
        XCTAssertNil(PerTrackParameterKeyPath.parse("track.not-a-uuid.ddsp.filter.cutoff"))
    }

    func testParse_prefixUUIDButEmptyBase_returnsNil() {
        let id = UUID()
        // "track.<uuid>." — trailing dot, no base.
        XCTAssertNil(PerTrackParameterKeyPath.parse("track.\(id.uuidString)."))
    }

    func testParse_prefixUUIDNoDot_returnsNil() {
        let id = UUID()
        // "track.<uuid>" — no separator / no base at all.
        XCTAssertNil(PerTrackParameterKeyPath.parse("track.\(id.uuidString)"))
    }

    func testParse_bareTrackPrefix_returnsNil() {
        XCTAssertNil(PerTrackParameterKeyPath.parse("track."))
    }

    // MARK: - isPerTrack

    func testIsPerTrack_trueForNamespaced_falseForGlobal() {
        let id = UUID()
        XCTAssertTrue(PerTrackParameterKeyPath.isPerTrack(
            PerTrackParameterKeyPath.make(laneID: id, base: "ddsp.amp.level")))
        XCTAssertFalse(PerTrackParameterKeyPath.isPerTrack("ddsp.amp.level"))
    }

    func testParse_acceptsLowercasedUUID() {
        let id = UUID()
        let kp = "track.\(id.uuidString.lowercased()).ddsp.env.attack"
        let parsed = PerTrackParameterKeyPath.parse(kp)
        XCTAssertEqual(parsed?.laneID, id)   // UUID(uuidString:) is case-insensitive
        XCTAssertEqual(parsed?.base, "ddsp.env.attack")
    }

    // MARK: - per-lane descriptor clone

    func testDescriptors_namespaceKeyPaths_inheritRanges_prefixDisplay() {
        let id = UUID()
        let out = PerTrackParameterKeyPath.descriptors(
            for: id, laneLabel: "Bass", from: DDSPParameterCatalog.descriptors)

        XCTAssertEqual(out.count, DDSPParameterCatalog.descriptors.count)

        for (src, dst) in zip(DDSPParameterCatalog.descriptors, out) {
            // keyPath namespaced + parses back to (id, original base).
            let parsed = PerTrackParameterKeyPath.parse(dst.keyPath)
            XCTAssertEqual(parsed?.laneID, id)
            XCTAssertEqual(parsed?.base, src.keyPath)
            // ranges / unit / default inherited verbatim.
            XCTAssertEqual(dst.min, src.min)
            XCTAssertEqual(dst.max, src.max)
            XCTAssertEqual(dst.defaultValue, src.defaultValue)
            XCTAssertEqual(dst.unit, src.unit)
            // displayName carries the lane tag.
            XCTAssertEqual(dst.displayName, "Bass · \(src.displayName)")
        }
    }

    func testDescriptors_emptyLabel_keepsPlainDisplayName() {
        let id = UUID()
        let out = PerTrackParameterKeyPath.descriptors(
            for: id, laneLabel: "", from: DDSPParameterCatalog.descriptors)
        for (src, dst) in zip(DDSPParameterCatalog.descriptors, out) {
            XCTAssertEqual(dst.displayName, src.displayName)
        }
    }

    func testDescriptors_emptyInput_returnsEmpty() {
        XCTAssertTrue(PerTrackParameterKeyPath.descriptors(
            for: UUID(), laneLabel: "Bass", from: []).isEmpty)
    }

    /// `valueLabels` (stepped/enum params) must be inherited verbatim by the
    /// clone. The DDSP catalog has none, so use a hand-made stepped descriptor.
    func testDescriptors_inheritValueLabels() {
        let id = UUID()
        let stepped = ParameterDescriptor(
            keyPath: "ddsp.osc.waveform", displayName: "Waveform",
            min: 0, max: 2, defaultValue: 0, unit: "",
            valueLabels: ["Sine", "Saw", "Square"])
        let out = PerTrackParameterKeyPath.descriptors(
            for: id, laneLabel: "Lead", from: [stepped])
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out.first?.valueLabels, ["Sine", "Saw", "Square"])
        XCTAssertEqual(PerTrackParameterKeyPath.parse(out.first?.keyPath ?? "")?.base,
                       "ddsp.osc.waveform")
    }
}
