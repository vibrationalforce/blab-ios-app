// AutomationPlayer.swift
// Echoel — plays parameter automation back over the live transport, the founder's
// "arrangiert … mit automationen". Like ArrangementPlayer it does NOT own a clock:
// it rides the one shared PatternEngine and is fed each transport step (via
// PianoRollModel's onTick). For every enabled lane it reads the keyframe value at
// the current tick and writes it to the live parameter.
//
// v1 scope (deliberately SAFE): targets are MAIN-THREAD-safe parameters only —
// master level (mixer output volume) and tempo (the transport's own BPM). It never
// touches DSP voice/render state, so automation can't destabilise the audio thread.
// Timing is per-bar (the 16-step loop), so a lane is a repeating shape over the bar
// — musical for swells / tempo moves. Song-position automation across an arrangement
// arrives once the arrangement exposes an absolute-bar counter.

import Foundation
import Observation

/// A parameter automation can drive. Normalized lane values [0...1] map to each
/// target's real range; the consumer applies the mapped value live.
public enum AutomationTarget: String, Codable, Sendable, CaseIterable, Identifiable {
    case masterLevel
    case tempo
    case filterCutoff

    public var id: String { rawValue }

    /// Registry-style stable identity ("modul.sektion.parameter") — cycle 2 of the
    /// automation-in-track plan. The enum's rawValue stays the PERSISTED legacy
    /// identity (saved lanes are never rewritten); this alias lets new code address
    /// the same target through the EchoelParameterRegistry keyPath convention.
    /// NOTE: filterCutoff is the ×0.25…×4 log MULTIPLIER on the voice's cutoff
    /// (setCutoffScale), not the absolute-Hz "ddsp.filter.cutoff" descriptor.
    public var keyPath: String {
        switch self {
        case .masterLevel:  return "master.amp.level"
        case .tempo:        return "transport.tempo.bpm"
        case .filterCutoff: return "ddsp.filter.cutoffScale"
        }
    }

    /// Resolve EITHER identity — the legacy rawValue ("masterLevel") or the keyPath
    /// alias — to the enum target. nil = not an enum target (a free keyPath lane).
    public static func forParameter(_ parameter: String) -> AutomationTarget? {
        if let t = AutomationTarget(rawValue: parameter) { return t }
        return allCases.first { $0.keyPath == parameter }
    }

    public var displayName: String {
        switch self {
        case .masterLevel:  return "Master Level"
        case .tempo:        return "Tempo"
        case .filterCutoff: return "Filter Cutoff"
        }
    }

    public var unit: String {
        switch self {
        case .masterLevel:  return ""
        case .tempo:        return "BPM"
        case .filterCutoff: return "×"
        }
    }

    /// Real-world value range the normalized lane maps onto.
    public var minValue: Double {
        switch self {
        case .tempo:        return 40
        case .filterCutoff: return 0.25
        case .masterLevel:  return 0
        }
    }
    public var maxValue: Double {
        switch self {
        case .tempo:        return 220
        case .filterCutoff: return 4
        case .masterLevel:  return 1
        }
    }
    public var decimals: Int { self == .tempo ? 0 : 2 }

    /// Neutral value (no audible effect) when a lane is empty / automation off.
    public var neutralValue: Double {
        switch self {
        case .filterCutoff: return 1        // ×1 = unchanged cutoff
        case .masterLevel:  return 1
        case .tempo:        return 120
        }
    }

    /// Map a normalized [0...1] lane value to the real parameter value. Filter cutoff
    /// uses a log (octave) curve so 0.5 sits at ×1; the rest are linear.
    public func value(forNormalized n: Double) -> Double {
        let c = Swift.min(1, Swift.max(0, n))
        if self == .filterCutoff {
            return minValue * pow(maxValue / minValue, c)   // 0.25…4, ×1 at c=0.5
        }
        return minValue + c * (maxValue - minValue)
    }

