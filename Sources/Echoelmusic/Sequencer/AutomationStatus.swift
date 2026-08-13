// AutomationStatus.swift
// Echoel — #559, slice 2 of `scratchpads/PLAN_AUTOMATION_IN_DER_SPUR.md`
// ("Sichtbarkeit vor Editierbarkeit", route-neutral: identical under Route A and Route B).
//
// WHAT THIS IS. The pure reading of the automation chain: given the three lane layers the
// player holds and a way to name/scale a parameter, it answers the player's question — WHICH
// parameters change by themselves, over what span, from which layer, and whether that lane
// reaches audio at all. No view, no clock, no engine; `Studio/AutomationStatusStrip.swift`
// renders it.
//
// ⭐ IT LIVES IN ITS OWN FILE ON PURPOSE, AND THAT IS THE #472/#473 LESSON APPLIED FORWARD
// rather than re-learned. `TimelineAutomationRowMath` spent months inside a 415-line file
// whose other half was an unmounted SwiftUI view: doorless is a property of a VIEW, deletable
// is a property of a FILE, and putting the two together made a plausible "delete the doorless
// file" cleanup into a break of `Core/TimelineStore.swift`. The strip this feeds may well be
// moved, re-hosted or removed when slice 3 picks a route — none of that may take the reading
// with it.
//
// ⚠️ WHAT IT DELIBERATELY DOES NOT DO: read a playhead. "At what value RIGHT NOW" would need
// the transport step or `AutomationPlayer.timelineTick`, and that tick is `@ObservationIgnored`
// with the reason written at its declaration — it moves at transport-step rate (~8–16 Hz) and
// a view that observes it rebuilds its host at that rate (10.76.41/50, the menu freeze). So
// the honest readout is the SPAN a lane covers (lowest…highest in real units) plus its
// keyframe count: facts about the CURVE, which change only when someone edits it. A live
// number would cost the instrument its Pickers to say something the ear already knows.
//
// ⚠️ AND IT REPORTS THE SILENT NO-OP RATHER THAN HIDING IT (`isBound == false`). Slice 1
// (#555–#558) measured that `applyStep` dispatches a free keyPath through
// `ParameterApplyRouter.applyNormalized`, which returns nil — a deliberate, crash-free no-op —
// when nothing is bound to it. A lane on such a keyPath draws, saves, replays and moves
// nothing. Dropping those rows from this list would make the surface agree with the defect:
// the player would see no automation and hear no automation and have no way to connect the
// two. They are listed, and named as ineffective.

import Foundation

/// How one parameter's normalized lane value (0…1) becomes a number a human reads.
///
/// A closure and not a min/max pair, because one of the three legacy targets is NOT linear:
/// `AutomationTarget.filterCutoff` maps through `minValue * pow(maxValue/minValue, c)` so that
/// 0,5 sits at ×1. A linear span would have printed a wrong number for exactly the parameter
/// whose whole point is that its middle is neutral.
public struct AutomationScale: Sendable {
    public let displayName: String
    public let unit: String
    public let decimals: Int
    private let map: @Sendable (Double) -> Double

    public init(displayName: String, unit: String, decimals: Int,
                map: @escaping @Sendable (Double) -> Double) {
        self.displayName = displayName
        self.unit = unit
        self.decimals = decimals
        self.map = map
    }

    /// A plain linear range — the shape of every registry descriptor, and the only shape a
    /// caller should ever hand-build. Written as a convenience over the closure form rather
    /// than as a second stored representation: two ways to hold a scale is two ways for the
    /// non-linear case to be forgotten (#416).
    public init(displayName: String, unit: String, decimals: Int,
                minValue: Double, maxValue: Double) {
        self.init(displayName: displayName, unit: unit, decimals: decimals) { n in
            minValue + Swift.min(1, Swift.max(0, n)) * (maxValue - minValue)
        }
    }

    /// A legacy enum target — keeps its own curve, linear or not.
    public init(target: AutomationTarget) {
        self.init(displayName: target.displayName, unit: target.unit,
                  decimals: target.decimals) { target.value(forNormalized: $0) }
    }

