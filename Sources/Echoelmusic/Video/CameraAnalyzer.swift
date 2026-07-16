#if canImport(AVFoundation)
import Foundation
import AVFoundation
import Accelerate
#if canImport(CoreImage)
import CoreImage
import Observation
#endif

/// Camera-based photoplethysmography (rPPG) analyzer.
///
/// Implements finger-on-lens pulse detection similar to HRV4Training:
/// 1. Detect finger covering the camera (high red, low variance)
/// 2. Extract red channel time series from camera frames
/// 3. Bandpass filter 0.7–4 Hz (42–240 BPM range)
/// 4. Peak detection with quality scoring
/// 5. Calculate HR and RR intervals for HRV (RMSSD)
///
/// Reference: Verkruysse et al. (2008) "Remote plethysmographic imaging"
/// HRV4Training approach: Plews et al. (2017) "Smartphone PPG"
@MainActor
@Observable
final class CameraAnalyzer {

    // MARK: - Published Output

    /// Average frame brightness (0–1), usable for filter modulation
    var brightness: Float = 0.5
    /// Average red channel (0–1), used for pulse detection
    var redChannel: Float = 0.5
    /// Average hue (0–360)
    var dominantHue: Float = 180
    /// Estimated BPM from pulse detection (0 = not detected)
    var estimatedBPM: Double = 0
    /// Confidence of BPM estimate (0–1)
    var bpmConfidence: Double = 0
    /// Whether pulse detection is active
    var isPulseDetecting: Bool = false
    /// Whether finger is detected on the camera lens
    var isFingerDetected: Bool = false
    /// Signal quality indicator (0–1)
    var signalQuality: Double = 0
    /// Latest RR intervals in ms — for HRV calculation
    var rrIntervals: [Double] = []
    /// Calculated RMSSD from camera PPG
    var rmssd: Double = 0

    // MARK: - Diagnostics (device breadcrumb only) — reveal WHICH stage blocks a
    // lock when bpm stays 0: amp≈0 → no pulsatile signal (positioning/torch);
    // peaks<3 with a strong acf → peak-counting issue (rounded waveform); acf low →
    // genuinely weak/aperiodic signal (perfusion/pressure). Not observed.
    @ObservationIgnored private(set) var lastPeakCount: Int = 0
    @ObservationIgnored private(set) var lastAutoStrength: Double = 0
    /// Independent autocorrelation BPM (octave-robust fundamental). Telemetry only —
    /// compared against the peak-count rate to diagnose octave (half/double) errors.
    @ObservationIgnored private(set) var lastAutoBPM: Double = 0
    @ObservationIgnored private(set) var lastFilteredAmplitude: Float = 0
    /// True frame-derived sample rate + window length fed to the autocorrelation —
    /// the two inputs that decide whether `dominantBPM` can lock. A rate far from the
    /// 15 Hz the bandpass is designed for (e.g. dropped/doubled frames) detunes both
    /// the passband and the lag→BPM mapping; surfaced so a device log can show WHY
    /// `acf` reads 0 even with a clean pulse (field finding 2026-06-23).
    @ObservationIgnored private(set) var lastActualRate: Double = 0
    @ObservationIgnored private(set) var lastWindowSize: Int = 0

    /// Frame counter for debugging
    private var frameCount: Int = 0

    /// Throttles the expensive peak scan so it runs ~4 Hz, not every 15 Hz frame —
    /// keeps the main actor free for the UI/tools.
    private var peakTick: Int = 0
    /// Counts samples since pulse start, for a fast DC-baseline warmup.
    private var dcWarmupCount: Int = 0

    /// Last few accepted per-window BPM estimates, for a MEDIAN smoother. rPPG
    /// peak-counting is noisy (a dicrotic notch or a motion bump adds/drops a peak →
    /// a single window jumps the rate, device log: 83→118→89 at a steady finger). A
    /// median of recent windows rejects those one-off excursions far better than the
    /// EMA alone (the EMA still chases a run of bad windows). Kept short so it tracks
    /// real change within a few seconds.
    private var recentBPMs: [Double] = []
    private let recentBPMCapacity = 5

    /// Physiological rate-of-change ceiling for the COMMITTED estimate. A resting
    /// heart cannot swing tens of bpm in a second; when autocorrelation drops out
    /// (acf≈0) the peak-count fallback can ramp the EMA 60→140 in ~2.5 s (device
    /// log 2026-07-02). The slew limiter caps the committed change per REAL second
    /// so a genuine ramp still passes but a runaway can't. Tuned generous enough
    /// (~8 bpm/s) that real exertion changes are not blocked.
    private static let maxBPMChangePerSecond: Double = 8.0
    /// Frame timestamp of the last committed estimate, for the real-time slew delta.
    /// 0 = none yet (first commit, or after a reset) → slew skipped so the lock seeds.
    private var lastEstimateTimestamp: TimeInterval = 0

    /// Recent bandpass-filtered pulse signal, normalized to ~[-1,1], for a live
    /// waveform ("Stimmungsbild"). Empty until samples exist; flat = no signal.
    var recentWaveform: [Float] {
        let n = Swift.min(filteredRedSignal.count, 90)   // ~6 s at 15 Hz
        guard n > 1 else { return [] }
        let slice = Array(filteredRedSignal.suffix(n))
        // vDSP max-magnitude avoids the intermediate `map { abs }` array on this
        // ~10 Hz read (the waveform array itself is the only allocation kept).
        var maxAbs: Float = 0
        vDSP_maxmgv(slice, 1, &maxAbs, vDSP_Length(n))
        let norm = Swift.max(maxAbs, 0.0001)
        return slice.map { $0 / norm }
    }

    // MARK: - Internal State

    /// Process EVERY delivered frame. The capture is locked to ≤30 fps but devices
    /// commonly deliver ~15 fps under torch + `.low` preset; the old "skip every 2nd"
    /// assumed a steady 30 fps and so HALVED the real rate to ~7.5 Hz (device log:
    /// rate=7.5), which detuned the bandpass AND pushed its 4 Hz low-pass past the
    /// 3.75 Hz Nyquist → invalid coefficients, no lock. Using every frame keeps the
    /// rate as high as the camera allows; `effectiveSampleRate` is then corrected to
    /// the MEASURED rate (below) so the filter is always valid for the true rate.
    private let analyzeEveryNthFrame = 1

    /// Nominal starting rate before the one-time measured-rate correction.
    private static let defaultSampleRate: Double = 15.0