    /// Inverse: real value → normalized [0...1] (for editing in real units).
    public func normalized(forValue v: Double) -> Double {
        if self == .filterCutoff {
            let cv = Swift.min(maxValue, Swift.max(minValue, v))
            return Swift.min(1, Swift.max(0, Foundation.log(cv / minValue) / Foundation.log(maxValue / minValue)))
        }
        let span = maxValue - minValue
        guard span > 0 else { return 0 }
        return Swift.min(1, Swift.max(0, (v - minValue) / span))
    }
}

/// Persisted automation document: the on/off state plus one lane per target.
///
/// Defensive decode (#170, the same law as `SynthPatch`/`Project`/`AutomationLane`).
/// `AutomationLane` is already forgiving element-side, but the DOCUMENT around it was
/// not: the synthesized decoder made `enabled` and `lanes` both REQUIRED, so adding one
/// field here tomorrow — or one lane element that is not a JSON object, or a truncated
/// write — threw, `AppGroupStore.load` returned nil, and `AutomationPlayer.init` fell
/// into its `else` branch: every drawn curve gone AND `enabled` silently flipped off.
/// Both halves are needed and both are here — element-tolerant `lanes` (a bad lane
/// becomes a hole, the rest survive) and field-tolerant `enabled`.
///
/// HONEST SCOPE — this protects a READ, not a save loop. THE LOAD-BEARING FACT IS THE
/// GREP, so state it as the grep: not one production call site in `Sources/` reaches
/// `persist()` — none of `addPoint`/`removePoint`/`movePoint`/`setValue`/`setCurve`/
/// `setCurvature`/`adoptLane`/`removeLane`/`clear`, and `enabled` (whose `didSet`
/// persists) has no setter either. `enabled`'s `didSet` also does not fire during `init`,
/// so launch writes nothing. `automation.json` is genuinely never rewritten today, and a
/// failed decode could not destroy the file the way the #163 library-wipe did.
/// ⛔ Do NOT restate this as "because the automation row is gone" — an earlier version of this
/// comment named `TimelineAutomationRow` and said exactly that, and it is wrong twice over:
/// that row committed into `TimelineStore`, not into this player (its only `AutomationPlayer`
/// touch was a READ of `extraAutomatableDescriptors`), so re-mounting it would not have
/// restored a writer at all. The row's view was DELETED in #473 (415 lines of FILE removed —
/// do not attach that number to the view itself; the `struct` was 198 lines), which does not
/// change the argument in either direction — and that is precisely why the retraction stays:
/// a future session building a new automation editor cannot re-derive this from code that no
/// longer exists, so it would land the same wrong sentence again. The load-bearing fact is
/// the grep above, not the state of any view.
///
/// What a bad decode CAN still do is silently stop curves a user drew in an earlier build
/// from playing: `applyStep` runs on every transport step (`PianoRollModel.start`'s
/// `pattern.onTick`, installed once at launch), so those lanes are live even with their
/// editor gone. That read is what this defends — with one narrowing that matters: the
/// persisted lanes only APPLY inside `if enabled`, and `enabled` has no in-app setter.
/// So this reaches exactly the user whose earlier build persisted `enabled: true`, and
/// the `?? false` default below is a ONE-WAY DOOR for them: once that flag degrades there
/// is no way back on from inside the app. That is the deliberate direction (automation
/// overwrites live performer values, so an unreadable flag must never turn it ON), but it
/// has to be written down, because "those lanes are live" reads as reversible and is not.
///
/// Internal, not `private`, ONLY so the regression test can decode it directly:
/// `AutomationPlayer` takes no injectable store, so testing through it would mean
/// writing into the real App-Group container.
struct AutomationState: Codable, Sendable {
    var enabled: Bool
    var lanes: [AutomationLane]

    init(enabled: Bool, lanes: [AutomationLane]) {
        self.enabled = enabled
        self.lanes = lanes
    }

