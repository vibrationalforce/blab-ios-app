// TimelineRegionPlayerTests.swift
// Echoel — the PURE parts of timeline playback (reorg P3): the absolute-position
// cursor and the whole-bar loop-length math. The audio side (loadClip) mirrors the
// proven ArrangementPlayer and is verified on device; here we lock the position
// contract the scheduler rides on.

import XCTest
@testable import Echoelmusic

final class TimelineRegionPlayerTests: XCTestCase {

    // MARK: - TimelinePlaybackCursor (absolute position from within-bar steps)

    func testCursor_firstBar_ticksPerStep() {
        var c = TimelinePlaybackCursor()
        for s in 0..<16 {
            XCTAssertEqual(c.advance(step: s), s * 120, "step \(s) → tick \(s*120)")
        }
    }

    func testCursor_barWrap_advancesToNextBar() {
        var c = TimelinePlaybackCursor()
        for s in 0..<16 { _ = c.advance(step: s) }   // through bar 0 (…→1800)
        XCTAssertEqual(c.advance(step: 0), 1920, "15→0 wrap enters bar 1 (tick 1920)")
        XCTAssertEqual(c.advance(step: 1), 2040)
    }

    func testCursor_multipleBars() {
        var c = TimelinePlaybackCursor()
        for _ in 0..<3 {                              // three full bars
            for s in 0..<16 { _ = c.advance(step: s) }
        }
        XCTAssertEqual(c.advance(step: 0), 5760, "start of bar 3 = 3*1920")
    }

    func testCursor_noSpuriousWrapOnRepeatedStepZero() {
        var c = TimelinePlaybackCursor()
        XCTAssertEqual(c.advance(step: 0), 0, "first step 0 does not count as a wrap")
        XCTAssertEqual(c.advance(step: 0), 0, "a repeated step 0 (no 15→0) does not advance the bar")
    }

    func testCursor_clampsOutOfRangeSteps() {
        var c = TimelinePlaybackCursor()
        XCTAssertEqual(c.advance(step: -5), 0, "negative clamps to 0")
        XCTAssertEqual(c.advance(step: 99), 15 * 120, "over-15 clamps to 15")
    }

    // MARK: - CLIP-5: cursor seeding (play from the playhead / relocate)

    func testCursor_seededStartBar_landsInThatBar() {
        var c = TimelinePlaybackCursor(startBar: 2)
        XCTAssertEqual(c.advance(step: 0), 2 * 1920, "seeded cursor starts at bar 2's downbeat")
        XCTAssertEqual(c.advance(step: 5), 2 * 1920 + 5 * 120)
    }

    func testCursor_seededMidPhase_firstStepIsNotAWrap() {
        // A relocate can land while the pattern is mid-bar — the first advance
        // must adopt that phase inside the seeded bar, never count a wrap.
        var c = TimelinePlaybackCursor(startBar: 3)
        XCTAssertEqual(c.advance(step: 9), 3 * 1920 + 9 * 120)
        // …and the NEXT real 15→0 wrap advances to bar 4 as usual.
        _ = c.advance(step: 15)
        XCTAssertEqual(c.advance(step: 0), 4 * 1920)
    }

    func testCursor_seededNegativeBar_clampsToZero() {
        var c = TimelinePlaybackCursor(startBar: -3)
        XCTAssertEqual(c.advance(step: 0), 0)
    }

    // MARK: - CLIP-5: barStartTick (pure locate-target math)

    func testBarStartTick_floorsToBar() {
        XCTAssertEqual(TimelineRegionPlayer.barStartTick(for: 1920 + 500, loopTicks: 7680), 1920)
        XCTAssertEqual(TimelineRegionPlayer.barStartTick(for: 0, loopTicks: 7680), 0)
    }

    func testBarStartTick_beyondEndFoldsIntoSong() {
        XCTAssertEqual(TimelineRegionPlayer.barStartTick(for: 7680, loopTicks: 7680), 0,
                       "the tick AT the loop end is the top")
        XCTAssertEqual(TimelineRegionPlayer.barStartTick(for: 7680 + 1920, loopTicks: 7680), 1920)
    }

    func testBarStartTick_zeroLoop_isZero() {
        XCTAssertEqual(TimelineRegionPlayer.barStartTick(for: 5000, loopTicks: 0), 0)
    }

