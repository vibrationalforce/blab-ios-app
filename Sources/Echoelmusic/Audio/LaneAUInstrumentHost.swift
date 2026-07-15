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
    /// fan-out; written only via `syncAssignments`' lifecycle (async completion
    /// of instantiate, and release).
    public private(set) var voices: [UUID: AUNoteVoice] = [:]
    /// The ref each live voice was built from (change detection on re-assign).
    @ObservationIgnored private var refs: [UUID: AUPluginRef] = [:]
    /// The PENDING ref per lane with an instantiation in flight. Carrying the
    /// ref (not a bare Set) is the stale-guard: an assignment cleared/changed
    /// while a load is suspended at `await instantiate` clears/replaces this
    /// entry, and the resumed Task checks its ref is STILL the pending one
    /// before attaching — a superseded load drops its unit un-attached
    /// (review HIGH: the Set version installed the removed plugin).
    @ObservationIgnored private var inFlight: [UUID: AUPluginRef] = [:]

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

    /// Reconcile hosted instances with the document's lane assignments:
    /// removed/changed assignments detach their instance (and invalidate any
    /// in-flight load); new assignments instantiate asynchronously (capped).
    /// `rollLane` is EXCLUDED (review MEDIUM): the primary roll lane plays
    /// through the app-global AUv3Host — hosting it here too would instantiate
    /// the same plugin twice (RAM/CPU, a wasted cap slot, double-sounding risk).
    /// Idempotent — safe on every assignment edit and at app-start restore.
    public func syncAssignments(lanes: [TimelineLane], rollLane: UUID?) {
        var wanted: [UUID: AUPluginRef] = [:]
        for lane in lanes where lane.kind == .midi && !lane.isBio && lane.id != rollLane {
            if let ref = lane.instrument, ref.isInstrument { wanted[lane.id] = ref }
        }
        // Tear down live instances whose lane is gone or whose plugin changed,
        // and invalidate in-flight loads the same way (the resumed Task checks).
        for (laneID, ref) in refs where wanted[laneID] != ref {
            release(laneID: laneID)
        }
        for (laneID, ref) in inFlight where wanted[laneID] != ref {
            inFlight[laneID] = nil
        }
        // Instantiate what's missing, oldest-first by lane order, capped.
        for lane in lanes {
            guard let ref = wanted[lane.id], refs[lane.id] == nil,
                  inFlight[lane.id] != ref else { continue }
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
        guard engine != nil else {
            log.audio("Lane AU '\(ref.name)': no engine wired — not hosted", level: .error)
            return
        }
        inFlight[laneID] = ref
        let desc = AudioComponentDescription(
            componentType: ref.componentType,
            componentSubType: ref.componentSubType,
            componentManufacturer: ref.componentManufacturer,
            componentFlags: 0, componentFlagsMask: 0)
        Task { @MainActor [weak self] in
            // Clear only OUR pending entry — a newer load for the same lane may
            // have replaced it while we were suspended.
            defer { if self?.inFlight[laneID] == ref { self?.inFlight[laneID] = nil } }
            do {
                let unit = try await AVAudioUnit.instantiate(with: desc, options: [])
                // Stale-guard (review HIGH): the assignment may have been cleared
                // or changed while we were suspended — a superseded load drops its
                // unit un-attached (ARC closes the extension connection; no leak).
                guard let self, self.inFlight[laneID] == ref,
                      let engine = self.engine else { return }
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
