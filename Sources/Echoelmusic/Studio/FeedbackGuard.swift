//
//  FeedbackGuard.swift
//  Echoelmusic — Studio (live voice safety)
//
//  Pure, testable heuristics for acoustic-feedback (howlround) suppression on the
//  live mic/vocoder path. This file is the BRAIN only — no audio DSP here:
//    • detect runaway level build-up  → recommend a gain duck (dB)
//    • find the ringing frequency bin  → recommend a notch
//
//  ⛔ WHAT THIS HEADER CLAIMED UNTIL 2026-07-31, AND WHAT IS ACTUALLY WIRED.
//  It said: "The audio cycle applies them: Apple's Voice-Processing I/O for system AEC (the
//  FaceTime echo canceller) + a notch biquad + the recommended duck in the FX chain."
//  At the #298 measurement ONE of those three was real; since #595 (2026-08-14) it is TWO.
//  Checked by grep over `Sources/`:
//    • the DUCK is live — `AudioEngine.updateFeedbackGuard()` calls `gainReductionDB` and
//      scales `monitorMixer.outputVolume`. It ducks the MIC MONITOR only, never the music, and
//      touches no audio thread and no tap. It runs on the MainActor from the **60 Hz** meter
//      poll, gated to every 4th tick (`monitorPollTick % 4 == 0`), i.e. ~15 Hz. ⛔ The first
//      version of this line called it "the ~15 Hz meter poll" — the poll is 60 Hz and the GATE
//      makes it 15. Anyone budgeting work onto that poll from this sentence would be off by 4×.
//    • the NOTCH is WIRED, and since #848 it is PREVENTIVE and PER-BAND (founder
//      2026-08-27: "auf die betroffenen Frequenzbändern … es soll erst gar kein Piepsen
//      entstehen"). `AudioEngine` taps the monitor input into `MonitorTapWindow` (lock
//      queue, zero actor hops in the tap); the ~15 Hz guard tick runs the FFT on EVERY
//      tick while monitoring and feeds `HowlDetector`, whose four-signature join
//      (neighbourhood dominance · persistence · growth · no harmonic/subharmonic
//      partner) fires while the howl is still QUIET; each affected band gets one of
//      FOUR `AVAudioUnitEQ` parametric notches in the MONITOR path only (input →
//      notchEQ → monitorMixer — the music never passes through it, the duck's exact
//      scoping), gain slewed via `slewedNotchGainDB` (never stepped), held ~2 s past
//      the last detection so a band cannot audibly pump. The duck is the broadband
//      LAST RESORT now, not the notch's gatekeeper.
//      ⛔ From #595 to #848 the notch was REACTIVE — single band, engaged only while
//      the duck already fired, keyed on `ringingBin` (which since #848 has no
//      production caller; it stays below as a tested pure primitive). ⛔ Until #595
//      this bullet stated the opposite (unwired, zero callers — NOT quoted verbatim
//      here: the two-way guard scans this RAW header for the old sentence, and a
//      verbatim quote would re-trigger it, the #491 collision); that was true for a
//      year. The paired two-way guard
//      (`AudioInputDoorTests.testFeedbackGuardHeaderMatchesWhatIsActuallyWired`) forces this
//      sentence and the wiring to move together, in BOTH directions — since #848 its
//      wiring proxy is `HowlDetector`, matching what production actually consumes.
//    • the AEC is NOT wired — `setVoiceProcessingEnabled` appears NOWHERE in `Sources/`.
//      Deliberate: it changes the whole I/O character and is Council-gated (see
//      `scratchpads/PLAN_VOICE_STAGE_2026-08-14.md`, "NICHT bauen").
//  This mattered more than a stale comment usually does: it is the file a session reads to
//  decide whether feedback suppression still needs work, and as written it answered "already
//  done, three layers deep". Headphone/IEM monitoring remains the zero-feedback path; on a
//  speaker the defence is now duck (level) + notch (frequency), still no AEC.
//
//  The free functions above the HowlDetector are allocation-free over caller-provided
//  buffers, so the audio thread can call them directly (Accelerate does the FFT
//  upstream). `HowlDetector` is the exception and says so at its declaration:
//  control-plane only, bounded allocation, never from a render block.
//

