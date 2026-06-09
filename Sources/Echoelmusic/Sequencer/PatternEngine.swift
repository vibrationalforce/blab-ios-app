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
/// **Concurrency:** `@MainActor`. The timer fires on the main run loop and
/// calls `advance()` via `MainActor.assumeIsolated` — same pattern as
/// `AudioEngine.startMeterPollTimer`.
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

    // MARK: - Internal

    // nonisolated(unsafe) so the deinit (which is nonisolated by default)
    // can call .invalidate() on a non-Sendable Timer. Same pattern as
    // AudioEngine.meterPollTimer.
    @ObservationIgnored nonisolated(unsafe) private var timer: Timer?

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
        // Timer holds a strong reference to its closure; invalidating breaks
        // the cycle. deinit runs on whatever actor releases the last ref —
        // Timer.invalidate is thread-safe.
        timer?.invalidate()
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

    /// Velocity (gain) for a cell: accent → loud, active → normal, off → 0.
    public func velocity(track: Int, step: Int) -> Float {
        guard track >= 0, track < PatternEngine.trackCount,
              step >= 0, step < PatternEngine.stepCount,
              steps[track][step] else { return 0 }
        return accents[track][step] ? PatternEngine.accentVelocity : PatternEngine.normalVelocity
    }

    /// Set the swing amount, clamped to [0, 0.5].
    public func setSwing(_ amount: Double) {
        swing = Swift.min(Swift.max(amount, 0), 0.5)
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
        guard clamped != tempo else { return }
        tempo = clamped
        // The next scheduled tick reads `tempo` fresh, so no restart needed.
    }

    /// Start the timer from step 0. Idempotent: calling while playing is a no-op.
    public func play() {
        guard !isPlaying else { return }
        isPlaying = true
        currentStep = 0
        scheduleTick(after: 60.0 / tempo / 4.0)
    }

    /// Stop the timer and reset `currentStep` to 0. Safe to call while stopped.
    public func stop() {
        timer?.invalidate()
        timer = nil
        currentStep = 0
        isPlaying = false
    }

    // MARK: - Timer (self-rescheduling, swing-aware)

    /// Schedules one non-repeating tick. Re-armed by `advance()` so each gap
    /// can carry a different (swing) duration.
    private func scheduleTick(after interval: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.advance()
            }
        }
    }

    private func advance() {
        let step = currentStep
        for track in 0..<PatternEngine.trackCount {
            if steps[track][step] {
                onStep?(track, step)
            }
        }
        onTick?(step)
        currentStep = (step + 1) % PatternEngine.stepCount

        guard isPlaying else { return }
        // Gap to the NEXT step. Swing lengthens the gap that follows a downbeat
        // (even step), delaying the off-beat; the following gap shortens to keep
        // each beat-pair the same total length (tempo preserved).
        let base = 60.0 / tempo / 4.0
        let s = Swift.min(Swift.max(swing, 0), 0.5)
        let interval = (step % 2 == 0) ? base * (1 + s) : base * (1 - s)
        scheduleTick(after: interval)
    }
}
