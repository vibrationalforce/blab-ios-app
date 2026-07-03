// PatternEngine.swift
// Echoel — 16-step × 8-track drum sequencer (model + tempo clock).
//
// W1 of v10 sprint: pure pattern model + Timer-driven step trigger.
// W2 will replace the Timer with a sample-accurate AVAudioSourceNode tick
// when SamplerVoice is wired into AudioEngine.

import Foundation
import Observation

/// 16-step × 8-track drum pattern with a tempo-driven trigger.
///
/// The engine owns the pattern grid (`steps`), the transport (`isPlaying`,
/// `currentStep`), and a timer that advances `currentStep` at 16th-note
/// resolution. When a step plays and that cell is `true`, `onStep(track,step)`
/// is called on the main actor — wire that callback to `SamplerVoice` (W2).
///
/// **Timing model:** 4/4 time, 16 steps per bar = 4 sixteenth-notes per beat.
/// Step duration = (60 / BPM) / 4 seconds. At 120 BPM, that's 125 ms.
///
/// **Concurrency:** `@MainActor`. A DispatchSourceTimer fires on the **main
/// queue** and calls `advance()` via `MainActor.assumeIsolated` — same pattern as
/// `AudioEngine.startMeterPollTimer`. The timer must NOT run on a background queue:
/// the Swift-6 executor check would trap (see `scheduleTick`).
@MainActor
@Observable
public final class PatternEngine {

    // MARK: - Constants

    public static let trackCount: Int = 8
    public static let stepCount: Int = 16
    public static let minTempo: Double = 30.0
    public static let maxTempo: Double = 300.0
    public static let defaultTempo: Double = 120.0

    // MARK: - Observed state

    /// 8 tracks × 16 steps. `steps[track][step] == true` means the cell triggers.
    public private(set) var steps: [[Bool]]

    /// Accent grid, parallel to `steps`. An accented active cell hits louder.
    public private(set) var accents: [[Bool]]

    /// Velocity (gain) for a non-accented vs accented hit.
    public static let normalVelocity: Float = 0.82
    public static let accentVelocity: Float = 1.0

    /// Transport state. `true` while the timer is running.
    public private(set) var isPlaying: Bool = false

    /// Current 16th-note position, 0..<stepCount. Resets to 0 on `stop()`.
    public private(set) var currentStep: Int = 0

    /// Beats per minute, clamped to [`minTempo`, `maxTempo`].
    public private(set) var tempo: Double = PatternEngine.defaultTempo

    /// Target tempo for a smooth GLIDE (0 = no glide in flight). When >0, `advance()` eases
    /// `tempo` toward it each tick so a body re-seed slides in instead of jumping ("bpm springt").
    /// Set via `glideTempo(to:)`; any explicit `setTempo` cancels it (an edit is precise/instant).
    @ObservationIgnored private var tempoGlideTarget: Double = 0

    /// Swing amount [0...0.5]. Lengthens the gap before off-beat (odd) 16ths,
    /// shortening the following gap so overall tempo is preserved. 0 = straight.
    public private(set) var swing: Double = 0

    // MARK: - Step-trigger callback

    /// Invoked on the main actor for every active cell at every step boundary.
    /// Wire this to `SamplerVoice.trigger(track:)` once SamplerVoice exists.
    public var onStep: ((_ track: Int, _ step: Int) -> Void)?

    /// Invoked once per step boundary (after drum cells), regardless of content.
    /// A second consumer on the SAME clock — used by the piano roll / melody lane
    /// so drums and melody share one transport (no two-timer drift).
    public var onTick: ((_ step: Int) -> Void)?

    /// Called whenever the transport stops, so the consumer can flush held notes
    /// (release every sounding voice). Centralised here so NO caller can forget
    /// to silence notes on stop and leave a drone ringing.
    public var onStop: (() -> Void)?

    // MARK: - Transport relay (Cycle 1 — zero behaviour change)

