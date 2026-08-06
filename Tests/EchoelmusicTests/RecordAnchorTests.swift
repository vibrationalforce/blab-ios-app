// RecordAnchorTests.swift
// Echoel — B17. Pure tests for the recording time-map + capture plan.

import XCTest
@testable import Echoelmusic

final class RecordAnchorTests: XCTestCase {

    // MARK: - tick(forSampleTime:)

    func testTick_NFramesAtRealSampleRate_mapsToStartTickPlusSecondsToTicks() {
        // 48 kHz, 120 BPM. ticksPerQuarter = 480 → ticks/sec = 480 * 120 / 60 = 960.
        let anchor = RecordAnchor(startSampleTime: 1_000, startTick: 500,
                                  sampleRate: 48_000, bpm: 120)

        // Advance exactly 1 second (48000 frames past the anchor's start sample).
        let oneSecondLater: Int64 = 1_000 + 48_000
        // 1 second at 960 ticks/sec = 960 ticks past startTick.
        XCTAssertEqual(anchor.tick(forSampleTime: oneSecondLater), 500 + 960)

        // Sanity: seconds(forSampleTime:) is the underlying 1.0 s.
        XCTAssertEqual(anchor.seconds(forSampleTime: oneSecondLater), 1.0, accuracy: 1e-9)
    }

    func testTick_44100SampleRate_halfSecond_roundsToNearestTick() {
        // 44.1 kHz, 90 BPM → ticks/sec = 480 * 90 / 60 = 720. Half a second = 22050 frames.
        let anchor = RecordAnchor(startSampleTime: 0, startTick: 0,
                                  sampleRate: 44_100, bpm: 90)
        let halfSecond: Int64 = 22_050
        XCTAssertEqual(anchor.tick(forSampleTime: halfSecond), 360)  // 720 * 0.5
    }

    func testTick_atAnchorSampleTime_isStartTick() {
        let anchor = RecordAnchor(startSampleTime: 5_000, startTick: 1_920,
                                  sampleRate: 48_000, bpm: 128)
        XCTAssertEqual(anchor.tick(forSampleTime: 5_000), 1_920)
    }

    // MARK: - tick(afterSeconds:)

    func testTickAfterSeconds_matchesTimelineTimeInverse() {
        // At 120 BPM one quarter (480 ticks) = 0.5 s. So 0.5 s → +480 ticks.
        let anchor = RecordAnchor(startSampleTime: 0, startTick: 0, sampleRate: 48_000, bpm: 120)
        XCTAssertEqual(anchor.tick(afterSeconds: 0.5), 480)

        // Cross-check against TimelineTime.seconds(fromTicks:) round-trip.
        let secs = TimelineTime.seconds(fromTicks: 480, bpm: 120)
        XCTAssertEqual(anchor.tick(afterSeconds: secs), 480)
    }

    // MARK: - Guards / edge cases

    func testTick_zeroSampleRate_collapsesToStartTick() {
        let anchor = RecordAnchor(startSampleTime: 0, startTick: 77, sampleRate: 0, bpm: 120)
        XCTAssertEqual(anchor.tick(forSampleTime: 99_999), 77)
        XCTAssertEqual(anchor.seconds(forSampleTime: 99_999), 0)
    }

    func testTick_zeroOrNegativeBpm_collapsesToStartTick() {
        let zeroBpm = RecordAnchor(startSampleTime: 0, startTick: 42, sampleRate: 48_000, bpm: 0)
        XCTAssertEqual(zeroBpm.tick(forSampleTime: 48_000), 42)
        XCTAssertEqual(zeroBpm.tick(afterSeconds: 5), 42)

        let negBpm = RecordAnchor(startSampleTime: 0, startTick: 42, sampleRate: 48_000, bpm: -120)
        XCTAssertEqual(negBpm.tick(afterSeconds: 1), 42)
    }

    func testSeconds_beforeAnchor_isNegative() {
        let anchor = RecordAnchor(startSampleTime: 48_000, startTick: 0, sampleRate: 48_000, bpm: 120)
        XCTAssertEqual(anchor.seconds(forSampleTime: 0), -1.0, accuracy: 1e-9)
    }

