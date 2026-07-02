//
//  CameraRPPGBioPublisher.swift
//  Echoelmusic — Bio
//
//  Wires the dormant camera rPPG path into the live EngineBus: drives
//  CameraCapture → CameraAnalyzer (photoplethysmography) and publishes a
//  BioSampleFrame(source: .cameraPPG) at ~1 Hz when a confident pulse is
//  detected. Opt-in (started explicitly by the UI), never auto-run.
//
//  Concurrency (mirrors the proven BioSourceManager pattern):
//  CameraCapture delivers CVPixelBuffers on its capture queue; we average the
//  center region to 3 Sendable Floats THERE, then hop to the main actor to feed
//  the @MainActor CameraAnalyzer (CVPixelBuffer is non-Sendable, so it never
//  crosses actors). EngineBus.publish(bio:) is nonisolated, so the 1 Hz loop can
//  publish directly.
//
//  RUNTIME NOTE: actual pulse detection needs a real device (camera + a finger
//  or face, ideally the torch). Compile-verified here; behaviour device-checked.
//

#if canImport(AVFoundation) && canImport(Observation)
import Foundation
import AVFoundation
import Observation

/// Lock-protected hand-off for pre-extracted RGB samples from the camera capture
/// queue to the @MainActor analyzer. The OLD path hopped to the main actor with a
/// `Task { @MainActor }` PER FRAME (~30/s at native capture rate, before the
/// analyzer's internal frame-skip). That flood of main-actor task submissions
/// starved the UI executor while biofeedback ran — the dropdown `.menu` Picker
/// stopped responding ("Sobald Biofeedback läuft kann ich nicht mehr auswählen").
/// Now the capture queue just appends samples here (one lock, no actor hop) and the
/// existing 10 Hz publish loop drains them on the main actor — zero per-frame tasks.
private final class RGBSampleQueue: @unchecked Sendable {
    struct Sample { let r: Float; let g: Float; let b: Float; let t: TimeInterval }
    private let lock = NSLock()
    private var samples: [Sample] = []
    /// Cap so a stalled drain can't grow this without bound (~3 s at 30 fps).
    private static let maxBuffered = 90

    func push(r: Float, g: Float, b: Float, t: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        if samples.count >= Self.maxBuffered { samples.removeFirst(samples.count - Self.maxBuffered + 1) }
        samples.append(Sample(r: r, g: g, b: b, t: t))
    }

    /// Atomically take and clear everything queued so far (FIFO order preserved).
    func drain() -> [Sample] {
        lock.lock()
        defer { lock.unlock() }
        guard !samples.isEmpty else { return [] }
        let out = samples
        samples.removeAll(keepingCapacity: true)
        return out
    }

    func clear() {
        lock.lock()
        samples.removeAll(keepingCapacity: true)
        lock.unlock()
    }
}

@MainActor
@Observable
public final class CameraRPPGBioPublisher {

    public private(set) var isRunning = false

    // Live status for the UI so the user can position correctly (rPPG is
    // position-sensitive). Updated ~3×/s while running.
    public private(set) var fingerDetected = false
    public private(set) var signalQuality: Double = 0   // 0...1
    public private(set) var confidence: Double = 0      // 0...1 — pulse-lock progress
    public private(set) var detectedBPM: Double = 0
    /// Live bandpass-filtered pulse waveform (~[-1,1]) for the "Stimmungsbild".
    public private(set) var waveform: [Float] = []
    /// Lock threshold — also the bus-publish gate.
    static let lockThreshold = 0.35
    /// True once a confident pulse is locked.
    public var isLocked: Bool { detectedBPM > 0 && confidence >= Self.lockThreshold }

