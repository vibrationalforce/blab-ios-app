#if canImport(AVFoundation)
import Foundation
import AVFoundation

/// Minimal AVCaptureSession for rPPG pulse detection.
/// Captures low-resolution video frames from the back camera.
/// Delivers pixel buffers via callback for CameraAnalyzer processing.
final class CameraCapture: NSObject, @unchecked Sendable {

    private let session = AVCaptureSession()
    private let captureQueue = DispatchQueue(label: "com.echoelmusic.camera.capture", qos: .userInitiated)
    private let sessionQueue = DispatchQueue(label: "com.echoelmusic.camera.session")

    /// Called for each captured frame (on captureQueue — NOT main thread)
    nonisolated(unsafe) var onFrame: ((CVPixelBuffer) -> Void)?

    // MARK: - Resilience (frame-stall watchdog + session-error recovery)
    /// Wall-clock of the last delivered frame. Written on captureQueue, read on the
    /// watchdog (sessionQueue); a CFAbsoluteTime is atomic-width so the small race is
    /// benign for a stall detector. Device logs showed the capture session silently
    /// stop delivering frames for ~68 s mid-session (thermal/resource contention with
    /// the audio+Metal pipeline) with no runtime-error — only a watchdog catches that.
    nonisolated(unsafe) private var lastFrameTime: CFAbsoluteTime = 0
    nonisolated(unsafe) private var lastRestartTime: CFAbsoluteTime = 0
    private var watchdog: DispatchSourceTimer?
    private var sessionObservers: [NSObjectProtocol] = []
    /// Consecutive stall-restart attempts (sessionQueue). Resets the instant frames
    /// flow again. Drives escalation: a cheap stop/start first, a FULL reconfigure if
    /// that didn't revive delivery (a deep stall — mediaServices reset / thermal —
    /// often survives a bare restart).
    private var stallRestarts = 0
    /// Last torch state the app asked for (sessionQueue-only). A session restart/
    /// reconfigure silently drops the torch, so recovery must re-arm it — without it
    /// rPPG has no signal and the "stall" looks unrecovered even after frames resume.
    private var torchDesired = false
    /// Called after the session is restarted/reconfigured by recovery, so the owner
    /// (rPPG publisher) can reset its exposure state machine and re-lock cleanly.
    nonisolated(unsafe) var onSessionReset: (() -> Void)?
    /// Whether the owner WANTS the session running (set by start, cleared by stop;
    /// sessionQueue-only). The watchdog needs this to revive a session that DIED —
    /// the old `guard session.isRunning` made it blind exactly when a failed cold
    /// start left the session down (device log 1783588109: 83 s with no reviver).
    private var shouldBeRunning = false
    /// Whether iOS has INTERRUPTED the session (thermal/system-pressure, another app
    /// grabbed the camera, backgrounded). Device log 1783603146: bright froze at 0.73
    /// and frames stopped (`in=0`) for ~2 min while every stall-restart AND cold
    /// restart failed — the classic signature of an interruption, during which
    /// startRunning() is a no-op until the OS ends it. The watchdog must NOT thrash
    /// restarts while interrupted (they can't work and the torch churn only adds heat);
    /// it waits for `AVCaptureSessionInterruptionEnded`. Set/cleared on sessionQueue.
    nonisolated(unsafe) private var interrupted = false

    /// Whether the session is running
    var isRunning: Bool { session.isRunning }

    // MARK: - Start

    func start() async throws {
        // 1. Request camera permission
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            guard granted else { throw CameraCaptureError.permissionDenied }
        } else if status == .denied || status == .restricted {
            throw CameraCaptureError.permissionDenied
        }

