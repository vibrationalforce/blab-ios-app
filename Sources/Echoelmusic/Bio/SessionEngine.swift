//
//  SessionEngine.swift
//  Echoelmusic — Bio
//
//  The orchestrator of the bio-paced Session (warm-restart cycle 4). It closes the
//  loop by composing the three proven, tested cores over live biofeedback:
//
//    live rPPG/breath (EngineBus.latestBio, 10 Hz)
//        → SessionGuide      (ease the breath toward personal resonance)
//        → EntrainmentEngine (flash-SAFE audio pulse + visual pulse plan)
//        → SessionClock      (latency-compensated phase, so it lands on the grid)
//        → a soft, launch-silent audio breathing cue  +  published visual state.
//
//  The realtime feel comes from the LOCAL cue (a slow amplitude swell generated on
//  the audio thread off its own sample clock), not from chasing the sensor. The
//  sensor only nudges the SLOW target (the pace), on the 10 Hz poll.
//
//  Threading follows the repo's proven BioReactiveSynthVoice discipline: an
//  AVAudioSourceNode whose render block reads only Float-atomic `nonisolated(unsafe)`
//  mirrors + its own scratch state, launch-silent until `arm()`. The MainActor 10 Hz
//  poll writes those mirrors and the @Observable session state. NO locks / malloc /
//  ObjC / GCD on the render path.
//
//  Honest scope: this guides the breath and pairs a calming tone + light with it —
//  self-observation and self-regulation, NOT therapy, treatment, or diagnosis, and
//  it makes no brainwave/EEG claim (we pace cardiac/respiratory rhythm, the only
//  rhythm we measure).
//

import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif

/// The per-tick decision: the pace we guide toward and the flash-safe plan for it.
/// Pure and testable — the orchestrator just applies it.
public struct SessionPlan: Equatable, Sendable {
    public var paceBpm: Double
    public var targetHz: Double
    public var entrainment: EntrainmentPlan
    public init(paceBpm: Double, targetHz: Double, entrainment: EntrainmentPlan) {
        self.paceBpm = paceBpm
        self.targetHz = targetHz
        self.entrainment = entrainment
    }
}

@MainActor
@Observable
public final class SessionEngine {

    // MARK: - Published session state (read in LEAF views only — 10 Hz churn)

    /// Whether the session is running (armed + audible). Safe to read anywhere.
    public private(set) var isRunning = false
    /// The breathing pace currently guided toward, breaths/min (for the cue label).
    @ObservationIgnored public private(set) var currentPaceBpm: Double = SessionGuide.defaultResonancePace
    /// The current entrainment plan (audio/visual rates, flash-safe). @ObservationIgnored
    /// so the 10 Hz refresh never invalidates an ancestor body (menu-freeze class).
    @ObservationIgnored public private(set) var currentPlan: SessionPlan = SessionPlan(
        paceBpm: SessionGuide.defaultResonancePace, targetHz: 0.1, entrainment: .steady)
    /// Elapsed session seconds (for the guide + a progress ring). @ObservationIgnored.
    @ObservationIgnored public private(set) var elapsedSeconds: Double = 0
    /// Latency-compensated visual brightness [0…1] for the light — read this in the
    /// Metal/visual LEAF only (it updates ~10 Hz; a parent read would freeze menus).
    @ObservationIgnored public private(set) var visualBrightness: Double = 0
    /// True when the light must not flicker (target unsafe/absent) → steady swell.
    @ObservationIgnored public private(set) var visualIsSteady = true

    // MARK: - Config

    /// How far the guide eases (seconds) from natural pace to resonance.
    public var descentSeconds: Double = SessionGuide.defaultDescentSeconds
    /// Cue intensity 0…1 (audio swell depth + visual brightness depth).
    public var intensity: Double = 0.8

    // MARK: - Bus / loop

    @ObservationIgnored private weak var bus: EngineBus?
    @ObservationIgnored private let loop = PollingLoop()
    @ObservationIgnored private var guide: SessionGuide?
    @ObservationIgnored private var sessionStart: CFAbsoluteTime = 0

