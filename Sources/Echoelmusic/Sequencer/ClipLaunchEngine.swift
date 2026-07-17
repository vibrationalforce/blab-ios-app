// ClipLaunchEngine.swift
// Echoel — Slice P0 of the Clip-Launch / Performance-Mode plan
// (scratchpads/PLAN_TIMELINE_AUTOMATION_PERFORMANCE.md; founder 2026-07-17:
// "Play Button auf den Clips und Performance Mode — mache dafür alles klar").
//
// The PURE multi-lane clip-launch state machine: quantized starting/stopping of
// timeline REGIONS at runtime, one independent machine per lane —
//
//     idle → queued(regionID, startAtTick)
//          → playing(regionID, startedAtTick)
//          → queuedStop(stopAtTick) → idle
//
// No clock, no Timer, no audio: the @MainActor TimelineRegionPlayer feeds every
// transport step's song-absolute tick into `tick(now:)` and applies the returned
// transitions (load the launched region's window / hand the lane back to the
// arrangement). All quantize grids are whole multiples of the 120-tick transport
// step, so every boundary lands exactly on a sampled tick — deterministic, never
// missed. Foundation-only value logic → unit-tested on Linux CI.
//
// LAWS (pinned by ClipLaunchEngineTests):
//  • Boundary math is exact: the launch tick is the next multiple of the grid AT
//    OR AFTER the request tick — a request already ON the boundary starts at that
//    very boundary ("Tick AUF der Grenze startet sofort"), not a full grid later.
//  • Double-launch of the region already queued/playing on a lane = no-op.
//  • Launching a DIFFERENT region replaces the lane's queue (last tap wins).
//  • A fired transition is anchored to its BOUNDARY tick (`atTick` = the boundary,
//    `startedAtTick` = the boundary), even when the sampled `now` overshoots it —
//    the launched clip's loop phase is musical, not sampling-jittered.
//  • Deterministic: no Date/UUID/random inside; transitions are emitted in
//    stable lane order (sorted by laneID uuidString).
//
// NOT PERSISTED — launch state is runtime-only performance state; it lives and
// dies with the transport (play/stop/relocate reset it). Nothing here is Codable
// on purpose, so no decode/back-compat surface exists.
//
// RELATION TO EXISTING TYPES: reuses `LaunchQuantize` (LaneLaunchLatch.swift) as
// the ONE quantize-grid enum (`.off` = immediate). `LaneLaunchLatch` itself is
// the earlier, clip-ID-based single-lane latch from the ONE-VIEW plan — it is
// not wired into playback; this engine is the region-based, multi-lane core that
// TimelineRegionPlayer actually drives. Reconciling/retiring the latch is a
// separate cleanup cycle (outside P0's file boundaries).

import Foundation

// MARK: - State

/// A region launched onto a lane: which region + the boundary tick its loop
/// phase is anchored to. (`LaunchedClip` is the older latch's clip-based type —
/// this one is region-based and carries the launch timebase.)
public struct LaunchedRegion: Equatable, Sendable {
    public let regionID: UUID
    /// The boundary tick the launch fired at — the launched clip's timebase:
    /// content position = (now − startedAtTick) folded into the clip's length.
    public let startedAtTick: Int
    public init(regionID: UUID, startedAtTick: Int) {
        self.regionID = regionID
        self.startedAtTick = startedAtTick
    }
}

/// One lane's launch state (the public query surface of the machine).
public enum LaneLaunchState: Equatable, Sendable {
    case idle
    /// A launch is queued for the boundary. `current` is the STILL-SOUNDING
    /// launched region it will replace (nil when the lane was idle at request
    /// time — the arrangement keeps playing until the boundary).
    case queued(regionID: UUID, startAtTick: Int, current: LaunchedRegion?)
    /// The launched region overrides the lane's arrangement and loops.
    case playing(LaunchedRegion)
    /// The launched region keeps looping until `stopAtTick`, then the lane
    /// returns to the arrangement.
    case queuedStop(current: LaunchedRegion, stopAtTick: Int)
}