import Foundation

public enum FeedbackGuard {

    /// ONE spelling of the duck's default depth (#416). A caller that widens the
    /// authority — Megaphone Mode uses `defaultMaxReductionDB + megaphoneBoostDB`,
    /// so the guard can always undo more than the boost — derives from this
    /// constant instead of restating the 12.
    public static let defaultMaxReductionDB: Float = 12

    /// Recommended gain reduction in dB (0 = none) when the level is both ABOVE a
    /// ceiling and trending upward across the short RMS history — the signature of
    /// feedback building up. Pure: depends only on the passed history.
    ///
    /// - Parameters:
    ///   - rmsHistory: recent broadband RMS samples, oldest → newest (0…1).
    ///   - ceiling: level above which we start worrying (0…1).
    ///   - maxReductionDB: clamp on how much we duck in one step.
    public static func gainReductionDB(rmsHistory: [Float],
                                       ceiling: Float = 0.85,
                                       maxReductionDB: Float = defaultMaxReductionDB) -> Float {
        guard let last = rmsHistory.last, rmsHistory.count >= 3 else { return 0 }
        let first = rmsHistory.first ?? last
        // Rising trend: newest meaningfully louder than oldest in the window.
        let rising = last > first * 1.10 && last > 0.001
        guard rising, last > ceiling else { return 0 }
        // Duck proportional to how far over the ceiling we are (linear → dB).
        let over = min(1, (last - ceiling) / max(0.0001, 1 - ceiling))
        return min(maxReductionDB, over * maxReductionDB)
    }

    /// The index of a dominant, persistent peak in a magnitude spectrum — the
    /// likely ringing frequency to notch — or nil when nothing clearly dominates.
    ///
    /// ⚠️ No production caller since #848: the preventive `HowlDetector` below
    /// superseded this reactive single-bin question in `updateFeedbackGuard`. Kept as
    /// a tested pure primitive (its global-dominance framing is the documented
    /// CONTRAST to the detector's local-neighbourhood one), not as dead weight to
    /// silently delete — see the header's notch bullet.
    ///
    /// - Parameters:
    ///   - magnitudes: linear FFT magnitudes (bin 0 = DC).
    ///   - dominanceRatio: peak must exceed the mean by at least this factor.
    public static func ringingBin(magnitudes: [Float], dominanceRatio: Float = 8) -> Int? {
        guard magnitudes.count > 2 else { return nil }
        var sum: Float = 0
        var peak: Float = 0
        var peakIdx = 0
        // Skip DC (bin 0).
        for i in 1..<magnitudes.count {
            let m = magnitudes[i]
            sum += m
            if m > peak { peak = m; peakIdx = i }
        }
        let count = Float(magnitudes.count - 1)
        guard count > 0 else { return nil }
        let mean = sum / count
        guard mean > 0, peak >= mean * dominanceRatio else { return nil }
        return peakIdx
    }

    /// Convert an FFT bin to its centre frequency in Hz.
    public static func binToHz(_ bin: Int, fftSize: Int, sampleRate: Double) -> Double {
        guard fftSize > 0 else { return 0 }
        return Double(bin) * sampleRate / Double(fftSize)
    }

    /// Rate-based slew for the monitor notch's gain in dB (#595): moves `current`
    /// toward `target` by at most `stepDB` per guard tick (~15 Hz), so engaging and
    /// releasing the notch are RAMPS, never steps — the slew law that governs every
    /// audible parameter jump in this repo. A non-finite `current` (a poisoned state
    /// variable) restarts from 0 rather than propagating; a non-finite `target` is
    /// treated as release (0). Pure, allocation-free.
    public static func slewedNotchGainDB(current: Float, target: Float,
                                         stepDB: Float = 4) -> Float {
        let cur = current.isFinite ? current : 0
        let tgt = target.isFinite ? target : 0
        let step = Swift.max(0.1, stepDB.isFinite ? stepDB : 4)
        if cur < tgt { return Swift.min(tgt, cur + step) }
        if cur > tgt { return Swift.max(tgt, cur - step) }
        return cur
    }

