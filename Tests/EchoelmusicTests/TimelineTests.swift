// TimelineTests.swift
// Echoel — locks the Arrange-timeline foundation (Stage 1): the 480-PPQ time
// model, the snap engine (snap-to-beat AND stepless), and the document's
// Codable/query behaviour. Pure — runs on Linux CI.

import XCTest
@testable import Echoelmusic

final class TimelineTests: XCTestCase {

    // MARK: - Time constants (the one shared resolution)

    func testTimeConstants_matchNotePPQ() {
        XCTAssertEqual(TimelineTime.ticksPerQuarter, Note.ticksPerQuarter)   // 480
        XCTAssertEqual(TimelineTime.ticksPerBar, 1920)
        XCTAssertEqual(TimelineTime.ticksPerTransportStep, Note.ticksPerStep) // 120
    }

    func testTransportStepConversion() {
        // Transport absoluteStep = bar*16 + step; bar 2, step 4 → (2*16+4)*120.
        XCTAssertEqual(TimelineTime.tick(fromAbsoluteStep: 0), 0)
        XCTAssertEqual(TimelineTime.tick(fromAbsoluteStep: 36), 4320)
    }

    func testSecondsConversion() {
        // 120 BPM: one quarter (480 ticks) = 0.5 s; one bar = 2 s.
        XCTAssertEqual(TimelineTime.seconds(fromTicks: 480, bpm: 120), 0.5, accuracy: 1e-9)
        XCTAssertEqual(TimelineTime.seconds(fromTicks: 1920, bpm: 120), 2.0, accuracy: 1e-9)
        // Guard: nonsense tempo never divides by zero.
        XCTAssertEqual(TimelineTime.seconds(fromTicks: 480, bpm: 0), 0)
    }

    // MARK: - Snap engine

    func testSnap_toBeat_roundsToNearestGridLine() {
        XCTAssertEqual(TimelineSnap.snap(0, to: .beat), 0)
        XCTAssertEqual(TimelineSnap.snap(239, to: .beat), 0)      // below half-grid → down
        XCTAssertEqual(TimelineSnap.snap(241, to: .beat), 480)    // above half-grid → up
        XCTAssertEqual(TimelineSnap.snap(480, to: .beat), 480)    // on-grid unchanged
    }

    func testSnap_off_isStepless_identity() {
        // "aber auch stufenlose Verschiebung" — .off must never quantize.
        for tick in [0, 1, 7, 119, 481, 1919, 12345] {
            XCTAssertEqual(TimelineSnap.snap(tick, to: .off), tick)
        }
    }

    func testSnap_neverNegative() {
        XCTAssertEqual(TimelineSnap.snap(-500, to: .beat), 0)
        XCTAssertEqual(TimelineSnap.snap(-3, to: .off), 0)
    }

    func testSnap_allResolutions_produceOnGridResults() {
        for res in SnapResolution.allCases where res != .off {
            guard let grid = res.ticks else { return XCTFail("grid nil for \(res)") }
            let snapped = TimelineSnap.snap(1000, to: res)
            XCTAssertEqual(snapped % grid, 0, "\(res) must land on its grid")
        }
    }

    func testMagneticSnap_pullsOnlyWithinMagnetRange() {
        // 30 ticks from the beat line, magnet 40 → pulled onto the line.
        XCTAssertEqual(TimelineSnap.magneticSnap(450, to: .beat, magnetTicks: 40), 480)
        // 30 ticks away but magnet only 20 → stays free (stepless feel).
        XCTAssertEqual(TimelineSnap.magneticSnap(450, to: .beat, magnetTicks: 20), 450)
        // Off = always free regardless of magnet.
        XCTAssertEqual(TimelineSnap.magneticSnap(450, to: .off, magnetTicks: 1000), 450)
    }

    // MARK: - Regions + document