    // MARK: - Audio (render-thread mirrors — Float-atomic, nonisolated(unsafe))

    // nonisolated: these constants are read on the audio thread (renderOnAudioThread,
    // a nonisolated context) — immutable Sendable values, so nonisolated is safe and
    // required (matches the blessed BioReactiveSynthVoice render-read statics).
    @ObservationIgnored nonisolated private static let sampleRate: Double = 48_000
    @ObservationIgnored nonisolated private static let carrierHz: Double = 220.0   // soft A3, neutral (no esoterik)
    @ObservationIgnored nonisolated private static let baseGain: Float = 0.16      // gentle; master trim holds level

    /// Breath pulse rate the audio swell follows (Hz). Written on main, read on audio.
    @ObservationIgnored nonisolated(unsafe) private var renderHz: Float = 0.1
    /// Swell depth 0…1 (how much the amplitude breathes). Written main, read audio.
    @ObservationIgnored nonisolated(unsafe) private var renderDepth: Float = 0.8
    /// Audio output latency to compensate (s) — advance the gate phase by this so the
    /// heard swell lands on the grid. Written main, read audio.
    @ObservationIgnored nonisolated(unsafe) private var audioLatency: Float = 0.005
    /// Launch-silence: pure zero until the first `arm()`. Written main, read audio.
    @ObservationIgnored nonisolated(unsafe) private var hasEverSounded = false

    /// Audio-thread-only running state (after attach).
    @ObservationIgnored nonisolated(unsafe) private var sampleClock: UInt64 = 0
    @ObservationIgnored nonisolated(unsafe) private var carrierPhase: Double = 0

    #if canImport(AVFoundation)
    @ObservationIgnored public lazy var sourceNode: AVAudioSourceNode = makeSourceNode()
    #endif

    public init() {}

    // MARK: - Lifecycle

    #if canImport(AVFoundation)
    /// Attach BEFORE `audioEngine.start()` (build-1363 hot-attach rule).
    public func attach(to audioEngine: AudioEngine) {
        audioEngine.attachSourceNode(sourceNode)
    }
    #endif

    /// Feed the measured audio output latency (AVAudioSession.outputLatency + IO
    /// buffer) so the heard swell is compensated. Clamped in SessionClock.
    public func setAudioLatency(_ seconds: Double) {
        audioLatency = Float(SessionClock.safeDelay(seconds))
    }

    /// Begin the session: arm the cue and start the 10 Hz closed loop.
    public func start(subscribing bus: EngineBus) {
        self.bus = bus
        guide = nil
        sessionStart = CFAbsoluteTimeGetCurrent()
        elapsedSeconds = 0
        isRunning = true
        hasEverSounded = true          // audio may now sound (launch-silence lifted)
        loop.start(interval: .milliseconds(100)) { [weak self] in
            self?.tick()
        }
    }

    public func stop() {
        loop.stop()
        isRunning = false
        renderDepth = 0                // fade the swell out (tone settles to steady quiet)
        visualBrightness = 0
        visualIsSteady = true
        guide = nil
    }

    // MARK: - The 10 Hz closed loop (MainActor)

    private func tick() {
        guard isRunning else { return }
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = Swift.max(0, now - sessionStart)
        elapsedSeconds = elapsed

        // Build the guide from the first usable breathing rate; hold it for the run
        // so the descent is stable (a new guide every tick would never progress).
        if guide == nil {
            let measured = bus?.usableBio().map { Double($0.breathRate) } ?? 12.0
            guide = SessionGuide(measuredBreathsPerMinute: measured, descentSeconds: descentSeconds)
        }
        guard let guide else { return }

        let coherence = bus?.usableBio().map { Double($0.coherence) } ?? 0
        let plan = Self.plan(guide: guide, elapsedSeconds: elapsed,
                             coherence: coherence, intensity: intensity)
        currentPlan = plan
        currentPaceBpm = plan.paceBpm

        // Push audio mirrors (Float-atomic) for the render thread.
        renderHz = Float(plan.targetHz)
        renderDepth = Float(Swift.min(1, Swift.max(0, intensity)))

        // Publish latency-compensated visual brightness for the visual LEAF. The
        // light breathes with the SAME plan; steady when the plan says so.
        visualIsSteady = plan.entrainment.visualIsSteady
        if plan.entrainment.visualIsSteady {
            visualBrightness = plan.entrainment.brightnessDelta * 0.5   // gentle steady glow
        } else {
            let g = SessionClock.renderGate(hostSeconds: elapsed,
                                            hz: plan.entrainment.visualPulseHz,
                                            perceptualDelaySeconds: 1.0 / 60.0)  // ~1 frame
            visualBrightness = plan.entrainment.brightnessDelta * g
        }
    }