    /// #848b (review F1): how far a candidate frequency may sit from an engaged notch
    /// band's frequency and still be the SAME howl. A pure percentage breaks in the
    /// low mids: one FFT bin is `sampleRate/fftSize` Hz (≈ 23 Hz at 48 k/2048), and the
    /// detector deliberately lets a track breathe ±1 bin — below `binWidthHz / ratio`
    /// (≈ 390 Hz at 48 k with ±6 %) a single bin step already exceeds the percentage
    /// window, so one room-mode howl alternated bins and burned TWO bands. The window
    /// is therefore the WIDER of the relative and the absolute arm; the absolute arm
    /// governs below `binWidthHz · binFloor / ratio` (≈ 586 Hz for a 1.5-bin floor).
    /// Arguments carry no defaults (#431 — the caller owns the one spelling of both
    /// numbers). Pure, allocation-free; non-finite or negative inputs collapse to 0,
    /// which no real frequency distance satisfies against a > 0 distance.
    public static func sameBandHalfWidthHz(frequencyHz: Float, binWidthHz: Float,
                                           ratio: Float, binFloor: Float) -> Float {
        let f = (frequencyHz.isFinite && frequencyHz > 0) ? frequencyHz : 0
        let w = (binWidthHz.isFinite && binWidthHz > 0) ? binWidthHz : 0
        let r = (ratio.isFinite && ratio > 0) ? ratio : 0
        let b = (binFloor.isFinite && binFloor > 0) ? binFloor : 0
        return Swift.max(f * r, w * b)
    }

    // MARK: - Early howl detection (#847 — founder 2026-08-27: "es soll erst gar kein
    // Piepsen entstehen")

    /// The PREVENTIVE half of the guard's brain: catches a howl while it is still quiet,
    /// so the wiring can notch the affected band before anything is audible.
    ///
    /// `ringingBin` above answers "which single bin dominates the whole spectrum RIGHT
    /// NOW" — a reactive question, asked only after the duck already fired. A howl's
    /// earlier signature is different and FOURFOLD: one spectral peak that (1) dominates
    /// its local NEIGHBOURHOOD (not the whole spectrum — a bass note dominates globally),
    /// (2) PERSISTS at the same bin (±1 for FFT-leakage jitter) across consecutive
    /// observations, (3) GROWS across the track's life (endpoint ratio over a 3-bin
    /// energy sum — the sum is leakage-invariant, so a stationary tone sitting between
    /// two bins cannot fake growth out of scalloping; a windowed "grew over the last N
    /// ticks" variant is registered for the wiring slice if the life-ratio proves too
    /// eager on very slow swells), and (4) has NO harmonic partner at 2f AND no
    /// SUBharmonic parent at f/2 (a voice or instrument has one or the other; the
    /// subharmonic veto is what keeps a crescendo's own octave from forming a clean
    /// track of its own — #847 review finding 1). All must hold — each alone matches
    /// some musical signal.
    ///
    /// ⭐ WIRED since #848: `AudioEngine.updateFeedbackGuard()` feeds it the monitor
    /// FFT on every guard tick with fresh audio (#850 skips a frozen window via the
    /// tap window's write stamp) and `applyNotchDefence` maps its candidates onto four
    /// dynamic notch bands — the notch is no longer gated on the duck, which is the
    /// broadband last resort. (#847 shipped this type deliberately caller-less for one
    /// commit; that boundary note is retired with the wiring, #425.) Behaviour is
    /// pinned by `AHowlIsCaughtBeforeItIsHeardTests` (END-TO-END, pure); the wiring
    /// shape by `TheNotchIsSlewedAndMonitorOnlyTests`.
    ///
    /// Control-plane, MainActor cadence (~15 Hz): unlike the free functions above this
    /// type may allocate (bounded: `maxTracks`); it must NEVER be called from a render
    /// block — the FFT it consumes is already produced upstream on the MainActor.
    public struct HowlDetector {