    /// Effective sample rate — starts at the nominal 15 Hz and is corrected ONCE to
    /// the true measured frame rate (so the bandpass is designed for reality, not an
    /// assumption). `var` because the filter re-tunes to it.
    private var effectiveSampleRate: Double = CameraAnalyzer.defaultSampleRate
    /// Set true after the one-time re-tune to the measured rate (avoids thrashing).
    private var filterRateAdapted = false

    // Raw and filtered signal buffers — maintained in sync
    private var rawRedSignal: [Float] = []
    private var filteredRedSignal: [Float] = []  // Running filtered signal (avoids O(n²) re-filtering)
    private var signalTimestamps: [TimeInterval] = []
    private let maxSignalLength = 600 // ~40 seconds at 15Hz

    // DC offset removal — slow-tracking mean prevents DC from leaking into bandpass
    private var dcEstimate: Float = 0

    // Bandpass filter state (2nd order Butterworth, 0.7–4 Hz)
    private var bpState = BandpassState()

    // Butterworth bandpass coefficients. Recomputed once when the true frame rate is
    // measured (var, not let) so the filter matches the real sample rate.
    private var bpc: BandpassCoefficients

    // Peak detection
    private var peakIndices: [Int] = []
    private var lastPeakTime: TimeInterval = 0

    // Finger detection — 30 frames = 2 seconds at 15Hz for robust detection
    private var fingerDetectionBuffer: [Bool] = []
    private let fingerDetectionWindow = 30
    /// Running count of `true` frames in the window, kept in sync on push/pop so the
    /// per-frame detection is O(1) (no `filter { $0 }.count` allocation at ~15 Hz).
    private var fingerTrueCount = 0

    // MARK: - Bandpass Filter Coefficients (pre-computed, constant)

    /// Pre-computed 2nd-order Butterworth bandpass coefficients
    private struct BandpassCoefficients {
        // High-pass at 0.7 Hz
        let hpA0, hpA1, hpA2, hpB1, hpB2: Float
        // Low-pass at 4.0 Hz
        let lpA0, lpA1, lpA2, lpB1, lpB2: Float

        init(sampleRate: Float) {
            // High-pass at 0.7 Hz: bilinear transform Butterworth 2nd order
            let wHP = tanf(Float.pi * 0.7 / sampleRate)
            let wHP2 = wHP * wHP
            let a0hp = 1.0 / (1.0 + 1.414 * wHP + wHP2)
            hpA0 = a0hp;  hpA1 = -2.0 * a0hp;  hpA2 = a0hp
            hpB1 = 2.0 * (wHP2 - 1.0) * a0hp
            hpB2 = (1.0 - 1.414 * wHP + wHP2) * a0hp
            // Low-pass at 4.0 Hz — but NEVER above the Nyquist limit. At low frame
            // rates (e.g. 7.5 Hz, Nyquist 3.75 Hz) a fixed 4 Hz cutoff makes the
            // bilinear prewarp tanf() go past π/2 → negative/garbage coefficients →
            // a broken filter. Clamp the cutoff to 0.45·rate so it is always valid.
            let lpHz = Swift.min(Float(4.0), sampleRate * 0.45)
            let wLP = tanf(Float.pi * lpHz / sampleRate)
            let wLP2 = wLP * wLP
            let denom = 1.0 + 1.414 * wLP + wLP2
            lpA0 = wLP2 / denom;  lpA1 = 2.0 * wLP2 / denom;  lpA2 = wLP2 / denom
            lpB1 = 2.0 * (wLP2 - 1.0) / denom
            lpB2 = (1.0 - 1.414 * wLP + wLP2) / denom
        }
    }

    // MARK: - Bandpass Filter State

    /// 2nd-order IIR bandpass filter state (Butterworth)
    /// Passband: 0.7 Hz (42 BPM) to 4.0 Hz (240 BPM)
    private struct BandpassState {
        // High-pass at 0.7 Hz (removes DC drift, respiration)
        var hp_x1: Float = 0
        var hp_x2: Float = 0
        var hp_y1: Float = 0
        var hp_y2: Float = 0

        // Low-pass at 4.0 Hz (removes noise, motion artifact)
        var lp_x1: Float = 0
        var lp_x2: Float = 0
        var lp_y1: Float = 0
        var lp_y2: Float = 0
    }

    // MARK: - Init

    init() {
        bpc = BandpassCoefficients(sampleRate: Float(Self.defaultSampleRate))
    }

    // MARK: - Pulse Detection (Bandpass + Peak)
    // NOTE: the live path is processExtractedRGB(...) below — the publisher averages
    // the centre region on the capture queue and feeds RGB here. The old
    // analyzeFrame/analyzePixelBuffer CVPixelBuffer path (and its unused
    // filterModulation/ModulationMode machinery) was dead code and was removed.

