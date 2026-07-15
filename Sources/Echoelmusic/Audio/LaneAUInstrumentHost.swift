// LaneAUInstrumentHost.swift
// Echoelmusic — Audio
//
// H5a (healing block): the per-LANE sibling of the app-global AUv3Host. Holds
// one hosted AUv3 INSTRUMENT instance per timeline lane that carries an
// `instrument` assignment (`TimelineLane.instrument: AUPluginRef` — persisted
// intent that, until H5, no engine code read). laneID-keyed, NOT slot-keyed:
// slots are priority ranks and shift when lanes are added/removed between
// plays; the lane id is the stable identity.
//
// H9a extends the same mechanics to the lane's INSERT EFFECTS
// (`TimelineLane.effects` — persisted since U3, engine-unread until now):
// the hosted chain is instrument → fx… → laneMixer → masterMixer, spliced at
// the laneMixer boundary H5 introduced. Lanes playing a BUILT-IN rack voice
// have no per-lane node boundary (pooled slots re-bind at play start, when the
// graph must not pause) — their `effects` stay honest data, deferred
// (PLAN_H9_AU_EFFECT_INSERTS_2026-07-15).
//
// Lifecycle law (Council 2026-07-15, PLAN_H5_AU_LANE_ROUTING): instantiation
// is async and graph-attach pauses the engine, so both happen ONLY here —
// at assignment time, app-start restore, or between plays — never at a
// mid-song region onset. Every failure path leaves `voices[laneID]` nil and
// the fan-out falls back to the built-in slot voice: an assignment can sound
// wrong-but-built-in, never silent. A failing EFFECT stage is skipped, not
// fatal — the chain still sounds.
//
// Instance cap: third-party AUs are heavyweight (RAM/CPU); more than
// `maxInstances` assignments (or `maxHostedUnits` total units, H9a) are
// honestly logged and skipped, not faked.

import Foundation

/// H9a: ONE per-lane hosting intent — the instrument plus its ordered insert
/// effects. Pure + Equatable so reconcile change-detection is a single
/// comparison: editing EITHER the instrument OR the effect list rebuilds the
/// lane's whole chain (a rebuild at assignment time is cheap; splicing a live
/// chain piecewise is where graphs get corrupted). Foundation-only — the
/// filter laws below are Linux-CI-tested.
public struct LaneAUAssignment: Equatable, Sendable {
    public var instrument: AUPluginRef
    public var effects: [AUPluginRef]

    /// Insert-stage ceiling per lane. Matches the global AUv3Host chain scale —
    /// more third-party stages per phone lane is a CPU debt, not a feature.
    public static let maxEffectsPerLane = 3

    public init(instrument: AUPluginRef, effects: [AUPluginRef] = []) {
        self.instrument = instrument
        self.effects = effects
    }

    /// Hosted units this assignment occupies (instrument + effect stages) —
    /// the currency of the shared `maxHostedUnits` budget.
    public var unitCount: Int { 1 + effects.count }

    /// The pure reconcile source: which lanes want a hosted chain. Laws
    /// (each pinned in LaneAUAssignmentTests):
    /// - MIDI, non-bio lanes only; the roll lane is EXCLUDED — the app-global
    ///   AUv3Host owns the primary channel (hosting it here too would run the
    ///   same plugin twice).
    /// - `lane.instrument` must be an instrument ref; an effect ref stored
    ///   there is ignored (pre-H9 law, unchanged).
    /// - `lane.effects` keeps only true EFFECT refs (an instrument in the
    ///   insert list would swallow the signal), order preserved, capped at
    ///   `maxEffectsPerLane` (first stages win; stages beyond the cap are
    ///   silently dropped here — the host's wired-vs-wanted install log is
    ///   where the honest count surfaces).
    /// - A lane with effects but NO hosted instrument is NOT returned: its
    ///   built-in rack voice has no per-lane node boundary today — honest
    ///   defer, not a half-wired chain.
    public static func wanted(lanes: [TimelineLane], rollLane: UUID?) -> [UUID: LaneAUAssignment] {
        var out: [UUID: LaneAUAssignment] = [:]
        for lane in lanes where lane.kind == .midi && !lane.isBio && lane.id != rollLane {
            guard let inst = lane.instrument, inst.isInstrument else { continue }
            let fx = lane.effects.filter { !$0.isInstrument }.prefix(maxEffectsPerLane)
            out[lane.id] = LaneAUAssignment(instrument: inst, effects: Array(fx))
        }
        return out
    }
}

#if canImport(AVFoundation)
import AVFoundation

@MainActor
@Observable
public final class LaneAUInstrumentHost {

    /// Hard ceiling on simultaneously hosted per-lane instruments (matches the
    /// LaneVoiceRack capacity — more lanes than that overflow anyway).
    public static let maxInstances = 4

