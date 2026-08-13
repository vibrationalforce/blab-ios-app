//
//  AutomationStatusStrip.swift
//  Echoelmusic — Studio
//
//  #559, slice 2 of `scratchpads/PLAN_AUTOMATION_IN_DER_SPUR.md`: "Sichtbarkeit vor
//  Editierbarkeit". The first surface anywhere in the app that says what the automation chain
//  is doing. It answers the player's question — "why is this changing by itself?" — and, on
//  every install today, answers it with an honest "nothing is".
//
//  ⭐ WHY VISIBILITY BEFORE EDITING, and it is not an ordering preference. Section 5 of the
//  plan states that none of the eight measured automation layers has ever been observed on a
//  device: `enabled` is `false`, the mutation API has had no caller since #473, and
//  `RecordController.arm()` none since #204. "~90 % built" is a claim about CODE. This strip is
//  the cheapest thing that turns any of it into something a person can look at, and it needs no
//  writer, no gesture and no route decision — which is also why it is word-for-word identical
//  under both routes the plan puts to the founder at slice 3.
//
//  ⚠️ THE FREEZE LAW DECIDES THE SHAPE (10.76.41/50), exactly as in #553. `soundPanel` is
//  reached through `dropdownContent`, which `EchoelStudioView.body` evaluates PERMANENTLY, and
//  that body hosts every `.menu` Picker of the instrument. `AnyView(...)` is not an observation
//  boundary; a `View` struct is. So this is its own struct and it reads `AutomationPlayer` in
//  its OWN body — the same construction as `AlwaysOnBioPanelStrip`, `BioStripView`,
//  `MasterVolumeField` and `MasterLoudnessGrid`, and stated here because the tempting later
//  "it's only a few rows, inline them" simplification IS the regression.
//
//  ⚠️ WHAT IT OBSERVES, AND AT WHAT RATE — because "it is a leaf" is a reason to be safe, not a
//  licence to be careless. It reads `lanes` (edited, never during playback today), `clipLanes`
//  (installed on a clip/region change — at most about once per bar) and `timelineLanes`
//  (installed on play/stop and on a structural refresh). It does NOT read the playhead:
//  `AutomationPlayer.timelineTick` is `@ObservationIgnored` and its declaration says why —
//  transport-step rate, ~8–16 Hz. A live "value right now" column would cost the instrument its
//  open Pickers to print a number the ear already has. The readout is the SPAN a curve covers,
//  which changes only when someone edits it.
//
//  ⭐ IT GIVES `AutomationPlayer.extraAutomatableDescriptors` ITS FIRST CALLER SINCE #473.
//  That property is the placebo law in executable form ("only offer a parameter that actually
//  moves audio"); it was orphaned when the timeline row was deleted, and its doc block asks for
//  exactly this use. Here it does the inverse job as well: a lane whose keyPath is NOT among
//  the bound descriptors is still listed, and marked as reaching nothing.

#if canImport(SwiftUI)
import SwiftUI

/// The automation readout for the Sound panel: which parameters move on their own, over what
/// span, from which layer — and which of them cannot reach audio.
@MainActor
struct AutomationStatusStrip: View {
    @Environment(AutomationPlayer.self) private var player

