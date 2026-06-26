//
//  BioVisualEditorView.swift
//  Echoelmusic — Studio
//
//  The Bio→Visual routing editor: the body sculpts the immersive visual
//  (Coherence → Blend morph, Breath → Spread, Heart rate → Intensity, …), the
//  same modulation vocabulary as the FX bio-routing. Non-destructive — the user's
//  base visual values stay editable; `VisualBioModulator` returns the shaped values
//  to render.
//
//  LAUNCH-SAFETY: this editor is presented from a LAZY `.sheet` (built only when
//  opened, never in the eager launch scroll) and deliberately AVOIDS the patterns
//  that black-screened in 10.76.20:
//    • NO `ForEach($modulator.routes)` (binding-ForEach over an @Observable array) —
//      we iterate routes by VALUE and edit each field through explicit per-field
//      bindings that write back via `modulator.updateRoute(_:)`.
//    • NO `Menu` / `.pickerStyle(.menu)` — carrier and target are chosen with plain
//      chip Buttons in horizontal scrollers (a static `ForEach` over CaseIterable,
//      which is a standard, safe construct).
//

#if canImport(SwiftUI)
import SwiftUI

@MainActor
struct BioVisualEditorView: View {
    @Bindable var modulator: VisualBioModulator
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(modulator.routes.isEmpty
                         ? "Let the body shape the light: e.g. Coherence → Blend (one look morphs into another), Breath → Spread, Heart rate → Intensity. Routes move a visual parameter around the value you set, from your live signal."
                         : "Each route moves its visual parameter around your set value, driven by the live body. Your base values stay editable in the Visual panel.")
                        .font(EchoelTheme.font(12))
                        .foregroundStyle(EchoelTheme.dim)
                        .fixedSize(horizontal: false, vertical: true)

                    // Active routes — VALUE iteration (never a binding-ForEach).
                    ForEach(modulator.routes) { route in
                        routeCard(route)
                    }

                    Divider().overlay(EchoelTheme.border)

                    Text("Add routing")
                        .font(EchoelTheme.font(13, .semibold))
                        .foregroundStyle(EchoelTheme.text)
                    Text("Pick a visual parameter for the body to drive.")
                        .font(EchoelTheme.font(11))
                        .foregroundStyle(EchoelTheme.dim)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(VisualModTarget.allCases) { target in
                                chip(target.displayName, selected: false) {
                                    modulator.addRoute(target: target)
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .background(EchoelTheme.bg)
            .navigationTitle("Bio → Visual")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - One route card

    @ViewBuilder
    private func routeCard(_ route: VisualModRoute) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Toggle("", isOn: bind(route, \.enabled)).labelsHidden().tint(EchoelTheme.accent)
                Text("\(route.carrier.displayName) → \(route.target.displayName)")
                    .font(EchoelTheme.font(13, .semibold))
                    .foregroundStyle(route.enabled ? EchoelTheme.text : EchoelTheme.dim)
                Spacer(minLength: 0)
                Button(role: .destructive) { modulator.removeRoute(id: route.id) } label: {
                    Image(systemName: "trash").font(.caption).foregroundStyle(EchoelTheme.dim)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete route")
            }

            // Source (body channel or LFO) — chips, no Menu.
            Text("Source").font(EchoelTheme.font(10, .medium)).foregroundStyle(EchoelTheme.dim)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FXModCarrier.allChoices, id: \.self) { carrier in
                        chip(carrier.displayName, selected: route.carrier == carrier) {
                            var r = route; r.carrier = carrier; modulator.updateRoute(r)
                        }
                    }
                }
            }

            // Target — chips, no Menu.
            Text("Target").font(EchoelTheme.font(10, .medium)).foregroundStyle(EchoelTheme.dim)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(VisualModTarget.allCases) { target in
                        chip(target.displayName, selected: route.target == target) {
                            var r = route; r.target = target; modulator.updateRoute(r)
                        }
                    }
                }
            }

            EchoelValueField(label: "Depth", value: bind(route, \.depth), range: 0...1, decimals: 2)
            HStack(spacing: 12) {
                Toggle("Bipolar", isOn: bind(route, \.bipolar)).tint(EchoelTheme.accent)
                    .font(EchoelTheme.font(12))
            }
            if route.carrier == .lfo {
                EchoelValueField(label: "LFO Hz", value: bind(route, \.lfoRateHz),
                                 range: 0.02...4, decimals: 2)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: EchoelTheme.radius).fill(EchoelTheme.fill))
    }

    // MARK: - Helpers

    /// An explicit per-field binding that reads the captured route value and writes
    /// the mutated route back through `updateRoute` (id-matched). This is the safe
    /// alternative to `ForEach($modulator.routes)`.
    private func bind<T>(_ route: VisualModRoute,
                         _ keyPath: WritableKeyPath<VisualModRoute, T>) -> Binding<T> {
        Binding(
            get: { route[keyPath: keyPath] },
            set: { newValue in
                var r = route
                r[keyPath: keyPath] = newValue
                modulator.updateRoute(r)
            }
        )
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(EchoelTheme.font(12, .medium))
                .foregroundStyle(selected ? EchoelTheme.onPrimary : EchoelTheme.text)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: EchoelTheme.radius)
                    .fill(selected ? EchoelTheme.accent : EchoelTheme.fill))
        }
        .buttonStyle(.plain)
    }
}
#endif