    /// Live, specific placement guidance — turns the internal amplitude/exposure
    /// diagnostics into user coaching so the lens reaches a lockable signal, instead
    /// of a flat "Acquiring…". Pure derived state, read on the main actor by the UI.
    public var coachingHint: String {
        if isLocked { return "Locked" }
        if !fingerDetected { return "Cover the rear camera + flash" }
        // Finger is on the lit lens but no lock yet — say WHY, from the live signal.
        if analyzer.brightness > 0.85 || analyzer.redChannel > 0.92 { return "Press a little lighter" }
        // Large swings = the finger moving / changing pressure, not a pulse (the analyzer
        // rejects these windows, so it can't lock). Tell the user the real blocker so a
        // motion-heavy contact gets actionable guidance instead of an endless "finding…".
        if CameraAnalyzer.isMotionAmplitude(analyzer.lastFilteredAmplitude) { return "Hold still — keep your finger steady" }
        if analyzer.lastFilteredAmplitude < 0.0008 { return "Press gently and hold still" }
        return "Hold still — finding your pulse…"
    }

    @ObservationIgnored private let capture = CameraCapture()
    @ObservationIgnored private let analyzer = CameraAnalyzer()
    @ObservationIgnored private weak var bus: EngineBus?
    @ObservationIgnored private var publishTask: Task<Void, Never>?
    /// Capture-queue → main-actor sample hand-off (no per-frame Task hop). See
    /// RGBSampleQueue: this is the fix for the menu freeze during biofeedback.
    @ObservationIgnored private let sampleQueue = RGBSampleQueue()

    // Exposure-lock state machine (10 Hz). Lock against the FINGER-covered scene,
    // not the dim finger-less one; re-settle if a lock saturates.
    @ObservationIgnored private var exposureLocked = false
    @ObservationIgnored private var fingerStableTicks = 0
    @ObservationIgnored private var saturatedTicks = 0
    @ObservationIgnored private var fingerLostTicks = 0
    private static let lockAfterTicks = 12      // ~1.2 s of stable finger before lock
    private static let resettleAfterTicks = 20  // ~2 s of saturation → re-settle
    private static let relockOnLossTicks = 30   // ~3 s without finger → allow re-lock
    // Only lock exposure when the finger scene is dark enough for PPG. A bright
    // finger scene means torch light is flooding the lens; locking there captured a
    // washed frame that never produced a pulse (device log 2026-07-02: locked at
    // bright=0.62, bpm=0 the whole session). Healthy PPG brightness is ~0.1–0.4.
    // `nonisolated` so the `nonisolated static func canLockNow` (and its tests) can
    // read it — the class is @MainActor, which would otherwise isolate this constant
    // and break the nonisolated reference (CLAUDE.md: @MainActor prop from nonisolated).
    nonisolated private static let maxLockBrightness: Float = 0.6

    // MARK: - Pure lock predicates (extracted so the state machine is unit-tested)

    /// A tick may count toward an exposure lock only when the finger is present AND
    /// the scene is dark enough for PPG — never lock a bright/flooded frame.
    nonisolated static func canLockNow(fingerDetected: Bool, brightness: Float) -> Bool {
        fingerDetected && brightness < maxLockBrightness
    }

    /// A locked scene is washed out (AC pulse swamped) once it drifts too bright or
    /// the red channel clips — trigger a re-settle so it recovers instead of sitting dead.
    nonisolated static func isWashedOut(brightness: Float, red: Float) -> Bool {
        brightness > 0.72 || red > 0.92
    }

    public init() {}

