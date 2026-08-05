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

        /// ⭐ THE SAME VERDICT, SHORT ENOUGH FOR A PANEL ROW (#408).
        ///
        /// WHY A SECOND FORMATTER RATHER THAN REUSING `diagnosticLine`: that one is written
        /// for `echoel_diag.log`, a file the founder has to export and send. It is deliberately
        /// verbose — it names its denominator and its own blind spots in-line, because whoever
        /// reads it next has no other context. A UI row has the opposite constraint: it is read
        /// in one glance, WHILE the crackle is happening, and it has a caption beside it that
        /// carries the caveat permanently. Squeezing the log line into a row would truncate;
        /// putting the row's brevity into the log would strip the caveats. Two readers, two
        /// lines, one `Tally`.
        ///
        /// AND THAT IS THE WHOLE POINT OF #408: this instrument has existed since #193 and has
        /// only ever spoken into a file. The founder reported "teilweise extremes Knacken" on
        /// v10.79.369 with no log attached — which is the normal case, not a lapse. A number
        /// the founder can SEE at the moment they hear it turns the next report into its own
        /// diagnosis.
        ///
        /// ⚠️ THE UNITS ARE MILLISECONDS HERE, NOT QUANTA. The log prints a multiplier because
        /// its reader is expected to know the buffer size; the row's reader is not, and "2.4×"
        /// means nothing without it. `worstLateInQuanta × quantumMilliseconds` is the same
        /// measurement expressed in the unit a person can compare against a sound they heard.
        ///
        /// ⚠️ A BLIND WINDOW MUST NOT READ AS A CLEAN ONE. `isClean` is `glitchCount == 0`,
        /// which is also true when the tap never fired — the exact ambiguity the log's
        /// proof-of-life rules exist to remove, and it would come straight back if this row
        /// printed "nothing late" for a window with no denominator.
        /// ⚠️ AND A WINDOW THAT WAS MOSTLY BLIND MUST NOT READ AS A FULLY MEASURED ONE. This
        /// is the same over-claim one step milder, and the first version of this method walked
        /// straight into it: `measuredIntervals` was used ONLY as a `> 0` gate and
        /// `discontinuityCount` never reached the row at all. The field docs sixty lines above
        /// state the rule being broken in as many words — *"a 60 s window in which the graph ran
        /// for 5 s is not 60 s of evidence, and the line must not read as though it were"* — and
        /// `diagnosticLine` honours it with a tail the row was missing.
        ///
        /// The failure is concrete, not theoretical: a Bluetooth route flapping through a
        /// window classifies (say) 50 intervals of which 48 are discontinuities and 0 are late.
        /// The log says so. The row said "Nothing late in the last 60 s" — a clean verdict read
        /// off a quarter-second of evidence, in the feature whose entire justification is that
        /// it does not over-claim. Note WHY the count looks healthy: the tap increments
        /// `measuredIntervals` BEFORE classifying, so discontinuities are inside it, not beside
        /// it (`AudioEngine.swift`, the `installTap` body).
        ///
        /// So the span is named whenever it falls meaningfully short of the window. It stays
        /// silent in the ordinary case — a row that always carries a caveat is a row nobody
        /// finishes reading.
        public func screenLine(overSeconds: Double, quantumMilliseconds: Double) -> String {
            let seconds = overSeconds.isFinite && overSeconds > 0 ? overSeconds : 0
            guard measuredIntervals > 0 else {
                return seconds > 0
                    ? String(format: "Not measured in the last %.0f s", seconds)
                    : "Not measured yet"
            }
            let evidence = evidenceSuffix(seconds: seconds,
                                          quantumMilliseconds: quantumMilliseconds)
            guard glitchCount > 0 else {
                // ⛔ The `seconds > 0` split is not decoration: without it this branch printed
                // "Nothing late in the last 0 s" — a clean verdict over a window of no length —
                // while the blind branch four lines up had already special-cased exactly that.
                // Unreachable from `pollAudioTiming` (it formats only after a 60 s guard), but
                // the asymmetry is what lets a future caller find it.
                return seconds > 0
                    ? String(format: "Nothing late in the last %.0f s", seconds) + evidence
                    : "Nothing late so far" + evidence
            }
            let ms = quantumMilliseconds.isFinite && quantumMilliseconds > 0
                ? worstLateInQuanta * quantumMilliseconds : 0
            // ⛔ `isFinite` AND a floor at half the printed resolution, not the old `ms > 0`.
            // `+infinity > 0` is true, so the old guard would have printed "worst inf ms
            // behind"; and 0.04 ms passed it only to render as "worst 0.0 ms behind" — the
            // fabricated zero the unknown-quantum branch exists to avoid. Neither is reachable
            // today (`classify` bounds lateness at 32 quanta and a glitch needs > 0.75), which
            // is exactly why they would have survived until the day something else changed.
            guard ms.isFinite, ms >= 0.05 else {
                return String(format: "%ld late in %.0f s", glitchCount, seconds) + evidence
            }
            return String(format: "%ld late in %.0f s · worst %.1f ms behind",
                          glitchCount, seconds, ms) + evidence
        }

        /// The honest denominator, appended only when it contradicts the window length.
        ///
        /// Needs the quantum: `measuredIntervals` is a count of render intervals, and without
        /// their duration it cannot become a span. When the quantum is unknown the row stays
        /// silent rather than guessing — an invented denominator would be worse than none.
        private func evidenceSuffix(seconds: Double, quantumMilliseconds: Double) -> String {
            guard seconds > 0, quantumMilliseconds.isFinite, quantumMilliseconds > 0 else {
                return ""
            }
            let measuredSeconds = Double(measuredIntervals) * quantumMilliseconds / 1000
            // 80 %: a window is never exactly full (the tap starts mid-window, a buffer or two
            // is lost to the poll boundary), so a strict comparison would append the caveat to
            // every healthy window and train the reader to skip it.
            guard measuredSeconds.isFinite, measuredSeconds < seconds * 0.8 else { return "" }
            return measuredSeconds < 1
                ? " · under 1 s of it measured"
                : String(format: " · only %.0f s of it measured", measuredSeconds)
        }

        /// The caveat that sits under `screenLine` PERMANENTLY, never only when the window is
        /// dirty. A clean timing window is not an all-clear for the founder's report: a voice
        /// steal, a parameter step or an un-faded seam produces a click with the audio path
        /// perfectly on time, and this instrument cannot see any of them (the file header says
        /// so at length). A caption that appeared only on dirty windows would let the clean
        /// case read as "the crackling is gone", which is the one sentence this must never say.
        public static let screenCaption =
            "Timing only. A click while the audio is on time is not counted here."

        /// What the row actually shows, resolved from the two facts it has: the last window's
        /// verdict (nil until one closes) and whether the engine is still measuring.
        ///
        /// ⚠️ THIS EXISTS BECAUSE THE FIRST VERSION HAD THE STALENESS HOLE IT WAS WRITTEN TO
        /// PREVENT. The row printed `lastTimingLine ?? "Measuring…"` and nothing more. `stop()`
        /// invalidates the meter poll timer without clearing that string, so after Stop the
        /// row kept showing the last verdict — usually "Nothing late in the last 60 s" —
        /// indefinitely, with no sign that measurement had ceased. The realistic sequence is
        /// the one #408 exists for: play, hear the crackle, hit Stop, open Master, read a
        /// clean verdict from BEFORE the stop as if it described now. The commit argued in its
        /// own message that "stale is worse than clean: a wrong answer, not a missing one" —
        /// and then applied that argument only to the log gate (≤ 60 s stale) and not to the
        /// stop path (unbounded).
        ///
        /// The verdict is NOT discarded on stop — it is qualified. Discarding would trade a
        /// wrong answer for a missing one; the founder's own gesture is to stop and then look.
        ///
        /// ⚠️ WHAT THIS STILL DOES NOT FIX: even while running, the line names the window that
        /// just CLOSED, so 59 s later "the last 60 s" is really 60–120 s ago. Inherent to a
        /// windowed measure, and small next to reading a pre-stop verdict as current — but it
        /// is an over-claim of recency, in a slice whose whole argument is about not
        /// over-claiming, so it is written down rather than left for someone to discover.
        public static func screenText(line: String?, isRunning: Bool) -> String {
            guard let line, !line.isEmpty else {
                return isRunning ? "Measuring…" : "Not measured"
            }
            return isRunning ? line : "\(line) · measured before the stop"
        }
    }
}
