// Transport.swift
// Echoel — the single authoritative musical clock for the whole DMW.
//
// Today time lives inside PatternEngine (it owns the timer + currentStep). As
// Echoel grows into a full production environment (arrangement, video playhead,
// MIDI clock, Ableton Link, broadcast), every domain must ride ONE clock or they
// drift. Transport is that clock's CONTROL PLANE: a pure, observable, fully
// unit-testable position + tempo model that anything can subscribe to.
//
// It does NOT own a hardware timer yet — PatternEngine keeps driving real time and
// will relay into Transport in a later cycle. This type is introduced ADDITIVELY
// first (nothing wires it; zero behaviour change) so it is proven in isolation
// before the sequencer/arrangement/video/clock consumers migrate onto it, one
// CI-green cycle at a time. See scratchpads/PLAN_TRANSPORT_CLOCK.md.

import Foundation
import Observation

/// Where the beat comes from. `.internal` = our own timer (today). `.midi` and
/// `.link` are reserved so an external DAW (MIDI clock) or networked peers
/// (Ableton Link) can drive the SAME Transport without any subscriber changing.
public enum TransportClockSource: String, Sendable, Codable {
    case `internal`, midi, link
}

/// A point in musical time. 4/4, 16 steps per bar (4 sixteenths per beat), 24
/// pulses-per-quarter (1 step = 6 ppq pulses, 96 per bar) — mirrors PatternEngine.
/// Every derived field is computed from `bar` + `step` so they can never disagree.
public struct TransportPosition: Equatable, Sendable, Codable {
    /// 0-based bar index since the last play()/seek.
    public var bar: Int
    /// 16th-note within the bar, 0..<stepsPerBar.
    public var step: Int

    public init(bar: Int = 0, step: Int = 0) {
        self.bar = max(0, bar)
        self.step = max(0, step)
    }

    public static let zero = TransportPosition(bar: 0, step: 0)

    /// Beat within the bar, 0..<beatsPerBar (4 steps = 1 beat).
    public var beat: Int { step / Transport.stepsPerBeat }
    /// Pulses-per-quarter tick within the bar (24 ppq → 6 per step).
    public var ppqTick: Int { step * Transport.ppqPerStep }
    /// Absolute step count since play() (`bar * 16 + step`) — handy for scheduling.
    public var absoluteStep: Int { bar * Transport.stepsPerBar + step }
}

@MainActor
@Observable
public final class Transport {

    // MARK: - Time model (mirrors PatternEngine: 4/4, 16 steps/bar)
    // `nonisolated` so the Sendable TransportPosition struct (and any nonisolated
    // context) can read these immutable constants without crossing actor isolation.

    public nonisolated static let stepsPerBar = 16
    public nonisolated static let beatsPerBar = 4
    public nonisolated static let stepsPerBeat = stepsPerBar / beatsPerBar    // 4
    public nonisolated static let ppqResolution = 24                          // pulses per quarter
    public nonisolated static let ppqPerStep = ppqResolution / stepsPerBeat   // 6
    public nonisolated static let minTempo: Double = 30.0
    public nonisolated static let maxTempo: Double = 300.0
    public nonisolated static let defaultTempo: Double = 120.0

    // MARK: - Observed control-plane state

    public private(set) var isPlaying = false
    public private(set) var position = TransportPosition.zero
    public private(set) var tempo: Double = Transport.defaultTempo
    public private(set) var swing: Double = 0
    /// Who drives the clock. Reserved for MIDI-clock / Ableton Link follow modes.
    public var clockSource: TransportClockSource = .internal

    // MARK: - Subscribers

    /// A step subscriber + its fire priority. Lower priority fires FIRST — this is
    /// load-bearing: the arrangement (loads the next section's clip) must run
    /// before the piano roll triggers that bar's notes. Explicit priority replaces
    /// the old single-slot `onTick`, which forced a fixed two-consumer order.
    private struct StepSub { let id: String; let priority: Int; let cb: (TransportPosition) -> Void }
    @ObservationIgnored private var stepSubs: [StepSub] = []
    @ObservationIgnored private var stopSubs: [String: () -> Void] = [:]
    @ObservationIgnored private var tempoSubs: [String: (Double) -> Void] = [:]
    @ObservationIgnored private var lastStep = 0

    public init() {}

    // MARK: - Tempo / swing (clamped exactly like PatternEngine)