    /// A registry parameter — the descriptor owns the real range (#416: one definition).
    ///
    /// `decimals` is a DISPLAY heuristic derived from the span, not a claim about the
    /// parameter's resolution: `ParameterDescriptor` carries no decimal count, and inventing a
    /// per-parameter table here would be a second spelling of something the registry does not
    /// state. Wide ranges (Hz) read badly with two decimals; narrow ones (0…1) read as nothing
    /// without them.
    public init(descriptor: ParameterDescriptor) {
        let span = Double(descriptor.max - descriptor.min)
        let decimals = span >= 100 ? 0 : (span >= 10 ? 1 : 2)
        self.init(displayName: descriptor.displayName, unit: descriptor.unit,
                  decimals: decimals) { Double(descriptor.denormalized(Float($0))) }
    }

    /// The real-world value for a normalized lane value, clamped like the lane itself.
    public func real(_ normalized: Double) -> Double {
        map(Swift.min(1, Swift.max(0, normalized)))
    }
}

/// One line of the readout: a lane that actually has keyframes, described.
public struct AutomationStatusRow: Identifiable, Sendable, Equatable {

    /// Which of the three layers the lane came from — in `AutomationPlayer.applyStep`'s
    /// WRITE order, which is also the precedence order: a later layer overwrites an earlier
    /// one on the same parameter within the same step.
    public enum Layer: String, Sendable, CaseIterable {
        /// The player's own persisted document (`automation.json`), gated by `enabled`.
        case global
        /// The fired clip's own lanes — clip CONTENT, applied OUTSIDE the `enabled` gate.
        case clip
        /// The arrangement's song-absolute lanes, applied last and therefore authoritative.
        case arrangement

        public var label: String {
            switch self {
            case .global:      return "Global"
            case .clip:        return "Clip"
            case .arrangement: return "Arrangement"
            }
        }
    }

    /// The lane's stored identity — a legacy rawValue, an enum keyPath alias, or a free
    /// registry keyPath. Kept verbatim: it is what a later edit has to address.
    public let parameter: String
    public let displayName: String
    public let layer: Layer
    public let pointCount: Int
    /// Lowest and highest real-world values the curve reaches. Derived from the lowest and
    /// highest NORMALIZED keyframes, which is only equal to the curve's real extremes because
    /// every mapping in use is monotonically increasing — pinned by the guard rather than
    /// assumed here, since a future non-monotonic mapping would silently invert this.
    public let lowest: Double
    public let highest: Double
    public let unit: String
    public let decimals: Int
    /// `false` = the curve replays and reaches no setter (slice 1's silent no-op).
    public let isBound: Bool
    /// `false` = this layer is switched off right now (only ever the global layer, whose
    /// lanes apply inside `if enabled`; clip and arrangement lanes are outside that gate).
    public let isActive: Bool
    /// `true` = a later layer holds a lane for the same parameter and wins each step.
    public let isOverridden: Bool

    public var id: String { "\(layer.rawValue)|\(parameter)" }

    public init(parameter: String, displayName: String, layer: Layer, pointCount: Int,
                lowest: Double, highest: Double, unit: String, decimals: Int,
                isBound: Bool, isActive: Bool, isOverridden: Bool) {
        self.parameter = parameter
        self.displayName = displayName
        self.layer = layer
        self.pointCount = pointCount
        self.lowest = lowest
        self.highest = highest
        self.unit = unit
        self.decimals = decimals
        self.isBound = isBound
        self.isActive = isActive
        self.isOverridden = isOverridden
    }
}

public enum AutomationStatus {

