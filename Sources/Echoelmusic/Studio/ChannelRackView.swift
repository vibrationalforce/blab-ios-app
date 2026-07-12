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
    // Orientation-adaptive layout (P4): size-class changes are rare (rotation /
    // window resize), never per-frame — reading them here is render-safe.
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.verticalSizeClass) private var vSize
    /// When mounted as a WorkspaceView surface (the "Mix" page) rather than presented as a
    /// sheet: drop the NavigationStack/Done toolbar and show a lightweight inline header.
    var embedded: Bool = false
    /// B5 sample door: the host's hook to open the sample browser for a drum
    /// channel (the browser's sheet SLOT lives in EchoelStudioView — this view
    /// never presents; nil hides the button, all other mounts unchanged).
    var onSampleBrowse: ((Int) -> Void)? = nil

    private var anySolo: Bool { player.solos.contains(true) }

    /// Channel-strip columns: wide layouts (iPad `.regular`, or a landscape phone —
    /// `.compact` height) get 2 columns to use the width; portrait phone stays a
    /// single column. Mirrors EchoelTheme.Metrics' landscape rule.
    private var rackColumns: Int {
        (hSize == .regular || vSize == .compact) ? 2 : 1
    }

    var body: some View {
        if embedded {
            // Inline inside a parent ScrollView (the Mix panel / Hackbrett): NO nested
            // ScrollView and no full-bleed background — the rows just flow in the host.
            rackStack
        } else {
            NavigationStack {
                ScrollView { rackStack.padding(16) }
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

    /// The channel strips (optional inline header + one row per channel). Shared by the
    /// sheet presentation (wrapped in a ScrollView) and the embedded Mix-panel mount
    /// (rendered directly so it flows in the host's scroll — no nested scrolling).
    private var rackStack: some View {
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
            if rackColumns > 1 {
                // Landscape / iPad: strips in a grid so the width isn't wasted.
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8),
                                         count: rackColumns), spacing: 8) {
                    ForEach(BeatPlayer.trackNames.indices, id: \.self) { i in
                        channelRow(i)
                    }
                }
            } else {
                // Portrait phone: one tall column (unchanged).
                ForEach(BeatPlayer.trackNames.indices, id: \.self) { i in
                    channelRow(i)
                }
            }
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
                if let onSampleBrowse {
                    // B5: the channel's SOUND door — pick/import the pad's sample
                    // right where the channel is mixed (re-doors the browser slot
                    // that lost its trigger with the Tools grid, deep audit 2026-07-12).
                    Button {
                        onSampleBrowse(i)
                    } label: {
                        Image(systemName: "waveform")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(EchoelTheme.dim)
                            .frame(width: 26, height: 26)
                            .background(RoundedRectangle(cornerRadius: EchoelTheme.radiusSmall)
                                .fill(EchoelTheme.fill))
                            .overlay(RoundedRectangle(cornerRadius: EchoelTheme.radiusSmall)
                                .strokeBorder(EchoelTheme.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Choose sample for \(BeatPlayer.trackNames[i])")
                }
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
                .frame(width: 44, height: 44)   // ≥44pt tap target (a11y)
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