    /// Start the camera, drive the analyzer from captured frames, and publish
    /// confident pulse estimates to the bus. No-op if already running.
    public func start(publishing bus: EngineBus) async {
        guard !isRunning else { return }
        self.bus = bus

        let sampleQueue = self.sampleQueue
        capture.onFrame = { pixelBuffer in
            // Average the center region on the capture queue → 3 Sendable Floats.
            CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            let regionX = width / 4, regionY = height / 4
            let regionW = width / 2, regionH = height / 2
            var totalR: Float = 0, totalG: Float = 0, totalB: Float = 0, count: Float = 0
            for y in stride(from: regionY, to: regionY + regionH, by: 8) {
                let rowPtr = base.advanced(by: y * bytesPerRow)
                for x in stride(from: regionX, to: regionX + regionW, by: 8) {
                    let pixel = rowPtr.advanced(by: x * 4)
                    totalB += Float(pixel.load(fromByteOffset: 0, as: UInt8.self))
                    totalG += Float(pixel.load(fromByteOffset: 1, as: UInt8.self))
                    totalR += Float(pixel.load(fromByteOffset: 2, as: UInt8.self))
                    count += 1
                }
            }
            guard count > 0 else { return }
            let avgR = totalR / count / 255.0
            let avgG = totalG / count / 255.0
            let avgB = totalB / count / 255.0
            // No per-frame actor hop — just enqueue. The 10 Hz publish loop drains
            // and feeds the analyzer on the main actor (timestamp preserves the rate
            // calc). This is what keeps the UI / dropdown menus responsive while bio runs.
            sampleQueue.push(r: avgR, g: avgG, b: avgB, t: ProcessInfo.processInfo.systemUptime)
        }

        // If the camera self-recovers from a silent stall (watchdog restart or full
        // reconfigure), the device exposure is fresh (back to auto). Drop our lock so
        // the loop re-locks against the finger instead of trusting a stale lock; the
        // torch is re-armed by CameraCapture itself. Fires on a background queue → hop.
        capture.onSessionReset = { [weak self] in
            Task { @MainActor [weak self] in self?.handleCameraSessionReset() }
        }

        do {
            try await capture.start()
        } catch {
            log.log(.warning, category: .biofeedback, "Camera rPPG failed to start: \(error.localizedDescription)")
            capture.onFrame = nil
            return
        }

        // Finger-on-lens PPG needs the back-camera torch to illuminate the
        // fingertip — without it there is no red-channel pulse signal. Driven on
        // the session's own running device for reliability.
        capture.setTorch(true)
        analyzer.startPulseDetection()
        isRunning = true
        EchoelCrashLog.breadcrumb("rPPG: started, torch requested")

        // Exposure is now locked from the publish loop ONLY once the finger is
        // stably covering the lit lens (see the loop below) — NOT on a blind timer.
        // Continuous auto-exposure stays on until then so the AGC adapts to the
        // bright finger-covered scene first; locking against the dim finger-less
        // scene was the device-log root cause of "bpm=0 forever" (R saturated 0.82).

        publishTask = Task { @MainActor [weak self] in
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))   // ~10 Hz: live feel
                guard let self, self.isRunning else { break }
                // Drain the frames the capture queue buffered since the last tick and
                // feed them to the analyzer IN ORDER, on the main actor, with their
                // capture timestamps (so the rate maths stays correct). Replaces the old
                // per-frame `Task { @MainActor }` flood that froze the menus while bio ran.
                for s in self.sampleQueue.drain() {
                    self.analyzer.processExtractedRGB(avgR: s.r, avgG: s.g, avgB: s.b, timestamp: s.t)
                }
                // Live status + waveform every tick so positioning is immediate.
                self.fingerDetected = self.analyzer.isFingerDetected
                self.signalQuality = min(max(self.analyzer.signalQuality, 0), 1)
                self.confidence = min(max(self.analyzer.bpmConfidence, 0), 1)
                self.detectedBPM = self.analyzer.estimatedBPM
                self.waveform = self.analyzer.recentWaveform

