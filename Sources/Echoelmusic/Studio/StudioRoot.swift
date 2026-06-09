#if canImport(SwiftUI)
import SwiftUI

@MainActor
struct StudioRoot: View {

    @Environment(EngineBus.self) private var bus

    /// Opt-in demo bio source (labeled "Demo"). Owned here, toggled from the
    /// bio strip's source tag so the instrument is playable without hardware.
    @State private var demoSource = BioSimulator()

    var body: some View {
        VStack(spacing: 0) {
            BioStripView()
            TabView {
                BeatTab()
                    .tabItem { Label("Tools", systemImage: "square.grid.4x3.fill") }

                WorksView()
                    .tabItem { Label("Works", systemImage: "waveform") }

                ModulationView()
                    .tabItem { Label("Sync", systemImage: "link") }

                WellView()
                    .tabItem { Label("Well", systemImage: "heart.fill") }
            }
        }
        // Demo source available to the whole subtree (was scoped to the strip
        // alone) so any tab can read it without a missing-environment crash.
        .environment(demoSource)
        .task {
            #if DEBUG
            // Dev: demo on immediately so the bus is live in Simulator/Xcode.
            demoSource.start(publishing: bus)
            #else
            // Release / TestFlight: give real sensors (HealthKit / Polar H10) a
            // few seconds to produce a frame; if none arrives, auto-start the
            // clearly-labeled "Demo" source so EVERY tester experiences the
            // bio-reactive instrument without paired hardware. BioSimulator
            // publishes source=.fallback (always labeled "Demo") and defers the
            // moment a real source connects — so this never masks real data.
            try? await Task.sleep(for: .seconds(4))
            let live = bus.latestBio
            if live == nil || live?.source == .fallback {
                demoSource.start(publishing: bus)
            }
            #endif
        }
    }
}
#endif