/// One lane's state change fired by `tick(now:)` — what the player must apply.
public struct LaunchTransition: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Begin the override: load the launched region's window on this lane.
        case started(regionID: UUID)
        /// End the override: hand the lane back to the arrangement.
        case stopped(regionID: UUID)
        /// Replace one launched region with another at the same boundary
        /// (stop + start fused, so the player loads exactly once).
        case switched(fromRegionID: UUID, toRegionID: UUID)
    }
    public let laneID: UUID
    public let kind: Kind
    /// The BOUNDARY tick this transition belongs to (≤ the sampled `now`).
    public let atTick: Int
    public init(laneID: UUID, kind: Kind, atTick: Int) {
        self.laneID = laneID
        self.kind = kind
        self.atTick = atTick
    }
}

// MARK: - Engine

/// Pure, deterministic multi-lane launch machine. Value type — the player owns
/// one instance on the @MainActor control plane; nothing here touches audio.
public struct ClipLaunchEngine: Equatable, Sendable {

    /// Per-lane state. Idle lanes are absent (kept minimal, `isIdle` is O(1)).
    private var lanes: [UUID: LaneLaunchState] = [:]

    public init() {}

    // MARK: Queries

    /// True when NO lane has any launch activity — the player's golden gate:
    /// while idle, every playback path is byte-identical to pre-launch code.
    public var isIdle: Bool { lanes.isEmpty }

    /// The lane's current state (`.idle` for lanes never launched).
    public func state(laneID: UUID) -> LaneLaunchState {
        lanes[laneID] ?? .idle
    }

    /// Whether a LAUNCHED region currently overrides this lane's arrangement.
    /// True for `.playing`, `.queuedStop`, and `.queued` with a still-sounding
    /// `current`; false for `.idle` and `.queued` from idle (the arrangement
    /// keeps playing until the boundary — Ableton behavior).
    public func isOverriding(laneID: UUID) -> Bool {
        switch state(laneID: laneID) {
        case .idle:                          return false
        case .queued(_, _, let current):     return current != nil
        case .playing, .queuedStop:          return true
        }
    }

    /// The launched region SOUNDING on this lane right now (nil = arrangement).
    public func soundingRegion(laneID: UUID) -> LaunchedRegion? {
        switch state(laneID: laneID) {
        case .idle:                          return nil
        case .queued(_, _, let current):     return current
        case .playing(let clip):             return clip
        case .queuedStop(let clip, _):       return clip
        }
    }

    /// Lanes whose arrangement is currently overridden, in stable (uuidString)
    /// order — deterministic for the player's re-apply loops.
    public var overriddenLaneIDs: [UUID] {
        lanes.keys
            .filter { isOverriding(laneID: $0) }
            .sorted { $0.uuidString < $1.uuidString }
    }

    // MARK: Pure tick math

    /// The next `quantize` boundary AT OR AFTER `tick`: the next multiple of the
    /// grid, where a tick already ON the boundary maps to ITSELF (starts at that
    /// very boundary). `.off` (= immediate) returns the tick unchanged. Never
    /// negative.
    public static func boundaryTick(onOrAfter tick: Int, quantize: LaunchQuantize) -> Int {
        let t = Swift.max(0, tick)
        guard let grid = quantize.ticks, grid > 0 else { return t }
        return (t + grid - 1) / grid * grid
    }

    /// The clip-INTERNAL tick of a looping launched region: the elapsed time
    /// since its anchor boundary folded into the clip's length. Elapsed < 0
    /// (querying before the anchor) clamps to 0; a degenerate length yields 0.
    /// NOTE: the MIDI playback layers (roll bar-cycling / LaneNotePump) loop in
    /// WHOLE BARS of the region — this exact-tick fold is the pure reference for
    /// tests and the (P1) UI playhead-in-clip display.
    public static func loopedContentTick(now: Int, startedAtTick: Int, lengthTicks: Int) -> Int {
        guard lengthTicks > 0 else { return 0 }
        let elapsed = now - startedAtTick
        guard elapsed > 0 else { return 0 }
        return elapsed % lengthTicks
    }

