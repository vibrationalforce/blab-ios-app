#if canImport(SwiftUI)
import SwiftUI

// AutomationView.swift
// Echoel — author parameter automation as a list of keyframes (no fancy canvas):
// pick a target (Master Level / Tempo), toggle automation on, and add keyframes
// — each a Beat position + Value + Curve, edited with the app-wide EchoelValueField.
// Playback rides the shared transport (AutomationPlayer.applyStep) so the param
// follows the lane each bar. Values are edited in REAL units (BPM, level); the lane
// stores them normalized.

@MainActor
struct AutomationView: View {

    @Environment(AutomationPlayer.self) private var automation
    @Environment(\.dismiss) private var dismiss

    @State private var target: AutomationTarget = .masterLevel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    enableRow
                    targetPicker
                    keyframes
                    Text("Automation plays over the loop: each keyframe sets \(target.displayName.lowercased()) at its beat, gliding (Linear) or stepping (Hold) to the next. Off leaves the parameter alone.")
                        .font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.dim)
                }
                .padding(16)
            }
            .background(EchoelTheme.bg.ignoresSafeArea())
            .navigationTitle("Automation")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    @ViewBuilder private var enableRow: some View {
        @Bindable var auto = automation
        Toggle(isOn: $auto.enabled) {
            Text("Automation on").font(EchoelTheme.font(14, .semibold)).foregroundStyle(EchoelTheme.text)
        }
        .tint(EchoelTheme.accent)
    }

    private var targetPicker: some View {
        Picker("Target", selection: $target) {
            ForEach(AutomationTarget.allCases) { t in Text(t.displayName).tag(t) }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder private var keyframes: some View {
        let points = automation.points(for: target)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Keyframes").font(EchoelTheme.font(11, .bold)).foregroundStyle(EchoelTheme.dim)
                Spacer()
                if !points.isEmpty {
                    Button("Clear") { automation.clear(target: target) }
                        .font(EchoelTheme.font(12, .semibold)).foregroundStyle(EchoelTheme.danger)
                        .buttonStyle(.plain)
                }
            }
            if points.isEmpty {
                Text("No keyframes. Add one to start shaping \(target.displayName.lowercased()).")
                    .font(EchoelTheme.font(13)).foregroundStyle(EchoelTheme.dim)
                    .padding(.vertical, 4)
            } else {
                ForEach(points) { p in keyframeRow(p) }
            }
            Button {
                let nextBeat = min(Double(AutomationPlayer.beatsPerBar),
                                   (points.last.map { AutomationPlayer.beat(forTick: $0.tick) } ?? -1) + 1)
                automation.addPoint(target: target, beat: max(0, nextBeat), value: 0.5)
            } label: {
                Label("Add keyframe", systemImage: "plus")
                    .font(EchoelTheme.font(13, .semibold)).foregroundStyle(EchoelTheme.text)
                    .frame(maxWidth: .infinity).frame(height: 40)
                    .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.border, lineWidth: 1))
    }

    private func keyframeRow(_ p: AutomationPoint) -> some View {
        VStack(spacing: 8) {
            EchoelValueField(label: "Beat", value: beatBinding(p),
                             range: 0...Float(AutomationPlayer.beatsPerBar), unit: "", decimals: 2)
            EchoelValueField(label: "Value", value: valueBinding(p),
                             range: Float(target.minValue)...Float(target.maxValue),
                             unit: target.unit, decimals: target.decimals)
            HStack(spacing: 8) {
                Picker("Curve", selection: curveBinding(p)) {
                    Text("Linear").tag(AutomationCurve.linear)
                    Text("Hold").tag(AutomationCurve.hold)
                }
                .pickerStyle(.segmented)
                Button {
                    automation.removePoint(target: target, id: p.id)
                } label: {
                    Image(systemName: "trash").foregroundStyle(EchoelTheme.danger)
                        .frame(width: 40, height: 32)
                        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete keyframe")
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.bg))
        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius).strokeBorder(EchoelTheme.border, lineWidth: 1))
    }

    // MARK: - Bindings (edit a keyframe in place via the player's API)

    private func beatBinding(_ p: AutomationPoint) -> Binding<Float> {
        Binding(
            get: { Float(AutomationPlayer.beat(forTick: p.tick)) },
            set: { automation.movePoint(target: target, id: p.id, toBeat: Double($0)) }
        )
    }
    private func valueBinding(_ p: AutomationPoint) -> Binding<Float> {
        Binding(
            get: { Float(target.value(forNormalized: p.value)) },
            set: { automation.setValue(target: target, id: p.id,
                                       normalized: target.normalized(forValue: Double($0))) }
        )
    }
    private func curveBinding(_ p: AutomationPoint) -> Binding<AutomationCurve> {
        Binding(
            get: { p.curve },
            set: { automation.setCurve(target: target, id: p.id, $0) }
        )
    }
}
#endif
