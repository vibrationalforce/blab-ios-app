// AutomationTimelineLayerTests.swift
// Automation-in-track cycle 5 — automation in the TIMELINE tracks: the arrange
// document carries song-ABSOLUTE automation lanes (ticks are song position, not
// per-bar), the timeline player feeds the absolute playhead tick each step, and
// the timeline layer applies LAST — after global loop + clip lanes — so the
// arrangement's automation is authoritative while the song plays. Legacy docs
// decode with no lanes; the layer is transient (the document persists it).

import XCTest
import Foundation
@testable import Echoelmusic

// MARK: - Document model (pure)

final class TimelineAutomationCodableTests: XCTestCase {

    func testLegacyTimelineJSON_decodesWithEmptyAutomation() throws {
        // A document saved BEFORE the automation field (no key).
        let legacy = """
        {"lanes":[],"regions":[]}
        """.data(using: .utf8) ?? Data()
        let doc = try JSONDecoder().decode(TimelineDocument.self, from: legacy)
        XCTAssertTrue(doc.automation.isEmpty, "legacy timelines must load lossless with no lanes")
    }

    func testTimelineAutomation_roundTripsThroughJSON() throws {
        var lane = AutomationLane(parameter: "masterLevel")
        lane.addPoint(tick: 0, value: 0.3)
        lane.addPoint(tick: TimelineTime.ticksPerBar * 3, value: 0.9)   // song-absolute
        let doc = TimelineDocument(lanes: [], regions: [], automation: [lane])
        let data = try JSONEncoder().encode(doc)
        let back = try JSONDecoder().decode(TimelineDocument.self, from: data)
        XCTAssertEqual(back.automation, [lane], "timeline lanes must survive save/load verbatim")
    }
}

// MARK: - Player timeline layer (@MainActor)

@MainActor
final class AutomationPlayerTimelineLayerTests: XCTestCase {

    private func cleanPlayer() -> AutomationPlayer {
        let auto = AutomationPlayer()
        for t in AutomationTarget.allCases { auto.clear(target: t) }
        auto.setClipLanes([])
        auto.setTimelineLanes([])
        return auto
    }

    private func lane(_ parameter: String, at tick: Int, value: Double) -> AutomationLane {
        var l = AutomationLane(parameter: parameter)
        l.addPoint(tick: tick, value: value)
        return l
    }

    func testTimelineLane_readsAtSongAbsoluteTick() {
        let auto = cleanPlayer()
        // A 2-bar linear ramp on song-ABSOLUTE ticks: 0.2 at tick 0 → 0.8 at bar 2.
        // Reading at bar 1 gives the halfway value (0.5), which per-bar wrapping
        // (step*120, max ~1 bar) could never produce — proving the tick is absolute.
        var l = AutomationLane(parameter: "masterLevel")
        l.addPoint(tick: 0, value: 0.2)
        l.addPoint(tick: TimelineTime.ticksPerBar * 2, value: 0.8)
        auto.setTimelineLanes([l])
        XCTAssertEqual(auto.timelineAppliedValue(forParameter: "masterLevel", atTick: 0) ?? -1,
                       0.2, accuracy: 1e-9)
        XCTAssertEqual(auto.timelineAppliedValue(forParameter: "masterLevel",
                                                 atTick: TimelineTime.ticksPerBar) ?? -1,
                       0.5, accuracy: 1e-9, "song-absolute bar 1 = halfway up the 2-bar ramp")
        XCTAssertEqual(auto.timelineAppliedValue(forParameter: "masterLevel",
                                                 atTick: TimelineTime.ticksPerBar * 2) ?? -1,
                       0.8, accuracy: 1e-9)
        auto.setTimelineLanes([])
    }

    func testTimelineLane_winsOverGlobalAndClip() {
        let auto = cleanPlayer()
        auto.enabled = true
        auto.addPoint(target: .masterLevel, beat: 0, value: 1.0)          // global
        auto.setClipLanes([lane("masterLevel", at: 0, value: 0.5)])       // clip
        auto.setTimelineLanes([lane("masterLevel", at: 0, value: 0.2)])   // timeline
        auto.setTimelineTick(0)
        // The timeline layer is applied last, so its value is authoritative.
        XCTAssertEqual(auto.timelineAppliedValue(forParameter: "masterLevel", atTick: 0) ?? -1,
                       0.2, accuracy: 1e-9)
        auto.clear(target: .masterLevel)
        auto.setClipLanes([]); auto.setTimelineLanes([]); auto.enabled = false
    }

    func testTimelineLane_enumAliasKeyPath_keepsEnumCurve() {
        let auto = cleanPlayer()
        auto.setTimelineLanes([lane(AutomationTarget.filterCutoff.keyPath, at: 0, value: 0.5)])
        XCTAssertEqual(auto.timelineAppliedValue(forParameter: "filterCutoff", atTick: 0) ?? 0,
                       1.0, accuracy: 1e-6, "filter stays log — ×1 at 0.5")
        auto.setTimelineLanes([])
    }

    func testTimelineLanes_neverPersistIntoGlobalDoc() {
        let auto = cleanPlayer()
        auto.setTimelineLanes([lane("ddsp.osc.brightness", at: 0, value: 0.7)])
        XCTAssertFalse(auto.lanes.contains { $0.parameter == "ddsp.osc.brightness" })
        let reloaded = AutomationPlayer()
        XCTAssertTrue(reloaded.timelineLanes.isEmpty, "the document persists timeline lanes, not the player")
        auto.setTimelineLanes([])
    }

    func testApplyStep_dispatchesTimelineExtraLaneAtStoredTick() {
        let reg = EchoelParameterRegistry()
        reg.register(DDSPParameterCatalog.descriptors)
        let router = ParameterApplyRouter(registry: reg)
        var got: Float?
        router.bind("ddsp.osc.brightness") { got = $0 }

        let auto = cleanPlayer()
        auto.wire(router: router)
        auto.enabled = false   // timeline automation plays regardless of the loop switch
        auto.setTimelineLanes([lane("ddsp.osc.brightness", at: TimelineTime.ticksPerBar, value: 0.5)])
        auto.setTimelineTick(TimelineTime.ticksPerBar)   // playhead at bar 1
        auto.applyStep(0)   // uses the STORED absolute tick, not the per-bar step
        XCTAssertEqual(got ?? -1, 0.5, accuracy: 1e-6)
        auto.setTimelineLanes([])
    }

    func testSetTimelineLanes_emptyClearsLayer() {
        let auto = cleanPlayer()
        auto.setTimelineLanes([lane("masterLevel", at: 0, value: 0.3)])
        auto.setTimelineLanes([])
        XCTAssertNil(auto.timelineAppliedValue(forParameter: "masterLevel", atTick: 0))
    }
}

// MARK: - Timeline player cursor feeds the absolute tick

@MainActor
final class TimelineRegionPlayerAutomationFeedTests: XCTestCase {

    func testCursorTickIsSongAbsolute() {
        // The pure cursor already tracks song-absolute ticks; automation rides it.
        var cursor = TimelinePlaybackCursor()
        _ = cursor.advance(step: 0)
        // Advance a full bar: steps 1…15 then wrap 0 = bar 1.
        for s in 1...15 { _ = cursor.advance(step: s) }
        let barWrap = cursor.advance(step: 0)
        XCTAssertEqual(barWrap, TimelineTime.ticksPerBar,
                       "after one bar the absolute tick is one bar of content ticks")
    }
}