    var body: some View {
        let rows = statusRows
        // NO HEADING HERE, DELIBERATELY. "Automation" is a section heading, and #362 unified
        // every one of them onto `EchoelStudioView.groupHeader` after finding three spellings
        // split by panel family — one of which asked for a weight the bundled font cannot
        // render. That builder is `private` to the view, so spelling the same 11 pt semibold
        // inline here would be a fourth spelling in a file no per-panel review would compare
        // (#416, and `SectionHeadingIsOneTreatmentTests` is the guard). The host calls
        // `groupHeader("Automation")` immediately above the mount instead. Hoisting the
        // builder somewhere shared is a real slice; quietly re-spelling it is not.
        VStack(alignment: .leading, spacing: 8) {
            enableRow
            if rows.isEmpty {
                Text(AutomationStatus.emptySentence)
                    .font(EchoelTheme.font(11)).foregroundStyle(EchoelTheme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(rows) { AutomationStatusRowView(row: $0) }
            }
        }
    }

    /// #561 — the master switch, and the reason it arrives here rather than in the slice the
    /// plan scheduled it for.
    ///
    /// ⭐ THE PLAN PUT IT LAST AND SAID WHY: *"ein Schalter, der etwas Unsichtbares
    /// einschaltet, ist kein Feature"*. That reason expired one slice ago — #559 put the state
    /// on screen, so the strip above can now say `off` next to a curve, and a player who reads
    /// that has no way to act on it. A surface that names a state and withholds its remedy is
    /// worse than one that says nothing.
    ///
    /// ⛔ AND THE SECOND REASON IS A DEFECT, NOT A FEATURE REQUEST: the flag's decode defaults
    /// to `false` on any unreadable document, deliberately (automation overwrites what the
    /// performer set live, so a damaged flag must never turn it ON) — and `AutomationState`'s
    /// own doc block calls that a ONE-WAY DOOR, because until this row there was no setter
    /// anywhere in `Sources/`. A user whose earlier build persisted `enabled: true` could lose
    /// it to one truncated write and never get it back from inside the app. That is a
    /// user-facing hole independent of which route slice 3 takes.
    ///
    /// ⚠️ TURNING IT ON WITH NO CURVES IS INAUDIBLE, and that is what makes shipping the switch
    /// before the writer safe rather than reckless. In `applyStep` the master and tempo targets
    /// apply only `if let r = real`, which is nil for an empty lane; the filter multiplier
    /// applies `real ?? target.neutralValue`, and that neutral is ×1 — exactly what the
    /// DISABLED branch writes via `setCutoffScale(1)`. So with nothing recorded the two states
    /// are the same sound, and `TheAutomationSwitchIsSafeToFlipTests` pins each half.
    private var enableRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(get: { player.enabled },
                                 set: { player.enabled = $0 })) {
                Text("Play automation")
                    .font(EchoelTheme.font(12, .semibold))
                    .foregroundStyle(EchoelTheme.text)
            }
            .toggleStyle(.switch)
            .tint(EchoelTheme.accent)
            .frame(minHeight: 44)
            .accessibilityHint("Lets recorded parameter curves move the sound while the transport runs")
            Text(player.enabled
                 ? "Recorded curves move these parameters while the transport runs."
                 : "Off by default. Clip automation still plays; this switch is for the song-wide curves.")
                .font(EchoelTheme.font(10))
                .foregroundStyle(EchoelTheme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Resolve names + real-world scales, then let the pure reader do the work.
    ///
    /// The enum branch comes FIRST because a legacy target is addressable under two identities
    /// (its saved rawValue and its registry keyPath alias) and `forParameter` resolves both —
    /// `ddsp.filter.cutoffScale` is the ×0,25…×4 log multiplier and must never be scaled as if
    /// it were the absolute-Hz `ddsp.filter.cutoff` descriptor.
    private var statusRows: [AutomationStatusRow] {
        let descriptors = player.extraAutomatableDescriptors
        return AutomationStatus.rows(
            global: player.lanes,
            clip: player.clipLanes,
            arrangement: player.timelineLanes,
            globalEnabled: player.enabled
        ) { parameter in
            if let target = AutomationTarget.forParameter(parameter) {
                return AutomationScale(target: target)
            }
            if let descriptor = descriptors.first(where: { $0.keyPath == parameter }) {
                return AutomationScale(descriptor: descriptor)
            }
            return nil
        }
    }
}

/// One automated parameter: name, layer, keyframe count, the span it covers — and, when
/// something is stopping it, the reason in a word.
///
/// The three "stopped" states are deliberately different words rather than one greyed-out
/// style, because they have different repairs and a player cannot act on a colour: **off** =
/// the global master switch is down (no in-app setter today — slice 4); **overridden** = a
/// later layer holds the same parameter and wins each step; **no effect** = nothing is bound to
/// that keyPath, so the curve replays into the router's nil return (slice 1's silent no-op).
@MainActor
struct AutomationStatusRowView: View {
    let row: AutomationStatusRow

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(row.displayName)
                    .font(EchoelTheme.font(12, .semibold)).foregroundStyle(EchoelTheme.text)
                    .lineLimit(1)
                Text(row.layer.label)
                    .font(EchoelTheme.font(10)).foregroundStyle(EchoelTheme.dim)
                Spacer(minLength: 0)
                if let note = stopNote {
                    Text(note)
                        .font(EchoelTheme.font(10, .semibold)).foregroundStyle(EchoelTheme.dim)
                }
                Text(spanText)
                    .font(EchoelTheme.font(11).monospacedDigit()).foregroundStyle(EchoelTheme.dim)
            }
            Text("\(row.pointCount) point\(row.pointCount == 1 ? "" : "s")")
                .font(EchoelTheme.font(10)).foregroundStyle(EchoelTheme.dim)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    /// Precedence order, not alphabetical: `isBound == false` is reported first because a lane
    /// that reaches no setter stays silent even after the switch goes up and the override is
    /// resolved. Reporting the cheapest-to-fix cause first would send a player to fix a
    /// symptom.
    private var stopNote: String? {
        if !row.isBound { return "no effect" }
        if row.isOverridden { return "overridden" }
        if !row.isActive { return "off" }
        return nil
    }

    private var spanText: String {
        let low = EchoelDecimalText.string(row.lowest, decimals: row.decimals)
        let high = EchoelDecimalText.string(row.highest, decimals: row.decimals)
        let span = low == high ? low : "\(low)–\(high)"
        return row.unit.isEmpty ? span : "\(span) \(row.unit)"
    }

    /// VoiceOver gets the same facts in the same order, as a sentence rather than a layout.
    private var accessibilityText: String {
        var parts = ["\(row.displayName), \(row.layer.label) automation, \(spanText)",
                     "\(row.pointCount) point\(row.pointCount == 1 ? "" : "s")"]
        if !row.isBound {
            parts.append("no effect, nothing is connected to this parameter")
        } else if row.isOverridden {
            parts.append("overridden by a later layer")
        } else if !row.isActive {
            parts.append("switched off")
        }
        return parts.joined(separator: ", ")
    }
}
#endif
