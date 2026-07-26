// RecordControllerAudioHookTests.swift
// Echoel — task #13 (PLAN_AUDIO_LANE_RECORDING_2026-07-21.md, S1): the new,
// flag-gated audio-capture wiring in RecordController. Exercises the REAL
// clock/store flow (Transport.tick/stop → RecordController → TakeRecorder →
// ClipStore/TimelineStore) against a spy `AudioTakeRecording` — no AVFoundation,
// no device, no simulator.

import XCTest
@testable import Echoelmusic

@MainActor
private final class SpyAudioRecorder: AudioTakeRecording {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    /// What `stop()` hands back — nil simulates "never actually captured"
    /// (e.g. `startRecording()` silently failed on the real recorder).
    var result: (url: URL, seconds: Double)?

    func start() { startCount += 1 }
    func stop() async -> (url: URL, seconds: Double)? {
        stopCount += 1
        return result
    }
}

final class RecordControllerAudioHookTests: XCTestCase {

    // `@MainActor` on the rig and on every test: Transport, TimelineStore, ClipStore,
    // EngineBus and RecordController are ALL `@MainActor @Observable` (they are the
    // control plane), so constructing or touching them from a nonisolated test body is
    // a hard Swift 6 error — not a warning. Same idiom as TimelineStoreDebounceTests.
    @MainActor
    private func makeRig() -> (transport: Transport, timeline: TimelineStore,
                               clips: ClipStore, bus: EngineBus, controller: RecordController) {
        (Transport(), TimelineStore(), ClipStore(), EngineBus(), RecordController())
    }

    @MainActor
    func testArmedAudioLanePlusMidi_withAudioRecorderWired_capturesBothOnStop() async {
        let (transport, timeline, clips, bus, controller) = makeRig()

        timeline.addLane(kind: .audio, name: "Mic \(UUID().uuidString)")
        guard let audioLaneID = timeline.document.lanes.last?.id else {
            return XCTFail("addLane did not append a lane")
        }
        timeline.toggleArm(id: audioLaneID)

        timeline.addLane(kind: .midi, name: "Synth \(UUID().uuidString)")
        guard let midiLaneID = timeline.document.lanes.last?.id else {
            return XCTFail("addLane did not append a lane")
        }
        timeline.toggleArm(id: midiLaneID)

        let spy = SpyAudioRecorder()
        let fileURL = URL(fileURLWithPath: "/tmp/echoel-test-\(UUID().uuidString).caf")
        spy.result = (fileURL, 1.5)

        controller.wire(transport: transport, timeline: timeline, clips: clips, bus: bus,
                        audioRecorder: spy)

        // The MIDI lane alone already makes the plan non-empty (RecordPlan.targets
        // excludes .audioInput by design), so the Record button's honest gate is
        // untouched by this feature.
        XCTAssertTrue(controller.hasArmedTarget())
        controller.arm()

        transport.play()
        transport.tick(step: 0)
        XCTAssertEqual(spy.startCount, 1, "an armed audio lane must start the injected recorder")

        // A note during the take so the MIDI lane's take is non-empty too.
        controller.recordNoteOn(pitch: 60, velocity: 0.8)
        transport.tick(step: 1)
        controller.recordNoteOff(pitch: 60)

        transport.stop()
        await controller.pendingFinish?.value

        XCTAssertEqual(spy.stopCount, 1)
        let audioRegion = timeline.document.regions.first { $0.laneID == audioLaneID }
        XCTAssertNotNil(audioRegion, "the audio lane should have gained a region from the captured file")
        if let clipID = audioRegion?.clipID {
            let clip = clips.slots.compactMap { $0 }.first { $0.id == clipID }
            XCTAssertEqual(clip?.kind, .audio)
        }
        let midiRegion = timeline.document.regions.first { $0.laneID == midiLaneID }
        XCTAssertNotNil(midiRegion, "the armed MIDI lane must still capture its note, unaffected by the audio hook")
    }

