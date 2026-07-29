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
//  worse than no instrument at all. The caller stamps CoreAudio's own `AVAudioTime`
//  `hostTime` — the render-cycle timestamp, not "when the tap block happened to run" —
//  and passes the interval between two consecutive deliveries of the always-on master
//  tap. That interval should equal the TAP's period (`frames / sampleRate`, where
//  `frames` is what the tap actually delivered, not what was requested). When it runs
//  long, the audio path was starved — CPU/thermal contention, which is exactly the class
//  the founder's "CPU overload" wording describes.
//
//  TWO PERIODS, AND THE DIFFERENCE IS THE WHOLE POINT. The tap is installed at 1024
//  frames while the IO buffer is 512 (`AudioConfiguration.currentBufferSize`), so ONE
//  missed render deadline delays the tap by only HALF a tap period. A threshold
//  denominated in tap periods would therefore miss the single dropped render cycle that
//  makes one audible crackle — which is the whole event under investigation. So lateness
//  is reported in RENDER QUANTA (`renderQuantumFrames / sampleRate`): one unit = one
//  missed render deadline, whatever size the tap happens to be.
//
//  WHAT IT DOES NOT MEASURE, so a clean report is never read as an all-clear:
//  · It is not an xrun counter. iOS exposes no dropout count for `AVAudioEngine`, and a
//    late tap timestamp is evidence that the audio path ran late, not proof that a sample
//    was dropped.
//  · It says nothing about the SECOND crackle class the #193 note asks to separate out:
//    signal-path discontinuity (a step in a parameter, an unfaded voice steal, a seam).
//    That produces a click with the audio path perfectly on time. A zero here narrows
//    the search to that class; it does not end it.
//  · The interval spans top-of-callback N−1 → top-of-callback N, so it CONTAINS the
//    previous callback's own metering work. If the true-peak/EBU meters overrun their
//    budget, this instrument will (correctly) report that as lateness — it cannot be used
//    to rule the metering path out.
//  · An engine pause/restart (interruption, node attach, route change) produces an
//    interval that is not a measurement at all. Those are classified separately as
//    DISCONTINUITIES and counted, never mixed into the starvation figure — see
//    `isDiscontinuity`.
//
//  Pure value types, no clock of its own: the caller passes seconds. That keeps the
//  audio-thread side to plain arithmetic (a timestamp CoreAudio already handed us times a
//  ratio resolved once off the audio path, both lock-free and allocation-free) and makes
//  every threshold arguable in a test instead of on a device.
//

import Foundation

/// What one tap-to-tap interval says about the audio path's timing.
public struct RenderGapReport: Equatable, Sendable {

    /// How far past the expected tap period this interval ran, in seconds. `0` when the
    /// interval was on time or early.
    public let lateBySeconds: Double

    /// The tap period this interval was measured against — `frames / sampleRate`.
    /// Carried along so a consumer never has to re-derive it (and get it wrong).
    public let expectedPeriodSeconds: Double

    /// One render deadline's worth of audio — `renderQuantumFrames / sampleRate`. This,
    /// not the tap period, is the unit lateness is reported in.
    public let quantumSeconds: Double

    public init(lateBySeconds: Double, expectedPeriodSeconds: Double, quantumSeconds: Double) {
        self.lateBySeconds = lateBySeconds
        self.expectedPeriodSeconds = expectedPeriodSeconds
        self.quantumSeconds = quantumSeconds
    }

    /// Lateness as a multiple of ONE RENDER DEADLINE — the scale-free number to reason
    /// in. `0` = on time, `1` = a whole render cycle's worth of audio late. Returns `0`
    /// for a non-positive quantum rather than dividing by it.
    public var lateInQuanta: Double {
        guard quantumSeconds > 0 else { return 0 }
        return lateBySeconds / quantumSeconds
    }
}

public enum RenderGapDetector {

    /// A tap-to-tap interval must exceed its expected period by THIS many render quanta
    /// before it counts as a glitch candidate.
    ///
    /// 0.75, so that ONE missed render deadline (exactly 1.0) is caught while sub-deadline
    /// scheduler jitter is not. Deliberately not tighter: CoreAudio's delivery jitters by
    /// a fraction of a cycle without anything being wrong, and an instrument that cries
    /// wolf gets ignored — which is the failure mode the `doctor` skill exists to warn
    /// about. Deliberately not looser either: at a 1024-frame tap over 512-frame IO, a
    /// threshold of 1.0 TAP period would need TWO consecutive missed deadlines to fire,
    /// and would therefore be blind to the single dropped cycle that makes one crackle.
    public static let glitchThresholdInQuanta: Double = 0.75

    /// Past THIS much lateness the interval is not a starvation measurement at all — the
    /// graph was paused (interruption, node attach, route change, app suspension). 32
    /// render quanta ≈ 340 ms at 512/48k: far beyond any plausible scheduling stall, far
    /// below the length of a phone call. Counted separately so a Siri prompt cannot
    /// contribute a `worst 1400×` to the founder's log and send the next cycle hunting a
    /// stall that never happened.
    public static let discontinuityThresholdInQuanta: Double = 32