    /// Set the musical tempo. Clamped to [minTempo, maxTempo] and relayed to every
    /// tempo subscriber when the value actually moves.
    ///
    /// The clamp is NaN-safe: `Swift.min(Swift.max(bpm, lo), hi)` — the form this used
    /// to have — passes NaN through BOTH clamps, because every comparison against NaN
    /// is false. This type owns no timer, so a NaN here does not stop anything by
    /// itself; it poisons the value every subscriber and readout mirrors. (The timer
    /// lives in `PatternEngine`, which computes `60.0 / tempo / 4.0` and is clamped
    /// the same way for that harder reason.)
    public func setTempo(_ bpm: Double) {
        let clamped = bpm.clamped(to: Self.minTempo...Self.maxTempo)
        let moved = clamped != tempo
        tempo = clamped
        // Assigned unconditionally (an @Observable write is how a same-value re-sync
        // reaches the UI — PatternEngine.setTempo relies on exactly that), but
        // subscribers fire only on a real move: the stopped-glide timer relays at
        // ~20 Hz and settles on one value, and re-notifying would make every
        // subscriber recompute for nothing.
        if moved {
            for cb in tempoSubs.values { cb(clamped) }
        }
    }

    /// Subscribe to tempo changes. The callback fires IMMEDIATELY with the current
    /// tempo, then on every subsequent change.
    ///
    /// The immediate seed is not a convenience — without it a subscriber registering
    /// mid-session keeps its own stale tempo until someone happens to move the
    /// clock, which is the very bug this exists to fix. Re-registering the same `id`
    /// replaces the previous callback.
    ///
    /// WHY THIS EXISTS: the metronome used to be PUSHED its tempo from ~6 scattered UI
    /// call sites, which failed in BOTH directions. Paths that touched no call site left
    /// the click BEHIND — parameter automation (`AutomationPlayer` `.tempo`) and the
    /// Body→Tempo modulation route moved the sequencer with the click still at the old
    /// rate. And two of the call sites ran the click AHEAD: both sat right after
    /// `PatternEngine.glideTempo`, which eases over ~2 s, so the click jumped to the
    /// glide TARGET while the sequencer was still on its way — every intermediate value
    /// of the ease was a click/sequencer mismatch. Anything that shows or sounds the
    /// tempo should subscribe here rather than keep a copy.
    public func onTempoChange(id: String, _ callback: @escaping (Double) -> Void) {
        tempoSubs[id] = callback
        callback(tempo)
    }

    public func removeTempoSubscriber(id: String) {
        tempoSubs[id] = nil
    }

    public func setSwing(_ amount: Double) {
        swing = Swift.min(Swift.max(amount, 0), 0.5)
    }

    // MARK: - Transport

    public func play() {
        position = .zero
        lastStep = 0
        isPlaying = true
    }

    public func stop() {
        isPlaying = false
        position = .zero
        lastStep = 0
        for cb in stopSubs.values { cb() }
    }

    /// Jump to a position without changing play state (arrangement / loop seek).
    public func seek(toBar bar: Int, step: Int = 0) {
        let s = Swift.min(Swift.max(step, 0), Self.stepsPerBar - 1)
        position = TransportPosition(bar: bar, step: s)
        lastStep = s
    }

    // MARK: - Tick

    /// Advance to `step` (0..<stepsPerBar) of the current bar. A wrap back to 0
    /// from a non-zero step increments the bar — the same 15→0 boundary the
    /// sequencer + ArrangementPlayer already use. Notifies step subscribers in
    /// priority order. Driven externally today (PatternEngine will relay here).
    public func tick(step: Int) {
        let s = ((step % Self.stepsPerBar) + Self.stepsPerBar) % Self.stepsPerBar
        var bar = position.bar
        if s == 0 && lastStep != 0 { bar += 1 }
        position = TransportPosition(bar: bar, step: s)
        lastStep = s
        for sub in stepSubs { sub.cb(position) }
    }

    // MARK: - Subscription

    /// Subscribe to every step boundary. `priority` orders firing (lower first);
    /// re-adding the same `id` replaces the previous registration.
    public func addStepSubscriber(_ id: String, priority: Int = 0, _ cb: @escaping (TransportPosition) -> Void) {
        stepSubs.removeAll { $0.id == id }
        stepSubs.append(StepSub(id: id, priority: priority, cb: cb))
        stepSubs.sort { $0.priority < $1.priority }
    }

    /// Subscribe to transport stop (flush held notes, etc.).
    public func addStopSubscriber(_ id: String, _ cb: @escaping () -> Void) {
        stopSubs[id] = cb
    }

    /// Remove every subscription registered under `id` — step, stop AND tempo.
    /// Tempo is included deliberately: a caller doing the obvious teardown would
    /// otherwise leak its tempo callback, since that one has its own remover.
    public func removeSubscriber(_ id: String) {
        stepSubs.removeAll { $0.id == id }
        stopSubs[id] = nil
        tempoSubs[id] = nil
    }
}