    /// Pure per-tick composition (testable): guide → pace → flash-safe entrainment.
    /// `nonisolated` — pure over the tested cores, no actor state, safe to unit-test.
    public nonisolated static func plan(guide: SessionGuide, elapsedSeconds: Double,
                                        coherence: Double, intensity: Double) -> SessionPlan {
        let bpm = guide.targetBpm(atSeconds: elapsedSeconds, coherence: coherence)
        let hz = bpm / 60.0
        let e = EntrainmentEngine.plan(targetHz: hz, intensity: intensity)
        return SessionPlan(paceBpm: bpm, targetHz: hz, entrainment: e)
    }

    // MARK: - Audio (render thread)

    #if canImport(AVFoundation)
    private func makeSourceNode() -> AVAudioSourceNode {
        nonisolated(unsafe) let weakSelf = WeakSessionBox(self)
        let renderBlock: AVAudioSourceNodeRenderBlock = { _, _, frameCount, abl in
            guard let engine = weakSelf.value else {
                SessionEngine.silence(abl, frameCount: Int(frameCount)); return noErr
            }
            engine.renderOnAudioThread(frameCount: Int(frameCount), abl: abl)
            return noErr
        }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1) else {
            return AVAudioSourceNode(renderBlock: renderBlock)
        }
        return AVAudioSourceNode(format: format, renderBlock: renderBlock)
    }

    /// Audio thread. A soft carrier sine whose amplitude BREATHES at the target rate,
    /// latency-compensated, launch-silent until armed. No locks/malloc/ObjC/GCD.
    nonisolated(unsafe) private func renderOnAudioThread(
        frameCount: Int, abl: UnsafeMutablePointer<AudioBufferList>) {
        guard hasEverSounded else { Self.silence(abl, frameCount: frameCount); return }
        let sr = Self.sampleRate
        let hz = Double(renderHz)
        let depth = Double(renderDepth)
        let lat = Double(audioLatency)
        let carrierInc = 2 * Double.pi * Self.carrierHz / sr
        let bufs = UnsafeMutableAudioBufferListPointer(abl)
        guard bufs.count > 0, let raw = bufs[0].mData else { return }
        let dst = raw.assumingMemoryBound(to: Float.self)
        var phase = carrierPhase
        var clock = sampleClock
        for i in 0..<frameCount {
            let t = Double(clock) / sr
            // Latency-compensated breath swell in [0,1] (raised cosine at hz).
            let gate = EntrainmentEngine.gate(atSeconds: t + lat, hz: hz)
            let amp = Double(Self.baseGain) * ((1 - depth) + depth * gate)
            dst[i] = Float(sin(phase) * amp)
            phase += carrierInc
            if phase > 2 * Double.pi { phase -= 2 * Double.pi }
            clock &+= 1
        }
        carrierPhase = phase
        sampleClock = clock
    }

    nonisolated private static func silence(
        _ abl: UnsafeMutablePointer<AudioBufferList>, frameCount: Int) {
        let bufs = UnsafeMutableAudioBufferListPointer(abl)
        guard bufs.count > 0, let raw = bufs[0].mData else { return }
        raw.assumingMemoryBound(to: Float.self).update(repeating: 0, count: frameCount)
    }
    #endif
}

/// Weak holder so the audio-thread render closure captures the MainActor engine
/// without retaining it.
private final class WeakSessionBox: @unchecked Sendable {
    weak var value: SessionEngine?
    init(_ value: SessionEngine) { self.value = value }
}