        // 2. Configure and start on background thread (required by Apple)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: CameraCaptureError.configurationFailed)
                    return
                }
                do {
                    try self.configureSession()
                    self.installSessionObservers()
                    self.session.startRunning()
                    self.shouldBeRunning = true
                    self.lastFrameTime = CFAbsoluteTimeGetCurrent()   // grace from start
                    self.startWatchdog()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        log.log(.info, category: .biofeedback, "CameraCapture started")
    }

    private func configureSession() throws {
        // CRITICAL: do NOT let the capture session touch the app's AVAudioSession.
        // It defaults to true, which reconfigures/deactivates the shared audio
        // session out from under the running AVAudioEngine → render-thread crash
        // the instant the camera starts (the classic "camera kills audio" device
        // crash). We capture video only, so it never needs to manage audio.
        session.automaticallyConfiguresApplicationAudioSession = false

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .low

        // Find back camera
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CameraCaptureError.noCamera
        }

        // Configure device: continuous auto-exposure initially, locked after stabilization
        try device.lockForConfiguration()
        if device.isExposureModeSupported(.continuousAutoExposure) {
            device.exposureMode = .continuousAutoExposure
        }
        // Lock the capture to 15 fps — the rate the rPPG analyzer is built around.
        // The pixel feed exists ONLY to read a fingertip pulse (0.7–4 Hz); the visual
        // is the Metal field and the recorder captures the rendered Metal, not this
        // camera. CameraAnalyzer processes every delivered frame and its nominal
        // sample rate IS 15 Hz (Nyquist 7.5 Hz ≫ the 4 Hz pulse band), so 30 fps
        // buys nothing for the measurement while running the sensor/ISP at ~2× the
        // power — the heat that trips the thermal stalls (device log 2026-06: camera
        // dead ~2 min under sustained load). Capping at 15 fps is the single biggest
        // "temperature friendly" lever here and also matches the analyzer's assumed
        // rate exactly (faster lock, no runtime bandpass re-tune on a clean device).
        // The exposure cap (≤ 1/30 s in lockExposure) is INDEPENDENT and preserved —
        // shutter stays fast for a crisp pulse; only the frame cadence drops.
        if let range = device.activeFormat.videoSupportedFrameRateRanges.first {
            let targetFPS = max(range.minFrameRate, min(15.0, range.maxFrameRate))
            let duration = CMTimeMake(value: 1, timescale: Int32(targetFPS))
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
        }
        device.unlockForConfiguration()

        // Input
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw CameraCaptureError.configurationFailed
        }
        session.addInput(input)

        // Output
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: captureQueue)

        guard session.canAddOutput(output) else {
            throw CameraCaptureError.configurationFailed
        }
        session.addOutput(output)
    }

    // MARK: - Torch (finger-PPG illumination)

    /// Drive the torch on the SESSION's own running device (reliable), not a
    /// separate `AVCaptureDevice.default(for:)` lookup that can race the session.
    /// Finger-on-lens PPG has no red-channel pulse without it.
    func setTorch(_ on: Bool) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.torchDesired = on          // remembered so recovery can re-arm it
            self.applyTorch()
        }
    }

    /// Apply `torchDesired` to the running device. MUST be called on sessionQueue
    /// (setTorch + recovery both do). Re-armed after every restart/reconfigure.
    private func applyTorch() {
        guard let device = (self.session.inputs.first as? AVCaptureDeviceInput)?.device,
              device.hasTorch else {
            log.log(.warning, category: .biofeedback, "Torch unavailable on capture device")
            return
        }
        do {
            try device.lockForConfiguration()
            if torchDesired {
                // Torch level 0.45 (was 0.6): device logs 2026-07-02 showed the finger washing
                // to R≈0.7–0.85 with a tiny pulsatile AC (amp≈0.01–0.05) — too much light
                // saturates the capillary DC and crushes the pulse. A lower level keeps more AC
                // contrast and headroom before washout. THERMALLY SCALED (see thermalTorchLevel):
                // the continuous LED is the biggest controllable heat source, and heat is the
                // root cause of the ~40–80 s mid-session camera stalls that no restart could
                // revive (device log 1783445611). Backing the torch off as the phone warms
                // relieves that — and less light KEEPS more pulsatile AC, so signal doesn't suffer.
                try device.setTorchModeOn(level: min(thermalTorchLevel(), AVCaptureDevice.maxAvailableTorchLevel))
            } else {
                device.torchMode = .off
            }
            device.unlockForConfiguration()
            log.log(.info, category: .biofeedback,
                    "Torch \(torchDesired ? "on" : "off"), active=\(device.isTorchActive)")
        } catch {
            log.log(.warning, category: .biofeedback, "Torch control failed: \(error.localizedDescription)")
        }
    }

    /// Torch level, scaled DOWN as the device heats. After a couple of minutes the LED +
    /// camera + audio + Metal pipeline pushes the phone into thermal throttling, and a
    /// throttled camera silently stops delivering frames — the ~40–80 s stalls in the device
    /// logs that survived every restart (the heat, not the session, was dead). Relieving the
    /// biggest controllable heat source when hot lets the camera keep/resume delivery. Less
    /// light also preserves pulsatile AC contrast (see applyTorch), so the pulse still reads.
    private func thermalTorchLevel() -> Float {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal, .fair: return 0.45     // normal — full working level
        case .serious:        return 0.28     // getting hot — back off to shed heat
        case .critical:       return 0.18     // very hot — minimum that still lights the finger
        @unknown default:     return 0.45
        }
    }

    // MARK: - Exposure Lock (call after ~2s for stable PPG baseline)

    /// Lock camera exposure to prevent auto-gain from corrupting PPG signal.
    /// IMPORTANT: only call this once the finger is actually covering the torch-lit
    /// lens — locking against a dim, finger-less scene freezes a high-gain exposure
    /// that then SATURATES (R≈0.82) when the bright fingertip arrives, swamping the
    /// tiny pulsatile AC so no pulse ever locks (device-log root cause, 2026-06-23).
    func lockExposure() {
        sessionQueue.async { [weak self] in
            guard let self,
                  let device = (self.session.inputs.first as? AVCaptureDeviceInput)?.device else { return }
            try? device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            // Prefer a CUSTOM exposure with a BOUNDED duration over plain `.locked`.
            // `.locked` freezes whatever auto-exposure last chose; in a dim fingertip
            // scene that is a LONG integration time. Even with the frame cadence pinned
            // to 15 fps (1/15 s = 66 ms period), an exposure longer than the frame
            // period would force the camera to skip frames and collapse the real rate
            // (device log 2026-06-30: rate fell 15→4.8→3.1), below which the pulse
            // bandpass can't resolve a heartbeat and reacquisition never re-locks.
            // Capping the exposure to ≤ 1/30 s (33 ms) sits well inside the 66 ms frame
            // period so the full 15 fps is delivered, and curbs the saturation that long
            // exposures caused. It is INDEPENDENT of the 15 fps cadence cap in configure().
            if device.isExposureModeSupported(.custom) {
                let fmt = device.activeFormat
                var dur = CMTimeMake(value: 1, timescale: 30)        // ≤ 1/30 s → fps ≥ 30
                if CMTimeCompare(dur, fmt.maxExposureDuration) > 0 { dur = fmt.maxExposureDuration }
                if CMTimeCompare(dur, fmt.minExposureDuration) < 0 { dur = fmt.minExposureDuration }
                // Keep the AGC's current ISO (clamped to the format range) so the
                // shorter exposure stays bright enough on the torch-lit finger.
                let iso = min(max(device.iso, fmt.minISO), fmt.maxISO)
                device.setExposureModeCustom(duration: dur, iso: iso, completionHandler: nil)
            } else if device.isExposureModeSupported(.locked) {
                device.exposureMode = .locked
            }
        }
    }

    /// Hand exposure back to continuous auto so it can re-settle to the current
    /// scene before a fresh `lockExposure()` — used to recover from a saturated
    /// lock (e.g. exposure was frozen before the finger arrived, or a re-grip).
    func unlockExposure() {
        sessionQueue.async { [weak self] in
            guard let self,
                  let device = (self.session.inputs.first as? AVCaptureDeviceInput)?.device,
                  device.isExposureModeSupported(.continuousAutoExposure) else { return }
            try? device.lockForConfiguration()
            device.exposureMode = .continuousAutoExposure
            device.unlockForConfiguration()
        }
    }

    // MARK: - Resilience

    /// Observe AVCaptureSession runtime errors + interruptions and recover. Extract
    /// only Sendable values inside each notification block, then hop to sessionQueue
    /// (Notification itself is non-Sendable, so it must not cross the boundary).
    private func installSessionObservers() {
        let nc = NotificationCenter.default
        let rt = nc.addObserver(forName: .AVCaptureSessionRuntimeError, object: session,
                                queue: nil) { [weak self] note in
            let code = (note.userInfo?[AVCaptureSessionErrorKey] as? AVError)?.code
            self?.sessionQueue.async { self?.recoverFromError(code) }
        }
        let intr = nc.addObserver(forName: .AVCaptureSessionWasInterrupted, object: session,
                                  queue: nil) { [weak self] note in
            let reason = (note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int) ?? -1
            // Breadcrumb (not just os_log) so the founder's diag log finally REVEALS why
            // the camera died — reason 4 = systemPressure (thermal), 2 = inUseByAnother,
            // 1/3 = backgrounded. This was invisible in every prior stall log.
            EchoelCrashLog.breadcrumb("rPPG: camera INTERRUPTED (reason \(reason)) — waiting for the OS, not thrashing restarts")
            self?.sessionQueue.async { self?.interrupted = true }
        }
        let ended = nc.addObserver(forName: .AVCaptureSessionInterruptionEnded, object: session,
                                   queue: nil) { [weak self] _ in
            self?.sessionQueue.async {
                guard let self else { return }
                self.interrupted = false
                EchoelCrashLog.breadcrumb("rPPG: camera interruption ended — resuming")
                if !self.session.isRunning { self.session.startRunning() }
                self.lastFrameTime = CFAbsoluteTimeGetCurrent()
                self.applyTorch()          // an interruption drops the torch
                self.onSessionReset?()     // owner re-locks exposure cleanly
                log.log(.info, category: .biofeedback, "Camera session resumed after interruption")
            }
        }
        // Thermal-state changes: re-apply the torch at the level for the NEW state, so the
        // LED backs off the instant the phone gets hot (breaking the heat→stall loop) and
        // restores full level once it cools. object is nil (ProcessInfo posts globally).
        let thermal = nc.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification,
                                     object: nil, queue: nil) { [weak self] _ in
            self?.sessionQueue.async {
                guard let self else { return }
                log.log(.info, category: .biofeedback,
                        "Thermal state → \(ProcessInfo.processInfo.thermalState.rawValue) — re-applying torch")
                self.applyTorch()
            }
        }
        sessionObservers = [rt, intr, ended, thermal]
    }

    /// On a runtime error (notably `.mediaServicesWereReset`, which invalidates the
    /// session) do a FULL reconfigure — a bare start can't recover a reset session,
    /// and the torch must be re-armed. Runs on sessionQueue (the observer hops there).
    private func recoverFromError(_ code: AVError.Code?) {
        // Share the watchdog's restart throttle: a hardware reset that keeps re-emitting
        // the error must not thrash reconfigures (each reconfigure can itself re-emit).
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastRestartTime > 6.0 else {
            log.log(.warning, category: .biofeedback, "Camera runtime error within cooldown — skipping reconfigure")
            return
        }
        log.log(.warning, category: .biofeedback, "Camera runtime error (\(code.map(String.init(describing:)) ?? "unknown")) — full reconfigure")
        restartSession(fullReconfigure: true)
    }

    /// Watchdog: if the session is running but no frame has arrived for >4 s, the
    /// capture pipeline has silently stalled (device logs: ~50–68 s freeze, no error).
    /// Recovery ESCALATES — a cheap stop/start first; a full reconfigure if frames
    /// still don't return (a deep stall survives a bare restart). Cooldown-guarded so
    /// it can never thrash, and `stallRestarts` resets the moment frames flow again.
    private func startWatchdog() {
        watchdog?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: sessionQueue)
        timer.schedule(deadline: .now() + 2, repeating: 2)
        timer.setEventHandler { [weak self] in
            guard let self, self.shouldBeRunning else { return }
            // While iOS holds the session interrupted (thermal/system-pressure, camera
            // in use by another app), restarts are futile no-ops and the torch churn
            // only adds heat — so WAIT for AVCaptureSessionInterruptionEnded instead of
            // thrashing (device log 1783603146: 4 cold restarts, 0 frames, ~2 min).
            guard !self.interrupted else { return }
            let now = CFAbsoluteTimeGetCurrent()
            if !self.session.isRunning {
                // The session DIED while it should be up (failed cold start, runtime
                // teardown). The old `guard session.isRunning` returned here — the
                // watchdog was blind exactly when it was the last line of defense
                // (device log 1783588109: rPPG blind ~83 s). Revive with a full
                // rebuild, cooldown-guarded like every other kick.
                guard now - self.lastRestartTime > 6.0 else { return }
                self.stallRestarts += 1
                log.log(.warning, category: .biofeedback,
                        "Camera session dead while active — watchdog reviving (attempt \(self.stallRestarts))")
                self.restartSession(fullReconfigure: true)
                return
            }
            if now - self.lastFrameTime <= 4.0 {          // frames flowing → healthy
                self.stallRestarts = 0
                return
            }
            guard now - self.lastRestartTime > 6.0 else { return }   // restart cooldown
            self.stallRestarts += 1
            // First kick is the cheap stop/start; if that didn't revive delivery,
            // escalate to a full teardown + reconfigure of inputs/outputs.
            let full = self.stallRestarts >= 2
            log.log(.warning, category: .biofeedback,
                    "Camera stalled \(String(format: "%.1f", now - self.lastFrameTime))s — "
                    + "restarting (attempt \(self.stallRestarts), full=\(full))")
            self.restartSession(fullReconfigure: full)
        }
        timer.resume()
        watchdog = timer
    }

    /// Restart the capture session after a stall. `fullReconfigure` tears down and
    /// rebuilds inputs/outputs (for a deep stall a bare stop/start can't clear). Always
    /// re-arms the torch (a restart drops it) and notifies the owner to re-lock exposure.
    /// MUST run on sessionQueue (the watchdog handler does).
    private func restartSession(fullReconfigure: Bool) {
        lastRestartTime = CFAbsoluteTimeGetCurrent()       // single shared restart throttle
        session.stopRunning()
        if fullReconfigure {
            session.beginConfiguration()
            for input in session.inputs { session.removeInput(input) }
            for output in session.outputs { session.removeOutput(output) }
            session.commitConfiguration()
            do {
                try configureSession()                    // re-adds I/O, resets exposure to auto
            } catch {
                log.log(.error, category: .biofeedback,
                        "Camera reconfigure failed: \(error.localizedDescription)")
            }
        }
        session.startRunning()
        lastFrameTime = CFAbsoluteTimeGetCurrent()         // grace after the kick
        applyTorch()                                       // restart silently drops the torch
        onSessionReset?()                                  // owner re-locks exposure cleanly
    }

    /// Publisher-driven recovery: the RGB SAMPLE PIPE stalled (the analyzer got no new
    /// frames for ~6 s) even though the capture-layer watchdog — which only checks that
    /// `captureOutput` is still firing — stayed happy (device log 2026-07-02: analyzer
    /// output byte-identical ~13 s while `rate` sat frozen). That gap is invisible to the
    /// frame-delivery watchdog, so the owner forces a recovery here. Full reconfigure (a
    /// deep stall survives a bare restart) on sessionQueue, sharing the 6 s restart
    /// throttle so it can't thrash against the watchdog.
    func recoverFromStall() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            // Same rule as the watchdog: an OS interruption can't be cleared by a
            // restart — wait for InterruptionEnded instead of forcing a futile rebuild.
            guard !self.interrupted else { return }
            let now = CFAbsoluteTimeGetCurrent()
            guard now - self.lastRestartTime > 6.0 else { return }   // shared restart cooldown
            log.log(.warning, category: .biofeedback,
                    "Camera RGB pipe stalled — publisher forced full recovery")
            self.restartSession(fullReconfigure: true)
        }
    }

    // MARK: - Stop

    func stop() {
        // All watchdog/observer state is mutated on sessionQueue (start + stop), so
        // tear it down there too — keeps access serialized, no data race.
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.shouldBeRunning = false
            self.watchdog?.cancel()
            self.watchdog = nil
            for o in self.sessionObservers { NotificationCenter.default.removeObserver(o) }
            self.sessionObservers = []
            self.session.stopRunning()
            for input in self.session.inputs { self.session.removeInput(input) }
            for output in self.session.outputs { self.session.removeOutput(output) }
        }
        log.log(.info, category: .biofeedback, "CameraCapture stopped")
    }
}

// MARK: - Frame Delivery

extension CameraCapture: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrameTime = CFAbsoluteTimeGetCurrent()   // watchdog heartbeat
        onFrame?(pixelBuffer)
    }
}

// MARK: - Errors

enum CameraCaptureError: Error, LocalizedError {
    case permissionDenied
    case noCamera
    case configurationFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Camera permission denied"
        case .noCamera: return "No camera available"
        case .configurationFailed: return "Camera configuration failed"
        }
    }
}
#endif
