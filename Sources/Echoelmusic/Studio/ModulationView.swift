#if canImport(SwiftUI)
import SwiftUI

/// Routing screen for the ModulationMatrix: add bio→parameter routes, switch
/// each between live coupling and a captured (held) value, and tune depth.
/// Binds the live `ModulationEngine` so edits take effect on the next tick.
///
/// Design: solid fills, ≤12px radii, labels above controls, legible values
/// first — no glassmorphism/glow per the UI constraints.
@MainActor
struct ModulationView: View {

    @Environment(ModulationEngine.self) private var engine
    @Environment(EngineBus.self) private var bus

    var body: some View {
        @Bindable var engine = engine
        NavigationStack {
            List {
                Section {
                    if engine.matrix.routes.isEmpty {
                        Text("No routes yet. Add one to let a biofeedback signal modulate a parameter.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach($engine.matrix.routes) { $route in
                            RouteRow(route: $route, currentFrame: bus.latestBio)
                        }
                        .onDelete { engine.matrix.routes.remove(atOffsets: $0) }
                    }
                } header: {
                    Text("Routes")
                } footer: {
                    Text("Live = the signal modulates continuously. Capture = freeze the current value; Drift adds light movement around it (0 = rigid).")
                }

                Section("Destinations") {
                    if engine.registeredDestinations.isEmpty {
                        Text("None wired in this build.").foregroundStyle(.secondary)
                    } else {
                        ForEach(engine.registeredDestinations, id: \.self) { key in
                            Text(key).font(.callout.monospaced())
                        }
                    }
                }
            }
            .navigationTitle("Modulation")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        addRoute()
                    } label: {
                        Label("Add Route", systemImage: "plus")
                    }
                    .disabled(engine.registeredDestinations.isEmpty)
                }
            }
        }
    }

    private func addRoute() {
        let destKey = engine.registeredDestinations.first ?? ModDestinationKey.tempo
        engine.matrix.routes.append(
            ModRoute(source: .coherence, destination: ModDestination(destKey), mode: .live)
        )
    }
}

/// One editable route. Source → destination, live/capture mode, depth, enable.
@MainActor
private struct RouteRow: View {

    @Binding var route: ModRoute
    /// Latest bio frame, used by Capture to freeze the current source value.
    let currentFrame: BioSampleFrame?

    private var isLive: Bool {
        if case .live = route.mode { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("Source", selection: $route.source) {
                    ForEach(ModSource.allCases, id: \.self) { src in
                        Text(label(for: src)).tag(src)
                    }
                }
                .labelsHidden()

                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(route.destination.key)
                    .font(.callout.monospaced())
                    .lineLimit(1)
                    .truncationMode(.head)

                Spacer()

                Toggle("Enabled", isOn: $route.enabled)
                    .labelsHidden()
            }

            Picker("Mode", selection: modeSelection) {
                Text("Live").tag(RouteMode.live)
                Text("Capture").tag(RouteMode.hold)
            }
            .pickerStyle(.segmented)

            if case .hold(let value, _) = route.mode {
                HStack {
                    Text("Held \(Double(value), format: .number.precision(.fractionLength(2)))")
                        .font(.caption.monospaced())
                    Spacer()
                    Button("Recapture") { capture() }
                        .font(.caption)
                        .buttonStyle(.bordered)
                }
                labeledSlider("Drift", value: driftBinding, range: 0...1)
            }

            labeledSlider("Depth", value: $route.depth, range: 0...1)

            Toggle("Invert", isOn: $route.invert)
                .font(.caption)
        }
        .padding(.vertical, 6)
    }

    // MARK: Mode handling

    private enum RouteMode: Hashable { case live, hold }

    private var modeSelection: Binding<RouteMode> {
        Binding(
            get: { isLive ? .live : .hold },
            set: { newValue in
                switch newValue {
                case .live: route.mode = .live
                case .hold: capture()
                }
            }
        )
    }

    private var driftBinding: Binding<Float> {
        Binding(
            get: { if case .hold(_, let d) = route.mode { return d } else { return 0 } },
            set: { newDrift in
                if case .hold(let v, _) = route.mode {
                    route.mode = .hold(value: v, drift: newDrift)
                }
            }
        )
    }

    /// Freeze the source's current normalized value into a hold, preserving drift.
    private func capture() {
        let drift: Float = { if case .hold(_, let d) = route.mode { return d } else { return 0 } }()
        if let frame = currentFrame {
            route = route.captured(from: frame, drift: drift)
        } else {
            // No live frame yet — hold at midpoint so the route is still usable.
            route.mode = .hold(value: 0.5, drift: drift)
        }
    }

    @ViewBuilder
    private func labeledSlider(_ title: String, value: Binding<Float>, range: ClosedRange<Float>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.caption)
                Spacer()
                Text(Double(value.wrappedValue), format: .number.precision(.fractionLength(2)))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    private func label(for source: ModSource) -> String {
        switch source {
        case .heartRate:   return "Heart Rate"
        case .hrv:         return "HRV"
        case .breathRate:  return "Breath Rate"
        case .breathPhase: return "Breath Phase"
        case .coherence:   return "Coherence"
        case .motion:      return "Motion"
        }
    }
}
#endif
