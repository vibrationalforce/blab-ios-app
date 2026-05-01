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

    /// Transport state. `true` while the timer is running.
    public private(set) var isPlaying: Bool = false

    /// Current 16th-note position, 0..<stepCount. Resets to 0 on `stop()`.
    public private(set) var currentStep: Int = 0

    /// Beats per minute, clamped to [`minTempo`, `maxTempo`].
    public private(set) var tempo: Double = PatternEngine.defaultTempo

    // MARK: - Step-trigger callback

    /// Invoked on the main actor for every active cell at every step boundary.
    /// Wire this to `SamplerVoice.trigger(track:)` once SamplerVoice exists.
    public var onStep: ((_ track: Int, _ step: Int) -> Void)?

    // MARK: - Internal

    @ObservationIgnored private var timer: Timer?

    // MARK: - Init

    public init() {
        self.steps = Array(
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

    /// Turn every cell off without changing transport state.
    public func clear() {
        for t in 0..<PatternEngine.trackCount {
            for s in 0..<PatternEngine.stepCount {
                steps[t][s] = false
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
        if isPlaying { restartTimer() }
    }

    /// Start the timer from step 0. Idempotent: calling while playing is a no-op.
    public func play() {
        guard !isPlaying else { return }
        isPlaying = true
        currentStep = 0
        startTimer()
    }

    /// Stop the timer and reset `currentStep` to 0. Safe to call while stopped.
    public func stop() {
        timer?.invalidate()
        timer = nil
        currentStep = 0
        isPlaying = false
    }

    // MARK: - Timer

    /// Duration of one 16th note at the current tempo.
    private var stepIntervalSeconds: TimeInterval {
        // 60 sec/min / BPM = beat duration; / 4 = 16th-note duration
        60.0 / tempo / 4.0
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(
            withTimeInterval: stepIntervalSeconds,
            repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.advance()
            }
        }
    }

    private func restartTimer() {
        timer?.invalidate()
        timer = nil
        if isPlaying { startTimer() }
    }

    private func advance() {
        let step = currentStep
        for track in 0..<PatternEngine.trackCount {
            if steps[track][step] {
                onStep?(track, step)
            }
        }
        currentStep = (currentStep + 1) % PatternEngine.stepCount
    }
}