    private enum CodingKeys: String, CodingKey { case enabled, lanes }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // `try?` rather than `decodeIfPresent`, deliberately: `decodeIfPresent` absorbs
        // absent/null but still THROWS on a type mismatch, which is one of the shapes
        // that has to stop being fatal here.
        // Defaulting to `false` is the conservative direction — automation writes over
        // whatever the performer has set live, so an unreadable flag must not be able to
        // turn it ON. It also matches the branch `init` already takes when nothing loads.
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? false
        lanes = []
        // NOT a bare `try? … ?? []`. That version shipped for one commit and made the
        // WORST case the silent one: `lanes` present but not an array lost EVERY lane
        // while `dropped` computed to 0, so the telemetry below never fired. It is the
        // exact case `decodeLossyArray` refuses to swallow ("swallowing it would leave
        // total loss undiagnosable"), so it gets the same treatment here.
        do {
            let wrapped = try c.decode([LossyDecoded<AutomationLane>].self, forKey: .lanes)
            lanes = wrapped.compactMap(\.value)
            // TELEMETRY — dropping a lane is bounded loss, but it is still permanent loss
            // the moment anything re-encodes the survivors. Logged once per read, never
            // per lane.
            let dropped = wrapped.count - lanes.count
            if dropped > 0 {
                log.log(.error, category: .system,
                        "AutomationState — dropped \(dropped)/\(wrapped.count) undecodable lane(s)")
            }
        } catch {
            // An ABSENT `lanes` key is the legitimate "document with no lanes yet" case
            // and must stay quiet — logging it would cry wolf on every clean first run.
            // Anything else is total lane loss and is logged WITH the underlying error,
            // because the reason is what tells a maintainer a schema change from a
            // truncated write.
            var absent = false
            if let decodeError = error as? DecodingError, case .keyNotFound = decodeError {
                absent = true
            }
            if !absent {
                log.log(.error, category: .system,
                        "AutomationState — `lanes` unreadable, ALL lanes lost: \(error)")
            }
        }
    }
}

@MainActor
@Observable
public final class AutomationPlayer {

    /// One bar = 16 steps = 4 quarter-note beats.
    public static let beatsPerBar = 4

    /// Master switch — when off, automation never writes a parameter.
    public var enabled: Bool { didSet { persist() } }

    /// One lane per target (created lazily, kept for the lifetime of the doc).
    public private(set) var lanes: [AutomationLane]

    /// The FIRED clip's own automation (cycle 4) — transient, never persisted
    /// here (the clip persists it). Set by the clip launch paths via
    /// `PianoRollModel.load`, cleared by loading anything without automation.
    /// Clip lanes are clip CONTENT: they play whenever the clip plays — like
    /// its notes, independent of the global `enabled` switch — and they win
    /// over a global lane on the same parameter (applied after it each step).
    public private(set) var clipLanes: [AutomationLane] = []

    /// The ARRANGEMENT's automation (cycle 5) — song-ABSOLUTE lanes from the
    /// timeline document. Transient here (the document persists them). Applied
    /// LAST each step so the arrangement's automation is authoritative while the
    /// song plays; the timeline player feeds `timelineTick` (the absolute
    /// playhead) each step before `applyStep` runs.
    public private(set) var timelineLanes: [AutomationLane] = []
    /// Song-absolute playhead tick for the timeline layer. @ObservationIgnored:
    /// it updates at transport-step rate (~8–16 Hz) — a view must never observe
    /// it (the 10 Hz menu-freeze law); the playhead has its own leaf elsewhere.
    @ObservationIgnored private var timelineTick = 0

    @ObservationIgnored private weak var pattern: PatternEngine?
    @ObservationIgnored private weak var audioEngine: AudioEngine?
    @ObservationIgnored private weak var voice: PolySynthVoice?
    /// Cycle-2 wire: extra keyPath lanes (beyond the three enum targets) apply
    /// through this router (registry-denormalized → live setter). Optional —
    /// without it the player behaves exactly as before.
    @ObservationIgnored private weak var router: ParameterApplyRouter?
    @ObservationIgnored private let store = AppGroupStore(subdirectory: "Automation")
    @ObservationIgnored private static let fileName = "automation"