    // MARK: Requests (control plane — user taps)

    /// Queue `regionID` to launch on `laneID` at the next `quantize` boundary
    /// at-or-after `atTick`. Laws: double-launch of the queued/playing region is
    /// a no-op; a different region REPLACES the queue; launching the region a
    /// queued-stop would end CANCELS that stop (the clip simply keeps playing);
    /// launching the still-sounding region while a switch is queued cancels the
    /// switch (back to plain `.playing`).
    public mutating func requestLaunch(laneID: UUID, regionID: UUID,
                                       atTick: Int, quantize: LaunchQuantize) {
        let startAt = Self.boundaryTick(onOrAfter: atTick, quantize: quantize)
        switch state(laneID: laneID) {
        case .idle:
            lanes[laneID] = .queued(regionID: regionID, startAtTick: startAt, current: nil)
        case .queued(let queuedRegion, _, let current):
            if queuedRegion == regionID { return }                    // double-launch no-op
            if let current, current.regionID == regionID {
                lanes[laneID] = .playing(current)                     // revert the queued switch
            } else {
                lanes[laneID] = .queued(regionID: regionID, startAtTick: startAt, current: current)
            }
        case .playing(let clip):
            if clip.regionID == regionID { return }                   // double-launch no-op
            lanes[laneID] = .queued(regionID: regionID, startAtTick: startAt, current: clip)
        case .queuedStop(let clip, _):
            if clip.regionID == regionID {
                lanes[laneID] = .playing(clip)                        // cancel the stop
            } else {
                lanes[laneID] = .queued(regionID: regionID, startAtTick: startAt, current: clip)
            }
        }
    }

    /// Queue the lane's launch to END at the next `quantize` boundary at-or-after
    /// `atTick` (back to the arrangement). A queued-but-not-yet-started launch is
    /// simply cancelled (idle again — nothing ever sounded); a queued switch is
    /// cancelled AND the sounding clip's stop is queued; a pending stop is
    /// re-quantized (last tap wins). No-op while idle.
    public mutating func requestStop(laneID: UUID, atTick: Int, quantize: LaunchQuantize) {
        let stopAt = Self.boundaryTick(onOrAfter: atTick, quantize: quantize)
        switch state(laneID: laneID) {
        case .idle:
            return
        case .queued(_, _, let current):
            if let current {
                lanes[laneID] = .queuedStop(current: current, stopAtTick: stopAt)
            } else {
                lanes[laneID] = nil                                   // never started — just un-queue
            }
        case .playing(let clip):
            lanes[laneID] = .queuedStop(current: clip, stopAtTick: stopAt)
        case .queuedStop(let clip, _):
            lanes[laneID] = .queuedStop(current: clip, stopAtTick: stopAt)   // re-quantize
        }
    }

    // MARK: Transport tick