                // EXPOSURE: lock once the finger has covered the lens for ~1.2 s (so
                // the AGC settled on the bright fingertip), and RE-SETTLE if the lock
                // ever leaves the sensor saturated (DC swamps the pulsatile AC).
                self.manageExposure()
                // Publish a confident pulse to the bus at ~1 Hz (every 10th tick).
                tick += 1
                // Diagnostics into the breadcrumb stream (~every 2 s) so a device
                // log reveals WHY there is no signal: finger off → torch/position;
                // finger on but bpm 0 → exposure/signal; conf < 0.35 → still locking.
                if tick % 20 == 0 {
                    // R/bright disambiguate finger placement; amp/pk/acf disambiguate
                    // WHY a placed finger won't lock: amp≈0 → no pulsatile AC (press
                    // lighter / torch); pk<3 with acf high → rounded waveform (the
                    // autocorrelation seed now covers it); acf low → weak/aperiodic
                    // perfusion. This is the one line that pinpoints the failing stage.
                    // `auto` = the independent autocorrelation BPM. If bpm ≈ auto/2 with a
                    // decent acf, the peak-count rate is HALVED (octave error); if they
                    // agree, the rate is genuine. Diagnoses the halving without a reference.
                    EchoelCrashLog.breadcrumb(String(format:
                        "rPPG: finger=%@ R=%.2f bright=%.2f q=%.2f amp=%.4f pk=%d acf=%.2f auto=%.0f rate=%.1f win=%d bpm=%.0f conf=%.2f",
                        self.fingerDetected ? "yes" : "no",
                        self.analyzer.redChannel, self.analyzer.brightness, self.signalQuality,
                        self.analyzer.lastFilteredAmplitude, self.analyzer.lastPeakCount,
                        self.analyzer.lastAutoStrength, self.analyzer.lastAutoBPM,
                        self.analyzer.lastActualRate,
                        self.analyzer.lastWindowSize, self.detectedBPM, self.confidence))
                }
                guard tick % 10 == 0, let bus = self.bus else { continue }
                let bpm = self.analyzer.estimatedBPM
                guard bpm > 0, self.analyzer.bpmConfidence >= Self.lockThreshold else { continue }
                let rmssdMs = Float(self.analyzer.rmssd)
                let hrv = Float(min(max(self.analyzer.rmssd / 200.0, 0), 1))
                // analyzer.rrIntervals are already in milliseconds.
                let rrMs = self.analyzer.rrIntervals
                // Real frequency-domain coherence from the camera RR series — the
                // SAME metric as the BLE path (HRVCoherence), not the signal-quality
                // value this used to mislabel as "coherence". rPPG RR is lower-trust
                // than a chest strap (BioSource.providesTrustedHRV is false for
                // .cameraPPG), so consumers still gate on the source; the field is now
                // at least semantically correct. 0 until enough beats/power.
                let coherence = HRVCoherence.compute(rrMs: rrMs, blend: 1.0)