        public struct Candidate: Equatable, Sendable {
            /// The affected FFT bin (the wiring maps it to Hz via `binToHz`).
            public let bin: Int
            /// Growth factor over the track's life — ranks candidates when the wiring
            /// has fewer EQ bands than candidates. Always finite.
            public let severity: Float
        }

        public struct Config: Sendable {
            /// Bins each side of a peak that form its neighbourhood mean.
            public var neighborhoodRadius: Int = 8
            /// Peak must exceed the neighbourhood mean by this factor. Lower than
            /// `ringingBin`'s global ×8 on purpose: local dominance is the sharper test.
            public var dominanceRatio: Float = 6
            /// Newest magnitude must exceed the track's first by this factor.
            public var growthRatio: Float = 1.25
            /// Consecutive observations before a track may become a candidate.
            /// At the ~15 Hz guard tick, 4 ≈ 270 ms — well inside a howl's build-up,
            /// well past any transient.
            public var persistenceTicks: Int = 4
            /// Veto: energy at 2×bin (±1 — an off-bin note's harmonic lands beside the
            /// exact double) above this fraction of the peak = a musical note.
            public var harmonicMaxRatio: Float = 0.35
            /// Veto: energy around bin/2 above this fraction of the peak = this peak IS
            /// the harmonic of a musical note (a crescendo's octave), not a howl.
            public var subharmonicMaxRatio: Float = 0.5
            /// Absolute floor — relative dominance over near-silence is not a howl.
            public var minMagnitude: Float = 0.001
            /// Bins below this are rumble/DC, never howl (the wiring additionally
            /// clamps to ≥ 40 Hz when converting to a filter frequency).
            public var minBin: Int = 2
            /// Upper bound on reported candidates per observation.
            public var maxCandidates: Int = 4
            public init() {}
        }

        private struct Track {
            var bin: Int
            var ticksSeen: Int
            var firstMagnitude: Float
            var lastMagnitude: Float
        }

        /// Bounded state: more simultaneous narrowband tracks than this is not a howl
        /// scenario, it is noise — the strongest survive.
        private static let maxTracks = 16

        public var config: Config
        private var tracks: [Track] = []

        public init(config: Config = Config()) {
            self.config = config
        }

        /// Forget all tracks (the wiring calls this when monitoring stops or the route
        /// changes — persistence must never survive a world change).
        public mutating func reset() {
            tracks.removeAll(keepingCapacity: true)
        }

        /// Feed one magnitude spectrum (bin 0 = DC, linear magnitudes); returns the
        /// bands whose four signatures all hold RIGHT NOW, strongest growth first.
        public mutating func observe(magnitudes: [Float]) -> [Candidate] {
            let peaks = localPeaks(in: magnitudes)

            // Match peaks to existing tracks (±1 bin — FFT leakage makes a stationary
            // howl breathe between neighbouring bins). One miss resets a track: at the
            // guard cadence a real regenerating loop never skips an observation.
            var next: [Track] = []
            var claimed = [Bool](repeating: false, count: peaks.count)
            for track in tracks {
                guard let i = peaks.indices.first(where: { !claimed[$0]
                    && abs(peaks[$0].bin - track.bin) <= 1 }) else { continue }
                claimed[i] = true
                var t = track
                t.bin = peaks[i].bin
                t.ticksSeen += 1
                t.lastMagnitude = peaks[i].energy
                next.append(t)
            }
            for i in peaks.indices where !claimed[i] {
                next.append(Track(bin: peaks[i].bin, ticksSeen: 1,
                                  firstMagnitude: peaks[i].energy,
                                  lastMagnitude: peaks[i].energy))
            }
            if next.count > Self.maxTracks {
                next.sort { $0.lastMagnitude > $1.lastMagnitude }
                next.removeLast(next.count - Self.maxTracks)
            }
            tracks = next

            var out: [Candidate] = []
            for t in tracks where t.ticksSeen >= Swift.max(1, config.persistenceTicks) {
                let base = Swift.max(t.firstMagnitude, Float.leastNormalMagnitude)
                let growth = t.lastMagnitude / base
                guard growth.isFinite, growth >= config.growthRatio else { continue }
                out.append(Candidate(bin: t.bin, severity: growth))
            }
            out.sort { $0.severity > $1.severity }
            if out.count > Swift.max(0, config.maxCandidates) {
                out.removeLast(out.count - Swift.max(0, config.maxCandidates))
            }
            return out
        }