    public init() {
        if let saved = store.load(AutomationState.self, name: Self.fileName) {
            self.enabled = saved.enabled
            self.lanes = AutomationPlayer.completed(saved.lanes)
        } else {
            self.enabled = false
            self.lanes = AutomationPlayer.completed([])
        }
    }

    /// Ensure exactly one lane exists per enum target (matched under EITHER
    /// identity — legacy rawValue or keyPath alias, saved names untouched) and
    /// PRESERVE every additional keyPath lane instead of dropping it (cycle 2:
    /// unknown lanes are future registry-parameter automation, not junk).
    private static func completed(_ existing: [AutomationLane]) -> [AutomationLane] {
        let enumLanes = AutomationTarget.allCases.map { target in
            existing.first { AutomationTarget.forParameter($0.parameter) == target }
                ?? AutomationLane(parameter: target.rawValue)
        }
        let extras = existing.filter { AutomationTarget.forParameter($0.parameter) == nil }
        return enumLanes + extras
    }

    // MARK: - Wiring

    /// Connect the live transport + master + synth so applied values land somewhere.
    public func wire(pattern: PatternEngine, audioEngine: AudioEngine, voice: PolySynthVoice? = nil) {
        self.pattern = pattern
        self.audioEngine = audioEngine
        self.voice = voice
    }

    /// Connect the keyPath→setter router for extra (non-enum) lanes. Separate from
    /// the transport wire so pure tests can wire only this.
    public func wire(router: ParameterApplyRouter) {
        self.router = router
    }

    // MARK: - Playback (called each transport step on the shared clock)

    /// Apply every enabled lane's value at `step` to its live parameter. Per-bar:
    /// the step maps to a tick within one bar, so the lane repeats each loop.
    public func applyStep(_ step: Int) {
        if enabled {
            for target in AutomationTarget.allCases {
                let real = appliedValue(for: target, atStep: step)
                switch target {
                case .masterLevel: if let r = real { applyEnum(target, real: r) }
                case .tempo:       if let r = real { applyEnum(target, real: r) }
                // Filter cutoff is a hidden multiplier → reset to neutral (×1) when its
                // lane is empty, so an unused lane never leaves the sound filtered.
                case .filterCutoff: applyEnum(target, real: real ?? target.neutralValue)
                }
            }
            // Extra keyPath lanes (cycle 2): registry-denormalize + dispatch through the
            // router. No router / unbound keyPath = safe no-op (never a dead crash).
            for lane in lanes where AutomationTarget.forParameter(lane.parameter) == nil {
                if let n = lane.value(atTick: step * Note.ticksPerStep) {
                    router?.applyNormalized(lane.parameter, Float(n))
                }
            }
        } else {
            // Automation off: release the hidden multiplier so the synth isn't
            // left filtered; master/tempo stay where they are (user-visible).
            voice?.setCutoffScale(1)
        }
        // Clip layer (cycle 4) — AFTER the global writes, so the fired clip's own
        // automation wins on a shared parameter, and OUTSIDE the `enabled` gate:
        // clip automation is clip content and plays like the clip's notes. Ticks
        // are clip-relative; today's live loop is the same 1-bar phase, so the
        // step tick IS the clip tick.
        for lane in clipLanes { dispatchLane(lane, atTick: step * Note.ticksPerStep) }
        // Timeline layer (cycle 5) — song-ABSOLUTE arrangement lanes, applied LAST
        // so the arrangement's automation is authoritative while the song plays.
        // The timeline player set `timelineTick` earlier in this same onTick chain;
        // [] when the timeline isn't playing = no effect.
        for lane in timelineLanes { dispatchLane(lane, atTick: timelineTick) }
    }

    /// Apply one lane's value at a resolved tick to its live target — the ONE
    /// dispatch the clip AND timeline layers share (enum → its curve → applyEnum;
    /// free keyPath → the router). No fork.
    private func dispatchLane(_ lane: AutomationLane, atTick tick: Int) {
        guard let n = lane.value(atTick: tick) else { return }
        if let target = AutomationTarget.forParameter(lane.parameter) {
            applyEnum(target, real: target.value(forNormalized: n))
        } else {
            router?.applyNormalized(lane.parameter, Float(n))
        }
    }