    /// Process pre-extracted RGB values. `timestamp` is captured when the FRAME arrived (on
    /// the capture queue), not when this runs — the samples are now buffered and drained in a
    /// batch by the 10 Hz publish loop (instead of one MainActor Task per frame, which flooded
    /// the main actor and froze the UI while biofeedback ran), so the real per-frame time must
    /// travel with the sample or the sample-rate estimate would collapse.
    func processExtractedRGB(avgR: Float, avgG: Float, avgB: Float, timestamp: TimeInterval) {
        frameCount += 1

        // Frame skipping: process every 2nd frame at ~30fps = 15Hz effective sample rate.
        // The bandpass filter coefficients are designed for effectiveSampleRate (15Hz).
        // Without skipping, cutoff frequencies would be wrong → broken pulse detection.
        guard frameCount % analyzeEveryNthFrame == 0 else { return }

        brightness = (avgR + avgG + avgB) / 3.0
        redChannel = avgR

        // Log every 30 processed frames (~2 sec at 15Hz effective)
        if (frameCount / analyzeEveryNthFrame) % 30 == 0 {
            log.log(.info, category: .biofeedback,
                "rPPG frame \(frameCount): R=\(String(format:"%.2f",avgR)) G=\(String(format:"%.2f",avgG)) B=\(String(format:"%.2f",avgB)) finger=\(isFingerDetected) pulse=\(isPulseDetecting) bpm=\(Int(estimatedBPM))")
        }

        // Finger detection: red DOMINANCE (ratios) is the real signature of a
        // finger over a torch-lit lens; the absolute red floor only rejects a dark
        // frame. Device logs showed a clean fingertip sitting at R≈0.35 (dim, torch
        // 0.6) — red-dominant and ratio-passing, but blocked by an over-tight 0.4
        // floor so the pulse never locked. Lower the floor to 0.28; the 1.2×/1.3×
        // ratio gates still keep a non-red scene out.
        // Overexposed frame (all channels clipped near white): the finger IS on the
        // lens but pressed too hard / the torch washed it out. The red-dominance test
        // would FAIL here (R≈G≈B≈1) and drop the lock, which made the exposure
        // re-settle and reset BPM to 0 (device log 2026-06-23: R=0.98 → finger=no →
        // re-settling → re-lock churn). Instead, treat saturation as "finger present,
        // signal temporarily bad": hold the lock, decay quality, and skip feeding the
        // clipped sample into the pulse buffer so the rate stays put through it.
        let isSaturated = Swift.min(avgR, avgG, avgB) > 0.92
        // Per-frame finger test with red-floor HYSTERESIS — extracted to a pure static so
        // the acquire-hard/hold-easy behaviour is unit-tested (see CameraAnalyzerOctaveTests).
        // A locked, corroborated pulse (conf ≥ 0.35 = the publisher's "locked"
        // boundary) eases the hold floor — see isFingerFrame's device-log rationale.
        let isFingerFrame = Self.isFingerFrame(avgR: avgR, avgG: avgG, avgB: avgB,
                                               wasDetected: isFingerDetected,
                                               pulseCorroborated: bpmConfidence >= 0.35)
        updateFingerDetection(isFingerFrame)

        // Pulse detection
        if isPulseDetecting && isFingerDetected {
            if isSaturated {
                signalQuality = max(0, signalQuality - 0.02)   // hold lock, drop quality
            } else {
                processPulseSignal(avgR: avgR, timestamp: timestamp)
            }
        } else if isPulseDetecting && !isFingerDetected {
            bpmConfidence = max(0, bpmConfidence - 0.02)
            signalQuality = max(0, signalQuality - 0.02)
            // Lock truly lost (not a brief flicker the hysteresis absorbs) → clear the
            // held values so the UI never shows a phantom rate. Device log: bpm stuck
            // at 66 for 60s+ at conf 0 because estimatedBPM was never reset on loss.
            if bpmConfidence < 0.05 {
                estimatedBPM = 0
                rmssd = 0
                rrIntervals.removeAll()
                recentBPMs.removeAll()   // don't seed the next lock from a stale median
            }
        }
    }

    /// Push a finger/no-finger frame into the sliding window and update
    /// `isFingerDetected`, maintaining a running true-count so the decision is O(1)
    /// per frame (replaces a `filter { $0 }.count` allocation at ~15 Hz). Shared by
    /// both the pixel-buffer and pre-extracted-RGB analysis paths.
    private func updateFingerDetection(_ isFingerFrame: Bool) {
        fingerDetectionBuffer.append(isFingerFrame)
        if isFingerFrame { fingerTrueCount += 1 }
        if fingerDetectionBuffer.count > fingerDetectionWindow {
            if fingerDetectionBuffer.removeFirst() { fingerTrueCount -= 1 }
        }
        // Hysteresis: harder to acquire (half the window) than to hold (a quarter),
        // so a brief glare/pressure flicker doesn't drop the lock and reset confidence.
        let needed = isFingerDetected ? (fingerDetectionWindow / 4) : (fingerDetectionWindow / 2)
        isFingerDetected = fingerTrueCount > needed
    }

    // MARK: - Pulse Signal Processing

    /// Toggle pulse detection on/off
    func togglePulseDetection() {
        isPulseDetecting.toggle()
        if isPulseDetecting {
            resetPulseState()
        }
    }

    /// Start pulse detection (without toggle)
    func startPulseDetection() {
        guard !isPulseDetecting else { return }
        isPulseDetecting = true
        resetPulseState()
    }

    /// Stop pulse detection
    func stopPulseDetection() {
        isPulseDetecting = false
    }

    /// Flush the rolling pulse window WITHOUT toggling detection off — for use after a
    /// camera stall recovery (device log 1783442844: after a stall + exposure re-lock,
    /// the window held pre-stall samples PLUS the huge brightness-step artifact the
    /// re-lock injected, so `amp` froze at 0.3618 and confidence stayed 0.00 for the
    /// whole ~10 s window; with the camera re-stalling every few seconds it never
    /// flushed, so the pulse — locked cleanly at conf 0.90 before the stall — never
    /// came back). Startup began from an EMPTY window and locked fine; a recovery must
    /// do the same. Only meaningful while detecting (no-op otherwise).
    func resetForRecovery() {
        guard isPulseDetecting else { return }
        resetPulseState()
    }

    private func resetPulseState() {
        rawRedSignal.removeAll()
        filteredRedSignal.removeAll()
        signalTimestamps.removeAll()
        peakIndices.removeAll()
        rrIntervals.removeAll()
        bpState = BandpassState()
        dcEstimate = 0
        dcWarmupCount = 0
        peakTick = 0
        recentBPMs.removeAll()
        lastEstimateTimestamp = 0
        estimatedBPM = 0
        bpmConfidence = 0
        signalQuality = 0
        rmssd = 0
        lastPeakCount = 0
        lastAutoStrength = 0
        lastAutoBPM = 0
        lastFilteredAmplitude = 0
        lastActualRate = 0
        lastWindowSize = 0
        // Re-measure the frame rate next session; restore the nominal filter until then.
        filterRateAdapted = false
        effectiveSampleRate = Self.defaultSampleRate
        bpc = BandpassCoefficients(sampleRate: Float(Self.defaultSampleRate))
    }

