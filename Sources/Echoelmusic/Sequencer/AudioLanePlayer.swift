// AudioLanePlayer.swift
// Echoel — the transport-driven executor for AUDIO lanes: on each transport window
// it plays / stops each audio lane's active region. This is the COORDINATOR half,
// kept Foundation-only + fully unit-tested by abstracting the device player behind
// `AudioRegionSink`. The thin AVFoundation adapter (an AudioClipPlayer per lane,
// attached to the engine) and the transport wiring land in a following, device-
// verified cycle — this file has NO AVFoundation, no audio-thread code, no state
// the render path touches.
//
// It composes the two already-tested pieces: TimelineScheduling decides WHICH
// region a lane plays and WHEN it changes (onset/clear); AudioRegionPlayback maps
// the song tick to the media-file position + remaining length. Additive + opt-in:
// nothing calls it until the wiring cycle, so it cannot regress the app today.
//
// KNOWN GAP (wiring cycle must close): gain is consulted only at a region CHANGE
// (`.load`) or `prime`. A live mute/solo/level toggle WHILE the playhead sits inside
// an unchanging region produces no `laneEvent`, so the sink keeps playing at the old
// gain until the next region boundary. The wiring cycle must re-drive the lane on a
// mute/solo/level change (observe it → call `apply`/`prime` or a dedicated re-gate),
// same as the primary roll lane hard-cuts on its mute transition.

import Foundation

/// The device player a lane drives, abstracted so the coordinator's mapping logic
/// is testable without AVFoundation. The wiring cycle provides an AudioClipPlayer-
/// backed implementation (attach to the engine, `scheduleSegment`).
@MainActor
public protocol AudioRegionSink: AnyObject {
    /// Begin playing `url` from `fromSeconds` into the file, for up to
    /// `lengthSeconds`, at linear `gain`. Replaces any current playback on this sink.
    func play(url: URL, fromSeconds: Double, lengthSeconds: Double, gain: Float)
    /// Stop this sink's playback.
    func stop()
}

@MainActor
public final class AudioLanePlayer {

    /// Makes a fresh device sink for a lane (injected; the wiring cycle returns an
    /// AudioClipPlayer-backed sink attached to the engine).
    private let makeSink: () -> AudioRegionSink
    /// Resolves a clip id to a playable file URL (injected; the wiring cycle passes
    /// `clips.clip(id:)` → mediaRef → URL). `nil` ⇒ nothing to play (the lane stops).
    private let resolveURL: (UUID) -> URL?

    private var sinks: [UUID: AudioRegionSink] = [:]

    public init(makeSink: @escaping () -> AudioRegionSink,
                resolveURL: @escaping (UUID) -> URL?) {
        self.makeSink = makeSink
        self.resolveURL = resolveURL
    }

    /// Apply the transport window `fromTick`→`toTick`: for each audio lane, start
    /// its newly-entered region (`.load`), stop it on leaving into a gap (`.clear`),
    /// or leave it playing (`.unchanged`). Order-independent, so a loop wrap works
    /// when the caller passes the real from/to ticks (mirrors the MIDI player).
    public func apply(in doc: TimelineDocument, fromTick: Int, toTick: Int, bpm: Double) {
        for laneID in doc.audioLaneIDs {
            switch TimelineScheduling.laneEvent(in: doc, laneID: laneID,
                                                fromTick: fromTick, toTick: toTick) {
            case .unchanged:
                break
            case .clear:
                sinks[laneID]?.stop()
            case .load(let region):
                start(region, laneID: laneID, atTick: toTick, in: doc, bpm: bpm)
            }
        }
    }

    /// Prime the audio lanes whose region is ACTIVE at `tick` (play()/seek entry):
    /// an already-active region reads `.unchanged` and would never load, so this is
    /// its onset twin — the audio analog of the MIDI `primeSecondaryLanes`.
    public func prime(in doc: TimelineDocument, atTick tick: Int, bpm: Double) {
        for laneID in doc.audioLaneIDs {
            guard let region = TimelineScheduling.activeRegion(in: doc, laneID: laneID, at: tick) else {
                sinks[laneID]?.stop()
                continue
            }
            start(region, laneID: laneID, atTick: tick, in: doc, bpm: bpm)
        }
    }

    /// Stop every lane (transport stop / teardown).
    public func stopAll() {
        for sink in sinks.values { sink.stop() }
    }

    // MARK: - Private

    /// Start `region` on `laneID` at `tick`: gate on the lane's audible gain, resolve
    /// the file, map the tick to the media position + remaining length, and drive the
    /// sink. A muted / soloed-away lane or an unresolvable file stops instead.
    private func start(_ region: TimelineRegion, laneID: UUID, atTick tick: Int,
                       in doc: TimelineDocument, bpm: Double) {
        let gain = doc.effectiveGain(for: laneID)
        guard gain > 0,
              let url = resolveURL(region.clipID) else {
            sinks[laneID]?.stop()
            return
        }
        // Media position at this tick (mid-region entry advances it); remaining
        // length to the region boundary. AudioRegionPlayback is the tested map.
        let from = AudioRegionPlayback.filePositionSeconds(for: region, atTick: tick, bpm: bpm)
            ?? region.contentOffsetSeconds
        let length = TimelineTime.seconds(fromTicks: region.endTick - tick, bpm: bpm)
        sink(for: laneID).play(url: url, fromSeconds: from,
                               lengthSeconds: max(0, length), gain: gain)
    }

    private func sink(for laneID: UUID) -> AudioRegionSink {
        if let existing = sinks[laneID] { return existing }
        let created = makeSink()
        sinks[laneID] = created
        return created
    }
}
