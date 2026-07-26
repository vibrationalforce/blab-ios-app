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

    /// Per-route fade state (`FXRouteFade` — pure, tested). Keyed by route id so
    /// reordering routes, or editing an unrelated one, does not disturb a fade in
    /// progress; the fade invalidates its own held offset when the route it belongs to
    /// is retargeted or retuned.
    @ObservationIgnored private var routeFades: [UUID: FXRouteFade] = [:]
    /// MONOTONIC, deliberately. `CFAbsoluteTimeGetCurrent` is wall clock: an NTP or
    /// timezone step backwards yields a negative delta, which the envelope reads as a
    /// bad clock — and the app already carries the wall clock for LFO phase, where a
    /// jump is harmless. A difference is not. `systemUptime` cannot go backwards.
    @ObservationIgnored private var lastTickUptime = ProcessInfo.processInfo.systemUptime

    public init() {}

    /// Bind to the chain a voice owns + the bio bus. Safe to call again to rebind.
    public func attach(chain: EchoelFXChain, bus: EngineBus) {
        self.chain = chain
        self.bus = bus
        // A rebind is a different chain: carrying half-finished fades onto it would
        // apply offsets to parameters this driver never captured a base for.
        routeFades.removeAll()
        lastTickUptime = ProcessInfo.processInfo.systemUptime
        reconcileBases()
    }

    public func start() {
        guard !isRunning, chain != nil else { return }
        isRunning = true
        // Anchor the clock here, or the first tick's dt would be the whole idle gap
        // since the last session and the envelope would snap instead of fading in.
        lastTickUptime = ProcessInfo.processInfo.systemUptime
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
        // Drop the fades too, so a later `start()` eases in from silence rather than
        // resuming a half-faded route. (Today the app never calls `stop()` — the driver
        // runs from launch to termination — so this is the correctness of the API, not
        // a path the shipping app exercises.)
        routeFades.removeAll()
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
        pruneRouteFades()   // before the chain guard: route edits land whether or not one is bound
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
        // Advance the fade clock BEFORE any early return, or a tick that bails would
        // hand the next one an inflated gap.
        let uptime = ProcessInfo.processInfo.systemUptime
        let dt = Float(uptime - lastTickUptime)
        lastTickUptime = uptime
        guard let c = chain else { return }
        // Gate on `usableBio()` — the SAME per-source window the mod-brain uses
        // (ModulationEngine.tick). The fixed-5 s `freshBio()` here meant FX
        // bio-modulation stopped after 5 s for a latent Watch/HealthKit source
        // (90 s window) while the main modulation kept steering — inconsistent
        // sound shaping off the same body. Now every sound-shaping bio gate is
        // the one authority: a frame usable to the engine is usable to the FX,
        // and a frame the engine drops (`nil`) disengages the FX bio routes too, fading
        // them back to the base value rather than cutting them.
        let frame = bus?.usableBio()
        let now = Float(CFAbsoluteTimeGetCurrent() - startTime)
        let active = activeTargets
        for target in active {
            guard let base = baseValues[target] else { continue }
            var sum: Float = 0
            var contributed = false
            for route in routes where route.enabled && route.target == target {
                let signal: Float?
                switch route.carrier {
                case .bio(let source):
                    // A missing frame, or a frame that carries nothing ON THIS CHANNEL,
                    // is an absence: HealthKit publishes no coherence, and coherence is
                    // what the FX view's "add route" button always creates. A BIPOLAR
                    // route would otherwise read signal 0 and apply a permanent
                    // full-negative offset (see `ModSource.isMeasured`, which also
                    // documents the one unipolar channel this changes: breath).
                    if let frame, source.isMeasured(in: frame) {
                        signal = source.normalizedValue(from: frame)
                    } else {
                        signal = nil
                    }
                case .lfo:
                    let phase = (now * route.lfoRateHz).truncatingRemainder(dividingBy: 1)
                    signal = FXModulation.lfoUnipolar(phase: phase)
                }

                // Hold the last real offset and fade it, rather than snapping to zero
                // the tick a sensor drops out. The camera's ~4 s dropout grace is the
                // live case: it republishes `breathRate: 0` while still holding a
                // continuous `breathPhase`, so an ungated boundary stepped a bipolar
                // breath→cutoff route by up to ~4.5 kHz in one 33 ms tick.
                var fade = routeFades[route.id] ?? FXRouteFade()
                fade.step(route: route, signal: signal, dt: dt)
                routeFades[route.id] = fade

                sum += fade.contribution
                // Still contributing while fading OUT, so the stage stays enabled for the
                // whole tail instead of cutting it.
                if fade.isEngaged { contributed = true }
            }
            // The write ALWAYS runs, deliberately: `sum` reaches 0 once every route has
            // faded out (the fade snaps to zero at its epsilon rather than decaying
            // asymptotically), so a channel that stops being measured returns its
            // parameter to base instead of freezing at the last modulated value.
            write(target, FXModulation.combine(base: base, target: target, offset: sum), to: c)
            // Enabling the stage does NOT: switching a filter or reverb on for a target
            // nothing is modulating changes the sound off nothing — the same complaint
            // this gate exists to answer, one level up. With the default coherence route
            // on a source that reports no coherence, that would have run every tick for
            // the whole session. (There is no matching disable, so a stage already on
            // stays on and no click is introduced.)
            if contributed { enableStage(for: target, on: c) }
        }
        // Publish the live snapshot at ~10 Hz (throttled) for the visibility leaf.
        // Only write on a real change so an idle/stable state fires no observation.
        tickCount &+= 1
        if FXModulation.shouldPublish(tick: tickCount, everyN: Self.publishEveryN) {
            let next = FXModulation.contributions(routes: routes, frame: frame, now: now)
            if next != liveContributions { liveContributions = next }
        }
    }

    /// Forget fade state for routes that no longer exist or were disabled, so the
    /// dictionary cannot grow across a long session of route edits — and so a route that
    /// is disabled and re-enabled eases back in rather than reappearing at its old
    /// engagement.
    ///
    /// Called from `reconcileBases` (the `routes` `didSet`), NOT from the tick: the set
    /// of live routes can only change when `routes` changes, and doing it per tick built
    /// an array, a map, a `Set` and a fresh dictionary 30× a second on the main actor —
    /// pure garbage for a per-edit fact, on the actor this app has a documented
    /// starvation law about.
    private func pruneRouteFades() {
        guard !routeFades.isEmpty else { return }
        let live = Set(routes.filter { $0.enabled }.map(\.id))
        routeFades = routeFades.filter { live.contains($0.key) }
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
