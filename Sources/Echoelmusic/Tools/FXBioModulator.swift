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

    /// WHICH of the four things the section heading over `liveContributions` may say —
    /// published here rather than derived in the view, and #641's review is the reason twice
    /// over (once for the gate it is read through, once for the state it was missing).
    ///
    /// ⛔ THE FIRST CUT DERIVED IT IN THE VIEW, from `liveContributions.contains(where:
    /// \.synthetic)`, AND THAT RE-CREATED THE COLLISION THE SLICE EXISTS TO REMOVE — one
    /// section away. `synthetic` on a contribution is computed from `bus?.usableBio()`, i.e.
    /// behind a FRESHNESS gate; the always-on heading three rows further down reads
    /// `bus.latestBio` RAW, which is never cleared. Past `.fallback`'s 5 s window every
    /// contribution goes non-contributing, so `synthetic` collapses to false and the sheet
    /// renders "Live — body → sound" directly above "Always on — simulated demo → timbre",
    /// from the SAME frame, permanently. Two gates, one screen, opposite claims.
    ///
    /// ⭐ SO IT ASKS THE RAW FRAME, matching the always-on half, and the two headings can no
    /// longer disagree. The two REGIMES stay as they are — `TwoFreshnessRegimesAreDeliberate
    /// Tests` pins them and unifying them is an audible change needing a hearing test — this
    /// only stops the two HEADINGS from being derived through different ones.
    ///
    /// ⛔ AND THE SECOND CUT WAS A BOOL, WHICH COULD NOT SAY THE THIRD THING. An LFO carrier is
    /// a real oscillator and is deliberately never marked synthetic, so a section of only LFO
    /// routes fell through the demo test and printed "Live — body → sound" over rows in which
    /// no body is involved at all — the product's core claim, over an oscillator. #641's own
    /// review registered that and left it; a `Bool` has no room for it. `LiveModOrigin` is the
    /// four states the section can actually be in, and `FXModulation.liveOrigin(routes:
    /// sourceIsSynthetic:)` owns the decision as a pure function, so it is testable END TO END
    /// instead of by scanning this file for a string.
    ///
    /// Written only inside the existing ~10 Hz throttled publish branch, and only on change, so
    /// it REPLACES `sourceIsSynthetic` (#642) rather than adding anything: no new tracked
    /// property, no new cadence, no new source. ⛔ The first draft said "adds a tracked property",
    /// carried over from the #641 doc it was edited out of — true when the Bool was new, false
    /// for the enum that took its place.
    public private(set) var liveOrigin: LiveModOrigin = .noRoutes
    @ObservationIgnored private var tickCount = 0
    /// 30 Hz tick / 3 ≈ 10 Hz UI refresh.
    @ObservationIgnored private static let publishEveryN = 3

    /// ⭐ #386 — EVERY CHAIN THIS DRIVER MOVES, not just the composer's.
    ///
    /// THE DEFECT. `attach(chain: polyVoice.fxChain, bus:)` bound ONE chain, so the body
    /// moved the generated take's filter/delay/reverb while the notes the performer played
    /// on the Field stayed exactly where they were. Two sounds, one body, one of them
    /// deaf to it — and nothing on screen said which. It is the same split reach #318
    /// fixed in the FX view-model, one level down: there the USER's hand reached one
    /// chain, here the USER's BODY does.
    ///
    /// ⛔ WHY THE BASE IS PER CHAIN AND NOT ONE VALUE. The driver's whole ownership model
    /// is "capture the user's intended value, drive around it, restore it". Chains do NOT
    /// necessarily hold the same value for a target: they converge on anything written
    /// through the FX surface (#318) or a character/preset apply, but nothing forces them
    /// equal — and `leadSynth.fxChain` is deliberately outside this inventory. Capturing
    /// one base and writing it to all of them would silently overwrite one chain's setting
    /// with another's the first time a route engages, and again on restore. So the base is
    /// an array, index-aligned with `allChains`; the bio OFFSET is shared (it comes from
    /// the body, not from a chain) and each chain rides it around its own value.
    ///
    /// ⚠️ THE INVENTORY IS DELIBERATELY THE SAME TWO AS `characterFXChains`, and the two
    /// omissions are the same: `leadSynth.fxChain` is live but never configured (adding it
    /// changes what the app sounds like and belongs to the founder's ear — #243), and
    /// `bioVoice.fxChain` is dead (nothing calls `BioReactiveSynthVoice.setFXEnabled`).
    /// If that list grows, it grows in ONE place at the call site, not here.
    @ObservationIgnored private var allChains: [EchoelFXChain] = []
    @ObservationIgnored private weak var bus: EngineBus?
    /// The user's intended value per modulated target, captured when the target's
    /// first route is enabled and restored when its last route goes away.
    /// ONE ENTRY PER CHAIN, index-aligned with `allChains` — see the `allChains` note.
    @ObservationIgnored private var baseValues: [FXModTarget: [Float]] = [:]
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

    /// Bind to the chains the sounding voices own + the bio bus. Safe to call again to
    /// rebind. `mirrors` defaults to empty so existing two-argument calls keep compiling
    /// and keep their exact behaviour.
    public func attach(chain: EchoelFXChain, mirrors: [EchoelFXChain] = [], bus: EngineBus) {
        // A rebind points at DIFFERENT objects, so the bases captured for the old ones
        // must go back to the old ones — not be written into the new ones, which is what
        // simply reconciling would do (the arrays would also be the wrong length). Restore
        // first, then forget.
        for (target, bases) in baseValues {
            for (i, c) in allChains.enumerated() where i < bases.count { write(target, bases[i], to: c) }
        }
        baseValues.removeAll()
        self.allChains = [chain] + mirrors
        self.bus = bus
        // A rebind is a different chain: carrying half-finished fades onto it would
        // apply offsets to parameters this driver never captured a base for.
        routeFades.removeAll()
        lastTickUptime = ProcessInfo.processInfo.systemUptime
        reconcileBases()
    }

    public func start() {
        guard !isRunning, !allChains.isEmpty else { return }
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
        // …and the heading falls back to the plain section name. `.noRoutes` is the honest
        // stopped state precisely BECAUSE it claims nothing — read its doc as "no claim", not
        // as "the user has no routes", which is false here: the routes survive a `stop()`.
        // ⛔ THE FIRST DRAFT OF THIS COMMENT NAMED THE WRONG STRING. It justified itself with
        // "with no display below it", pointing at `.noRoutes`'s empty-state line ("No routes
        // yet, so no effect parameter is moving."). That is the one string that CANNOT appear
        // in the stopped state — `BioModLiveView` renders the other branch, "Start a session to
        // watch the body move these parameters." The conclusion survives, the evidence did not.
        liveOrigin = .noRoutes
        // Drop the fades too, so a later `start()` eases in from silence rather than
        // resuming a half-faded route. (Today the app never calls `stop()` — the driver
        // runs from launch to termination — so this is the correctness of the API, not
        // a path the shipping app exercises.)
        routeFades.removeAll()
        // Restore every captured base so EVERY chain returns to the user's settings (#386
        // — restoring only the composer's would leave the Field's chain parked wherever
        // the last tick left it).
        for (target, bases) in baseValues {
            for (i, c) in allChains.enumerated() where i < bases.count { write(target, bases[i], to: c) }
        }
    }

    // MARK: - Active targets / base capture

    /// Targets that currently have at least one enabled route.
    ///
    /// ⭐ #388 — CACHED, NOT RECOMPUTED PER TICK. This was a computed property, read from
    /// `tick()` (every 33 ms) and from `reconcileBases()`, and each read built an array
    /// (`filter`), a second array (`map`) and a `Set` on the main actor. That is the
    /// identical construct the note on `pruneRouteFades` below forbids, for the identical
    /// reason, in the identical file: the actor this app has a documented starvation law
    /// about (the 10.76.48 menu freeze) does not want per-tick garbage for a fact that
    /// changes per EDIT.
    ///
    /// ⛔ AND IT IS A PER-EDIT FACT, exactly like the fade pruning. The set can only change
    /// when `routes` changes, `routes` is the only input, and its `didSet` is the single
    /// writer path — `FXModRoute` is a struct, so even `routes[i].enabled = false` goes
    /// through it (the FX view edits routes exclusively through `$modulator.routes`
    /// bindings, `append` and `removeAll`; nothing decodes or restores them).
    ///
    /// ⚠️ WHAT THE CACHE NOW RESTS ON, said plainly because the blast radius grew. Both this
    /// and `routeFades` depend on that `didSet` firing. It already did before #388, so this
    /// adds no new risk — but a missed `didSet` used to leak a few fade entries and now
    /// makes the 30 Hz tick drive the WRONG target set. The one way to miss it is an
    /// initializer: property observers do not fire for the initializing assignment. Today
    /// `init()` takes no routes, so cache and routes start consistent. Anything that adds
    /// an `init(routes:)` or a decode path must call `refreshActiveTargets()` itself, or
    /// every bio-FX route goes silently dead — not glitchy, dead.
    @ObservationIgnored private var activeTargets: Set<FXModTarget> = []

    /// The one writer of `activeTargets`. Kept separate from `reconcileBases` so the
    /// ordering requirement below is visible at the call site rather than buried.
    private func refreshActiveTargets() {
        activeTargets = Set(routes.filter { $0.enabled }.map { $0.target })
    }

    /// Capture a base for every newly-active target; restore + drop bases for targets
    /// that are no longer modulated. Called on attach and whenever routes change.
    private func reconcileBases() {
        // ⚠️ BOTH OF THESE STAY ABOVE THE CHAIN GUARD, and the honest reason is robustness,
        // NOT a live bug — the first version of this comment claimed the latter and a
        // reviewer showed it was unreachable. For the record, so nobody re-derives it:
        // refreshing BELOW the guard could only strand a stale cache while `allChains` is
        // empty, and in that state `tick()` has already returned at its own chain guard;
        // the only exit from it is `attach`, which reconciles unconditionally. So the
        // placement buys nothing today. It is here because a route edit is a fact about
        // `routes` and not about whether a chain happens to be bound — the same
        // non-live reason `pruneRouteFades()` sits here — and because it stays correct if
        // a `detach()` ever empties `allChains` again. This repo's own rule applies: a
        // rationale that cannot be checked is worse than none, because the next session
        // cannot refute it.
        refreshActiveTargets()
        pruneRouteFades()
        guard !allChains.isEmpty else { return }
        let active = activeTargets
        // Capture bases for new targets — one per chain, each its own user value (#386).
        for t in active where baseValues[t] == nil {
            baseValues[t] = allChains.map { read(t, from: $0) }
        }
        // ⚠️ THE WHOLE ALIGNMENT INVARIANT RESTS ON ONE LINE: `baseValues.removeAll()` sitting
        // BEFORE the `allChains` assignment in `attach`. Nothing else can change either
        // collection's length. The `where i < bases.count` clauses that guard the four write
        // loops therefore never trip today — and if a future edit made them trip, they would
        // SKIP a chain silently: never driven, never restored, which is the exact defect #386
        // exists to close, wearing a bounds check as a disguise. `assert` (debug-only, never a
        // release crash) is the loudest form available here; note honestly that no test exercises
        // it, because nothing constructs this driver outside the app.
        assert(baseValues.values.allSatisfy { $0.count == allChains.count },
               "FXBioModulator base/chain length drift — a chain would be silently skipped")
        // Restore + drop targets no longer modulated.
        for t in baseValues.keys where !active.contains(t) {
            if let bases = baseValues[t] {
                for (i, c) in allChains.enumerated() where i < bases.count { write(t, bases[i], to: c) }
            }
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
        guard !allChains.isEmpty else { return }
        // Gate on `usableBio()` — the SAME per-source window the mod-brain uses
        // (ModulationEngine.tick). The fixed-5 s `freshBio()` here meant FX
        // bio-modulation stopped after 5 s for a latent Watch/HealthKit source
        // (90 s window) while the main modulation kept steering — inconsistent
        // sound shaping off the same body. That half is unchanged and correct: this
        // driver, `ModulationEngine.tick` and the composer all ask the same window.
        //
        // ⛔ WHAT FOLLOWED WAS FALSE, AND IT WAS THE LOAD-BEARING SENTENCE (#499). It read:
        // "Now every sound-shaping bio gate is the one authority: a frame usable to the
        // engine is usable to the FX, and a frame the engine drops (`nil`) disengages the FX
        // bio routes too." THE ENGINE DROPS NOTHING. Measured: the two producers that shape
        // the instrument's own TIMBRE — `BioReactiveSynthVoice.applyLatestIfFresh` and
        // `PolySynthVoice.applyLatestIfFresh` — read `bus.latestBio` RAW and dedupe on
        // `frame.timestamp`; neither file contains the string `usableBio` at all. So there
        // are TWO freshness regimes on ONE bus: three GATED readers (this driver, the
        // mod-brain, the composer) and two UNGATED ones (the timbre). The sentence claimed
        // the opposite of what the code does, in the comment that justifies this line.
        //
        // ⭐ BOTH REGIMES ARE RIGHT, AND THAT IS WHY #499 CORRECTS THE PROSE RATHER THAN THE
        // CODE. An FX route is an ADDITIVE offset the user explicitly asked for; holding one
        // off a body that stopped arriving is a stale claim, so it fades to base. Timbre has
        // no release path at all — the producers dedupe, so a frozen source is a no-op that
        // PARKS the timbre at the last body instead of zeroing it, and zeroing it would claim
        // the engine dropped the channel when it did not. That argument is written out at
        // `AlwaysOnBioChannel.reading(in:now:)`, and #503 put the parking on screen ("held").
        //
        // ⚠️ SO THE VISIBLE RESIDUE IS REAL AND IS NOT FIXED HERE: on a frozen camera source
        // (6 s window) the FX offsets release while the timbre stays parked, and only the
        // timbre half says so on screen. Unifying either direction is an audible change and
        // needs a hearing test, not a consistency edit — which is exactly what the false
        // sentence above invited. `TwoFreshnessRegimesAreDeliberateTests` pins both halves so
        // a later "make them consistent" cleanup goes red instead of silently picking one.
        let frame = bus?.usableBio()
        let now = Float(CFAbsoluteTimeGetCurrent() - startTime)
        let active = activeTargets
        for target in active {
            guard let bases = baseValues[target] else { continue }
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
            // #386: the SAME offset reaches every chain, each around ITS OWN base. The
            // offset is a property of the body; the base is a property of the chain.
            for (i, c) in allChains.enumerated() where i < bases.count {
                write(target, FXModulation.combine(base: bases[i], target: target, offset: sum), to: c)
                // Enabling the stage does NOT: switching a filter or reverb on for a target
                // nothing is modulating changes the sound off nothing — the same complaint
                // this gate exists to answer, one level up. With the default coherence route
                // on a source that reports no coherence, that would have run every tick for
                // the whole session.
                //
                // ⛔ THIS IS A LATCH AND THE RESTORE PATHS DO NOT UNDO IT — the old parenthetical
                // here ("a stage already on stays on and no click is introduced") reassured about
                // the harmless half and stayed silent on the half that matters. The restores
                // return the PARAMETER to its base; they never clear the flag. So the first tick
                // on which a route contributes arms e.g. `reverbEnabled` on that chain for the
                // rest of the session, and removing the route leaves it armed at the base mix.
                // That was tolerable while only the composer's chain was reachable; since #386 it
                // also happens to the Field, where a non-zero base mix on a stage the user had
                // switched OFF now stays audible after the route is gone. Named, not fixed: an
                // automatic disable needs a "was it the driver that turned this on" record, and
                // getting that wrong silences a stage the user armed by hand.
                if contributed { enableStage(for: target, on: c) }
            }
        }
        // Publish the live snapshot at ~10 Hz (throttled) for the visibility leaf.
        // Only write on a real change so an idle/stable state fires no observation.
        tickCount &+= 1
        if FXModulation.shouldPublish(tick: tickCount, everyN: Self.publishEveryN) {
            let next = FXModulation.contributions(routes: routes, frame: frame, now: now)
            if next != liveContributions { liveContributions = next }
            // RAW, not `frame` — see `liveOrigin`'s doc: `frame` above is `bus?.usableBio()`,
            // and deriving the heading through the freshness gate is exactly what made the two
            // headings contradict each other. The route arithmetic (enabled-only, bio-or-not)
            // lives in the pure function, which is what the guard exercises end to end.
            let origin = FXModulation.liveOrigin(
                routes: routes,
                sourceIsSynthetic: bus?.latestBio?.source.isSynthetic ?? false)
            if origin != liveOrigin { liveOrigin = origin }
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
    ///
    /// ⛔ THIS NOTE WAS TRUE AND ITS NEIGHBOUR IGNORED IT. `activeTargets` sat a few
    /// declarations above doing the identical thing — filter, map, `Set`, every tick —
    /// until #388. A rule written next to the one place that already obeys it does not
    /// find the place that does not; when this shape appears again, grep the file for
    /// `Set(` and `filter` inside anything the 33 ms loop reaches, don't trust the note.
    private func pruneRouteFades() {
        guard !routeFades.isEmpty else { return }
        let live = Set(routes.filter { $0.enabled }.map(\.id))
        routeFades = routeFades.filter { live.contains($0.key) }
    }

    // MARK: - Chain parameter mapping

    private func read(_ t: FXModTarget, from c: EchoelFXChain) -> Float {
        switch t {
        // #138 — THE BASE CAPTURE, and the reason the target/glide split exists at all.
        // Reading the audio mirror here would let the driver latch a value caught
        // mid-glide and then modulate around that random intermediate forever.
        case .filterCutoff:    return c.filterCutoff
        case .filterResonance: return c.filterResonance
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
        // #138: the 30 Hz driver writes the TARGET. This is the writer whose staircase
        // (a ~10 Hz bio carrier resampled at 30 Hz) the glide exists to smooth.
        case .filterCutoff:    c.filterCutoff = v
        case .filterResonance: c.filterResonance = v
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