        private struct Peak {
            let bin: Int
            /// 3-bin energy (i−1 + i + i+1, finite parts) — the growth quantity.
            /// Leakage-invariant: a stationary tone between two bins sloshes magnitude
            /// between them but keeps the sum, so scalloping cannot fake growth
            /// (#847 review finding 2).
            let energy: Float
        }

        /// Signatures (1) and (4): locally dominant peaks above the absolute floor with
        /// neither a harmonic partner nor a subharmonic parent. Non-finite bins are
        /// invisible — skipped as a peak, excluded from every mean and sum, vetoing
        /// nothing.
        private func localPeaks(in magnitudes: [Float]) -> [Peak] {
            let n = magnitudes.count
            let lo = Swift.max(1, config.minBin)
            guard n > lo + 1 else { return [] }
            // Strongest finite magnitude in bins [a, b] ∩ [0, n), or 0 for an empty/
            // poisoned window — shared by both veto reads below.
            func windowMax(_ a: Int, _ b: Int) -> Float {
                let low = Swift.max(0, a)
                let high = Swift.min(n - 1, b)
                guard low <= high else { return 0 }
                var best: Float = 0
                for j in low...high where magnitudes[j].isFinite {
                    best = Swift.max(best, magnitudes[j])
                }
                return best
            }
            var found: [Peak] = []
            for i in lo..<(n - 1) {
                let m = magnitudes[i]
                guard m.isFinite, m >= config.minMagnitude else { continue }
                let left = magnitudes[i - 1]
                let right = magnitudes[i + 1]
                guard m >= (left.isFinite ? left : 0),
                      m >= (right.isFinite ? right : 0) else { continue }
                // Neighbourhood mean, peak excluded, poisoned bins excluded.
                let r = Swift.max(1, config.neighborhoodRadius)
                var sum: Float = 0
                var count = 0
                for j in Swift.max(lo, i - r)...Swift.min(n - 1, i + r) where j != i {
                    let v = magnitudes[j]
                    guard v.isFinite else { continue }
                    sum += v
                    count += 1
                }
                guard count > 0 else { continue }
                let mean = sum / Float(count)
                guard mean > 0, m >= mean * config.dominanceRatio else { continue }
                // Harmonic veto: strong energy around 2f = a musical note, not a loop.
                // ±1 because an off-bin note's harmonic lands BESIDE the exact double
                // (#847 review finding 3).
                if i * 2 - 1 < n, windowMax(i * 2 - 1, i * 2 + 1) > m * config.harmonicMaxRatio {
                    continue
                }
                // Subharmonic veto: strong energy around f/2 means THIS peak is the
                // octave of a musical note mid-crescendo — the review's sharpest false
                // positive (finding 1): without this, the fundamental is vetoed but its
                // own 2nd harmonic builds a clean track and gets notched, audibly
                // thinning the voice.
                let s = i / 2
                if s >= lo, windowMax(s - 1, s + 1) > m * config.subharmonicMaxRatio {
                    continue
                }
                let e = (left.isFinite ? left : 0) + m + (right.isFinite ? right : 0)
                found.append(Peak(bin: i, energy: e))
            }
            return found
        }
    }
}
