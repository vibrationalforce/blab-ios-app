// VideoAudioPairing.swift
// Echoelmusic — Sequencer
//
// PURE placement logic for "video sound" (Founder 2026-07-16: „Video Sound mit den selben
// Algorithmen"). The timeline video MONITOR is muted by design; a video's sound must become
// a first-class AUDIO clip so it plays through AudioLanePlayer → masterMixer and inherits
// warp/FX (the stretch engine) — see scratchpads/PLAN_VIDEO_AUDIO.md.
//
// This resolves WHERE the extracted-audio clip goes so it stays LOCKED to the video region:
// identical startTick + lengthTicks (same musical span), same trim in-point. The async audio
// EXTRACTION + store mutation is the impure edge (Slice 1b); this pure core is where the
// alignment/lane/slot correctness lives, fully unit-testable. No AVFoundation, no stores.

import Foundation

public enum VideoAudioPairing {

    /// Where the paired audio clip lands.
    public enum LaneChoice: Equatable, Sendable {
        /// Land on this existing (non-bio) audio lane.
        case existing(UUID)
        /// No audio lane exists yet — the caller must add a `.audio` lane and use it.
        case createNew
    }

    /// The paired audio placement. Shares the video region's `startTick` and `lengthTicks`
    /// so picture and sound never drift; `contentOffsetSeconds` mirrors the video's trim.
    public struct Plan: Equatable, Sendable {
        public let lane: LaneChoice
        public let startTick: Int
        public let lengthTicks: Int
        public let contentOffsetSeconds: Double
        public let gain: Float

        public init(lane: LaneChoice, startTick: Int, lengthTicks: Int,
                    contentOffsetSeconds: Double, gain: Float) {
            self.lane = lane
            self.startTick = startTick
            self.lengthTicks = lengthTicks
            self.contentOffsetSeconds = contentOffsetSeconds
            self.gain = gain
        }
    }

    /// The clip grid must have room for BOTH the video clip and its paired audio clip.
    public static let requiredFreeSlots = 2

    public static func hasRoom(freeSlotCount: Int) -> Bool {
        freeSlotCount >= requiredFreeSlots
    }

    /// Plan the paired audio placement, LOCKED to the video region.
    ///
    /// - Parameters:
    ///   - videoStartTick: the placed video region's start (audio aligns exactly to it).
    ///   - videoLengthTicks: the video region's span (audio inherits it VERBATIM so the two
    ///     have identical spans; floored at one tick — matching the video region's own
    ///     `max(1, …)` floor — so a degenerate 0 can't produce a zero-length audio clip).
    ///   - existingAudioLaneIDs: non-bio `.audio` lane ids in document order; `.first` wins,
    ///     else `.createNew`.
    ///   - contentOffsetSeconds: the video's trim in-point (audio starts at the same media pos).
    ///   - gain: initial clip gain.
    public static func plan(videoStartTick: Int,
                            videoLengthTicks: Int,
                            existingAudioLaneIDs: [UUID],
                            contentOffsetSeconds: Double = 0,
                            gain: Float = 1) -> Plan {
        let lane: LaneChoice = existingAudioLaneIDs.first.map(LaneChoice.existing) ?? .createNew
        return Plan(lane: lane,
                    startTick: max(0, videoStartTick),
                    lengthTicks: max(1, videoLengthTicks),   // == the video region's span (never 0)
                    contentOffsetSeconds: max(0, contentOffsetSeconds.isFinite ? contentOffsetSeconds : 0),
                    gain: gain.isFinite ? gain : 1)
    }
}