    // MARK: - CLIP-5 review HIGH: the phase-consistent relocate anchor

    func testRelocateAnchorTick_addsThePatternPhase() {
        // The pattern's 16-step phase keeps running through a jump — the anchor
        // must land where the NEXT transport step lands, or audio lags MIDI.
        XCTAssertEqual(TimelineRegionPlayer.relocateAnchorTick(targetBarTick: 3840, nextPatternStep: 0), 3840)
        XCTAssertEqual(TimelineRegionPlayer.relocateAnchorTick(targetBarTick: 3840, nextPatternStep: 7), 3840 + 7 * 120)
        XCTAssertEqual(TimelineRegionPlayer.relocateAnchorTick(targetBarTick: 3840, nextPatternStep: 15), 3840 + 15 * 120)
    }

    func testRelocateAnchorTick_clampsOutOfRangePhase() {
        XCTAssertEqual(TimelineRegionPlayer.relocateAnchorTick(targetBarTick: 1920, nextPatternStep: -3), 1920)
        XCTAssertEqual(TimelineRegionPlayer.relocateAnchorTick(targetBarTick: 1920, nextPatternStep: 99), 1920 + 15 * 120)
    }

    // MARK: - loopTicks (whole-bar song length)

    private func doc(endTick: Int) -> TimelineDocument {
        let lane = TimelineLane(name: "MIDI", kind: .midi)
        // A single region [0, endTick) on the lane sets the document's endTick.
        let r = TimelineRegion(laneID: lane.id, clipID: UUID(), startTick: 0, lengthTicks: max(1, endTick))
        return TimelineDocument(lanes: [lane], regions: [r])
    }

    func testLoopTicks_exactBar_staysOneBar() {
        XCTAssertEqual(TimelineRegionPlayer.loopTicks(for: doc(endTick: 1920)), 1920)
    }

    func testLoopTicks_roundsUpToWholeBars() {
        XCTAssertEqual(TimelineRegionPlayer.loopTicks(for: doc(endTick: 1921)), 3840, "1 tick over one bar → two bars")
        XCTAssertEqual(TimelineRegionPlayer.loopTicks(for: doc(endTick: 2400)), 3840)
        XCTAssertEqual(TimelineRegionPlayer.loopTicks(for: doc(endTick: 3840)), 3840)
    }

    func testLoopTicks_emptySong_isZero() {
        XCTAssertEqual(TimelineRegionPlayer.loopTicks(for: TimelineDocument()), 0)
    }
}

#if canImport(SwiftUI)
// H4 integration (code review MEDIUM: the pure helpers alone stay green even if
// the per-step glue is deleted): transportStep must PULL the live document, merge
// its mixer fields, and push the changed gain/pan to the slot sinks.
@MainActor
final class TimelineRegionPlayerLiveMixerTests: XCTestCase {

    func testTransportStep_pullsLiveMixerEdit_andPushesSlotGainPan() {
        let roll = TimelineLane(name: "MIDI 1", kind: .midi)
        let secondary = TimelineLane(name: "MIDI 2", kind: .midi)
        let document = TimelineDocument(lanes: [roll, secondary], regions: [
            TimelineRegion(laneID: roll.id, clipID: UUID(), startTick: 0, lengthTicks: 3840),
            TimelineRegion(laneID: secondary.id, clipID: UUID(), startTick: 0, lengthTicks: 3840),
        ])

        let player = TimelineRegionPlayer()
        var gains: [Int: Float] = [:]
        var pans: [Int: Float] = [:]
        player.enableMultiRoll(capacity: 4, sink: { _, _ in })
        player.slotGainSink = { gains[$0] = $1 }
        player.slotPanSink = { pans[$0] = $1 }

        var storeDocument = document                    // the "store" the app injects
        player.liveDocument = { storeDocument }

        // Locals kept alive for the whole test — the player only holds them weakly.
        let pattern = PatternEngine()
        let clips = ClipStore()
        let pianoRoll = PianoRollModel()
        player.play(document: document, clips: clips,
                    pattern: pattern, pianoRoll: pianoRoll)
        defer { player.stop() }
        XCTAssertEqual(gains[0], 1, "prime pushes the secondary slot's initial gain")
        XCTAssertEqual(pans[0], 0)

        // Live mixer edit in the STORE while playing — never handed to play().
        storeDocument.lanes[1].level = 0.25
        storeDocument.lanes[1].pan = -0.5
        player.transportStep(1)

        XCTAssertEqual(gains[0] ?? -1, 0.25, accuracy: 1e-6,
                       "the step pulls the store edit and re-pushes the slot gain")
        XCTAssertEqual(pans[0] ?? -1, -0.5, accuracy: 1e-6)
    }