    func testRegion_clampsAndEndTick() {
        let lane = UUID(), clip = UUID()
        let r = TimelineRegion(laneID: lane, clipID: clip,
                               startTick: -10, lengthTicks: 0, contentOffsetSeconds: -1)
        XCTAssertEqual(r.startTick, 0)          // no negative start
        XCTAssertEqual(r.lengthTicks, 1)        // never zero-length
        XCTAssertEqual(r.contentOffsetSeconds, 0)
        XCTAssertEqual(r.endTick, 1)
    }

    func testDocument_laneQuery_sortsByStart() {
        let lane = TimelineLane(name: "MIDI 1", kind: .midi)
        let other = TimelineLane(name: "Audio 1", kind: .audio)
        let clip = UUID()
        let a = TimelineRegion(laneID: lane.id, clipID: clip, startTick: 1920, lengthTicks: 480)
        let b = TimelineRegion(laneID: lane.id, clipID: clip, startTick: 0, lengthTicks: 480)
        let c = TimelineRegion(laneID: other.id, clipID: clip, startTick: 960, lengthTicks: 480)
        let doc = TimelineDocument(lanes: [lane, other], regions: [a, b, c])

        XCTAssertEqual(doc.regions(in: lane.id).map(\.startTick), [0, 1920])
        XCTAssertEqual(doc.endTick, 2400)       // a ends at 1920+480
    }

    func testDocument_codableRoundTrip() throws {
        let lane = TimelineLane(name: "Bio", kind: .visual, isBio: true)
        let region = TimelineRegion(laneID: lane.id, clipID: UUID(),
                                    startTick: 333, lengthTicks: 777,
                                    contentOffsetSeconds: 1.25)
        let doc = TimelineDocument(lanes: [lane], regions: [region])
        let data = try JSONEncoder().encode(doc)
        let back = try JSONDecoder().decode(TimelineDocument.self, from: data)
        XCTAssertEqual(back, doc)               // stepless positions survive exactly
    }

    // MARK: - Legacy-song migration (Stage 1b)

    func testMigration_sectionsBecomeBarAlignedRegionsOnMIDILane() {
        let clipA = UUID(), clipB = UUID()
        let sections = [
            ArrangementSection(clipID: clipA, name: "Intro", colorIndex: 0, lengthBars: 2),
            ArrangementSection(clipID: nil,   name: "Gap",   colorIndex: 0, lengthBars: 1),
            ArrangementSection(clipID: clipB, name: "Drop",  colorIndex: 1, lengthBars: 4),
        ]
        let doc = TimelineStore.migrate(sections: sections)

        // Lanes: one MIDI + one empty Audio (multi-lane shape from day one).
        XCTAssertEqual(doc.lanes.map(\.kind), [.midi, .audio])
        let midiLane = doc.lanes[0]

        // Regions: gap creates none but advances the cursor; all bar-aligned.
        let regions = doc.regions(in: midiLane.id)
        XCTAssertEqual(regions.count, 2)
        XCTAssertEqual(regions[0].clipID, clipA)
        XCTAssertEqual(regions[0].startTick, 0)
        XCTAssertEqual(regions[0].lengthTicks, 2 * TimelineTime.ticksPerBar)
        XCTAssertEqual(regions[1].clipID, clipB)
        // Drop starts after Intro (2 bars) + Gap (1 bar) = bar 3.
        XCTAssertEqual(regions[1].startTick, 3 * TimelineTime.ticksPerBar)
        XCTAssertEqual(regions[1].lengthTicks, 4 * TimelineTime.ticksPerBar)
        XCTAssertEqual(doc.regions(in: doc.lanes[1].id), [])
    }

    func testMigration_emptySong_seedsDefaultLanesOnly() {
        let doc = TimelineStore.migrate(sections: [])
        XCTAssertEqual(doc.lanes.count, 2)
        XCTAssertTrue(doc.regions.isEmpty)
        XCTAssertEqual(doc.endTick, 0)
    }

