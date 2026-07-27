// LaneLaunchLatch.swift
// Echoel — lane-scoped, device-independent clip-launch core (PLAN_ONE_VIEW L1, P4).
//
// The "latched region override" per lane: tapping a clip in the ONE timeline view
// latches it over that lane's arrangement content and loops it until the next tap
// (Ableton-session launch, but in the arrange view — no separate Clip View). Pure
// value logic on song-absolute 480-PPQ ticks; the @MainActor driver rides the ONE
// shared Transport and calls these — no second clock, no parallel player.
//
// All launch grids are multiples of ticksPerTransportStep (120), so every quantize
// boundary lands exactly on a sampled transport step → deterministic, never missed.
//
// NOTE: the older single-slot `LaunchQuantizer` class (global, also loaded drums) is
// DELETED (#132 Slice 5a) — this was already its lane-scoped successor, and the legacy
// one had no caller left. The timing namespace here stays `LaunchTiming`: the name was
// chosen to avoid colliding with that class, and renaming it now would be churn for a
// collision that no longer exists.

import Foundation

// MARK: - Grid

/// Launch quantize grid. Raw values persist (@AppStorage) — keep stable. Every
/// non-`.off` grid is a whole multiple of the 120-tick transport step.
public enum LaunchQuantize: String, Codable, CaseIterable, Sendable {
    case off, sixteenth, beat, bar, twoBar, fourBar

    /// Grid spacing in song ticks; `nil` = no quantize (launch immediately).
    public var ticks: Int? {
        switch self {
        case .off:       return nil
        case .sixteenth: return TimelineTime.ticksPerTransportStep    // 120
        case .beat:      return TimelineTime.ticksPerBeat             // 480
        case .bar:       return TimelineTime.ticksPerBar              // 1920
        case .twoBar:    return TimelineTime.ticksPerBar * 2          // 3840
        case .fourBar:   return TimelineTime.ticksPerBar * 4          // 7680
        }
    }

    public var displayName: String {
        switch self {
        case .off:       return "Off"
        case .sixteenth: return "1/16"
        case .beat:      return "Beat"
        case .bar:       return "Bar"
        case .twoBar:    return "2 Bars"
        case .fourBar:   return "4 Bars"
        }
    }
}

// MARK: - Pure timing math

/// Deterministic launch/loop tick math. No state, no clock — the driver feeds it
/// absolute ticks.
public enum LaunchTiming {

    /// The next quantize boundary STRICTLY after `now` for `quantize`. `.off`
    /// (or an unknown grid) returns `now` → the caller launches immediately.
    public static func nextLaunchTick(now: Int, quantize: LaunchQuantize) -> Int {
        guard let grid = quantize.ticks, grid > 0 else { return max(0, now) }
        let n = max(0, now)
        return (n / grid + 1) * grid
    }

    /// Did the playhead cross `boundary` moving `from` → `to`? Half-open on the
    /// left, closed on the right: `from < boundary <= to`.
    public static func crossed(boundary: Int, from: Int, to: Int) -> Bool {
        from < boundary && boundary <= to
    }

    /// Position WITHIN a looping latched clip at `now`: `(now − sinceTick) mod
    /// loopLength`, clamped to `0` before the latch starts.
    public static func loopContentTick(now: Int, sinceTick: Int, loopLength: Int) -> Int {
        guard loopLength > 0 else { return 0 }
        let rel = now - sinceTick
        guard rel > 0 else { return 0 }
        return rel % loopLength
    }

    /// Did the latched loop wrap between `from` and `to` (→ MIDI re-stages the next
    /// loop)? False before the latch starts or on a non-advancing/zero span.
    public static func loopWrapped(from: Int, to: Int, sinceTick: Int, loopLength: Int) -> Bool {
        guard loopLength > 0, to > from, to > sinceTick else { return false }
        let a = max(0, from - sinceTick)
        let b = to - sinceTick
        return a / loopLength != b / loopLength
    }
}

// MARK: - Latch content

/// A clip latched onto a lane: what to load + how long its loop is.
public struct LaunchedClip: Equatable, Sendable {
    public let clipID: UUID
    public let loopLengthTicks: Int
    public init(clipID: UUID, loopLengthTicks: Int) {
        self.clipID = clipID
        self.loopLengthTicks = max(1, loopLengthTicks)
    }
}

/// What the lane's player must do when the latch resolves.
public enum LaunchEvent: Equatable, Sendable {
    case none                 // nothing changed this step
    case latch(LaunchedClip)  // begin/replace the override now — load this clip
    case release              // drop the override — arrangement resumes
}

// MARK: - Per-lane latch state machine (pure)

/// The "latched region override" for ONE lane. Value type, no allocation, evaluated
/// only on the @MainActor control plane. Coexists with arrangement playback: when
/// `.following` the lane plays its arrangement region; when `.latched` the clip
/// overrides and loops until released.
public struct LaneLaunchLatch: Equatable, Sendable {

    public enum Active: Equatable, Sendable {
        case following                                   // arrangement region plays
        case latched(clip: LaunchedClip, sinceTick: Int) // override loops
    }