    /// The single authoritative musical clock. PatternEngine remains the source of
    /// real-time pulses (it owns the timer); it RELAYS each pulse into `Transport`
    /// so position/tempo/play-state live in one observable place that future
    /// consumers (timeline playhead, MIDI clock, Ableton Link) can all ride. Today
    /// nothing subscribes to Transport — this mirror is additive and audible-no-op;
    /// existing `onStep`/`onTick`/`onStop` stay wired and firing. See
    /// scratchpads/PLAN_TRANSPORT_CLOCK.md. Weak so the app owns Transport's lifetime.
    @ObservationIgnored public weak var transport: Transport?

    // MARK: - Internal

    // A DispatchSourceTimer that fires ON THE MAIN QUEUE. A DispatchSource (vs a
    // RunLoop Timer) still fires while the run loop is in tracking mode — UI
    // scrolling no longer needs `.common` mode to keep the beat — but by targeting
    // the main queue the handler runs on the main thread, where the engine's
    // @MainActor work (model/UI/synth mutation) is valid WITHOUT any cross-thread
    // executor hop. See scheduleTick for why a background queue is fatal here.
    // nonisolated(unsafe) so the nonisolated deinit can cancel it; the source is
    // only mutated on the main actor.
    @ObservationIgnored nonisolated(unsafe) private var timer: DispatchSourceTimer?

    // MARK: - Init

    public init() {
        self.steps = Array(
            repeating: Array(repeating: false, count: PatternEngine.stepCount),
            count: PatternEngine.trackCount
        )
        self.accents = Array(
            repeating: Array(repeating: false, count: PatternEngine.stepCount),
            count: PatternEngine.trackCount
        )
    }

    deinit {
        // Cancel the timer source so its handler closure is released (breaks the
        // retain cycle). DispatchSourceTimer.cancel() is thread-safe, so it's safe
        // from the nonisolated deinit.
        timer?.cancel()
    }

    // MARK: - Pattern editing

    /// Flip a single cell. Out-of-range track/step is a silent no-op.
    public func toggleStep(track: Int, step: Int) {
        guard track >= 0, track < PatternEngine.trackCount else { return }
        guard step >= 0, step < PatternEngine.stepCount else { return }
        steps[track][step].toggle()
    }

    /// Set a single cell explicitly. Out-of-range track/step is a silent no-op.
    public func setStep(track: Int, step: Int, on: Bool) {
        guard track >= 0, track < PatternEngine.trackCount else { return }
        guard step >= 0, step < PatternEngine.stepCount else { return }
        steps[track][step] = on
    }

    /// Toggle the accent flag on a cell. Out-of-range is a silent no-op.
    public func toggleAccent(track: Int, step: Int) {
        guard track >= 0, track < PatternEngine.trackCount else { return }
        guard step >= 0, step < PatternEngine.stepCount else { return }
        accents[track][step].toggle()
    }

    /// Set the accent flag on a cell explicitly. Out-of-range is a silent no-op.
    public func setAccent(track: Int, step: Int, on: Bool) {
        guard track >= 0, track < PatternEngine.trackCount else { return }
        guard step >= 0, step < PatternEngine.stepCount else { return }
        accents[track][step] = on
    }

    /// Velocity (gain) for a cell: accent → loud, active → grooved, off → 0.
    ///
    /// Non-accented hits used to fire at one flat `normalVelocity` (0.82), the textbook
    /// "machine-gun hats" tell — every 16th identical. Instead we apply a deterministic
    /// GROOVE curve: a metric weighting (downbeat > 8th > 16th) plus a small (±6%) seeded
    /// jitter keyed on (track, step) so hats/percussion breathe like a human player without
    /// ever wandering. Accents stay exactly 1.0, so drawn accents are untouched. Pure +
    /// deterministic (same grid → same groove), so it's fully unit-testable.
    public func velocity(track: Int, step: Int) -> Float {
        guard track >= 0, track < PatternEngine.trackCount,
              step >= 0, step < PatternEngine.stepCount,
              steps[track][step] else { return 0 }
        if accents[track][step] { return PatternEngine.accentVelocity }
        return PatternEngine.groovedVelocity(track: track, step: step)
    }