    func testSnapResolution_rawValues_stableForPersistence() {
        XCTAssertEqual(SnapResolution.bar.rawValue, "bar")
        XCTAssertEqual(SnapResolution.sixteenth.rawValue, "sixteenth")
        XCTAssertEqual(SnapResolution.off.rawValue, "off")
    }

    // MARK: - Lane mixer math (K2a)

    func testEffectiveGain_levelMuteAndClamp() {
        var doc = TimelineDocument(lanes: [
            TimelineLane(name: "MIDI 1", kind: .midi),
            TimelineLane(name: "Audio 1", kind: .audio, level: 0.5),
        ])
        XCTAssertEqual(doc.effectiveGain(for: doc.lanes[0].id), 1)
        XCTAssertEqual(doc.effectiveGain(for: doc.lanes[1].id), 0.5)
        doc.lanes[0].isMuted = true
        XCTAssertEqual(doc.effectiveGain(for: doc.lanes[0].id), 0)
        // Level clamps into 0…2 even if a stored document carries junk.
        doc.lanes[1].level = 9
        XCTAssertEqual(doc.effectiveGain(for: doc.lanes[1].id), 2)
        // Unknown lane → silent, never a crash.
        XCTAssertEqual(doc.effectiveGain(for: UUID()), 0)
    }

    func testEffectiveGain_soloSilencesOthers_muteWinsOverOwnSolo() {
        var doc = TimelineDocument(lanes: [
            TimelineLane(name: "A", kind: .midi),
            TimelineLane(name: "B", kind: .audio, level: 0.8, isSoloed: true),
        ])
        XCTAssertEqual(doc.effectiveGain(for: doc.lanes[0].id), 0)     // not soloed
        XCTAssertEqual(doc.effectiveGain(for: doc.lanes[1].id), 0.8)   // the solo
        // Mute beats the lane's own solo.
        doc.lanes[1].isMuted = true
        XCTAssertEqual(doc.effectiveGain(for: doc.lanes[1].id), 0)
    }

    func testRollSlotGain_firstNonBioMIDILaneOwnsTheRoll() {
        var doc = TimelineDocument(lanes: [
            TimelineLane(name: "Bio", kind: .midi, isBio: true),
            TimelineLane(name: "MIDI 1", kind: .midi, level: 0.7),
            TimelineLane(name: "MIDI 2", kind: .midi, level: 0.2),
        ])
        XCTAssertEqual(doc.rollSlotGain, 0.7)                    // bio lane skipped
        doc.lanes[1].isMuted = true
        XCTAssertEqual(doc.rollSlotGain, 0)                      // mute reaches the roll
        // No MIDI lane at all → unity (roll not represented on the timeline).
        let audioOnly = TimelineDocument(lanes: [TimelineLane(name: "A", kind: .audio)])
        XCTAssertEqual(audioOnly.rollSlotGain, 1)
    }

    func testLaneDecode_preK2aDocumentWithoutMixKeys_defaultsToUnity() throws {
        // A lane persisted BEFORE the mixer strip existed (no level/mute/solo keys)
        // must decode with unity defaults — nobody's timeline may fail to load.
        let legacyJSON = """
        {"id":"\(UUID().uuidString)","name":"MIDI 1","kind":"midi","isBio":false}
        """
        let lane = try JSONDecoder().decode(TimelineLane.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(lane.level, 1)
        XCTAssertFalse(lane.isMuted)
        XCTAssertFalse(lane.isSoloed)
    }

    func testLaneMixState_roundTripsThroughCodable() throws {
        let lane = TimelineLane(name: "A", kind: .audio, level: 1.25,
                                isMuted: true, isSoloed: true)
        let data = try JSONEncoder().encode(lane)
        let back = try JSONDecoder().decode(TimelineLane.self, from: data)
        XCTAssertEqual(back, lane)
    }
}
