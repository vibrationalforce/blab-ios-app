//
//  FXBioModulator.swift
//  Echoelmusic — the control-rate driver that makes EchoelFX bio-reactive.
//
//  Reads the live bio snapshot + free LFOs at ~30 Hz and writes the modulated FX
//  parameters to the audio-thread `EchoelFXChain` (the same plain-Float atomic-width
//  write contract the FX view-model already uses — no locks, no audio-thread work).
//  Pure mapping lives in `FXModulation`; this object holds the routes, the captured
//  user "base" per target, and the timing.
//
//  Ownership model (kept simple + conflict-free): while a target has ≥1 enabled
//  route, this driver OWNS that parameter — it captures the user's base once, drives
//  the param around it, and enables the target's stage so the move is audible. When
//  the last route on a target is removed/disabled, it restores the base.
//

import Foundation

@MainActor
@Observable
public final class FXBioModulator {

    /// The routes the user has set up. Editing these is what the FX "Bio-reactive"
    /// section does. Observed so the UI reflects add/remove/enable.
    public var routes: [FXModRoute] = [] {
        didSet { reconcileBases() }
    }

    /// Whether the driver loop is running (a session is live).
    public private(set) var isRunning = false

    /// Live per-route contributions for the "which parameters is the body moving"
    /// display (Item 2). Refreshed at ~10 Hz (throttled from the 30 Hz tick) so a
    /// leaf view can observe it without registering the whole tree as a 30 Hz
    /// observer (menu-freeze law). Empty when stopped or no enabled routes.
    public private(set) var liveContributions: [BioModContribution] = []
    @ObservationIgnored private var tickCount = 0
    /// 30 Hz tick / 3 ≈ 10 Hz UI refresh.
    @ObservationIgnored private static let publishEveryN = 3

    @ObservationIgnored private var chain: EchoelFXChain?
    @ObservationIgnored private weak var bus: EngineBus?
    /// The user's intended value per modulated target, captured when the target's
    /// first route is enabled and restored when its last route goes away.
    @ObservationIgnored private var baseValues: [FXModTarget: Float] = [:]
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let startTime = CFAbsoluteTimeGetCurrent()

    public init() {}

    /// Bind to the chain a voice owns + the bio bus. Safe to call again to rebind.
    public func attach(chain: EchoelFXChain, bus: EngineBus) {
        self.chain = chain
        self.bus = bus
        reconcileBases()
    }