    /// The sentence shown when no lane anywhere holds a keyframe — which is the state of
    /// every install today, and saying so plainly is the point of the slice. It states the
    /// ABSENCE of a writer rather than promising a feature: the mutation API has had no
    /// caller since #473 and `RecordController.arm()` none since #204, so "nothing yet" is
    /// not a state the player can leave by looking harder.
    ///
    /// ⛔ IT READ "Nothing is automated yet — no parameter is moving on its own." UNTIL #562,
    /// AND THAT SECOND CLAUSE WAS FALSE ON THE SCREEN IT SHIPPED ON. #559 mounted this strip at
    /// the bottom of `soundPanel`; #560 put a line at the top of the SAME panel saying the body
    /// moves Brightness, Harmonics, Noise, Cutoff and the two vibrato rows around the values
    /// the player sets. So one panel said parameters move on their own and, a screen further
    /// down, that none do. That is #425 — a claim and its own refutation in one place — arriving
    /// on a USER-FACING surface rather than in a doc block, and it took two slices one cycle
    /// apart to build, which is exactly why neither review caught it: each sentence was true
    /// about its own subject and wrong about the screen.
    ///
    /// ⭐ THE REPAIR IS NOT "SAY LESS". The player's real question is "why is this moving?", and
    /// an empty automation list that only denies itself leaves the question standing. The second
    /// clause now ANSWERS it, and it is true because the always-on bio path is the only other
    /// writer of these parameters today — `applyBioReactive` recomputes them per render block
    /// from their `bioBase*` anchors (#556). The day a third source appears, this sentence is
    /// wrong again and `TheTwoSelfMovingSourcesAgreeTests` is where that shows up.
    public static let emptySentence =
        "No automation recorded — nothing is replaying a curve. Anything moving on its own "
        + "right now is your body, not automation."

    /// Describe every lane that has keyframes, in the order the player writes them.
    ///
    /// EMPTY LANES ARE SKIPPED, and that is the guard's "exactly the lanes the player
    /// applies" rule rather than tidiness: `AutomationLane.value(atTick:)` returns nil for a
    /// lane with no points, so `applyStep` writes nothing for it. `AutomationPlayer.completed`
    /// keeps one structurally-empty lane per legacy enum target for the lifetime of the
    /// document — listing those three would report automation on every fresh install.
    ///
    /// - Parameter scale: names and scales a parameter; `nil` = nothing is bound to it, so the
    ///   row is reported with its raw keyPath, its normalized span, and `isBound == false`.
    public static func rows(global: [AutomationLane],
                            clip: [AutomationLane],
                            arrangement: [AutomationLane],
                            globalEnabled: Bool,
                            scale: (String) -> AutomationScale?) -> [AutomationStatusRow] {
        let layers: [(AutomationStatusRow.Layer, [AutomationLane])] =
            [(.global, global), (.clip, clip), (.arrangement, arrangement)]
        var out: [AutomationStatusRow] = []
        for (index, entry) in layers.enumerated() {
            for lane in entry.1 where !lane.isEmpty {
                let scaling = scale(lane.parameter)
                let values = lane.points.map(\.value)
                let low = values.min() ?? 0
                let high = values.max() ?? 0
                // Only ACROSS layers. Within one layer the player's own construction gives at
                // most one lane per parameter — `completed` fills exactly one slot per enum
                // target and `adoptLane` replaces alias-equal lanes instead of appending — so
                // a same-layer duplicate is a state nothing can reach today, and resolving it
                // here would be a rule about a shape that does not exist.
                let overridden = layers.dropFirst(index + 1).contains { later in
                    later.1.contains {
                        !$0.isEmpty
                            && TimelineAutomationRowMath.sameParameter($0.parameter, lane.parameter)
                    }
                }
                out.append(AutomationStatusRow(
                    parameter: lane.parameter,
                    displayName: scaling?.displayName ?? lane.parameter,
                    layer: entry.0,
                    pointCount: lane.points.count,
                    lowest: scaling?.real(low) ?? low,
                    highest: scaling?.real(high) ?? high,
                    unit: scaling?.unit ?? "",
                    decimals: scaling?.decimals ?? 2,
                    isBound: scaling != nil,
                    isActive: entry.0 == .global ? globalEnabled : true,
                    isOverridden: overridden))
            }
        }
        return out
    }
}