    /// The REAL value a lane-set would apply for a parameter at a tick (enum curve
    /// preserved, e.g. log filter; free keyPath → its normalized value, the
    /// router's descriptor owns the real mapping). nil when no lane covers it.
    /// The shared read behind clip + timeline `…AppliedValue`. Pure.
    private func layerValue(in lanes: [AutomationLane],
                            forParameter parameter: String, atTick tick: Int) -> Double? {
        let target = AutomationTarget.forParameter(parameter)
        for lane in lanes {
            let sameLane = lane.parameter == parameter
                || (target != nil && AutomationTarget.forParameter(lane.parameter) == target)
            guard sameLane, let n = lane.value(atTick: tick) else { continue }
            return target.map { $0.value(forNormalized: n) } ?? n
        }
        return nil
    }

    /// The ONE live write site for enum targets — global, clip and timeline lanes
    /// all terminate here (no dispatch fork).
    private func applyEnum(_ target: AutomationTarget, real: Double) {
        switch target {
        case .masterLevel:  audioEngine?.masterVolume = Float(real)
        case .tempo:        pattern?.setTempo(real)
        case .filterCutoff: voice?.setCutoffScale(Float(real))
        }
    }

    // MARK: - Clip layer (cycle 4)

    /// Install the fired clip's automation (empty = clear the layer). Transient —
    /// never persisted here; the clip's own JSON carries the lanes.
    public func setClipLanes(_ lanes: [AutomationLane]) {
        clipLanes = lanes
    }

    /// The REAL value the clip layer would apply for a parameter at `step`, or nil
    /// when no clip lane covers it. Pure — exposed for testing.
    public func clipAppliedValue(forParameter parameter: String, atStep step: Int) -> Double? {
        layerValue(in: clipLanes, forParameter: parameter, atTick: step * Note.ticksPerStep)
    }

    // MARK: - Timeline layer (cycle 5) — song-absolute arrangement automation

    /// Install the arrangement's automation (empty = clear the layer). Transient —
    /// the timeline document persists these lanes, not the player.
    public func setTimelineLanes(_ lanes: [AutomationLane]) {
        timelineLanes = lanes
    }

    /// Feed the song-absolute playhead tick (from the timeline player's cursor).
    /// Called each transport step BEFORE `applyStep`, so the timeline layer reads
    /// the correct song position. Clamped ≥ 0.
    public func setTimelineTick(_ tick: Int) {
        timelineTick = max(0, tick)
    }

    /// The REAL value the timeline layer would apply for a parameter at a
    /// song-ABSOLUTE tick, or nil when no timeline lane covers it. Pure.
    public func timelineAppliedValue(forParameter parameter: String, atTick tick: Int) -> Double? {
        layerValue(in: timelineLanes, forParameter: parameter, atTick: tick)
    }

    /// The real-world value an ENUM target would take at `step`, addressed by either
    /// identity (legacy rawValue or keyPath alias). nil for non-enum keyPaths — their
    /// curve lives in the registry descriptor, applied via the router, not guessed here.
    public func appliedValue(forKeyPath keyPath: String, atStep step: Int) -> Double? {
        guard let target = AutomationTarget.forParameter(keyPath) else { return nil }
        return appliedValue(for: target, atStep: step)
    }

    /// The real-world value a target would take at `step` (per-bar tick), or nil if
    /// its lane is empty. Pure — the core of `applyStep`, exposed for testing.
    public func appliedValue(for target: AutomationTarget, atStep step: Int) -> Double? {
        let lane = lane(for: target)
        guard let n = lane.value(atTick: step * Note.ticksPerStep) else { return nil }
        return target.value(forNormalized: n)
    }

    // MARK: - Lane access + editing

    public func lane(for target: AutomationTarget) -> AutomationLane {
        lanes.first { AutomationTarget.forParameter($0.parameter) == target }
            ?? AutomationLane(parameter: target.rawValue)
    }