    @MainActor
    func testAudioRecorderReturnsNil_noRegionAddedForThatLane_midiStillCommits() async {
        let (transport, timeline, clips, bus, controller) = makeRig()

        timeline.addLane(kind: .audio, name: "Mic \(UUID().uuidString)")
        guard let audioLaneID = timeline.document.lanes.last?.id else {
            return XCTFail("addLane did not append a lane")
        }
        timeline.toggleArm(id: audioLaneID)
        timeline.addLane(kind: .midi, name: "Synth \(UUID().uuidString)")
        guard let midiLaneID = timeline.document.lanes.last?.id else {
            return XCTFail("addLane did not append a lane")
        }
        timeline.toggleArm(id: midiLaneID)

        let spy = SpyAudioRecorder()
        spy.result = nil   // simulates a silently-failed real recorder

        controller.wire(transport: transport, timeline: timeline, clips: clips, bus: bus,
                        audioRecorder: spy)
        controller.arm()
        transport.play()
        transport.tick(step: 0)
        controller.recordNoteOn(pitch: 64, velocity: 0.5)
        transport.tick(step: 1)
        controller.recordNoteOff(pitch: 64)
        transport.stop()
        await controller.pendingFinish?.value

        XCTAssertEqual(spy.stopCount, 1)
        XCTAssertNil(timeline.document.regions.first { $0.laneID == audioLaneID },
                     "a nil capture result must drop the take honestly, not fabricate a region")
        XCTAssertNotNil(timeline.document.regions.first { $0.laneID == midiLaneID },
                        "the MIDI take must still commit even when the audio leg produced nothing")
    }

    @MainActor
    func testOverlappingStop_whileAudioFinishPending_doesNotDropTheTake() async {
        // Transport.stop() has no "already stopped" guard, and a second, unrelated
        // stop subscriber (e.g. the app's route-loss handler) can re-invoke it
        // while the first stop's async audio finish is still in flight. Without
        // the re-entrancy guard in `commitOnStop`, that second call would see
        // `recorder.isRecording` still true and `recordingAudioLaneID` already
        // nil, take the synchronous branch, and finish the take out from under
        // the pending Task — silently dropping the mic take.
        let (transport, timeline, clips, bus, controller) = makeRig()

        timeline.addLane(kind: .audio, name: "Mic \(UUID().uuidString)")
        guard let audioLaneID = timeline.document.lanes.last?.id else {
            return XCTFail("addLane did not append a lane")
        }
        timeline.toggleArm(id: audioLaneID)

        let spy = SpyAudioRecorder()
        spy.result = (URL(fileURLWithPath: "/tmp/echoel-test-\(UUID().uuidString).caf"), 2.0)

        controller.wire(transport: transport, timeline: timeline, clips: clips, bus: bus,
                        audioRecorder: spy)
        controller.arm()
        transport.play()
        transport.tick(step: 0)
        XCTAssertEqual(spy.startCount, 1)

        // First stop schedules `pendingFinish` (the Task body hasn't run yet —
        // Task bodies only start on the next actor hop). A second, overlapping
        // stop call must be ignored rather than finishing the take early.
        transport.stop()
        let firstPending = controller.pendingFinish
        XCTAssertNotNil(firstPending, "the audio leg must defer commit into pendingFinish")
        // A second, overlapping stop must be a no-op (the re-entrancy guard),
        // not start a second audio-stop or finish the take synchronously.
        transport.stop()

        await firstPending?.value

        XCTAssertEqual(spy.stopCount, 1, "the recorder must only be stopped once across both stop calls")
        XCTAssertNotNil(timeline.document.regions.first { $0.laneID == audioLaneID },
                        "the audio take must still land — an overlapping stop must not drop it")
    }

    @MainActor
    func testNoAudioRecorderWired_behavesExactlyAsBeforeTheHook() async {
        // The default `audioRecorder: nil` path — proves the feature is inert
        // (Release-shipped behavior) when the app doesn't inject a recorder,
        // regardless of an armed audio lane.
        let (transport, timeline, clips, bus, controller) = makeRig()

        timeline.addLane(kind: .audio, name: "Mic \(UUID().uuidString)")
        guard let audioLaneID = timeline.document.lanes.last?.id else {
            return XCTFail("addLane did not append a lane")
        }
        timeline.toggleArm(id: audioLaneID)
        timeline.addLane(kind: .midi, name: "Synth \(UUID().uuidString)")
        guard let midiLaneID = timeline.document.lanes.last?.id else {
            return XCTFail("addLane did not append a lane")
        }
        timeline.toggleArm(id: midiLaneID)

        controller.wire(transport: transport, timeline: timeline, clips: clips, bus: bus)
        controller.arm()
        transport.play()
        transport.tick(step: 0)
        controller.recordNoteOn(pitch: 67, velocity: 0.5)
        transport.tick(step: 1)
        controller.recordNoteOff(pitch: 67)
        transport.stop()

        XCTAssertNil(controller.pendingFinish, "no audio leg ⇒ commitOnStop must stay fully synchronous")
        XCTAssertNil(timeline.document.regions.first { $0.laneID == audioLaneID })
        XCTAssertNotNil(timeline.document.regions.first { $0.laneID == midiLaneID })
    }
}