    func testSlotLaneSink_bindsAtPrime_releasesOnStop() {
        // H5b: the player publishes which LANE a slot plays (snapshot-truth) so
        // the app can route the slot to that lane's hosted AU instrument.
        let roll = TimelineLane(name: "MIDI 1", kind: .midi)
        let secondary = TimelineLane(name: "MIDI 2", kind: .midi)
        let document = TimelineDocument(lanes: [roll, secondary], regions: [
            TimelineRegion(laneID: roll.id, clipID: UUID(), startTick: 0, lengthTicks: 1920),
            TimelineRegion(laneID: secondary.id, clipID: UUID(), startTick: 0, lengthTicks: 1920),
        ])
        let player = TimelineRegionPlayer()
        var bindings: [(Int, UUID?)] = []
        player.enableMultiRoll(capacity: 4, sink: { _, _ in })
        player.slotLaneSink = { bindings.append(($0, $1)) }

        let pattern = PatternEngine()
        let clips = ClipStore()
        let pianoRoll = PianoRollModel()
        player.play(document: document, clips: clips,
                    pattern: pattern, pianoRoll: pianoRoll)
        XCTAssertEqual(bindings.first?.0, 0)
        XCTAssertEqual(bindings.first?.1, secondary.id, "prime binds slot 0 to the secondary lane")

        player.stop()
        XCTAssertNil(bindings.last?.1, "stop releases the slot's lane binding")
        XCTAssertEqual(bindings.last?.0, 0)
    }

    func testSlotKindSink_firesLaneKindAtPrime_resetsToPolyOnStop() {
        // S2-W2-4: the player publishes each slot's voice KIND so the app rebinds
        // the physical voice. A drums lane fires .drums at prime; stop resets to
        // .poly so a reused slot never keeps a stale kit/sub.
        let roll = TimelineLane(name: "MIDI 1", kind: .midi)
        let drums = TimelineLane(name: "EchoelDrums", kind: .midi, builtinInstrument: .drums)
        let document = TimelineDocument(lanes: [roll, drums], regions: [
            TimelineRegion(laneID: roll.id, clipID: UUID(), startTick: 0, lengthTicks: 1920),
            TimelineRegion(laneID: drums.id, clipID: UUID(), startTick: 0, lengthTicks: 1920),
        ])
        let player = TimelineRegionPlayer()
        var kinds: [(Int, LaneVoiceKind)] = []
        player.enableMultiRoll(capacity: 4, sink: { _, _ in })
        player.slotKindSink = { kinds.append(($0, $1)) }

        let pattern = PatternEngine()
        let clips = ClipStore()
        let pianoRoll = PianoRollModel()
        player.play(document: document, clips: clips, pattern: pattern, pianoRoll: pianoRoll)
        XCTAssertEqual(kinds.first?.0, 0)
        XCTAssertEqual(kinds.first?.1, .drums, "prime binds slot 0's drums lane to the .drums kind")

        player.stop()
        XCTAssertEqual(kinds.last?.1, .poly, "stop resets the slot's kind to poly")
        XCTAssertEqual(kinds.last?.0, 0)
    }

    func testSlotSampleSink_firesLaneSampleRefAtPrime_resetsToNilOnStop() {
        // S2-W3: the player publishes each slot's persisted sample REF (after the
        // kind — same sites), so the app loads it into the bound sampler unit;
        // stop resets to nil so a reused slot never keeps a stale sample memo.
        let roll = TimelineLane(name: "MIDI 1", kind: .midi)
        let smp = TimelineLane(name: "EchoelSampler", kind: .midi,
                               builtinInstrument: .sampler, samplePath: "drum:Kick")
        let document = TimelineDocument(lanes: [roll, smp], regions: [
            TimelineRegion(laneID: roll.id, clipID: UUID(), startTick: 0, lengthTicks: 1920),
            TimelineRegion(laneID: smp.id, clipID: UUID(), startTick: 0, lengthTicks: 1920),
        ])
        let player = TimelineRegionPlayer()
        var refs: [(Int, String?)] = []
        player.enableMultiRoll(capacity: 4, sink: { _, _ in })
        player.slotSampleSink = { refs.append(($0, $1)) }

        let pattern = PatternEngine()
        let clips = ClipStore()
        let pianoRoll = PianoRollModel()
        player.play(document: document, clips: clips, pattern: pattern, pianoRoll: pianoRoll)
        XCTAssertEqual(refs.first?.0, 0)
        XCTAssertEqual(refs.first?.1, "drum:Kick",
                       "prime publishes the sampler lane's sample ref for its slot")

        player.stop()
        XCTAssertEqual(refs.last?.0, 0)
        XCTAssertNil(refs.last?.1, "stop clears the slot's sample memo")
    }