    /// Add or replace a lane by parameter identity (alias-aware: a lane named by an
    /// enum target's keyPath lands in that enum slot, never as a duplicate). This is
    /// the door future registry-parameter automation walks through.
    public func adoptLane(_ lane: AutomationLane) {
        if let i = lanes.firstIndex(where: {
            $0.parameter == lane.parameter ||
            (AutomationTarget.forParameter($0.parameter) != nil &&
             AutomationTarget.forParameter($0.parameter)
                == AutomationTarget.forParameter(lane.parameter))
        }) {
            // Keep the slot's PERSISTED identity — an alias-named adopt must never
            // rewrite a saved legacy name (migration invariant; review 2026-07-13).
            var adopted = lane
            adopted.parameter = lanes[i].parameter
            lanes[i] = adopted
        } else {
            lanes.append(lane)
        }
        persist()
    }

    /// Remove an EXTRA keyPath lane. Enum-target lanes are structural (one per
    /// target, kept by `completed`) — clearing their points is `clear(target:)`.
    public func removeLane(parameter: String) {
        guard AutomationTarget.forParameter(parameter) == nil else { return }
        lanes.removeAll { $0.parameter == parameter }
        persist()
    }

    public func points(for target: AutomationTarget) -> [AutomationPoint] {
        lane(for: target).points
    }

    // MARK: - Parameter-string lane access + editing (cycle 3)
    // ONE UI code path for every lane: the sheet addresses a target purely by its
    // parameter string — a legacy rawValue, an enum keyPath alias (both land in
    // the same structural slot, saved names untouched) or a free registry keyPath
    // (its lane is created on the first edit). Same data as the enum route.

    /// The lane index for a parameter string. nil = no such lane yet.
    private func index(ofParameter parameter: String) -> Int? {
        guard !parameter.isEmpty else { return nil }
        if let target = AutomationTarget.forParameter(parameter) { return index(of: target) }
        return lanes.firstIndex { $0.parameter == parameter }
    }

    /// Look up + persist in one place so every string edit stays uniform.
    private func editLane(_ parameter: String, _ change: (inout AutomationLane) -> Void) {
        guard let i = index(ofParameter: parameter) else { return }
        change(&lanes[i])
        persist()
    }

    public func lane(forParameter parameter: String) -> AutomationLane? {
        index(ofParameter: parameter).map { lanes[$0] }
    }

    public func points(forParameter parameter: String) -> [AutomationPoint] {
        lane(forParameter: parameter)?.points ?? []
    }

    @discardableResult
    public func addPoint(parameter: String, beat: Double, value: Double,
                         curve: AutomationCurve = .linear) -> AutomationPoint? {
        guard !parameter.isEmpty else { return nil }
        let i: Int
        if let existing = index(ofParameter: parameter) {
            i = existing
        } else {
            lanes.append(AutomationLane(parameter: parameter))   // first edit creates it
            i = lanes.count - 1
        }
        let p = lanes[i].addPoint(tick: AutomationPlayer.tick(forBeat: beat),
                                  value: value, curve: curve)
        persist()
        return p
    }

    public func removePoint(parameter: String, id: UUID) {
        editLane(parameter) { $0.removePoint(id: id) }
    }

    public func movePoint(parameter: String, id: UUID, toBeat beat: Double) {
        editLane(parameter) { $0.movePoint(id: id, toTick: AutomationPlayer.tick(forBeat: beat)) }
    }

    /// Move + revalue a keyframe in one gesture step (canvas point-drag).
    public func movePoint(parameter: String, id: UUID, toBeat beat: Double,
                          normalized value: Double) {
        editLane(parameter) {
            $0.movePoint(id: id, toTick: AutomationPlayer.tick(forBeat: beat))
            $0.setValue(id: id, value)
        }
    }

    public func setValue(parameter: String, id: UUID, normalized value: Double) {
        editLane(parameter) { $0.setValue(id: id, value) }
    }

