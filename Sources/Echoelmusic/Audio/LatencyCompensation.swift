// LatencyCompensation.swift
// Echoel — align a recorded take back to the beat. A performer hears the backing
// track delayed by the output latency and sings to what they hear; the mic then
// captures that with the input latency on top. So the recorded file sits LATE by
// the round-trip (output + input) — ~10–30 ms wired, ~150–250 ms over Bluetooth.
// Removing that head offset lines the take up with the transport, which is what
// makes "record over Bluetooth and still produce in time" actually work.
//
// Pure value type (fully unit-tested); the live AVAudioSession reading is a
// thin, platform-guarded convenience.

import Foundation

/// The round-trip latency between the transport and a captured take.
public struct LatencyCompensation: Sendable, Equatable, Codable {

    /// Output (playback) latency in seconds — what delays the beat the singer hears.
    public var outputLatency: Double
    /// Input (capture) latency in seconds — what delays the mic signal.
    public var inputLatency: Double
    /// Manual nudge for residual offset a user dials in by ear.
    public var extraSeconds: Double

    public init(outputLatency: Double = 0, inputLatency: Double = 0, extraSeconds: Double = 0) {
        self.outputLatency = outputLatency
        self.inputLatency = inputLatency
        self.extraSeconds = extraSeconds
    }

    /// Total head offset to remove, never negative.
    public var totalSeconds: Double { max(0, outputLatency + inputLatency + extraSeconds) }

    /// The offset expressed in samples at a given sample rate.
    public func frameOffset(sampleRate: Double) -> Int {
        guard sampleRate > 0 else { return 0 }
        return Int((totalSeconds * sampleRate).rounded())
    }

    /// Align a captured buffer to the transport by dropping the round-trip
    /// latency from its head. Returns the trimmed samples; if the take is shorter
    /// than the offset there is nothing usable, so it returns empty.
    public func aligned(_ samples: [Float], sampleRate: Double) -> [Float] {
        let off = frameOffset(sampleRate: sampleRate)
        guard off > 0 else { return samples }
        guard off < samples.count else { return [] }
        return Array(samples[off...])
    }
}

#if canImport(AVFoundation) && !os(macOS)
import AVFoundation

public extension LatencyCompensation {
    /// Read the live round-trip latency from the active audio session. Reflects
    /// the current route, so it is correct for whatever is connected right now
    /// (built-in, wired, USB, or Bluetooth). macOS uses the HAL (no AVAudioSession).
    static func current(extraSeconds: Double = 0) -> LatencyCompensation {
        let s = AVAudioSession.sharedInstance()
        return LatencyCompensation(outputLatency: s.outputLatency,
                                   inputLatency: s.inputLatency,
                                   extraSeconds: extraSeconds)
    }
}
#endif
