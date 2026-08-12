//
//  HapticEngine.swift
//  Echoelmusic — Studio (eyes-free performance feedback)
//
//  The side-effecting CoreHaptics layer that plays the pure `HapticCue` values
//  produced by `BioHaptics`. Same split the codebase uses elsewhere (pure kernel
//  + thin engine), so all the mapping logic stays unit-tested in `BioHaptics`
//  and this file is a minimal, capability-gated player.
//
//  Design (research §A5):
//   • A SEPARATE `playsHapticsOnly` engine — decoupled from the audio render
//     path, lower start-up latency, and it never touches the audio thread.
//   • `setAllowHapticsAndSystemSoundsDuringRecording(true)` — without it the
//     `.playAndRecord` session (mic-over-beats, video) silently kills haptics.
//   • Capability-gated: a no-op on hardware without a haptic engine, so callers
//     can fire cues unconditionally.
//
//  ⛔ THE LINE THAT STOOD HERE FILED THIS FILE AS INERT AND ITS WIRING AS FUTURE
//  WORK, naming both drivers. Measured 2026-08-12 (#552): the sequencer half is
//  DONE — `EchoelmusicApp` registers `transport.addStepSubscriber("haptics", …)`,
//  which calls `HapticController.tapBeat(step:)`, which reaches `play(_:)` below;
//  the arming switch is `hapticsRow` in `tempoToolsPanel`, behind the Tempo chip.
//  This file changes behaviour on every quarter-note once the user arms haptics.
//  Only the bio half is still absent, and the warning at
//  `HapticController.breath(phase:coherence:)` says why its obvious wiring site
//  (the ~10 Hz poll tick, against a 0,1-s continuous cue) would produce a
//  continuous buzz rather than a breath.
//

#if canImport(CoreHaptics)
import Foundation
import CoreHaptics
#if canImport(AVFoundation)
import AVFoundation
#endif

@available(iOS 13.0, macOS 11.0, *)
@MainActor
public final class HapticEngine {

    /// Whether this device has a usable haptic engine. False on CI/Simulator/Mac
    /// without a Taptic Engine — `start()` and `play()` then no-op.
    public private(set) var supportsHaptics: Bool

    /// Whether the engine is started and ready to play.
    public private(set) var isRunning = false

    private var engine: CHHapticEngine?

    public init() {
        supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    // MARK: - Lifecycle

    /// Starts the haptic engine. Idempotent; a no-op when haptics are unsupported.
    public func start() {
        guard supportsHaptics, engine == nil else { return }
        configureAudioSessionForHaptics()
        do {
            let created = try CHHapticEngine()
            created.playsHapticsOnly = true            // not an audio source → lower latency
            created.isAutoShutdownEnabled = true        // idle-shutdown, restarted on demand
            created.resetHandler = { [weak self] in
                Task { @MainActor in try? self?.engine?.start() }
            }
            created.stoppedHandler = { [weak self] _ in
                Task { @MainActor in self?.isRunning = false }
            }
            try created.start()
            engine = created
            isRunning = true
        } catch {
            log.log(.error, category: .accessibility,
                    "Haptic engine start failed: \(error.localizedDescription)")
        }
    }

    /// Stops and releases the engine.
    public func stop() {
        engine?.stop(completionHandler: nil)
        engine = nil
        isRunning = false
    }

    // MARK: - Playback

    /// Plays one cue immediately. Safe no-op when unsupported or not started.
    public func play(_ cue: HapticCue) {
        guard isRunning, let engine else { return }
        do {
            let player = try engine.makePlayer(with: Self.pattern(for: cue))
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            log.log(.error, category: .accessibility,
                    "Haptic play failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Cue → pattern (data only; no hardware needed)

    /// Builds a CoreHaptics pattern from a pure `HapticCue`. Transient cues carry
    /// no duration; continuous cues use the cue's duration.
    static func pattern(for cue: HapticCue) throws -> CHHapticPattern {
        let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: cue.intensity)
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: cue.sharpness)
        let event: CHHapticEvent
        switch cue.kind {
        case .transient:
            event = CHHapticEvent(eventType: .hapticTransient,
                                  parameters: [intensity, sharpness], relativeTime: 0)
        case .continuous:
            event = CHHapticEvent(eventType: .hapticContinuous,
                                  parameters: [intensity, sharpness],
                                  relativeTime: 0, duration: TimeInterval(cue.duration))
        }
        return try CHHapticPattern(events: [event], parameters: [])
    }

    // MARK: - Audio session

    #if canImport(AVFoundation) && os(iOS)
    private func configureAudioSessionForHaptics() {
        // Best-effort: allow haptics to play through a recording session.
        try? AVAudioSession.sharedInstance().setAllowHapticsAndSystemSoundsDuringRecording(true)
    }
    #else
    private func configureAudioSessionForHaptics() {}
    #endif
}
#endif
