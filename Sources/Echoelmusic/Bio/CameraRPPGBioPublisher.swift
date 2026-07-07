//
//  CameraRPPGBioPublisher.swift
//  Echoelmusic — Bio
//
//  Wires the dormant camera rPPG path into the live EngineBus: drives
//  CameraCapture → CameraAnalyzer (photoplethysmography) and publishes a
//  BioSampleFrame(source: .cameraPPG) at ~1 Hz when a confident pulse is
//  detected. Opt-in (started explicitly by the UI), never auto-run.
//
//  Concurrency:
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
    /// A CALM BPM for on-screen display (founder 2026-07-02: "ruhige Anzeige"). It updates
    /// only on a CONFIDENT reading and EMA-smooths, HOLDING the last good value through
    /// low-confidence patches — so the glanceable number stops bouncing (e.g. 55↔98 during
    /// a marginal grip). The measurement (`detectedBPM`) and the bus-published HR stay
    /// honest and untouched; this is display-only.
    public private(set) var displayBPM: Double = 0
    /// Only readings at/above this confidence move `displayBPM` (higher than `lockThreshold`
    /// so the noisy 0.35–0.55 band holds instead of wandering).
    static let displayThreshold = 0.6
    /// Max change of the shown pulse per ~100 ms tick — a physiological slew cap so the
    /// displayed BPM can never jump. 1.0 bpm/tick ≈ 10 bpm/s: calm enough that a resting
    /// readout doesn't visibly twitch, still fast enough to track a genuine rise/fall within
    /// a couple seconds. (Was 2.0 — founder: "bpm springt"; the readout was still too lively.)
    static let maxDisplayStep = 1.0
    /// Live bandpass-filtered pulse waveform (~[-1,1]) for the "Stimmungsbild".
    public private(set) var waveform: [Float] = []
    /// Lock threshold — also the bus-publish gate.
    static let lockThreshold = 0.35

    /// Minimum AUTOCORRELATION strength ("acf") a reading must carry before it may move the
    /// shown pulse OR latch the tempo. Confidence alone can be inflated by the peak-counter
    /// SELF-AGREEING on a noisy, poorly-placed finger (device log 2026-07-04: R saturated
    /// 0.7–0.8, acf 0.14, conf 0.90 → "settled" at a WRONG 79 bpm while the true resting pulse
    /// was ~54, visible later in the SAME session at acf 0.78). Requiring real periodicity
    /// means a bad reading now HOLDS ("acquiring") instead of showing/seeding a fantasy number
    /// — the pulse must EARN trust. On this device real locks always carry strong acf
    /// (0.57–0.84); junk maxes ~0.29, so 0.4 separates them cleanly. (Camera is the approximate
    /// fallback — a chest strap gives clean beat-to-beat directly and is the preferred source.)
    static let trustAutoFloor = 0.4

    /// A reading may move the display / latch the tempo only when it is BOTH confident AND
    /// corroborated by real periodicity (autocorrelation). Pure → unit-testable.
    static func pulseTrustworthy(confidence: Double, autoStrength: Double) -> Bool {
        confidence >= displayThreshold && autoStrength >= trustAutoFloor
    }
    /// True once a confident pulse is locked.
    public var isLocked: Bool { detectedBPM > 0 && confidence >= Self.lockThreshold }

    /// True once the pulse is confident AND FLAT — display-grade confidence with the calm
    /// displayBPM moving ≤ ~3 bpm over ~3 s. This is the gate for LATCHING the take tempo:
    /// confidence alone fires on the falling tail of the warm-up curve (device log: locked 87
    /// while the pulse was still descending 125→…→69 — "in dem Moment wo bpm locked springt
    /// die bpm nach oben"). Settled = the descent has actually finished.
    public private(set) var isSettled = false
    /// Reference value + start time of the current flat window (tracked in the 10 Hz tick).
    private var settleRef: Double = -1
    private var settleSince: CFAbsoluteTime = 0
    /// Flat-window parameters: ≤3 bpm drift sustained for ≥3 s.
    private static let settleTolerance = 3.0
    private static let settleSeconds = 3.0

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
    /// Monotonic token identifying the CURRENT start() call. Bumped by every start() and
    /// by stop(); a start() that resumes from its `await` only proceeds if it is still the
    /// latest generation — so a Start→Stop or Start→Stop→Start interleave during the camera
    /// config window can't resurrect a stopped camera or orphan a second publish loop.
    @ObservationIgnored private var startGeneration = 0

    // Exposure-lock state machine (10 Hz). Lock against the FINGER-covered scene,
    // not the dim finger-less one; re-settle if a lock saturates.
    @ObservationIgnored private var exposureLocked = false
    @ObservationIgnored private var fingerStableTicks = 0
    @ObservationIgnored private var saturatedTicks = 0
    @ObservationIgnored private var fingerLostTicks = 0
    /// Ticks the finger has been CONTINUOUSLY present (regardless of brightness) —
    /// drives the strict→permissive lock-ceiling decay (prefer a dark lock).
    @ObservationIgnored private var fingerPresentTicks = 0
    /// Accumulated full-window weak-periodicity ticks while locked (bright-lock
    /// recovery) and the bounded number of weak re-locks used this placement.
    @ObservationIgnored private var weakAcfTicks = 0
    @ObservationIgnored private var weakRelocksUsed = 0
    /// Counts publish-loop ticks with ZERO drained RGB samples. When the RGB pipe
    /// stalls (analyzer frozen while the capture watchdog stays happy — device log
    /// 2026-07-02), this crosses the threshold and forces a full camera recovery.
    @ObservationIgnored private var stallTicks = 0
    /// Consecutive publisher-forced recoveries WITHOUT any frames returning in between.
    /// Capped so a camera that starts but never yields a usable sample can't be
    /// reconfigured forever (each reconfigure delays frames further — thermal/battery
    /// churn, permanently "acquiring"). Refilled only after SUSTAINED flow (see
    /// healthyTicks) — the brief trickle right after a recovery (exposure re-lock
    /// frames) must NOT reset it, or a recurring stall thrashes at "1/3" forever and
    /// never escalates (device log 1783177538: six recoveries all logged as 1/3,
    /// 45 s of dead pulse).
    @ObservationIgnored private var forcedRecoveries = 0
    /// Consecutive publish ticks WITH samples — the "flow is really healthy again"
    /// counter that refills the recovery budget after ~3 s of sustained samples.
    @ObservationIgnored private var healthyTicks = 0
    /// One-shot final escalation: when in-place recoveries are exhausted, do a FULL
    /// cold stop→start of the capture once (the founder's manual Stop→Start healed
    /// exactly the stall the in-place recovery could not — same log).
    @ObservationIgnored private var didColdRestart = false
    private static let maxForcedRecoveries = 3
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

    // PREFER A DARK LOCK (device log 1783401421 vs 1783370283): a lock at
    // bright=0.19 produced acf 0.8+ and a settled pulse; a lock at bright=0.34
    // (well under the permissive 0.6 cap) froze a too-bright exposure — the
    // window filled but acf never rose above ~0.4, the pulse NEVER settled, and
    // the tempo never body-seeded for the whole take. So the first seconds hold
    // a STRICT ceiling while the AGC pulls the torch-lit scene down; only after
    // that do we fall back to the permissive cap (a late soft lock still beats
    // no lock on unusual skin/devices).
    nonisolated static let strictLockBrightness: Float = 0.28
    nonisolated static let strictLockWindowTicks = 60   // ~6 s at the 10 Hz poll

    /// The brightness ceiling a lock must satisfy, given how long the finger has
    /// been continuously present. Pure → unit-tested.
    nonisolated static func lockBrightnessCeiling(fingerPresentTicks: Int) -> Float {
        fingerPresentTicks < strictLockWindowTicks ? strictLockBrightness : maxLockBrightness
    }

    // BRIGHT-LOCK RECOVERY: a lock that is bright-but-not-washed-out (0.34 << the
    // 0.72 washout line) shows a FULL analysis window with ~zero periodicity —
    // the saturation path never fires, so without this the take sits unsettled
    // forever. Sustained weak acf while unsettled → hand exposure back to auto so
    // the strict dark gate can re-lock. Bounded per placement (never thrashes).
    nonisolated static let weakRelockAcfFloor: Float = 0.2
    nonisolated static let weakRelockAcfStrong: Float = 0.4
    nonisolated static let weakRelockAfterTicks = 120   // ~12 s of accumulated weakness
    nonisolated static let maxWeakRelocks = 2

    /// One 10 Hz step of the weak-periodicity counter. Not diagnostic until the
    /// window is FULL; a settled pulse is never disturbed; intermittent "acf=0"
    /// no-estimate markers accumulate, genuinely strong acf pays the counter
    /// back down twice as fast. Pure → unit-tested.
    nonisolated static func weakTicksStep(current: Int, windowFull: Bool,
                                          acf: Float, settled: Bool) -> Int {
        guard windowFull, !settled else { return 0 }
        if acf < weakRelockAcfFloor { return current + 1 }
        if acf >= weakRelockAcfStrong { return max(0, current - 2) }
        return current
    }

    /// Whether a locked-but-weak exposure should be handed back to auto. Pure.
    nonisolated static func weakLockNeedsResettle(weakTicks: Int, relocksUsed: Int) -> Bool {
        weakTicks >= weakRelockAfterTicks && relocksUsed < maxWeakRelocks
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
        // Claim the running state + a fresh generation token SYNCHRONOUSLY, before the
        // first `await` below. Camera permission + session config is a suspension window of
        // seconds on first run; without this a Start→Stop (or Start→Stop→Start) during that
        // window would let this task resume past the await and re-arm torch/analyzer/
        // publishTask AFTER stop() — resurrecting a stopped camera (stuck torch, bio still
        // publishing) or orphaning a second 10 Hz loop. The generation check after the await
        // makes only the LATEST start() the authoritative owner.
        startGeneration += 1
        let gen = startGeneration
        isRunning = true
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
            // Only undo state if WE are still the latest start (a newer start/stop that
            // superseded us during the await owns the state now — don't clobber it).
            if gen == startGeneration {
                isRunning = false
                capture.onFrame = nil
                capture.onSessionReset = nil
            }
            return
        }

        // A stop() or a newer start() ran DURING the await above. stop() and every start()
        // bump `startGeneration`, so if ours is stale we are no longer the owner: the latest
        // start() (or stop's teardown) is authoritative — return without touching the shared
        // camera/torch/publishTask. This closes both "stop undone" and the orphan-loop leak.
        guard gen == startGeneration else { return }

        // Finger-on-lens PPG needs the back-camera torch to illuminate the
        // fingertip — without it there is no red-channel pulse signal. Driven on
        // the session's own running device for reliability.
        capture.setTorch(true)
        analyzer.startPulseDetection()
        stallTicks = 0
        forcedRecoveries = 0
        healthyTicks = 0
        didColdRestart = false
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
                let drained = self.sampleQueue.drain()
                for s in drained {
                    self.analyzer.processExtractedRGB(avgR: s.r, avgG: s.g, avgB: s.b, timestamp: s.t)
                }
                // Sample-pipe stall guard (device log 2026-07-02: analyzer output frozen
                // byte-identical for ~13 s — no NEW RGB reached it — while the capture-layer
                // watchdog saw frames and stayed happy). If NO samples arrive for ~6 s while
                // we're running, the RGB path (not just the raw session) has stalled: force a
                // full camera recovery. Cooldown lives in CameraCapture.recoverFromStall().
                if drained.isEmpty {
                    self.healthyTicks = 0
                    self.stallTicks += 1
                    if self.stallTicks >= 60 {          // ~6 s at 10 Hz
                        self.stallTicks = 0
                        if self.forcedRecoveries < Self.maxForcedRecoveries {
                            self.forcedRecoveries += 1
                            EchoelCrashLog.breadcrumb("rPPG: no new frames ~6 s — forcing camera recovery (\(self.forcedRecoveries)/\(Self.maxForcedRecoveries))")
                            self.capture.recoverFromStall()
                        } else if !self.didColdRestart {
                            // FINAL ESCALATION (once): in-place reconfigures didn't bring the
                            // sample pipe back, but a full cold stop→start does — the founder's
                            // manual Stop→Start healed exactly this stall (log 1783177700:
                            // immediately healthy after 45 s of thrash). Rebuild the whole
                            // session from scratch: inputs, outputs, torch, exposure.
                            self.didColdRestart = true
                            EchoelCrashLog.breadcrumb("rPPG: recoveries exhausted — cold camera restart")
                            self.capture.stop()
                            try? await Task.sleep(for: .milliseconds(800))
                            guard self.isRunning, !Task.isCancelled else { break }
                            try? await self.capture.start()
                            self.capture.setTorch(true)
                            self.handleCameraSessionReset()   // drop stale exposure lock → re-lock on finger
                        } else {
                            // Cold restart also failed: stop reconfiguring (it only delays
                            // frames further). The capture-layer watchdog + observers keep
                            // running; the honest UI state stays "acquiring", never a fake number.
                            EchoelCrashLog.breadcrumb("rPPG: still no frames after cold restart — leaving it to the watchdog")
                        }
                    }
                } else {
                    self.stallTicks = 0
                    self.healthyTicks += 1
                    // Refill the recovery budget only after ~3 s of SUSTAINED flow — not on
                    // the first post-recovery trickle (that reset was the "stuck at 1/3" bug).
                    if self.healthyTicks >= 30 {
                        self.forcedRecoveries = 0
                        self.didColdRestart = false
                    }
                }
                // Live status + waveform every tick so positioning is immediate.
                self.fingerDetected = self.analyzer.isFingerDetected
                self.signalQuality = min(max(self.analyzer.signalQuality, 0), 1)
                self.confidence = min(max(self.analyzer.bpmConfidence, 0), 1)
                self.detectedBPM = self.analyzer.estimatedBPM
                // Autocorrelation strength of the latest window — the corroboration signal that
                // separates a real pulse (strong periodicity) from a peak-counter self-agreeing
                // on a noisy finger. Gate both the display and the settle on it (see trustAutoFloor).
                let autoStrength = self.analyzer.lastAutoStrength
                // Calm display value: advance only on a TRUSTWORTHY reading (confident AND
                // corroborated by real periodicity), else hold — so a poorly-placed finger
                // shows "acquiring" instead of a fantasy number.
                if self.detectedBPM > 0 && Self.pulseTrustworthy(confidence: self.confidence, autoStrength: autoStrength) {
                    var bpm = self.detectedBPM
                    // OCTAVE-FOLD toward the established rate: rPPG often reports 2× (or ½) the
                    // true pulse (founder: "springt ständig auf 196 bpm"). Once a stable value
                    // exists, fold a doubled/halved estimate back so the SHOWN number doesn't
                    // yank between 98 and 196 — physiological continuity, display-only.
                    if self.displayBPM > 0 {
                        if bpm > self.displayBPM * 1.6 { bpm /= 2 }
                        else if bpm < self.displayBPM * 0.6 { bpm *= 2 }
                    }
                    if self.displayBPM == 0 {
                        self.displayBPM = bpm                       // first confident reading: adopt as-is
                    } else {
                        // EMA micro-smoothing, THEN a physiological SLEW cap so the shown pulse
                        // can never JUMP unrealistically (founder: "gemessener Puls … ohne
                        // unrealistische Sprünge"). A real heart rate changes a few bpm/s at most;
                        // anything faster is an rPPG glitch. ≤maxDisplayStep per ~100 ms tick glides
                        // through genuine changes and rejects teleports — a 70→133 octave/glitch
                        // eases over ~seconds instead of snapping.
                        let smoothed = self.displayBPM * 0.6 + bpm * 0.4
                        let step = Swift.max(-Self.maxDisplayStep,
                                             Swift.min(Self.maxDisplayStep, smoothed - self.displayBPM))
                        self.displayBPM += step
                    }
                }
                // SETTLED tracking: the tempo-latch gate. Confident + the calm displayBPM flat
                // (≤settleTolerance) for settleSeconds → the warm-up descent is over. Any move
                // beyond tolerance or a confidence drop restarts the window (and un-settles).
                let nowT = CFAbsoluteTimeGetCurrent()
                if self.displayBPM > 0 && Self.pulseTrustworthy(confidence: self.confidence, autoStrength: autoStrength) {
                    if self.settleRef < 0 || abs(self.displayBPM - self.settleRef) > Self.settleTolerance {
                        self.settleRef = self.displayBPM
                        self.settleSince = nowT
                        self.isSettled = false
                    } else if nowT - self.settleSince >= Self.settleSeconds {
                        self.isSettled = true
                    }
                } else {
                    self.settleRef = -1
                    self.isSettled = false
                }
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
            // The ceiling is STRICT for the first ~6 s of finger presence (prefer the
            // dark, high-AC lock the good sessions live in), then falls back to the
            // permissive cap so unusual skin/devices still lock eventually.
            fingerPresentTicks = fingerDetected ? (fingerPresentTicks + 1) : 0
            let ceiling = Self.lockBrightnessCeiling(fingerPresentTicks: fingerPresentTicks)
            fingerStableTicks = (Self.canLockNow(fingerDetected: fingerDetected, brightness: bright)
                                 && bright < ceiling)
                ? (fingerStableTicks + 1) : 0
            if fingerStableTicks >= Self.lockAfterTicks {
                capture.lockExposure()
                capture.setTorch(true)              // exposure reconfig can drop torch
                exposureLocked = true
                saturatedTicks = 0
                fingerLostTicks = 0
                weakAcfTicks = 0
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

        // BRIGHT-LOCK RECOVERY (device log 1783401421: locked at bright=0.34 —
        // legal under the old 0.6 cap, far from the 0.72 washout line — and the
        // full window then read acf ≈ 0–0.4 for the entire take; the pulse never
        // settled, so the tempo never body-seeded). Sustained ~zero periodicity
        // on a FULL window while unsettled → hand exposure back to auto so the
        // strict dark gate above re-locks properly. Bounded per placement.
        weakAcfTicks = Self.weakTicksStep(current: weakAcfTicks,
                                          windowFull: analyzer.lastWindowSize >= 140,
                                          acf: Float(analyzer.lastAutoStrength),
                                          settled: isSettled)
        if Self.weakLockNeedsResettle(weakTicks: weakAcfTicks, relocksUsed: weakRelocksUsed) {
            weakRelocksUsed += 1
            capture.unlockExposure()
            exposureLocked = false
            fingerStableTicks = 0
            fingerPresentTicks = 0   // restart the strict dark window — the point of the re-lock
            saturatedTicks = 0
            weakAcfTicks = 0
            EchoelCrashLog.breadcrumb(String(format:
                "rPPG: re-settling exposure — weak periodicity on a bright lock (bright=%.2f acf=%.2f, relock %d/%d)",
                bright, Float(analyzer.lastAutoStrength), weakRelocksUsed, Self.maxWeakRelocks))
            return
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
            fingerPresentTicks = 0
            weakAcfTicks = 0
            weakRelocksUsed = 0   // a NEW placement earns a fresh re-lock budget
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
        fingerPresentTicks = 0
        weakAcfTicks = 0
        weakRelocksUsed = 0   // fresh capture session = fresh re-lock budget
        stallTicks = 0
        // Do NOT reset forcedRecoveries here: every forced recovery fires this very
        // callback ~20 ms later, so zeroing the budget here made each recovery erase
        // its own count — "(1/3)" forever, cold restart unreachable (device log
        // 1783201461: four recoveries all logged 1/3 while the analyzer stayed
        // frozen). The budget refills ONLY on ~3 s of sustained frame flow
        // (healthyTicks in the publish loop) or a full stop().
        EchoelCrashLog.breadcrumb("rPPG: camera session recovered after stall — re-locking exposure")
    }

    public func stop() {
        // Bump the generation so any start() still suspended in its camera-config `await`
        // bails on resume instead of resurrecting the camera we're tearing down here.
        startGeneration += 1
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
        displayBPM = 0
        isSettled = false          // next take must re-prove a flat pulse before tempo latches
        settleRef = -1
        waveform = []
        exposureLocked = false
        fingerStableTicks = 0
        saturatedTicks = 0
        fingerLostTicks = 0
        stallTicks = 0
        forcedRecoveries = 0
    }

}
#endif
