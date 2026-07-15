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
    @ObservationIgnored private var lastStep = 0

    /// H9b: the lock-free mirror hosted AUv3 plugins read their musical
    /// context from (render-thread readers — see HostMusicalState). nil by
    /// default so Transport stays pure in unit tests; the app wires `.shared`.
    /// Written on every state change below — Transport is the ONE clock, so
    /// this is the one write point.
    @ObservationIgnored public var hostStateMirror: HostMusicalState?

    public init() {}

    /// Push the current control-plane state into the host mirror (call after
    /// every mutation — cheap plain stores).
    private func syncHostMirror() {
        guard let m = hostStateMirror else { return }
        m.tempo = tempo
        m.isPlaying = isPlaying
        m.beatPosition = HostBeatMath.beats(fromAbsoluteStep: position.absoluteStep,
                                            stepsPerBeat: Self.stepsPerBeat)
    }

    // MARK: - Tempo / swing (clamped exactly like PatternEngine)

    public func setTempo(_ bpm: Double) {
        tempo = Swift.min(Swift.max(bpm, Self.minTempo), Self.maxTempo)
        syncHostMirror()
    }

    public func setSwing(_ amount: Double) {
        swing = Swift.min(Swift.max(amount, 0), 0.5)
    }

    // MARK: - Transport

    public func play() {
        position = .zero
        lastStep = 0
        isPlaying = true
        syncHostMirror()
    }

    public func stop() {
        isPlaying = false
        position = .zero
        lastStep = 0
        syncHostMirror()
        for cb in stopSubs.values { cb() }
    }

    /// Jump to a position without changing play state (arrangement / loop seek).
    public func seek(toBar bar: Int, step: Int = 0) {
        let s = Swift.min(Swift.max(step, 0), Self.stepsPerBar - 1)
        position = TransportPosition(bar: bar, step: s)
        lastStep = s
        syncHostMirror()
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
        syncHostMirror()
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

    public func removeSubscriber(_ id: String) {
        stepSubs.removeAll { $0.id == id }
        stopSubs[id] = nil
    }
}