    /// Advance the machine to the transport's song-absolute `now` and return the
    /// lanes that change state at a boundary `≤ now`. At most ONE transition per
    /// lane per call (states hold a single pending action); transitions are
    /// anchored to their boundary tick and emitted in stable lane order.
    public mutating func tick(now: Int) -> [LaunchTransition] {
        guard !lanes.isEmpty else { return [] }
        var out: [LaunchTransition] = []
        for laneID in lanes.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            switch lanes[laneID] ?? .idle {
            case .idle, .playing:
                break
            case .queued(let regionID, let startAt, let current):
                guard now >= startAt else { break }
                lanes[laneID] = .playing(LaunchedRegion(regionID: regionID, startedAtTick: startAt))
                if let current {
                    out.append(LaunchTransition(laneID: laneID,
                                                kind: .switched(fromRegionID: current.regionID,
                                                                toRegionID: regionID),
                                                atTick: startAt))
                } else {
                    out.append(LaunchTransition(laneID: laneID,
                                                kind: .started(regionID: regionID),
                                                atTick: startAt))
                }
            case .queuedStop(let clip, let stopAt):
                guard now >= stopAt else { break }
                lanes[laneID] = nil
                out.append(LaunchTransition(laneID: laneID,
                                            kind: .stopped(regionID: clip.regionID),
                                            atTick: stopAt))
            }
        }
        return out
    }

    // MARK: Maintenance (control plane)

    /// Shift EVERY stored tick by `deltaTicks` — the song-loop-wrap rebase: when
    /// the player's tick timebase folds back by the loop length, the launch
    /// timebase folds with it (boundaries and loop lengths are whole bars, so
    /// grid alignment survives; an anchored `startedAtTick` may go negative —
    /// the elapsed math stays continuous across the wrap).
    public mutating func shift(by deltaTicks: Int) {
        guard deltaTicks != 0 else { return }
        for (laneID, s) in lanes {
            switch s {
            case .idle:
                break
            case .queued(let regionID, let startAt, let current):
                lanes[laneID] = .queued(regionID: regionID,
                                        startAtTick: startAt + deltaTicks,
                                        current: current.map {
                                            LaunchedRegion(regionID: $0.regionID,
                                                           startedAtTick: $0.startedAtTick + deltaTicks)
                                        })
            case .playing(let clip):
                lanes[laneID] = .playing(LaunchedRegion(regionID: clip.regionID,
                                                        startedAtTick: clip.startedAtTick + deltaTicks))
            case .queuedStop(let clip, let stopAt):
                lanes[laneID] = .queuedStop(current: LaunchedRegion(regionID: clip.regionID,
                                                                    startedAtTick: clip.startedAtTick + deltaTicks),
                                            stopAtTick: stopAt + deltaTicks)
            }
        }
    }

    /// Force one lane back to idle WITHOUT a transition (control-plane cancel —
    /// the caller has already handled the lane's audio, e.g. a vanished region).
    public mutating func clear(laneID: UUID) {
        lanes[laneID] = nil
    }

    /// Drop every launch (play/stop/relocate — launch state never survives a
    /// transport reset). No transitions: the caller resets the audio side itself.
    public mutating func removeAll() {
        lanes.removeAll()
    }

    /// Reconcile after a STRUCTURAL document edit: silently drop state that
    /// references a deleted lane or region. A queued launch whose region vanished
    /// collapses to its surviving `current` (still `.playing`) or to idle; a
    /// vanished `current` under a queued launch keeps the queue (from idle).
    /// No transitions — the caller re-primes the audio side.
    public mutating func prune(validLaneIDs: Set<UUID>, validRegionIDs: Set<UUID>) {
        for (laneID, s) in lanes {
            guard validLaneIDs.contains(laneID) else {
                lanes[laneID] = nil
                continue
            }
            switch s {
            case .idle:
                lanes[laneID] = nil
            case .queued(let regionID, let startAt, let current):
                let survivor = current.flatMap { validRegionIDs.contains($0.regionID) ? $0 : nil }
                if validRegionIDs.contains(regionID) {
                    if survivor == nil, current != nil {
                        lanes[laneID] = .queued(regionID: regionID, startAtTick: startAt, current: nil)
                    }
                } else if let survivor {
                    lanes[laneID] = .playing(survivor)
                } else {
                    lanes[laneID] = nil
                }
            case .playing(let clip):
                if !validRegionIDs.contains(clip.regionID) { lanes[laneID] = nil }
            case .queuedStop(let clip, _):
                if !validRegionIDs.contains(clip.regionID) { lanes[laneID] = nil }
            }
        }
    }
}
