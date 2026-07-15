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
// Lifecycle law (Council 2026-07-15, PLAN_H5_AU_LANE_ROUTING): instantiation
// is async and graph-attach pauses the engine, so both happen ONLY here —
// at assignment time, app-start restore, or between plays — never at a
// mid-song region onset. Every failure path leaves `voices[laneID]` nil and
// the fan-out falls back to the built-in slot voice: an assignment can sound
// wrong-but-built-in, never silent.
//
// Instance cap: third-party AUs are heavyweight (RAM/CPU); more than
// `maxInstances` assignments are honestly logged and skipped, not faked.

#if canImport(AVFoundation)
import AVFoundation
import Foundation

@MainActor
@Observable
public final class LaneAUInstrumentHost {

    /// Hard ceiling on simultaneously hosted per-lane instruments (matches the
    /// LaneVoiceRack capacity — more lanes than that overflow anyway).
    public static let maxInstances = 4

    @ObservationIgnored private weak var engine: AudioEngine?
    /// Live per-lane voices (laneID → hosted instrument). Read by the note
    /// fan-out; written only by `syncAssignments`.
    public private(set) var voices: [UUID: AUNoteVoice] = [:]
    /// The ref each live voice was built from (change detection on re-assign).
    @ObservationIgnored private var refs: [UUID: AUPluginRef] = [:]
    /// Lanes with an instantiation in flight (re-entrancy guard — async load).
    @ObservationIgnored private var inFlight: Set<UUID> = []

    public init() {}

    /// Wire to the live engine (once, at app start — mirrors AUv3Host.use).
    public func use(engine: AudioEngine) { self.engine = engine }

    /// The hosted voice for a lane, nil ⇒ caller uses the built-in slot voice.
    public func voice(laneID: UUID) -> AUNoteVoice? { voices[laneID] }

    /// Reconcile hosted instances with the document's lane assignments:
    /// removed/changed assignments detach their instance; new assignments
    /// instantiate asynchronously (capped). Idempotent — safe to call on every
    /// assignment edit and at app-start restore.
    public func syncAssignments(lanes: [TimelineLane]) {
        var wanted: [UUID: AUPluginRef] = [:]
        for lane in lanes where lane.kind == .midi && !lane.isBio {
            if let ref = lane.instrument, ref.isInstrument { wanted[lane.id] = ref }
        }
        // Tear down instances whose lane is gone or whose plugin changed.
        for (laneID, ref) in refs where wanted[laneID] != ref {
            release(laneID: laneID)
        }
        // Instantiate what's missing, oldest-first by lane order, capped.
        for lane in lanes {
            guard let ref = wanted[lane.id], refs[lane.id] == nil,
                  !inFlight.contains(lane.id) else { continue }
            guard refs.count + inFlight.count < Self.maxInstances else {
                log.audio("Lane AU cap (\(Self.maxInstances)) reached — '\(ref.name)' on '\(lane.name)' not hosted", level: .error)
                continue
            }
            instantiate(ref, laneID: lane.id)
        }
    }

    /// Silence every hosted lane instrument (transport stop paths).
    public func allNotesOff() {
        for v in voices.values { v.allNotesOff() }
    }

    // MARK: - Private

    private func instantiate(_ ref: AUPluginRef, laneID: UUID) {
        guard engine != nil else { return }
        inFlight.insert(laneID)
        let desc = AudioComponentDescription(
            componentType: ref.componentType,
            componentSubType: ref.componentSubType,
            componentManufacturer: ref.componentManufacturer,
            componentFlags: 0, componentFlagsMask: 0)
        Task { @MainActor [weak self] in
            defer { self?.inFlight.remove(laneID) }
            do {
                let unit = try await AVAudioUnit.instantiate(with: desc, options: [])
                guard let self, let engine = self.engine else { return }
                let voice = AUNoteVoice(avUnit: unit)
                var attached = false
                engine.withGraphPaused {
                    attached = engine.attachLaneInstrument(unit, laneMixer: voice.laneMixer)
                }
                guard attached else {
                    log.audio("Lane AU '\(ref.name)': attach failed (no format) — built-in voice keeps the lane", level: .error)
                    return
                }
                self.voices[laneID] = voice
                self.refs[laneID] = ref
                log.audio("Lane AU hosted: '\(ref.name)' → lane \(laneID)")
            } catch {
                log.audio("Lane AU '\(ref.name)' failed to load: \(error.localizedDescription) — built-in voice keeps the lane", level: .error)
            }
        }
    }

    private func release(laneID: UUID) {
        refs[laneID] = nil
        guard let voice = voices.removeValue(forKey: laneID) else { return }
        voice.allNotesOff()
        engine?.withGraphPaused {
            engine?.detachLaneInstrument(voice.avUnit, laneMixer: voice.laneMixer)
        }
    }
}
#endif