    // MARK: - RecordPlan.targets

    func testTargets_resolvesArmedRecordableLanesToExpectedSources() {
        let bioID = UUID()
        let midiID = UUID()
        let audioID = UUID()
        let visualID = UUID()
        let disarmedID = UUID()

        let lanes = [
            TimelineLane(id: bioID, name: "Bio", kind: .midi, isBio: true, isArmed: true),
            TimelineLane(id: midiID, name: "Synth", kind: .midi,
                         builtinInstrument: .polySynth, isArmed: true),
            TimelineLane(id: audioID, name: "Mic", kind: .audio, isArmed: true),
            // Armed but a pure visual lane → .none → not recordable → excluded.
            TimelineLane(id: visualID, name: "Vis", kind: .visual, isArmed: true),
            // Recordable kind but NOT armed → excluded.
            TimelineLane(id: disarmedID, name: "Off", kind: .audio, isArmed: false),
        ]
        let doc = TimelineDocument(lanes: lanes)

        let targets = RecordPlan.targets(in: doc)
        XCTAssertEqual(targets.count, 2)
        // Order follows document lane order.
        XCTAssertEqual(targets[0].laneID, bioID)
        XCTAssertEqual(targets[0].source, .bio)
        XCTAssertEqual(targets[1].laneID, midiID)
        XCTAssertEqual(targets[1].source, .midiInput)

        // CLIP-2 (honest planner): the armed MIC lane is NOT a target —
        // TakeRecorder cannot capture audio yet (task #13), and counting it let
        // Record run a take that silently recorded nothing (data loss).
        XCTAssertFalse(targets.contains { $0.laneID == audioID })
        // The visual + disarmed lanes are absent.
        XCTAssertFalse(targets.contains { $0.laneID == visualID })
        XCTAssertFalse(targets.contains { $0.laneID == disarmedID })
    }

    func testCaptureImplemented_truthTable_matchesTakeRecorder() {
        // The one law behind CLIP-2: sources TakeRecorder actually captures today.
        // If a new recorder lands (task #13), flip the source here AND in
        // TakeRecorder.begin — this table is the honest promise the arm UI makes.
        XCTAssertTrue(RecordSource.midiInput.captureImplemented)
        XCTAssertTrue(RecordSource.bio.captureImplemented)
        XCTAssertFalse(RecordSource.audioInput.captureImplemented)
        XCTAssertFalse(RecordSource.videoCapture.captureImplemented)
        XCTAssertFalse(RecordSource.none.captureImplemented)
    }

    func testTargets_onlyUncapturableArmed_isEmpty_soRecordStaysDisabled() {
        // An armed mic/video lane alone must NOT enable the global Record button
        // (hasArmedTarget reads targets) — pre-fix it lit red and lost the take.
        let lanes = [
            TimelineLane(name: "Mic", kind: .audio, isArmed: true),
            TimelineLane(name: "Cam", kind: .video, isArmed: true),
        ]
        XCTAssertTrue(RecordPlan.targets(in: TimelineDocument(lanes: lanes)).isEmpty)
    }

    func testTargets_emptyDocument_isEmpty() {
        XCTAssertTrue(RecordPlan.targets(in: TimelineDocument()).isEmpty)
    }

    func testTargets_nothingArmed_isEmpty() {
        let lanes = [
            TimelineLane(name: "A", kind: .midi, isArmed: false),
            TimelineLane(name: "B", kind: .audio, isArmed: false),
        ]
        XCTAssertTrue(RecordPlan.targets(in: TimelineDocument(lanes: lanes)).isEmpty)
    }

    // MARK: - armedAudioLaneIDs (task #13, PLAN_AUDIO_LANE_RECORDING_2026-07-21.md S1)