    private func processPulseSignal(avgR: Float, timestamp: TimeInterval) {
        let now = timestamp

        // DC offset removal. Warm up FAST for the first ~1s (τ≈0.7s) so the
        // baseline — and thus the bandpass — settles in ~1s instead of ~6s (the
        // main cause of a slow first lock), then track slowly (τ≈6.6s) to stay
        // immune to respiration drift.
        dcWarmupCount += 1
        let dcCoeff: Float = dcWarmupCount < Int(effectiveSampleRate) ? 0.90 : 0.99
        dcEstimate = dcEstimate * dcCoeff + avgR * (1 - dcCoeff)
        let dcRemoved = avgR - dcEstimate

        // Filter DC-removed signal and store alongside raw
        let filtered = applyBandpassFilter(dcRemoved)

        rawRedSignal.append(avgR)
        filteredRedSignal.append(filtered)
        signalTimestamps.append(now)

        if rawRedSignal.count > maxSignalLength {
            rawRedSignal.removeFirst()
            filteredRedSignal.removeFirst()
            signalTimestamps.removeFirst()
            peakIndices = peakIndices.compactMap { $0 > 0 ? $0 - 1 : nil }
        }

        // ── One-time re-tune of the bandpass to the TRUE frame rate ──────────────
        // The assumed 15 Hz is often wrong (device log: real rate 7.5–15 Hz). A
        // mismatch detunes the filter and, below ~8 Hz, breaks it (4 Hz low-pass past
        // Nyquist). Once enough samples give a stable rate, re-design the filter for it
        // and restart the buffers so the window refills with correctly-filtered data.
        // On a clean 15 Hz device the rate matches and this is a no-op.
        if !filterRateAdapted, signalTimestamps.count >= 30,   // ~2 s, past DC warmup
           let firstT = signalTimestamps.first, let lastT = signalTimestamps.last, lastT > firstT {
            let measured = Double(signalTimestamps.count - 1) / (lastT - firstT)
            if measured.isFinite, measured >= 4, measured <= 60,
               abs(measured - effectiveSampleRate) / effectiveSampleRate > 0.15 {
                effectiveSampleRate = measured
                bpc = BandpassCoefficients(sampleRate: Float(measured))
                bpState = BandpassState()
                rawRedSignal.removeAll(keepingCapacity: true)
                filteredRedSignal.removeAll(keepingCapacity: true)
                signalTimestamps.removeAll(keepingCapacity: true)
                peakIndices.removeAll(keepingCapacity: true)
                dcEstimate = 0
                dcWarmupCount = 0
            }
            filterRateAdapted = true
        }

        // Need ~2s of data before the first estimate (was 3s — faster first lock).
        guard rawRedSignal.count >= Int(effectiveSampleRate * 2) else { return }

        // THROTTLE the expensive peak scan + quality update to ~4 Hz. Running the
        // O(n) scan with its allocations every 15 Hz frame on the @MainActor was
        // starving the UI ("tools don't work" once the finger path went live). The
        // per-sample IIR filtering above still runs every frame, so the signal is
        // intact — only the heavy scan is rate-limited.
        peakTick += 1
        guard peakTick % 4 == 0 else { return }

        // Peak detection uses stored filtered signal (O(n) vs previous O(n²))
        detectPeaks(timestamp: now)
        updateSignalQuality()
    }

    /// 2nd-order IIR bandpass filter (0.7–4.0 Hz) using pre-computed coefficients
    private func applyBandpassFilter(_ input: Float) -> Float {
        let hpOut = bpc.hpA0 * input + bpc.hpA1 * bpState.hp_x1 + bpc.hpA2 * bpState.hp_x2
            - bpc.hpB1 * bpState.hp_y1 - bpc.hpB2 * bpState.hp_y2
        bpState.hp_x2 = bpState.hp_x1;  bpState.hp_x1 = input
        bpState.hp_y2 = bpState.hp_y1;  bpState.hp_y1 = hpOut

        let lpOut = bpc.lpA0 * hpOut + bpc.lpA1 * bpState.lp_x1 + bpc.lpA2 * bpState.lp_x2
            - bpc.lpB1 * bpState.lp_y1 - bpc.lpB2 * bpState.lp_y2
        bpState.lp_x2 = bpState.lp_x1;  bpState.lp_x1 = hpOut
        bpState.lp_y2 = bpState.lp_y1;  bpState.lp_y1 = lpOut

        return lpOut
    }

    // MARK: - Peak Detection

