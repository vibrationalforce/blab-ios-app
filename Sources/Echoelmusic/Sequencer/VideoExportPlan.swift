// VideoExportPlan.swift
// Echoel — Sequencer
//
// PURE video export planner. Turns a TimelineDocument's VIDEO lanes+regions into an
// ordered list of composition instructions (source trim ↔ timeline placement, plus a
// deterministic z-order) that a device-side AVMutableVideoComposition builder consumes.
// Foundation-only, fully unit-testable, DETERMINISTIC — no clocks, no RNG, no UUID().
//
// Time model matches Timeline.swift: song-absolute 480-PPQ ticks converted to seconds
// via TimelineTime.seconds(fromTicks:bpm:). Video is real-time (1 source-second =
// 1 transport-second at tempo), so a region's source span equals its timeline span.

import Foundation

/// One layer of a video composition: which clip on which lane plays, the source
/// time range to read, the timeline time range to place it at, and how it stacks.
public struct VideoCompositionInstruction: Equatable, Sendable {
    /// The timeline lane the region lives on.
    public let laneID: UUID
    /// The clip whose media this instruction reads.
    public let clipID: UUID
    /// Trim-in point into the source media, in seconds (≥ 0).
    public let sourceStartSeconds: Double
    /// Length of source media to read, in seconds (> 0).
    public let sourceDurationSeconds: Double
    /// Where this layer starts on the export timeline, in seconds (≥ 0).
    public let timelineStartSeconds: Double
    /// How long this layer occupies the export timeline, in seconds (> 0).
    public let timelineDurationSeconds: Double
    /// Stacking order: lower = further back, higher = closer to front. Derived
    /// from lane order (first video lane = 0).
    public let zIndex: Int
    /// Layer opacity, 0…1.
    public let opacity: Float

    public init(laneID: UUID, clipID: UUID,
                sourceStartSeconds: Double, sourceDurationSeconds: Double,
                timelineStartSeconds: Double, timelineDurationSeconds: Double,
                zIndex: Int, opacity: Float) {
        self.laneID = laneID
        self.clipID = clipID
        self.sourceStartSeconds = sourceStartSeconds
        self.sourceDurationSeconds = sourceDurationSeconds
        self.timelineStartSeconds = timelineStartSeconds
        self.timelineDurationSeconds = timelineDurationSeconds
        self.zIndex = zIndex
        self.opacity = opacity
    }
}

/// Pure planner: `TimelineDocument` (video lanes only) → ordered composition
/// instructions. No device APIs; the AVFoundation builder is the only consumer.
public enum VideoExportPlan {

    /// Build composition instructions for every region on a VIDEO lane, z-ordered
    /// by lane order (first video lane in `document.lanes` = zIndex 0) and, within a
    /// lane, by region start tick. Time ranges convert ticks → seconds at `bpm` via
    /// `TimelineTime.seconds`. Non-video lanes are excluded; an empty document (or a
    /// non-positive bpm) yields `[]`.
    ///
    /// - Parameters:
    ///   - document: the arrange timeline to export.
    ///   - bpm: tempo used for tick→second conversion; must be > 0 or the result is empty.
    /// - Returns: instructions ordered by `zIndex` then `timelineStartSeconds`.
    public static func instructions(document: TimelineDocument, bpm: Double) -> [VideoCompositionInstruction] {
        guard bpm > 0 else { return [] }

        var result: [VideoCompositionInstruction] = []
        var zIndex = 0

        for lane in document.lanes {
            // VIDEO lanes only; a bio lane is never a media lane.
            guard lane.kind == .video, !lane.isBio else { continue }

            // Regions on this lane, deterministically ordered by start tick.
            let laneRegions = document.regions(in: lane.id)
            for region in laneRegions {
                let timelineStart = TimelineTime.seconds(fromTicks: region.startTick, bpm: bpm)
                let timelineEnd = TimelineTime.seconds(fromTicks: region.endTick, bpm: bpm)
                let timelineDuration = max(0, timelineEnd - timelineStart)
                // A region always has lengthTicks ≥ 1, so at bpm > 0 the duration is > 0;
                // guard defensively anyway and skip degenerate spans.
                guard timelineDuration > 0 else { continue }

                let sourceStart = max(0, region.contentOffsetSeconds)
                // Real-time video: source span == timeline span.
                let sourceDuration = timelineDuration

                result.append(VideoCompositionInstruction(
                    laneID: lane.id,
                    clipID: region.clipID,
                    sourceStartSeconds: sourceStart,
                    sourceDurationSeconds: sourceDuration,
                    timelineStartSeconds: timelineStart,
                    timelineDurationSeconds: timelineDuration,
                    zIndex: zIndex,
                    opacity: 1))
            }

            // Every video lane advances the stack, even if it had no regions, so a
            // lane's zIndex is stable regardless of how many regions it carries.
            zIndex += 1
        }

        return result
    }
}
