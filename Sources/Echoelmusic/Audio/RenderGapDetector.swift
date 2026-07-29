//
//  RenderGapDetector.swift
//  Echoelmusic — Audio
//
//  Turns "es knistert" into a number (#193).
//
//  WHY THIS EXISTS. The founder hears crackling and described it precisely: "Wie CPU
//  overload bei Ableton oder so". Two cycles have already responded by REDUCING LOAD —
//  the display FPS pin to 60 (v10.79.129), the gating of the expensive true-peak/EBU
//  metering behind `_detailedMetering` — and it is still reported. Both were guesses in
//  the right direction, and neither could be confirmed or refuted, because nothing in
//  this app measures whether the audio path is actually missing its deadline. The task
//  entry for #193 says it in as many words: find the source, do not guess.
//
//  WHAT IT MEASURES, stated narrowly because a proxy sold as a dropout counter would be
//  worse than no instrument at all. It measures the WALL-CLOCK INTERVAL between
//  consecutive deliveries of the always-on master tap. That interval should equal the
//  buffer period (512 frames ÷ sample rate ≈ 10.67 ms, `AudioConfiguration`). When it
//  runs long, the thread servicing audio was starved — CPU/thermal contention, which is
//  exactly the class the founder's "CPU overload" wording describes.
//
//  WHAT IT DOES NOT MEASURE, so a clean report is never read as an all-clear:
//  · It is not an xrun counter. iOS exposes no dropout count for `AVAudioEngine`, and a
//    tap is not the render thread — a late TAP is evidence of starvation on the audio
//    path, not proof that a sample was dropped.
//  · It says nothing about the SECOND crackle class the #193 note asks to separate out:
//    signal-path discontinuity (a step in a parameter, an unfaded voice steal, a seam).
//    That produces a click with the audio thread perfectly on time. A zero here narrows
//    the search to that class; it does not end it.
//  · Bursty delivery can produce a long interval followed by a short one with no
//    starvation at all. That is why the report carries the WORST overshoot and a count
//    rather than an average, and why a single event means nothing — a rate does.
//
//  Pure value types, no clock of its own: the caller passes seconds. That keeps the
//  audio-thread side to plain arithmetic (`mach_absolute_time` + a cached ratio, both
//  lock-free and allocation-free) and makes every threshold arguable in a test instead
//  of on a device.
//

import Foundation

/// What one tap-to-tap interval says about the audio path's timing.
public struct RenderGapReport: Equatable, Sendable {

    /// How far past the expected buffer period this interval ran, in seconds. `0` when
    /// the interval was on time or early.
    public let lateBySeconds: Double

    /// The buffer period this interval was measured against — `frames / sampleRate`.
    /// Carried along so a consumer never has to re-derive it (and get it wrong).
    public let expectedPeriodSeconds: Double

    public init(lateBySeconds: Double, expectedPeriodSeconds: Double) {
        self.lateBySeconds = lateBySeconds
        self.expectedPeriodSeconds = expectedPeriodSeconds
    }

    /// Lateness as a multiple of the buffer period — the scale-free number to reason in.
    /// `0` = on time, `1` = one whole buffer period late. Returns `0` for a non-positive
    /// period rather than dividing by it.
    public var lateInBuffers: Double {
        guard expectedPeriodSeconds > 0 else { return 0 }
        return lateBySeconds / expectedPeriodSeconds
    }
}

public enum RenderGapDetector {

    /// A tap-to-tap interval must exceed the buffer period by THIS multiple before it
    /// counts as a glitch candidate.
    ///
    /// 1.0 = "a whole extra buffer period late". Deliberately not tighter: Core Audio
    /// delivers taps in small bursts and the scheduler jitters by a millisecond or two
    /// without anything being wrong, so a 0.2 threshold would fill the log with noise
    /// and the instrument would be ignored — which is the failure mode the `doctor`
    /// skill exists to warn about. One full period late means a buffer's worth of work
    /// did not happen when it should have; that is worth a line in the diagnostics file.
    public static let glitchThresholdInBuffers: Double = 1.0

    /// Compare one tap-to-tap interval against what it should have been.
    ///
    /// `elapsedSeconds` is wall-clock between the two deliveries; `frames` and
    /// `sampleRate` give the period the interval is measured against. Non-finite or
    /// non-positive inputs yield an all-zero report rather than a NaN that would poison
    /// every downstream max() — the same boundary-sanitising rule the DSP path follows.
    public static func compare(elapsedSeconds: Double,
                               frames: Int,
                               sampleRate: Double) -> RenderGapReport {
        guard elapsedSeconds.isFinite, sampleRate.isFinite,
              sampleRate > 0, frames > 0 else {
            return RenderGapReport(lateBySeconds: 0, expectedPeriodSeconds: 0)
        }
        let period = Double(frames) / sampleRate
        // `max(0, …)` and not the other argument order: `Swift.max(0, x)` returns 0 for a
        // NaN x, `Swift.max(x, 0)` returns NaN. Guarded above too, but the ordering is
        // load-bearing and CLAUDE.md records a shipped silence bug from getting it wrong.
        let late = Swift.max(0, elapsedSeconds - period)
        return RenderGapReport(lateBySeconds: late, expectedPeriodSeconds: period)
    }

    /// Whether this interval is late enough to be worth recording.
    public static func isGlitch(_ report: RenderGapReport,
                                thresholdInBuffers: Double = glitchThresholdInBuffers) -> Bool {
        guard report.expectedPeriodSeconds > 0 else { return false }
        return report.lateInBuffers > thresholdInBuffers
    }

    /// Running tally the audio thread keeps and the UI poll drains.
    ///
    /// A struct of two plain scalars on purpose: the audio-thread side updates two
    /// `nonisolated(unsafe)` pointer cells with arithmetic only — no allocation, no lock,
    /// no ObjC — and the reader takes a snapshot. Neither number is exact under a
    /// concurrent read; both are counters whose ORDER OF MAGNITUDE is the diagnosis, so a
    /// torn read costs nothing worth a lock on the audio path.
    public struct Tally: Equatable, Sendable {
        public var glitchCount: Int
        public var worstLateInBuffers: Double

        public init(glitchCount: Int = 0, worstLateInBuffers: Double = 0) {
            self.glitchCount = glitchCount
            self.worstLateInBuffers = worstLateInBuffers
        }

        public var isClean: Bool { glitchCount == 0 }

        /// One line for `echoel_diag.log` — the file the founder actually shares. Says
        /// what it measured AND what it did not, because a bare "0 glitches" would read
        /// as "the crackle is fixed" when it only means "the thread was not starved".
        public func diagnosticLine(overSeconds: Double) -> String {
            guard glitchCount > 0 else {
                return String(format: "audio timing: no starvation in %.0f s "
                              + "(does not rule out signal-path clicks)", overSeconds)
            }
            return String(format: "audio timing: %d late buffers in %.0f s, worst %.1f× "
                          + "the buffer period", glitchCount, overSeconds, worstLateInBuffers)
        }
    }
}
