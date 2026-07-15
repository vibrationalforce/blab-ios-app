// VideoLanePlayer.swift
// Echoel — the transport-driven executor for VIDEO lanes: on each transport tick it
// tells each video lane's device player WHERE in its media to be (seek/hold) or to
// stop. The COORDINATOR half, kept Foundation-only + fully unit-tested by abstracting
// the device player (AVQueuePlayer/AVPlayer) behind `VideoRegionSink`. The thin
// AVFoundation adapter (seek + drift-correct via VideoResyncPolicy) and the transport
// wiring land in a following, device-verified cycle — this file has NO AVFoundation,
// no state the render path touches.
//
// It reuses the existing PURE mapping: VideoRegionSync.resolve turns the playhead
// tick into the region's source-seconds (or `.inactive`/`.exhausted`). Unlike audio
// (fire-once buffer schedule), video is a CONTINUOUS seek-sync — the coordinator
// emits the expected source position EVERY tick and the device sink decides whether
// to hard-seek (drift) or let it run. Additive + opt-in: nothing calls it until the
// wiring cycle, so it cannot regress the app today.

import Foundation

/// The device video player a lane drives, abstracted so the coordinator's logic is
/// testable without AVFoundation. The wiring cycle provides an AVPlayer-backed
/// implementation (seek to `sourceSeconds`, run when `playing`, apply VideoResyncPolicy).
@MainActor
public protocol VideoRegionSink: AnyObject {
    /// Present `url` with its playhead at `sourceSeconds`. `playing == true` = let it
    /// run (in-region); `false` = hold this frame (media exhausted before the span ends).
    func present(url: URL, atSourceSeconds sourceSeconds: Double, playing: Bool)
    /// Hide/stop this lane's video (playhead left the region).
    func stop()
}

@MainActor
public final class VideoLanePlayer {

    /// Makes a fresh device sink for a lane (injected; the wiring cycle returns an
    /// AVPlayer-backed sink).
    private let makeSink: () -> VideoRegionSink
    /// Resolves a clip id to a playable file URL (injected). `nil` ⇒ nothing to show.
    private let resolveURL: (UUID) -> URL?
    /// The media's NATIVE duration in seconds for a clip id (injected; measured on
    /// device at import). Drives `.exhausted` when the media is shorter than its
    /// placed span. `<= 0` / unknown ⇒ VideoRegionSync treats it as a single held frame.
    private let nativeDuration: (UUID) -> Double

    private var sinks: [UUID: VideoRegionSink] = [:]

    public init(makeSink: @escaping () -> VideoRegionSink,
                resolveURL: @escaping (UUID) -> URL?,
                nativeDuration: @escaping (UUID) -> Double) {
        self.makeSink = makeSink
        self.resolveURL = resolveURL
        self.nativeDuration = nativeDuration
    }

    /// Sync every video lane to `tick`: seek/hold the active region's media, or stop
    /// the lane in a gap. Continuous (call each transport step + on scrub); the device
    /// sink applies the resync policy. A muted lane or an unresolvable file stops.
    ///
    /// Visibility gates on `isMuted` ONLY (a muted video lane hides) — NOT on
    /// audio-mix solo/level: those are audio-monitoring concepts (an audio solo
    /// should not blank the visuals), so this deliberately differs from
    /// AudioLanePlayer's `effectiveGain` gate. Revisit with the founder if a video
    /// solo concept is wanted.
    public func apply(in doc: TimelineDocument, atTick tick: Int, bpm: Double) {
        // Reconcile: release any sink whose lane was removed / re-typed since the last
        // apply (else its device player would hold the last frame forever).
        let live = Set(doc.videoLaneIDs)
        for laneID in sinks.keys.filter({ !live.contains($0) }) {
            sinks[laneID]?.stop()
            sinks[laneID] = nil
        }
        for laneID in doc.videoLaneIDs {
            guard let lane = doc.lanes.first(where: { $0.id == laneID }), !lane.isMuted,
                  let region = TimelineScheduling.activeRegion(in: doc, laneID: laneID, at: tick),
                  let url = resolveURL(region.clipID) else {
                sinks[laneID]?.stop()
                continue
            }
            switch VideoRegionSync.resolve(startTick: region.startTick,
                                           lengthTicks: region.lengthTicks,
                                           contentOffsetSeconds: region.contentOffsetSeconds,
                                           bpm: bpm,
                                           nativeDurationSeconds: nativeDuration(region.clipID),
                                           playheadTick: tick) {
            case .inactive:
                sinks[laneID]?.stop()
            case .play(let sourceSeconds):
                sink(for: laneID).present(url: url, atSourceSeconds: sourceSeconds, playing: true)
            case .exhausted(let sourceSeconds):
                sink(for: laneID).present(url: url, atSourceSeconds: sourceSeconds, playing: false)
            }
        }
    }

    /// Stop every lane (transport stop / teardown).
    public func stopAll() {
        for sink in sinks.values { sink.stop() }
    }

    private func sink(for laneID: UUID) -> VideoRegionSink {
        if let existing = sinks[laneID] { return existing }
        let created = makeSink()
        sinks[laneID] = created
        return created
    }
}

// MARK: - Monitor selection (pure)

/// The Video Monitor's "which picture" selector (founder 2026-07-15: the header film
/// button opens ONE floating video monitor). Unlike `VideoLanePlayer` (per-lane sinks),
/// the monitor shows a single picture: the FIRST unmuted video lane with an active
/// region at the playhead wins; muted lanes and gaps fall through to the next lane.
/// Pure + Foundation-only so the pick is unit-tested without AVFoundation; the playback
/// outcome itself comes from the already-tested `VideoRegionSync`.
public enum VideoMonitorSelect {

    /// The clip to show at `tick`, or nil when no unmuted video lane has an active
    /// region there. `nativeDuration` resolves a clip id to its media duration in
    /// seconds (`<= 0` / unknown ⇒ a single held frame — e.g. a still image).
    public static func active(in doc: TimelineDocument, atTick tick: Int, bpm: Double,
                              nativeDuration: (UUID) -> Double)
        -> (clipID: UUID, playback: VideoRegionPlayback)? {
        for laneID in doc.videoLaneIDs {
            guard let lane = doc.lanes.first(where: { $0.id == laneID }), !lane.isMuted,
                  let region = TimelineScheduling.activeRegion(in: doc, laneID: laneID, at: tick)
            else { continue }
            let playback = VideoRegionSync.resolve(startTick: region.startTick,
                                                   lengthTicks: region.lengthTicks,
                                                   contentOffsetSeconds: region.contentOffsetSeconds,
                                                   bpm: bpm,
                                                   nativeDurationSeconds: nativeDuration(region.clipID),
                                                   playheadTick: tick)
            if case .inactive = playback { continue }
            return (region.clipID, playback)
        }
        return nil
    }
}