    public func setCurve(parameter: String, id: UUID, _ curve: AutomationCurve) {
        editLane(parameter) { $0.setCurve(id: id, curve) }
    }

    /// Bend the segment leaving a keyframe (the canvas' vertical segment-drag).
    public func setCurvature(parameter: String, id: UUID, _ curvature: Double) {
        editLane(parameter) { $0.setCurvature(id: id, curvature) }
    }

    /// Empty a lane's points. Enum lanes stay structural (never removed);
    /// removing an extra lane entirely is `removeLane(parameter:)`.
    public func clear(parameter: String) {
        editLane(parameter) { $0.clear() }
    }

    /// The registry parameters a UI may offer for NEW automation lanes: bound to a
    /// live setter in the router (placebo law — a lane must move audio) and not
    /// already addressed by a legacy enum target (those stay on their own slots).
    ///
    /// ⚠️ ZERO CALLERS IN `Sources/` SINCE #473, and that is written here rather than
    /// acted on. Its only reader was `TimelineAutomationTargetOption`, inside the
    /// unmounted automation row that #473 deleted; it was FOUND by re-grepping AFTER
    /// the cut, which is the #472 lesson (a deletion orphans neighbours no register
    /// line predicted). Kept, not deleted: this is the placebo law in executable form —
    /// "only offer a parameter that actually moves audio" — and it is exactly what a
    /// future automation surface needs first. Deleting it is a SECOND decision, and
    /// making one inside a removal commit is how a "nothing else changed" claim stops
    /// being true (#470).
    public var extraAutomatableDescriptors: [ParameterDescriptor] {
        guard let router else { return [] }
        let enumKeyPaths = Set(AutomationTarget.allCases.map(\.keyPath))
        return router.automatableDescriptors().filter { !enumKeyPaths.contains($0.keyPath) }
    }

    /// Tick for a beat position (0…beatsPerBar) within the bar.
    public static func tick(forBeat beat: Double) -> Int {
        Int((beat * Double(Note.ticksPerQuarter)).rounded())
    }
    public static func beat(forTick tick: Int) -> Double {
        Double(tick) / Double(Note.ticksPerQuarter)
    }

    // The enum-typed editors delegate to the string route — ONE write path
    // (cycle 3), the enum keeps its ergonomic call sites.

    @discardableResult
    public func addPoint(target: AutomationTarget, beat: Double, value: Double,
                         curve: AutomationCurve = .linear) -> AutomationPoint? {
        addPoint(parameter: target.rawValue, beat: beat, value: value, curve: curve)
    }

    public func removePoint(target: AutomationTarget, id: UUID) {
        removePoint(parameter: target.rawValue, id: id)
    }

    public func movePoint(target: AutomationTarget, id: UUID, toBeat beat: Double) {
        movePoint(parameter: target.rawValue, id: id, toBeat: beat)
    }

    public func setValue(target: AutomationTarget, id: UUID, normalized value: Double) {
        setValue(parameter: target.rawValue, id: id, normalized: value)
    }

    public func setCurve(target: AutomationTarget, id: UUID, _ curve: AutomationCurve) {
        setCurve(parameter: target.rawValue, id: id, curve)
    }

    /// Bend the segment leaving a keyframe (the canvas' vertical segment-drag).
    public func setCurvature(target: AutomationTarget, id: UUID, _ curvature: Double) {
        setCurvature(parameter: target.rawValue, id: id, curvature)
    }

    /// Move + revalue a keyframe in one gesture step (canvas point-drag).
    public func movePoint(target: AutomationTarget, id: UUID, toBeat beat: Double,
                          normalized value: Double) {
        movePoint(parameter: target.rawValue, id: id, toBeat: beat, normalized: value)
    }

    public func clear(target: AutomationTarget) {
        clear(parameter: target.rawValue)
    }

    private func index(of target: AutomationTarget) -> Int? {
        lanes.firstIndex { AutomationTarget.forParameter($0.parameter) == target }
    }

    private func persist() {
        store.save(AutomationState(enabled: enabled, lanes: lanes), name: Self.fileName)
    }
}