    /// Adaptive threshold peak detection using stored filtered signal (O(n) per call)
    private func detectPeaks(timestamp: TimeInterval) {
        let n = filteredRedSignal.count
        guard n >= 5 else { return }

        let windowSize = min(n, Int(effectiveSampleRate * 10))
        let startIdx = n - windowSize
        let window = Array(filteredRedSignal[startIdx..<n])

        // TRUE sample rate from timestamps (don't assume 15 Hz) so every BPM derived
        // here — peak-counting and autocorrelation — is correct regardless of frame rate.
        let span = signalTimestamps[n - 1] - signalTimestamps[startIdx]
        let actualRate = span > 0 ? Double(windowSize - 1) / span : effectiveSampleRate
        lastActualRate = actualRate
        lastWindowSize = windowSize

        // Robust periodicity once per scan — reused for telemetry, the fresh-lock
        // cross-check, and the few-peaks fallback (avoids recomputing it twice).
        //
        // Detrend ONLY the periodicity input (RPPGConditioning.linearDetrend — tested):
        // PulsePeriodEstimator removes the MEAN but not the SLOPE, so a slow DC ramp
        // (breathing / exposure settle) that survives the band filter still swamps the
        // small cardiac AC in the autocorrelation — the device "no-lock" (finger=yes,
        // high amp, acf≈0.1, bpm=0 the whole run). Killing the linear trend restores the
        // cardiac peak for the estimator, WITHOUT touching the amplitude-calibrated motion
        // gates below (they stay tuned on the filtered `window`). Finishes the built-but-
        // unwired RPPGConditioning core it was written for (#14). Device-verify pending.
        let auto = PulsePeriodEstimator.dominantBPM(
            RPPGConditioning.linearDetrend(window), sampleRate: actualRate)
        lastAutoStrength = auto?.strength ?? 0
        lastAutoBPM = auto?.bpm ?? 0

        // Adaptive threshold: 55% of amplitude range
        var maxAmp: Float = 0
        vDSP_maxv(window, 1, &maxAmp, vDSP_Length(windowSize))
        var minAmp: Float = 0
        vDSP_minv(window, 1, &minAmp, vDSP_Length(windowSize))
        let amplitude = maxAmp - minAmp
        lastFilteredAmplitude = amplitude
        // Reject flat signal — no finger contact
        guard amplitude > 0.0003 else { lastPeakCount = 0; return }
        // Reject MOTION/pressure artifacts: a real pulse AC is a small fraction of the red
        // DC, so an amplitude this large is the finger moving / changing pressure / lifting
        // — its steady peak count would otherwise earn a false "agreement" lock (device log
        // amp≈0.76, acf≈0.2 → false lock at 105 bpm). Skip the window AND bleed confidence
        // so a motion run can neither earn nor hold a lock (drops below the lock gate fast).
        if Self.isMotionAmplitude(amplitude) {
            lastPeakCount = 0
            // Bleed confidence for a motion window — but this runs PER SAMPLE, and the
            // publish loop drains ~15–30 samples per tick, so a flat 0.6 compounds to ≈0 and
            // wipes a good lock in ONE tick. Device log 2026-07-02: a clean conf-0.96 / bpm-50
            // lock (acf 0.5–0.7) collapsed to conf 0.00 the instant amp brushed 0.21 during a
            // small pressure change — the autocorrelation still saw the pulse perfectly. So
            // when the independent autocorrelation still confirms a strong, steady pulse
            // (acf > 0.4), bleed GENTLY (a 1–2 s wobble survives the lock gate); a true motion
            // / false-lock window (weak acf, e.g. amp≈0.76 acf≈0.2) still bleeds hard.
            bpmConfidence *= Self.motionBleed(autoStrength: lastAutoStrength)
            return
        }
        // SOFT motion: elevated amplitude with NO corroborating periodicity (a wobble the
        // peak-counter self-agrees into a false, drifting rate — device log 2026-07-03,
        // 54→82 at amp≈0.06/acf=0). SKIP the window (so the estimate holds instead of
        // drifting) and bleed confidence GENTLY per sample — a sustained ripple falls below
        // the display/lock gate within a second or two, while a single-window blip on a real
        // lock barely dents (0.9 vs the hard gate's 0.6). Real locks carry autocorrelation
        // and never enter this band, so a genuine pulse is untouched.
        if Self.isUncorroboratedRipple(amplitude: amplitude, autoStrength: lastAutoStrength) {
            lastPeakCount = 0
            bpmConfidence *= 0.9
            return
        }
        let threshold = minAmp + amplitude * 0.55

        // Minimum inter-beat interval — ADAPTIVE refractory (rejects the dicrotic notch;
        // see refractorySeconds). Uses the autocorrelation fundamental set above; falls back
        // to 300 ms (≤200 bpm) when no plausible period is available.
        let minPeakDistance = Int(effectiveSampleRate * Self.refractorySeconds(autoBPM: lastAutoBPM))

        // Find local maxima above threshold
        var newPeaks: [Int] = []
        for i in 2..<(windowSize - 2) {
            let val = window[i]
            guard val > threshold else { continue }
            if val > window[i-1] && val > window[i-2] && val > window[i+1] && val > window[i+2] {
                if let last = newPeaks.last, (i - last) < minPeakDistance { continue }
                newPeaks.append(i)
            }
        }
        lastPeakCount = newPeaks.count

        guard newPeaks.count >= 3 else { fallbackBPM(auto); return }

        var intervals: [Double] = []
        for j in 1..<newPeaks.count {
            let dt = signalTimestamps[startIdx + newPeaks[j]] - signalTimestamps[startIdx + newPeaks[j-1]]
            guard dt > 0.3 && dt < 1.5 else { continue }
            intervals.append(dt)
        }

        guard intervals.count >= 2 else { fallbackBPM(auto); return }

        // IQR outlier rejection
        let sorted = intervals.sorted()
        let cnt = sorted.count
        let q1 = sorted[cnt / 4]
        let q3 = sorted[(cnt * 3) / 4]
        let iqr = q3 - q1
        let cleanIntervals = intervals.filter {
            $0 > (q1 - 1.5 * iqr) && $0 < (q3 + 1.5 * iqr)
        }

        guard !cleanIntervals.isEmpty else { return }

        let avgInterval = cleanIntervals.reduce(0, +) / Double(cleanIntervals.count)
        let bpm = 60.0 / avgInterval
        guard bpm > 40 && bpm < 200 else { return }

        // FRESH-LOCK corroboration (re-grip robustness, device-log feedback): right
        // after the finger is re-placed, motion settling can peak-count a HARMONIC
        // (extra peaks → a shorter interval → a false-high BPM, e.g. 180 at rest).
        // When there is no prior estimate (estimatedBPM == 0), cross-check the new
        // rate against the independent autocorrelation period; if a CONFIDENT
        // periodicity disagrees by >20 %, the discrete count is the suspect one — so
        // SEED FROM THE AUTOCORRELATION rather than discarding the window. The old
        // code `return`ed here, which left bpm=0 forever when peak-counting kept
        // catching a dicrotic notch (device log: finger=yes, q≈0.30, bpm=0 all run).
        if estimatedBPM == 0,
           let auto, auto.strength > 0.4,
           abs(bpm - auto.bpm) / auto.bpm > 0.2 {
            estimatedBPM = auto.bpm
            bpmConfidence = bpmConfidence * 0.82 + min(1, (auto.strength - 0.4) / 0.4) * 0.18
            rrIntervals = cleanIntervals.map { $0 * 1000.0 }
            if rrIntervals.count >= 3 { calculateRMSSD() }
            return
        }

        let variance = cleanIntervals.reduce(0.0) { $0 + ($1 - avgInterval) * ($1 - avgInterval) }
            / Double(cleanIntervals.count)
        let cv = sqrt(variance) / avgInterval

        // Confidence combines within-window regularity (CV) with run-to-run BPM
        // STABILITY. rPPG inter-beat intervals are noisier than contact PPG, so a
        // CV-only score (1 − cv·3) stayed under the lock gate even while the BPM sat
        // rock-steady at ~58 for minutes (device log) — confidence never rose. A BPM
        // that agrees window-to-window is the stronger trust signal, so it can carry
        // confidence on its own.
        let cvConf = max(0, min(1, 1.0 - cv * 2.0))
        let agreement = estimatedBPM > 0
            ? max(0, 1.0 - abs(bpm - estimatedBPM) / 12.0)
            : cvConf
        let confidence = max(cvConf, agreement)

        // STABILISE before committing: fold octave errors toward the running rate,
        // then take the MEDIAN of the last few windows. This is what removes the
        // 83→118→89 jumpiness in the device log — a lone noisy window can no longer
        // yank the published BPM; a real change still carries once it persists across
        // a couple of windows.
        let target = stabilisedBPM(bpm)

        let prevEstimate = estimatedBPM
        estimatedBPM = estimatedBPM == 0 ? target : estimatedBPM * 0.80 + target * 0.20
        // AUTOCORRELATION TRUST (device-log feedback): the dicrotic notch can add an
        // extra peak per beat, inflating the discrete count by ~1.3–1.7× — a NON-octave
        // error `octaveCorrected` (×2/×0.5 bands) deliberately won't touch. The log
        // showed pk-count bpm jumping 132/100/79 while a STRONG, steady autocorrelation
        // sat at 75–79 (acf 0.74–0.87). When that periodicity is confident, pull the
        // estimate toward it — gently, weighted by acf strength — so peak-count noise
        // can't yank the published rate while a clean fundamental is being ignored.
        // Weak acf → no pull (peak-counting still leads at low SNR; the fingertip case).
        estimatedBPM = Self.autoTrust(estimate: estimatedBPM, autoBPM: lastAutoBPM, autoStrength: lastAutoStrength)
        // PHYSIOLOGICAL SLEW LIMIT (audit 2026-07-02, P0.1): cap the committed change to
        // maxBPMChangePerSecond over the REAL elapsed time since the last commit. This is
        // the load-bearing fix for the acf=0 runaway (60→140 with the finger still on) —
        // it directly bounds rate-of-change regardless of which guard failed. A first
        // commit or a re-seed after full loss (prevEstimate==0) is exempt so the lock
        // still snaps in. dt is capped at 2 s so one long gap can't grant a huge jump.
        var slewClamped = false
        if prevEstimate > 0, lastEstimateTimestamp > 0 {
            let dt = Swift.min(2.0, Swift.max(0, timestamp - lastEstimateTimestamp))
            let limited = Self.slewLimited(previous: prevEstimate, target: estimatedBPM,
                                           maxDelta: Self.maxBPMChangePerSecond * dt)
            slewClamped = abs(limited - estimatedBPM) > 0.5
            estimatedBPM = limited
        }
        lastEstimateTimestamp = timestamp
        // Ramp on every valid window (no hard gate): a clean, stable pulse locks in
        // a few seconds; brief noisy windows are smoothed by the EMA, not ignored.
        bpmConfidence = bpmConfidence * 0.82 + confidence * 0.18
        // SOFT confidence penalty when the estimate tried to jump faster than physiology
        // allows: a clamped window is inherently untrustworthy, so don't let the
        // agreement metric (which rewards self-consistency, audit finding) keep a drifting
        // rate "locked". This is self-gating — a steady low-SNR fingertip lock never
        // clamps, so it is never penalised; only an implausible jump is. Recovers at once.
        if slewClamped { bpmConfidence *= 0.85 }

        rrIntervals = cleanIntervals.map { $0 * 1000.0 }
        if rrIntervals.count >= 3 { calculateRMSSD() }
    }