    /// Deterministic groove velocity for a non-accented active cell. Metric emphasis:
    /// downbeats (÷4) loudest, backbeat 8ths (÷2) mid, off-16ths softest (ghosted); a
    /// bounded ±6% hash jitter adds micro-humanity. Centered on `normalVelocity`.
    static func groovedVelocity(track: Int, step: Int) -> Float {
        let base = normalVelocity
        // Metric weight: on-beat > 8th > 16th. Small spans keep the existing feel.
        let metric: Float
        if step % 4 == 0      { metric =  0.10 }   // downbeat — push
        else if step % 2 == 0 { metric =  0.02 }   // 8th — slight
        else                  { metric = -0.10 }   // off-16th — ghost
        // Deterministic bounded jitter in [-0.06, 0.06] from a cheap (track,step) hash.
        let h = (UInt32(bitPattern: Int32(step &* 73 &+ track &* 19 &+ 1)) &* 2654435761) >> 8
        let jitter = (Float(h % 1000) / 1000.0 - 0.5) * 0.12   // ±0.06
        let v = base + metric + jitter
        return Swift.min(0.98, Swift.max(0.35, v))             // stay below accent, audible floor
    }

    /// Set the swing amount, clamped to [0, 0.5].
    public func setSwing(_ amount: Double) {
        swing = Swift.min(Swift.max(amount, 0), 0.5)
        transport?.setSwing(swing)
    }

    /// Replace the whole grid (steps + accents), e.g. when launching a clip.
    /// Mismatched dimensions are ignored per-track so a bad clip can't crash.
    public func load(steps newSteps: [[Bool]], accents newAccents: [[Bool]]) {
        guard newSteps.count == PatternEngine.trackCount,
              newAccents.count == PatternEngine.trackCount else { return }
        for t in 0..<PatternEngine.trackCount {
            guard newSteps[t].count == PatternEngine.stepCount,
                  newAccents[t].count == PatternEngine.stepCount else { continue }
            steps[t] = newSteps[t]
            accents[t] = newAccents[t]
        }
    }

    /// Turn every cell off (steps + accents) without changing transport state.
    public func clear() {
        for t in 0..<PatternEngine.trackCount {
            for s in 0..<PatternEngine.stepCount {
                steps[t][s] = false
                accents[t][s] = false
            }
        }
    }

    // MARK: - Transport

    /// Set tempo in BPM. Values outside [minTempo, maxTempo] are clamped.
    /// If the engine is playing, the timer restarts at the new interval.
    public func setTempo(_ bpm: Double) {
        let clamped = Swift.min(Swift.max(bpm, PatternEngine.minTempo), PatternEngine.maxTempo)
        tempoGlideTarget = 0   // an explicit edit is precise + instant → cancel any in-flight glide
        // Relay to the authoritative Transport FIRST, before the no-op early return below.
        // If Transport.tempo ever diverged (a write before the relay was wired, or a direct
        // Transport edit), a subsequent same-value setTempo must still re-sync the displayed
        // value — otherwise the transport bar keeps showing a stale tempo forever.
        transport?.setTempo(clamped)
        guard clamped != tempo else { return }
        tempo = clamped
        // Re-arm at the new rate if playing, otherwise the already-scheduled tick
        // would still fire at the OLD interval (one lagged step after a tempo
        // change / regenerate). scheduleTick invalidates the old timer first.
        if isPlaying {
            let base = 60.0 / tempo / 4.0
            let s = Swift.min(Swift.max(swing, 0), 0.5)
            scheduleTick(after: (currentStep % 2 == 0) ? base * (1 + s) : base * (1 - s))
        }
    }

    /// Smoothly GLIDE the tempo to `bpm` over ~2 s instead of snapping — used when the body
    /// re-seeds the take tempo, so the beat eases into the new pulse rather than jumping
    /// ("bpm springt"). `advance()` does the per-tick easing. When stopped there are no ticks
    /// to glide on, so it snaps immediately. User/transport edits keep using `setTempo`
    /// (instant + precise). Values are clamped to [minTempo, maxTempo].
    public func glideTempo(to bpm: Double) {
        let clamped = Swift.min(Swift.max(bpm, PatternEngine.minTempo), PatternEngine.maxTempo)
        guard isPlaying else { setTempo(clamped); return }
        tempoGlideTarget = clamped
    }

    /// Start the timer from step 0. Idempotent: calling while playing is a no-op.
    public func play() {
        guard !isPlaying else { return }
        isPlaying = true
        currentStep = 0
        transport?.play()
        scheduleTick(after: 60.0 / tempo / 4.0)
    }