    func testSlotKindSink_firesBeforePatchAtPrime() {
        // ORDERING LAW: the kind must land BEFORE the per-slot patch/value sinks,
        // so the app's facade routes them to the freshly-bound physical voice.
        let roll = TimelineLane(name: "MIDI 1", kind: .midi)
        let drums = TimelineLane(name: "EchoelDrums", kind: .midi, builtinInstrument: .drums)
        let document = TimelineDocument(lanes: [roll, drums], regions: [
            TimelineRegion(laneID: roll.id, clipID: UUID(), startTick: 0, lengthTicks: 1920),
            TimelineRegion(laneID: drums.id, clipID: UUID(), startTick: 0, lengthTicks: 1920),
        ])
        let player = TimelineRegionPlayer()
        var order: [String] = []
        player.enableMultiRoll(capacity: 4, sink: { _, _ in }) { _, _ in order.append("patch") }
        player.slotKindSink = { _, _ in order.append("kind") }

        let pattern = PatternEngine()
        let clips = ClipStore()
        let pianoRoll = PianoRollModel()
        player.play(document: document, clips: clips, pattern: pattern, pianoRoll: pianoRoll)
        defer { player.stop() }

        let k = order.firstIndex(of: "kind")
        let p = order.firstIndex(of: "patch")
        XCTAssertNotNil(k, "kind sink must fire at prime")
        XCTAssertNotNil(p, "patch sink must fire at prime")
        if let k, let p { XCTAssertLessThan(k, p, "kind binds before patch routes") }
    }

    // MARK: - CLIP-5: play(fromTick:) + relocate(toTick:)

    /// Roll lane spans the whole song; the SECONDARY lane has a region ONLY in
    /// bars 2–3 — whether its slot binds at prime reveals WHERE playback started.
    private func makeLocateFixture() -> (doc: TimelineDocument, secondary: TimelineLane) {
        let roll = TimelineLane(name: "MIDI 1", kind: .midi)
        let secondary = TimelineLane(name: "MIDI 2", kind: .midi)
        let document = TimelineDocument(lanes: [roll, secondary], regions: [
            TimelineRegion(laneID: roll.id, clipID: UUID(), startTick: 0, lengthTicks: 4 * 1920),
            TimelineRegion(laneID: secondary.id, clipID: UUID(), startTick: 2 * 1920, lengthTicks: 2 * 1920),
        ])
        return (document, secondary)
    }

    func testPlayFromTick_startsAtThatBar_andPrimesItsLanes() {
        let (document, secondary) = makeLocateFixture()
        let player = TimelineRegionPlayer()
        var bindings: [(Int, UUID?)] = []
        player.enableMultiRoll(capacity: 4, sink: { _, _ in })
        player.slotLaneSink = { bindings.append(($0, $1)) }

        let pattern = PatternEngine()
        let clips = ClipStore()
        let pianoRoll = PianoRollModel()
        player.play(document: document, clips: clips, pattern: pattern,
                    pianoRoll: pianoRoll, fromTick: 2 * 1920 + 500)   // mid-bar 2
        defer { player.stop() }

        XCTAssertEqual(player.currentTick, 2 * 1920, "start folds to bar 2's downbeat")
        XCTAssertEqual(bindings.first?.1, secondary.id,
                       "the lane active at bar 2 primes — playback really starts there")
    }