    /// Octave-fold a raw window BPM toward the running estimate, then return the
    /// median of the recent accepted windows. Pure post-processing on the discrete
    /// peak-count rate (the autocorrelation strength is ~0 at typical fingertip SNR,
    /// so it can't be relied on to carry the lock — the device log shows acf≈0 while
    /// peak-counting alone produced the rate).
    private func stabilisedBPM(_ raw: Double) -> Double {
        var bpm = raw
        // Harmonic guard: peak-counting a dicrotic notch doubles the count (≈2×) and
        // a missed beat halves it (≈0.5×). Fold ONLY in true harmonic territory — a
        // RATIO gate, not nearest-candidate. A nearest-candidate fold would mis-read a
        // genuine 1.5–2× HR ramp (e.g. 60→110) as a doubled old rate and trap the lock
        // at the old octave (dsp-review finding); the 0.625–1.6 band is left untouched
        // so a real heart-rate change always passes through.
        if estimatedBPM > 0 {
            let ratio = raw / estimatedBPM
            if ratio > 1.6, raw / 2.0 >= 40 { bpm = raw / 2.0 }          // likely doubled
            else if ratio < 0.625, raw * 2.0 <= 200 { bpm = raw * 2.0 }  // likely halved
        }
        // Octave anchor (task #6): correct GRADUAL half/double drift the running-estimate
        // fold above can't see (each step stays inside 0.625…1.6 yet accumulates). Done
        // at the SOURCE — the raw window rate — against the octave-robust autocorrelation
        // fundamental, so the median + EMA below then operate on octave-correct values
        // (no tug-of-war between a half-rate target and a corrective nudge).
        bpm = Self.octaveCorrected(raw: bpm, autoBPM: lastAutoBPM, autoStrength: lastAutoStrength)
        recentBPMs.append(bpm)
        if recentBPMs.count > recentBPMCapacity { recentBPMs.removeFirst() }
        let sorted = recentBPMs.sorted()
        return sorted[sorted.count / 2]
    }

    /// Octave anchor against the octave-robust autocorrelation fundamental — the guard
    /// for GRADUAL half/double drift (task #6). The per-window ratio fold in
    /// `stabilisedBPM` only trips on a SUDDEN jump (raw outside 0.625…1.6 of the running
    /// estimate); a slow drift where each window steps just inside that band accumulates
    /// undetected until the locked rate sits a full octave off. Autocorrelation reports
    /// the TRUE fundamental regardless of peak-count octave, so when a CONFIDENT
    /// periodicity says the estimate is ~½× or ~2× the fundamental, nudge it back.
    ///
    /// Conservative by construction: it acts ONLY in explicit octave bands (raw ≈ ½× or
    /// ≈ 2× the fundamental) — never in the 0.625…1.6 "genuine HR change" band — and an
    /// octave error is EXACTLY a factor of two, so it corrects by ×2 / ×0.5 (gated on a
    /// confident autocorrelation), not an arbitrary blend. Pure (no state) → unit-
    /// testable on Linux.
    nonisolated static func octaveCorrected(raw: Double, autoBPM: Double, autoStrength: Double) -> Double {
        guard raw > 0, autoBPM > 40, autoStrength > 0.45 else { return raw }
        let r = raw / autoBPM
        if r > 0.42 && r < 0.6,  raw * 2.0 <= 220 { return raw * 2.0 }   // raw ≈ ½× → double
        if r > 1.7 && r < 2.4,   raw * 0.5 >= 35  { return raw * 0.5 }   // raw ≈ 2×  → halve
        return raw
    }