    /// Compare one tap-to-tap interval against what it should have been.
    ///
    /// `elapsedSeconds` is the delta between two CoreAudio `hostTime` stamps; `frames`
    /// and `sampleRate` give the tap period the interval is measured against;
    /// `renderQuantumFrames` is the IO buffer size, the unit lateness is reported in.
    /// Non-finite or non-positive inputs yield an all-zero report rather than a NaN that
    /// would poison every downstream max() — the same boundary-sanitising rule the DSP
    /// path follows.
    public static func compare(elapsedSeconds: Double,
                               frames: Int,
                               sampleRate: Double,
                               renderQuantumFrames: Int) -> RenderGapReport {
        guard elapsedSeconds.isFinite, sampleRate.isFinite,
              sampleRate > 0, frames > 0, renderQuantumFrames > 0 else {
            return RenderGapReport(lateBySeconds: 0, expectedPeriodSeconds: 0, quantumSeconds: 0)
        }
        let period = Double(frames) / sampleRate
        let quantum = Double(renderQuantumFrames) / sampleRate
        // `max(0, …)` and not the other argument order: `Swift.max(0, x)` returns 0 for a
        // NaN x, `Swift.max(x, 0)` returns NaN. Guarded above too, but the ordering is
        // load-bearing and CLAUDE.md records a shipped silence bug from getting it wrong.
        let late = Swift.max(0, elapsedSeconds - period)
        return RenderGapReport(lateBySeconds: late,
                               expectedPeriodSeconds: period,
                               quantumSeconds: quantum)
    }

    /// Whether this interval is late enough to be worth recording as starvation.
    /// Discontinuities are excluded here so a caller cannot double-count one.
    public static func isGlitch(_ report: RenderGapReport,
                                thresholdInQuanta: Double = glitchThresholdInQuanta) -> Bool {
        guard report.quantumSeconds > 0, !isDiscontinuity(report) else { return false }
        return report.lateInQuanta > thresholdInQuanta
    }

    /// Whether this interval is so long that it is evidence of a paused graph rather than
    /// a starved one.
    public static func isDiscontinuity(_ report: RenderGapReport,
                                       thresholdInQuanta: Double = discontinuityThresholdInQuanta) -> Bool {
        guard report.quantumSeconds > 0 else { return false }
        return report.lateInQuanta > thresholdInQuanta
    }

    /// Running tally the audio thread keeps and the UI poll drains.
    ///
    /// A struct of three plain scalars on purpose: the audio-thread side updates
    /// `nonisolated(unsafe)` cells with arithmetic only — no allocation, no lock, no ObjC
    /// — and the reader takes a snapshot. Reading them concurrently with those writes is
    /// a data race in the formal sense (TSan would flag it), not merely a possibly-torn
    /// value; it is accepted because these are counters whose ORDER OF MAGNITUDE is the
    /// diagnosis, and no lock belongs on the audio path to make a diagnostic tidier.
    public struct Tally: Equatable, Sendable {
        public var glitchCount: Int
        public var worstLateInQuanta: Double
        /// Intervals discarded as pause/restart artefacts. Reported, not hidden: if this
        /// is large the instrument was mostly looking at a stopped graph, and the
        /// starvation figure next to it means correspondingly less.
        public var discontinuityCount: Int

        public init(glitchCount: Int = 0,
                    worstLateInQuanta: Double = 0,
                    discontinuityCount: Int = 0) {
            self.glitchCount = glitchCount
            self.worstLateInQuanta = worstLateInQuanta
            self.discontinuityCount = discontinuityCount
        }

        public var isClean: Bool { glitchCount == 0 }

        /// One line for `echoel_diag.log` — the file the founder actually shares. Says
        /// what it measured AND what it did not, because a bare "0 glitches" would read
        /// as "the crackle is fixed" when it only means "the audio path was not starved".
        ///
        /// `quantumMilliseconds` is printed so the multiplier can be converted back to
        /// milliseconds by whoever reads the log next, without knowing the buffer size
        /// the device happened to be running.
        public func diagnosticLine(overSeconds: Double, quantumMilliseconds: Double) -> String {
            let tail = discontinuityCount > 0
                ? String(format: " · %ld pause/restart gaps ignored", discontinuityCount)
                : ""
            guard glitchCount > 0 else {
                return String(format: "audio timing: no starvation in %.0f s "
                              + "(quantum %.2f ms; does not rule out signal-path clicks)",
                              overSeconds, quantumMilliseconds) + tail
            }
            return String(format: "audio timing: %ld late renders in %.0f s, worst %.1f× "
                          + "the %.2f ms render quantum",
                          glitchCount, overSeconds, worstLateInQuanta, quantumMilliseconds) + tail
        }
    }
}