                // Respiration from the RR series via RSA (breathing modulates HR).
                // Replay the current RR window through a fresh estimator → the current
                // breath amplitude (drives the ball) + rate. Pure + cheap. Reported
                // only when the respiratory oscillation is clear (confidence gate), so
                // breathRate > 0 signals "measured breath available" to the UI.
                var resp = RespirationEstimator()
                var tAcc = 0.0
                for ms in rrMs where ms > 250 && ms < 2000 {
                    tAcc += ms / 1000.0
                    resp.ingest(heartRate: 60_000.0 / ms, at: tAcc)
                }
                let measuredBreath = resp.confidence >= 0.4
                bus.publish(bio: BioSampleFrame(
                    timestamp: CFAbsoluteTimeGetCurrent(),
                    heartRateBPM: Float(bpm),
                    hrvNormalized: hrv,
                    breathRate: measuredBreath ? Float(resp.ratePerMinute) : 0,
                    breathPhase: measuredBreath ? Float(resp.amplitude) : 0,
                    coherence: coherence.valid ? coherence.coherence : 0,
                    motionEnergy: 0,
                    source: .cameraPPG,
                    hrvRMSSDms: rmssdMs,
                    hrvSDNNms: Float(HRVMetrics.sdnn(rrMs: rrMs)),
                    hrvPNN50: Float(HRVMetrics.pnn50(rrMs: rrMs))
                ))
            }
        }
    }

    /// 10 Hz exposure state machine. Locks exposure only after the finger has
    /// stably covered the torch-lit lens (so the AGC has adapted to that bright
    /// scene), and re-settles if a lock leaves the sensor saturated — the fix for
    /// the device-log "R=0.82, bpm=0 forever" (exposure was frozen too early,
    /// against the dim finger-less scene, then saturated when the finger arrived).
    private func manageExposure() {
        let bright = self.analyzer.brightness
        let red = self.analyzer.redChannel
        // Washout detection (threshold 0.72, was 0.85): a locked scene that drifts to
        // bright 0.6–0.8 (finger lightening / re-grip) is already washed out — the AC
        // pulse is swamped — so recover instead of sitting dead (device log 2026-07-02:
        // stayed "locked" at bright 0.80 with bpm=0). Healthy PPG bright is ~0.1–0.4,
        // well under 0.72, so a good lock is never disturbed.
        let saturating = Self.isWashedOut(brightness: bright, red: red)

        if !exposureLocked {
            // Wait for a stable finger AND a dark-enough scene, THEN lock. The
            // brightness gate stops a lock from capturing a washed/flooded frame
            // (device log 2026-07-02: locked at bright=0.62 → no pulse all session).
            // If the finger is present but the scene is too bright, keep auto-exposure
            // running so the AGC pulls the exposure down before we freeze it.
            fingerStableTicks = Self.canLockNow(fingerDetected: fingerDetected, brightness: bright)
                ? (fingerStableTicks + 1) : 0
            if fingerStableTicks >= Self.lockAfterTicks {
                capture.lockExposure()
                capture.setTorch(true)              // exposure reconfig can drop torch
                exposureLocked = true
                saturatedTicks = 0
                fingerLostTicks = 0
                EchoelCrashLog.breadcrumb(String(format:
                    "rPPG: exposure locked on finger (bright=%.2f R=%.2f)", bright, red))
            }
            return
        }

        // Locked. If it saturates for a sustained spell, the AC pulse is swamped →
        // hand exposure back to auto so it re-settles, then the loop re-locks.
        if saturating {
            saturatedTicks += 1
            if saturatedTicks >= Self.resettleAfterTicks {
                capture.unlockExposure()
                exposureLocked = false
                fingerStableTicks = 0
                saturatedTicks = 0
                EchoelCrashLog.breadcrumb(String(format:
                    "rPPG: re-settling exposure — saturated (bright=%.2f R=%.2f)", bright, red))
            }
        } else {
            saturatedTicks = max(0, saturatedTicks - 1)
        }

        // Finger gone for a while → drop the lock so the next placement re-locks
        // against the new (possibly different) finger pressure/position.
        fingerLostTicks = fingerDetected ? 0 : (fingerLostTicks + 1)
        if fingerLostTicks >= Self.relockOnLossTicks {
            capture.unlockExposure()
            exposureLocked = false
            fingerStableTicks = 0
            saturatedTicks = 0
            fingerLostTicks = 0
        }
    }

    /// The camera restarted the session under us (stall recovery). The device is
    /// freshly configured with exposure back to auto, so reset our exposure state
    /// machine to re-lock cleanly. Also breadcrumbed so the recovery is visible in a
    /// device log (previously a stall just looked like frozen values).
    private func handleCameraSessionReset() {
        exposureLocked = false
        fingerStableTicks = 0
        saturatedTicks = 0
        fingerLostTicks = 0
        EchoelCrashLog.breadcrumb("rPPG: camera session recovered after stall — re-locking exposure")
    }

    public func stop() {
        publishTask?.cancel()
        publishTask = nil
        capture.onSessionReset = nil
        capture.setTorch(false)
        capture.unlockExposure()       // leave the device back in auto for next time
        capture.stop()
        capture.onFrame = nil
        sampleQueue.clear()            // drop any frames buffered but not yet drained
        analyzer.stopPulseDetection()
        isRunning = false
        fingerDetected = false
        signalQuality = 0
        confidence = 0
        detectedBPM = 0
        waveform = []
        exposureLocked = false
        fingerStableTicks = 0
        saturatedTicks = 0
        fingerLostTicks = 0
    }

}
#endif