    /// Confidence-weighted pull of the running estimate toward the autocorrelation
    /// fundamental — the guard for NON-octave peak-count inflation (the dicrotic-notch
    /// case `octaveCorrected` can't address: an extra peak per beat scales the count by
    /// ~1.3–1.7×, which is neither ≈2× nor ≈½×). Autocorrelation reports the true
    /// fundamental period directly, so when it is usable we lean the estimate that way.
    ///
    /// STRENGTHENED again (device logs 2026-06-30): across THREE long reads the
    /// autocorrelation `auto` sat steady at 50–65 bpm (acf up to 0.83) while discrete
    /// peak-counting wandered 62→106→72 — and `auto` was already TRUSTWORTHY down to
    /// acf≈0.4 (it held 63–65 there), a band the previous 0.5 gate ignored, so those
    /// moderate windows kept following the noisy count. Now: gate at 0.4 (was 0.5), ramp
    /// 0.4→0.85 to the same 0.8 cap, so a usable periodicity steadies the readout from the
    /// moment it becomes reliable. The EMA + octave guards upstream still protect against an
    /// autocorrelation octave slip. Pure (no state) → unit-testable on Linux.
    nonisolated static func autoTrust(estimate: Double, autoBPM: Double, autoStrength: Double) -> Double {
        guard estimate > 0, autoBPM > 40, autoStrength > 0.4 else { return estimate }
        let w = min(0.8, (autoStrength - 0.4) / 0.45 * 0.8)
        return estimate * (1 - w) + autoBPM * w
    }

    /// Clamp `target` to within `maxDelta` of `previous` — the physiological slew
    /// limiter (audit 2026-07-02, P0.1). `maxDelta <= 0` (no time elapsed) returns
    /// `target` unchanged. Pure (no state) → unit-testable on Linux.
    nonisolated static func slewLimited(previous: Double, target: Double, maxDelta: Double) -> Double {
        guard maxDelta > 0 else { return target }
        return Swift.min(previous + maxDelta, Swift.max(previous - maxDelta, target))
    }

    /// Whether a bandpass-filtered window amplitude is MOTION, not pulse. The red channel
    /// is normalised ~[0,1]; a real fingertip pulse AC is a small fraction of the DC. An
    /// amplitude this large means the finger moved / changed pressure / lifted — a motion
    /// artifact whose steady peak count can otherwise earn a false "agreement" lock.
    /// Gate tightened 0.25 → 0.20 (device logs 2026-06-30): real locks topped out at amp
    /// ≈0.16 (the strongest clean fingertip pulse), while a hard-press / re-grip published
    /// WRONG rates at amp 0.22–0.33 that the old 0.25 gate let through (e.g. bpm 70 at
    /// amp 0.32, conf 0.64). 0.20 cleanly separates the two (1.25× over the 0.16 ceiling)
    /// without rejecting any observed real pulse. Pure → Linux-testable.
    nonisolated static func isMotionAmplitude(_ amplitude: Float) -> Bool {
        amplitude > 0.20
    }

    /// A mid-amplitude window with NO corroborating periodicity — a MOTION RIPPLE the
    /// peak-counter can still turn into a steady, self-agreeing (false) rate. Device log
    /// 2026-07-03: with a good lock already at 54 bpm, a finger wobble produced amp≈0.06 /
    /// acf=0.00 / auto=0, the peak-count drifted 54→69→82, and because each window agreed
    /// with the (also drifting) estimate, `agreement` pushed confidence to 0.78 — a visible
    /// pulse jump. It sits BELOW the hard motion gate (0.20) so `isMotionAmplitude` misses it.
    ///
    /// Discriminator: on this device EVERY real lock — even at low SNR — carried a real
    /// autocorrelation (auto 51–56, acf 0.3–0.8); only motion gives meaningful amplitude with
    /// ZERO periodicity. So the gate is amplitude clearly above the resting-lock AC (≈0.025)
    /// AND essentially no autocorrelation. The AND keeps a genuine pulse out of the band:
    /// a low-amplitude steady lock (amp < 0.05) and any window with some periodicity
    /// (autoStrength ≥ 0.15) both pass through untouched. Pure → Linux-testable.
    ///
    /// NOTE (device-verify): a hypothetical device whose real pulse has BOTH elevated
    /// amplitude AND ~zero autocorrelation would be bled here; none observed (this device's
    /// real locks always corroborate). Reversible if a future log shows a real lock caught.
    nonisolated static func isUncorroboratedRipple(amplitude: Float, autoStrength: Double) -> Bool {
        amplitude > 0.05 && amplitude <= 0.20 && autoStrength < 0.15
    }

    /// Per-sample confidence multiplier for a motion-amplitude window. Applied once per
    /// analysed sample (the drain feeds ~15–30/tick), so it MUST stay close to 1 for the
    /// keep case or it compounds to ≈0 in a single tick. When the independent autocorrelation
    /// still confirms a strong, steady pulse (acf > 0.4), a brief pressure blip on a good lock
    /// bleeds only slightly (0.98 → ~0.55–0.74 across a full tick, well above the 0.35 gate);
    /// a genuine motion / false-lock window (weak acf) still bleeds hard (0.6 → collapses fast).
    /// Device log 2026-07-02: this is what stops a conf-0.96 lock dying the instant amp≈0.21.
    nonisolated static func motionBleed(autoStrength: Double) -> Double {
        autoStrength > 0.4 ? 0.98 : 0.6
    }

