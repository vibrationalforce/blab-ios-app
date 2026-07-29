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
//  `frames` is what the PREVIOUS delivery carried — the audio this interval covers).
//  When it runs long, the audio path did not deliver on time. CPU/thermal contention is
//  the class the founder's "CPU overload" wording describes and the one this is built to
//  catch; a short pause looks the same from here, which is why the frame-position channel
//  below is reported alongside instead of being folded in.
//
//  TWO PERIODS, AND THE DIFFERENCE IS THE WHOLE POINT. The tap is installed at 1024
//  frames while the IO buffer is around 512, so ONE missed render deadline delays the tap
//  by only HALF a tap period. A threshold denominated in tap periods would therefore miss
//  the single dropped render cycle that makes one audible crackle — which is the whole
//  event under investigation. So lateness is reported in RENDER QUANTA
//  (`renderQuantumFrames / sampleRate`): one unit = one missed render deadline, whatever
//  size the tap happens to be. The caller must pass the buffer size the session GRANTED
//  (`AVAudioSession.ioBufferDuration`), not the one it preferred — those differ routinely
//  on iOS and always on Bluetooth, and using the preference would scale every number here
//  by the ratio between them while printing a millisecond figure that is simply wrong.
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
//  · A LONG pause or a stream restart (interruption, node attach, route change) produces
//    an interval that is not a measurement at all; those are counted separately as
//    discontinuities. A SHORT pause — under the ceiling, with the render position
//    untouched — is indistinguishable from lateness by the clock alone, and is NOT
//    filtered out. It is reported as lateness with a zero frame drift beside it, which is
//    the honest output: whether the founder's device produces skipped frames or stalled
//    time when it crackles is the open question, and reducing the two channels to one
//    number would answer it by assertion instead of by measurement.
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

    /// What one delivery was: on time, late, or not a measurement at all.
    ///
    /// `glitch` carries BOTH channels. `driftInQuanta` is `0` when the render position
    /// advanced exactly as it should have (or carried no usable position) — i.e. the
    /// clock says late, the frame count says nothing was skipped.
    public enum Verdict: Equatable, Sendable {
        case onTime
        case glitch(lateInQuanta: Double, driftInQuanta: Double)
        case discontinuity
    }

    /// THE decision the diagnostics file is built out of, kept here rather than in the tap
    /// callback so it is arguable in a test instead of on a device. It is the one branch
    /// able to INVERT the instrument's output, and it lived untested in the callback for
    /// exactly one commit.
    ///
    /// Two independent pieces of evidence, reduced to one rule:
    ///
    /// · WALL-CLOCK — the `hostTime` interval against `previousFrames / sampleRate`.
    ///   (`previousFrames`, not the current buffer's: the interval covers the audio the
    ///   PREVIOUS delivery carried. Comparing it against the current length made every
    ///   change in delivered buffer size look like a break, and alternating sizes would
    ///   have pinned the glitch count at zero forever while the log looked healthy.)
    ///
    /// · FRAME POSITION — how far `sampleTime` advanced versus how far it should have.
    ///   Pass `nil` when the timestamp carried no valid sample time. A FORWARD drift means
    ///   audio that should have been rendered was not, which is the event under
    ///   investigation, so it is weighed exactly like wall-clock lateness rather than
    ///   dismissed. Only a BACKWARDS jump, or a drift past the pause ceiling, means the
    ///   graph was stopped and restarted.
    ///
    /// The earlier version treated ANY sample-position drift as a pause. That would have
    /// filed a single dropped render cycle — the crackle — under "pause/restart gaps
    /// ignored", and printed a confident "no starvation" over the top of it.
    public static func classify(elapsedSeconds: Double,
                                previousFrames: Int,
                                sampleGap: Int64?,
                                sampleRate: Double,
                                renderQuantumFrames: Int) -> Verdict {
        let report = compare(elapsedSeconds: elapsedSeconds,
                             frames: previousFrames,
                             sampleRate: sampleRate,
                             renderQuantumFrames: renderQuantumFrames)
        guard report.quantumSeconds > 0 else { return .onTime }

        var drift = 0.0
        if let gap = sampleGap {
            drift = Double(gap - Int64(previousFrames)) / Double(renderQuantumFrames)
            // Backwards at ANY magnitude: the position cannot move back inside a running
            // stream, so this is a restart, not a small error worth a tolerance.
            if drift < 0 { return .discontinuity }
        }
        // The two channels are kept SEPARATE all the way out. An earlier version returned
        // `max(late, drift)` in the field labelled `lateInQuanta` — so a delivery that was
        // perfectly on time but skipped a buffer reported wall-clock lateness that never
        // happened, and the log printed it as a millisecond-convertible claim about the
        // clock. Either channel alone can raise the verdict; neither may speak for the
        // other.
        let late = report.lateInQuanta
        if late > discontinuityThresholdInQuanta || drift > discontinuityThresholdInQuanta {
            return .discontinuity
        }
        if late > glitchThresholdInQuanta || drift > glitchThresholdInQuanta {
            return .glitch(lateInQuanta: late, driftInQuanta: drift)
        }
        return .onTime
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
        /// The frame drift OF THE SAME INTERVAL that produced `worstLateInQuanta` — the
        /// two are meant to be one event, not two independent window maxima. That
        /// distinction is the whole value of the pair: `0` drift beside a large lateness
        /// means the graph stopped rendering, non-zero means audio was skipped. Maximising
        /// them separately would compose a description of an event that never occurred.
        ///
        /// Stated exactly, because this file does not let a comment outrun its code: the
        /// producer writes the two in sequence without a lock, so a snapshot taken between
        /// those two stores can still pair a new lateness with the previous drift. That is
        /// a handful of instructions per 60 s window, not a structural guarantee — and a
        /// lock on the audio path to tidy a diagnostic would be the worse trade.
        public var worstDriftInQuanta: Double
        /// Intervals discarded as pause/restart artefacts. Reported, not hidden: if this
        /// is large the instrument was mostly looking at a stopped graph, and the
        /// lateness figure next to it means correspondingly less.
        public var discontinuityCount: Int
        /// Intervals actually classified. The honest denominator: a 60 s window in which
        /// the graph ran for 5 s is not 60 s of evidence, and the line must not read as
        /// though it were.
        public var measuredIntervals: Int

        public init(glitchCount: Int = 0,
                    worstLateInQuanta: Double = 0,
                    worstDriftInQuanta: Double = 0,
                    discontinuityCount: Int = 0,
                    measuredIntervals: Int = 0) {
            self.glitchCount = glitchCount
            self.worstLateInQuanta = worstLateInQuanta
            self.worstDriftInQuanta = worstDriftInQuanta
            self.discontinuityCount = discontinuityCount
            self.measuredIntervals = measuredIntervals
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
            var tail = String(format: " · %ld intervals seen", measuredIntervals)
            if discontinuityCount > 0 {
                tail += String(format: " · %ld pause/restart gaps ignored", discontinuityCount)
            }
            guard glitchCount > 0 else {
                return String(format: "audio timing: nothing late in %.0f s "
                              + "(quantum %.2f ms; does not rule out signal-path clicks)",
                              overSeconds, quantumMilliseconds) + tail
            }
            return String(format: "audio timing: %ld late in %.0f s, worst one %.1f× the "
                          + "%.2f ms quantum with frame drift %.1f×",
                          glitchCount, overSeconds, worstLateInQuanta,
                          quantumMilliseconds, worstDriftInQuanta) + tail
        }
    }
}