    func testArmedAudioLaneIDs_returnsOnlyArmedAudioLanes_inDocumentOrder() {
        let audioID1 = UUID()
        let audioID2 = UUID()
        let lanes = [
            TimelineLane(id: audioID1, name: "Mic 1", kind: .audio, isArmed: true),
            TimelineLane(name: "Synth", kind: .midi, builtinInstrument: .polySynth, isArmed: true),
            TimelineLane(name: "Off Mic", kind: .audio, isArmed: false),
            TimelineLane(id: audioID2, name: "Mic 2", kind: .audio, isArmed: true),
        ]
        let ids = RecordPlan.armedAudioLaneIDs(in: TimelineDocument(lanes: lanes))
        XCTAssertEqual(ids, [audioID1, audioID2])
    }

    func testArmedAudioLaneIDs_noArmedAudioLane_isEmpty() {
        let lanes = [
            TimelineLane(name: "Synth", kind: .midi, builtinInstrument: .polySynth, isArmed: true),
            TimelineLane(name: "Off Mic", kind: .audio, isArmed: false),
        ]
        XCTAssertTrue(RecordPlan.armedAudioLaneIDs(in: TimelineDocument(lanes: lanes)).isEmpty)
    }

    func testArmedAudioLaneIDs_doesNotChangeTargets_captureImplementedGateStaysHonest() {
        // The new helper is purely additive — it must never make .audioInput
        // count as a `targets()` result (that promise is what keeps the Record
        // button honest until S3's device-verified flip).
        let audioID = UUID()
        let lanes = [TimelineLane(id: audioID, name: "Mic", kind: .audio, isArmed: true)]
        let doc = TimelineDocument(lanes: lanes)
        XCTAssertEqual(RecordPlan.armedAudioLaneIDs(in: doc), [audioID])
        XCTAssertTrue(RecordPlan.targets(in: doc).isEmpty)
    }

    // MARK: - bioNormalized

    func testBioNormalized_midRange_isBetweenZeroAndOne() {
        let v = bioNormalized(bpm: 85, breathRate: 15)
        XCTAssertGreaterThan(v, 0)
        XCTAssertLessThan(v, 1)
    }

    func testBioNormalized_clampsAboveRange() {
        // Heart far above its top → 1. NOTE (#433): 200 breaths/min is outside
        // `BioSampleFrame.plausibleBreathRate`, so it is now treated as "no breath reading" and
        // the heart term stands alone — same answer, different reason than before.
        XCTAssertEqual(bioNormalized(bpm: 500, breathRate: 200), 1.0, accuracy: 1e-6)
    }

    func testBioNormalized_clampsBelowRange() {
        // Heart below its floor → 0. Both breath values here are outside the plausible set, so
        // there is no breath term to blend (#433) — a missing reading is not "very calm".
        XCTAssertEqual(bioNormalized(bpm: 0, breathRate: 0), 0.0, accuracy: 1e-6)
        XCTAssertEqual(bioNormalized(bpm: -40, breathRate: -5), 0.0, accuracy: 1e-6)
    }

    func testBioNormalized_atFloors_isZero() {
        // ⛔ THIS ASSERTED `(50, 6) == 0` UNTIL #433, AND THAT ZERO WAS THE DEFECT: 6/min is
        // `BreathPacer.defaultRate`, the rate Echoel's own guide paces by default, and it sat
        // exactly on the old breath floor. The floor is now 3.0 (the low bound of the plausible
        // set), so the paced target carries travel. The floors that still read 0 are the real
        // ones: heart at 50, breath at 3.
        XCTAssertEqual(bioNormalized(bpm: 50, breathRate: 3), 0.0, accuracy: 1e-6)
        XCTAssertEqual(bioNormalized(bpm: 50, breathRate: 6), 0.0714285, accuracy: 1e-5)
    }

    func testBioNormalized_atTops_isOne() {
        XCTAssertEqual(bioNormalized(bpm: 120, breathRate: 24), 1.0, accuracy: 1e-6)
    }

    func testBioNormalized_nanIsSafe() {
        XCTAssertEqual(bioNormalized(bpm: .nan, breathRate: .nan), 0.0, accuracy: 1e-6)
    }
}