    func testPlayFromTick_beyondEnd_foldsToTop() {
        let (document, secondary) = makeLocateFixture()
        let player = TimelineRegionPlayer()
        var bindings: [(Int, UUID?)] = []
        player.enableMultiRoll(capacity: 4, sink: { _, _ in })
        player.slotLaneSink = { bindings.append(($0, $1)) }

        let pattern = PatternEngine()
        let clips = ClipStore()
        let pianoRoll = PianoRollModel()
        player.play(document: document, clips: clips, pattern: pattern,
                    pianoRoll: pianoRoll, fromTick: 4 * 1920)   // exactly the song end
        defer { player.stop() }

        XCTAssertEqual(player.currentTick, 0, "at/past the end folds to the top")
        XCTAssertFalse(bindings.contains { $0.1 == secondary.id },
                       "the bars-2–3 lane is NOT active at the top")
    }

    func testRelocate_whilePlaying_reprimesAtTargetBar() {
        let (document, secondary) = makeLocateFixture()
        let player = TimelineRegionPlayer()
        var bindings: [(Int, UUID?)] = []
        player.enableMultiRoll(capacity: 4, sink: { _, _ in })
        player.slotLaneSink = { bindings.append(($0, $1)) }

        let pattern = PatternEngine()
        let clips = ClipStore()
        let pianoRoll = PianoRollModel()
        player.play(document: document, clips: clips, pattern: pattern, pianoRoll: pianoRoll)
        defer { player.stop() }
        XCTAssertFalse(bindings.contains { $0.1 == secondary.id },
                       "at the top the bars-2–3 lane is silent")

        player.relocate(toTick: 2 * 1920 + 500)   // drop the head mid-bar 2

        XCTAssertEqual(player.currentTick, 2 * 1920, "relocate folds to the bar")
        XCTAssertEqual(bindings.last?.1, secondary.id,
                       "the target bar's lane primes after the jump")
    }

    func testRelocate_whileStopped_isANoOp() {
        let (document, _) = makeLocateFixture()
        let player = TimelineRegionPlayer()
        player.enableMultiRoll(capacity: 4, sink: { _, _ in })

        let pattern = PatternEngine()
        let clips = ClipStore()
        let pianoRoll = PianoRollModel()
        player.play(document: document, clips: clips, pattern: pattern, pianoRoll: pianoRoll)
        player.stop()

        player.relocate(toTick: 2 * 1920)
        XCTAssertEqual(player.currentTick, 0,
                       "a stopped player ignores relocate — play(fromTick:) owns the parked head")
    }
}

// S2 (audio-lane clip-launch): the TimelineRegionPlayer dispatches an AUDIO lane's
// launch transitions to the AudioLanePlayer override (loop the launched segment /
// hand back to the arrangement), and every transport-reset path clears the audio
// override alongside the MIDI launch. Reuses the AudioLanePlayerTests spy harness.
@MainActor
final class TimelineRegionPlayerAudioLaunchTests: XCTestCase {

    private func setup() -> (TimelineRegionPlayer, AudioLanePlayer,
                             AudioLanePlayerTests.Factory, TimelineLane, TimelineRegion,
                             PatternEngine, ClipStore, PianoRollModel) {
        let url = URL(fileURLWithPath: "/tmp/echoel-s2.wav")
        let lane = TimelineLane(name: "Audio 1", kind: .audio)
        let region = TimelineRegion(laneID: lane.id, clipID: UUID(),
                                    startTick: 0, lengthTicks: 1920)
        let document = TimelineDocument(lanes: [lane], regions: [region])
        let factory = AudioLanePlayerTests.Factory()
        let audio = AudioLanePlayer(makeSink: factory.make, resolveURL: { _ in url })
        let player = TimelineRegionPlayer()
        player.audioLanes = audio
        let pattern = PatternEngine()
        let clips = ClipStore()
        let pianoRoll = PianoRollModel()
        player.play(document: document, clips: clips, pattern: pattern, pianoRoll: pianoRoll)
        return (player, audio, factory, lane, region, pattern, clips, pianoRoll)
    }