    /// H9a: shared budget for ALL hosted units (instruments + effect stages)
    /// across lanes. Instrument-only assignments behave exactly as before
    /// (4 lanes = 4 units, under budget); effect chains draw from the rest.
    public static let maxHostedUnits = 8

    @ObservationIgnored private weak var engine: AudioEngine?
    /// Live per-lane voices (laneID → hosted instrument chain). Read by the
    /// note fan-out; written only via `syncAssignments`' lifecycle (async
    /// completion of instantiate, and release).
    public private(set) var voices: [UUID: AUNoteVoice] = [:]
    /// The assignment each live voice was built from (change detection —
    /// instrument OR effects edit ⇒ rebuild).
    @ObservationIgnored private var refs: [UUID: LaneAUAssignment] = [:]
    /// The PENDING assignment per lane with an instantiation in flight.
    /// Carrying the assignment (not a bare Set) is the stale-guard: an
    /// assignment cleared/changed while a load is suspended at `await
    /// instantiate` clears/replaces this entry, and the resumed Task checks
    /// its assignment is STILL the pending one before attaching — a superseded
    /// load drops its units un-attached (review HIGH: the Set version
    /// installed the removed plugin).
    @ObservationIgnored private var inFlight: [UUID: LaneAUAssignment] = [:]
    /// Assignments that failed to load/attach, per lane — retried only when
    /// the lane's assignment CHANGES (review MEDIUM: sync runs on every
    /// persist, so a fast-failing plugin would otherwise re-spawn an async
    /// instantiate per fader-drag increment — load churn + log spam).
    @ObservationIgnored private var failed: [UUID: LaneAUAssignment] = [:]
    /// Lanes whose over-cap skip was already logged (log once, not per persist).
    @ObservationIgnored private var capLogged: Set<UUID> = []

    public init() {}

    /// Wire to the live engine (once, at app start — mirrors AUv3Host.use).
    public func use(engine: AudioEngine) { self.engine = engine }

    /// The hosted voice for a lane, nil ⇒ caller uses the built-in slot voice.
    public func voice(laneID: UUID) -> AUNoteVoice? { voices[laneID] }

    /// H5b slot→lane binding, pushed by the region player at region load/prime
    /// (from the PLAYBACK SNAPSHOT — the store's lane order can drift mid-play).
    /// nil clears a slot (region gap / lane overflow).
    @ObservationIgnored private var slotBindings: [Int: UUID] = [:]

    public func bindSlot(_ slot: Int, laneID: UUID?) {
        slotBindings[slot] = laneID
    }

    /// The hosted voice a SLOT currently drives (via its bound lane), nil ⇒
    /// the built-in rack voice keeps the slot. Used by the app's note sink.
    public func voice(slot: Int) -> AUNoteVoice? {
        guard let laneID = slotBindings[slot] else { return nil }
        return voices[laneID]
    }

    /// Reconcile hosted chains with the document's lane assignments:
    /// removed/changed assignments detach their chain (and invalidate any
    /// in-flight load); new assignments instantiate asynchronously (capped).
    /// The roll lane is EXCLUDED (review MEDIUM): it plays through the
    /// app-global AUv3Host — hosting it here too would instantiate the same
    /// plugin twice (RAM/CPU, a wasted cap slot, double-sounding risk).
    /// Idempotent — safe on every assignment edit and at app-start restore.
    public func syncAssignments(lanes: [TimelineLane], rollLane: UUID?) {
        let wanted = LaneAUAssignment.wanted(lanes: lanes, rollLane: rollLane)
        // Tear down live chains whose lane is gone or whose assignment changed,
        // and invalidate in-flight loads the same way (the resumed Task checks).
        for (laneID, a) in refs where wanted[laneID] != a {
            release(laneID: laneID)
        }
        for (laneID, a) in inFlight where wanted[laneID] != a {
            inFlight[laneID] = nil
        }
        // A CHANGED assignment gets a fresh chance; an unchanged failed one
        // stays parked until the user picks a different plugin/chain.
        for (laneID, a) in failed where wanted[laneID] != a {
            failed[laneID] = nil
        }
        capLogged.formIntersection(wanted.keys)
        // Instantiate what's missing, oldest-first by lane order, capped.
        for lane in lanes {
            guard let a = wanted[lane.id], refs[lane.id] == nil,
                  inFlight[lane.id] != a, failed[lane.id] != a else { continue }
            guard refs.count + inFlight.count < Self.maxInstances,
                  hostedUnitCount + a.unitCount <= Self.maxHostedUnits else {
                if capLogged.insert(lane.id).inserted {
                    log.audio("Lane AU budget (\(Self.maxInstances) lanes / \(Self.maxHostedUnits) units) reached — '\(a.instrument.name)' on '\(lane.name)' not hosted", level: .error)
                }
                continue
            }
            instantiate(a, laneID: lane.id)
        }
    }

