// AutomationStateDecodeTests.swift
// Echoel — #170, the DOCUMENT half of the automation data-loss guard.
//
// `AutomationLaneDecodeTests` already locks the ELEMENT half (a renamed field degrades
// one field, a corrupt keyframe drops one keyframe). This file locks the wrapper around
// them: `AutomationState`, which `AutomationPlayer.init` loads at launch. Its
// synthesized decoder made `enabled` and `lanes` both REQUIRED, so ONE lane element that
// is not a JSON object — or one field added to the document tomorrow — threw,
// `AppGroupStore.load` returned nil, and `init` fell into its `else` branch: every drawn
// curve gone AND `enabled` silently off.
//
// Why this still matters with the editor gone: no shipping surface WRITES automation any
// more (`TimelineAutomationRow` is unmounted), but `applyStep` runs on every transport
// step, so lanes drawn in an earlier build are still played back today. These tests
// defend that read.
//
// Falsifiability, stated per test rather than for the file — the first version of this
// header claimed `testUnknownDocumentField_doesNotThrow` fails on the old code, and that
// was WRONG: JSONDecoder ignores unknown keys, so it passes either way. The tests that
// genuinely FAIL against the pre-#170 synthesized decoder are the four that make a
// REQUIRED key unreadable: `testCorruptLaneElement_keepsTheOtherLanes`,
// `testEveryLaneCorrupt_…`, `testMissingEnabled_…`, `testWrongTypedEnabled_…`,
// `testMissingLanes_…` and `testLanesWrongType_…`. The rest are characterization tests
// and are marked as such where they sit.

import XCTest
@testable import Echoelmusic

final class AutomationStateDecodeTests: XCTestCase {

    private func decode(_ json: String) throws -> AutomationState {
        try JSONDecoder().decode(AutomationState.self, from: Data(json.utf8))
    }

    /// One well-formed lane. `id` is deliberately OMITTED, not synthesized: a UUID string
    /// built from the parameter name would sooner or later be malformed, and
    /// `AutomationLane`'s `decodeIfPresent(UUID.self)` throws on a malformed one — the
    /// test would then be exercising the helper's bug instead of the decoder. Absent `id`
    /// is the case that lane's own decoder already defaults (fresh UUID).
    private func lane(_ parameter: String, tick: Int = 0, value: Double = 0.5) -> String {
        """
        {"parameter":"\(parameter)","points":[{"tick":\(tick),"value":\(value),"curve":"linear","curvature":0}]}
        """
    }

    // MARK: - The element half, at document level

    func testCorruptLaneElement_keepsTheOtherLanes() throws {
        // Middle element is a bare string — `AutomationLane.init(from:)` needs a keyed
        // container, so it throws, and the synthesized `[AutomationLane]` decode threw
        // with it, taking BOTH good lanes and `enabled` down.
        let state = try decode("""
        {"enabled":true,"lanes":[\(lane("tempo")),"garbage",\(lane("masterLevel"))]}
        """)
        XCTAssertTrue(state.enabled, "a corrupt lane must not flip automation off")
        XCTAssertEqual(state.lanes.count, 2, "the two readable lanes must survive the hole")
        XCTAssertEqual(state.lanes.map(\.parameter), ["tempo", "masterLevel"],
                       "surviving lanes keep their order")
    }

    func testEveryLaneCorrupt_yieldsEmptyLanes_butDoesNotThrow() throws {
        // The honest limit of element-tolerance: all-holes is still total lane loss. It
        // must at least not throw, so `enabled` and any future document field survive.
        let state = try decode(#"{"enabled":true,"lanes":[1,2,3]}"#)
        XCTAssertTrue(state.lanes.isEmpty)
        XCTAssertTrue(state.enabled)
    }

    // MARK: - The field half (the decodeIfPresent law)

    func testUnknownDocumentField_doesNotThrow() throws {
        // CHARACTERIZATION, not a regression test — this passes against the old decoder
        // too, because JSONDecoder ignores unknown keys. It is here to pin the direction
        // of the compatibility that DOES hold (forward: an old build reading a newer
        // file), so nobody "fixes" it later with a strict-keys decoding strategy. The
        // direction that was broken is the opposite one, covered by the tests above:
        // a REQUIRED key going unreadable.
        let state = try decode("""
        {"enabled":true,"lanes":[\(lane("tempo"))],"schemaVersion":7,"loopMode":"bar"}
        """)
        XCTAssertTrue(state.enabled)
        XCTAssertEqual(state.lanes.count, 1)
    }

    func testMissingEnabled_defaultsToOff_doesNotThrow() throws {
        let state = try decode("{\"lanes\":[\(lane("tempo"))]}")
        XCTAssertFalse(state.enabled,
                       "an unreadable flag must never be able to turn automation ON")
        XCTAssertEqual(state.lanes.count, 1, "the lanes still load")
    }

    func testWrongTypedEnabled_defaultsToOff_doesNotThrow() throws {
        // `decodeIfPresent` would still THROW here — this is why the decoder uses `try?`.
        let state = try decode("{\"enabled\":\"yes\",\"lanes\":[\(lane("tempo"))]}")
        XCTAssertFalse(state.enabled)
        XCTAssertEqual(state.lanes.count, 1)
    }

    func testMissingLanes_yieldsEmpty_doesNotThrow() throws {
        let state = try decode(#"{"enabled":true}"#)
        XCTAssertTrue(state.enabled)
        XCTAssertTrue(state.lanes.isEmpty)
    }

    func testLanesWrongType_yieldsEmpty_doesNotThrow() throws {
        let state = try decode(#"{"enabled":false,"lanes":{"tempo":[]}}"#)
        XCTAssertTrue(state.lanes.isEmpty)
    }

    // MARK: - Encoding is untouched

    func testRoundTrip_encodeStaysSynthesized_andDecodesBack() throws {
        // The decoder is custom; the ENCODER is still synthesized, so the on-disk shape
        // of an existing install must be unchanged. A round-trip through both is the
        // cheapest way to pin that the CodingKeys still line up.
        let original = AutomationState(
            enabled: true,
            lanes: [AutomationLane(parameter: "tempo",
                                   points: [AutomationPoint(tick: 480, value: 0.75)])]
        )
        let data = try JSONEncoder().encode(original)
        let back = try JSONDecoder().decode(AutomationState.self, from: data)
        XCTAssertTrue(back.enabled)
        XCTAssertEqual(back.lanes.count, 1)
        XCTAssertEqual(back.lanes.first?.parameter, "tempo")
        XCTAssertEqual(back.lanes.first?.points.first?.tick, 480)
        XCTAssertEqual(back.lanes.first?.points.first?.value ?? 0, 0.75, accuracy: 1e-9)
    }
}
