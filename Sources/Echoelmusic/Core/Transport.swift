// Transport.swift
// Echoel — the single authoritative musical clock for the whole DMW.
//
// Today time lives inside PatternEngine (it owns the timer + currentStep). As
// Echoel grows into a full production environment (arrangement, video playhead,
// MIDI clock, Ableton Link, broadcast), every domain must ride ONE clock or they
// drift. Transport is that clock's CONTROL PLANE: a pure, observable, fully
// unit-testable position + tempo model that anything can subscribe to.
//
// It does NOT own a hardware timer — PatternEngine keeps driving real time and RELAYS
// into Transport on every tempo, swing, step, play and stop. The "nothing wires it;
// zero behaviour change" note that stood here was true only for the first cycle: this
// type is now the single source that the metronome (EchoelmusicApp: onTempoChange),
// the haptic pulse and the stop-subscribers ride on.
//
// CONSEQUENCE for anyone adding a tempo path: it MUST relay here. A tempo that moves
// the sequencer without reaching Transport leaves the click behind — that was the
// actual bug behind "Metronom folgt nicht dem bio/automatisierten Tempo".

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

    /// Seconds of ONE step (a 16th) at `bpm`, and therefore the gap between `play()` and the
    /// moment step 0 SOUNDS.
    ///
    /// ⚠️ It is the BASE of the inter-tick gap, not the gap itself: `PatternEngine` feeds it
    /// to `swingGap(afterStep:base:swing:)`, which lengthens the gap after an even step and
    /// shortens the next one. The two are equal only while `swing == 0` — which is every
    /// shipping path today (#278), but writing "the gap between ticks" would make this doc
    /// false the day swing returns, in the file the timing is read from.
    ///
    /// ⭐ WHY THIS IS A SHARED STATIC AND NOT A FOURTH COPY OF `60.0 / tempo / 4.0`
    /// (#300 Nachlese). `play()` below fans out to `playSubs` IMMEDIATELY, but
    /// `PatternEngine.play()` then schedules its first `advance()` one whole step later —
    /// `play()`'s own comment explains why that asymmetry is deliberate and load-bearing
    /// for `TouchQuantizer`. Anything that must line up with the FIRST AUDIBLE STEP rather
    /// than with the play edge has to wait exactly this long, and the MIDI clock is the
    /// first such subscriber: emitting Start (0xFA) on the play edge put a slaved DAW's
    /// bar 1 one 16th (125 ms at 120 bpm) ahead of Echoel's, permanently, from the first
    /// bar. Two independently-maintained copies of the formula would let that gap silently
    /// reopen, so the sequencer and the clock read it from here.
    ///
    /// Non-optional on purpose: both callers schedule a timer with the result, and an
    /// optional would push a `??` fallback (or a banned force-unwrap) into two scheduling
    /// paths. The tempo is clamped to `[minTempo, maxTempo]` with the NaN-safe
    /// `clamped(to:)` first — exactly what `PatternEngine.setTempo` and `Transport.setTempo`
    /// already do to every tempo that reaches them — so a non-finite input becomes the
    /// slowest legal step (0.5 s at 30 bpm), never an undefined scheduler deadline.
    public nonisolated static func stepDuration(atTempo bpm: Double) -> TimeInterval {
        60.0 / bpm.clamped(to: minTempo...maxTempo) / Double(stepsPerBeat)
    }

    // MARK: - Observed control-plane state

    public private(set) var isPlaying = false
    public private(set) var position = TransportPosition.zero
    public private(set) var tempo: Double = Transport.defaultTempo
    public private(set) var swing: Double = 0
    /// Who drives the clock. Reserved for MIDI-clock / Ableton Link follow modes.
    public var clockSource: TransportClockSource = .internal

    /// Wall-clock stamp (`CFAbsoluteTime`) of the most recent step boundary — the
    /// anchor `currentTick(at:)` interpolates from. `0` means "no valid stamp"
    /// (stopped, or no step has fired yet).
    ///
    /// `@ObservationIgnored` because this changes at the step rate (~8 Hz at 120 BPM)
    /// and nothing should be able to bind a view to it. To be exact about what that
    /// buys, since the first version of this comment overclaimed: it does NOT make
    /// `currentTick(at:)` safe to call from a body. That method also reads `position`,
    /// which IS observed and is written in the same statement block as this stamp — so
    /// the freeze risk lives there, and the warning that matters is on the method.
    @ObservationIgnored public private(set) var lastStepAt: CFAbsoluteTime = 0

    // MARK: - Subscribers

    /// A step subscriber + its fire priority. Lower priority fires FIRST — this is
    /// load-bearing: the arrangement (loads the next section's clip) must run
    /// before the piano roll triggers that bar's notes. Explicit priority replaces
    /// the old single-slot `onTick`, which forced a fixed two-consumer order.
    private struct StepSub { let id: String; let priority: Int; let cb: (TransportPosition) -> Void }
    @ObservationIgnored private var stepSubs: [StepSub] = []
    @ObservationIgnored private var stopSubs: [String: () -> Void] = [:]
    /// Play-edge subscribers (#300). See `addPlaySubscriber` for why stop had one first.
    @ObservationIgnored private var playSubs: [String: () -> Void] = [:]
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
        // Note the deliberate asymmetry: a same-value write re-syncs MIRRORS of this
        // property but does NOT re-heal a subscriber that drifted out of band. That is
        // sound only because nothing else writes what a subscriber owns — the click's
        // BPM has exactly one writer, this list. Any future subscriber must keep that
        // property, or this gate has to go.
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
        // DELIBERATELY NOT STAMPED — and this is load-bearing, not an omission.
        // `PatternEngine.play()` calls us and then schedules its FIRST `advance()` a
        // whole step later, which relays `tick(step: 0)` — step 0 again. Stamping here
        // would anchor step 0 at play-time and then re-anchor it 125 ms later, so a
        // touch just before that second stamp read tick 119 and one just after read
        // tick 0: the clock RAN BACKWARDS by a full step. `TouchQuantizer` is built
        // entirely on "a live note can never be moved earlier", so that would have
        // reordered two consecutive touches. It is also simply the wrong instant —
        // step 0's notes SOUND at that first `advance()`, not at play-time, so the
        // tick clock now agrees with what the player hears.
        // Until then `currentTick(at:)` returns nil, which its contract already
        // defines as "sound it now, uncorrected".
        lastStepAt = 0
        isPlaying = true
        for cb in playSubs.values { cb() }
    }

    public func stop() {
        isPlaying = false
        position = .zero
        lastStep = 0
        lastStepAt = 0          // no grid while stopped — see `currentTick(at:)`
        for cb in stopSubs.values { cb() }
    }

    /// Jump to a position without changing play state (arrangement / loop seek).
    public func seek(toBar bar: Int, step: Int = 0) {
        let s = Swift.min(Swift.max(step, 0), Self.stepsPerBar - 1)
        position = TransportPosition(bar: bar, step: s)
        lastStep = s
        // Re-anchor, unconditionally. Without it the interpolation would keep measuring
        // from the step boundary BEFORE the jump — a position that no longer exists.
        // The `if isPlaying` this once carried bought nothing (`currentTick` already
        // guards on `isPlaying`) and cost consistency: `tick(step:)` stamps whether or
        // not the clock runs, so the conditional was the one writer that could leave the
        // anchor describing a different position than `position` does.
        // (No production caller today — `seek` is exercised only by tests.)
        lastStepAt = CFAbsoluteTimeGetCurrent()
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
        // Stamped BEFORE the fan-out so a subscriber that asks for `currentTick(at:)`
        // inside its own callback measures from THIS step, not the previous one.
        lastStepAt = CFAbsoluteTimeGetCurrent()
        for sub in stepSubs { sub.cb(position) }
    }

    /// The song-absolute 480-PPQ tick the transport is at RIGHT NOW, interpolated
    /// between step boundaries.
    ///
    /// This exists because `position` moves once per sixteenth. A live touch needs to
    /// know how far PAST the last grid point the finger landed; fed the step position
    /// alone, `TouchQuantizer` would see every touch as already perfectly on the grid
    /// and never correct anything.
    ///
    /// Returns `nil` when there is no grid: stopped, or nothing stamped yet. A caller
    /// MUST read that as "sound it now, uncorrected" — holding notes back against a
    /// beat the player cannot hear is worse than not quantizing at all.
    ///
    /// ⚠️ Reads `position` and `tempo`, which ARE observed. Call it from a touch
    /// handler, a timer or a subscriber callback — NEVER from a SwiftUI `body` or from
    /// a computed var a body evaluates, or that body becomes an ~8 Hz observer and
    /// every open `.menu` Picker popover is torn down under the finger.
    ///
    /// SWING IS NOT MODELLED, AND UNDER SWING THIS CLOCK IS WRONG ENOUGH TO MATTER.
    /// `PatternEngine.swingGap` makes an even step last `base × (1 + swing)` and the
    /// following odd step `base × (1 − swing)`; this map assumes both last the nominal
    /// `60 / bpm / 4`. `MusicStyle.swing` ships real values — jazz 0.34, rock'n'roll
    /// 0.28, rocksteady 0.22, klezmer 0.20, ska 0.18, vaporwave 0.15, disco 0.14,
    /// trap 0.12 — so at jazz/120 BPM the LONG step lasts 167.5 ms and everything after
    /// its first 125 ms reads as the same last tick, while the SHORT step lasts 82.5 ms
    /// and ticks 80…119 of it are unreachable: a ~40-tick / ~42 ms error, not the "well
    /// under one tick" an earlier version of this comment claimed.
    ///
    /// The consequence is specific, which is why it is spelled out rather than hedged:
    /// `TouchQuantizer.latenessToleranceTicks` is 12, and on a short swung step this
    /// clock UNDERSTATES lateness by up to a third — a touch 18 ticks late reads as 12
    /// and falls inside the tolerance, so the echo silently does not fire. The two
    /// halves of every swung pair are therefore judged by different rules. Separately,
    /// only the grids that tile a step (`.sixteenth`, `.eighth`, `.quarter`) land on
    /// real boundaries at all; the triplet grids never do.
    ///
    /// The correct fix is a swung grid on BOTH sides (clock and quantizer). No caller
    /// needs it yet, so it is written down instead of guessed at.
    public func currentTick(at now: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()) -> Int? {
        guard isPlaying, lastStepAt > 0 else { return nil }
        return StepTickMath.tick(absoluteStep: position.absoluteStep,
                                 secondsSinceStep: now - lastStepAt,
                                 bpm: tempo)
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

    /// Subscribe to transport PLAY.
    ///
    /// ⚠️ WHY THIS DID NOT EXIST UNTIL #300, because the asymmetry is the interesting part:
    /// stop needs a broadcast (every held note must be released, from anywhere), whereas
    /// everything that had to ACT on play was already downstream of `PatternEngine.play()`,
    /// which calls this and then drives its own tick. MIDI Clock is the first subscriber that
    /// must LEARN of play and is NOT on the tick path — a clock master sends Start (0xFA)
    /// once, before the first pulse, and there is no step to hang that on.
    ///
    /// ⚠️ "LEARN OF", NOT "EMIT AT". The first version of this sentence said the subscriber
    /// must emit *at the instant of play*, and that reading is what put MIDI Start one 16th
    /// early. This edge is when the transport DECIDES to play; step 0 SOUNDS one step later
    /// (see `play()` and `stepDuration(atTempo:)`). A subscriber that has to line up with the
    /// music, rather than with the decision, must delay itself by that step.
    ///
    /// Unlike `addStepSubscriber` there is no priority: play is a single edge, and inventing
    /// an ordering nobody needs would be a second thing to get wrong.
    public func addPlaySubscriber(_ id: String, _ cb: @escaping () -> Void) {
        playSubs[id] = cb
    }

    /// Remove every subscription registered under `id` — step, stop, play AND tempo.
    /// Tempo is included deliberately: a caller doing the obvious teardown would
    /// otherwise leak its tempo callback, since that one has its own remover. Play was
    /// added with #300 for the same reason — a new list that this method does not clear is
    /// a leak nobody notices until a stale callback fires against a dead object.
    public func removeSubscriber(_ id: String) {
        stepSubs.removeAll { $0.id == id }
        stopSubs[id] = nil
        playSubs[id] = nil
        tempoSubs[id] = nil
    }
}