    /// Silence every hosted lane instrument (transport stop paths).
    public func allNotesOff() {
        for v in voices.values { v.allNotesOff() }
    }

    // MARK: - Private

    /// Live + pending unit load against the shared `maxHostedUnits` budget.
    private var hostedUnitCount: Int {
        refs.values.reduce(0) { $0 + $1.unitCount }
            + inFlight.values.reduce(0) { $0 + $1.unitCount }
    }

    private static func componentDescription(for ref: AUPluginRef) -> AudioComponentDescription {
        AudioComponentDescription(
            componentType: ref.componentType,
            componentSubType: ref.componentSubType,
            componentManufacturer: ref.componentManufacturer,
            componentFlags: 0, componentFlagsMask: 0)
    }

    private func instantiate(_ assignment: LaneAUAssignment, laneID: UUID) {
        // Deliberately NOT parked in `failed` (review LOW considered): this
        // guard is reachable only during teardown (use(engine:) precedes the
        // first sync at app start) — parking here would wedge hosting if a
        // future caller ever synced before wiring the engine.
        guard engine != nil else {
            log.audio("Lane AU '\(assignment.instrument.name)': no engine wired — not hosted", level: .error)
            return
        }
        inFlight[laneID] = assignment
        Task { @MainActor [weak self] in
            // Clear only OUR pending entry — a newer load for the same lane may
            // have replaced it while we were suspended.
            defer { if self?.inFlight[laneID] == assignment { self?.inFlight[laneID] = nil } }
            do {
                let unit = try await AVAudioUnit.instantiate(
                    with: Self.componentDescription(for: assignment.instrument), options: [])
                // H9a: effect stages load one by one; a failing stage is
                // SKIPPED (the chain still sounds — never silence), logged.
                var effectUnits: [AVAudioUnit] = []
                for ref in assignment.effects {
                    do {
                        effectUnits.append(try await AVAudioUnit.instantiate(
                            with: Self.componentDescription(for: ref), options: []))
                    } catch {
                        log.audio("Lane FX '\(ref.name)' failed to load: \(error.localizedDescription) — stage skipped", level: .error)
                    }
                }
                // Stale-guard (review HIGH), AFTER every await: the assignment
                // may have been cleared or changed while we were suspended — a
                // superseded load drops its units un-attached (ARC closes the
                // extension connections; no leak).
                guard let self, self.inFlight[laneID] == assignment,
                      let engine = self.engine else { return }
                // Pre-flight (review HIGH): keep only effects that ACCEPT the
                // chain format — connect() raises on refusal, it doesn't throw.
                // The voice carries the WIRED set, so release detaches exactly
                // what attach connected.
                let wiredFX = engine.effectsAcceptingChainFormat(effectUnits)
                // H9b: tempo/transport context on the whole chain (instrument
                // AND effect stages) — tempo-synced plugins lock to the song.
                AUHostContext.install(on: unit.auAudioUnit)
                for fx in wiredFX { AUHostContext.install(on: fx.auAudioUnit) }
                let voice = AUNoteVoice(avUnit: unit, effectUnits: wiredFX)
                var attached = false
                engine.withGraphPaused {
                    attached = engine.attachLaneInstrument(unit, effects: wiredFX,
                                                           laneMixer: voice.laneMixer)
                }
                guard attached else {
                    self.failed[laneID] = assignment   // park — retried only on a CHANGED assignment
                    log.audio("Lane AU '\(assignment.instrument.name)': attach failed (no format) — built-in voice keeps the lane", level: .error)
                    return
                }
                self.voices[laneID] = voice
                self.refs[laneID] = assignment
                self.capLogged.remove(laneID)   // a fresh over-budget episode logs again (review LOW)
                // Honest chain report (review MEDIUM): wired-vs-wanted stage
                // count, so a skipped stage is visible at every install AND at
                // app-start restore (which re-runs this whole path).
                let fxNote = assignment.effects.isEmpty ? ""
                    : " + \(wiredFX.count)/\(assignment.effects.count) FX"
                log.audio("Lane AU hosted: '\(assignment.instrument.name)'\(fxNote) → lane \(laneID)")
            } catch {
                // Park the failed assignment only if this load is still the
                // pending one (a superseded load must not veto its successor).
                if let self, self.inFlight[laneID] == assignment { self.failed[laneID] = assignment }
                log.audio("Lane AU '\(assignment.instrument.name)' failed to load: \(error.localizedDescription) — built-in voice keeps the lane", level: .error)
            }
        }
    }

    private func release(laneID: UUID) {
        refs[laneID] = nil
        guard let voice = voices.removeValue(forKey: laneID) else { return }
        voice.allNotesOff()
        engine?.withGraphPaused {
            engine?.detachLaneInstrument(voice.avUnit, effects: voice.effectUnits,
                                         laneMixer: voice.laneMixer)
        }
    }
}
#endif
