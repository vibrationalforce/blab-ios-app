import Foundation
import AVFoundation
import Accelerate

/// Real-time pitch detection using the YIN algorithm
/// YIN is a robust fundamental frequency estimator designed for speech and music
///
/// Reference: "YIN, a fundamental frequency estimator for speech and music"
/// by Alain de Cheveigné and Hideki Kawahara (2002)
class PitchDetector {

    // MARK: - Configuration

    /// YIN threshold for pitch detection (0.0 - 1.0)
    /// Lower = more sensitive but more false positives
    /// Higher = more conservative but may miss quiet notes
    private let threshold: Float = 0.1

    /// Minimum detectable frequency (Hz)
    /// Human voice typically ranges from 80 Hz (bass) to 1100 Hz (soprano)
    private let minFrequency: Float = 60.0

    /// Maximum detectable frequency (Hz)
    private let maxFrequency: Float = 2000.0

    /// Minimum RMS amplitude to consider as signal (not silence)
    private let silenceThreshold: Float = 0.001


    // MARK: - Public Methods

    /// Detect fundamental frequency (pitch) from audio buffer using YIN algorithm
    ///
    /// The YIN algorithm steps:
    /// 1. Calculate difference function (similar to autocorrelation)
    /// 2. Cumulative mean normalized difference function (CMNDF)
    /// 3. Find absolute minimum below threshold
    /// 4. Parabolic interpolation for sub-sample accuracy
    ///
    /// - Parameters:
    ///   - buffer: Audio buffer containing PCM samples
    ///   - sampleRate: Sample rate of the audio (typically 44100 or 48000 Hz)
    /// - Returns: Detected pitch in Hz, or 0.0 if no pitch detected
    func detectPitch(buffer: AVAudioPCMBuffer, sampleRate: Float) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else {
            return 0.0
        }

        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0.0 }

        // Check for silence (RMS below threshold)
        let rms = calculateRMS(channelData, frameLength: frameLength)
        guard rms > silenceThreshold else {
            return 0.0
        }

        // Calculate buffer size for YIN (half the frame length for efficiency)
        let bufferSize = frameLength / 2

        // Calculate lag range based on frequency constraints
        let minLag = Int(sampleRate / maxFrequency)
        let maxLag = min(Int(sampleRate / minFrequency), bufferSize)

        guard maxLag > minLag else { return 0.0 }

        // Step 1: Calculate difference function
        var differenceFunction = [Float](repeating: 0, count: maxLag)
        calculateDifferenceFunction(channelData,
                                   frameLength: frameLength,
                                   differenceFunction: &differenceFunction,
                                   maxLag: maxLag)

        // Step 2: Cumulative mean normalized difference function
        var cmndf = [Float](repeating: 0, count: maxLag)
        calculateCMNDF(differenceFunction: differenceFunction,
                      cmndf: &cmndf,
                      maxLag: maxLag)

        // Step 3: Find absolute minimum below threshold
        guard let tau = findAbsoluteMinimum(cmndf: cmndf,
                                           minLag: minLag,
                                           maxLag: maxLag,
                                           threshold: threshold) else {
            return 0.0
        }

        // Step 4: Parabolic interpolation for sub-sample accuracy
        let refinedTau = parabolicInterpolation(cmndf: cmndf, tau: tau)

        // Convert lag (tau) to frequency
        let pitch = sampleRate / refinedTau

        // Validate pitch is in expected range
        guard pitch >= minFrequency && pitch <= maxFrequency else {
            return 0.0
        }

        return pitch
    }


    // MARK: - Private Methods

    /// Calculate RMS (Root Mean Square) amplitude using vDSP
    private func calculateRMS(_ data: UnsafePointer<Float>, frameLength: Int) -> Float {
        var rms: Float = 0.0
        vDSP_rmsqv(data, 1, &rms, vDSP_Length(frameLength))
        return rms
    }

    /// Step 1: Calculate difference function
    /// d_t(τ) = Σ (x_j - x_(j+τ))²
    ///
    /// This is similar to autocorrelation but uses squared differences
    /// Optimized with vDSP for vectorized operations
    private func calculateDifferenceFunction(_ data: UnsafePointer<Float>,
                                            frameLength: Int,
                                            differenceFunction: inout [Float],
                                            maxLag: Int) {
        // Each lag τ compares frameLength - τ samples.  Using a fixed window length
        // truncates low-lag comparisons and skews the YIN difference function.  We
        // adapt the length per τ and rely on vDSP to sum the squared distances
        // without allocating temporary buffers.
        guard maxLag > 0 else { return }

        differenceFunction[0] = 0.0

        guard maxLag > 1 else { return }

        for tau in 1..<maxLag {
            let length = frameLength - tau

            guard length > 0 else {
                differenceFunction[tau] = 0.0
                continue
            }

            var sum: Float = 0.0

            vDSP_distancesq(data,
                             1,
                             data.advanced(by: tau),
                             1,
                             &sum,
                             vDSP_Length(length))

            differenceFunction[tau] = sum
        }
    }

    /// Step 2: Calculate Cumulative Mean Normalized Difference Function (CMNDF)
    /// d'_t(τ) = d_t(τ) / [(1/τ) * Σ d_t(j)] for τ > 0
    /// d'_t(0) = 1
    ///
    /// This normalization makes the function independent of signal amplitude
    private func calculateCMNDF(differenceFunction: [Float],
                               cmndf: inout [Float],
                               maxLag: Int) {
        // First value is always 1 by definition
        cmndf[0] = 1.0

        var cumulativeSum: Float = 0.0

        for tau in 1..<maxLag {
            cumulativeSum += differenceFunction[tau]

            // Avoid division by zero
            if cumulativeSum == 0 {
                cmndf[tau] = 1.0
            } else {
                // d'(τ) = d(τ) * τ / cumulativeSum
                cmndf[tau] = differenceFunction[tau] * Float(tau) / cumulativeSum
            }
        }
    }

    /// Step 3: Find absolute minimum below threshold
    /// Search for the first minimum that goes below the threshold
    ///
    /// - Parameters:
    ///   - cmndf: Cumulative mean normalized difference function
    ///   - minLag: Minimum lag to search (based on maxFrequency)
    ///   - maxLag: Maximum lag to search (based on minFrequency)
    ///   - threshold: YIN threshold (typically 0.1)
    /// - Returns: The lag (tau) at the absolute minimum, or nil if none found
    private func findAbsoluteMinimum(cmndf: [Float],
                                    minLag: Int,
                                    maxLag: Int,
                                    threshold: Float) -> Int? {
        // Start searching from minLag
        for tau in minLag..<maxLag {
            // Look for values below threshold
            if cmndf[tau] < threshold {
                // Found a candidate, now search for local minimum
                // A local minimum is where d'(τ-1) > d'(τ) < d'(τ+1)
                var minTau = tau

                // Continue until we find a local minimum or hit the end
                while minTau + 1 < maxLag {
                    if cmndf[minTau + 1] < cmndf[minTau] {
                        minTau += 1
                    } else {
                        break
                    }
                }

                return minTau
            }
        }

        // If no value below threshold, return absolute minimum in range
        var minValue = cmndf[minLag]
        var minTau = minLag

        for tau in (minLag + 1)..<maxLag {
            if cmndf[tau] < minValue {
                minValue = cmndf[tau]
                minTau = tau
            }
        }

        // Only return if the minimum is reasonably low
        if minValue < threshold * 2.0 {
            return minTau
        }

        return nil
    }

    /// Step 4: Parabolic interpolation for sub-sample accuracy
    /// Uses three points around the minimum to estimate the true minimum
    ///
    /// Given three points: (x-1, y-1), (x, y), (x+1, y+1)
    /// The interpolated minimum is at: x + (y-1 - y+1) / (2 * (y-1 - 2y + y+1))
    ///
    /// - Parameters:
    ///   - cmndf: Cumulative mean normalized difference function
    ///   - tau: Integer lag position
    /// - Returns: Refined lag with sub-sample accuracy
    private func parabolicInterpolation(cmndf: [Float], tau: Int) -> Float {
        // Need at least one sample on each side for interpolation
        guard tau > 0 && tau < cmndf.count - 1 else {
            return Float(tau)
        }

        let y1 = cmndf[tau - 1]  // Previous sample
        let y2 = cmndf[tau]      // Current sample (minimum)
        let y3 = cmndf[tau + 1]  // Next sample

        // Parabolic interpolation formula
        let numerator = y1 - y3
        let denominator = 2.0 * (y1 - 2.0 * y2 + y3)

        // Avoid division by zero or very small numbers
        guard abs(denominator) > 0.0001 else {
            return Float(tau)
        }

        let delta = numerator / denominator

        // The interpolated peak should be within ±0.5 of the integer peak
        guard abs(delta) < 1.0 else {
            return Float(tau)
        }

        return Float(tau) + delta
    }


    // MARK: - Utility Methods

    /// Get next power of 2 for efficient FFT (if needed in future)
    private func nextPowerOf2(_ value: Int) -> Int {
        guard value > 1 else { return 1 }
        return 1 << (Int.bitWidth - (value - 1).leadingZeroBitCount)
    }
}