    /// Stop the timer and reset `currentStep` to 0. Safe to call while stopped.
    public func stop() {
        timer?.cancel()
        timer = nil
        currentStep = 0
        isPlaying = false
        tempoGlideTarget = 0   // drop any in-flight glide so the next take starts clean
        transport?.stop()
        onStop?()   // flush held notes so nothing drones after stop
    }

    // MARK: - Timer (self-rescheduling, swing-aware)

    /// Schedules one tick after `interval`. Re-armed by `advance()` so each gap
    /// can carry a different (swing) duration.
    ///
    /// Uses a DispatchSourceTimer **on the main queue** with zero leeway: it fires
    /// precisely on time and, unlike a RunLoop Timer, keeps firing while the run
    /// loop is in tracking mode (UI scrolling no longer starves it — the reason
    /// the old Timer needed `.common` mode). The handler runs on the main thread,
    /// so `MainActor.assumeIsolated` recovers the static isolation needed to mutate
    /// model/UI/synth state — exactly the proven `AudioEngine.startMeterPollTimer`
    /// pattern.
    ///
    /// iOS 18 / Swift 6 NOTE — DO NOT move this timer to a background queue.
    /// Both `MainActor.assumeIsolated` AND `Task { @MainActor in }` HARD-TRAP
    /// (`dispatch_assert_queue_fail` → SIGTRAP) when the handler runs on a
    /// background dispatch worker under the strict Swift-6 executor: the runtime's
    /// isolation check asserts it is literally on the main queue and aborts when it
    /// isn't. (Builds 1769/1777 crashed exactly here — first with `assumeIsolated`,
    /// then with `Task`.) The only crash-safe options from a non-main thread are
    /// `DispatchQueue.main.async { … }` or, as here, firing on `.main` directly.
    private func scheduleTick(after interval: TimeInterval) {
        timer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + interval, leeway: .nanoseconds(0))
        t.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.advance() }
        }
        t.resume()
        timer = t
    }

    // DIAG (temporary): one-shot breadcrumb confirming the first tick fired on the
    // main thread without the Swift-6 executor trap. Remove once build 1777's
    // beat-clock SIGTRAP is confirmed resolved on device.
    @ObservationIgnored private var didLogFirstTick = false

    private func advance() {
        if !didLogFirstTick {
            didLogFirstTick = true
            EchoelCrashLog.breadcrumb("pattern: first tick OK (main-queue timer)")
        }
        // A timer block already dispatched to main can arrive AFTER stop()/setTempo
        // cancelled the source. Bail before firing so no ghost step/note sounds
        // once the transport is stopped (the spurious step-0 hit after Stop).
        guard isPlaying else { return }

        let step = currentStep
        // Relay this pulse into the authoritative clock FIRST, so any Transport
        // subscriber sees the new position before the legacy onStep/onTick consumers
        // act on it (priority ordering lives in Transport). Zero-cost when unwired.
        transport?.tick(step: step)
        for track in 0..<PatternEngine.trackCount {
            if steps[track][step] {
                onStep?(track, step)
            }
        }
        onTick?(step)
        currentStep = (step + 1) % PatternEngine.stepCount

        // Ease the tempo toward a body-seeded glide target so a re-seed SLIDES in instead of
        // jumping ("bpm springt"). One-pole (~0.15/tick → ~2 s settle); snaps + clears when
        // within 0.5 bpm. Relay each step so the transport bar / click glide in lockstep.
        if tempoGlideTarget > 0 {
            let diff = tempoGlideTarget - tempo
            if abs(diff) <= 0.5 {
                tempo = tempoGlideTarget
                tempoGlideTarget = 0
            } else {
                tempo += diff * 0.15
            }
            transport?.setTempo(tempo)
        }

        // Gap to the NEXT step. Swing lengthens the gap that follows a downbeat
        // (even step), delaying the off-beat; the following gap shortens to keep
        // each beat-pair the same total length (tempo preserved).
        let base = 60.0 / tempo / 4.0
        let s = Swift.min(Swift.max(swing, 0), 0.5)
        let interval = (step % 2 == 0) ? base * (1 + s) : base * (1 - s)
        scheduleTick(after: interval)
    }
}