    public func start() {
        guard !isRunning, chain != nil else { return }
        isRunning = true
        task?.cancel()
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(33))   // ~30 Hz
                guard let self, self.isRunning else { break }
                self.tick()
            }
        }
    }

    public func stop() {
        isRunning = false
        task?.cancel(); task = nil
        liveContributions = []   // display empties when no session is live
        // Restore every captured base so the chain returns to the user's settings.
        if let c = chain {
            for (target, base) in baseValues { write(target, base, to: c) }
        }
    }

    // MARK: - Active targets / base capture

    /// Targets that currently have at least one enabled route.
    private var activeTargets: Set<FXModTarget> {
        Set(routes.filter { $0.enabled }.map { $0.target })
    }

    /// Capture a base for every newly-active target; restore + drop bases for targets
    /// that are no longer modulated. Called on attach and whenever routes change.
    private func reconcileBases() {
        guard let c = chain else { return }
        let active = activeTargets
        // Capture bases for new targets.
        for t in active where baseValues[t] == nil {
            baseValues[t] = read(t, from: c)
        }
        // Restore + drop targets no longer modulated.
        for t in baseValues.keys where !active.contains(t) {
            if let base = baseValues[t] { write(t, base, to: c) }
            baseValues[t] = nil
        }
    }

    // MARK: - Tick

    private func tick() {
        guard let c = chain else { return }
        // Gate on `usableBio()` — the SAME per-source window the mod-brain uses
        // (ModulationEngine.tick). The fixed-5 s `freshBio()` here meant FX
        // bio-modulation stopped after 5 s for a latent Watch/HealthKit source
        // (90 s window) while the main modulation kept steering — inconsistent
        // sound shaping off the same body. Now every sound-shaping bio gate is
        // the one authority: a frame usable to the engine is usable to the FX,
        // and a frame the engine drops (`nil`) drops the FX bio offset too (the
        // `guard let frame else { continue }` below leaves the base value).
        let frame = bus?.usableBio()
        let now = Float(CFAbsoluteTimeGetCurrent() - startTime)
        let active = activeTargets
        for target in active {
            guard let base = baseValues[target] else { continue }
            var sum: Float = 0
            for route in routes where route.enabled && route.target == target {
                let signal: Float
                switch route.carrier {
                case .bio(let source):
                    guard let frame else { continue }   // no body → no bio offset
                    signal = source.normalizedValue(from: frame)
                case .lfo:
                    let phase = (now * route.lfoRateHz).truncatingRemainder(dividingBy: 1)
                    signal = FXModulation.lfoUnipolar(phase: phase)
                }
                sum += FXModulation.offset(target: target, signal: route.curve.apply(signal),
                                           depth: route.depth, bipolar: route.bipolar)
            }
            write(target, FXModulation.combine(base: base, target: target, offset: sum), to: c)
            enableStage(for: target, on: c)   // make the modulation audible
        }
        // Publish the live snapshot at ~10 Hz (throttled) for the visibility leaf.
        // Only write on a real change so an idle/stable state fires no observation.
        tickCount &+= 1
        if FXModulation.shouldPublish(tick: tickCount, everyN: Self.publishEveryN) {
            let next = FXModulation.contributions(routes: routes, frame: frame, now: now)
            if next != liveContributions { liveContributions = next }
        }
    }

    // MARK: - Chain parameter mapping

    private func read(_ t: FXModTarget, from c: EchoelFXChain) -> Float {
        switch t {
        case .filterCutoff:    return c.filterL.cutoff
        case .filterResonance: return c.filterL.resonance
        case .saturationDrive: return c.saturationDrive
        case .chorusMix:       return c.chorus.mix
        case .flangerMix:      return c.flanger.mix
        case .phaserMix:       return c.phaser.mix
        case .tremoloDepth:    return c.tremolo.depth
        case .delayMix:        return c.delay.mix
        case .delayFeedback:   return c.delay.feedback
        case .reverbMix:       return c.reverb.mix
        case .reverbSize:      return c.reverb.roomSize
        case .bitcrushMix:     return c.bitcrush.mix
        case .stereoWidth:     return c.widener.width
        }
    }

    private func write(_ t: FXModTarget, _ v: Float, to c: EchoelFXChain) {
        switch t {
        case .filterCutoff:    c.filterL.cutoff = v; c.filterR.cutoff = v
        case .filterResonance: c.filterL.resonance = v; c.filterR.resonance = v
        case .saturationDrive: c.saturationDrive = v
        case .chorusMix:       c.chorus.mix = v
        case .flangerMix:      c.flanger.mix = v
        case .phaserMix:       c.phaser.mix = v
        case .tremoloDepth:    c.tremolo.depth = v
        case .delayMix:        c.delay.mix = v
        case .delayFeedback:   c.delay.feedback = v
        case .reverbMix:       c.reverb.mix = v
        case .reverbSize:      c.reverb.roomSize = v
        case .bitcrushMix:     c.bitcrush.mix = v
        case .stereoWidth:     c.widener.width = v
        }
    }

    private func enableStage(for t: FXModTarget, on c: EchoelFXChain) {
        switch t {
        case .filterCutoff, .filterResonance: c.filterEnabled = true
        case .saturationDrive:                c.saturationEnabled = true
        case .chorusMix:                      c.chorusEnabled = true
        case .flangerMix:                     c.flangerEnabled = true
        case .phaserMix:                      c.phaserEnabled = true
        case .tremoloDepth:                   c.tremoloEnabled = true
        case .delayMix, .delayFeedback:       c.delayEnabled = true
        case .reverbMix, .reverbSize:         c.reverbEnabled = true
        case .bitcrushMix:                    c.bitcrushEnabled = true
        case .stereoWidth:                    c.widenerEnabled = true
        }
    }
}
