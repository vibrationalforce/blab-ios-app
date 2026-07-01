#if canImport(SwiftUI)
import SwiftUI

// ChannelRackView.swift
// Echoel — the per-track mixer (Channel Rack). One row per drum channel with its
// level (EchoelValueField, the app-wide parameter control), plus Mute and Solo.
// The gate itself (BeatPlayer.shouldSound) is pure + unit-tested; this view only
// reads/writes the persisted per-track state. Uncodixfy: solid fills, ≤8px radius,
// colour/opacity feedback only (no glow, no scale).

@MainActor
struct ChannelRackView: View {

    @Environment(BeatPlayer.self) private var player
    @Environment(\.dismiss) private var dismiss
    /// When mounted as a WorkspaceView surface (the "Mix" page) rather than presented as a
    /// sheet: drop the NavigationStack/Done toolbar and show a lightweight inline header.
    var embedded: Bool = false

    private var anySolo: Bool { player.solos.contains(true) }

    var body: some View {
        if embedded {
            content.background(EchoelTheme.bg.ignoresSafeArea())
        } else {
            NavigationStack {
                content
                    .background(EchoelTheme.bg.ignoresSafeArea())
                    .navigationTitle("Channel Rack")
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { dismiss() }
                        }
                        ToolbarItem(placement: .cancellationAction) {
                            if anySolo {
                                Button("Clear Solo") { player.clearSolos() }
                            }
                        }
                    }
            }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 8) {
                if embedded {
                    // Inline header for the mounted Mix surface (no nav bar here).
                    HStack {
                        Text("Channel Rack")
                            .font(EchoelTheme.font(15, .semibold)).foregroundStyle(EchoelTheme.text)
                        Spacer(minLength: 0)
                        if anySolo {
                            Button("Clear Solo") { player.clearSolos() }
                                .font(EchoelTheme.font(12, .medium)).foregroundStyle(EchoelTheme.accent)
                        }
                    }
                    .padding(.bottom, 2)
                }
                ForEach(BeatPlayer.trackNames.indices, id: \.self) { i in
                    channelRow(i)
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func channelRow(_ i: Int) -> some View {
        let muted = player.mutes.indices.contains(i) && player.mutes[i]
        let soloed = player.solos.indices.contains(i) && player.solos[i]
        // A channel reads as "not sounding" when muted, or when something else is
        // soloed and this one isn't — mirror the audible state visually.
        let dimmed = !BeatPlayer.shouldSound(track: i, mutes: player.mutes, solos: player.solos)

        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Text(player.sampleLabels.indices.contains(i) ? player.sampleLabels[i]
                                                             : BeatPlayer.trackNames[i])
                    .font(EchoelTheme.font(13, .semibold))
                    .foregroundStyle(dimmed ? EchoelTheme.dim : EchoelTheme.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
                mixButton("M", on: muted, tint: Color(red: 0.85, green: 0.3, blue: 0.3)) {
                    player.setMute(track: i, !muted)
                }
                mixButton("S", on: soloed, tint: EchoelTheme.accent) {
                    player.setSolo(track: i, !soloed)
                }
            }
            EchoelValueField(label: "Level", value: levelBinding(i),
                             range: 0...2, unit: "", decimals: 2)
                .opacity(dimmed ? 0.55 : 1)

            // Per-channel insert FX: filter type + (when active) cutoff, plus drive.
            let fxType = player.fx.indices.contains(i) ? player.fx[i].type : 0
            HStack(spacing: 8) {
                Text("Filter").font(EchoelTheme.font(12)).foregroundStyle(EchoelTheme.dim)
                Spacer(minLength: 0)
                Picker("Filter", selection: fxTypeBinding(i)) {
                    ForEach(ChannelInsertFX.FilterType.allCases, id: \.rawValue) { t in
                        Text(t.label).tag(t.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .tint(EchoelTheme.text)
            }
            if fxType != ChannelInsertFX.FilterType.off.rawValue {
                EchoelValueField(label: "Cutoff", value: fxFloatBinding(i, \.cutoff),
                                 range: 20...18000, unit: "Hz", decimals: 0)
                    .opacity(dimmed ? 0.55 : 1)
            }
            EchoelValueField(label: "Drive", value: fxFloatBinding(i, \.drive),
                             range: 0...1, unit: "", decimals: 2)
                .opacity(dimmed ? 0.55 : 1)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
        .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
            .strokeBorder(EchoelTheme.border, lineWidth: 1))
    }

    /// A compact square Mute/Solo toggle — filled when active (colour-only feedback).
    private func mixButton(_ label: String, on: Bool, tint: Color,
                           _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(EchoelTheme.font(13, .bold))
                .foregroundStyle(on ? EchoelTheme.onPrimary : EchoelTheme.text)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                    .fill(on ? tint : EchoelTheme.fill))
                .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                    .strokeBorder(EchoelTheme.border, lineWidth: on ? 0 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label == "M" ? "Mute" : "Solo")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// Binding to a channel's insert-FX filter type (rawValue).
    private func fxTypeBinding(_ i: Int) -> Binding<Int> {
        Binding(
            get: { player.fx.indices.contains(i) ? player.fx[i].type : 0 },
            set: { newValue in
                guard player.fx.indices.contains(i) else { return }
                var f = player.fx[i]; f.type = newValue
                player.setFX(track: i, f)
            }
        )
    }

    /// Binding to one Float field of a channel's insert FX (cutoff / drive).
    private func fxFloatBinding(_ i: Int,
                               _ keyPath: WritableKeyPath<BeatPlayer.ChannelFX, Float>) -> Binding<Float> {
        Binding(
            get: { player.fx.indices.contains(i) ? player.fx[i][keyPath: keyPath] : 0 },
            set: { newValue in
                guard player.fx.indices.contains(i) else { return }
                var f = player.fx[i]; f[keyPath: keyPath] = newValue
                player.setFX(track: i, f)
            }
        )
    }

    /// Binding to a channel's level that preserves the rest of its PadShape.
    private func levelBinding(_ i: Int) -> Binding<Float> {
        Binding(
            get: { player.shapes.indices.contains(i) ? player.shapes[i].level : 1.0 },
            set: { newValue in
                guard player.shapes.indices.contains(i) else { return }
                var s = player.shapes[i]
                s.level = min(max(newValue, 0), 2)
                player.setShape(track: i, s)
            }
        )
    }
}
#endif
