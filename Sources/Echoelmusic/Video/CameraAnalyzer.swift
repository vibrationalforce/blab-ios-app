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

    /// Frame counter for debugging
    private var frameCount: Int = 0

    // MARK: - Filter Modulation Output

    /// Normalized modulation value (0–1) from camera analysis
    var filterModulation: Float = 0.5
    /// Modulation mode
    var modulationMode: ModulationMode = .brightness

    enum ModulationMode: String, CaseIterable {
        case brightness = "Brightness"
        case color = "Color"
        case motion = "Motion"
    }

    // MARK: - Internal State

    private var frameSkipCounter = 0
    /// Process every 2nd frame at 30fps = 15 Hz sample rate (Nyquist > 4 Hz max HR)
    private let analyzeEveryNthFrame = 2
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Effective sample rate after frame skipping
    private let effectiveSampleRate: Double = 15.0 // 30fps / 2

    // Raw signal buffer
    private var rawRedSignal: [Float] = []
    private var signalTimestamps: [TimeInterval] = []
    private let maxSignalLength = 512 // ~34 seconds at 15Hz

    // Bandpass filter state (2nd order Butterworth, 0.7–4 Hz)
    private var bpState = BandpassState()

    // Peak detection
    private var peakIndices: [Int] = []
    private var lastPeakTime: TimeInterval = 0

    // Finger detection
    private var fingerDetectionBuffer: [Bool] = []
    private let fingerDetectionWindow = 10 // frames

    // Motion detection
    private var previousBrightness: Float = 0.5

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

    // MARK: - Frame Analysis

    /// Call from CameraManager's onFrameCaptured callback
    func analyzeFrame(_ sampleBuffer: CMSampleBuffer) {
        frameSkipCounter += 1
        guard frameSkipCounter >= analyzeEveryNthFrame else { return }
        frameSkipCounter = 0

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        analyzePixelBuffer(pixelBuffer)
    }

    /// Analyze a CVPixelBuffer for pulse detection
    func analyzePixelBuffer(_ pixelBuffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)

        guard pixelFormat == kCVPixelFormatType_32BGRA else { return }

        // Sample center region (50% of frame for finger-on-lens)
        let regionX = width / 4
        let regionY = height / 4
        let regionW = width / 2
        let regionH = height / 2

        var totalR: Float = 0
        var totalG: Float = 0
        var totalB: Float = 0
        var sampleCount: Float = 0

        // Also track variance for finger detection
        var sumR2: Float = 0

        let step = 4
        for y in stride(from: regionY, to: regionY + regionH, by: step) {
            let rowStart = baseAddress.advanced(by: y * bytesPerRow)
            for x in stride(from: regionX, to: regionX + regionW, by: step) {
                let pixel = rowStart.advanced(by: x * 4)
                let b = Float(pixel.load(fromByteOffset: 0, as: UInt8.self)) / 255.0
                let g = Float(pixel.load(fromByteOffset: 1, as: UInt8.self)) / 255.0
                let r = Float(pixel.load(fromByteOffset: 2, as: UInt8.self)) / 255.0
                totalR += r
                totalG += g
                totalB += b
                sumR2 += r * r
                sampleCount += 1
            }
        }

        guard sampleCount > 0 else { return }

        let avgR = totalR / sampleCount
        let avgG = totalG / sampleCount
        let avgB = totalB / sampleCount
        let avgBrightness = (avgR + avgG + avgB) / 3.0

        // Red channel variance — low variance + high red = finger on lens
        let varianceR = (sumR2 / sampleCount) - (avgR * avgR)

        brightness = brightness * 0.7 + avgBrightness * 0.3
        redChannel = redChannel * 0.7 + avgR * 0.3
        previousBrightness = brightness

        // Update filter modulation
        switch modulationMode {
        case .brightness:
            filterModulation = brightness
        case .color:
            let maxChannel = max(avgR, avgG, avgB)
            let minChannel = min(avgR, avgG, avgB)
            filterModulation = maxChannel - minChannel
        case .motion:
            let delta = abs(avgBrightness - previousBrightness)
            filterModulation = min(delta * 10, 1.0)
        }

        // Finger detection: high red, low green/blue relative, low spatial variance
        let isFingerFrame = avgR > 0.5 && avgR > avgG * 1.3 && avgR > avgB * 1.5 && varianceR < 0.02

        fingerDetectionBuffer.append(isFingerFrame)
        if fingerDetectionBuffer.count > fingerDetectionWindow {
            fingerDetectionBuffer.removeFirst()
        }

        // Finger is "detected" when >70% of recent frames match
        let fingerFrames = fingerDetectionBuffer.filter { $0 }.count
        isFingerDetected = fingerFrames > (fingerDetectionWindow / 2)

        // Pulse detection
        if isPulseDetecting && isFingerDetected {
            processPulseSignal(avgR: avgR)
        } else if isPulseDetecting && !isFingerDetected {
            // Reset confidence when finger removed
            bpmConfidence = max(0, bpmConfidence - 0.02)
            signalQuality = max(0, signalQuality - 0.02)
        }
    }

    // MARK: - Pulse Detection (Bandpass + Peak)

    /// Process pre-extracted RGB values (called from MainActor via BioSourceManager)
    /// This avoids the @MainActor crash from accessing pixel buffers on background threads.
    func processExtractedRGB(avgR: Float, avgG: Float, avgB: Float) {
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

        // Finger detection: high red dominance when finger covers lens + torch on
        let isFingerFrame = avgR > 0.4 && avgR > avgG * 1.2 && avgR > avgB * 1.3

        fingerDetectionBuffer.append(isFingerFrame)
        if fingerDetectionBuffer.count > fingerDetectionWindow {
            fingerDetectionBuffer.removeFirst()
        }

        let fingerFrames = fingerDetectionBuffer.filter { $0 }.count
        isFingerDetected = fingerFrames > (fingerDetectionWindow / 2)

        // Pulse detection
        if isPulseDetecting && isFingerDetected {
            processPulseSignal(avgR: avgR)
        } else if isPulseDetecting && !isFingerDetected {
            bpmConfidence = max(0, bpmConfidence - 0.02)
            signalQuality = max(0, signalQuality - 0.02)
        }
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

    private func resetPulseState() {
        rawRedSignal.removeAll()
        signalTimestamps.removeAll()
        peakIndices.removeAll()
        rrIntervals.removeAll()
        bpState = BandpassState()
        estimatedBPM = 0
        bpmConfidence = 0
        signalQuality = 0
        rmssd = 0
    }

    private func processPulseSignal(avgR: Float) {
        let now = ProcessInfo.processInfo.systemUptime

        // Append raw red channel value
        rawRedSignal.append(avgR)
        signalTimestamps.append(now)

        if rawRedSignal.count > maxSignalLength {
            rawRedSignal.removeFirst()
            signalTimestamps.removeFirst()
            // Adjust peak indices
            peakIndices = peakIndices.compactMap { $0 > 0 ? $0 - 1 : nil }
        }

        // Apply bandpass filter to latest sample
        let filtered = applyBandpassFilter(avgR)

        // Need at least 3 seconds of data before peak detection
        guard rawRedSignal.count >= Int(effectiveSampleRate * 3) else { return }

        // Peak detection on filtered signal
        detectPeaks(latestFiltered: filtered, timestamp: now)

        // Calculate signal quality
        updateSignalQuality()
    }

    /// 2nd-order IIR bandpass filter (0.7–4.0 Hz)
    /// Implemented as cascaded high-pass + low-pass (Butterworth)
    private func applyBandpassFilter(_ input: Float) -> Float {
        let fs = Float(effectiveSampleRate)

        // High-pass at 0.7 Hz — remove DC drift and respiration
        // Butterworth 2nd order: pre-warped bilinear transform
        let fHP: Float = 0.7
        let wHP = tanf(Float.pi * fHP / fs)
        let wHP2 = wHP * wHP
        let aHP0: Float = 1.0 / (1.0 + 1.414 * wHP + wHP2)
        let aHP1: Float = -2.0 * aHP0
        let aHP2: Float = aHP0
        let bHP1: Float = 2.0 * (wHP2 - 1.0) * aHP0
        let bHP2: Float = (1.0 - 1.414 * wHP + wHP2) * aHP0

        let hpOut = aHP0 * input + aHP1 * bpState.hp_x1 + aHP2 * bpState.hp_x2
            - bHP1 * bpState.hp_y1 - bHP2 * bpState.hp_y2

        bpState.hp_x2 = bpState.hp_x1
        bpState.hp_x1 = input
        bpState.hp_y2 = bpState.hp_y1
        bpState.hp_y1 = hpOut

        // Low-pass at 4.0 Hz — remove high-frequency noise
        let fLP: Float = 4.0
        let wLP = tanf(Float.pi * fLP / fs)
        let wLP2 = wLP * wLP
        let aLP0: Float = wLP2 / (1.0 + 1.414 * wLP + wLP2)
        let aLP1: Float = 2.0 * aLP0
        let aLP2: Float = aLP0
        let bLP1: Float = 2.0 * (wLP2 - 1.0) / (1.0 + 1.414 * wLP + wLP2)
        let bLP2: Float = (1.0 - 1.414 * wLP + wLP2) / (1.0 + 1.414 * wLP + wLP2)

        let lpOut = aLP0 * hpOut + aLP1 * bpState.lp_x1 + aLP2 * bpState.lp_x2
            - bLP1 * bpState.lp_y1 - bLP2 * bpState.lp_y2

        bpState.lp_x2 = bpState.lp_x1
        bpState.lp_x1 = hpOut
        bpState.lp_y2 = bpState.lp_y1
        bpState.lp_y1 = lpOut

        return lpOut
    }

    // MARK: - Peak Detection

    /// Adaptive threshold peak detection
    /// Finds local maxima in filtered signal with minimum inter-beat interval
    private func detectPeaks(latestFiltered: Float, timestamp: TimeInterval) {
        let n = rawRedSignal.count
        guard n >= 5 else { return }

        // Re-filter recent window for peak detection (last 10 seconds)
        let windowSize = min(n, Int(effectiveSampleRate * 10))
        let startIdx = n - windowSize

        // Build filtered signal for window
        var filteredWindow = [Float](repeating: 0, count: windowSize)
        var tempState = BandpassState()
        for i in 0..<windowSize {
            let fs = Float(effectiveSampleRate)
            let input = rawRedSignal[startIdx + i]

            // High-pass
            let fHP: Float = 0.7
            let wHP = tanf(Float.pi * fHP / fs)
            let wHP2 = wHP * wHP
            let aHP0: Float = 1.0 / (1.0 + 1.414 * wHP + wHP2)
            let aHP1: Float = -2.0 * aHP0
            let aHP2: Float = aHP0
            let bHP1: Float = 2.0 * (wHP2 - 1.0) * aHP0
            let bHP2: Float = (1.0 - 1.414 * wHP + wHP2) * aHP0

            let hpOut = aHP0 * input + aHP1 * tempState.hp_x1 + aHP2 * tempState.hp_x2
                - bHP1 * tempState.hp_y1 - bHP2 * tempState.hp_y2
            tempState.hp_x2 = tempState.hp_x1
            tempState.hp_x1 = input
            tempState.hp_y2 = tempState.hp_y1
            tempState.hp_y1 = hpOut

            // Low-pass
            let fLP: Float = 4.0
            let wLP = tanf(Float.pi * fLP / fs)
            let wLP2 = wLP * wLP
            let aLP0: Float = wLP2 / (1.0 + 1.414 * wLP + wLP2)
            let aLP1: Float = 2.0 * aLP0
            let aLP2: Float = aLP0
            let bLP1: Float = 2.0 * (wLP2 - 1.0) / (1.0 + 1.414 * wLP + wLP2)
            let bLP2: Float = (1.0 - 1.414 * wLP + wLP2) / (1.0 + 1.414 * wLP + wLP2)

            let lpOut = aLP0 * hpOut + aLP1 * tempState.lp_x1 + aLP2 * tempState.lp_x2
                - bLP1 * tempState.lp_y1 - bLP2 * tempState.lp_y2
            tempState.lp_x2 = tempState.lp_x1
            tempState.lp_x1 = hpOut
            tempState.lp_y2 = tempState.lp_y1
            tempState.lp_y1 = lpOut

            filteredWindow[i] = lpOut
        }

        // Adaptive threshold: 60% of max amplitude in recent window
        var maxAmp: Float = 0
        vDSP_maxv(filteredWindow, 1, &maxAmp, vDSP_Length(windowSize))
        var minAmp: Float = 0
        vDSP_minv(filteredWindow, 1, &minAmp, vDSP_Length(windowSize))
        let amplitude = maxAmp - minAmp
        let threshold = minAmp + amplitude * 0.6

        // Minimum inter-beat interval: 300ms (200 BPM max)
        let minPeakDistance = Int(effectiveSampleRate * 0.3)

        // Find peaks
        var newPeaks: [Int] = []
        for i in 2..<(windowSize - 2) {
            let val = filteredWindow[i]
            guard val > threshold else { continue }
            // Local maximum: higher than 2 neighbors on each side
            if val > filteredWindow[i - 1] && val > filteredWindow[i - 2]
                && val > filteredWindow[i + 1] && val > filteredWindow[i + 2] {

                // Check minimum distance from last peak
                if let lastPeak = newPeaks.last {
                    guard (i - lastPeak) >= minPeakDistance else { continue }
                }
                newPeaks.append(i)
            }
        }

        // Convert peak indices to absolute indices and calculate intervals
        guard newPeaks.count >= 3 else { return }

        var intervals: [Double] = []
        for j in 1..<newPeaks.count {
            let dt = signalTimestamps[startIdx + newPeaks[j]] - signalTimestamps[startIdx + newPeaks[j - 1]]
            // Validate: 300ms to 1500ms (40-200 BPM)
            guard dt > 0.3 && dt < 1.5 else { continue }
            intervals.append(dt)
        }

        guard intervals.count >= 2 else { return }

        // Reject outliers: remove intervals > 1.5 IQR from median
        let sorted = intervals.sorted()
        let median = sorted[sorted.count / 2]
        let q1 = sorted[sorted.count / 4]
        let q3 = sorted[sorted.count * 3 / 4]
        let iqr = q3 - q1
        let cleanIntervals = intervals.filter {
            $0 > (q1 - 1.5 * iqr) && $0 < (q3 + 1.5 * iqr)
        }

        guard !cleanIntervals.isEmpty else { return }

        let avgInterval = cleanIntervals.reduce(0, +) / Double(cleanIntervals.count)
        let bpm = 60.0 / avgInterval

        // Confidence from interval consistency
        let variance = cleanIntervals.reduce(0.0) { $0 + ($1 - avgInterval) * ($1 - avgInterval) }
            / Double(cleanIntervals.count)
        let stdDev = sqrt(variance)
        let cv = stdDev / avgInterval // coefficient of variation
        let confidence = max(0, min(1, 1.0 - cv * 3.0)) // CV < 0.33 = full confidence

        // Smooth BPM output
        if confidence > 0.3 {
            if estimatedBPM == 0 {
                estimatedBPM = bpm
            } else {
                estimatedBPM = estimatedBPM * 0.7 + bpm * 0.3
            }
            bpmConfidence = bpmConfidence * 0.8 + confidence * 0.2
        }

        // Store RR intervals for HRV (in milliseconds)
        rrIntervals = cleanIntervals.map { $0 * 1000.0 }

        // Calculate RMSSD
        if rrIntervals.count >= 3 {
            calculateRMSSD()
        }
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

            // Good PPG signal has small but measurable variance
            let snr = Double(variance)
            if snr > 0.0001 && snr < 0.01 {
                quality += 0.3
            }
        }

        signalQuality = signalQuality * 0.9 + quality * 0.1
    }

    // MARK: - Cleanup

    func reset() {
        resetPulseState()
        brightness = 0.5
        redChannel = 0.5
        filterModulation = 0.5
        isPulseDetecting = false
        isFingerDetected = false
        fingerDetectionBuffer.removeAll()
    }
}
#endif