    /// Per-frame finger-presence test with red-floor HYSTERESIS (acquire hard, hold easy) —
    /// mirrors the frame-count window's own hysteresis. Device log 2026-07-02: a lit finger
    /// sat at R≈0.22–0.37, oscillating ACROSS a single 0.28 floor every ~8 s → `finger`
    /// flip-flopped yes/no, which both wiped the BPM state (the conf<0.05 reset) and gapped
    /// the pulse buffer (no samples fed while finger=no) → acf=0.00, bpm never locked. It was
    /// a limit cycle: finger-loss dropped the exposure lock, the re-lock brightened R back
    /// over 0.28, repeat. Holding finger-present down to a lower floor once acquired
    /// keeps the window continuous so the pulse can actually lock; the 1.2×/1.3× red-dominance
    /// gates still reject a non-finger scene at either floor, and a fully saturated frame (all
    /// channels clipped, finger pressed too hard) still counts as present. Pure → Linux-testable.
    ///
    /// Hold floor 0.18 → 0.12 (device log 2026-07-15, build 2361, session 2: 92 s NO lock):
    /// the app's OWN strict-dark exposure lock freezes exposure at bright≈0.08–0.10, which
    /// puts a genuinely-held finger at R≈0.15–0.17 — below the old 0.18 hold floor. Same
    /// limit cycle one level darker: sub-floor R → finger=no → window flush → re-acquire
    /// needs 0.28 which the dark lock never reaches. Session 3 of the same log proved
    /// bright 0.10 LOCKS (q 0.97, conf 0.96) when the detector merely keeps holding — so
    /// the hold floor must sit BELOW the dark lock's own R output, and the ACQUIRE floor
    /// stays hard at 0.28 (acquisition still demands a clearly lit finger).
    ///
    /// `pulseCorroborated` (device log 2026-07-16, build 2382 — the floor chase's
    /// third rung): the pulse LOCKED at conf 0.87 / bpm 64, then the dark exposure
    /// lock kept decaying R 0.16→0.11 (bright 0.04, G+B≈0.01 — still massively
    /// red-dominant) → R fell below the 0.12 hold floor → finger=no → full reset
    /// 2 s AFTER locking. Lowering the floor again (0.28→0.18→0.12→…) just chases
    /// the exposure lock downward. Instead: while a real periodicity is being
    /// MEASURED (the caller passes bpmConfidence ≥ lock threshold), the measurement
    /// itself is the evidence a finger is there — the absolute floor relaxes to
    /// 0.05 and the red-DOMINANCE ratios remain the gate against a non-finger
    /// scene. Near-darkness (R ≤ 0.05, no torch reflection) still releases, and a
    /// truly removed finger kills the periodicity → confidence decays → the normal
    /// 0.12 floor returns. Acquisition is never loosened. Pure → Linux-testable.
    nonisolated static func isFingerFrame(avgR: Float, avgG: Float, avgB: Float,
                                          wasDetected: Bool,
                                          pulseCorroborated: Bool = false) -> Bool {
        let saturated = Swift.min(avgR, avgG, avgB) > 0.92
        let redFloor: Float = wasDetected ? (pulseCorroborated ? 0.05 : 0.12) : 0.28
        return saturated || (avgR > redFloor && avgR > avgG * 1.2 && avgR > avgB * 1.3)
    }

    /// Minimum inter-beat distance (seconds) for peak detection — an ADAPTIVE refractory
    /// that rejects the DICROTIC NOTCH (the smaller secondary peak ~0.3–0.4× of a beat after
    /// systole). On contacts where the notch clears the amplitude threshold it DOUBLES the
    /// peak count: device log pk≈18–20 → bpm≈110 while the autocorrelation fundamental sat at
    /// ~55–65, and acf was too low (<0.3) for the acf-gated octave/autoTrust guards to fire —
    /// so the inflated count won. Spacing beats at ~0.5× the autocorrelation-estimated period
    /// keeps real beats (1.0× apart) while killing the notch (~0.4× in). Clamped 0.30–0.60 s
    /// (≤200…≥100 bpm reach); falls back to the fixed 0.30 s when no plausible period is
    /// available (autoBPM 0 on a zero-strength window → behaves exactly as before). The
    /// autocorrelation reports the FUNDAMENTAL (not the notch), so it's the right rate to set
    /// the refractory from even when its STRENGTH is low. Pure → Linux-testable.
    nonisolated static func refractorySeconds(autoBPM: Double) -> Double {
        guard autoBPM >= 40, autoBPM <= 180 else { return 0.3 }
        return min(0.6, max(0.3, 0.5 * 60.0 / autoBPM))
    }

    /// When discrete peak-counting fails (rounded/weak rPPG waveform → fewer than
    /// 3 clean peaks, the device-log "bpm=0 forever" case), recover the rate from
    /// the window's periodicity via autocorrelation. Gated on periodicity strength
    /// so it locks onto a real pulse, not noise.
    private func fallbackBPM(_ auto: (bpm: Double, strength: Double)?) {
        guard let r = auto, r.strength > 0.3 else { return }
        estimatedBPM = estimatedBPM == 0 ? r.bpm : estimatedBPM * 0.80 + r.bpm * 0.20
        let conf = max(0, min(1, (r.strength - 0.3) / 0.5))
        bpmConfidence = bpmConfidence * 0.82 + conf * 0.18
    }

    // MARK: - HRV Calculation

    /// Calculate RMSSD from successive RR interval differences
    private func calculateRMSSD() {
        guard rrIntervals.count >= 2 else { return }

        var sumSquaredDiffs: Double = 0
        var count = 0

        for i in 1..<rrIntervals.count {
            let diff = rrIntervals[i] - rrIntervals[i - 1]
            sumSquaredDiffs += diff * diff
            count += 1
        }

        guard count > 0 else { return }
        rmssd = sqrt(sumSquaredDiffs / Double(count))
    }

    // MARK: - Signal Quality

    private func updateSignalQuality() {
        // Quality based on: finger detected, confidence, signal amplitude
        var quality: Double = 0

        if isFingerDetected { quality += 0.3 }
        quality += bpmConfidence * 0.4

        // Signal-to-noise: check red channel variability
        if rawRedSignal.count >= 30 {
            let recent = Array(rawRedSignal.suffix(30))
            var mean: Float = 0
            vDSP_meanv(recent, 1, &mean, 30)
            var variance: Float = 0
            var temp = [Float](repeating: 0, count: 30)
            var negMean = -mean
            vDSP_vsadd(recent, 1, &negMean, &temp, 1, 30)
            vDSP_dotpr(temp, 1, temp, 1, &variance, 30)
            variance /= 30.0

            // Good PPG signal has a small but measurable pulsatile component. Judge
            // it RELATIVE to the DC level (coefficient of variation), not as an
            // absolute variance: at a bright finger (DC≈0.8) a healthy ~1% AC gives
            // variance ≈6e-5, which the old absolute `> 0.0001` gate wrongly rejected
            // — so quality capped at 0.31 and never reflected a real pulse (device
            // log). CV in ~0.1%…10% of DC is the plausible fingertip-PPG band.
            let meanD = Double(mean)
            if meanD > 0.01 {
                let cv = Double(sqrt(max(0, variance))) / meanD
                if cv > 0.001 && cv < 0.1 {
                    quality += 0.3
                }
            }
        }

        signalQuality = signalQuality * 0.9 + quality * 0.1
    }

    // MARK: - Cleanup

    func reset() {
        resetPulseState()
        brightness = 0.5
        redChannel = 0.5
        isPulseDetecting = false
        isFingerDetected = false
        fingerDetectionBuffer.removeAll()
        fingerTrueCount = 0
        dcEstimate = 0
    }
}
#endif