    func testAudioLaunch_startsOverrideAtBoundary_andStopReleases() {
        let (player, audio, factory, lane, region, pattern, clips, pianoRoll) = setup()
        _ = (pattern, clips, pianoRoll)   // keep the weakly-held locals alive
        defer { player.stop() }

        let primed = factory.sinks.first?.plays.count ?? 0
        XCTAssertGreaterThanOrEqual(primed, 1, "play() primes the arrangement audio region")
        XCTAssertFalse(audio.isLaunchOverriding(lane.id))

        // Launch the audio region immediately (.off), then cross the boundary.
        player.launchRegion(region.id, quantize: .off)
        player.transportStep(1)
        XCTAssertTrue(audio.isLaunchOverriding(lane.id),
                      "the audio lane is launched after the boundary fires")
        XCTAssertGreaterThan(factory.sinks.first?.plays.count ?? 0, primed,
                             "the launch re-triggered the segment (override started)")

        // Stop the launch → the override clears and the lane returns to the arrangement.
        let beforeStop = factory.sinks.first?.plays.count ?? 0
        player.stopLaunched(laneID: lane.id, quantize: .off)
        player.transportStep(2)
        XCTAssertFalse(audio.isLaunchOverriding(lane.id), "stop clears the audio override")
        XCTAssertGreaterThan(factory.sinks.first?.plays.count ?? 0, beforeStop,
                             "the lane restarts its arrangement region on stop")
    }

    func testAudioLaunch_reTriggersOnSongWrap_noSilentBar() {
        // Real-dispatch reproduction of the S3a wrap re-trigger defect (the primitive
        // test `testShiftLaunchOverrides_foldsAnchor…` called `apply` directly, hiding
        // the fact that a wrap is serviced by `prime`, which SKIPS overrides). The song
        // and the launched region are both one bar (loopTicks == region length == 1920),
        // and the launch is anchored to tick 0 (launched BEFORE the first step, `.off`
        // fires immediately at the boundary), so the launched loop's boundary coincides
        // exactly with the song wrap — the pathological case.
        let (player, audio, factory, lane, region, pattern, clips, pianoRoll) = setup()
        _ = (pattern, clips, pianoRoll)
        defer { player.stop() }

        player.launchRegion(region.id, quantize: .off)   // anchor 0 (currentTick == 0)
        player.transportStep(1)
        XCTAssertTrue(audio.isLaunchOverriding(lane.id), "launched from the top")

        // Fill the rest of the bar — no loop boundary is crossed inside bar 0, so no
        // re-trigger fires here (only the wrap step should).
        for s in 2...15 { player.transportStep(s) }
        let beforeWrap = factory.sinks.first?.plays.count ?? 0
        player.transportStep(0)   // 1800 → 1920 ≥ loopTicks → song wrap

        XCTAssertTrue(audio.isLaunchOverriding(lane.id), "still launched across the wrap")
        XCTAssertGreaterThan(factory.sinks.first?.plays.count ?? 0, beforeWrap,
                             "the boundary-aligned launched loop re-triggers on the song "
                             + "wrap (no silent bar; audio stays in lockstep with MIDI)")
    }

    func testTransportStop_clearsAudioOverride() {
        let (player, audio, _, _, region, pattern, clips, pianoRoll) = setup()
        _ = (pattern, clips, pianoRoll)
        player.launchRegion(region.id, quantize: .off)
        player.transportStep(1)
        XCTAssertTrue(audio.hasLaunchOverrides)
        player.stop()
        XCTAssertFalse(audio.hasLaunchOverrides, "transport stop clears the audio override (paired with stopAll)")
    }

    func testMidiLane_launchIsUnaffectedByTheAudioBranch() {
        // Golden guard: a MIDI-only song still never touches the audio override path.
        let roll = TimelineLane(name: "MIDI 1", kind: .midi)
        let region = TimelineRegion(laneID: roll.id, clipID: UUID(), startTick: 0, lengthTicks: 1920)
        let document = TimelineDocument(lanes: [roll], regions: [region])
        let factory = AudioLanePlayerTests.Factory()
        let audio = AudioLanePlayer(makeSink: factory.make, resolveURL: { _ in nil })
        let player = TimelineRegionPlayer()
        player.audioLanes = audio
        let pattern = PatternEngine(); let clips = ClipStore(); let pianoRoll = PianoRollModel()
        player.play(document: document, clips: clips, pattern: pattern, pianoRoll: pianoRoll)
        defer { player.stop() }
        player.launchRegion(region.id, quantize: .off)
        player.transportStep(1)
        XCTAssertFalse(audio.hasLaunchOverrides, "a MIDI launch never creates an audio override")
        XCTAssertNotEqual(player.launchState(laneID: roll.id), .idle,
                          "the MIDI roll lane is launched via the roll path")
    }
}
#endif