    public enum Pending: Equatable, Sendable {
        case launch(clip: LaunchedClip, fireTick: Int)
        case release(fireTick: Int)
    }

    public private(set) var active: Active = .following
    public private(set) var pending: Pending?

    public init() {}

    public var isLatched: Bool { if case .latched = active { return true }; return false }
    public var activeClipID: UUID? {
        if case let .latched(clip, _) = active { return clip.clipID }
        return nil
    }
    public var pendingClipID: UUID? {
        if case let .launch(clip, _) = pending { return clip.clipID }
        return nil
    }
    public var isReleasePending: Bool {
        if case .release = pending { return true }; return false
    }

    /// Tap a clip → launch it. Immediate when stopped or `.off`; otherwise queued to
    /// the next boundary (the currently sounding content keeps playing until then).
    @discardableResult
    public mutating func requestLaunch(_ clip: LaunchedClip, now: Int,
                                       quantize: LaunchQuantize, isPlaying: Bool) -> LaunchEvent {
        guard isPlaying, quantize != .off else {
            active = .latched(clip: clip, sinceTick: max(0, now))
            pending = nil
            return .latch(clip)
        }
        pending = .launch(clip: clip,
                          fireTick: LaunchTiming.nextLaunchTick(now: now, quantize: quantize))
        return .none
    }

    /// Stop / re-tap the live clip → return to arrangement. Immediate when stopped or
    /// `.off`; otherwise queued to the next boundary. No-op while already following.
    @discardableResult
    public mutating func requestStop(now: Int, quantize: LaunchQuantize,
                                     isPlaying: Bool) -> LaunchEvent {
        guard case .latched = active else { pending = nil; return .none }
        guard isPlaying, quantize != .off else {
            active = .following
            pending = nil
            return .release
        }
        pending = .release(fireTick: LaunchTiming.nextLaunchTick(now: now, quantize: quantize))
        return .none
    }

    /// Drop the queued change (re-tap a queued cell before it fires).
    public mutating func cancelPending() { pending = nil }

    /// Transport stopped → clear the latch (plan: "Stop löscht Latch").
    public mutating func handleStop() {
        active = .following
        pending = nil
    }

    /// Fed each transport step as absolute ticks. Applies a queued change on the
    /// boundary it crosses; otherwise `.none`.
    @discardableResult
    public mutating func resolve(from fromTick: Int, to toTick: Int) -> LaunchEvent {
        guard let p = pending else { return .none }
        let fire: Int
        switch p {
        case let .launch(_, f): fire = f
        case let .release(f):   fire = f
        }
        guard LaunchTiming.crossed(boundary: fire, from: fromTick, to: toTick) else { return .none }
        switch p {
        case let .launch(clip, _):
            active = .latched(clip: clip, sinceTick: fire)
            pending = nil
            return .latch(clip)
        case .release:
            active = .following
            pending = nil
            return .release
        }
    }

    /// Position within the latched loop at `now` (`nil` while following).
    public func contentTick(at now: Int) -> Int? {
        guard case let .latched(clip, since) = active else { return nil }
        return LaunchTiming.loopContentTick(now: now, sinceTick: since,
                                            loopLength: clip.loopLengthTicks)
    }

    /// Did the latched loop wrap between `from` and `to` (→ re-stage MIDI)?
    public func loopWrapped(from: Int, to: Int) -> Bool {
        guard case let .latched(clip, since) = active else { return false }
        return LaunchTiming.loopWrapped(from: from, to: to, sinceTick: since,
                                        loopLength: clip.loopLengthTicks)
    }
}

// MARK: - Gesture → intent (pure)

/// The decision a press resolves to. `pending` = still deciding.
public enum PressOutcome: Equatable, Sendable {
    case pending, launch, openEditor, move
}

public struct GestureThresholds: Equatable, Sendable {
    public var longPressSeconds: Double
    public var moveSlopPt: Double
    public var minLaunchWidthPt: Double
    public init(longPressSeconds: Double = 0.35, moveSlopPt: Double = 10,
                minLaunchWidthPt: Double = 24) {
        self.longPressSeconds = longPressSeconds
        self.moveSlopPt = moveSlopPt
        self.minLaunchWidthPt = minLaunchWidthPt
    }
}

/// Maps a region press to its intent (spec: Tap=launch ≥24pt · long-press-release=
/// editor · long-press-then-drag=move). Pure — the SwiftUI gesture feeds it numbers.
public enum LaunchGestureResolver {
    public static func resolve(elapsedSeconds: Double, movedPt: Double, released: Bool,
                               renderedWidthPt: Double,
                               thresholds: GestureThresholds = .init()) -> PressOutcome {
        if movedPt > thresholds.moveSlopPt { return .move }        // drag wins any time
        guard released else { return .pending }
        if elapsedSeconds >= thresholds.longPressSeconds { return .openEditor }
        return renderedWidthPt >= thresholds.minLaunchWidthPt ? .launch : .openEditor
    }
}
